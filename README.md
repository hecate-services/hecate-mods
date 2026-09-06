# hecate-mods

**Moderator agent that keeps a mesh room alive when other participants leave**

## Status: moderate_room MVP

The service boots, joins the mesh, answers `/health` on 8462, and answers
one mesh capability: `hecate_mods.moderate_room`. It records room lifecycle
facts (formed, joined, left, ended) via an event-sourced `guide_room_lifecycle`
domain and ends moderation automatically after a configurable idle timeout.
See #1.

Both `capabilities()` and `identity_spec()`'s `actions`/`resources` grow
only when the thing they name exists, still — `invite_agent_to_room` (#2)
is not announced yet.

## Design

Mesh rooms (`agents.room.<hex>`) are ephemeral pub/sub: a room only stays
"watched" for as long as at least one participant is present, and nothing on
the mesh itself retains messages once every participant disconnects. A
room can be **ephemeral** (default, no change from today) or **moderated** —
a `moderate_room` command spins up a supervised `guide_room_lifecycle` actor
that stays in the room so it can outlive everyone who happened to be in it
at the time.

Settled, 2026-09-06 (brainstorm with Raf):

- **No content recording.** The moderator never transcribes conversation —
  that stays each participant's own prerogative. It records lifecycle facts
  only: formed, joined, left, ended. **Implemented, #1.**
- **Idle timeout, configurable, default 96h**, reset on a participant
  joining (not on leave, not on message activity — the moderator has no
  visibility into the latter by design). No join within the window ends
  moderation. **Implemented, #1** — `active_rooms_reaper` sweeps a thin
  read model (`active_rooms_store`, just `room_topic` + `last_joined_at`)
  every 15 minutes; the room aggregate itself has no per-room timer.
- **Invite is participant-gated.** Only a current room participant can ask
  the moderator to invite another agent in. #2 — the one piece of this
  design with real security teeth (mesh RPCs have no built-in auth), so
  it's the first thing in this repo going through feature-branch +
  Fable-reviewed PR instead of trunk-based. **Not built yet.**
- Voting/polling: raised, deliberately deferred. #3
- Bot avatar: no wire format change needed, derive from the existing
  petname client-side whenever a UI wants one. #4

### How a room gets watched

There is no "room" concept in `macula` itself — `agents.room.<hex>` is a
plain pubsub topic, and the join/leave envelope shape is macula-mcp's own
convention (`envelope.ts`), not something the Erlang mesh core knows
about. `room_topic_listener` (a `macula_subscriber`) decodes that
envelope directly and requires a **cryptographically verified publisher**
(the mesh delivery's own `Meta.publisher_verified`), not just a
self-claimed `from`, before treating a fact as a real join or leave —
stronger than macula-mcp's own TS-side check, which only compares labels.

Subscriptions are dynamic, one per currently-moderated room, reconciled
by `active_rooms_reaper` via `hecate_om_pubsub:ensure_subscriptions/1`
(both on its periodic tick and right after `moderate_room` succeeds) —
never a static `subscriptions/0` list, since which rooms exist is decided
at runtime.

## Running it

    rebar3 compile
    rebar3 eunit
    rebar3 lint

    scripts/health.sh                      # against a running node

Building the image needs a Rust toolchain, because macula ships a QUIC NIF and
the alpine build compiles it from source rather than fetching one linked against
a different libc.

    podman build -t hecate-mods -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `HECATE_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. No default: a service that guesses its realm announces itself where nobody can attribute it. |
| `MACULA_STATION_SEEDS` | required | Station to dial. No default: naming a realm costs nothing, dialling a production station from every dev clone does. |
| `HECATE_HEALTH_PORT` | `8462` | Health endpoint. Host networking makes a collision a silent bind failure, so check the host before changing.  |
| `HECATE_NODE_NAME` | `hecate_mods` | Erlang node name. |
| `HECATE_NODE_HOST` | `127.0.0.1` | Erlang node host. |
| `HECATE_COOKIE` | `hecate_mods` | Erlang cookie. |

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry **placement**: which
host, which station, which realm, which secret store. Keeping the two apart is
what stops a config table in a README and the real environment drifting.

## Deployment

CI builds on every push to `main` and pushes
`ghcr.io/hecate-services/hecate-mods:latest` plus the semver tag. Pull `:latest` under
watchtower and a merge is a deploy, while a rollback is pinning to a semver tag.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `HECATE_REALM` supplied from somewhere it is not committed.

## The service contract

Six callbacks in `hecate_mods_service`, all required, all resolved **by name** by
`hecate_om` at startup on a live node. The `-behaviour(hecate_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

### The store, and the read model alongside it

This service owns a `reckon-db` event store (`store_id/0` + `data_dir/0`,
`hecate_mods_store`) for `room_aggregate`, plus a `barrel_docdb` read model
(`read_model_id/0`) for `active_rooms_store` — a THIN index (`room_topic` +
`last_joined_at` only) so `active_rooms_reaper` can find idle rooms and
resubscribe after a restart without enumerating the whole event store (see
`hecate-parksim`'s `scavenge_aged_sessions` for the precedent, and
`reckon-db`'s own `dcb.md` "When NOT to use DCB" for why its indexed reads
aren't a substitute here). It is NOT a copy of aggregate state — full room
state stays `room_aggregate`'s job, rehydrated from that room's own event
stream.

⚠ **The store is wired in three places, and the missing one crash-loops the
node.** `store_id/0` + `data_dir/0` on `hecate_mods_service`; the `evoq`
adapter block in `config/sys.config.src`, without which boot raises
`{not_configured, event_store_adapter}` before any service code runs; and
the volume mount in `deploy/docker-compose.yml`. A sibling service put two
of three fleet nodes into a boot loop by doing the first and not the
second — this repo's own scaffold had no store at all until this MVP
added one by hand, cross-checking `hecate-om`'s own `store=1` template
output for each of the three pieces rather than guessing.

## Licence

Apache-2.0.
