# T-312 — Panel icon sampling (2026-11-25)

## Implementation

`DrawingDockIcons.apply_to` applies the named or fallback SVG and explicit
`CanvasItem.TEXTURE_FILTER_NEAREST` on the icon-only Button. Expanded dock
and minimized rail use `_panel_button`, flyout uses `_flyout_panel_button`,
and floating hosts use the same shared resolver. No canvas, picker body,
unrelated toolbar, project setting, or global texture-filter change. Nearest
is a reversible, owner-suggested engineering default, not final UX approval.

## Before/after and visual inspection

Godot `4.8.beta4.official.b070e63b1`, required native Rust extension, software
X11/Mesa llvmpipe OpenGL compatibility. Baseline `1326e3f3`; corrected build is
that commit plus this ticket's production blobs `c3996238` (dock icons),
`84ff86e2` (workspace), and `185ba04a` (floating host). The baseline rendered
all four standalone states at 100% and 150%: effective filter was linear (2)
for expanded, rail and floating, and nearest (1) for flyout. Corrected
standalone and real Atlas Object Editor report nearest for all four states at
both scales. Baseline functional checks were already green: the defect was
visual, not a functional input failure. Filter diagnostics document sampling;
no cosmetic-only geometry assertions were introduced.

The actual captured windows and original-pixel before/after crops were opened
and inspected. `/mnt/data/t312-visual/comparison-100.png` and
`comparison-150.png` show the formerly softened outlines matching the crisp,
pixel-stepped flyout outline. Actual standalone and Atlas captures use the
names `{expanded,rail,flyout,floating}-{standalone,atlas}-{100,150}.png` in the
same directory; `atlas-states.png` is an overview of the eight hosted captures.
The checkerboard, color gradients, label placement, focus indicators and panel
identity remain intact. The hosted blue artwork rectangle keeps its sharp
edges (the floating panel can occlude the artwork, as before). At 150% the
picker's lower controls are scrollable in the constrained space. No new
layout or artwork sampling policy was introduced. Physical HiDPI monitor,
GPU/Windows rendering and hosted CI remain unverified.

## Verification

Pinned `make test-panel-icons TOOLCHAIN=bundle BUNDLE=<supplied bundle>`:
32/32 standalone and 36/36 actual hosted Object Editor checks. Pointer
activation, collapse/reopen, keyboard dock toggling and flyout selection,
floating selection including fallback icon, redocking, original view ownership,
canvas and panel-body filter preservation, document revision/history/dirty
state, registry source hash and Atlas history are checked. The initial hosted
synthetic edge-toggle click did not minimize; the final new test uses the
focusable toggle's keyboard path and continues to exercise panel pointer
input. The existing standalone and embedded edge-toggle pointer suites passed;
no claim is made about physical pointer targeting in every hosted configuration.

Adjacent suites: T-225 floating icons 63/63; T-254 flyout 138/138 and hosted
10/10; T-251 toggle 92/92 and hosted 19/19; T-309 Window recovery 69/69 and
hosted 20/20; compact workspace 75/75; dock model 82/82. Python responsive,
docking plan, pointer-log and floating-dock tests passed 29/29; explicit typing
passed 635 scripts and 33 skill documents. Ticket-store validator passed 312
tickets. `test-panel-icons` is included in the existing on-demand native
workspace workflow; hosted run is pending.

T-250 returns to Manual Review because all seventeen direct engineering
prerequisites are Done. T-059, native consolidation and physical/portability
acceptance remain open. No owner signoff is inferred.
