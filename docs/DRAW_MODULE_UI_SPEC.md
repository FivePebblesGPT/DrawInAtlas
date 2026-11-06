# DrawInAtlas — Draw Module UI Specification

**Status:** Proposed design  
**Scope:** Revised Draw workspace layout, based on the earlier mockup (section 8), with a compact top bar and `BarDivider` overflow behavior.

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

**Recommendation:** Adopt the one-row menu + scrollable tool-options design. Keep `BarDivider` as a small reusable layout primitive, while making the options container responsible for scrolling, overflow state, and accessibility.