%%% @doc Command `invite_agent_to_room_v1'.
%%%
%%% Only a current room participant may ask the moderator to invite
%%% another agent in (macula-io/hecate-mods#2) -- `requester_node_id'
%%% is a claim this command carries, verified against the aggregate's
%%% own participant-set state (`room_aggregate:guard_requester_is_
%%% participant/2'), never trusted on its own. `proof' binds that claim
%%% to a signature only the requester's own private key could produce,
%%% over `procedure/2' specifically -- bound to THIS room_topic and
%%% THIS target_node_id, not just this capability in general, so a
%%% proof captured off the wire cannot be replayed to invite a
%%% DIFFERENT target, or into a DIFFERENT room the same requester
%%% happens to also be in (Fable review, hecate-mods#5: the original
%%% `procedure/0' bound only to the fixed capability name, the same
%%% class of gap `ring_delivery''s own per-ring-id proof binding was
%%% deliberately written to avoid on the OUTGOING side).
%%%
%%% `requester_node_id'/`target_node_id' are normalized to lowercase
%%% hex here, at construction, once -- not scattered as ad hoc
%%% `string:lowercase/1' calls at each later comparison. Also found by
%%% the same review: macula-mcp's `ring_service.ts' compares `ring.to'
%%% to its own canonical (always-lowercase) node id with exact
%%% case-sensitive equality, so an uppercase-hex `target_node_id' (valid
%%% per this module's own hex64 check, which is case-insensitive) would
%%% otherwise silently fail to route or to verify at all.
-module(invite_agent_to_room_v1).
-behaviour(evoq_command).

-export([command_type/0, procedure/2]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1, get_room_topic/1, get_requester_node_id/1,
         get_target_node_id/1, get_purpose/1, get_proof/1]).

-define(HEX64, "^[0-9a-fA-F]{64}$").
-define(MAX_PURPOSE_BYTES, 280).

-record(invite_agent_to_room_v1, {
    room_topic :: binary() | undefined,
    requester_node_id :: binary() | undefined,
    target_node_id :: binary() | undefined,
    purpose :: binary() | undefined,
    proof :: map() | undefined
}).

-opaque t() :: #invite_agent_to_room_v1{}.
-export_type([t/0]).

-spec command_type() -> atom().
command_type() -> invite_agent_to_room_v1.

%% @doc The procedure name a requester's ownership proof for THIS
%% specific invite must be signed over -- shared between
%% `room_aggregate' (verifying) and any real caller producing a proof.
%% Bound to `RoomTopic' and `TargetNodeIdHex' so a proof authorizes
%% exactly one invite, never a different target or a different room.
-spec procedure(binary(), binary()) -> binary().
procedure(RoomTopic, TargetNodeIdHex) ->
    <<"hecate_mods.invite_agent_to_room#room:", RoomTopic/binary, ":target:", TargetNodeIdHex/binary>>.

%% @doc Room-topic FORMAT is checked here, not only in `validate/1':
%% `stream_id/1' (called by `dispatch/1', before the aggregate or its
%% handler's own `validate/1' ever run) pattern-matches the exact
%% `"agents.room."' prefix and crashes on anything else (Fable review,
%% hecate-mods#5).
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{room_topic := Topic, requester_node_id := Requester, target_node_id := Target,
      purpose := Purpose} = Params) when is_binary(Topic), is_binary(Requester),
                                         is_binary(Target), is_binary(Purpose) ->
    checked_room_topic(room_topic:valid(Topic), Topic, Requester, Target, Purpose, Params);
new(_) ->
    {error, missing_required_field}.

checked_room_topic(true, Topic, Requester, Target, Purpose, Params) ->
    {ok, #invite_agent_to_room_v1{
        room_topic = Topic,
        requester_node_id = string:lowercase(Requester),
        target_node_id = string:lowercase(Target),
        purpose = Purpose,
        proof = maps:get(proof, Params, #{})
    }};
checked_room_topic(false, _Topic, _Requester, _Target, _Purpose, _Params) ->
    {error, invalid_room_topic}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(Params) -> new(Params).

%% @doc `room_topic' is already guaranteed valid-shaped, and
%% `requester_node_id'/`target_node_id' already lowercased, by `new/1'
%% -- every `t()' is constructed there.
-spec validate(t()) -> ok | {error, term()}.
validate(#invite_agent_to_room_v1{requester_node_id = Requester, target_node_id = Target,
                                  purpose = Purpose, proof = Proof})
  when is_map(Proof) ->
    checked(hex64(Requester), hex64(Target), Requester, Target, Purpose);
validate(_) -> {error, missing_required_field}.

checked(true, true, Requester, Target, Purpose) ->
    distinct(Requester =/= Target, Purpose);
checked(false, _, _Requester, _Target, _Purpose) -> {error, invalid_requester_node_id};
checked(_, false, _Requester, _Target, _Purpose) -> {error, invalid_target_node_id}.

distinct(true, Purpose) -> purposed(Purpose);
distinct(false, _Purpose) -> {error, cannot_invite_self}.

purposed(Purpose) when is_binary(Purpose), byte_size(Purpose) > 0,
                       byte_size(Purpose) =< ?MAX_PURPOSE_BYTES -> ok;
purposed(_Purpose) -> {error, invalid_purpose}.

hex64(Bin) when is_binary(Bin) ->
    case re:run(Bin, ?HEX64) of
        {match, _} -> true;
        nomatch -> false
    end;
hex64(_NotABinary) -> false.

-spec to_map(t()) -> map().
to_map(#invite_agent_to_room_v1{room_topic = Topic, requester_node_id = Requester,
                                target_node_id = Target, purpose = Purpose, proof = Proof}) ->
    #{command_type => invite_agent_to_room_v1, room_topic => Topic,
      requester_node_id => Requester, target_node_id => Target,
      purpose => Purpose, proof => Proof}.

-spec stream_id(t()) -> binary().
stream_id(#invite_agent_to_room_v1{room_topic = Topic}) ->
    room_aggregate:stream_id(Topic).

-spec get_room_topic(t()) -> binary() | undefined.
get_room_topic(#invite_agent_to_room_v1{room_topic = V}) -> V.

-spec get_requester_node_id(t()) -> binary() | undefined.
get_requester_node_id(#invite_agent_to_room_v1{requester_node_id = V}) -> V.

-spec get_target_node_id(t()) -> binary() | undefined.
get_target_node_id(#invite_agent_to_room_v1{target_node_id = V}) -> V.

-spec get_purpose(t()) -> binary() | undefined.
get_purpose(#invite_agent_to_room_v1{purpose = V}) -> V.

-spec get_proof(t()) -> map() | undefined.
get_proof(#invite_agent_to_room_v1{proof = V}) -> V.
