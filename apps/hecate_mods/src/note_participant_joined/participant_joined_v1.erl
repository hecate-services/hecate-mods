%%% @doc Event `participant_joined_v1'. Lifecycle fact only -- no message
%%% content, per this workspace's own decision (macula-io/hecate-mods#1):
%%% conversation content stays each participant's own prerogative.
-module(participant_joined_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_room_topic/1, get_node_id/1, get_joined_at/1]).

-record(participant_joined_v1, {
    room_topic :: binary(),
    node_id :: binary(),
    joined_at :: integer()
}).

-opaque t() :: #participant_joined_v1{}.
-export_type([t/0]).

event_type() -> <<"participant_joined_v1">>.

-spec new(map()) -> t().
new(#{room_topic := Topic, node_id := NodeId} = Params) ->
    #participant_joined_v1{
        room_topic = Topic,
        node_id = NodeId,
        joined_at = maps:get(joined_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{room_topic := Topic, node_id := NodeId, joined_at := At})
  when is_binary(Topic), is_binary(NodeId), is_integer(At) ->
    {ok, #participant_joined_v1{room_topic = Topic, node_id = NodeId, joined_at = At}};
from_map(_) ->
    {error, invalid_participant_joined_event}.

-spec to_map(t()) -> map().
to_map(#participant_joined_v1{room_topic = Topic, node_id = NodeId, joined_at = At}) ->
    #{event_type => <<"participant_joined_v1">>, room_topic => Topic,
      node_id => NodeId, joined_at => At}.

-spec get_room_topic(t()) -> binary().
get_room_topic(#participant_joined_v1{room_topic = V}) -> V.

-spec get_node_id(t()) -> binary().
get_node_id(#participant_joined_v1{node_id = V}) -> V.

-spec get_joined_at(t()) -> integer().
get_joined_at(#participant_joined_v1{joined_at = V}) -> V.
