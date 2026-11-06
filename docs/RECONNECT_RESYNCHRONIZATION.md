# T-047 — Reconnect and resynchronize permitted state

## Current reconnect threat model (T-075, 2026-11-02)

This is trusted **in-process handle replacement**, not an authenticated resume operation over real network sockets. It applies to the older `AtlasHostSession` token and raster-grant harness, **not** to the editor's `DrawingDocument` / `AtlasDrawingRegistry` artwork, linked `AtlasObjectLibrary` sources, Object Editor drafts or T-066 multi-file campaign generations ([composition](DRAWING_ATLAS_COMPOSITION.md), [objects](OBJECT_ASSETS_WORKFLOW.md), [storage](DRAWING_STORAGE_CONTRACT.md)). A test passing reconnect and JSON round-tripping does not prove revision convergence for the current Drawing source graph. There is no actual interrupted transport, credential expiry, remote-cache invalidation, cross-process journal, or duplicate delivery from a real network.

The production threat includes a stolen/forged resume token, stale player grants revealing private D0/D1 art, divergent linked assets, duplicate edits after missed acknowledgements and cached frames surviving revocation. Production recovery must bind identity, authenticated role and current policy to a fresh session epoch, reject stale messages, and deliver only a re-sanitized current snapshot. A previous receiver may retain already exported pixels regardless of in-process purge. [T-039](Tickets/T-039.md) policy approval, [T-043](Tickets/T-043.md) native privacy acceptance and [T-048](Tickets/T-048.md) independent collaboration acceptance are unresolved. Windows/Linux desktop is current; [T-044 Web](Archive/Web/T-044.md) is Archived.

**Status:** Isolated, trusted-controller **in-process proof**. This is not socket
reconnection, a secure resume credential, an approved network permission model,
or an integrated production multiplayer feature. T-045/T-046 and T-039 owner
acceptance remains outstanding. No persistent schema or token command changed.

## Disconnect, identity and revision handoff

The host retains each unique `peer_id` for the lifetime of its `session_id`,
including after disconnect. A trusted controller calls
`AtlasHostSession.disconnect_peer(existing_handle)` to detach the connection.
This immediately purges viewer artwork bytes from the disconnected handle.
Subsequent submissions, resync requests, and cached-reply retries from that
handle are refused. It cannot be reintroduced through `join`/`join_as` or
repurposed to change its role. A disconnected GM mirror retains only its old
non-authoritative, detached token snapshot; it cannot submit.

A trusted controller invokes `AtlasHostSession.reconnect(previous_handle)`.
Only the **exact registered previous handle** can be used to resume a peer.
An arbitrary ID or a handle from another session/host does not suffice. The
host issues a **new client handle** with the same host-owned role/grants and
original peer ID; the prior handle stays retired. The host rejects reconnect
if that peer is still active, the bound source has diverged, or the session
has closed. Offline peers count toward the existing 16-lifetime-peer limit.
This object-identity check is a local test seam, **not network authentication**:
production transports must replace it with authenticated, server-bound
connection ownership and independently secured resume credentials.

Reconnection does **not** increment the authoritative revision or mutate
history. The new handle receives a full detached snapshot at the *current*
revision (decimal string on the wire), instead of applying missed deltas.
The host constructs the snapshot using the **current** viewer grants and
T-039 sanitization at that moment. Revoked grants result in `{}` artwork;
newly permitted layers can be published only by an explicit host policy
change. GM receives only token records; player/spectator receive only
approved raster PNG data and never token/label/fog source resources. Offline
viewers are excluded from broadcasts. Old handles ignore late deltas and
snapshots and cannot restore a previously granted image.

## Uncertain request and replay policy

The host keeps its per-peer `(request_id, request, response)` ledger across
disconnect/reconnect, subject to the T-045 bound of 256 requests per lifetime
peer. The new handle inherits the old request sequence and last payload, so
fresh commands do not reuse earlier IDs. **No queued edit is automatically
replayed.** For a possibly lost acknowledgement, the GM explicitly calls
`retry_last()` after reconnect. An *identical* previous request returns the
cached original response (including the original revision) without applying
another history command; a reused ID with a different payload yields
`REQUEST_REUSE`. A new edit uses the new snapshot revision. An old connection
cannot submit while offline or after its replacement connects. Rejected
operations do not silently rebase. This proof does not persist ledgers across
host process restarts; a truly new session needs a unique `session_id` and
re-authentication. Persistent operation journaling, distributed undo,
transport timeouts, retries, and bounded network messages remain unapproved.

## Fail-closed behavior and coverage

The host's existing baseline and local-history guards apply before reconnect.
Out-of-band raster edits, history undo/redo, replaced layers, and shutdown
invalidate the session rather than replaying mismatched state. Viewer pixels
are cleared on disconnect and on detected divergence; other copies already
exported by a client or its display cannot be retracted by this API. Network
and browser caches must enforce their own revocation lifecycle.

Run:

```bash
godot --headless --path . --script res://tests/reconnect_resync_smoke.gd
```

The test covers missed GM edits, fresh snapshot/revision handoff, original-
request cached retries with zero duplicate history effects, forged/recycled
connection handles, inactive-peer ID budget, retired-handle late packets,
role retention, reconnect across changed viewer grants and detail levels,
blank-on-revocation, JSON-safe source filtering, source divergence, local
undo, and close/restart refusal.

**T-047 remains open:** network identity/authentication, secure resume tokens,
actual interrupted transport, cross-process request journaling, real pending
operation queues/rebase policy, and approved end-to-end player privacy behavior
still require implementation and independent acceptance. This is not a
production reconnect capability.
