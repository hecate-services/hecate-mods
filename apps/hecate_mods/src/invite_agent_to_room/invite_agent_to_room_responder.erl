%%% @doc RESPONDER for the `hecate_mods.invite_agent_to_room` mesh
%%% capability (macula-io/hecate-mods#2).
%%%
%%% Unlike every other capability in this domain, this one is GATED:
%%% the caller must prove (a signed ownership proof, verified inside
%%% `room_aggregate') they are `requester_node_id', AND that verified
%%% identity must be a current participant of `room_topic' per the
%%% room's own state -- never a caller-supplied claim, per the issue's
%%% own explicit requirement. A refused request gets a real answer
%%% (`{ok => 0, error => Reason}'), never a silent drop or a hang.
%%%
%%% The ring itself (`ring_delivery', network I/O) only runs AFTER
%%% `agent_invited_v1' is durably recorded -- i.e. only once authorized.
%%% @end
-module(invite_agent_to_room_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, []}.

-spec handle_request(map(), term()) -> {reply, map(), term()}.
handle_request(Payload, State) ->
    Params = params(Payload),
    Reply = case invite_agent_to_room_v1:new(Params) of
        {ok, Cmd} -> authorized(maybe_invite_agent_to_room:dispatch(Cmd), Cmd);
        {error, Reason} -> #{ok => 0, error => reason_to_binary(Reason)}
    end,
    {reply, Reply, State}.

authorized({ok, _Version, _Events}, Cmd) ->
    rung(ring_delivery:ring(
        invite_agent_to_room_v1:get_target_node_id(Cmd),
        invite_agent_to_room_v1:get_room_topic(Cmd),
        invite_agent_to_room_v1:get_purpose(Cmd)
    ));
authorized({error, Reason}, _Cmd) ->
    #{ok => 0, error => reason_to_binary(Reason)}.

rung(#{answer := Answer} = Outcome) ->
    omit_undefined(#{ok => 1, answer => Answer, reason => maps:get(reason, Outcome, undefined)});
rung(#{unreachable := 1, reason := Reason}) ->
    #{ok => 1, unreachable => 1, reason => Reason}.

omit_undefined(Map) -> maps:filter(fun(_K, V) -> V =/= undefined end, Map).

params(Payload) ->
    #{
        room_topic => hecate_om_wire:field(room_topic, Payload),
        requester_node_id => hecate_om_wire:field(requester_node_id, Payload),
        target_node_id => hecate_om_wire:field(target_node_id, Payload),
        purpose => hecate_om_wire:field(purpose, Payload),
        proof => proof(hecate_om_wire:field(proof, Payload))
    }.

proof(Proof) when is_map(Proof) ->
    #{
        timestamp => hecate_om_wire:field(timestamp, Proof),
        signature => hecate_om_wire:field(signature, Proof)
    };
proof(_NotAMap) ->
    #{}.

reason_to_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_to_binary(R) when is_binary(R) -> R;
reason_to_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
