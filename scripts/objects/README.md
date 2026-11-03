# Atlas Object Asset registry — T-060

Object Assets are **reusable Drawing sources**, not linked whole-map drawings. These
Atlas-owned classes use the one canonical Drawing engine in `addons/drawing/`:

- `AtlasObjectLibrary` is the authority for stable asset/instance identity,
  versioned file publication, registry snapshots and link resolution.
- `AtlasObjectAsset` is a **detached published-version value handle**; modifying its public fields cannot change the library, and it never
  exposes mutable source layers or pixels.
- `AtlasObjectInstance` is a placement record with its own immutable ID and
  generation token, map/floor/detail identity, affine asset-local→world
  transform, visibility, revision and primitive metadata. No instance-level
  raster override exists.
- `AtlasObjectDraft` holds a **private** `DrawingDocument` plus an expected
  asset revision, and optionally a captured originating instance ID,
  generation and binding revision. Discarding a draft is Cancel.

## Construction and publication

```gdscript
var objects: AtlasObjectLibrary = AtlasObjectLibrary.new("/some/project/Campaign.scn")
var created: DrawingResult = objects.create_asset(drawing_source, "Castle")
var source_id: String = String(created.value)
var first: DrawingResult = objects.place(source_id, "world", "ground", "D0",
    Transform2D.IDENTITY)
var second: DrawingResult = objects.place(source_id, "greyhaven", "upper", "D1",
    Transform2D.IDENTITY)
var opened: DrawingResult = objects.begin_draft(source_id)
var draft: AtlasObjectDraft = opened.value
# Edit draft.document with the ordinary DrawingDocument APIs.
var saved: DrawingResult = objects.save_draft(draft)
```

`save_draft` checks its expected published revision, saves a new immutable
`Objects/<asset-id>/vNNNNNN.drawing` version, and **only then** atomically
replaces the registry index. Consumers see the old version until the index
replacement completes. `asset_published(asset_id, revision)` and
`instances_changed(instance_ids)` notify preview/Atlas adapters that cached
render targets must be refreshed. A failed registry commit discards its newly
staged file and keeps the draft intact for retry; previously published bytes
are never overwritten. The underlying `.drawing` codec preserves canonical
RGBA8, group IDs, UTF-8 text and typed semantic Variant values, including
`Vector2` and `Color` (non-Object binary Variant encoding).

`render_instance(id, asset_local_rect)` returns read-only bounded composited
pixels and the placement transform; `hit_test(id, map_world_point)` maps the
world point through the instance transform. `select_at(map,floor,detail,point)`
returns matching instance IDs. The current generic renderer uses raster-alpha
coverage; text/vector hit regions and polished tool affordances belong in
T-058/T-055/T-062. Missing/NULL references return an **explicit NULL result**
with local fallback marker bounds, rather than rendering a nonexistent source.

## Save As and Atlas history

`begin_draft(source_id, instance_id)` pins the source version **and** the
originating placement's stable `(instance_id, generation, binding_revision)`.
`save_as(draft, atlas_timeline, before_context, after_context)` constructs one
`AtlasAssetRebind` command. It validates exact origin map/floor/detail,
selection, source and generation; the first application persists B and rebinds
only the origin instance in **one registry index publication**. Undo changes
only the instance link back to A, retaining the saved B. Redo reuses the exact
same B ID. Revision and generation checks reject stale or replaced placements,
including after undo; removal of B prevents redo from silently recreating it.
The Atlas global history's external-dirty token remains set after undo because
B survived. `save_as(draft)` from an independently opened source creates B
without any Atlas binding change. Both forms deep-copy document, group,
layer and nested semantic IDs so later edits cannot mutate the original.

## Portable storage and safety

The T-060 **temporary component-level** index is
`Objects/<campaign-filename>.atlas-object-index.json` beside the campaign's
`.scn` file. It references only canonical relative paths under
`Objects/<asset-id>/vNNNNNN.drawing` and SHA-256 fingerprints; opaque IDs are
never derived from paths or display names. The index is written via a flushed
same-directory temporary file and a single rename. It checks that the index
has not changed since this library handle loaded it and fails closed if a
second writer modified the registry. Symlink components, `..` traversal,
noncanonical names, corrupt/replaced source files, duplicate IDs and unsafe
transforms are rejected. Unreachable staged files may be cleaned on a later
safe retention pass; no zero-reference automatic deletion is allowed.

The file model is portable by copying or moving **the enclosing directory**
containing the campaign and `Objects/`. `load()` will preserve broken source
IDs and instance transforms, exposing a NULL placeholder. Explicit source
delete policies are `cancel`, `remove` dependent instances or retain `null`
placements; the **prompt UI** belongs to T-065. NULL placeholders preserve
instance IDs/generations, original source keys and transforms, and remain
selectable inside a bounded local marker. Nested dependencies are T-064.

**Important distinction:** This T-060 separately persisted object index
remains a transitional integration interface. T-066 subsequently incorporated
the Object Asset registry snapshot, instance records and immutable source
version references into the authoritative campaign generation/root with
verified commit and recovery rules; see `docs/DRAWING_STORAGE_CONTRACT.md`. T-055 mounts Object placements in the real Atlas
editor; T-062 supplies the dedicated Object Editor tab, Save/Save As UI and
unsaved-close workflow. The retained legacy `.scn` codec still does not embed these
records, but the main editor now uses the T-066 portable generation save. A single Git monorepo and a single Drawing implementation
are retained. No owner UX gate is treated as satisfied by these headless tests.

## Validation

```sh
# Root Atlas project (requires Godot 4.8 beta 2)
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/object_assets_smoke.gd
python3 -m unittest discover -s tests -p 'test_drawing_*.py'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

The T-060 suite exercises 95 checks including two-map source sharing, private
edits, exact pixels and typed metadata, Save/Save As, one-command rebinding,
retained B after undo and reload, redo after delete failure, generation and
revision rejection, independent Save As, partial-publication fault injection,
concurrent registry guard/reload, directory move, symlink/traversal defenses,
and NULL placement hit tests.

## T-062 Object Editor integration (2026-11-02)

Host the canonical Drawing UI in an Atlas project by adding
`AtlasObjectEditorWindow.new()` as a child of the scene tree, then call
`configure(library, history, current_context_callable)`. The callable must
return the real `DrawingHistoryContext` with map/floor/detail, selected instance
and source asset ID; it is checked before opening and **again at publication**.
Use `open_instance(instance_id)` for an origin-bound Object Editor tab, or
`open_source(asset_id)` for a standalone asset tab; the latter's Save As cannot
rebind Atlas instances. Closing tabs releases the origin capture.

The Drawing-owned `DrawingObjectEditorSession` works on a private draft and
receives only host-injected publisher callbacks: the Drawing package imports no
Atlas classes. Save publishes a versioned immutable asset and refreshes all
linked placements; Save As from an origin executes T-054's durable B creation
plus instance rebind as one history command. Undo retains B and redo reuses its
exact ID. Errors preserve the draft/dirty indicator. Object name, signed
local origin and optional authoring rectangle are stored with the asset record;
`bounds` is an authoring guide, **not a pixel clip**. Older T-060 registries
without these optional frame fields remain readable with default origin and
unbounded sparse art.

T-055 is still responsible for adding an `Edit Source` action to the main
Atlas selection UI and rendering placed instances in that canvas. T-065 adds
the Asset Browser dock and object deletion/NULL prompts. T-066 adds unified campaign-generation saving while retaining the temporary
component-level registry for Object Asset compatibility.

```sh
godot --headless --path . --script res://tests/object_editor_smoke.gd
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/object_editor_ui_smoke.gd
```

## T-064 bounded nested source rendering (2026-11-03)

A published Object source can reference ordered child Object sources via the
existing Atlas registry. `render_source_tree(source_id, local_rect)` draws
the root, then visible descendants (depth-first, later siblings on top),
using composed parent-local affine transforms and the same canonical
`DrawingRenderer` as flat assets. `render_instance` uses that path only when
a source has children; flat placement and independent Drawing still work as
before. Missing/NULL children use a bounded visible marker rather than
looking up stale pixels. `composed_bounds` returns the union of transformed
child frames; `hit_test_path` returns a stable root-to-child ID path so a
future editor can distinguish parent selection from child selection.

The renderer refuses unsafe source/view sizes (1,048,576 output pixels,
2,048 visible nodes, 4,194,304 total sampled and composited pixels), and
uses a traversal-path cycle guard as a second line of defense. Atlas preview
invalidation follows child-graph mutation and published asset Save; unsaved
child drafts remain invisible to parents. Run the focused headless witness:

```sh
godot --headless --path . --script res://tests/object_child_render_smoke.gd
```

The nested editor-selection and Undo/Redo paths were implemented in later
T-064 milestones. The single-source Save As/export graph-copy policy remains
undecided; none of these engineering tests is owner acceptance.


## Copy a published nested Objects component (T-064)

`AtlasObjectLibrary.copy_objects_to(destination_campaign_path)` creates the
`Objects/` component for an **already-existing target campaign directory**.
The destination `Objects/` folder must not exist. The caller separately copies
or saves the actual campaign `.scn` and other campaign components; this helper
preserves currently indexed source revision bytes, source IDs, nested reference
IDs/transforms and map-instance records without importing or flattening them.
It validates published hashes, refuses symlinked output paths and concurrent
index changes, then promotes a verified staging directory. A failure does not
publish a partial `Objects/`. Old unindexed revision backups and live drafts
are not copied. This does not implement nested single-source Save As or export:
those graph-copy policy decisions are still open in T-064.

Run `godot --headless --path . --script res://tests/object_nested_project_copy_smoke.gd`
to exercise clone/reload, edits isolated from the original project and
corrupt/stale collision checks. CI runs the same headless witness.


## Complete saved portable campaign copy (T-064 engineering milestone)

`AtlasCampaignStore.copy_portable(source_campaign_path, new_campaign_path)`
(`AtlasCampaignCopy.copy_portable` for a fault-injection callback) clones an
**already checkpointed** T-066 bundle into a **new project directory**. The
parent directory must exist; the destination project folder must not. Source
and destination paths must be canonical absolute `.scn` filenames, with no
linked ancestors. It validates the current and backup generations, refuses a
transitional Objects index newer than the saved root, recursively copies
`Drawings/`, `Objects/` (including retained old revisions), `Fonts/` and the
portable root/recovery pointers, retargets the campaign-named Objects index,
and validates the new project before a single final directory rename. Every
file is checked against the source digest. Symlinks, component-copy failures,
source-root changes and destination collisions prevent publication and clean
up the private staging folder. This copies only the canonical bundle data,
not unrelated files, unsaved edits or the editor's in-memory history; no
per-object graph duplication policy is chosen. The destination is a separate,
editable project and never shares canonical source files with the original.

`godot --headless --path . --script res://tests/object_nested_campaign_copy_smoke.gd`
runs the 46-check cross-generation, nested references, undo-safe publication,
backup, failure/corruption and clone-independence witness. This backend API
now also has an Atlas-facing File → **Copy saved campaign…** action
(Ctrl/Cmd+Shift+S), with a destination parent picker and a new folder and
`.scn` name. This command refuses unsaved Atlas/Drawing/Object Editor edits,
works only from a published checkpoint, and keeps the original campaign open.
It is **not** the unresolved nested single-source Save As/export policy and
it has no owner UX signoff. `tests/object_nested_campaign_copy_ui_smoke.gd`
verifies the UI guard and exact copied registry/pixel contents.

## Nested source NULL repair (T-064 engineering milestone)

Deleting a published source with the retain-NULL policy keeps child-instance
ID, generation, local transform and missing source key. The nested inspector's
**Repair NULL with source** action chooses an available replacement by its
published ID; it never guesses a same-named source. The library endpoint
`repair_child_placeholder(parent_id, child_id, expected_parent_revision,
expected_generation, expected_child_revision, replacement_source_id)` verifies
identity, revision, source hash and acyclicity, publishes the whole registry
atomically and records `null_origin_source_id` without rewriting artwork.
The parent-local `AtlasObjectChildEditSession.repair_selected()` participates
in the same Undo/Redo timeline as structure and transforms. A stale session
must reload; a live child is not eligible for repair. Export/Save As nested
copying policy remains an explicit separate product decision.


## Nested child visibility (T-064 engineering milestone)

`AtlasObjectChildInspector` exposes **Hide selected / Show selected** for
published child instances. The source's immutable pixels are untouched;
`AtlasObjectLibrary.set_child_visibility()` validates exact graph revision,
child generation and revision before committing the parent's `visible` field.
Hidden children and all descendants are omitted from render/hit traversal,
but their IDs/transforms remain selectable in the parent inspector for later
re-show. The existing child-edit session records the action with reversible
Undo/Redo; graph-change signaling invalidates Atlas previews. The dedicated
`tests/object_child_visibility_smoke.gd` is CI-gated. This does not settle
nested source Save As/export policy or owner interaction acceptance.

## Nested child scaling (T-064 engineering milestone)

The nested parent inspector's **Shrink 10%** and **Grow 10%** buttons call
`AtlasObjectChildEditSession.scale_selected(factor)` through the existing
optimistic `transform_child` transaction. Scaling multiplies the child-local
basis vectors, leaving its parent-local origin intact, and preserving source
artwork, stable child IDs, descendants and any mirrored or nonuniform basis.
Zero/negative/nonfinite factors fail, as do stale parent writers and rejected
registry publications. The existing transform history supports Undo/Redo and
Atlas source-change invalidation. `tests/object_child_scale_smoke.gd` is a
fast-CI headless witness; native screenshots are targeted. This is not an
owner-approved nested Save As/export policy or hardware UX signoff.
