# Portable Drawing and Atlas campaign storage — T-066

**Implemented and locally verified:** 2026-11-02, Godot 4.8-beta2, Linux. This is the currently versioned `v1` campaign-generation contract, **not** a decision that 256-pixel tiles or one file per chunk are the optimal final format. **T-067 has completed its benchmark**: 512×512 is the recommended future new-document stride and immutable segmented packs the candidate physical layout; **neither is deployed by the v1 writer**. T-071 reconciles the historical audit and importer pages with this contract.

## Authority, paths, and portable identity

The application accepts an absolute logical `Campaign.scn` path but **does not create that `.scn` as the new authoritative save**. Atlas writes a sibling `Campaign.atlas.json` atomic root pointer and `Campaign.atlas.bak.json` recovery pointer. Those point to immutable generation files:

```text
Project/
  Campaign.atlas.json            # current atomic generation pointer
  Campaign.atlas.bak.json        # previous independently recoverable pointer
  Drawings/
    generations/<generation-id>/
      generation.json            # checksummed file/object/font/document refs
      campaign.scn               # legacy native scene metadata (not pixels)
      registry.json              # stable map/floor/detail -> DrawingDocument IDs
      objects.json               # immutable Object Asset/instance index snapshot
    manifests/<document-id>/<manifest-sha256>.json
    chunks/<prefix>/<canonical-tile-digest>.zst
  Objects/<asset-id>/vNNNNNN.drawing  # independently published source versions
  Fonts/OFL-1.1.txt
  Fonts/<licensed-font-id>.ttf
```

All generation references are project-relative, validated against symlinks, `..` and noncanonical paths, then SHA-256 verified before publication or acceptance. The root and generation schemas are `atlas-campaign-root-v1` and `atlas-campaign-generation-v1`; generic document metadata is `drawing-sparse-manifest-v1`. Atlas alone owns campaign membership and the `(map_id, floor_id, detail_id)` registry; standalone Drawing and independent third consumers still use `addons/drawing/` without Atlas imports.

Every active authored detail has exactly one stable internal document ID and a recorded rational pixel density and explicit **per-document tile stride**. A detail never painted has a logical identity but no raster manifest or chunk data. No D0 artwork is synthesized beneath an empty higher-detail level. Grid/entrance overlays remain Atlas-owned.

## Sparse tile and exact-byte contract

Each populated tile is a canonical straight-RGBA8 byte array, including hidden RGB where alpha is zero. The canonical tile ID includes dimensions and bytes; its on-disk payload is lossless Zstandard (`.zst`). The generation index contains both this canonical digest and the compressed-file digest; the first load verifies the physical digest without decoding every raster. A viewport request decompresses only referenced tiles and checks the **canonical** digest again. A bounded LRU (`32 MiB`, at most `64` decoded entries) replaces unlimited image retention; load errors fail closed instead of fabricating transparent pixels.

The JSON manifest encodes signed chunk coordinates as decimal **strings**; integer coordinates outside the precise IEEE-754 range (e.g. ±9,007,199,254,740,993) reopen exactly. Tile width is versioned in the document manifest, not inferred from whichever project default Godot uses. Generic semantic dictionaries preserve Godot Variant values with a SHA-256-checked typed encoding; text, source asset IDs, independently movable instance IDs and licensed font data remain portable.

## Atomic generation publication and recovery

1. Atlas checks the last loaded root digest (optimistic concurrency) and validates the map/floor/detail registry against the live campaign. A stale writer is rejected **before** writing a new authoritative root.
2. Only modified populated tiles become new compressed content-addressed blobs. Reused tiles and never-opened documents retain their previously verified manifest references. Removed maps/floors are excluded from the new index, but retained data is not immediately deleted (undo/old-generation safety).
3. Publish immutable, verified manifests, Object source references, font and OFL license files, and generation-scoped scene, registry, object index and generation index. Loading or publication fails on a missing/corrupt/tampered path, blob, licensed font or source asset.
4. Stage and flush a complete new root pointer. Before replacing an existing valid head, save the previously valid pointer as the backup; **only the single root-pointer rename commits the generation**. A failed write/rename never advances in-memory document savepoints.
5. On open, verify the head generation; on failure independently verify and recover the backup. Non-current data is retained for undo/recovery and can also be republished. A rejected concurrent writer retains its dirty document for manual resolution.

Object version files are independently immutable and are referenced, not rewritten, when a campaign generation changes. Source Save/Save As publication and Atlas global undo remain T-060/T-054 ownership. Undo's saved variant B is retained even after unbinding it. **Automatic orphan/dead-generation garbage collection is deliberately disabled.** Future Optimize Project must trace all live, retained, and undo/history references before deleting anything; that compaction operation is not currently implemented.

The scheme is robust against the tested interrupted writes and atomic file-renames, **not a universal guarantee for arbitrary filesystem power loss** (no directory `fsync` API or physical-drive crash laboratory test). Copy or rename the **entire enclosing project directory**, not just the root JSON. A partial copy cannot be treated as a complete project. No migration of historical `.scn` saves is promised; the old native codec is retained only as a compatibility/test path.

## Loading and memory boundary

Project startup reads and hashes compressed files and validates all indexes but does not inflate raster tiles or load every DrawingDocument into memory. `AtlasDrawingRegistry` resolves each authored detail on first actual view/edit; the layer panel projects stored blank/authored metadata without force-opening every D-level. Document reads and history requests validate tile bytes lazily. I/O is synchronous during save and integrity preflight in this version: no claim of asynchronous streaming or fixed VRAM use, and no silent disposal of dirty documents.

## Repeatable local evidence / bounded performance sample

Run the reproducible sparse-save and failure-injection witness:

```bash
godot --headless --path . --script res://tests/campaign_bundle_smoke.gd
godot --headless --path . --script res://tests/campaign_bundle_editor_smoke.gd
```

`campaign_bundle_smoke` includes sparse two-tile edits at widely separated signed positions; exact transparent-pixel RGB, partial boundary tiles, a second generation, previous-generation fallback, failed root rename, failed generation write, stale concurrent writer, map removal, optional text/fonts, two linked Object instances, moved/renamed whole directories, and corrupt/missing/unsafe references. `campaign_bundle_editor_smoke` drives the real editor Save/Load path, including confirmation before discarding dirty Drawing documents on Load or Sample; the cancel/reopen path keeps only one pending callback. Sample reset preserves the observed root-generation lease so intentional replacement remains concurrency-safe. Invalid JSON pointers fail without Godot parser error logs. The legacy layer UI fixture tests `.atlas.json` recovery, not obsolete `.bak.scn` files. The exact `.atlas.json` pointer and file-count assertions are regression coverage, not a data migration guarantee.

A single local Linux headless run (2026-11-02, test run from current checkout; **not a controlled cross-device benchmark**) reported:

| Sparse save case | Wall-clock time | File writes (including staged files) | Renames | New compressed tile files |
| --- | ---: | ---: | ---: | ---: |
| First publish of two distant tiles | 13.5 ms | 8 | 8 | 2 |
| Incremental retry, one changed tile already safely staged by failed save | 11.5 ms | 6 | 6 | 0 |

The test measures `Time.get_ticks_usec()` and instrumented `AtlasStoreIO` operations on the same run; these numbers are **illustrative**, hardware/cache dependent, and should not be treated as a performance target. Total content-addressed tile blobs after the aborted save/retry: **3**, not billions for the huge sparse coordinate range. One small edit changes only its touched tile, not the entire document or map. Startup preflight hashes compressed files and uses additional proportional I/O; no CPU, peak RAM/VRAM or large-file-count measurements are claimed yet. **T-067** has now completed the [reproducible size/packing benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md): 512 is the recommended *future new-document* stride and immutable segmented shared packs the candidate physical layout. **Neither is deployed by this v1 writer**; the versioned per-document stride and verified single-blob `.zst` paths remain unchanged pending tested adoption. The current per-tile `.zst` layout is `v1`, explicitly extensible rather than a preapproved permanent geometry.

## Reproducible portability and failure acceptance — T-071

These are **current implemented behaviors** verified by `tests/campaign_bundle_smoke.gd` and `tests/campaign_bundle_editor_smoke.gd`, not just an unimplemented design proposal. Run the fixtures on a **temporary test project** (the scripts create their own temporary folders), never delete files from a real user campaign:

```bash
# Run from the Atlas repository root with Godot 4.8 beta 2.
godot --headless --path . --script res://tests/campaign_bundle_smoke.gd
# Exercise the actual editor Save/Load UI and dirty-document protection.
xvfb-run -a godot --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/campaign_bundle_editor_smoke.gd
```

| Acceptance case / fixture operation | Expected result and source check |
| --- | --- |
| **Whole-directory relocation:** save a campaign with D0/D1, linked Object Assets and editable text, copy the enclosing project directory to a different name/location, reopen there and save again. | The new `Atlas.scn` *logical path* resolves relative `Drawings/`, `Objects/`, `Fonts/` references; stable IDs, pixels (including transparent hidden RGB), object links and licensed fonts survive. `campaign_bundle_smoke.gd::_portable_assets_and_fonts`. |
| **Partial copy:** omit `Fonts/lato-regular-v1.ttf` after copying the project directory. | Load fails validation; it **must not silently fall back** to a system font or produce a plausibly incomplete document. `_portable_assets_and_fonts`. Copying only `Campaign.atlas.json` or the generation's `campaign.scn` is **not** a supported backup. |
| **Missing or damaged referenced chunk:** corrupt the compressed `.zst` blob in a one-generation fixture, then remove the file entirely. | Load returns `ERR_FILE_CORRUPT` when there is no independently valid backup; the image is not silently replaced with transparency. `_corruption_and_precision`. In multi-generation projects, fallback is allowed **only** if the backup generation independently validates every reference. |
| **Interrupted new generation:** after saving two generations, remove the active `generation.json` while the backup index and its files remain. | `AtlasCampaignBundle.load()` returns `recovered = true`, with the **previous complete generation** and its exact old pixels; `_run`. |
| **Failed write or root-pointer rename:** inject a generation-file write failure or a `.atlas.json` root rename failure after a valid first save. | Save fails without advancing the authoritative root or the dirty document savepoint. The prior generation still loads; a later complete retry can succeed. `_failures_and_sparse`. |
| **Concurrent editors:** open two writers at the same root digest, publish from one, then try to publish from the stale other. | The stale writer receives `STALE_ROOT` and retains its changes rather than replacing the other writer's root. `_failures_and_sparse`. |
| **Large signed coordinates:** write a pixel at `(9007199254740993, -9007199254740993)`, save and reload. | Decimal-string chunk addresses avoid JSON floating-point integer loss, preserving exact pixel bytes. `_corruption_and_precision`. |
| **Unpainted authored detail:** create a logical D1 without raster pixels and save. | D1 remains blank/unallocated rather than borrowing D0 artwork; opening it does not hydrate every document. `_run`. |

**What recovery does not guarantee:** arbitrary power-loss/directory-durability semantics, backups made by copying only selected files, an automatic repair of corrupted user data, or migration of historical native-only `.scn` campaigns. The implementation intentionally retains old generations and unreferenced saved assets; no production garbage collector/Optimize Project is implemented. Partial copies may be rejected even if a subset of art looks readable: do **not** normalize failure by inventing blank tiles.

**Versioned geometry remains independent of buffering:** each document's persisted `tile_stride` is part of `drawing-sparse-manifest-v1`; signed coordinate interpretation must never change silently. The `DrawingRasterImport.import_image()` edit-region default is **128**, legacy `AtlasRasterChunk.SIZE = 256` is a historical baseline, and a renderer's GPU upload tile is a separate choice. [[T-067]] measured 256/512/1024/2048; **512** is a future default recommendation, not a migration or deployed switch. Production physical packing is still individual verified Zstandard blobs, **not** a deployed shared pack. A future pack writer/retiling pass must pass the same complete-generation publication, exact RGBA8, signed-coordinate, interrupted-write and backup-fallback tests before adoption.

**Authority references:** [[DECISIONS_DRAWING_ATLAS_2026-11-01]] (approved architecture), [[T-066]] (shipped format), [[T-067]] (measured but undeployed recommendations), [T-029 dictionary audit](DICTIONARY_CONVERSION_AUDIT.md), [T-030 raster import](RASTER_CHUNK_IMPORT.md), and [chunk geometry benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md). This T-071 documentation-only change does not alter save bytes, create a new UI workflow or approve any manual-review gate.

## Test commands and separate review gates

```bash
python3 -m unittest discover -s tests -p 'test_drawing*.py'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
godot --headless --editor --path . --import --quit
godot --headless --path . --script res://tests/storage_smoke.gd
godot --headless --path . --script res://tests/drawing_world_mapping_smoke.gd
godot --headless --path . --script res://tests/drawing_composition_smoke.gd
```

T-066 is storage-engineering work and has **no owner-review gate**. It does not close T-056/T-059 (hands-on UX), T-064 (nested assets), T-065 (Asset Browser/NULL prompts), T-067 (future stride/pack deployment), nor T-071 (this broader documentation sync). Windows runtime and literal power-loss resilience remain unverified; CI workflow success on GitHub cannot be claimed without a remote run.

**Validation note:** one combined regression attempt encountered a process abort in the legacy `storage_smoke.gd` test without a diagnostic assertion. An isolated rerun passed all 77 checks. The new bundle tests passed in the same verification period; this intermittent failure remains unexplained. The standalone Drawing clean Linux x86_64 release export and packaged font/license probe also passed, demonstrating that the shared generic package still exports independently of Atlas.
