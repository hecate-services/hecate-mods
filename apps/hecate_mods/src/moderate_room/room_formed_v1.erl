%%% @doc Event `room_formed_v1'.
-module(room_formed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_room_topic/1, get_idle_timeout_hours/1, get_formed_at/1]).

-record(room_formed_v1, {
    room_topic :: binary(),
    idle_timeout_hours :: pos_integer(),
    formed_at :: integer()
}).

-opaque t() :: #room_formed_v1{}.
-export_type([t/0]).

event_type() -> <<"room_formed_v1">>.

-spec new(map()) -> t().
new(#{room_topic := Topic, idle_timeout_hours := Hours} = Params) ->
    #room_formed_v1{
        room_topic = Topic,
        idle_timeout_hours = Hours,
        formed_at = maps:get(formed_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{room_topic := Topic, idle_timeout_hours := Hours, formed_at := At})
  when is_binary(Topic), is_integer(Hours), is_integer(At) ->
    {ok, #room_formed_v1{room_topic = Topic, idle_timeout_hours = Hours, formed_at = At}};
from_map(_) ->
    {error, invalid_room_formed_event}.

-spec to_map(t()) -> map().
to_map(#room_formed_v1{room_topic = Topic, idle_timeout_hours = Hours, formed_at = At}) ->
    #{event_type => <<"room_formed_v1">>, room_topic => Topic,
      idle_timeout_hours => Hours, formed_at => At}.

-spec get_room_topic(t()) -> binary().
get_room_topic(#room_formed_v1{room_topic = V}) -> V.

-spec get_idle_timeout_hours(t()) -> pos_integer().
get_idle_timeout_hours(#room_formed_v1{idle_timeout_hours = V}) -> V.

-spec get_formed_at(t()) -> integer().
get_formed_at(#room_formed_v1{formed_at = V}) -> V.
