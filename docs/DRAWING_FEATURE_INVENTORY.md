# Drawing feature inventory — Paint.NET / PhotoCraft comparison

**Status: OWNER-APPROVED FEATURE INVENTORY (2026-11-02).** The owner explicitly approved the complete Essential/Later/Skip matrix as the Drawing product-scope plan. Approval sets scope and priorities; it does **not** claim the features are implemented, tested, or visually signed off.

**Scope:** Independent, reduced-feature Drawing application/package reused by Atlas for map art and Object Asset editing. Paint.NET is the primary *interaction* reference; PhotoCraft is a reference for editable text, more advanced layers, vectors, masks and effects. **Do not attempt full feature parity with either editor.**

Related: [[T-059]], [[T-051]], [[T-052]], [[T-053]], [[T-058]], [[T-060]], [[T-062]], [[T-063]], [[T-065]], [[DRAW_MODULE_UI_SPEC]], [[DECISIONS_DRAWING_ATLAS_2026-11-01]].

## Interpretation and authority

- **Essential:** **approved** for the complete reduced-feature Drawing baseline; **not** automatically a prerequisite for the tiny T-053 end-to-end vertical slice. Items specifically tagged approved were also settled under the prior owner decision/ticket.
- **Later:** **approved as deferred priorities**, to be considered through separate bounded implementation tickets once core workflows are usable; this is not a commitment to implement all Later items in the initial release.
- **Skip:** **approved as excluded from the initial reduced-feature scope**. A future owner request can reopen a specific case.
- **Reference** means inspiration/capability family, **not** identical behavior or verified current version-to-version parity. Paint.NET's traditional text is rasterized after commit; editable one-element text layers here come from PhotoCraft and approved DrawInAtlas requirements. PhotoCraft calls itself early alpha.
- This document **does not override** the approved contracts for one generic DrawingDocument per Atlas map/floor/detail (Option B), sparse multi-file `Drawings/` and `Objects/` persistence, one text per layer, private Object Editor drafts, Save/Save As rebinding, retained saved variants, history, missing authored detail, NULL assets or Windows/Linux-first delivery.
- The proposed one-row top bar and layout details still need native UX validation under T-063. Existing approved Object Editor and Asset Browser choices remain approved.

## Comparative feature matrix

Every row is an independent scope choice and rationale. The labels `Both` and `PhotoCraft` describe broad product references, not necessarily identical implementations.

### Workspace, navigation and documents

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| New/Open/Save/Save As | Both | Essential | Standalone drawings and asset documents need round-trip file I/O. |
| Native layered document codec | Both | Essential | Preserve layer IDs, groups, editable text, alpha, and undo-safe savepoints. |
| Document tabs and unsaved-close prompts | Both | Essential | Support multiple drawings and dedicated Object Editor tabs without losing drafts. |
| Fixed menus, common shortcuts and visible shortcut labels | Both | Essential | Provide familiar command access without an extra quick-action toolbar row. |
| One-row contextual tool options and BarDivider | Project UI proposal | Essential (proposed UX) | Prototype T-063 fixed menus plus horizontally scrolling tool options; require owner UX sign-off. |
| Compact tool rail; Colors/Layers/History docks | Both / project UI proposal | Essential (proposed UX) | Keep primary controls visible while maximizing canvas space. |
| Asset Browser dock | Project T-065 | Essential (approved) | Browse linked, unused and missing Object Assets; same dock behavior as peer panels. |
| Panel resize/show/hide and keyboard access | Both / project | Essential | The workspace needs usable layouts on small and large displays. |
| Fully floating docks and persisted custom layouts | PhotoCraft-style | Later | Fixed resizable docks are sufficient initially; T-063 phase 3 can evaluate customization. |
| Pan, zoom, fit view, cursor-centric zoom | Both | Essential | Required for drawing and inspecting large art. |
| Transparent checkerboard and zoom/cursor status | Both | Essential | Make alpha and canvas location clear, particularly in reusable assets. |
| Pixel grid and basic grid display | Both | Essential | Useful for precise raster work and visual alignment. |
| Rulers and user-defined guides | Both | Later | Useful for advanced layout, but basic snapping comes first. |
| Generic pixel/guide/object snapping | Both / project T-052 | Essential | Drawing owns snap behavior; Atlas may supply candidate geometry without leaking Atlas types. |
| Canvas crop/resize/rotate | Both | Later | Useful for bounded standalone images; must not silently redefine Atlas's continuous world art. |
| View rotation | PhotoCraft | Later | Helpful for freehand strokes but introduces input/coordinate complexity. |
| Undo/redo and History dock | Both | Essential | Every committed gesture is reversible and commands retain stable edit context. |
| Unbounded history with no memory policy | Paint.NET-inspired | Skip | Use bounded/managed history for sparse very large documents. |
| User-configurable shortcut bindings | Both-style | Later | Start with predictable and documented defaults. |

### Raster drawing, fills and brushes

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| Paintbrush with size, opacity and hardness | Both | Essential | Basic freehand drawing with alpha-correct compositing. |
| Pencil / hard pixel brush | Both | Essential | One-pixel precision and sharp symbol/edge drawing. |
| Alpha eraser | Both | Essential | Clear pixels rather than painting background color. |
| Paint bucket / flood fill | Both | Essential | Fast region coloring; respect layer, selection and edit scope. |
| Eyedropper from layer or visible composite | Both | Essential | Reuse colors quickly, with explicit sampling mode. |
| Straight lines and basic editable-while-drawing curves | Paint.NET | Essential | Roads, rivers, outlines; commit ordinary art as raster. |
| Rectangle, ellipse and polygon drawing | Both | Essential | Common drafting tools; keep ordinary shapes raster unless explicitly semantic. |
| Basic stroke smoothing | PhotoCraft | Essential | Improve mouse/pen quality without building a complex wet-paint engine. |
| Brush presets and quick size shortcuts | Both | Essential | A small starter set and obvious size controls are enough initially. |
| Gradient tool including transparency | Both | Later | Useful for shading; not critical to baseline painting. |
| Magic Wand / color-based selection | Both | Later | Useful for editing regions after flood fill works reliably. |
| Clone Stamp | Both | Later | Supports copying textures or repeated art. |
| Recolor existing pixels | Paint.NET | Later | Saves repainting terrain or variants. |
| Pen pressure and tilt | Both / PhotoCraft advanced | Later | Valuable to artists, but stabilize mouse input first; tilt is optional after pressure. |
| Import/define custom brush tips | PhotoCraft | Later | Support purpose-built terrain and symbol brushes. |
| Scattering/texture terrain brushes | PhotoCraft | Later | Forest, grass, rocks and roads offer high domain value. |
| Smudge/Dodge/Burn/Sponge | PhotoCraft | Later | Optional illustration polish; lower impact than selections and asset editing. |
| Mixer brushes, dual brushes and wet-media simulation | PhotoCraft | Skip | Large brush-engine cost for limited map-editor benefit. |
| Healing/Patch/Red-eye retouching | PhotoCraft | Skip | Photo restoration is not a core product task. |
| History Brush / Art History Brush | PhotoCraft | Skip | Undo plus ordinary repainting should cover the primary need. |
| AI subject/background selection | PhotoCraft | Skip | Adds model/runtime/UX complexity unrelated to core map authoring. |

### Selections, moving and transformations

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| Rectangle and ellipse marquee | Both | Essential | Fast bounded-region manipulation. |
| Freehand lasso | Both | Essential | Support irregular regions. |
| Replace/add/subtract/intersect selection modes | Both | Essential | Compose useful masks and disjoint regions. |
| Selection and selected-pixel movement as distinct operations | Paint.NET | Essential | Moving the outline must never implicitly move layer pixels. |
| Selection boundary visualization, invert, deselect and select all | Both | Essential | Discoverable selection lifecycle. |
| Cut/copy/paste and duplicate selected content | Both | Essential | Basic raster/object editing and clipboard workflows. |
| Selected-region clipping of paint, fill and erase | Both / Atlas | Essential | Also underpins Atlas's restrict-to-current-cell mask. |
| Move/scale/rotate of selected layers, objects and instances | Both | Essential | Fundamental authoring and Object Asset placement. |
| Feather/expand/contract selection | Both | Later | Useful for soft edges, masking and corrections. |
| Quick Selection and sophisticated edge refinement | PhotoCraft | Later | Evaluate only after Magic Wand and basic lasso perform well. |
| Perspective, mesh warp and liquify | PhotoCraft | Skip | High implementation cost and little map workflow relevance. |

### Layers, text, semantic paths and object editing

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| Layer create/delete/rename/duplicate/reorder | Both | Essential | Foundational layer operations with stable identities. |
| Layer visibility, lock and opacity | Both | Essential | Control compositing and protect content. |
| Nested generic groups | PhotoCraft | Essential (approved) | Atlas floor/detail hierarchy must not be hard-coded into Drawing's layer model. |
| Normal alpha compositing | Both | Essential | Deterministic first compositing path. |
| Common blend modes: Multiply/Screen/Overlay and more | Both | Later | Useful for shading, but needs compositor tests and saved-model semantics. |
| Layer tree search, compact rows, virtualization and scroll-to-selection | Project T-058 | Essential (approved) | Thousands of one-label-per-layer records must remain usable. |
| Multi-layer selection, align/distribute/link | PhotoCraft | Later | Batch operations improve productivity after basic layer actions stabilize. |
| Exactly one editable text element per text layer | PhotoCraft / project T-058 | Essential (approved) | A text layer appears on first successful text commit, not tool selection. |
| Font/size/style/color/alignment for text | Both | Essential | Minimum map-label styling; keep text editable. |
| Advanced paragraph leading/tracking/layout | PhotoCraft | Later | Useful for long captions, not necessary for first label workflow. |
| Explicit undoable rasterize text layer | PhotoCraft / project T-058 | Essential (approved) | Preserve display and restore editability through undo; never silently flatten. |
| Portable licensed font bundling and safe fallback | Project T-058 | Essential (approved) | Text remains portable; do not embed unlicensed system fonts. |
| Image / reusable object layers | PhotoCraft / project | Essential (approved) | Source art can be reused without baking into a map's raster layer. |
| Editable semantic wall/open/closed paths | Project | Essential | Object geometry requires editable points and handles, unlike ordinary raster lines. |
| General resolution-independent vector shapes | PhotoCraft | Later | May help reusable symbols; do not force every raster line to become a vector object. |
| General Pen/path tooling with Bézier anchor editing | PhotoCraft | Later | Useful beyond the minimum semantic-path editor. |
| Vector path boolean operations | PhotoCraft | Skip | A large separate vector-geometry subsystem for a low-frequency need. |
| Non-destructive raster layer masks | PhotoCraft | Later | Desirable for composition, but selection masks and transparency suffice initially. |
| Clipping masks | PhotoCraft | Later | Improves contained shading and decorative edits. |
| General vector masks | PhotoCraft | Skip initially | Defer beyond basic raster masks and semantic path needs. |
| Live adjustment layers | PhotoCraft | Later | Add only a few high-value adjustments after core document transactions stabilize. |
| Separate generalized Smart Object system | PhotoCraft | Skip | DrawInAtlas already has an approved Object Asset and linked-instance model. |
| Simple text stroke/shadow/glow styles | PhotoCraft | Later | Useful for label legibility; avoid full effects framework at first. |
| Bevel/emboss/satin and complex layer style engine | PhotoCraft | Skip | Primarily advanced photo/design features. |

### Colors, adjustments and effects

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| RGBA + RGB/HSV/hex color entry | Both | Essential | Precise colors and alpha are necessary for painting. |
| Saved swatches / compact palettes | Both | Essential | Repeated map colors should be reusable. |
| Brightness/Contrast and Hue/Saturation | Both | Later | High-value recoloring for imported assets. |
| Desaturate/Black & White | Both | Later | Simple conversion for stylistic reuse. |
| Gaussian Blur and basic Sharpen | Both | Later | Useful for shadows and imported art; not essential for first editor. |
| Curves/Levels | Both | Later | More complex color correction of imported material. |
| Live in-canvas filter preview | PhotoCraft | Later | Implement with each actually supported filter. |
| Full distort/noise/render filters catalogue | Both | Skip | Do not duplicate hundreds of effects; revisit individual domain-specific needs. |
| Lens flare/red-eye/photo restoration effects | Both | Skip | Poor fit for map and object authoring. |
| Smart filter stacks | PhotoCraft | Skip | High compositing and persistence cost. |
| Color-managed CMYK/Lab/HDR/32-bit pipeline | PhotoCraft | Skip initially | Use a reliable sRGB/RGBA workflow; treat embedded-profile handling separately if needed. |

### File interchange and extension points

| Feature | Reference | Choice | Reason |
|---|---|---|---|
| Lossless WebP import/export and canonical artwork payloads | Both / project | Essential | Current DrawInAtlas artwork contract requires lossless WebP; keep data lossless. |
| PNG import/export with alpha | Both | Essential | Most useful transparent image interchange format. |
| JPEG import | Both | Essential | Common reference-image input. |
| JPEG export | Both | Later | PNG covers initial export; flattened JPEG is convenient afterwards. |
| Raster clipboard paste/import | Both | Essential | Quick import of screenshots and props. |
| SVG import as object / rasterized import | PhotoCraft | Later | Useful for icons; specify whether vector preservation is supported. |
| OpenRaster read/write of layered art | PhotoCraft | Later | Pragmatic layered interchange candidate. |
| Paint.NET PDN layered import | Paint.NET / PhotoCraft importer | Later (conditional) | Only if users need migration; avoid implying full round-trip support. |
| PSD/PSB/TIFF/XCF/KRA comprehensive compatibility | PhotoCraft | Skip initially | Complicated editable interchange can dominate the product scope. |
| HEIC/AVIF/OpenEXR/FITS and niche codecs | PhotoCraft | Skip initially | PNG/JPEG/WebP handle expected workflows. |
| Third-party effect/plugin API | Paint.NET | Skip initially | Stabilize generic Drawing package public API before plugins. |
| User-facing script/CLI/agent control channel | PhotoCraft | Later | Shared internal commands now; external automation protocol only if demand is clear. |
| Web editor release in desktop-first milestone | PhotoCraft | Skip for now | Windows/Linux first; do not equate deferral with permanent cancellation. |

## Atlas-specific features and non-negotiable boundaries

| Capability | Scope | Why and governing ticket |
|---|---|---|
| Standalone Godot Drawing app + one reusable package | Approved / essential | Same canonical engine must run without Atlas. T-052/T-053. |
| Atlas maps `(map, floor, detail)` to one internal generic DrawingDocument | Approved / essential | No `Floor` or `LOD` types inside Drawing; no extra user tabs for internal D-level documents. T-051/T-061. |
| Sparse signed raster chunks, lazy loading and multi-file persistence | Approved / essential | Huge negative/positive world coordinates without giant blank allocations; `Drawings/` on disk is sparse too. T-052/T-066. |
| Separate authored detail groups and shared map-world coordinate reference | Approved / essential | Explicit pixel density per detail; blank missing detail remains blank while grid/navigation overlays stay visible. T-051/T-061. |
| Reusable Object Asset sources in `Objects/` and Atlas instances | Approved / essential | Asset-local geometry and per-instance transforms; map background artwork is distinct. T-060. |
| Dedicated Object Editor document tab | Approved / essential | Reuse Drawing engine; do not build second painter. T-062. |
| Draft edits private until explicit source Save | Approved / essential | Linked instances render last published source until Save. T-062. |
| Save As from instance A makes new B and rebinds A alone | Approved / essential | Other instances still use original; standalone Save As rebinds none. T-060/T-062. |
| Atlas undo of Save As retains saved B | Approved / essential | Undo restores A's previous link; redo uses same B ID; B stays browsable even if unreferenced. T-060/T-065. |
| Nested Object Asset references with acyclic graph | Approved / essential, staged | Flat objects first; guard reference cycles, missing children and cache invalidation. T-064. |
| Asset Browser and NULL broken-reference proxies | Approved / essential | Include unreferenced variants and explicit delete/remove/NULL/cancel policy. T-065. |
| One editable text element per layer + explicit undoable rasterization | Approved / essential | Do not create empty text layers on tool selection; keep grouping/search fast. T-058. |
| Bundled redistributable fonts with stable IDs | Approved / essential | Portable editable text; handle missing/unlicensed fonts safely. T-058/T-065. |
| Generic snapping owned by Drawing | Approved / essential | Atlas may supply candidate constraints without importing grid classes. T-052. |
| Global Atlas undo with contextual navigation, selection and mode restoration | Approved / essential | Preserve zoom; selection-only history is app-wide opt-in OFF by default. T-051/T-054. |
| Painting gesture input wins over entrance navigation | Approved / essential | Entrance double-click navigates only through appropriate selection/pan modes. T-051/T-055. |
| Native Windows/Linux first; Web separately decided | Approved milestone scope | Do not block initial standalone app on browser export. T-051/T-053. |

## T-073 implementation ledger — scope approval is not delivery (2026-11-02)

**Source of authority:** the 99 comparison rows above are the owner's **47 Essential / 34 Later / 18 Skip** priorities. Do not reclassify or delete them when an engineering ticket finishes. `[[T-059]]` retains the separate **hands-on final UX gate**; this documentation ledger is not owner acceptance. `[[DRAW_MODULE_UI_SPEC]]` remains a **proposed** workspace composition under `[[T-063]]`, whereas the dedicated Object Editor tab (`[[T-062]]`) and a dock-peer Asset Browser requirement (`[[T-065]]`) are **accepted requirements**. The tab is implemented; the Asset Browser dock is still blocked on T-063.

### First slice: bounded T-053 witness (implemented and tested)

| Check | What must work | Automated witness / observed boundary |
|---|---|---|
| [x] Standalone isolation | Start `drawing/project.godot` without Atlas imports; reuse `addons/drawing/` as the sole canonical editable package | `drawing/tests/standalone_smoke.gd`; `tests/test_drawing_app.py` and third consumer |
| [x] Document and group | New drawing creates a generic group and editable raster layer with stable IDs | `drawing/tests/standalone_smoke.gd` |
| [x] Fundamental pointer operations | Brush, Eraser, rectangle Select, pixel Move, undo/redo | `drawing/tests/standalone_smoke.gd`; viewport-delivered input + framebuffer: `drawing/tests/native_pointer.gd` |
| [x] Lossless portable witness | Save/reopen `.drawing` with exact RGBA8 including hidden RGB at zero alpha, same document/group/layer IDs | `drawing/tests/standalone_smoke.gd` |
| [x] One shared Object Editor shell | A dedicated tab edits an independent source, without Atlas drawing engine copies | `drawing/tests/object_editor_ui_smoke.gd`; Atlas publication/rebinding separately in `tests/object_editor_smoke.gd` (T-062) |

**Do not expand the minimum witness retroactively:** the first four checks justify T-053's completed vertical slice; the Object Editor integration was added later under T-062. Completion of these checks does **not** close the 47 Essential items or T-059.

### Remaining complete-baseline work (bounded follow-on tickets)

Use this as a **coverage checklist**, not as a replacement for the 99-row approval matrix. Mixed rows require a real acceptance demonstration before their entire capability can be checked.

| Baseline area | Current measured state | Owner-approved outcome still to verify / governing work |
|---|---|---|
| [ ] Drawing tool breadth | Standalone palette has **Brush, Eraser, Select, Move, Text, Pan**; generic edit APIs implement additional operations | Ship and pointer-test Bucket/Fill (T-023), Line (T-024), Polygon (T-025), Wall Path (T-026), and outstanding text UX/culling (T-027); inventory also asks for pencil, ellipse, eyedropper, presets, smoothing, selection modes and clipboard UX |
| [ ] Selection and transforms | Rectangle selection and moving its pixels work; signed-region clipping is tested | Distinguish moving selection bounds from pixels; expose approved lasso/ellipse, add/subtract/intersect, cut/copy/paste, scale/rotate and lock-aware interaction consistently |
| [ ] Full document/layer workflow | Groups, text layers, search/paged tree, exact file round-trip, undo and Save As exist | Verify ordinary commands and keyboard focus, large layer tree, visibility/lock/opacity/reorder and empty/cancel behaviors in native UI; T-059 final usability gate |
| [x] Editable text engine and shared source tab | One text element/layer and explicit undoable rasterization implemented (T-058); dedicated Object Editor tab/private Save drafts implemented (T-062) | Additional generic text-placement UX remains tracked by T-027; this check is **not** its closure |
| [ ] Object Asset browse and safety | Versioned sources, instances, saved variants, NULL registry semantics and bound Save As implemented (T-060/T-062) | Nested cycle-safe references T-064; **Asset Browser as a normal dock peer** incl. search, unused variants, NULL repair and deletion choices T-065; do not treat registry methods as an implemented dock |
| [x] Atlas mapping, composition and campaign store | Shared signed world documents, blank details, overlays, global history, compressed generation saves and recovery have tests (T-054/T-055/T-061/T-066) | Owner hands-on independent Atlas/standalone acceptance T-056 remains open; pending packed writer/native acceleration does not erase tested storage |
| [ ] Compact workspace and accessibility | A shared tabbed Drawing workspace exists, with a menu/options row, rail and Colors/Layers/History tabs | Prototype and test full fixed-menu `BarDivider` overflow, focus, discoverable shortcuts, resize and dock parity under T-063; final user evaluation under T-059 |
| [ ] Desktop release validation | Linux standalone release export and software framebuffer checks exist | Windows native pointer/keyboard/export test and owner hands-on usability T-056/T-059; no implied Web requirement |

The full approved baseline includes many items not individually listed here; the comparative matrix above remains exhaustive. Later/Skip rows are not silently promoted when adjacent Essential items are implemented.

### Pointer, keyboard and discoverability acceptance matrix

Each case starts with a **real UI entry point** and an observable result. A cited test covers only the stated behavior; `Pending native UX` needs a human walkthrough at ordinary and narrow window sizes (see `[[DRAW_MODULE_UI_SPEC]]` and `[[T-059]]`).

| ID | Pointer/keyboard sequence | Observable assertion | Evidence / disposition |
|---|---|---|---|
| UX-01 | Open Drawing, click **Brush**, drag across canvas; switch to **Eraser** and drag back; press `Ctrl+Z`, then `Ctrl+Y` | One committed edit per gesture; eraser undone/redone; saved RGBA8 remains exact | `drawing/tests/standalone_smoke.gd`, `drawing/tests/native_pointer.gd`, `drawing/tests/workspace_keyboard_smoke.gd`; core tested |
| UX-02 | Click **Select**, drag a rectangle; click **Move**, drag its pixels; undo | Selection rectangle and moved pixels are distinct; movement undoes without shifting artwork outside the selection | `drawing/tests/standalone_smoke.gd`; selection-mode breadth still pending |
| UX-03 | `Ctrl+N` then use **File → Save**; reopen via **File → Open**; select a tab and click `×` with unsaved changes | Independent tab, saved exact IDs/pixels, visible dirty indicator, Save/Discard/Cancel decision | `drawing/tests/standalone_smoke.gd`, `drawing/tests/workspace_keyboard_smoke.gd`, `drawing/tests/object_editor_ui_smoke.gd`; full keyboard/dialog native UX pending |
| UX-04 | Click **Text** and cancel, then commit label and select **Layer → Rasterize text layer**; press `Ctrl+Z` | Cancel does not add a layer; a single editable element is created on success; undo restores text layer | `drawing/tests/text_editor_smoke.gd`; additional T-027 text UX pending |
| UX-05 | From Atlas instance A open dedicated Object Editor tab; edit source; Save; Save As B; undo rebind | Draft is private until Save, linked instances receive saved updates, Save As rebinds A only, B survives undo | `tests/object_editor_smoke.gd`; Asset Browser browse/relink in T-065 pending |
| UX-06 | With a small window and high UI scale, Tab through menu and tool options; use Shift+wheel/touchpad overflow, change tools, focus last hidden control | No wrap, no invisible focus, discoverable overflow, scroll reset, no accidental slider adjustment | **Pending native UX — T-063/T-059** (not demonstrated by existing compositor tests) |
| UX-07 | Open/close, resize and keyboard-focus **Asset Browser** like Colors/Layers/History; find unused B and a NULL instance | Dock parity, retained B visible, explicit repair/delete/remove/NULL/cancel choices | **Accepted requirement; pending UI — T-065/T-059** |
| UX-08 | In Atlas, paint over an entrance, switch to selection/pan and double-click entrance; switch to blank D1; undo remote-map paint | Painting wins over navigation; blank art stays blank with grid/entrances; history restores mode/map without changing zoom | `tests/drawing_composition_smoke.gd`, `tests/drawing_world_mapping_smoke.gd`, `tests/drawing_history_smoke.gd`; owner walkthrough T-056 |

**Current key routing, not a UI promise:** `addons/drawing/workspace.gd` handles `Ctrl`/`Meta+N/O/S/Z/Y/W` and `Ctrl`/`Meta+Shift+Z` (redo). It currently sends `Ctrl+Shift+S` to the normal **Save** handler, **not** Save As; menu items also lack visible shortcut labels. The final UX must show discoverable labels and correct this binding under T-063. `Ctrl+Y` and `Ctrl+Shift+Z` both work today; choose/document one *primary* redo shortcut during T-063, rather than treating either as owner-approved. Do not claim that the proposed eight menus, per-tool options, or Asset Browser dock are already shipped.

## Minimum T-053 slice versus complete baseline

**Minimum implementation witness (do not wait for every 'Essential' row):** launch Drawing without Atlas; create a document and generic group/layer; paint/erase; select/move; undo/redo; save/reopen with identical alpha, pixels and stable layer identity. Prove package-consumer isolation and real pointer interactions.

**Complete reduced-feature baseline:** add the rest of the essential tools and document commands, editable text/semantic objects, suitable layer navigation, approved Object Asset integration and persistence, then obtain owner hands-on acceptance. Treat optional filters, advanced brush mechanics, masks and extra codecs as bounded follow-on work.

## Tool interaction, shortcuts and discoverability

- Show exactly the supported controls for the active tool; sample UI options in `DRAW_MODULE_UI_SPEC` are illustrative, **not** automatic feature commitments.
- Primary controls: Brush (preset/size/opacity/hardness; smoothing only when implemented), Eraser (size/opacity/hardness), Shapes (fill/stroke/width), Selection (replace/add/subtract/intersect), Text (font/size/style/alignment/color), Move (position/scale/rotation).
- Fixed File/Edit/View/Image/Layers/Select/Window/Help menus on the proposed compact top row; contextual tool options scroll horizontally with discoverable overflow, keyboard focus tracking and no accidental wheel-driven slider changes (T-063).
- Standard commands: New `Ctrl+N`, Open `Ctrl+O`, Save `Ctrl+S`, Save As `Ctrl+Shift+S`, Undo `Ctrl+Z`. **Choose and document exactly one default redo shortcut** (`Ctrl+Shift+Z` or `Ctrl+Y`) before final UX sign-off; other platform conventions may be aliases.
- Show tooltips and shortcuts in menus/rail, visible selection boundaries and layer lock/visibility states. Keep selection distinct from the active layer, Atlas floor group and current edit-target document.
- Tool choice, cancelled gestures, empty text edits and panel focus should not dirty documents. Content changes become one undoable edit; global selection-only history is opt-in OFF by default.
- Prevent applying edits to hidden or locked layers; enforce selection/edit-scope masks and explicit layer targets. Respect pan/navigation gestures and precise world coordinates.
- Clarify whether commands operate on the selected layer or visible composite (especially eyedropper and flood fill); don't silently alter unrelated layers.

## Usability acceptance flows (owner walkthrough, not tests-only signoff)

1. **Ordinary drawing:** start standalone Drawing; create a file/group/layer; paint, erase, fill and add shapes; select/move pixels; undo/redo; save/reopen; verify alpha and IDs.
2. **Selection semantics:** drag selection outline without moving pixels, then move selected pixels; test add/subtract/intersect and layer/selection clipping.
3. **Text lifecycle:** choose Text and cancel without producing a layer; commit one label; edit same text; rasterize; undo to regain text editability; verify bundled/missing fonts.
4. **Large layer tree:** open a document with thousands of one-text-per-layer labels; search/group/navigate/scroll-to-selection quickly; keep Atlas floor group selection distinct.
5. **Snapping and geometry:** draw at negative and distant coordinates, with and without grid candidates, ensuring stable world position and selection boundaries.
6. **Object source vs instances:** author source castle; place A and B; source Save updates both only after publication; Save As through A creates B-variant and rebinds A alone.
7. **Undo retained variant:** Undo that Save As restores original link without deleting new variant; redo uses same new asset ID. Verify browsing the unreferenced variant after reload.
8. **Atlas detail/navigation:** switch floor/detail; blank high detail contains no lower-level art but keeps grid/entrance overlays; painting takes priority over entrance input.
9. **Global undo:** undo edit from another map/floor/detail; focus relevant selection/mode with existing zoom preserved and without producing a navigation history command.
10. **Portable save/recovery:** relocate campaign file plus `Drawings/`, `Objects/` and licensed fonts; test missing/corrupt chunks, lost assets/NULL proxies, staged save failure and recovery.
11. **Compact workspace:** normal/narrow windows, high scaling, horizontal option overflow, keyboard tab focus, unsaved-tab prompt and dock resizing using actual pointer/keyboard input.

## Reference material

- [Paint.NET tools](https://www.getpaint.net/doc/latest/ToolsWindow.html)
- [Paint.NET tool settings](https://www.getpaint.net/doc/latest/Toolbar.html)
- [Paint.NET selection modes](https://www.getpaint.net/doc/latest/SelectionTools.html)
- [Paint.NET layers](https://www.getpaint.net/doc/latest/WorkingWithLayers.html)
- [PhotoCraft repository and feature catalogue](https://github.com/storytold/photocraft)
- [T-059 ticket](Tickets/T-059.md)
- [Drawing UI specification](DRAW_MODULE_UI_SPEC.md)
- [Approved Drawing/Atlas decisions](DECISIONS_DRAWING_ATLAS_2026-11-01.md)

**Owner sign-off (2026-11-02):** The complete 99-item Essential/Later/Skip inventory is **approved as written** (47 Essential, 34 Later, 18 Skip). Use it as the scope authority for Drawing feature planning. Preserve T-053's small initial standalone vertical slice; implement the Essential baseline incrementally. Later features remain deferred, Skip features remain out of initial scope. The separately proposed [[DRAW_MODULE_UI_SPEC]] still needs actual native UX validation; approval of this feature matrix is not implementation or usability acceptance. No acceptance based only on a passing test count.
