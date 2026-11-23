# T-263 — explicit Bash for fail-closed live-stroke Make recipes

## Defect and negative control (remote-to-local parent `b485b668`)

GNU Make's default `SHELL` on Unix is `/bin/sh`, but the T-262
`test-live-stroke` Make recipes use Bash's `set -euo pipefail`. Older POSIX
shells may reject `pipefail`, so a clean native build can fail before Godot
starts. The current container's Dash supports `pipefail`; the negative control
**simulates an older shell** and does not claim an observed failure on the
user's own machine.

Run from the checkout root:

```console
python3 -m unittest -v tests/test_t263_make_live_stroke_shell.py
```

Before the one-line shell selection change, **4 tests passed, 1 failed**:
`test_bash_specific_recipe_overrides_older_posix_shell` reported `make: ***
[Makefile:81: test-live-stroke] Error 97` and `pipefail is not available in
this shell`. The test injects a restricted Make shell **before** including the
real `Makefile`. The original `test-live-stroke` recipes run unchanged;
additional Makefile overrides suppress only the expensive native build and
Godot import prerequisites. Stubbed Godot and checker executables record exact
process order, and a stub Xvfb wrapper passes through the command. This is a
process-control test, not a substitute for the native paint witness.

## Fix and process failure controls

`Makefile` explicitly selects `/bin/bash`. After the fix, the five T-263
regressions pass, including:

- model then model checker, X11 then X11 checker, with actual recipe execution;
- failed model Godot exit **41** and failed X11 Godot exit **42** both reject
  the target even when the fake log checker returns success; `tee` cannot
  hide either process error;
- failed X11 checker exit **44** rejects the target;
- the emulated older POSIX shell cannot intercept the Bash-only recipes.

The existing T-262 contract suite still passes **5/5** tests, including strict
X11 log assertions and malformed trace negative cases.

## Real native acceptance — 2026-11-22

```sh
export PATH=/mnt/data/toolchain/rust/bin:"$PATH"
export CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor CARGO_NET_OFFLINE=true
export CARGO=/mnt/data/toolchain/rust/bin/cargo
make test-live-stroke TOOLCHAIN=system \
  GODOT=/mnt/data/toolchain/bin/godot \
  CARGO=/mnt/data/toolchain/rust/bin/cargo \
  UV=/mnt/data/toolchain/bin/uv
```

**Exit 0**. The command rebuilt/checksummed the required Rust native extension,
regenerated and imported standalone Drawing and Atlas, checked
`NATIVE_EXTENSION_READY` in each consumer, and ran both held-preview scripts.

| Observed witness | Result |
| --- | --- |
| Headless native Hokusai model | `T085_MODEL_PASSED`, **81/81** |
| Actual Linux software-X11 framebuffer and held pointer | `T085_NATIVE_PASSED`, **144/144** |
| Zooms | 100%, 50%, 25%; each 31 short samples |
| Long native replays | 9×840 samples, three trials at each zoom |
| Native X11 software preview-frame p95 | **8.819 ms** (Godot frame callback, not physical display) |
| Native long-stroke release→commit p95 (three zooms) | **13.395 / 11.809 / 13.001 ms** |

**Environment:** Godot `4.8.beta3.official.c51ff06e8`, Rust 1.99.1,
Linux x86_64, Xvfb 1600×1200×24, Mesa llvmpipe 25.0.7, offline Cargo vendor.
The log contains acknowledged Godot root/V-Sync warnings; no script-load or
native-extension errors. No GitHub Actions hosted run or user physical-device
measurements were performed. This ticket does not close T-085, T-094,
T-180, T-250, T-059 or any owner review.
