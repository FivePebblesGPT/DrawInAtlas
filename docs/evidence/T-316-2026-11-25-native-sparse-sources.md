# T-316 — lazy physical sparse native source ownership

## Baseline and design

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`,
local parent `8b1ac7e7` (T-315). The initial real-native witness (23 checks)
reported seven failures: physical sparse reads were not native-owned before
first paint, so Save/Copy parity, owner reuse and later parking could not be
established. During implementation, a broader 41-check witness found five
failures of the structural replay edge case (source read after Undo restored
an unresolved removal snapshot). Both regressions are corrected.

Physical `DrawingBundleManifest.decode` now opts into native lazy admission
while retaining metadata-only Open. `_resolve_chunk` performs its existing
callback identity, revision, epoch, canonical digest and length validation
first, then admits exact source bytes at the current revision before setting
the Godot tile and erasing the pending descriptor. A provisional native owner
is invisible until its first import succeeds. A later import uses the
existing owner, including during an active native stroke for an unstaged ID.
Native-rejected, corrupt and obsolete callbacks never publish the requested
tile. Neither read nor import changes the dirty/savepoint state or history.
No disk schema, native ABI, or UI appearance changes.

The local structural removal event can initially hold pending references. If
its Undo is followed by a lazy read, Redo verifies the original digest, current
native identity and exact native bytes, prepares a detached snapshot, and
parks the now-owned subtree. Only after native success does it promote those
pending descriptors in the event. Busy/altered-source rejection leaves the
original event, revision, tree and cursor unchanged; repeating Undo/Redo
restores the resident bytes without another provider call. Untouched pending
neighbors stay lazy. Atlas Move/Copy remains host-owned.

## Execution

Linux x86-64; Godot `4.8.beta4.official.b070e63b1`, pinned bundled native
extension. Full Make target returned zero:

```sh
make test-native-sparse-sources TOOLCHAIN=bundle BUNDLE='/mnt/data/drawing-toolchain-linux-x86_64.tar(2).zst'
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py'
python3 -m unittest discover -s tests -p 'test_t211_native_ci_contract.py'
python3 -m unittest discover -s tests -p 'test_t071_storage_docs.py'
```

| Witness | Result |
| --- | ---: |
| T-316 native sparse admission and structural replay | 58/58 |
| T-157 reentrant lazy source | 23/23 |
| T-158 signed lazy bounds | 24/24 |
| T-166 native save fence | 24/24 |
| T-315 portable initialization | 61/61 |
| T-066 actual campaign generation and recovery | 100/100 |
| T-066 editor Save/Load | 23/23 |
| T-172 host transfer replay | 33/33 |
| T-089 layer structure model | 63/63 |
| T-148 native retirement | 34/34 |
| T-148 native tiles | 312/312 |
| T-314 native subtree publication | 35/35 |
| T-310 binary codec | 307/307 |
| T-068 publication tile cache | 30/30 |
| T-148 Atlas native history | 43/43 |
| Python CI/storage contracts | 32/32 |
| Explicit typing and ticket-store validation | pass, 316 tickets |

The first eight witnesses are the Make target; the seven additional Godot
witnesses ran directly against the same native binary after imports. The
layer-structure fixture produced its expected pending-stroke refusal warning,
not a script error. The actual campaign fixture now additionally asserts
lazy allocation, immediate signed-source ownership and unchanged savepoint.
The T-316 marker is mandatory in fast-desktop CI and ordinary `make test`;
new hosted runs have not occurred. No visual acceptance is claimed because
this is model/source authority work rather than a UI redesign.

## Remaining boundaries

Read-only sparse admissions consume native's existing 256 MiB aggregate
resident/transaction/history budget. Unlike the chunk decoder LRU, native
source ownership is not yet evictable, so a long large-map browsing session
can reach that cap even without edits. Admission then fails explicitly with
the source still pending; the cap is not a bound on total process RSS and
this is not evidence of large-map responsiveness. A safe clean-source
retirement/re-admission policy must preserve exact RGBA8, pending refs and
all history tokens; it remains a T-148 follow-up before broad native authority
acceptance. Historical logical-only and unsupported-stride model consumers
remain unchanged. Host-owned history/revision consolidation, physical GPU,
Windows, hosted CI and the owner-review gates remain outstanding.
