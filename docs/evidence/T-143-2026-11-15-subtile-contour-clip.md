# T-143 — saturated selection contour correctness after sub-tile camera pan

**Date:** 2026-11-15. **Source baseline:** T-142
`09d6a4d99d1229eb5012cd39e68ede4bda3ec325`, Git tree
`6457fb5f6faa6bf77ebb98d7e636cc7aa8b4a7f2`. **Remote baseline:**
`61c6f689974a848f8a7cc4040c98be418518b156`. **Engine:** Godot
`4.8.beta3.official.c51ff06e8`; Linux Xvfb/X11, llvmpipe Mesa, 1920×1080
root, 1680×960 Canvas at 25% zoom. No physical GPU/input-to-photon data.

## Defect and bounded correction

At 25% zoom the native witness creates 4095 distinct shared selection tiles
plus two sparse edge islands. The two clipped source footprints differ by
**8 source pixels** in X. The camera focal tile and the 64px selection tile
window remain unchanged, but the left island leaves the viewport and a right
island enters it. Both eligible lists contain exactly **4096** tile IDs.

The unchanged T-142 cache reconciles only when the focal tile or tile window
changes. It therefore remains full of the old off-screen tile and cannot
trace the newly visible right island. The actual framebuffer contains no
outline at the new island. The correction also remembers the *pixel-level*
clipped footprint; when that changes under a saturated plan, it removes only
out-of-plan contour entries and retains all 4095 shared ones. It does not
rebuild membership on stationary redraws, enlarge the 4096-entry cache or
increase the four-new-tiles-per-frame limit. Selection state/raster/history
are never modified.

## Independent negative control and positive results

The native witness was first run against **unchanged T-142 source**, with
identical new test fixtures. It completed normally but failed **3/10**
assertions: the new edge contour was not cached, the off-screen contour
remained, and the framebuffer had **zero** distinguishing edge pixels.
The original T-142 API also rejected the model's new footprint argument with
a script error; that incomplete model run is **not** counted as a successful
assertion run. These two logs are preserved as negative controls.

With the corrected Canvas, the model passes **14/14** assertions: 4095
shared cached contours survive, only the stale edge entry is evicted, a
stable footprint leaves the full cache untouched, a changed tile window
still invalidates, and mask authorization is unchanged. The real native
X11 witness passes **10/10**, with **12** distinguishable framebuffer pixels
near the newly visible right island. Both finish with exit code zero and
strict Godot log verification.

| Neighboring verification | Result |
| --- | --- |
| T-139/T-140/T-141/T-142 headless models | 14/14, 17/17, 12/12, 13/13; strict logs |
| T-139/T-140/T-141/T-142 native framebuffer | 7/7, 9/9, 8/8, 11/11; strict logs |
| T-088 selection and clipboard | 131/131 headless, 51/51 native; strict logs |
| T-088 sparse Paste / Capture | 56/56, 54/54; strict logs |
| T-096 large-selection / Move | 13,847/13,847 headless, 34/34 native; strict logs |
| Independent native-absent Drawing consumer | Import and standalone 42/42 passed |
| Python T-130–T-139 and T-140–T-143 contracts | 33/33 and 15/15 passed |
| Explicit typing | 460 scripts and 33 skill documents passed |
| Canonical ticket/CI inventory | 143 tickets validated; 46 required check IDs |

The independent consumer's strict checker recognized **four post-success
renderer RID/texture leak diagnostics**; they remain in the raw log. Godot
resource import ran before the checked tests. This is local software-renderer
verification, **not** hosted CI or physical owner approval.

## Reproduction

```sh
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --audio-driver Dummy \
  --path drawing --script res://tests/t143_contour_clip_model.gd
xvfb-run -a /path/to/Godot_v4.8-beta3_linux.x86_64 \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t143_contour_clip_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T143_MODEL_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T143_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t14*_*.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

For independent source-package verification, use
`python3 tools/build_drawing_app.py --output /tmp/empty-drawing --without-native`,
then import that project's resources and run `res://tests/standalone_smoke.gd`
with the pinned beta3 Godot.

## Preserved evidence and limits

Raw baseline, candidate, neighboring, independent-consumer and audit logs
are in [`t143-subtile-contour-logs/`](t143-subtile-contour-logs/).
The checksum for each retained file is recorded in
[`T-143-2026-11-15-log-sha256.json`](T-143-2026-11-15-log-sha256.json).
The source delta corrects a specific saturated cache consistency bug. It
is neither a dense-canvas speedup, guarantee of full over-budget outline
coverage, physical input-to-photon measurement nor owner acceptance. T-088
remains In Progress; T-096 Manual Review; T-086/T-095 hardware and
T-106/T-107 hosted CI gates remain unchanged.
