%%% @doc LISTENER for one moderated room's mesh topic, wired dynamically by
%%% `active_rooms_reaper' into a supervised `macula_subscriber' via
%%% `hecate_om_pubsub:ensure_subscriptions/1' (one per currently-moderated
%%% room, not a static `subscriptions/0' declaration -- which rooms exist
%%% is decided at runtime by `moderate_room', see
%%% `hecate_mods_service:identity_spec/0'). Its only job is to decode the
%%% fact and, for an attested join or leave, dispatch the matching
%%% command; it decides nothing about the aggregate's own guards.
%%%
%%% The delivery `Topic' argument (not the payload's own self-claimed
%%% `room_topic' field) is what this listener dispatches commands
%%% against: it is the topic macula's subscription actually delivered on,
%%% unspoofable by the payload, whereas `room_topic' inside the envelope
%%% is merely a self-reported field this module still decodes as part of
%%% validating the envelope is well-formed at all.
%%%
%%% A malformed or unattested fact is logged at info, not warning: unlike
%%% `hecate-agora''s single-shape agora topic, an ordinary mesh room
%%% legitimately carries many envelope kinds this service has no interest
%%% in (`remark_made', `question_asked', ...) and messages from peers this
%%% service will never be able to attest if their frame wasn't signed --
%%% neither is a producer contract violation.
-module(room_topic_listener).

-behaviour(macula_subscriber).

-export([init/1, handle_event/4]).

init(#{room_topic := RoomTopic} = Args) when is_binary(RoomTopic) ->
    {ok, Args}.

handle_event(Topic, Payload, Meta, State) ->
    heard(Topic, room_envelope:decode(Payload, Meta)),
    {noreply, State}.

heard(Topic, {ok, #{kind := <<"participant_joined">>, from := From}}) ->
    outcome(maybe_note_participant_joined:dispatch(command(note_participant_joined_v1, Topic, From)));
heard(Topic, {ok, #{kind := <<"participant_left">>, from := From}}) ->
    outcome(maybe_note_participant_left:dispatch(command(note_participant_left_v1, Topic, From)));
heard(_Topic, {ok, _Uninteresting}) ->
    ok;
heard(Topic, {error, Reason}) ->
    logger:info("[hecate_mods] ignored a fact on ~s: ~p", [Topic, Reason]).

command(note_participant_joined_v1, Topic, From) ->
    {ok, Cmd} = note_participant_joined_v1:new(#{room_topic => Topic, node_id => From}),
    Cmd;
command(note_participant_left_v1, Topic, From) ->
    {ok, Cmd} = note_participant_left_v1:new(#{room_topic => Topic, node_id => From}),
    Cmd.

outcome({ok, _Version, _Events}) -> ok;
outcome({error, Reason}) ->
    logger:info("[hecate_mods] dispatch declined: ~p", [Reason]).
