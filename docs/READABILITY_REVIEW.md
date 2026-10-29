# Readability review — post-milestone 6

This pass refines the implementation introduced in `c46fb66`. It preserves the
existing behavior and public interfaces, including the dialog's three-Resource
draft array and the navigator's dictionary-based history. Fog/projector work is
outside this pass.

Compare with `git diff c46fb66 -- scripts/`. The main change is explicit phases
and contracts, rather than fewer lines or more files.

## Significant refinements

- **Transactions:** `AtlasLinkEdit._replace()` now reads as link validation,
  document lifecycle, destination validation, placement ownership/reuse, scope,
  then mutation. A private `ValidatedChange` record carries prepared objects;
  only `_apply_validated_change()` mutates the campaign or restoration slots.
- **Form conversion:** `AtlasLinkDialog` separates selection loading, displayed
  baselines and link/document/placement construction. Named modes replace numeric
  mode checks; nested ternaries are explicit branches. The coordinator accesses
  semantic dialog operations instead of individual controls for mode/pitch/errors.
- **Capture scheduling:** typed `CaptureRequest` objects replace heterogeneous
  job dictionaries. Parent retention, bounded child selection, async rendering
  and drawing have distinct methods. Frozen-image records retain their existing
  shape; request geometry names identify child and parent coordinate spaces.
- **Input:** canvas gesture/button/press/release/motion handlers expose precedence.
  Wheel accumulation is explicitly separate from the navigator's blocked-step
  gate. Capture generations and destination layer preferences have clearer names.

## Where to review most thoroughly

### 1. Shared placement transactions and ordered undo

Start with `scripts/editing/commands/link_edit.gd`:

- `_replace()` and `_prepare_placement()` establish which objects are expected,
  current, reconstructed or already registered.
- `_resolve_placement_reuse()` distinguishes object identity from exact snapshot
  equality. An unchanged shared placement can be reused; changing its geometry
  through one entrance remains rejected.
- `_apply_validated_change()` and `_insertion_slot()` retain restoration positions
  across apply/revert. Trace both shared and unshared unlink, replacement and redo.

Pay special attention to empty versus malformed snapshots, guarded deletion of a
new destination, and undo bypassing the original selected-cell scope. Those are
deliberate contracts, not interchangeable validation cases.

### 2. Form precision and snapshot/live identity

Read `scripts/interface/link_dialog.gd` in this order:
`_select()` → `_remember_displayed_values()` → `draft()` → `_draft_link()` /
`_draft_placement()` → `_preserved_number()`.

The displayed baseline is recorded **after** populating controls. Untouched
values come from the selection-time snapshot, preserving native precision despite
display rounding. Placement identity is looked up from the current campaign link;
the coordinator still performs stale-form validation before committing. A link
anchor can differ from its placement origin and must not be overwritten merely
because another field changes. Centered arrival remains footprint-only.

`_apply_drag()` preserves the original quantization, including its unquantized
minimum for negative drags. Origin-snapping changes would be behavioral work.

### 3. Cancellation and frozen registration

Review `scripts/interface/map_capture.gd: capture()` alongside
`scripts/interface/map_references.gd: _refresh()`, `_render_request()` and
`_prepare_parent_request()`.

An obsolete request must return before disabling a viewport owned by its
successor. The reference manager must reject an obsolete capture before caching
or publishing it. `captured_rect` describes configured framing, not a guarantee
that an image was successfully returned.

Frozen parents retain both pixels and registration, including while hidden or
after footprint movement. Entrance/floor/source/kind changes invalidate their
context. Parent thumbnails remain independent of the child-preview mode.

### 4. Input fall-through and synchronous callbacks

Read `scripts/interface/canvas.gd: _begin_link_press()`, `_finish_left_release()`,
`_handle_mouse_motion()` and `_consume_wheel()`; then
`scripts/navigation/map_navigator.gd: wheel_step()` and `_consume_boundary_step()`.

A single link click starts movement **and** selects the grid cell; only entering
via double-click consumes that selection path. Release precedence stays link move,
artwork manipulation, battlemap draft, generic artwork. Commit state is cleared
before signals because listeners can synchronously change the active document.
Fractional input and blocked semantic steps are separate state machines; do not
carry overscroll remainders or combine their clocks as incidental cleanup.

The navigator's existing success assumptions in `enter_link()` also deserve a
careful read: destination preferences are nullable by type, and view transition
results are not used for rollback. No normal-user failure was established by the
review, and adding guards/rollback would be a separate behavior change.

## Review provenance and validation

Code-only subagent reviews were instructed to inspect only relevant `.gd`/`.tscn`
implementation and tests, excluding project docs, Markdown, README, AGENTS,
CLAUDE, skills and hidden agent directories. They reported following those access
restrictions. An initial review and follow-up covered transaction/input/capture
code; a fresh reviewer independently inspected the form and reference scheduler.
Their follow-ups found no concrete introduced behavior regression, without
claiming formal proof. They did not modify files or execute tests.

The parent also compared the old and refined implementations directly:

- **108 transaction traces:** apply/revert/reapply results and full campaign
  metadata across creation, sharing, conversion, stale inputs, invalid endpoints
  and selected-cell scope.
- **144 draft cases:** existing/new markers and footprints, native precision,
  centering, short drags and all four rotated drag quadrants. Generated UUIDs
  alone were normalized for comparison.

The temporary differential runner is preserved at
`/tmp/opencode/drawinatlas-simplification-equivalence.gd`; it loads baseline source
from `c46fb66` and is not application or test-suite code.

The unchanged **17 headless suites and four native-renderer suites** pass, as do
startup, Web release export and source/exported-pack save roundtrips. Workflow
lint passes; the scene/reference checker reports zero errors and six existing
addon warnings. No application test was weakened or rewritten for this refactor.
