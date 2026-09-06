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
%%% @end
-module(room_state).
-behaviour(evoq_state).

-include("room_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([status/1, room_topic/1, idle_timeout_hours/1, last_joined_at/1,
         is_formed/1, is_ended/1]).

-record(state, {
    room_topic :: binary() | undefined,
    status = 0 :: non_neg_integer(),
    idle_timeout_hours :: pos_integer() | undefined,
    last_joined_at :: integer() | undefined
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
    S#state{last_joined_at = maps:get(joined_at, Ev)};
%% Deliberately a no-op: this aggregate does not track a live participant
%% set for the MVP (nothing in the idle-timeout decision needs one), but
%% the event is still real, recorded lifecycle history the store keeps --
%% see maybe_note_participant_left. An explicit clause documents that as
%% intentional rather than an oversight.
apply_event(S, #{event_type := <<"participant_left_v1">>}) ->
    S;
apply_event(S, #{event_type := <<"room_moderation_ended_v1">>}) ->
    S#state{status = evoq_bit_flags:set(S#state.status, ?ROOM_ENDED)};
apply_event(S, _Unknown) ->
    S.

-spec to_map(state()) -> map().
to_map(#state{room_topic = T, status = St, idle_timeout_hours = H, last_joined_at = At}) ->
    #{room_topic => T, status => St, idle_timeout_hours => H, last_joined_at => At}.
