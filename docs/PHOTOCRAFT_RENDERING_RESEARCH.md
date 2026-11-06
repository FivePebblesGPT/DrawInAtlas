# PhotoCraft real-time painting pipeline: source-level investigation and DrawInAtlas adaptation

**Investigated:** 2026-11-05  
**Reference:** `storytold/photocraft`, `main` at **`0a9717fa64a62376721ef43400125c5e6eb65862`**  
**Target:** `FivePebblesGPT/DrawInAtlas`, `aidev` at **`4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c`**  
**Evidence method:** source files and recursive repository trees retrieved from GitHub at the pinned commits; PhotoCraft's [`AGENTS.md`](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/AGENTS.md), [`docs/architecture.md`](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/docs/architecture.md) and [`docs/development.md`](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/docs/development.md) were inspected before implementation tracing. **No repository was modified.** A local `git clone` was attempted but blocked by container DNS/network restrictions; the source itself was inspected through the GitHub connector, not a successfully cloned worktree. There was no local Godot, Rust, or C++ toolchain available for running the applications. Consequently, no new runtime measurements are claimed here.

**Evidence labels:** **Verified** = implementation call path at pinned source; **Recorded** = pre-existing benchmark/result stored in the target repository, not reproduced in this investigation; **Inference** = analysis of observed code; **Proposal** = unimplemented design; **Unverified** = requires runtime evidence. Link fragments `#Lx-Ly` in this report refer to the stated immutable commit.

## 1. Executive summary

**PhotoCraft does not depend on GPU-side brush rasterization to make a stroke appear before mouse release.** On press, its Rust brush engine creates a *copy-on-write preview document* and a sparse, **64×64 coverage-tile** stroke renderer. On input, it adds brush dabs on the CPU, composites **only dirty stroke tiles** against the original target surface into that preview document, and gives the preview to the ordinary canvas compositor. That compositor caches GPU layer pages and the final display texture, refreshing damaged regions instead of the full view. The first stationary point is explicitly handled by a temporary “finish-now” tail preview. On release, matching command, revision, seed, parameters, and points allow the committed transaction to **adopt already-rendered pixels**, avoiding another stroke raster pass. [Brush preview](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L590-L753) · [coverage](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L1-L8) · [commit](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L273-L335).

**DrawInAtlas lacks the equivalent presentation path.** Its detached transaction correctly stages edits atomically, but `DrawingCanvas.paint_to()` never requests redraw or renders pending pixels; `_draw()` then rerenders *all* visible source regions and creates fresh textures whenever it is called. `paint_path()` also duplicates three growing change dictionaries for **each pointer update**. [Canvas](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L60-L229) · [session](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L145-L219).

**Decision:** pursue **Option A first, with selected Godot-native presentation facilities from Option B**: live detached stroke preview; persistent, independently updateable *display* tiles; strict dirty invalidation; and batched pointer samples. Preserve the existing document/history contracts. A selective GDExtension becomes justified **only after** end-to-end measurements show that isolated GDScript pixel kernels still miss the responsiveness budget. The existing native research does not yet establish that necessity.

## 2. Verified PhotoCraft architecture

### 2.1 Actual execution diagram

```text
egui-winit / OS pointer events                  CPU, main/UI frame
   |  canvas.rs: process all PointerMoved events within press/release
   v
ToolEvent::Down / Move / Up                     UI dispatch, synchronous
   |  tool_input.rs
   v
Drag points + stylus pose/times                 UI-owned gesture state
   |  Down: begin_live_stroke()
   v
engine::brush_cmds::LiveStroke::begin_with()     CPU, synchronous
   |  clone COW Document + capture pre-stroke Surface
   v
paint::DabGenerator + StrokeRenderer             CPU, synchronous
   |  smoothing -> spacing -> dabs -> sparse 64² coverage
   |  compositing from pre-stroke Surface to COW preview Surface
   |  initial lone dab via tail_preview() / finish-now simulation
   v
UI LiveStroke { preview document, key, damage[] }
   |  display_doc() selects preview WITHOUT document revision increment
   v
canvas::textures::damage_since()                 CPU cache bookkeeping
   |  preview-key + dirty-rect tracking
   v
GPU compositor when supported                    GPU draw commands, submitted by UI
   |  compare COW Arc tile pointers; upload changed 256² layer tiles
   |  compute only dirty region; reuse layer/cache textures
   |  encode to persistent, mipmapped display texture, regenerate dirty mips
   |-- fallback: CPU reference composite damaged region -> partial texture upload
   |-- over-budget: viewport pages/background CPU jobs -> cached GPU pages
   v
egui custom GPU canvas / textured quad        GPU view transform and presentation
   |
   +-- Pointer up: offer live stroke, run paint.stroke as ONE edit
          if revision/points/settings/seed match: reuse preview pixels
          else: rasterize at commit; history snapshot and cache correction
```

Paths supporting the chain: [UI dispatch and batching](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L1030-L1105), [tool event and initial preview](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/tool_input.rs#L490-L547), [UI preview metadata](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L229-L253), [engine preview](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L590-L753), [selection of live display document](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/display.rs#L163-L171), [compositor dispatch](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L390-L496), [release/commit](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L622-L680).

### 2.2 Ownership, threading, and synchronous boundaries

| Stage | File/function, precise source | Owner/storage | Execution / scheduling | Authoritative write? |
|---|---|---|---|---|
| Press and motion capture | [`canvas.rs` 1030–1105](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L1030-L1105); [`tool_input.rs` 490–547](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/tool_input.rs#L490-L547) | UI `Drag`, stylus pose | Main/UI, batch per frame | No |
| Geometry and dabs | [`dynamics.rs` 764–850](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L764-L850) | `DabGenerator` → `PathWalker`/`Smoother` | CPU, synchronous when fed | No |
| Dab coverage | [`render.rs` 474–599](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L474-L599) | Sparse `CoverageMap`, 64×64 `CovTile` | CPU; optional Rayon for large tile batches | No |
| Live raster pixels | [`brush_cmds.rs` 598–648, 685–753](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L598-L753) | COW clone of `Arc<Document>`, pre-stroke `Surface`; detached layer pixels | CPU, synchronous in UI call path | **Preview copy only** |
| Dirty versions | [`strokes.rs` 229–253, 425–470](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L229-L470) | `LiveStroke.damage: Vec<DRect>` and key | UI bookkeeping, immediate | No |
| Visible document selection | [`display.rs` 163–171](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/display.rs#L163-L171) | `display_doc()` returns preview `Arc<Document>` | UI synchronous | No |
| Cache invalidation | [`textures.rs` 322–408, 456–567](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L322-L567) | Display/preview revision keys and dirty rects | UI before draw | No |
| Source layer tiles → GPU | [`cells.rs` 303–459](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/cells.rs#L303-L459) | Persistent resident layer pages, cached `Arc<Tile>` pointers | CPU conversion/staging + wgpu queue writes | No |
| Blend/layer compositing | [`gpu_canvas.rs` 601–745](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L601-L745); [`plan.rs` 1–14](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/plan.rs#L1-L14) | Reused GPU accumulator/output textures | wgpu commands encoded/submitted from UI; GPU executes asynchronously | No |
| CPU fallback / upload | [`textures.rs` 179–214](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L179-L214), [`gpu_canvas.rs` 789–836](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L789-L836) | Reused egui/display textures | Small CPU rect often synchronous; large CPU fallback may be deferred | No |
| Final presentation | [`canvas.rs` 420–496](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L420-L496) | `GpuCanvas` textured shader or egui texture | GPU canvas draw; physical scan-out is outside source guarantee | No |
| Release/history | [`strokes.rs` 622–680](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L622-L680); [`brush_cmds.rs` 273–335](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L273-L335) | Session live offer, edited authoritative doc/history | UI command/transaction synchronous; GPU display catches up | **Yes, once at commit** |

**Crucial distinction:** *PhotoCraft's live stroke is not simply painted directly to the permanent layer*, nor is it accumulated primarily by a GPU brush shader. The brush uses **CPU rasterization into a detached COW document**; GPU compositing is a separate subsequent stage. The implementation corresponds most closely to **D (hybrid)**, combining **B-like temporary state** with a document-faithful compositor and CPU-backed raster pixels. [Preview structure](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L522-L550) · [preview doc routing](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/display.rs#L163-L171).

`StrokeRenderer`'s optional Rayon work for sufficiently large coverage/composite tile batches does **not** imply the brush engine is dispatched to a background worker: the UI calls it synchronously. Separately, **large CPU document refreshes** and **oversized-document viewport pages** can be prepared on workers. Do not attribute all brush responsiveness to asynchronous painting. [Parallel threshold and accumulation](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L43-L72) · [CPU fallback deferral](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L562-L584) · [viewport-page workers](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/viewport_pages.rs#L1-L13).

## 3. Live stroke lifecycle

### Pointer-down → first visible pixel

1. **Press is captured immediately**, before egui's drag-distance threshold. `tool_event(Down)` initializes a `Drag`, preserves initial position and stylus state, and calls `begin_live_stroke()` for Brush/Pencil/Eraser and other live tools. [Canvas press handling](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L1030-L1048) · [tool_input](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/tool_input.rs#L490-L518).
2. **A detached source is established.** `LiveStroke::begin_with` captures the original `(DocId, revision)`, clones the document structurally (`(*st.doc).clone()`), stores `pre = surf.clone()`, and immediately calls `live.push(&initial_points)`. COW keeps untouched surface tiles shared. [Engine](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L598-L648) · [raster storage](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/raster/src/lib.rs#L1-L6).
3. **A lone point is not dropped.** `PathWalker::push()` initially stores a `pending_first` rather than emitting a normal segment. `LiveStroke::push()` calls `renderer.tail_preview()`; this clones the generator for a hypothetical immediate finish, producing the initial stationary dab and compositing it to the preview surface. Thus the *first dab exists before button release*, despite the path walker's first-point deferral. [Path walker](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L346-L364) · [finish-now preview](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L989-L1035) · [engine push](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L729-L752).
4. **The first screen display** occurs when `display_doc()` selects the live preview's `Arc<Document>` and preview version, `damage_since()` marks the new area, and `paint_canvas()` invokes `ensure_gpu()` or `ensure_texture_in_view()` before drawing the result. This is a draw-frame path, **not a guarantee of zero-millisecond event-to-photon latency**. [Display](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/display.rs#L163-L171) · [damage](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L406-L408) · [presentation branches](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L390-L496).

### Moving, overlap, release, cancellation

- **Raw movement:** Freehand captures each delivered `PointerMoved` in-order, bounded by the press/release events; a single UI frame may include multiple OS moves. Points (and pressure/tilt/rotation samples) are dispatched individually but rasterized once per frame in `feed_live_stroke()`. The raster step consumes only points after `LiveStroke.fed`, and records a damage rect per step. [Batch](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L1046-L1105) · [feed](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L425-L470).
- **Repeated/self-crossing dabs:** The sparse stroke coverage map accumulates brush flow and an opacity ceiling across the gesture, then composites the affected tile against the **original pre-stroke pixel**. Consequently, self-crossings do not behave like repeated alpha-blending of the whole brush onto the already composited document. `mark_dirty` and `tail_preview` handle regions that must be restored or repainted as smoothing moves. [Coverage semantics](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L1-L8) · [accumulate](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L530-L599) · [dirty-region composite](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L1123-L1177).
- **Release:** `commit_brush_stroke()` feeds any not-yet-painted points from the release frame, then offers the renderer to the session and runs the brush command **once**. `LiveCommit::matches()` checks command, document/revision, seed, full point list, and remaining settings. If matched, `stroke_with()` assigns the already-computed `Surface` to the authoritative target during `Session::edit`; if not, it performs normal rasterization. The UI stores `CommittedStroke` so previously displayed preview versions need only their missing damage, not a full repaint. [UI commit](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L622-L680) · [match](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L552-L587) · [authoritative edit](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/engine/src/cmd/brush_cmds.rs#L273-L335).
- **Cancel:** A discarded UI preview leaves the authoritative document unchanged; the code explicitly clears both `app.drag` and `app.live_stroke` on mixer Escape/context changes, and rejects a mismatched mixer release. The **complete Escape semantics for every other brush/tool/context were not exhaustively verified**; that behavioral test remains open. [Mixer cancellation](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L410-L423) · [gesture guard](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gesture.rs#L9-L18).
- **History:** PhotoCraft's history stores pre-edit, whole-document **COW snapshots**, not full copies of every tile's bytes on each movement. It is a different internal history representation from DrawInAtlas's compact per-pixel delta; there is no reason to transplant it. [History implementation](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ops/src/lib.rs#L1-L10).

### Sampling, smoothing, and true path fidelity

**Verified:** PhotoCraft reads all pointer moves the egui event queue delivers in a frame, whereas simply reading the final pointer position discards those intermediate samples. It explicitly starts stroke tracking before drag threshold, synthesizes timestamps across frame-batched events because egui mouse moves lack timestamps, and passes stylus pressure, tilt, and rotation. [Input](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L1046-L1105) · [timestamp/pose](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L425-L449) · [spread time](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L538-L545).

`DabGenerator` runs optional smoothing, interpolated path stepping, spacing, pose/dynamics and dab construction incrementally. `Smoother` supports exponential smoothing, pulled-string lag, catch-up while stationary, and finish-on-release behavior. `PathWalker` supports distance spacing, speed/time spacing, bounded airbrush repeats and special pixel-grid traversal for small aliased brushes. [Smoothing](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L98-L199) · [interpolation/spacing](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L229-L427) · [dab generator](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L764-L850).

**Limit:** interpolation can make *covered pixels continuous* along a segment; it **cannot reconstruct a curved pointer movement never delivered by the OS/application**. Smoothing can change/lag the curve, but is not recovery of missing motion. The source proves avoidance of *unnecessary loss of queued samples*, not immunity to missing/coalesced events or UI-thread stalls. No matched fast-motion tracking error measurements are available. The brush raster work is still synchronous in the UI frame and therefore can delay subsequent input processing. **Proposal:** instrument event counts and maximum delivered inter-sample distance; preserve raw floating-point positions to the raster pipeline, and only interpolate between actual samples.

## 4. Performance mechanisms

### 4.1 Sparse storage, caching and GPU synchronization

**Two different tile scales matter:** PhotoCraft's persistent layer storage is a **256×256 COW tile surface** on a logically infinite plane (`Surface`); brush **coverage** uses smaller **64×64** transient tiles (`COV_TILE = 64`). The README's tile assertion is supported by actual storage code; it does not imply PhotoCraft's GUI canvas is an unbounded document — GPU canvas and viewport-page APIs use a finite `Document.size`. [Raster storage](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/raster/src/lib.rs#L1-L6) · [coverage constant/map](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L43-L43) · [coverage tiles](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/render.rs#L474-L508) · [finite GPU doc size](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L601-L609).

1. **Source tile upload:** The wgpu compositor maintains GPU-resident layer/mask pages. `Compositor::sync()` compares each surface tile `Arc` against the tile reference in the resident page with `Arc::ptr_eq`, uploading only changed 256² tiles and clearing removed tiles; unchanged tiles remain GPU-resident. The path can retain overlapping texels on resize and reuse an existing GPU page from a duplicated layer. `Stats.tiles_uploaded` and bytes are tracked. [Actual sync implementation](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/cells.rs#L303-L459). This prevents a small stroke from re-uploading every source layer.
2. **Layer compositing:** The compositor converts the layer tree into GPU passes for opacity, blend modes, masks, groups, clipping and effects. It processes dirty regions in bounded working chunks and can reuse lower-stack checkpoints. Some document features or GPU failures use the CPU reference compositor. [GPU compositor overview](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/lib.rs#L1-L36) · [pass planning](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/plan.rs#L1-L14) · [GPU execution/region](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L645-L745). **Qualified:** all *affected* layers may still need processing inside the dirty region; it is not a guarantee that every unrelated upper layer is skipped. Effect reach can increase the affected rectangle.
3. **Persistent display texture:** `GpuCanvas::composite()` renders directly into the previously allocated document texture using scissor rectangles. Only dirty-region mipmap texels are regenerated. For a CPU fallback, `upload_rect()` writes the changed subrectangle with wgpu; egui's CPU path uses `TextureHandle.set_partial()`. Full texture creation/replacement occurs for missing, changed-size or invalid caches, not every stroke. [GPU scissor](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L685-L745) · [CPU partial](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L179-L214) · [wgpu rect upload](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas/doc_textures.rs#L134-L156).
4. **Dirty-version reconciliation:** A preview `display_key` records incremental damage. Once a commit adopts the preview, `CommittedStroke` calculates only *unseen* changes; otherwise a normal committed edit invalidates its damaged region. Undo/redo COW tile identity changes are reflected in the next compositor sync. Source proves invalidation mechanisms; absence of flicker on every device is **not measured**. [Damage matching](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L322-L408) · [release](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/strokes.rs#L657-L680) · [pointer-difference residency](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/gpu/src/cells.rs#L426-L459).
5. **Display/presentation buffering:** Persisted display textures, loaded render attachments (`wgpu::LoadOp::Load`) and cache versioning prevent unnecessary blank resets; out-of-budget viewport pages keep an old page until the replacement upload, with cancellation and versioned results. A dedicated *double-buffered full canvas* was **not identified** from the traced path; do not claim one. [Render attachment](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas.rs#L703-L720) · [viewport pages](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/viewport_pages.rs#L1-L13).

**Priority split:** Sparse CPU dab coverage, visible preview state, damage propagation, resident display textures and limited updates are **directly relevant to a simple brush**. Checkpointed layer-stack caches, complex effect-region dependency analysis, page eviction and deep blend pipeline optimization matter **primarily** with many layers, filters and huge documents. They are not a first-milestone prerequisite for DrawInAtlas.

### 4.2 Zoom and large source-pixel views

- **100% (zoom 1.0):** normal path uses a full-resolution stored composite texture if it fits the GPU budget, and the draw shader samples/scales it. New brush dabs remain at document resolution and require only damaged source tiles; a simple zoom/pan with unchanged pixels does not itself require rerunning composition. [GPU view uniforms](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L444-L470) · [unchanged early return](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L533-L548).
- **50% / 25%:** a budget-fitting GPU document still uses its cached, mipmapped display textures; 2×2 mip sampling is implemented with per-damage-chain updates. The brush raster remains document-space. [Mipmap generation](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/gpu_canvas/doc_textures.rs#L159-L231) · [brush geometry](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/paint/src/dynamics.rs#L785-L832).
- **When the full canvas texture exceeds budget:** `viewport_pages` calculates visible source pages and a reduction factor: for 100%, 50%, 25%, nominal factors are **1, 2, 4**, respectively, provided the page budget does not force further coarsening. It uses at most a bounded number of pages, prioritizes center-visible pages, uses two cancellable background workers, and uploads derived textures; small dirty areas may update only the affected reduced texels. At smaller zooms, the factor is bounded and can be adjusted to fit the page budget. [Factor/page selection](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/viewport_pages.rs#L84-L133) · [render/worker queue](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/viewport_pages.rs#L580-L695).
- **CPU fallback:** whole-document reduced composite plus a separate visible-detail texture may be used; partial dirty-region rendering and `set_partial()` are implemented. This is **not necessarily as cheap as simple GPU scaling**, especially after cache invalidation. [CPU canvas](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas.rs#L471-L496) · [CPU cached reduction](https://github.com/storytold/photocraft/blob/0a9717fa64a62376721ef43400125c5e6eb65862/crates/ui-egui/src/canvas/textures.rs#L115-L220).

**Not established:** physical FPS at exact zooms, actual screen latency for millions of source pixels, device-dependent compositor memory thresholds, and seamless zoom under all effects. Source establishes *the strategies*, not measured guarantees. Conversely, DrawInAtlas's standalone canvas currently clamps zoom to **0.5 minimum**; 25% is not available in the traced standalone UI without a change to that bound. [DrawInAtlas zoom clamp](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L97-L114).

## 5. DrawInAtlas comparison

### 5.1 Corresponding call path

```text
DrawingCanvas._gui_input(Button press)
  -> start_gesture(position) -> DrawingDocument.begin_edit(layer, revision)
  -> session = DrawingEditSession ; paint_to(initial pixel)
  -> DrawingEditSession.paint_path([rounded/centered point])
       -> clone _before/_after/_covered dictionaries for rollback
       -> _paint_segment(previous, new) -> scan candidate bounding box
       -> _stage(pixel) -> string pixel key, source-tile lookup, blend, pending dictionaries
       [NO presentation, no queue_redraw()]
DrawingCanvas._gui_input(MouseMotion)
  -> update_gesture -> paint_to -> same synchronous stage; repeat dictionary cloning
       [NO presentation, no queue_redraw()]
DrawingCanvas._gui_input(Button release)
  -> finish_gesture -> paint_to -> session.commit()
  -> DrawingDocument._publish_edit(): validate sources/revision,
       detach touched tiles, write changed pixels, dirty markers,
       revision++, one DrawingDelta/history entry
  -> queue_redraw()
DrawingCanvas._draw()
  -> for every 192x192 region in visible document-space view:
       DrawingRenderer.render(document, area): for each visible layer/row,
         lookup tile runs, blend pixels into fresh packed RGBA8
       Image.create_from_data + ImageTexture.create_from_image
       draw_texture_rect() using camera/zoom
```

Trace: [`canvas.gd` 45–229](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L45-L229), [`edit_session.gd` 57–257](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L57-L257), [`document.gd` 218–234, 325–402](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/document.gd#L325-L402), [`renderer.gd` 6–92](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/renderer.gd#L6-L92).

### 5.2 Evidence-based defect table

| Component / symptom | Current implementation | Classification | Status and evidence | Remedy and verification |
|---|---|---|---|---|
| **Invisible live brush** | `paint_to` only stages `_after`; `_draw()` reads committed `document` exclusively; no redraw until release | **Architectural / presentation** | **Confirmed.** [`canvas.gd` 60–96, 172–229](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L60-L229) | Add detached preview pixels, invalidate dirty display tile, draw while button still pressed; pixel-readback witness before release |
| **Full-view CPU compositing on redraw** | 192px regions *across whole view* and every visible layer; fresh buffers/`Image`s | **Architectural** | **Confirmed.** [`canvas.gd` 69–96](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L69-L96), [`renderer.gd` 6–92](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/renderer.gd#L6-L92) | Cache composited display tiles keyed to source dirty tiles + layer/visibility revisions; report rendered source pixels per stroke |
| **Fresh textures every redraw** | Every drawn 192px region calls `ImageTexture.create_from_image` | **Architectural / upload** | **Confirmed.** [`canvas.gd` 85–96](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L85-L96) | Persistent 128–256px display textures; use `ImageTexture.update(Image)` when size/format unchanged; count creates vs updates and upload bytes |
| **Long-gesture superlinear copying** | Each `paint_path()` copies three accumulated dictionaries before processing a new sample | **Algorithmic** | **Confirmed.** [`edit_session.gd` 154–177](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L154-L177) | Replace whole-transaction copies per input event with atomic per-batch staging/rollback journal; benchmark cost vs points already drawn |
| **Per-pixel dictionary/string overhead** | `_stage()` formats `"x,y"`, hashes keys, blends/records; `DrawingRasterTile` also hashes pixel index | **Algorithmic; native candidate only if measured** | **Confirmed operations; cost share not isolated.** [`edit_session.gd` 57–97](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L57-L97), [`raster_tile.gd` 1–54](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/raster_tile.gd#L1-L54) | Tile-indexed packed staging buffers/bitsets or batched sparse deltas; profile hash/alloc fractions before GDExtension |
| **Oblique swept-capsule geometry** | Candidate bounding rectangle, `Geometry2D.get_closest_point_to_segment` for each candidate; special-case axis-aligned strokes | **Algorithmic / possible native** | **Confirmed mechanism; isolated hotspot unmeasured.** [`edit_session.gd` 180–257](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L180-L257) | Scan only covered spans/optimized squared-distance, retain exact oracle regression; measure 4/32/64/128px |
| **Fast path looks straight** | `_gui_input` accepts delivered motion; immediately converts position to **integer** doc pixel, then draws capsule between samples | **Input/presentation** | **Confirmed quantization and segment joining, but cause of visual artifacts not isolated.** [`canvas.gd` 47–54, 116–187](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L47-L187) | Retain floating document-space path; log raw samples and event accumulation; re-render identical recorded traces |
| **Zoom-out collapse** | `dimensions = ceil(view.size/zoom)` then all regions composited on every view redraw | **Architectural** | **Confirmed scaling; actual ms vs zoom unmeasured here.** [`canvas.gd` 69–96](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L69-L96) | Reuse persistent display tiles and GPU scale; optional derived display LOD only if measured; benchmark 100/50/25% (allow <0.5 in test harness) |
| **History atomicity / dirty markers** | `_publish_edit` validates expected revision and source pixels, clones touched tiles, emits `DrawingDirtyRegion` and one delta, bumps revision once | **Existing strength** | **Confirmed.** [`document.gd` 325–402](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/document.gd#L325-L402) | Reuse existing publication semantics and dirty regions; do not publish per mouse move |
| **Lazy tile source loading** | `_resolve_chunk` can synchronously fetch/validate advertised absent tiles | **Potential I/O hitch** | **Confirmed possible call path; impact hypothetical.** [`document.gd` 275–296](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/document.gd#L275-L296) | Track fetch duration/count during gesture, prefetch if needed; never substitute blank on failure |
| **Selection masks/layer hierarchy in preview** | `paint_path` accepts `DrawingSelection`, but `canvas.paint_to()` passes no selection argument; `renderer` flattens visible groups | **Correctness/integration gap** | **Confirmed call shape; behavioral intent uncertain.** [`canvas.gd` 172–187](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/canvas.gd#L172-L187), [`renderer.gd` 48–92](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/renderer.gd#L48-L92) | Preview must use same target/mask rules as commit; add mask and hierarchy byte parity tests; do not assert unsupported advanced blends already work |
| **C++ will solve latency** | No production native raster path selected | **Unsupported conclusion** | **Hypothesis only.** [T-068 existing study](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L128-L168) | First isolate CPU kernel vs compositing/upload/frame time; only then test a narrow extension |

**Important scope caveat:** The existing software-only synthetic visual benchmark creates **`AtlasCanvas`, not standalone `DrawingCanvas`**; it cannot prove the standalone's live-preview behavior or directly benchmark its `_draw()` path. [Visual test 69–105](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/tests/drawing_latency_stress_visual.gd#L69-L105). Drawing's shared canonical code resides in `addons/drawing/`; standalone shell stages/calls the shared implementation and should not fork it. [Drawing core contract](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/README.md#L1-L44).

## 6. Recommended architecture

### 6.1 Core design (Godot 4.8, GDScript-first)

```text
ONE canonical addons/drawing module; UI adapter in standalone/Atlas

InputEventMouseButton/Motion (retain Vector2 document coordinates)
    -> DrawingStrokeController: ordered sample queue, bounded per-frame consume
    -> DrawingEditSession: detached authoritative transaction (unchanged contract)
                | 
                +-> DrawingLiveStroke: tile-indexed pending state / covered-bitset
                     + base document revision, target layer, frozen tool/transform
                     + old pixels read from source once; candidate/dab geometry
                     + modified rects per document/display tile
                     + preview bytes derived from EXACT _blend semantics
    -> DrawingDisplayCache: composite-display tile entries keyed by
         document ID + content/metadata revision + tile coords + layer state
         and optional pending stroke generation
    -> persistent Image + ImageTexture per small DISPLAY tile
         dirty tile: render only changed region/layer dependencies,
         use texture.update(image) for same-size whole display tile
         unchanged tile: just draw stored texture at zoom/pan transform
    -> DrawingCanvas._draw() draws visible cache tiles + overlay cursor/selection

Pointer release -> feed last samples -> DrawingEditSession.commit()
    -> existing validate/detach/revision/history/dirty regions
    -> map preview cache tiles to new committed revision when byte-identical
    -> drop pending overlay; recomposite only impacted display tiles if necessary
Pointer cancel -> session.cancel(); drop pending; restore unchanged cached document
```

This is a **proposal**, not a statement about existing APIs. It adopts PhotoCraft's two key separations: **temporary pixel truth versus committed document truth**, and **document changes versus texture/display cache changes**.

**Ownership and correctness contracts:**

- `DrawingDocument` remains the only authoritative owner of sparse RGBA8 tiles, layer tree, revision and history. `DrawingEditSession` owns uncommitted changes (`_before/_after`), with a read-only source revision and existing `commit()`/`cancel()` API. `DrawingLiveStroke` is a *view/cache presentation companion* or a non-public edit-session accessor, **not a second history system**. Avoid exposing mutable resident document tiles to UI.
- The live pixel buffer must show the exact **final per-pixel composite of the current gesture against original layer pixels**, not simply draw a brush mark on the already composited screen. An eraser can reveal lower layers, and a stroke on a non-top layer may be affected by upper layers, selections, opacity or blend dependencies. **Do not use a naive transparent overlay for general layers**, because its screen source-over math is not equivalent to target-layer mutation plus layer-stack compositing. For the current simple hard brush on a normal topmost raster layer, a specifically tested overlay path is acceptable; otherwise recomposite only the affected *screen/display tiles* with pending target-layer bytes substituted. Compare preview readback with a separately committed reference document pixel-for-pixel, including hidden RGB in stored data.
- Preserve exact `DrawingEditSession._blend()` rounding and once-covered behavior; preserve `DrawingRasterTile` RGBA8 encoding, alpha-zero hidden RGB, masks, selected layer, parent visibility/locking, and signed-world coordinates. Changing geometry from capsule to dab stamps **changes pixels**: introduce a new brush mode only deliberately, not as a hidden performance refactor. [Current stage/blend](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/edit_session.gd#L57-L97) · [storage contract](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/addons/drawing/README.md#L13-L44).
- Display tile IDs should encode **64-bit-safe signed tile coordinates** separately; avoid converting huge world anchors into `Vector2i`/float as part of indexing. Only display-local positions use Godot `Vector2`/`Rect2i`. Compute viewport visibility and tile intersection without materializing a full infinite canvas.
- `DrawingDirtyRegion` returned by a commit becomes the core cache invalidation input. Convert it into affected *display* tile IDs; include all dependent layers and metadata changes. During a stroke, live dirty tile IDs are separate from committed revision state. A `generation` token must guard async/background results: reject if document, revision, layer, tool, color/mask, or target cache generation changed.
- **Godot API limit:** `ImageTexture.update(Image)` replaces the texture's **entire data**; it is not an arbitrary GPU subrectangle upload. The practical equivalent of PhotoCraft's `set_partial()` is to use **small independently cached display textures** (e.g. 128²/256²) and update only those dirty textures, or later a justified native rendering path. Do not invent a portable `ImageTexture.update_rect()` API. Godot-side T-068 already measured these sizes under llvmpipe. [Godot upload study](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L142-L144).

### 6.2 The minimum viable presentation path

**Milestone implementation choice (proposal):** Start with a dirty-display-tile *preview composite* instead of GPU-side stroke drawing. On each `paint_path` success, retrieve only the session's staged changes for intersecting display tiles, reconstruct the effective target layer region (original + `_after`) in an ephemeral `Image`/byte array, compose it with other visible layers in the **same layer order/math** as `DrawingRenderer`, and upload that display tile via cached `ImageTexture.update()`. The normal renderer can initially be wrapped to replace the one staged layer during tile composition; keep this opt-in internal to the shared Drawing module. At release, commit exactly once, invalidate/rebase only touched display tiles; at cancel, discard ephemeral state. Although this first pass may be less efficient than a full preview COW document, it yields immediate pre-release correctness without altering canonical document/history storage.

**Refinement after that works:** Build a small per-display-tile cache with separate committed and active-preview generations. Optimize `_after` access via tile-local packed buffers or touched-index lists; reuse `Image` and `PackedByteArray` backing where safe. Keep the CPU compositor as exact test oracle and only use Godot's GPU texture scaling to navigate. Only if compositing **a large stack** dominates after these fixes should a Godot-native `SubViewport`/`CanvasItem` layer arrangement be trialed; blending/opacity/masks and hidden RGB parity must be proven. RenderingServer/RenderingDevice custom GPU operations are **not free** and introduce more state and correctness risk than cached textured quads.

**Cache invalidation matrix (proposal):**

| Event | Committed tile cache | Live preview cache | View transform only |
|---|---|---|---|
| Mouse movement | Keep committed data | Dirty only touched display tiles, increment live generation | No |
| Release / successful commit | Invalidate changed regions; adopt byte-identical preview tile where verified | Clear/rekey to new revision | No |
| Cancel / revision conflict | Keep committed revision | Discard all live entries, no history | No |
| Undo/redo / tile import | Invalidate affected tile and dependent composites | Cancel stale preview | No |
| Visibility, hierarchy, opacity, text/edit changes | Invalidate affected composition dependencies (may be wide) | Cancel or rebuild under new generation | No |
| Pan / zoom, unchanged source | Reuse cache; only fetch previously unseen display tiles | Reposition existing live tiles | **Yes**; zoom-out LOD optional |
| Lazy fetch failure | Do not cache blank as valid | Stop or signal error | No |

## 7. GDScript versus GDExtension decision

| Option | What changes | Complexity / portability | Expected remaining bottleneck | Exactness / maintenance risks | Decision |
|---|---|---|---|---|---|
| **A — Optimized GDScript** | Keep editor/session/renderer; live staged preview, dirty tile cache, persistent `ImageTexture`, per-batch rollback, raw-point retention, packed tile edit scratch | **Medium**; pure Godot 4.8, Linux/Windows, one shared implementation | GDScript per-pixel geometry and dictionary indexing for 64–128px, huge gestures; CPU layer composite if many visible layers | Moderate cache invalidation and preview-vs-commit parity work; easiest to test with existing oracle | **Start here** |
| **B — Hybrid Godot-native/GDScript** | A plus native Godot textured quads / native GPU scaling and, only if needed, `SubViewport` or RenderingDevice composition of cache tiles | **Medium–high**; stays Godot-only, GPU renderer/platform capability varies | Exact CPU raster/deltas still cost time; GPU blend/mask compatibility; texture upload/update granularity | Greater cross-backend/driver complexity and exact RGBA8 mismatch risk, especially alpha-zero RGB | **Use native rendering primitives from day one; custom GPU compositor only after evidence** |
| **C — Selective GDExtension** | A/B architecture intact; move measured swept-brush candidate scan, RGBA8 blend/bounded sparse-delta producer or composition kernel into versioned C++ `PackedByteArray` batch interface | **High**; Godot ABI, C++ toolchains, exports, Linux/Windows CI, threading ownership and error propagation | Still full-view cost if A not fixed; marshal/copy/texture update costs; CPU/GPU synchronization | Exact rounding, source revisions, atomic errors, hidden RGB, signed anchors, masks; dual-language maintenance | **Conditional only; no rewrite now** |

**Native threshold (proposal, not a pre-existing performance measurement):** First make a standalone 4px continuous stroke appear *during drag*, with zero unnecessary full-view renders and no repeated texture creation on steady-state updates. Capture median/p95 for at least 100–500 meaningful samples and per-stage breakdown on **physical Linux and Windows hardware**. If, with rendering/upload fixed, **brush raster + batch staging** alone regularly consumes an unacceptable part of the target 16.7ms frame budget (or an agreed project-specific target) at **32/64/128px**, prototype C++ only for that bounded kernel. Require end-to-end median and p95 improvement *including actual Godot↔native conversion and main-thread publication*; source-byte equality against the GDScript oracle; bounded memory; atomic error behavior; thread/race and exports. No speedup threshold can honestly be set from the present evidence.

T-068 already contains a detached scalar C++ kernel, fuzz/rounding tests, and optional GDExtension research checkpoints, but it explicitly does **not** establish a shippable, app-integrated, hardware-measured native drawing path. The current report neither rejects those experiments nor treats them as a mandate. [T-068 benchmark scope](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L128-L168) · [publication prototype](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L50-L75) · [FP safety](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L28-L45).

## 8. Incremental implementation plan

Each stage is separately testable and reversible. **Do not start a native rewrite or modify both application copies.** All implementation should be canonical under `addons/drawing/` and reused by independent Drawing and the Atlas adapter.

1. **P0 — First live pixel, with a single transaction.** Keep `_after` staged, implement explicit active-preview dirty rectangles and render a readback-visible 4px dab immediately on mouse-down, *before release*, then a slowly moving stroke. Assert document revision/history unchanged until release. Test cancellation reverts the frame without changing stored RGBA8. Instrument press → preview CPU ready → frame submit. **Pass gate:** visible buffered result before `MouseButtonUp`; one committed revision and history action.
2. **P0 — Stop full-viewport redraw and texture recreation.** Persistent 128/256px display tile entries, viewport culling, early unchanged path, count `DrawingRenderer.render` pixel area and `ImageTexture.create_from_image` calls. Use `ImageTexture.update` for existing same-size tiles and only on dirtied tiles. **Pass gate:** steady-state 4px stroke recomposites/upload updates *proportional to dirty tiles*, not window/document area; pan/zoom with unchanged pixels reuses textures. Test 1, 4, 16 layers and at minimum 100%, 50%; 25% through a temporary benchmark view transform if needed.
3. **P1 — Remove per-event O(stroke-size) copies.** Replace triplicate map duplication in `paint_path` with bounded atomic batch edits, or a reversible per-batch change log. Keep `STALE_REVISION`, `NO_CHANGE`, once-per-covered-pixel and rollback guarantees. **Pass gate:** stage cost per fixed short input segment stays roughly constant as an existing stroke grows, subject to coverage/cache variation; failure fixtures prove no partial mutation.
4. **P1 — Preserve input fidelity.** Retain float world positions (no early `Vector2i`), queue Godot motion events at the canvas boundary, optionally test disabling accumulated input **locally** for drawing, and process queued samples in order once per render tick. Preserve press/release interval, last point and any supported pressure. **Pass gate:** recorded high-frequency curved trace has the same polyline/coverage independent of frame batching; sample-loss counter detects missing events rather than inventing them.
5. **P1 — Efficient CPU staging/compositing.** Profile candidate scans, `Geometry2D` calls, source/delta string keys, `DrawingRasterTile.get_rgba`, and dirty tile copy. Introduce tile-local typed scratch/bitset and row-oriented pixel loops behind an exact-output oracle. **Pass gate:** 4/32/64/128px, fast diagonal and self-cross outputs byte-identical to specified legacy hard-brush semantics, including edge seams, masks, hidden RGB and undo/redo.
6. **P2 — Correct layer/selection preview.** Render pending target pixels *in place* within layer order for erasing, lower-layer visibility, nested groups, text, masks and relevant opacity. Broaden dependent-region invalidation where layer metadata/effects require it. **Pass gate:** live preview framebuffer equals reference document rendering for all supported cases; non-supported blend/effect features remain explicitly out-of-scope rather than silently approximated.
7. **P2 — Zoom scalability and optional LOD.** Show cached GPU-scaled display tiles without refreshing underlying pixels on camera changes. At very low zoom, benchmark *derived display-resolution composites* and a bounded cache/eviction policy; do not downsample or degrade authoritative artwork tiles. **Pass gate:** 100/50/25% steady-state drawing work is bounded by dirty source regions and relevant visible tiles, with deterministic cancellation/invalidation.
8. **P3 — Native kernel only if gate fails.** Implement a standalone, bounded GDExtension batch surface with versioned layout. Measure marshaling + pixel operations + publication + texture upload + frame, including Windows. **Pass gate:** audited exactness and demonstrable end-to-end improvement, otherwise keep the simpler GDScript backend.

**Suggested diagnostic counters:** received pointer events/frame; total gesture points; max point-to-point distance; per-frame queue depth; `_after` entries; new/dirty/visible display tiles; CPU candidate pixels; staged changed pixels; source tile resolves; composed source pixels × layers; image/texture creates/updates; transferred texture bytes; CPU stage ms; GPU submission ms; `frame_post_draw` ms; physical presentation ms only with appropriate instrumentation; process RSS/HWM and separately profiled VRAM. Record revision IDs before, during and after cancellation, commit, undo and redo.

## 9. Benchmark evidence

### 9.1 What was and was not run in this investigation

**This investigation executed no PhotoCraft or DrawInAtlas benchmark.** The current container is Linux x86_64 with Python 3.13.5 and git 2.47.3; `godot`, `cargo` and `rustc` are unavailable. An attempted GitHub `git clone` failed because `github.com` was not resolvable, so the repository source was fetched at exact commits via GitHub instead. The repository benchmark results below are **existing saved evidence only**, not new measurements or a matched reference/target comparison. No physical display latency, actual pointer device input latency, GPU-driver timings, VRAM or CPU/GPU power measurements were collected here.

### 9.2 Existing DrawInAtlas recorded measurements

**Recorded 2026-11-02:** Godot 4.8 beta2, Linux sandbox. CPU-only two-layer 96×96 composite, five runs/positions, source project saved stride 512: prior per-pixel compositor **95.692ms median / 99.060ms p95**, tile-run version **6.096ms / 6.317ms**; stride 1024: **96.077 / 96.695** versus **5.989 / 6.101**; stride 2048: **94.966 / 96.127** versus **5.995 / 6.239**. This shows the **already-implemented tile-run improvement** in the stored benchmark; it does **not** validate that the current `_draw()` is efficient. The same 512-stride test recorded full edit+commit+undo+redo **4px short sweep 1.625 / 1.878ms**, **64px round 115.117 / 121.459ms**, **fast long 39.432 / 40.672ms**. These are *not* raster-only kernel or event-to-photon latencies. The saved JSON reports `checks: 693`, whereas adjacent prose says 691; preserve the source discrepancy rather than quietly reconcile it. [Raw CPU evidence](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/benchmarks/T068_2026-11-02_godot.json) · [study explanation](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L114-L126).

**Recorded 2026-11-02 upload-only under Mesa llvmpipe:** `ImageTexture.update` full 128² RGBA8 tile **0.014 / 0.028ms median/p95**, 256² **0.017 / 0.036ms**, 512² **0.044 / 0.062ms**, 1024² **0.168 / 0.200ms**. These are *upload-call* timings, not time until pixels appear. [Raw upload evidence](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/benchmarks/T068_2026-11-02_upload.json) · [interpretation](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L142-L144).

**Recorded 2026-11-04 software-only X11 synthetic events:** Godot 4.8 beta2, llvmpipe, **five trials per case**, full `AtlasCanvas` gesture from synthetic press through release and `RenderingServer.frame_post_draw`, 81/81 assertions. These do **not** measure an active *uncommitted* stroke, the standalone editor's canvas, hardware pointer delivery, or physical display scan-out. [Raw experiment](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/benchmarks/T068_2026-11-04_visual_process_software.json) · [test implementation](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/tests/drawing_latency_stress_visual.gd#L1-L165).

| Synthetic workload | Dispatch median / p95 ms | Synthetic dispatch-to-`frame_post_draw` median / p95 ms |
|---|---:|---:|
| 4px dab | 0.537 / 0.744 | 10.746 / 11.222 |
| 32px dab | 10.960 / 11.452 | 22.920 / 24.288 |
| 64px dab | 39.714 / 41.280 | 57.176 / 58.343 |
| 4px long stroke | 3.560 / 3.736 | 20.654 / 29.721 |
| 4px self-crossing | 2.898 / 3.091 | 18.424 / 18.613 |

The **p95 here is just the maximum of five trials** (the test's nearest-rank calculation); it is not a reliable tail-latency distribution. The document's later *two-phase* load study reported counterintuitively lower loaded times, while its subsequent ABBA load-order experiment reversed the direction. Those fluctuations demonstrate that simple software-only per-phase comparisons are not a robust performance gate. [Test's percentile computation](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/tests/drawing_latency_stress_visual.gd#L29-L35) · [ABBA limitation](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L1846-L1878).

**Recorded native microkernel:** a detached C++ scalar batch shows promising low isolated times, but its fixtures precover candidates, it lacks the final Godot marshal/edit/present pipeline and is **not an integrated application latency measurement**. The previous T-068 study itself declines to select a native renderer. [C++ details and limits](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L128-L140).

### 9.3 Reproduction commands for equipped environments

From clean checkouts of the exact revisions (provided as *reproduction instructions*, **not commands executed successfully here**):

```bash
git clone https://github.com/storytold/photocraft.git
cd photocraft
git checkout --detach 0a9717fa64a62376721ef43400125c5e6eb65862
# Inspect development.md and AGENTS.md, then use the repo's pinned toolchain.
# Do not assert a PhotoCraft UI performance number without a runnable GUI/driver.

cd ..
git clone https://github.com/FivePebblesGPT/DrawInAtlas.git
cd DrawInAtlas
git checkout --detach 4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c
# Existing headless reference / CPU oracle benchmark:
godot --headless --path . \
  --script res://tests/drawing_raster_backend_benchmark.gd \
  -- --output /tmp/t068-godot.json
# Existing X11 software-only synthetic diagnostics:
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s '-screen 0 1400x900x24' \
  python3 tools/benchmarks/t068_visual_device.py \
    --godot /path/to/Godot_v4.8-beta2_linux.x86_64 \
    --profile software --output /tmp/t068-visual-software.json
python3 tools/benchmarks/t068_visual_device.py \
  --evidence /tmp/t068-visual-software.json
# Existing upload benchmark:
xvfb-run -a godot --path . --rendering-driver opengl3 \
  --audio-driver Dummy \
  --script res://tests/drawing_raster_upload_benchmark.gd \
  -- --output /tmp/t068-upload.json
```

Sources for the established commands: [benchmark instructions](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L11-L26) and [general reproduction](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/docs/DRAWING_CPU_RASTER_BENCHMARK.md#L98-L110). Verify resource imports and executable names for the local installation. The standalone app uses `drawing/project.godot` and its **GL Compatibility** renderer, not the same host UI as the saved Atlas synthetic tests. [Standalone project settings](https://github.com/FivePebblesGPT/DrawInAtlas/blob/4d96ad4ac7730b212b77fcc4db23ebd9e2dbf81c/drawing/project.godot#L1-L16).

### 9.4 Required *new* matched benchmark protocol

**Not yet performed.** Instrument the actual standalone DrawingCanvas, and separately the Atlas adapter, on the *same* hardware and build. Replay timestamped pointer paths: a stationary 4px press held for multiple frames, 4px fast diagonal/curved move, 32px, 64px, 128px, long stroke, self-crossing, and cancellation/undo/redo. Repeat with one and many raster layers, selection mask on/off, at 100/50/25% zoom (test-level 25% allowance if needed). Use at least 100–500 trials/case, warm-up sessions, randomized ABBA/ABAB order, raw timestamps, and consistent CPU/GPU/display clocks. Count **how many input events were actually delivered**.

Separate: press-event dispatch, sample queueing, CPU candidate/dab math, staging `_after`, preview composite, `Image` preparation, texture update enqueue, GPU submission, `frame_post_draw`, and **actual physical scan-out** with a calibrated high-speed camera or suitable input-to-photon instrument. `frame_post_draw` and graphics timestamp queries are **not** event-to-photon; distinguish synchronous CPU work from driver/GPU submission and display. Check source SHA, Godot version and renderer; collect Linux/Windows machine/driver, whole-process RSS, VRAM and jitter. The independent canonical `DrawingRenderer` and history byte checks must remain correctness oracles.

## 10. Open questions and risks

1. **No direct PhotoCraft runtime profile:** What are first-dab, dirty compose and presentation median/p95 on representative desktop GPUs, and does the input loop stall under a 128px brush? Source does not answer.
2. **No direct standalone latency profile:** The saved T-068 visual witness uses AtlasCanvas, not DrawingCanvas, and synthetic down/move/up happen before its frame await. Neither first-uncommitted-pixel nor physical scan-out was measured.
3. **No matched apples-to-apples workload:** PhotoCraft's brush engine has dynamics and different stroke semantics, while DrawInAtlas currently rasterizes swept hard capsules once per covered pixel. Exact time comparison requires equivalent simple brushes and pixel coverage settings.
4. **Incomplete general-tool cancellation study:** Preview state is demonstrably discardable and mixer Escape is explicit, but every PhotoCraft tool's Escape/focus-loss behavior was not exhaustively verified. DrawInAtlas needs comprehensive cancellation tests.
5. **Selection and blended-layer parity:** Target `DrawingCanvas.paint_to` does not pass its selection object. General preview layer hierarchy/compositing rules may require more than source-over overlay; confirm supported renderer feature set and add byte-oracle cases before claiming correctness.
6. **Authoritative geometry and transparent RGB:** Packed caches and GPU compositing must preserve canonical straight RGBA8 bytes. Hardware display conversion may be lossy; separate *stored pixel exactness* from visual preview equivalence and never feed GPU-readback bytes into authoritative storage.
7. **Metadata invalidation:** Layer visibility, hierarchy, order, mask, text and blending changes can invalidate more than one painted tile; derived cache generation keys and dependency-region rules need design/tests.
8. **Sparse/infinite canvas and zoom-out:** Unlike PhotoCraft's finite displayed document, DrawInAtlas has signed 64-bit sparse coordinates and lazy storage. A bounded display tile cache plus eviction and world-safe indexing is essential. Aggressive LOD must not introduce global full-image allocations.
9. **Godot partial GPU uploads:** `ImageTexture.update` replaces a whole texture. Small display tiles are viable, but GPU transfer costs on real Windows/Linux drivers and mip/nearest filtering choice remain unverified.
10. **Input fidelity is bounded by the source:** Turning off Godot input accumulation or collecting more intermediate events might improve curves but cannot recover events the operating system never delivered; may increase CPU pressure and latency. Test per platform/device.
11. **Prototype versus product:** T-068 detached native prototypes provide useful correctness/kernels evidence but lack cross-platform, production-export and physical event-to-present proof. Do not mistake isolated `ctypes` or scalar kernels for measured GDExtension wins.
12. **Fresh commit drift:** These findings apply only to the two stated SHAs. The repository's README, documentation and historic benchmark claims are not substitutes for this pinned execution-path inspection. Source fetch succeeded but a full local clone/build did not.

### Final engineering decision

**Yes: the *architectural* prerequisites for responsive, continuous drawing are achievable with GDScript and Godot's existing native graphics APIs.** DrawInAtlas's most immediate defects — no pre-release pixel presentation, repeated full-view compositing, per-redraw texture creation, and repeated copying of growing stage dictionaries — can be fixed without C++ while preserving detached revisions, sparse tiles, exact RGBA8 and one gesture = one history action. **Whether optimized GDScript alone meets the desired p95 for 64–128px brushes remains unverified.** Measure that after the preview/cache milestones; introduce a narrowly bounded C++ raster/batch kernel only if profiling proves the remaining CPU work is the limiting factor and its in-Godot end-to-end improvement outweighs maintenance and correctness risk. PhotoCraft's transferable advantage is **incremental, accurately cached presentation of detached live pixels**, not the mere choice of Rust/wgpu instead of GDScript.