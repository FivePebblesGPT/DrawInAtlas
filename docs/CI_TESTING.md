# Godot CI policy: fast desktop core and deferred compatibility coverage

**Policy (2026-11-03):** Required push/PR GDScript CI now verifies the implemented **Drawing package and shared Atlas composition foundation**. The approved complete Drawing Essential baseline remains unfinished under T-059. Windows/Linux desktop are the release-first targets. **Web export, broad native framebuffer sweeps, and historical Atlas pointer/shape tests are intentionally excluded from push CI.** They remain in source and are not claimed green.

## Required CI

- Pinned Godot `4.8.0-beta2`, Git LFS checkout, explicit typing and CI order/aggregation guards.
- T-051–053 isolated Drawing contract, core, standalone consumer and Linux desktop release package.
- Main project import before GDScript tests: T-015 marker-only authoring and archived-data boundary (13/23), link/history and link form (29/55), overview (67), stale-result (27), hierarchy (44), Organization UI (84) and reference controls (17), all on the modern marker model; T-054 Drawing/Atlas history, T-058 headless text and licensed fonts, T-060 Object Assets, T-062 Object Editor, T-061 world mapping, T-055 Drawing composition, T-066 atomic campaign saves.
- T-068 safe stationary round-dab CPU shortcut: `tests/drawing_dab_geometry_smoke.gd` compares its pixels against the **original** Godot `Geometry2D` segment oracle at fractional/negative positions, tile seams and 64-bit signed anchors, including undo/redo, no-op alpha and hidden RGB (125 assertions). The large raster benchmark and 25-gesture native stress run are **targeted**, not push-gating.
- T-073 feature inventory and T-063 workspace documentation assertions.
- T-065 partial portable Object source discovery, identity/path/hash safety, search and real dock/Object Editor tab coupling (`drawing/tests/asset_browser_smoke.gd`, 37 checks). Bounded source thumbnails (`drawing/tests/asset_browser_thumbnails_smoke.gd`, 54 checks) are generated from canonical Drawing pixels, requested only for visible rows, and cached in a 24-image digest-keyed LRU. Changed/source-replaced files invalidate previews after successful publication or explicit Refresh; stale bytes fail closed. Explicit standalone portable `*.drawing` Import/Export file copies
  (`drawing/tests/asset_browser_transfer_smoke.gd`, 29 checks) reject stable-ID
  collisions, observed target overwrites, stale source bytes, and unregistered
  imports into Atlas-managed `*.atlas-object-index.json` roots. These copies do
  not register Atlas instances or create NULL repairs. The native pointer/scroll/focus and preview witness (`drawing/tests/asset_browser_native.gd`, 19 checks without optional screenshot (20 with capture)) is targeted and does not satisfy T-065 owner acceptance or Atlas NULL/drop functionality.
- T-065 Atlas-owned source safety: `tests/object_asset_repair_smoke.gd`
  (48 disk-backed checks) covers optimistic deletion confirmations,
  Remove/NULL policies, stable placement generations, explicit no-guess
  repairs and rollback. `tests/object_source_manager_smoke.gd`
  (20 checks) covers source usage and actual button/confirmation paths.
  Both run in fast push CI. The native Atlas sidebar/canvas witness
  `tests/object_source_manager_native.gd` (17 Xvfb/Mesa checks; 18 with screenshot) is targeted,
  **not** owner approval; source drag into Atlas remains unfinished.
- T-078 reusable grouped dock state model and existing shell binding (82 headless assertions).
- T-080 reusable nonmutating drag planner and transactional commit/cancel (60 fast headless assertions); actual pointer/layout behavior is verified separately by native Xvfb/Mesa evidence.
- T-081 floating group ownership, unique panel/container state, stale/invalid rollback and abandoned-empty-container handling (64 fast headless checks). Native host move/resize, focus/z-order, tab/group reorganization and HiDPI are tested separately (55 Godot 4.8 beta 2 Xvfb/Mesa checks).
- T-082 cross-container pointer dock/detach/redock transaction model and unique panel ownership (62 fast headless checks), with shared T-078–T-081 state/preview contracts. Native `drawing/tests/dock_cross_native.gd` (56 actual pointer/keyboard checks plus optional screenshot) is targeted/non-push.
- T-083 versioned `user://` dock settings, missing/renamed panel recovery, invalid/corrupt JSON fallback, exact model round-trip, and resolution adaptation (`drawing/tests/dock_persistence_smoke.gd`, **46** headless assertions) are required push CI. The actual app save/relaunch/reset/hidden-host/420px/1.5× UI witness (`drawing/tests/dock_persistence_native.gd`, **63** checks, **65** with optional screenshots via `T083_SCREENSHOTS`) remains targeted/native and **does not imply owner UX approval**.
- T-079 dock UI renders from the same model; its targeted **native** Xvfb/Mesa witness (`drawing/tests/dock_ui_native.gd`, 40 assertions) remains non-push engineering acceptance, alongside the T-063 native 75-check regression. T-080 native drag `drawing/tests/dock_reorder_native.gd` (68 assertions: press/hover/release, cancellations, hints, overflow, keyboard and viewport) and T-081 native `drawing/tests/dock_float_native.gd` (55 assertions) likewise remain targeted/non-push.
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
