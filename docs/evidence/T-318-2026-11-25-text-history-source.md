# T-318 — detached text raster history source authority

PR #24 remote checkpoint `79bf892fbab44ab7670655dca1b448e41788aae9`,
local parent `13ee878a` (T-317). The real Godot 4.8 beta4 + Rust fail-first
witness reproduced 9 failures in 27 checks: absent owner Undo/Redo left the
raster detached, stale owner Undo/Redo advanced only the host, changed
live bytes could be lost on detached Undo, and Redo with a newly attached
unreferenced owner advanced without importing glyphs.

The new history-specific FFI reuses the bounded subtree descriptor and
unreferenced-ID checks. It imports/parks atomically, retains unrelated native
Undo/Redo, and advances revision once with no new pixel event. Existing owned
park/unpark remains the primary path; validation now covers additional
unowned snapshot keys and malformed tile backing storage before publication.
Detached Undo checks the entire saved raster tile set and exact current
bytes; detached Redo trusts the retained structural snapshot as the fallback
source when no native canonical copy exists. Pending edits and stale attached
stores reject rather than detach or rebase. The corrected witness includes
malformed late descriptors, empty glyphs, retry after rejection, attached and
provisional owners, and an isolated native-token retention test with a
synthetic synchronized host revision. The Rust unit test independently proves
atomic failed batches, retained unrelated redo and signed hidden RGB.

| Witness | Result |
| --- | ---: |
| T-318 detached text history source | 52/52 |
| T-313 text source publication | 32/32 |
| T-148 text raster revision | 32/32 |
| T-154 parked text history | 30/30 |
| T-155 text re-rasterization | 32/32 |
| T-178 semantic text fence | 43/43 |
| Atlas semantic text | 60/60 |
| T-148 native tile contract | 312/312 |
| T-310 binary codec | 307/307 |
| Text editor model | 18/18 |
| T-314 subtree source | 35/35 |
| T-315 portable file source | 61/61 |
| T-316 sparse source | 58/58 |
| Rust unit tests | 40/40 |
| Python CI contracts | 30/30 (17 subtests) |
| Explicit typing | Passed |

The new witness is required by ordinary `make test` and fast desktop CI.
No appearance changes; no physical-device, Windows or hosted CI acceptance.
The history admission retains the existing 8,192 descriptor and 256 MiB
aggregate limits; it does not replace semantic history or authenticate a
snapshot whose original owner is lost. The rest of T-148/T-149 native
consolidation remains open and T-250 owner approval is unchanged.
