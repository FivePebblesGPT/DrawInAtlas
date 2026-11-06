# T-048 — Collaboration acceptance: integrated proof and limitations

**Status: tested in-process engineering proof, not deployment acceptance.**
The authoritative session, identity handles, filtered publication and viewer
rendering remain isolated from production collaboration, network transport and
the real GM/player editor interface. T-039 publishing policy and independent
privacy review have not been approved. No wire protocol is exposed to peers.

## Reproducible integrated acceptance scenarios

Run against Godot 4.8 beta 2 from the project root:

```bash
godot --headless --path . --script res://tests/collaboration_acceptance_smoke.gd
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/collaboration_acceptance_visual.gd
```

The headless test constructs a campaign with two raster detail levels, an
unauthorized green raster layer at **each** detail level, a secret text object,
private token IDs/labels, private campaign/map names and tags, and a half-open
fog mask. Its acceptance sequence is deterministic:

1. Two trusted GM clients, a D0 player and a D1 spectator join separately.
   Serialize **each actual `host.snapshot_for(viewer)` dictionary** through
   `JSON.stringify`, parse it and decode the `png_base64` chunks as PNG images.
   Assert no private identifiers/text/metadata appear in either JSON string,
   and that revealed pixels are *only* their granted red or blue pixels while
   every unrevealed pixel is transparent. These are detached payload checks;
   simply hiding a private layer in the UI would fail them.
2. Forge viewer-to-GM edits, spoof a peer handle, and submit an unexpected
   private-data command field. Check error codes plus unchanged campaign,
   revision, and undo state. Real GM moves must advance the authoritative
   revision and produce equal independent GM token mirrors without adding
   token metadata to player or spectator payloads.
3. Disconnect one GM and the player. The remaining GM edits; the host revokes
   the offline player's grants; attempted text/token grants fail. Reconnect
   both using trusted previous handles. The GM must converge to current state,
   while the player must receive blank, current-policy artwork instead of a
   cached pre-revocation PNG. The retired handles cannot rejoin or read.
4. An accepted request retried with its existing ID must not apply twice.
   Explicit later authorization publishes only the requested raster again.
   The uninterrupted spectator must remain synchronized at its own D1 policy.
5. Mutate source raster pixels outside the host history. Snapshot publication
   must fail, and live player/spectator mirrors must clear their PNG bytes.

The **native visual test** creates its own read-only OS window. It receives
**only the JSON-round-tripped viewer dictionary**, decodes its PNG to a
`TextureRect`, and samples the OS framebuffer. It checks authorized red D0,
private/fogged darkness, revocation clearing, disconnect, blank reconnection,
explicit blue D1 reauthorization and session-close clearing. It writes a
reproducible image to `user://validation/collaboration-t048-visual.png`.
This window is a *test transport consumer*, not the production player UI.

CI executes both tests alongside existing focused T-045–T-047 suites and the
native projector/privacy framebuffer checks. A full suite run and native
Web/save validation should still accompany release review.

## Acceptance not yet established

- **Identity and network:** `join_as`, reconnect and grant changes are callable
  by an in-process trusted controller; no sockets, authenticated identities,
  secure reconnect credentials, replay epochs, rate limiting or bounded full
  transport messages exist. Do not give an untrusted party a host reference.
- **Publication:** T-039 object-level/token-level permissions, shared fog
  semantics, player ownership, production binding and consent remain unapproved.
  Current viewer snapshots authorize raster layers only, per floor/LOD.
- **Transport adversaries:** `snapshot_for` is serialized to JSON in tests, but
  no real packet capture or independent remote endpoint has been exercised.
  The test `TextureRect` is deliberately separate from production output.
- **Revocation limits:** cached bytes already copied by external receivers
  cannot be recalled. Production screens, caches and socket buffers require
  explicit invalidation, lifetime rules and adversarial end-to-end review.
- **Collaboration breadth:** host commands cover existing token movement only;
  full canvas edits, multi-map sessions, distributed undo and process-restart
  recovery are unresolved.
- **Acceptance evidence:** no external attacker review, real multi-machine
  testing, owner sign-off, or production deployment approval has occurred.

**Do not close T-048 or E-008 until these pending acceptance gates are met.**
