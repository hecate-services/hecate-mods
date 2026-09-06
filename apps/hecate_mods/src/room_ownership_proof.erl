%%% @doc Verifies a caller actually holds the private key for the
%%% node_id they claim to be -- the fix for hecate-mods#2's own open
%%% authorization question.
%%%
%%% Confirmed by reading macula-mcp's `ownership_proof.ts' directly: the
%%% signed message is CANONICAL across this whole platform, byte for
%%% byte identical to `guide_mailbox_lifecycle''s own
%%% `mailbox_ownership_proof' -- node_id (32 raw bytes) ++ timestamp (8
%%% bytes, big-endian) ++ procedure (raw UTF-8), no delimiters, no
%%% length prefixes. `ownership_proof.ts''s own header names both
%%% `mailbox_ownership_proof' and `citizen_ownership_proof' as the
%%% verifiers it must match, so this module mirrors them rather than
%%% inventing a fourth scheme. A macula node_id IS the raw Ed25519
%%% public key, so nothing but the id itself is needed to verify.
%%%
%%% `hecate_om_wire' unwraps whatever shape a wire-transported value
%%% arrives in (bare binary, bare atom, `{text, Binary}') the same way
%%% every other responder in this org's services does; this module's own
%%% public API takes already-unwrapped hex strings (the convention
%%% `room_envelope' and `room_state' already use for node ids throughout
%%% this repo) and only drops to raw bytes internally, at the point the
%%% actual Ed25519 call needs them.
%%% @end
-module(room_ownership_proof).

-export([verify/3]).

-define(MAX_SKEW_MS, 60_000).
-define(HEX64, "^[0-9a-fA-F]{64}$").
-define(HEX128, "^[0-9a-fA-F]{128}$").

%% @doc `NodeIdHex' (64 hex chars) claims to have produced `Proof' (a
%% map with `timestamp' and `signature') over `Procedure', within the
%% skew window. `ok' or `{error, invalid_node_id | missing_proof |
%% bad_signature | stale_proof}' -- never crashes on a malformed
%% caller input, since a responder must refuse with a real answer, not
%% a hang or a crashed transient process.
-spec verify(binary(), map(), binary()) -> ok | {error, atom()}.
verify(NodeIdHex, Proof, Procedure)
  when is_binary(NodeIdHex), is_map(Proof), is_binary(Procedure) ->
    case valid_hex(NodeIdHex, ?HEX64) of
        true -> checked_fields(maps:find(timestamp, Proof), maps:find(signature, Proof),
                               binary:decode_hex(NodeIdHex), Procedure);
        false -> {error, invalid_node_id}
    end;
verify(_NodeIdHex, _Proof, _Procedure) ->
    {error, invalid_node_id}.

checked_fields({ok, Ts}, {ok, Sig}, NodeId, Procedure) when is_integer(Ts), is_binary(Sig) ->
    decoded_sig(valid_hex(Sig, ?HEX128), Sig, Ts, NodeId, Procedure);
checked_fields(_Ts, _Sig, _NodeId, _Procedure) ->
    {error, missing_proof}.

decoded_sig(true, Sig, Ts, NodeId, Procedure) ->
    fresh(Ts, NodeId, binary:decode_hex(Sig), Procedure);
decoded_sig(false, _Sig, _Ts, _NodeId, _Procedure) ->
    {error, bad_signature}.

fresh(Ts, NodeId, Sig, Procedure) ->
    skew_checked(abs(erlang:system_time(millisecond) - Ts), Ts, NodeId, Sig, Procedure).

skew_checked(Skew, Ts, NodeId, Sig, Procedure) when Skew =< ?MAX_SKEW_MS ->
    signed(macula_identity:verify(message(NodeId, Ts, Procedure), Sig, NodeId));
skew_checked(_Skew, _Ts, _NodeId, _Sig, _Procedure) ->
    {error, stale_proof}.

signed(true) -> ok;
signed(false) -> {error, bad_signature}.

-spec message(binary(), integer(), binary()) -> binary().
message(NodeId, Timestamp, Procedure)
  when is_binary(NodeId), byte_size(NodeId) =:= 32, is_integer(Timestamp), is_binary(Procedure) ->
    <<NodeId/binary, Timestamp:64/big, Procedure/binary>>.

valid_hex(Bin, Pattern) ->
    case re:run(Bin, Pattern) of
        {match, _} -> true;
        nomatch -> false
    end.
