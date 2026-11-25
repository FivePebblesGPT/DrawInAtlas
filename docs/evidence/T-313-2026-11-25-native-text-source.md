# T-313 — native structural text source publication

## Baseline and change

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `01e1dfdf` (T-312). The real pinned beta4/Rust fail-first fixture failed two of its first six assertions: rasterizing the first text layer did not attach a native store or authorize its glyph tiles. After immediate native publication, a separate fail-first probe found the live semantic Save/Copy projection still incorrectly compared the inactive parked glyph bytes. That persistence defect was corrected; public chunk reads return detached copies, so the mutation negative control explicitly modifies the resident projection.

`TileStore.publish_structural_source` performs checked, all-or-none adoption of signed, complete RGBA8 tile buffers, without adding a duplicate pixel Undo token. The FFI validates descriptor count, shape, duplicate coordinates, revision, live ownership and resident-plus-new memory before copying the buffers. The caller checks Godot projection coordinates. New text conversion attaches a provisional store only on success, and replacing a parked source preserves unrelated canonical tiles and Undo tokens. The existing structural park/unpark bridge now works even before any Brush. A live semantic node with its previous glyph raster parked has no raster projection and can be saved or copied without serializing that parked source. The structural event remains Godot-owned.

## Execution

Linux x86-64, pinned Godot `4.8.beta4.official.b070e63b1`, bundled Rust toolchain; real native GDExtension. Ran:

```sh
make test-native-text-source TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py' -v
python3 -m unittest discover -s tests -p 'test_t211_native_ci_contract.py' -v
```

| Witness | Result |
| --- | ---: |
| T-313 standalone source ownership, immediate and replacement, RGBA8/persistence, malformed FFI, pending and empty sources | 32/32 |
| T-148 text raster revision | 32/32 |
| T-154 parked history | 30/30 |
| T-155 re-rasterization | 32/32 |
| Rust unit tests (including new atomic source test) | 37/37 |
| T-058 text model | 60/60 |
| T-307 hosted Object Editor (extended conversion, exact source, park/replay, unchanged published source and Atlas history) | 26/26 |
| T-178 text history fence | 43/43 |
| Object Editor UI/persistence | 26/26 |
| T-148 native tile contract | 312/312 |
| T-310 binary Drawing persistence | 307/307 |
| T-148 Object native lifecycle | 38/38 |
| T-148 Atlas native tile history | 43/43 |
| Native standalone text (X11 framebuffer) | 7/7 |
| Python CI order and required-native contracts | 24/24 |
| Explicit typing and Kanban gate validation | pass, 313 tickets |

The full Make target exited 0. The existing fast CI `make test` now invokes `verify-native-text-source` (all four headless text/history suites); its Rust unit step also runs the new core test. Hosted X11 verification exercises the real Object Editor (llvmpipe; expected unsupported VSync warning). This is a storage/history backend change, not a UI appearance change; no cosmetic acceptance or new screenshot claim. The tests preserve semantic-to-raster exact composited pixels, native tile bytes including hidden RGB in unrelated ink, Save/Open, and source isolation. Historical T-148/T-155 test expectations now check immediate source import and no redundant first-paint import rather than the previous lazy import policy.

## Remaining boundaries

Glyph shaping and structural history remain in Godot. Native source publication admits at most 8,192 descriptors and 256 MiB resident-plus-new bytes (conservative before old parked bytes are released); it rejects stale or busy stores rather than forcing a rebase. Empty sources remain valid; synthetic strides below the native ABI and isolated model-only consumers retain the old non-native path. Other producers, including detached subtree import and host-owned detached history, still need T-148 integration. Physical GPU/Windows and hosted CI are not verified. T-250 remains Manual Review; no owner approval inferred. No new LFS assets.
