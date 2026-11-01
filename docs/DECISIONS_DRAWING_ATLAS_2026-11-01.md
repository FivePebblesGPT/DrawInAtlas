# Drawing / Atlas architecture decisions — 2026-11-01

**Status:** owner decisions confirmed, remaining API/UX choices open under [[T-051]]. This is the intended architecture, not the currently running implementation.

## Confirmed
1. **Physically independent Drawing:** a standalone, reduced-feature PhotoCraft/Paint.NET-style graphics editor, not merely an Atlas-private test scene. Detailed feature list to follow.
2. **Independent artwork:** a drawing can exist without any Atlas map. Whether Atlas links/copies/shares it is unresolved.
3. **Floors are layers:** Drawing has ordinary layers/groups; Atlas organizes them into logical floors. Drawing must not know about floors as a map concept.
4. **Drawing owns snapping** (Aseprite-like); Atlas may supply snap targets or edit constraints through generic interfaces.
5. **Atlas owns world surfaces and authored LOD organization; Drawing draws.** Atlas chooses active surface, layers and detail to display/edit. Native third-party map LOD/rendering is a possible optimization, not an approved dependency.
6. **Text tool:** an editable text layer is created on the first successful text edit, not when selecting the tool. Later explicit rasterization is supported.
7. **Pointer precedence:** painting over an entrance paints. Double-click the same entrance with Selection/ObjectSelection or Pan to navigate, not with drawing tools.
8. **History:** one global ordered Atlas history for now. Standalone Drawing also has independent history when run without Atlas.
9. **No saves to migrate:** omit historical save conversion and backwards-compatibility planning; test integrity/recovery of new formats.
10. **Physical independence:** Drawing must build, launch, test and be consumable without Atlas. Separate-repository versus independently built packaged project is not decided.

## Proposed dependency direction
```text
Standalone Drawing app --> reusable versioned Drawing package
                                   ^
                                   |
                 Atlas app (maps, layer/floor views, LOD,
                  entrances, world coordinates, global history)
```

Drawing's canonical artwork does not depend on Atlas classes/scenes. Atlas must not modify Drawing's private renderer or storage internals; consume a public API.

## Unresolved design gates
- Repository/package/release ownership; supported standalone platforms and Web target.
- Whether multiple maps link one live Drawing asset, make copies, or use both; Drawing file format.
- Exact mapping of Atlas floors to one Drawing document's layers/groups, and shared layers between floors.
- Board units, resolution, transforms and authored-level positioning when Atlas supplies vast world-map surfaces.
- Authored-detail fallback when a level is empty; explicit editing target while zoomed.
- One text layer per text object versus multiple text records; fonts and rasterization density.
- Entrance double-click identity/overlap/time-distance rules, global undo across maps.
- Minimum Drawing UX until the owner sends the feature list.

## Distinguish LOD concepts
**Derived image LOD** (mipmaps, tile pyramids and streaming of one image) differs from **authored detail LOD** (different artwork at different world scales). Benchmark Godot against native options under [[T-057]]; neither libvips nor MapLibre is preselected. Godot Web/GDExtension/WASM constraints must be measured rather than assumed away.

Historical T-015 migration proposals are superseded because there are no old user saves, though removal of obsolete battlemap code still requires verification.
