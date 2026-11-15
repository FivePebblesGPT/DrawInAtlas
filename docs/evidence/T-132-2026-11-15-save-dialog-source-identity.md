# T-132 — Asynchronous Save As callback ownership (2026-11-15)

## Reproducible defect and scope

On the exact parent commit `c9522fea43815eb07b6dcb9c470bf7bb82898122`
(T-131), `DrawingWorkspace` connected `FileDialog.file_selected` straight to
`_save_file(path)` and the hosted Object variant confirmation straight to
`_save_as_named_object()`. Both methods looked up `active_tab` when the delayed
callback fired. Switching to another tab, closing the original tab and reusing
its index, or cancelling the chooser could therefore direct the stale
confirmation to the wrong Drawing document or Object Editor session. The
result was a cross-document overwrite or unauthorized source/variant publish.

**Change:** the canonical `addons/drawing/workspace.gd` records the original
active tab index, exact `DrawingDocument` reference and exact Object session
when opening either Save As dialog. Every asynchronous completion checks all
three identities before writing a path, publishing an asset or staging
metadata. Cancelling a chooser revokes its authority and clears pending
save-and-close intent. Rejected callbacks fail visibly. Trusted direct Save,
valid FileDialog Save As, local Object source Save As and hosted named Object
publication remain supported; T-131's failed-publisher metadata rollback
remains intact.

## Deterministic red/green control

- **Source:** exact T-131 parent Git tree in a detached clean checkout.
  The new `drawing/tests/t132_dialog_document_identity_smoke.gd` was copied in
  exclusively as a red control; this did not import the candidate runtime
  change. The detached standalone Drawing package was staged using
  `python3 tools/build_drawing_app.py --in-place` and imported using the
  pinned Godot engine before executing the test.
- **Engine:** `Godot 4.8.beta3.official.c51ff06e8` from the supplied bundle,
  native-absent Linux headless mode, dummy audio.
- **Representative execution:**

  ```sh
  GODOT=/mnt/data/work/bundle8/Godot_v4.8-beta3_linux.x86_64
  "$GODOT" --headless --audio-driver Dummy --editor --path drawing --import --quit
  "$GODOT" --headless --audio-driver Dummy --path drawing \
    --script res://tests/t132_dialog_document_identity_smoke.gd \
    > /tmp/t132-dialog.log 2>&1
  python3 tools/check_godot_model_log.py /tmp/t132-dialog.log \
    --marker T132_DIALOG_PASSED
  ```

  On the unmodified source the test exits nonzero with
  `T132_DIALOG_FAILED checks=34 failures=14` (expected negative control).
  SHA-256 of raw red log:
  `0691cdeb7c6be91fad060cd31965ff4458beed61863d96af84248545cde9de18`.
  The rejected cases include cross-tab overwrite and path binding, chooser
  cancellation, tab-index reuse, incorrect local Object publication, and
  wrong hosted Object variant publisher.

  On the candidate the same test exits zero and prints exactly
  `T132_DIALOG_PASSED checks=34 failures=0`. Strict
  `tools/check_godot_model_log.py` accepts the result; SHA-256 of raw green
  log: `84c5686a48ef28e6f4d53cc78c92430961d97d7d1313d42375c57c8412a28592`.
  Assertions cover exact portable saved RGBA8 from the originating document,
  unchanged sentinel destination bytes, normal direct Save, local Object
  FileDialog, named hosted variant dispatch, and cancellation of pending
  close-after-save. An initial local rerun lacked freshly imported SVG
  resources and produced parser/asset errors; it was rerun after the required
  Godot import and **is not** counted as a pass.

## Adjacent checks and CI

- T-131 Object metadata, **21/21**; T-125 persistence guards, **29/29**;
  T-126 tab switching, **34/34**; T-120 File/Open and T-121 bounded image
  snapshot, passing strict headless logs; Drawing Object Editor UI,
  **26/26**; standalone Drawing smoke, **42/42**.
- Atlas Object Editor smoke, **45/45**, after root-project Godot resource
  import. Native software-rendered X11 File/Object menu witness, **20/20**;
  strict native log verifier passed.
- Independent *native-absent* Drawing consumer staged to a fresh destination,
  Godot imported, and standalone smoke passed **42/42**.
- Python source and strict CI contracts, including the new
  `tests/test_t132_dialog_document_identity.py`, passed; explicit GDScript
  typing and canonical ticket-store validation passed (**132** tickets).
- The new Godot smoke and Python contracts run inside the existing required
  `ci_t085_live_stroke_preview` workflow step. The exact marker and
  `checks=34 failures=0` are both required, without increasing the
  existing **46** unique check IDs or weakening the fail-late policy.
- The extra T-124 queued-Brush run exceeded the batch timeout before a
  final success marker; it is **unverified**, not a passing regression.

## Limits and manual gates

Godot's recognized post-process renderer/Resource RID leak diagnostics appear
**after** the success marker and remain visible in raw logs; unrelated script
errors are not suppressed. Test callbacks are dispatched with real Godot
signals in headless mode; this does not prove physical interaction with each
operating system's native file picker, or a hosted CI green run. No owner
physical-hardware UX/latency approval is claimed. T-095, T-056/T-059 and
T-106/T-107 remain independent open integration/hosted/manual gates.
