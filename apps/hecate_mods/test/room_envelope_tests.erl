%%% @doc Tests for `room_envelope':decode/2 -- pure, no mesh, no store.
%%% Every wire shape here is macula-mcp's own envelope.ts contract, and
%%% every attestation case exercises the STRONGER Erlang-side signal
%%% (`Meta.publisher_verified') this module requires over macula-mcp's own
%%% weaker TS-side "publisher label matches claimed from" check.
-module(room_envelope_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FROM, <<"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa">>).
-define(ROOM, <<"agents.room.deadbeefdeadbeefdeadbeefdeadbeef">>).

envelope(Overrides) ->
    maps:merge(#{kind => <<"participant_joined">>, from => ?FROM,
                 room_topic => ?ROOM, text => <<>>}, Overrides).

verified_meta() -> #{publisher => ?FROM, publisher_verified => true}.

decodes_a_well_formed_attested_envelope_test() ->
    {ok, Decoded} = room_envelope:decode(envelope(#{}), verified_meta()),
    ?assertEqual(#{kind => <<"participant_joined">>, from => ?FROM, room_topic => ?ROOM}, Decoded).

decodes_a_raw_32_byte_publisher_key_normalized_to_hex_test() ->
    RawKey = binary:decode_hex(?FROM),
    Meta = #{publisher => RawKey, publisher_verified => true},
    ?assertMatch({ok, _}, room_envelope:decode(envelope(#{}), Meta)).

publisher_hex_case_is_ignored_test() ->
    Meta = #{publisher => string:uppercase(?FROM), publisher_verified => true},
    ?assertMatch({ok, _}, room_envelope:decode(envelope(#{}), Meta)).

rejects_when_not_verified_test() ->
    Meta = #{publisher => ?FROM, publisher_verified => false},
    ?assertEqual({error, {not_attested, ?FROM}}, room_envelope:decode(envelope(#{}), Meta)).

rejects_when_never_signed_test() ->
    Meta = #{publisher => ?FROM, publisher_verified => not_signed},
    ?assertEqual({error, {not_attested, ?FROM}}, room_envelope:decode(envelope(#{}), Meta)).

rejects_when_publisher_missing_entirely_test() ->
    ?assertEqual({error, {not_attested, ?FROM}}, room_envelope:decode(envelope(#{}), #{})).

rejects_when_verified_but_publisher_does_not_match_from_test() ->
    Other = binary:copy(<<"c">>, 64),
    Meta = #{publisher => Other, publisher_verified => true},
    ?assertEqual({error, {publisher_mismatch, ?FROM}}, room_envelope:decode(envelope(#{}), Meta)).

rejects_a_from_that_is_not_64_hex_test() ->
    ?assertMatch({error, {invalid_from, _}},
                 room_envelope:decode(envelope(#{from => <<"not-hex">>}), verified_meta())).

rejects_a_missing_kind_test() ->
    ?assertMatch({error, {malformed_envelope, _}},
                 room_envelope:decode(maps:remove(kind, envelope(#{})), verified_meta())).

rejects_a_missing_room_topic_test() ->
    ?assertMatch({error, {malformed_envelope, _}},
                 room_envelope:decode(maps:remove(room_topic, envelope(#{})), verified_meta())).

rejects_a_non_map_payload_test() ->
    ?assertEqual({error, {not_a_map, <<"garbage">>}}, room_envelope:decode(<<"garbage">>, verified_meta())).

%% This service has no interest in ordinary conversation -- decode still
%% succeeds (the envelope is well-formed and attested), classification of
%% "is this a kind I act on" is `room_topic_listener''s job, not this
%% module's.
decodes_an_uninteresting_kind_without_error_test() ->
    {ok, Decoded} = room_envelope:decode(envelope(#{kind => <<"remark_made">>}), verified_meta()),
    ?assertEqual(<<"remark_made">>, maps:get(kind, Decoded)).
