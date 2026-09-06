%%% @doc Tests for `room_topic:valid/1' -- pure, no mesh, no store.
-module(room_topic_tests).

-include_lib("eunit/include/eunit.hrl").

accepts_a_well_formed_topic_test() ->
    ?assert(room_topic:valid(<<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>)).

rejects_uppercase_hex_test() ->
    %% The room-topic contract (envelope.ts) is lowercase-only, unlike a
    %% node id (which is case-insensitive hex) -- this is a DIFFERENT
    %% rule, deliberately not the same regex.
    ?assertNot(room_topic:valid(<<"agents.room.DEADBEEFDEADBEEFDEADBEEFDEADBEEF">>)).

rejects_the_wrong_hex_length_test() ->
    ?assertNot(room_topic:valid(<<"agents.room.deadbeef">>)),
    ?assertNot(room_topic:valid(<<"agents.room.deadbeefdeadbeefdeadbeefdeadbeefaa">>)).

rejects_a_missing_prefix_test() ->
    ?assertNot(room_topic:valid(<<"deadbeefdeadbeefdeadbeefdeadbeef">>)).

rejects_a_central_topic_test() ->
    ?assertNot(room_topic:valid(<<"agents.lobby">>)).

rejects_garbage_test() ->
    ?assertNot(room_topic:valid(<<"not-a-room-topic">>)),
    ?assertNot(room_topic:valid(<<>>)).

rejects_a_non_binary_test() ->
    ?assertNot(room_topic:valid(undefined)),
    ?assertNot(room_topic:valid(42)).
