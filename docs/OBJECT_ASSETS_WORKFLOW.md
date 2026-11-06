# Reusable Object Assets — authoring, links and safe deletion

**Current authority (T-074, 2026-11-02):** [owner-approved decisions](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md), [T-054](Tickets/T-054.md), [T-066](Tickets/T-066.md) and the actual `scripts/objects/` code. This is an implementation guide, **not** owner acceptance of the complete UX. [T-064](Tickets/T-064.md) and [T-065](Tickets/T-065.md) remain unfinished.

## Two kinds of Drawing data, one engine

| Question | Map/floor/detail artwork | Reusable Object Asset source |
| --- | --- | --- |
| Owner | `AtlasDrawingRegistry` maps `(map_id, floor_id, detail_id)` to an internal `DrawingDocument` | `AtlasObjectLibrary` owns versioned source assets; `AtlasObjectEditorBridge` opens private drafts |
| Purpose | Continuous, sparse authored world artwork at one density per D-level | A portable, independently editable castle/tree/prop source reused by linked instances |
| Storage | `Drawings/` sparse manifests and `.zst` raster chunks, referenced by an immutable campaign generation | `Objects/<asset-id>/vNNNNNN.drawing`, plus asset/instance index snapshot in the campaign generation |
| User navigation | Atlas Map → Floor → Detail → Layers; no tab for each internal document | A dedicated Object Editor **source document tab**, separate from an Atlas instance's placement/selection |
| Persistence | Atlas publishes the whole generation via `Campaign.atlas.json` (with backup pointer) | Source Save publishes a new immutable version; campaign save captures the Object index and associated source references |

Both consumers use `addons/drawing/`; the Drawing package imports **no Atlas types**. An Object Asset is **not** a per-hex map document or a live link to a second entire map. The standalone Drawing app also opens ordinary drawings; an independently opened Object Editor source has no originating Atlas instance to rebind (**no Atlas rebind**).

An Object Asset has a durable **asset ID**, display name, version/revision, source-file checksum, signed asset-local origin and optional authoring bounds. Bounds are a guide, **not** an art clip. A linked `AtlasObjectInstance` instead has its own **instance ID** and generation token, source asset ID, map/floor/detail IDs, affine asset-local-to-world transform, visibility and binding revision. Editing a placement cannot mutate source pixels. Source IDs, instance IDs and internal DrawingDocument IDs are **different identity domains**; names and filesystem paths must never substitute for stable IDs.

## Worked example: Castle A, Variant B and broken links

The IDs here are **illustrative**; the registry generates opaque stable IDs (do not use a display name such as “Castle” as an ID). Assume an Atlas campaign `Campaign.scn` is stored beside `Drawings/`, `Objects/`, and `Fonts/`.

1. **Create and place:** author castle art with a generic DrawingDocument, then call `AtlasObjectLibrary.create_asset(source, "Castle A")`. Suppose it returns `asset-A`, published as `Objects/asset-A/v000001.drawing`. Call `place(asset-A, map-east, ground, D0, transform)` twice: **instance-I** and **instance-J** are separate placements with independent transforms/revisions, both pointing to **asset-A**. Map art in `Drawings/` does not become part of either castle source.
2. **Edit privately:** open **instance-I** in the dedicated Object Editor (`AtlasObjectEditorBridge.open_from_instance(instance-I)`). The editor captures `instance-I`, generation, source `asset-A`, binding revision and map/floor/detail context, then edits a detached `AtlasObjectDraft.document`. Before Save, both **I** and **J** still render published **asset-A** (revision 1); changes reach linked placements **only after Save**. Closing/discarding the draft publishes nothing.
3. **Save:** `save_draft(draft)` publishes `Objects/asset-A/v000002.drawing` and updates `asset-A`'s published revision. Both I and J now render revision 2; neither placement transform or instance ID changes. A stale draft/source revision cannot overwrite a newer publication, and the shared source is not overwritten in place.
4. **Save As through I:** modify I's draft and invoke bound `save_as(...)` with its captured Atlas history context. It publishes independent **asset-B** as `Objects/asset-B/v000001.drawing` and **rebinds only instance-I** from A to B in one registry publication/history command. **J remains linked to A**, and A's published pixels remain unchanged. The Object Editor follows B. A stale, removed, moved, rebound or generation-replaced origin fails safely instead of rebinding another instance; the unsaved draft remains available for deliberate recovery/reopening.
5. **Undo / redo:** undo restores **I → asset-A** and the relevant selection/editing context, but **asset-B stays saved and reopenable**, even with zero linked instances. The campaign can therefore remain dirty after undo. Redo restores **I → the same asset-B ID**; it must never create a third asset. If B was explicitly deleted after undo, redo **fails closed**, leaving the original link intact rather than fabricating B.
6. **Independent Save As:** opening **asset-A** without any Atlas instance context, then Save As, makes another independent source **asset-C** and switches that editor tab to C. Neither I nor J is rebound.
7. **Delete A:** `delete_asset(asset-A, "cancel")` does nothing; `"remove"` removes A's linked placement records; `"null"` deletes the A registry entry but retains affected placements as **NULL**. For a retained instance J, `instance_info(J)` reports `status: "NULL"` and preserves J's `instance_id`, original `source_id: asset-A`, original transform and map/floor/detail. It can be selected through a bounded marker, not guessed art. The deletion UI is **not yet implemented**.
8. **Copy/reopen and repair:** move the entire campaign directory, including `Objects/`, `Drawings/`, `Fonts/` and generation indexes: intact relative links reopen; the component-level Object registry exposes missing/corrupt source files as NULL instead of silently substituting a similarly named asset. **The T-066 campaign loader is stricter:** if a referenced source file is absent or corrupt, generation integrity validation rejects that generation and tries the independently valid backup; it does not promise to open a corrupt generation with NULL artwork. The user must inspect the original source ID, restore the exact verified file or use an **explicit future** repair/relink action (T-065). No automatic same-name matching or silent replacement is allowed.

**Save hierarchy:** `AtlasObjectLibrary` still has a transitional component-level `Objects/<campaign-filename>.atlas-object-index.json` for direct library operations and tests. The **authoritative Atlas campaign Save/Load** is the T-066 generation/pointer snapshot, not a lone `.scn` nor that component index. Source files remain immutable and versioned; the source library and campaign generation must be preserved as a unit when copying a portable project. Unreferenced saved B is **not** automatically garbage-collected.

## Deletion, NULL and explicit repair

The registry API already offers three policies; a choice **dialog is only planned** under T-065:

| Policy | Existing registry behavior | Future UI promise (not yet shipped) |
| --- | --- | --- |
| `cancel` | No publication, all IDs and links unchanged | Cancel deletion |
| `remove` | Removes source from active index and all placements that reference it | **Remove references/placements** with clear consequences |
| `null` | Removes source from active index; retains each placement's stable ID, generation token, original source ID, world transform and visibility as a selectable NULL marker | **Keep visible NULL placeholders** and later offer deliberate repair |

`AtlasObjectLibrary.instance_info()` and `render_instance()` expose `NULL` when the source is explicitly deleted with placeholders **or** when the library is inspecting a registry whose source file is missing/corrupt. That component-level NULL behavior does not bypass **T-066 campaign-generation integrity preflight**, which may reject/recover a broken generation before exposing its placements. `hit_test()` keeps a **bounded** local marker selectable without loading the missing raster. Missing data must **never** be treated as blank/transparent successful artwork or silently linked to an asset with a matching filename/name. The current registry supports preservation and inspection, **not** an end-user repair/rebind workflow. `T-065` owns the Asset Browser dock, source deletion prompt, NULL representation/repair affordances, search, unused asset listing and keyboard/docking parity; its hard prerequisite `T-063` is not yet Done. Old version bytes may be retained for history/backups even when a source is removed from the active index; that is not an automatic restore API.

## Nested Object Assets: approved direction, implementation staged

The owner approved that an Object Asset may contain child Object Asset instances with asset-local transforms. **T-064 (Ready) has not implemented this graph.** Existing flat top-level Atlas placements, generic Drawing `OBJECTS` layer entries and typed semantic values must not be mistaken for nested asset links.

T-064 must introduce explicit stable child-reference IDs and enforce *acyclic* graphs: reject A→A and A→B→C→A during insertion, Save, import and reload, with guarded traversal of corrupt data. Published child Save should invalidate parent caches and all placed descendants *transitively* while preserving private drafts. Child deletion must support the same Remove/NULL/Cancel choices, retaining source ID and local transform when NULL is chosen. Nested selection, nested Save As semantics, dependency persistence, recursion/performance limits and hit-testing remain unimplemented or undecided; do not claim a tested cycle detector or transitive invalidation today. T-064's undecided parent Save As copy-versus-link policy must be resolved before shipping nesting.

## APIs, tests and acceptance handoff

- `scripts/objects/object_asset.gd`, `object_instance.gd`, `object_draft.gd`, `object_library.gd`: published identity, placement records, private draft, versioned source and registry APIs.
- `scripts/objects/object_editor_bridge.gd` and `object_editor_window.gd`: capture live Atlas identity, construct a canonical `DrawingObjectEditorSession`, prevent stale Save/Save As, and publish only on successful commands.
- `addons/drawing/` and `drawing/`: shared Drawing engine and standalone editor; no Atlas engine fork.
- `tests/object_assets_smoke.gd`: publication, placement transforms, Save As B/undo/redo/delete-B, missing/NULL, portable copy, concurrent writer and integrity checks.
- `tests/object_editor_smoke.gd` and `drawing/tests/object_editor_ui_smoke.gd`: actual source editor tabs, staged edit/Save/Save As, captured origin, unsaved-close behavior.
- `tests/campaign_bundle_smoke.gd`: authoritative generation save, object snapshots and recovery.
- `tests/test_t074_object_docs.py`: ensures these documents track the code and maintain T-064/T-065 and manual-review boundaries.

Run (from repository root; requires Godot 4.8 beta 2):

```bash
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/object_assets_smoke.gd
godot --headless --path . --script res://tests/object_editor_smoke.gd
godot --headless --path . --script res://tests/campaign_bundle_smoke.gd
python3 -m unittest discover -s tests -p 'test_t074_object_docs.py' -v
python3 tools/validate_ticket_store.py
```

**Open product/review work:** T-064 nested graph, T-065 Asset Browser and explicit repair UI, T-063 workspace/dock behavior, T-059 final owner UX acceptance, T-056 full standalone/Atlas integration signoff. Documentation of the approved flow is **not** evidence that those tickets are Done.
