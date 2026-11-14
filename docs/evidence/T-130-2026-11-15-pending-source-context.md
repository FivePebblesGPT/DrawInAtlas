# T-130 — Pending selection and image/Object frame source-context safety

Date: 2026-11-15. Branch: `sprint/2026-11-14`. The negative-control base is
local T-129 `12c0b9281ebd71b5181d8148d5ac5cb4b13b3641`; the remote is
`61c6f689974a848f8a7cc4040c98be418518b156`. The pinned engine is
**Godot 4.8.beta3.official.c51ff06e8**, Linux x86-64 from supplied bundle 8.
Runs use headless/dummy audio and Xvfb/Mesa GL, **not** an owner display/GPU
or physical input-to-photon measurement.

## Bug and independent failing baseline

The original shared workspace allowed Ctrl+D/Deselect during a released or
queued Brush gesture. `canvas.clear_selection()` changes the captured edit
mask, causing `DrawingCanvas._cancel_stroke_if_selection_changed()` to discard
the active session and T-124's queued second gesture. Changing the standalone
image frame similarly assigned `Canvas.image_bounds` before the stroke
committed, invoking the setter's cancellation path; changed Object frame
metadata could rebind context mid-stroke.

The exact same `drawing/tests/t130_pending_source_context_smoke.gd` first ran
against the unmodified T-129 workspace, with the test added only to
`drawing/tests/` (no fix applied), then against the changed canonical
workspace rebuilt into the independent Drawing stage. The baseline failed
**16 of 34** assertions: lost selection, cancelled first/queued paint,
stale/changed frame metadata and lost saved pixels. The candidate passed
**34/34**, with two ordered commits and original/persisted image content.

```sh
G=/mnt/data/work/bundle8/Godot_v4.8-beta3_linux.x86_64
python3 tools/build_drawing_app.py --in-place
"$G" --headless --audio-driver Dummy --editor --path drawing --import --quit
"$G" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t130_pending_source_context_smoke.gd > t130.log 2>&1
python3 tools/check_godot_model_log.py t130.log --marker T130_CONTEXT_PASSED
```

- **Baseline exit 1:** `T130_CONTEXT_FAILED checks=34 failures=16`.
  Raw SHA-256: `ddb7a1f2850d659b38cb2fb4fcfc2d166e63736342c043570b5a89775cc64e54`.
- **Candidate exit 0:** `T130_CONTEXT_PASSED checks=34 failures=0`;
  strict log accepted, with four known post-exit resource-leak diagnostics
  retained and classified separately. Raw SHA-256:
  `38df1bd5d56f3672976c8f7230024f9c3c2469b0bc344cc321d514a202682f1b`.

## Neighboring regressions (observed exits)

| Check | Result |
| --- | --- |
| T-130 source context, headless | 34/34, exit 0, strict log |
| T-129 pending content edits | 35/35, exit 0 |
| T-128 History list | 37/37, exit 0 |
| T-127 Undo/Redo | 40/40, exit 0 |
| T-126 document switches | 34/34, exit 0 |
| T-125 Save/Close protection | 29/29, exit 0 |
| T-124 queued Brush | 69/69, exit 0 |
| T-087 image frame model | PASS, exit 0 |
| T-062 Object Editor UI | 26 checks, zero failures, exit 0 |
| T-085 live stroke | PASS, exit 0 |
| T-087 native X11 frame | PASS, exit 0 |
| T-088 native X11 clipboard/selection | PASS, exit 0 |
| T-124 native X11 queued Brush | 19/19, exit 0 |
| Independent native-absent Drawing consumer | Built/imported; `DRAWING_STANDALONE_PASSED`, exit 0 |
| T-130 Python source/CI contracts | 2 tests, all passed |

Native X11 used `xvfb-run -a -s '-screen 0 1280x900x24'` with Godot
`--display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy`.
All runs were software-rendered. The independent consumer was created with
`python3 tools/build_drawing_app.py --without-native --output <empty-directory>`;
its standalone smoke retained the four known teardown RID leak diagnostics.

## CI and review boundary

The T-130 34-check Godot oracle and two Python contracts are part of the
existing `ci_t085_live_stroke_preview` step. CI fails for process exit,
forbidden script/error markers, absent/duplicate success, or changed assertion
count. This adds **no new required check ID** to the original 46-check
inventory. A new hosted CI replay was **not** performed or claimed.

The guard is a context/data-integrity correction, not faster 60px Brush
painting, native backend adoption or physical input-to-visible evidence.
T-095 remains `manual_review: true` and In Progress. T-106/T-107 hosted CI
and T-056/T-059 owner-facing review remain unresolved.
