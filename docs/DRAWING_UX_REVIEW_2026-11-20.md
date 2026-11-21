# Drawing owner follow-up — 2026-11-20

**Source:** owner-provided screenshot `DrawInAtlasColorPanel(3).png` and interaction notes in the 2026-11-20 conversation. The original PNG is **not checked in** by this documentation-only PR. The text below is the durable implementation contract; a static screenshot by itself establishes neither performance traces nor successful review.

## Observations

- Basic painting now appears workable to the owner, but **“deleting the selection” takes a long time**. That was **untimed owner feedback**; later [T-221](Tickets/T-221.md) reproduced slow **Delete pixels** separately from fast Deselect, and [measured a sparse-clear fix](evidence/T-221-2026-11-22-selection-delete.md). Owner physical-hardware recheck remains open.
- The dock still has too much chrome and inconsistent iconography. The visual layout/interaction rules below **supersede incompatible chrome requirements** in the older dock plan, but retain the one-group-floating-host design and existing transaction safety.
- The first visual Brushes dock (T-184) exists, but the selector needs to be denser and provide more settings supported by the actual native libmypaint/Hokusai engine.

## Dock contract

| Surface | Expected behavior | Ticket |
| --- | --- | --- |
| Whole-dock toggle | Replace giant full-width `Minimize panels` row with a **translucent half-circle edge overlay**. Does not hide per-group collapsed states | [T-222](Tickets/T-222.md) |
| Panel icon | One icon per **individual panel**. LMB activates/expands a closed or inactive panel, or collapses/hides its already active/open group; RMB opens contextual **three-dots-equivalent menu** without extra always-visible button | [T-222](Tickets/T-222.md) |
| Group marker | **No visible group names**. A triangle marker roughly **half a panel-icon width** represents collapsed/expanded state. LMB toggles; drag moves **whole group**; RMB opens group context menu | [T-223](Tickets/T-223.md) |
| Icon proximity | Dragging panel icon near another icon group **merges** panels; between groups **reorders**. Panel icon moves one panel, marker moves group; explicit preview and transaction-safe cancel | [T-224](Tickets/T-224.md) |
| Floating tab | Same panel **icons** as dock, not text tabs. Retain **one tabbed group per floating host**, small move grip, close, edge/corner resize | [T-225](Tickets/T-225.md) |

Never allow an icon drag to accidentally activate a collapse action. Docked/minimized/floating panels share one stable-ID owner; all layout state survives restart and invalid operations roll back.

## Colors panel

The owner's screenshot indicates two major regions: a top FG/BG and recent-color strip, and the **native color picker embedded directly below**.

```text
+----------------------------------------------------+
| [  FG (active)  ][ BG ] | |recent| |recent| |recent| |
|----------------------------------------------------|
|      Native Godot ColorPicker for selected FG/BG    |
|      native hue/value/alpha/mode and hex controls   |
|      (scroll the panel to see all rows on small UI) |
+----------------------------------------------------+
```

- FG/BG each display their color. **Highlight the currently edited role**; the picker always reflects it and writes to **only that role**. Clicking BG is not Swap, and BG edits do not change the Brush paint color.
- The other half contains **vertical recent-color bars**, omitting **both current FG and BG colors** and avoiding duplicates. Preserve canonical RGBA8/alpha and hidden RGB identities.
- Keep Swap/Default/previous-color behavior discoverable without bulky explanatory text.
- The recent bar is **filtered at display time**, not destructively pruned from the remembered history, and compares canonical packed RGBA8 identity rather than approximate floats.
- The **full built-in Godot `ColorPicker` is an inline panel child**. Short docks and floating hosts scroll internally, **not** via an overflowing popup. Respect keyboard focus and wheel use.
- [T-226](Tickets/T-226.md) owns this change and must preserve T-092's pixel/history/persistence safeguards; UX acceptance remains open.

## Brushes panel

Keep visual preset samples, active-selection focus and four native Hokusai presets, but **replace long captions with tooltips/hints**. Add actual `.myb`/libmypaint controls **only after verifying native mapping**, ranges, defaults, dynamical curves and per-preset applicability. Freeze the complete effective settings for queued and live strokes. See [T-227](Tickets/T-227.md) and the originally completed [T-184](Tickets/T-184.md).

## Conflict audit and ownership (current design takes precedence)

| Existing ticket/contract | Potential collision | Resolution |
| --- | --- | --- |
| **T-079** (Done) | Old named chevron/group header, old minimize chrome | Historical delivery remains Done; **T-222/T-223 supersede visible chrome**, reusing T-079 group/flyout semantics |
| **T-080/T-082** (Done) | Tab/group drag and insertion previews could be confused with proximity grouping | Keep transactional `DrawingDockLayout`/`DrawingDockDrag`; **T-223 marker = whole-group drag**, **T-224 panel icon = one-panel drag**. Never treat static proximity as a merge |
| **T-081/T-091** | Old textual floating tabs and host/grip geometry | **T-225 owns tab icon visuals**; **T-091 keeps one-group host, edge resize, grip, width restore and physical validation**. Active tab clicks never collapse/close floating host |
| **T-083** (manual gate) | Could be marked approved after only older dock tests | Closure now explicitly depends on T-091 and **T-222–T-225**, then requires fresh owner UX approval |
| **T-092/T-063** | Prior native popover/collapsed advanced picker | **T-226 supersedes picker presentation only**, preserving FG/BG, exact color, preferences, History and Undo contracts; T-092 cannot close before T-226 |
| **T-182/T-184** (Done) | Brush dropdown and visual preset panel could duplicate T-227 | Keep Done baseline; **T-227 owns only compact presentation and additional verified native settings**, not re-implementing presets/brush panel |
| **T-088/T-095/T-197** | Selection Delete lag could be incorrectly folded into Brush latency or native selection migration | **T-221 owns initial Delete-vs-Deselect reproduction and its measured fix**; T-088 keeps mask/clipboard/Move acceptance; T-095/T-197 retain brush hardware/p95 targets |
| **T-148/T-149** | Performance fix might bypass native tile/history authority | Preserve Rust source revisions, signed tile, mask and atomic history rules; T-221 is an independent diagnosis, not a GDScript-only fallback authority |

### Icon click and collapse precedence

- **Expanded dock:** an inactive panel icon selects that tab, expanding its group if necessary; clicking the *already active* icon in an expanded group collapses that group. The triangular group marker toggles the **same collapse bit**, not a second state.
- **Minimized icon rail:** the icon opens/selects or hides the transient group **flyout**, without silently overwriting the persisted group collapse bit. The edge half-circle still toggles **whole-dock** minimized state.
- **Floating host:** icon tabs switch active panels; clicking the current tab is a **no-op**, not a collapse, minimize or close action. Host grip moves/redocks the entire floating group.
- **Pointer safety:** drag threshold wins over click; RMB on icon or marker opens the appropriate context menu without triggering LMB. Preserve keyboard-accessible equivalents.

### Owner-directed execution order

1. **T-221 — P0, Done:** Delete pixels (not Deselect) was slow in software; sparse-clear fix tested. Owner hardware recheck remains in T-088.
2. **T-222 — P0, Done (2026-11-22):** edge half-circle plus exact icon input semantics; [native/Atlas evidence](evidence/T-222-2026-11-22-dock-interactions.md), T-083 owner review still pending.
3. **T-226 — P0, Done (2026-11-22):** FG/BG + recents + embedded scrolling native picker; independent of marker implementation.
4. **T-223 — P0, Done (2026-11-22):** unnamed 24px group triangle and whole-group drag/menu; [native/Atlas evidence](evidence/T-223-2026-11-22-group-marker.md), T-083 owner review still pending.
5. **T-224 — P0, Done (2026-11-22):** single-icon thresholded grouping and [explicit native drop previews](evidence/T-224-2026-11-22-icon-proximity.md) verified; no T-083 owner approval implied.
6. **T-225 — P1, Ready:** floating icon tab consistency.
7. **T-227 — P1, Ready:** compact brush selector and additional proven libmypaint controls.

This is the **next owner-directed UI/performance sprint queue**, ahead of optional cosmetic/backlog work, while **T-148 native authority, T-149 migration and CI correctness retain their separate P0/engineering significance**. Priorities do not override hard dependencies or manual review.

## Manual review and gates

**At Manual Review, not yet approved:** [T-009](Tickets/T-009.md) Search/Find purpose; [T-038](Tickets/T-038.md) independent code review; [T-039](Tickets/T-039.md) player projection/privacy policy.

**Still In Progress or gated:** [T-083](Tickets/T-083.md) dock owner UX, [T-091](Tickets/T-091.md) physical floating-panel interaction, [T-092](Tickets/T-092.md) Colors/history UX, [T-088](Tickets/T-088.md) selection/native masks, [T-095](Tickets/T-095.md) physical Brush latency, and [T-059](Tickets/T-059.md) overall Drawing experience. The owner's request for changes explicitly **does not constitute approval** of the existing implementation.

Native ownership [T-148](Tickets/T-148.md)/[T-149](Tickets/T-149.md), Windows portability [T-105](Tickets/T-105.md) and required hosted CI [T-106](Tickets/T-106.md) remain separate. This PR started as planning/documentation only; T-221 now provides a code fix and local benchmark evidence. T-222 and T-226 also supply tested code updates, but the remaining UX tickets and owner gates are **not** approved by those implementations.

## Dependency-respecting order

Use the owner-directed order above. Completed **T-221, T-222, T-226 and T-223**; next owner priority is **T-224**. T-224 is now Ready (T-223 prerequisite complete); T-225 and T-227 remain independent Ready work. Implement one bounded engineering ticket at a time with native screenshots, pointer tests and logs. Do not mark parent owner gates Done without explicit dated owner signoff.
