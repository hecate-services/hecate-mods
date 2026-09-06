%%% @doc Aggregate for the room-moderation domain.
%%%
%%% One aggregate per moderated room. Stream: `room-{hex}', where `hex' is
%%% the 32-hex-char suffix a room topic (`agents.room.<hex>') already
%%% carries -- unlike `guide_mailbox_lifecycle''s citizen DID, a room
%%% topic's own suffix already satisfies reckon-db's stream-id contract
%%% (`^[a-z]{1,32}-[a-f0-9]{32}$'), so no hashing is needed here.
%%%
%%% Lifecycle: `moderate_room' (birth) -> `note_participant_joined' /
%%% `note_participant_left' / `invite_agent_to_room' (repeatable) ->
%%% `end_room_moderation' (death, terminal). `invite_agent_to_room'
%%% (macula-io/hecate-mods#2) additionally requires the requester to be
%%% a current participant, verified against this aggregate's own state,
%%% never a caller-supplied claim. Status/lifecycle GATING lives here,
%%% in `execute/2', not in the desk handlers -- same split as
%%% `guide_mailbox_lifecycle''s `mailbox_aggregate'.
%%% @end
-module(room_aggregate).
-behaviour(evoq_aggregate).

-include("room_status.hrl").

-export([init/1, execute/2, apply/2]).
-export([state_module/0, stream_id/1]).

-spec state_module() -> module().
state_module() -> room_state.

-spec stream_id(binary()) -> binary().
stream_id(RoomTopic) when is_binary(RoomTopic) ->
    <<"agents.room.", Hex/binary>> = RoomTopic,
    <<"room-", Hex/binary>>.

init(RoomTopic) ->
    {ok, room_state:new(RoomTopic)}.

execute(State, #{command_type := CmdType} = Payload) ->
    do_execute(CmdType, State, Payload);
execute(_State, _Unknown) ->
    {error, unknown_command}.

apply(State, Event) ->
    room_state:apply_event(State, Event).

%%--------------------------------------------------------------------
%% Command routing
%%--------------------------------------------------------------------

do_execute(moderate_room_v1, State, Payload) ->
    case room_state:is_formed(State) of
        true  -> {error, already_moderated};
        false -> maybe_moderate_room:handle_from_map(Payload)
    end;

do_execute(note_participant_joined_v1, State, Payload) ->
    guard_active(State, fun() -> maybe_note_participant_joined:handle_from_map(Payload) end);

do_execute(note_participant_left_v1, State, Payload) ->
    guard_active(State, fun() -> maybe_note_participant_left:handle_from_map(Payload) end);

do_execute(end_room_moderation_v1, State, Payload) ->
    guard_active(State, fun() -> maybe_end_room_moderation:handle_from_map(Payload) end);

do_execute(invite_agent_to_room_v1, State, Payload) ->
    guard_active(State, fun() -> guard_requester_is_participant(State, Payload) end);

do_execute(_Unknown, _State, _Payload) ->
    {error, unknown_command}.

%% @doc Formed, not yet ended. Every post-formation command needs this.
guard_active(State, Fun) ->
    case {room_state:is_formed(State), room_state:is_ended(State)} of
        {false, _}    -> {error, not_moderated};
        {true, true}  -> {error, moderation_ended};
        {true, false} -> Fun()
    end.

%% @doc macula-io/hecate-mods#2's own authorization requirement: "via
%% the actor's own state, not the moderator trusting caller-supplied
%% claims." The requester's signed ownership proof is verified FIRST --
%% only a VERIFIED node id is a trustworthy value to check against this
%% aggregate's participant set. Checking membership before verifying
%% identity would let anyone claim to BE a participant without proving
%% it, which is exactly the hole this desk exists to close.
guard_requester_is_participant(State, Payload) ->
    RequesterNodeId = maps:get(requester_node_id, Payload),
    Proof = maps:get(proof, Payload),
    Procedure = invite_agent_to_room_v1:procedure(),
    verified(room_ownership_proof:verify(RequesterNodeId, Proof, Procedure),
             State, RequesterNodeId, Payload).

verified(ok, State, RequesterNodeId, Payload) ->
    participant(room_state:is_participant(State, RequesterNodeId), Payload);
verified({error, _} = Err, _State, _RequesterNodeId, _Payload) ->
    Err.

participant(true, Payload) -> maybe_invite_agent_to_room:handle_from_map(Payload);
participant(false, _Payload) -> {error, not_a_participant}.
