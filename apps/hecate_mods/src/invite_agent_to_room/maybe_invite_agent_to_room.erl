%%% @doc Handler for `invite_agent_to_room_v1'.
%%%
%%% Pure: authorization (the requester's proof verified, then checked
%%% against the room's own participant state) lives in the aggregate
%%% (`room_aggregate:guard_requester_is_participant/2'), not here -- by
%%% the time this runs, the request is already authorized. This handler
%%% only validates the payload's shape and builds the event, same split
%%% as `guide_mailbox_lifecycle''s `maybe_initiate_mailbox'.
%%% @end
-module(maybe_invite_agent_to_room).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case invite_agent_to_room_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(invite_agent_to_room_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case invite_agent_to_room_v1:validate(Cmd) of
        ok ->
            Event = agent_invited_v1:new(#{
                room_topic => invite_agent_to_room_v1:get_room_topic(Cmd),
                requester_node_id => invite_agent_to_room_v1:get_requester_node_id(Cmd),
                target_node_id => invite_agent_to_room_v1:get_target_node_id(Cmd),
                purpose => invite_agent_to_room_v1:get_purpose(Cmd)
            }),
            {ok, [agent_invited_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event. The actual
%% ring (network I/O) happens in `invite_agent_to_room_responder' AFTER
%% this succeeds, never here: an evoq aggregate's `execute/2' is pure,
%% same convention every other desk in this domain follows.
-spec dispatch(invite_agent_to_room_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = invite_agent_to_room_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = invite_agent_to_room_v1,
        aggregate_type = room_aggregate,
        aggregate_id = invite_agent_to_room_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mods_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
