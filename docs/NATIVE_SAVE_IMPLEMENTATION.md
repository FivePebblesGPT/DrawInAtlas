# Native single-file campaign saves

**Status:** local Godot 4.8-beta1 acceptance passed on 2026-10-29. This records
local evidence, not a successful remote CI run or merge of draft PR #4.

## Physical and runtime contract

`AtlasCampaignStore` writes one compressed binary **`.scn` PackedScene** containing
a data-only `AtlasCampaignSaveRoot`, owned `AtlasMapSaveNode` children and embedded
Resource-backed domain objects. The campaign Resource owns metadata, links and
placements; owned map nodes supply the authoritative map list, reconstructed as
a runtime registry by stable ID. Node names, paths and child order are not map
identity. Editor/viewer nodes are never packed. There are no standalone `.res`
files, artwork sidecars or JSON payloads inside the native file.

Each raster chunk embeds lossless WebP bytes, dimensions, signed chunk position
and SHA-256 identity over dimensions and exact RGBA8 bytes. Decoded Images remain
non-exported runtime caches. **AD-10 selects embedded WebP plus whole-scene
ResourceSaver compression**, based on the [comparative benchmark](NATIVE_SAVE_BENCHMARKS.md).

The default is `user://drawinatlas_campaign.scn`. A campaign's adjacent paths are
`name.bak.scn`, `name.pending.scn` and `name.bak.pending.scn`. Pending files are
never automatic recovery candidates. A verified candidate is staged and reloaded
before activation; only a validated current head can replace the previous backup.
A corrupt head therefore cannot overwrite a healthy backup. Every write/rename
is checked. Recovery returns structured provenance and keeps the editor dirty
until a new save repairs the head; failed loads retain the active work/history.

## Validation and isolation

Native format version **1** is separate from the retained in-memory dictionary
schema number 6. Complete-candidate validation checks the version, domain rules,
semantic digest and exact pixel hashes before exposing a campaign. Map IDs are
sorted for metadata/digest consistency; ordered floors and layers are preserved.
External resource dependencies are restricted to shipped `res://scripts/*.gd`;
arbitrary asset/campaign dependencies are rejected rather than hidden sidecars.

Scene encoding/decoding uses isolated temporary resource paths because Godot has
no PackedScene-from-byte-buffer API. `CACHE_MODE_IGNORE` bypasses both the main
scene and embedded subresource cache; only immutable application scripts are
shared. Independent file loads have separate mutable maps, floors, strokes,
layers, chunks and decoded Images. Native tests exercise those nested copies.

Old v1–v6 JSON user saves are neither imported nor deleted. Compatibility
`to_dict`/`from_dict` methods remain useful for validation, snapshots and tests;
the clipboard retains its independent format. Neither is a JSON save loader.

## Evidence and limits

See [implementation notes](IMPLEMENTATION_NOTES.md#native-single-file-saves--local-validation-2026-10-29)
for all headless, framebuffer, startup and export results. `tests/storage_smoke.gd`
includes **76 checks** and explicit portable-fixture commands:

```bash
godot --headless --path . --script res://tests/storage_smoke.gd -- write-portable /tmp/campaign.scn
# Run in another freshly imported compatible checkout/process:
godot --headless --path /path/to/other/checkout --script res://tests/storage_smoke.gd -- read-portable /tmp/campaign.scn
```

The fixture contains multiple floors, cyclic links/multiple entrances, a spatial
placement, high-precision scalar settings, transformed raster artwork and hidden
RGB in negative/edge chunks. Fresh source checkouts and an exported resource pack
were tested in both directions; unrelated Godot projects/versions are not a
portability promise. The pack was run with the exact beta engine; a standalone
Linux release binary was not produced because its templates were unavailable.

Whole-file rewrites, whole-graph loading and eager pixel hydration remain real
costs. The implementation does not globally deduplicate identical chunk payloads
or garbage-collect abandoned pending files. Backups/staging/temporary decoding can
require several full-file generations of free space. Linux replacement behavior
is verified, not Windows/macOS behavior or power-loss durability. Browser smoke
remains deferred; successful Web export is a build-compatibility check only.
