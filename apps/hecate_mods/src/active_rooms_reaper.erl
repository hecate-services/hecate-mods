%%% @doc Two jobs, one periodic tick, because both need the same answer to
%%% "which rooms are currently moderated": (1) reconcile this node's live
%%% mesh subscriptions against `active_rooms_store:list_active/0' via
%%% `hecate_om_pubsub:ensure_subscriptions/1' (self-healing, and how a
%%% moderated room's mesh presence survives a restart -- see
%%% `hecate_mods_service.erl''s own read-model doc), and (2) end
%%% moderation (reason `idle_timeout') for any room
%%% `active_rooms_store:due_for_timeout/1' reports.
%%%
%%% `reconcile_now/0' lets a command handler trigger an immediate
%%% resubscribe right after `moderate_room'/`end_room_moderation'
%%% succeeds, instead of waiting up to a full tick -- responsiveness, not
%%% a correctness requirement, since the next periodic tick would catch
%%% it regardless (matches `hecate_om_pubsub:ensure_subscriptions/1''s
%%% own "safe to call repeatedly" contract).
%%%
%%% Modeled on `hecate-parksim''s `scavenge_aged_sessions': a single
%%% periodic gen_server reading a read model, not a per-entity timer
%%% process -- 96h default timeouts have no need for per-room precision.
%%% @end
-module(active_rooms_reaper).
-behaviour(gen_server).

-export([start_link/0, reconcile_now/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL_MS, 900_000). %% 15 min -- ample precision for hour-scale timeouts

-record(st, {interval_ms :: pos_integer()}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec reconcile_now() -> ok.
reconcile_now() -> gen_server:cast(?MODULE, reconcile).

init([]) ->
    IntervalMs = cfg(reaper_interval_ms, ?DEFAULT_INTERVAL_MS),
    self() ! tick,
    {ok, #st{interval_ms = IntervalMs}}.

handle_call(_Req, _From, St) -> {reply, {error, unsupported}, St}.

handle_cast(reconcile, St) -> do_reconcile(), {noreply, St};
handle_cast(_Msg, St) -> {noreply, St}.

handle_info(tick, #st{interval_ms = Ms} = St) ->
    %% Sweep BEFORE reconcile: a room the sweep just ended should stop
    %% being subscribed to in this same tick, not linger until the next
    %% one.
    do_sweep(),
    do_reconcile(),
    erlang:send_after(Ms, self(), tick),
    {noreply, St};
handle_info(_Msg, St) -> {noreply, St}.

%%--------------------------------------------------------------------

do_reconcile() ->
    Desired = [{Topic, room_topic_listener, #{room_topic => Topic}}
               || Topic <- active_rooms_store:list_active()],
    hecate_om_pubsub:ensure_subscriptions(Desired).

do_sweep() ->
    NowMs = erlang:system_time(millisecond),
    lists:foreach(fun end_idle/1, active_rooms_store:due_for_timeout(NowMs)).

end_idle(RoomTopic) ->
    case end_room_moderation_v1:new(#{room_topic => RoomTopic, reason => <<"idle_timeout">>}) of
        {ok, Cmd} -> logged(maybe_end_room_moderation:dispatch(Cmd), RoomTopic);
        {error, Reason} -> logger:warning("[hecate_mods] reaper could not build end command for ~s: ~p",
                                          [RoomTopic, Reason])
    end.

logged({ok, _Version, _Events}, RoomTopic) ->
    logger:info("[hecate_mods] ended moderation for ~s (idle_timeout)", [RoomTopic]);
logged({error, Reason}, RoomTopic) ->
    %% Not necessarily a problem: a concurrent join between the sweep's
    %% read and this dispatch loses the race legitimately (the aggregate's
    %% own guard_active/2 already re-checks state at dispatch time), so
    %% this logs rather than treats every non-ok outcome as an error.
    logger:info("[hecate_mods] reaper's end_room_moderation for ~s declined: ~p", [RoomTopic, Reason]).

cfg(Key, Default) ->
    case application:get_env(hecate_mods, Key, Default) of
        N when is_integer(N), N > 0 -> N;
        _ -> Default
    end.
