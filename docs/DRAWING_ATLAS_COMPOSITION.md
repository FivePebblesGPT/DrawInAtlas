# Atlas ↔ canonical Drawing composition — T-055

**Implementation:** `scripts/interface/drawing_composition.gd` (`AtlasDrawingComposition`), `scripts/interface/canvas.gd`, `scripts/interface/editor.gd`, `scripts/interface/layer_panel.gd`, `scripts/interface/preview_panel.gd`. **Validated:** 2026-11-02, Godot 4.8-beta2 on Linux. **Status:** completed Atlas composition boundary, not production campaign persistence or final owner UX acceptance.

## Ownership and content identity

- `addons/drawing/` remains the **one** Drawing engine. The standalone `drawing/` project and the Atlas editor use its `DrawingDocument`, `DrawingEditSession`, `DrawingSelection` and renderer; none of these files imports Atlas. Atlas's adapter resolves **one internal DrawingDocument** per `(map_id, floor_id, detail_level)` through `AtlasDrawingRegistry` (T-061). Atlas still owns camera, entrances, grids, fog, tokens and maps; Drawing receives only raster-space edit/render requests.
- Atlas's layer panel projects **Map → Floor group → Detail group → Layers**, followed by separate Object instances. Legacy map artwork is temporarily shown in a compatibility hierarchy while migration happens incrementally. The generated document is *not* a user-facing independent tab. Ordinary standalone Drawing documents remain separate files.
- Higher authored detail has an explicit, independent pixel density. Missing D1 art neither inherits D0 pixels nor allocates a full-size transparent map. `AtlasWorldSpace` keeps integer world ticks; the edit session anchors pixel coordinates close to the gesture so large, signed map positions do not overflow view-relative brush arithmetic. Editing a map while zoom selection changes is always tied to the original map/floor/detail and canceled by a real map change.

## Native canvas input and global history

The editor passes live Brush/Eraser input to `AtlasDrawingComposition.start_stroke()`, `append_stroke()` and `finish_stroke()`. These methods open one generic edit transaction, hold its original world-to-pixel offset and color/width, and commit exactly **one Atlas global-history entry** through T-054. Cancel discards the pending pixel edits. The legacy painter is retained for compatibility tests and tool paths that have not yet migrated.

When `AtlasEditScope` supplies a polygon, the adapter converts it to a **bounded, gesture-local pixel selection**. This matters for negative and far signed coordinates: the generic `DrawingEditSession` tests local pixels, not absolute world pixels. Empty masks deny all, and masks exceeding the fixed candidate budget reject the gesture. Grid snapping remains Atlas's responsibility; Drawing knows only ordinary numeric coordinates and pixel selections.

A Painting tool owns clicks on top of entrances. Selection, Object-selection, Move or Pan may navigate only on a second click with the **same stable entrance ID**, within configurable 450 ms / 10 screen-pixel tolerance. Entrance IDs are sorted for deterministic overlaps, and stale IDs cannot trigger navigation. Single-click Pan does not move links. Canvas selection of an Object instance is by its own placement ID; a repeated object click opens the shared Object Editor through a typed Atlas bridge without changing the source until Save.

`AtlasEditHistory` remains the sole chronological history of Atlas commands and committed Drawing edits. T-054's context coordinator restores the map/floor/detail, valid selection/edit mode, and camera **pan only when needed**, without changing zoom. Preview requests never append history. Canonical painting finishes with the last in-canvas sample if the pointer exits into editor chrome; out-of-bounds mouse movements/releases never paint or produce duplicate history. Pan is a visible palette tool with the H shortcut.

## Linked Object Assets and read-only frames

`AtlasObjectLibrary` supplies the **independent source documents** in sibling `Objects/` files, private drafts and versions. `AtlasDrawingRegistry.visible_placements()` filters by exact map/floor/detail. Each instance has its own stable ID, transform and visibility. `AtlasDrawingComposition.place_asset()`, `select_instance()` and `render_region()` operate on these references; **the map's Drawing background is never implicitly a placed Object Asset**.

Flat source images can derive an authored rectangle from their sparse tile extent when explicit frame bounds are absent. Source Save publishes one revision visible at **all** linked placements; unsaved drafts do not affect any placement. Save As and undoable rebinding are handled by the existing T-060/T-062 bridge, not by cloning another Drawing engine. T-064 is responsible for deeply nested Object Assets and cycle checks; T-065 is responsible for a full Asset Browser and deletion UI.

`render_region()` requires an explicit, bounded pixel rectangle, renders the requested generic document and composes transformed linked sources. The returned `Image` is detached. The image cache keys include document/source/instance revisions and transforms, and invalidates on source publication, placement updates or undo/redo. Atlas previews derive framing from visible canonical sparse-tile addresses and transformed, signed Object Asset bounds, not exclusively from legacy map extents. Distant source art therefore remains visible in the read-only overview without mutating its document. Atlas canvases split the visible area into short-lived **128-pixel GPU upload tiles**; preview/overview callers use `preview()` directly, **without constructing an interactive AtlasCanvas**. The grid, navigation markers and interaction affordances draw in a higher overlay layer so opaque new ink cannot conceal them.

## Safety, limits, and deferred tickets

- Rendering and previews reject frames over **1,048,576 source pixels**; Atlas canvas avoids synthesizing more than **2,097,152 visible pixels** at once. At extreme zoom/density combinations the current implementation omits the canonical layer rather than risk unbounded allocations; this is **not** final large-world LOD performance. T-057/T-067/T-068 benchmark and optimize it. The current CPU transformed-object renderer skips source bounds over 2048×2048 or the same pixel cap; there is no native raster acceleration yet.
- **The legacy `.scn` Save does not durably store canonical DrawingDocuments.** The editor warns instead of falsely marking these edits saved. T-066 must implement the campaign index, `Drawings/` sparse manifests/chunks, `Objects/` generations, portable fonts and recovery. Closing T-055 does **not** imply save/reload completeness.
- New Object instances are distinct from the legacy board background; no complete Asset Browser, NULL deletion workflow, Windows runtime or owner UX acceptance is claimed here. T-056 remains an **owner-review-gated validation ticket**, not automatically Done.
- The linked-maps UI smoke suite initially had two legacy footprint-dialog assertions failing on both the unchanged pre-T-055 commit `ba8df2f` and this branch. Its manually injected fixture now explicitly selects the stable entrance ID before opening the form; all **58 checks pass**. Historical raster assertions in `smoke.gd`, `tools_ui_smoke.gd` and `linked_maps_ui_smoke.gd` intentionally detach the canonical canvas adapter so that migration does not erase legacy-path coverage.

## Reproduction

```bash
# Godot import / typed scripts
godot --headless --editor --path . --import --quit
python3 tests/check_explicit_types.py

# Live editor, signed/detail/asset, private-publication, entrance and history witness
godot --headless --path . --script res://tests/drawing_composition_smoke.gd
# T055_COMPOSITION_PASSED checks=89 failures=0

# Real software GPU/framebuffer, composed ink, blank D1, overlays and redo
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_composition_visual.gd
# T055_NATIVE_PASSED checks=13 failures=0

# Existing independent package and historical Atlas tests
python3 -m unittest discover -s tests -p 'test_drawing*.py'
godot --headless --path . --script res://tests/drawing_world_mapping_smoke.gd
godot --headless --path . --script res://tests/drawing_history_smoke.gd
godot --headless --path . --script res://tests/object_assets_smoke.gd
godot --headless --path . --script res://tests/object_editor_smoke.gd
python3 tools/validate_ticket_store.py
```

All new checks are integrated into `.github/workflows/godot-check.yml` (headless and software-framebuffer). The CI workflow has **not** been independently confirmed green on GitHub because the local branch is not pushed.
