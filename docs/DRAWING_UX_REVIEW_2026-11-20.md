# Drawing owner follow-up — 2026-11-20

**Source:** owner-provided screenshot `DrawInAtlasColorPanel(3).png` and interaction notes in the 2026-11-20 conversation. The original PNG is **not checked in** by this documentation-only PR. The text below is the durable implementation contract; a static screenshot by itself establishes neither performance traces nor successful review.

## Observations

- Basic painting now appears workable to the owner, but **deleting a selection takes a long time**. No duration, hardware benchmark or cause has been verified. [T-221](Tickets/T-221.md) separates Delete pixels from Deselect and measures the actual `clear_rect`/commit path.
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
- The **full built-in Godot `ColorPicker` is an inline panel child**. Short docks and floating hosts scroll internally, **not** via an overflowing popup. Respect keyboard focus and wheel use.
- [T-226](Tickets/T-226.md) owns this change and must preserve T-092's pixel/history/persistence safeguards; UX acceptance remains open.

## Brushes panel

Keep visual preset samples, active-selection focus and four native Hokusai presets, but **replace long captions with tooltips/hints**. Add actual `.myb`/libmypaint controls **only after verifying native mapping**, ranges, defaults, dynamical curves and per-preset applicability. Freeze the complete effective settings for queued and live strokes. See [T-227](Tickets/T-227.md) and the originally completed [T-184](Tickets/T-184.md).

## Manual review and gates

**At Manual Review, not yet approved:** [T-009](Tickets/T-009.md) Search/Find purpose; [T-038](Tickets/T-038.md) independent code review; [T-039](Tickets/T-039.md) player projection/privacy policy.

**Still In Progress or gated:** [T-083](Tickets/T-083.md) dock owner UX, [T-091](Tickets/T-091.md) physical floating-panel interaction, [T-092](Tickets/T-092.md) Colors/history UX, [T-088](Tickets/T-088.md) selection/native masks, [T-095](Tickets/T-095.md) physical Brush latency, and [T-059](Tickets/T-059.md) overall Drawing experience. The owner's request for changes explicitly **does not constitute approval** of the existing implementation.

Native ownership [T-148](Tickets/T-148.md)/[T-149](Tickets/T-149.md), Windows portability [T-105](Tickets/T-105.md) and required hosted CI [T-106](Tickets/T-106.md) remain separate. This PR is **planning/documentation only**, not a code or benchmark fix.

## Dependency-respecting order

Ready independent work: **T-221**, **T-222**, **T-225**, **T-226**, **T-227**. Next, **T-223** after T-222, then **T-224** after T-223. Implement one bounded engineering ticket at a time with native screenshots, pointer tests and logs. Do not mark parent owner gates Done without explicit dated owner signoff.
