%%% @doc A real, throwaway barrel_docdb record for the suites that write
%%% to one -- no mesh, no `hecate_om:boot/1'. Same shape as hecate-agora's
%%% own `agora_test_db'.
-module(hecate_mods_test_db).

-export([setup/0, teardown/1]).

setup() ->
    {ok, _} = application:ensure_all_started(barrel_docdb),
    %% Wall-clock time in the name: `unique_integer/1' repeats across the
    %% fresh VM `rebar3 eunit' starts per invocation, and an integer-only
    %% name can reopen a crashed past run's leftover directory.
    DbName = <<"hecate_mods_test_",
               (integer_to_binary(erlang:system_time(microsecond)))/binary, "_",
               (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Dir = filename:join(filename:basedir(user_cache, "hecate-mods-test"),
                        binary_to_list(DbName)),
    ok = filelib:ensure_path(Dir),
    ok = hecate_om_read_model:ensure(DbName, Dir),
    persistent_term:put(hecate_om_read_model_db, DbName),
    {DbName, Dir}.

teardown({DbName, Dir}) ->
    persistent_term:erase(hecate_om_read_model_db),
    ok = barrel_docdb:delete_db(DbName),
    _ = file:del_dir_r(Dir),
    ok.
