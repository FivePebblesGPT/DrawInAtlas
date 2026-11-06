# Standalone Drawing — owner hands-on usability findings (2026-11-05)

**Status: acceptance failed.** This is a user-observed usability checkpoint against the `aidev` implementation, not a statement that the independent Drawing minimum witness (T-053) or compact-shell engineering (T-063) never existed. The owner's three annotated screenshots were shared in conversation; do not invent checked-in screenshot files or approval links. Findings are separate from root Atlas project's older pre-split review. **No new owner approval is inferred.**

## Triage and source evidence

The editor loads/saves `.drawing` successfully in the reported workflow (#22). That is a **passed path**, not proof that every file is recoverable. Document `revision` increasing on undo (#23) is expected for monotonically versioned state: `DrawingDocument.replay_delta()` republishes inverse pixels. Hide/confine the internal generation instead of decrementing it. The remaining behaviors constitute incomplete, misleading, or broken UX.

| Owner # | Observed behavior / expected result | Primary ticket | Scope/evidence |
| --- | --- | --- | --- |
| 1 | ~1 s stroke response; continuous visible paint before release | [[T-085]] / [[T-086]] | `canvas.gd:paint_to` stages pixels without compositing a draft |
| 2 | No visible canvas edge or transparency checkerboard; define finite image frame over sparse model | [[T-087]] | `canvas.gd:_draw` uses opaque workspace background |
| 3 | Black side bars at nondefault resolution | [[T-090]] | Drawing stretch/aspect and responsive layout require native repro |
| 4 | Brush-size mouse wheel does not adjust value | [[T-090]] | `editor_top_bar.gd:consume_option_wheel` consumes SpinBox wheel |
| 5 | Select does not yield useful editing behavior | [[T-088]] | Marquee-only implementation |
| 6 | Tool SVG appearance inconsistent; review existing licensed icon resources | [[T-090]] | `addons/drawing/icons/*.svg`; provenance not established |
| 7 | Dock width is not restored on relaunch | [[T-091]] / [[T-083]] | Persistence schema exists; real splitter drag/save path suspect |
| 8 | Window menu contains Object/File operations; better command organization | [[T-090]] | `workspace.gd:_build_interface` |
| 9 | Detached far-right × and unnecessary + button | [[T-090]] | TabBar plus separate controls |
| 10 | Floating window can contain groups within groups; excess headings | [[T-091]] | Owner correction supersedes prior floating container contract |
| 11 | Default color popup too large | [[T-092]] | Current native ColorPickerButton |
| 12 | Floating host should be grip+×+tabs and resize from all edges; subtle corner hint | [[T-091]] | `floating_host.gd` custom title/group/resize rows |
| 13 | Click blank with Select should deselect, not select one pixel | [[T-088]] | `canvas.gd:finish_gesture` forms nonempty rectangular selection |
| 14 | Selection is an independent mask/channel, not merely rectangle outline | [[T-088]] | `edit_session.gd` already has selection-aware APIs but workspace does not wire brush to mask |
| 15 | Zoom-out lag, skipped mouse points and straight-looking strokes | [[T-085]] / [[T-086]] | Stage, viewport redraw and input scheduling need measured separation |
| 16 | 'Generic Drawing grid snap' unclear and no show-grid option | [[T-087]] | Toggle assigns 8px snap only |
| 17 | Move tool appears inert | [[T-088]] | Only acts on existing rectangle and displacement, poor feedback |
| 18 | Selection cannot delete/cut/copy/move/limit edits | [[T-088]] | Missing complete selection workflow |
| 19 | Toggle visibility belongs on each layer row as an eye | [[T-089]] | Menu-only visibility, row glyph |
| 20 | +Layer/+Group append to wrong parent/order | [[T-089]] | `_layer_selected`, `_add_group`, `_add_layer` use incompatible targets |
| 21 | Unclear how to load reusable Objects | [[T-093]] / [[T-065]] | Specialized source file vs `Objects/` root discovery |
| 22 | `.drawing` saving and loading **works in tested flow** | [[T-094]] regression | Preserve roundtrip, no new bug ticket |
| 23 | Undo increases visible revision; explain internal generation vs history cursor | [[T-092]] | Internal revision monotonic by design; don't weaken conflict checks |

**Evidence labels:** owner = directly observed; source paths = static code explanations, **not independent runtime reproduction**. No screenshot or performance measurement is presented as verified hardware evidence.

## Milestone delivery sequence

| Milestone | Deliverables | Definition of done |
| --- | --- | --- |
| **M0 — restore trust** | [[T-094]] red CI and owner-run regression matrix; [[T-084]] PhotoCraft scout independently | CI failures diagnosed and reproducible; source-grounded research delivered without blocking application work |
| **M1 — paint responsively** | [[T-085]], [[T-086]] | Live draft stroke, reliable samples, persistent dirty display tiles, measured 100/50/25% zoom; no 1s freeze |
| **M2 — usable canvas/edit model** | [[T-087]], [[T-088]], [[T-089]] | Visible image transparency/frame/grid; selection-mask clipboard/Move; predictable layer hierarchy/undo |
| **M3 — usable workspace** | [[T-090]], [[T-091]], [[T-092]], [[T-093]] | Responsive menu/tabs/icons/wheel, compact one-group floating hosts, color/history, discoverable Objects |
| **M4 — owner re-review and release** | Existing [[T-056]], [[T-059]], [[T-083]], [[T-065]] | Native Windows/Linux pointer/framebuffer + manual signoff; no automated proxy approval |

These are **priorities**, not a transitive graph making interactive painting wait for PhotoCraft source analysis, UI cosmetics, all 47 Essential items, or optional native C++ adoption. New tickets T-084–T-094 start Ready where their historical hard prerequisites are Done. Reassess priorities after engineering evidence.

## Product and architecture invariants

- One DrawingDocument/renderer package for standalone and Atlas; no Atlas imports into the shared addon.
- Atlas owns signed world-space transforms, detail levels and grid overlays; Drawing owns generic selection, paint and document layers.
- Uncommitted strokes render during gestures, but published edits remain atomic with one undo operation, preserved revisions, exact pixels and safe cancellation.
- Standalone image bounds/checkerboard are presentation/document-frame semantics, not a global prohibition on infinite sparse Atlas drawing.
- Dock corrections supersede the earlier **multi-group floating host** proposal; keep explicit owner re-approval under T-083. Do not erase historical engineering witnesses or say the old design was approved.
- No native backend adoption until the actual edit-to-visible path (not isolated C++ kernels) proves a repeatable benefit on real hardware.
