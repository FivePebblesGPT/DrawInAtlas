# T-267 — Required-native selection/contour CI (2026-11-22)

## Reproduction and scope

Branch `sprint/2026-11-20-selection-dock-colors-brushes`, local parent
`8b09d307`; last observed PR #22 remote head `7b1fd306`.
The previous `.github/workflows/godot-native-t088-selection.yml` staged the
Drawing project and immediately invoked Godot import, without building the
required native Rust extension. The native `.so` is not a tracked Git/LFS
artifact. A new three-test contract failed **2/3** against that workflow and
the missing Make target; the diagnostic-only third contract passed.

The required-native T-210 graphical regression has **52** assertions; the
existing log verifier accepted only 51. The verifier now rejects an otherwise
valid-looking 51-check log and requires at least 52 with a single summary,
single success marker, no failed checks and no hidden engine diagnostics.

## Correction

The on-demand workflow pins `1.99.1` Rust alongside Godot 4.8 beta 3, executes
`make build TOOLCHAIN=system` before any selection/contour test, preserves
seven signed contour X11 witnesses (T-139–T-145), and additionally runs the
Atlas-owned T-253 native Delete/history/Save/Open test. Existing diagnostics
are uploaded even on failure, with strict `set -euo pipefail` and per-test
marker validation.

The new `make test-selection-native` target builds/imports both native
consumers, checks the T-088 52-assertion framebuffer test, first/last contour
examples T-139/T-145, dense X11 Delete, and Atlas dense-history. The hosted
workflow intentionally retains all **seven** contour variants; a local Make
smoke run does not pretend to replace that full matrix.

## Local verification

Godot `4.8.beta3.official.c51ff06e8`, Linux X11/Mesa llvmpipe,
offline Rust 1.99.1 and vendored Cargo crates, `CARGO_NET_OFFLINE=true`,
`CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor` (machine-local path).

| Witness | Result |
| --- | --- |
| Pre-change CI contract | **2 failed / 3 tests**, expected missing native build and Make target |
| Updated T-267 and T-088 Python CI/log contracts | **11/11 passed** |
| `make test-selection-native TOOLCHAIN=system` | **exit 0**; real Rust build; both Godot imports `NATIVE_EXTENSION_READY` |
| T-088 native selection, Move, clipboard and zoom | **52/52**, strict log pass |
| T-088 headless selection/clipboard model | **131/131**, success marker |
| T-139 and T-145 signed edge contours in Make | **7/7 and 10/10**, strict log pass |
| T-140–T-144 remaining contour X11 matrix | **9/9, 8/8, 11/11, 10/10, 9/9**; individually or in the initially timed-out batch |
| T-253 dense X11 Selection Delete | **41/41**; p95 176,951 µs (7 virtual-X11 samples) |
| Atlas dense Delete/native history/save/reopen | **15/15**, strict log pass |

Adding the new Make section also exposed a brittle neighboring T-266 Python
contract which split the viewport recipe body at the old `# T-251` heading.
It now isolates the recipe at its first blank section boundary instead of
coupling to the identity of the next test target.

The first unoptimized Make suite reached T-143 without a failure but was
terminated at the container's 300-second command limit. Each subsequent
contour case passed independently; the revised Make smoke target passes
end-to-end within the execution limit. No hosted Actions invocation occurred.

Reproduction with the provided offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_NET_OFFLINE=true CARGO_VENDOR_DIR=/path/to/toolchain/vendor
make test-selection-native TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot CARGO=/path/to/toolchain/rust/bin/cargo
python3 -m unittest tests.test_t267_selection_ci tests.test_t088_floating_log -v
```

**Review boundary:** These are simulated X11 and headless/native tests, not a
hosted CI green or physical input-to-photon acceptance. T-088/T-149, T-094,
T-180 and owner T-059/T-250 remain open under their existing gates.
