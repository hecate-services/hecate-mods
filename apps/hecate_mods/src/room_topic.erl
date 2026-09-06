%%% @doc The one room-topic format check every command that takes a
%%% `room_topic' needs, shared so it can never drift between them
%%% (`moderate_room_v1' and `invite_agent_to_room_v1' each used to carry
%%% their own copy, only one of which actually ran it).
%%%
%%% Called from `new/1', not just `validate/1': `room_aggregate:
%%% stream_id/1' pattern-matches the exact `"agents.room."' prefix and
%%% CRASHES (badmatch) on anything else, and `dispatch/1' computes the
%%% stream id before the aggregate -- and therefore before any handler's
%%% own `validate/1' -- ever runs. A malformed `room_topic' must be
%%% refused at construction time, not merely rejected later once
%%% something downstream has already tried to route on it (found by
%%% Fable review, hecate-mods#5).
-module(room_topic).

-export([valid/1]).

%% Matches macula-mcp's own room-topic contract (envelope.ts:
%% ROOM_TOPIC_PREFIX + 32 lowercase hex chars) -- the one wire format
%% every mesh room topic actually has.
-define(ROOM_TOPIC_RE, "^agents\\.room\\.[0-9a-f]{32}$").

-spec valid(term()) -> boolean().
valid(Topic) when is_binary(Topic) ->
    case re:run(Topic, ?ROOM_TOPIC_RE) of
        {match, _} -> true;
        nomatch -> false
    end;
valid(_NotABinary) -> false.
