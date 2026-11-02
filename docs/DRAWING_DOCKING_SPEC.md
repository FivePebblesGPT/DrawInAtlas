# Drawing workspace panel docking — agreed follow-up scope

**Planning state (2026-11-02):** Owner agreed to split the PhotoCraft-like docking work into **T-078–T-083**, with implementation **not started**. These are requirements for future engineering tickets, not a claim that Drawing already supports them or that final UX is approved. The current T-063 dock stacks Colors/Layers/History vertically in a scroll container and has a show/hide control; its owner-review boundaries remain intact. See [the workflow](TICKET_WORKFLOW.md) and [the UI specification](DRAW_MODULE_UI_SPEC.md).

## Reference behavior and terminology

The owner supplied PhotoCraft 0.19.0 demonstrations/screenshots on 2026-11-02 and clarified the previously missed grouping rule:

- **Panel:** one tool-specific view, identified by a stable ID (e.g., Colors, Layers, History). Its tab and icon are alternate activators of the **same** view, never copies. Accessible icon/tooltip text must identify the panel; do not use ambiguous one-letter buttons.
- **Panel group:** an **ordered** set of one or more panels sharing a tab strip and one displayed active panel. Multiple groups may appear in a vertically stacked dock. Each group can collapse its body independently while preserving tabs and its active-panel ID.
- **Dock icon rail:** there is **one icon per attached panel**, not one icon per group. A separator between contiguous icon sequences indicates a **group boundary**. Clicking any group member's icon opens or focuses that **group's shared flyout** and selects the clicked panel's tab. For example, a Color/Swatches/Gradients/Patterns group yields four successive icons but a single tabbed flyout.
- **Expanded dock:** groups stack vertically and the area scrolls; group contents are independently collapsible. A group header/tab bar and its corresponding right-edge icon sequence remain recognizable. Changing one group's active tab does not modify another group's selection.
- **Minimized dock:** the dock's width contracts to a slim rail containing its ordered icons **and separators**, not a permanently fixed set of all available panels. Opening a group creates a **Godot UI** flyout to the rail's left, over the workspace; it does not resize the canvas or spawn an operating-system window. Selecting another icon in that group switches the existing flyout's active tab, while selecting an icon from another group switches to that group. Clicking the active icon can hide the flyout; canvas interaction alone should not automatically dismiss it (observed PhotoCraft behavior).
- **Floating container:** an in-app, moveable/resizable `Control`-based host for one or more tabbed panels/groups. It has the same grouping, tab order, active selection, and reorganization rules as the dock, rather than being a dumb popup or native OS window. Detaching a group removes **all** its member icons and associated separators from its old dock rail; its tabs remain available in the floating container. Reattaching restores the icons in the new order.
- **Docking preview:** while dragging, visually show valid group/tab insertion targets (including exact position relative to existing rail groups). A drag is transactional: cancellation or an invalid drop leaves the source membership/order unchanged. Reattaching a whole floating tab group inserts its members **in their current relative order at the indicated cursor location**, not at an arbitrary end position.

Distinct concepts: **panel visibility**, **panel ownership** (dock or floating container), **group membership and ordered position**, **active panel**, **group body collapsed/expanded**, **whole-dock minimized/expanded**, and **temporary flyout visibility**. None should be inferred indirectly from another. Panel IDs must appear in at most one live container at a time; hidden/closed panels must remain recoverable through an application menu without silently being reassigned to the dock.

## User flows that define acceptance

1. **Grouped rail flyout:** minimize the right dock; icons `Colors | Layers | History` (initially singleton groups) stay visible and have tooltips; click Layers and see a dock-attached in-app flyout; click Layers again to hide it. After grouping Colors and Layers, their adjacent icons have **no separator between them**; clicking either shows **one shared flyout**, with the requested tab active. A separator remains between that group and History.
2. **Independent vertical groups:** restore the dock and collapse Colors while leaving Layers open. Scroll through groups on a short window without losing focus/selection or forcing the canvas to change height. Switch to minimized and back; preserve collapsed/active state.
3. **Reorder and regroup:** drag the Layers tab before Colors inside a tabbed group; drag History into the group and later split it out, without duplicating or losing any panel ID. Corresponding icon order and separators update to match membership immediately upon drop.
4. **Float and redock a group:** detach a two-panel group to a movable, resizable **in-app** floating host; both member icons disappear from the source dock. Reorder tabs in the floating host; drag the **whole group** onto an indicated dock insertion point; both icons return **in that tab order** at the cursor's indicated group position. Dragging only one tab must not drag the entire group.
5. **Cancel and recover:** escape/invalid drop restores the original layout; hide/close a floating panel without unexpectedly redocking it, then reopen via Window or an equivalent panel list. No orphaned group, duplicate tab, or data loss after repeated moves.
6. **Persist and validate:** restart/restore a mixed docked/floating layout with group order, active tabs, collapsed groups and minimized state intact. Invalid/offscreen geometry is clamped into the current application viewport; narrow-screen/HiDPI focus and hit targets work; owner verifies the native interaction once engineering tests are complete.

These are target scenarios, **not evidence of present behavior**. Grouped tabs, float/drop targets, and persistence deliberately ship in later tickets. Native pointer/keyboard evidence is required for interaction tickets; code-only/document assertions are not a substitute. All windows are in-app controls, never independent OS windows.

## Delivery stages and dependency edges

Statuses below are the **initial planning state on 2026-11-02**, not a substitute for the ticket frontmatter as work advances.

| Ticket | Stage | Hard prerequisite | Gate |
| --- | --- | --- | --- |
| [T-078](Tickets/T-078.md) | Shared stable-ID panel/group/container state model and transactional moves | T-063 | Engineering tests; **Ready** |
| [T-079](Tickets/T-079.md) | Collapsible vertically scrolling groups, grouped icon rail, shared group flyouts | T-078 | Native interaction tests; **Blocked** |
| [T-080](Tickets/T-080.md) | Tab reordering, group creation/splitting and rail insertion previews | T-079 | Native drag tests; **Blocked** |
| [T-081](Tickets/T-081.md) | Movable/resizable in-app floating **tabbed group** containers | T-080 | Native window/control tests; **Blocked** |
| [T-082](Tickets/T-082.md) | Cross-container docking: tabs and whole groups with alignment hints | T-081 | Native target/cancellation tests; **Blocked** |
| [T-083](Tickets/T-083.md) | Workspace layout persistence/recovery and final owner UX acceptance | T-082 | **Owner manual review** after engineering; **Blocked** |

Only **one implementation ticket per turn**. T-065's future Asset Browser may register as another panel, but this design work does not make T-065 Done or create an unnecessary hard dependency on it. T-059 and T-056 retain their separate full-Drawing UX and Atlas integration manual gates. Owner agreement to this staged scope is **not** manual approval of a future T-083 implementation.

## Test strategy

- **T-078:** headless invariant/property-style tests for stable IDs, ownership uniqueness, ordered groups/containers, active selection, move commit/rollback and serialized model round-trips.
- **T-079:** native Godot input/visual witnesses for chevrons, independent collapse, icon order/separators, shared flyout tab selection, keyboard/tooltip access, minimized/expanded transition, short-window scrolling and canvas size.
- **T-080:** realistic pointer drag tests covering within-group reorder, split, merge, insertion positions, invalid target and Esc rollback; verify icon order matches tab order.
- **T-081:** native focus/resizing/viewport clipping tests for in-app floating tabbed groups (including no `Window` OS handoff), grouped/ungrouped source icons and repeated detach/close/reopen.
- **T-082:** group versus single-tab drag targets, between/inside-group hints, precise cursor insertion, preserve floating tab order, cancel and repeated cross-container moves.
- **T-083:** deterministic persistence/recovery and migration from T-063 defaults; cross-resolution DPI/narrow-window tests and an evidence-backed **owner** native usability review. No agent can approve that gate.

## Limits and explicit non-goals

Do not change DrawingDocument pixel/layer data, Atlas content or document-tab semantics for dock rearrangement. Avoid native OS subwindows and premature arbitrary multi-monitor docking. Do not treat a screenshot or successful automated test as owner UX signoff. Work on keyboard focus, color contrast, minimum hit size and screen-reader/tooltip labels should accompany each interactive stage, not be left solely to the final ticket.
