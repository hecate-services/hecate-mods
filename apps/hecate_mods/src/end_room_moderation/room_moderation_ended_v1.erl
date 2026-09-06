%%% @doc Event `room_moderation_ended_v1'. Terminal.
-module(room_moderation_ended_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_room_topic/1, get_reason/1, get_ended_at/1]).

-record(room_moderation_ended_v1, {
    room_topic :: binary(),
    reason :: binary(),
    ended_at :: integer()
}).

-opaque t() :: #room_moderation_ended_v1{}.
-export_type([t/0]).

event_type() -> <<"room_moderation_ended_v1">>.

-spec new(map()) -> t().
new(#{room_topic := Topic, reason := Reason} = Params) ->
    #room_moderation_ended_v1{
        room_topic = Topic,
        reason = Reason,
        ended_at = maps:get(ended_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{room_topic := Topic, reason := Reason, ended_at := At})
  when is_binary(Topic), is_binary(Reason), is_integer(At) ->
    {ok, #room_moderation_ended_v1{room_topic = Topic, reason = Reason, ended_at = At}};
from_map(_) ->
    {error, invalid_room_moderation_ended_event}.

-spec to_map(t()) -> map().
to_map(#room_moderation_ended_v1{room_topic = Topic, reason = Reason, ended_at = At}) ->
    #{event_type => <<"room_moderation_ended_v1">>, room_topic => Topic,
      reason => Reason, ended_at => At}.

-spec get_room_topic(t()) -> binary().
get_room_topic(#room_moderation_ended_v1{room_topic = V}) -> V.

-spec get_reason(t()) -> binary().
get_reason(#room_moderation_ended_v1{reason = V}) -> V.

-spec get_ended_at(t()) -> integer().
get_ended_at(#room_moderation_ended_v1{ended_at = V}) -> V.
