%%% @doc Tests for `hecate_mods_reason:to_binary/1' -- pure.
-module(hecate_mods_reason_tests).

-include_lib("eunit/include/eunit.hrl").

renders_an_atom_test() ->
    ?assertEqual(<<"not_a_participant">>, hecate_mods_reason:to_binary(not_a_participant)).

passes_a_binary_through_unchanged_test() ->
    ?assertEqual(<<"already there">>, hecate_mods_reason:to_binary(<<"already there">>)).

renders_anything_else_via_format_test() ->
    ?assertEqual(<<"{oops,1}">>, hecate_mods_reason:to_binary({oops, 1})).
