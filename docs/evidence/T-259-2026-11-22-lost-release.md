# T-259 — recover dropped mouse-up without focus loss (2026-11-22)

## Reproduction and fail-first control

- Baseline: local checkout `1a95441b` plus only new tests, Godot `4.8.beta3.official.c51ff06e8`, Linux X11/Xvfb and Mesa llvmpipe, 1200×760 window with 100%, 150%, 200% simulated content scales.
- Press floating grip/corner/tab, move while `button_mask` includes left, **omit the mouse-up without dispatching a focus-out notification**, and deliver a motion with `button_mask=0`.
- On previous production code, standalone **13 failures / 28 checks** (move/resize rollback, late release and tab-drag cancellation); Atlas **4 failures / 10 checks** for the same category. Standalone clean fail-first was repeated after staging/importing the actual native SVG resources, with zero resource-loader errors.

## Fix and evidence

`DrawingFloatingHost._input` treats a button-mask transition to unpressed as cancellation **only if this host owns a move/resize or pending tab/owned cross-drag**. A shared `_cancel_pointer_preview` restores the saved move/resize frame and aborts the drag transaction; this is also invoked by Escape and focus-loss. The suppressed release can no longer publish stale geometry or ownership. New presses reset suppression, and an idle sibling cannot cancel a different host's drag.

Post-fix on the same X11 runner:

- Standalone `drawing/tests/t259_floating_lost_release_native.gd`: **28/28 passed**; three scale factors, move/resize/tab recovery, restart of real gestures, sibling isolation, unchanged document revision/dirty bit and panel model.
- Atlas `tests/t259_atlas_floating_lost_release_native.gd`: **10/10 passed**, including one-group ownership and source/history invariants.
- Standalone neighbor suite, each exited 0 with passing marker: T-257, T-258, T-256, T-255, T-091 grip and one-group, T-081 floating, T-083 persistence. The combined batch was interrupted after T-254 printed its 178/178 passing marker, so it is not counted as a completed aggregate. T-254 was rerun independently and **178/178 passed**, exit 0. T-080 reordering and T-082 cross-dock native suites each exited 0 with their passing markers.
- Atlas neighbor tests rerun individually: T-257, T-258, T-256, T-255 each exited 0 with passing markers. `tests/test_t078_t083_docking_plan.py` **10/10**, `tests/test_t091_dock.py` **4/4**, and `tools/validate_ticket_store.py` validated **259 tickets** with review gates intact.

On-demand `.github/workflows/godot-native-t259-floating-release.yml` builds the pinned native extension, imports both Godot consumers, runs graphical checks with strict pass markers and uploads logs; the workflow itself has **not run on GitHub**.

## Limits / owner gates

Input uses real X11 pointer dispatch with a simulated lost release. This does not claim OS-driver-level reproduction or Windows/physical hardware acceptance. It is an engineering-only correction; T-091 physical review, T-083 dock UX approval and T-250 hands-on Drawing signoff remain open. No change to pixel, native history, Save/Open or campaign data.
