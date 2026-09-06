%%% @doc State module for the room aggregate.
%%%
%%% One aggregate per moderated room, keyed by `room_topic' (the stream
%%% id). `status' is a bit-flag integer (`room_status.hrl'), not an atom
%%% -- status fields in this workspace are always bit flags, per
%%% `guide_mailbox_lifecycle''s `mailbox_state.erl'.
%%%
%%% `last_joined_at' is the ONE field the idle-timeout reaper cares
%%% about: it is set at formation (so a freshly-moderated room with no
%%% joins yet still has a baseline to measure idleness from) and reset
%%% on every `participant_joined_v1' -- never on `participant_left_v1'
%%% or message activity, which this aggregate has no visibility into by
%%% design (see macula-io/hecate-mods#1).
%%%
%%% `participants' (macula-io/hecate-mods#2) is the live set of node
%%% ids (hex strings, matching `room_envelope''s own convention)
%%% currently in the room, per this aggregate's own observed
%%% join/leave facts -- the authorization source `invite_agent_to_room'
%%% checks against, never a caller-supplied claim.
%%% @end
-module(room_state).
-behaviour(evoq_state).

-include("room_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, room_topic/1, idle_timeout_hours/1, last_joined_at/1,
         is_formed/1, is_ended/1, is_participant/2]).

-record(state, {
    room_topic :: binary() | undefined,
    status = 0 :: non_neg_integer(),
    idle_timeout_hours :: pos_integer() | undefined,
    last_joined_at :: integer() | undefined,
    participants = sets:new([{version, 2}]) :: sets:set(binary())
}).

-type state() :: #state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(RoomTopic) ->
    #state{room_topic = RoomTopic}.

-spec status(state()) -> non_neg_integer().
status(#state{status = S}) -> S.

-spec room_topic(state()) -> binary() | undefined.
room_topic(#state{room_topic = T}) -> T.

-spec idle_timeout_hours(state()) -> pos_integer() | undefined.
idle_timeout_hours(#state{idle_timeout_hours = H}) -> H.

-spec last_joined_at(state()) -> integer() | undefined.
last_joined_at(#state{last_joined_at = At}) -> At.

-spec is_formed(state()) -> boolean().
is_formed(#state{status = S}) -> evoq_bit_flags:has(S, ?ROOM_FORMED).

-spec is_ended(state()) -> boolean().
is_ended(#state{status = S}) -> evoq_bit_flags:has(S, ?ROOM_ENDED).

%% @doc Whether `NodeId' (any case -- envelope senders are not
%% guaranteed to send lowercase hex, see `room_envelope''s own
%% attestation check) is currently in this room, per this aggregate's
%% own observed joins/leaves.
-spec is_participant(state(), binary()) -> boolean().
is_participant(#state{participants = P}, NodeId) ->
    sets:is_element(string:lowercase(NodeId), P).

%% @doc Folds one event into state. Matched by `event_type', which is
%% always the snake_case_vN binary every event module's own `event_type/0'
%% returns -- never the record/module name directly, since this also runs
%% during replay from the raw stored map.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"room_formed_v1">>} = Ev) ->
    S#state{
        room_topic = maps:get(room_topic, Ev),
        status = evoq_bit_flags:set(S#state.status, ?ROOM_FORMED),
        idle_timeout_hours = maps:get(idle_timeout_hours, Ev),
        last_joined_at = maps:get(formed_at, Ev)
    };
apply_event(S, #{event_type := <<"participant_joined_v1">>} = Ev) ->
    NodeId = string:lowercase(maps:get(node_id, Ev)),
    S#state{
        last_joined_at = maps:get(joined_at, Ev),
        participants = sets:add_element(NodeId, S#state.participants)
    };
apply_event(S, #{event_type := <<"participant_left_v1">>} = Ev) ->
    NodeId = string:lowercase(maps:get(node_id, Ev)),
    S#state{participants = sets:del_element(NodeId, S#state.participants)};
apply_event(S, #{event_type := <<"room_moderation_ended_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?ROOM_ENDED)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{room_topic = T, status = St, idle_timeout_hours = H, last_joined_at = At,
              participants = P}) ->
    #{room_topic => T, status => St, idle_timeout_hours => H, last_joined_at => At,
      participants => lists:sort(sets:to_list(P))}.
