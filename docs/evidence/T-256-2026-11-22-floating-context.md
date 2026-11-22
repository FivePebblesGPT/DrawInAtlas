# T-256 — Floating icon context-menu parity

**Date:** 2026-11-22 · **PR:** #22 · **Environment:** Godot 4.8 beta 3,
Linux x86_64, Xvfb/X11, Mesa llvmpipe OpenGL compatibility, Dummy audio,
canonical required Rust GDExtension from the provided offline toolchain.
**Not done:** Windows/real display, owner hands-on verification, hosted CI run.

## Reproduction and fix

In the original T-255 floating host, clicking an inactive icon selected it,
but neither RMB nor Shift+F10/Menu opened the icon's 3-dots-equivalent menu.
The existing private `_arrange` helper had no UI event connection. Grip RMB
had no whole-group menu. A clean negative control running the new standalone
native script **before any implementation change** exited 1 with missing
`FloatingPanelContextMenu` and `FloatingGroupContextMenu` (2 failed of 7
reached checks).

The host now instantiates stable `PopupMenu` children outside its rebuilt tab
strip. Input dispatch scopes RMB to the **visible scroll viewport**, never
Godot's un-clipped tab rectangles. Keyboard context targets the currently
focused tab or grip, while menu actions freeze the targeted panel ID rather
than implicitly using the selected panel. Every action checks ownership at
execution time and uses existing transactional dock operations. Icons and
floating header geometry are unchanged; no new text tabs or persistent UI
buttons were introduced.

## Verified regression matrix

| Test | Outcome |
| --- | --- |
| `drawing/tests/t256_floating_tab_menu_native.gd` | **28 checks, 0 failures**: inactive RMB target, disabled boundary options, model no-op, reorder, Shift+F10, grip Menu key, clipped tab vs grip, 150/200% scale, whole-group dock, split to one new floating host and document nonmutation |
| `tests/t256_atlas_floating_tab_menu_native.gd` | **9 checks, 0 failures**: canonical Atlas-owned workspace, inactive icon RMB, single panel redock, rejected stale callback, unchanged source/revision/history |
| Existing floating single-group/edge grip | T-091 **44/44** and grip **53/53** |
| Existing floating model/native T-081 and T-082 | T-081 **58/58**, T-082 **57/57** |
| T-083 persistence | **63/63** |
| T-225 floating icons | **81/81** |
| T-254 flyout icon context | **178/178** |
| T-255 clipped floating tabs | **20/20** |
| Atlas T-225, T-254, T-255 | **10/10, 12/12, 14/14** |

All checked scripts exited zero. The new regression was run after Godot
reimported the standalone source and Atlas project. Diagnostic warning output
for X11 unsupported VSync and running as root was retained, not categorized as
a failed test. The new on-demand workflow builds the mandatory native library
and imports both consumers before running the two native witnesses; it has
**not** yet run on hosted GitHub Actions. Optional `T256_SCREENSHOTS` captures
are extra artifacts, not required to pass in headless CI.

## Reproduction

```bash
make test-floating-context TOOLCHAIN=system
# Or after an existing native build and both project imports:
T256_SCREENSHOTS=/tmp/t256-shots xvfb-run -a godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t256_floating_tab_menu_native.gd
xvfb-run -a godot --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/t256_atlas_floating_tab_menu_native.gd
```

These checks do **not** approve T-091's physical Windows/Linux pointer
acceptance, T-083 or T-250's owner UX signoff, or any Atlas feature-delivery
dependency blocked by T-250.
