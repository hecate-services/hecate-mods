%%% @doc Projection: room_formed_v1 / participant_joined_v1 /
%%% room_moderation_ended_v1 -> the `active_rooms_store' barrel_docdb
%%% read model.
%%%
%%% The `evoq_read_model' handle is a checkpoint passthrough only -- real
%%% data lives in `active_rooms_store' (barrel_docdb), not in the read
%%% model itself, matching `project_mailboxes''s own
%%% `letter_lifecycle_to_mailboxes' and its own cited precedent
%%% (hecate-mpong-bot).
%%%
%%% `participant_left_v1' is deliberately NOT in `interested_in/0': it
%%% does not change anything this index tracks (the idle clock resets on
%%% a join, never a leave -- macula-io/hecate-mods#1), so there is
%%% nothing for this projection to do with it.
-module(room_lifecycle_to_active_rooms).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"room_formed_v1">>, <<"participant_joined_v1">>, <<"room_moderation_ended_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets,
                                   #{name => active_rooms_projection}),
    {ok, #{}, RM}.

%% `Event' here is what evoq_store_subscription:evoq_event_to_routable/1
%% builds: #{event_type, event_id, stream_id, version, data, tags,
%% timestamp, epoch_us} -- the event's own fields are nested under
%% `data'. `field/2' is atom-or-binary tolerant since a round trip
%% through the store is not guaranteed to preserve atom keys.
project(#{event_type := <<"room_formed_v1">>, data := Data}, _Meta, State, RM) ->
    ok = active_rooms_store:record_formed(
        field(room_topic, Data), field(idle_timeout_hours, Data), field(formed_at, Data)),
    {ok, State, RM};

project(#{event_type := <<"participant_joined_v1">>, data := Data}, _Meta, State, RM) ->
    ok = active_rooms_store:touch_joined(field(room_topic, Data), field(joined_at, Data)),
    {ok, State, RM};

project(#{event_type := <<"room_moderation_ended_v1">>, data := Data}, _Meta, State, RM) ->
    ok = active_rooms_store:remove(field(room_topic, Data)),
    {ok, State, RM};

project(_Event, _Meta, State, RM) ->
    {skip, State, RM}.

field(Key, Map) when is_atom(Key) ->
    BinKey = atom_to_binary(Key, utf8),
    maps:get(Key, Map, maps:get(BinKey, Map, undefined)).
