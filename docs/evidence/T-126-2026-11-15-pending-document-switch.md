# T-126 — preserve unpublished Brush input across document switches

Date: 2026-11-15 · branch: `sprint/2026-11-14`

## Source, scope and failure mechanism

The GitHub branch HEAD was verified as `61c6f689974a848f8a7cc4040c98be418518b156`
before the change. The local starting HEAD was T-125
`ed18d92f233591008df2cc067a830379fb6f6462`, with T-122–T-125 still
unpushed. The final delivery must include **all five local commits**, not
only T-126. The packaged target SHA/tree are verified after commit.

In `addons/drawing/workspace.gd`, `_activate()` sets `canvas.document` to
another document and then clears `canvas.session`. Until a long Brush/Eraser
release finishes, the original document is often still *clean*, despite
pending input. T-125 blocks Save and active closure, but it did not protect
New/Open, Object attachment, keyboard/TabBar switching, inactive-tab
closure or Save-and-Close of an older inactive tab. Switching could therefore
cancel an edit, leave the original clean, and lose already received pixels.

The T-126 guard reuses the existing `has_pending_stroke()` predicate and
user-visible `_can_persist_or_close()` error path. It checks before creating
new tabs or decoding files and at the central tab-switch/removal gates. A
rejected TabBar click restores the previously active selection; recursive
same-tab signals cannot clear an active pending session. Existing idle
same-tab refresh behavior must remain intact (a first iteration that skipped
*all* idle callbacks regressed the standalone selection test). Save-and-Close
of another tab clears its close intent if rejected.

No Godot document format, chunk/brush geometry, image decoding, native backend,
source revision or frame-budgeted raster stage was modified. The user must
retry tab navigation after commit; no deferred action is synthesized.

## Reproduction and retained evidence

Exact pinned engine: `Godot 4.8.beta3.official.c51ff06e8` from supplied
bundle 8, Linux x86-64. For the tests below, the canonical addon is staged
into `drawing/` and its resources freshly imported:

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t126_pending_tab_switch_smoke.gd
python3 tools/check_godot_model_log.py LOG --marker T126_TAB_SWITCH_PASSED
```

The **negative control** used the unchanged, independently staged T-125
checkout at commit `ed18d92f`. Its real-file test exits **1**, with
**26/33** failed assertions. Specifically, switching/cycling, same-tab
reentrancy and TabBar selection, inactive close, internal removal and a
stale Save-and-Close callback abandoned the first released stroke; New,
Open, Object creation/attachment discarded or displaced an unfinished
edit. Negative test failures are expected; no Godot parser error is used
as evidence. Original-log SHA-256:
`81965ee9fffa97b9e341e7fa873864f34e3f17a3e17662e10d527af847e53ad3`.

The corrected candidate passes **34/34** with zero process exit and strict
log verification. The test uses one 210-point 44px Brush stroke plus a
queued second stroke before attempting tab switches and inactive close.
Neither can publish until the prior session completes. Afterwards both
commits remain on the original `DrawingDocument`, can be undone and redone
independently, and roundtrip exact RGBA8 bytes through a portable `.drawing`
file. New/Open and Atlas Object attachment remain rejected while pending,
then complete successfully once the same canvas finishes. The other
new-document fixture uses a real 2×2 PNG. Candidate-log SHA-256:
`5c6ffaf01a1f27fd2befc3adffd89b34e2f173c99727aa2cd4cfbb6cd9a43f4d`.

Both test cases use real Godot Canvas/Workspace methods and file I/O. The
native pointer tests below exercise real X11 framebuffer/input paths under
Xvfb/Mesa; they are **not** physical reference-hardware latency evidence.

## Neighboring verification

All passing Godot tests returned process exit 0 and passed the exact-success
marker checks in `tools/check_godot_model_log.py`; recognized post-success
RID/font/texture leaks remain separately reported.

| Test | Checked assertions |
| --- | ---: |
| T-126 pending document switching / queued history / portable Save | **34/34** |
| T-125 pending Save/Close/Object publication | **29/29** |
| T-124 queued Brush/Eraser and history | **69/69** |
| T-120 conventional File/Open | **34/34** |
| T-121 bounded raster snapshot | **24/24** |
| T-085 live-stroke model | **77/77** |
| Object Editor model | **26/26** |
| Standalone Drawing model | **42/42** |
| T-095 independent Brush coverage | **32/32** |
| Native X11 T-120 File/Object menu | **20/20** |
| Native X11 T-095 stroke navigation | **51/51** |
| Native X11 T-124 queued Brush | **19/19** |
| Fresh native-absent independent Drawing consumer | **42/42** |

Native invocations use `xvfb-run -a godot --display-driver x11
--rendering-method gl_compatibility --audio-driver Dummy --path drawing
--script res://tests/NAME.gd` followed by the same strict log verifier.

Source and CI Python suites: T-126 (3), T-125 (3), T-124 (3), T-120 (5),
T-121 (3), T-090 (9), T-093 (3), fail-late CI (8), T-094 owner matrix (4),
Drawing app (3), Drawing package contract (7), Drawing core (2): **53/53**
passed, including actual isolated clean consumer/third-project tests. The
explicit typing checker passed **434 project scripts and 33 skill docs**.
The new oracle is incorporated under existing required fast desktop
`ci_t085_live_stroke_preview` with fail-late source log checking and exact
success marker; the inventory remains **46** required IDs. No new hosted CI
run or owner/hardware approval is inferred.

## Review boundary

T-095 remains `In Progress`, `manual_review: true`, until actual reference
hardware input/preview timing and explicit owner acceptance. This fix stops
silently lost input when a document switch races with released Brush work;
it does not reduce the backlog or prove input-to-photon latency. T-085/T-086
physical UX and T-106/T-107 hosted CI remain independently open.
