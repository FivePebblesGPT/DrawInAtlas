# Native canonical tile store — ABI v1 (T-148, incremental)

**Scope and status (2026-11-15):** `DrawingNativeTiles` and the paired `DrawingNativeBrush.apply_tile_batch` → `commit_tiles` path are used by production `DrawingCanvas` for Hokusai presets and Eraser. **The Rust store is now retained by each `DrawingDocument` across native gestures**, and its Undo/Redo tokens are replayed on the real document history timeline. The Godot document still publishes full RGBA8 consumer snapshots for rendering, save and other editing tools. Ordinary non-brush `_publish_edit` / `_publish_tile_edit` operations now join this same history through one checked external whole-tile adoption call when the native store is current. Metadata-only document revisions now use a checked native revision advance, preserving both canonical tiles and native history tokens. T-148 **remains In Progress**: bounded direct subtree retirement now preserves unaffected native raster history, but rejected retirement, previously owned text rasterization, detached/global replay and other unbridged producers can still require a checked rebase. Universal native authority is not established. T-149 owns subsequent display/Atlas/persistence consumer conversion. See [mixed-raster checkpoint](evidence/T-148-2026-11-15-mixed-raster.md), [metadata checkpoint](evidence/T-148-2026-11-15-metadata-revisions.md), [never-authorized raster subtree evidence](evidence/T-148-2026-11-15-unreferenced-raster.md), and [native-owned subtree evidence](evidence/T-148-2026-11-15-parked-subtrees.md).

**T-153 update (2026-11-16):** Production Brush and Eraser use one
Hokusai/libmypaint rasterizer. `begin_stroke` accepts a **preset text instead
of a renderer mode**. On Eraser, Rust applies the Hokusai dab alpha to reduce
original source alpha and preserves source RGB. Other generic native
selection/tile/history mechanisms remain unchanged. Historical NativeHard
benchmarks are not current correctness or timing oracles.

## Ownership, byte format and source identity

- `DrawingNativeTiles` is a Godot `RefCounted` holding one Rust-authoritative `TileStore`; production constructs it once per `DrawingDocument` and retains it across gestures, with a checked external-revision rebase. Call `configure(storage_stride, initial_revision)` exactly once (`16 <= stride <= 2048`, `revision >= 0`). **Storage** tiles are not the Hokusai internal 64px tiles or the 128px display tile size; normal planned stride is **256**.
- `TileId = (layer: String, tile_x: i64, tile_y: i64)` uses signed world coordinates, `div_euclid` floor division for tile ID and `rem_euclid` for local pixels. World coordinate absolute value must not exceed `2^60`; overflow fails before any draft changes. Layers are independent namespaces, including identical `(tile_x,tile_y)`.
- **Godot persistence/projection bound (T-158):** Although the Rust stroke
  input ABI accepts anchors through `±2^60`, the Godot consumer's existing
  whole-tile publication/history projection uses an inclusive signed tile
  coordinate bound of `floor(2^52 / storage_stride)` on **each axis**.
  `register_lazy_chunk` now rejects larger coordinates with `COORD_RANGE`
  **before** recording a pending source or changing its display epoch;
  `export_manifest` checks resident and lazy tile keys likewise. Logical
  manifest opening and `.drawing` decoding inherit this registration gate.
  Comparisons are sign-safe even for `INT64_MIN`; valid signed boundary
  coordinates and alpha-zero hidden RGB still roundtrip. This does **not**
  expand the supported Godot display coordinate range or change native
  stroke/history semantics. See [T-158 regression](evidence/T-158-2026-11-16-tile-bounds.md).
- **Signed native replay/publication guard (T-159):** In addition to T-158's
  lazy/manifest boundary, `_publish_native_tile_edit` and
  `_replay_native_tile_delta` now validate both tile axes against the same
  signed `floor(2^52 / storage_stride)` limit **before** source resolution or
  dirty rectangle construction. `_replay_pixel_delta_native` validates both
  historical pixel axes against inclusive `±2^52` **before** tile grouping.
  Every comparison is sign-safe for `INT64_MIN` (where Godot's `abs()` returns
  an overflowing negative value); rejection leaves native history and the
  document revision untouched. These checks do not expand Rust coordinate
  limits, modify tile encoding, or complete T-148's universal ownership gate.
  See [T-159 regression](evidence/T-159-2026-11-16-replay-bounds.md).
- **Native-attached direct publication guard (T-160):** Once a persistent
  `DrawingNativeTiles` store is attached, `_publish_edit` (global pixel maps)
  requires canonical decimal signed coordinates within `±2^52`, and
  `_publish_tile_edit` (tile-local dictionaries) requires canonical signed
  tile IDs within `±floor(2^52 / storage_stride)`. These guards run before
  lazy source resolution or global tile-offset multiplication and reject
  without changing Rust's revision/history token or Godot's dirty tiles.
  Before native attachment the historical direct-session signed-64-bit
  coordinate contract is intentionally left unchanged until T-150 removes
  Legacy; a legacy-only out-of-projection document cannot claim native
  authority or a valid portable manifest. The current guard is not a claim
  that every non-Brush raster producer is universally native-owned.

- **Nonhistorical direct source ownership (T-162):** With an in-sync Rust
  store, `DrawingDocument._publish_edit` and `_publish_tile_edit` publish full
  before/after RGBA8 even when `record_history=false` using
  `DrawingNativeTiles.adopt_untracked_edit`. This accepts the same checked
  tile descriptors and source identities as `adopt_external_edit`, but returns
  `history_token=0`; Rust atomically advances the revision and retains all
  unrelated resident sources while clearing invalidated native Undo/Redo
  tokens. Godot installs its detached display/save tiles only after Rust
  succeeds; no local or Atlas history event is synthesized. New untracked
  content still updates Godot's unsaved-change state and invalidates local
  Redo, while detached historical `_publish_edit` replay explicitly skips
  re-marking content dirty so it can preserve the preexisting history cursor.
  With no attached
  store, historical nonnative publishing remains unchanged. Rejected native
  transactions do not modify either source or revision; stale/out-of-sync
  stores still follow T-148's conservative external rebase boundary.

- **Public signed anchor guard (T-161):** The legacy-compatible
  `DrawingDocument.begin_edit`, `DrawingRenderer.render` and
  `DrawingRasterImport.import_image` entry points reject anchors outside
  inclusive `±2^60` with one sign-safe `SignedTiles.document_anchor_in_range`
  helper. The renderer checks the supplied 64-bit origin *before* adding the
  signed 32-bit `Rect2i` offset and checks the translated result too;
  `INT64_MAX + 1` must never wrap to an `INT64_MIN` falsely accepted by
  `abs()`. The import and gesture guards run before source mutation or
  creation of a transaction. The historical ±2^60 non-native endpoints
  remain permitted; this is **not** a wider Rust native import bound nor
  approval of any T-095 hardware latency gate. See [T-161 evidence](evidence/T-161-2026-11-16-public-anchors.md).

- A tile contains exactly `stride * stride * 4` bytes in **straight** `[R,G,B,A]` order, row-major with row stride `stride*4`; data are **not premultiplied**. Alpha-zero pixels can retain RGB, including through masks, Undo, Redo, read and reimport. A full transparent black tile may be imported with an **empty** byte array, but still counts as an **explicitly authorized** source identity. An absent tile is an error, never implied blank. Imported source identities cannot be replaced in place *within one document revision*. An externally changed document revision not covered by an atomic native transaction requires `rebase_external_revision`; this invalidates all prior source authorizations and native history, then source imports must match the new revision. `has_source` plus the Godot document's verified source-object identity prevents redundant tile imports across native gestures without accepting silent source replacement. The buffer length must remain exact.
- `set_layer_editable(layer, editable)` authorizes non-raster layer authority before an edit; changing it to false before native publication rejects the whole commit. Until Godot document integration, callers must interpret this as the combined visible/unlocked state and fail closed on missing authority.
- Memory limits: at most **128** touched storage tiles per open transaction and **128** simultaneously parked raster-layer identities, **256 MiB** counted across resident source, working drafts, masks and retained Undo/Redo tile snapshots, and **64** retained Undo transactions. History uses reversible full-tile before/after snapshots; these are conservative bounds, not byte-delta/COW subrect compression. Dense RGBA8 bytes are chosen for full-canvas paint over per-pixel string dictionaries; the map of tile IDs is sparse. Out-of-budget requests fail before publication. A full 512² (four 256px tiles) source + one edit with Undo history occupies **3,145,728 counted bytes** at the tested point.

## Native stroke to store transaction

The new path uses **the same** `DrawingNativeBrush` object as T-147. In Godot `Object.call` terms:

| Call | Parameters | Result / behavior |
| --- | --- | --- |
| `tiles.configure` | `storage_stride:int, revision:int` | `bool`; once only |
| `tiles.advance_metadata_revision` | `expected_revision:int, discard_redo:bool` | `bool`; only for byte/identity-preserving non-raster edits; advances exactly one revision, retaining Undo, optionally evicting Redo; rejects active/stale/overflow without side effects |
| `tiles.set_layer_editable` | `layer:String, editable:bool` | `bool` |
| `tiles.import_source` | `layer, tile_x:i64, tile_y:i64, revision:int, rgba_bytes:PackedByteArray` | `bool`; empty bytes explicitly authorize blank, nonempty must be exactly `stride²*4` |
| `tiles.begin_edit` | `layer, revision, selection_required:bool` | `{ok,transaction}`; one active edit; opaque positive 64-bit ID |
| `tiles.import_mask` | `transaction,layer,tile_x,tile_y,mask:PackedByteArray` | `bool`; one already-authorized source tile, exactly `stride²` selection bytes, nonzero = allowed |
| `brush.begin_stroke` | `layer,preset_text,width,rgba,revision,local_clip` | `{ok,handle}`; v1 stroke |
| `brush.append_samples` | `handle,revision,PackedFloat32Array([x,y,pressure,delta_s]...)` | `{ok,...}`; one pending batch |
| `brush.required_tiles` | `handle,revision,stride,anchor_x:i64,anchor_y:i64` | `{ok,tiles:[{tile_x:i64,tile_y:i64}]}` for **pending** clipped samples, bounded to 128 IDs; use to bulk-read/authorize missing source/masks without exporting per-pixel changes |
| `brush.apply_tile_batch` | `tiles,handle,revision,transaction,anchor_x:i64,anchor_y:i64,erase:bool` | `{ok,dirty_tiles}`; entirely Rust-local Hokusai pigment and alpha-aware erase, selection, staging and source verification **and** brush-batch acknowledgement on success / full brush rewind on failure |
| `brush.acknowledge_batch` | `handle,revision,accepted:bool` | `bool`; **only for transitional `preview_changes` path**. `apply_tile_batch` consumes its own pending batch and atomically acknowledges or rewinds; a separate ack must fail. |
| `tiles.dirty_tiles` | `transaction` | Array of `{layer,tile_x:i64,tile_y:i64,dirty:Rect2i,base_revision,generation}`; **tile-local** dirty rectangle `[start,end)` |
| `tiles.read_tile` | `layer,tile_x:i64,tile_y:i64,preview:bool` | `{ok,format:"straight_rgba8",stride_bytes,generation,bytes:PackedByteArray}`; detached immutable **copy**, valid independently of later mutation |
| `brush.commit_tiles` | `tiles,handle,revision,transaction` | `{ok,dirty_tiles,revision,history_token}`; the positive token names its native history entry for a changed gesture, and validates matching layer/revision and fully acknowledged stroke, then atomically publishes tiles/history and consumes brush handle; a failed validation leaves draft/handle retryable; a no-op returns `{ok:true,no_change:true,dirty_tiles:0,revision:original}` |
| `tiles.discard_edit` + `brush.abort_stroke` | `transaction` / `handle` | `bool`; discard both halves of a cancelled edit |
| `tiles.adopt_external_edit` | `layer, revision, Array[Dictionary]([{tile_x:i64,tile_y:i64,before:PackedByteArray,after:PackedByteArray},...])` | `{ok,history_token,tiles,revision}` on success; all-or-nothing, 1–128 distinct tiles, validated preimages and full `stride²*4` replacement spans; empty `before` explicitly denotes a blank source, no change and malformed spans reject; no active native stroke; GDScript must preflight before invoking |
| `tiles.adopt_untracked_edit` | Same bounded `layer, revision, tiles` descriptors as `adopt_external_edit` | `{ok, history_token:0, tiles, revision}` on success; atomically stores canonical source and advances revision without adding Undo. Clears obsolete native token stacks; GDScript records no local/host history entry. Malformed, stale, repeated, mismatched and active edits reject before mutating Rust canonical tiles |
| `tiles.undo_edit`, `tiles.redo_edit` | — | `{ok,tiles,revision}`; direct native-only history transactions |
| `tiles.has_history_token` | `history_token:int, expected_revision:int, undo:bool` | `bool`; side-effect-free history-top identity check before document timeline replay |
| `tiles.replay_history_token` | `history_token:int, expected_revision:int, undo:bool` | `{ok,token,tiles,revision}`; checked native replay, rejects wrong token/stale revision with no mutation |
| `tiles.advance_unreferenced_layers_revision` | `expected_revision:int, affected_raster_ids:PackedStringArray, discard_redo:bool` | `bool`; checked one-step structural revision **only** when 1–128 distinct affected raster IDs have no resident/authorized tile or Undo/Redo history. An authorized blank tile or active stroke rejects. Does not remove native pixels/history; rejected edits still require external rebase. |
| `tiles.advance_parked_layers_revision` | `expected_revision:int, affected_raster_ids:PackedStringArray, restore:bool, discard_redo:bool` | `bool`; 1–128 distinct IDs (and at most 128 total parked), quiescent exact revision, all present/not parked on removal or all parked on restoration; requires at least one Rust-owned layer when parking, otherwise use the unreferenced metadata bridge. One-step revision preserves canonical RGBA8, authorizations and native Undo tokens; parked layers deny edit, import and replay while absent, unrelated layers remain paintable. Rejects stale/duplicate/active/overflow atomically. `discard_redo=true` only for new structural edits. |
| `tiles.replace_parked_layers_revision` | `expected_revision:int, layer_ids:PackedStringArray` | `bool`; quiescent, 1–128 nonempty distinct **parked** raster IDs only; one checked `r → r+1` replacement discards only their obsolete tiles/authorization/editability/Undo, clears branched Redo and removes reservations, preserving unrelated native source and Undo. Rejected stale/ahead/active/mixed/unparked IDs leave all state unchanged. Used only when the text source actually changes after Undo; byte-identical structural Redo must unpark instead. |
| `tiles.is_layer_parked` | `layer_id:String` | `bool`; prevents creation of a new layer reusing a parked Rust-owned identity |
| `tiles.rebase_external_revision` | `expected_native_revision:int, new_document_revision:int` | `bool`; when no transaction is active, advances to a strictly higher document revision while invalidating native tile authorizations and Undo/Redo; stale, equal or active requests fail closed |
| `tiles.has_source` | `layer,tile_x,tile_y,revision` | `bool`; indicates that an identity has been authorized for that native revision, **not** that a Godot source object still matches—caller must compare its identity |
| `tiles.list_tiles` | `offset:int,limit:int` | `{ok,tiles:[{layer,tile_x,tile_y,generation}],total,next_offset,revision}`; limit 1..128, `next_offset=-1` means end; persist a stable current-revision snapshot |
| `tiles.stats` | — | `{revision,stride,tiles,parked_layers,bytes_used,ffi_calls,bytes_imported,bytes_exported,pixel_stream_calls,undo,redo}` |

**Per-batch order:** `append_samples → required_tiles → import_source/import_mask (only missing authorized inputs) → apply_tile_batch`; on `apply_tile_batch` error, native brush state and native draft are already rolled back for that batch. Re-append the source samples only after missing input/authority is repaired. `apply_tile_batch` validates **both** brush and edit layer/revision, and builds a detached replacement set; failure cannot partially stage a batch or advance cursor/pigment state. `required_tiles` is discovery, **not implicit permission** to assume a missing tile is empty. `commit_tiles` is the recommended *paired* publication boundary. The older `tiles.commit_edit` and `brush.commit_stroke` are independently callable for direct tests and transitional consumers but must **not** be used as a two-step paired commit in the final producer (one half could otherwise succeed while the other fails).

**Versioning and lifetime:** The document's serialized `revision` is the one published global revision stamp. Native `TileStore.revision` is its transaction-checked mirror. Native Brush/Eraser gestures and eligible external pixel edits (through `_publish_edit`/`_publish_tile_edit`) each commit exactly one Rust transaction from `r` to `r+1` before the Godot document installs detached consumer tiles at `r+1`. For external raster edits, the document first resolves every source and checks tile-object identity; the Rust bridge verifies resident source **bytes** (or explicitly authorized new source), editability, bounds and memory, and either commits all tiles/history or none. `DrawingDelta.native_history_token` identifies a retained Rust entry on the one ordered timeline. Undo/Redo prevalidate the Godot projected source, then use matching live Rust tokens; older evicted/mixed events still have detached tile snapshots as a fallback. **Metadata bridge:** `advance_metadata_revision(expected_revision, discard_redo)` is a checked *single-step* `r → r+1` revision mirror for operations that leave raster source bytes and identities unchanged. It preserves canonical tiles, authorizations and Rust Undo tokens; a *new* metadata edit clears Rust redo to match Godot's branched history, while a metadata Undo/Redo advances the stamp without clearing redo. It rejects stale/overflow revisions or active strokes without side effects. GDScript then detaches a rejected or diverged store (retaining detached document history), rather than claiming synchronized native ownership. **Structural raster guard:** `advance_unreferenced_layers_revision` permits create/remove Undo/Redo and nested subtree delete/restore if all raster child IDs have **never entered** this Rust store; a resident/authorized tile (even blank), tokenized Undo *or* Redo, active edit, stale revision, repeated ID or more than 128 layers rejects atomically. Godot still advances its revision on rejection and later uses a checked external rebase. **Detached subtree import:** `DrawingDocument.import_subtree` now prebuilds detached nodes and remapped tile metadata before publication; copied raster layer IDs that are entirely new to Rust advance through the same bounded, checked `advance_unreferenced_layers_revision` guard. Semantic-only imports use `advance_metadata_revision`. This preserves unrelated native undo tokens and canonical authorized tiles without claiming that the transferred Godot pixels are already resident in Rust; the first stroke on an imported layer still performs explicit source import. Native parked ID collisions reject the import without changing the document. A rejected/stale/>128-layer native bridge leaves the document on the conservative later checked-rebase path, not a partial native transaction; a direct removal now uses the bounded retirement operation below after verifying native source parity. **Recorded native-owned subtree park/restore:** `advance_parked_layers_revision` holds resident bytes and tokens in a checked parked set across local structure Undo/Redo. Before park, Godot checks known imported source identities **and full RGBA8 parity with Rust**; before restore, detached saved tiles are compared with original sources. Only a byte-identical restore rebinds canonical source objects without reimport. Direct reads for save/debug are possible, but new native imports/Brush/history replay for parked layers fail; unrecorded removal intentionally does not park. **Text conversion guard:** `rasterize_text` prebuilds the text glyph RGBA8 projection before checked `advance_unreferenced_layers_revision` at the same stable layer ID. Undo/Redo of that text↔raster kind change uses the same guard with `discard_redo=false`. Rust preserves unrelated source/history only when the converted layer was never authorized or referenced by native Undo/Redo; it imports glyph tiles lazily on the first native Brush. A newly rendered text source at a **previously parked** ID now uses the checked `replace_parked_layers_revision` bridge to retire the obsolete source and its tokens while retaining unrelated Rust history; a currently owned unparked ID rejects instead of pretending to be unreferenced. Text-raster Undo/Redo of the original source still uses verified park/unpark. Native-ahead rejects before Godot publication, while already-behind stores retain the conservative rebase. The Godot text rasterizer still materializes glyph tiles; it is not a native glyph rasterizer. **Detached history replay bootstrap (2026-11-16):** When `DrawingDocument` has no attached `DrawingNativeTiles` or it is behind the document's current revision, history replay no longer publishes a Godot-only tile projection. The document first resolves and revalidates all lazy sources and exact detached RGBA8 snapshots. It then creates a **provisional** ABI-v1 tile store at `base_revision`, imports the 1–128 touched expected-source tiles (including explicit empty/zero source), enables the authorized layer, and sends the same bounded expected/replacement tile batch to Rust `replay_detached_history`. Only a successful Rust revision `base_revision + 1` replaces the attached store and invalidates previous `_native_source_identities`; Godot publishes its prebuilt display/save tiles afterward without further lazy callbacks. Failure to instantiate, import, or replay leaves the document and old store untouched. If Rust is **ahead** of the document, replay fails closed rather than replacing newer native authority. A current store still uses native token replay or checked in-sync detached replay. Newly attached native authority is **partial** until untouched layers are independently authorized on first use; the host still owns detached history snapshots, and no Rust history tokens are invented for them. This cold replay recovery is separate from the Brush hot path and does not transfer UI/history ownership.

**Remaining exceptions:** rejected/over-limit retirement, unbridged raster source producers and external host-history mutations can still advance the document without a native transaction and force a quiescent `rebase_external_revision(native_r, document_r)` that loses old Rust history. Changed text sources at already-parked IDs use T-155's selective bridge; unchanged T-154 history snapshots still use reversible parking. Universal revision ownership and removing the shadow history fallback remain T-148 work.

**Direct unrecorded subtree retirement (2026-11-15):** `retire_layers_revision(expected, layer_ids, discard_redo)` is the irreversible counterpart to recorded `advance_parked_layers_revision`. It validates a bounded 1–128 distinct nonempty-ID batch, the exact document/native revision, absence of an active transaction and absence of parked IDs **before changing anything**. One successful call removes only those IDs' resident RGBA8 tiles, source authorizations, editability entries and Undo/Redo tokens, frees their memory and advances the native revision once. Other raster layers' exact source bytes and live native history survive. The document checks previously imported tile-object identity **and full native RGBA8 parity** before making the call; after success it drops only the retired source identities, deterministically erases the tree and removes obsolete *local* content/tree history references to that subtree, preserving surrounding Undo/Redo order. Host-owned external history is not mutated. This direct path is **not reversible parking**: the old IDs have no reserved tombstone and are reimported as entirely new source if reused. A failed preflight or API call leaves native history untouched; Godot falls back to a later checked rebase. Missing external history replay, unrecognized raster producers and integrated Atlas/Object native-source persistence remain acceptance gaps.

**Snapshots and display:** `read_tile` exports exactly one whole tile's contiguous copied bytes (not an unsafe pointer); `list_tiles` enumerates canonical identities in pages, and `dirty_tiles` gives the subset needed for screen invalidation. The dirty bounds are a conservative union of changed preview coordinates across accepted batches, suitable for display invalidation, not a minimal post-gesture diff bounding box. UI may cache `ImageTexture`s but must verify revision/generation; row alignment and the 128px display tiling are a **T-149 responsibility**. The original direct Save/Open witness enumerates native tiles and checks bulk-export SHA-256 parity. The newer production Canvas and document-persistence witnesses pass a real standalone `.drawing` Save/Open and Undo/Redo using the *document's packed tile projection*; the save orchestrator does not yet serialize Rust's persistent history stack. Atlas/Object integration is not yet proven.

**Measured bridge baseline:** With 99 96px NativeHard pointer samples, the direct Godot→Rust tile path stages a full 512×512 source in 4 tiles using 90.0ms of **native stage scheduling in one measured headless process**, 45 tile-store FFI calls (as counted at the measurement point), and zero `pixel_stream_calls`. This is **not** an editor responsiveness or input-to-photon benchmark; those timings predate the live Canvas cutover. The new software X11 witness measures one 512²/96px Canvas gesture at 536ms Hokusai / 808ms NativeHard, but these single runs are neither calibrated physical latency nor comparable to the earlier multi-process benchmark. See the live consumer evidence for exact transfer counts. See [T-148 evidence](evidence/T-148-2026-11-15-native-store.md) and [T-147 stroke ABI](NATIVE_STROKE_ABI_V1.md).


## Checked native-token replay payload (2026-11-16 checkpoint)

`DrawingNativeTiles.replay_history_token(token, expected_revision, undo, layer_id, tiles)` now requires a bounded 1–128 descriptor array of `{tile_x: int64, tile_y: int64, expected: PackedByteArray, replacement: PackedByteArray}`. Signed tile coordinates use the same native coordinate limits as imports. A missing/duplicate key, incorrect layer/direction, changed expected source or target bytes, malformed tile buffer, or stale canonical Rust pixels **rejects before mutation**. Empty PackedByteArray means an all-zero storage tile; transparent nonzero hidden RGB must match byte-for-byte. The native store compares these spans with the *entire* top Rust history event and its currently resident source in the same FFI call that applies Undo/Redo. Godot prepares the payload after reentrant source validation and cannot publish caller-modified replacement bytes that differ from Rust's canonical history. `has_history_token` is only a cheap probe, not sufficient authority. This is a breaking pre-release extension ABI change, covered by [T-148 history-payload evidence](evidence/T-148-2026-11-16-native-history-payload.md). The older detached snapshot fallback and incomplete universal raster authority remain separate acceptance gaps.

## Checked detached-history replay (2026-11-16 checkpoint)

`DrawingNativeTiles.replay_detached_history(layer_id, expected_revision, tiles)` accepts 1–128 descriptors of `{tile_x: int64, tile_y: int64, expected: PackedByteArray, replacement: PackedByteArray}`; empty packed bytes represent an all-zero tile. Rust checks the active transaction, layer editability, parked status, signed coordinate range, duplicate IDs, source RGBA8 equality (including transparent hidden RGB), exact stride/length, changed bytes, memory budget, and the shared revision **before** installing any replacement. A previously unimported tile is explicitly authorized by its expected image. Successful replay updates native canonical tiles and generations and advances the common revision by one; any unrelated resident tiles remain untouched. It invalidates native Undo/Redo stacks rather than synthesizing an opaque Rust token outside the host history timeline. Failure changes neither canonical source nor revision/history.

`DrawingDocument._replay_native_tile_delta` uses this operation only when the previous token is unavailable **and** the attached native store's revision equals the document's. It preflights all lazy providers and immutable snapshot bytes, calls Rust once, then installs only detached display/save projections. A valid live token still uses `replay_history_token`'s stronger exact-native-event parity check. When the native store is absent or stale, existing detached snapshot replay remains a deliberately incomplete fallback until universal native authority is implemented. This operation does not serialize Rust's history stack, make GDScript snapshots disappear, or close T-148. See [detached replay evidence](evidence/T-148-2026-11-16-detached-native-replay.md).

## Atlas global history handoff (2026-11-15 checkpoint)

`DrawingDelta` has two mutually exclusive reversible representations: legacy per-pixel `before`/`after` dictionaries when `tile_stride == 0`, or whole packed RGBA8 `before_tiles`/`after_tiles` with `tile_stride > 0` and a nonzero `native_history_token` for an active Rust transaction. `AtlasDrawingEdit` must take a **detached copy of the entire typed delta** when `AtlasEditHistory.commit_drawing` commits an already-published gesture, including all tile buffers and the opaque token. Copying only `before`/`after` would silently create an empty command for native painting.

Atlas remains the sole chronological command owner for `external_history` documents. `DrawingDocument.replay_delta` verifies the current source bytes of *every* changed tile before either replay; if Rust still recognizes the expected history token at its live top, it advances the same native/document revision and updates the display/save projection. An evicted or explicitly detached native owner uses the exact copied tile snapshots as a fallback and the next native brush reauthorizes those projected bytes on a checked rebase. Callers may mutate the returned commit delta without affecting the Atlas command. These snapshot fallbacks and Godot consumer bytes are **not** a replacement for the still-incomplete universal native-history authority.

A full Atlas campaign-generation save/lazy reload and fresh Brush on a reopened native-authored Drawing detail pass alongside standalone `.drawing` persistence and Atlas global Undo/Redo. This does **not** prove that native history tokens are serialized, nor integrated native-source Object editing. See [T-148 Atlas history evidence](evidence/T-148-2026-11-15-atlas-native-history.md).

## Production persistent native Brush/Eraser bridge (incomplete universal authority)

1. Canvas captures a frozen selection and source revision and creates a Rust stroke; `DrawingEditSession` requests the persistent Rust store from its `DrawingDocument`. The store's revision must match the document, or a **quiescent checked external rebase** discards old source authorizations/history. Untrusted source callbacks are checked again against revision, layer editability and source-object identity. Already imported tiles are reused without bulk retransfer only when the Godot source object still matches the identity recorded on authorization.
2. `append_samples → required_tiles → import_source/mask (if needed) → apply_tile_batch` produces native dirty tile IDs; preview reads detached packed `read_tile(..., true)` bytes. GDScript creates no per-painted-pixel stage/history map in production Brush/Eraser.
3. Mouse-up preflights **all** dirty tile bytes, identities and bounds against the Godot document **before** consuming the Rust brush transaction, then rechecks revision/layer authority and every source identity *after* all potentially reentrant providers. A detached preflight bundle is installed without any further lazy source callback after Rust commit. `commit_tiles` atomically installs canonical Rust tiles/history and yields a history token; `_publish_native_tile_edit` installs byte-identical packed Godot display/save snapshots and appends one tokenized timeline event. The consumer projection must not independently mutate the Rust revision. Cancelling discards drafts but retains the document's canonical Rust store.
4. On ordinary local Undo/Redo, `DrawingDocument` prevalidates bounded, canonical signed tile IDs and full before/after RGBA8 snapshots. Lazy source providers can reenter, so **after all source materialization** the document must recheck the revision, layer editability and identity, every source tile identity and byte string, and the delta snapshots before consuming a Rust token or installing a detached fallback. See [reentrant history replay evidence](evidence/T-148-2026-11-16-native-history-replay.md). A matching live native history token is replayed through Rust, followed by the identical projection update; older mixed events use the detached byte-snapshot fallback and force a checked rebase before the next native gesture. This fallback is **not** the universal native history owner required by final T-148 acceptance.
5. Layer-property, reorder, new empty-layer, text-only, density and semantic-object updates invoke the checked metadata revision bridge *after* their GDScript mutation. The bridge is only invoked for operations that do not change raster source. A reentrant active edit or stale Rust revision makes that call fail closed and detaches the document's native store, so the next gesture must authorize current source afresh; local detached history is still available. Structural deletion/replay of semantic-only subtrees uses the metadata bridge. A subtree containing raster children instead uses the checked `advance_unreferenced_layers_revision` gate: only previously unimported raster IDs can advance without rebasing, even when they contain pending lazy Godot source references. If Rust already owns their bytes/history, the call rejects and a later native gesture must rebase. Source-changing detached replay and previously-native-owned text rasterization are not yet universal native transactions; recorded local native-owned subtree removal/restore uses checked native parking, while eligible direct removals use the separate retirement protocol.
6. An ordinary non-brush raster publication with a current native store preflights source identities, allocates detached display/save tiles and prepares a tile history envelope **before** `adopt_external_edit`. The FFI call accepts at most 128 tile descriptors with full packed before/after buffers; on success its token joins the Brush/Eraser history and document installation performs no fallible provider calls. On any rejection the Godot document has not mutated. With no native store (historical test fixtures) the original GDScript publisher remains; other raster mutation paths can still trigger rebase, so universal authority and Atlas/Object native-source integration remain open.

The mixed-raster 64px 2-tile witness transfers **49,152 external packed RGBA8 bytes** in one accepted call (one resident `before+after` plus one blank `before` and full `after`), separately counted as `external_bytes_received`; zero per-pixel native output is returned. This excludes failed calls and does not establish a latency improvement. The historical pre-T-153 NativeHard 64px-canvas held/committed witness exported 49,152 tile bytes and imported 16,384 bytes over 10 tile-store FFI calls and 11 Rust-stroke calls; `tile_pixel_stream_calls` is zero. Legacy direct stroke statistics may still count `exported_ints` internally, so this number alone is *not* a proof that the engine computes no per-pixel integer values. See [T-148 live evidence](evidence/T-148-2026-11-15-live-cutover.md).


## New text source on a parked native raster ID (T-155, 2026-11-16)

A semantic text edit after Undo of a painted rasterization invalidates that
rasterization's Redo and creates new glyph RGBA8 at the **same** layer ID.
Rather than advancing only Godot and forcing a whole-store rebase,
`rasterize_text` now prebuilds the new source and calls
`replace_parked_layers_revision(revision, [layer_id])` when Rust is current
and the previous glyph source is parked. Rust validates the entire bounded
batch (1–128 distinct parked IDs; exact quiescent revision) before dropping
only their canonical bytes, authorization, editability, obsolete history
and parked tombstones. The one revision step clears Redo, preserves other
layers' Undo/pixels and permits fresh explicit glyph import on first paint.
A mixed parked/unparked batch, native-ahead store or active edit refuses
without publishing any Godot raster; a rejected active edit is retryable.
A current Rust-owned unparked text ID may **not** claim to be unreferenced.
This does not replace T-154 byte-checked Undo/Redo park/unpark or make
GDScript text glyph rasterization a Rust operation. See
[T-155 evidence](evidence/T-155-2026-11-16-reraster.md).

## Historical pixel-map history replay after native attachment (T-156, 2026-11-16)

`DrawingDelta` events from pre-native ordinary raster work may carry only
`before/after` pixel dictionaries (`tile_stride == 0`). When the document
already has `DrawingNativeTiles`, `replay_delta` now converts those cold
history events into bounded detached whole-tile RGBA8 images, then calls the
**same** `_replay_native_tile_delta` and Rust `replay_detached_history` used
by native snapshots. It never publishes a Godot-only raster revision while an
attached Rust owner remains in sync; malformed/noncanonical signed pixel
IDs, changed caller-owned deltas, stale pixels, native-ahead revisions and
oversized tile sets reject before Rust mutates. The conversion limits
allocated tile spans to 128 and conservatively budgeted 256MiB before any
lazy source resolution; it neither creates per-pixel Brush stage calls nor
invents new Rust Undo tokens outside the document/Atlas chronological owner.

Detached native replay deliberately clears obsolete Rust tokens; an older
pixel-map event remains a host-owned history snapshot. Its later Undo/Redo
repeats the checked native replay, including when the next Hokusai event's
Rust token has been invalidated. Without an attached native store, the
historical direct-session pixel publisher remains outside this narrow bridge.
General source producers, host history lifetime and final T-148 universal
authority still require further integration. See [T-156 evidence](evidence/T-156-2026-11-16-legacy-pixel-native.md).

## Native-owned text/raster history parking (T-154, 2026-11-16)

`DrawingDocument._replay_text_tree` calls the existing bounded native
`advance_parked_layers_revision(expected_revision, [layer_id], restore,
false)` when a previously authorized text-derived raster is hidden by Undo
or restored by Redo. Rust retains exact canonical straight RGBA8, hidden
RGB, source authorization and prior Undo/Redo tokens; an unrelated layer
remains paintable. Before this native revision advances, Godot checks that
its currently displayed raster (park) or detached event raster (restore)
matches every tracked authorized source identity and corresponding full Rust
`read_tile` bytes; no lazy callbacks run after the native mutation. Restoring
rebinds detached Godot object identities only after native acceptance.

An unowned text ID cannot create a parked tombstone: rejection of the park
operation must be followed by successful
`advance_unreferenced_layers_revision` at the same revision, or the edit
fails closed. If an attached Rust store was already *behind* the document
from an earlier unsupported edit, the existing checked rebase boundary is
retained instead of pretending to own new data. A store *ahead* is rejected.
This handles reversible **history playback of previously-owned** rasterized
text, not arbitrary live text rerasterization into a parked ID or complete
native-only history serialization. See [T-154 evidence](evidence/T-154-2026-11-16-text-raster-parking.md).

## Reentrant lazy source materialization (T-157, 2026-11-16)

`DrawingDocument._resolve_chunk` is a **Godot consumer source-hydration**
boundary, not a Rust paint kernel. A pending blob's loader is an external
callback and can reenter document edits, repoint its pending source, or
recursively request the same key. Before callback invocation, Godot freezes
its revision, display-source epoch, layer identity, lazy ref/digest/loader and
known persistence metadata. Once the callback returns, it rejects changed
authority **before** decoding or installing RGBA8. A per-document key guard
rejects recursive same-key requests with `SOURCE_BUSY`; changed revision
returns `STALE_REVISION`, changed layer/pending source returns `STALE_SOURCE`.
An unsuccessful fetch leaves the current pending reference in place for a
corrected retry. Exact byte length, straight-RGBA8 SHA-256 and hidden RGB are
still required. This closes a direct read/display stale-source gap but does
not serialize Rust history or make all non-Brush raster producers native. See
[T-157 evidence](evidence/T-157-2026-11-16-lazy-guard.md).
