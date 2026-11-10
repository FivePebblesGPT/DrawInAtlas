# T-095 — 2026-11-11 native Hokusai/GDScript batch transaction evidence

## Scope and gate

- Branch: `sprint/2026-11-11`; remote baseline SHA was
  `f9e54fdfc81fb72840023665694fb24b55fb220e` (confirmed via live GitHub
  branch list on 2026-11-11).
- Ticket: T-095 **In Progress**, `manual_review: true`, T-053 Done prerequisite.
  T-096 separately in **Manual Review**. No owner decision or hosted CI gate
  is inferred from software tests, and no PR or merge was performed.
- Engine: bundled Godot `4.8.beta3.official.c51ff06e8`; Rust/Cargo
  `1.99.1`; Hokusai `0.3.0`; godot-rust `0.5.5` / API `4.7`.
  Vendored dependencies and `--locked --offline` build. No archive or native
  binary is committed.

## Independent failure reproduction

`drawing/tests/t095_native_pigment_atomic.gd` instantiates the *real*
`DrawingNativeBrush` GDExtension and parses the bundled `hard_round.myb`,
rather than stubbing `preset_segments`. It creates two independent
document/native pairs with 16px source tiles, large positive/negative signed
anchors, hidden-RGB transparent source, translucent pixels, a subtractive
selection hole and clipping. Both engines accept an initial sample batch.
Only the first document rejects the second source-tile resolution on a
later, nonempty Hokusai batch. Both paths are then checked after either
(a) retrying the same failed batch and continuing with an additional pigment
batch, or (b) committing the prior valid batch without a retry.

Before this change (same branch, original native binary and original
GDScript), the test exited 1 with **4 of 56 checks failing**:

- Replayed same-object pigment/preview did not match uninterrupted reference.
- The following native paint batch also diverged.
- Signed RGBA8 bytes at commit differed from detached/reference preview.
- Redo did not restore the reference's committed pixel image.

The failure did **not** require a native panic, physical GPU stall, or any
manual approval; it was a deterministic native-state rollback defect.
The injected GDScript read originally kept detached preview unchanged,
but could not undo the native pigment surface/export cache/RNG state.

## Implementation

- `begin_preset_batch` snapshots `BrushState` and starts a per-tile
  copy-on-first-write journal; `preset_segments` journals prior exported
  raw fixed-point/RGBA8 caches only for changed native tiles.
- `rollback_preset_batch` restores the original tile map, including
  **removing previously absent tiles**, cursor/RNG state and quantized
  export snapshots. `commit_preset_batch` discards journals after the full
  GDScript preflight and stage are successful; successful paint still
  stays tile-local.
- The sparse `TrackedSurface` implements the upstream `MemSurface` tile
  and atomic-dirty contract, while exposing exact deletion of failed new
  tiles instead of retaining allocation-only ghosts.
- `DrawingEditSession.paint_path_hokusai` begins a native batch before
  sampling, rejects unsupported real GDExtension binaries, rolls back on
  invalid delta, out-of-range coordinate, or failed lazy-source read, and
  commits only after all GDScript patches update. Legacy scripted oracles
  without native pigment state keep their existing stub behavior.
- Canvas Hokusai opt-in now checks transaction capabilities at gesture
  start and falls back to Legacy for an older incompatible binary.

## Local checks, no owner/hosted claims

After rebuilding and staging through `python3 tools/build_drawing_app.py
--in-place` and cold Godot editor import, actual native test output:

```text
T095_NATIVE_PIGMENT_ATOMIC_RESULT checks=57 failures=0
T095_NATIVE_PIGMENT_ATOMIC_PASSED
```

All tests below exited with process code **0** in the local beta3 setup:

| Verification | Result |
| --- | --- |
| Rust unit tests (including existing/new/missing native tile rollback) | 4/4 |
| `cargo fmt --check`; `cargo clippy --all-targets -- -D warnings` | clean |
| Native source-read/commit/retry oracle | 57/57 |
| Hokusai scripted delta parity | 126/126 |
| Signed Hokusai tile shift | 422/422 |
| Native export cache (hard/soft/ink/airbrush) | 81/81 |
| Real native Brush integration (all four presets) | 30/30 |
| NativeHard preflight | 28/28 |
| Existing hard-brush byte oracle | 32/32 |
| Native-tile commit / Legacy-tile commit | 56/56 / 519/519 |
| Deferred Brush / failed mixed-edit rollback | 492/492 / 504/504 |
| Stage-result reuse / sparse preview / stage-batch ring | 30/30 / 133/133 / 29/29 |
| Released-stroke navigation, Xvfb/Mesa GL | 48/48 |
| Native-present, prior-binary and fresh native-absent fallback | 7/7 each |

Xvfb/Mesa `brush_latency_native.gd` (five 120-motion 60px/786% strokes)
exited 0 and printed `T095_NATIVE_PASSED`, stage p95 **179.799ms** and
release-to-commit p95 **55.692ms** in that local run. This regression
witness is **not a paired Hokusai before/after benchmark**, physical
input-to-photon measurement, owner-device acceptance, or proof that
T-095's reported responsiveness issue is fixed. No hosted Actions run,
Windows export or hardware reviewer result was verified this turn.

A compatibility negative control temporarily rebuilt the exact original
`f9e54fdf` Rust source, left the new Canvas GDScript installed, and ran
`native_brush_fallback.gd`: **7/7**, process exit 0, selecting Legacy
for a genuine class that lacks the transaction methods. The rebuilt
current native binary was restored afterward. A *separate* clean project
import without any `.gdextension` or native binary passed the same
fallback oracle **7/7**, exit 0. With the new native binary installed,
the Hokusai-capable path also passed **7/7**, exit 0.

The existing **46 required fast GDScript CI check IDs** are unchanged.
The on-demand `godot-native-t095-brush.yml` now runs the native rollback
oracle after the pinned release build and validates its marker with the
strict fail-closed log checker; its raw log is uploaded.
