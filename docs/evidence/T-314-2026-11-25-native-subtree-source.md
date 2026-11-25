# T-314 — immediate native ownership of detached raster subtrees

## Baseline and implementation

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`, local
parent `3b6cb471` (T-313). The new real-native fail-first fixture failed two
of its initial four assertions: the first multi-layer import did not attach
Rust or authorize any copied source. The previous metadata-only import bridge
advanced the native revision without importing raster bytes, delaying authority
until the first paint. T-314 introduces a single bounded multi-layer source
publication via `publish_subtree_revision`. It reuses the unreferenced-layer
revision preflight, verifies full descriptor membership, exact RGBA8 and
unique signed keys before cloning buffers, then advances one revision and
installs every source without creating a second pixel Undo event. Other native
Undo tokens remain intact, while branching discards Redo.

The document validates tile stride, canonical sparse/packed storage and signed
projection keys before detaching the tree. It rejects pending edit sessions,
reserves parked identities, and configures a provisional native owner on first
use. On success it binds the exact prepared tile identities before exposing
the tree. Source save/copy fences, structural park/replay and permanent
retirement now cover imported pixels even before first paint. Tests check
corruption of hidden RGB, malformed late descriptors, duplicate IDs/keys,
unknown layers, busy/stale/referenced/parked IDs, bounded memory, mismatched
strides, exact Save/Open, and unrelated native Undo/Redo. Atlas Move Undo/Redo
asserts immediate native authority in the receiving document; existing Copy
and rejected-replay witnesses remain green.

## Execution

Linux x86-64, Godot `4.8.beta4.official.b070e63b1`, pinned bundled Rust.

```sh
make test-native-subtree-source TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py' -v
python3 -m unittest discover -s tests -p 'test_t211_native_ci_contract.py' -v
```

| Witness | Result |
| --- | ---: |
| T-314 immediate multi-layer source publication | 35/35 |
| T-148 import/native history | 33/33 |
| T-169 import fence | 24/24 |
| T-175 semantic import fence | 27/27 |
| T-172 Atlas Move/Copy replay | 33/33 |
| Rust unit tests, including atomic subtree batch | 38/38 |
| T-148 unrecorded retirement | 34/34 |
| T-148 native tile contract | 312/312 |
| T-313 native text source | 32/32 |
| T-310 binary persistence | 307/307 |
| T-171 native export fence | 33/33 |
| T-148 Atlas native history | 43/43 |
| Drawing semantic text | 60/60 |
| Asset transfer and standalone smoke | pass |
| Python CI contracts | 24/24 |
| Explicit typing and Kanban | pass, 314 tickets |

The first combined Make run encountered an older test's result-only log marker;
all its 33 assertions passed. Added an explicit success marker and reran the
verification target plus Rust tests successfully, then reran the complete Make
target with exit 0. The new tests run from the
ordinary `make test` target. This is a backend change and does not change UI
appearance; no new visual acceptance evidence is claimed.

## Boundaries

Imports admit at most 128 raster layer IDs and 8,192 descriptors subject to the
256 MiB resident-plus-incoming native budget. All tiles must match the
recipient stride; no retiling is attempted. Empty imported raster layers do not
allocate native source data. The existing synthetic sub-native stride/model-only
consumer path is retained. Cross-document commands remain host-owned; this is
not a multi-document Rust transaction, and existing compensating rollback
semantics are unchanged. Remaining raster producers, general detached/host
history and universal revision authority remain T-148 work. T-250 is Manual
Review, with no owner approval inferred. Physical GPU/Windows and hosted CI
remain unverified. No new LFS assets.
