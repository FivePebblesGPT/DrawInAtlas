# T-127 — pending Brush history revision safety

Date: 2026-11-15 · branch: `sprint/2026-11-14`

## Bug and bounded implementation

At the verified remote branch baseline `61c6f689974a848f8a7cc4040c98be418518b156`,
T-122–T-126 were still local commits. The starting local T-126 HEAD was
`aab45fc4a12ceab122071f46070fcced45ec8b98`. All prior local commits must
remain included in this turn's remote-relative delivery.

An already released Brush/Eraser stroke can remain in detached staging for many
frames, and T-124 can retain a second gesture behind it. Workspace `_undo()`
or `_redo()` operated directly on the *last committed* document history.
This moved the document revision underneath the uncommitted edit; Canvas
`_process()` then cancelled the stale session and discarded the pending and
queued input. Unlike an explicit Escape cancellation, this lost paint as a
side effect of navigating older history.

`addons/drawing/workspace.gd` now invokes the existing fail-closed
`_can_persist_or_close("Undo"|"Redo")` guard before touching the current
history or floating-selection policy. Keyboard, menu and History-button entry
points call these same routines. No `DrawingDocument` mutation, new native
backend, synchronous drain, binary format or selection policy is introduced.
The user can retry history navigation after the normal queued commit.

## Reproduction and exact controls

Engine: supplied bundle-8 Godot **4.8.beta3.official.c51ff06e8**, Linux
x86-64, headless software renderer. Stage the shared package and import before
running the oracle:

```sh
export PATH=/mnt/data/work/binaries:$PATH
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout 180s godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t127_pending_history_smoke.gd > t127-history.log 2>&1
python3 tools/check_godot_model_log.py t127-history.log \
  --marker T127_HISTORY_PASSED
```

**Red control:** Stage the *unchanged T-126 workspace.gd* over the generated
`drawing/addons/drawing/workspace.gd` and run the exact same new oracle. It
exits **1**, failing **20/40** assertions. Undo removes earlier committed paint
while a long 210-point, 44px Brush and second queued stroke are still pending.
The next Canvas frame cancels both; Redo similarly changes history under an
uncommitted stroke. The failures also capture the previously missing keyboard,
History button and visible warning guards. Original raw-log SHA-256:
`7d8cfa642d1e51878e38cd8a2e57207863143fd157bbf9d090387243db5d0623`.

**Green candidate:** Restage the current shared addon and re-import, then
run the test unchanged. Exit **0**, **40/40** assertions. Both blocked history
commands preserve revision, prior paint, deferred queue and current session
across actual process frames. The two queued paints subsequently commit
independently; two Undos remove exactly those edits while preserving earlier
paint, and Redos restore identical RGBA8 bytes. Save/Open of `.drawing`
compares the final 256×256 RGBA8 image byte-for-byte. A second scenario
checks Redo at an older history cursor; the new edit correctly replaces the
obsolete redo branch. Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z and History buttons are
exercised. Raw-log SHA-256:
`b539751b36f0007d129c31075c68eefc085fe9396ffeae51e2b273312c3c9028`.

Both runs emit the existing post-success Godot dummy-renderer leak diagnostics;
the strict verifier reports them separately and rejects unrelated runtime
errors. The red control's assertion failures are intentional.

## Neighboring regression coverage

| Existing witness | Observed result |
| --- | --- |
| T-124 queued Brush / Eraser history | 69/69 |
| T-125 pending Save/Close/Object | 29/29 |
| T-126 pending tab switches | 34/34 |
| T-085 live-stroke model | Success marker, strict log and zero exit |
| Standalone Drawing model | 42/42 |
| T-095 independent Brush pixel coverage | 32/32 |
| T-120 unified File/Open | Success marker, strict log and zero exit |
| T-121 raster snapshot | Success marker, strict log and zero exit |
| Native X11 T-124 real pointer/framebuffer | 19/19 |
| Native X11 T-095 stroke navigation | 51/51 |
| Native X11 T-120 File/Object | Success marker, strict log and zero exit |

Native X11 uses Xvfb/Mesa `gl_compatibility`, `--audio-driver Dummy`,
`--display-driver x11` with actual GUI tests. It does **not** represent
physical GPU input-to-photon timing or a Windows result. Supplemental local verification:

- Python source/CI/owner suites: **106 test cases, 102 passing, 4 skipped**.
  These include T-120–T-127 (24 tests), fail-late CI (8), T-090 (9),
  T-094 owner matrix (4), Drawing app/contract/core (12, 4 skipped),
  T-107 historical replay audit (10), T-094 hosted evidence (9), owner
  evidence (16), and CI replay (14). All suites exited 0; skipped cases
  reflect unavailable external environment conditions, not assertions.
- Explicit GDScript typing: **435 project scripts and 33 skill documents
  passed** (`python3 tests/check_explicit_types.py`).
- Fresh **native-absent independent Drawing consumer**:
  `python3 tools/build_drawing_app.py --output /mnt/data/work/t127_fresh_consumer
  --without-native`, Godot beta3 resource import, then the external
  `res://tests/standalone_smoke.gd`: **42/42**, zero process exit and strict
  log verifier (known post-exit leaks separately reported).
- `python3 tools/validate_ticket_store.py`: **127 tickets valid**, review
  ancestry intact. `.github/workflows/godot-check.yml` retains exactly **46
  unique `ci_*` IDs**. No fail-late policy exceptions added.


The new oracle is included under existing required fast CI step
`ci_t085_live_stroke_preview`, with `timeout`, strict process/log marker
verification and Python contracts, without adding a 47th required CI ID.

## Completion / limitations

A new hosted 46/46 green run has not been obtained. Neither T-095 physical
reference-hardware latency nor T-056/T-059 UX acceptance is claimed.
T-095 stays In Progress with its explicit owner gate, and T-106/T-107 remain
separate hosted evidence obligations.
