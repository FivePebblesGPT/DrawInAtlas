# T-317 — conservative native sparse renderer residency

## Baseline and design

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`;
local parent `faf27856` (T-316). The fail-first real-native witness requested
18 distinct signed 2048px physical sources (288 MiB of RGBA8) by rendering
a two-pixel viewport on each. The original implementation failed seven of
25 checks: admissions 17 and 18 failed at the 256 MiB aggregate store cap,
the oldest source remained resident, and there was no re-admission boundary.
The corrected 45-check witness observes a peak of 201,326,592 native counted
bytes (192 MiB), renders every tile, preserves hidden RGB across re-fetch,
and verifies both native and projection removal. This is counted native bytes,
not total RSS, a timing benchmark, or physical GPU acceptance.

The new additive native v1 method compares the entire committed RGBA8 span,
requires a pristine generation, matching revision and live authorization,
and rejects any active transaction, parked layer or retained Undo/Redo
reference. Only DrawingDocument may establish physical reloadability. It
retains the original verified ref/digest/callable and weak tile identity;
changed refs, changed/dirty projections, replaced tiles and local structural
snapshot layers are ineligible. Native success restores the original
pending descriptor and erases the resident projection and identity. There
are no callbacks, revision changes or edits in that release operation.
Ordinary re-admission verifies the same ref/digest and RGBA8 length before
publishing anything.

Only the dedicated renderer resolution entry point trims on missing physical
sources. It preserves the original two-argument resolver/override contract
used by edit, export, and instrumented renderer tests. The initial additional
parameter was removed after two older subclass tests detected the signature
mismatch. Trimming reserves room before the new provider runs, so a failed
incoming fetch can still leave unrelated *clean* cache entries pending; the
logical document and requested source remain unchanged. Reentrant provider
calls and active script/native sessions cannot trim. The high-water check
uses 192 MiB including the next tile and targets 128 MiB, with at most 256
FIFO candidate keys collected and examined per miss. Temporarily protected
entries rotate to avoid permanently blocking later candidates. Neither this
policy nor the physical format is global artwork eviction.

## Execution

Linux x86-64; Godot `4.8.beta4.official.b070e63b1`, pinned bundled native
extension. Commands:

```sh
make test-native-sparse-eviction TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py'
python3 -m unittest discover -s tests -p 'test_t211_native_ci_contract.py'
python3 -m unittest discover -s tests -p 'test_t071_storage_docs.py'
```

The final Make target and all eight direct adjacent Godot witnesses returned
zero. The campaign test adds a real physical blob release and re-admission,
including saving a subsequent generation while the source is pending and
re-reading it afterward. The renderer instrumentation regressions passed
again with the original resolver signature preserved.

| Witness | Result |
| --- | ---: |
| T-317 native sparse eviction | 45/45 |
| T-316 native sparse admission | 58/58 |
| T-157 reentrant source | 23/23 |
| T-158 signed lazy bounds | 24/24 |
| T-166 native save fence | 24/24 |
| T-315 portable initialization | 61/61 |
| T-066 physical campaign generation | 105/105 |
| T-066 editor Save/Load | 23/23 |
| T-172 host transfer replay | 33/33 |
| Rust unit tests | 39/39 |
| T-086 shared chunks / cold tile | 31/31 + 45/45 |
| T-086 visible plan / sparse layer | 82/82 + 74/74 |
| T-086 sparse pixels | 590/590 |
| T-088 selection sparse capture | 54/54 |
| T-148 native tiles | 312/312 |
| T-310 binary Drawing | 307/307 |
| Python CI/storage contracts | 32/32 |
| Explicit typing and ticket-store validation | pass, 317 tickets |

The new witness is required by ordinary `make test` and fast-desktop CI.
Hosted runs on the new commit have not occurred.

## Remaining boundaries

FIFO, not LRU; the soft thresholds and scan bound are engineering defaults.
Edited, parked, structurally retained, active, stale or non-reloadable sources
can still fill the 256 MiB native cap. Non-render readers do not evict, so
large bulk operations and history can still fail explicitly. No general
native eviction of dirty/history bytes, streaming edit admission, host-history
consolidation, physical latency/RSS/VRAM, Windows, hosted CI or owner UX signoff
is claimed. Frame-local immutable source references, Godot projections and
blob decoder caches are outside the native accounting. No UI appearance
changes are introduced.
