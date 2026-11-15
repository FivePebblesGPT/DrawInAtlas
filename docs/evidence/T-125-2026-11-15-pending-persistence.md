# T-125 — fail-closed persistence while a Brush release is unpublished

Date: 2026-11-15 · branch: `sprint/2026-11-14`

## Exact base and reproduced failure

The GitHub branch `sprint/2026-11-14` was checked before this work at
`61c6f689974a848f8a7cc4040c98be418518b156`. Local HEAD at selection was
T-124 `c20156da2f0ef1840afaaa38e5d59be7c71e188f`, including the two
other unpushed T-122 and T-123 commits. The final delivery therefore must
include **all four unpushed commits**, not just T-125.

`DrawingCanvas.finish_gesture()` requests background draining under a bounded
per-frame CPU budget. Until `DrawingEditSession.commit()` publishes, the
`DrawingDocument` can report a clean revision, even though its release/queued
Brush input is still underway. `DrawingWorkspace._save_file()` used to write
that clean pre-commit document; `_request_close_tab()` could instantly close
its clean tab and cancel the pending work. The Object Editor publisher had the
same detached-session blind spot. This is not a hypothetical threading race:
calling the real handlers before one pending release finishes demonstrates it.

## Red and green controls

1. Build the isolated Drawing stage from the canonical shared addon:
   `python3 tools/build_drawing_app.py --in-place`.
2. Import its resources with the **pinned** bundle 8
   `Godot 4.8.beta3.official.c51ff06e8`:
   `godot --headless --editor --path drawing --import --quit`.
3. Run `godot --headless --audio-driver Dummy --path drawing --script res://tests/t125_pending_persistence_smoke.gd`.
4. Run `python3 tools/check_godot_model_log.py LOG --marker T125_PENDING_PASSED`
   **and** require process exit 0. The checker may separately identify known
   post-success RID/font/texture leaks but does not suppress runtime errors.

For the independent pre-change control, the staged `canvas.gd` and
`workspace.gd` were replaced with the exact local T-124 `HEAD` versions,
then the stage was freshly reimported so SVG/resource errors would not
contaminate the result. The final **25-check negative control failed 9**
assertions and exited 1. Specifically, precommit Save overwrote a separately
written sentinel file, Save As opened despite pending pixels, the FileDialog
callback overwrote stale content, queued input did not block Save, Close Tab
removed the clean-but-uncommitted document, and Object publication saved an
old draft. No unrelated Godot parser/runtime errors preceded that failure.

With only the canonical Canvas/workspace changes restaged and reimported, the
same final test passed **29/29** and exited 0. It verifies: ordinary Save,
Save As and direct callback rejection; sentinel destination immutability;
active-tab Close Tab rejection; queued second Brush gesture awaiting the
first; the document's two committed revisions; successful later Save and
file reopen with exact RGBA8 pixels; normal dirty-close confirmation and
clean close; Object Editor publisher rejection and subsequent exact pixel
roundtrip. All rejections are visible on the normal status-bar error path.

Source implementation uses one public, read-only Canvas predicate; the shared
workspace checks it at **all** Save, Save As, direct FileDialog, Object
publisher and active Close Tab entrypoints. This is intentionally fail-closed
rather than synchronous draining: a Save request while an expensive gesture
is still processing must be retried after the normal atomic commit. A blocked
Save-and-Close also clears its stale close intent, preventing a later unrelated
Save from unexpectedly closing the tab. No save schema, native brush backend,
source/pixel semantics or transaction boundary was modified.

SHA-256 for preserved local raw logs:

- Baseline red: `ef4e48d1b7885d01d306b5eb1fb733142e3697b7662545084f5e297027a948a6`
- Candidate green: `24d0ee8f946a99759767a9749fce813e26a9b44b9c30d999366fa955c82e7b19`

## Neighboring regressions

All the following passed on the candidate using zero process exit and the
strict `check_godot_model_log.py` check. Counts are asserted by each witness,
not synthesized from a marker alone.

| Witness | Result |
| --- | --- |
| New T-125 Save/Close/queued/Object publication | 29/29 |
| T-124 chronology/queued Brush | 69/69 |
| T-120 conventional File/Open model | 34/34 |
| T-121 bounded raster snapshot model | 24/24 |
| T-093 Object source discovery | 56/56 |
| Object Editor UI model | 26/26 |
| T-085 detached live-stroke model | 77/77 |
| T-095 Brush/Eraser source-pixel oracle | 32/32 |
| Standalone Drawing smoke | 42/42 |
| T-120 native X11 File/Object/framebuffer | 20/20 |
| T-095 native X11 pan/zoom stroke navigation | 51/51 |
| Fresh native-absent independent Drawing package, import and smoke | 42/42 |

The native witnesses used Xvfb with Godot's OpenGL Compatibility renderer and
Mesa software graphics, **not** physical GPU/latency acceptance. The
independent consumer used `build_drawing_app.py --output ... --without-native`
and a fresh editor import, not stale `drawing/` staging.

Python contracts completed: T-125 (3), T-124 (3), T-120 (5), T-121 (3),
T-093 (3), fail-late CI (8), CI order (1), T-094 owner matrix (4), Drawing
app (3), Drawing consumer contract (7), Drawing core (2). All 42 tests were
collected, with 4 preexisting environment-controlled skips. The pinned
explicit-type checker passed **433** project scripts and **33** skill docs.
`python3 tools/validate_ticket_store.py` validated **125** tickets with no
manual-review closure violations. The new test executes under the existing
T-085 required fast-desktop step; required CI inventory remains **46**, with
no weakened fail-late guard or synthetic hosted pass.

## What this does not establish

T-095 remains **In Progress**, `manual_review: true`: the actual-owner
large-Brush latency and reference-hardware pointer-to-photon p95 target have
not been accepted. The new guard can temporarily require a user to retry Save
until paint finishes; it is not a throughput improvement. T-106 and T-107
still require fresh hosted CI/evidence. Local headless and Xvfb/Mesa results
do not constitute physical Windows/Linux device or owner UX signoff. The
known Godot post-success renderer resource leaks remain separately visible.
