# T-315 — portable Open native source ownership

## Baseline and design

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`, local
parent `75ca2656` (T-314). The real-native fail-first fixture reported
6 failures of 21 assertions: binary, legacy JSON and portable Object readers
returned materialized source bytes without a native store. Consequently their
native save/copy parity fences had nothing to check until a later edit.

After full portable envelope, manifest, font, digest and referenced-tile
validation, `DrawingFileIO.decode()` now calls
`DrawingDocument._adopt_opened_raster_sources()`. The clean, fully resolved
document configures an unattached store at its saved revision and imports each
bounded signed source using the existing same-revision `import_source` ABI.
The owner and exact Godot source identities are installed only after every
import succeeds. No revision, history or dirty marker is created. Invalid
storage, unresolved references or a previously attached store reject the
bootstrap; failure cannot publish any partial native owner. Subsequent edits
reuse the owner. Save/Copy verifies native source bytes including hidden RGB;
local structural removal/restore parks/unparks the already authorized sources.

All portable readers share this boundary, including the legacy encoding
used by Object registry revisions. Logical `open_manifest()` remains lazy for
sparse campaign content. Empty documents and historical native-unsupported
small strides remain readable. Native-free historical model fixtures remain
supported until T-150; production builds still require the native extension.
No new Rust ABI, file version, or UI appearance is introduced.

## Execution

Linux x86-64, Godot `4.8.beta4.official.b070e63b1`, pinned bundled Rust.

```sh
make test-native-file-sources TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
make verify-native-file-sources TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py' -v
python3 -m unittest discover -s tests -p 'test_t211_native_ci_contract.py' -v
```

| Witness | Result |
| --- | ---: |
| T-315 portable initialization | 61/61 |
| T-310 binary codec | 307/307 |
| T-166 native save source fence | 24/24 |
| T-158 signed lazy tile bounds | 24/24 |
| T-230 detached pixel replay | 33/33 |
| T-232 first tile-local publication | 34/34 |
| T-233 first pixel-map publication | 37/37 |
| Standalone smoke | 43/43 |
| Asset transfer | 43/43 |
| T-148 Object native lifecycle | 38/38 |
| T-148 Atlas native history | 43/43 |
| Object assets | 95/95 |
| Semantic text | 60/60 |
| Python CI contracts | 24/24 |
| Explicit typing and Kanban | pass, 315 tickets |

The initial Make target passed. Its expanded verification target also passed
(exit 0). The older Object lifecycle witness initially failed its assertion
that the saved private draft's store was null; it now verifies a distinct
native owner with zero Undo/Redo, exact canonical bytes and an authorized
source. T-230, T-232 and T-233 now check reuse of the already authorized
owner after Open; their independent detached-bootstrap tests remain intact.
T-315 runs under the regular Make test target and required fast-desktop CI.
Hosted CI for the local commit has not run.

## Remaining boundaries

Portable decode remains synchronous. This eagerly adds one native RGBA8 copy
per referenced tile, bounded by the existing 128 MiB expanded-file budget
(and native's 256 MiB store budget). This is not a bound on process RSS; the
Godot projection and codec buffers still exist. T-310 storage benchmarks are
historical, not measurements of this new load path. Large-file and linked
catalog memory/latency profiling remains open. Sparse campaign lazy sources,
full host-owned history/revision consolidation, physical-device performance,
Windows portability and manual owner review are not closed by T-315.
