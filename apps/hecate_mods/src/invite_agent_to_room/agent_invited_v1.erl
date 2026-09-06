%%% @doc Event `agent_invited_v1'. Records the INTENT (a verified
%%% participant asked for a target to be invited), not the ring's
%%% outcome -- the actual ring is network I/O performed by
%%% `invite_agent_to_room_responder' after this event is durably
%%% recorded, same split as `moderate_room_responder''s post-dispatch
%%% `active_rooms_reaper:reconcile_now/0' side effect.
-module(agent_invited_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_room_topic/1, get_requester_node_id/1, get_target_node_id/1,
         get_purpose/1, get_invited_at/1]).

-record(agent_invited_v1, {
    room_topic :: binary(),
    requester_node_id :: binary(),
    target_node_id :: binary(),
    purpose :: binary(),
    invited_at :: integer()
}).

-opaque t() :: #agent_invited_v1{}.
-export_type([t/0]).

event_type() -> <<"agent_invited_v1">>.

-spec new(map()) -> t().
new(#{room_topic := Topic, requester_node_id := Requester, target_node_id := Target,
      purpose := Purpose} = Params) ->
    #agent_invited_v1{
        room_topic = Topic,
        requester_node_id = Requester,
        target_node_id = Target,
        purpose = Purpose,
        invited_at = maps:get(invited_at, Params, erlang:system_time(millisecond))
    }.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{room_topic := Topic, requester_node_id := Requester, target_node_id := Target,
           purpose := Purpose, invited_at := At})
  when is_binary(Topic), is_binary(Requester), is_binary(Target), is_binary(Purpose), is_integer(At) ->
    {ok, #agent_invited_v1{room_topic = Topic, requester_node_id = Requester,
                           target_node_id = Target, purpose = Purpose, invited_at = At}};
from_map(_) ->
    {error, invalid_agent_invited_event}.

-spec to_map(t()) -> map().
to_map(#agent_invited_v1{room_topic = Topic, requester_node_id = Requester,
                        target_node_id = Target, purpose = Purpose, invited_at = At}) ->
    #{event_type => <<"agent_invited_v1">>, room_topic => Topic,
      requester_node_id => Requester, target_node_id => Target,
      purpose => Purpose, invited_at => At}.

-spec get_room_topic(t()) -> binary().
get_room_topic(#agent_invited_v1{room_topic = V}) -> V.

-spec get_requester_node_id(t()) -> binary().
get_requester_node_id(#agent_invited_v1{requester_node_id = V}) -> V.

-spec get_target_node_id(t()) -> binary().
get_target_node_id(#agent_invited_v1{target_node_id = V}) -> V.

-spec get_purpose(t()) -> binary().
get_purpose(#agent_invited_v1{purpose = V}) -> V.

-spec get_invited_at(t()) -> integer().
get_invited_at(#agent_invited_v1{invited_at = V}) -> V.
