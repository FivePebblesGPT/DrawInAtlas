# T-134 — stale authoring confirmation source binding

Date: 2026-11-15 · Branch: `sprint/2026-11-14` · Godot: pinned 4.8 beta3

## Defect and negative control

The canonical `addons/drawing/workspace.gd` bound each authoring dialog's
`confirmed` signal directly to a method that mutates `current_document()` or
`current_object()`. T-132's protected Save As chooser did not cover these
six dialogs. A captured edit could instead modify an unrelated active tab,
including an Object source, or replay after cancellation.

The `drawing/tests/t134_authoring_dialog_identity_smoke.gd` oracle uses real
shared Drawing workspaces, two distinct Drawing/Objects tabs, and real
`ConfirmationDialog.confirmed` signals. It checks tab switches, selected-row
changes, cancellation, tab-index reuse, visible rejection, and legitimate
same-origin confirmation across all six dialogs.

Red control: staged unchanged T-133 `workspace.gd` into the ignored standalone
`drawing/addons/drawing/` directory, then ran:

```sh
timeout 85s godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t134_authoring_dialog_identity_smoke.gd
```

**Exit 1, 9/22 assertions failed** on the final red run. The failures were
cross-tab layer rename, editable Text publication, image-frame mutation, grid
mutation, cancelled late rename, changed layer target, Object rename, Object
frame, and lack of a visible stale-dialog refusal. The initial unreimported
red environment also lacked the imported font; final comparator and candidate
were run after importing bundled resources. No owner device behavior was
inferred from either.

## Implementation

The shared workspace now maintains an in-memory per-dialog authoring target
captured at opening (tab index, exact document and Object session, selected
layer/node and revision). Each dialog's UI signal routes through a dedicated
confirmation wrapper that **consumes** this authority before invoking its
original edit method. Cancellations clear it; layer/Text require unchanged
source selection and revision. The other dialogs require the originating tab,
document and Object session. Direct edit methods remain intact for the
existing independent model tests. Invalid confirmations fail visibly without
changing either document or view. No new native dependency or file format.

## Execution and regression evidence

```sh
python3 tools/build_drawing_app.py --in-place --without-native
godot --headless --audio-driver Dummy --editor --path drawing --import
set -o pipefail
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t134_authoring_dialog_identity_smoke.gd 2>&1 | tee /tmp/t134.log
python3 tools/check_godot_model_log.py /tmp/t134.log --marker T134_DIALOG_PASSED
xvfb-run -a -s '-screen 0 1600x900x24' godot \
  --rendering-driver opengl3 --audio-driver Dummy --path drawing \
  --script res://tests/t134_authoring_dialog_identity_smoke.gd
python3 -m unittest discover -s tests -p 'test_t134_authoring_dialog_identity.py' -v
python3 tools/validate_ticket_store.py
```

- Fixed-headless **22/22**, exit 0, strict log accepted.
- Native X11/Mesa **22/22**, exit 0, strict log accepted. The native runner
  exercises real Godot windows but uses scripted tab changes and software
  rendering; this is not an arbitrary desktop window manager or owner UX pass.
- Neighboring `text_editor_smoke.gd`, `layer_structure_smoke.gd`,
  `image_frame_smoke.gd`, `object_editor_ui_smoke.gd`, T-131, T-132 and T-133
  all exited 0, printed success markers and passed strict log validation.
- A freshly staged **native-absent** standalone Drawing consumer built,
  imported its resources, and passed its `standalone_smoke.gd` with strict
  log verification. Selected T-131 through T-134 Python contract suites
  passed **18/18**; the explicit-typing checker passed **442 GDScript
  scripts and 33 skill documents**. `tools/validate_ticket_store.py`
  accepted **134 canonical tickets**, including all manual-review gates.
- The headless and native Godot runs emitted only the known teardown
  resource-leak diagnostics **after** success; they remain in the raw logs,
  separately classified by `check_godot_model_log.py`.

The exact 22-assertion check is wired into the existing T-085 fail-late CI
step, without changing the 46 required check IDs. Hosted GitHub CI was not
run on this unpushed candidate. Physical latency, cross-platform testing,
owner interaction approval and performance improvements remain unclaimed.
