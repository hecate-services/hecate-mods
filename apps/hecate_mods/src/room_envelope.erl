%%% @doc Decodes a mesh room envelope off the wire (macula-mcp's own
%%% contract, `envelope.ts' -- there is no Erlang-side "room" concept in
%%% `macula' itself: a room topic is a plain pubsub topic, and the
%%% envelope shape is a convention layered on top by macula-mcp's TS
%%% client, not something this platform's Erlang core knows about).
%%%
%%% Fields decoded: `kind', `from', `room_topic' -- the only three this
%%% service acts on. `text' is deliberately never read: this service
%%% records lifecycle facts only, never conversation content
%%% (macula-io/hecate-mods#1).
%%%
%%% Attestation here is STRONGER than macula-mcp's own TS-side check
%%% (`isAttested', envelope.ts: publisher label equals the claimed
%%% `from'). The Erlang delivery `Meta' additionally carries
%%% `publisher_verified' -- whether the publisher cryptographically
%%% signed the frame (see `agora_post_fact''s own doc for the same
%%% `Meta' shape) -- and this module requires that signature, not just a
%%% label match, before treating an envelope as a real join/leave: a
%%% self-claimed `from' with no verified signature is exactly the kind
%%% of unattested claim this workspace's "no anonymity, only
%%% sovereignty" stance exists to reject.
%%%
%%% Pure, so every wire shape is unit-testable without a mesh.
-module(room_envelope).

-export([decode/2]).

-define(HEX64, "^[0-9a-fA-F]{64}$").

-spec decode(term(), map()) -> {ok, #{kind := binary(), from := binary(), room_topic := binary()}}
                              | {error, term()}.
decode(Payload, Meta) when is_map(Payload), is_map(Meta) ->
    shaped(text(hecate_om_wire:field(kind, Payload)),
           text(hecate_om_wire:field(from, Payload)),
           text(hecate_om_wire:field(room_topic, Payload)),
           Meta);
decode(Payload, _Meta) ->
    {error, {not_a_map, Payload}}.

shaped(Kind, From, RoomTopic, Meta)
  when is_binary(Kind), Kind =/= <<>>,
       is_binary(From), is_binary(RoomTopic) ->
    case re:run(From, ?HEX64) of
        {match, _} -> attested(Kind, From, RoomTopic, Meta);
        nomatch    -> {error, {invalid_from, From}}
    end;
shaped(Kind, From, RoomTopic, _Meta) ->
    {error, {malformed_envelope, #{kind => Kind, from_present => From =/= undefined,
                                    room_topic_present => RoomTopic =/= undefined}}}.

attested(Kind, From, RoomTopic, Meta) ->
    case {publisher_hex(maps:get(publisher, Meta, undefined)),
          maps:get(publisher_verified, Meta, not_signed)} of
        {Publisher, true} when is_binary(Publisher) ->
            same(string:lowercase(Publisher) =:= string:lowercase(From), Kind, From, RoomTopic);
        _NotVerifiedOrNoPublisher ->
            {error, {not_attested, From}}
    end.

same(true, Kind, From, RoomTopic) ->
    {ok, #{kind => Kind, from => From, room_topic => RoomTopic}};
same(false, _Kind, From, _RoomTopic) ->
    {error, {publisher_mismatch, From}}.

%% The publisher is a raw Ed25519 public key on the wire in some delivery
%% paths, already lowercase hex in others -- same two shapes
%% `agora_post_fact:publisher/1' normalizes, kept consistent with it.
publisher_hex(Key) when is_binary(Key), byte_size(Key) =:= 32 ->
    binary:encode_hex(Key, lowercase);
publisher_hex(Hex) when is_binary(Hex), byte_size(Hex) =:= 64 ->
    string:lowercase(Hex);
publisher_hex(_Absent) ->
    undefined.

text(undefined) -> undefined;
text(Bin) when is_binary(Bin) -> Bin;
text(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
text(_Other) -> undefined.
