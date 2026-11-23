# T-270 — Floating-dock required-native on-demand CI checkpoint

## Starting state and fail-first evidence

From local PR #22 checkout at `fc6744f4` (22 commits beyond the last
observed remote `7b1fd306`), the T-091 on-demand workflow imported Drawing
without first building/registering the Hokusai Rust `.so`. The extension
is not tracked in Git. It also ran only standalone Drawing tests and had
no Atlas-hosted pointer/history witness.

The new `tests/test_t270_floating_dock_ci.py` failed the original workflow
and missing Make target (9 subtest failures plus one absent-build substring
error); the retained log-verifier negative-control test already passed.
The corrected three T-270 Python tests, together with four historical T-091
contracts, pass **7/7**. Fail-closed cases cover truncated summaries,
repeated success markers and engine script errors.

## Change

- On-demand T-091 CI now pins Rust **1.99.1** and Godot **4.8 beta 3**;
  `make build TOOLCHAIN=system` compiles/registers the extension and imports
  both Drawing and Atlas before any X11 test.
- Existing real-X11 T-091 tests retain their explicit log checkers and
  optional screenshot collection. An additional Atlas T-257 X11 witness
  checks cancellation of real move/resize pointer interactions and rejection
  of stale mouse releases. The Atlas exact summary and shared error verifier
  are both mandatory. All three logs and framebuffer captures are uploaded
  using `if: always()`.
- `make test-floating-dock` reproduces the complete build/import/three-X11
  sequence; each piped Godot process uses Bash `set -euo pipefail` so `tee`
  cannot conceal a failed subprocess.
- The older T-091 workflow contract now checks the actual required-native
  Make build rather than looking for a literal inline `--import --quit`
  command that was moved into the Make target.

No production Drawing, Atlas, Godot UI, native Rust or history logic changed.

## Actual local test results

Environment: supplied offline Cargo 1.99.1 and vendored crates, Godot
`4.8.beta3.official.c51ff06e8`, Linux x86-64 X11/Xvfb at 2200×1500×24,
Mesa llvmpipe/OpenGL compatibility; no network or hardware display.

| Witness | Result |
| --- | --- |
| Pre-fix workflow/Make CI negative control | 9 failed subassertions + absent-build error, as expected |
| T-270 plus T-091 Python CI/log contracts after fix | 7/7 passed |
| Full `make test-floating-dock` build and both imports | Exit 0, both `NATIVE_EXTENSION_READY` |
| T-091 one-group/resize native X11 | 44 checks, 0 failed |
| T-091 grip, same-frame tab and redock native X11 | 53 checks, 0 failed |
| Atlas T-257 move/resize Escape cancellation X11 | 8 checks, 0 failed |
| Neighbor T-091 dock model (headless) | 54 checks, 0 failed |
| Neighbor T-255 clipped floating-tabs X11 | 20 checks, 0 failed |
| Neighbor T-258 focus-loss rollback X11 | 30 checks, 0 failed |

The Make run completed with two native-ready messages and no test error
markers. The three neighboring regression suites also exited successfully.

To reproduce with the supplied offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_VENDOR_DIR=/path/to/toolchain/vendor CARGO_NET_OFFLINE=true
make test-floating-dock TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot \
  CARGO=/path/to/toolchain/rust/bin/cargo
python3 -m unittest tests.test_t270_floating_dock_ci tests.test_t091_dock
python3 tools/validate_ticket_store.py
```

## Limitations and separate gates

The hosted GitHub on-demand workflow was **not** executed in this turn.
Physical Linux/Windows border hit targets, real Alt+Tab, GPU-specific focus
and owner visual acceptance remain unverified under **T-091/T-083/T-250**.
The independent T-094/T-180 hosted CI/release acceptance is unchanged.
