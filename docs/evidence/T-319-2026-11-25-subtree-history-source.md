# T-319 — Detached multi-layer structural history source authority

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`,
local parent `d72860a8` (T-318). Pinned Godot 4.8 beta4 with the compiled
Rust extension reproduced 10 failures in 19 checks against the prior code.
A detached removal Undo restored Godot-only raster data, a detached Redo
removed those sources without native parking, and a replacement owner could
not restore a snapshot marked parked by the previous owner. Invalid late
history descriptors and divergent live bytes also escaped the detached path.

The additive subtree-history publication method adopts all unreferenced
raster IDs and their exact retained source tiles at one native revision,
optionally parking the entire group in that same revision. It retains
unrelated native Redo and creates no pixel token. A provisional owner is
attached only after success. Native-backed subsequent replay validates the
adopted snapshot's hierarchy, complete tile authority and live source bytes;
extra unauthorized tiles cannot be published or silently erased. The Rust
unit test independently proves malformed later descriptors leave all native
layers and the revision untouched and that multi-layer parking preserves a
foreign Redo token. Save and Copy parity apply before any new paint.

The existing physical sparse late-read promotion is unchanged. A historical
logical-only lazy read after Undo exposed a compatibility issue in the first
implementation (T-148 metadata test, 1/61 failures). Restricting the new
admission to removal events with retained tiles or a previous parked-source
flag preserves the existing logical-only metadata bridge. The retry passed.
Pending descriptors are not resolved by the detached path; if a pending tile
has been read while detached and its retained snapshot cannot prove those
bytes, Redo rejects rather than losing the source. Entirely empty removals
remain metadata-only. Mixed already-owned and unowned retained raster IDs in
a single existing owner continue to use the existing checked path; unified
admission for that case and universal host-history authority remain open.

| Witness | Result |
| --- | ---: |
| T-319 detached subtree source | 51/51 |
| T-314 detached subtree import | 35/35 |
| T-148 import revision | 33/33 |
| T-169 native import fence | 24/24 |
| T-175 semantic import fence | 27/27 |
| T-172 Atlas transfer replay | 33/33 |
| T-318 detached text history | 52/52 |
| T-148 Atlas native history | 43/43 |
| T-148 metadata revision | 61/61 |
| T-177 raster history fence | 89/89 |
| T-176 structural history fence | 121/121 |
| T-168 subtree removal fence | 30/30 |
| T-148 unrecorded retirement | 34/34 |
| T-315 portable source | 61/61 |
| T-316 sparse admission | 58/58 |
| T-317 sparse eviction | 45/45 |
| T-310 binary Drawing | 307/307 |
| T-148 native tiles | 312/312 |
| Rust unit tests | 41/41 |
| Python CI/replay/log contracts | 45/45 (175 subtests) |
| Explicit typing | Passed (642 scripts, 33 skill documents) |

Both pinned project imports and T-319/T-314/T-148-import checks completed in
`make test-native-subtree-history-source`; the outer container timeout
interrupted the neighboring test loop. The target was then rerun to exit 0
with `-o import-drawing -o import-atlas` to reuse those completed imports.
The existing Atlas history witness now emits a success marker for the strict
log validator. Python CI replay tests initially failed one environment check
because Git LFS is unavailable; the rerun with the two checkout-only LFS
filter overrides passed. The ten additional headless regressions above were
run separately against the same staged extension and scripts.

No UI changes, no physical GPU/Windows/hosted CI acceptance. New admission
is bounded to 128 raster IDs, 8,192 descriptors and 256 MiB aggregate native
data. A group with resident sources reserves its raster IDs (including empty
siblings), just like the existing parked-subtree operation. Detached Undo
trusts the retained structural snapshot if the original native copy is gone;
this is not cryptographic authentication of the host timeline. T-148 stays
In Progress and the owner-review gates remain untouched.
