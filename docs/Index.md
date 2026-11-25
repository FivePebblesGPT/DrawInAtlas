**2026-11-25 owner review — next Drawing sprint:** [review and ordered queue](DRAWING_UX_REVIEW_2026-11-25.md), T-302–T-311 Done; T-312 Ready. Prior dock/ColorPicker corrections received positive feedback, but missing tools, export, color, text, object, panels, storage and layer/icon polish remain. T-250 is Blocked pending corrections and explicit owner acceptance. T-148–T-152 native consolidation remains open; hosted beta4 CI on PR #23 head `da308376` passed (see review). Do not infer full approval.

**[T-301](Tickets/T-301.md) P1 implementation Done (2026-11-24):**
[True polygon interior vs selected-pixel bounded preflight](evidence/T-301-2026-11-24-polygon-selection.md)
keeps accepted deferred Brush and lazy source untouched when a selected pixel
lies inside polygon bounds but outside its painted geometry. Native beta4
fail-first 3/39, passing 39/39 and eight adjacent 573/573 checks; T-068/T-148,
hosted CI and owner approval remain open.

**[T-300](Tickets/T-300.md) P1 implementation Done (2026-11-24):**
[Bounded exact selection-mask overlap preflight](evidence/T-300-2026-11-24-masked-overlap.md)
prevents masked interior holes and boolean subtraction from flattening a
pending Brush on no-op bulk edits. Real beta4 Rust fail-first 13/59,
corrected 62/62 and 652/652 neighboring checks pass. T-068/T-148,
hosted CI and owner review remain open.

**[T-299](Tickets/T-299.md) P1 implementation Done (2026-11-24):**
[Disjoint/empty selection bulk no-ops preserve accepted deferred Brush](evidence/T-299-2026-11-24-masked-bulk.md)
without materialization, lazy I/O or history changes. Real Godot beta4 native
fail-first 8/40, corrected 40/40, adjacent 480/480; T-068/T-148 and
hosted/owner gates remain open.

**[T-298](Tickets/T-298.md) P1 implementation Done (2026-11-24):**
[T-095 native tile-publisher stride selection](evidence/T-298-2026-11-24-brush-stride.md)
uses canonical pixel-key Brush/Erase publication for valid synthetic strides
below Rust's 16px minimum, instead of failing after correct previews.
The existing T-095 on-demand native test now passes 632/632, the adjacent
tile-key oracle passes 33,037/33,037, and supported native strides retain
tile-local history. T-095 physical owner review, T-068/T-148 and hosted CI
remain open.

**[T-297](Tickets/T-297.md) P1 implementation Done (2026-11-23):**
[Brush candidate-window numeric overflow guard](evidence/T-297-2026-11-23-brush-candidate-bounds.md)
clips floating bounds before integer conversion and preserves small clipped
strokes with huge finite widths. Original 48/113 fail-first, corrected 113/113,
neighboring native geometry and history regressions green. T-095's pre-existing
stride-3 test and T-068/T-148, hosted CI and owner gates remain open.

**[T-296](Tickets/T-296.md) P1 implementation Done (2026-11-23):**
[Native Delete signed projection preflight](evidence/T-296-2026-11-23-clear-native-projection.md)
rejects globally unpublishable clear regions before lazy chunk access or
flattening a deferred Brush. Real beta4 Rust fail-first 15/50 failures,
corrected 50/50 plus eight neighboring native/Atlas checks pass.
T-148/T-068, hosted CI and T-250 owner approval remain open.

**[T-295](Tickets/T-295.md) P1 implementation Done (2026-11-23):**
[native signed Brush per-pixel preflight](evidence/T-295-2026-11-23-brush-native-projection.md)
rejects globally unpublishable swept Brush/mixed pixel edits before lazy
source reads or deferred Brush materialization. Fail-first 30/50 failures,
corrected 50/50, neighboring pixel/geometry and Atlas X11 checks pass.
T-068/T-148, hosted CI and T-250 owner review remain open.

**[T-294](Tickets/T-294.md) P1 implementation Done (2026-11-23):**
[bulk edit global native projection guard](evidence/T-294-2026-11-23-bulk-native-projection.md)
rejects unpublishable signed rectangle, byte-region and polygon edits before
lazy-source access or deferred Brush materialization. Real beta4 Rust witness
71/71 and eight adjacent native suites 301/301 pass. T-148/T-068 and
hosted/owner review gates remain open.

**[T-293](Tickets/T-293.md) P1 implementation Done (2026-11-23):**
[native global signed flood-fill projection guard](evidence/T-293-2026-11-23-native-fill-projection.md)
rejects unpublishable ±2⁵² seeds/frontier neighbors before lazy reads,
with 18-failure native baseline, corrected 41/41, independent mutation
controls and 283/283 adjacent native checks. T-148/T-068 and hosted/owner
gates remain open.

**[T-292](Tickets/T-292.md) P1 implementation Done (2026-11-23):**
[signed-boundary flood-fill frontiers now exclude unpublishable neighbors before
lazy source reads](evidence/T-292-2026-11-23-fill-frontier.md).
Fail-first 10/22 failures, corrected 38/38, eight adjacent native suites
283/283 pass. T-148/T-068, hosted CI and T-250 owner review remain open.

**[T-291](Tickets/T-291.md) P1 implementation Done (2026-11-23):**
[selection-excluded flood-fill seeds now bypass lazy source reads without
flattening a valid deferred Brush](evidence/T-291-2026-11-23-masked-seed-preflight.md).
Fail-first catches 10/33 failures, corrected 33/33 and seven neighboring
native suites 250/250 pass. T-148/T-068, hosted CI and T-250 remain open.

**[T-290](Tickets/T-290.md) P1 implementation Done (2026-11-23):**
[bulk rectangle/byte-region/polygon preflight now preserves deferred Brush and
avoids lazy-source side effects on invalid input](evidence/T-290-2026-11-23-bulk-preflight.md).
Fail-first reproduced eight failures; 28/28 corrected Rust-backed checks and
adjacent fill/history regressions pass. T-148/T-068 and hosted/owner gates
remain open.

**[T-289](Tickets/T-289.md) P1 implementation Done (2026-11-23):**
[early flood-fill seed/RGBA8 validation prevents invalid requests from
invoking arbitrary lazy-source loaders](evidence/T-289-2026-11-23-fill-preflight.md).
The real native fail-first fixture reported 13/23 failures; corrected 23/23,
161 neighboring native checks and strict required-CI coverage pass. T-068
performance/portability, hosted CI and T-250 owner gates remain open.

**[T-288](Tickets/T-288.md) P1 validation Done (2026-11-23):**
[T-068 native fill-to-frame runner builds/registers Rust before profiling](evidence/T-288-2026-11-23-native-fill-frame.md),
with exact post-frame canonical RGBA8 coverage instead of retired pixel
history maps, and actual pinned beta4 engine/hash provenance. Two 21-trial
software-X11 profiles pass all 770 native checks; hosted CI, physical
latency, Windows and T-250 owner review remain separate gates.

**[T-287](Tickets/T-287.md) P1 validation Done (2026-11-23):**
[local fast-CI replay now rejects unmodeled workflow and job configuration](evidence/T-287-2026-11-23-workflow-envelope.md),
including alternate runners, root/job env/defaults, triggers, matrix/containers
and extra jobs. Fourteen fail-first negative cases were detected, and 50
focused/neighboring Python tests pass; the 46 live check scripts remain intact.
This is not a hosted beta4 CI pass or T-250 owner review.

**[T-286](Tickets/T-286.md) P1 validation Done (2026-11-23):**
[local fast-CI replay now rejects non-replayable step metadata](evidence/T-286-2026-11-23-ci-replay-metadata.md),
including unsupported working directory/environment, duplicate condition
keys and malformed YAML constructs. Fail-first caught eight violations;
47 focused and neighboring Python tests pass, with all 46 live workflow
checks still recognized. Hosted CI and T-250 owner signoff remain open.

**[T-285](Tickets/T-285.md) P1 implementation Done (2026-11-23):**
[repeat Godot beta4 Linux native export normalization](evidence/T-285-2026-11-23-reexport-normalization.md)
now accepts a second identical engine-emitted native library only after
exact-tree, stage-digest and ELF/PCK/native preflight, with final inspection
and late-error rollback. All 29 packaging and 45 neighboring Python checks
pass; hosted export templates and owner/Windows acceptance remain open.

**[T-284](Tickets/T-284.md) P1 validation Done (2026-11-23):**
[deterministic T-124 queued Brush predecessor under native mouse-up drain](evidence/T-284-2026-11-23-queued-brush-backlog.md)
uses 840 accepted input samples (more than the single synchronous release
budget), prevents a null-session fault injector crash and passes four 78-check
beta4 runs, real X11 20-check parity, and neighboring pending-edit checks.
The older hosted beta3 T-124 failure is not evidence of a beta4 production
regression; hosted CI and physical owner review remain unverified.

**[T-283](Tickets/T-283.md) P1 validation Done (2026-11-23):**
[T-137 native cold-preview/Redo fast-CI contract](evidence/T-283-2026-11-23-cold-preview-ci-contract.md)
now matches the 19-check settled Redo witness and preserves strict fail-closed
logs; real beta4 T-137 15/19 and adjacent T-086 153 checks pass. T-086
hardware/hosted-CI and T-250 owner acceptance remain open.

**[T-282](Tickets/T-282.md) P1 validation Done (2026-11-23):**
[native verified-source mixed flood-fill staging and complete-history witness](evidence/T-282-2026-11-23-verified-stage.md)
now passes 36/36 Rust-backed beta4 checks, retaining immutable-source,
fill-budget, stale-revision, signed-seam and unsafe-publication rules. Both
pixel-oracle mutation controls fail as expected; full hosted CI, T-068
performance/portability and T-250 owner signoff remain separate gates.

**[T-281](Tickets/T-281.md) P1 validation Done (2026-11-23):**
[native lazy flood-fill tile-cache committed-pixel/Undo/Redo witness](evidence/T-281-2026-11-23-native-fill-cache.md)
now passes 39/39 Rust-backed beta4 checks, including masked and unmasked
seams, exact hidden RGB, large signed native bounds and two mutation controls.
The independent verified-staging fill test remains red (8/29); T-068 and
hosted CI remain open. No T-250 owner acceptance is inferred.

**[T-280](Tickets/T-280.md) P1 validation Done (2026-11-23):**
[native axis-sweep Geometry2D full-region publication/Undo/Redo oracle](evidence/T-280-2026-11-23-axis-native-geometry.md)
now passes 241/241 Rust-backed beta4 checks across 34 directional/masked
sweeps; pixel/mask mutation controls fail as expected. Two independent
T-068 flood-fill witnesses still fail, so T-068 and hosted CI remain open.

**[T-279](Tickets/T-279.md) P1 validation Done (2026-11-23):**
[native T-068 stationary-dab Geometry2D oracle and signed publication witness](evidence/T-279-2026-11-23-dab-native-geometry.md)
now passes 112/112 Rust-backed beta4 checks with exact reference geometry,
committed RGBA8, full-region Undo/Redo and unsafe projection rejection.
The independent axis-sweep fixture still fails 34/137; T-068/hosted CI
remain unapproved.

**[T-278](Tickets/T-278.md) P1 validation Done (2026-11-23):**
[native T-068 tile-cache publication and signed anchor witness](evidence/T-278-2026-11-23-native-tile-cache.md)
now passes 38/38 real Rust-backed Godot beta4 checks with exact committed
RGBA8/Undo/Redo snapshots and rejected unsafe signed publication. The
separate T-068 geometry/sweep CI failures remain unresolved.

**[T-277](Tickets/T-277.md) P1 validation Done (2026-11-23):**
[required-native T-068 Skia live-oracle parity repair](evidence/T-277-2026-11-23-skia-native-oracle.md)
regenerates all 16 cases at legal signed anchors and matches the immutable
beta2 pixels/coverage exactly. Other T-068 native smokes remain red, so the
entire T-068/hosted-CI gate is **not** green.

# Ticket Kanban Index

**[T-276](Tickets/T-276.md) P1 validation Done (2026-11-23):**
[T-066 native-signed save/commit boundary CI fixture correction](evidence/T-276-2026-11-23-signed-ci-contract.md)
separates rejected unsafe direct edits from rejected corrupted cold saves;
97-check real Godot beta4 bundle test and adjacent native boundaries pass.
The wider hosted CI and T-250 owner gate remain open.

**[T-275](Tickets/T-275.md) P1 engineering Done (2026-11-23):**
[stale T-063/T-072 CI ticket-state assertions and narrow Canvas test repair](evidence/T-275-2026-11-23-workspace-ci-gates.md)
validated canonical manual-review dependencies without pretending T-056/T-065
are Ready or approved; real Godot beta4 T-063 X11 73-check witness passed.
**T-250 still requires explicit owner signoff**, and unrelated fast CI failures remain.

**[T-273](Tickets/T-273.md) P0 engineering Done (2026-11-23):**
[outer-right-edge dock toggle and chevron correction](evidence/T-273-2026-11-23-dock-edge.md)
passed standalone X11 92-check, Atlas 19-check, flyout 138/10-check witnesses;
real expanded/minimized/floating/HiDPI screenshots were **opened and reviewed**.
**[T-274](Tickets/T-274.md) P0 engineering Done (2026-11-23):**
[full-width native ColorPicker and opt-in exact RGBA8](evidence/T-274-2026-11-23-native-picker-composition.md)
validated real Drawing/Atlas pointer, scroll, colors/history and visual
inspection at expanded/minimized/floating/HiDPI. **T-250 is Manual Review**:
engineering prerequisites complete, but explicit owner signoff is absent.

**[T-272](Tickets/T-272.md) engineering Done (2026-11-23):**
[UI-only assertion cleanup and actual visual-inspection evidence](evidence/T-272-2026-11-23-visual-test-audit.md)
now has 50 passing X11 Drawing/Atlas witness logs (one historical Godot
ScrollContainer diagnostic), 33 passing Python contract tests, and strict
observed T-081/T-090/T-091 check floors. This removes cosmetic test oracles,
**not** the visible dock-toggle/ColorPicker defects or T-250 owner gate.

**[T-271](Tickets/T-271.md) engineering Done (2026-11-23):**
[required-native T-093 Object-source CI](evidence/T-271-2026-11-23-object-sources-ci.md)
now builds/imports Rust-backed Drawing and Atlas before the 56-check root
model, 27-check standalone X11 browser, 20-check File/Object UI and new
24-check Atlas published-source/open/identity/history witness. **T-065/T-059/T-250
owner acceptance and T-094/T-180 hosted review remain open.**

**[T-270](Tickets/T-270.md) engineering Done (2026-11-23):**
[T-091 required-native floating-dock CI](evidence/T-270-2026-11-23-floating-native-ci.md)
now builds/imports Rust-backed Drawing and Atlas before 44-check one-group,
53-check grip and 8-check Atlas Escape X11 witnesses. The clean
`make test-floating-dock` passes; **T-091 physical Windows/Linux, T-083/T-250
owner and T-094/T-180 hosted review remain open.**

**[T-269](Tickets/T-269.md) engineering Done (2026-11-22):** [Required-native T-089 layer on-demand CI](evidence/T-269-2026-11-22-native-layers-ci.md) now compiles/registers Rust and imports Drawing/Atlas before the 63-check hierarchy model, 36-check X11 row/framebuffer and new 27-check Atlas nested group/host history/Save/Open witnesses. Local `make test-layer-hierarchy` passes; **T-059/T-250 owner UX, T-094/T-180 hosted CI and physical review remain open.**

**T-268 engineering Done (2026-11-22):** [Required-native T-096 large-selection/Move CI](evidence/T-268-2026-11-22-large-move-ci.md) now builds/imports the Rust-backed Drawing/Atlas consumers, enforces 13,847-check model and 34-check X11 Move evidence, and adds 22-check Atlas signed masked Move/native history/Save/Open. The full `make test-large-move` passes locally; **T-096 stays Blocked on T-149, T-250 owner and T-094/T-180 hosted gates remain open.**

**T-267 engineering Done (2026-11-22):** [Native T-088 selection/contour on-demand CI](evidence/T-267-2026-11-22-native-selection-ci.md) now builds/imports both Rust-backed consumers before 52-check selection/Move, seven signed contour and T-253 dense Delete tests. Clean local `make test-selection-native` and Atlas dense history pass; **T-088/T-149, T-094/T-180 hosted acceptance and T-250 owner review remain open.**

**T-266 engineering Done (2026-11-22):** [Required-native T-086 viewport on-demand CI](evidence/T-266-2026-11-22-native-viewport-ci.md) builds/imports both Godot consumers before the X11 suite; native T-086 153/153 and T-137 19/19 now check real Hokusai preview/cold Redo settlement, with exact current-renderer RGBA8 hashes and preserved immutable historical baseline fixtures. **T-086 native display/physical acceptance, T-094/T-180 hosted CI and T-250 owner review remain open.**

**T-265 engineering Done (2026-11-22):** [Clipped document-tab close targeting](evidence/T-265-2026-11-22-document-tab-close.md) now delegates visible-tab identity to Godot rather than overlapping hidden `get_tab_rect` rectangles. Fail-first wrong-document close reproduced in standalone/Atlas; native X11 verifies dirty prompt, clean hidden-tab preservation, scroll, 100/150/200% and shared Atlas embedding. **T-059 and T-250 owner UX approval remain open.**

**T-264 engineering Done (2026-11-22):** [Right-dock mouse-up loss recovery](evidence/T-264-2026-11-22-dock-release.md) cancels stale icon/group/rail/flyout transfers when unpressed motion reports that the left button is gone; native standalone X11 and embedded Atlas tests preserve panel ownership and document history. **T-091 physical Windows/Linux, T-083 dock approval and T-250 owner review remain open.**

**T-263 engineering Done (2026-11-22):** [Explicit Bash for the T-262 live-stroke Make target](evidence/T-263-2026-11-22-make-bash-shell.md) removes dependence on `/bin/sh` supporting `pipefail`; a fail-first restricted-shell control, process-exit negative cases and the real native 81/81 + X11 144/144 Make run pass. **T-085/T-094/T-180 and T-250 remain open.**

**T-262 engineering Done (2026-11-22):** [T-085 required-native on-demand CI repair](evidence/T-262-2026-11-22-live-stroke-ci.md) pins Rust 1.99.1, builds/imports both Drawing and Atlas, runs 81/81 headless and 144/144 X11 held-preview checks with strict nine-burst coverage. `make test-live-stroke` and fail-first Python contracts pass locally. **T-085 physical p95, T-094 hosted CI and owner gates remain open.**

**T-261 engineering Done (2026-11-22):** [Interrupted native ColorPicker pointer gestures](evidence/T-261-2026-11-22-color-interruption.md) now roll back exact FG/BG on focus loss or missed mouse-up, fence stale `color_changed` and recover on the next press; keyboard-only colors settle. Fail-first standalone 8 failures and Atlas 3; corrected standalone 15/15, Atlas 10/10. **T-250 owner review and T-059 physical acceptance remain open.**

**T-260 engineering Done (2026-11-22):** [Floating-dock current-width regression](evidence/T-260-2026-11-22-dock-width-regression.md) updates T-081 native and Python assertions for the T-251 226px expanded width, 34px toggle gutter and 48px minimized rail; the strict X11 witness now passes 71/71. The clean-build on-demand workflow pins Rust and builds both native consumers. **T-250, T-083 and T-091 owner/physical gates remain open.**

**T-259 engineering Done (2026-11-22):** [Missed mouse-up without focus loss](evidence/T-259-2026-11-22-lost-release.md) no longer leaves floating move/resize or tab drag alive after a motion reports the left button released. Fail-first 13/28 standalone and 4/10 Atlas regressions; post-fix 28/28 and 10/10, with neighboring floating suites passing. **T-091 physical review and T-250/T-083 owner gates remain open.**

**T-258 Done (2026-11-22):** [Floating gesture focus-loss rollback](evidence/T-258-2026-11-22-focus-loss.md) cancels temporary move/resize and tab transfers if the OS eats a mouse-up. Fail-first standalone 13/25 and Atlas 4/9 failures, then native 30/30 and Atlas 9/9 pass; ten neighboring suites are green. **T-091 physical focus/window-manager review and T-250/T-083 gates stay open.**

**T-257 Done (2026-11-22):** [Floating move/resize Escape geometry rollback](evidence/T-257-2026-11-22-floating-cancel.md) restores the initial frame and suppresses stale release after cancellation; fail-first standalone 18/31 and Atlas 4/8 failures, now standalone 31/31 and Atlas 8/8 pass. Existing dock/float regressions remain green. **T-091 physical Windows/Linux validation and T-250/T-083 owner gates remain open.**

**T-256 Done (2026-11-22):** [Floating icon context menus](evidence/T-256-2026-11-22-floating-context.md) now cover inactive-tab RMB, focused Shift+F10/Menu, a grip-only group menu and clipped-tab-safe dispatch. Standalone X11 28/28, Atlas 9/9 and 11 neighboring native suites pass. **T-091 remains In Progress for physical-device validation; T-250/T-083 owner gates remain open.**

**T-255 Done (2026-11-22):** [Clipped floating-tab pointer hit testing](evidence/T-255-2026-11-22-clipped-floating-tabs.md) prevents invisible horizontal-scroll tabs from stealing grip/close clicks; fail-first native test 4/19 failed before, 22/22 after with two PNGs; Atlas 14/14, six neighboring native suites exit green. **T-091 remains In Progress for physical testing; T-250/T-083 owner approval remains open.**

**T-092 engineering Done (2026-11-22):** After T-226/T-252, the single
Colors/History/preferences implementation passes current native Godot 4.8
beta3 standalone model **66/66**, X11 **57/57** and Atlas-hosted
history/prefs **21/21**. A clean on-demand workflow now builds the required
Rust library before either consumer import; [current evidence](evidence/T-092-2026-11-22-current-native.md).
**No owner signoff:** T-250/T-059/T-056 remain open.

**T-090 engineering Done (2026-11-22):** current Godot 4.8 beta3 software-X11 responsive workspace 83/83, headless More 32/32, repaired T-063 dock-gutter scroll 75/75 and T-120 native menu regression; local cold `make build` imports both native consumers. The T-090 on-demand workflow now builds required Rust before import. [Evidence](evidence/T-090-2026-11-22-current-native.md). T-059/T-250 hardware UX approval stays open.


**T-087 engineering Done (2026-11-22):** Current Hokusai-only standalone
model 82/82, real-X11 framebuffer 104/104 and new Atlas-hosted frame/grid
15/15 verify independently visual image bounds, transparent checkerboard,
source-grid snapping and off-frame raster preservation at scaled Atlas
viewport sizes. [Evidence](evidence/T-087-2026-11-22-current-native.md).
**No physical/owner signoff:** T-059, T-250 and T-056 remain open.


**T-254 Done (2026-11-22):** [icon-only minimized flyouts](evidence/T-254-2026-11-22-flyout-icons.md) share the dock/floating icons, including fallback and focusable 42px tabs; clicked-tab RMB/Shift+F10, active no-op, Escape rollback, restart, 100/150/200% X11 and Atlas checks pass. Prior code fails 81 checks; corrected 183/183 X11 and 12/12 Atlas. **All P0 owner UX corrections T-251–T-254 are Done. T-250 is now Manual Review, not approved.**

**T-253 Done (2026-11-22):** [Dense Selection Delete input→frame repair](evidence/T-253-2026-11-22-dense-selection-delete.md): 71,901 occupied pixels / 512² image, clean fail-first X11 p95 **1,127ms→179ms** (7 trials); the same 500ms witness fails before, passes after, exact native tile history, signed RGBA8/hidden RGB and Atlas generation Save/Open verified. T-250 owner review remains Blocked, next P0 **T-254**.

**T-252 Done (2026-11-22):** [Settled native ColorPicker gestures](evidence/T-252-2026-11-22-recent-colors.md) now preview live without flooding recents; Restore previous chrome and Recent heading removed, compact FG/Swap/BG/recents preserved. Persist exact RGBA8 colors in an independent app-only setting; standalone X11/model, Atlas, prefs and neighboring regressions pass locally. T-250 remains Blocked pending T-253/T-254 and owner approval.

**OWNER UX OVERRIDE — 2026-11-22:** Actual Drawing build was **not approved**. **T-251, T-252, T-253, T-254 all Done for engineering fixes**; now **T-250 Manual Review** requires hands-on Drawing acceptance before any unfinished/future Atlas feature ticket can be Done. The owner PNGs are now in `docs/assets/drawing-ux-2026-11-22/` (remote `7b1fd306`). [Rejection/acceptance contract](DRAWING_UX_REVIEW_2026-11-22.md). Prior seven UX engineering tickets remain historical Done, not usability approval. Stop prioritizing optional history hardening/CI over this UX queue.

**T-249 Done (2026-11-22):** [Atlas context handler reservation](evidence/T-249-2026-11-22-context-handler-reservation.md) prevents synchronous command callbacks or listeners from replacing the context capture/restoration handlers mid-operation. The 84-check regression fails 42 cases on the prior code and passes after the fix; T-148, hosted CI and owner gates remain open.

**T-248 Done (2026-11-22):** [active-map reservation](evidence/T-248-2026-11-22-active-map-reservation.md) prevents synchronous Atlas history callbacks from rebinding the current edit target through direct or reflective property writes. The 70-check fixture fails 14 cases on the prior code and passes after the fix; T-148, hosted CI, and owner gates remain open.

**T-247 Done (2026-11-22):** [Atlas changed-notification reservation](evidence/T-247-2026-11-22-atlas-notifications.md) prevents reentrant commands, Undo/Redo, reset and dirty/savepoint changes during synchronous history observers. The 259-check fixture fails 124 cases on the previous code and passes after the fix; T-148 and owner/hosted gates stay open.

**T-246 Done (2026-11-22):** [ordinary Atlas command reservation](evidence/T-246-2026-11-22-atlas-command-reservation.md) blocks reentrant host commands, Undo/Redo, reset and checkpoint writes during context capture, asset/transfer apply and synchronous history observers. A 206-check test fails 60 cases on old code and passes after the fix. T-148 remains In Progress, T-149 Blocked; hosted and owner gates remain open.

**T-244 Done (2026-11-22):** [pending script-session history handoff guard](evidence/T-244-2026-11-22-pending-session-handoff.md) reserves local/Atlas history before a GDScript edit stages pixels or attaches Rust. Fail-first controls reject 7/50 standalone and 9/18 real Atlas checks on the old code; both pass after the weak-session guard. T-148 remains In Progress; hosted/owner gates remain open.

**T-243 Done (2026-11-22):** [active native history handoff fence](evidence/T-243-2026-11-22-active-history-handoff.md) prevents switching between local and Atlas history while a Rust tile edit is active. The 40-check fixture fails 10 checks on the old code/binary, then passes 40/40 after the fix; cancellation restores legitimate transitions and native/Atlas history regressions remain green. T-148 remains In Progress, with hosted and owner gates open.

**Current as of 2026-11-22.** This is the **authoritative active navigation**, synchronized with `docs/Tickets/T-*.md` frontmatter. The old chronological 3,119-line engineering journal is preserved at [Index-History-2026-11-15.md](Index-History-2026-11-15.md). Past narrative status or performance recommendations are source-pinned history, not present acceptance. Review [ticket workflow, prerequisites and manual gates](TICKET_WORKFLOW.md) before implementation.

**Owner-directed sprint priority (2026-11-20; [scope/conflict audit](DRAWING_UX_REVIEW_2026-11-20.md)):** **#1 T-221 P0 Done** (sparse Delete diagnosis and fix; hardware owner recheck still open), **#2 T-222 P0 Done** (half-circle and tested icon semantics), **#3 T-226 P0 Done** (FG/BG + inline scrollable native picker), **#4 T-223 P0 Done** (group marker/whole-group drag), **#5 T-224 P0 Done** (icon-proximity grouping, explicit drop hints and rollback tested), **#6 T-225 P1 Done** (shared floating icon tabs), **#7 T-227 P1 Done** (compact native preview grid and mapped dab-density control). New tickets take precedence over non-blocking cosmetic/backlog work, **not** over correctness/urgent CI gates or T-148's independent native architecture obligations. T-083/T-088/T-092 and physical review remain unapproved.

**T-242 Done (2026-11-22):** [read-only history owner property](evidence/T-242-2026-11-22-history-owner-property.md) closes the public Boolean write bypass of T-241. The standalone and real Atlas timeline fail-first controls reject 10/25 and 9/18 assertions on old code, then pass 25/25 and 18/18 after the fix. T-148 remains In Progress, and the owner/hosted gates are unchanged.

**T-241 Done (2026-11-22):** [host-owned history transition fence](evidence/T-241-2026-11-22-host-history-owner.md) prevents a populated external/Atlas command timeline from being silently replaced by local history after host edits, without blocking pristine mode selection. A 29-check regression fails 6 checks on the old implementation and passes after the fix; native/Atlas neighbors pass. T-148 and owner gates remain open.

**T-240 Done (2026-11-22):** [native FFI whole-batch payload preflight](evidence/T-240-2026-11-22-ffi-payload-preflight.md) checks all lengths, coordinates and duplicate IDs before copying any tile buffers for adoption or history. The 32-check witness fails four checks on the prior binary, then passes; Rust, native-X11 and Atlas neighbors pass. T-148 remains In Progress and T-149/hosted/owner gates stay open.

**T-239 Done (2026-11-22):** [retained native history-order fence](evidence/T-239-2026-11-22-native-history-order.md) prevents an older *still-retained* host Undo/Redo token from falling through to detached replay and clearing unrelated Rust history. The 36-check native witness fails 10 checks on the prior document code, passes after the fix, and preserves genuine eviction fallback. T-148 and hosted/owner gates remain open.

**T-238 Done (2026-11-22):** [native Brush source-byte reentrancy guard](evidence/T-238-2026-11-22-brush-source-reentrancy.md) checks previously resolved tile RGBA8 again after later lazy callbacks, rejecting in-place mutation despite unchanged tile identity/revision. A real-native 18-check witness fails twice on the prior code and passes with the fix; standalone, Atlas history and native-X11 neighbors pass. T-148 and hosted/owner gates remain open.

**T-237 Done (2026-11-22):** [detached native history whole-payload preflight](evidence/T-237-2026-11-22-detached-history-preflight.md) rejects malformed later tile keys/buffers before lazy callbacks and detects mid-callback delta changes before consuming a Rust history token. The final 40-check test fails 24 checks against the previous implementation, then passes; native/Atlas replay neighbors remain green. T-148 and hosted/physical gates remain open.

**T-236 Done (2026-11-22):** [direct pixel-map preflight](evidence/T-236-2026-11-22-pixel-map-preflight.md) freezes and validates complete before/after maps ahead of lazy source callbacks, then rejects reentrant pixel-map edits and in-place resident tile-byte mutation. The unchanged-code regression fails 16/35, while the fixed 35-check test, T-068 smoke correction, native/Atlas publication suites and required-native CI contract pass. T-148 remains In Progress, with T-149 and physical/hosted gates unapproved.

**T-235 Done (2026-11-22):** [tile-local patch preflight](evidence/T-235-2026-11-22-tile-patch-preflight.md) freezes complete direct tile patch descriptors before lazy callbacks, then rejects reentrant descriptor/source-byte mutation before Rust adoption. The unchanged-code regression fails 17/34 and passes 34/34 after the fix; native/Atlas regression checks pass. T-148 remains In Progress, and T-149/physical/hosted gates remain open.

**T-234 Done (2026-11-22):** [native Brush publication preflight](evidence/T-234-2026-11-22-publication-preflight.md) validates the entire stride-sensitive 128-tile/256 MiB descriptor set before lazy source callbacks and rejects reentrant input changes. The expanded fail-first control found 13 failures; the 32-check final test and native/Atlas/X11 neighbors pass. T-148 remains In Progress; T-149 and physical/hosted gates remain open.

**T-233 Done (2026-11-22):** [first direct pixel-map native authority](evidence/T-233-2026-11-22-pixel-bootstrap.md) extends the T-232 provisional Rust adoption to the ordinary direct/mixed pixel publisher. The fail-first test found 12 defects; the expanded 37-check test, T-100 and T-095 pixel oracles, historical T-156/T-230 recovery, Atlas, Rust and native-X11 validation pass. T-148 still needs the remaining raster producers and host-owned command lifetime; T-149 and physical/hosted gates remain open.

**T-231 Done (2026-11-22):** [stride-aware native direct-edit budget](evidence/T-231-2026-11-22-direct-budget.md) rejects 6×2048px or 129×64px external pixel/tile edits before lazy callbacks and Rust buffer copies, with 8 fail-first failures, 24 post-fix checks, signed exact-RGBA8 history and Atlas/X11 regression coverage. T-148 and hosted/owner gates remain open.

**T-230 Done (2026-11-22):** [detached legacy pixel history native bootstrap](evidence/T-230-2026-11-22-detached-pixel-bootstrap.md) routes the first local/Atlas per-pixel Undo/Redo into checked Rust history even with no previously attached store; 8 fail-first checks, 33 final tests and native-history/Atlas/Object regression evidence. The host-owned detached timeline and other non-Brush raster producers remain T-148 work; T-149 and hardware/hosted CI gates remain open.

**T-229 Done (2026-11-22):** [stride-aware native history budget](evidence/T-229-2026-11-22-history-budget.md) rejects oversized full-tile Undo/Redo envelopes before lazy source calls and native byte copies; Rust/standalone/Atlas and X11 regression checks pass. **T-148 remains In Progress** for universal canonical history/raster ownership; T-149 remains Blocked.

**T-228 Done (2026-11-22):** [local PR #22 strict CI-staging and docking-contract repair](evidence/T-228-2026-11-22-fast-ci-layout.md) keeps the whole staged project out of the exact Linux release distribution and fixes the stale literal T-083 dependency assertion; local packaging, release-gate and roadmap tests pass. **T-106 remains In Progress until exact-head hosted CI passes**, with T-180 portability gates and T-083 owner UX review still open.

**T-221 Done (2026-11-22):** [Selection Delete input-to-render diagnosis and fix](evidence/T-221-2026-11-22-selection-delete.md) replaces an O(marquee area) full-pixel clear with a sparse occupied-tile clear; native X11 Delete p50 1,212.5 ms → 21.3 ms (7 matched trials, framebuffer and Undo checked), Ctrl+D remains non-dirty. Standalone/Atlas native history, hidden RGB, Save/Open and selection suites pass. **T-222 is also Done (2026-11-22):** [compact dock interaction evidence](evidence/T-222-2026-11-22-dock-interactions.md) covers the vector overlay, expanded/rail LMB/RMB, keyboard menu, transactional drag guard, 100/150/200% scaling, native framebuffer and Atlas-host tests. **T-226 is Done (2026-11-22):** [inline picker Colors evidence](evidence/T-226-2026-11-22-inline-colors.md) covers role selection, RGBA8 history filtering, 190px/HiDPI scroll, direct picker pointer and Atlas campaign Save/Open. **T-223 is Done (2026-11-22):** [narrow vector group-marker evidence](evidence/T-223-2026-11-22-group-marker.md) covers collapse vs whole-group drag, RMB/keyboard menu, 150–200% scaling, restart, and Atlas embedding. **T-224 is Done (2026-11-22):** [icon-proximity drop evidence](evidence/T-224-2026-11-22-icon-proximity.md) covers single-icon merge vs group-marker drag, blue/green/amber previews, invalid-body drop rollback, horizontal autoscroll, exact restart, native X11 and Atlas floating host. **T-225 is Done (2026-11-22):** [floating icon tab evidence](evidence/T-225-2026-11-22-floating-icons.md) covers shared SVG/fallback identity, focus-safe icon actions, one-group grip, hide/reopen, restart, scaling and Atlas embedding. **T-227 is Done (2026-11-22):** [compact Brushes native evidence](evidence/T-227-2026-11-22-compact-brushes.md) maps bounded dabs/actual radius into Hokusai, verifies native pigment/96px/gesture freezing, 150–200% scaling and Atlas. Owner hardware review remains unapproved; no other owner-queue ticket is Ready. T-088/T-059 owner physical review, T-149 and hosted CI remain open.

**Implementation agent handoff for [Sprint 2026-11-15 / PR #19](SPRINT_2026-11-15_HANDOFF.md):** The original plan started with T-146 (real 96px Hokusai hard-round pointer benchmark). **T-146 is now Done** with [strict native X11 benchmark evidence](evidence/T-146-2026-11-15-hokusai-benchmark.md). T-147 has also completed its single native stroke ABI. **T-153 Done (2026-11-16): NativeHard deleted; Brush/Eraser now always use Hokusai presets, including Hard Round.** **T-148 is In Progress:** native tile storage, atomic brush transactions, the production Canvas tile-only Brush/Eraser path and **per-document persistent tile/history ownership**, plus **bounded atomic import of ordinary external raster edits**, pass real graphical/headless tests. **T-148 remains open:** checked revision bridges now preserve native brush history through layer/semantic-object edits and structural removal/restore of semantic trees, never-imported raster layers **and now locally recorded native-owned raster subtrees**, plus source-preserving **detached subtree imports and text-to-raster conversion** when their raster IDs are new to Rust. Unrecorded native-owned removals now use checked selective retirement; Atlas global native Brush commands retain their tile snapshots and Rust history tokens through Undo/Redo, and a real native-authored Atlas campaign generation Save/Open is verified. A real native-authored Object Editor draft now passes Save, Save As, linked-instance rendering, registry reload and portable Object export regression. History replay now rejects reentrant lazy-source revision, permission and source-identity changes before Rust Undo/Redo or detached publication; **Rust also verifies the complete native-token before/after RGBA8 payload before replay**; in-sync detached replay now applies source tiles atomically in Rust and invalidates obsolete native tokens, while absent/stale native stores still use a Godot snapshot fallback; remaining Object/Atlas raster producers and universal revision ownership remain open. **T-154 Done:** previously painted text/raster Undo/Redo now parks and restores native-owned glyph tiles and retains unrelated Rust Undo/Redo tokens with checked snapshot parity. **T-155 Done:** semantic edits followed by re-rasterization now selectively replace parked native glyph sources while retaining unrelated Rust Ink/Undo authority. **T-156 Done:** older pixel-map local/Atlas Undo/Redo now uses checked native whole-tile replay once Rust is attached; the broader host-owned history gate remains. Finish universal authority before opening T-149; see [mixed raster evidence](evidence/T-148-2026-11-15-mixed-raster.md) and [semantic subtree evidence](evidence/T-148-2026-11-15-semantic-subtrees.md), [unreferenced raster evidence](evidence/T-148-2026-11-15-unreferenced-raster.md) and [native-owned subtree evidence](evidence/T-148-2026-11-15-parked-subtrees.md) and [import bridge evidence](evidence/T-148-2026-11-15-import-subtree.md) and [text conversion evidence](evidence/T-148-2026-11-15-text-raster.md).

**Toolchain implementation T-180:** [System/native GUI, cold offline and identical Arch/Ubuntu bundle builds](evidence/T-180-2026-11-17-local-validation.md) pass; artifact is 251.281285 MiB, zstd-19, internal checksums, no repository or external sidecar. The dedicated hosted toolchain workflow is **green**. **In Progress:** four retained desktop native-transition/export failures (42/46). The upload cap is 500 MiB. T-148/T-149 dependency gates and T-095/T-105 manual/portability acceptance remain open.

**T-198 Done (2026-11-19):** [strict gesture-local matched callback-gap profiler](evidence/T-198-2026-11-19-matched-callbacks.md) distinguishes 541 confirmed adjacent Canvas periods (none ≥83.333ms) from 19 long *global* callback gaps across four retained real-workspace trials. There are 251 unmatched Canvas adjacencies; **neither smooth physical FPS nor the 200ms gesture-tail target has been established**. [T-197](Tickets/T-197.md) remains In Progress.

**T-199 Done (2026-11-19):** [separate Canvas redraw-end cadence instrumentation](evidence/T-199-2026-11-19-canvas-cadence.md) covers all **792** adjacent Canvas draw submissions in the four retained processes (including **251** that lack paired renderer callbacks), with no observed ≥83.333ms redraw gaps; a fresh zero-exit native workspace process adds 198 valid intervals, 92 without paired callbacks. **This measures Canvas redraw submissions only**, not unsampled display frames, physical scanout, sustained FPS or the 200ms 100-event p95 target. T-197 remains In Progress.

**T-200 Done (2026-11-19):** [native Hokusai references for four historical T-095 profiling smokes](evidence/T-200-2026-11-19-native-profiler-oracle.md) replace obsolete `paint_path` byte oracles after native consolidation and require real changed-preview callback attribution. All four retained telemetry/Undo suites pass **three independent native-X11 runs each (86 checks per run)**, with changed-pigment/width negative controls. This repairs test evidence only; it does not satisfy T-197's 200ms/continuous-FPS targets or T-095's owner gate.

**T-202 Done (2026-11-19):** [T-066 signed campaign-save regression repaired](evidence/T-202-2026-11-19-signed-save-fixture.md): the old >2^53 fixture cannot be persisted after T-158/T-159 native projection safety. A legal near-±2^52 sparse hidden-RGB save/open passes; the historical out-of-range edit is now explicitly rejected without modifying the published generation. Existing root storage/editor and native signed-source suites pass; **hosted CI is not yet rerun**. T-106 and T-180 stay open.

**T-220 Done (2026-11-19):** [packed binary project identity validation](evidence/T-220-2026-11-19-packed-project-identity.md) parses the actual Godot `ECFG` application name and startup scene instead of accepting `ECFG` magic alone. Twelve fail-first false accepts now reject, a foreign pack cannot install the native `.so`, and the real 528-resource export passes isolated native ABI/boot. Hosted/Windows/owner gates stay open.

**T-219 Done (2026-11-19):** [canonical Godot PCK resource-name validation](evidence/T-219-2026-11-19-pck-names.md) rejects embedded NULs, excess alignment padding and control bytes before native packaging. Six fail-first failures now pass; a UTF-8 positive case, unchanged rejected export bytes and the real 528-resource native ABI launch are verified. Hosted CI, Windows and physical owner gates remain open.

**T-218 Done (2026-11-19):** [complete Godot PCK payload integrity and non-overlap check](evidence/T-218-2026-11-19-pck-payload.md) verifies MD5 for every indexed resource and disjoint nonempty extents, not only startup/native witnesses. Five fail-first checks now pass; native packaging refuses corrupted optional assets without publication. The real 528-resource PCK still passes isolated native ABI/boot. This is not authenticity, official release-template, hosted CI, Windows, performance, or owner acceptance.

**T-217 Done (2026-11-19):** [Godot 4.8 PCK v4 startup/native resource inventory](evidence/T-217-2026-11-19-pck-index.md) prevents an unrelated `GDPC`-prefixed pack from passing Linux native export preflight. It validates bounded directory entries, native ABI manifest, compiled remaps and essential payload MD5 checks, preserves Windows structural-only status, and passes the real 528-entry PCK isolated launch. Hosted official-template, Windows-runtime and owner gates remain open.

**T-216 Done (2026-11-19):** [effective standalone Drawing project identity and startup scene validation](evidence/T-216-2026-11-19-project-identity.md) rejects comments/other sections, duplicate application settings and unrelated startup scenes before native packaging. Six fail-first cases now reject atomically; real 522-file stage, existing native ABI launch, 71 configured Python and 35 Rust tests pass. Hosted Windows/export-template and owner gates remain open.

**T-215 Done (2026-11-19):** [strict native source-stage inventory](evidence/T-215-2026-11-19-stage-inventory.md) now rejects undeclared empty directories and FIFO/socket nodes before native Linux packaging, matching the final export inspector. Five fail-first failures, 18 package tests, 70 configured Python tests, 35 Rust tests and a real PCK/native ABI launch pass; hosted/export-template and owner gates remain open.

**T-214 Done (2026-11-19):** [ownership-safe native export temp cleanup](evidence/T-214-2026-11-19-temp-ownership.md) removes the fixed `.so.tmp` cleanup path that could delete foreign bytes or symlinks during preflight rejection. Three fail-first failures are now guarded by an exclusive temporary allocation, mode preservation and a copy-interruption rollback test. All 13 packaging, configured Python/Rust, and real packed-app ABI checks pass; hosted/export-template and owner gates remain open.

**T-213 Done (2026-11-19):** [strict exact-tree export inventory](evidence/T-213-2026-11-19-export-entries.md) now rejects unexpected empty folders and non-regular filesystem nodes (including FIFOs) in native Linux and structural Windows exports. Six fail-first cases, 15 release/package tests, real beta3 native launch and configured Python/Rust checks pass. Official templates, hosted CI and physical review remain open.

**T-212 Done (2026-11-19):** [atomic required-native Linux export packaging](evidence/T-212-2026-11-19-native-export-atomic.md) preflights the exact ELF/PCK/`.so` projection before publishing a library, and removes newly installed bytes if final inspection rejects. Two fail-first leak cases now pass; actual Godot beta3 packed-app isolated native ABI and boot pass. This is a Linux packaging integrity improvement, **not** an official release-template, hosted CI, Windows or owner acceptance. T-180/T-105 remain open.

**T-211 Done (2026-11-19):** [required-native T-095 CI check migration](evidence/T-211-2026-11-19-required-native-ci.md) removes three un-runnable scripted-bridge tests and replaces the fast-desktop stub check with real 57-check Hokusai rollback, 24-check signed lazy tile and 39-check signed replay; the optional native workflow retains its existing coverage and now runs a strict 56-check document-tile publication witness. The existing required step IDs and fail-late verifier are unchanged. This is **local**, not a new hosted green T-106/T-180 run or a T-095 owner signoff.

**T-210 Done (2026-11-19):** [T-088 native selection/clipboard/Move graphical fixture](evidence/T-210-2026-11-19-native-selection.md) now passes **52/52 ×4 native-X11** with strict markers (formerly **24/51 failures**). A real 24px Hokusai footprint, native Eraser alpha/hidden-RGB semantics and byte-exact translated mask-edge evidence replace obsolete 1px/full-clear assumptions. T-088 remains In Progress for T-149 and owner UX; no production code or approval changed.

**T-209 Done (2026-11-19):** [T-129 required-native layer/clipboard pending-source regression](evidence/T-209-2026-11-19-native-content-edit.md) replaces two obsolete fixed-two-frame pending assertions with pending-**or-both-committed** checks on source revision and History cursor. The original **2/35 failure** is retained; all **35 checks pass ×4 headless and ×2 native-X11** with strict markers. All 7 neighboring queue/history cases and three layer/clipboard model/native cases pass; the historical T-088 native selection/clipboard X11 witness was red independently at that checkpoint (subsequently repaired by T-210). T-095, hosted CI, and native-transition gates stay open; no production code changed.

**T-208 Done (2026-11-19):** [T-128 native History-list guard fixture repaired](evidence/T-208-2026-11-19-native-history-list.md): two 3px stationary dabs were not valid native Undo candidates, and a two-frame pending-only assertion rejected legal complete publication. The unchanged 37-check safety oracle now passes **37/37 ×4 headless and ×2 X11**; backward/forward list guards, row restoration, exact RGBA8 History replay and Save/Open remain verified. T-129's separate **2/35** historical regression was subsequently repaired by T-209; hosted CI/owner gates remain open. No production code changed.

**T-207 Done (2026-11-19):** [T-127 required-native pending history regression repair](evidence/T-207-2026-11-19-native-history-oracle.md) replaces the unpainted 3px stationary Legacy dab and two-frame pending assumption with a real 24px Hokusai stroke and pending-or-**fully committed** checks on revision and cursor. Headless **40/40 ×4**, software-X11 **40/40 ×2**, strict markers and 4 Python CI contracts pass. The historical T-128 failure (8/37) was subsequently repaired by T-208; T-129 baseline (2/35) was subsequently repaired by T-209; T-095 hardware and hosted CI gates remain open. No production painting code changed.

**T-205 Done (2026-11-19):** [T-130 native completion-safe source-context regression](evidence/T-205-2026-11-19-source-context-timing.md) fixes the stale assertion that both queued gestures must still be pending after exactly two frames. The 34-check suite now accepts only unchanged selection plus either still-pending paint or **both** committed transactions; headless **34/34 ×4**, X11 **34/34 ×2**. The T-124 and T-127 historical test failures are now repaired by T-206 and T-207; T-128 fixture is repaired under T-208; T-129 was subsequently repaired by T-209. No production/performance or owner acceptance claim.

**T-206 Done (2026-11-19):** [T-124 native queued-gesture oracle repair](evidence/T-206-2026-11-19-native-queue-oracle.md) replaces retired `paint_path` comparisons with independent source/time-identical Hokusai replay. Both released-before-promotion and held-promotion Brush/Eraser paths, exact canonical RGBA8, separate Undo/Redo history, bounded overflow and failed-predecessor behavior pass **78/78 ×4 headless; 20/20 ×3 native-X11**. The changed-width negative control detects a wrong source transaction. T-127 is repaired by T-207; T-128 historical regression is repaired under T-208; T-129 regression is repaired by T-209; CI/physical-review gates stay open.

**T-204 Done (2026-11-19):** [T-085 required-native live stroke queue and cancellation fixture repair](evidence/T-204-2026-11-19-native-live-stroke.md) replaces legacy full-path Brush byte oracle with same-source/time Hokusai replay, uses real native-sized mask strokes and fixes an illegal layer creation inside an open transaction. Headless **81/81 ×4**, native-X11 **144/144 ×4**, including nine 840-point loops per native run. These are simulated/raw-X11 inputs, not physical FPS, hosted CI or T-085 owner acceptance. T-085/T-106/T-180 stay open.

**T-203 Done (2026-11-19):** [T-087 required-native image-frame test repair](evidence/T-203-2026-11-19-native-image-frame.md) replaces old 1px stationary Legacy Brush oracles with real swept Hokusai events and source/Undo evidence. Headless **82/82 ×6** and native-X11 framebuffer **104/104 ×4**; unchanged CI markers, no production painting change. T-087/T-180/T-106 and hardware/manual gates remain open.

**T-201 Done (2026-11-19):** [required-native Linux standalone package and fail-closed export gate](evidence/T-201-2026-11-19-linux-native-export.md) replaces the obsolete native-absent ELF/PCK inspection, verifies the Rust GDExtension and two isolated launches, and updates T-105 Linux residency/desktop and on-demand CI. **Official export templates are not installed locally**; the real exported-PCK/native-ABI witness uses the supplied editor binary as a surrogate. Hosted official release, Windows native/export, T-180/T-105/CI, and T-095/T-197 physical gates remain open.

**Sprint 2026-11-17:** PR #20 was squash-merged into `main` at
`8f45f1a84bcc28b87d1b50f4bacfa173de653733`; continue on `sprint/2026-11-17`.
New owner testing reports mismatched preset hardness, requests a separate visual
brush/parameter panel, and observes roughly 12 FPS while drawing. [T-183](Tickets/T-183.md) is Done (preset edge/opacity behavior corrected and
profiled); [T-184](Tickets/T-184.md) is Done (native-backed visual Brushes dock);
[T-185](Tickets/T-185.md) is Done: [four valid full-workspace native X11
processes (32 gestures), two retained incomplete exits, frame p95/long-frame
and 100-event rapid fill baselines](evidence/T-185-2026-11-17-current-workspace-profile.md).
[T-186](Tickets/T-186.md) is Done for [one bounded exact-dirty native preview
optimization](evidence/T-186-2026-11-17-exact-native-dirty-preview.md):
54% cold composition 755→270ms, frame p95 123→71ms, warm-tile correctness
retained. The 100-event rapid 96px p50 remains 517ms cold / 613ms warm,
**above the 250/200ms target**; [T-187](Tickets/T-187.md) is Done for
[one measured direct-native single-layer preview path](evidence/T-187-2026-11-17-direct-native-preview.md):
matched pooled cold rapid p50/p95 662/742→343/383ms, warm 553/598→344/358ms, and full-workspace
54% cold composition CPU 299→2.8ms with 99/99 final graphical parity/cache
checks. The pinned 100-event metric still **misses 250/200ms**, now tracked
by [T-188](Tickets/T-188.md) (Done) for [run-aware native delta grouping](evidence/T-188-2026-11-17-run-aware-native-staging.md):
final same-native rapid cold p50/p95 388/494→266/422ms, warm
358/450→286/297ms, with exact native source/history parity and 63/63
new graphical checks. [T-189](Tickets/T-189.md) is now Done for
[per-native-storage-tile immutable source lookups](evidence/T-189-2026-11-17-native-source-read.md):
reversed-order same-binary rapid pooled cold full-gesture p50/p95
339/364→282/390ms, warm 297/337→273/281ms, with 77 graphical and
29 Rust tests. Tile-stage CPU consistently falls, but cold tail and real
workspace release/frame pacing remain mixed. [T-190](Tickets/T-190.md) is now Done for [bounded exact sRGB8 native export](evidence/T-190-2026-11-17-srgb-byte-quantization.md):
30 native Rust tests and 77 graphical parity checks; final same-binary rapid warm p50/p95 347/423→232/240ms in pair 1 and 297/335→261/282ms in pair 2, while cold pair 2 regressed. Full-workspace frame/release is mixed. [T-191](Tickets/T-191.md) is now Done for [one bounded unchanged-native-row scan](evidence/T-191-2026-11-17-native-row-scan.md): 31 Rust tests and 77 same-binary graphical parity checks, 2 reversed-order 100-event rapid A/B pairs and 4 confirmed full-workspace processes. Native row comparisons bypass unchanged pixels, but stage CPU, frame and release tails remain mixed. The **250ms/200ms whole-gesture targets are not reliably met**. [T-192](Tickets/T-192.md) is Done for [reuse of the native rollback write journal as exact dirty candidates](evidence/T-192-2026-11-17-native-dirty-journal.md): 2,134→0 redundant native dirty-set insertion attempts, 32 Rust tests, 81 graphical parity checks and two reversed-order rapid/workspace comparison pairs. Frame, warm and release timings remain variable; [T-193](Tickets/T-193.md) is Done for [32-slot batch-local journal hints](evidence/T-193-2026-11-17-native-journal-hint.md): 1,840/2,134 native membership probes avoided, 34 Rust and 83 graphical checks, two reversed-order rapid pairs and four confirmed full-workspace processes. **Frame, release and complete-gesture timing are mixed or worse**. [T-194](Tickets/T-194.md) is Done for a [measured 20-segment native batch cap](evidence/T-194-2026-11-17-native-batch-cadence.md): two reversed-order same-binary pairs, cold/warm rapid p95 343/320→240/240ms, with exact source parity, 79 graphical checks and preserved 6ms soft stage deadline. This meets the **250ms rapid software-X11 milestone in the measured small sample**, not the 200ms stretch goal, sustained frame-tail target, or physical hardware acceptance; [T-195](Tickets/T-195.md) is Done for a [release-only second 6ms-bounded drain](evidence/T-195-2026-11-17-release-catchup.md): 85 graphical checks, two reversed-order same-binary rapid/workspace A/B pairs, and full `make check`/11-suite graphical passes. Pooled strict 100-event cold p50/p95 239/304→215/253ms, warm 228/278→201/209ms; the **200ms stretch and paced frame tails remain open**. [T-196](Tickets/T-196.md) is Done for [a deep-backlog-only idle-deferred release drain](evidence/T-196-2026-11-17-deferred-backlog-drain.md): same-binary strict 100-event cold p50/p95 204/215→183/227ms, warm 193/217→192/205ms (n=4 each), a 99-check graphical parity/cancel test, and four valid 54%/100% full-workspace processes with no deferred work on ordinary short gestures. First-preview samples and paced frame tails are not consistently better; the **200ms p95 stretch and T-095 physical owner acceptance remain open** under [T-197](Tickets/T-197.md), now **In Progress**: [a matched-renderer-callback regression and two valid full-workspace profiles](evidence/T-197-2026-11-18-preview-callback.md) expose 79–92ms cumulative Eraser fallback composition; no p95 or FPS improvement has been claimed.

## Current alpha architecture — Rust-owned raster

**Owner decision (updated 2026-11-16):** keep the completed 96px Hokusai hard-round benchmark as the baseline, **remove NativeHard entirely** under T-153, and use Hokusai/libmypaint presets as the **only** native Brush/Eraser rasterizer in the existing Rust GDExtension, move canonical raster tiles, blending, masks, staging, rollback and undo data **out of GDScript**, connect Godot through **batched stroke commands → native-owned dirty tile/byte buffers**, and **delete Legacy** (no compatibility, native-free fallback or migration required in alpha). Godot retains workspace, tools/input reception, layer/metadata UI and GPU texture submission; Rust owns painting. Hokusai is **not required to match Legacy pixel geometry**. Only after retiring Legacy should the new pipeline be reprofiled and its measured dominant bottleneck optimized.

**Do not close the integration/acceptance parents** T-095 (physical 60/96px Brush responsiveness and explicit owner approval), T-068 (native portability and measured full-editor throughput), T-086 (hardware viewport performance), T-088/T-096 (selection/Move acceptance), or T-094 (hosted CI and owner matrix) solely from a passing refactor. Completion of T-104 or the historic 46-step tests never restores GDScript as the target backend.

**T-153 complete:** [Hokusai-only Brush](Tickets/T-153.md) verified; [execution evidence](evidence/T-153-2026-11-16-hokusai-only.md). For the **native architecture chain**, T-148 remains the next dependency-ordered engineering gate; the separate **owner-directed 2026-11-20 UI/performance sprint** is prioritized above non-blocking polish. T-148 remains In Progress for universal native tile/history authority; T-154 preserves previous text/raster Undo/Redo, T-155 selectively replaces obsolete parked glyph sources on a new text conversion, T-156 replays previously host-owned pixel-map commands via checked native tiles once Rust is attached, T-157 guards lazy materialization against reentrant source replacement, and T-158 rejects unsafe signed lazy/manifest tile coordinates before persistence. T-159 closes the signed-overflow validation in native publication and pixel/native history replay; T-160 also rejects unsafe *direct* pixel/tile edits once Rust is attached, without breaking legacy non-native signed-64-bit fixtures. T-161 closes the remaining `abs(INT64_MIN)` and pre-addition overflow holes at public gesture, viewport and image-import anchors; historical ±2^60 endpoints are unchanged. T-162 keeps direct raster edits with `record_history=false` native-authoritative when Rust is already attached, without inventing Undo tokens. T-163 rejects overflowing clipboard capture rectangles before materializing any source. T-164 rejects image imports whose last pixel crosses the public signed document boundary, before creating an edit transaction. T-165 prevents any direct pixel/tile publisher from bypassing a divergent attached Rust revision, including reentrant lazy fetches; explicit rebase remains a separate recovery step. T-166 now rejects manifest export and save acknowledgements when authorized Godot tile bytes or the attached Rust revision differ, without silently certifying stale pixels. T-167 extends the same checked boundary to the low-level dirty save snapshot, returning an explicit `DrawingResult` rather than exposing unchecked tile bytes. T-168 now rejects native-owned raster subtree deletion before mutating Godot when Rust refuses the parked, retired or unreferenced revision bridge. T-169 also rejects raster subtree import before Godot publication if the attached native revision or bounded unreferenced-layer bridge fails; no more silent Godot-only fallback for busy, ahead or oversized native imports. T-170 now preflights the *source* native retirement and exact RGBA8 before either cross-document move implementation publishes the destination, preventing ordinary busy/stale-source half-moves. T-171 now fences direct detached subtree export and Copy (standalone or Atlas) against stale attached native revisions and in-place source bytes, including lazy callback mutation. T-174 now makes public object add/move, semantic text commits and density updates fail closed before native-attached metadata rejection. T-177 now makes local raster-bearing structural Undo/Redo acquire a checked parked/unreferenced Rust revision before mutating the Godot tree, rejecting busy/stale or retained-source replays atomically. T-178 now also acquires checked native metadata before semantic text-history Undo/Redo, rejecting busy and stale stores without detaching canonical raster source. T-178 now also acquires the checked native metadata revision before local semantic text creation/edit Undo/Redo, preserving Rust source and the local history cursor on rejection. T-179 now also rejects semantic-only subtree deletion **before Godot erasure** if the attached Rust metadata revision is busy or divergent, preserving native history across recorded, unrecorded and host-owned removals. The rest of the native migration is sequenced by hard dependencies. See [architecture and ticket audit](NATIVE_RASTER_TICKET_AUDIT_2026-11-15.md) for which previous recommendations were superseded.

## 1. Native raster execution (critical path)

Statuses: T-146 and T-147 **Done**; T-153 **Done** and required before T-148 can close; T-148 **In Progress** (native tile/history authority still incomplete); T-149–T-152 **Blocked** by dependencies. No manual-review gate is imposed on engineering refactors; owner physical UX review stays with T-095.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-146 · 96px Hokusai hard-round full-canvas pointer benchmark](Tickets/T-146.md) | Done | [12 process / 15 gesture native X11 evidence](evidence/T-146-2026-11-15-hokusai-benchmark.md); translucent full-source coverage; T-095 gate remains | [T-097](Tickets/T-097.md), [T-101](Tickets/T-101.md) |
| [T-147 · Unify NativeHard and Hokusai behind one native stroke engine](Tickets/T-147.md) | Done | [One v1 stroke ABI and real native rollback/FFI evidence](evidence/T-147-2026-11-15-unified-stroke.md); native tile contract documented | [T-146](Tickets/T-146.md) |
| [T-153 · Retire NativeHard; use Hokusai for every Brush preset](Tickets/T-153.md) | Done | [Hokusai-only release, ABI, 96px graphical and Object/Atlas regression evidence](evidence/T-153-2026-11-16-hokusai-only.md); T-095 hardware gate remains | [T-147](Tickets/T-147.md) |
| [T-154 · Preserve native history through text-to-raster Undo/Redo](Tickets/T-154.md) | Done | [Checked native parking, exact RGBA8 retry and Save/Open evidence](evidence/T-154-2026-11-16-text-raster-parking.md); T-148 remains open | [T-147](Tickets/T-147.md), [T-153](Tickets/T-153.md) |
| [T-155 · Atomically replace parked text-derived native raster source](Tickets/T-155.md) | Done | [32-check rerasterization, selective retirement, fail-first and native/Atlas/Object evidence](evidence/T-155-2026-11-16-reraster.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-154](Tickets/T-154.md) |
| [T-156 · Replay historical pixel-map history through native tiles](Tickets/T-156.md) | Done | [37-check local/Atlas history replay, fail-first and graphical evidence](evidence/T-156-2026-11-16-legacy-pixel-native.md); general native authority remains T-148 | [T-153](Tickets/T-153.md) |
| [T-157 · Reject stale and reentrant lazy raster sources](Tickets/T-157.md) | Done | [23-check native authority, fail-first and root lazy source regressions](evidence/T-157-2026-11-16-lazy-guard.md); T-148 remains open | [T-153](Tickets/T-153.md) |
| [T-158 · Bound signed lazy raster tiles before persistence](Tickets/T-158.md) | Done | [24-check signed source/.drawing, fail-first and native/Atlas/X11 regressions](evidence/T-158-2026-11-16-tile-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md) |
| [T-159 · Reject signed 64-bit extremes in native publication and history replay](Tickets/T-159.md) | Done | [Real Hokusai replay/publication boundary regression](evidence/T-159-2026-11-16-replay-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-158](Tickets/T-158.md) |
| [T-160 · Guard native-attached direct pixel/tile publication bounds](Tickets/T-160.md) | Done | [46-check source/history/Save/Open regression and fail-first control](evidence/T-160-2026-11-16-direct-publish-bounds.md); non-native historical range unchanged; T-148 remains open | [T-153](Tickets/T-153.md), [T-159](Tickets/T-159.md) |
| [T-161 · Reject signed public gesture, viewport and image anchors](Tickets/T-161.md) | Done | [47-check native anchor regression and 7-failure pre-fix control](evidence/T-161-2026-11-16-public-anchors.md); historical ±2^60 endpoints retained; T-148 remains open | [T-153](Tickets/T-153.md), [T-159](Tickets/T-159.md) |
| [T-162 · Keep untracked direct raster edits native-authoritative](Tickets/T-162.md) | Done | [25-check mixed pixel/tile native source, Hokusai history and Save/Open regression](evidence/T-162-2026-11-16-untracked-native.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-160](Tickets/T-160.md) |
| [T-163 · Guard signed clipboard capture rectangle bounds](Tickets/T-163.md) | Done | [34-check fail-first/native/lazy source regression](evidence/T-163-2026-11-16-clipboard-bounds.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-161](Tickets/T-161.md) |
| [T-164 · Guard full signed image-import extents](Tickets/T-164.md) | Done | [26-check fail-first/native/import-endpoint regression](evidence/T-164-2026-11-16-image-extents.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-161](Tickets/T-161.md) |
| [T-165 · Fail closed on divergent attached-native direct publication](Tickets/T-165.md) | Done | [51-check Hokusai/native reentrancy and revision-fence witness with 18-failure pre-fix control](evidence/T-165-2026-11-16-attached-revision-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-162](Tickets/T-162.md) |
| [T-166 · Reject unauthorized native save projections](Tickets/T-166.md) | Done | [24-check Hokusai/Rust source-byte and revision-fence witness with fail-first control](evidence/T-166-2026-11-16-native-save-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-165](Tickets/T-165.md) |
| [T-167 · Check native authority before dirty raster snapshots](Tickets/T-167.md) | Done | [25-check native dirty snapshot and 11-failure pre-fix control](evidence/T-167-2026-11-16-checked-dirty-snapshot.md); T-148 host history gate remains open | [T-153](Tickets/T-153.md), [T-166](Tickets/T-166.md) |
| [T-168 · Fail closed on rejected native raster subtree removal](Tickets/T-168.md) | Done | [30-check Hokusai-native subtree removal fence, 19-failure pre-fix control](evidence/T-168-2026-11-16-native-subtree-removal.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-154](Tickets/T-154.md) |
| [T-169 · Fail closed on rejected native-attached raster subtree import](Tickets/T-169.md) | Done | [Native revision/busy/129-ID fail-first and retry witness](evidence/T-169-2026-11-16-native-import-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-168](Tickets/T-168.md) |
| [T-170 · Preflight source native retirement before cross-document raster moves](Tickets/T-170.md) | Done | [30-check native/Atlas transfer and 9-failure pre-fix control](evidence/T-170-2026-11-16-transfer-preflight.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-168](Tickets/T-168.md), [T-169](Tickets/T-169.md) |
| [T-171 · Reject unauthorized native-owned detached raster subtree exports](Tickets/T-171.md) | Done | [33-check direct/Copy/Atlas native source fence, 11-failure control, and Rust/X11 matrix](evidence/T-171-2026-11-16-native-export-fence.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-166](Tickets/T-166.md), [T-170](Tickets/T-170.md) |
| [T-172 · Preflight target-native retirement before Atlas transfer Undo](Tickets/T-172.md) | Done | [30-check Atlas Move/Copy Undo and native-ahead regression with four-failure pre-fix control](evidence/T-172-2026-11-16-atlas-undo-preflight.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-170](Tickets/T-170.md) |
| [T-173 · Fail closed on rejected native-attached public layer metadata revisions](Tickets/T-173.md) | Done | [31-check Hokusai/Rust busy/native-ahead metadata guard; 22-failure pre-fix control](evidence/T-173-2026-11-16-native-layer-metadata.md); T-148 remains open | [T-153](Tickets/T-153.md), [T-165](Tickets/T-165.md) |
| [T-174 · Fail closed on rejected native semantic/density revisions](Tickets/T-174.md) | Done | [48-check semantic/native history and density fail-first witness](evidence/T-174-2026-11-16-native-semantic-preflight.md); T-148 stays open | [T-173](Tickets/T-173.md), [T-165](Tickets/T-165.md) |
| [T-175 · Fail closed on rejected native semantic-only subtree imports](Tickets/T-175.md) | Done | [27-check Hokusai/native semantic Copy, 13-failure control and 29-run matrix](evidence/T-175-2026-11-16-semantic-import-fence.md); T-148 stays open | [T-174](Tickets/T-174.md), [T-169](Tickets/T-169.md) |
| [T-176 · Fail closed on rejected native semantic structural Undo/Redo](Tickets/T-176.md) | Done | [121-check native semantic history replay, 25-failure pre-fix control and Rust/Atlas/X11 matrix](evidence/T-176-2026-11-16-semantic-history.md); T-148 stays open | [T-173](Tickets/T-173.md) |
| [T-177 · Fail closed on rejected native raster structural Undo/Redo](Tickets/T-177.md) | Done | [89-check native raster-history, fail-first and Rust/Atlas/X11 regression](evidence/T-177-2026-11-16-raster-history.md); T-148 remains open | [T-176](Tickets/T-176.md), [T-168](Tickets/T-168.md) |
| [T-178 · Fail closed on rejected native semantic text Undo/Redo](Tickets/T-178.md) | Done | [43-check native text history, 21-failure pre-fix control and Rust/Atlas/X11 regression](evidence/T-178-2026-11-16-text-history.md); T-148 stays open | [T-174](Tickets/T-174.md), [T-176](Tickets/T-176.md) |
| [T-179 · Fail closed on rejected native semantic-only subtree removal](Tickets/T-179.md) | Done | [62-check busy/ahead native semantic removal, local/host history retry and Hokusai evidence](evidence/T-179-2026-11-16-semantic-removal.md); T-148 stays open | [T-173](Tickets/T-173.md), [T-176](Tickets/T-176.md) |
| [T-229 · Bound detached native history transfers before source reads](Tickets/T-229.md) | Done | [18-check fail-first/positive Godot, 36 Rust, 536 native-history/Atlas and 46 X11 checks](evidence/T-229-2026-11-22-history-budget.md); T-148 universal ownership remains open | [T-156](Tickets/T-156.md), [T-157](Tickets/T-157.md) |
| [T-230 · Bootstrap native ownership for detached historical pixel replay](Tickets/T-230.md) | Done | [8-failure pre-fix witness, 33-check native-local/host/Save/Open and neighbor matrix](evidence/T-230-2026-11-22-detached-pixel-bootstrap.md); T-148 host timeline remains open | [T-156](Tickets/T-156.md), [T-229](Tickets/T-229.md) |
| [T-231 · Preflight stride-aware direct native raster transfers](Tickets/T-231.md) | Done | [8-failure pre-fix and 24-check Godot, 36 Rust, standalone/Atlas and 46 native-X11 checks](evidence/T-231-2026-11-22-direct-budget.md); T-148 general native ownership still open | [T-162](Tickets/T-162.md), [T-229](Tickets/T-229.md) |
| [T-232 · Bootstrap native authority on first direct tile-local edit](Tickets/T-232.md) | Done | [8-failure pre-fix, 34-check native bootstrap, T-100 pixel-oracle, native/Atlas/X11 evidence](evidence/T-232-2026-11-22-tile-bootstrap.md); T-148 general pixel edit production remains open | [T-162](Tickets/T-162.md), [T-231](Tickets/T-231.md) |
| [T-249 · Preserve Atlas context handlers during history callbacks](Tickets/T-249.md) | Done | [42-failure prior-code control, 84-check direct/reflective context and native-history witness](evidence/T-249-2026-11-22-context-handler-reservation.md); T-148 remains open | [T-248](Tickets/T-248.md) |
| [T-248 · Preserve Atlas active-map target during reserved history callbacks](Tickets/T-248.md) | Done | [14-failure prior-code control, 70-check direct/reflective active-map callback regression](evidence/T-248-2026-11-22-active-map-reservation.md); T-148 host integration remains open | [T-247](Tickets/T-247.md) |
| [T-247 · Reserve Atlas history during synchronous changed notifications](Tickets/T-247.md) | Done | [124-failure prior-code control, 259-check synchronous host notification/replay matrix](evidence/T-247-2026-11-22-atlas-notifications.md); T-148 host lifecycle remains open | [T-246](Tickets/T-246.md) |
| [T-246 · Reserve Atlas history during non-Drawing command application](Tickets/T-246.md) | Done | [60-failure pre-fix control, 206-check Atlas command/transfer/asset reentrancy witness](evidence/T-246-2026-11-22-atlas-command-reservation.md); T-148 host timeline integration remains open | [T-245](Tickets/T-245.md) |
| [T-245 · Reserve Atlas command history during Drawing publication](Tickets/T-245.md) | Done | [22-failure fail-first and 126-check real Atlas reentrant command/Undo/Redo acceptance](evidence/T-245-2026-11-22-atlas-commit-reentrancy.md); T-148 host command lifecycle remains open | [T-244](Tickets/T-244.md), [T-239](Tickets/T-239.md) |
| [T-244 · Reserve history owner during pending script edit sessions](Tickets/T-244.md) | Done | [7/50 standalone and 9/18 Atlas fail-first, 50/50 + 18/18 post-fix checks](evidence/T-244-2026-11-22-pending-session-handoff.md); T-148 remains open | [T-241](Tickets/T-241.md), [T-243](Tickets/T-243.md) |
| [T-243 · Fence native active edits against history-owner handoff](Tickets/T-243.md) | Done | [10-failure pre-fix control and 40-check local/host native history acceptance](evidence/T-243-2026-11-22-active-history-handoff.md); T-148 remains open | [T-241](Tickets/T-241.md), [T-242](Tickets/T-242.md) |
| [T-242 · Expose host history ownership as a checked read-only property](Tickets/T-242.md) | Done | [10/25 and 9/18 fail-first controls, exact native standalone and Atlas timeline regression](evidence/T-242-2026-11-22-history-owner-property.md); T-148 lifetime migration remains open | [T-241](Tickets/T-241.md) |
| [T-241 · Fence host-owned history against implicit local takeover](Tickets/T-241.md) | Done | [6-failure prior-code control, 29-check native owner handoff regression and Atlas global-history smoke](evidence/T-241-2026-11-22-host-history-owner.md); T-148 host command migration remains open | [T-239](Tickets/T-239.md) |
| [T-240 · Preflight native history/adoption FFI buffers before copying](Tickets/T-240.md) | Done | [4-failure prior-native control, 32-check direct/detached/token replay witness, Rust/Atlas/X11 evidence](evidence/T-240-2026-11-22-ffi-payload-preflight.md); T-148 host command ownership remains open | [T-229](Tickets/T-229.md), [T-231](Tickets/T-231.md), [T-237](Tickets/T-237.md) |
| [T-239 · Reject retained out-of-order native host history replay](Tickets/T-239.md) | Done | [10-failure prior-code control, 36-check current native token-order/eviction witness, standalone/Atlas and Rust regressions](evidence/T-239-2026-11-22-native-history-order.md); T-148 host lifecycle remains open | [T-237](Tickets/T-237.md), [T-230](Tickets/T-230.md) |
| [T-238 · Reject reentrant native Brush source-byte mutation](Tickets/T-238.md) | Done | [2-failure prior-code control, 18-check native source guard and standalone/Atlas/X11 regressions](evidence/T-238-2026-11-22-brush-source-reentrancy.md); T-148 host lifecycle remains open | [T-234](Tickets/T-234.md) |
| [T-237 · Preflight detached native tile-history payloads before lazy source reads](Tickets/T-237.md) | Done | [24-failure control, 40-check source/delta guard and standalone/Atlas replay regressions](evidence/T-237-2026-11-22-detached-history-preflight.md); T-148 host lifecycle remains open | [T-156](Tickets/T-156.md), [T-229](Tickets/T-229.md) |
| [T-236 · Preflight direct pixel-map descriptors before lazy source reads](Tickets/T-236.md) | Done | [16-failure control, 35-check map/source reentrancy guard, signed native/Atlas and T-068 smoke](evidence/T-236-2026-11-22-pixel-map-preflight.md); T-148 host authority remains open | [T-233](Tickets/T-233.md), [T-235](Tickets/T-235.md) |
| [T-235 · Preflight tile-local patch descriptors before lazy source reads](Tickets/T-235.md) | Done | [17-failure control, 34-check descriptor/source reentrancy guard, native/Atlas](evidence/T-235-2026-11-22-tile-patch-preflight.md); T-148 host lifetime remains open | [T-232](Tickets/T-232.md), [T-234](Tickets/T-234.md) |
| [T-234 · Preflight native Brush tile publication before lazy sources](Tickets/T-234.md) | Done | [13-failure control, 32-check final descriptor/reentrancy test, native ABI/Atlas/X11](evidence/T-234-2026-11-22-publication-preflight.md); T-148 host lifetime remains open | [T-231](Tickets/T-231.md) |
| [T-233 · Bootstrap native authority on first direct pixel-map edit](Tickets/T-233.md) | Done | [12-failure control, 37-check native edit bootstrap, T-100/T-095 oracles, historical replay, Atlas/Rust/X11](evidence/T-233-2026-11-22-pixel-bootstrap.md); T-148 host lifecycle remains open | [T-232](Tickets/T-232.md) |
| [T-148 · Native-owned tiled raster editing and atomic undo transactions](Tickets/T-148.md) | In Progress | [Atlas native history](evidence/T-148-2026-11-15-atlas-native-history.md), [Object-native Save/Save As](evidence/T-148-2026-11-15-object-native.md), [reentrant history replay](evidence/T-148-2026-11-16-native-history-replay.md) and [atomic native payload parity](evidence/T-148-2026-11-16-native-history-payload.md) and [detached native replay](evidence/T-148-2026-11-16-detached-native-replay.md) with [absent/stale-store bootstrap](evidence/T-148-2026-11-16-detached-bootstrap.md) and [bounded history transfers](evidence/T-229-2026-11-22-history-budget.md) and [first pixel replay native bootstrap](evidence/T-230-2026-11-22-detached-pixel-bootstrap.md) and [first tile-local publication native bootstrap](evidence/T-232-2026-11-22-tile-bootstrap.md) and [first direct pixel publication native bootstrap](evidence/T-233-2026-11-22-pixel-bootstrap.md) verified; next: host-owned command lifetime and remaining raster producers | [T-147](Tickets/T-147.md), [T-153](Tickets/T-153.md) |
| [T-149 · Godot native dirty-tile preview, display and persistence seams](Tickets/T-149.md) | Blocked | After T-148: batched Godot inputs and native dirty-tile display/save seams | [T-148](Tickets/T-148.md) |
| [T-150 · Remove Legacy Brush backend and compatibility paths](Tickets/T-150.md) | Blocked | After T-149: retire Legacy without migration or native-free fallback | [T-149](Tickets/T-149.md) |
| [T-151 · Profile post-consolidation native Brush critical path](Tickets/T-151.md) | Blocked | After T-150: profile the consolidated full editor and all native seams | [T-150](Tickets/T-150.md) |
| [T-152 · Optimize the highest measured native Brush bottleneck](Tickets/T-152.md) | Blocked | After T-151: optimize one evidenced latency bottleneck | [T-151](Tickets/T-151.md) |

## 2. Active performance, application and CI work

These tracks may progress independently where possible, but their final acceptance must exercise the new native tile/store seam.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md), [T-108](Tickets/T-108.md), [T-250](Tickets/T-250.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | In Progress | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md), [T-109](Tickets/T-109.md), [T-250](Tickets/T-250.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | Rust-first direction; T-105 portability and post-consolidation profiling | [T-052](Tickets/T-052.md), [T-104](Tickets/T-104.md), [T-105](Tickets/T-105.md), [T-151](Tickets/T-151.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | In Progress | T-222–225 engineering Done; T-091 physical validation and explicit owner review remain | [T-082](Tickets/T-082.md), [T-091](Tickets/T-091.md), [T-222](Tickets/T-222.md), [T-223](Tickets/T-223.md), [T-224](Tickets/T-224.md), [T-225](Tickets/T-225.md) |
| [T-085 · Real-time strokes and smooth input](Tickets/T-085.md) | In Progress | Retest batched native input, held preview and cancellation | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |
| [T-086 · Incremental viewport cache and zoom](Tickets/T-086.md) | In Progress | Native dirty-tile display + physical dense zoom acceptance | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md), [T-149](Tickets/T-149.md) |
| [T-087 · Visible image edge, transparency and grid](Tickets/T-087.md) | Done | [Current standalone + Atlas native evidence](evidence/T-087-2026-11-22-current-native.md); physical/owner visual approval stays T-059/T-250/T-056 | [T-053](Tickets/T-053.md) |
| [T-088 · Selection masks, clipboard and Move](Tickets/T-088.md) | In Progress | T-221 sparse Delete fix Done; physical recheck, T-149 native mask and Move/clipboard acceptance remain | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md), [T-221](Tickets/T-221.md) |
| [T-090 · Responsive UI, menu, tabs and brush wheel](Tickets/T-090.md) | Done | [Current beta3 native/More/resize and cold-build evidence](evidence/T-090-2026-11-22-current-native.md); owner T-059/T-250 UX gate remains separate | [T-063](Tickets/T-063.md) |
| [T-091 · Single-group floating dock and width recovery](Tickets/T-091.md) | In Progress | T-225/T-255–T-258 icon tabs, clipped hits, menus, Escape/focus-loss rollback Done; physical floating/edge resize validation remains | [T-082](Tickets/T-082.md), [T-225](Tickets/T-225.md) |
| [T-092 · Compact Colors and History preferences](Tickets/T-092.md) | Done | [Current required-native standalone/Atlas evidence](evidence/T-092-2026-11-22-current-native.md); physical owner UX remains T-059/T-250/T-056 | [T-063](Tickets/T-063.md), [T-226](Tickets/T-226.md) |
| [T-094 · Restore CI and owner acceptance evidence](Tickets/T-094.md) | In Progress | Required-native hosted CI and independent owner evidence | [T-053](Tickets/T-053.md), [T-055](Tickets/T-055.md), [T-063](Tickets/T-063.md), [T-106](Tickets/T-106.md), [T-107](Tickets/T-107.md), [T-150](Tickets/T-150.md) |
| [T-095 · Eliminate 60px Brush latency](Tickets/T-095.md) | In Progress | After T-152: reference-device 60/96px responsiveness and owner signoff | [T-053](Tickets/T-053.md), [T-098](Tickets/T-098.md), [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md), [T-152](Tickets/T-152.md) |
| [T-180 · Rebuildable offline toolchain and Make-first Drawing launch](Tickets/T-180.md) | In Progress | [Identical 251 MiB Arch/Ubuntu builds and hosted cold-native workflow](evidence/T-180-2026-11-17-local-validation.md) pass; four desktop/native-transition/export failures remain | [T-153](Tickets/T-153.md) |
| [T-183 · Correct native preset identity and edge behavior](Tickets/T-183.md) | Done | [189-check native workspace/GUI profiles and fresh old/new 96px performance baseline](evidence/T-183-2026-11-17-native-preset-audit.md); tooltips and source presets corrected, no owner hardware claim | [T-153](Tickets/T-153.md), [T-182](Tickets/T-182.md) |
| [T-184 · Separate visual Brushes panel and parameters](Tickets/T-184.md) | Done | [Native Hokusai previews, 132 UI/pixel checks, frozen gesture and floating layout evidence](evidence/T-184-2026-11-17-brush-panel.md); owner UX gates remain open | [T-182](Tickets/T-182.md) |
| [T-185 · Re-profile current Drawing frame drops and native path](Tickets/T-185.md) | Done | [Four complete software-X11 processes, 32 scenarios, two unverified exits, 54% p95 118ms cold frames; T-146 rapid p50 654ms cold / 680ms warm, composition dominant](evidence/T-185-2026-11-17-current-workspace-profile.md) | [T-146](Tickets/T-146.md), [T-181](Tickets/T-181.md) |
| [T-186 · Profile-led optimization toward 250ms / 200ms](Tickets/T-186.md) | Done | [Exact native dirty 128px preview A/B: 54% cold frame p95 123→71ms; 19+14 graphical checks](evidence/T-186-2026-11-17-exact-native-dirty-preview.md); 250/200ms rapid targets continue through T-187 into T-188 | [T-185](Tickets/T-185.md) |
| [T-187 · Residual native Drawing latency after exact preview invalidation](Tickets/T-187.md) | Done | [Same-native repeated pooled cold p50/p95 662/742→343/383ms, warm 553/598→344/358ms; 54% composition CPU 299→2.8ms and 99-check graphical parity/crop cap](evidence/T-187-2026-11-17-direct-native-preview.md); 250/200ms full-gesture targets remain open in T-188 | [T-186](Tickets/T-186.md) |
| [T-188 · Run-aware native Brush/Eraser staging](Tickets/T-188.md) | Done | [Two matched same-binary A/B rounds](evidence/T-188-2026-11-17-run-aware-native-staging.md), final cold p50/p95 388/494→266/422ms, warm 358/450→286/297ms; 63 graphical checks, 28 Rust tests; frame and release variation retained; 250/200ms continue through T-189 to T-190 | [T-187](Tickets/T-187.md) |
| [T-189 · Further 96px native full-gesture latency after run grouping](Tickets/T-189.md) | Done | [Per-tile source read vs per-pixel A/B](evidence/T-189-2026-11-17-native-source-read.md), pooled cold p50/p95 339/364→282/390ms and warm 297/337→273/281ms; tile-stage improvement, mixed frame/cold tail, 77 graphical, 29 Rust; targets T-190 | [T-188](Tickets/T-188.md) |
| [T-190 · Exact native sRGB byte quantization after source lookup hoisting](Tickets/T-190.md) | Done | [Bounded 64KiB sRGB8 LUT with exact powf fallback](evidence/T-190-2026-11-17-srgb-byte-quantization.md), 30 Rust/77 graphical, 2 reversed-order final rapid pairs: warm improved, cold tails mixed; targets continue T-191 | [T-189](Tickets/T-189.md) |
| [T-191 · Residual complete 96px gesture after exact sRGB8 export](Tickets/T-191.md) | Done | [Row-skip exact native fixed-point scan](evidence/T-191-2026-11-17-native-row-scan.md): 31 Rust/77 graphical, same-binary rapid/workspace A/B; whole-gesture and frame tails variable, 250/200ms goals remain T-192 | [T-190](Tickets/T-190.md) |
| [T-192 · Remaining 96px full-gesture critical path after row skip](Tickets/T-192.md) | Done | [Exact native batch write-journal dirty candidates](evidence/T-192-2026-11-17-native-dirty-journal.md): 2,134→0 redundant HashSet insert attempts; 32 native and 81 graphical checks, same-binary rapid/workspace A/B; CPU/frame/release tails mixed, targets T-193 | [T-191](Tickets/T-191.md) |
| [T-193 · Residual Hokusai raster and full-gesture latency](Tickets/T-193.md) | Done | [32-slot journal hint skips 1,840/2,134 map probes](evidence/T-193-2026-11-17-native-journal-hint.md); 34 Rust/83 graphical, rapid/workspace same-binary A/B; no reliable latency or frame-tail gain; target moves to T-194 | [T-192](Tickets/T-192.md) |
| [T-194 · Remaining source-faithful 96px full-gesture target](Tickets/T-194.md) | Done | [20 vs 16 source-space segments per native batch](evidence/T-194-2026-11-17-native-batch-cadence.md): strict 100-event cold/warm p95 343/320→240/240ms, 79 graphical parity checks, complete rapid 250ms milestone only; 200ms and paced/hardware gates open | [T-193](Tickets/T-193.md) |
| [T-195 · 96px 200ms stretch and paced frame tails](Tickets/T-195.md) | Done | [Release-only bounded second drain](evidence/T-195-2026-11-17-release-catchup.md), 85 graphical checks and 2 reversed-order rapid/workspace pairs; cold p95 304→253ms, warm 278→209ms; 200ms and paced frame tails T-196 | [T-194](Tickets/T-194.md) |
| [T-196 · Residual 200ms and paced release/frame tails](Tickets/T-196.md) | Done | [Deep backlog idle-deferred single drain](evidence/T-196-2026-11-17-deferred-backlog-drain.md); 99 graphical checks; warm 100-event p95 217→205ms, cold p95 215→227ms, paced tails mixed; 200ms follows T-197 | [T-195](Tickets/T-195.md) |
| [T-197 · Remaining 200ms and first-preview / paced frame tails](Tickets/T-197.md) | In Progress | [Native display-only hidden-RGB crop and reverse-order same-binary A/B](evidence/T-197-2026-11-18-native-display.md); Eraser composition 76.7–81.9→3.0–3.5ms, exact source parity, paced frame and 200ms p95/hardware gates open | [T-196](Tickets/T-196.md) |
| [T-198 · Matched Canvas frame callback-gap attribution](Tickets/T-198.md) | Done | [Five fail-first unit cases and four re-ingested native workspace processes](evidence/T-198-2026-11-19-matched-callbacks.md): 541 confirmed adjacent Canvas callback intervals (0 ≥83ms), 251 unmatched adjacencies, 19 long **global** signal intervals; no physical FPS inference, T-197 still open | [T-196](Tickets/T-196.md) |
| [T-199 · Canvas redraw cadence independent of renderer callbacks](Tickets/T-199.md) | Done | [Five confirmed real workspace processes](evidence/T-199-2026-11-19-canvas-cadence.md): 990 valid adjacent draw-end periods, including 343 lacking paired callbacks, 0 ≥83ms; not physical FPS, T-197 remains open | [T-198](Tickets/T-198.md) |
| [T-200 · Restore T-095 native Brush profiling oracles](Tickets/T-200.md) | Done | [Four Hokusai-only profiler regressions](evidence/T-200-2026-11-19-native-profiler-oracle.md): 23+19+23+21 checks ×3 graphical passes, real callback attribution, divergent pigment/width controls and exact native source/Undo; 200ms and hardware gates open | [T-153](Tickets/T-153.md) |
| [T-201 · Required-native Linux export package and ABI gate](Tickets/T-201.md) | Done | [Fail-closed native ELF staging/inspection and isolated real-PCK/ABI runtime](evidence/T-201-2026-11-19-linux-native-export.md), 5 new+15 existing unit cases, 35 Rust/32 Drawing checks; hosted official template, Windows, CI and owner gates open | [T-153](Tickets/T-153.md) |
| [T-220 · Validate exported binary Drawing project identity](Tickets/T-220.md) | Done | [12 fail-first false accepts, bounded ECFG String identity and startup checks, byte-unchanged packaging rejection and real 528-resource ABI launch](evidence/T-220-2026-11-19-packed-project-identity.md); hosted and owner gates open | [T-219](Tickets/T-219.md) |
| [T-219 · Reject ambiguous Godot PCK resource names](Tickets/T-219.md) | Done | [Six fail-first name cases, canonical UTF-8/alignment enforcement, rejected-package byte parity and real 528-resource native ABI launch](evidence/T-219-2026-11-19-pck-names.md); hosted and owner gates open | [T-218](Tickets/T-218.md) |
| [T-218 · Verify complete exported PCK payload integrity](Tickets/T-218.md) | Done | [All indexed MD5 and non-overlapping resource extents, corrupted optional asset preflight rollback, real 528-resource native ABI launch](evidence/T-218-2026-11-19-pck-payload.md); hosted and owner gates remain open | [T-217](Tickets/T-217.md) |
| [T-217 · Verify native Drawing resources in exported Godot PCK](Tickets/T-217.md) | Done | [Fail-first unrelated-pack acceptance, bounded PCK v4 index/MD5/remap contracts and real 528-entry native ABI launch](evidence/T-217-2026-11-19-pck-index.md); Windows structural-only and hosted gates open | [T-216](Tickets/T-216.md) |
| [T-216 · Require effective Drawing stage identity and startup scene](Tickets/T-216.md) | Done | [Six fail-first spoof/duplicate/wrong-scene cases, package-unchanged controls and real 522-file native stage/PCK ABI](evidence/T-216-2026-11-19-project-identity.md); 71 configured Python, 35 Rust tests, hosted gates open | [T-215](Tickets/T-215.md) |
| [T-215 · Reject undeclared staged directories and special nodes](Tickets/T-215.md) | Done | [Five fail-first staged-directory/FIFO failures and positive real-stage/native ABI checks](evidence/T-215-2026-11-19-stage-inventory.md); 18 release-package tests, 70 configured Python, 35 Rust; hosted gates open | [T-214](Tickets/T-214.md) |
| [T-214 · Preserve foreign export temp entries on rejection](Tickets/T-214.md) | Done | [Three fail-first foreign-entry failures and owned-temp interrupted-copy rollback](evidence/T-214-2026-11-19-temp-ownership.md); 13 package tests, real native ABI launch; hosted/Windows gates open | [T-213](Tickets/T-213.md) |
| [T-213 · Reject undeclared directories and special export nodes](Tickets/T-213.md) | Done | [Six fail-first subtests and exact-tree candidate/final inspection](evidence/T-213-2026-11-19-export-entries.md); 15 unit tests, real Linux native ABI launch; hosted/Windows runtime gates open | [T-212](Tickets/T-212.md) |
| [T-212 · Preserve failed Linux export packaging atomically](Tickets/T-212.md) | Done | [Preflight real ELF/PCK/native candidate, rollback late rejection](evidence/T-212-2026-11-19-native-export-atomic.md); 2 fail-first + 8 current package tests, real PCK/isolated ABI, 35 Rust; hosted template/Windows remain open | [T-201](Tickets/T-201.md) |
| [T-202 · Restore T-066 signed campaign-save boundary regression](Tickets/T-202.md) | Done | [Fail-first and 91-check valid-edge/unsafe-save/root-preservation witness](evidence/T-202-2026-11-19-signed-save-fixture.md); root storage/editor and native signed-source tests pass; hosted CI open | [T-066](Tickets/T-066.md), [T-158](Tickets/T-158.md), [T-159](Tickets/T-159.md) |
| [T-203 · Restore T-087 required-native image-frame regressions](Tickets/T-203.md) | Done | [Headless 82/82 ×6 and X11 104/104 ×4](evidence/T-203-2026-11-19-native-image-frame.md); real Hokusai strokes, clipping/camera cancellation and hidden-RGB Eraser; hosted CI and owner UX remain open | [T-153](Tickets/T-153.md) |
| [T-204 · Restore T-085 native live-stroke regressions](Tickets/T-204.md) | Done | [81 headless ×4 and 144 native-X11 ×4 checks](evidence/T-204-2026-11-19-native-live-stroke.md); exact routed event Hokusai oracle, mask/cancellation and long-loop Undo, parent T-085/manual hardware gates open | [T-153](Tickets/T-153.md), [T-200](Tickets/T-200.md) |
| [T-205 · Restore T-130 native source-context timing oracle](Tickets/T-205.md) | Done | [34 checks ×4 headless and ×2 X11](evidence/T-205-2026-11-19-source-context-timing.md); mask retained through pending **or** both commits, neighboring old red smokes preserved, CI/owner gates open | [T-130](Tickets/T-130.md), [T-153](Tickets/T-153.md) |
| [T-206 · Restore T-124 queued native Brush/Eraser parity oracle](Tickets/T-206.md) | Done | [78 headless checks ×4 and 20 real-input X11 checks ×3](evidence/T-206-2026-11-19-native-queue-oracle.md); exact delivered source/times against sequential native Hokusai replay, Undo/Redo and changed-width control; hosted CI and owner gates open | [T-124](Tickets/T-124.md), [T-153](Tickets/T-153.md) |
| [T-207 · Restore T-127 native pending history regression](Tickets/T-207.md) | Done | [40/40 ×4 headless and ×2 X11](evidence/T-207-2026-11-19-native-history-oracle.md); 24px real native Undo candidate, guarded history cursor, two-frame pending-or-all-committed check; historical T-128/T-129 failures follow under T-208/T-129 | [T-127](Tickets/T-127.md), [T-153](Tickets/T-153.md) |
| [T-208 · Restore T-128 native History-list pending regression](Tickets/T-208.md) | Done | [37/37 ×4 headless and ×2 X11](evidence/T-208-2026-11-19-native-history-list.md); native moving History candidates, guarded row restoration, exact Undo/Redo, required CI marker; T-129 now repaired by T-209 | [T-128](Tickets/T-128.md), [T-153](Tickets/T-153.md) |
| [T-209 · Restore T-129 native pending layer/clipboard regression](Tickets/T-209.md) | Done | [35/35 ×4 headless and ×2 X11](evidence/T-209-2026-11-19-native-content-edit.md); pending-or-both-committed revision/cursor guard, exact source, strict marker; historical T-088 X11 failure later repaired under T-210 | [T-129](Tickets/T-129.md), [T-153](Tickets/T-153.md) |
| [T-210 · Restore T-088 native selection/clipboard/Move witness](Tickets/T-210.md) | Done | [52/52 ×4 native-X11](evidence/T-210-2026-11-19-native-selection.md); original 24/51 red, real Hokusai source, exact masked Move, hidden-RGB Eraser and strict marker; parent T-088/owner gates open | [T-153](Tickets/T-153.md), [T-209](Tickets/T-209.md) |
| [T-211 · Replace deleted T-095 scripted-delta CI bridge](Tickets/T-211.md) | Done | [Three parse-fail controls; real Hokusai 57, signed 24+39 and publication 56 checks](evidence/T-211-2026-11-19-required-native-ci.md), strict markers, no CI step-ID change; hosted/owner gates remain open | [T-153](Tickets/T-153.md), [T-158](Tickets/T-158.md), [T-159](Tickets/T-159.md) |
| [T-228 · Restore strict PR #22 fast-desktop release and dock-plan checks](Tickets/T-228.md) | Done | [Two reproduced fast-CI blockers repaired locally](evidence/T-228-2026-11-22-fast-ci-layout.md); strict sibling `dist/` layout and additive T-083 hard-dependency checks, hosted T-106 still open | [T-053](Tickets/T-053.md), [T-078](Tickets/T-078.md), [T-201](Tickets/T-201.md) |
| [T-105 · Portable native candidate builds and process-memory evidence](Tickets/T-105.md) | In Progress | Required-native Linux/Windows builds, exports and process/VRAM evidence | [T-052](Tickets/T-052.md), [T-150](Tickets/T-150.md) |
| [T-106 · Restore green required fast-desktop GitHub CI](Tickets/T-106.md) | In Progress | Fresh post-Legacy required-native CI inventory + hosted green | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-107 · Hosted CI replay and 23-finding owner-evidence matrix](Tickets/T-107.md) | In Progress | New hosted replay and 23-finding owner matrix; preserve historic 46 | [T-053](Tickets/T-053.md), [T-150](Tickets/T-150.md) |
| [T-108 · Nested Object Save As link-vs-copy policy and safe export](Tickets/T-108.md) | In Progress | Completed scope; see ticket evidence | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md), [T-250](Tickets/T-250.md) |

## 3. Owner decisions and independent manual review

Do **not** infer signoff from software tests or prior product scope. T-096 was moved to Blocked until T-149 native-tile revalidation restores review readiness.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | Completed scope; see ticket evidence | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Blocked | Completed scope; see ticket evidence | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md), [T-250](Tickets/T-250.md) |

| [T-250 · Owner manual review of Drawing before Atlas](Tickets/T-250.md) | Blocked | **2026-11-25 owner feedback:** prior fixes look good so far; T-302–T-312 corrective work and explicit owner acceptance remain open; no Atlas release signoff | [T-251](Tickets/T-251.md), [T-252](Tickets/T-252.md), [T-253](Tickets/T-253.md), [T-254](Tickets/T-254.md), [T-273](Tickets/T-273.md), [T-274](Tickets/T-274.md), [T-302](Tickets/T-302.md), [T-303](Tickets/T-303.md), [T-304](Tickets/T-304.md), [T-305](Tickets/T-305.md), [T-306](Tickets/T-306.md), [T-307](Tickets/T-307.md), [T-308](Tickets/T-308.md), [T-309](Tickets/T-309.md), [T-310](Tickets/T-310.md), [T-311](Tickets/T-311.md), [T-312](Tickets/T-312.md) |

## 4. Other ready backlog

Other feature/product tickets remain valid; no unrelated approval is assumed.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-302 · Expose standalone Bucket tool](Tickets/T-302.md) | Done | Shared Bucket toolbar and bounded fill; standalone/Atlas native pointer witnesses and visual inspection passed. | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-303 · Add raster Shapes tool and contextual options](Tickets/T-303.md) | Done | Shared Rectangle/Ellipse/Polygon, fill/stroke, FG/BG and width; native pointer, history and visual witnesses passed. | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-304 · Simplify Selection menu, shortcut captions and snapping chrome](Tickets/T-304.md) | Done | Native synchronized Selection mode submenu; duplicate tool commands and Snap chrome removed; distinct accelerator captions, overflow click fix; 59 standalone + 15 hosted checks and actual menu inspection passed. | [T-063](Tickets/T-063.md), [T-090](Tickets/T-090.md) |
| [T-305 · Export PNG, WebP and JPEG with format-specific settings](Tickets/T-305.md) | Done | Bounded visible composite export; PNG/WebP/JPEG options, encoded preview, atomic publication; codec, standalone and hosted native tests and visual inspection passed. | [T-053](Tickets/T-053.md), [T-120](Tickets/T-120.md) |
| [T-306 · Verify end-to-end sRGB artwork color pipeline](Tickets/T-306.md) | Done | Corrected double-encoded Brush RGB at Hokusai input; sRGB storage, real SDR framebuffer, import/export profile limits and native regressions verified. | [T-052](Tickets/T-052.md), [T-190](Tickets/T-190.md) |
| [T-307 · Text Options panel, live text preview and menu commands](Tickets/T-307.md) | Done | Shared dock-owned Text Options and menu, detached live glyphs in canonical layer order; exact preview/commit, one-event history, cancellation, portable Save/Open and real native standalone/hosted witnesses. | [T-058](Tickets/T-058.md), [T-063](Tickets/T-063.md) |
| [T-308 · Restore Object Editor background and standalone asset drag/drop](Tickets/T-308.md) | Done | **2026-11-25:** shared Object checkerboard, native standalone stable-ID linked drag/drop with graph authorization, atomic history and Save/Open; 40/40 standalone + 12/12 hosted; Atlas registry boundary preserved. | [T-062](Tickets/T-062.md), [T-093](Tickets/T-093.md), [T-109](Tickets/T-109.md) |
| [T-309 · Restore individual hidden panels from Window menu](Tickets/T-309.md) | Done | Individual Window panel recovery with checkmarks, original host ownership, partial persistence and no unwanted peers; removed Float selected dock group. 69 standalone / 20 hosted native checks and visual inspection. | [T-081](Tickets/T-081.md), [T-082](Tickets/T-082.md), [T-225](Tickets/T-225.md) |
| [T-310 · Versioned binary .drawing document and measured storage optimization](Tickets/T-310.md) | Done | Versioned typed binary standalone codec; legacy reader, bounded sparse RGBA8, exact fonts/objects, atomic save and [307 checks plus measured storage evidence](evidence/T-310-2026-11-25-binary-drawing.md); Atlas format unchanged. | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md), [T-066](Tickets/T-066.md), [T-067](Tickets/T-067.md) |
| [T-311 · Interactive layer-group disclosure and structural indentation](Tickets/T-311.md) | Done | Native TreeItem hierarchy, pointer/keyboard disclosure, view-only tab state, filtered/paged ancestor context and [47 standalone/11 hosted checks with visual review](evidence/T-311-2026-11-25-layer-disclosure.md). | [T-089](Tickets/T-089.md) |
| [T-312 · Unify panel icon texture filtering](Tickets/T-312.md) | Ready | **P2 owner queue:** [2026-11-25 review](DRAWING_UX_REVIEW_2026-11-25.md); Popup panel icons use nearest-neighbor while other states use bilinear filtering; owner notes nearest-neighbor looks stylish. | [T-225](Tickets/T-225.md), [T-254](Tickets/T-254.md) |
| [T-273 · Align whole right-dock toggle with outer edge](Tickets/T-273.md) | Done | **P0 engineering:** [real X11 screenshots and behavioral input proof](evidence/T-273-2026-11-23-dock-edge.md); T-250 owner review unapproved | [T-251](Tickets/T-251.md) |
| [T-274 · Compact native ColorPicker width and duplicate chrome](Tickets/T-274.md) | Done | **P0 engineering:** [native full-width picker, optional exact RGBA8, real X11 screenshots and Drawing/Atlas regression](evidence/T-274-2026-11-23-native-picker-composition.md); owner approval remains T-250 | [T-226](Tickets/T-226.md), [T-252](Tickets/T-252.md) |
| [T-275 · Repair stale workspace CI/owner-gate test contracts](Tickets/T-275.md) | Done | **P1 CI engineering:** [T-063/T-072 canonical status dependencies and 73-check native workspace regression](evidence/T-275-2026-11-23-workspace-ci-gates.md); T-250 approval and other hosted CI gates remain open | [T-063](Tickets/T-063.md), [T-072](Tickets/T-072.md) |
| [T-276 · Repair T-066 native-signed campaign-save CI fixture](Tickets/T-276.md) | Done | **P1 validation:** [97-check native-signed edit and corrupted save projection proof](evidence/T-276-2026-11-23-signed-ci-contract.md); broader CI/native architecture and T-250 owner gates remain open | [T-066](Tickets/T-066.md), [T-158](Tickets/T-158.md), [T-159](Tickets/T-159.md), [T-202](Tickets/T-202.md) |
| [T-277 · Repair T-068 Skia live oracle under native ownership](Tickets/T-277.md) | Done | **P1 validation:** [16-case live native exact parity against immutable beta2 fixture](evidence/T-277-2026-11-23-skia-native-oracle.md); other T-068 smokes and hosted CI remain red | [T-158](Tickets/T-158.md), [T-160](Tickets/T-160.md), [T-276](Tickets/T-276.md) |
| [T-278 · Repair T-068 source-tile cache native publication smoke](Tickets/T-278.md) | Done | **P1 validation:** [38/38 real native tile-cache reads/Undo/Redo and signed projection protection](evidence/T-278-2026-11-23-native-tile-cache.md); stationary-dab fixture repaired in T-279; axis-sweep remains red | [T-158](Tickets/T-158.md), [T-160](Tickets/T-160.md), [T-277](Tickets/T-277.md) |
| [T-279 · Restore stationary-dab Geometry2D oracle on native tiles](Tickets/T-279.md) | Done | **P1 validation:** [112/112 signed native-geometry and full-region Undo/Redo checks](evidence/T-279-2026-11-23-dab-native-geometry.md); axis-sweep and hosted CI remain red | [T-277](Tickets/T-277.md), [T-278](Tickets/T-278.md) |
| [T-280 · Restore native axis-sweep Geometry2D and complete-region Undo/Redo oracle](Tickets/T-280.md) | Done | **P1 validation:** [241/241 native axis, mask, committed RGBA8 and Unsafe-rejection checks](evidence/T-280-2026-11-23-axis-native-geometry.md); separate fill and hosted CI gates remain open | [T-277](Tickets/T-277.md), [T-278](Tickets/T-278.md) |
| [T-301 · Preserve pending Brush across polygon/selection geometric no-ops](Tickets/T-301.md) | Done | **P1 implementation:** [3-failure native baseline, 39/39 corrected and 573/573 neighboring checks](evidence/T-301-2026-11-24-polygon-selection.md); T-068/T-148 and hosted/owner gates remain open | [T-300](Tickets/T-300.md) |
| [T-300 · Preserve deferred Brush across masked interior bulk no-ops](Tickets/T-300.md) | Done | **P1 implementation:** [13-failure baseline, 62/62 native and 652/652 neighboring checks](evidence/T-300-2026-11-24-masked-overlap.md); T-068/T-148, hosted/owner gates remain open | [T-299](Tickets/T-299.md) |
| [T-299 · Preserve deferred Brush on selection-excluded bulk no-ops](Tickets/T-299.md) | Done | **P1 implementation:** [8-failure baseline, 40/40 real native and 480/480 neighboring checks](evidence/T-299-2026-11-24-masked-bulk.md); T-068/T-148/hosted and T-250 owner gates remain open | [T-153](Tickets/T-153.md), [T-290](Tickets/T-290.md) |
| [T-298 · Select canonical Brush publisher for unsupported native tile strides](Tickets/T-298.md) | Done | **P1 implementation:** [10-failure native regression, 632/632 source-reference and 33,037/33,037 tile-key cache checks](evidence/T-298-2026-11-24-brush-stride.md); T-095 owner hardware/hosted and T-068/T-148 gates remain open | [T-153](Tickets/T-153.md) |
| [T-297 · Reject Brush candidate-window integer overflow before raster staging](Tickets/T-297.md) | Done | **P1 implementation:** [48/113 original failures, 113/113 corrected clipped/unclipped Brush and Undo/Redo checks](evidence/T-297-2026-11-23-brush-candidate-bounds.md); T-095 stride-3 and T-068/T-148 hosted/owner gates remain open | [T-153](Tickets/T-153.md) |
| [T-296 · Preflight native Delete projection before lazy I/O](Tickets/T-296.md) | Done | **P1 implementation:** [15-failure real-native baseline, 50/50 signed Delete/Brush/Undo/Redo and eight neighboring suites](evidence/T-296-2026-11-23-clear-native-projection.md); T-148/T-068/hosted/owner gates open | [T-153](Tickets/T-153.md) |
| [T-295 · Preflight native Brush per-pixel projection before lazy I/O](Tickets/T-295.md) | Done | **P1 implementation:** [30-failure native baseline, 50/50 signed Brush/mixed-gesture/Undo/Redo and neighboring regression evidence](evidence/T-295-2026-11-23-brush-native-projection.md); T-148/T-068/hosted/owner gates open | [T-153](Tickets/T-153.md) |
| [T-294 · Preflight native bulk edit global projection before lazy I/O](Tickets/T-294.md) | Done | **P1 implementation:** [44-failure native baseline, 71/71 signed bulk/Brush/Undo/Redo and 301/301 neighbors](evidence/T-294-2026-11-23-bulk-native-projection.md); T-148/T-068/hosted/owner gates open | [T-153](Tickets/T-153.md) |
| [T-293 · Preflight native global flood-fill projection before lazy I/O](Tickets/T-293.md) | Done | **P1 implementation:** [18-failure native baseline, 41/41 exact signed endpoint/Undo/Redo and 283/283 neighbors](evidence/T-293-2026-11-23-native-fill-projection.md); T-148/T-068/hosted/owner gates open | [T-153](Tickets/T-153.md) |
| [T-292 · Bound flood-fill frontiers before lazy source reads](Tickets/T-292.md) | Done | **P1 implementation:** [10-failure native baseline, 38/38 signed edge fill, 283/283 neighboring native and required-CI witness](evidence/T-292-2026-11-23-fill-frontier.md); T-148/T-068/owner/hosted gates open | [T-153](Tickets/T-153.md) |
| [T-291 · Skip selection-excluded fill seeds before lazy reads](Tickets/T-291.md) | Done | **P1 implementation:** [10-failure native pre-fix, 33/33 fixed, 250/250 neighboring native and required-CI witness](evidence/T-291-2026-11-23-masked-seed-preflight.md); T-148/T-068/owner/hosted gates open | [T-153](Tickets/T-153.md) |
| [T-290 · Preflight bulk raster regions before deferred Brush and lazy I/O](Tickets/T-290.md) | Done | **P1 implementation:** [8-failure native pre-fix, 28/28 fixed, 323 neighboring native checks and strict required-CI marker](evidence/T-290-2026-11-23-bulk-preflight.md); T-148/T-068/owner/hosted gates remain open | [T-153](Tickets/T-153.md) |
| [T-289 · Reject invalid flood-fill seeds/colors before lazy reads](Tickets/T-289.md) | Done | **P1 implementation:** [13-failure native pre-fix, 23/23 fixed, 161 neighboring native checks and required-CI strict marker](evidence/T-289-2026-11-23-fill-preflight.md); T-068/hardware/hosted gates remain open | [T-153](Tickets/T-153.md) |
| [T-288 · Restore native Rust fill-to-frame CI and beta4 profiler provenance](Tickets/T-288.md) | Done | **P1 validation:** [native build and registration, exact 96/96 fill, two 21-trial X11 processes 770/770, mutation and engine-hash contracts](evidence/T-288-2026-11-23-native-fill-frame.md); T-068/T-094/owner gates open | [T-153](Tickets/T-153.md) |
| [T-287 · Reject non-replayable workflow and job metadata in local fast CI](Tickets/T-287.md) | Done | **P1 validation:** [14 fail-first envelope violations, 50/50 replay/CI/owner-evidence Python contracts](evidence/T-287-2026-11-23-workflow-envelope.md); hosted CI and owner review remain open | [T-122](Tickets/T-122.md), [T-286](Tickets/T-286.md) |
| [T-286 · Reject non-replayable step metadata in local fast CI](Tickets/T-286.md) | Done | **P1 validation:** [8 fail-first metadata violations, 47/47 strict replay/CI/owner-evidence Python contracts](evidence/T-286-2026-11-23-ci-replay-metadata.md); hosted CI and owner review remain open | [T-122](Tickets/T-122.md) |
| [T-285 · Normalize repeat beta4 Linux native release exports](Tickets/T-285.md) | Done | **P1 implementation:** [29 native-package plus 45 adjacent PCK/CI/portability tests](evidence/T-285-2026-11-23-reexport-normalization.md); exact two-native inventory, stage digest, late rollback, hosted/owner gates remain open | [T-201](Tickets/T-201.md), [T-212](Tickets/T-212.md) |
| [T-284 · Make T-124 queued Brush CI backlog deterministic](Tickets/T-284.md) | Done | **P1 validation:** [840 input samples force deferred second gesture, 4 × 78/78 headless, 20/20 native X11, fail-closed short-path mutation](evidence/T-284-2026-11-23-queued-brush-backlog.md); hosted/owner T-085/T-250 gates remain open | [T-124](Tickets/T-124.md), [T-262](Tickets/T-262.md) |
| [T-283 · Repair T-137 cold-preview fast-CI Redo contract](Tickets/T-283.md) | Done | **P1 validation:** [15/15 model, 19/19 X11 settled Redo, 153/153 T-086 neighbor, strict CI contracts](evidence/T-283-2026-11-23-cold-preview-ci-contract.md); owner/hosted/hardware gates open | [T-137](Tickets/T-137.md), [T-266](Tickets/T-266.md) |
| [T-282 · Restore verified-source mixed fill staging on native tile history](Tickets/T-282.md) | Done | **P1 validation:** [36/36 native immutable-source fill, full-region commit/Undo/Redo, signed seam and mutation controls](evidence/T-282-2026-11-23-verified-stage.md); hosted CI/performance and owner gates remain open | [T-281](Tickets/T-281.md), [T-278](Tickets/T-278.md) |
| [T-281 · Restore native lazy flood-fill tile-cache and full-region history witness](Tickets/T-281.md) | Done | **P1 validation:** [39/39 native lazy fill, signed seam, masked/unmasked Undo/Redo and mutation controls](evidence/T-281-2026-11-23-native-fill-cache.md); verified-stage and hosted CI remain open | [T-278](Tickets/T-278.md), [T-280](Tickets/T-280.md) |
| [T-272 · Remove appearance-only UI test assertions; require visual inspection](Tickets/T-272.md) | Done | Appearance-only oracles retired; real screenshots inspected, 50 native logs and 33 Python checks pass; [full audit](evidence/T-272-2026-11-23-visual-test-audit.md). Original dock/ColorPicker UX remains for owner T-250 | — |
| [T-251 · Fix dock toggle placement/overlap](Tickets/T-251.md) | Done | **P0 owner correction complete:** [native/Atlas focus, geometry and scale evidence](evidence/T-251-2026-11-22-dock-toggle.md); T-250 owner review still pending | [T-222](Tickets/T-222.md) |
| [T-252 · Commit deliberate recent colors and remove Restore previous](Tickets/T-252.md) | Done | **P0 correction complete:** [color gesture and native/Atlas evidence](evidence/T-252-2026-11-22-recent-colors.md); T-250 owner review outstanding | [T-226](Tickets/T-226.md) |
| [T-271 · Restore native Object-source discovery CI and Atlas browser identity](Tickets/T-271.md) | Done | **P1 engineering:** [Rust build, 56 model, 27/20 X11 UI and 24 Atlas identity/host history](evidence/T-271-2026-11-23-object-sources-ci.md); T-065/T-059/T-250 owner and T-094/T-180 hosted gates remain open | [T-093](Tickets/T-093.md), [T-120](Tickets/T-120.md), [T-153](Tickets/T-153.md) |
| [T-270 · Restore required-native T-091 floating-dock CI and Atlas rollback](Tickets/T-270.md) | Done | **P1 engineering:** [Rust build, 44/53 X11 floating/grip and 8 Atlas cancellation](evidence/T-270-2026-11-23-floating-native-ci.md); T-091/T-083/T-250 review and hosted CI remain open | [T-091](Tickets/T-091.md), [T-153](Tickets/T-153.md), [T-257](Tickets/T-257.md) |
| [T-269 · Restore native T-089 layer UI CI and Atlas group/history verification](Tickets/T-269.md) | Done | **P1 engineering:** [63 model, 36 X11, 27 Atlas framebuffer/global-history/Save/Open](evidence/T-269-2026-11-22-native-layers-ci.md); T-059/T-250 owner UX and T-094/T-180 hosted gates open | [T-089](Tickets/T-089.md) |
| [T-268 · Restore required-native T-096 large Move and Atlas history CI](Tickets/T-268.md) | Done | **P1 engineering:** [13,847 model, 34 native X11, 22 Atlas signed large Move/Undo/Redo/Save/Open](evidence/T-268-2026-11-22-large-move-ci.md); T-096/T-149 and T-250 gates open | [T-267](Tickets/T-267.md), [T-253](Tickets/T-253.md) |
| [T-267 · Restore required-native selection/contour on-demand CI](Tickets/T-267.md) | Done | **P1 engineering:** [native clean build, 52/52 Selection, seven signed contours, X11 dense Delete, Atlas history](evidence/T-267-2026-11-22-native-selection-ci.md); T-088/T-149 and owner gates remain open | [T-153](Tickets/T-153.md), [T-210](Tickets/T-210.md), [T-253](Tickets/T-253.md) |
| [T-266 · Restore required-native viewport-cache CI and settled cold preview tests](Tickets/T-266.md) | Done | **P1 engineering:** [native build, T-086 153/153, T-137 19/19, current RGBA8 renderer hash/CI contracts](evidence/T-266-2026-11-22-native-viewport-ci.md); T-086/T-149/T-250 gates remain open | [T-153](Tickets/T-153.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md), [T-137](Tickets/T-137.md) |
| [T-265 · Close visible document tabs correctly under horizontal overflow](Tickets/T-265.md) | Done | **P1 engineering:** [fail-first native Drawing/Atlas close-target and clean-tab safety](evidence/T-265-2026-11-22-document-tab-close.md); owner T-059/T-250 review unchanged | [T-090](Tickets/T-090.md), [T-120](Tickets/T-120.md) |
| [T-264 · Recover lost mouse-up from right-dock icon/group gestures](Tickets/T-264.md) | Done | **P1 engineering:** [standalone X11 and Atlas pointer fail-first/rollback evidence](evidence/T-264-2026-11-22-dock-release.md); T-091/T-083/T-250 gates open | [T-251](Tickets/T-251.md), [T-254](Tickets/T-254.md), [T-259](Tickets/T-259.md) |
| [T-263 · Make held-stroke test fail-closed on older POSIX shells](Tickets/T-263.md) | Done | **P1 engineering:** [restricted-shell fail-first, real Make process controls and 81/144 native evidence](evidence/T-263-2026-11-22-make-bash-shell.md); T-085/T-094/T-250 gates unchanged | [T-262](Tickets/T-262.md) |
| [T-262 · Build native Brush for T-085 held-preview CI and enforce full log coverage](Tickets/T-262.md) | Done | **P1 engineering:** [native build, strict 81/144 checks, nine 840-sample replays and CI contracts](evidence/T-262-2026-11-22-live-stroke-ci.md); T-085/T-094 hosted/physical gates open | [T-204](Tickets/T-204.md), [T-153](Tickets/T-153.md) |
| [T-261 · Cancel interrupted ColorPicker previews and recover fresh presses](Tickets/T-261.md) | Done | **P1 engineering:** [fail-first standalone/Atlas X11 evidence](evidence/T-261-2026-11-22-color-interruption.md); T-250/T-059 owner review unchanged | [T-252](Tickets/T-252.md) |
| [T-253 · Fix remaining end-to-end Selection Delete frame stall](Tickets/T-253.md) | Done | **P0 engineering Done:** [X11 input-to-frame fail-first and exact RGBA8/Atlas evidence](evidence/T-253-2026-11-22-dense-selection-delete.md); owner hardware under T-250 still open | [T-221](Tickets/T-221.md) |
| [T-255 · Prevent hidden floating tabs from intercepting grip/close](Tickets/T-255.md) | Done | **P1 engineering complete:** [fail-first standalone/Atlas native evidence](evidence/T-255-2026-11-22-clipped-floating-tabs.md); T-091 physical UX and T-250 owner gates open | [T-225](Tickets/T-225.md), [T-254](Tickets/T-254.md) |
| [T-256 · Floating icon-tab RMB and keyboard context parity](Tickets/T-256.md) | Done | **P1 engineering complete:** [fail-first X11 and Atlas proof](evidence/T-256-2026-11-22-floating-context.md); T-091 physical and T-250 owner gates open | [T-225](Tickets/T-225.md), [T-255](Tickets/T-255.md) |
| [T-259 · Recover missing floating mouse-up without focus loss](Tickets/T-259.md) | Done | **P1 engineering complete:** [fail-first standalone/Atlas pointer evidence](evidence/T-259-2026-11-22-lost-release.md); T-091 physical Windows/Linux and T-250 owner gates open | [T-258](Tickets/T-258.md) |
| [T-258 · Cancel floating gestures on OS/application focus loss](Tickets/T-258.md) | Done | **P1 engineering complete:** [fail-first standalone/Atlas focus-loss proof](evidence/T-258-2026-11-22-focus-loss.md); T-091 physical Windows/Linux and T-250 owner gates open | [T-257](Tickets/T-257.md) |
| [T-257 · Restore floating move/resize geometry on Escape](Tickets/T-257.md) | Done | **P1 engineering complete:** [fail-first standalone/Atlas native proof](evidence/T-257-2026-11-22-floating-cancel.md); T-091 physical and T-250 owner gates open | [T-225](Tickets/T-225.md), [T-256](Tickets/T-256.md) |
| [T-254 · Use icon-only tabs in minimized panel flyouts](Tickets/T-254.md) | Done | **P0 engineering complete:** [X11/Atlas/icon/keyboard evidence](evidence/T-254-2026-11-22-flyout-icons.md); owner acceptance remains T-250 | [T-225](Tickets/T-225.md) |
| [T-221 · Profile and fix slow selection Delete](Tickets/T-221.md) | Done | **P0 / #1 owner queue completed.** [Measured evidence](evidence/T-221-2026-11-22-selection-delete.md): sparse Delete p50 1,212.5 → 21.3 ms native X11; owner hardware review remains in T-088 | [T-053](Tickets/T-053.md) |
| [T-222 · Replace giant dock minimize chrome with compact icon interactions](Tickets/T-222.md) | Done | **P0 / #2 completed.** [Native/Atlas evidence](evidence/T-222-2026-11-22-dock-interactions.md): vector edge overlay, icon actions and scaling; T-083 owner review open | [T-079](Tickets/T-079.md) |
| [T-226 · Redesign Colors with focused FG/BG, recent-color bars and inline scrollable native picker](Tickets/T-226.md) | Done | **P0 / #3 completed.** [Model/native/Atlas evidence](evidence/T-226-2026-11-22-inline-colors.md): canonical RGBA8 history; inline native picker, narrow/floating scroll; parent T-092 review still open | [T-063](Tickets/T-063.md) |
| [T-223 · Replace named group headers with half-width triangle markers](Tickets/T-223.md) | Done | **P0 / #4 completed.** [Native/Atlas evidence](evidence/T-223-2026-11-22-group-marker.md): 24px vector marker, shared collapse, whole-group drag/menu, scaling and persistence; T-083 owner review open | [T-222](Tickets/T-222.md) |
| [T-224 · Group panels by icon proximity while keeping panel and group drags distinct](Tickets/T-224.md) | Done | **P0 / #5 completed.** [Native/model/Atlas evidence](evidence/T-224-2026-11-22-icon-proximity.md): icon-only grouping, colored merge/reorder/split hints, floating one-group transfer, rollback and persistence; T-083 owner review remains open | [T-223](Tickets/T-223.md) |
| [T-225 · Use dock-style panel icons instead of text in floating tabs](Tickets/T-225.md) | Done | **P1 / #6 completed.** [Native/Atlas evidence](evidence/T-225-2026-11-22-floating-icons.md): same SVG/fallback icons, pressed/focus, pointer/keyboard, drag/grip, restart and scaling; T-091/T-083 physical/owner review open | [T-081](Tickets/T-081.md) |
| [T-227 · Compact the Brushes selector and expose verified libmypaint parameters](Tickets/T-227.md) | Done | **P1 / #7 completed.** [Native/model/Atlas evidence](evidence/T-227-2026-11-22-compact-brushes.md): compact native preview grid, 1–8 mapped dabs/actual radius, frozen queued/native strokes and strict preset preferences; T-095/T-059 owner hardware remains open | [T-184](Tickets/T-184.md) |

| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Blocked | Completed scope; see ticket evidence | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md), [T-250](Tickets/T-250.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-024 · Line](Tickets/T-024.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-025 · Polygon](Tickets/T-025.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Blocked | Completed scope; see ticket evidence | [T-250](Tickets/T-250.md) |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Blocked | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md), [T-250](Tickets/T-250.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Blocked | Completed scope; see ticket evidence | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md), [T-250](Tickets/T-250.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |

## 5. Blocked by dependencies or future owner review

T-096 is blocked on T-149 because the pending native source/preview path would invalidate review evidence from the previous implementation.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |


| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md), [T-250](Tickets/T-250.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | Completed scope; see ticket evidence | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md), [T-250](Tickets/T-250.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md), [T-250](Tickets/T-250.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-250](Tickets/T-250.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Completed scope; see ticket evidence | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md), [T-250](Tickets/T-250.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | Completed scope; see ticket evidence | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md), [T-250](Tickets/T-250.md) |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Completed scope; see ticket evidence | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md), [T-250](Tickets/T-250.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md), [T-250](Tickets/T-250.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Completed scope; see ticket evidence | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md), [T-250](Tickets/T-250.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | Completed scope; see ticket evidence | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md), [T-250](Tickets/T-250.md) |
| [T-096 · Accurate selection contours and responsive Move](Tickets/T-096.md) | Blocked | Native source/Move revalidation before physical owner review | [T-053](Tickets/T-053.md), [T-149](Tickets/T-149.md) |


## 6. Previously completed, retained as historical evidence

**Done is historical delivery, not an endorsement of the old architecture.** T-084, T-097–T-101 and T-104 are valid completed research/implementation records but their optional-native/GDScript-default and Legacy pixel-parity recommendations are superseded. T-102/T-103 and T-124–T-145 retain useful tests and user-facing behavior; T-149/T-150 must adapt relevant tests rather than ship obsolete fallback code.

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | Completed scope; see ticket evidence | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | Completed scope; see ticket evidence | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | Completed scope; see ticket evidence | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | Completed scope; see ticket evidence | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | Completed scope; see ticket evidence | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | Completed scope; see ticket evidence | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | Completed scope; see ticket evidence | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | Completed scope; see ticket evidence | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | Completed scope; see ticket evidence | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | Completed scope; see ticket evidence | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | Completed scope; see ticket evidence | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | Completed scope; see ticket evidence | — |
| [T-022 · Move](Tickets/T-022.md) | Done | Completed scope; see ticket evidence | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | Completed scope; see ticket evidence | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | Completed scope; see ticket evidence | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | Completed scope; see ticket evidence | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | Completed scope; see ticket evidence | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | Completed scope; see ticket evidence | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | Completed scope; see ticket evidence | [T-001](Tickets/T-001.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | Completed scope; see ticket evidence | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | Completed scope; see ticket evidence | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | Completed scope; see ticket evidence | [T-051](Tickets/T-051.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | Completed scope; see ticket evidence | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | Completed scope; see ticket evidence | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | Completed scope; see ticket evidence | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | Completed scope; see ticket evidence | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | Completed scope; see ticket evidence | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | Completed scope; see ticket evidence | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | Completed scope; see ticket evidence | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | Completed scope; see ticket evidence | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | Completed scope; see ticket evidence | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | Completed scope; see ticket evidence | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | Completed scope; see ticket evidence | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | Completed scope; see ticket evidence | [T-079](Tickets/T-079.md) |
| [T-260 · Restore floating-dock width regression after toggle redesign](Tickets/T-260.md) | Done | **P1 engineering:** [71 native checks and clean-native workflow](evidence/T-260-2026-11-22-dock-width-regression.md); T-250/T-083/T-091 review unchanged | [T-081](Tickets/T-081.md), [T-251](Tickets/T-251.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | Completed scope; see ticket evidence | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | Completed scope; see ticket evidence | [T-081](Tickets/T-081.md) |
| [T-084 · Scout PhotoCraft live-paint pipeline](Tickets/T-084.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-052](Tickets/T-052.md) |
| [T-089 · Layer hierarchy, row eye/lock and undo](Tickets/T-089.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-093 · Discoverable Object source/open workflows](Tickets/T-093.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-097 · 96px full-canvas Brush correctness and profiling baseline](Tickets/T-097.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-053](Tickets/T-053.md) |
| [T-098 · Incremental detached Brush preview compositing](Tickets/T-098.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-099 · Frame-safe Brush input draining and held-preview scheduling](Tickets/T-099.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-100 · Bounded sparse atomic Brush publication and Undo](Tickets/T-100.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-101 · Optional NativeHard and Hokusai end-to-end throughput](Tickets/T-101.md) | Done | Historical completed evidence; legacy implementation no longer policy | [T-097](Tickets/T-097.md) |
| [T-102 · Cold dense viewport first-population performance](Tickets/T-102.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-103 · Zoom-out, cache-budget and large-layer viewport stress](Tickets/T-103.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-104 · Operation-specific native raster backend decision](Tickets/T-104.md) | Done | Historical backend research; 2026-11-12 GDScript-default choice superseded | [T-052](Tickets/T-052.md), [T-097](Tickets/T-097.md) |
| [T-109 · Production-scale Asset Browser and filesystem hardening](Tickets/T-109.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-110 · Byte-exact UTF-8 authorization for portable Object sources](Tickets/T-110.md) | Done | Completed scope; see ticket evidence | [T-109](Tickets/T-109.md) |
| [T-111 · Line release target identity and layer eligibility](Tickets/T-111.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-112 · Atlas Line/Polygon portable Save/Open regression](Tickets/T-112.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-113 · Bucket same-ID map/floor release authorization](Tickets/T-113.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-114 · Polygon registered campaign/map/floor authorization](Tickets/T-114.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-115 · Text modal registered campaign/map/floor authorization](Tickets/T-115.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-116 · Atlas Text portable Save/Open regression](Tickets/T-116.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md) |
| [T-117 · Wall Path registered campaign/map/floor authorization](Tickets/T-117.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-118 · Wall Path portable Save/Open and mask-context regression](Tickets/T-118.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md), [T-066](Tickets/T-066.md), [T-117](Tickets/T-117.md) |
| [T-119 · GM Token registered source authorization](Tickets/T-119.md) | Done | Completed scope; see ticket evidence | [T-028](Tickets/T-028.md) |
| [T-120 · Conventional File/Object menus and unified Open](Tickets/T-120.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md), [T-093](Tickets/T-093.md) |
| [T-121 · Single-snapshot bounded raster Open](Tickets/T-121.md) | Done | Completed scope; see ticket evidence | [T-120](Tickets/T-120.md) |
| [T-122 · Historical T-107 CI replay source integrity](Tickets/T-122.md) | Done | Completed scope; see ticket evidence | [T-053](Tickets/T-053.md) |
| [T-123 · Predecode bounded PNG/WebP/JPEG geometry](Tickets/T-123.md) | Done | Completed scope; see ticket evidence | [T-121](Tickets/T-121.md) |
| [T-124 · Ordered queued Brush/Eraser during release drain](Tickets/T-124.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-099](Tickets/T-099.md), [T-100](Tickets/T-100.md) |
| [T-125 · Block stale Save/Close of pending Brush edits](Tickets/T-125.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-124](Tickets/T-124.md) |
| [T-126 · Guard pending Brush edits against document switches](Tickets/T-126.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md) |
| [T-127 · Guard Undo/Redo against pending Brush revision conflict](Tickets/T-127.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-124](Tickets/T-124.md), [T-125](Tickets/T-125.md), [T-126](Tickets/T-126.md) |
| [T-128 · Guard History list jumps during pending Brush drain](Tickets/T-128.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-127](Tickets/T-127.md) |
| [T-129 · Guard concurrent layer and clipboard edits during Brush drain](Tickets/T-129.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-128](Tickets/T-128.md) |
| [T-130 · Guard selection and frame source context during Brush drain](Tickets/T-130.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-129](Tickets/T-129.md) |
| [T-131 · Preserve Object rename and variant metadata on rejected publication](Tickets/T-131.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md) |
| [T-132 · Bind asynchronous Save As to its originating document](Tickets/T-132.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-120](Tickets/T-120.md), [T-131](Tickets/T-131.md) |
| [T-133 · Guard standalone OS window-close against unsaved state](Tickets/T-133.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-125](Tickets/T-125.md), [T-132](Tickets/T-132.md) |
| [T-134 · Bind authoring dialogs to originating document and layer](Tickets/T-134.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-132](Tickets/T-132.md) |
| [T-135 · Sparse indexed committed viewport traversal](Tickets/T-135.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-103](Tickets/T-103.md) |
| [T-136 · Indexed detached-preview plus committed sparse traversal](Tickets/T-136.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-135](Tickets/T-135.md) |
| [T-137 · Bounded cold detached-preview population](Tickets/T-137.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-102](Tickets/T-102.md), [T-136](Tickets/T-136.md) |
| [T-138 · Over-budget detached-preview focal retention](Tickets/T-138.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-103](Tickets/T-103.md), [T-136](Tickets/T-136.md) |
| [T-139 · Bounded sparse explicit-mask selection outlines](Tickets/T-139.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md) |
| [T-140 · Focal-first over-budget selection outlines](Tickets/T-140.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md) |
| [T-141 · Occupied sparse-mask overflow outlines](Tickets/T-141.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-139](Tickets/T-139.md), [T-140](Tickets/T-140.md) |
| [T-142 · Preserve overlapping contour tiles after an in-window pan](Tickets/T-142.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-140](Tickets/T-140.md), [T-141](Tickets/T-141.md) |
| [T-143 · Reconcile saturated contour cache for sub-tile clipped pans](Tickets/T-143.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md) |
| [T-144 · Reuse bounded outline candidate plans across deferred frames](Tickets/T-144.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-141](Tickets/T-141.md), [T-143](Tickets/T-143.md) |
| [T-145 · Retain eligible contours across shifted selection tile windows](Tickets/T-145.md) | Done | Completed safety/display proof; revalidate where native seam changes | [T-053](Tickets/T-053.md), [T-142](Tickets/T-142.md), [T-143](Tickets/T-143.md), [T-144](Tickets/T-144.md) |
| [T-181 · Keep native preview display tiles visible during movement](Tickets/T-181.md) | Done | [19-check fail-first/green framebuffer and hosted Xvfb evidence](evidence/T-181-T-182-2026-11-17-preview-and-presets.md); cold-cache neighbors pass; T-095/T-149 remain open | [T-153](Tickets/T-153.md) |
| [T-182 · Expose native brush preset controls](Tickets/T-182.md) | Done | [Hard Round/Soft/Ink/Airbrush, 96px UI, 16 native-control and 75 compact-workspace checks](evidence/T-181-T-182-2026-11-17-preview-and-presets.md); hosted cold checks pass | [T-153](Tickets/T-153.md) |

## 7. Archived work

| Ticket | Status | Scope / next gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | Completed scope; see ticket evidence | — |


## Maintenance and proof

Ticket state/dependencies live in YAML frontmatter. Add each ticket exactly once to this Index; update it whenever status or dependency changes and run `python3 tools/validate_ticket_store.py`. A manual gate cannot be self-approved; an archived or superseded recommendation is not a completed native implementation. Historical T-107/T-122 46-check replay must remain pinned to its original workflow, while new T-106/T-107 required-native CI must report its real contemporary check inventory.
