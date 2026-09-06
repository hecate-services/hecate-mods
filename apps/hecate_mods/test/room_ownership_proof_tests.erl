%%% @doc Tests for `room_ownership_proof' -- pure crypto, no mesh, no
%%% store. Uses a real generated Ed25519 keypair each run, matching
%%% `macula_identity''s own real sign/verify, not a fixture signer --
%%% this is exactly the wire-compatibility boundary macula-io/
%%% hecate-mods#2 depends on being right.
-module(room_ownership_proof_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PROCEDURE, <<"hecate_mods.invite_agent_to_room">>).

keypair() -> macula_identity:generate().

node_id_hex(KeyPair) -> binary:encode_hex(macula_identity:node_id(KeyPair), lowercase).

%% Signs exactly the byte layout `room_ownership_proof:message/3'
%% (private) computes -- reimplemented here, deliberately, the same way
%% a real independent caller (macula-mcp's own `signOwnershipProof')
%% would produce a proof, rather than calling the module's own private
%% helper and trivially agreeing with itself.
sign(KeyPair, NodeIdHex, Timestamp, Procedure) ->
    NodeId = binary:decode_hex(NodeIdHex),
    Message = <<NodeId/binary, Timestamp:64/big, Procedure/binary>>,
    binary:encode_hex(macula_identity:sign(Message, KeyPair), lowercase).

proof(KeyPair, NodeIdHex, Timestamp, Procedure) ->
    #{timestamp => Timestamp, signature => sign(KeyPair, NodeIdHex, Timestamp, Procedure)}.

now_ms() -> erlang:system_time(millisecond).

verifies_a_genuine_proof_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    Proof = proof(KeyPair, NodeIdHex, now_ms(), ?PROCEDURE),
    ?assertEqual(ok, room_ownership_proof:verify(NodeIdHex, Proof, ?PROCEDURE)).

rejects_a_proof_signed_by_a_different_key_test() ->
    Claimed = keypair(),
    Actual = keypair(),
    ClaimedHex = node_id_hex(Claimed),
    %% Signed by Actual's key but claiming to be Claimed's node_id --
    %% exactly the forgery this module exists to catch.
    Proof = proof(Actual, ClaimedHex, now_ms(), ?PROCEDURE),
    ?assertEqual({error, bad_signature}, room_ownership_proof:verify(ClaimedHex, Proof, ?PROCEDURE)).

rejects_a_proof_bound_to_a_different_procedure_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    %% Signed for a different capability's procedure -- a valid proof
    %% minted for get_mailbox must not authorize invite_agent_to_room,
    %% and vice versa.
    Proof = proof(KeyPair, NodeIdHex, now_ms(), <<"hecate_mods.some_other_capability">>),
    ?assertEqual({error, bad_signature}, room_ownership_proof:verify(NodeIdHex, Proof, ?PROCEDURE)).

rejects_a_stale_proof_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    StaleTs = now_ms() - 120_000,
    Proof = proof(KeyPair, NodeIdHex, StaleTs, ?PROCEDURE),
    ?assertEqual({error, stale_proof}, room_ownership_proof:verify(NodeIdHex, Proof, ?PROCEDURE)).

rejects_a_proof_from_the_future_beyond_skew_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    FutureTs = now_ms() + 120_000,
    Proof = proof(KeyPair, NodeIdHex, FutureTs, ?PROCEDURE),
    ?assertEqual({error, stale_proof}, room_ownership_proof:verify(NodeIdHex, Proof, ?PROCEDURE)).

rejects_a_malformed_node_id_test() ->
    Proof = #{timestamp => now_ms(), signature => binary:copy(<<"a">>, 128)},
    ?assertEqual({error, invalid_node_id}, room_ownership_proof:verify(<<"not-hex">>, Proof, ?PROCEDURE)).

rejects_a_missing_signature_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    ?assertEqual({error, missing_proof}, room_ownership_proof:verify(NodeIdHex, #{timestamp => now_ms()}, ?PROCEDURE)).

rejects_a_malformed_signature_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    Proof = #{timestamp => now_ms(), signature => <<"not-hex-and-wrong-length">>},
    ?assertEqual({error, bad_signature}, room_ownership_proof:verify(NodeIdHex, Proof, ?PROCEDURE)).

%% Case-insensitivity on the node id itself isn't required by this
%% module's own contract (hex decode is case-tolerant either way, per
%% binary:decode_hex/1) -- this just pins that an uppercase-hex caller
%% still verifies, since node ids arrive in whatever case a sender used.
verifies_regardless_of_node_id_hex_case_test() ->
    KeyPair = keypair(),
    NodeIdHex = node_id_hex(KeyPair),
    Proof = proof(KeyPair, NodeIdHex, now_ms(), ?PROCEDURE),
    ?assertEqual(ok, room_ownership_proof:verify(string:uppercase(NodeIdHex), Proof, ?PROCEDURE)).
