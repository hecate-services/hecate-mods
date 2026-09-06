%%% @doc Command `moderate_room_v1'.
%%%
%%% Spins up moderation for a room: from this point the room is watched
%%% (see `room_topic_listener') so it outlives whoever happened to be in
%%% it when moderation started, until `idle_timeout_hours' passes with no
%%% participant joining.
%%% @end
-module(moderate_room_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_room_topic/1, get_idle_timeout_hours/1]).

%% Raf's own decision (macula-io/hecate-mods#1): 96h default, configurable.
-define(DEFAULT_IDLE_TIMEOUT_HOURS, 96).

-record(moderate_room_v1, {
    room_topic :: binary() | undefined,
    idle_timeout_hours :: pos_integer() | undefined
}).

-opaque t() :: #moderate_room_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> moderate_room_v1.

%% @doc Room-topic FORMAT is checked here, not only in `validate/1':
%% `stream_id/1' (called by `dispatch/1', before the aggregate or its
%% handler's own `validate/1' ever run) pattern-matches the exact
%% `"agents.room."' prefix and crashes on anything else. A malformed
%% topic must never reach that point at all (found by Fable review,
%% hecate-mods#5).
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{room_topic := Topic} = Params) when is_binary(Topic) ->
    checked_room_topic(room_topic:valid(Topic), Topic, Params);
new(_) ->
    {error, missing_room_topic}.

checked_room_topic(true, Topic, Params) ->
    {ok, #moderate_room_v1{
        room_topic = Topic,
        idle_timeout_hours = maps:get(idle_timeout_hours, Params, ?DEFAULT_IDLE_TIMEOUT_HOURS)
    }};
checked_room_topic(false, _Topic, _Params) ->
    {error, invalid_room_topic}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(Params) -> new(Params).

%% @doc `room_topic' is already guaranteed valid-shaped by `new/1' --
%% every `t()' is constructed there -- so only `idle_timeout_hours'
%% needs checking here.
-spec validate(t()) -> ok | {error, term()}.
validate(#moderate_room_v1{idle_timeout_hours = Hours}) when is_integer(Hours), Hours > 0 ->
    ok;
validate(#moderate_room_v1{}) ->
    {error, invalid_idle_timeout_hours}.

-spec to_map(t()) -> map().
to_map(#moderate_room_v1{room_topic = Topic, idle_timeout_hours = Hours}) ->
    #{command_type => moderate_room_v1, room_topic => Topic, idle_timeout_hours => Hours}.

-spec stream_id(t()) -> binary().
stream_id(#moderate_room_v1{room_topic = Topic}) ->
    room_aggregate:stream_id(Topic).

-spec get_room_topic(t()) -> binary() | undefined.
get_room_topic(#moderate_room_v1{room_topic = V}) -> V.

-spec get_idle_timeout_hours(t()) -> pos_integer() | undefined.
get_idle_timeout_hours(#moderate_room_v1{idle_timeout_hours = V}) -> V.
