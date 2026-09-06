%%% @doc Command `end_room_moderation_v1'.
%%%
%%% Terminal for the room aggregate. MVP's only caller is
%%% `active_rooms_reaper' (reason `idle_timeout') -- there is no
%%% external RPC to end moderation early in this issue's scope.
%%% @end
-module(end_room_moderation_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_room_topic/1, get_reason/1]).

-record(end_room_moderation_v1, {
    room_topic :: binary() | undefined,
    reason :: binary() | undefined
}).

-opaque t() :: #end_room_moderation_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> end_room_moderation_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{room_topic := Topic} = Params) when is_binary(Topic) ->
    {ok, #end_room_moderation_v1{
        room_topic = Topic,
        reason = maps:get(reason, Params, <<"idle_timeout">>)
    }};
new(_) ->
    {error, missing_room_topic}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(Params) -> new(Params).

-spec validate(t()) -> ok | {error, term()}.
validate(#end_room_moderation_v1{room_topic = Topic, reason = Reason})
  when is_binary(Topic), is_binary(Reason), byte_size(Reason) > 0 -> ok;
validate(_) -> {error, missing_room_topic}.

-spec to_map(t()) -> map().
to_map(#end_room_moderation_v1{room_topic = Topic, reason = Reason}) ->
    #{command_type => end_room_moderation_v1, room_topic => Topic, reason => Reason}.

-spec stream_id(t()) -> binary().
stream_id(#end_room_moderation_v1{room_topic = Topic}) ->
    room_aggregate:stream_id(Topic).

-spec get_room_topic(t()) -> binary() | undefined.
get_room_topic(#end_room_moderation_v1{room_topic = V}) -> V.

-spec get_reason(t()) -> binary() | undefined.
get_reason(#end_room_moderation_v1{reason = V}) -> V.
