%%% @doc Handler for `end_room_moderation_v1'.
%%%
%%% Pure: the "must be actively moderated, not already ended" guard lives
%%% in the aggregate (`room_aggregate:guard_active/2'), not here.
%%% @end
-module(maybe_end_room_moderation).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case end_room_moderation_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(end_room_moderation_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case end_room_moderation_v1:validate(Cmd) of
        ok ->
            Event = room_moderation_ended_v1:new(#{
                room_topic => end_room_moderation_v1:get_room_topic(Cmd),
                reason => end_room_moderation_v1:get_reason(Cmd)
            }),
            {ok, [room_moderation_ended_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(end_room_moderation_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = end_room_moderation_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = end_room_moderation_v1,
        aggregate_type = room_aggregate,
        aggregate_id = end_room_moderation_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mods_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
