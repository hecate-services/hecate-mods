%%% @doc Handler for `moderate_room_v1'.
%%%
%%% Pure: the "already moderated" guard lives in the aggregate
%%% (`room_aggregate:do_execute/3'), not here -- this handler only
%%% validates the payload and builds the event, same split as
%%% `guide_mailbox_lifecycle''s `maybe_initiate_mailbox'.
%%% @end
-module(maybe_moderate_room).

-export([handle_from_map/1, handle/1, dispatch/1]).

-include_lib("evoq/include/evoq.hrl").

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    case moderate_room_v1:from_map(Payload) of
        {ok, Cmd} -> handle(Cmd);
        {error, _} = E -> E
    end.

-spec handle(moderate_room_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) ->
    case moderate_room_v1:validate(Cmd) of
        ok ->
            Event = room_formed_v1:new(#{
                room_topic => moderate_room_v1:get_room_topic(Cmd),
                idle_timeout_hours => moderate_room_v1:get_idle_timeout_hours(Cmd)
            }),
            {ok, [room_formed_v1:to_map(Event)]};
        {error, _} = E -> E
    end.

%% @doc Dispatch via evoq -- persists the produced event.
-spec dispatch(moderate_room_v1:t()) -> {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(Cmd) ->
    CmdMap = moderate_room_v1:to_map(Cmd),
    EvoqCmd = #evoq_command{
        command_type = moderate_room_v1,
        aggregate_type = room_aggregate,
        aggregate_id = moderate_room_v1:stream_id(Cmd),
        payload = CmdMap,
        metadata = #{timestamp => erlang:system_time(millisecond)}
    },
    evoq_command_router:dispatch(EvoqCmd, #{
        store_id => hecate_mods_store,
        adapter => reckon_evoq_adapter,
        consistency => eventual
    }).
