# Sprint 2026-11-15 — Implementation agent handoff

**Prepared:** 2026-11-15 · **Target:** [PR #19](https://github.com/FivePebblesGPT/DrawInAtlas/pull/19), branch `sprint/2026-11-15` · **Phase:** implementation has **not** begun for T-146–T-152 at handoff time.

> **Operating instruction:** Follow [`docs/Index.md`](Index.md), the canonical YAML frontmatter in [`docs/Tickets/`](Tickets/), and [`docs/TICKET_WORKFLOW.md`](TICKET_WORKFLOW.md). **Complete exactly one ticket per agent turn**, respecting hard dependencies and manual-review gates. Implement autonomously within approved scope; test thoroughly; update ticket, evidence and Index; commit and push the change; deliver the complete remote-relative `.lfsmbox.zst` commit diff as requested by the owner. Do **not** mark several tickets Done in a single turn.

## 1. Verified repository and PR starting point

- **Repository:** `FivePebblesGPT/DrawInAtlas`.
- **PR #18:** squashed and merged into `main`; canonical merge/squash commit **`ac59cdb8ad10a139fea154172a3f17295bec3e02`**. Do **not** rebase implementation on the old `sprint/2026-11-14` tip (`4aecce7...`) or treat its pre-squash commit count as the new history.
- **PR #19:** `sprint/2026-11-15` → `main`; initial pre-handoff branch tip **`ffd0b26ee377e509e7221c255136014d541b74c1`**, one README ALPHA-label commit above the squash. The branch may have newer handoff or implementation commits by the time the agent starts: always fetch and verify **the current remote SHA** before work.
- **Owner-approved policy:** the project is **alpha**. Breaking development-only APIs/builds during migration is acceptable. **No Legacy GDScript painting migration, compatibility shim or native-absent fallback is required.** Reproducible, verified builds and correct transaction semantics still matter for a completed ticket.
- **Branch hygiene:** never overwrite or force-push concurrent work. Use `git fetch origin`, inspect `origin/main` and `origin/sprint/2026-11-15`, and create commits on the existing PR #19 head. Record the remote head **before starting each ticket** for the final mailbox/diff. The initial reference SHA above is not a permanent base.

## 2. Architecture decisions (authoritative)

The old GDScript-first/native-optional recommendations in T-068/T-084/T-104 and T-097–T-101 are historical, source-pinned **benchmark evidence**, not the desired runtime.

| Seam | Godot / GDScript retains | Rust / existing GDExtension owns | Data crossing the boundary |
| --- | --- | --- | --- |
| **Input/control** | UI/tool state, OS pointer receipt, camera, layer/selection UI and gesture command dispatch | Unified NativeHard/Hokusai strategies, stroke lifecycle, dab/resampling, masking | **Batched** position/pressure/time samples, frozen settings, opaque stroke handles |
| **Raster edit + document** | Non-raster layer hierarchy, application metadata, source/save orchestration, history UI | Canonical tile pixel bytes, alpha blending/erase, copy-on-write edits, rollback, atomically published source, raster Undo/Redo data | Tile/transaction IDs, bounded bulk import/export, revision and authorization checks |
| **Display** | `RenderingServer`, `ImageTexture`, texture cache and pan/zoom presentation | Native dirty tile/rectangle calculation and RGBA8 tile/preview buffers | Dirty descriptors and **bounded contiguous tile bytes or handles**, **not** per-pixel coordinate/color streams |

The existing `DrawingNativeBrush` GDExtension **already contains both NativeHard and Hokusai**. Consolidate their APIs/state, not separate repositories. The preset `addons/drawing/brushes/hard_round.myb` already exists. **Hokusai is allowed to paint different pixels than Legacy/NativeHard**; its own coverage, appearance, source, preview, commit, persistence and Undo/Redo must be self-consistent.

Current document storage is commonly **256×256 sparse GDScript pixel dictionaries** (`DrawingRasterTile._pixels`) while display textures are **128×128**; those are independent tile granularities. Existing `paint_path_native_hard()` returns pixel-coordinate pairs and `paint_path_hokusai()` returns coordinate/color triples to GDScript; these hot-path transfers and per-pixel staging must disappear under T-148/T-149. Rust need not own window/UI or Godot GPU draw submission. Do not claim zero-copy texture uploads without measuring the actual Godot API.

The transaction safety checks **remain necessary** even if moved across seams: authoritative source revision, editable/living layer, stable source tile identity, valid bounded coordinates/strides/RGBA8, selection policy, and all-or-nothing cancellation/commit. Validate at **transaction/tile granularity** wherever possible, rather than constructing huge per-pixel GDScript history dictionaries. Never introduce competing native and Godot revision authorities.

## 3. Ticket order — one bounded deliverable per turn

| Order | Ticket | Canonical starting status | Dependency / deliverable |
| --- | --- | --- | --- |
| 1 | [T-146](Tickets/T-146.md) | **Ready** | 96px full-canvas **Hokusai hard-round** real-pointer performance/correctness benchmark |
| 2 | [T-147](Tickets/T-147.md) | Blocked | Depends T-146: unify NativeHard/Hokusai in one Rust stroke lifecycle/ABI |
| 3 | [T-148](Tickets/T-148.md) | Blocked | Depends T-147: native-owned raster tile store, blend/mask, atomic history/Undo |
| 4 | [T-149](Tickets/T-149.md) | Blocked | Depends T-148: Godot batched input, dirty display tiles and persistence seams |
| 5 | [T-150](Tickets/T-150.md) | Blocked | Depends T-149: delete Legacy and native-free brush fallback, remove obsolete tests/branches |
| 6 | [T-151](Tickets/T-151.md) | Blocked | Depends T-150: **reprofile new** full editor pipeline across Rust/FFI/document/Godot |
| 7 | [T-152](Tickets/T-152.md) | Blocked | Depends T-151: optimize **the measured** dominant new bottleneck |

A child becoming Done does not close its performance/UX parent. **T-095 remains In Progress, `manual_review: true`**, with the actual 60/96px reference-device responsiveness and explicit owner acceptance still outstanding. **T-096 remains Blocked, `manual_review: true`** until the T-149 selection/Move paths are revalidated, then may return to Manual Review only when evidence is ready. T-068, T-085, T-086, T-088, T-094, T-105–T-107 have post-refactor revalidation/portability/hosted-CI work. Never self-approve T-056/T-059/T-065/T-083 or privacy/player gates.

## 4. Immediate implementation turn: T-146 only

**Target:** actual Godot mouse-down/move/up **100-event**, nine alternating horizontal sweep, **96px** Brush painting on a newly created **512×512** image using the **real Rust Hokusai engine** and bundled **hard-round** MyPaint preset. This must remain Brush-driven; **do not use** `fill_rect()`, a bucket fill, synthetic final pixel writes, or a stub pretending to be the native extension.

### Code/evidence entry points

- `drawing/tests/t095_full_canvas_brush_native.gd`: source of the existing 96px/100-event nine-sweep trajectory, frame metrics and Legacy/NativeHard baseline. It currently **rejects Hokusai** and asserts **exact opaque red** on every source pixel, so do **not** simply add `Hokusai` to its backend allowlist and leave its Legacy oracle unchanged. Prefer an independent `drawing/tests/t146_hokusai_full_canvas_native.gd`, or explicitly split backend-specific correctness oracles while keeping source-identical pointer geometry.
- `drawing/tests/brush_latency_native.gd`: the existing actual **60px** Hokusai five-stroke natural-media latency witness, **not** a 96px whole-canvas comparison.
- `addons/drawing/canvas.gd`: `BUNDLED_PRESETS`, `brush_backend`, `brush_preset`, `configure_preset`, `_drain_segments`, current backend selection.
- `addons/drawing/edit_session.gd`: `paint_path_hokusai()` → native `preset_segments()`, `hokusai_perf.native_us/stage_us`, delta transfer; NativeHard's `hard_segments()` comparison.
- `addons/drawing/document.gd`, `raster_tile.gd`, `renderer.gd`: source, transaction/Undo, preview, texture and dirty-region attribution.
- Historical measured profiles: [T-095 Godot function profiler](evidence/T-095-2026-11-11-96px-godot-profiler.md), [T-101 native/Hokusai dispatch](evidence/T-101-2026-11-12-native-dispatch.md), [T-104 backend decision](evidence/T-104-2026-11-12-operation-backends.md). In prior 60px Hokusai trials native computation was roughly **14–15ms** but GDScript staging roughly **173–232ms**; this is **not** a 96px benchmark or proof of Hokusai superiority. Legacy/NativeHard historical full-canvas gesture time remained **seconds**.

### Required checks and data

1. **Native identity:** fail explicitly if `DrawingNativeBrush` is missing/incompatible, `configure_preset` fails, or the requested Hokusai backend silently selects Legacy/NativeHard. Log actual selected backend, preset settings, native build hash, Godot version, repository SHA and feature flags.
2. **Visual correctness, not cross-backend parity:** use the same source path, viewport and timing plan as T-095; report covered source-pixel count/area, alpha/opacity distribution, holes and visible framebuffer samples/image. State whether a 96px hard-round preset truly fills the canvas; if it does not, distinguish an honest failing preset from a **separately logged** calibrated preset experiment. Do not lower a threshold just to manufacture PASS. Hokusai does **not** have to reproduce opaque-red Legacy SHA-256 tiles.
3. **Transaction correctness:** one committed revision for the gesture, successful Undo/Redo and stable source/preview/framebuffer state; cancellation/rollback, source failures and signed tile/selection/mask boundaries. Preserve unchanged hidden RGBA8 bytes where applicable.
4. **Timing:** input receipt → first visible changed preview; oldest pending sample/queue depth; native dab/pigment CPU; GDExtension marshal/changed-pixel volume; GDScript stage/blend, commit/publication, preview compositor, texture upload; release → commit and input → settled postdraw; per-frame p50/p95/max; CPU/RSS and memory conditions. Separate per-stage cumulative CPU from end-to-end wall clock. `RenderingServer.frame_post_draw` **is not physical input-to-photon**.
5. **Repetition and failure accounting:** record cold and warm runs on the same pinned host/binary with independent process exits, comparable NativeHard/Legacy **reference** runs, raw logs, method of p50/p95 calculation and sample size. No successful marker counts if the Godot process later times out/crashes. Use the strict `tools/check_godot_model_log.py` marker checker. Prefer a new explicit Hokusai marker, e.g. `T146_HOKUSAI_FULL_CANVAS_PASSED`, rather than recycling the exact-red T-095 claim.
6. **Artifact:** commit benchmark harness, independent result oracle, raw-log/evidence references (and hashes as practical), commands, quantitative tables and updated T-146/Index. A failed/slow experiment still needs accurate reporting. Mark **Done** only when T-146's narrow acceptance is fully met, not merely because Hokusai renders a dab.

### Example invocation after implementing the *new* witness

The development bundle supplies Godot **4.8 beta3** and the pinned offline Rust/Hokusai workspace; locate/build the **real native release** and verify it imports successfully. The commands below are a **reproduction template**, not evidence they have already passed on PR #19:

```bash
# From repo root. Set GODOT to the actual pinned beta3 binary.
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --audio-driver Dummy --editor --path drawing --import --quit

# New T-146 witness must require actual Hokusai, not permit silent fallback.
DRAWING_BRUSH_BACKEND=Hokusai T095_FULL_CANVAS_RUNS=2 \
  timeout 120s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t146_hokusai_full_canvas_native.gd \
  > /tmp/t146-hokusai-96px.log 2>&1
godot_status=$?
test "$godot_status" -eq 0
python3 tools/check_godot_model_log.py /tmp/t146-hokusai-96px.log \
  --marker T146_HOKUSAI_FULL_CANVAS_PASSED

python3 tools/validate_ticket_store.py
```

Use the actual script/marker names written for T-146. Add only justified tests to fast/on-demand CI; do not claim GitHub-hosted green from a local test. Preserve the original T-095 Legacy/NativeHard source oracle for **historical reference until T-150**.

## 5. After T-146: engineering constraints, not premature work

**T-147:** converge the already shared Rust GDExtension into an opaque stroke handle and batch-based `begin/append/preview/commit/abort` interface. Both strategies retain their own pigment/coverage model but share transaction lifetime. No per-pixel FFI calls.

**T-148:** make Rust authoritative for canonical raster tile bytes and raster Undo. Handle native selection/masks/blending, source tile generations and atomic errors at tile/transaction boundaries. Measure sparse vs dense in-memory representation; do not assume 256 storage == 128 display stride.

**T-149:** hook that native state into Godot without materializing thousands of per-pixel dictionaries. Godot owns rendering submission; native reports changed display tiles and bulk packed data. Protect the successful T-124–T-134 queued-stroke/save/close/tab/Undo guards and existing selection/Move, text and Atlas consumers.

**T-150:** remove Legacy and native-absent paint fallback completely, including obsolete tests and dead branches; preserve generic non-Brush editing features and make missing/wrong-version native binaries **explicit errors**. Alpha breakage during transition is permitted; finished code must be testable and native-supported platforms documented.

**T-151:** remeasure the *new* architecture before declaring where CPU is spent; capture Godot/GDScript profiler, Rust native timings/allocations, per-seam bytes/call count, commit/render/frame and peak RSS. Historical T-095 values do not rank the post-refactor implementation.

**T-152:** optimize **one** measured dominant stage with a controlled negative/positive comparison and realistic whole-gesture/held-preview/Undo testing. Do not conflate native kernel microseconds with end-to-end responsiveness.

## 6. One-ticket completion / delivery protocol

- Re-fetch `origin/sprint/2026-11-15`, inspect `git status` and recorded upstream SHA; do not mistake old pre-squash PR #18 branches, archive bundles or historic docs for authoritative current source.
- Implement **one ticket** with a focused commit (Conventional Commits subject, author in owner's configured git identity; include `Co-authored-by: OpenAI Codex <codex@openai.com>`), complete reproducible tests, negative controls where appropriate, and source/command/exit/log evidence. Update the ticket's **YAML status**, checkbox/acceptance text, relevant docs and the matching `docs/Index.md` row **in the same turn**.
- Run `python3 tools/validate_ticket_store.py` before push; record strict native Godot log checks and targeted neighbor regressions. If a test/toolchain cannot run, say **which** and keep status honest. Use conditional checks rather than asserting unverified Windows/Linux or owner hardware performance.
- Create **one `.lfsmbox.zst`** with the **complete commit diff relative to the remote SHA recorded before this turn**, via the owner's supplied `git_lfs_mbox.py` workflow; screenshots are exempt from the single-file artifact constraint. The script is not tracked at `tools/git_lfs_mbox.py` at this handoff—locate the provided helper and inspect its `--help`/include-since semantics rather than assuming flags. Verify the archive exists and covers the entire requested range before linking it.
- Push the commit(s) on PR #19, confirm the final remote HEAD, attach the mailbox file to the chat, link tests/evidence, identify the **next** Ready ticket or blocker, and keep manual owner gates intact.
- Do not mark the entire sprint complete just because T-146 is Done. Do not start T-147 in the same turn: the owner requires **one ticket per turn**.

## 7. Source-of-truth links

- [Canonical Kanban](Index.md) and [native ticket audit](NATIVE_RASTER_TICKET_AUDIT_2026-11-15.md)
- [Ticket workflow and manual gates](TICKET_WORKFLOW.md)
- [T-095 owner responsiveness gate](Tickets/T-095.md) and [T-096 selection/Move owner gate](Tickets/T-096.md)
- [T-105 required-native portability](Tickets/T-105.md) and [T-094 CI/evidence](Tickets/T-094.md)
- [T-101 existing Rust/Hokusai benchmarks](evidence/T-101-2026-11-12-native-dispatch.md)
- [PR #18 squashed into main](https://github.com/FivePebblesGPT/DrawInAtlas/pull/18) and [PR #19 for this implementation sprint](https://github.com/FivePebblesGPT/DrawInAtlas/pull/19)

**Handoff status:** architecture, tickets and benchmark starting point are documented; there is **no T-146 test result, Rust refactor, Legacy removal, reference-device acceptance or new hosted CI success** claimed by this handoff.
