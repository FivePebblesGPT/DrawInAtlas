# PhotoCraft 0.20.2: selected-pixel Move and selection combination reference

**Investigation:** 2026-11-06, using the owner-supplied Linux .deb and Godot/computer-use bundle.  
**Target:** [DrawInAtlas PR #13](https://github.com/FivePebblesGPT/DrawInAtlas/pull/13), selection and Move work in T-088; owner review is still required.  
**PhotoCraft executable:** 0.20.2 (reported CLI build commit 7c12f6471, built 2026-11-05), extracted from photocraft-0.20.2-linux-x86_64.deb, SHA-256: 0418bc32168f11bdcddc17a2dcd53f10eb9c55cd164e9b19cee93cc50e8c8367.

## Evidence boundaries

- **Executable-verified:** Real PhotoCraft 0.20.2 CLI/engine commands and exact resulting composite pixels, not a simulation of selection geometry. Selection harness: **29/29** assertions passed. Four additional selection-during-Move probes passed.
- **GUI launched, but interactions not verified:** The supplied computer-use-linux/X11/XTEST tooling identified the PhotoCraft window and dispatched keys under Xvfb/Mesa llvmpipe. A "Switched to CPU rendering" modal prevented reliable pointer/modifier/Enter/Escape/outside-click testing. The binary opened a small native .pcraft selection fixture, but that alone is not an interaction test.
- **Secondary source corroboration:** [PhotoCraft move_ui.rs](https://github.com/storytold/photocraft/blob/ce97bde34b85696790bba90b224282887b0b8b55/crates/ui-egui/src/canvas/move_ui.rs) describes *selected pixels* as floating until Return, Deselect, or another command drops them, whereas a **whole-layer Move** commits on drag release. This source snapshot may differ from the installed binary; verify the GUI mapping before treating shortcut behavior as accepted.
- Do not claim Paint.NET parity or physical Windows/Linux acceptance from these tests.

## 1. Selected-pixel Move: executable findings

Fixture: transparent 64×64 RGB/8 document, editable raster layer, selected rectangle (8,8,16,16) filled with opaque red using edit.fill. The installed PhotoCraft CLI was driven with its actual select.float, select.drop, select.deselect, document.pixel and edit.undo commands.

| Sequence | Observed result |
| --- | --- |
| Float by (20,0) | Floating object reported offset [20,0] |
| Explicit drop | select.drop reported dropped=true, offset [20,0] |
| Inspect after drop | Original pixel (12,12) transparent; target (32,12) red |
| Float (20,0), then float (5,3) before drop | Cumulative floating offset [25,3]; after drop (37,15) red |
| Float, then deselect, then attempt drop | select.drop reported dropped=false; target remained red |
| Float, then document.pixel, then attempt drop | select.drop reported dropped=false: this engine command already resolved the float |
| Float, drop, Undo | Undo returned true; original red again and destination transparent |
| Float, Undo *without* explicit drop | Undo reported floating="returned"; subsequent drop reported dropped=false; source restored |

**Interpretation:** Releasing a *selected-pixel* drag in DrawInAtlas must not immediately commit the edit. PhotoCraft has a durable transient floating-selection state that can receive repeated moves and resolves through a separate action. The headless engine proves command semantics, **not** which specific GUI clicks or keys invoke those commands.

In PR #13, addons/drawing/canvas.gd::finish_gesture() currently commits the detached move session on mouse-up. Separate **end of drag** from **confirmation of the floating edit**. Retain a detached session and cumulative offset across releases, allow repeated drags, and only publish one history event on confirmation. Cancel must restore source and avoid history pollution. Do not change whole-layer behavior by assumption: its PhotoCraft lifecycle is different.

## 2. Replace/Add/Subtract/Intersect: pixel-verified

The selection harness created a new transparent **24×24** image (576 pixels), used the real selection commands, applied edit.fill to selected pixels, exported an image, and asserted exact pixels. For binary checks, antiAlias=false and feather=0.

Rectangle A = [4,12) × [4,12), B = [8,16) × [8,16). Each is 64 pixels; overlap is 16.

| Operation | Expected red pixels | Actual | Pass |
| --- | ---: | ---: | --- |
| Replace A with B | 64 | 64 | Yes |
| A Add B (union) | 112 | 112 | Yes |
| A Subtract B | 48 | 48 | Yes |
| A Intersect B | 16 | 16 | Yes |
| Reverse subtraction B minus A | 48 | 48 | Yes |
| Add duplicate A | 64 | 64 | Yes |
| Subtract disjoint shape | 64 | 64 | Yes |
| Intersect disjoint, then Fill | 576 | 576 | Yes |
| Subtract A from A, then Fill | 576 | 576 | Yes |
| Subtract with no initial selection, then Fill | 576 | 576 | Yes |
| Intersect with no initial selection, then Fill | 576 | 576 | Yes |
| Add with no initial selection | 64 | 64 | Yes |
| Sequential Add/Subtract/Intersect | 45 | 45 | Yes |
| Invert A | 512 | 512 | Yes |
| Select All, then subtract B | 512 | 512 | Yes |
| Deselect, then Fill | 576 | 576 | Yes |
| Reselect A, then Fill | 64 | 64 | Yes |
| No selection, then Fill | 576 | 576 | Yes |

**Other selection producers:** Ellipse (measured binary area 52) passed Replace=52, Add=103, Subtract=51, Intersect=13; polygonal Lasso (measured binary area 32) passed Replace=32, Add=84, Subtract=52, Intersect=12. These verify *set operations against each shape's measured mask*, not a hardcoded ellipse or triangle.

**Soft-edge evidence:** Antialiased ellipse emitted alpha values {0,16,112,207,255}; non-antialiased ellipse only {0,255}. A rectangle with feather radius 2 produced 49 distinct alpha values. The current boolean selection core does not automatically reproduce feather/partial-coverage semantics; treat this as a future fidelity requirement, not silently as completed T-088 functionality.

## 3. Empty-selection behavior and Atlas compatibility

For disjoint intersection or complete subtraction, the next Fill affected all **576** pixels, as did Fill without an active selection. At the *engine-command-and-Fill* level this means an empty result behaves like **no active selection**, not a persistent enabled-empty (deny-all) mask. No claim is made about the GUI's visual outline or modifier behavior.

**Important DrawInAtlas distinction:** DrawingSelection intentionally supports enabled=true plus zero allowed pixels as **deny-all** for Atlas board-cell masks. Do **not** delete or conflate that core state. Define an explicit standalone UX transition from an empty result to **deselected** where PhotoCraft-compatible behavior is desired, while preserving the Atlas API's deny-all semantics.

## 4. New selection commands during a floating Move

Four additional executable probes used an 8×8 red source, invoked select.float with offset (12,0), then select.rect with each of Replace/Add/Subtract/Intersect, then select.drop. In all four cases the final drop reported dropped=false; source (6,6) was transparent and destination (18,6) red. This is consistent with a new selection command resolving an existing floating piece first.

**Limitation:** This is the installed command dispatcher's behavior. Do not infer exact outside-click, Shift/Alt, tool-switch, or Escape routing without a working reference GUI.

## 5. Required follow-up acceptance for PR #13

1. **Selected-pixel Move state:** After mouse-up, pixels remain in a live floating preview, with canonical document/history still unchanged. A second drag accumulates offset. Enter and the appropriate deselection action confirm once; Escape cancels without a content entry. Verify these UI mappings on PhotoCraft's working GUI first.
2. **Selection set operations:** Confirm rectangle Replace/Add/Subtract/Intersect, disjoint/identical overlap, repeated operations, and no-initial-selection behavior. Empty result must be intentionally handled at the standalone UI boundary without changing Atlas deny-all.
3. **Cross-operation behavior:** Starting a new selection while pixels float should resolve the float according to the chosen, verified UX contract. Check Undo/Redo and active layer state after the operation.
4. **Fidelity/extensions:** Ellipse, lasso, antialiasing, and feathering should be scoped and tested explicitly; these are not proven implemented in the current DrawInAtlas PR.
5. **Native evidence:** Run real hardware mouse/keyboard and framebuffer tests (zoom/DPI variants), record visible pending state before confirmation, and retain the T-059/owner acceptance gate. These executable CLI checks alone are insufficient.

## Reproduction materials retained outside this commit

The investigation generated a 256×256 PhotoCraft .pcraft fixture and a 29-check Python/Pillow harness (test_selection_modes.py), results.json, per-case PNGs, and a comparison PNG; the local archive photocraft_selection_modes_tests.zip has SHA-256 5e0a266292336ea1c5b56f29e740aae6bf7bee6c98f13a17bcc993ea3c9e9f3e. The external .deb and generated binaries/images are **not** included in this documentation commit. Re-run the harness using Python 3/Pillow and the supplied extracted PhotoCraft CLI; it invokes the binary for every command and compares exported pixels, rather than reimplementing its selection logic.
