# T-129 — Layer/clipboard source mutation cannot discard pending Brush paint

Date: 2026-11-15. Branch: `sprint/2026-11-14`. Baseline: local T-128
`63cd5cda46e46acbd6710942e701534054969ef4` (remote remains
`61c6f689974a848f8a7cc4040c98be418518b156`). Engine:
**Godot 4.8.beta3.official.c51ff06e8** from bundle 8, Linux x86-64;
headless dummy renderer and Xvfb/Mesa GL compatibility, not physical owner
GPU or input-to-photon timing.

## Reproduction and boundary

`DrawingWorkspace._set_row_visibility`, `_set_row_lock`, `_remove_layer`,
`_create_selected_layer`, reorder and rename mutated the shared document while
`canvas.session` retained an unfinished Brush edit. Some structure paths
explicitly called `canvas.cancel_gesture()` **after** the mutation. Revision
conflicts on the next frame cancelled the already delivered input. Switching
Tree rows also invalidated T-124's deferred follow-up because the paint-source
layer changed without a history event. Clipboard Cut/Delete/Paste, text editing
and rasterization similarly lacked an up-front source-ownership check.

The new guard uses the existing actionable pending-stroke refusal *before*
each listed mutator. A rejected Tree row selection restores the previous row
without freeing live TreeItems or overwriting the warning via a recursive
same-row callback. Copy and non-mutating panel controls remain available.
The original processing budget and canonical RGBA8/Undo semantics are untouched.
Direct `DrawingDocument` calls by independent Atlas code are not changed.

## Red and green Godot witness

The exact same `drawing/tests/t129_pending_content_edit_smoke.gd` was executed
against (a) the unmodified T-128 `addons/drawing/workspace.gd`, temporarily
copied over the independently staged `drawing/addons/drawing/workspace.gd`, and
(b) a rebuilt/imported package containing the fix. The original canonical
source in `addons/drawing` was not overwritten during the negative control.

```sh
export PATH=/mnt/data/work/binaries:$PATH
python3 tools/build_drawing_app.py --in-place
godot --headless --audio-driver Dummy --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t129_pending_content_edit_smoke.gd > t129.log 2>&1
python3 tools/check_godot_model_log.py t129.log \
  --marker T129_PENDING_EDIT_PASSED  # green only
```

- **Baseline:** exit 1; **17 of 35 assertions fail**. Layer/group creation,
  visibility/lock, reorder, rename and remove, plus row selection, mutate or
  retarget source during detached paint; a later frame loses queued input.
  Raw SHA-256: `fe474eb5cf8838d94d1cad2ba35cea39aeed3f07580b0536b51d8100cf52c071`.
- **Candidate:** exit 0; **35/35 assertions** pass with strict log verification.
  Both Brush transactions are preserved, source revisions remain unchanged
  during rejection, Tree selection is restored even after a real `item_selected`
  signal, the final pixels are saved/reopened, and layer edits/Undo resume after
  processing. Raw SHA-256:
  `466862914408b6c35e80f9ee70be5d22a25ea58c2aba4e52f5ad14ca20eed058`.
  Four preexisting post-success Godot RID leak diagnostics are preserved and
  classified separately; they were not hidden or treated as runtime failures.

The legacy T-089 headless fixture previously asserted that clicking group
visibility must cancel a detached edit. It now verifies the **opposite** until
explicit cancellation, then applies the row edit and Undo as before. The
revised suite passes **63/63**, exit 0, raw log SHA-256:
`b424f2ff263ad89a7183a0ac3da1b9d5238b0a7f4c128f3bb3191344b99e6de9`.
No test silently reclassifies a lost stroke as successful.

## Neighboring verification (observed)

| Verification | Result |
| --- | --- |
| T-129 headless | 35/35, strict log, exit 0 |
| T-089 layer-structure headless | 63/63, exit 0 |
| T-088 clipboard headless | 131/131, strict log, exit 0 |
| T-124 queued Brush headless | 69/69, strict log, exit 0 |
| T-125 pending persistence | 29/29, strict log, exit 0 |
| T-126 pending tab switch | 34/34, strict log, exit 0 |
| T-127 pending Undo/Redo | 40/40, strict log, exit 0 |
| T-128 pending History list | 37/37, strict log, exit 0 |
| T-085 live-stroke headless | 77 checks, strict log, exit 0 |
| T-120 unified Open | 34 checks, strict log, exit 0 |
| T-121 raster snapshot | 24 checks, strict log, exit 0 |
| T-095 Brush pixel oracle | PASS, strict log, exit 0 |
| Native X11 T-089 layer structure | 36 checks, exit 0 |
| Native X11 T-088 selection/clipboard | PASS marker, exit 0 |
| Native X11 T-124 queued Brush | 19/19, exit 0 |
| Standalone native-absent consumer | Built, imported, `DRAWING_STANDALONE_PASSED`, exit 0 |
| Python T-124–T-129 and T-088/089 contracts | 27 tests, all passed |
| GDScript explicit typing | 437 scripts + 33 skill documents passed |
| Ticket-store validator | 129 canonical tickets valid |

Native X11 runs used `xvfb-run -a -s '-screen 0 1280x900x24'` with
`--display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy`.
The independently exported consumer was created through
`python3 tools/build_drawing_app.py --without-native --output <empty-directory>`;
its import and `res://tests/standalone_smoke.gd` executed successfully.

## CI and owner gates

The new 35-assertion witness and two source/CI contracts run in the **existing**
required `ci_t085_live_stroke_preview` workflow step with explicit exit-code,
strict-log and exact-count checks. The inventory remains **46 distinct required
CI IDs**. The established T-089 required check retains its adjusted
63-check source/Undo witness. No new hosted run was obtained or claimed.

This correction prevents inadvertent input loss; it does not improve a slow
60px Brush, measure real hardware, provide physical input-to-photon timing,
select a native backend, or close T-095 (`manual_review: true`) or T-056/T-059,
T-106/T-107 owner/hosted obligations.
