# T-216 — Effective standalone project identity and launch scene

**Date:** 2026-11-19. **Branch:** `sprint/2026-11-17`. The exact SHA-256
of the final modified Python and documentation files, raw logs and process
results are in [the evidence manifest](T-216-2026-11-19-project-identity-raw/manifest.json).

## Reproduced defect

On the T-215 code, `inspect_stage()` searched the entire `project.godot` text for
`config/name="Drawing"`. The new test reproduced **six failed subtests** on that
baseline (`python3 -m unittest discover -s tests -p test_t201_linux_native_package.py -v`,
exit 1): a commented matching name, a name in an unrelated section, duplicate
conflicting names, a second `[application]` section, an unrelated startup
scene, and a commented matching startup scene. The old inspector accepted
all six. See `fail-first.log` for the original assertions and process result.

## Implementation

`tools/benchmarks/t068_release_gate.py` now reads the effective keys from a
single `[application]` section, ignoring other sections and comments. Duplicate
`config/name` or `run/main_scene` settings and duplicate application sections
fail explicitly. The required identity is `"Drawing"`, and the required startup
scene is `"res://main.tscn"`. This checks the existing standalone consumer
contract rather than trusting matching text in a comment.

The T-201 package regression now confirms that all six invalid stages are
rejected **before** an ELF/PCK byte changes or a native `.so` or temporary
preflight directory appears. The canonical stage still packages normally.

## Validation

| Command / check | Observed result |
| --- | --- |
| Final `python3 -m unittest discover -s tests -p test_t201_linux_native_package.py -v` | 19 passed, exit 0 |
| `python3 -m unittest discover -s tests -p test_t068_release_gate.py -v` | 6 passed, exit 0 |
| `make python-test` | Seven configured suites; **71 tests** passed, exit 0 |
| Offline vendored `bash tools/build_native_brush.sh --test` | 35 Rust tests passed, exit 0 |
| Actual 522-file native standalone stage `inspect_stage()` | Passed, exit 0 |
| Previously exported real Godot beta3 PCK with required native library, `launch_linux()` | Two isolated zero-exit launches, native ABI verified, 0 leak diagnostics |
| Pinned `ruff check` on changed Python files; `ruff format --check` modified test | Passed, exit 0 |
| Pinned `ty check` on Makefile-configured Python targets | Passed, exit 0 |
| `python3 tools/validate_ticket_store.py` | 216 tickets and review gates validated, exit 0 |

The stage and PCK are independently retained real artifacts; the test fixture
also creates a synthetic ELF/PCK for negative cases. The real isolated launch
uses the supplied Godot 4.8 beta3 executable paired with its PCK, **not** an
official Linux release-template binary. No Windows-native runner or hosted CI
was exercised. This ticket does not meet T-105/T-106/T-180 gates or the
physical-device and manual-owner approvals.

## Retained raw evidence

[Raw evidence directory](T-216-2026-11-19-project-identity-raw/) includes the
fail-first output, final packaging/release/configured-Python/Rust checks,
Ruff/ty/format checks, real stage and launch report, ticket-validator output,
and a file/source SHA-256 manifest. No binary assets were added to Git LFS.
