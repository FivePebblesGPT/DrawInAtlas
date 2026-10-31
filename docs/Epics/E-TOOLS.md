---
id: E-TOOLS
type: epic
priority: P1
parent: "[[E-004]]"
---
# Familiar drawing-tool suite

## Source
[[ManualReview_2026-10-30#Usability testing|Usability testing]], item 16: Selection, Brush, Eraser, Move, Bucket, Line, Polygon, Contour and Text, with familiar editor interactions inspired by MS Paint, Aseprite and Paint.net.

## Confirmed refinements — 2026-10-30
- **Paint.net** is the primary interaction reference.
- Selection affects the **active layer by default**.
- Replace the original Contour/lasso-drawing request with an **editable point-by-point path tool**, supporting open walls and closed enclosures. This is distinct from polygon shape/fill interaction.
- Text remains editable after placement. Cull it at unreadably small on-screen sizes; the screen-space threshold is still to be evaluated.

## Tickets
- [[T-019|Selection]]
- [[T-020|Brush]]
- [[T-021|Eraser]]
- [[T-022|Move]]
- [[T-023|Bucket]]
- [[T-024|Line]]
- [[T-025|Polygon]]
- [[T-026|Editable open/closed wall paths]]
- [[T-027|Text]]

## Shared acceptance
Use Paint.net to resolve interaction questions unless an explicit tool-specific requirement differs. Tools participate coherently in selection masks, coordinates, undo/redo, layer protections and saving. Existing implemented tools must be reviewed against that contract rather than blindly duplicated. UI placement follows [[T-006]].

Completion is tracked in [[Index]], after acceptance of all nine tool tickets.
