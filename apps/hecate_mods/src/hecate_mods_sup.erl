%% @doc Supervises this service's own processes.
%%
%% Two children: `room_lifecycle_to_active_rooms' (the evoq_projection
%% turning room lifecycle events into `active_rooms_store', matching
%% `project_mailboxes_sup''s own shape) and `active_rooms_reaper' (the
%% periodic idle-timeout sweep + mesh-subscription reconciler, matching
%% `hecate-parksim''s `scavenge_aged_sessions'). Order matters: the
%% projection must be running before the reaper's very first tick reads
%% `active_rooms_store', which `one_for_one' with this list order
%% guarantees at startup (each child starts before the next is added).
-module(hecate_mods_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        worker(room_lifecycle_to_active_rooms, evoq_projection, start_link,
              [room_lifecycle_to_active_rooms, #{}, #{}]),
        worker(active_rooms_reaper, active_rooms_reaper, start_link, [])
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.

worker(Id, Module, Function, Args) ->
    #{
        id       => Id,
        start    => {Module, Function, Args},
        restart  => permanent,
        shutdown => 5000,
        type     => worker,
        modules  => [Module]
    }.
