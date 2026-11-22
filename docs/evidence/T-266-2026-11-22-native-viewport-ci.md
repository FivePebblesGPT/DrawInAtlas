# T-266 — Required-native viewport-cache CI repair (2026-11-22)

## Baseline and reproduction

- Branch: `sprint/2026-11-20-selection-dock-colors-brushes`; unpushed parent
  `d8e0e02f`; latest observed PR #22 remote head `7b1fd306`.
- Linux X11, Mesa llvmpipe, Godot `4.8.beta3.official.c51ff06e8`, required
  offline Rust GDExtension. Testing uses the project’s provided vendored Cargo
  tree (`CARGO_NET_OFFLINE=true`); no GitHub-hosted run was performed.
- Existing `.github/workflows/godot-native-t086-viewport.yml` imported the
  Drawing package directly after checkout. The native `.so` is generated, not
  tracked; a fresh runner did not first build/register it.
- Before changes, `viewport_cache_native.gd` returned **153 checks, 4 failed**.
  A pressed Hokusai stroke had `session != null` but `_preview_epoch == 0` and
  `preview_index_keys == 0`: the test was inspecting a native session before
  any paint pixels had been staged. A one-pixel Undo correctly removed its
  transparent target tile, while an independent visible tile refreshed (one
  65,536-byte upload), contradicting the old aggregate zero-upload assertion.
- The existing T-137 18-check X11 suite consistently failed **one** Redo
  framebuffer check. Instrumentation showed the canonical source already held
  the restored `0xffdd2233` pigment, but `cold_tiles_deferred == 12`, so three
  framebuffer frames could not guarantee that tile was drawn.
- `t086_compare_cold_composite.py --godot <pinned Godot>` fails while importing
  the old renderer: it lacks `DrawingRenderer.prepare_visible_layers()` and
  the current seven-argument `render(...)`. These old files remain immutable
  and SHA-pinned; this is an API-compatibility failure, **not** performance
  evidence of either a regression or an improvement.

## Repair and pass conditions

The T-086 native X11 witness now uses a genuine movement sample at 100% and
25% zoom with a pinned hard preset. A still-open session is not mistaken for
painted pixels; the preview index must contain affected tiles, bound uploads,
and survive signed-zoom framebuffer and cancellation assertions. The erasure
check requires that the erased transparent tile and its occupancy hint vanish,
that no new blank texture is allocated, and that the surviving texture may
legitimately refresh. Hidden-RGB exact Undo/Redo remains tested.

The T-137 Redo witness waits for a bounded **24×2 frame** cold-settlement
window, asserts the display scheduler completes, and verifies both canonical
RGBA8 and the visible blue pixel. Its success count increases from 18 to 19.

`make build TOOLCHAIN=system` now precedes all native on-demand tests. The
paired pre-cache **framebuffer** benchmark is preserved and was independently
run successfully on current Godot. The archived cold-composite baseline files
are checked by their original SHA-256 tests, but their incompatible comparison
is not a current required CI step. Instead the current renderer executes nine
measurements per case with three exact RGBA8 output hashes under the pinned
engine. `check_t086_logs.py` rejects incomplete, duplicated, errored or
unexpected source/benchmark results.

## Local verification

| Test | Observed result |
| --- | --- |
| Before T-266 T-086 native | **153/153 executed, 4 failed**, process 1 |
| Updated T-086 native | **153/153 passed**, exit 0 |
| Before T-266 T-137 native | **18 checks, 1 failed**, repeated |
| Updated T-137 native | **19/19 passed**, twice plus clean Make run |
| `make test-viewport-cache TOOLCHAIN=system` | **exit 0**; native compiled, both Godot projects imported and reported `NATIVE_EXTENSION_READY`, T-086 153, T-137 19, 3 cold cases and 3 historical fixture contracts passed |
| T-102 model/native | 13/13 and **110/110** passed |
| T-103 model/native | 13/13 and **150/150** passed |
| T-135 signed sparse viewport | **23/23** passed |
| T-136 detached sparse union | **26/26** passed |
| T-138 bounded focal retention | **22/22** passed |
| Historical pre-cache vs cached X11 comparison | `T086_COMPARISON_PASSED` (software CPU measurements, not physical latency) |
| Current cold renderer benchmark | `T086_COLD_BENCH_PASSED`; nine samples each, three exact source SHA-256 values |
| T-266 strict Python CI contracts and historical fixture tests | **6/6 + 3/3** passed |

Exact current renderer fingerprints at Godot 4.8 beta 3:

| Case | RGBA8 SHA-256 |
| --- | --- |
| Opaque | `e49dcee7b4b28a4ad6a8de43560d13cfecdb307c1d02a9458da8bc8042debb3a` |
| Alpha | `25e7f578b53dd14aa3b5a0a7b5956eb784a363abf294ed2b2e4c5e0597f462a7` |
| Empty alpha (hidden RGB) | `8a39d2abd3999ab73c34db2476849cddf303ce389b35826850f9a700589b4a90` |

To reproduce with the supplied offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_NET_OFFLINE=true CARGO_VENDOR_DIR=/path/to/toolchain/vendor
make test-viewport-cache TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot CARGO=/path/to/toolchain/rust/bin/cargo
python3 -m unittest tests.test_t266_viewport_ci tests.test_t086_benchmark_fixtures
```

**Limits:** The on-demand GitHub Actions workflow was not executed on a hosted
runner. The historical cold comparison is not current native throughput evidence;
the current cold benchmark captures CPU timings and deterministic source bytes,
not physical input-to-photon latency. T-086 and T-149 remain under their own
native display and physical memory/performance gates; T-094/T-180 release gates,
T-059/T-250 owner review and unrelated Atlas features remain unchanged.
