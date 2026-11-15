# T-138 — over-budget detached-preview focal texture retention

Date: 2026-11-15. Engine: **Godot 4.8.beta3.official.c51ff06e8**.
Linux x86-64, Xvfb/Mesa OpenGL compatibility software renderer, **not** a
physical GPU or input-to-photon measurement.

## Reproduction and fix

T-103's focal plan was disabled whenever a detached Brush or Move session was
active. T-136 supplies a complete bounded preview-display stamp index when
safe; the new planner validates its key/generation metadata and merges
preview-only tiles with committed occupancy before choosing the nearest 144
cache entries. It still renders all visible tiles, creates transient textures
for those outside the retained set, and does not alter the T-137 cold-budget
fallback for over-capacity views. Missing or untrustworthy preview metadata
continues through the previous conservative per-tile eviction path.

The native witness registers 191 real source chunks across a signed 16×12
raster footprint, leaving a preview-only hole at the focal center; it stages
one uncommitted Brush dab. Canvas is 1080×800 at 50% zoom. The same 22-check
script ran on an unchanged T-137 Canvas (`2e3a637f06fb`) and on the candidate.
The old source exits nonzero, failing **2/22** focal-retention assertions after
preview and pan while pixel, cache-bound and history assertions pass. The
candidate exits zero, passing **22/22**. The 19-check headless model covers
committed selection, signed priority, preview-only keys, focus shifts,
deterministic ordering, Move drafts, incomplete indexes, malformed/noncanonical
keys, invalid generations, excessive candidate metadata, unknown occupancy
and cancellation. Strict Godot log verifier accepts every passing run.

| Same native witness, one sample | Old T-137 | T-138 |
| --- | ---: | ---: |
| Focal plan with active preview | 0 | 144 |
| Focal plan after pan | 0 | 144 |
| Cached texture entries after pan | 144 | 144 |
| Cache hits after pan | 135 | 144 |
| Tiles composited after pan | 57 | 48 |
| Transient textures after pan | 41 | 36 |
| Cold tiles deferred after pan | 0 | 0 |

The candidate's pan composited 48 instead of 57 textures in this single paired
software run. The difference is **not** a repeatability estimate, a general
performance speedup or reference-hardware acceptance. Intermediate drawing,
RGBA8 source, cancellation, Undo/Redo and full over-budget rendering remain
unchanged; retained cache bytes remain at or below the 9MiB estimate.

## Commands used

```sh
python3 tools/build_drawing_app.py --in-place
# Local Godot beta3 binary pinned in the supplied bundle.
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t138_preview_focal_plan_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t138_preview_focal_plan_native.gd
python3 tools/check_godot_model_log.py candidate-model.log --marker T138_FOCAL_PASSED
python3 tools/check_godot_model_log.py candidate-native.log --marker T138_NATIVE_PASSED
python3 -m unittest discover -s tests -p test_t138_preview_focal_plan.py -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

Negative control used the **exact `git show HEAD:addons/drawing/canvas.gd` bytes**
for the temporarily staged standalone package; the canonical repository source
was never reset. The original baseline and corrected candidate were both
rendered with the same native test. Raw logs are retained in
[`t138-preview-focal-logs/`](t138-preview-focal-logs/). The [JSON result file](T-138-2026-11-15-preview-focal-results.json) records the baseline SHA,
source SHA-256 digests and raw-log hashes.

## Regressions and boundaries

- Focused: **19/19** headless; **22/22** native; **3/3** Python contracts,
  strict logs and zero process exits.
- Headless neighbors: T-103, T-102, T-135, T-136, T-137, original T-086
  cache, focal, and preview-index suites: **9/9** commands passed.
- Native neighbors: T-103 over-budget, T-135 sparse renderer, T-136
  preview union, T-137 cold population and original T-086 viewport,
  as well as the candidate T-138: **6/6** commands passed.
- Independent native-absent standalone Drawing consumer imports and passes
  **42/42**. Known post-exit Godot RID/resource leaks are retained and
  explicitly classified by the strict log checker, never suppressed.
- Explicit typing and CI/source contracts pass; required fast CI retains
  **46 unique check IDs**. All manual gates and other ticket statuses stay
  unchanged.

No hosted CI, physical Linux/Windows display/GPU, tablet, or owner UX approval
was observed. T-086/T-095 remain open. These results apply only to the
software test fixture and the bounded focal-cache selection rule.
