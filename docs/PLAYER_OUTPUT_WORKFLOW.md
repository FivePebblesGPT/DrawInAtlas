# T-040 — Native player output and physical calibration (isolated proof)

**Status: partial engineering proof, NOT an approved live projector.** T-039's publication policy, T-043's end-to-end privacy acceptance, and real-table usability review are still open. Nothing here authorizes displaying the live GM board. This native player-output session is **not connected to editor controls**, campaign saving, or network replication.

## Native proof path

`AtlasPlayerOutputSession` opens a separate native Godot `Window` and holds an independent `AtlasMapCapture` plus a texture-only `TextureRect`. It **never** adds the GM canvas or canonical campaign to the window. The window starts blank. `publish(source_document, floor_id, detail_level, granted_layer_ids)` first clears any previous texture, uses `AtlasPlayerProjection.build_capture_input` to make a fully detached, single-board campaign, and only then renders that detached board into its private capture viewport. Grant IDs must come from a trusted GM publication policy; there is no production grant authoring UI. A missing, stale, duplicate, or invalid grant returns a blank window. No layer becomes public merely because it is visible in the editor.

The output size is render **pixels**; `open_native` rejects more than 3840×2160 pixels to avoid massive allocations. A native resize invalidates the image and requires an explicit matching camera frame and new authorized render. The frame must share the output aspect ratio; mismatches fail closed, never stretch hidden material into view. T-013 framing remains **session-only** and edits no artwork. `update_frame(frame)` copies the approved frame's center and board width when following. Freeze pins the last authorized camera and pixels until explicitly resumed or invalidated; invalidation clears the texture and cancels pending captures regardless of freeze. The native session also checks the full source publication fingerprint (layer state and pixel hashes, floor identity, LOD, grid, grant IDs, and ordered fog operations) at the end of asynchronous capture; any intervening change rejects that image. This does not watch idle/frozen images. Editing fog or revoking permissions **must** call `invalidate()` immediately; future production wiring must track policy/content revisions automatically and reject every stale publication attempt. Resuming follow updates the camera only; it requires another sanitized `publish` to display pixels.

The native test uses `root.gui_embed_subwindows = false` before opening the window; otherwise Godot may embed the subwindow in the GM window. Whether native windows can be created depends on the platform/window manager. This proof is tested using Linux X11 under Xvfb/Mesa and is **not** evidence of Windows, macOS, Wayland, multiple real monitors, hardware brightness, or Web behavior. There is no fallback in this ticket; T-044 owns Web output.

## Physical table calibration remains independent

`AtlasProjectorCalibration` stores only user-measured physical display width (millimeters) and desired tabletop cell size (millimeters). It never guesses a monitor DPI or writes pixels into the board. The measured output width is not the same as the frame's document width or the native window's pixel width:

- **Frame/camera:** center and board-width in document units; moving or resizing changes the *visible area* but not artwork geometry.
- **Output render resolution:** physical window's logical/pixel size; resizing invalidates capture and may change aspect.
- **Physical calibration:** actual measured screen/projector illuminated width in millimeters and desired physical cell width; independent from the frame and output pixels.

Given a document grid cell width `g` in board units, measured physical width `S` mm, desired cell width `C` mm, and actual frame width `W` board units:

- Suggested frame width `W_target = S × g / C` (does not automatically resize frame).
- Current physical cell width `C_actual = S × g / W`.
- Nominal pixels per mm `= output_width_px / S` (logical GPU pixels can differ from physical device pixels under OS scaling).

Calibrate by measuring the **illuminated** display width with a physical ruler, entering desired miniature-base/cell size, then deliberately setting the GM frame width. Real-projector overscan, OS scaling, and keystone correction require physical remeasurement; these calculations alone cannot certify accurate table calibration. GRIDLESS maps have no grid cell width to calibrate and must remain uncalibrated. No persisted calibration policy or owner-approved UI exists yet.

## Tests and remaining gates

- `tests/player_output_session_smoke.gd` validates the formulas, invalid values, frame/calibration independence, and headless output denial.
- `tests/player_output_session_visual.gd` opens an independent native window under X11, confirms a granted red raster appears while a secret green raster does not enter the player texture or displayed framebuffer, and checks freeze, follow, frame aspect, invalid grants, revocation during an in-flight GPU capture, native resize, and GM source immutability.
- The existing `player_projection_contract_smoke` and `player_projection_visual` suites remain the T-039 lower-level authorization boundary checks.

**Remaining for T-040 acceptance:** approve T-039's real grant and privacy model; wire a trusted editor publishing controller; define automatic invalidation on every policy/art/content change; implement owner-facing output monitor selection/fullscreen controls, projector display calibration UI, and output error recovery; test real multiple monitors/OS scaling and physical tabletop calibration; and obtain hands-on GM/player usability approval. These are not proven or silently accepted by this isolated candidate. Keep `docs/Index.md` unchecked.


## Privacy acceptance regression (T-043, 2026-11-01)

The isolated native output now fingerprints all source layers (including live
raster pixel hashes), grid geometry, floor instance, LOD, explicit grant IDs
and ordered fog operations **before and after** asynchronous GPU readback.
This rejects source edits while a sanitized frame is in flight. It does not
provide ongoing authorization subscription: a future trusted editor policy
controller **must** call `AtlasPlayerOutputSession.invalidate()` on audience,
grant, layer-access or fog revisions, including while camera follow is frozen.
Never use the editor preview cache's `audience="player"` partition as permission.

Run `tests/player_privacy_acceptance_smoke.gd` headlessly and
`tests/player_privacy_acceptance_visual.gd` under native X11 rendering. The
latter saves a native framebuffer witness to `user://validation/player-privacy-t043.png`.
The tests cover private rooms/labels/tokens, D0/D1, re-hiding, preview cache
poisoning, freeze/revocation, and mid-capture edits. These checks do **not**
validate a live production GM-to-player session or a physical projector.

## T-044 — Single-window/Web-compatible fallback (isolated proof)

`AtlasPlayerOutputSession.open_embedded(host)` is a presentation *surface*,
not a second OS window. A trusted caller supplies a **visible, empty, dedicated
Control** sized to the player viewport (normally the whole Web app). Missing,
pre-populated, zero-sized or oversized hosts are rejected. The session adds an
opaque black input-blocking backdrop and a texture-only display, using exactly
the same `AtlasPlayerProjection.build_capture_input` sanitizer and private
`AtlasMapCapture` as the native output. No GM canvas or canonical campaign is
parented into this player host. The host must remain reserved for player
content; embedding into a live GM sidebar or adding editor overlays is **not**
a safe fallback. Production GM/player screen switching is not wired.

Output begins blank. A trusted GM caller must explicitly provide layer grants
and a matching camera frame before `publish()`. Missing or stale grants,
render errors, mid-capture revocation, resize, aspect mismatch and host hiding
all leave the surface blank; resized output requires a new matching frame.
Follow/freeze changes only the player camera. A future trusted controller must
call `invalidate()` on every publication-policy, fog and source-art revision,
even while frozen. This isolated proof does **not** automatically subscribe to
production editor changes. `close_output()` and removal of the session from the
scene tree release the embedded surface. Superseded asynchronous callbacks do
not invalidate a newer output.

**Limitations:** This fallback displays a player screen *instead of* the GM
editor in one viewport, not concurrently on a physical second monitor. Fullscreen,
second-display selection and screen sharing belong to the browser/OS and are
not implemented here. No native-only window API, DOM/JS bridge, network client,
threads, or clipboard are required by this fallback; the rendering path uses
Godot Control, SubViewport and Compatibility-renderer image readback.

`tests/player_web_fallback_smoke.gd` checks headless host constraints, camera,
resize, visibility and teardown; `player_web_fallback_visual.gd` uses a native
harness window with an empty presentation Control to inspect the actual display
framebuffer before, during and after authorized capture/revocation. This proves
**native X11 Compatibility rendering**, not runtime Web behavior. The Web export
build is a separate compilation check. Browser-runtime testing was deferred by
the user and remains unperformed, alongside real player/GM privacy approval,
production UI integration and owner acceptance. Keep `docs/Index.md` open.
