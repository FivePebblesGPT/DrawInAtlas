# Bucket — current Drawing/Atlas workflow (T-072)

**Authority and availability (2026-11-02).** The owner-approved [47 Essential / 34 Later / 18 Skip inventory](DRAWING_FEATURE_INVENTORY.md) defines *scope*, not shipped tools or final UX acceptance. The [decision record](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [canonical Drawing package](../addons/drawing/README.md), [test plan](DRAWING_TEST_PLAN.md) and [Kanban](Index.md) take precedence over the archived workflow below.

The independently runnable `DrawingWorkspace` in `addons/drawing/workspace.gd` currently exposes **Brush, Eraser, Select, Move, Text, Pan**. Atlas embeds the same Drawing engine for raster editing (`T-055`), while some *older Atlas tools and tests* still execute against legacy `AtlasLayer` / `AtlasRasterLayer` paths. A working legacy test does not prove the corresponding standalone tool is shipped. Atlas owns map/floor/detail, selected-cell mask constraints, entrance navigation, and the global chronological history (`T-054`); Drawing owns generic documents, tools, local edit sessions, and snapping. **No per-hex DrawingDocument** exists.

A content gesture uses `DrawingDocument.begin_edit()` → bounded `DrawingEditSession` staging → `commit()` (one undoable operation), or `cancel()` (no changes). Atlas embeds with `set_external_history(true)` and registers the edit with `AtlasEditHistory.commit_drawing()`; standalone Drawing keeps local history. Selection-only history is an **application-level opt-in, OFF by default**, not an automatic content edit. When Atlas history replays, it restores the valid originating map/floor/detail, selection and mode, preserves zoom, and pans only if content is not visible. Navigation-only actions do not create undo entries.

The once-per-gesture swept brush, exact straight **RGBA8 including hidden RGB on unchanged transparent pixels**, per-pixel edit-scope clipping, and only-touched-tile copy-on-write are generic Drawing behaviors. `DrawingEditSession.apply_region(Rect2i, PackedByteArray)` is the **bounded edit-region native-acceleration boundary**, not evidence that Blend2D, Skia or a C++ GDExtension has shipped. `T-068` is **In Progress**; no native backend is selected. Source storage uses T-066's portable `Drawings/` generations rather than a current single-file native `.scn` raster save.

## Current implementation versus Bucket candidate

**Engine primitive available; standalone tool NOT shipped:** `DrawingEditSession.flood_fill(seed, rgba, selection, limit)` provides a bounded, four-connected edit within existing allocated raster pixels. Begin a session on the selected raster layer → stage `flood_fill()` → commit as one content history entry, or cancel/reject without a partial edit. `DrawingSelection` clips the region. This is an **API witness**, not a claim that the standalone palette exposes an F/Bucket button, tolerance slider, Shift/global mode or preview-on-release. `T-023` remains **Ready**, and its legacy Atlas raster Bucket candidate below is not approved as the final shared Drawing UX.

**Witnesses:** `tests/campaign_bundle_smoke.gd` and `tests/drawing_raster_backend_benchmark.gd` exercise canonical touched-region and persistence boundaries; `tests/bucket_smoke.gd` / `tests/bucket_visual.gd` test the **legacy Atlas** seed/tolerance/preview implementation. Contiguous/global UI, tolerance policy and native batch fill need their own implementation and review under T-023/T-059, not a completion claim here.

---

## Historical Atlas-era workflow and candidate notes (not a current Drawing UX contract)

The following is preserved for original ticket/acceptance traceability. Its use of **“current”, “implemented”, “native save”, tool shortcuts and old test counts refers to the pre-separation Atlas-era prototype**, unless a statement is explicitly confirmed in the current section above. See `docs/Index.md` for the actual ticket status.


### Reference and proposed interaction

Paint.NET is the primary tool reference: [Paint Bucket](https://paint.net/doc/latest/PaintBucket.html). It offers contiguous/global flood, tolerance, layer/image sampling, premultiplied/straight alpha matching, and live fill adjustments. This implementation adopts **active-layer sampling**, **four-connected contiguous by default**, an optional **global** mode, **premultiplied-alpha tolerance**, and a **preview-on-press / commit-on-release** gesture. It does *not* claim Paint.NET's live recoloring, draggable seed or combined-image sampling. The specific choices remain subject to owner acceptance under [[T-023]].

- **F / Bucket** selects the tool in the categorized sidebar. Its inspector offers raster tolerance from **0–100%** (0 = exact, initial default), a **Global** checkbox (off initially), and RGBA replacement color. **Shift+click** temporarily reverses the global/contiguous setting. Bucket routes to the raster layer at the current authored detail level; the retired palette-cell terrain kind is no longer a supported authoring target (T-050). No setting silently changes the currently authored detail level.
- For raster, contiguous searches **four-connected pixels** from the pressed seed. Global tests every **existing pixel in that same raster layer**, including disconnected chunks. Neither mode samples other layers, the composite image, ink outlines, map links, or terrain. Neighbors are compared to the **seed** color; tolerance cannot drift through a color gradient. Tolerance is the maximum channel delta of premultiplied red/green/blue plus alpha (normalized 0–1). Fully transparent pixels compare equal regardless of hidden RGB bytes, even at zero tolerance. Fill **replaces** matched RGBA pixels with the chosen RGBA color; it is not a source-over brush stroke.
- Raster space is finite wherever pixels have been allocated in stored chunks, including partial edge chunks. A click outside stored pixels rejects the fill rather than inventing infinite background. Transparent pixels *within* allocated image extents can be filled. A bounded cell-edit selection restricts affected raster pixels by their full transformed quad; no portion of a protected pixel is modified. The search stops at **262,144 eligible pixels** and rejects the entire transaction on overflow.
- The original 2026-10-30 Bucket candidate also described a terrain-palette flood. That prototype content plane was retired by [[T-050]]; current Bucket authoring is **raster only**, independent of grid cells. Grid rotation, zoom and pan never change stored raster geometry.
- A **left press** calculates an in-memory detached preview on the selected layer. This is a real framebuffer rendering, not a persisted change. **Release** applies the preview as one undoable command. **Escape**, tool/layer changes, window focus loss or a right/middle click cancel the pending preview. Seed and options are frozen from press to release; pointer motion while held does not move the seed. A successful preview also records its exact map, floor, layer ID and source layer metadata/content hashes; if any target context or source pixels change before release, the preview is discarded with a visible message instead of overwriting a newer edit. Unrelated-layer changes remain possible. Error messages distinguish missing raster pixels, locked/hidden layers, invalid bounds, stale targets, no-op and fill-limit overflow; none leave partial changes. Undo/redo preserves exact raster bytes.
- Existing direct `fill_at(point)` API remains a one-step commit for internal and compatibility callers. It uses the same policy as the pointer preview. No native-save schema is changed, and no background growth or implicit per-hex raster is introduced.

### Tests and remaining design decisions

- `tests/bucket_smoke.gd`: contiguous/global, tolerances and premultiplied-alpha, finite transparent regions, signed raster chunk seams, selection masks, lock/no-op/limit failures, inspector wiring, detached preview, stale history/source/target rejection, cancellation, undo/redo and native-save roundtrip.
- `tests/bucket_visual.gd`: native framebuffer pointer press/release, visible preview, Escape rollback, undo/redo, an interleaved history edit during a real pointer gesture, color-boundary isolation and compact 800×600 layout.
- Both tests run in `.github/workflows/godot-check.yml`, including strict engine-error-log checks. The rest of the domain, native, Web export and portability gates remain unchanged.
- **Review request:** confirm whether active-layer-only sampling, seed-matched premultiplied tolerance, alpha *replacement* rather than compositing, and the release-to-commit gesture match intended Bucket behavior. Other Paint.NET capabilities (live drag-to-reseed, composite sampling, global terrain fill, straight-alpha matching, pattern/blend-mode fills) are deliberately not assumed. Source-only readability simplification remains [[T-033]], not part of the behavioral change.

### Mask changes during a preview (2026-11-01)

The pixel candidate is authorized for the **edit mask that existed at press**.
A selected-cell change, enabling/disabling its lock, or rotating/changing its
grid footprint before release invalidates that candidate. Release clears it
without a history command, leaves source pixels unchanged, and reports that
the edit mask changed. Changing the highlighted cell while cell lock is off
is harmless and does not invalidate an unrestricted preview. Start a new
press to fill using the new mask. This safety rule does not add a selection or
mask to the persisted campaign format.
