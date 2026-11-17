# Ticket Kanban Index

**Current as of 2026-11-17.** This is the **authoritative active navigation**, synchronized with `docs/Tickets/T-*.md` frontmatter. The old chronological 3,119-line engineering journal is preserved at [Index-History-2026-11-15.md](Index-History-2026-11-15.md). Past narrative status or performance recommendations are source-pinned history, not present acceptance. Review [ticket workflow, prerequisites and manual gates](TICKET_WORKFLOW.md) before implementation.

**Implementation agent handoff for [Sprint 2026-11-15 / PR #19](SPRINT_2026-11-15_HANDOFF.md):** The original plan started with T-146 (real 96px Hokusai hard-round pointer benchmark). **T-146 is now Done** with [strict native X11 benchmark evidence](evidence/T-146-2026-11-15-hokusai-benchmark.md). T-147 has also completed its single native stroke ABI. **T-153 Done (2026-11-16): NativeHard deleted; Brush/Eraser now always use Hokusai presets, including Hard Round.** **T-148 is In Progress:** native tile storage, atomic brush transactions, the production Canvas tile-only Brush/Eraser path and **per-document persistent tile/history ownership**, plus **bounded atomic import of ordinary external raster edits**, pass real graphical/headless tests. **T-148 remains open:** checked revision bridges now preserve native brush history through layer/semantic-object edits and structural removal/restore of semantic trees, never-imported raster layers **and now locally recorded native-owned raster subtrees**, plus source-preserving **detached subtree imports and text-to-raster conversion** when their raster IDs are new to Rust. Unrecorded native-owned removals now use checked selective retirement; Atlas global native Brush commands retain their tile snapshots and Rust history tokens through Undo/Redo, and a real native-authored Atlas campaign generation Save/Open is verified. A real native-authored Object Editor draft now passes Save, Save As, linked-instance rendering, registry reload and portable Object export regression. History replay now rejects reentrant lazy-source revision, permission and source-identity changes before Rust Undo/Redo or detached publication; **Rust also verifies the complete native-token before/after RGBA8 payload before replay**; in-sync detached replay now applies source tiles atomically in Rust and invalidates obsolete native tokens, while absent/stale native stores still use a Godot snapshot fallback; remaining Object/Atlas raster producers and universal revision ownership remain open. **T-154 Done:** previously painted text/raster Undo/Redo now parks and restores native-owned glyph tiles and retains unrelated Rust Undo/Redo tokens with checked snapshot parity. **T-155 Done:** semantic edits followed by re-rasterization now selectively replace parked native glyph sources while retaining unrelated Rust Ink/Undo authority. **T-156 Done:** older pixel-map local/Atlas Undo/Redo now uses checked native whole-tile replay once Rust is attached; the broader host-owned history gate remains. Finish universal authority before opening T-149; see [mixed raster evidence](evidence/T-148-2026-11-15-mixed-raster.md) and [semantic subtree evidence](evidence/T-148-2026-11-15-semantic-subtrees.md), [unreferenced raster evidence](evidence/T-148-2026-11-15-unreferenced-raster.md) and [native-owned subtree evidence](evidence/T-148-2026-11-15-parked-subtrees.md) and [import bridge evidence](evidence/T-148-2026-11-15-import-subtree.md) and [text conversion evidence](evidence/T-148-2026-11-15-text-raster.md).

**Toolchain implementation T-180:** [System/native GUI, cold offline and identical Arch/Ubuntu bundle builds](evidence/T-180-2026-11-17-local-validation.md) pass; artifact is 251.281285 MiB, zstd-19, internal checksums, no repository or external sidecar. The dedicated hosted toolchain workflow is **green**. **In Progress:** four retained desktop native-transition/export failures (42/46). The upload cap is 500 MiB. T-148/T-149 dependency gates and T-095/T-105 manual/portability acceptance remain open.

**Sprint 2026-11-17:** PR #20 was squash-merged into `main` at
`8f45f1a84bcc28b87d1b50f4bacfa173de653733`; continue on `sprint/2026-11-17`.
New owner testing reports mismatched preset hardness, requests a separate visual
brush/parameter panel, and observes roughly 12 FPS while drawing. [T-183](Tickets/T-183.md) is Done (preset edge/opacity behavior corrected and
profiled); [T-184](Tickets/T-184.md) is Done (native-backed visual Brushes dock);
[T-185](Tickets/T-185.md) is Done: [four valid full-workspace native X11
processes (32 gestures), two retained incomplete exits, frame p95/long-frame
and 100-event rapid fill baselines](evidence/T-185-2026-11-17-current-workspace-profile.md).
[T-186](Tickets/T-186.md) is now Ready for one measured and falsifiable
optimization toward a declared 250ms benchmark milestone
and 200ms stretch. "Seems usable" is not final physical acceptance.

## Current alpha architecture — Rust-owned raster

**Owner decision (updated 2026-11-16):** keep the completed 96px Hokusai hard-round benchmark as the baseline, **remove NativeHard entirely** under T-153, and use Hokusai/libmypaint presets as the **only** native Brush/Eraser rasterizer in the existing Rust GDExtension, move canonical raster tiles, blending, masks, staging, rollback and undo data **out of GDScript**, connect Godot through **batched stroke commands → native-owned dirty tile/byte buffers**, and **delete Legacy** (no compatibility, native-free fallback or migration required in alpha). Godot retains workspace, tools/input reception, layer/metadata UI and GPU texture submission; Rust owns painting. Hokusai is **not required to match Legacy pixel geometry**. Only after retiring Legacy should the new pipeline be reprofiled and its measured dominant bottleneck optimized.

**Do not close the integration/acceptance parents** T-095 (physical 60/96px Brush responsiveness and explicit owner approval), T-068 (native portability and measured full-editor throughput), T-086 (hardware viewport performance), T-088/T-096 (selection/Move acceptance), or T-094 (hosted CI and owner matrix) solely from a passing refactor. Completion of T-104 or the historic 46-step tests never restores GDScript as the target backend.

**T-153 complete:** [Hokusai-only Brush](Tickets/T-153.md) verified; [execution evidence](evidence/T-153-2026-11-16-hokusai-only.md). The next dependency-ordered work is continuing T-148, not a new ticket in this turn. T-148 remains In Progress for universal native tile/history authority; T-154 preserves previous text/raster Undo/Redo, T-155 selectively replaces obsolete parked glyph sources on a new text conversion, T-156 replays previously host-owned pixel-map commands via checked native tiles once Rust is attached, T-157 guards lazy materialization against reentrant source replacement, and T-158 rejects unsafe signed lazy/manifest tile coordinates before persistence. T-159 closes the signed-overflow validation in native publication and pixel/native history replay; T-160 also rejects unsafe *direct* pixel/tile edits once Rust is attached, without breaking legacy non-native signed-64-bit fixtures. T-161 closes the remaining `abs(INT64_MIN)` and pre-addition overflow holes at public gesture, viewport and image-import anchors; historical ±2^60 endpoints are unchanged. T-162 keeps direct raster edits with `record_history=false` native-authoritative when Rust is already attached, without inventing Undo tokens. T-163 rejects overflowing clipboard capture rectangles before materializing any source. T-164 rejects image imports whose last pixel crosses the public signed document boundary, before creating an edit transaction. T-165 prevents any direct pixel/tile publisher from bypassing a divergent attached Rust revision, including reentrant lazy fetches; explicit rebase remains a separate recovery step. T-166 now rejects manifest export and save acknowledgements when authorized Godot tile bytes or the attached Rust revision differ, without silently certifying stale pixels. T-167 extends the same checked boundary to the low-level dirty save snapshot, returning an explicit `DrawingResult` rather than exposing unchecked tile bytes. T-168 now rejects native-owned raster subtree deletion before mutating Godot when Rust refuses the parked, retired or unreferenced revision bridge. T-169 also rejects raster subtree import before Godot publication if the attached native revision or bounded unreferenced-layer bridge fails; no more silent Godot-only fallback for busy, ahead or oversized native imports. T-170 now preflights the *source* native retirement and exact RGBA8 before either cross-document move implementation publishes the destination, preventing ordinary busy/stale-source half-moves. T-171 now fences direct detached subtree export and Copy (standalone or Atlas) against stale attached native revisions and in-place source bytes, including lazy callback mutation. T-174 now makes public object add/move, semantic text commits and density updates fail closed before native-attached metadata rejection. T-177 now makes local raster-bearing structural Undo/Redo acquire a checked parked/unreferenced Rust revision before mutating the Godot tree, rejecting busy/stale or retained-source replays atomically. T-178 now also acquires checked native metadata before semantic text-history Undo/Redo, rejecting busy and stale stores without detaching canonical raster source. T-178 now also acquires the checked native metadata revision before local semantic text creation/edit Undo/Redo, preserving Rust source and the local history cursor on rejection. T-179 now also rejects semantic-only subtree deletion **before Godot erasure** if the attached Rust metadata revision is busy or divergent, preserving native history across recorded, unrecorded and host-owned removals. The rest of the native migration is sequenced by hard dependencies. See [architecture and ticket audit](NATIVE_RASTER_TICKET_AUDIT_2026-11-15.md) for which previous recommendations were superseded.

## 1. Native raster execution (critical path)

Statuses: T-146 and T-147 **Done**; T-153 **Done** and required before T-148 can close; T-148 **In Progress** (native tile/history authority still incomplete); T-149–T-152 **Blocked** by dependencies. No manual-review gate is imposed on engineering refactors; owner physical UX review stays with T-095.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-146 · 96px Hokusai hard-round full-canvas pointer benchmark](Tickets/T-146.md) | Done | [12 process / 15 gesture native X11 evidence](evidence/T-146-2026-11-15-hokusai-benchmark.md); translucent full-source coverage; T-095 gate remains | [T-097](Tickets/T-097.md), [T-101](Tickets/T-101.md) |
| [T-147 · Unify NativeHard and Hokusai behind one native stroke engine](Tickets/T-147.md) | Done | [One v1 stroke ABI and real native rollback/FFI evidence](evidence/T-147-2026-11-15-unified-stroke.md); native tile contract documented | [T-146](Tickets/T-146.md) |
| [T-153 · Retire NativeHard; use Hokusai for every Brush preset](Tickets/T-153.md) | Done | [Hokusai-only release, ABI, 96px graphical and Object/Atlas regression evidence](evidence/T-153-2026-11-16-hokusai-only.md); T-095 hardware gate remains | [T-147](Tickets/T-147.md) |
| [T-154 · Preserve native history through text-to-raster Undo/Redo](Tickets/T-154.md) | Done | [Checked native parking, exact RGBA8 retry and Save/Open evidence](evidence/T-154-2026-11-16-text-raster-parking.md); T-148 remains open | [T-147](Tickets/T-147.md), [T-153](Tickets/T-153.md) |
| [T-155 · Atomically replace parked text-derived native raster source](Tickets/T-155.md) | Done | [32-check rerasterization, selective retirement, fail-first and native/Atlas/Object evidence](evidence/T-155-2026-11-16-reraster.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-154](Tickets/T-154.md) |
| [T-156 · Replay historical pixel-map history through native tiles](Tickets/T-156.md) | Done | [37-check local/Atlas history replay, fail-first and graphical evidence](evidence/T-156-2026-11-16-legacy-pixel-native.md); general native authority remains T-148 | [T-153](Tickets/T-153.md) |
| [T-157 · Reject stale and reentrant lazy raster sources](Tickets/T-157.md) | Done | [23-check native authority, fail-first and root lazy source regressions](evidence/T-157-2026-11-16-lazy-guard.md); T-148 remains open | [T-153](Tickets/T-153.md) |
| [T-158 · Bound signed lazy raster tiles before persistence](Tickets/T-158.md) | Done | [24-check signed source/.drawing, fail-first and native/Atlas/X11 regressions](evidence/T-158-2026-11-16-tile-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md) |
| [T-159 · Reject signed 64-bit extremes in native publication and history replay](Tickets/T-159.md) | Done | [Real Hokusai replay/publication boundary regression](evidence/T-159-2026-11-16-replay-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-158](Tickets/T-158.md) |
| [T-160 · Guard native-attached direct pixel/tile publication bounds](Tickets/T-160.md) | Done | [46-check source/history/Save/Open regression and fail-first control](evidence/T-160-2026-11-16-direct-publish-bounds.md); non-native historical range unchanged; T-148 remains open | [T-153](Tickets/T-153.md), [T-159](Tickets/T-159.md) |
| [T-161 · Reject signed public gesture, viewport and image anchors](Tickets/T-161.md) | Done | [47-check native anchor regression and 7-failure pre-fix control](evidence/T-161-2026-11-16-public-anchors.md); historical ±2^60 endpoints retained; T-148 remains open | [T-153](Tickets/T-153.md), [T-159](Tickets/T-159.md) |
| [T-162 · Keep untracked direct raster edits native-authoritative](Tickets/T-162.md) | Done | [25-check mixed pixel/tile native source, Hokusai history and Save/Open regression](evidence/T-162-2026-11-16-untracked-native.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-160](Tickets/T-160.md) |
| [T-163 · Guard signed clipboard capture rectangle bounds](Tickets/T-163.md) | Done | [34-check fail-first/native/lazy source regression](evidence/T-163-2026-11-16-clipboard-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-161](Tickets/T-161.md) |
| [T-164 · Guard full signed image-import extents](Tickets/T-164.md) | Done | [26-check fail-first/native/import-endpoint regression](evidence/T-164-2026-11-16-image-extents.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-161](Tickets/T-161.md) |
| [T-165 · Fail closed on divergent attached-native direct publication](Tickets/T-165.md) | Done | [51-check Hokusai/native reentrancy and revision-fence witness with 18-failure pre-fix control](evidence/T-165-2026-11-16-attached-revision-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-162](Tickets/T-162.md) |
| [T-166 · Reject unauthorized native save projections](Tickets/T-166.md) | Done | [24-check Hokusai/Rust source-byte and revision-fence witness with fail-first control](evidence/T-166-2026-11-16-native-save-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-165](Tickets/T-165.md) |
| [T-167 · Check native authority before dirty raster snapshots](Tickets/T-167.md) | Done | [25-check native dirty snapshot and 11-failure pre-fix control](evidence/T-167-2026-11-16-checked-dirty-snapshot.md); T-148 host history gate remains open | [T-153](Tickets/T-153.md), [T-166](Tickets/T-166.md) |
| [T-168 · Fail closed on rejected native raster subtree removal](Tickets/T-168.md) | Done | [30-check Hokusai-native subtree removal fence, 19-failure pre-fix control](evidence/T-168-2026-11-16-native-subtree-removal.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-154](Tickets/T-154.md) |
| [T-169 · Fail closed on rejected native-attached raster subtree import](Tickets/T-169.md) | Done | [Native revision/busy/129-ID fail-first and retry witness](evidence/T-169-2026-11-16-native-import-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-168](Tickets/T-168.md) |
| [T-170 · Preflight source native retirement before cross-document raster moves](Tickets/T-170.md) | Done | [30-check native/Atlas transfer and 9-failure pre-fix control](evidence/T-170-2026-11-16-transfer-preflight.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-168](Tickets/T-168.md), [T-169](Tickets/T-169.md) |
| [T-171 · Reject unauthorized native-owned detached raster subtree exports](Tickets/T-171.md) | Done | [33-check direct/Copy/Atlas native source fence, 11-failure control, and Rust/X11 matrix](evidence/T-171-2026-11-16-native-export-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-166](Tickets/T-166.md), [T-170](Tickets/T-170.md) |
| [T-172 · Preflight target-native retirement before Atlas transfer Undo](Tickets/T-172.md) | Done | [30-check Atlas Move/Copy Undo and native-ahead regression with four-failure pre-fix control](evidence/T-172-2026-11-16-atlas-undo-preflight.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-170](Tickets/T-170.md) |
| [T-173 · Fail closed on rejected native-attached public layer metadata revisions](Tickets/T-173.md) | Done | [31-check Hokusai/Rust busy/native-ahead metadata guard; 22-failure pre-fix control](evidence/T-173-2026-11-16-native-layer-metadata.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-165](Tickets/T-165.md) |
| [T-174 · Fail closed on rejected native semantic/density revisions](Tickets/T-174.md) | Done | [48-check semantic/native history and density fail-first witness](evidence/T-174-2026-11-16-native-semantic-preflight.md); T-148 stays open | [T-173](Tickets/T-173.md), [T-165](Tickets/T-165.md) |
| [T-175 · Fail closed on rejected native semantic-only subtree imports](Tickets/T-175.md) | Done | [27-check Hokusai/native semantic Copy, 13-failure control and 29-run matrix](evidence/T-175-2026-11-16-semantic-import-fence.md); T-148 stays open | [T-174](Tickets/T-174.md), [T-169](Tickets/T-169.md) |
| [T-176 · Fail closed on rejected native semantic structural Undo/Redo](Tickets/T-176.md) | Done | [121-check native semantic history replay, 25-failure pre-fix control and Rust/Atlas/X11 matrix](evidence/T-176-2026-11-16-semantic-history.md); T-148 stays open | [T-173](Tickets/T-173.md) |
| [T-177 · Fail closed on rejected native raster structural Undo/Redo](Tickets/T-177.md) | Done | [89-check native raster-history, fail-first and Rust/Atlas/X11 regression](evidence/T-177-2026-11-16-raster-history.md); T-148 remains open | [T-176](Tickets/T-176.md), [T-168](Tickets/T-168.md) |
| [T-178 · Fail closed on rejected native semantic text Undo/Redo](Tickets/T-178.md) | Done | [43-check native text history, 21-failure pre-fix control and Rust/Atlas/X11 regression](evidence/T-178-2026-11-16-text-history.md); T-148 stays open | [T-174](Tickets/T-174.md), [T-176](Tickets/T-176.md) |
| [T-179 · Fail closed on rejected native semantic-only subtree removal](Tickets/T-179.md) | Done | [62-check busy/ahead native semantic removal, local/host history retry and Hokusai evidence](evidence/T-179-2026-11-16-semantic-removal.md); T-148 stays open | [T-173](Tickets/T-173.md), [T-176](Tickets/T-176.md) |
| [T-148 · Native-owned tiled raster editing and atomic undo transactions](Tickets/T-148.md) | In Progress | [Atlas native history](evidence/T-148-2026-11-15-atlas-native-history.md), [Object-native Save/Save As](evidence/T-148-2026-11-15-object-native.md), [reentrant history replay](evidence/T-148-2026-11-16-native-history-replay.md) and [atomic native payload parity](evidence/T-148-2026-11-16-native-history-payload.md) and [detached native replay](evidence/T-148-2026-11-16-detached-native-replay.md) with [absent/stale-store bootstrap](evidence/T-148-2026-11-16-detached-bootstrap.md) verified; next: host-owned detached timeline and remaining raster producers | [T-147](Tickets/T-147.md), [T-153](Tickets/T-153.md) |
| [T-149 · Godot native dirty-tile preview, display and persistence seams](Tickets/T-149.md) | Blocked | After T-148: batched Godot inputs and native dirty-tile display/save seams | [T-148](Tickets/T-148.md) |
| [T-150 · Remove Legacy Brush backend and compatibility paths](Tickets/T-150.md) | Blocked | After T-149: retire Legacy without migration or native-free fallback | [T-149](Tickets/T-149.md) |
| [T-151 · Profile post-consolidation native Brush critical path](Tickets/T-151.md) | Blocked | After T-150: profile the consolidated full editor and all native seams | [T-150](Tickets/T-150.md) |
| [T-152 · Optimize the highest measured native Brush bottleneck](Tickets/T-152.md) | Blocked | After T-151: optimize one evidenced latency bottleneck | [T-151](Tickets/T-151.md) |

## 2. Active performance, application and CI work

These tracks may progress independently where possible, but their final acceptance must exercise the new native tile/store seam.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md), [T-108](Tickets/T-108.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | In Progress | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md), [T-109](Tickets/T-109.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | Rust-first direction; T-105 portability and post-consolidation profiling | [T-052](Tickets/T-052.md), [T-104](Tickets/T-104.md), [T-105](Tickets/T-105.md), [T-151](Tickets/T-151.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | In Progress | Completed scope; see ticket evidence | [T-082](Tickets/T-082.md) |
| [T-085 · Real-time strokes and smooth input](Tickets/T-085.md) | In Progress | Retest batched native input, held preview and cancellation | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-086 · Incremental viewport cache and zoom](Tickets/T-086.md) | In Progress | Native dirty-tile display + physical dense zoom acceptance | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md), [T-149](Tickets/T-149.md) |
| [T-087 · Visible image edge, transparency and grid](Tickets/T-087.md) | In Progress | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-088 · Selection masks, clipboard and Move](Tickets/T-088.md) | In Progress | Native selection/mask seam; clipboard and Move remain | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-090 · Responsive UI, menu, tabs and brush wheel](Tickets/T-090.md) | In Progress | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-091 · Single-group floating dock and width recovery](Tickets/T-091.md) | In Progress | Completed scope; see ticket evidence | [T-082](Tickets/T-082.md) |
| [T-092 · Compact Colors and History preferences](Tickets/T-092.md) | In Progress | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-094 · Restore CI and owner acceptance evidence](Tickets/T-094.md) | In Progress | Required-native hosted CI and independent owner evidence | [T-053](Tickets/T-053.md), [T-055](Tickets/T-055.md), [T-063](Tickets/T-063.md), [T-106](Tickets/T-106.md), [T-107](Tickets/T-107.md), [T-150](Tickets/T-150.md) |
| [T-095 · Eliminate 60px Brush latency](Tickets/T-095.md) | In Progress | After T-152: reference-device 60/96px responsiveness and owner signoff | [T-053](Tickets/T-053.md), [T-098](Tickets/T-098.md), [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md), [T-152](Tickets/T-152.md) |
| [T-180 · Rebuildable offline toolchain and Make-first Drawing launch](Tickets/T-180.md) | In Progress | [Identical 251 MiB Arch/Ubuntu builds and hosted cold-native workflow](evidence/T-180-2026-11-17-local-validation.md) pass; four desktop/native-transition/export failures remain | [T-153](Tickets/T-153.md) |
| [T-183 · Correct native preset identity and edge behavior](Tickets/T-183.md) | Done | [189-check native workspace/GUI profiles and fresh old/new 96px performance baseline](evidence/T-183-2026-11-17-native-preset-audit.md); tooltips and source presets corrected, no owner hardware claim | [T-153](Tickets/T-153.md), [T-182](Tickets/T-182.md) |
| [T-184 · Separate visual Brushes panel and parameters](Tickets/T-184.md) | Done | [Native Hokusai previews, 132 UI/pixel checks, frozen gesture and floating layout evidence](evidence/T-184-2026-11-17-brush-panel.md); owner UX gates remain open | [T-182](Tickets/T-182.md) |
| [T-185 · Re-profile current Drawing frame drops and native path](Tickets/T-185.md) | Done | [Four complete software-X11 processes, 32 scenarios, two unverified exits, 54% p95 118ms cold frames; T-146 rapid p50 654ms cold / 680ms warm, composition dominant](evidence/T-185-2026-11-17-current-workspace-profile.md) | [T-146](Tickets/T-146.md), [T-181](Tickets/T-181.md) |
| [T-105 · Portable native candidate builds and process-memory evidence](Tickets/T-105.md) | In Progress | Required-native Linux/Windows builds, exports and process/VRAM evidence | [T-052](Tickets/T-052.md), [T-150](Tickets/T-150.md) |
| [T-106 · Restore green required fast-desktop GitHub CI](Tickets/T-106.md) | In Progress | Fresh post-Legacy required-native CI inventory + hosted green | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-107 · Hosted CI replay and 23-finding owner-evidence matrix](Tickets/T-107.md) | In Progress | New hosted replay and 23-finding owner matrix; preserve historic 46 | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-108 · Nested Object Save As link-vs-copy policy and safe export](Tickets/T-108.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |

## 3. Owner decisions and independent manual review

Do **not** infer signoff from software tests or prior product scope. T-096 was moved to Blocked until T-149 native-tile revalidation restores review readiness.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Manual Review | Completed scope; see ticket evidence | — |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | Completed scope; see ticket evidence | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Manual Review | Completed scope; see ticket evidence | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md) |

## 4. Other ready backlog

Other feature/product tickets remain valid; no unrelated approval is assumed.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Ready | Completed scope; see ticket evidence | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Ready | Completed scope; see ticket evidence | — |
| [T-024 · Line](Tickets/T-024.md) | Ready | Completed scope; see ticket evidence | — |
| [T-025 · Polygon](Tickets/T-025.md) | Ready | Completed scope; see ticket evidence | — |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Ready | Completed scope; see ticket evidence | — |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Ready | Completed scope; see ticket evidence | — |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Ready | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Ready | Completed scope; see ticket evidence | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |

## 5. Blocked by dependencies or future owner review

T-096 is blocked on T-149 because the pending native source/preview path would invalidate review evidence from the previous implementation.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | Completed scope; see ticket evidence | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | Completed scope; see ticket evidence | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md) |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Completed scope; see ticket evidence | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | Completed scope; see ticket evidence | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md) |
| [T-096 · Accurate selection contours and responsive Move](Tickets/T-096.md) | Blocked | Native source/Move revalidation before physical owner review | [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-186 · Profile-led optimization toward 250ms / 200ms](Tickets/T-186.md) | Ready | [T-185 measured composition/refresh as first falsifiable candidate](evidence/T-185-2026-11-17-current-workspace-profile.md); target not met; preserve T-181 warm visibility | [T-185](Tickets/T-185.md) |

## 6. Previously completed, retained as historical evidence

**Done is historical delivery, not an endorsement of the old architecture.** T-084, T-097–T-101 and T-104 are valid completed research/implementation records but their optional-native/GDScript-default and Legacy pixel-parity recommendations are superseded. T-102/T-103 and T-124–T-145 retain useful tests and user-facing behavior; T-149/T-150 must adapt relevant tests rather than ship obsolete fallback code.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | Completed scope; see ticket evidence | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | Completed scope; see ticket evidence | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | Completed scope; see ticket evidence | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | Completed scope; see ticket evidence | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | Completed scope; see ticket evidence | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | Completed scope; see ticket evidence | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | Completed scope; see ticket evidence | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | Completed scope; see ticket evidence | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | Completed scope; see ticket evidence | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | Completed scope; see ticket evidence | — |
| [T-022 · Move](Tickets/T-022.md) | Done | Completed scope; see ticket evidence | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | Completed scope; see ticket evidence | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | Completed scope; see ticket evidence | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | Completed scope; see ticket evidence | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | Completed scope; see ticket evidence | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | Completed scope; see ticket evidence | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | Completed scope; see ticket evidence | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | Completed scope; see ticket evidence | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | Completed scope; see ticket evidence | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | Completed scope; see ticket evidence | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | Completed scope; see ticket evidence | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | Completed scope; see ticket evidence | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | Completed scope; see ticket evidence | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | Completed scope; see ticket evidence | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | Completed scope; see ticket evidence | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | Completed scope; see ticket evidence | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | Completed scope; see ticket evidence | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | Completed scope; see ticket evidence | [T-079](Tickets/T-079.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | Completed scope; see ticket evidence | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | Completed scope; see ticket evidence | [T-081](Tickets/T-081.md) |
| [T-084 · Scout PhotoCraft live-paint pipeline](Tickets/T-084.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-052](Tickets/T-052.md) |
| [T-089 · Layer hierarchy, row eye/lock and undo](Tickets/T-089.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-093 · Discoverable Object source/open workflows](Tickets/T-093.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-097 · 96px full-canvas Brush correctness and profiling baseline](Tickets/T-097.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-053](Tickets/T-053.md) |
| [T-098 · Incremental detached Brush preview compositing](Tickets/T-098.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-099 · Frame-safe Brush input draining and held-preview scheduling](Tickets/T-099.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-100 · Bounded sparse atomic Brush publication and Undo](Tickets/T-100.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-101 · Optional NativeHard and Hokusai end-to-end throughput](Tickets/T-101.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-102 · Cold dense viewport first-population performance](Tickets/T-102.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-103 · Zoom-out, cache-budget and large-layer viewport stress](Tickets/T-103.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-104 · Operation-specific native raster backend decision](Tickets/T-104.md) | Done | Historical backend research; 2026-11-12 GDScript-default choice superseded | [T-052](Tickets/T-052.md), [T-097](Tickets/T-097.md) |
| [T-109 · Production-scale Asset Browser and filesystem hardening](Tickets/T-109.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-110 · Byte-exact UTF-8 authorization for portable Object sources](Tickets/T-110.md) | Done | Completed scope; see ticket evidence | [T-109](Tickets/T-109.md) |
| [T-111 · Line release target identity and layer eligibility](Tickets/T-111.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-112 · Atlas Line/Polygon portable Save/Open regression](Tickets/T-112.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-113 · Bucket same-ID map/floor release authorization](Tickets/T-113.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-114 · Polygon registered campaign/map/floor authorization](Tickets/T-114.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-115 · Text modal registered campaign/map/floor authorization](Tickets/T-115.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-116 · Atlas Text portable Save/Open regression](Tickets/T-116.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-117 · Wall Path registered campaign/map/floor authorization](Tickets/T-117.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-118 · Wall Path portable Save/Open and mask-context regression](Tickets/T-118.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md), [T-117](Tickets/T-117.md) |
| [T-119 · GM Token registered source authorization](Tickets/T-119.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-120 · Conventional File/Object menus and unified Open](Tickets/T-120.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-093](Tickets/T-093.md) |
| [T-121 · Single-snapshot bounded raster Open](Tickets/T-121.md) | Done | Completed scope; see ticket evidence | [T-120](Tickets/T-120.md) |
| [T-122 · Historical T-107 CI replay source integrity](Tickets/T-122.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-123 · Predecode bounded PNG/WebP/JPEG geometry](Tickets/T-123.md) | Done | Completed scope; see ticket evidence | [T-121](Tickets/T-121.md) |
| [T-124 · Ordered queued Brush/Eraser during release drain](Tickets/T-124.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md) |
| [T-125 · Block stale Save/Close of pending Brush edits](Tickets/T-125.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-124](Tickets/T-124.md) |
| [T-126 · Guard pending Brush edits against document switches](Tickets/T-126.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md) |
| [T-127 · Guard Undo/Redo against pending Brush revision conflict](Tickets/T-127.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md), [T-126](Tickets/T-126.md) |
| [T-128 · Guard History list jumps during pending Brush drain](Tickets/T-128.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-127](Tickets/T-127.md) |
| [T-129 · Guard concurrent layer and clipboard edits during Brush drain](Tickets/T-129.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-128](Tickets/T-128.md) |
| [T-130 · Guard selection and frame source context during Brush drain](Tickets/T-130.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-129](Tickets/T-129.md) |
| [T-131 · Preserve Object rename and variant metadata on rejected publication](Tickets/T-131.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md) |
| [T-132 · Bind asynchronous Save As to its originating document](Tickets/T-132.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-131](Tickets/T-131.md) |
| [T-133 · Guard standalone OS window-close against unsaved state](Tickets/T-133.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md), [T-132](Tickets/T-132.md) |
| [T-134 · Bind authoring dialogs to originating document and layer](Tickets/T-134.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-132](Tickets/T-132.md) |
| [T-135 · Sparse indexed committed viewport traversal](Tickets/T-135.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md) |
| [T-136 · Indexed detached-preview plus committed sparse traversal](Tickets/T-136.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-135](Tickets/T-135.md) |
| [T-137 · Bounded cold detached-preview population](Tickets/T-137.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-136](Tickets/T-136.md) |
| [T-138 · Over-budget detached-preview focal retention](Tickets/T-138.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-103](Tickets/T-103.md), [T-136](Tickets/T-136.md) |
| [T-139 · Bounded sparse explicit-mask selection outlines](Tickets/T-139.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-140 · Focal-first over-budget selection outlines](Tickets/T-140.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md) |
| [T-141 · Occupied sparse-mask overflow outlines](Tickets/T-141.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md), [T-140](Tickets/T-140.md) |
| [T-142 · Preserve overlapping contour tiles after an in-window pan](Tickets/T-142.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-140](Tickets/T-140.md), [T-141](Tickets/T-141.md) |
| [T-143 · Reconcile saturated contour cache for sub-tile clipped pans](Tickets/T-143.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md) |
| [T-144 · Reuse bounded outline candidate plans across deferred frames](Tickets/T-144.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-141](Tickets/T-141.md), [T-143](Tickets/T-143.md) |
| [T-145 · Retain eligible contours across shifted selection tile windows](Tickets/T-145.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md), [T-143](Tickets/T-143.md), [T-144](Tickets/T-144.md) |
| [T-181 · Keep native preview display tiles visible during movement](Tickets/T-181.md) | Done | [19-check fail-first/green framebuffer and hosted Xvfb evidence](evidence/T-181-T-182-2026-11-17-preview-and-presets.md); cold-cache neighbors pass; T-095/T-149 remain open | [T-153](Tickets/T-153.md) |
| [T-182 · Expose native brush preset controls](Tickets/T-182.md) | Done | [Hard Round/Soft/Ink/Airbrush, 96px UI, 16 native-control and 75 compact-workspace checks](evidence/T-181-T-182-2026-11-17-preview-and-presets.md); hosted cold checks pass | [T-153](Tickets/T-153.md) |

## 7. Archived work

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | Completed scope; see ticket evidence | — |


## Maintenance and proof

Ticket state/dependencies live in YAML frontmatter. Add each ticket exactly once to this Index; update it whenever status or dependency changes and run `python3 tools/validate_ticket_store.py`. A manual gate cannot be self-approved; an archived or superseded recommendation is not a completed native implementation. Historical T-107/T-122 46-check replay must remain pinned to its original workflow, while new T-106/T-107 required-native CI must report its real contemporary check inventory.
