# T-261 — Native ColorPicker interruption recovery (2026-11-22)

## Reproduction (prior code at `63af17d4`)

Both tests run against the *unmodified* `workspace.gd`, with the same focused
native X11 scripts and imported Drawing/Atlas projects. Actual mouse-down,
held motion and mouse-up go through the Godot `Window.push_input` path; focus
loss is injected with `Node.notification`, and the dropped mouse-up is
represented by a following motion with no left-button mask.

| Consumer | Result on previous code |
| --- | --- |
| Standalone `t261_color_interruption_native.gd` | **8 failures / 15 checks** |
| Atlas-hosted `t261_atlas_color_interruption_native.gd` | **3 failures / 10 checks** |

Failures include a foreground preview persisting across focus loss, a stale
picker signal replacing the pigment, missed mouse-up leaving a live session,
background RGBA8 failing to roll back and keyboard edits not settling.

## Correction

`DrawingWorkspace._notification()` cancels only the active **pointer** edit
when window or application focus is lost, but settles a pending keyboard/text
edit. `_track_color_input` detects a motion without left-button mask while
pointer ownership is held. The shared interruption helper reverts the exact
canonical pigment and suppresses late native picker signals; a fresh press
lifts that suppression and starts a new gesture. Existing Escape cancellation
continues waiting for its original release.

## Validation

- Godot `4.8.beta3.official.c51ff06e8`, Linux X11/Xvfb/Mesa software rendering.
- Post-fix standalone native X11: **17/17** passed, including FG restart,
  late color signal/release, real next-press commit, missing release, BG hidden
  RGBA8, keyboard focus-loss settle and unchanged local document history.
- Post-fix Atlas-hosted native X11: **10/10** passed with a real campaign
  registry, exact RGBA8 raster tile and unchanged host revision/history.
- `make test-color-interruption` and the on-demand CI workflow stage/build and
  import both native consumers before the standalone/Atlas scripts.

### Neighbor regression matrix

| Test | Verified result |
| --- | --- |
| T-252 standalone model/native/Atlas | 56/56, 35/35, 31/31 |
| T-226 standalone model/native/Atlas | 21/21, 39/39, 17/17 |
| T-092 Color/History model/native/Atlas | 66/66, 53/53, 21/21 |
| T-258 floating focus loss standalone/Atlas | 30/30, 9/9 |
| T-261 standalone/Atlas strict log acceptance | Passed |
| Explicit-typing source check | 588 scripts + 33 skill documents |
| Ticket-store validator / docking-plan Python | 261 tickets / 10 passed |
| T-092 color Python contracts | 6 passed |

The T-261 standalone witness additionally checks the on-disk app-only palette
preferences after canceled focus/lost-release gestures; interrupted previews
never replace the last settled preference. Both test consumers pass against
actual imported native Godot projects. The hosted workflow is **not** claimed
to have run, and no physical-device acceptance is inferred. Neither a synthetic
focus notification nor virtual-X11 pointer events establish behavior for a
specific physical OS/window manager or grant owner T-250/T-059 acceptance.
