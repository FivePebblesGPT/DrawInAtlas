# Drawing / Atlas architecture — owner decisions (2026-11-01)

**Status:** owner direction recorded through Round 3. The *target design* is not implemented. Remaining cross-cutting details are explicit in [[T-051]]; detailed Painting UX features still await [[T-059]]. Epic: [[E-009]].

## Accepted Round 1–2 decisions
1. **Drawing** is a physically independent, reduced-feature PhotoCraft/Paint.NET-style application and library. Its exact feature inventory will follow.
2. Drawing artwork can be authored and saved without any Atlas campaign/map.
3. Atlas organizes logical floors over Drawing layers; there is no Atlas floor type in Drawing.
4. Drawing owns snapping tools and logic; Atlas can supply generic candidate geometry/constraints.
5. Atlas manages world surfaces, authored detail/LOD and navigation; Drawing edits and renders supplied content. Native rendering libraries are candidates, not required solutions.
6. Text creates an **editable text layer on its first successful content commit**, not merely tool selection; users may later rasterize it.
7. Painting clicks paint, even above a map entrance. Double-click the same entrance with Selection/ObjectSelection or Pan to navigate.
8. Atlas retains **one global ordered undo/redo timeline**. Standalone Drawing has its own local undo service without importing Atlas.
9. **No historical user saves exist to migrate**: no migration task, backwards-compatibility requirement or destructive-conversion pipeline; new files still require safe save/load/recovery.
10. Drawing is **physically independent**, not just a well-structured namespace.

## Accepted Round 3 decisions (2026-11-01)
11. **Monorepo:** independent Drawing Godot project and reusable Drawing package in the **same repository** as Atlas. Do not create a separate Git repository by default.
12. **Both reuse modes:** reuse artwork as a **linked live shared asset** or make an **independent copy**. The user-facing operation must make this distinction clear.
13. **Floor = layer group:** one logical Atlas floor maps to a Drawing layer group. Atlas owns floor metadata and mapping, not Drawing.
14. **Missing authored LOD = blank:** display **no lower-detail artwork underneath** an empty higher-detail level. Atlas can show an explicit empty-detail status/navigation UI; it must not fabricate lower-level art.
15. **Shared world-coordinate reference:** all authored detail levels of a given map align to one continuous world coordinate system. Detail levels may have different raster pixel densities.
16. **Cross-map undo navigates:** when a global undo affects the edit recorded on map A while viewing map B, navigate to A to reveal the result.
17. **One text element per layer.** Explicit rasterization converts that layer to raster content in one undoable operation.
18. **Web support may be dropped**, but has **not** been definitively dropped. Do not treat Web compatibility as an unconditional blocking gate for the new architecture; make desktop/Web release targets an explicit final choice.

## Proposed decomposition (engineering hypothesis, NOT an additional owner decision)
```text
One repository
  Independent Drawing Godot application
      -> One reusable Drawing library/package
             DrawingDocument + raster/text/object layer groups
             pixels, snapping, painting, selection, rendering,
             document file I/O and local edit transactions
  Atlas Godot application -> same Drawing package/API
             asset registry (linked vs copied)
             map bindings/transforms, floor -> layer-group mapping
             authored-detail selection, world navigation/grid
             entrance hit testing, global undo and project storage
```
**One canonical Drawing implementation** must serve both projects. Godot project boundaries and actual source/import layout remain a T-051 layout spike because the repository currently uses `project.godot` at its root. A nested project directory alone does not prove source isolation.

## Consequences and tensions requiring deliberate design
- **Shared assets vs shared world coordinates:** an asset needs stable local geometry plus a per-map placement transform. All D-levels within a map share the *same Atlas world reference*, but a reused castle might appear at different positions/scales in unrelated maps. Do not mistake shared **coordinate reference** for identical texture pixel density or identical asset placement.
- **Linked vs copied:** linked uses one canonical asset ID; copied creates a new asset ID and independent editable state. Decide whether live links can be external standalone files or only registry-managed project assets (T-060).
- **Layer groups as floors:** the Drawing group tree is generic; Atlas owns which group is a floor. Editing a group should not accidentally change group membership in other maps; define copy-on-write only if genuinely intended.
- **Blank missing LOD:** never silently substitute or ghost lower-detail artwork. Do not allocate a giant empty image; blank is a sparse/empty view until the first authored mark. Atlas must expose current D-level and a reliable way back.
- **Precision:** default Godot `Vector2` values have 32-bit precision, and Godot 2D rendering does not automatically solve huge-world precision via the large-world build option. Test integer/chunk-index world positions and camera-relative drawing coordinates at distant signed locations before settling the API. Reference: https://docs.godotengine.org/en/4.4/classes/class_vector2.html and https://docs.godotengine.org/en/4.4/tutorials/physics/large_world_coordinates.html .
- **Cross-map undo + linked art:** a transaction must retain its *originating map/floor/detail context* as well as the asset ID. On global undo, navigate to the originating map, even if other maps also show the same asset. View navigation itself should not add another history entry.
- **One text element per layer:** large maps may contain thousands of text layers; layer-tree virtualization and selection performance matter.
- **Conditional Web:** native-library adoption may simplify desktop, but must not silently remove a release target. Resolve Web target explicitly before final release gates.

## Outstanding questions (not silently approved)
1. Project/package layout, source packaging and Godot import isolation; standalone/Atlas desktop OS targets.
2. Shared asset lifetime, external-file linkage vs project-owned registry, rename/delete/update conflict and copy behavior.
3. One DrawingDocument per map/detail or a shared document containing floor and detail groups; whether one group can appear on multiple floors.
4. Asset-local to Atlas-world transform, reference scale, chunk/world precision, and pixels-per-world-unit per detail level.
5. Blank high-detail UI and overlay visibility; whether entering a blank level auto-creates content only upon a paint commit.
6. Navigation destination on undo if the original map/floor no longer exists; redo symmetry and camera placement.
7. Text font embedding, fallback, visual rasterization fidelity; entrance double-click thresholds/overlaps.
8. Final Web support decision and provided Drawing feature list.

## Scope control
Historical migration work is waived. Source/test cleanup may still be necessary, and fresh formats must roundtrip. No mandatory third-party native LOD engine before [[T-057]] produces measurements. No presumed UX acceptance.

## Round 4 clarification — Object Editor, exact group hierarchy and contextual undo (2026-11-01)

**Authoritative correction to the earlier ambiguous phrase “linked artwork”:**
- The owner imagines a **reusable object asset**, authored in an **Object Editor**, and placed as an **object instance** on Atlas maps. **This is not primarily a live link to a whole map DrawingDocument.** Keep background/map surface authoring separate from reusable object authoring.
- Editing an object's **source asset** and choosing **Save** updates that source and therefore its linked Atlas instances. **Save As** creates an independent new asset/copy. Whether Save As automatically rebinds the currently selected Atlas instance is **unanswered**.
- Object assets may contain generic Drawing raster/vector/text layers, as agreed in the Object Editor design. A placed instance has its own transform and selection identity. Atlas must not silently mutate the source when moving or rotating an instance. Need to decide whether per-instance edit overrides exist and whether objects can contain other object instances.
- Confirmed exact hierarchy: **Map → Floor group → Detail group → Layers**. These groups are organized by Atlas through generic Drawing layer/group constructs; detail content shares map-world coordinates. Missing high-detail drawing remains blank.
- Global undo should feel **Blender-like** by following the affected selection and restoring/switching into the relevant editing **mode**, in addition to returning to the originating map. Capture stable edit context in commands; on undo/redo, switch to the affected map/floor/detail, select the affected object/layer and restore a valid mode as appropriate. It is **not yet decided** whether ordinary selection-only or mode-only changes themselves push undo steps, whether each past tool is restored, or which camera position is used. Do not claim Blender-specific behavior as an exact contract.
- The uploaded `DrawInAtlas — Draw Module UI Specification` is preserved as the **proposed** [[DRAW_MODULE_UI_SPEC]]. Its one-row top bar, `BarDivider`, tab/rail/dock/status layout and overflow behavior are tracked in [[T-063]] and linked from [[T-059]]. This is not a complete tool feature inventory nor a signed-off final UI.

### Boundary sketch
```text
Drawing reusable engine / standalone editor
  - world/surface drawing: raster + object + text layers and layer groups
  - reusable Object Asset editor: asset-local editable layers + save/save-as
Atlas
  - Map -> Floor group -> Detail group -> Layers
  - object instance registry: (source_asset_id, instance_id, world transform)
  - object placement/selection and link resolution
  - one chronological history + selection/mode/context restoration
```

### New risk cases to test
1. Edit asset source through instance A; linked instances B/C refresh. Undo should restore source once and select/focus the relevant origin without confusing source vs instance selection.
2. Save As copied asset; original stays unchanged. User must know whether instance A still references original or is rebound.
3. Transform instance without touching source; undo selects that instance and restores appropriate instance/placement mode.
4. Undo an edit after changing to another map/mode, with stale or deleted selection. Restoration must be safe and not create another history entry.
5. Asset editor UI and Atlas-embedded Drawing share one canonical engine but can expose different workspace commands; the compact Draw UI spec remains proposed.

See [[T-060]], [[T-062]], [[T-054]], [[T-063]] and the remaining questions in [[T-051]].
