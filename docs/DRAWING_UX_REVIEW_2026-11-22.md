# Drawing owner UX rejection — 2026-11-22 (PR #22)

**Decision:** Owner **did not approve** the current standalone Drawing UX. Fix the visible editor **before** optional native history hardening or unrelated CI cleanup. [Manual review gate](Tickets/T-250.md) blocks unfinished/future Atlas feature tickets.

## Source images (owner-provided in conversation)

Original attachments are now checked into this repository byte-for-byte under [`assets/drawing-ux-2026-11-22/`](assets/drawing-ux-2026-11-22/). Do not silently substitute a recreated concept image for these originals.

- **Actual running editor:** committed as `DrawingCurrent.png` (1280×795; the owner's conversation attachment `image(1).png`). Demonstrates the dock toggle colliding with panel buttons and recents collecting a full red drag gradient.

![Owner's actual Drawing build screenshot](assets/drawing-ux-2026-11-22/DrawingCurrent.png)

- **Approved visual *reference*, not approval of implementation:** committed as `DrawInAtlasColorPanelConcept.png` (1280×795). Compare the top FG/BG and recent-color strip, picker spacing and icon-only tab layout against this image.

![Owner's original Color panel concept](assets/drawing-ux-2026-11-22/DrawInAtlasColorPanelConcept.png)

## Rejected behavior and corrective ownership

| Finding | Owner requirement | Ticket |
| --- | --- | --- |
| Dock minimize toggle collides with icons and sits on canvas seam | Toggle **inside dock**. Minimized: flow/VBoxContainer slot that moves icons down. Expanded: **same place** as dock overlay, no overlap | [T-251](Tickets/T-251.md) |
| Restore previous button redundant | Remove or retire in favor of deliberate, accurate recent colors | [T-252](Tickets/T-252.md) |
| Recent colors show every intermediate drag sample | Live FG/BG preview while dragging; add only **settled committed** color(s) to recents, not a gradient | [T-252](Tickets/T-252.md) |
| Delete selection visibly stalls ~1 s | Reproduce actual input-to-first-updated-frame stall, not just T-221 isolated sparse-clear duration; profile and fix | [T-253](Tickets/T-253.md) |
| Flyout uses text buttons | Use identical panel icons in expanded, minimized flyout and floating hosts; text belongs in tooltip/accessibility | [T-254](Tickets/T-254.md) |
| Implemented color UI differs from concept | Layout proportions, role focus, recent bars and inline picker should match reference at small/docked/floating sizes | [T-252](Tickets/T-252.md), [T-250](Tickets/T-250.md) |

## Priority and acceptance

**P0 execution order:** T-251 → T-252 → T-253 → T-254 (one independently testable ticket per engineering turn), followed by **T-250 Manual Review**. This order is a priority, not artificial dependencies among parallel fixes. Regression suites must validate Drawing and its Atlas consumer, but CI/test work unrelated to a measured UX regression should not displace this queue. Existing native safety/fail-closed rules remain mandatory.

**Atlas gate:** All *unfinished* Atlas feature/user-facing integration tickets must depend directly on T-250, including E-005/E-007/E-008/E-009 Atlas product-facing descendants. Do not change historical Done ticket states or put the gate on Drawing-only fixes; do not claim owner approval merely from images, CI or software-X11 tests. New Atlas tickets must name T-250 as a direct dependency. Owners may approve T-250 only after T-251–T-254 are Done and a concrete hands-on review of the updated build.

The original T-221/T-222/T-225/T-226 engineering evidence remains historical proof for narrower scopes; no new owner-reported failure is overridden by old synthetic benchmark results.

## T-251 engineering result — 2026-11-22

The toggle now has a 48×56 reserved minimized rail slot and a 34px
expanded-only horizontal gutter (with a fixed 226px expanded minimum) for the same 30×56 dock-local overlay. Actual
X11 pointer, focus, narrow-window, simulated HiDPI and Atlas-host regression
checks pass. See [T-251 evidence](evidence/T-251-2026-11-22-dock-toggle.md).
Do not treat this as color-panel, Selection Delete or overall dock acceptance.
The owner's original current/concept PNGs were committed at `7b1fd306`
under `docs/assets/drawing-ux-2026-11-22/` before this fix.

## T-252 engineering result — 2026-11-22

The ColorPicker may now change FG/BG continuously during a drag while the
recent-color list records one **previous settled** pigment on release, not each
frame of the gradient. Keyboard changes, native text/spin controls, cancellation,
and role switching have explicit completion boundaries. The earlier redundant
restore-previous row and Recent label are removed, and the native picker follows
the one-row FG/Swap/BG plus vertical recent bars directly. Exact hex/default
controls remain available by scrolling. Pigment preferences survive restart
independently of `.drawing` content/history. [Evidence](evidence/T-252-2026-11-22-recent-colors.md)
includes model/native X11 pointer and Atlas integration tests. Owner hardware UX
confirmation is still outstanding. The manual Drawing gate T-250 stays Blocked
until T-253, T-254 and actual owner review are complete.

## T-253 dense-selection correction — 2026-11-22

[T-253](Tickets/T-253.md) has new fail-first **real X11 input→frame**
evidence: p95 1,127ms before, 179ms after for 71,901 pixels at 119% zoom,
plus exact RGBA8/Undo/Redo/Atlas Save/Open checks. The sparse 8-pixel
T-221 result did not predict the dense frame stall. **Engineering Done does
not equal owner acceptance:** physical retest remains on T-250/T-088;
T-254 icon-only flyouts remain the next P0 task.
