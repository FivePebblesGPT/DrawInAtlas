# Drawing core (T-052)

**Canonical source:** `addons/drawing/*.gd` and their Godot UID files. This is the
only editable generic Drawing package. It lives inside the Atlas-root Godot
project so Atlas can import it directly in T-055, and is byte-identically
staged into independent, **Atlas-free** consumers using
`tools/build_drawing_contract_consumer.py --fixture drawing_core_consumer`.
Generated staging copies must never be edited in place. The standalone Drawing
application shell is implemented under T-053; see `drawing/README.md` for the independently buildable project and isolated witness.

## Document and edit boundary

- `DrawingDocument.new(id, stride, density_num, density_den)` creates a logically
  sparse document. `stride` is per document and currently supports 1–2048; **256
  is a compatibility default, not the selected production tile geometry.**
  T-067 chooses production geometry after measurement.
- `create_layer(kind, name, parent_id)` gives opaque immutable IDs. `group`
  nodes support nested ordered children and inherited visibility/locking;
  `raster`, `text`, and `objects` are generic content types. `inspect_node`
  returns **detached** objects; `node_metadata` avoids copying pixel data.
- `begin_edit(layer_id, expected_revision, view_transform, anchor_x, anchor_y)`
  returns `DrawingResult.value: DrawingEditSession`. One gesture freezes the
  revision, local coordinate transform and signed 64-bit pixel anchor. The
  anchor is not converted to a large floating-point world position.
- `apply_region(Rect2i, PackedByteArray)` is the bounded native-acceleration
  seam (canonical straight RGBA8), with exact changed rectangles returned
  by `commit()`. `paint_path`, `paint_polygon`, `fill_rect`, `clear_rect` and
  `flood_fill` offer portable Godot implementations; selection masks, clipboard
  copy/move/paste, image import and generic snapping are separate helpers.
  Pixels are staged in the session; **only touched tiles** are cloned at commit.
  `cancel()` and revision conflicts publish nothing. A single swept gesture
  blends any covered pixel once against its original RGBA8 value.
- `read_pixel(layer_id, x:int, y:int)` reads signed 64-bit absolute pixel
  coordinates. Public `request_chunk_at(layer_id, cx:int, cy:int)` returns a
  detached tile snapshot, never live storage. A missing **unreferenced** tile
  is blank; an advertised blob that cannot be fetched or verified returns
  `MISSING_TILE` / `CORRUPT_TILE`, never a fabricated transparent tile.
- `DrawingRasterTile` stores sparse canonical RGBA8 pixel values, including
  hidden RGB in alpha-zero pixels. Whole-tile byte arrays are made **only** on
  explicit requests. Digest identity includes tile width, height and the RGBA8
  format label followed by exact bytes.
- `DrawingRenderer.render(document, bounded_rect, anchor_x, anchor_y)`
  composites only the requested viewport and honors hidden groups; it does
  not allocate an infinite backing image.
- `export_subtree` / `import_subtree` / `transfer_subtree` validate IDs and
  trees, deep-detach tiles and preserve IDs on moves but mint fresh IDs on
  copies. An inaccessible lazy tile blocks transfer instead of being dropped.

## Lifecycle for persistence implementers

`export_manifest()` yields a **logical, not frozen physical**, metadata tree
with sorted signed chunk coordinates, digest, per-document tile stride and
relative opaque blob references. Dirty/new chunk refs are empty pending
staging; `snapshot_for_save()` yields just modified RGBA8 tile bytes and
removed-tile tombstones. After the owner saves all dirty blobs, fills their
refs, verifies them, and atomically publishes the project generation, call
`mark_published(revision, published_refs)`; it rejects lost dirty tile refs.
`open_manifest(manifest, fetcher)` validates the generic layer tree and creates
lazy chunk references; content fetch and digest verification occur on read.
T-066 chooses the physical manifest/codec, fault-injects generation recovery,
cache eviction, and guarantees atomic multi-file publication. The current
API is an in-memory logical protocol, **not an implemented project save**.

Undo/redo replays compact raster deltas for an independent document. Since
T-054, `DrawingDocument` also owns an ordered local history with optional
selection-only entries (`record_selection_history`, OFF by default), detached
`DrawingHistoryContext` snapshots, context annotations for committed gestures,
unique content state identities and dirty/savepoint separation. Mode/camera
navigation alone is not an undo step. The standalone UI opts in from Options.

For embedded Drawing, call `set_external_history(true)` **before** edits, then
use `AtlasEditHistory.commit_drawing(session, before_context, after_context)`.
It records one externally committed delta in the existing Atlas timeline;
`DrawingDocument.undo()` is intentionally disabled in that mode to prevent
double histories. The Atlas-owned `AtlasDrawingEdit` supports revision-checked
undo/redo. The host must supply validated stable map/floor/detail/document/asset
IDs and any affected world bounds; a UI-only restoration cannot recreate
missing geometry. Atlas's multi-document move and Save As history callbacks
are tested in `tests/drawing_history_smoke.gd`; concrete asset registry/editor
and physical campaign save remain T-060/T-062/T-066. Structural metadata
mutations are currently dirty but not local undo commands (follow-up feature
scope). T-058 now implements one-text-object-per-layer commits and undoable rasterization;
T-060 implements durable linked Object Assets; T-068 profiles and selects
native drawing acceleration. No platform export or UX approval is claimed.

## Reproduce isolated tests

```sh
python3 -m unittest discover -s tests -p 'test_drawing_*.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

The core test starts an external Godot project containing **only** a small
consumer scene and unmodified `addons/drawing/` files. No Atlas scripts,
scenes, autoloads, plugins or root `project.godot` are staged. See
`tests/fixtures/drawing_core_consumer/main.gd.txt` for runtime acceptance.

## Standalone app integration (T-053)

`DrawingFileIO` wraps the exact logical manifest and canonical per-tile bytes in
`drawing-standalone-v1` `.drawing` single-file documents. It validates SHA-256
and exact hidden-RGB pixels on reopen, maintains stable IDs and keeps signed
chunk coordinates as strings to survive Godot JSON's floating numeric parser.
It is a **standalone file codec**, not Atlas campaign persistence (T-066).
`tools/build_drawing_app.py` stages these canonical package files byte-for-byte
into an independently runnable project. The untracked `drawing/addons/` staging
folder must never be edited or committed. The `drawing_package_consumer` fixture
verifies a third independent Godot consumer uses the same complete engine.

For local tests: `python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v`.
The native compositor/viewport test is `drawing/tests/native_pointer.gd`, run
under X11/Mesa (Xvfb on CI). Windows builds have a preset but need Windows
export templates/runtime validation. Final UX and campaign save remain future work.

## Editable text API and bundled font contract (T-058)

`DrawingTextElement` is a detached one-per-layer record with nonempty content,
stable font ID (`lato-regular-v1`, `lato-bold-v1`, `lato-italic-v1`), integer
point size, straight RGBA8, signed top-left world origin (`Vector2i`), local
rotation/scale and horizontal alignment. `DrawingDocument.commit_text("",
draft, expected_revision, parent)` creates a text layer atomically only for a
valid content commit, or pass an existing text-layer ID to edit the same
record. `rasterize_text(layer_id, expected_revision)` converts text to sparse
ordinary pixels using `DrawingTextRaster`'s same Godot FontFile shaped glyph
compositor as `DrawingRenderer`. Both operations are individual local history
entries; undo/redo restores text editability and source layer ID. Missing fonts and unbounded raster requests reject without mutation;
unsupported glyphs use a visible replacement with an explicit warning.

Standalone `DrawingFileIO` writes the referenced OFL Lato font binary, stable
identity and SHA-256 inside the `.drawing` JSON envelope with the license;
reopen validates it before exposing the text. These files are relocatable as
single documents. This is not the multi-file campaign `Fonts/` save contract
(T-066), nor an instruction to embed unknown user-system font files without
legal review. T-055 will integrate this same API with Atlas canvas; T-062 adds
Object Editor document tabs.

## Shared Object Editor (T-062)

`DrawingObjectEditorSession`, `DrawingObjectEditorFile`, `canvas.gd` and
`workspace.gd` implement a reusable tabbed Drawing editor that knows nothing
about Atlas maps, registries, instances or history. The host injects Save and
Save As publishers returning detached documents and published identities.
Object tabs have isolated drafts, local undo, signed origin and optional
non-clipping bounds. The standalone file codec retains optional
`drawing-object-source-v1` metadata in the ordinary `.drawing` wrapper;
corrupt/oversize metadata is rejected on open. Atlas supplies the bridge and
versioned asset library; do not import Atlas scripts into this package.
