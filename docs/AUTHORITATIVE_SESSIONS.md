# T-045 — Authoritative session and command prototype

**Status: engineering proof, not an approved multiplayer product contract.**
The source-of-truth remains a single GM campaign and its `AtlasEditHistory`.
`AtlasHostSession` binds one existing map, floor and `AtlasTokenLayer`, and only
that instance is allowed to turn client requests into `AtlasTokenEdit` history
commands. `AtlasSessionClient` stores detached primitive records; it never
receives editable `Resource` or `EditCommand` objects. The proof deliberately
covers **moving existing GM tokens**, not generic canvas edits, arbitrary
object creation, player audience grants or the rest of the campaign graph.

## Candidate session protocol

- **Transport:** synchronous, in-process calls carrying dictionary payloads;
  payloads round-trip through JSON. This is a test seam for a future transport,
  **not** a socket, authenticated channel, or remote multiplayer session.
- **Identity:** the trusted local controller creates a session ID and joins
  peers with unique IDs. IDs are 1–80 ASCII alphanumeric/underscore/hyphen
  characters. `AtlasHostSession.join()` establishes the client handle; a
  client-supplied peer string cannot change the bound handle's identity. This
  does **not** authenticate a peer over an untrusted network.
- **Authority:** only the host has the campaign/history. A client sends a
  seven-field request: `request_id`, `session_id`, `peer_id`, `operation`
  (`token_move`), `base_revision` (canonical unsigned decimal string),
  `token_id` and `position` ([finite x, finite y]). No arbitrary resource,
  command, script or `before` state is accepted. Values and exact field count
  are checked before constructing a host command.
- **Revisions:** start at zero; every successful command increments the host
  revision exactly once and broadcasts a detached, ordered snapshot to trusted
  GM mirrors. Other clients must submit against the latest revision. Retrying
  an identical `(peer_id, request_id)` receives its cached outcome, without
  applying the command twice; changing its payload returns `REQUEST_REUSE`.
  Request, response and snapshot revisions are decimal strings so JSON cannot
  round a revision via floating-point numbers. The bounded proof supports 16
  lifetime peers and 256 requests per peer.
- **Rejections:** responses include `ok`, a stable error code and the current
  host revision. Unknown operations, malformed data, nonexistent objects,
  no-ops, unauthorized target identity, outdated revisions, locked/invisible
  layers, edit-mask violations and history-command failures do not change the
  canonical campaign or history. A missed/out-of-order update requires an
  explicit snapshot resync before further editing.
- **Local history:** host commands use the existing guarded `AtlasTokenEdit`
  inside `AtlasEditHistory`; a successful edit is dirty/undoable in the local
  history. A direct local undo, replacement of the bound layer, or modification
  of its data/metadata **outside** this host invalidates the live session.
  The host also listens to local history changes (including undo/redo/save
  checkpoint changes) and invalidates itself unless it initiated the command.
  Once invalidated, the host refuses future requests/resync. The GM must close
  and start a fresh session at a new revision epoch. There is no distributed
  undo/redo policy yet; do not expose local undo while a session is active.
- **Shutdown:** `close()` revokes all client handles; their final detached
  snapshots remain locally readable but can no longer submit or resync.

## Trust limits and decisions still required

This is a **GM-only**, single-process prototype. In the original T-045 checkpoint all peers received the
bound **GM token layer**, potentially containing secrets. The T-046 extension
now adds explicit host-bound viewer roles that **never** receive that token
layer. These viewer roles remain an isolated proof, and the T-039 policy still
requires owner acceptance before production publication. This prototype must not be wired
into the unapproved player-output surface.

A production implementation additionally requires authenticated transport,
connection ownership, bounded message size and rate limits, reconnection,
replay handling across transport epochs, permission-aware snapshots, persistence
of revision/session semantics if desired, host/editor mutual exclusion and a
policy for local undo/rebase. The prototype's snapshot comparison detects
out-of-band changes **to the bound layer** (and replacement of map/floor/layer
instances); it is not a whole-campaign revision tracker. It is not a network
security or concurrency proof. All these choices require owner acceptance.

## Reproduction

Run `godot --headless --path . --script res://tests/authoritative_session_smoke.gd`.
The suite demonstrates two independent clients, JSON round-tripping, host
validation and history, idempotent retries, revision conflicts, edit masks,
mirrored token agreement, local undo divergence, resync and shutdown. No new
native-save fields are introduced, and no editor UI or live network is wired.

## T-046 incremental role-filtered replication proof

T-046 adds separate host-held `gm`, `player`, and `spectator` role assignments.
The T-045 GM token flow is unchanged; player/spectator mirrors receive only
explicit sanitized raster grants from the existing T-039 boundary and cannot
edit. Revocation, outbound image bytes, serialized fog and failure behavior are
specified and regression-tested in [ROLE_FILTERED_REPLICATION](ROLE_FILTERED_REPLICATION.md).
The original GM-only protocol above still applies to **GM peers only**;
viewer clients must not be given the GM join capability across a network.
