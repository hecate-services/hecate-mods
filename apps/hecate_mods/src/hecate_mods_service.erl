%% @doc The hecate_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. hecate_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% IT ANNOUNCES NOTHING AND ASKS FOR NOTHING, on purpose. A service that does
%% nothing yet has no capability to offer and needs no authority from the realm.
%% Advertising a capability before it exists puts a lie on the mesh that another
%% service can find and call. Both lists grow when the thing they name exists,
%% and a generated test fails when they change, so growing them is a deliberate
%% act rather than a comment someone forgot.
-module(hecate_mods_service).

-behaviour(hecate_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ==========================================================================
%% AND A READ MODEL, alongside the store below
%% ==========================================================================
%%
%% `active_rooms_store' writes/reads a THIN operational index here directly
%% via `barrel_docdb', keyed by this same database name -- room_topic +
%% last_joined_at (+ status) only, just enough for the idle-timeout reaper
%% and boot-time re-subscription to find currently-moderated rooms without
%% enumerating every stream in the event store (see
%% `hecate-parksim/apps/project_parking_sessions/src/scavenge_aged_sessions.erl'
%% for the precedent this follows and its own reasoning against event-store
%% enumeration). Full room state (participants, etc.) is NOT duplicated here
%% -- that stays `room_aggregate''s job, rehydrated by replaying that room's
%% own event stream once a listener actually needs it.
%%
%% `read_model_ttl_sweep/0' arms barrel_docdb's native per-document TTL
%% sweeper as a DEFENSIVE BACKSTOP only (matching hecate-agora's own hot
%% record): `active_rooms_store' sets `expires_at' past each room's own
%% idle_timeout_hours on every write, purely as a bound on storage if
%% `active_rooms_reaper' ever falls behind. It cannot terminate a room
%% actor or emit `room_moderation_ended_v1' itself -- the reaper stays
%% the real, required mechanism regardless.
-export([read_model_id/0, read_model_ttl_sweep/0]).
%% ==========================================================================
%% AND TWO OPTIONAL ONES, WHICH TURN THE STORE ON
%% ==========================================================================
%%
%% Exporting `store_id/0' and `data_dir/0' TOGETHER makes `hecate_om:boot/1'
%% open a reckon-db store before this module's `start/1' fires.
%%
%% ⚠ THE reckon-db APPLICATIONS RUN EITHER WAY. `reckon_db', `reckon_evoq',
%% `reckon_gater', `evoq', `khepri' and `ra' start with `hecate_om' whether these
%% callbacks exist or not. What the two add is a STORE: a data directory, an open
%% handle, and something written. A sibling service claimed for months that they
%% suppressed the whole stack while six of its thirty-one running applications
%% quietly disproved it.
%%
%% ⚠⚠ AND `config/sys.config.src' MUST CARRY THE `evoq' BLOCK. hecate_om starts
%% a per-store evoq subscription that reads the global log, and that crashes on
%% `{not_configured, event_store_adapter}' without it. evoq starts as a
%% release-boot application before any service's `start/2' runs, so nothing can
%% inject it later. A sibling put two of three fleet nodes into a boot-crash
%% loop this exact way.
-export([store_id/0, data_dir/0]).

info() ->
    #{name => <<"hecate-mods">>,
      version => <<"0.1.0">>,
      description => <<"Moderator agent that keeps a mesh room alive when other participants leave">>}.

start(_Opts) -> hecate_mods_sup:start_link().

stop(_State) -> ok.

%% The read model's health: the reaper and boot-time resubscription both
%% depend on it to find currently-moderated rooms at all, so it failing to
%% open is a real failure, unlike a dark mesh.
health() ->
    probe(hecate_om:read_model()).

probe({ok, DbName}) -> opened(barrel_docdb:db_info(DbName));
probe({error, no_read_model}) -> {down, no_read_model}.

opened({ok, _Info}) -> ok;
opened({error, Reason}) -> {down, {read_model_unavailable, Reason}}.

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO. One mesh RPC: moderate a room.
%% Ungated for MVP -- any caller may ask any room be moderated (mirrors
%% mesh rooms' own trust model: joining/opening a room needs no
%% authorization today either). `invite_agent_to_room' (#2) is the one
%% piece of this design with real security teeth and is deliberately not
%% built here.
capabilities() ->
    [#{name => <<"hecate_mods.moderate_room">>, version => 1,
       handler => {moderate_room_responder, []}}].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% `agents.room.*' is a wildcard, not an enumeration, for the same reason
%% `hecate-mail' declares `mailboxes/*': which rooms exist is decided at
%% runtime by callers of `moderate_room', never known at boot.
identity_spec() ->
    #{scope => <<"hecate-mods">>,
      actions => [<<"moderate_room">>],
      resources => [<<"agents.room.*">>],
      ttl_days => 30}.

%% ==========================================================================
%% The store
%% ==========================================================================

%% @doc The reckon-db store this service owns.
%%
%% ⚠ IT IS NAMED IN TWO PLACES, here and in the `evoq' block of
%% `config/sys.config.src', and nothing makes them agree by itself. Disagreeing
%% opens one store and addresses another.
-spec store_id() -> atom().
store_id() -> hecate_mods_store.

%% @doc Where it lives on disk.
%%
%% ⚠ DEFAULTS TO A PATH INSIDE THE CONTAINER AND MUST NOT STAY THERE ON A NODE.
%% The fleet keeps application data on its `/bulk' drives and boots from a small
%% eMMC, so `deploy/docker-compose.yml' mounts a volume and sets this. The default
%% is what a laptop wants; a container without the mount loses its record on every
%% recreate, which is the same as not keeping one.
-spec data_dir() -> string().
data_dir() -> chosen(os:getenv("HECATE_DATA_DIR")).

chosen(false) -> "/tmp/hecate_mods";
chosen("") -> "/tmp/hecate_mods";
chosen(Path) -> Path.

%% @doc The barrel_docdb database `active_rooms_store' reads and writes --
%% see the header note on `-export([read_model_id/0])'.
-spec read_model_id() -> binary().
read_model_id() -> <<"hecate_mods">>.

%% @doc One hour between sweeper passes -- well under the shortest
%% realistic `idle_timeout_hours' margin, so the sweeper always gets many
%% chances to run before its backstop role would matter.
-spec read_model_ttl_sweep() -> #{interval_ms := pos_integer(), batch := pos_integer()}.
read_model_ttl_sweep() -> #{interval_ms => 3_600_000, batch => 1000}.
