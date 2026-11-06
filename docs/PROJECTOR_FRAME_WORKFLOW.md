# T-013 — GM-side projector framing (session-only candidate)

**Status: interactive framing candidate, not an approved projector or a player-safe output.** The privacy rules of [[T-039]] are not agreed and T-040's second window, camera follow/freeze and calibration are not yet implemented.

## How to try it

From an open board, press **Frame** in the top toolbar. The cyan rectangle is GM-only chrome with a yellow **lower-right** resize handle; the picker next to the button chooses an *intended output aspect* (16:9, 4:3 or 1:1). Drag inside the rectangle to change its **board center**. Drag the handle to change its **board width** (larger = more board shown; smaller = less). The opposite upper-left corner stays fixed during resize. The frame retains the selected ratio. **Esc** cancels an active drag; when idle, Esc exits frame mode. Right-click cancels a drag. Selecting an artwork tool exits frame mode. Middle-drag and the mouse wheel still navigate the **GM camera**, separately from the frame.

The frame appears only on the GM editing canvas; entering the mode intercepts left clicks so the same gesture cannot paint, select or transform document artwork. A frame change does not move or resample layers, change the document's grid, update the GM camera, or push a command into native undo/redo. On map/floor navigation the frame is dismissed; on re-entry it starts centered on the current GM view. There is no saved frame or cross-map restore. Changing the aspect only adjusts height, not board width or pixel size.

## Geometry and non-publishing boundary

`AtlasProjectorFrame` tracks a board-space `center`, `width` and proposed output `Vector2i`. At aspect `a = output_width / output_height`, its rectangle is `Rect2(center - (width, width/a)/2, (width, width/a))`. A future authorized player camera could use `center` and `output_width/width` as center and zoom, but **none of that geometry is sent to any renderer or screen yet**. Output pixel dimensions here express *aspect*, not tabletop calibration. Calibrated physical grid cell length and native output window dimensions must remain independent (T-040).

This model has **no access to artwork or grants**. `AtlasPlayerProjection` is the detached, deny-by-default proof from T-039; a future player surface must obtain a sanitized output from that boundary, never render `AtlasCanvas`, use a GM preview cache, or simply hide private layers in a composite. Frame contents shown on the GM canvas are therefore *not* evidence of player privacy. Further design decisions are needed for follow/freeze revocation, persistence and history (none now), initial placement, output handling and owner usability approval.

## Tests

`tests/projector_frame_smoke.gd` checks numeric geometry, aspect changes, validation, bounded resizing, candidate-mode isolation from canonical campaign/history, cancellation, tool switching and map navigation. `tests/projector_frame_visual.gd` sends actual pointer events through a native 960×660 viewport, validates move/resize/consumption and border visibility, then records a compact 800×600 witness. This demonstrates frame **input**, not real multi-monitor output. Tests are listed in CI and must be considered alongside the T-039 privacy contract suites.
