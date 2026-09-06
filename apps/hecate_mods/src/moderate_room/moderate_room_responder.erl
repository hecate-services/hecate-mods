%%% @doc RESPONDER for the `hecate_mods.moderate_room` mesh capability.
%%%
%%% Ungated for MVP: any caller may ask any room be moderated, matching
%%% mesh rooms' own trust model (opening/joining a room needs no
%%% authorization either). `idle_timeout_hours' is optional -- omitted,
%%% `moderate_room_v1:new/1' applies the 96h default.
%%% @end
-module(moderate_room_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    Params = params(Payload),
    Reply = case moderate_room_v1:new(Params) of
        {ok, Cmd} -> reply_for(maybe_moderate_room:dispatch(Cmd));
        {error, Reason} -> #{ok => 0, error => reason_to_binary(Reason)}
    end,
    {reply, Reply, State}.

params(Payload) ->
    Base = #{room_topic => hecate_om_wire:field(room_topic, Payload)},
    case hecate_om_wire:field(idle_timeout_hours, Payload, undefined) of
        undefined -> Base;
        Hours -> Base#{idle_timeout_hours => Hours}
    end.

reply_for({ok, _Version, _Events}) ->
    %% Without this, the room has no live subscription until
    %% `active_rooms_reaper''s next periodic tick (up to 15 min) --
    %% a join arriving in that window would go unobserved entirely,
    %% not just late.
    active_rooms_reaper:reconcile_now(),
    #{ok => 1};
reply_for({error, Reason}) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
