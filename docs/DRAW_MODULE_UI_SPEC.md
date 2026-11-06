# DrawInAtlas — Draw Module UI Specification

**Status:** Proposed design  
**Scope:** Revised Draw workspace layout, based on the earlier mockup (section 8), with a compact top bar and `BarDivider` overflow behavior.

## 2026-11-05 native owner correction (supersedes disputed prototype details)

The owner tested the shipped standalone shell and rejected several usability choices despite earlier T-063 engineering tests. [Full review](DRAWING_USABILITY_REVIEW_2026-11-05.md) and [[T-090]]/[[T-091]]/[[T-092]] define corrective work: responsive full-width client without black side bars; brush-size wheel works; coherent icons; logical File/Object vs Window commands; per-tab × without separate +; compact color/history; one floating group per host, grip/×/tabs-only header and edge resizing. Retain the **single menu/tool-options row**, no redundant quick-action toolbar, central canvas and normal layer/dock hierarchy. This does not constitute approval of the final UX; [[T-059]]/[[T-083]] remain unapproved. Historical proposal details below remain documented where not superseded.

## Authority, delivered subset, and accepted exceptions (T-073; 2026-11-02)

**Proposed, not signed off:** the owner-proposed compact `BarDivider` layout has
now been implemented as an engineering prototype in **T-063**. The 99-row,
47 Essential / 34 Later / 18 Skip feature inventory is approved scope, **not**
owner usability acceptance. Full native Drawing UX acceptance remains with
**T-059** and standalone/Atlas integration acceptance with **T-056**. The
`BarDivider` is a visual boundary only; the independent `ToolOptionsRegion`
owns the scroll state. Neither the prototype nor native automation constitutes
owner signoff.

**Already accepted independent of this proposed layout:** the dedicated Object Editor
document tab (T-062) is implemented with the same Drawing shell.
**Asset Browser dock parity** is approved but not yet shipped; T-065 is now
**Ready**, and owns real asset search, thumbnails, NULL repair and placement.
Internal Atlas `(map, floor, detail)` DrawingDocuments are not user tabs or
Object Assets. These requirements remain fixed regardless of final UX changes.

**Current UI audit (T-063; source: `addons/drawing/workspace.gd` and
`addons/drawing/editor_top_bar.gd`):** the shared shell now implements the
fixed File/Edit/View/Image/Layers/Select/Window/Help menu order, context-sensitive
Brush/Eraser/Select/Move/Text controls, horizontal tool-option scrolling with
chevrons/Shift+wheel, keyboard focus-to-view, reset on tool switch and a
narrow-screen **More** menu. It uses a single top row, without duplicate
quick-access toolbar, plus a six-tool rail (**Brush, Eraser, Select, Move,
Text, Pan**), document tabs, a resizable/hideable Colors/Layers/History dock,
and a clipped status bar. The selection-history preference (OFF by default)
is in the History dock, not a tool option. Unsupported options (opacity,
feather and arbitrary transforms) are **not** displayed as working controls.

**Visible shortcut labels:** File/Edit menus expose New `Ctrl+N`, Open
`Ctrl+O`, Save `Ctrl+S`, Save As `Ctrl+Shift+S`, Undo `Ctrl+Z` and primary
Redo `Ctrl+Y`; `Ctrl+Shift+Z` remains a supported redo alias. Native automation
(`drawing/tests/compact_workspace_smoke.gd`) verifies Save As, narrow overflow,
keyboard focus, wheel protection and unsaved-close behavior. These native
engineering checks visibly label implemented shortcut behavior, rather than
assert owner usability signoff. The formerly
missing menu shortcut labels and incorrect Save As binding are corrected in
T-063, but owner hands-on UX remains open.

### Concrete first-slice vs full-workspace checklist

| Stage | Item | Evidence or remaining gate |
|---|---|---|
| [x] Minimal T-053 | Launch independent Drawing; group/layer, Brush/Eraser, rectangular selection and pixel Move; undo/redo; byte-exact `.drawing` save/reopen | `drawing/tests/standalone_smoke.gd` and native `drawing/tests/native_pointer.gd` |
| [x] Shared Object Editor source tab | Reuse the same document/tools; draft stays private until source Save; Save As from instance rebinds only that instance | `drawing/tests/object_editor_ui_smoke.gd`, `tests/object_editor_smoke.gd`; T-062 done |
| [x] T-063 phase 1 | Fixed eight-menu row, context-sensitive tool options to right of `BarDivider`, no duplicate toolbar, visible shortcuts and correct Save As | Implemented and native-tested; owner final signoff remains T-059 |
| [x] T-063 phase 2 | Width-sensitive overflow cues and wheel/Tab behavior; tool-change reset, focus visibility, high DPI and narrow windows | Implemented and native-tested on Linux; Windows/owner acceptance pending |
| [ ] T-065 docking | Resizable/show-hide Colors/Layers/History dock; peer Asset Browser with search, variants and NULL repair | T-063 resizable peer dock complete; Asset Browser still Ready, not implemented |
| [ ] T-059 full baseline | Complete approved Essential workflows, including still-Ready tool UX, then get owner hands-on final signoff | **Manual review; not granted by this document** |

### Repeatable native pointer/keyboard cases (not paper-only signoff)

- **UI-01, existing slice:** launch standalone, pointer-paint/erase and drag rectangle selection/move; issue `Ctrl+Z` / `Ctrl+Y`, save and reopen; compare exact pixel/IDs and visually check changed/unchanged canvas points (`drawing/tests/standalone_smoke.gd`, `drawing/tests/native_pointer.gd`, `drawing/tests/workspace_keyboard_smoke.gd`).
- **UI-02, shortcut discoverability — T-063 engineering verified:** open File/Edit menus with pointer and keyboard; confirm visible key labels; press `Ctrl+N`, `Ctrl+O`, `Ctrl+S`, `Ctrl+Shift+S`, `Ctrl+Z`, one primary redo and `Ctrl+W`. Confirm Save As prompts for new path and Close prompts before losing a dirty tab. Current `Ctrl+N`, `Ctrl+Z`, both redo aliases and `Ctrl+W` are exercised by `drawing/tests/workspace_keyboard_smoke.gd`; the discovery/Save As assertions are now in `drawing/tests/compact_workspace_smoke.gd`. Record screenshot, native platform and chosen redo binding.
- **UI-03, overflow — T-063 native engineering verified:** at 1280×800 and a narrow window (e.g. 800×600), with 100%/150–200% UI scale, choose Brush and Tab through its controls, use Shift+wheel or chevrons to reveal the rightmost field, switch to Text and back. Assert one row, visible focus/edge cue, scroll reset, usable menu width, and unchanged slider values while scrolling. The new native Godot witness verifies the real options scroll and keyboard focus; final owner pointer/usability acceptance remains open.
- **UI-04, Asset Browser parity — pending T-065:** activate the Browser by keyboard, resize/show/hide it like Colors/Layers/History; browse a retained unused Save As variant and explicit NULL proxy; ensure tabs are source editor tabs, not internal per-detail documents.
- **UI-05, Object Editor already testable:** open an instance-bound source; edit a private draft, Save then Save As; undo rebind while keeping saved variant and invoke a separate source tab (`tests/object_editor_smoke.gd`, `drawing/tests/object_editor_ui_smoke.gd`). Owner interaction acceptance remains open.

The comprehensive owner walkthrough and first-slice/full-baseline checklist are cross-referenced in `[[DRAWING_FEATURE_INVENTORY]]`. Automated tests can validate regressions, **not** replace physical keyboard, focus, panel resizing or owner review evidence.

## Future PhotoCraft-style docking (planning only; T-078–T-083)

The owner agreed on 2026-11-02 to track a **six-ticket follow-up**,
not to extend already-Done T-063. The canonical [panel docking design](DRAWING_DOCKING_SPEC.md)
explicitly models **ordered panel groups**: separators in the right icon rail
separate groups; **each individual panel keeps its own icon**, and any icon in
a group opens the **same tabbed flyout**, selecting that tab. Groups may move
as units to/from **in-app** floating containers while retaining their ordered
tabs. Independent group collapse, reordering, insertion previews and layout
persistence are separately gated T-079–T-083 features, **not shipped today**.
T-083 has an owner UX approval gate; T-059 and T-056 remain outstanding.

## 1. Design objective

Make the drawing environment familiar to users of Paint.NET and PhotoCraft without spending an entire row of vertical space on a conventional quick-access toolbar.

Core principles:

- Give the canvas as much space as possible.
- Keep standard application commands in the menu bar, with keyboard shortcuts for common operations.
- Show tool-specific settings next to the menu bar instead of in a separate row.
- Keep frequently used drawing tools on a compact vertical rail.
- Use a right-side dock for Colors, Layers, History, and other panels.
- Scroll tool options horizontally only when they overflow the space available.

## 2. Revised workspace layout

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ File  Edit  View  Image  Layers  Select  Window  Help │ Brush  Size  Opacity  ›│
│                                                    ↑                         │
│                                               BarDivider                     │
├──────────────────────────────────────────────────────────────────────────────┤
│ [Untitled Drawing *] [×]                                                   │
├────┬──────────────────────────────────────────────────────────┬──────────────┤
│    │                                                          │ Colors       │
│ T  │                                                          │ ──────────── │
│ O  │                                                          │ [■] [■]      │
│ O  │                      CANVAS                              │ ──────────── │
│ L  │                                                          │ Layers       │
│ S  │                                                          │ [Drawing]    │
│    │                                                          │ [Background] │
├────┴──────────────────────────────────────────────────────────┴──────────────┤
│ X: 128  Y: 64                         1920 × 1080                 Zoom: 100%│
└──────────────────────────────────────────────────────────────────────────────┘
```

The **top bar contains two functional regions**:

1. **Fixed menu region (left):** File, Edit, View, Image, Layers, Select, Window, Help. Its commands open as menus.
2. **Scrollable tool-options region (right):** Context-sensitive controls for the active tool, such as Brush size, Opacity, Hardness, and Blend mode.

A `BarDivider` marks the boundary. The document tab row, canvas, tool rail, right dock, and status bar remain separate.

### Why remove the quick-access toolbar?

The earlier mockup used a row with New, Open, Save, Undo, and Redo. These actions belong in **File** and **Edit**, and many users already access them through shortcuts. Removing that row avoids duplicating controls and frees vertical space. This is a DrawInAtlas design decision, not a claim that Paint.NET uses the same layout.

Suggested commands and shortcuts:

| Menu | Command | Typical shortcut |
|---|---|---|
| File | New | Ctrl+N |
| File | Open | Ctrl+O |
| File | Save | Ctrl+S |
| File | Save As | Ctrl+Shift+S |
| Edit | Undo | Ctrl+Z |
| Edit | Redo | Ctrl+Y or Ctrl+Shift+Z (choose one default) |

Keep a visible modified-document indicator (`*`), preserve unsaved-change prompts, and show shortcuts in menu items.

## 3. Compact top bar

### Fixed menu region

- Remains visible when tool options overflow.
- Contains menu triggers, not duplicate quick-action buttons.
- Can reduce gaps or place less frequently used menus into a **More** overflow menu on narrow windows.
- Should not consume the entire width and leave no room for tool settings.

### Scrollable tool-options region

- Displays the selected tool's controls.
- Uses a single horizontal line at ordinary window sizes.
- Scrolls horizontally only when content exceeds its allocated width.
- Shows subtle edge gradients and/or chevrons when additional controls are hidden.
- Supports touchpad horizontal scrolling, Shift + mouse wheel, and optional chevron buttons.
- Scrolls focused controls into view during keyboard Tab navigation.
- Resets scroll to the start when a different tool is selected.
- Keeps critical controls first: for example, Brush preset, Size, Opacity, Hardness, and then more advanced settings.
- Must not let the pointer wheel accidentally change a slider value while the user intends to scroll the bar; use explicit focus/hover rules.

Example contextual content:

| Tool | Top-bar controls |
|---|---|
| Brush | Preset, Size, Opacity, Hardness, Blend mode, Smoothing |
| Eraser | Size, Opacity, Hardness, Mode |
| Rectangle | Fill, Stroke color, Stroke width, Corner radius, Shape/Pixel mode |
| Selection | Selection mode (New/Add/Subtract/Intersect), Feather, Antialias |
| Text | Font, Size, Style, Alignment, Color |
| Move/Transform | Position, Width, Height, Rotation, Constrain proportions |

Only show controls supported by the Draw engine; do not render misleading or nonfunctional options.

## 4. `BarDivider` design

`BarDivider` is a **layout boundary**, not necessarily the scrolling implementation itself.

```text
EditorTopBar
├── MenuRegion               (fixed)
│   ├── FileMenu
│   ├── EditMenu
│   ├── ViewMenu
│   └── ...
├── BarDivider               (boundary / visual separator)
└── ToolOptionsRegion        (flexible width; horizontal overflow)
    └── ActiveToolOptions
        ├── BrushOptions
        ├── EraserOptions
        ├── SelectionOptions
        └── ...
```

**Responsibilities:**

- `MenuRegion`: command navigation and its own narrow-window overflow handling.
- `BarDivider`: marks the boundary between fixed and flexible regions; may optionally support resizing in a future iteration.
- `ToolOptionsRegion`: owns width constraints, scrolling, overflow cues, and focus visibility.
- `ActiveToolOptions`: supplies controls for the current drawing tool.

### Overflow algorithm (conceptual)

1. Measure the width available to `ToolOptionsRegion` after the fixed menu region and divider are laid out.
2. If tool controls fit, hide scroll affordances and display all options normally.
3. If controls exceed available width, enable horizontal scrolling and display an appropriate edge indication.
4. Keep the bar itself at a fixed height; do not wrap controls onto a second line.
5. When the active tool changes, update controls and return the scroll position to the start.
6. If keyboard focus moves into an offscreen control, scroll it into view.
7. If the application window becomes too narrow, collapse lower-priority menu items rather than shrinking the options region to zero.

**Recommended accessibility:** visible focus states, tooltips, discernible labels, keyboard-reachable overflow controls, and no reliance on horizontal-wheel input alone.

## 5. Other workspace elements

### Left tool rail

Compact vertical icons for selection, move, brush, eraser, eyedropper, fill, shapes, text, and navigation tools. Show tooltips with names and shortcuts. Support tool grouping later if needed.

### T-063 refinement — owner-requested (2026-11-02)

The owner requested an **icon-only tool rail** with tooltips instead of the six
button labels; a **hideable document tab strip** (Window → Show document tabs,
Ctrl/Cmd+Tab navigation, active document/dirty status even when hidden); and
**stacked, vertically scrollable Colors/Layers/History dock panels**, rather
than mutually exclusive tabs. The engineering refinement is complete with a
75-check native witness. Document-tab-strip visibility is session-local, not a
persisted workspace setting. This overrides the earlier tabbed-panel prototype
for T-063 but does **not** approve the overall proposed UI or close T-059's
hands-on owner review. T-065 Asset Browser should join the stacked dock, not
reinstate peer tabs without further owner direction.

### Right-side dock

Start with a single dock containing **Colors** and **Layers**, with **History** as a tab. Expand later to Properties, Brushes, and Navigator. Allow panel resizing and show/hide controls; floating panels and arbitrary docking can be introduced later.

### Document tabs

Display the active document, a modified-state marker, and a close action. Ask about unsaved changes before closing.

### Status bar

Show cursor coordinates, canvas dimensions, and zoom. Keep it compact and provide easy access to zoom adjustment.

## 6. Architectural boundaries

The UI should send actions through shared commands rather than modifying document state independently in every toolbar or menu component.

```text
DrawModule
├── WorkspaceUI
│   ├── EditorTopBar
│   │   ├── MenuRegion
│   │   ├── BarDivider
│   │   └── ToolOptionsRegion
│   ├── DocumentTabs
│   ├── ToolRail
│   ├── CanvasViewport
│   ├── PanelDock
│   └── StatusBar
├── ToolSystem
├── CommandSystem  (execute / undo / redo)
├── DocumentModel  (layers / selections / content)
└── RenderingEngine
```

This permits future redesigns of the workspace without tightly coupling UI layout to drawing behavior.

## 7. Implementation phases

### Phase 1 — Compact functional workspace

- Remove the redundant New/Open/Save/Undo/Redo toolbar row.
- Move active tool options to the right of the menu bar.
- Add the `BarDivider` and horizontally scrollable options container.
- Retain keyboard shortcuts and unsaved-document indication.
- Build the compact left tool rail, central canvas, right dock, document tabs, and status bar.

### Phase 2 — Overflow and input polish

- Add overflow gradients/chevrons, horizontal scroll support, keyboard focus management, and tool-change scroll reset.
- Add responsive menu overflow for narrow windows.
- Verify behavior at small window sizes and high UI scaling.

### Phase 3 — Workspace customization

- Add docking, floating and tabbed panels, persisted layouts, and workspace reset.
- Add optional resize behavior for the bar boundary **only if** testing shows a need.

## 8. UX acceptance criteria

- At typical desktop widths, menu entries and the most important tool settings fit on one row.
- At narrower widths, tool settings scroll horizontally without wrapping or obscuring the canvas.
- The File/Edit menus and common shortcuts remain available after the quick-access toolbar is removed.
- A user can discover offscreen options through visible overflow cues.
- A keyboard user can focus every tool option and see the focused control.
- Switching tools shows the correct contextual options and resets horizontal scroll.
- Small window widths do not reduce the options region to an unusable sliver.
- The UI does not lose document changes when closing a tab or switching modules.

---

**Recommendation (proposal only as owner UX; engineering T-063 done, T-059 pending):** Continue hands-on validation of the implemented one-row menu + scrollable tool-options design before claiming final UX adoption. Keep `BarDivider` as a small reusable layout primitive, while making the options container responsible for scrolling, overflow state, and accessibility.