%%% @doc Event `participant_left_v1'. Lifecycle fact only -- no message
%%% content, per this workspace's own decision (macula-io/hecate-mods#1).
-module(participant_left_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_room_topic/1, get_node_id/1, get_left_at/1]).

-record(participant_left_v1, {
    room_topic :: binary(),
    node_id :: binary(),
    left_at :: integer()
}).

-opaque t() :: #participant_left_v1{}.
-export_type([t/0]).

event_type() -> <<"participant_left_v1">>.

-spec new(map()) -> t().
new(#{room_topic := Topic, node_id := NodeId} = Params) ->
    #participant_left_v1{
        room_topic = Topic,
        node_id = NodeId,
        left_at = maps:get(left_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{room_topic := Topic, node_id := NodeId, left_at := At})
  when is_binary(Topic), is_binary(NodeId), is_integer(At) ->
    {ok, #participant_left_v1{room_topic = Topic, node_id = NodeId, left_at = At}};
from_map(_) ->
    {error, invalid_participant_left_event}.

-spec to_map(t()) -> map().
to_map(#participant_left_v1{room_topic = Topic, node_id = NodeId, left_at = At}) ->
    #{event_type => <<"participant_left_v1">>, room_topic => Topic,
      node_id => NodeId, left_at => At}.

-spec get_room_topic(t()) -> binary().
get_room_topic(#participant_left_v1{room_topic = V}) -> V.

-spec get_node_id(t()) -> binary().
get_node_id(#participant_left_v1{node_id = V}) -> V.

-spec get_left_at(t()) -> integer().
get_left_at(#participant_left_v1{left_at = V}) -> V.
