# T-210 — Native T-088 selection, clipboard and Move graphical witness

**Date:** 2026-11-19. **PR #21:** local branch `sprint/2026-11-17` from
remote `9aa1cbe0028d7f6cc64044051ef1c2f4a2ebc5d9`.
**Runtime:** bundled Godot **4.8.beta3.official.c51ff06e8**, Linux X11/Xvfb,
Mesa llvmpipe, 1010×740 Canvas; source zoom 50/100/200/400%.
Extension: bundled offline Rust Hokusai/GDExtension. These measurements are
**software-only**; no physical device, Windows or hosted PR CI was tested.

## Failure and native-source explanation

The original historical `drawing/tests/selection_clipboard_native.gd` ran with
**exit 1** and `T088_NATIVE: 51 checks; 24 failed`. The strict CI verifier also
returned 1. The original fixture used `canvas.brush_width = 1.0` with a short
native Brush stroke; Hokusai published no changed pigment, so subsequent
Undo, Eraser, detached Move, clipboard, keyboard, zoom and Save/Open assertions
operated on an absent source. `baseline-original.log` retains the whole
process output; `baseline.strict.txt` retains the rejection.

A diagnostic change to **24px** Brush generated real pixels, bringing the
witness to only **2/51 failed** (`diagnostic-width24.log`). Inspection with
source-pixel diagnostics (not retained in the final test) established:

- Native Eraser output at (-17, 0) was `0x01fede66` from `0xfffede66`:
  almost transparent alpha **1/255**, with hidden RGB retained. The
  subtraction-hole pixel at (-15, 0) stayed **byte-exact** `0xff188fe0`.
  Equating a successfully erased visual pixel to canonical integer zero was
  an obsolete single-stroke oracle.
- The widened native Brush actually painted the **selected** left edge at
  (-19, 0); a subsequent +9 Move correctly translated it to (-10, 0).
  The prior assertion expected (-10, 0) to remain empty. The repaired test
  instead requires exact `source(-19,0) == destination(-10,0)` and verifies
  the **subtracted** source (-15,0) never publishes at (-6,0).

The final test also requires an unselected pixel at (-10, 0) to remain zero
during Brush and Eraser, preserves the unmodified hole byte, tests preview
without committing, history revision/Undo/Redo, multi-step persistent
floating Move/cancel, keyboard Cut/Copy/Paste/Delete and `.drawing` reopen.
It now reports **52 assertions**, adding an explicit selected-edge check;
there are no skipped assertions. The CI `T088_NATIVE_PASSED` marker and
strict verifier remain unchanged. This is a **test-only** change.

Two new focused Python fixture contracts in the existing
`tests/test_t088_floating_log.py` fail on the original fixture (**2 failures
out of 8 tests**, `python-contract-fail-first.log`) and pass against the new
source (**8/8**, `python-contract-final.log`). They reject the old 1px setup,
full-clear expectation and lost selected-edge Move check.

## Reproduction commands

Run from the repository root with the supplied offline toolchain and the
canonical native extension already built/imported:

```sh
export GODOT_SILENCE_ROOT_WARNING=1
G=/mnt/data/toolchain/bin/godot
xvfb-run -a -s '-screen 0 1280x900x24' "$G" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/selection_clipboard_native.gd
python3 tools/check_native_t088_log.py native-x11-1.log
python3 -m unittest discover -s tests -p 'test_t088_floating_log.py' -v
make python-test
python3 tests/check_explicit_types.py
PATH=/mnt/data/toolchain/rust/bin:$PATH \
CARGO=/mnt/data/toolchain/rust/bin/cargo \
CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor \
CARGO_NET_OFFLINE=true CARGO_TARGET_DIR=/mnt/data/work/target \
  bash tools/build_native_brush.sh --test
python3 tools/validate_ticket_store.py
```

The runtime logs, exact process exits, strict verifications, first-fail log,
Python diagnostics and SHA-256 hashes are retained under
[`T-210-2026-11-19-native-selection-raw/`](T-210-2026-11-19-native-selection-raw/).
In particular, `exits.tsv`, `source-and-log-hashes.txt` and the four
`native-x11-*.log` files capture independent zero-exit final runs.

| Validation | Result |
| --- | --- |
| Original native-X11 T-088 | Exit **1**, **24/51 failed**; strict reject |
| Widened-footprint diagnostic | Exit **1**, **2/51 failed** |
| Final native-X11 T-088 ×4 | **Exit 0 ×4**, **52/52 ×4**, strict verifier exit 0 ×4 |
| Original-source Python contract | Exit **1**, **2/8 tests failed** |
| Final-source T-088 Python contract | Exit **0**, **8/8 passed** |
| T-088 headless selection model | Exit **0**, **131/131**; strict marker accepted |
| T-129 pending content edits | Exit **0**, **35/35**; strict marker accepted |
| T-124 queued Hokusai | Exit **0**, **78/78** |
| T-139 native selection contour | Exit **0**, **7/7** |
| T-140 native focal-mask outline | Exit **0**, **9/9** |
| Offline Rust tests | Exit **0**, **35 passed** |
| `make python-test` | Exit **0**, **56 tests** across seven suites |
| GDScript explicit types | Exit **0**, 521 scripts, 33 skill docs |
| Pinned Ruff (changed test and Make targets) | Exit **0** |
| Pinned ty (Make-defined targets) | Exit **0** |
| Ticket/manual-review validator | Exit **0**, **210 tickets** |

**Recorded limitation:** Direct `ty check tests/test_t088_floating_log.py`
returns one existing unresolved dynamic import of `check_native_t088_log`
via runtime `sys.path.insert`. This import line predates T-210. The same
diagnostic remains when passing that module explicitly; the repository's
**defined** ty target passes. `ty-focused.log`, `ty-with-import.log`, and
`ty-defined.log` retain the outputs. This diagnostic is not called green.

## Remaining integration gates

T-088 stays **In Progress**, dependent on T-149 and its eventual native
mask boundary validation and owner-visible UX. T-095/T-197 require separate
performance/hardware evidence; T-106/T-180 hosted CI, Windows and release
exports remain open. This repair supplies **no** new owner/manual acceptance,
FPS benchmark or proof of source authority completion.
