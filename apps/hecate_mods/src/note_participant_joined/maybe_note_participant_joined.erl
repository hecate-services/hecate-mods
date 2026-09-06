%%% @doc Handler for `note_participant_joined_v1'.
%%%
%%% Pure: the "must be actively moderated" guard lives in the aggregate
%%% (`room_aggregate:guard_active/2'), not here.
%%% @end
-module(maybe_note_participant_joined).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case note_participant_joined_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(note_participant_joined_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case note_participant_joined_v1:validate(Cmd) of
        ok ->
            Event = participant_joined_v1:new(#{
                room_topic => note_participant_joined_v1:get_room_topic(Cmd),
                node_id => note_participant_joined_v1:get_node_id(Cmd)
            }),
            {ok, [participant_joined_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(note_participant_joined_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = note_participant_joined_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = note_participant_joined_v1,
        aggregate_type = room_aggregate,
        aggregate_id = note_participant_joined_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mods_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
