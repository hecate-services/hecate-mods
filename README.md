# hecate-mods

**Moderator agent that keeps a mesh room alive when other participants leave**

## Status: scaffold

The service boots, joins the mesh and answers `/health` on 8462. It
does nothing else yet.

It announces no capability and asks the realm for no authority, because it can do
nothing yet. Both lists grow when the thing they name exists. Advertising a
capability before it exists puts a lie on the mesh where another service can find
it and call it.

## Design

Mesh rooms (`agents.room.<hex>`) are ephemeral pub/sub: a room only stays
"watched" for as long as at least one participant is present, and nothing on
the mesh itself retains messages once every participant disconnects. A
room can be **ephemeral** (default, no change from today) or **moderated** —
a `moderate_room` command spins up a supervised `guide_room_lifecycle` actor
that stays in the room so it can outlive everyone who happened to be in it
at the time.

Settled, 2026-09-06 (brainstorm with Raf), tracked as issues rather than
implemented here yet:

- **No content recording.** The moderator never transcribes conversation —
  that stays each participant's own prerogative. It records lifecycle facts
  only: formed, joined, left, ended. #1
- **Idle timeout, configurable, default 96h**, reset on a participant
  joining (not on leave, not on message activity — the moderator has no
  visibility into the latter by design). No join within the window ends
  moderation. #1
- **Invite is participant-gated.** Only a current room participant can ask
  the moderator to invite another agent in. #2 — the one piece of this
  design with real security teeth (mesh RPCs have no built-in auth), so
  it's the first thing in this repo going through feature-branch +
  Fable-reviewed PR instead of trunk-based.
- Voting/polling: raised, deliberately deferred. #3
- Bot avatar: no wire format change needed, derive from the existing
  petname client-side whenever a UI wants one. #4

None of this is implemented yet — the service still does nothing but
join the mesh and answer `/health`, honestly, per the scaffold's own rule
about not advertising a capability before it exists.

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

### Adding a store later

This service has no `reckon-db` store, which is the right answer for most. The
reckon-db applications run either way; what a store adds is a data directory, an
open handle, and something written.

The cheapest way to get one is to scaffold again with `store=1`, which generates
the callbacks, the config and the guards together.

⚠ **By hand it is three things and not one, and the missing third crash-loops the
node.** Export `store_id/0` and `data_dir/0`; add the `evoq` adapter block to
`config/sys.config.src`, without which boot raises
`{not_configured, event_store_adapter}` before any service code runs; and mount a
volume in the compose file. A sibling service put two of three fleet nodes into a
boot loop by doing the first and not the second.

## Licence

Apache-2.0.
