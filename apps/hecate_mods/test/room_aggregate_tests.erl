%%% @doc Tests for the room aggregate and its four desks, exercised
%%% through `init/1' + `execute/2' + `apply/2' -- the same three
%%% callbacks evoq itself drives, with no mesh, no store, no process.
%%% Same convention as `guide_mailbox_lifecycle''s `mailbox_aggregate_tests'.
-module(room_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ROOM, <<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>).
-define(ALICE, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(BOB, <<"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

new_state() ->
    {ok, S} = room_aggregate:init(?ROOM),
    S.

step(State, Payload) ->
    case room_aggregate:execute(State, Payload) of
        {ok, Events} ->
            NewState = lists:foldl(fun(Event, S) -> room_aggregate:apply(S, Event) end, State, Events),
            {{ok, Events}, NewState};
        {error, _} = Error ->
            {Error, State}
    end.

run(State, []) -> State;
run(State, [Cmd | Rest]) ->
    {{ok, _}, NewState} = step(State, Cmd),
    run(NewState, Rest).

moderate_cmd() -> moderate_cmd(96).
moderate_cmd(Hours) ->
    #{command_type => moderate_room_v1, room_topic => ?ROOM, idle_timeout_hours => Hours}.
joined_cmd(NodeId) ->
    #{command_type => note_participant_joined_v1, room_topic => ?ROOM, node_id => NodeId}.
left_cmd(NodeId) ->
    #{command_type => note_participant_left_v1, room_topic => ?ROOM, node_id => NodeId}.
end_cmd() -> end_cmd(<<"idle_timeout">>).
end_cmd(Reason) ->
    #{command_type => end_room_moderation_v1, room_topic => ?ROOM, reason => Reason}.

moderated_state() -> run(new_state(), [moderate_cmd()]).

%%--------------------------------------------------------------------
%% moderate_room
%%--------------------------------------------------------------------

moderate_room_from_fresh_state_test() ->
    {{ok, [Event]}, State} = step(new_state(), moderate_cmd()),
    ?assertEqual(<<"room_formed_v1">>, maps:get(event_type, Event)),
    ?assertEqual(96, maps:get(idle_timeout_hours, Event)),
    ?assertEqual(true, room_state:is_formed(State)),
    ?assertEqual(false, room_state:is_ended(State)),
    %% Baseline: the idle clock starts at formation, not undefined --
    %% otherwise a room with zero joins ever could never time out.
    ?assertEqual(room_state:last_joined_at(State), maps:get(formed_at, Event)).

moderate_room_twice_is_rejected_test() ->
    S1 = moderated_state(),
    {Result, _} = step(S1, moderate_cmd()),
    ?assertEqual({error, already_moderated}, Result).

%%--------------------------------------------------------------------
%% note_participant_joined / note_participant_left
%%--------------------------------------------------------------------

joined_before_moderation_is_rejected_test() ->
    {Result, _} = step(new_state(), joined_cmd(?ALICE)),
    ?assertEqual({error, not_moderated}, Result).

joined_after_moderation_resets_the_idle_clock_test() ->
    S1 = moderated_state(),
    FormedAt = room_state:last_joined_at(S1),
    %% Real clock, not a fake one -- this only needs joined_at to be
    %% strictly after formed_at, not a specific value.
    timer:sleep(2),
    {{ok, [Event]}, S2} = step(S1, joined_cmd(?ALICE)),
    ?assertEqual(<<"participant_joined_v1">>, maps:get(event_type, Event)),
    ?assert(room_state:last_joined_at(S2) > FormedAt),
    ?assertEqual(room_state:last_joined_at(S2), maps:get(joined_at, Event)).

left_after_moderation_does_not_reset_the_idle_clock_test() ->
    S1 = moderated_state(),
    LastJoined = room_state:last_joined_at(S1),
    {{ok, [Event]}, S2} = step(S1, left_cmd(?BOB)),
    ?assertEqual(<<"participant_left_v1">>, maps:get(event_type, Event)),
    %% The one behavior this whole feature exists to get right (Raf's own
    %% decision, macula-io/hecate-mods#1): a leave never resets the timeout.
    ?assertEqual(LastJoined, room_state:last_joined_at(S2)).

joined_after_ended_is_rejected_test() ->
    S1 = run(moderated_state(), [end_cmd()]),
    {Result, _} = step(S1, joined_cmd(?ALICE)),
    ?assertEqual({error, moderation_ended}, Result).

%%--------------------------------------------------------------------
%% end_room_moderation
%%--------------------------------------------------------------------

end_before_moderation_is_rejected_test() ->
    {Result, _} = step(new_state(), end_cmd()),
    ?assertEqual({error, not_moderated}, Result).

end_after_moderation_succeeds_test() ->
    S1 = moderated_state(),
    {{ok, [Event]}, S2} = step(S1, end_cmd(<<"idle_timeout">>)),
    ?assertEqual(<<"room_moderation_ended_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"idle_timeout">>, maps:get(reason, Event)),
    ?assertEqual(true, room_state:is_ended(S2)),
    %% Terminal, but formed stays true -- ended is additive, not a reset
    %% of formation (same convention as mailbox's ARCHIVED bit).
    ?assertEqual(true, room_state:is_formed(S2)).

end_twice_is_rejected_test() ->
    S1 = run(moderated_state(), [end_cmd()]),
    {Result, _} = step(S1, end_cmd()),
    ?assertEqual({error, moderation_ended}, Result).

%%--------------------------------------------------------------------
%% Unknown commands
%%--------------------------------------------------------------------

unknown_command_type_is_rejected_test() ->
    {Result, _} = step(new_state(), #{command_type => not_a_real_command}),
    ?assertEqual({error, unknown_command}, Result).

payload_with_no_command_type_is_rejected_test() ->
    {Result, _} = step(new_state(), #{}),
    ?assertEqual({error, unknown_command}, Result).
