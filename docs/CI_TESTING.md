# Godot CI policy: fast desktop core and deferred compatibility coverage

**Policy (2026-11-03):** Required push/PR GDScript CI now verifies the implemented **Drawing package and shared Atlas composition foundation**. The approved complete Drawing Essential baseline remains unfinished under T-059. Windows/Linux desktop are the release-first targets. **Web export, broad native framebuffer sweeps, and historical Atlas pointer/shape tests are intentionally excluded from push CI.** They remain in source and are not claimed green.

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
