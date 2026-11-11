## T-095 owner trace overlapping-commit epoch isolation — 2026-11-11

The non-gating `godot-native-t095-brush.yml` now labels its existing analyzer
check as covering overlapping completed-stroke timestamps. The strict
`T095_TRACE_ANALYZER_PASSED` marker and saved raw log remain mandatory. The
**10/10** stdlib Python contracts include a red/green appended-file case
where a later `down_us` exceeds the previous `down_us` but precedes the
previous `commit_us`; the old analyzer pooled unrelated 80 ms and 5 ms
release→commit observations. The corrected analyzer partitions these cohorts
without changing its output schema v3 or the Godot schema-1 exporter. Five
pinned-engine neighbors pass with strict log checks. This identifies an
observable timestamp-order discontinuity, not a verified process/device
boundary or physical GPU responsiveness result. The required fast-CI matrix,
T-094 fail-closed policy and T-095/T-096 review gates are unchanged; hosted
Actions remain unverified.
[Evidence](evidence/T-095-2026-11-11-trace-commit-overlap.md).

## T-095 appended owner trace timestamp-epoch isolation — 2026-11-11

The **non-gating** `godot-native-t095-brush.yml` retains the strict
`T095_TRACE_ANALYZER_PASSED` marker and raw analyzer log, now with **nine**
stdlib Python contracts. The analysis output schema v3 adds
`timestamp_epoch_index` (one-based per input file) and partitions matching
Brush-setting groups when `down_us` moves backward in an appended JSONL file.
A red old-analyzer control pools the 80 ms and 5 ms example into one group;
the updated version keeps both cohorts distinct. A timestamp regression is
only an observable clock boundary, not a verified hardware or session ID;
restarts without a regression remain undetectable. The Godot schema-1
exporter and canonical Brush path are unchanged. The required fast-CI matrix,
T-094 fail-closed log policy and T-095/T-096 review gates remain intact.
Hosted CI and owner-device acceptance were not verified.
[Evidence](evidence/T-095-2026-11-11-trace-epoch-isolation.md).

## T-095 offline trace cohort isolation — 2026-11-11

The non-gating `godot-native-t095-brush.yml` continues to run
`tests/test_t095_trace_analyzer.py` with the strict
`T095_TRACE_ANALYZER_PASSED` marker and retained raw log; the suite now has
**eight** Python contracts. It fails closed if separate input JSONL files
with identical Brush settings are pooled, or if strokes within the same file
are incorrectly split. The new **analysis output schema v2** adds
`source_file_index` (1-based argument position) to per-stroke/group output
and declares `cohort_boundary`; the application-exported `schema: 1` format
is unchanged. No filename or device identity is included in generated
reports. Even a single appended file may mix sessions, so these groups do
**not** prove hardware equivalence. The required fast-CI matrix, T-094
log checker and T-095/T-096 manual-review gates are unchanged.
Hosted CI and reference-device responsiveness remain unverified.
[Evidence](evidence/T-095-2026-11-11-trace-cohort-isolation.md).

## T-095 offline owner-device trace analysis — 2026-11-11

The non-gating `godot-native-t095-brush.yml` workflow now executes
`tests/test_t095_trace_analyzer.py` (eight stdlib Python contracts), preserving
`/tmp/t095-trace-analyzer.log` and requiring one exact
`T095_TRACE_ANALYZER_PASSED` marker through T-094's fail-closed log checker.
The tool `tools/analyze_t095_trace.py` validates and summarizes existing
schema-1 opt-in `user://` Brush JSONL records. It clearly separates retained
percentiles, lifetime maxima, absent Godot callbacks and physical display
latency; malformed or incompatible records fail without a partial report.
The canonical Drawing Brush and exporter are unchanged, and this **does not**
introduce a new required fast-CI check, physical hardware acceptance or a
hosted Actions pass. T-095 remains In Progress with an owner review gate;
T-096 remains in Manual Review.
[Detailed verification](evidence/T-095-2026-11-11-owner-trace-analysis.md).

## T-095 opt-in local Brush profile trace — 2026-11-11

The non-gating `godot-native-t095-brush.yml` now checks
`drawing/tests/t095_owner_trace_smoke.gd` with the strict exact
`T095_OWNER_TRACE_PASSED` marker and retains
`/tmp/t095-owner-trace.log` under `if: always()`. The local independent
**17/17** regression covers default-disabled logging, two appended successful
gestures, a bounded numeric JSONL schema, no document/pixel identifiers,
cancelled gesture suppression, traversal rejection, 4 MiB file ceiling and
RGBA8/Undo/Redo parity. The original Canvas and staged disabled-writer control
fail one test each. Twelve adjacent strict-marker headless tests, real Xvfb
navigation/integration/pointer runs, and a clean native-absent import passed.
The feature is a local, explicit opt-in **owner hardware diagnostic**, not
telemetry by default and not evidence of physical input-to-photon latency.
The 46 fast-CI check IDs, T-094 fail-closed log policy, T-095 owner gate and
T-096 Manual Review are unchanged. Hosted CI remains unverified.
[Evidence](evidence/T-095-2026-11-11-owner-trace-jsonl.md).

## T-095 preview input-receipt to Canvas/post-draw correlation — 2026-11-11

The **non-gating** on-demand `godot-native-t095-brush.yml` stages canonical
Drawing and runs `drawing/tests/t095_preview_input_postdraw_smoke.gd`, requiring
exactly one `T095_PREVIEW_INPUT_POSTDRAW_PASSED` marker through T-094's
fail-closed `check_godot_model_log.py` checker. The raw
`/tmp/t095-preview-input-postdraw.log` is retained under `if: always()`.
The local **22/22** independent oracle verifies earliest batch-receipt
correlation, no-op and coalesced callbacks, cancellation, bounded history,
real 60px Brush pixels and Undo/Redo; deliberately discarding receipt stamps
fails **8** assertions. The actual native five-stroke witness reports retained
receipt→draw/callback p50/p95 and unmatched callback counts. These are engine
input-receipt/render-callback intervals, **not** device-to-photon measurements.
The 46 required fast-CI check IDs and T-094 strict logging policy remain
unchanged; hosted CI and owner physical-device acceptance are unverified.
[Evidence](evidence/T-095-2026-11-11-preview-input-postdraw.md).

## T-095 bounded duplicate-target input drain — 2026-11-11

The non-gating, on-demand `godot-native-t095-brush.yml` now runs
`drawing/tests/t095_duplicate_drain_batch_smoke.gd` with the strict
`T095_DUPLICATE_DRAIN_PASSED` marker via the existing T-094 fail-closed
log checker and uploads its raw log regardless of later job failures.
The **195/195** local Canvas witness compares 162 chronological source
samples, individual timestamp accounting, exact RGBA8 preview/commit,
Undo/Redo and bounded Legacy same-position staging against a full-raster
reference. The original Canvas fails three new grouping assertions. No
input is dropped, no Hokusai/NativeHard staging semantics change, and the
required fast desktop CI check IDs are unchanged. Isolated batch/CPU metrics
and Xvfb/Mesa tests do **not** establish owner physical responsiveness or
hosted CI acceptance.
[Detailed evidence](evidence/T-095-2026-11-11-duplicate-drain.md).

## T-095 cross-batch stationary Legacy dab regression — 2026-11-11

The non-gating, on-demand `godot-native-t095-brush.yml` workflow stages the
canonical Drawing source and runs `drawing/tests/t095_cross_batch_dab_smoke.gd`,
requiring exactly one `T095_CROSS_BATCH_DAB_PASSED` marker through the existing
fail-closed `check_godot_model_log.py` verifier. The raw
`/tmp/t095-cross-batch-dab.log` is uploaded under `if: always()`. The
**663/663** local oracle compares 121 separate Brush/Eraser 60px one-point
batches against independent full-raster controls and validates signed bytes,
RGBA8, preview/history, moved endpoints, changed width/color/mode/selection,
clip/budget, transform/anchor, late source-tile failure and exact retry/Undo.
Disabling reuse in a staged copy triggers four intentional failures. The
isolated six-run alternated `t095_cross_batch_dab_bench.gd` is opt-in and has
**no CI timing budget**. The native absence fallback remains safe; the 46
required fast-CI check IDs and T-094 strict log policy remain unchanged.
Hosted CI and owner physical-device responsiveness/approval are unverified.
[Evidence](evidence/T-095-2026-11-11-cross-batch-dab.md).

## T-095 same-batch duplicate waypoint oracle — 2026-11-11

The on-demand `godot-native-t095-brush.yml` runs
`drawing/tests/t095_duplicate_waypoints_smoke.gd` using the same fail-closed
`check_godot_model_log.py` and its exact `T095_DUPLICATE_WAYPOINT_PASSED`
marker, retaining `/tmp/t095-duplicate-waypoints.log` even when later steps
fail. The independent 276-check test validates signed RGBA8 preview/commit,
Brush/Eraser history, clipping and mask changes *across* batches, and
failure/retry. The skip applies only to consecutive identical points **inside**
one Legacy `paint_path()` call, not to native Hokusai pigment or changed
settings at the same position across calls. A disabled-shortcut control fails
ten checks. The isolated seven-run 60px batch CPU witness has no CI timing
budget. Neither the 46 required fast-CI checks nor T-094's fail-closed logging
policy changes. Hosted CI, whole-pointer latency and owner hardware approval
remain unverified. [Evidence](evidence/T-095-2026-11-11-duplicate-waypoints.md).

## T-095 stationary/axis scanline bounds independent oracle — 2026-11-11

The **on-demand** `godot-native-t095-brush.yml` checks
`drawing/tests/t095_axis_scanline_bounds_smoke.gd` with the strict exact
`T095_AXIS_SCANLINE_PASSED` marker and preserves its log. The **278/278**
headless oracle computes every candidate using original full-rectangle
Geometry2D/Vector2 distances, independently of the conservative optimized
stationary/axis scanline bounds. It covers 60px and narrow/fractional widths,
signed anchors, irregular storage tiles, masks, clipping/splitting, exact
preview, commit delta and Undo/Redo, including three ~10-million-coordinate
float32 axis-fallback cases that fail four checks on the original source.
A staged-only wrong-bound control fails 22 checks. No required fast-CI step or owner acceptance status changes;
local Xvfb measured no credible full-pointer-gesture speedup. Hosted Actions
and physical input-to-photon acceptance remain unverified.
[Evidence](evidence/T-095-2026-11-11-axis-scanline-bounds.md).

## T-095 native/GDScript Hokusai pigment rollback witness — 2026-11-11

The **on-demand** `godot-native-t095-brush.yml` builds the pinned
GDExtension, then runs `drawing/tests/t095_native_pigment_atomic.gd` with the
strict `T095_NATIVE_PIGMENT_ATOMIC_PASSED` log marker and retains the raw log.
The test requires the actual native class and bundled `.myb`, not a simulated
pixel list. It injects a *late* GDScript source-chunk read failure after one
successful native pigment batch, compares failed-batch preview and history,
then verifies exact same-object retry, subsequent pigment deltas, no-retry
commit, signed >32-bit anchors, selection holes, RGBA8 source bytes and
Undo/Redo against an uninterrupted native reference. Original 2026-11-11
binary: **4 of 56 assertions failed**; transactional fix: **57/57** locally.
Four Rust unit tests, Clippy and format pass. The existing fallback oracle
now checks Hokusai transaction negotiation: 7/7 with current native,
7/7 using the actual previous native binary (Legacy fallback), and
7/7 on a fresh native-absent import. The GDScript stub-only
126-check bulk-delta oracle remains independent and works without a native
library. No change to the **46 required fast-CI check IDs**; hosted Actions
and owner-hardware 60px responsiveness/approval remain unverified.

## T-095 NativeHard/GDScript source-read rollback witness — 2026-11-11

The **on-demand** native workflow builds the pinned Rust extension and then
runs `drawing/tests/t095_native_hard_source_atomic.gd` with the strict
`T095_NATIVE_HARD_SOURCE_ATOMIC_PASSED` marker. The test does not skip if
no native class is installed. It injects a late Drawing source-tile failure
after native coverage has advanced, and verifies reject/retry and reject/skip
parity on the **actual GDExtension** for both Brush and Eraser, with
independent document/native pairs, 64-bit signed anchors, selection holes,
RGBA8 preview, commit and Undo/Redo. The previous addon/native binary fails
**7/53** Brush assertions; the expanded fix passes **113/113**, plus Rust
**5/5**, Clippy and release build. The workflow uploads the raw log even if
later steps fail, and the 46 fast required GDScript check IDs are unchanged.
An old installed real binary without the NativeHard transaction handshake
selects Legacy at the start of a stroke. Neither local software assertions
nor the on-demand CI declaration prove hosted CI or owner hardware latency
acceptance. [Evidence](evidence/T-095-2026-11-11-native-hard-source-rollback.md).

## T-095 optional NativeHard batch-atomicity witness — 2026-11-09

The on-demand `godot-native-t095-brush.yml` workflow additionally builds the
Linux Rust/GDExtension from the pinned `native/drawing_brush/Cargo.lock`, stages
both manifest and binary, pre-registers the extension ahead of cold editor
import, then runs `t095_native_hard_atomic.gd` with the fail-closed marker
`T095_NATIVE_HARD_ATOMIC_PASSED`. This test **requires** the actual native
class, never silently skips without a binary, and checks rejected later
samples/oversized batches leave the native cursor and covered-pixel history
unchanged. The local **28/28** pass and original-binary **6-failure** control
do not count as hosted CI. The 46 required fast-GDScript checks are untouched;
T-095 owner hardware review and T-096's separate manual gate remain open.

## T-095 Legacy Brush direct tile-publication oracle — 2026-11-09

The on-demand `godot-native-t095-brush.yml` workflow now runs
`drawing/tests/t095_legacy_tile_commit_smoke.gd` and validates the exact
`T095_LEGACY_TILE_COMMIT_PASSED` marker with the fail-closed model-log checker.
It compares native-style validated tile publication against the original
canonical pixel-key publisher for ordinary Brush/Eraser, mixed API fallback,
signed coordinates, source replacement, stale revisions and atomic history
(**507 local checks**). It adds no new required fast-CI check ID and does not
make optional native packaging or physical owner responsiveness an approved
gate. The selected local tests pass; hosted Actions was not run.

## T-095 NativeHard packed output transfer oracle — 2026-11-11

The **on-demand**, non-gating `godot-native-t095-brush.yml` runs the real
GDExtension `drawing/tests/t095_native_hard_packed_output.gd`, validates its
exact `T095_NATIVE_HARD_PACKED_OUTPUT_PASSED` marker using the fail-closed
model-log checker and uploads its raw log even if a later step fails. The
**20/20 local assertions** compare tens of thousands of ordered signed
coordinates with a separate full-rectangle f32 reference, including crossing
sweeps and the native source-read transaction rollback/retry handshake; the
previous binary also passes the control oracle. Only output transport changed,
not candidate geometry or document ownership. The local isolated native-call
benchmarks are **not** pointer-to-photon or owner-hardware acceptance. The
46 required fast-CI check IDs are unchanged; hosted Actions is unverified.
[Evidence](evidence/T-095-2026-11-11-native-hard-packed-output.md).

# Godot CI policy: fast desktop core and deferred compatibility coverage

## T-095 aligned input-backlog/Canvas-frame diagnostics — 2026-11-11

The non-gating, manually dispatched `godot-native-t095-brush.yml` runs
`drawing/tests/t095_frame_input_backlog_smoke.gd` after staging the canonical
addon. The strict T-094 fail-closed checker requires exactly one
`T095_FRAME_BACKLOG_PASSED` marker, and `if: always()` uploads the raw
`/tmp/t095-frame-backlog.log`. The **24/24** local oracle verifies pending
sample age/count across interpolation and queue compaction, the latest-1024
frame ring with lifetime maxima, actual 60px Brush draw samples, independent
RGBA8 source parity and Undo/Redo. The previous Canvas fails four checks.
The graphical `brush_latency_native.gd` witness additionally prints bounded
frame-pending-age/depth p50/p95/max statistics alongside draw CPU p50/p95;
these are engine CPU/receipt times, not physical GPU or input-to-photon
measurements. The 46 required fast-CI IDs remain unchanged. Hosted CI and
owner-device acceptance are unverified.
[Evidence](evidence/T-095-2026-11-11-frame-backlog-correlation.md).

## T-095 Canvas preview projection reuse — 2026-11-11

The non-gating, on-demand `godot-native-t095-brush.yml` stages the canonical
Drawing addon and runs `drawing/tests/t095_preview_index_reuse_smoke.gd`,
requiring the exact `T095_PREVIEW_REUSE_PASSED` marker through the existing
fail-closed `check_godot_model_log.py` verifier. The raw log is uploaded even
if later workflow steps fail. This model/SceneTree oracle checks exact signed
storage-to-display stamp parity, live paint invalidation, unchanged cursor
redraw reuse, view changes, session swaps, cancellation, external document
revisions and the over-budget fallback. A staged-only disabled-cache control
failed 5 expectations. The isolated repeated index build timing is not a
real-frame or hardware latency measurement. Neither the required fast-CI IDs
nor T-094's strict crash and leak log policy changes; hosted CI and owner
physical acceptance remain unverified.
[Evidence](evidence/T-095-2026-11-11-preview-index-reuse.md).

## T-095 unchanged-preview Canvas redraw oracle — 2026-11-11

The non-gating, on-demand `godot-native-t095-brush.yml` now runs
`drawing/tests/t095_noop_redraw_smoke.gd` in the headless Drawing package,
requires the exact `T095_NOOP_REDRAW_PASSED` marker through the T-094
fail-closed log verifier, and uploads the raw log under `if: always()`.
The **24/24** local SceneTree test counts real Canvas `draw` callbacks
across consecutive consumed samples, compares source/history with an
independent edit, and exercises a fully selection-masked stroke. Against the
original staged Canvas it fails three checks (**55** callbacks); with the
preview-generation check it passes (**7** callbacks). This is a software
redraw-scheduling witness, **not** owner-device 60px Brush acceptance, a
whole-gesture latency benchmark, or hosted CI verification. No required
fast-CI check ID, ticket status, or manual-review gate changes.
[Evidence](evidence/T-095-2026-11-11-noop-preview-redraw.md).

## T-095 Hokusai buffered native pigment delta oracle — 2026-11-11

The **on-demand**, non-gating `godot-native-t095-brush.yml` builds the real
Rust extension and runs `drawing/tests/t095_native_preset_packed_output.gd`.
The fail-closed model-log checker requires the exact
`T095_NATIVE_PRESET_PACKED_PASSED` marker; the raw log is uploaded even if a
subsequent step fails. Four SHA-256 digests were recorded from the **old native
binary**, not regenerated from the optimized path. The 69/69 pass spans four
bundled presets, ordered 32-bit signed (x,y,RGBA8) triples, 242,651 exported
pixels, real batch rollback and exact same-object retry. A temporary
coordinate-order reversal fails four golden checks. Optional native-call
CPU timings exhibit warmup variation; no hardware input-to-photon or owner
review approval is inferred. No required fast-CI check IDs change; hosted CI
is still unverified.


**Policy (2026-11-03):** Required push/PR GDScript CI now verifies the implemented **Drawing package and shared Atlas composition foundation**. The approved complete Drawing Essential baseline remains unfinished under T-059. Windows/Linux desktop are the release-first targets. **Web export, broad native framebuffer sweeps, and historical Atlas pointer/shape tests are intentionally excluded from push CI.** They remain in source and are not claimed green.

## Owner-facing Drawing quality gates — 2026-11-05

[Owner's 23-finding hands-on review](DRAWING_USABILITY_REVIEW_2026-11-05.md) documents failures not captured by earlier green core/standalone smoke tests. [[T-094]] owns the reproducible failing CI groups (`T-068` strict native ABI stress and `T-073` stale T-064 status assertion) and the actionable desktop witness matrix. Do not interpret green T-053/T-063 tests, headless assertions or standalone export as proof of live paint/selection/dock usability. Add targeted native pointer/framebuffer/performance tests under [[T-085]]–[[T-093]], with real hardware checks where necessary; keep `.drawing` roundtrip as a positive regression. No owner manual gate is completed by CI.

## T-095 conservative oblique Brush scanline oracle — 2026-11-11

The **on-demand**, non-gating `godot-native-t095-brush.yml` runs
`drawing/tests/t095_oblique_scanline_bounds_smoke.gd`, requiring the exact
`T095_OBLIQUE_SCANLINE_PASSED` marker via the fail-closed model-log verifier
and preserving its raw log. Local pinned-beta3 results **513/513** compare
oblique optimized candidate pruning against the original full-rectangle
Geometry2D and `_stage()` oracle across 22 signed, masked, clipped, split,
high-coordinate, fractional-width/60px Brush/Eraser cases. A deliberately
undersized staged-only bound fails **55** of the initial 466 checks. The
optional long-diagonal CPU benchmark reports local stage-only gains, **not**
a controlled physical pointer/compositor result; full mixed-workload results
are noisy. No required fast-CI check ID or manual-review approval changed.
Hosted CI and owner-hardware latency remain unverified.

## T-095 per-session source/preview tile-reference cache oracle — 2026-11-11

The **on-demand**, non-gating `godot-native-t095-brush.yml` runs the
`drawing/tests/t095_brush_tile_reference_cache_smoke.gd` oracle and requires
exact `T095_BRUSH_TILE_REFERENCE_PASSED` using the fail-closed model-log
checker; it uploads the raw log even on subsequent CI failure. Locally the
**626/626** independent canonical-publisher checks cover signed coordinates,
irregular strides, Brush/Eraser, transparent pixels, selections, tile revisit,
late source-read rejection, rollback, exact preview, before/after history,
Undo and Redo. A deliberately invalid patch-reference control failed **95**
checks. The test does not depend on native availability. Neither this local
verification nor the on-demand workflow declaration constitutes hosted CI or
physical owner-device acceptance. The **46 required fast-CI IDs** are unchanged;
T-095 remains `In Progress` with manual review outstanding.

## T-095 source-tile-key reuse oracle — 2026-11-11

The **on-demand** `godot-native-t095-brush.yml` runs
`drawing/tests/t095_brush_tile_key_cache_smoke.gd` and requires the strict
`T095_BRUSH_TILE_KEY_CACHE_PASSED` marker, preserving the raw test log. The
33,037-assertion source/history oracle covers signed >32-bit coordinates,
eight power-of-two and irregular strides, transparent/partial-alpha source,
Brush and Eraser, selection holes, tile revisits, exact preview/commit and
Undo/Redo, plus source-load failure/retry. Local beta3 results pass; hosted
CI is unverified. The required fast-CI 46-step matrix and owner device
approval are unchanged.

## T-095 bounded latest stage-batch profiler witness — 2026-11-09

The existing on-demand `godot-native-t095-brush.yml` runs the new
`drawing/tests/t095_stage_batch_window_smoke.gd` with fail-closed
`T095_STAGE_BATCH_WINDOW_PASSED` and uploads its raw output. The **29/29**
headless oracle checks the 4,096-entry latest-window ring, exact lifetime
batch count/max, an evicted early outlier, full-wrap ordering, and a real
Brush stroke with unchanged RGBA8 pixels, Undo/Redo and navigation. A
previous-source negative control fails; the new test also passes on a clean
standalone package without the native extension. Long-stroke p50/p95 describe
**only the latest retained 4,096 batches**; exact worst and count are lifetime
metrics. This is a telemetry integrity fix, not an owner-device speed result,
and it does not change the 46 required fast-CI IDs or close the T-095 gate.

## T-095 per-pixel Brush result reuse witness — 2026-11-09

The on-demand `godot-native-t095-brush.yml` now checks
`t095_brush_result_reuse_smoke.gd` (**30/30**, marker
`T095_BRUSH_RESULT_PASSED`) through the strict fail-closed model-log
validator. It tests that only internal Brush staging reuses a session-local
immutable success, while ordinary `_stage()` calls and failures keep their
independent result semantics, and exercises exact preview, history and
Undo/Redo. It passes with and without the optional native extension. This
changes no required fast-CI check IDs, does not represent hosted CI success,
and does not replace hardware owner acceptance for T-095.

## T-095 bounded sample-to-stage telemetry witness — 2026-11-09

The on-demand `godot-native-t095-brush.yml` now also runs the strictly
validated `t095_latency_window_smoke.gd` (**22/22**, marker
`T095_LATENCY_WINDOW_PASSED`). It checks the chronological last-4,096 latency
window, exact lifetime count and worst age, plus a real 4,602-waypoint Brush
stroke's source pixels, post-release navigation and Undo/Redo. Its original-
source negative control fails the 4,096 cap. Longer-stroke input-latency
percentiles from the retained array are **latest-window estimates**, not
whole-stroke percentiles; exact worst age is separately recorded. This
changes neither the 46 required fast-CI check IDs nor the independent
physical owner-acceptance gate.

## T-095 sustained-input buffer retention witness — 2026-11-09

The on-demand `godot-native-t095-brush.yml` now includes the strictly
validated `t095_input_queue_compaction_smoke.gd` (**31/31**), preserving its
raw log even if a later test fails. The test checks a 6,000-event sustained
producer/consumer queue, a live 1,600-point Brush stroke, exact source-space
input and timestamp preservation, post-release camera/tool navigation and
byte-identical independent render/Undo/Redo output. It does **not** change
any of the 46 required fast-CI IDs or constitute physical GPU latency or
owner signoff. The T-095 manual gate remains open.

## T-095 Legacy 60px source-tile/original-geometry witnesses — 2026-11-09

The on-demand `godot-native-t095-brush.yml` runs two additional fail-closed,
Godot-headless oracles: `t095_oblique_geometry_smoke.gd` (**86/86**, original
`Geometry2D` swept-circle output) and `t095_stage_tile_lookup_smoke.gd`
(**4,193/4,193**, independent source-read/preview/history parity across
signed anchors and seven tile strides). They use strict named success markers,
retain their logs, and do **not** change the 46 required fast-CI check IDs.
The paired five-stroke 60px/786% Xvfb Legacy witness measures GDScript
staging CPU only, not physical input-to-photon latency. T-095 remains
`In Progress` with owner manual review required.

## T-095 direct native-tile commit parity — 2026-11-09

The on-demand `godot-native-t095-brush.yml` now runs
`drawing/tests/t095_tile_commit_smoke.gd` (**56/56**) through the
fail-closed `T095_TILE_COMMIT_PASSED` verifier, saving its raw log. This
**native-independent** regression compares canonical history, dirty-region
bounds, preview, commit, Undo/Redo and injected partial-failure cases against
the original global-pixel edit path. It does not add a required fast-CI
check ID, install Rust, prove an OS export works, or accept physical UI
responsiveness. The T-095 manual owner gate stays open.

## T-095 Hokusai batch-delta parity — 2026-11-08

The existing required `ci_t085_live_stroke_preview` fast-CI step now also
runs `drawing/tests/hokusai_bulk_delta_smoke.gd` with the fail-closed
`T095_BULK_DELTA_PASSED` marker. Its deterministic native-output stub
compares 57 source/preview/transaction assertions with the former pixel-at-a-
time staging path, including invalid trailing coordinates, signed 64-bit
anchors, and atomic rejection/retry after a failed lazy source-tile load.
This does not require Rust to be installed in hosted CI, and does not change
the 46 required check IDs. The on-demand T-095 workflow repeats it.
Actual Rust/Hokusai or physical paint responsiveness still requires separate
native/hardware evidence; test assertions alone are not performance approval.

## T-094 native POSIX signal failure classification — 2026-11-08

The shared `tools/check_godot_model_log.py` verifier rejects bare and
Bash/Dash/Sh-prefixed native `Bus error`, `Illegal instruction`, and
`Floating point exception` crash banners after a valid `*_PASSED` marker.
Real CLI tests and six old-checker negative controls demonstrate the
fail-closed behavior, while benign prose and the existing *exact* post-exit
RID/texture-leak exception remain unchanged. The existing T-073 Python
contract step runs the new tests: the fast-CI inventory remains **46 required
checks**. This does not substitute for hosted GitHub Actions or physical
owner acceptance.

## T-087 host camera/pointer mapping guard — 2026-11-08

The required T-087 fast-CI step continues to run
`drawing/tests/image_frame_smoke.gd`, now including cancellation when an
embedded host pans the camera during queued Brush or selection input
(**78 checks**). The existing on-demand
`godot-native-t087-image-frame.yml` requires **104 native Xvfb/Mesa**
assertions, including visible held preview, no ghost commit after pan,
restored input state, marquee cancellation and no-op camera assignments.
Neither the 46 required check IDs nor the hardware/manual approval gates
change. A successful native software-renderer run is not physical owner
acceptance.

## T-094 optional physical timing summary — 2026-11-07

The existing T-073/T-094 Python documentation CI step tests
`drawing_owner_evidence.py verify --timing-summary` with synthetic five-sample,
outlier, `FAIL`, `NOT RUN`, malformed timing and mixed-commit cases. This
optional reviewer command reports **only validated** per-zoom p50/p95 using
R-7 linear interpolation; it does not sample a physical monitor, enforce
latency thresholds, add a CI step ID or approve the owner UX gate. Raw
artifacts and physical review remain required.

## T-086 density-aware sparse-source compositor — 2026-11-07

The existing required T-086 CI step runs
`drawing/tests/renderer_sparse_pixel_smoke.gd`, now including public-pixel
RGBA8 parity for 13/24/48/64/96-entry signed source tiles, clipping,
layered alpha, detached preview overrides and cancellation (**590 checks**).
The same strict `T086_SPARSE_PIXEL_PASSED` marker is required; the 46-check
inventory is unchanged. `drawing/tests/renderer_density_benchmark.gd` is an
**on-demand, nine-sample CPU-only** density-sweep witness (8–256 seeded
pixels), printing per-case medians, p95 and output SHA-256. Do not enforce
wall-clock thresholds in fast CI or mistake this for native GPU/owner evidence.
The T-086 ticket contains paired before/after software timings. Physical
Windows/Linux responsiveness, large dense cold zoom and owner acceptance are
still outstanding.

## T-086 shared frame source-chunk parity — 2026-11-06

After staging and **importing** the standalone Drawing package:

```sh
godot --headless --path drawing --script res://tests/renderer_shared_chunks_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/viewport_cache_native.gd
```

The 31-check model proves byte-exact adjacent display-tile parity, 8→2
source-chunk resolution calls on a two-layer/four-tile example, a hard
256-reference frame-plan cap, live detached preview updates and proper
stale-epoch/corrupt-lazy-source rejection. The native witness passes 76
framebuffer assertions and records `source_chunks_shared`. The existing
`ci_t086_viewport_cache_model` step runs the model and validates its success
marker; no required CI check ID was added. These are **local headless and
software-GL** tests, not a large dense first-zoom frame timing or physical
GPU acceptance. T-086 stays In Progress.

## T-086 detached preview index parity — 2026-11-06

After staging **and importing** the standalone Drawing package, run:

```sh
godot --headless --path drawing --script res://tests/viewport_preview_index_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/viewport_cache_native.gd
```

The 2,146-check model compares frame-local preview generations with the
legacy per-display-area lookup across signed seams, different storage strides,
cancellation, 64-bit overflow fallback and the capped index. The native
75-check witness verifies actual Xvfb/Mesa held-button pixels and that
cancellation removes the preview. New per-frame metrics distinguish one
index build/number of keys from a bounded fallback. Five diagnostic paired
lookup timings are printed; do not set CI timing thresholds or construe this
as full viewport or physical input-to-photon latency. The existing
`ci_t086_viewport_cache_model` step runs this after sparse-layer parity;
required 46 CI check IDs are unchanged. T-086 remains In Progress.

## T-086 cold compositor regression and opt-in measurement — 2026-11-06

The existing `ci_t086_viewport_cache_model` fail-late step also runs
`drawing/tests/renderer_cold_tile_smoke.gd` (45 exact model assertions),
so the **46 required check IDs do not change**. Its success marker is
validated with `tools/check_godot_model_log.py`, which rejects script or
runtime defects and reports only the known post-success Godot exit leaks.

For reproducible cold **CPU** composition medians/p95 and pixel SHA-256 parity
against the pinned pre-optimization source, run
`python3 tools/benchmarks/t086_compare_cold_composite.py --godot godot`.
The same script runs in the manual-on-demand
`godot-native-t086-viewport.yml` workflow alongside the native viewport
framebuffer witness and the older pre-cache full-frame benchmark. It builds
isolated standalone projects and verifies the archived baseline's hash; it
never asserts physical display latency, GPU memory bounds or hardware owner
acceptance. T-086's remaining cold zoom/large dense hardware gates stay open.

The follow-up direct sparse-map read optimization also has a separately
SHA-256-pinned immediate-predecessor fixture. Compare this narrower CPU change
without conflating it with the earlier storage-row cache and opaque fast path:

```sh
python3 tools/benchmarks/t086_compare_cold_composite.py --godot godot \
  --baseline pre-indexed-read
```

The fast T-086 step now checks both fixture digests and fails before launching
Godot if either pinned source is corrupted. The manual-only T-086 workflow
runs both CPU comparisons and retains separate before/after logs. The new
four-dense-layer model tests confirm exact source-over/preview parity, but CPU
medians do not imply full cold-zoom frame speed or GPU scan-out performance.

## T-086 frame-local visible-layer preparation — 2026-11-06

The **same** `ci_t086_viewport_cache_model` check runs
`drawing/tests/renderer_visible_plan_smoke.gd` after the cold compositor
oracle. The test validates byte-exact render equivalence for sixteen source
rectangles, unchanged ordered layer traversal (one per prepared frame rather
than one per display tile), detached preview, document revision/visibility
and lazy-source epoch rejection, and invalid plan diagnostics. The paired
nine-sample CPU-only timing is diagnostic and does **not** enforce a latency
threshold. The native T-086 framebuffer witness also checks that cache-hit
redraws prepare **zero** plans and a dirty redraw prepares **one**.

Preparation remains frame-local, never serialized or reused after a source
revision/epoch change. This is not a physical-GPU performance witness and does
not close T-086's large dense zoom/hardware gates. The required 46-check fast
CI inventory is unchanged.

## T-086 bounded sparse-layer compositor witness — 2026-11-06

The existing `ci_t086_viewport_cache_model` step runs
`drawing/tests/renderer_sparse_layer_smoke.gd` with the strict success-marker
log checker. It verifies that only potentially occupied committed/lazy
raster layers are resolved for a planned cold display tile, while active
previews, source errors and invalid/oversized footprints conservatively keep
the original path. Direct renderer callers are unchanged. The check runs
**inside the existing 46-check inventory**, with a nine-pair *diagnostic*
headless CPU timing printout but **no flaky timing assertion**. The native
viewport suite remains separately runnable under Xvfb and requires a clean
Godot editor import after standalone staging. This does not imply hardware
input or cold zoom acceptance.

## T-094 OOM and allocator-crash log guard — 2026-11-07

The shared `tools/check_godot_model_log.py` now fails closed on bare or
shell-prefixed `Killed` (for example a SIGKILL/OOM termination), glibc
allocator-corruption banners (`malloc():`, `free():`, `realloc():`,
`munmap_chunk():`, `double free or corruption`), and uncaught Python runtime
headers even **after** an exact `*_PASSED` marker. ANSI decorations and
leading whitespace cannot hide these diagnostics. The 20-test Python contract
suite includes a negative comparison with previously accepted fault lines,
CLI rejection, harmless explanatory prose, and exact known post-exit Godot
RID leak allowlisting. This augments the workflow's separate pipefail/command
exit-code checks; it does not add a workflow step, bless a local test as hosted
CI, or approve physical-owner findings.

## T-094 unified Drawing model-log policy — 2026-11-07

The fast-CI Godot-backed T-085/T-086/T-087/T-088/T-089/T-091/T-092/T-093
steps all run `tools/check_godot_model_log.py` with a single exact success
marker, and treat verifier failure as `ci_fail_marker` (without short-circuiting
subsequent fail-late checks). T-090 runs both Python contracts and a 32-check
headless overflow-menu model witness with the same fail-closed checker. The
T-089 test's canonical `T089_MODEL_PASSED: 62 checks` counts as one success
marker; the verifier accepts only a positive integer in that counted syntax.
Duplicate markers, arbitrary success substrings, unexpected `ERROR:` lines,
script/parse/compile/model errors and incorrect counted-marker text are fatal.
Only **named, post-success** Godot 4.8-beta2 RID/texture leak diagnostics are
retained with a separate count; they are not evidence of clean teardown.

The required CI check-ID inventory remains **46**. The existing required
T-073 documentation test step executes additional strict workflow and
synthetic shell regressions in `tests/test_t094_godot_model_log.py`; no extra
hosted job, LFS asset or manual gate was added. Exploratory selected local
replays cannot attest to a complete GitHub Actions run or physical UX.

## T-094 mandatory T-095/T-096 source oracles and summary grammar — 2026-11-07

Required fast-CI checks `ci_t085_live_stroke_preview` and
`ci_t088_selection_clipboard_model` now also execute the independent T-095
Brush/Eraser source/rollback and T-096 large selection/Move mask/byte oracles,
respectively. Each runs only after canonical standalone staging/import, writes
a distinct log and uses the same fail-late, exact-marker Godot log verifier.
The actual pointer/framebuffer/timing tests remain **opt-in Xvfb/Mesa**, and
physical owner acceptance still needs owner-supplied hardware evidence.
The 46 required check IDs and the CI report/export schema are unchanged.

`check_godot_model_log.py` accepts only bare `*_PASSED`, exact positive
`N/N`, `: N checks`, `(N checks; 0 failed)`, `(N checks, 0 failures)`,
`checks=N failures=0`, `N checks, failures=0`, or the font witness's
`(0 failures)` syntax. Partial `N/M`, zero assertion counts, nonzero failures,
extra annotation and duplicate malformed success summaries are failures.
Existing named *post-success* Godot leak diagnostics are retained and counted,
never used to suppress other runtime faults. Tests for positive/negative
formats and mandatory workflow wiring run in the existing T-073 documentation
step. Partial local replay is always reported incomplete, even when all
selected steps pass.

## T-094 headless FileDialog and stale standalone assertion guard — 2026-11-07

Godot 4.8 beta 2 reports a runtime `ERROR: Window 0 spawned at invalid
position` when a native FileDialog is centered against the 0×0 headless
screen. The Drawing workspace presents the **same save dialog** using `show()`
only on the headless display driver; desktop X11/Windows retain
`popup_centered()`. The T-062 Object Editor model still exercises
Save-and-Close, open dialog visibility and now the pending-close target. The
strict CI log checker does **not** suppress the invalid-window error. The
standalone T-053 Python contract requires a strict `0 failed` summary and
at least the current 42 checks, instead of treating an added assertion as a
failure merely because an old fixed count of 38 was embedded in the caller.
The T-096 model uses the permitted 120-second watchdog. These fixes preserve
the 46-check inventory; none are owner physical-GPU or native-dialog UX approval.

## T-094 complete Linux fast-CI replay and T-068 fixture renewal — 2026-11-07

The checked-in 46-check inventory replayed on pinned Godot 4.8 beta 2 in
an isolated local profile with matching Linux export templates. A complete
**45/46** diagnostic run found a stale T-068 pinned-oracle generator which
accessed the pre-T-095 `DrawingEditSession._covered` string dictionary.
The generator now obtains the same pixel indices from T-095's integer-keyed
global `_covered_rows` and proves **exact equality of all 16 pinned
regenerated fixtures**, including zero-alpha coverage and signed anchors.
The subsequent complete local replay executed and passed **46/46 checks**;
full per-step logs and script/log digests are in the local external replay
directory. The audit is **exploratory** (`--allow-dirty`), not a hosted
GitHub Actions run, a commit-pinned audit, or native Windows/Linux owner
approval. The outstanding manual UX gates remain explicitly unapproved.

## T-094 strict-native and owner evidence checkpoint — 2026-11-06

The merged `main` baseline [CI run](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/42140327784)
remains **red**: a detached GCC/Clang strict quad-stress mask and stale T-064
status assumptions in T-073 are reproducible issues, not legitimate owner UX
failures. The stress harness now explicitly compiles with
`-ffp-contract=off` and tests a real `-O3 -mfma` profile on capable Linux
hosts: contraction changed convex validation outcomes in a local reproducer.
It retains 96-case exact parity per profile, source pins and atomic rejection
assertions; detailed case/return diagnostics help triage a future regression.
T-073/T-074 verify **ticket obligations**, not frozen Kanban stages.

The [23-finding native acceptance runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md)
is guarded by `tests/test_t094_owner_matrix.py` inside the existing fail-late
T-073 documentation job. It records real pointer/framebuffer/hardware and
owner evidence **separately** from fast deterministic checks. The local
standalone `.drawing` regression, Linux export/isolated run, and Xvfb
software-pointer sanity checks are not substitute approval for T-056,
T-059, T-065 or T-083. T-094 remains In Progress until remote CI and
future Linux/Windows owner-witness rows are evidenced; don't change
review flags merely because this patch's local tests pass.

## T-094 fail-closed check accounting and physical evidence capture

The fast CI terminal summary now derives **all expected `ci_` step IDs** from
its checked-in `.github/workflows/godot-check.yml`; an absent, skipped,
malformed or unexpected check fails the final job rather than being omitted
from a misleading “all passed” count. Duplicate IDs are rejected. This does
not remove `continue-on-error` or stop later jobs from collecting their logs.
Regression contracts: `tests/test_godot_ci_fail_late.py`.

Owner-run native evidence is documented in the
[23-finding matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md). The offline
`tools/drawing_owner_evidence.py` creates per-OS **NOT RUN** manifests and
verifies hashed artifacts and metadata. Combined Linux/Windows reports must
refer to **one exact source commit and Godot build**, with optional
`--expected-commit $(git rev-parse HEAD)` pinning; mixed revisions cannot
produce a complete acceptance record. Its tests run in the existing T-073
fail-late CI step (`tests/test_t094_owner_evidence.py`), not an extra fast CI
step. A structurally valid JSON manifest cannot approve the four owner-gated
tickets, validate a physical pointer or substitute for remote CI success.

## T-094 local fast-CI replay (diagnostic, not remote CI)

`tools/replay_godot_ci.py` can execute the **46 check steps** from the checked-in
`.github/workflows/godot-check.yml` on a developer Linux environment with the
**exact** `4.8.beta2.official.*` Godot binary. This is a faithful Bash-command
rehearsal, not a new CI suite. It does not install Godot, checkout code, run
GitHub's service container, or produce Windows/physical owner evidence. Run it
from the repository with `godot` on `PATH`:

```sh
python3 tools/replay_godot_ci.py --output /tmp/drawing-ci-replay --expected-commit "$(git rev-parse HEAD)"
# To isolate checks during development (intentionally returns nonzero/incomplete):
python3 tools/replay_godot_ci.py --output /tmp/drawing-ci-subset \
  --check ci_t085_live_stroke_preview --check ci_t086_viewport_cache_model
```

A new output directory is required. Each extracted Bash script runs under
`-eo pipefail` in its own process group; a per-step watchdog (default 1800 s)
terminates an entire timed-out process group. Later checks still run after
failures. The output directory contains `scripts/`, `logs/`, `report.json`,
and `summary.md`; each executed step records its exit code, runtime, and
SHA-256 script/log digest. A selected subset always lists other checks as
**missing** and **never passes the complete-CI gate**. Unrecognized workflow
shells, expressions, conditions or actions fail closed instead of silently
replaying a different command.

To avoid falsely attributing an uncommitted test to a Git revision, the normal
runner rejects dirty worktrees and `--expected-commit` requires clean source.
`--allow-dirty` is an explicitly **exploratory** mode: its report has no
`candidate_commit` attestation and cannot become remote-CI/owner evidence.
The regression contracts run in the existing T-073 fast CI step:
`tests/test_t094_ci_replay.py`. **T-094 remains In Progress** until patched
GitHub CI itself is green and real Linux/Windows owner evidence is reviewed.

## T-094 complete replay evidence audit

The completed local replay of clean commit `c18e69b` passed **46/46** checked-in
fast workflow steps under `4.8.beta2.official.cafc17a19`. It took 295.2 s of
step runtimes and retained **56 recognized Godot 4.8 beta2 exit-leak lines in
13 logs**. This still requires remote GitHub Actions verification, and the
leak lines must not be described as a clean teardown. The SHA-256 of that
run's `report.json` was
`a99f7a2c4ce42d0593574d1e5351438a4092adb1d299987f4b08f4ca8e99930d`.

Audit a copied, retained replay directory before citing the local result:

```sh
python3 tools/verify_godot_ci_replay.py /tmp/drawing-ci-replay \
  --expected-commit "$(git rev-parse HEAD)"
```

The auditor verifies **all** 46 expected checks, script bytes against the
workflow, per-script/per-log digests, outcome and exit codes, log-path safety,
step order and the regenerated summary. A missing result, failed test,
changed workflow, altered script/log, symlink or incomplete replay is rejected.
A matching digest can detect accidental/tampered local bytes; it **does not**
independently attest who ran them. The `--expected-commit` must refer to the
candidate used for that replay (use its full SHA for historical runs). The
contract regressions in `tests/test_t094_ci_replay.py` also exercise tampering.

## T-094 hosted fast-CI outcome artifact (not owner/hardware approval)

The fast workflow has **46 check IDs** plus two final non-check steps that run
`always()` after its required fail-late summary. The first exports a small,
sanitized `ci-evidence/godot-fast-ci.json`; the second uploads it with
`actions/upload-artifact@v4` (30-day retention), including when a test step
fails. Only step **outcomes**, not `toJSON(steps)` outputs, logs, expressions,
or arbitrary CI metadata, enter the uploaded JSON. If Godot setup fails after checkout but before `godot` is available,
the artifact is marked incomplete, never green. If checkout itself fails, no
repository exporter is available; the GitHub run status remains authoritative.

The artifact records the checkout SHA (in pull-request workflows, often a
**synthetic merge SHA**), GitHub run/attempt IDs, OS, Godot 4.8-beta2 version,
workflow hash and all expected IDs. Download from that particular GitHub
Actions run; verify its run/attempt provenance independently, then check:

```sh
python3 tools/export_godot_ci_evidence.py --verify ./godot-fast-ci.json \
  --expected-commit <exact-checked-out-40-char-sha> \
  --expected-run-id <github-actions-run-id>
```

This fails closed on missing/skipped/failed checks with a forged green verdict,
wrong engine/workflow/revision, altered order and invalid result counts.
A valid **red** report can still be inspected (it must not claim success).
The `tests/test_t094_hosted_ci_evidence.py` contracts execute within the
existing T-073 fast step, keeping the push CI check set fixed at 46.
This JSON is **not signed**, cannot establish its own GitHub provenance, and
never substitutes for the separately reviewed physical Windows/Linux owner
manifest, user acceptance or `manual_review_approved` fields.

## T-094 physical timing evidence granularity

The owner-run physical manifest is a **self-reported format validator**, not
hardware or reviewer attestation. For findings #01 and #15, a claimed `PASS`
requires three per-phase millisecond sample arrays at **each** of 25%, 50%,
and 100% zoom (at least 45 samples across the three zooms and phases). The
older single pooled `timings_ms` object is no longer accepted as evidence for
multiple zoom levels. The [physical owner runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md)
provides the JSON shape; untouched `NOT RUN` templates still validate.
`tests/test_t094_owner_evidence.py` checks omitted zoom/phase data, malformed
sample values, and leakage of stale claims into unrun rows. This is part of the
existing fast documentation contract step, not an added physical CI test.

## T-094 strict Godot model-log classification and repeatable export

A complete fast-workflow local replay of the pre-fix checkpoint
`71ab793` executed **46/46** checks and correctly reported **35 pass / 11
fail**. All 11 failed after their model **success markers** because Godot
4.8-beta2 headless teardown emitted named `RID allocations ... were leaked
at exit` errors. Every retained failed-step log was inspected; no additional
pre-success script, parse, assertion, or runtime errors were found. This
explains the *local* red result, **not** the previously red upstream run or
its still-unverified status on patched code.

`tools/check_godot_model_log.py --marker TXXX_MODEL_PASSED /tmp/godot-xxx.log`
replaces broad post-test `grep '^ERROR:'` handling only in affected fast
smokes. It requires exactly one marker, rejects all parse/script/model
failures and unknown runtime errors, and reports only **known,
post-success** Godot RID/GL teardown leaks explicitly while preserving the
raw logs. Tests in `tests/test_t094_godot_model_log.py` exercise both
acceptance and fail-closed cases. The isolated Linux release gate performs
its own similarly strict exit-code/startup/runtime validation and publishes
the recognized post-exit leak count; it never treats those logs as clean.
The CI release step now stages in a fresh `mktemp` directory and cleans it
on exit, making repeated local replay safe from stale `/tmp/drawing-dist`
collisions. Each previously failing step passed its **targeted** replay,
but those partial runs do not certify all 46 checks or physical owner UX.

## T-086 over-budget cache-focus witness (2026-11-06)

The same fast `ci_t086_viewport_cache_model` workflow step now additionally runs
`drawing/tests/viewport_cache_focus_smoke.gd`, validating bounded center/pointer
retention and stable replacement with **15/15** headless assertions; the number
of required fast steps remains **46**. The on-demand X11/Xvfb
`viewport_cache_native.gd` suite now passes **80/80**, covering pointer focus
changes with a 192-tile dense software viewport. Both suites must run after
`build_drawing_app.py --in-place` and a standalone Godot editor import.
This does not cap transient GPU references for dense views, certify frame
latency on real Windows/Linux hardware, or approve owner interaction.

## T-086 transparent subchunk texture regression (2026-11-07)

The on-demand `godot-native-t086-viewport.yml` now requires an exact
**140-check** native test result and runs `check_godot_model_log.py` rather
than broadly grepping for all `ERROR:` lines (which would misclassify
recognized post-success Godot RID teardown diagnostics). The new real
X11 framebuffer tests cover sparse 256px source / 128px display overhang,
zero-alpha hidden RGB, edited/undone and lazy-loaded reoccupation, preview
cancellation and unknown-occupancy fallback. A 640×460 llvmpipe software
witness at 100% zoom uploads 65,536 instead of 262,144 RGBA8 texture bytes
on first display; full cold-frame and physical GPU latency remain unverified.

## T-086 persistent source-space viewport cache

Fast push/PR CI stages/imports the independent Drawing package and runs
`drawing/tests/viewport_cache_smoke.gd` (27 model checks). Its change-journal,
revision gaps, signed source seams and draft-stamp tests cannot prove real
texture reuse. The **manual-only** `.github/workflows/godot-native-t086-viewport.yml`
runs `drawing/tests/viewport_cache_native.gd` on Xvfb/Mesa after importing
fonts (68 framebuffer/texture checks), and calls
`python3 tools/benchmarks/t086_compare_viewport.py` to compare the T-085
pre-cache canvas against the current package using the **same** 12-trial
100/50/25% workload. Measurements separate CPU composition, `ImageTexture`
full uploads, redraw-to-frame submission, RSS/HWM and the retained texture
payload estimate. These are Linux **software** diagnostics, not physical
Windows/Linux GPU/DPI/scan-out/owner acceptance. T-086 remains In Progress
until those hardware and large dense viewport gaps are addressed. The native
witness also exercises a >144-tile conservative fallback without destroying
previously cached in-view textures; its transient frame references may exceed
the fixed retained-cache payload budget.

## T-087 standalone image-frame and independent grid

Fast push/PR CI stages/imports the canonical Drawing package and executes
`drawing/tests/image_frame_smoke.gd` (47 checks: optional signed frame metadata,
legacy read, byte-exact outside-frame pixels, invalid envelope rejection,
workspace dirty/save/open and tab-local grid options). The **on-demand**
`.github/workflows/godot-native-t087-image-frame.yml` adds
`drawing/tests/image_frame_native.gd` (36 Xvfb/Mesa framebuffer/input checks)
for constant 16-screen-pixel checker squares, 25/50/100/200% zoom, signed
pan/grid alignment, native snapped pointer, off-frame editing and undo.
The bounded fail-late guard in `tests/test_godot_ci_fail_late.py` deliberately
includes the model steps and prevents silent runaway push CI (currently 49 steps).
Xvfb/Mesa is **software-only**; neither that workflow nor the new `Done`
engineering ticket is physical Windows/Linux owner approval. Owner findings
#02/#16 remain pending in T-059 and the 23-finding acceptance matrix.

**T-087 follow-up (2026-11-08):** The same required model step now
runs **70** checks and the on-demand Xvfb-native witness runs **95** checks,
including held-pointer clipping-policy OFF→ON/ON→OFF cancellation and
no-op/commit/Undo controls. Six model and eight native checks fail when the fixed
canvas is replaced with the committed pre-fix version. This changes no
required check IDs and does not imply physical owner acceptance or hosted
GitHub Actions verification.

## T-093 Object source discovery and safe portable open

Fast push/PR CI runs `drawing/tests/object_discovery_smoke.gd` (**56**
headless checks, no GUI input acceptance), plus
`tests/test_t093_object_discovery.py` (CI, root-preference and fail-closed
native-log contracts) as one new fail-late step. The fast workflow is bounded
to **49** steps. The on-demand
`.github/workflows/godot-native-t093-object-sources.yml` first stages/imports
standalone fonts and SVG resources; `drawing/tests/object_discovery_native.gd`
then exercises **27 native Xvfb/Mesa pointer/framebuffer checks** with optional
screenshots, validated by `tools/check_native_t093_log.py`. Directory selection
inside the separate OS/FileDialog viewport is covered by its callback, *not*
by a real OS pointer click. The verifier rejects any runtime errors before
success and retains known post-success GL/RID leak diagnostics. Existing T-065
portable source and Atlas registry/NULL tests must remain green; T-065 and
finding #21 require owner hardware review independently. No proof of physical
Windows/Linux UX, input-to-photon latency or campaign-wide NULL usability
follows from software rendering.

## T-092 compact color controls, cursor history and app preferences

Fast push/PR CI runs `drawing/tests/color_history_smoke.gd` (**46** model
checks) plus `tests/test_t092_color_history.py` (four CI/log/preference
contracts) as a single fail-late step. The bounded fast workflow now has at
most **48 steps**. The on-demand
`.github/workflows/godot-native-t092-color-history.yml` stages/imports
Godot 4.8-beta2 fonts and SVG resources, runs
`drawing/tests/color_history_native.gd` (**34** native Xvfb/Mesa framebuffer,
actual viewport pointer dispatch and workspace relaunch checks, plus optional
three PNGs), and verifies logs using `tools/check_native_t092_log.py`.
Native acceptance does **not** assert a click inside the separate Preferences
modal viewport; the control signal and file persistence are tested, while a
physical Linux/Windows modal-pointer and owner visual check is **NOT RUN**.
The verifier retains recognized **post-success** GL/RID leak diagnostics, and
rejects any missing marker, runtime error or failed check. Owner #11/#23 and
all manual-review gates remain unapproved.

**2026-11-07 canonical-hex checkpoint:** The required T-092 model suite
now runs **67** assertions, rejecting bare/abbreviated hex and accepting only
`#RRGGBB` or `#RRGGBBAA` with exact RGBA8 preservation. The on-demand native
suite runs **51** pointer/Enter, framebuffer, preference, and dock assertions;
`tools/check_native_t092_log.py` rejects fewer than 51, errors, nonzero
failures, or a missing marker. Reimport the standalone project after every
`build_drawing_app.py --in-place` staging change, because the icon SVG import
metadata is generated rather than copied. A software Xvfb pass is not a
physical Windows/Linux owner approval, or a hosted GitHub Actions result.

## T-091 single floating tab group and splitter-width recovery

Fast push/PR CI executes `drawing/tests/dock_single_group_smoke.gd` (54
headless assertions) and `tests/test_t091_dock.py` (4 contract/log-verifier
tests) in one fail-late step; the existing T-078–083 state-model smoke
steps remain. The step bound is **47**. `.github/workflows/godot-native-t091-docking.yml`
is on-demand and imports the staged standalone fonts/icons before running
`drawing/tests/dock_single_group_native.gd` on Xvfb/Mesa. Its **44** native
baseline assertions (+2 screenshot readbacks when enabled) cover a one-row header, eight edge/corner pointer resize paths,
hide/recover, cold-relaunch width/host geometry, narrow-window clamps and
1.5× content scaling, and four edge overdrags that must preserve the opposite anchor at the client boundary; `T091_SCREENSHOTS` exports framebuffer PNGs. The
fail-closed `check_native_t091_log.py` retains known post-success Godot/Mesa
leaks but fails on script/runtime/unknown teardown errors, missing markers or
failed assertions. No physical Windows/Linux pointer/owner acceptance is
claimed; T-091 and T-083 remain In Progress.

## T-088 selection channel, clipboard, and native Move

Fast push/PR CI stages and imports the canonical Drawing package, then runs
`drawing/tests/selection_clipboard_smoke.gd` (100 model checks) for boolean
channel composition, the Atlas **enabled-empty deny-all** contract, masked
brush/fill/flood/clear, exact RGBA8 and hidden RGB, selection-only history,
atomic Cut/Paste/Move, negative tile seams, stale revision, locked/hidden
layers and standalone `.drawing` reopen. This is a focused additional
**44th step** within fail-late CI, never a new full framebuffer run on push.

`.github/workflows/godot-native-t088-selection.yml` is **on demand** and
runs `drawing/tests/selection_clipboard_native.gd` after clean asset import
under Xvfb/Mesa. Its 44 real pointer/keyboard/framebuffer checks include
Select click-empty, drags with Add/Subtract holes, held-button Brush/Move,
Escape/undo/redo, Ctrl+C/X/V and Delete, 50/100/200/400% pointer/zoom and
signed-tile seams. A four-sample `frame_post_draw` p50/p95 upper-bound is
logged; it is **not** a physical input-to-photon measurement. The software
runner does not close T-056/T-059 or any other manual owner-review gate.

**2026-11-07 T-088 sparse Paste extension:** The existing required T-088
step additionally runs `drawing/tests/selection_sparse_paste_smoke.gd` with
`T088_SPARSE_PASTE_PASSED` through the same strict complete-log verifier.
Its independent dense pixel oracle checks sparse/opaque fallback, mask holes,
signed coordinates, alpha-zero hidden RGB, failure rollback and Undo/Redo
(**56 checks**). The seven-trial stage-only CPU numbers are recorded in
[T-088](Tickets/T-088.md), not a physical latency or hosted CI claim.
No new check ID or owner signoff is introduced.

## T-089 structural layers, pointer row controls and undo

Fast push/PR CI stages/imports the one shared Drawing package and runs
`drawing/tests/layer_structure_smoke.gd` (**62** headless model assertions) as
its 45th bounded fail-late check. It verifies locally owned structural
history, tree insertion semantics, stable identity, canonical RGBA8, locked
subtree guards, editor selection context and filtered/paged navigation.
The **on-demand** `.github/workflows/godot-native-t089-layers.yml` imports
fonts/SVG icons first, then runs `drawing/tests/layer_structure_native.gd`
(**32** X11/Xvfb/Mesa framebuffer and physical-event-dispatch **software**
checks) at 1120×800 and 880×550, 400% zoom. The native test clicks the actual
inline eye and lock controls; it does not simulate the Tree signal or stand
in for physical Linux/Windows owner review. Pinned Godot is 4.8-beta2.
The optional native job additionally checks runtime errors with a fail-closed
log verifier (`tools/check_native_t089_log.py`): recognized Godot/Mesa
renderer-release leak reports after the success marker are retained and
counted, never silently discarded. Script errors, early runtime errors, and
unknown post-marker errors still fail; shutdown leak-free operation is not
claimed. Owner findings #19/#20 remain **PENDING** and no manual review status or
remote CI success is inferred from local tests. Shared regressions include the T-062 Object
Editor UI (25/25, selected Tree row tracks new text), the native T-063
420px/150%-scale compact workspace (layer actions wrap within the dock),
and T-073 native keyboard routing. Neither these nor remote automation
establish physical review acceptance.

## T-090 responsive workspace and icon license audit

Fast push/PR CI runs nine deterministic `tests/test_t090_responsive_workspace.py`
contracts and a 32-check Godot headless **More-menu state/dispatch oracle**
inside its unchanged bounded T-090 step (the **46th** check). The model runs
after a canonical standalone stage/editor import, and its single exact
`T090_OVERFLOW_PASSED` marker is checked by `check_godot_model_log.py`.
This covers window stretch, More-menu checkmarks and dispatch,
File/Object/Window menu ownership, per-tab close with a dirty guard, Brush px
wheel/keyboard semantics, and byte-identical MIT icons + license staging for
standalone and independent package consumers. The on-demand
`.github/workflows/godot-native-t090-workspace.yml` performs a fresh standalone
stage and Godot 4.8-beta2 import, then executes
`drawing/tests/responsive_workspace_native.gd` under Linux X11/Xvfb/Mesa
llvmpipe on a 2200×1500 virtual screen. It checks physical viewport edges
at 800×600, 1280×760, 1920×1080, also 1.5/2.0 content scale; real hover-wheel,
keyboard and nonactive-tab close/cancel/save pointer events; and emits optional
seven screenshot PNGs (84 checks, vs 77 without PNG capture); the
expanded native run includes a real pointer opening More and verifying its
Window checkmark as tabs change. The fail-closed
`tools/check_native_t090_log.py` checks summaries/markers and runtime errors;
recognized **post-success Godot/Mesa shutdown leaks** are retained and counted,
not treated as a clean teardown. This is *not* physical Windows/Linux owner
approval, and no input-to-photon latency measurement is claimed.

## Required CI

- Pinned Godot `4.8.0-beta2`, Git LFS checkout, explicit typing and CI order/aggregation guards.
- T-051–053 isolated Drawing contract, core, standalone consumer and Linux desktop release package.
- Main project import before GDScript tests: T-015 marker-only authoring and archived-data boundary (13/23), link/history and link form (29/55), overview (67), stale-result (27), hierarchy (44), Organization UI (84) and reference controls (17), all on the modern marker model; T-054 Drawing/Atlas history, T-058 headless text and licensed fonts, T-060 Object Assets, T-062 Object Editor, T-061 world mapping, T-055 Drawing composition, T-066 atomic campaign saves.
- T-068 targeted *non-push* canonical Bucket fill-to-software-frame witness:
  `tests/drawing_fill_frame_native.gd` verifies the real Drawing fill and
  renderer behind a **test-only** GUI release adapter, with signed RGBA8
  delta/revision checks, framebuffer pixel changes, and rollback on small
  budgets. Two Xvfb/Mesa runs passed 96 and 95 checks; the optional screenshot
  and JSON diagnostics are reproduced through manual
  `.github/workflows/godot-native-t068-fill.yml`. This witness is deliberately
  **excluded** from fast push/PR CI. It does not measure the production Bucket
  UI, hardware input, real display scan-out or true peak RSS/VRAM.
- T-068 optional Cairo CPU format comparator:
  `tests/test_t068_cairo_cpu.py` (**10** Python tests) exercises an independent
  straight-RGBA8 oracle, exact opaque-pixel parity, loss of premultiplied
  transparent hidden RGB, mismatch accounting, and the installed Cairo
  runtime when available; the runtime tests skip if libcairo is absent from
  fast CI. The separate **manual-only**
  `.github/workflows/godot-native-t068-cairo.yml` installs Cairo and runs the
  complete two-run 32/64/128² comparison, with a machine-readable JSON
  artifact. It never installs a native dependency in Drawing/Atlas or
  promotes opaque-only parity to a chosen backend.
- T-068 optional pinned Blend2D CPU compositor comparator:
  `tests/test_t068_blend2d_cpu.py` (**12** Python checks, including **7**
  optional live tests) verifies exact source digest, bounded caller lengths,
  untouched hidden-RGB preservation for region-only conversion, opaque/clear
  byte-parity and premultiplied-alpha non-parity. The no-dependency contracts
  join the existing T-068 fast-CI step; live tests skip without externally
  supplied Blend2D 0.21.2 build paths. The manual-only
  `.github/workflows/godot-native-t068-blend2d.yml` downloads the
  SHA-256-pinned source, builds Blend2D with its bundled AsmJit, and records
  two 9-trial runs plus raw JSON diagnostics. No library is shipped or loaded
  into Drawing, and timing boundaries are not considered equivalent.
- T-068 matched native scalar/Blend2D hard-brush ABI calls:
  `tests/test_t068_matched_brush.py` replays two source-pinned runs of six 32²
  and four 512² Godot-authored brush cases without requiring any native
  dependency on push CI. Exact pixel/mask hashes, missing/extra coverage,
  backend call orders, trial counts and medians are checked; tampering fails.
  The manual-only Blend2D workflow builds the pinned source and scalar C++
  kernel and reruns both against the same buffers in alternating order.
  This is an isolated Python→C++ call timing, **not** publication, real
  hardware, Windows or production backend acceptance.
- T-068 Linux native process-memory screen:
  `tests/test_t068_native_memory.py` verifies source-pinned, two-run `/proc`
  `VmRSS`/`VmHWM` evidence for 12 fresh scalar/Blend2D native workers,
  including complete pinned Godot hard-brush coverage/pixel parity, worker
  ordering and sample consistency. The offline replay is push-CI safe and
  requires no native library. The manual-only Blend2D workflow runs the
  actual Linux process-memory sampling after building both native ABIs.
  This **does not** measure production editor RAM, device VRAM, Windows,
  physical latency or a backend speedup.
- T-068 detached transformed four-corner convex selection comparison:
  `tests/test_t068_blend2d_quad.py` replays 15 Godot-authored 64² masks
  for transformed polygonal scope checks and validates the two-run native
  evidence without a required native dependency. The workflow-dispatch
  Blend2D job compiles the isolated `t068_blend2d_quad_selection` ABI and
  checks failure atomicity, mask-to-brush handoff and 30 exact parity comparisons.
  Exact polygon-edge and vertex ties are covered; near-boundary floating-point tolerance and hardware/release gates remain open.
- T-068 strict CPU selection kernel compiler matrix:
  `tests/test_t068_quad_compiler_matrix.py` checks a source-pinned, two-run
  Godot 48-case oracle under **GCC and Clang `-O0/-O2/-O3`** (576 exact masks)
  and 42 malformed-input atomic rejection checks. GCC `-Ofast` and Clang
  `-O3 -ffast-math` builds must fail specifically on the native compile guard:
  fast-math can elide `std::isfinite` checks, violating failure atomicity.
  The fast push/PR T-068 contracts and the manual-only bridge workflow both
  exercise this matrix. This is Linux C++ ABI safety, not native deployment,
  Windows support, a measured speedup, or physical GPU evidence.
- T-068 scalar strict-FP build safety: `tests/test_t068_scalar_strict_fp.py`
  ensures GCC `-Ofast` and Clang `-O3 -ffast-math` **fail compilation**, then
  verifies six strict GCC/Clang builds reject NaN/Inf widths and pointer
  samples without changing coverage, RGBA8 or sparse outputs. A documented
  GCC `-Ofast` failure of the old code motivates the source-local guard.
  No experimental extension is installed or selected. The scalar and native
  bridge records were freshly regenerated for the changed source checksum.
- T-068 detached C++ ASan/UBSan safety screen:
  `tests/test_t068_native_sanitizer.py` builds two instrumented
  standalone executables (GCC and Clang `-O1`), each run twice,
  exercising the four-corner mask and scalar brush coverage,
  canonical RGBA8 and sparse-delta ABIs. The 1,024 total seeded
  cases match independently checked mask geometry and exact
  full/sparse reconstruction; 68 malformed calls reject atomically
  without redzone corruption. The source-pinned evidence must match
  all counters/digests, and ASan/UBSan must exit cleanly. It runs
  in the usual (non-gating legacy) T-068 step and the opt-in native
  bridge workflow. This does not establish Windows, arbitrary ABI
  safety, production threading or physical latency.
- T-068 additional convex polygon scope stress:
  `tests/test_t068_quad_stress.py` checks a SHA-pinned Godot 4.8b2
  96-case convex scope oracle against the detached C++ selection ABI under
  GCC `-O2` and Clang `-O3`. Both profiles run twice (**384 masks**),
  and evidence tampering or invalid native output fails the normal push-CI
  job. `T068_QUAD_GODOT=godot` regenerates the independent fixture byte-for-byte.
  The experiment is not loaded by either app and does not imply Windows,
  GPU, or release acceptance.
- T-068 native Atlas four-corner scope through the *temporary* Godot bridge:
  `tests/test_t068_quad_gdextension.py` pins two 55-check Godot 4.8b2
  runs against 15 real `AtlasFill._allows_pixel` full masks, tests the
  checked C++ scope ABI and rejects tampered mask, sparse and RGBA8 evidence.
  The standard CI uses the no-Godot contract and native C++ unit checks; the
  full `build_quad_selection()` + `apply_scalar_brush_sparse()` integration
  remains manual-only in `godot-native-t068-bridge.yml`. It neither loads
  the extension at application startup nor establishes native backend,
  physical GPU, Windows or release acceptance.
- T-068 native Atlas four-corner **document publication**:
  `tests/test_t068_quad_publication.py` checks pinned two-run,
  **153-assertion-per-run** Godot evidence for 15 exact native selection masks,
  ordered sparse records, before pixels, canonical straight-RGBA8,
  revision/history increments, Undo/Redo and `NO_CHANGE` without publication.
  The Python replay reconstructs every expected final pixel from the
  independent Godot-authored mask fixture and rejects malformed source,
  output, history, revisions and evidence counts. Fast CI checks evidence
  without a native extension; the explicit `--quad-publication-only --runs 2`
  bridge mode runs in the manual-only native CI job. The temporary extension
  does not prove deployed Atlas UI behavior or physical GPU performance.
- T-068 counterbalanced **software-only** frame-load witness:
  `tests/test_t068_visual_counterbalanced.py` replays the source-pinned
  four-session ABBA `idle/loaded/loaded/idle` experiment. It checks raw
  timing/median/p95 pairs, two loaded-minus-idle contrasts per workload,
  activity of both CPU workers, identical software GPU identity and
  whole-Godot-process RSS/HWM. The Xvfb run is opt-in through
  `godot-native-t068-bridge.yml`; fast CI only replays evidence. Four fresh
  Godot processes pass 324 checks. Run order is counterbalanced but not
  randomized; no physical input-to-photon, Windows or VRAM gate is satisfied.
- T-068 opt-in **software-only** frame-jitter/CPU-load diagnostic:
  `tests/test_t068_visual_contention.py` replays two source-pinned 25-gesture
  Godot 4.8b2 X11 sessions (idle and with a separate CPU-busy subprocess),
  checks the recorded `/proc` worker CPU ticks, raw frame/dispatch statistics,
  llvmpipe adapter, canonical framebuffer checks and process RSS/HWM.
  Replay is fast-CI safe; the real two-process Xvfb run is only in the
  workflow-dispatch bridge job. Sequential nonrandomized phases and five
  samples per case do **not** establish load causation, stable p95, physical
  input-to-photon, GPU VRAM, or Windows/production backend acceptance.
- T-068 visual/X11 process-memory diagnostic:
  `tests/test_t068_visual_device.py` replays a **source-pinned Xvfb/llvmpipe**
  25-trial Godot input-to-`frame_post_draw` witness and independently validates
  raw timing medians/p95, process RSS/HWM samples, Godot 4.8 beta2 identity,
  and rejection of false hardware/VRAM claims. Fast CI never starts an X11
  window for this test; an opt-in `godot-native-t068-bridge.yml` step starts a
  separate software-GL Godot process and publishes fresh JSON diagnostics.
  Physical hardware runs require `--profile hardware` and a non-software
  `glxinfo`/Godot adapter. Synthetic input does not measure OS-to-photon latency.
- T-068 native scalar sparse publication **cancellation/conflict**:
  `tests/test_t068_scalar_atomicity.py` checks source-pinned two-run
  37-assertion Godot evidence and independently reconstructs canonical
  RGBA8 for four cancel/stale-before/stale-during/forged-original cases.
  Tampered raw evidence fails closed in fast CI without loading a native
  extension. The real 4-case `--atomic-only --runs 2` GDExtension test is
  opt-in under `godot-native-t068-bridge.yml`. This proves deterministic
  `DrawingDocument` publication rejection in a test project, not thread
  safety of the production app or a performance result.
- T-068 temporary Godot↔native transformed sparse brush comparison:
  `tests/test_t068_scalar_transform.py` verifies source-pinned, two-run
  110-check native GDExtension evidence for transformed view-space strokes,
  sparse/inverted binary selections, erasure, RGBA8, and revision-checked
  Undo/Redo. Its fast-CI tests require no extension. Real Godot native calls
  run only through `godot-native-t068-bridge.yml` (`workflow_dispatch`),
  not push/PR CI. This is client-inverted geometry and a caller-generated
  mask, **not** Atlas four-corner scope or physical GPU testing.
- T-068 detached scalar C++17 hard-brush compositing:
  `tests/test_t068_scalar_hard_brush.py` and `tests/test_t068_scalar_rgba8.py`
  compile the dependency-free, non-shipping scalar research ABI. The latter
  replays two runs of 28 pinned cases with exact coverage and straight-RGBA8
  parity, verifies small-case real Godot output and large-case independent
  patterned-source compositing, and tests fail-closed buffer aliases,
  malformed inputs and error atomicity. It is included in the existing T-068
  fast CI step without introducing any native runtime dependency or claiming
  physical performance or publication acceptance.
- T-068 verified cached flood-fill sources:
  `tests/drawing_fill_tile_cache_smoke.gd` (**30** fast-CI assertions) checks
  four-connected fills on verified lazy Object tiles as well as resident
  chunks, exact alpha-zero hidden RGB, missing/corrupt provider retry,
  selected pixels, budget rollback and far signed coordinates. The source
  cache is gesture-local; no tile is published before revision validation.
  Before/after fill CPU samples are diagnostic only and not CI gating;
  Windows/Linux hardware performance and native backend comparisons remain
  open under T-068.
- T-068 verified-source fill staging:
  `tests/drawing_fill_verified_stage_smoke.gd` (**29** headless assertions)
  verifies that fill reuses already validated immutable source RGBA8 when
  staging, without rereading each matched source pixel, while ordinary edits,
  rollback, exact hidden RGB, far signed tile seams, Undo/Redo and stale
  publication preserve prior behavior. The witness runs in the existing
  T-068 fast-CI step; software framebuffer stress remains targeted only.
- T-068 bounded flood-fill frontier:
  `tests/drawing_fill_frontier_smoke.gd` (**56** fast-CI assertions) checks
  unique-candidate work budgets, atomic rollback/retry, transparent hidden-RGB
  undo, masks, negative coordinates, and deterministic independent four-neighbor
  grid-oracle parity. It is added to the existing T-068 job step; its 32²–96²
  five-sample CPU timing pairs are diagnostic, **not** a gating performance
  target or physical end-to-end benchmark.
- T-068 safe stationary round-dab CPU shortcut: `tests/drawing_dab_geometry_smoke.gd` compares its pixels against the **original** Godot `Geometry2D` segment oracle at fractional/negative positions, tile seams and 64-bit signed anchors, including undo/redo, no-op alpha and hidden RGB (125 assertions). The large raster benchmark and 25-gesture native stress run are **targeted**, not push-gating.
- T-068 bounded axis-aligned swept hard-brush shortcut:
  `tests/drawing_axis_sweep_smoke.gd` (**239** assertions) compares precise
  touched-pixel dictionaries, RGBA8 values, masks, once-per-gesture coverage,
  undo/redo and 320 seeded axis geometry cases against independent Godot
  `Geometry2D` closest-segment results. It runs in the existing T-068 fast-CI
  step, not a new native test or CI job. The seven-sample headless
  `drawing_axis_sweep_benchmark.gd` is **diagnostic only**, not a push gate or
  physical input-to-visible timing claim.

- T-073 feature inventory and T-063 workspace documentation assertions.
- T-065 partial portable Object source discovery, identity/path/hash safety, search and real dock/Object Editor tab coupling (`drawing/tests/asset_browser_smoke.gd`, 37 checks). Bounded source thumbnails (`drawing/tests/asset_browser_thumbnails_smoke.gd`, 62 checks) are generated from canonical Drawing pixels, requested only for visible rows, and cached in a 24-image digest-keyed LRU. Changed/source-replaced files invalidate previews after successful publication or explicit Refresh; stale bytes fail closed. Explicit standalone portable `*.drawing` Import/Export file copies
  (`drawing/tests/asset_browser_transfer_smoke.gd`, 29 checks) reject stable-ID
  collisions, observed target overwrites, stale source bytes, and unregistered
  imports into Atlas-managed `*.atlas-object-index.json` roots. These copies do
  not register Atlas instances or create NULL repairs. The native pointer/scroll/focus and preview witness (`drawing/tests/asset_browser_native.gd`, 19 checks without optional screenshot (20 with capture)) is targeted and does not satisfy T-065 owner acceptance or Atlas NULL/drop functionality.
- T-065 shared Atlas Asset Browser bridge:
  `tests/asset_browser_atlas_smoke.gd` (**32** headless checks) verifies the
  shared UI's registry-driven published listing, keyboard placement, exact
  view-coordinate drop, stale/forged source rejection, distinct Atlas asset
  versus embedded Drawing IDs and campaign-rebind safety. Its native
  `tests/asset_browser_atlas_native.gd` (**12** checks; **13** with screenshot)
  checks the GUI drag provider and canvas drop dispatch in a real window.
  A distinct, targeted **real OS-pointer** witness
  (`tests/asset_browser_atlas_pointer_native.gd` plus
  `tools/test_t065_x11_pointer.py`) now verifies the actual Godot drag start,
  mouse release, invalid-target cancellation and Esc without publishing,
  **19/19** checks (**20/20** with screenshot). It uses XTEST events through
  a disposable X11/Xvfb desktop and requires optional `python-xlib`:
  `xvfb-run -a -s '-screen 0 1400x900x24' python3 tools/test_t065_x11_pointer.py --godot godot`.
  It is **not** part of fast push CI, nor a substitute for Windows/Linux
  physical-hardware and owner hands-on UX acceptance.
- T-065 real-file source parsing: `drawing/tests/asset_browser_real_io_smoke.gd`
  exercises a 351 KB, four-tile Object source, canonical pixel/metadata
  round-trip, corruption rejection, thumbnail cache and missing-source safety
  (**49 headless checks**). The bounded JSON envelope is parsed once for both
  Drawing pixels and Object metadata on full Open; an explicit
  metadata-only inspection now populates SHA-verified Atlas pages without
  decoding canonical blobs. The full loader, not that inspection, continues
  to authorize previews, Open, import/export and placement; Atlas paged browsing keeps unmodified
  off-page thumbnails within the existing 24-image LRU, but invalidates changed
  revisions and different campaign roots. Timings are diagnostic only; no
  production hardware latency threshold is implied. This runs in fast CI.
- T-065 larger Atlas source lists: `tests/asset_browser_atlas_paging_smoke.gd`
  (`T065_PAGING_PASSED`, **1,428 checks**) verifies globally searchable
  registry metadata beyond the former 512-source truncation, deterministic
  64-source pages, empty/stale-page bounds, 1,301 synthetic IDs and 66 real
  disk-backed published sources. The 10,000-summary case tests the existing
  maximum registry count without opening 10,000 files. Per-page file/hash/
  revision checks remain mandatory before Open, drag or placement; owner UX,
  physical-device latency and genuinely large source-file IO remain separate.
- T-065 Atlas-managed portable source registration and export:
  `tests/object_portable_registry_smoke.gd` (**33** disk-backed checks) covers
  embedded source-ID preservation, canonical campaign versioning, origin/frame
  metadata, duplicate/reserved IDs, symlinked paths, stale registry handles,
  optimistic publication rollback/retry, and independent portable reload.
  Object Manager Import/Export callbacks extend
  `tests/object_source_manager_smoke.gd` to **33** headless checks; native Atlas
  source-manager actions extend `tests/object_source_manager_native.gd` to
  **22** targeted X11/Mesa checks (23 with optional screenshot). The standalone
  Drawing browser's Import still rejects Atlas-managed registries, and shared
  browser-to-Atlas physical-hardware review and owner acceptance remain open.
- T-064 verified nested project-component copying:
  `tests/object_nested_project_copy_smoke.gd` (`T064_PROJECT_COPY_PASSED`,
  **37** headless assertions) verifies atomic staging of the current
  checksum-verified Objects registry/source revisions into a separate campaign
  directory, intact child hit paths and IDs, independent cloned drafts,
  exact indexed file hashes, placement/NULL behavior, and collision/stale-index
  refusal. It does not copy campaign scene/history or authorize nested source
  Save As/export; those remain separate T-064/T-066 responsibilities.
- T-064 saved-campaign Copy UI: `tests/object_nested_campaign_copy_ui_smoke.gd`
  (**39** headless checks) verifies Atlas File menu and Ctrl+Shift+S access to
  independent full-project copy, mandatory saved checkpoint, refusal of dirty
  Atlas/Drawing/Object Editor state, safe destination paths, collision and
  rename behavior, preserved nested child IDs and exact published Drawing
  pixels. Included in the existing T-064 project-copy step without adding a
  CI job. Targeted native Xvfb/Mesa (40 checks including screenshot) and a
  420px compact dialog capture do **not** substitute for physical owner UX
  review or decide nested single-source Save As/export ownership.
- T-064 complete saved-project copy:
  `tests/object_nested_campaign_copy_smoke.gd` (`T064_CAMPAIGN_COPY_PASSED`,
  **46** headless checks) validates a renamed destination, two portable root
  generations including recovery pointer, immutable retired Object revisions,
  deep child links and placements, byte-exact signed sparse Drawing data,
  isolated clone edits/re-save, source corruption and uncheckpointed Objects
  rejection, symlink refusal, destination collision and injected partial-copy
  cleanup. It copies a verified *saved* root through a private staging folder;
  it is not a UI Save As or a nested-asset deep-copy policy. CI runs it headlessly.
- T-064 nested Object source-graph safety: `tests/object_child_graph_smoke.gd`
  (`T064_CHILD_GRAPH_PASSED`, 56 checks) verifies real on-disk parent/child
  references, bounded nonrecursive cycle/depth checks, immutable pixel Save,
  optimistic index conflict handling, corrupt snapshot rollback, and nested
  Remove/NULL confirmation behavior. This is **only the graph/persistence
  milestone**; no recursive rendering/selection or owner UX acceptance is
  implied. It runs in fast push CI.
- T-064 bounded nested Object render and hit paths: `tests/object_child_render_smoke.gd`
  (`T064_CHILD_RENDER_PASSED`, 36 checks) verifies parent/child/grandchild
  pixels, negative translations and quarter-turn transforms, paint order,
  stable child-ID hit paths, NULL markers, published Save visibility, disk
  reload and Atlas map-frame invalidation. Source composition is limited to
  1,048,576 pixels per viewport, 2,048 visible nodes and 4,194,304 cumulative
  sampling/destination pixels. No nested editor UI or Save As policy is implied.
  This regression runs in fast push CI; physical display interaction remains
  outside that automated gate.
- T-064 linked-child placement duplication:
  `tests/object_child_duplicate_smoke.gd` (**53** headless checks) covers
  distinct child instance identity/generation with an unchanged referenced
  source, parent-local offset and sibling insertion, mixed structural
  Undo/Redo, stale writer/publication veto/NULL limits, missing source files,
  rendered pixels, nested hit paths, and portable reload/copy. It runs in the
  existing fast-CI child-edit step. The optional **54**-check native inspector
  screenshot witness is targeted; it is not required push CI or owner
  acceptance. Source Save As/export policy remains unresolved under T-064.
- T-064 optional child-instance labels: `tests/object_child_label_smoke.gd`
  (**54** headless assertions) checks duplicate-source identity, primitive
  metadata retention, 64-character validation, optimistic child and parent
  revisions, no-op/failed publication, interleaved parent-local Undo/Redo,
  portable registry copy, reload and actual inspector editing. The targeted
  Xvfb/Mesa **55-check** run captures a 420px screenshot; native tests remain
  non-push and do not imply Windows/Linux owner UX signoff or nested asset
  Save As/export policy approval.
- T-064 parent-owned nested sibling order: `tests/object_child_order_smoke.gd`
  (**51/51** headless checks) verifies atomic, stale-safe sibling moves,
  exact painter and hit-test priority, invalidation of Atlas composition
  previews, identity/pixel isolation, parent-scoped mixed Undo/Redo,
  boundary no-ops, persistence and live inspector buttons/keyboard actions.
  It runs in the existing fast-CI T-064 child-edit step. The targeted
  **52/52** Xvfb/Mesa witness captures a 420px inspector; this is not a
  physical-hardware test or owner acceptance of graph-copy policy.
- T-064 nested child uniform scaling: `tests/object_child_scale_smoke.gd`
  (**42/42** headless checks) validates positive parent-local basis scaling,
  child/descendant hit paths and rendered pixels, nonuniform/mirrored affine
  transforms, unchanged source revisions, invalid factors, stale writers,
  atomic publication veto, history branching and live inspector buttons.
  It is included in the existing fast-CI nested edit step. The targeted
  **43/43** Xvfb/Mesa witness captures the 420px-wide inspector; it is not
  hardware owner acceptance or an approval of nested Save As/export policy.
- T-064 reversible visibility in nested parent layouts:
  `tests/object_child_visibility_smoke.gd` (**39** headless assertions,
  fast push CI) checks optimistic child generation and parent revision,
  pixel-source isolation, no-op and publication veto, mixed Undo/Redo,
  hidden descendants excluded from render/hit paths, Atlas cache
  invalidation, portable reload and the live inspector Hide/Show control.
  A targeted Xvfb/Mesa inspector screenshot passes **40** checks; it is not
  push-gated and does not imply physical owner UX approval.
- T-064 explicit nested canvas targeting: `tests/object_child_canvas_select_smoke.gd`
  (**21** headless checks, fast push CI) verifies normal root selection versus
  Alt+click child/grandchild selection in the shared Atlas inspector, preserved
  local Undo, active-map and registry revalidation, and rejection of stale or
  forged hits. Targeted Xvfb/Mesa presentation captures a **22**-check screenshot
  run; neither this nor synthetic input replaces physical owner pointer review.
- T-064 nested canvas drag transactions: `tests/object_child_canvas_drag_smoke.gd`
  (**31/31** headless, **32/32** Xvfb/Mesa with screenshot) verifies real Godot canvas input dispatch, rotated root and deep child
  coordinate conversion, a single published parent-local undo step, unchanged
  source pixels/placement, subthreshold Alt+click, Escape/focus-loss/pointer
  exit/tool/map cancellation, stale index/placement and forged hit rejection,
  with an optional Xvfb/Mesa screenshot of the uncommitted guide. It runs in
  fast push CI headlessly. Synthetic and native framebuffer events are not
  physical mouse hardware or owner UX approval; T-064 remains In Progress.
- T-064 explicit nested NULL-child repair: `tests/object_child_null_repair_smoke.gd`
  (`T064_CHILD_REPAIR_PASSED`, **45** headless checks) verifies source-deletion
  NULL identity, explicit published replacement, original-ID metadata,
  cycle/parent/child revision rejection, publication failure rollback,
  mixed source-rebinding and transform Undo/Redo, disk reload and actual
  inspector button wiring. It runs in fast CI. An optional Xvfb/Mesa
  screenshot run passes **46/46** checks and is a targeted visual check, not an owner
  usability or Windows/Linux physical-hardware approval.
- T-064 reversible child attachment and removal: `tests/object_child_structure_smoke.gd` (**45** headless checks, push-CI-gated) now interleaves structure and transform history without source artwork changes. Registry restore preserves ID, generation and sibling order, advances child revisions and retains cycle/stale/publication protection. The extended native inspector (`tests/object_child_edit_native.gd`, **16** Xvfb/Mesa checks including screenshot) is targeted/non-push. The explicit source picker is filtered and bounded to 128 matching published assets. Neither test is owner or physical-Windows UX approval.
- T-064 parent-scoped nested child editing: `tests/object_child_edit_smoke.gd`
  (`T064_CHILD_EDIT_PASSED`, **45** assertions) checks stable child selection,
  local translation and rotation, monotonic revisions across undo/redo,
  divergent history branches, stale/concurrent edits, failed index publication,
  independent child source navigation and Atlas source-manager controls.
  A separate **10-check** Xvfb/Mesa window/interaction witness
  (`tests/object_child_edit_native.gd`) is targeted, not fast-push or owner
  UX approval. Attach/remove history, integrated canvas child selection,
  nested Save As and portable graph copy remain open.
- T-065 Atlas-owned source safety: `tests/object_asset_repair_smoke.gd`
  (48 disk-backed checks) covers optimistic deletion confirmations,
  Remove/NULL policies, stable placement generations, explicit no-guess
  repairs and rollback. `tests/object_source_manager_smoke.gd`
  (33 checks) covers source usage and actual button/confirmation paths.
  Both run in fast push CI. The native Atlas sidebar/canvas witness
  `tests/object_source_manager_native.gd` (22 Xvfb/Mesa checks; 23 with screenshot) is targeted,
  **not** owner approval; see the guarded shared-browser bridge above.
- T-078 reusable grouped dock state model and existing shell binding (82 headless assertions).
- T-080 reusable nonmutating drag planner and transactional commit/cancel (60 fast headless assertions); actual pointer/layout behavior is verified separately by native Xvfb/Mesa evidence.
- T-081 floating group ownership, unique panel/container state, stale/invalid rollback and abandoned-empty-container handling (64 fast headless checks). Native host move/resize, focus/z-order, tab/group reorganization and HiDPI are tested separately (55 Godot 4.8 beta 2 Xvfb/Mesa checks).
- T-082 cross-container pointer dock/detach/redock transaction model and unique panel ownership (62 fast headless checks), with shared T-078–T-081 state/preview contracts. Native `drawing/tests/dock_cross_native.gd` (56 actual pointer/keyboard checks plus optional screenshot) is targeted/non-push.
- T-083 versioned `user://` dock settings, missing/renamed panel recovery, invalid/corrupt JSON fallback, exact model round-trip, and resolution adaptation (`drawing/tests/dock_persistence_smoke.gd`, **46** headless assertions) are required push CI. The actual app save/relaunch/reset/hidden-host/420px/1.5× UI witness (`drawing/tests/dock_persistence_native.gd`, **63** checks, **65** with optional screenshots via `T083_SCREENSHOTS`) remains targeted/native and **does not imply owner UX approval**.
- T-079 dock UI renders from the same model; its targeted **native** Xvfb/Mesa witness (`drawing/tests/dock_ui_native.gd`, 40 assertions) remains non-push engineering acceptance, alongside the T-063 native 75-check regression. T-080 native drag `drawing/tests/dock_reorder_native.gd` (68 assertions: press/hover/release, cancellations, hints, overflow, keyboard and viewport) and T-081 native `drawing/tests/dock_float_native.gd` (58 assertions, or 59 with a PNG capture) is available in the on-demand `godot-native-t081-floating.yml` workflow with a strict `check_native_t081_log.py` checker; this is software-X11 engineering evidence, not owner/physical acceptance.
- Each check retains its original GitHub Actions `steps.*.outcome` even with `continue-on-error: true`; the final summary still fails the job if any required check fails. Scripted Godot processes have 120-second watchdogs.

## Targeted renderer/LOD feasibility evidence (T-057, completed research)

T-057 uses reproducible **non-push** headless and native renderer benchmarks:
`tests/t057_lod_headless.gd` (249 checks when writing raw JSON),
`tests/t057_lod_native.gd` (36 native X11/Mesa checks), and the retained
`tests/drawing_raster_upload_benchmark.gd` (four full-tile update sizes).
Results, hardware limits and the retain-Godot decision are in
[DRAWING_LOD_RENDERER_BENCHMARK.md](DRAWING_LOD_RENDERER_BENCHMARK.md).
These measure software-GL frame submission, not physical GPU scanout or Windows.
Do not turn a screen-only research recommendation into automatic runtime adoption.

## Targeted T-068 brush-geometry and input-to-frame evidence

Fast push CI now additionally requires `tests/drawing_edit_tile_cache_smoke.gd`
(`T068_TILE_CACHE_PASSED`, 31 checks) and
`tests/drawing_publication_tile_cache_smoke.gd` (`T068_PUBLICATION_PASSED`,
30 checks) alongside the existing 125-check original-geometry oracle. It tests lazy chunk errors/retry, cached absent tiles,
source revision conflicts and hidden RGB. The publication witness checks
per-tile source resolution, signed seams, stale originals, missing lazy blobs,
reentrant provider edits, and atomic undo/redo; neither runs heavy benchmarks in push CI.

The targeted `tests/drawing_raster_backend_benchmark.gd` compares 512/1024/2048 storage strides against the independent legacy compositor; `tests/drawing_latency_stress_visual.gd` drives 25 synthetic Control pointer gestures (stationary 4/32/64 canonical pixels, long and crossing), checks canonical Drawing revisions and actual framebuffer pixel changes, and records separate dispatch and `frame_post_draw` median/p95. Run the latter on Linux with software X11/Mesa, not in fast push CI. These timings do not measure physical GPU presentation or a Windows system. See [the T-068 CPU raster report](DRAWING_CPU_RASTER_BENCHMARK.md) for evidence and unresolved backend requirements.

The separate `tests/drawing_publication_tile_cache_benchmark.gd` is **targeted**,
not push-gating. Its isolated CPU commit median is not physical input-to-present
latency. See raw before/after measurements in `docs/benchmarks/`.

## Deferred but retained

- The old T-003 parent/child registered-overlay acceptance source is preserved unchanged at `tests/retired_legacy/references_ui_footprints_legacy.gd.txt` as an **obsolete** test, not current release coverage; the active marker-only reference test supersedes it. Historical Atlas/battlemat/selection/move/shape/wall smoke tests, especially T-014, T-019, T-022, T-024, T-025 and T-026. Some assert superseded `AtlasRasterLayer` ownership while the current editor writes canonical `DrawingDocument`. Investigate and repair each contract as related features are implemented rather than weakening expectations or claiming success.
- All Xvfb/Mesa native framebuffer suites (including slow T-058 and the broad native acceptance), interactive desktop witnesses, and performance probes are **targeted/manual or release-stage** checks while Drawing is completed. Native T-056/T-059 gates remain unapproved.
- Web export and browser artifacts are removed from the push workflow. Reintroduce them only after a specific Web support decision; T-044 remains archived.

A deferred script remains runnable manually, for example:

```bash
godot --headless --editor --path . --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/retired_battlemap_controls_smoke.gd
```

CI guards:

```bash
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py' -v
python3 -m unittest discover -s tests -p 'test_godot_ci_fail_late.py' -v
python3 tools/validate_ticket_store.py
```

This is **reduced-scope CI**, not a full release sign-off. In particular, do not infer T-014/019/022/024/025/026 or native UI acceptance from a green run.


## T-068 extended native Bucket-adapter profiling (on demand, 2026-11-03)

The manual-only `.github/workflows/godot-native-t068-fill.yml` executes
`tools/benchmarks/t068_fill_process_profile.py` in two isolated 21-trial
Godot 4.8 beta 2 Xvfb/Mesa processes. It requires successful source/pixel/
framebuffer/cancellation checks and writes per-run JSON, PNG, logs and an
aggregate Linux `/proc/PID/status` RSS/VmHWM report. It checks the executable
path to avoid sampling the `xvfb-run` shell. The five deterministic Python
unit tests in `tests/test_t068_fill_process_profile.py` run in the existing
fast-CI T-068 step; **the native runner itself is not push/PR-gating**. This
is a synthetic `DrawingEditSession` input adapter, not the real Bucket GUI,
physical display latency, per-gesture memory or GPU VRAM.


### T-068 isolated native thread-safety witness (2026-11-03)

The existing fast T-068 step runs
`python3 -m unittest discover -s tests -p test_t068_native_thread_jitter.py`
(two tests). The compiler-backed contract checks 1/2/4 worker output parity
across both native prototype APIs. The full 101-call contention benchmark is
**not** a push/PR gate; run
`python3 tools/benchmarks/t068_native_thread_jitter.py --trials 101`
when diagnostic evidence is needed. This is standalone host CPU C++ and does
not run Godot framebuffer or a GDExtension. See T-068 and its raw evidence.


### T-068 opt-in checked native buffer contract (2026-11-03)

The existing fast T-068 CI step now also runs
`python3 -m unittest discover -s tests -p test_t068_checked_abi.py`.
Six tests compile the **isolated**, not-shipped native CPU kernel and compare
new length-checked calls against ABI-1 output for 160 deterministic RGBA8
cases. They also check short/null buffers, partial alias rejection, sentinel
canaries and atomic failures. This requires only a host C++17 compiler; it
adds **no** Godot native framebuffer check to fast push CI and does not
endorse the prototype as the Drawing runtime.


### T-068 temporary GDExtension integration boundary (2026-11-03)

The on-demand `godot-native-t068-bridge.yml` additionally executes the
**128-check atomic multi-tile DrawingDocument witness**, after the checked
native, GL publication and single-tile document checks. The adapter limits
work to 16 unique tiles and 1,048,576 staged pixels; the test exercises
second-tile failures, a concurrent revision change, 64-bit signed bounds and
one-step undo/redo. This is a temporary test project and is **not** an
additional push/PR framebuffer step. The fast runner contracts reject a
missing/failed multi-tile success marker. See T-068 and its raw JSON.


`tests/test_t068_bridge_runner.py` runs **11 fast, non-native** harness
contracts in the existing T-068 push/PR step. It checks fail-closed subprocess
handling, evidence markers, source locations and the absence of a checked-in
`.gdextension` descriptor. It does **not** load a native Godot extension.

The **workflow-dispatch-only** `.github/workflows/godot-native-t068-bridge.yml`
compiles the extension from source with g++ and the `gdextension_interface.h`
generated by Godot **4.8 beta 2**. Its two temporary-project Godot runtime
runs each require **443 passing pixel/argument checks**, then an Xvfb/Mesa
software-GL run requires **370 revision/publication/texture checks**, and a
separate headless run requires **219 canonical DrawingDocument transaction/
history checks**, and a final headless run requires **128 multi-tile
atomic-publication checks**. The independent texture adapter verifies reentrant source
conflicts, exact dirty rectangles and full `ImageTexture.update()` readback.
The new adapter copies only the canonical Drawing core scripts into the
temporary project, stages the native result via `DrawingEditSession.apply_region()`
and commits through the real `DrawingDocument` transaction; this is not
production backend adoption or a partial GPU upload. The workflow explicitly installs Xvfb/Mesa and
produces JSON benchmark evidence. It deliberately does not run in push/PR CI, does not
install a native binary in either app, and does not imply editor-load or
physical-device acceptance. See [T-068](Tickets/T-068.md).


### T-068 isolated sparse-delta GDExtension witness (2026-11-04)

The workflow-dispatch-only `godot-native-t068-bridge.yml` also runs a checked
sparse-native-output / atomic canonical-document witness after the existing
whole-tile integration checks. It compares exact RGBA8, dirty regions and
Undo/Redo, rejects malformed/forged native pixel records and invalid masks,
and records **five alternate-order full-vs-sparse synthetic staging samples**
for each 32/64/128 tile size. `tests/test_t068_bridge_runner.py` adds
non-native contract checks to the **existing** push-CI T-068 step; the native
binary, framebuffer tests and benchmark stay outside fast push/PR CI. No
`.gdextension` is installed in the shipping projects. A returned dirty
rectangle does not imply GPU subrectangle upload, and these samples are
not physical or production UI latency measurements. T-068 remains In Progress.


### T-068 complete sparse-output validation (2026-11-04)

The existing **non-native** fast-CI runner contract asserts that the isolated
sparse adapter computes the full expected change set from verified source
bytes and fails if a native response omits any required pixel. A valid no-op
remains representable by a four-byte zero count. The existing **on-demand**
`godot-native-t068-bridge.yml` requires at least **173 sparse test checks** per
run, including forged empty/partial payloads and an incomplete second tile.
The optional extension is not loaded in the main application or fast push CI;
this does not imply third-party native backend adoption or hardware acceptance.


### T-068 detached scalar hard-brush parity (2026-11-04)

The existing fast-CI T-068 step compiles the **self-contained C++17 scalar
coverage comparator** and executes `tests/test_t068_scalar_hard_brush.py`.
Five tests validate 56 exact coverage comparisons across two independent
runs against pinned real Godot oracles, plus randomized distance cases,
invalid-buffer failure atomicity, and evidence replay. This work introduces
no external library download or new workflow job. It is a research-only
geometry witness, not a shipped Godot module or native UI/GPU acceptance.


### T-068 checked scalar sparse hard-brush wire (2026-11-04)

The existing fast-CI T-068 step additionally compiles the detached C++17
scalar brush and runs `tests/test_t068_scalar_deltas.py` (six tests). It
compares 56 changed-pixel wire streams against 16 genuine Godot pixel and
12 Godot-coverage/independent-pixel fixtures; validates sorted unique records,
source-before bytes and full RGBA8 reconstruction, buffer-capacity/alias
atomicity, malicious wire rejection and two-run evidence regeneration.
The native result is **not** wired into the application: no Godot publication,
texture update, physical-device latency or memory result is claimed.
[Raw evidence](benchmarks/T068_2026-11-04_scalar_deltas.json).


### T-068 optional scalar brush GDExtension integration (2026-11-04)

The existing **on-demand** `godot-native-t068-bridge.yml` additionally links
`tools/benchmarks/t068_scalar_hard_brush.cpp` into its temporary native
library and executes `t068_scalar_sparse_smoke.gd`. Each real Godot 4.8
beta 2 run requires **31 passing scalar checks** and a fail-closed JSON
witness (63 changed records on a canonical 16² test stroke). The suite checks
Godot `DrawingEditSession.paint_path()` output before publishing sparse
records in a revision-checked document edit, then checks exact Undo/Redo,
hidden RGB, mask, erase, no-op and malformed capacity rejection. A missing,
truncated or contradictory marker fails the runner. Two-run source-pinned
[evidence](benchmarks/T068_2026-11-04_scalar_gdextension.json) is committed.

The existing fast push/PR CI step runs
`python3 -m unittest discover -s tests -p test_t068_scalar_gdextension.py`
without loading a `.gdextension`. This boundary **is not enabled in either
app**, has no physical-device GPU proof and does not certify portable native
shipping or a measured speedup. T-068 stays In Progress.


### T-068 counterbalanced native sparse brush/document publication (2026-11-04)

The on-demand `godot-native-t068-bridge.yml` runs the isolated
`t068_scalar_publication_profile.gd` under Godot 4.8b2, with six matched
32²/128²/256² 4px short/crossing workloads, two fresh-document warmups and
**six timed pairs in alternating execution order** (three per order), in
each of two independent runs. Complete canonical and native pixels, native
wire originals, one revision and Undo/Redo must match outside the measured
phases. One complete trusted Godot oracle is precomputed per workload, and
verified native bytes may only be staged after matching it. Full runs require **536 publication checks**; missing Godot markers
or error diagnostics fail the command.

Fast push CI runs `tests/test_t068_scalar_publication.py` without a native
binary. It validates source/profile digests, the pinned schema-v2 evidence,
all six raw paired samples per workload, counterbalanced order, exact paired
totals, and independently recomputed min/median/max. Tampered measurements,
missing trials and fake distributions fail closed. This is CPU-only
research; the test cannot establish physical input-to-present latency or
portable native release eligibility. No extension is loaded in the apps.


### T-068 isolated 512/1024/2048 native brush publication (2026-11-04)

A distinct `--large-only` `t068_bridge/run_bridge.py` mode builds a temporary
Godot 4.8b2/Linux GDExtension and runs
`t068_scalar_large_publication.gd`: one horizontal 4px stroke per full-size
storage tile, four alternating-order timed pairs plus a warmup, and exact
canonical whole-tile source, native wire, published pixels and Undo/Redo.
The two independent pinned runs each pass **146 checks**; oversized
`max_changes > 65536` and insufficient-capacity native requests must reject.
Fast push CI runs `test_t068_scalar_large_publication.py` without building or
loading the extension; the manual `godot-native-t068-bridge.yml` additionally
runs the two-run live check in a **separate opt-in build** and uploads JSON.
It remains a headless CPU-only comparison, not Windows/Linux physical
input-to-visible p95, hardware RAM/VRAM, application backend acceptance, or
a deployable native export. The 1024²/2048² matched native timings are slower
than canonical Godot in both pinned runs.


### T-068 native/Godot near-edge quad differential (2026-11-04)

Fast push CI runs `T068_QUAD_GODOT=godot python3 -m unittest discover -s
 tests -p test_t068_quad_differential.py`. This first regenerates the
independent Godot-authoritative 48-case four-corner scope oracle (exact
serialized mask bytes must match), then compiles the detached C++17 native
mask source with the host compiler. It validates **two reproducible runs with exact 48/48 mask parity** and
rejects evidence corruption, source changes, malformed buffers and lost
counterexample provenance. The original strict-double kernel's **247 omitted
pixels across 16 cases** remain in a separately hashed historical record.
The Godot 4.8b2-compatible native float32 segment/approximate-edge policy
is a constrained research result, not proof across precision modes,
compilers, large coordinates or arbitrary convex boundaries. The application
remains on canonical Godot masking; no extension is loaded or accepted.
Physical input-to-visible, memory and release gates remain open.

### T-068 portable Drawing release isolation gate (2026-11-04)

Fast CI's existing T-053 standalone Linux export now additionally invokes
`python3 tools/benchmarks/t068_release_gate.py --stage /tmp/drawing-dist/project
--linux /tmp/drawing-dist --launch-linux --output /tmp/t068-standalone-linux-release.json`.
The validator checks the separately exported x86_64 ELF and `Drawing.pck`,
forbids unapproved native extension/shipped-library sidecars, and launches the
binary from a fresh working directory with isolated HOME/XDG paths. It rejects
missing PCK, wrong executable architecture, nonzero exit, and Godot script
errors; separate four-test offline contracts run in the T-068 fast step.
Release templates are required for CI's actual export. On a host without them,
only the offline tests/stage checks can run: no release acceptance may be
inferred. Windows artifacts may be structurally checked with `--windows`, but
must also be launched on Windows; physical GPU and release acceptance remain
open under T-068.

## T-094 decorated/error-bearing model-log fail-closed check — 2026-11-07

`tools/check_godot_model_log.py` detects Godot `ERROR:` lines even when
terminal-color SGR escapes or indentation precede the diagnostic. After a
valid success marker, plain shell crash banners (`Segmentation fault`,
`Aborted`, `FATAL ERROR`, `CRASH`, and uncaught C++ termination text) still
fail the step. The known Godot post-exit RID/texture leak exception only
accepts the **literal** unadorned log line after one exact success marker;
there is no general relaxation for errors emitted after `*_PASSED`.

The original log content is retained for the reviewer, and the 46 required
fast-CI check IDs are unchanged. Run `python3 -m unittest
tests.test_t094_godot_model_log` or the existing T-073 required step to
exercise both positive logs and deliberate false-green controls. This check
validates log interpretation only; an actual GitHub-hosted run and physical
owner acceptance must still be obtained independently.

### T-088 sparse clipboard capture oracle — 2026-11-07

The existing required `ci_t088_selection_clipboard_model` step also runs
`drawing/tests/selection_sparse_capture_smoke.gd` with strict
`T088_SPARSE_CAPTURE_PASSED` whole-log validation. It compares the sparse
capture to an independent pixel-by-pixel oracle, tests lazy integrity/error
boundaries and signed 64-bit Atlas anchors, and detects a regression that
resolves all absent source chunks. This is a deterministic model gate, not
physical UI, GPU-performance or owner acceptance evidence. The CI inventory
remains **46 required checks**.

## T-094 shell-wrapped crash and traceback guards — 2026-11-07

The shared `check_godot_model_log.py` verifier treats shell-prefixed child
`Segmentation fault`/`Aborted` lines (including Bash line/PID prefixes and Dash
line numbers) and a Python traceback header as fatal even after a valid model
success marker. Raw and ANSI/indented variations are covered. It still counts
only the specifically named *literal* post-success Godot shutdown leak lines;
no other error is excused. The existing required T-073 Python test step carries
these regressions, without changing the 46 required check IDs. The local test
result is not hosted CI evidence or owner hardware UX approval.

### T-065 source index membership and revision directory limits — 2026-11-07

The existing required `ci_t065_asset_browser_model` and
`ci_t065_asset_transfer_model` steps run the expanded exact-source regression
fixtures. A filesystem-valid `.drawing` file added after listing must not be
read/exported via a caller-created record until refresh. Indexed records and
Atlas's subset drag tokens remain supported; the published Atlas registry is
still an independent placement authority. A directory containing 2,049
version candidates must be skipped with a warning rather than expose an
arbitrary old revision. These checks test bounded **per-revision-directory**
enumeration, not root-directory scalability or atomic no-follow POSIX file
operations. The native Atlas and standalone browser witnesses remain
on-demand, and no required CI step ID was added.


### T-065 combined root candidate budget — 2026-11-07

The existing required `ci_t065_asset_browser_model` step additionally covers
incremental `Objects/` **root** enumeration, not only revision subfolders.
The 64-check headless oracle constructs 2,048 direct entries (one source, one
folder and unrelated files), verifies a complete authorized index, then adds
a 2,049th entry and requires `ASSET_LIMIT` with the previous index unchanged.
The real browser must report the specific budget failure; removing the extra
entry and refreshing must recover. The pre-fix scanner returns a false-success
partial index on the same fixture. This is a correctness/work-bound test, not
a full real-campaign performance acceptance test. Atlas registry guards,
manual review and the 46 required CI check IDs are unchanged.

### T-065 failure-atomic 512-source index — 2026-11-08

The existing required `ci_t065_asset_browser_model` step now runs **79**
real-file model assertions. The portable index accepts exactly 512 distinct
saved Object sources, examines later candidates for duplicate IDs rather than
publishing a truncated list, and rejects a 513th unique source with
`ASSET_LIMIT` without replacing the last authorized snapshot. Both loose
`.drawing` sources and versioned `vNNNNNN.drawing` directories are exercised;
the real browser must display the limit error and preserve its previous root.
Negative controls against the original implementation fail four assertions.
This adds no required CI check ID and does not replace hosted CI, physical
keyboard/pointer testing or T-065 owner approval.

### T-094 compact Godot engine diagnostic log guard — 2026-11-08

`tools/check_godot_model_log.py` rejects the compact Godot timestamped `E`
error format (`E 0:00:00:542 ...`), even when a valid model `*_PASSED`
marker appeared earlier. ANSI and leading whitespace do not hide those engine
errors. It still permits `I`/`W` lines, explanatory prose and the **exact**
known post-exit leak messages following one success marker. This additional
verifier contract is exercised by `tests.test_t094_godot_model_log` in the
existing T-073 required workflow step. No required check ID is added; local
replay is not hosted CI or physical owner approval.


### T-095 deferred Legacy Brush staging oracle — 2026-11-09

The existing **on-demand**, non-gating `godot-native-t095-brush.yml` now runs
`drawing/tests/t095_brush_deferred_staging_smoke.gd` and checks its exact
`T095_BRUSH_DEFERRED_PASSED` success marker with the fail-closed model-log
verifier. It compares the deferred tile-local Brush/Eraser preview and commit
against the original canonical-key publisher, including mixed edit fallback,
failed lazy-source rollback, signed anchors, source identity, and Undo/Redo.
The current local oracle passes **492/492**; the updated existing Legacy
publication oracle passes **519/519**. This adds no required fast-CI check ID,
does not replace a hosted workflow result, and provides no physical GPU or
owner usability acceptance.


### T-095 deferred Brush + mixed operation rollback — 2026-11-09

After `python3 tools/build_drawing_app.py --in-place`, run:

```sh
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy \
  --path drawing --script res://tests/t095_mixed_edit_rollback_smoke.gd \
  > /tmp/t095-mixed-rollback.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t095-mixed-rollback.log \
  --marker T095_MIXED_ROLLBACK_PASSED
```

The **504/504** oracle tests four mixed APIs after an earlier deferred Brush,
with a late lazy-tile failure, rollback, retry or immediate commit, source
preview bytes, canonical before/after history and Undo/Redo at signed anchors
for two tile strides. An original-source negative control fails 96 checks.
The on-demand `godot-native-t095-brush.yml` workflow runs it through the
existing fail-closed checker after staging and import; no required fast CI
check ID is added. Native-present and fresh native-absent local runs passed.
This is transaction correctness evidence, not full hosted CI or real hardware
60px latency acceptance. T-095 remains In Progress and manual review stays
open.


### T-095 NativeHard conservative scanline oracle — 2026-11-11

The **on-demand** `godot-native-t095-brush.yml` compiles the actual Rust
GDExtension, then strictly checks `drawing/tests/t095_native_hard_scanline_smoke.gd`
with marker `T095_NATIVE_HARD_SCANLINE_PASSED` and retains its raw log.
The **42/42** native oracle checks byte-exact ordered output against the original
full-candidate rectangle for twelve signed/fractional/60px and clipped sweeps;
the high-coordinate case retains its original native witness because independent
GDScript arithmetic rounds two edge pixels differently at ~10M positions.
Rust's test suite independently compares the *exact native f32 predicate* on
these 11 fixed and 96 deterministic sampled segments (6/6 Rust tests pass).
A deliberately undersized row-bound control fails the GDExtension oracle.
An opt-in `t095_native_hard_scanline_bench.gd` times **only native coverage
and output**, not Godot staging, compositor, pointer motion or real display.
It is not included in the required 46-step fast-GDScript CI. Hosted workflow
and owner hardware acceptance remain unverified; T-095 stays In Progress.

### T-095 bounded render-frame phase instrumentation — 2026-11-11

The non-gating, on-demand `godot-native-t095-brush.yml` now runs
`drawing/tests/t095_frame_phase_window_smoke.gd` after staging the canonical
Drawing app. It requires the exact `T095_FRAME_PHASE_PASSED` marker through
the existing fail-closed `check_godot_model_log.py` tool and retains
`/tmp/t095-frame-phase.log` under `if: always()`.

The local **19/19** test covers a 1024-frame bounded ring, three wraps plus
late samples, a retained lifetime maximum for an evicted compositor outlier,
chronologically aligned five-phase CPU samples, real Canvas preview callbacks,
independent pixel/history parity, and Undo/Redo. Disabling live recording in a
temporary staged copy fails two checks. A fresh native-absent standalone import
passes. Required fast desktop check IDs and the T-094 strict log policy are
unchanged. CPU callback times **cannot prove physical input-to-photon latency**;
reference-device owner acceptance, hosted CI and T-095 manual review remain
outstanding. [Evidence](evidence/T-095-2026-11-11-frame-phase-window.md).


## T-095 Canvas post-draw callback pairing — 2026-11-11

The optional, non-gating `godot-native-t095-brush.yml` workflow now invokes
`drawing/tests/t095_frame_post_draw_pairing_smoke.gd` with the strict
`T095_POSTDRAW_PAIR_PASSED` marker and keeps
`/tmp/t095-postdraw-pairing.log` on every outcome. The **23/23** local oracle
checks matching one Godot `frame_post_draw` callback to the latest active
Canvas frame, rejecting duplicate/stale callbacks, ring-wrap corruption and
RGB/history divergence. Previous-source control fails five checks. The
five-stroke Xvfb witness emits a *matched-frame-only* callback p50/p95 and
exact retained/total count. No physical input-to-photon or owner approval is
inferred; hosted Actions were not run. The required fast-CI check IDs and
T-094 fail-closed log policy are unchanged.
[Detailed evidence](evidence/T-095-2026-11-11-postdraw-callback-pairing.md).

## T-095 changed-preview staging to Godot callback — 2026-11-11

The **on-demand**, non-gating `godot-native-t095-brush.yml` additionally runs
`drawing/tests/t095_preview_stage_postdraw_smoke.gd` and strictly requires
`T095_PREVIEW_STAGE_POSTDRAW_PASSED` through
`tools/check_godot_model_log.py`. Its raw log
`/tmp/t095-preview-stage-postdraw.log` is retained when a job fails.
The **22/22** local oracle tests only pixel-changing batch stage timestamps
correlated to Canvas `_draw` and matched `frame_post_draw` callbacks, including
no-op/unmatched frame exclusion, cancelled sessions, bounded ring rollover,
RGBA8 and Undo/Redo parity. The previous staged Canvas fails four assertions.
The pointer witness emits a changed-preview-only p50/p95 summary; unmatched
frames never masquerade as zero-delay callbacks. These observations are engine
intervals, **not physical input-to-photon**. Required fast-CI check IDs and
T-094 strict logging are unchanged; hosted Actions and owner acceptance remain
unverified. [Evidence](evidence/T-095-2026-11-11-preview-stage-postdraw.md).
