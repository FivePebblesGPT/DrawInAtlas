# T-265 — Clipped document tabs must close the visible document (2026-11-22)

## Reproduction and failure risk

- Baseline checkout: local `1d8e5377` (16 older user-delivered commits and T-264); PR #22 remote head `7b1fd306` as checked when this ticket started.
- Linux/Xvfb, Mesa llvmpipe, Godot `4.8.beta3.official.c51ff06e8` and required Rust `DrawingNativeBrush` extension. Drawing uses a 930×760 window containing **13 long-title unsaved tabs**; Atlas runs the same `DrawingWorkspace` under a 1024×800 embedded parent.
- `TabBar.clip_tabs` scrolls to the last active document. In this Godot build `get_tab_rect(0)` through `get_tab_rect(10)` all return a zero-origin rectangle even though those tabs are hidden. The visible tab 11 overlaps that fallback close-glyph rectangle.
- Previous `_tab_close_hit` iterated all tab rectangles and returned **index 0** on a real click at visible tab 11. The baseline standalone test failed **6 of 20** initial assertions (including the actual click targeting the wrong document), and the Atlas test failed **2 of 5**. The first negative-control standalone run also exposed stale SVG imports in the staged Drawing copy; only clean post-import runs are counted as passing regression evidence.
- This is not just a mistaken prompt: if hidden tab 0 is already clean, closing visible dirty tab 11 could silently remove **the wrong document**. The final test makes tab 0 clean with a local fixture savepoint and checks it is not removed.

## Implementation

`DrawingWorkspace._tab_close_hit` now converts the pointer into TabBar-local coordinates, rejects coordinates outside the visible strip, and asks **`get_tab_idx_at_point`** for the index actually rendered under the pointer **before** checking the 28px close-glyph rectangle. `get_tab_rect` is only queried for that one visible index. The conventional File > Close Tab action and dirty-document safeguard are unchanged. No native history, pixel, color, layer, persistence or Atlas application code changed.

## Verified locally

| Test | Result |
| --- | --- |
| Standalone `drawing/tests/t265_document_tab_close_native.gd` | **21/21**, exit 0 |
| Atlas `tests/t265_atlas_document_tab_close_native.gd` | **5/5**, exit 0 |
| `make test-document-tabs TOOLCHAIN=system` with offline Cargo vendor | **exit 0**; native Rust built, both Godot projects imported and registered native extension, both graphical tests passed |
| T-090 native responsive workspace | **83/83**, exit 0 |
| T-120 native File/Object menus | **20/20**, exit 0 |
| T-120 headless unified Open | **34/34**, exit 0 |
| T-125 pending Save/Close safeguards | **29/29**, exit 0 |
| T-126 tab-switch pending-gesture safeguards | **34/34**, exit 0 |
| T-090 More-menu overflow | **32/32**, exit 0 |
| T-090/T-120 focused Python contracts | **15/15**, exit 0 |
| `python3 tests/check_explicit_types.py` | **592 project scripts / 33 skill documents**, pass |
| `python3 tools/validate_ticket_store.py` | **265 tickets and manual-review dependency gates**, pass |

The standalone native test uses actual `root.push_input` pointer press/release against an inactive visible tab, preserves all thirteen tabs and their original active tab until the correct dirty-close prompt is canceled, and proves that subsequently closing *visible* clean tab 0 works normally. It covers tab-body false-positive rejection, outside-the-strip rejection, returning to first tab and 100/150/200% simulated content scale. Atlas verifies exact inactive close-target prompt and revision/history invariants.

Reproducible local build and invocation:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_NET_OFFLINE=true CARGO_VENDOR_DIR=/path/to/toolchain/vendor
make test-document-tabs TOOLCHAIN=system GODOT=/path/to/godot CARGO=/path/to/cargo UV=/path/to/uv
```

The [on-demand workflow](../../.github/workflows/godot-native-t265-document-tabs.yml) pins Godot 4.8 beta 3 and Rust 1.99.1, builds and imports both projects before invoking Xvfb, rejects incomplete logs with `check_godot_model_log.py`, and retains logs on failure. **Hosted GitHub Actions has not been run.**

## Review boundaries

These are reproducible software-X11 pointer/selection tests, not physical Windows/Linux/HiDPI UX acceptance. T-090 and T-120 remain engineering Done for their prior scopes. T-059 and **T-250 remain unapproved**, and T-083/T-091 retain their separate owner/physical checks. No blocked Atlas features were closed.
