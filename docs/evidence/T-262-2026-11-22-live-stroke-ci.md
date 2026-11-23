# T-262 — T-085 required-native CI and full held-stroke log gate

## Fail-first (previous workflow at `c7910cd7`)

`python3 -m unittest discover -s tests -p 'test_t262_live_stroke_ci.py' -v`
reported **6 assertion failures and 1 import error / 4 test methods**.
The prior on-demand workflow had no pinned Rust installer or native build,
ran only `build_drawing_app.py --in-place` and Godot import, excluded the
headless witness, and checked only a loose `grep` success marker. This is an
**identified workflow contract failure**, not a claim that GitHub hosted the
old workflow or that the old framebuffer test itself was red.

## Correction

- `.github/workflows/godot-native-t085-stroke.yml` installs Rust 1.99.1,
  executes `make build TOOLCHAIN=system` before either consumer's test, runs
  headless and X11 T-085 witnesses and uploads both logs. All process pipes
  are `set -euo pipefail`.
- `tools/check_native_t085_log.py` reuses the shared Godot diagnostic verifier
  and adds T-085-specific event-count, zoom, replay and timing coverage.
  Generic success markers alone cannot satisfy this checker.
- `Makefile` adds `test-live-stroke: import-drawing import-atlas` with
  strict model and real-X11 log verification.
- `tests/test_t262_live_stroke_ci.py` contains workflow, native fixture,
  Make and twelve malformed/diagnostic negative oracle cases.

## Local verification — Godot 4.8 beta 3, Rust 1.99.1, Linux X11/Mesa

`make build TOOLCHAIN=system` passed using the supplied offline
`CARGO_VENDOR_DIR` (no crates.io access). Both consumers independently
reported `NATIVE_EXTENSION_READY`. The on-demand workflow was **not** run
on GitHub; these are corresponding local commands.

| Verification | Result |
| --- | --- |
| Corrected Python CI contracts | **5/5 passed** |
| New verifier against real T-085 X11 log | Passed |
| `make test-live-stroke` (build/import + headless + native X11) | Passed, exit 0 |
| T-085 headless native-Hokusai model | **81/81** passed |
| T-085 actual X11 held-button framebuffer | **144/144** passed |
| T-085 840-sample native control bursts | **9/9** completed, three each at 100/50/25% |
| T-124 queued native Brush history | **78/78** passed |
| T-227 native settings / real X11 Brushes | **47/47**, **42/42** passed |
| T-227 Atlas Brushes UI/source | **13/13** passed |
| T-181 exact native held preview | **19/19** passed |

The X11 test routes real Godot pointer input through the Control, captures
software framebuffer while the left mouse button is held, and validates the
queued stroke against an independently committed timestamp-identical native
Hokusai reference. `make test-live-stroke` repeats both consumers' native
imports before the tests; the second run passed the same 81/144 assertions.

**Environment:** `4.8.beta3.official.c51ff06e8`, Linux x86-64,
Xvfb `1600×1200×24`, OpenGL Compatibility, Mesa llvmpipe 25.0.7,
Rust 1.99.1, offline vendored dependencies. Actual Windows/Linux physical
input delivery, hardware presentation p95 and hosted CI remain **not run**.
T-085, T-094, T-180, T-250 and T-059 statuses/gates are unchanged.
