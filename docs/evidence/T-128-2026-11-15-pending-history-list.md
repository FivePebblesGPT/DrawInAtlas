# T-128 — History-list navigation must not cancel pending Brush input

Date: 2026-11-15. Branch: `sprint/2026-11-14`. Local source baseline:
`9740cd4d8cea037a82cc184a02107fb952c6c93e` (T-127). Engine: supplied
bundle-8 **Godot 4.8.beta3.official.c51ff06e8**, Linux x86-64, dummy
headless renderer for source tests and Xvfb/Mesa software OpenGL for existing
native pointer tests. No physical GPU/touch/stylus/Windows result was obtained.

## Reproduction and fix

The T-127 `_undo`/`_redo` commands checked `_can_persist_or_close()`, but
`DrawingWorkspace._history_item_selected` directly ran independent
`document.undo()`/`document.redo()` loops after the user selected a History
list row. While `canvas.has_pending_stroke()` was true (including a second
queued Brush gesture), this changed the document revision; the Canvas then
cancelled delivered input on the next frame. The History selection could also
visually indicate a row that was not actually safe to commit.

The fix checks the target cursor before mutation. No-op selection is harmless;
otherwise the same visible pending-stroke guard used by T-127 rejects an
unsafe jump, and the `ItemList` is reselected to the actual cursor under the
existing `_rendering_history` reentrancy suppression. Valid navigation is
unchanged after the stroke finishes. No changes to Brush timing, renderer,
file format, or canonical straight RGBA8 representation.

## Negative control and focused result

Stage the exact original T-127 `addons/drawing/workspace.gd` from `git show
HEAD:addons/drawing/workspace.gd` over the generated
`drawing/addons/drawing/workspace.gd`, and run the *same new* witness after
resource import. Then restage the current shared addon and rerun:

```sh
export PATH=/mnt/data/work/binaries:$PATH
python3 tools/build_drawing_app.py --in-place
# For red control, replace staged workspace.gd with the T-127 HEAD version.
godot --headless --editor --path drawing --import --quit
timeout 100s godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t128_history_list_pending_smoke.gd > t128.log 2>&1
python3 tools/check_godot_model_log.py t128.log \
  --marker T128_HISTORY_LIST_PASSED # green only
```

- **Red (original T-127):** process exit 1; **13 failed of 37** assertions.
  The list jump alters revision, moves the cursor, clears older pixels,
  cancels two unpublished strokes, and leaves a mismatched selected row. A
  forward jump also alters the existing Redo branch beneath pending paint.
  Red raw log SHA-256:
  `409045b916c06e56e7c03689dca680e815afecae5e3969aeacc3d1d680b210c1`.
- **Green (T-128):** process exit 0; **37/37 assertions**; strict
  `check_godot_model_log.py` success, with four known post-exit resource-leak
  lines classified separately. The test exercises backward/forward UI row
  selection, selected-row restoration, queued Brush publication as distinct
  history transactions, old-branch discard, exact RGBA8 history restoration,
  and a complete portable `.drawing` Save/Open roundtrip. Raw log SHA-256:
  `60f2b297e0f8eee892192facd0e39c91129c216b18ce92613bca0e33654a7e07`.

Both the baseline and candidate were imported before the clean comparison;
Godot's known post-success dummy-renderer leaks remain visible, not suppressed.

## Neighboring regression and CI checks

| Test | Observed result |
| --- | --- |
| T-124 queued Brush/Eraser | 69/69, strict log |
| T-125 pending Save/Close | 29/29, strict log |
| T-126 pending tab switching | 34/34, strict log |
| T-127 Undo/Redo while draining | 40/40, strict log |
| T-085 live-stroke model | PASSED marker, strict log |
| T-120 unified File/Open | PASSED marker, strict log |
| T-121 raster byte snapshot | PASSED marker, strict log |
| Standalone Drawing | PASSED marker, zero exit |
| T-095 Brush coverage | PASSED marker, zero exit |
| T-124 native X11 framebuffer/pointer | 19/19, zero exit |
| T-120 native X11 menu interactions | PASS, zero exit |
| Python T-120–T-128 contracts | 26/26 |
| T-094 owner matrix + T-107 replay audit | 14/14 |
| Explicit GDScript typing | 436 project scripts, 33 skill documents |

Existing native GUI tests used:

```sh
xvfb-run -a -s '-screen 0 1280x900x24' godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t124_queued_brush_native.gd
xvfb-run -a -s '-screen 0 1280x900x24' godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t120_file_object_native.gd
```

The T-128 witness and two Python contracts run under the existing required
`ci_t085_live_stroke_preview` job step, with a 120-second timeout, exact
**37-check** success line, strict fail-late process/log checking, and no new
required CI ID. This is **not** an assertion that the updated commit has run
on GitHub-hosted CI. Owner physical-device and product UX acceptance remain
open under T-095, T-056, T-059, and T-106/T-107 as applicable.
