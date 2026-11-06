# T-046 — Host roles and filtered replication proof

**Status:** isolated, trusted in-process engineering checkpoint; **not** an approved
player publication policy, authenticated multiplayer channel, or production UI.
This extends [AUTHORITATIVE_SESSIONS](AUTHORITATIVE_SESSIONS.md) without changing
any native `.scn` persistence fields.

## Trust boundary and roles

The trusted **local session controller** calls `AtlasHostSession.join()` for a
GM editor or `join_as(peer_id, role, grants, detail_level)` to bind a peer to
`gm`, `player`, or `spectator`. Roles and grants are stored **on the host**,
never accepted from a client's command packet. Client handles do contain an
in-process reference to the host; this is **not** an authentication system.
An untrusted network client must never be allowed to call `join`, `join_as`,
`set_viewer_grants`, or obtain a raw host reference. Real transport/identity
binding remains in T-045/T-048.

- **GM:** existing T-045 token-move requests, guarded canonical history, token
  snapshots, revision and idempotent request tracking. No publication data
  is sent to that channel.
- **Player / spectator:** read-only, identical denial policy in this proof.
  No canonical token IDs, labels, strokes, objects, fog operations, map titles,
  links, placements, previews, or editor cache entries are sent. No user-
  supplied command can mutate the canonical host history, even if it forges a
  GM peer ID. Both roles can be *explicitly* granted raster layers for **one
  bound floor and one detail level** by the trusted controller; otherwise the
  artwork dictionary is empty.
- **Future roles:** intermediate co-GM, token ownership, network authorization,
  semantic-object grants, fog overlay operations, and arbitrary canvas edit
  commands require a separately accepted policy. An Objects-layer grant is
  denied here because labels are not safely separable. Token-layer grants are
  denied regardless of normal editor visibility.

## Serialization and filtering

`AtlasPlayerProjection.build_artwork_view` is the only input to viewer
publication. It removes non-granted layers, source IDs/names, private metadata,
other floors/LODs and **unrevealed raster pixels before serialization**. The
host additionally restricts accepted grants to raster layers. Each sanitized
chunk travels as detached `png_base64` inside the primitive `artwork`
dictionary, alongside the sanitized layer geometry, coordinates and content
address. Publication is limited to **8 MiB of compressed PNG chunk bytes**
per snapshot and **16,777,216 decoded raster pixels** before cloning.
Malformed or oversized publication returns no artwork,
never source resources or a GM-image fallback. Every network transport must
also validate and bound its actual encoded message size.

Messages carry a canonical decimal-string host `revision`. GM token edits and
host-owned viewer permission changes increment it and broadcast **separately
filtered snapshots per recipient**. Retries of accepted GM request IDs still
return their cached answer without reapplying edits. `set_viewer_grants` checks
new grants against the current source and can revoke publication by replacing
them with `[]`; live player/spectator mirrors immediately replace the old
bytes. An invalid/out-of-order update clears viewer imagery and requires an
explicit resync. Shutdown and detected out-of-band map/floor/pixel/history
changes invalidate the host and clear live viewer payloads. The host compares
the bound document's full canonical dictionary, including raster image hashes,
not just tokens. **No code can retract bytes already copied/exported by a
previous receiver**: real output screens/caches/transport must enforce their
own revocation and secure lifetime rules.

## Coverage and remaining acceptance

Run `godot --headless --path . --script res://tests/filtered_replication_smoke.gd`.
The suite proves: distinct GM/player/spectator payloads, forbidden viewer
edits and forged GM identity, per-peer grants, denial of semantic/token layers,
LOD scoping, independent PNG bytes, fog masking in the serialized image,
JSON round-tripping without source secrets, role-aware revision broadcasts,
revocation/idempotence, invalid updates/resync, local pixel divergence,
undo invalidation, and session close.

Still required for T-046 acceptance: owner-approved publication granularity
(T-039), object/token ownership and permissions, safe semantic-object/fog
replication, authenticated server-side identity binding and real reconnect epochs
(T-047 only provides trusted in-process reconnect), network message budgets, rekeying and replay limits, real transport,
and production end-to-end privacy review. Do **not** mark T-046 complete in
`docs/Index.md` based on this proof.
