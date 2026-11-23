# T-255 — Narrow floating-tab clipped hit-test evidence

**Date:** 2026-11-22. **PR:** #22 (`sprint/2026-11-20-selection-dock-colors-brushes`).
**Base:** remote `7b1fd306`, on top of the seven unpushed T-251–T-092
commits. Godot 4.8 beta 3, x86_64 Linux X11/Xvfb, Mesa llvmpipe,
software GL compatibility, Dummy audio and required Rust-native GDExtension.
**Not tested:** physical devices, Windows, monitor switching, hosted CI run.

## Failure and correction

A 236×380 floating host contains five 42px icon tabs and a scrollable
160px strip. With the horizontal scroll at 66px, a fully **clipped** Colors
button reports global x=192–234px and overlaps the move grip x=220–254px;
the actual visible strip starts at x=258px. Prior `_input()` incorrectly
selected Colors when a pointer clicked the grip at x=230px. At scroll 0,
the invisible fifth tab extends across the close button's visible interior.

Reproduction first ran against the unchanged source with the new test:
**exit 1, 4/19 failed**: the grip click activated the invisible tab,
subsequent ownership assertions failed, and close was intercepted.
The implementation restricts viewport-level tab dispatch to the **visible
strip bounds** while preserving Godot 4.8 beta's workaround for actually
visible tab clicks. Normal grip/close and the independent resize edge
continue through their usual handlers. No model, document, or ABI changes.

## Validation

| Test | Result |
| --- | --- |
| `drawing/tests/t255_floating_tab_hit_native.gd` | **22 checks, 0 failed** (two PNG framebuffer captures) — overflow and geometric proof, hidden grip click, real grip drag, partial visible-tab click, close/hide/reopen, exact unchanged document revision/dirty status |
| `tests/t255_atlas_floating_tab_hit_native.gd` | **14 checks, 0 failed** — embedded host, five tabs, hidden grip click, clipped close, panel instance identity and Atlas lifecycle/history integrity |
| T-091 `dock_single_group_native.gd` | **44/44** |
| T-091 `dock_grip_redock_native.gd` | **53/53** |
| T-081 `dock_float_native.gd` | **58/58** |
| T-225 `t225_floating_icons_native.gd` | Exit 0, **81 checks** without screenshot mode |
| T-254 `t254_flyout_icons_native.gd` | Exit 0, `T254_FLYOUT_NATIVE_PASSED` |
| T-225 `t225_atlas_floating_icons_native.gd` | **10/10** |

Both T-255 output logs were checked with
`tools/check_godot_model_log.py --marker T255_NATIVE_PASSED` or
`--marker T255_ATLAS_PASSED`, rejecting missing/failure/error markers.
The on-demand workflow builds native first, imports **both** consumers and
collects original X11 logs and optional screenshots; it was not run on GitHub.

To repeat locally with a configured toolchain, run `make test-floating-tabs`
(which builds/imports both consumers), or after staging/importing manually:

```bash
T255_SCREENSHOTS=/tmp/t255-screens xvfb-run -a godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t255_floating_tab_hit_native.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path . \
  --script res://tests/t255_atlas_floating_tab_hit_native.gd
```

The two PNGs are user-facing test artifacts, not part of the Git mailbox.
**No owner approval** was requested or recorded. T-091's physical Windows/
Linux and DPI pointer acceptance, T-083, T-059, and T-250 remain open.
