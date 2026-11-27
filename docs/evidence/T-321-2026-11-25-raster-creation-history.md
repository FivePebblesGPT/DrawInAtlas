# T-321 — Raster creation history with retained native paint tokens

PR #24 remote base `79bf892fbab44ab7670655dca1b448e41788aae9`, local parent
`a81f6620` (T-320). The pinned Godot 4.8 beta4 fail-first witness failed 3 of
10 checks: Undo of a painted-then-undone layer creation was rejected, its
blank sources and Redo were not parked, and a detached nonempty raster could
be removed by creation Undo. The first corrected run passed 17/17, expanded
branch and rejection coverage 58/58, final expanded witness 64/64.

The existing unreferenced-layer fence correctly rejects native ownership,
including blank tiles, so it is not an appropriate replay bridge for a
created raster after its strokes have been undone. The new checked
`advance_empty_created_layer_revision` verifies the entire empty canonical
source set, no still-applied native history, correct parked lifecycle and
current revision, then parks/restores or advances the unreferenced ID. Godot
validates the empty original snapshot, live metadata, source object identity,
bytes, pending/known physical references and unpublished edit reservation.
The created node is not removed on failure. Native Redo remains parked and
cannot run before restoration. No source images or tokens are duplicated.

When the local owner truncates an abandoned creation branch, the new
`discard_empty_creation_history` releases only that absent blank layer's
canonical source, reservation, editability and future events at the unchanged
revision. The checked reclamation also works during an unrelated pending
native transaction (selection-only branch). Unrelated applied history is
preserved. A refused reclamation leaves native authority intact rather than
forcing an unsafe release. General abandoned removal/text snapshot lifecycle
and external host history consolidation remain open. The previous T-177
regression explicitly expected refusal for a real Hokusai stroke followed by
creation Undo; that obsolete expectation is now an exact native token
roundtrip, retaining the 89-check suite and all its original failure fences.

| Witness | Result |
| --- | ---: |
| T-321 native raster creation and branch history | 64/64 |
| T-177 raster structural history (real Hokusai) | 89/89 |
| T-176 structural history fence | 121/121 |
| T-319 detached subtree history | 51/51 |
| T-320 mixed subtree history | 46/46 |
| T-318 detached text history | 52/52 |
| T-239 retained native history order | 36/36 |
| T-148 metadata revision | 61/61 |
| T-148 native tile contract | 312/312 |
| T-316 sparse admission | 58/58 |
| T-310 binary Drawing codec | 307/307 |
| T-148 Atlas native history | 43/43 |
| Rust unit tests | 43/43 |
| Python required-native / fast-CI contracts | 26/26 |
| Explicit typing | Passed |

`make test-raster-creation-history TOOLCHAIN=bundle BUNDLE=<supplied archive>`
passed both project imports, the final new witness, T-177, all Rust tests
and Atlas native history. The nine separate neighboring Godot scripts passed
against the same fully imported build. The new witness runs in ordinary
`make test` and fast desktop CI. No UI appearance changes, hosted CI run,
Windows or physical GPU/performance acceptance are claimed.

Both methods are cold history operations, with existing 128 parked layer
and 256 MiB store limits. The Rust store must verify that all resident bytes
are zero (not merely transparent) and the host's exact identity count
matches; the host cannot use the creation fence to remove nonempty source.
The general host command timeline, older detached tile-snapshot history and
other parked layer reclamation remain T-148 integration work. Owner UX
acceptance remains T-250.
