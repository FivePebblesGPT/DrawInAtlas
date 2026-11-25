# T-285 — repeated Godot beta4 native export normalization

**Date:** 2026-11-23. **Branch:** `sprint/2026-11-23-godot-beta4`.
**Before:** local `d8be43d3`, remote `main` baseline
`bbae76c33a6066582b2cd89e07cc3246fef942ce`.

## Failure and mechanism

Godot beta4 already emits `libdrawing_brush.so` at the Linux export root;
commit `3e41dd8e` added verified normalization into
`addons/drawing/native/bin/libdrawing_brush.so` for the **first** export.
When the canonical library was already installed, a repeated beta4 export
introduced the root-level copy again. The old `package()` existing-library
branch called `inspect_distribution()` directly, which rejected the extra
file before considering that it was the matching engine copy.

Three new tests on the original local code produced **1 error + 2 failures**
(28 tests total). The error was `Unexpected export file:
libdrawing_brush.so`; the two failures expected a specific mismatch or a
verified late-inspection rollback rather than the same generic inventory
rejection. Retained [fail-first log](T-285-2026-11-23-reexport-raw/fail-first.log).

## Correction and safety

The only additional accepted intermediate state is the **exact** Linux
inventory `{Drawing.x86_64, Drawing.pck, canonical native ELF, root native
ELF}` when packaging a second export. The new inventory flag is rejected
outside the already-installed Linux re-export case. Both native paths are
checked against the staged native SHA-256; a disposable sibling links the
canonical final ELF/PCK/native projection for full inspection. The root copy
is then moved to a private temporary backup. If the final inspector rejects,
the original root copy is restored, including its bytes/mode. Neither a
bad root copy, corrupt PCK, extra file/directory nor a symlink is removed or
silently normalized. The final distribution still rejects root `.so` files.

## Tests

Run from repository root with Python 3.13.5:

```sh
python3 -m unittest discover -s tests -p 'test_t201_linux_native_package.py' -v
python3 -m unittest discover -s tests -p 'test_t217_pck_index.py' -q
python3 -m unittest discover -s tests -p 'test_t218_pck_payload_integrity.py' -q
python3 -m unittest discover -s tests -p 'test_t219_pck_resource_names.py' -q
python3 -m unittest discover -s tests -p 'test_t220_pck_project_identity.py' -q
python3 -m unittest discover -s tests -p 'test_t228_fast_ci_contract.py' -q
python3 -m unittest discover -s tests -p 'test_t068_release_gate.py' -q
python3 -m unittest discover -s tests -p 'test_t105_portability.py' -q
python3 tools/validate_ticket_store.py
```

| Check | Result | Raw evidence |
| --- | --- | --- |
| Linux packaging, repeat-export pass/mismatch/rollback/symlink/PCK | **29/29 passed** | [package](T-285-2026-11-23-reexport-raw/package-green.log) |
| PCK index | **10/10** | [log](T-285-2026-11-23-reexport-raw/t285-test_t217_pck_index-green.log) |
| PCK payload MD5 | **5/5** | [log](T-285-2026-11-23-reexport-raw/t285-test_t218_pck_payload_integrity-green.log) |
| Packed names | **5/5** | [log](T-285-2026-11-23-reexport-raw/t285-test_t219_pck_resource_names-green.log) |
| Packed project identity | **6/6** | [log](T-285-2026-11-23-reexport-raw/t285-test_t220_pck_project_identity-green.log) |
| Fast CI contract | **3/3** | [log](T-285-2026-11-23-reexport-raw/t285-test_t228_fast_ci_contract-green.log) |
| Release gate | **6/6** | [log](T-285-2026-11-23-reexport-raw/t285-test_t068_release_gate-green.log) |
| Portability contracts | **10/10** | [log](T-285-2026-11-23-reexport-raw/t285-test_t105_portability-green.log) |
| Ruff (three changed Python files), Python byte compilation | Passed | [Ruff](T-285-2026-11-23-reexport-raw/ruff.log) |
| Ty on packager | Passed | [Ty](T-285-2026-11-23-reexport-raw/ty-package.log) |
| Ty on packager + full release gate | Existing diagnostic in `inspect_release` nested report assignment, not introduced here | [diagnostic](T-285-2026-11-23-reexport-raw/ty-release-gate.log) |
| Ticket validation | **285 tickets valid**, review gates retained | [validator](T-285-2026-11-23-reexport-raw/tickets.log) |

## Validation boundaries

No official Godot 4.8 beta4 Linux export templates were available locally,
so this ticket establishes exact synthetic ELF/PCK/native output integrity and
failure-atomic normalization, **not** a fresh real-template exported-app launch.
The full Python discovery run exceeded its execution limit without a test
summary; this is not a claimed pass or failure. The remote main's earlier
first-export packaging failure was already handled by the beta4 upgrade, not
by T-285. Hosted beta4 CI, Windows native release, T-180/T-105 portability and
owner manual-review decisions remain independent gates.
