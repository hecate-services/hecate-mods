%%% @doc Performs the actual ring (network I/O + hecate-mods' own
%%% signing) once `room_aggregate' has already authorized the request
%%% and `agent_invited_v1' is durably recorded. hecate-mods rings AS
%%% ITSELF (its own node_id, its own keypair) -- the issue's own framing
%%% is "the moderator... rings them in... on the requester's behalf,"
%%% not the requester's own identity performing the call.
%%%
%%% There is no "ring" concept in `macula' itself, same as rooms
%%% (`room_envelope''s own doc): this reimplements macula-mcp's own
%%% wire contract directly (`rings.ts', `ring_service.ts',
%%% `ownership_proof.ts'), read from source rather than guessed --
%%% `ring_id'/`kind'/field names, and the identical byte-for-byte
%%% `{node_id, timestamp, procedure}' signed message every ownership
%%% proof on this platform shares (see `room_ownership_proof''s own
%%% doc).
%%%
%%% ⚠ REALM ASSUMPTION, flagged for review rather than silently
%%% guessed: `agent.<node_id>.ring' is served under the mesh's default
%%% (all-zero) realm every ordinary mesh agent presents under
%%% (mesh_hello/mesh_ring/mesh_rooms all default there, per this
%%% workspace's own memory) -- NOT `hecate_om:realm()', which is
%%% hecate-mods' own Hecate-scoped realm for ITS OWN capability
%%% registration. Calling under the wrong realm fails as
%%% `unknown_next_peer', not a clear "wrong realm" error, so this is
%%% exactly the kind of thing worth a second pair of eyes plus a live
%%% round-trip test before merge, not just a read of the docs.
%%%
%%% Deliberately NOT reimplemented (scope note for the PR/Fable review,
%%% not an oversight): `ring_service.ts''s reply-proof verification
%%% (`verifyOwnershipProof' on the ANSWER), direct-dial fallback on a
%%% plain call failure, and wait-for-join. Those protect the RINGER's
%%% own trust decision about a reply it receives; the security property
%%% hecate-mods#2 actually asks for is the AUTHORIZATION gate on who
%%% may TRIGGER a ring at all, which is enforced before this module
%%% ever runs. The plain answer (accepted/declined/deferred) is relayed
%%% to the RPC caller as-is; "unreachable" covers a failed/malformed
%%% call the same way `mesh_ring.ts' does.
-module(ring_delivery).

-export([ring/3]).
%% Pure helpers, exported for direct unit tests independent of a live
%% mesh/keypair -- same convention as `active_rooms_store''s own split
%% between pure query logic and its I/O wrappers.
-export([ring_args/5, ring_procedure/1, ring_proof_procedure/2, with_identity_proof/4]).

-define(ALL_ZERO_REALM, <<0:256>>).
-define(RING_KIND, <<"ring">>).
-define(CALL_TIMEOUT_MS, 40_000).

-type outcome() :: #{answer := 1 | 2 | 3, reason => binary()}
                  | #{unreachable := 1, reason := binary()}.

-spec ring(binary(), binary(), binary()) -> outcome().
ring(TargetNodeIdHex, RoomTopic, Purpose) ->
    dialed(hecate_om:macula_client(), hecate_om:keypair(), TargetNodeIdHex, RoomTopic, Purpose).

dialed({ok, Pool}, {ok, KeyPair}, TargetNodeIdHex, RoomTopic, Purpose) ->
    FromNodeId = binary:encode_hex(macula_identity:node_id(KeyPair), lowercase),
    RingId = binary:encode_hex(crypto:strong_rand_bytes(16), lowercase),
    Args = ring_args(RingId, FromNodeId, TargetNodeIdHex, Purpose, RoomTopic),
    Procedure = ring_procedure(TargetNodeIdHex),
    ProofProcedure = ring_proof_procedure(TargetNodeIdHex, RingId),
    Payload = with_identity_proof(Args, KeyPair, FromNodeId, ProofProcedure),
    called(macula_client:call(Pool, ?ALL_ZERO_REALM, Procedure, Payload, ?CALL_TIMEOUT_MS));
dialed({error, _}, _KeyPairResult, _TargetNodeIdHex, _RoomTopic, _Purpose) ->
    #{unreachable => 1, reason => <<"mesh_unavailable">>};
dialed(_MaculaClientResult, {error, no_keypair}, _TargetNodeIdHex, _RoomTopic, _Purpose) ->
    #{unreachable => 1, reason => <<"hecate-mods has no signing keypair (ephemeral identity)">>}.

%% @doc `rings.ts''s `RingArgs' shape, exactly: kind, ring_id, from, to,
%% purpose, room_topic, sent_at.
-spec ring_args(binary(), binary(), binary(), binary(), binary()) -> map().
ring_args(RingId, FromNodeId, TargetNodeIdHex, Purpose, RoomTopic) ->
    #{
        kind => ?RING_KIND,
        ring_id => RingId,
        from => FromNodeId,
        to => TargetNodeIdHex,
        purpose => Purpose,
        room_topic => RoomTopic,
        sent_at => erlang:system_time(millisecond)
    }.

%% @doc `citizenship.ts''s `withIdentityProof': the args, plus
%% `citizen_did' (this platform's proof wrapper names it that
%% regardless of caller kind) and a `proof' signed over `ProofProcedure'
%% -- bound to THIS ring id, per `rings.ts''s own `ringProofProcedure',
%% never the bare `agent.<to>.ring' the station routes the call on.
with_identity_proof(Args, KeyPair, FromNodeId, ProofProcedure) ->
    Timestamp = erlang:system_time(millisecond),
    Message = <<(macula_identity:node_id(KeyPair))/binary, Timestamp:64/big, ProofProcedure/binary>>,
    Signature = binary:encode_hex(macula_identity:sign(Message, KeyPair), lowercase),
    Args#{
        citizen_did => FromNodeId,
        proof => #{timestamp => Timestamp, signature => Signature}
    }.

ring_procedure(NodeIdHex) -> <<"agent.", NodeIdHex/binary, ".ring">>.

ring_proof_procedure(NodeIdHex, RingId) ->
    <<(ring_procedure(NodeIdHex))/binary, "#ring:", RingId/binary>>.

called({ok, Payload}) -> parsed_reply(Payload);
called({error, Reason}) -> #{unreachable => 1, reason => reason_binary(Reason)}.

parsed_reply(#{answer := Answer} = Payload) when Answer =:= 1; Answer =:= 2; Answer =:= 3 ->
    with_reason(#{answer => Answer}, maps:get(reason, Payload, undefined));
parsed_reply(Other) ->
    #{unreachable => 1, reason => <<"malformed reply: ", (reason_binary(Other))/binary>>}.

with_reason(Map, undefined) -> Map;
with_reason(Map, Reason) when is_binary(Reason) -> Map#{reason => Reason}.

reason_binary(R) when is_atom(R) -> atom_to_binary(R, utf8);
reason_binary(R) when is_binary(R) -> R;
reason_binary(R) -> iolist_to_binary(io_lib:format("~p", [R])).
