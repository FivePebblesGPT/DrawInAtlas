# PhotoCraft real-time painting scout — agent handoff (T-084)

**Research-only; no implementation changes or native backend adoption.** Repositories: `https://github.com/storytold/photocraft` (reference) and `https://github.com/FivePebblesGPT/DrawInAtlas/tree/aidev` (target). Pin exact commits, read repository agent instructions and licenses, and verify actual source versus README claims.

## Task
Reverse-engineer the first **visible uncommitted pixel** in PhotoCraft: pointer down/motion/up → sample queue/interpolation → brush geometry/dabs → pending stroke owner → dirty tile/rectangle tracking → CPU/GPU buffer transfer → compositing/scaling → screen presentation → commit/cancel/undo. For every edge list source file/function/line permalink, thread, ownership, timing and whether data is durable or draft. Decide whether PhotoCraft uses a transient overlay, direct layer updates, GPU accumulation or a hybrid **from evidence**.

Specifically inspect how PhotoCraft uses 256px COW tiles, CPU reference compositor vs wgpu path, texture reuse/upload and zoom/LOD. Determine whether brush lag could block input; distinguish lost pointer events from interpolated geometry. Investigate clipping/selection masks and per-gesture undo.

## Target comparison
Trace these exact DrawInAtlas paths: `addons/drawing/canvas.gd` (`_gui_input`, `paint_to`, `_draw`, `finish_gesture`); `edit_session.gd:paint_path`; `document.gd:_publish_edit`; `renderer.gd:render`; `tools/benchmarks` and T-068. Identify confirmed GDScript algorithm costs vs architectural lack of draft preview, full viewport compositing, texture recreation, synchronous handlers and zoom amplification. Do not infer all failures from CPU raster arithmetic.

## Deliverable
Write `docs/PHOTOCRAFT_RENDERING_RESEARCH.md` with: (1) 300-word summary, (2) verified source execution graph, (3) pending-stroke lifecycle, (4) caching/upload/zoom/undo behavior, (5) component comparison and confirmed-vs-inferred findings, (6) Godot 4.8 design, (7) GDScript vs selective GDExtension decision, (8) small implementation sequence, (9) reproducible timing with median/p95 and per-stage measurements where runnable, (10) open unknowns/risks.

Compare options: optimized GDScript dirty tiles and live overlay; GDScript with Godot-native GPU compositing; opt-in narrow C++ kernels. Test 4/32/64px dabs, rapid/diagonal/crossing gesture, many layers, 100/50/25% zoom, cancel and undo, including Linux/Windows if practical. **Never** call frame submission input-to-photon, copy PhotoCraft source wholesale, or claim a faster native backend without full marshaling/publication/frame measurements.

Research should inform [[T-085]]/[[T-086]] but is **not their hard prerequisite**. Decisions must preserve standalone package isolation and byte-exact canonical Drawing pixels.
