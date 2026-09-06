%%% @doc Tests for `invite_agent_to_room_v1:new/1' and `procedure/2' --
%%% pure, no mesh, no store. Same crash-prevention reasoning as
%%% `moderate_room_v1_tests' (Fable review, hecate-mods#5): `new/1' must
%%% reject a malformed `room_topic' itself, since `dispatch/1' computes
%%% `stream_id/1' -- which crashes on anything not shaped
%%% `"agents.room.<32hex>"' -- before validation ever runs.
-module(invite_agent_to_room_v1_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ROOM, <<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>).
-define(ALICE, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(BOB, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).

base_params() ->
    #{room_topic => ?ROOM, requester_node_id => ?ALICE, target_node_id => ?BOB,
      purpose => <<"come help">>, proof => #{timestamp => 1, signature => <<"x">>}}.

new_accepts_well_formed_params_test() ->
    ?assertMatch({ok, _}, invite_agent_to_room_v1:new(base_params())).

new_rejects_a_malformed_room_topic_instead_of_deferring_to_stream_id_test() ->
    Params = (base_params())#{room_topic => <<"garbage">>},
    ?assertEqual({error, invalid_room_topic}, invite_agent_to_room_v1:new(Params)).

stream_id_never_crashes_on_a_command_new_1_accepted_test() ->
    {ok, Cmd} = invite_agent_to_room_v1:new(base_params()),
    ?assertEqual(<<"room-deadbeefdeadbeefdeadbeefdeadbeef">>, invite_agent_to_room_v1:stream_id(Cmd)).

%% Fable review, hecate-mods#5: macula-mcp's own ring_service.ts compares
%% the wire `to' field against its own canonical (always lowercase) node
%% id with exact case-sensitive equality. requester_node_id/target_node_id
%% are normalized once, here, so nothing downstream needs to remember to.
new_lowercases_requester_and_target_node_ids_test() ->
    Params = (base_params())#{requester_node_id => string:uppercase(?ALICE),
                              target_node_id => string:uppercase(?BOB)},
    {ok, Cmd} = invite_agent_to_room_v1:new(Params),
    ?assertEqual(?ALICE, invite_agent_to_room_v1:get_requester_node_id(Cmd)),
    ?assertEqual(?BOB, invite_agent_to_room_v1:get_target_node_id(Cmd)).

new_rejects_missing_fields_test() ->
    ?assertEqual({error, missing_required_field}, invite_agent_to_room_v1:new(#{})).

validate_rejects_inviting_yourself_test() ->
    {ok, Cmd} = invite_agent_to_room_v1:new((base_params())#{target_node_id => ?ALICE}),
    ?assertEqual({error, cannot_invite_self}, invite_agent_to_room_v1:validate(Cmd)).

%% Case must not be a loophole around the self-invite guard either --
%% now that new/1 normalizes both to lowercase, ALICE vs alice can no
%% longer slip past as "distinct."
validate_rejects_inviting_yourself_by_case_variant_test() ->
    Params = (base_params())#{requester_node_id => ?ALICE, target_node_id => string:uppercase(?ALICE)},
    {ok, Cmd} = invite_agent_to_room_v1:new(Params),
    ?assertEqual({error, cannot_invite_self}, invite_agent_to_room_v1:validate(Cmd)).

validate_accepts_a_command_new_1_already_accepted_test() ->
    {ok, Cmd} = invite_agent_to_room_v1:new(base_params()),
    ?assertEqual(ok, invite_agent_to_room_v1:validate(Cmd)).

%% Fable review, hecate-mods#5: the proof must be bound to THIS specific
%% invite, not just the capability name -- otherwise a proof captured
%% off the wire could be replayed against a different target or room.
procedure_is_bound_to_room_topic_and_target_test() ->
    P1 = invite_agent_to_room_v1:procedure(?ROOM, ?BOB),
    P2 = invite_agent_to_room_v1:procedure(?ROOM, ?ALICE),
    P3 = invite_agent_to_room_v1:procedure(<<"agents.room.cafebabecafebabecafebabecafebabe">>, ?BOB),
    ?assertNotEqual(P1, P2),
    ?assertNotEqual(P1, P3).
