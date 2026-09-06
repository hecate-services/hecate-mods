%%% @doc Tests for `moderate_room_v1:new/1' -- pure, no mesh, no store.
%%%
%%% The malformed-room-topic case matters specifically because of WHAT
%%% happens after `new/1' if it doesn't catch it: `dispatch/1' computes
%%% `stream_id(Cmd)' -> `room_aggregate:stream_id/1', which pattern-
%%% matches the exact `"agents.room."' prefix and CRASHES (badmatch) on
%%% anything else -- before the aggregate, and therefore before
%%% `validate/1', ever runs. `new/1' is the only gate that can catch
%%% this before it reaches that crash (Fable review, hecate-mods#5).
-module(moderate_room_v1_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ROOM, <<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>).

new_accepts_a_well_formed_room_topic_test() ->
    ?assertMatch({ok, _}, moderate_room_v1:new(#{room_topic => ?ROOM})).

new_rejects_a_malformed_room_topic_instead_of_deferring_to_stream_id_test() ->
    ?assertEqual({error, invalid_room_topic}, moderate_room_v1:new(#{room_topic => <<"garbage">>})).

new_applies_the_96h_default_idle_timeout_test() ->
    {ok, Cmd} = moderate_room_v1:new(#{room_topic => ?ROOM}),
    ?assertEqual(96, moderate_room_v1:get_idle_timeout_hours(Cmd)).

new_honors_an_explicit_idle_timeout_test() ->
    {ok, Cmd} = moderate_room_v1:new(#{room_topic => ?ROOM, idle_timeout_hours => 24}),
    ?assertEqual(24, moderate_room_v1:get_idle_timeout_hours(Cmd)).

new_rejects_a_missing_room_topic_test() ->
    ?assertEqual({error, missing_room_topic}, moderate_room_v1:new(#{})).

%% A room_topic that survives `new/1' never fails `stream_id/1' -- this
%% is the actual regression check: no crash, real stream id back.
stream_id_never_crashes_on_a_command_new_1_accepted_test() ->
    {ok, Cmd} = moderate_room_v1:new(#{room_topic => ?ROOM}),
    ?assertEqual(<<"room-deadbeefdeadbeefdeadbeefdeadbeef">>, moderate_room_v1:stream_id(Cmd)).

validate_rejects_a_non_positive_idle_timeout_test() ->
    {ok, Cmd} = moderate_room_v1:new(#{room_topic => ?ROOM, idle_timeout_hours => 0}),
    ?assertEqual({error, invalid_idle_timeout_hours}, moderate_room_v1:validate(Cmd)).

validate_accepts_a_command_new_1_already_accepted_test() ->
    {ok, Cmd} = moderate_room_v1:new(#{room_topic => ?ROOM}),
    ?assertEqual(ok, moderate_room_v1:validate(Cmd)).
