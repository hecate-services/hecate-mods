%%% @doc Tests for `active_rooms_store' against a real, throwaway
%%% barrel_docdb database (`hecate_mods_test_db') -- no mesh, no event
%%% store, no `hecate_om:boot/1'.
-module(active_rooms_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ROOM_A, <<"agents.room.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(ROOM_B, <<"agents.room.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb">>).
-define(HOUR_MS, 3_600_000).

setup() -> hecate_mods_test_db:setup().
teardown(Db) -> hecate_mods_test_db:teardown(Db).

active_rooms_store_test_() ->
    {foreach, fun setup/0, fun teardown/1, [
        fun record_formed_appears_in_list_active/0,
        fun touch_joined_updates_last_joined_at/0,
        fun touch_joined_on_unknown_room_is_a_no_op/0,
        fun remove_drops_it_from_list_active/0,
        fun remove_on_unknown_room_is_a_no_op/0,
        fun due_for_timeout_finds_only_the_stale_room/0,
        fun a_join_after_formation_postpones_timeout/0
    ]}.

now_ms() -> erlang:system_time(millisecond).

record_formed_appears_in_list_active() ->
    ok = active_rooms_store:record_formed(?ROOM_A, 96, now_ms()),
    ?assertEqual([?ROOM_A], active_rooms_store:list_active()).

touch_joined_updates_last_joined_at() ->
    FormedAt = now_ms(),
    ok = active_rooms_store:record_formed(?ROOM_A, 96, FormedAt),
    %% A moment far enough in the future that "was it updated" isn't
    %% sensitive to clock resolution.
    JoinedAt = FormedAt + 1000,
    ok = active_rooms_store:touch_joined(?ROOM_A, JoinedAt),
    %% due_for_timeout is the only public read of last_joined_at's actual
    %% value -- a room definitely not due right after JoinedAt, at a
    %% cutoff that WOULD have been due measured from FormedAt, proves the
    %% touch moved the clock forward.
    Cutoff = FormedAt + (96 * ?HOUR_MS) + 500,
    ?assertEqual([], active_rooms_store:due_for_timeout(Cutoff)).

touch_joined_on_unknown_room_is_a_no_op() ->
    ?assertEqual(ok, active_rooms_store:touch_joined(?ROOM_A, now_ms())),
    ?assertEqual([], active_rooms_store:list_active()).

remove_drops_it_from_list_active() ->
    ok = active_rooms_store:record_formed(?ROOM_A, 96, now_ms()),
    ok = active_rooms_store:remove(?ROOM_A),
    ?assertEqual([], active_rooms_store:list_active()).

remove_on_unknown_room_is_a_no_op() ->
    ?assertEqual(ok, active_rooms_store:remove(?ROOM_A)).

%% 90 minutes late against a 1h timeout: comfortably past the due
%% threshold (60 min) but comfortably before `active_rooms_store''s own
%% defensive TTL backstop (fires at formed_at + idle_timeout_hours + 1h =
%% 2h late here) -- picking a margin that collides with the backstop
%% would make barrel_docdb's own lazy expiry hide the document before
%% this query ever ran, which is a real interaction worth this comment,
%% not a coincidence to trip over again.
due_for_timeout_finds_only_the_stale_room() ->
    Now = now_ms(),
    NinetyMinMs = 90 * 60 * 1000,
    ok = active_rooms_store:record_formed(?ROOM_A, 1, Now - NinetyMinMs),
    %% Formed just now, same 1h timeout, nowhere near due.
    ok = active_rooms_store:record_formed(?ROOM_B, 1, Now),
    ?assertEqual([?ROOM_A], active_rooms_store:due_for_timeout(Now)).

a_join_after_formation_postpones_timeout() ->
    Now = now_ms(),
    NinetyMinMs = 90 * 60 * 1000,
    ok = active_rooms_store:record_formed(?ROOM_A, 1, Now - NinetyMinMs),
    %% Without the join, room A would already be due (previous test) --
    %% a join just now resets the clock, exactly the behavior this
    %% feature exists to provide (macula-io/hecate-mods#1).
    ok = active_rooms_store:touch_joined(?ROOM_A, Now),
    ?assertEqual([], active_rooms_store:due_for_timeout(Now)).
