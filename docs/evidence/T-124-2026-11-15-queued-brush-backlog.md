# T-124 — release backlog must not discard the next Brush/Eraser gesture

Date: 2026-11-15 · branch `sprint/2026-11-14`

## Reproduction and ownership

Source base: local T-123 commit `2150c48508cb6bc318a5ffb828e31ed380980d73`.
Verified remote HEAD before implementation: `61c6f689974a848f8a7cc4040c98be418518b156`.
Both T-122 and T-123 are still *local* commits relative to that HEAD;
T-124 is a third consecutive local commit. Its final remote-relative delivery
must include all three rather than pretending T-122/T-123 were pushed.

Previously, `DrawingCanvas.start_gesture` returned early with the warning
"Previous stroke is still draining" if `session != null`. A second press,
its subsequent motion and release were thrown away during an older released
Brush/Eraser backlog. This is reproducible with the normal Canvas state
machine. It is not a hypothetical data race or a physical-device timing
claim.

## Negative control

The new `drawing/tests/t124_queued_brush_smoke.gd` was run on the unmodified
T-123 `addons/drawing/canvas.gd` in the staged standalone Drawing app, then
on the candidate source with the *same* Godot executable and test. The
negative control failed **19 of its original 33 assertions**: a complete
second stroke did not publish, and independent two-step pixel/Undo/Redo
comparisons failed in both pre-released and held capture cases. There were
no `SCRIPT ERROR` diagnostics required for failure; this was an input
state-machine regression.

The fully expanded candidate oracle includes Brush and Eraser with signed
source positions, a real selection-mask hole, queued release, held promotion,
post-release zoom/pan/tool changes, overflow and a deliberately stale
predecessor commit. It passes **69/69**. The fail-closed cap is 4096 source
samples (only one queued follow-up gesture); a second concurrent pending
press or overflowing queue is explicitly rejected. On failed predecessor
commit, the queued gesture is discarded instead of being published against
an unexpected predecessor state. Input receipt timestamps are retained
for queue attribution. We do not create a second edit session until the
first has successfully closed.

## Pinned runtime and commands

- Godot: `4.8.beta3.official.c51ff06e8`, x86-64 Linux.
- Graphical path: Xvfb, OpenGL Compatibility, Mesa llvmpipe; **not** a
  physical display or input-to-photon measurement.
- Build/import: `python3 tools/build_drawing_app.py --in-place` followed by
  `godot --headless --audio-driver Dummy --editor --path drawing --import --quit`.
- Headless: `godot --headless --audio-driver Dummy --path drawing --script res://tests/t124_queued_brush_smoke.gd`.
- Native: `xvfb-run -a -s '-screen 0 1280x900x24' godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t124_queued_brush_native.gd`.
- Strict log validation: `python3 tools/check_godot_model_log.py LOG --marker T124_QUEUED_PASSED` (or `T124_NATIVE_PASSED`). Process exit must also be zero.

All final candidate headless/native runs exit zero, pass the fail-closed
checker, and emit exactly one marker. The new native test passes **19/19**:
it pushes genuine Godot pointer button/motion events through the viewport,
reads the X11 software framebuffer after the second commit, checks one
opaque second-stroke pigment pixel and compares complete canonical RGBA8
bytes to an independent two-stroke reference. The first and second strokes
are separately Undo/Redo-able.

## Adjacent regressions

| Witness | Result |
| --- | --- |
| T-085 detached live stroke model | PASS, 77 assertions |
| T-095 independent 60px Brush/Eraser source oracle | PASS, 32 assertions |
| T-095 duplicate stationary segment drain | PASS, 195 assertions |
| T-095 preview index reuse | PASS, 529 assertions |
| T-095 input-to-postdraw attribution | PASS, 22 assertions |
| T-095 Brush return value/history | PASS, 30 assertions |
| T-100 sparse atomic publication | PASS, 197 assertions |
| T-124 queued Brush/Eraser model | PASS, 69 assertions |
| T-124 X11 pointer + software framebuffer | PASS, 19 assertions |
| T-095 pan/zoom released-stroke navigation X11 | PASS, 51 assertions |
| T-099 held preview scheduling X11 | PASS, 46 assertions |
| T-098 exact changed-tile preview X11 | PASS, 29 assertions |
| T-095 full-canvas 96px pointer/Undo/Redo X11 | PASS, software-only; no latency acceptance |
| Independent Drawing consumer build/import/standalone | PASS, 42 standalone assertions |
| Python source/CI contracts | PASS, 3 T-124 assertions |
| Python Drawing app / core / contract / CI fail-late / owner-matrix | PASS, with existing skips documented by those suites |
| Explicit GDScript types | PASS, 432 project scripts / 33 skill docs |
| `python3 tools/validate_ticket_store.py` | PASS, 124 tickets |

The T-095 96px software workload needed **4868.432 ms** from input to
postdraw, including **4809.004 ms** from release to commit (single run,
`Legacy`, 100 pointer events, 512x512 image). The proposed 100 ms physical
reference budget remains **unmet** in this software trial. This is not a
statistically meaningful p95 and not a claim of end-to-end hardware latency.
It demonstrates why T-095 remains In Progress despite this input-loss fix.

The preserved Godot engine still reports known post-success renderer RID
allocations in the standalone consumer test. Strict log checking separately
classifies those warnings; new script/parse errors or pre-success renderer
errors are fatal. The only observed native input/color expectation correction
was a test-fixture RGBA integer order mistake, corrected to an opaque
`0xff9ad045` before the final X11 pass. Runtime colors/codec/brush behavior
were not changed to satisfy the test.

## Recorded raw-log fingerprints (local reproduction)

- Baseline negative oracle: `fad8639a30d2da6dc8a7b3fab0a6afeecc9b656d8c55798e75645686353041ee`
- Final positive model (69 checks): `876557e332bcfc1c7e3b4441621888a70dcbe0b813ace540975e09cbe6eecfaa`
- Native pointer/framebuffer (19 checks): `967234f0a96b5c25c6a796018bffbc3440b47894a7094d96a3fb614a5ec40787`
- Native pan/zoom navigation (51 checks): `40c141d0debdfd5377dbdb7d69c04f4c4e81633e0460f41c6dd0bef02953e073`
- Native T-099 preview (46 checks): `6fffbfd7ead343d9b1454557118b704381c834f8740dc8447b2c8e788fcb16c0`
- Native 96px full canvas run: `85243c339e50bef708a82b8958ebd6c640e257468c9aa31c41201ea9ad46731d`
- Independent consumer standalone: `c5764b85826b4e4089b3b63e6106c1545c85a9d3adb3a1184ce0688a75791d3b`

The first, interrupted *aggregated shell batch* was not accepted as evidence
of each command exiting cleanly: the T-099 witness was rerun independently
with exit code zero, strict marker validation and the hash above. Old CI
hosted checks were not rerun; new assertions are wired into the existing
T-085 required check ID and the on-demand native T-095 workflow without a
47th required fast-CI check.

## Remaining gates

This ticket is a narrowly scoped engineering completion. No owner-review
approval, Windows run, physical tablet/pointer test, meaningful hardware
p50/p95, or green current hosted PR run was obtained. T-095 retains
`manual_review: true` and In Progress status; T-085/T-086 input-to-visible
and T-106/T-107 hosted/owner evidence requirements remain independent.
