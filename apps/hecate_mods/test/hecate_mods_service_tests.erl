%% @doc The service contract, asserted locally.
%%
%% hecate_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(hecate_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes hecate_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots hecate_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(hecate_mods_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, hecate_mods).
-define(SERVICE, hecate_mods_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If hecate_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"hecate-mods">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

%% Health is the read model's health. Without one open, the reaper and
%% boot-time resubscription both have nothing to read, so that is `down',
%% not a shrug; with one open it is green. Both halves are asserted so a
%% future "always ok" regression fails here.
health_is_down_without_the_read_model_and_green_with_it_test() ->
    persistent_term:erase(hecate_om_read_model_db),
    ?assertEqual({down, no_read_model}, ?SERVICE:health()),
    Db = hecate_mods_test_db:setup(),
    ?assertEqual(ok, ?SERVICE:health()),
    ok = hecate_mods_test_db:teardown(Db).

%% Two capabilities now: moderate a room (#1) and invite an agent into
%% one (#2). The assertion still exists so that adding a THIRD one
%% breaks this test and makes someone write down what the service can
%% now additionally do.
announces_moderate_room_and_invite_capabilities_test() ->
    ?assertMatch([#{name := <<"hecate_mods.moderate_room">>, version := 1,
                    handler := {moderate_room_responder, []}},
                  #{name := <<"hecate_mods.invite_agent_to_room">>, version := 1,
                    handler := {invite_agent_to_room_responder, []}}],
                 ?SERVICE:capabilities()).

identity_spec_has_the_shape_hecate_om_expects_test() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_list(Actions)),
    ?assert(is_list(Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%% A resource this service is not authorised for is a publish the realm would
%% refuse once UCAN delegation lands. `agents.room.*' is a wildcard, not an
%% enumeration, because which rooms exist is decided at runtime by callers
%% of `moderate_room', never known at boot (same reasoning as hecate-mail's
%% `mailboxes/*'). The outgoing ring call is deliberately NOT in resources
%% here -- see `identity_spec/0''s own comment on why that's an open
%% question, not an oversight.
authority_matches_what_is_announced_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([<<"moderate_room">>, <<"invite_agent_to_room">>], Actions),
    ?assertEqual([<<"agents.room.*">>], Resources).

%% The supervisor's DECLARED children, not an actually-started tree:
%% `room_lifecycle_to_active_rooms' (the projection) and
%% `active_rooms_reaper' both genuinely depend on `hecate_om' already
%% running (the event store, the read model, `hecate_om_pubsub''s own
%% subscription gen_server) -- real platform services this test does not
%% boot, unlike the empty scaffold this test originally covered. Calling
%% `init/1' directly exercises the wiring (right module, right child ids,
%% right start order) without starting a process tree that would crash on
%% a missing live mesh, which is exactly the boundary a live/integration
%% check (not a unit test) should cover instead.
supervisor_declares_the_projection_and_the_reaper_test() ->
    {ok, {_SupFlags, Children}} = hecate_mods_sup:init([]),
    Ids = [Id || #{id := Id} <- Children],
    ?assertEqual([room_lifecycle_to_active_rooms, active_rooms_reaper], Ids).

%%==============================================================================
%% The config the store cannot boot without
%%==============================================================================

%% ⚠ A SIBLING SERVICE'S FLEET CRASH-LOOPED ON TWO OF THREE NODES FOR WANT OF THE
%% `evoq' BLOCK. Same guard as `hecate_mail_service_tests', other repo.
the_evoq_adapter_is_configured_wherever_a_store_is_opened_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assert(erlang:function_exported(?SERVICE, store_id, 0)),
    lists:foreach(
      fun(Needed) ->
              ?assertNotEqual(nomatch, binary:match(Text, Needed),
                              {missing_from_sys_config, Needed})
      end,
      [<<"{evoq,">>, <<"event_store_adapter">>, <<"subscription_adapter">>,
       <<"reckon_evoq_adapter">>]).

the_store_id_agrees_between_erlang_and_config_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    Declared = atom_to_binary(?SERVICE:store_id(), utf8),
    ?assertNotEqual(nomatch, binary:match(Text, Declared),
                    {store_id_not_in_sys_config, Declared}).

the_data_directory_is_answerable_test() ->
    ?assert(erlang:function_exported(?SERVICE, data_dir, 0)),
    ?assert(is_list(?SERVICE:data_dir())),
    ?assertNotEqual("", ?SERVICE:data_dir()).

%% The read model's database name is what `active_rooms_store' addresses
%% via `hecate_om:read_model()' -- nothing checks the two agree except a
%% human reading both files, same class of guard as the store id above.
the_read_model_id_is_answerable_test() ->
    ?assert(erlang:function_exported(?SERVICE, read_model_id, 0)),
    ?assert(is_binary(?SERVICE:read_model_id())).

%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Image = pinned("Containerfile", "FROM docker.io/erlang:([0-9]+)"),
    Ci = pinned(".github/workflows/lint.yml", "image: erlang:([0-9]+)"),
    Running = list_to_binary(erlang:system_info(otp_release)),
    %% Sorted and deduplicated, so a failure prints all three rather than the
    %% first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, Ci, Running])).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [{capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
