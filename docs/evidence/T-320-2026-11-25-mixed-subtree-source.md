# T-320 — Mixed subtree raster source authority

Remote PR #24 base `79bf892fbab44ab7670655dca1b448e41788aae9`, local parent
`ff8019d6` (T-319). The pinned Godot 4.8 beta4 fail-first witness reproduced
6 failures in 12 checks: the recorded mixed removal parked only existing
native bytes, omitted an unowned sibling and an unowned coordinate within an
owned layer, and could not restore a mixed replacement owner. The first fix
passed 12/12; expanded regression and pending-descriptor fence pass 46/46.

The new native operation validates the complete descriptor set, including
explicit blank authorizations. Native-owned entries must match both identity
and exact RGBA8; missing entries must not be authorized or referenced by a
native history image. Existing generations and tokens survive. The operation
admits missing coordinates and parks or restores the affected layer IDs in
one revision. Older partially parked snapshots are accepted only when their
existing native sources are parked and exact. Recorded removal clears Redo
as before; structural replay preserves it. Newly adopted events use the
strict retained-source fence, including pending descriptor parity and late
verified physical-source promotion. Unresolved sources never invoke I/O here.
A separate Rust test checks atomic rejection and retained generation/token
behavior. Godot witnesses include stale canonical bytes, an omitted native
coordinate, wrong parked lifecycle, busy owner, malformed coordinates, blank
authorization, signed hidden RGB, pending-source tampering, Save/Copy fences,
and repeated replay with an unrelated Redo token.

| Witness | Result |
| --- | ---: |
| T-320 mixed subtree source | 46/46 |
| T-319 detached subtree source | 51/51 |
| T-314 detached subtree import | 35/35 |
| T-148 import revision | 33/33 |
| T-148 metadata revision | 61/61 |
| T-168 subtree removal fence | 30/30 |
| T-169 native import fence | 24/24 |
| T-175 semantic import fence | 27/27 |
| T-176 structural history fence | 121/121 |
| T-177 raster history fence | 89/89 |
| T-172 Atlas transfer replay | 33/33 |
| T-316 sparse admission | 58/58 |
| T-317 sparse eviction | 45/45 |
| T-310 binary Drawing | 307/307 |
| T-148 native tile contract | 312/312 |
| T-148 Atlas native history | 43/43 |
| Rust unit tests | 42/42 |

`make test-native-mixed-subtree-source` completed both pinned project imports,
the initial expanded 45-check witness, neighboring import/replay witnesses,
Rust tests and Atlas native history. The final pending fence and 46-check
witness were rerun against the same native extension; T-319, T-316, T-148
metadata and T-176 also passed. Initial binary test on a staging-only project
failed with missing imported font resources; after the full project import
it passed all 307 checks. No UI changes; no hosted CI, physical GPU or Windows
acceptance claimed.

The 128-layer and 8192-descriptor limits remain; native resident plus the
complete temporary descriptor batch must fit 256 MiB (conservative peak).
Unowned retained bytes are still trusted legacy snapshots, not cryptographic
authentication. Already fully adopted events fail closed if only some native
sources are subsequently lost; fully detached recovery remains T-319. Host
command timeline consolidation remains T-148, and owner UX approval T-250.
