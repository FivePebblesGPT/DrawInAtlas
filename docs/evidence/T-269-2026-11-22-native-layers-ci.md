# T-269 — Required-native T-089 Layers CI / Atlas verification (2026-11-22)

## Baseline and fail-first reproduction

Branch `sprint/2026-11-20-selection-dock-colors-brushes` at local
`1eea3f5a` (21 commits beyond the last observed PR #22 remote
`7b1fd306`). The original T-089 optional workflow invoked
`tools/build_drawing_app.py --in-place` and Godot editor import, but **never
built or registered** `libdrawing_brush.so`. No `.so` is checked in. On a clean
runner the native-backed Drawing UI would therefore be unavailable.

The added `tests/test_t269_layer_ci.py` failed all **3/3** workflow,
Make-target and artifact contracts against that starting state; those same
three contracts pass after the repair. This is a structural CI negative
control, **not** a claim that a previous hosted test was executed or failed.

Before changing the workflow, the already-staged standalone tests passed:
T-089 structure model **63/63** (its intentional pending-stroke warning is
retained) and native software-X11 **36/36**. The 36-check native verifier was
already exact; it remains authoritative.

## Changes and native coverage

- The optional workflow now pins Godot 4.8 beta3 and Rust 1.99.1,
  runs `make build TOOLCHAIN=system` to compile/register native Rust and
  import **both** canonical Drawing consumers before executing tests.
- The 63-check model uses a strict exact-count assertion plus the shared
  fail-closed Godot log verifier. The X11 test uses the unchanged 36-check
  `check_native_t089_log.py`. The new 27-check Atlas test uses an exact
  summary and the shared strict Godot verifier. Every log is uploaded under
  `if: always()`, even when a witness fails.
- `make test-layer-hierarchy` runs the same build/import/model/X11/Atlas
  sequence, with Bash `set -euo pipefail`, `tee` and per-test verifiers.
- New `tests/t269_atlas_layers_native.gd` creates a real `AtlasCampaign`,
  registers a 64px tiled Drawing detail, and embeds the **same** workspace
  class used by standalone Drawing. Two opaque lower/upper raster layers
  and a nested group retain signed, hidden-RGB source bytes. Actual X11
  group-eye clicks change the framebuffer from upper green to lower red and
  back without moving selection or erasing the source. Group lock and
  unlock preserve edit authorization. A native signed tile edit commits
  through `AtlasEditHistory` as one global command; there is no Drawing
  local Undo shadow. Global Undo/Redo is source-exact, and saving/reloading
  an Atlas campaign preserves nested group IDs, visibility/lock state and
  both opaque and zero-alpha straight-RGB tile bytes.

These are **test/CI-only changes**; no production Canvas, layers, Rust,
Atlas history or renderer code was modified.

## Local execution and independent regressions

Test environment: Godot `4.8.beta3.official.c51ff06e8`, Rust 1.99.1,
Linux x86-64, X11/Xvfb at 1600×1200×24, Mesa llvmpipe OpenGL compatibility,
and supplied offline Cargo vendor directory. The workflow was **not** run
on GitHub; no Windows or physical input-to-display claim is made.

| Witness | Observed result |
| --- | --- |
| Fail-first T-269 workflow/Make/artifact contracts | 3 failed / 3, then 3 passed / 3 |
| `make test-layer-hierarchy` native build and both imports | exit 0; both `NATIVE_EXTENSION_READY` |
| T-089 model | 63 checks, 0 failures |
| T-089 standalone X11 | 36 checks, 0 failures |
| New T-269 Atlas X11 | 27 checks, 0 failures |
| Atlas layer model | 135 checks, 0 failures |
| Atlas native tile/global history | 43 checks, 0 failures |
| T-092 Atlas History under X11 | 21 checks, 0 failures |
| Python T-269/T-089/T-092 CI contracts | 14 tests passed |
| Explicit GDScript typing | 594 project scripts, 33 skill documents passed |
| Ruff 0.17.5 and ty 0.0.104 (new CI contract) | passed |
| Ticket index / owner-review dependency validator | 269 tickets valid |

The T-092 witness must run with X11: a preliminary headless invocation
correctly failed its display prerequisite and was rerun under X11 to pass
21/21. The supplied offline uv wheel index lacked registry metadata for
`uv run --offline --with`; lint was therefore executed with the identical
pinned Ruff/ty binaries already extracted in the toolchain cache. No online
package resolution was attempted.

Full local reproduction with the supplied offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:/path/to/toolchain/bin:$PATH
export CARGO_VENDOR_DIR=/path/to/toolchain/vendor CARGO_NET_OFFLINE=true
make test-layer-hierarchy TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot \
  CARGO=/path/to/toolchain/rust/bin/cargo \
  UV=/path/to/toolchain/bin/uv
python3 -m unittest tests.test_t269_layer_ci tests.test_t089_native_log
python3 tools/validate_ticket_store.py
```

## Independent gates

T-089 remains engineering **Done**, but T-059 and T-250 still need explicit
owner UX approval. T-094/T-180 require separately verified hosted native CI,
packaging and release acceptance. T-105 Windows and physical Linux/Windows
input/display remain unverified. The test adds no new user-facing Atlas
feature and does not satisfy or bypass any owner gate.
