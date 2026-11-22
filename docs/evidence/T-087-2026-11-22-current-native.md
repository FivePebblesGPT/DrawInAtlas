# T-087 — Current native frame/grid validation and Atlas-hosted view

**Date:** 2026-11-22. **Base:** PR #22 local `9480bab0`, with T-251–T-254
UX corrections already applied; remote baseline `7b1fd306`. **Ticket:**
[T-087](../Tickets/T-087.md), bounded Drawing frame/grid engineering
acceptance, **not** physical/owner acceptance.

## Existing contracts retained

The source implementation of `DrawingImageFrame`, `DrawingCanvas`,
`DrawingFileIO`, the Rust-native Brush, Atlas storage and UI was not changed.
The existing suites exercise this on the **current** Hokusai-only native
backend, not the deleted Legacy painting engine:

- `drawing/tests/image_frame_smoke.gd`: **82/82** headless checks, exit 0.
  Signed frame metadata, safe failure on invalid open/save, inherited legacy
  frame, hidden RGB, clipping boundaries, grid and snap independence, and
  cancellation of a held native brush when its input context changes.
- `drawing/tests/image_frame_native.gd`: **104/104** checks, exit 0.
  Actual software-X11 rendering and pointer delivery, 16-screen-pixel
  checker behavior under multiple zoom/camera states, independently toggled
  grid and snap, native Brush/Eraser clipped input, stale mouse-release
  rollback, and off-frame art remaining renderable and undoable.

## New Atlas integration witness

`tests/t087_atlas_image_frame_native.gd` mounts a **real Atlas campaign** and
obtains a D1 Drawing document via `AtlasDrawingRegistry`. It constructs a
straight-RGBA8 tile with a colored pixel inside the finite guide and a red
pixel outside it, then renders that document using the shared `DrawingCanvas`
in an Atlas window. Fifteen assertions pass:

1. Atlas attaches the campaign and supplies a real high-detail document.
2. Framebuffer shows transparency checker inside the guide while colored
   *canonical* artwork beyond the guide is still visible.
3. Turning on visible grid changes image presentation at its source-aligned
   intersections, without tinting pixels beyond the frame; turning it on
   never implicitly enables snapping.
4. A signed snap origin works independently of whether grid lines are shown.
5. Resizing the guide, changing zoom/camera and resizing Atlas from a
   780×540 compact window to 1180×780 do not crop the off-guide art.
6. Exact source tile bytes, document revision and undo history remain
   unchanged by these view operations. Atlas can deliberately keep
   `clip_strokes_to_image_frame = false` while a finite guide is shown.

**Important framebuffer detail:** the root Atlas window applies a
non-identity content scale at 780×540; the actual viewport final transform
was approximately 0.609× relative to logical control coordinates. The first
harness incorrectly used untransformed `Control.global_position` to index the
physical framebuffer and failed **3/12** assertions despite the red pixel
being present. Correcting the oracle to sample through
`root.get_final_transform()` made the native view test **12/12**. The expanded
final 15-check version additionally asserts the signed grid overlay,
window resize, and camera pan. This was a **test-coordinate correction**, not
a claimed product defect or a performance optimization.

## Reproduction, final post-import validation

**Environment:** Godot `4.8.beta3.official.c51ff06e8`, Linux x86-64,
Xvfb/X11, Mesa llvmpipe (OpenGL compatibility), Godot dummy audio. Native
`.so` was present and imported in both consumers. First regenerated the
standalone package with `tools/build_drawing_app.py --in-place`, ran the
native-project preparation script on both projects, then the Godot editor
import for both. Both import logs contained **zero** `SCRIPT ERROR:` or
`ERROR:` diagnostics. The test commands below all exited 0:

| Command | Result |
| --- | --- |
| `godot --headless --audio-driver Dummy --path drawing --script res://tests/image_frame_smoke.gd` | `T087_MODEL: 82 checks; 0 failed` |
| `xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/image_frame_native.gd` | `T087_NATIVE: 104 checks; 0 failed` |
| `xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t087_atlas_image_frame_native.gd` | `T087_ATLAS: 15 checks; 0 failures` |
| Root `res://tests/drawing_composition_smoke.gd` | `T055_COMPOSITION_PASSED checks=89 failures=0` |
| Root `res://tests/drawing_world_mapping_smoke.gd` | `T061_WORLD_MAPPING_PASSED checks=125 failures=0` |
| Root `res://tests/drawing_history_smoke.gd` | `DRAWING_HISTORY_PASSED (101 checks; 0 failed)` |
| Standalone `res://tests/standalone_smoke.gd` | `DRAWING_STANDALONE_PASSED` |

The on-demand `.github/workflows/godot-native-t087-image-frame.yml` now
runs `make build TOOLCHAIN=system` to compile/import the **required** native
extension for both projects, then verifies the exact standalone model/native
and new Atlas-native success markers. This workflow was **not** run on hosted
GitHub Actions for this local commit; no green hosted status is claimed.

## Review boundaries

T-087's four engineering acceptance checkboxes were already satisfied by
prior implementation; this turn revalidates them on the current native head
and adds the missing Atlas-hosted native framebuffer/source witness. Mark
T-087 Done for **engineering only**. Do **not** mark the owner-requested
visual/pointer acceptance Done: [T-059](../Tickets/T-059.md) still needs
standalone physical review, [T-250](../Tickets/T-250.md) is at **Manual
Review** and still blocks Atlas delivery, and [T-056](../Tickets/T-056.md)
remains Blocked for independent integration/real-device acceptance. This is
not a Windows GPU, physical high-DPI, mouse-to-photon or release/export test.
