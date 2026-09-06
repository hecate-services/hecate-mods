%%% @doc Tests for `ring_delivery''s pure helpers -- no mesh, no keypair
%%% wired through hecate_om. The round-trip test is the one that
%%% matters most: it confirms `with_identity_proof/4' produces a
%%% signature `room_ownership_proof' (and, by the same shared byte
%%% layout, macula-mcp's own `verifyOwnershipProof') actually accepts.
-module(ring_delivery_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TARGET, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(ROOM, <<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>).

ring_procedure_matches_macula_mcps_own_naming_test() ->
    ?assertEqual(<<"agent.", ?TARGET/binary, ".ring">>, ring_delivery:ring_procedure(?TARGET)).

%% Fable review, hecate-mods#5: macula-mcp's own ring_service.ts compares
%% the wire `to' field / procedure name against its own canonical
%% (always lowercase) node id with exact case-sensitive equality.
%% target_node_id is valid (per invite_agent_to_room_v1's own hex64
%% check) in any case, so this module must normalize it itself rather
%% than assume a caller already did.
ring_procedure_lowercases_an_uppercase_target_test() ->
    ?assertEqual(<<"agent.", ?TARGET/binary, ".ring">>,
                 ring_delivery:ring_procedure(string:uppercase(?TARGET))).

ring_proof_procedure_is_bound_to_the_ring_id_test() ->
    Got = ring_delivery:ring_proof_procedure(?TARGET, <<"deadbeef">>),
    ?assertEqual(<<"agent.", ?TARGET/binary, ".ring#ring:deadbeef">>, Got).

ring_args_has_rings_ts_shape_test() ->
    Args = ring_delivery:ring_args(<<"someringid">>, <<"fromhex">>, ?TARGET, <<"purpose">>, ?ROOM),
    ?assertEqual(<<"ring">>, maps:get(kind, Args)),
    ?assertEqual(<<"someringid">>, maps:get(ring_id, Args)),
    ?assertEqual(<<"fromhex">>, maps:get(from, Args)),
    ?assertEqual(?TARGET, maps:get(to, Args)),
    ?assertEqual(<<"purpose">>, maps:get(purpose, Args)),
    ?assertEqual(?ROOM, maps:get(room_topic, Args)),
    ?assert(is_integer(maps:get(sent_at, Args))).

ring_args_lowercases_an_uppercase_target_in_the_to_field_test() ->
    Args = ring_delivery:ring_args(<<"someringid">>, <<"fromhex">>, string:uppercase(?TARGET),
                                   <<"purpose">>, ?ROOM),
    ?assertEqual(?TARGET, maps:get(to, Args)).

%% The actual wire-compatibility boundary: sign via with_identity_proof/4,
%% then verify the exact same way room_ownership_proof (and, sharing the
%% same byte layout, macula-mcp's own ring_service.ts) would.
with_identity_proof_produces_a_verifiable_signature_test() ->
    KeyPair = macula_identity:generate(),
    FromNodeId = binary:encode_hex(macula_identity:node_id(KeyPair), lowercase),
    ProofProcedure = ring_delivery:ring_proof_procedure(?TARGET, <<"deadbeef">>),
    Args = ring_delivery:ring_args(<<"deadbeef">>, FromNodeId, ?TARGET, <<"purpose">>, ?ROOM),
    Payload = ring_delivery:with_identity_proof(Args, KeyPair, FromNodeId, ProofProcedure),
    ?assertEqual(FromNodeId, maps:get(citizen_did, Payload)),
    #{proof := Proof} = Payload,
    ?assertEqual(ok, room_ownership_proof:verify(FromNodeId, Proof, ProofProcedure)),
    %% Bound to the ring id: the same signature must NOT verify against
    %% a different procedure (a different ring, or the bare unbound
    %% agent.<to>.ring name).
    ?assertMatch({error, bad_signature},
                 room_ownership_proof:verify(FromNodeId, Proof, ring_delivery:ring_procedure(?TARGET))).
