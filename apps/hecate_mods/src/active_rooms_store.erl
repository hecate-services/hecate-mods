%%% @doc THIN operational index of currently-moderated rooms: room_topic +
%%% last_joined_at (+ idle_timeout_hours) only, in `hecate_om:read_model()''s
%%% barrel_docdb database. This is NOT a copy of `room_aggregate' state --
%%% full room state (participants, etc.) stays the aggregate's own job,
%%% rehydrated by replaying that room's event stream. This index exists for
%%% exactly two operational needs neither the aggregate nor DCB's own
%%% indexed reads solve without either enumerating every stream in the
%%% store (rejected -- see `hecate-parksim/apps/project_parking_sessions/
%%% src/scavenge_aged_sessions.erl' for the precedent and its own reasoning)
%%% or growing forever with every room ever formed (DCB's
%%% read_by_event_types has no notion of "still active"):
%%%
%%%   1. `active_rooms_reaper' needs to find rooms whose idle timeout has
%%%      elapsed, without scanning the event store.
%%%   2. On restart, `active_rooms_reaper' needs to know which rooms were
%%%      being moderated, to re-subscribe to their mesh topics and re-arm
%%%      their idle timeout -- otherwise a watchtower-triggered restart
%%%      (every push to main) would silently forget every moderated room.
%%%
%%% One document per moderated room, keyed by `room_topic' directly (no
%%% hashing or inversion needed -- see `mailboxes_read_model''s own
%%% `list_unarchived/1' for the precedent that a plain `fold_docs' is the
%%% right default at this service's scale; revisit only if a real
%%% moderated-room count ever makes it slow, matching that module's own
%%% reasoning). Ended rooms are deleted outright rather than flagged and
%%% kept -- nothing here needs to browse ended rooms, so there is nothing
%%% "thin" about keeping them.
%%% @end
-module(active_rooms_store).

-export([record_formed/3, touch_joined/2, remove/1]).
-export([due_for_timeout/1, list_active/0]).

-define(HOUR_MS, 3_600_000).

-spec record_formed(binary(), pos_integer(), integer()) -> ok.
record_formed(RoomTopic, IdleTimeoutHours, FormedAt)
  when is_binary(RoomTopic), is_integer(IdleTimeoutHours), is_integer(FormedAt) ->
    write_doc(#{
        <<"id">> => RoomTopic,
        <<"room_topic">> => RoomTopic,
        <<"idle_timeout_hours">> => IdleTimeoutHours,
        <<"last_joined_at">> => FormedAt
    }, expiry(IdleTimeoutHours, FormedAt)).

%% @doc Resets the idle clock. A no-op, not an error, if the room has
%% already ended (or was never formed) -- a join observed on a room this
%% index no longer knows about is a harmless race with `remove/1', not a
%% caller bug.
-spec touch_joined(binary(), integer()) -> ok.
touch_joined(RoomTopic, JoinedAt) when is_binary(RoomTopic), is_integer(JoinedAt) ->
    touched(get_doc(RoomTopic), JoinedAt).

touched({ok, #{<<"idle_timeout_hours">> := Hours} = Doc}, JoinedAt) ->
    write_doc(Doc#{<<"last_joined_at">> => JoinedAt}, expiry(Hours, JoinedAt));
touched({error, not_found}, _JoinedAt) ->
    ok.

-spec remove(binary()) -> ok.
remove(RoomTopic) when is_binary(RoomTopic) ->
    {ok, DbName} = hecate_om:read_model(),
    case barrel_docdb:delete_doc(DbName, RoomTopic) of
        {ok, _} -> ok;
        {error, not_found} -> ok
    end.

%% @doc Every currently-moderated room whose idle window has elapsed as of
%% `NowMs' -- `active_rooms_reaper''s own sweep query. A full fold, not an
%% indexed range scan: correct and simple at this service's expected
%% scale (moderated rooms are opt-in, not every mesh room), matching
%% `mailboxes_read_model:list_unarchived/1''s own precedent and stated
%% reasoning for the same choice.
-spec due_for_timeout(integer()) -> [binary()].
due_for_timeout(NowMs) when is_integer(NowMs) ->
    fold(fun(Doc, Acc) -> collect_due(NowMs, Doc, Acc) end).

collect_due(NowMs, #{<<"room_topic">> := Topic, <<"last_joined_at">> := At,
                     <<"idle_timeout_hours">> := Hours}, Acc) ->
    case (NowMs - At) > (Hours * ?HOUR_MS) of
        true  -> {ok, [Topic | Acc]};
        false -> {ok, Acc}
    end.

%% @doc Every currently-moderated room's topic -- boot-time resubscription.
-spec list_active() -> [binary()].
list_active() ->
    fold(fun(#{<<"room_topic">> := Topic}, Acc) -> {ok, [Topic | Acc]} end).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

%% Defensive backstop only (belt-and-suspenders, matching hecate-agora's
%% own hot-record TTL sweep): a passive tombstone-GC at the storage layer
%% if the active reaper ever falls behind. It cannot terminate a room
%% actor or emit `room_moderation_ended_v1' itself, so the reaper stays
%% the real mechanism regardless -- this only bounds storage, with a
%% margin well past the timeout itself so the reaper always gets many
%% chances to act first.
expiry(IdleTimeoutHours, SinceMs) ->
    SinceMs + (IdleTimeoutHours * ?HOUR_MS) + ?HOUR_MS.

%% `{error, no_read_model}' reads as "nothing to do yet" here, not a
%% crash: the only way this module's write path (`write_doc/2', which DOES
%% crash on it -- a genuine loss of the read model while a real event is
%% being projected is a bug worth failing loudly for) runs at all is via
%% `room_lifecycle_to_active_rooms' reacting to a real dispatched event,
%% which cannot happen before `hecate_om:boot/1' has already opened the
%% read model. A bare `active_rooms_reaper' tick, e.g. in a test that
%% starts `hecate_mods_sup' standalone without booting hecate_om at all,
%% hits only this read path.
fold(Fun) ->
    rows(hecate_om:read_model(), Fun).

rows({ok, DbName}, Fun) ->
    {ok, Rows} = barrel_docdb:fold_docs(DbName, Fun, []),
    Rows;
rows({error, no_read_model}, _Fun) ->
    [].

get_doc(RoomTopic) ->
    found(hecate_om:read_model(), RoomTopic).

found({ok, DbName}, RoomTopic) -> barrel_docdb:get_doc(DbName, RoomTopic);
found({error, no_read_model}, _RoomTopic) -> {error, not_found}.

write_doc(Doc, ExpiresAt) ->
    {ok, DbName} = hecate_om:read_model(),
    {ok, _} = barrel_docdb:put_doc(DbName, Doc, #{expires_at => ExpiresAt}),
    ok.
