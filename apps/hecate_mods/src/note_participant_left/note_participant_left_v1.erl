%%% @doc Command `note_participant_left_v1'.
%%%
%%% Dispatched internally by `room_topic_listener' when it observes an
%%% attested `participant_left' envelope on a moderated room's mesh
%%% topic -- never called from an external RPC. Records the lifecycle
%%% fact only; does NOT reset the idle clock (Raf's own decision,
%%% macula-io/hecate-mods#1: the timeout resets on a join, never a leave).
%%% @end
-module(note_participant_left_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_room_topic/1, get_node_id/1]).

-record(note_participant_left_v1, {
    room_topic :: binary() | undefined,
    node_id :: binary() | undefined
}).

-opaque t() :: #note_participant_left_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> note_participant_left_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{room_topic := Topic, node_id := NodeId}) when is_binary(Topic), is_binary(NodeId) ->
    {ok, #note_participant_left_v1{room_topic = Topic, node_id = NodeId}};
new(_) ->
    {error, missing_room_topic_or_node_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(Params) -> new(Params).

-spec validate(t()) -> ok | {error, term()}.
validate(#note_participant_left_v1{room_topic = Topic, node_id = NodeId})
  when is_binary(Topic), is_binary(NodeId), byte_size(NodeId) > 0 -> ok;
validate(_) -> {error, missing_room_topic_or_node_id}.

-spec to_map(t()) -> map().
to_map(#note_participant_left_v1{room_topic = Topic, node_id = NodeId}) ->
    #{command_type => note_participant_left_v1, room_topic => Topic, node_id => NodeId}.

-spec stream_id(t()) -> binary().
stream_id(#note_participant_left_v1{room_topic = Topic}) ->
    room_aggregate:stream_id(Topic).

-spec get_room_topic(t()) -> binary() | undefined.
get_room_topic(#note_participant_left_v1{room_topic = V}) -> V.

-spec get_node_id(t()) -> binary() | undefined.
get_node_id(#note_participant_left_v1{node_id = V}) -> V.
