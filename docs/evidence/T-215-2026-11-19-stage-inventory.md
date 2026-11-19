# T-215 — reject undeclared source-stage directories and special nodes

**2026-11-19**, PR #21 `sprint/2026-11-17`; exact source SHA-256 and retained
process-log hashes are in [the evidence manifest](T-215-2026-11-19-stage-inventory-raw/manifest.json).

## Reproduced defect

On the pre-fix T-214 source, `inspect_stage()` assembled its inventory using
`Path.is_file()` and skipped all other paths except symlinks. Consequently an
otherwise valid native Drawing stage was approved with:

- An extra empty top-level `unrelated/` or `addons/other/` folder.
- A FIFO under `tests/` or `.godot/imported/`.

The new regression tests failed five subtest assertions in the original
17-test package suite (exit 1). These are *staging* validation defects, not
faults in the native renderer. The baseline stderr is in `fail-first.log`.

## Implementation

`tools/benchmarks/t068_release_gate.py` now inspects every entry in the
standalone stage, before reading required content or allowing the native packager
to publish a library. It rejects symlinks, all non-regular nodes (including
FIFOs and Unix sockets), and directory paths outside the previously documented
Drawing source/asset/test and Godot cache trees. Existing manifest mapping,
required files, native ELF verification and source-file allowlist checks remain.
Generated empty nested `.godot` directories and canonical Drawing script/test
subtrees continue to be valid. A new socket test and package-unchanged check
cover additional failure modes.

## Validation

| Check | Observed result |
| --- | --- |
| Original `python3 -m unittest discover -s tests -p test_t201_linux_native_package.py -v` with new tests but old inspector | Five failed subtests; exit 1 |
| Final focused packaging suite | 18 tests passed; exit 0 |
| `make python-test` configured seven suites | 70 tests passed; exit 0 |
| Vendored offline `bash tools/build_native_brush.sh --test` | 35 native Rust tests passed; exit 0 |
| Fresh `build_drawing_app.stage()` and `inspect_stage()` | 522 real staged files and required native library verified; exit 0 |
| Existing real beta3 ELF/PCK/native distribution plus isolated `launch_linux()` | Native ABI check and separate app launch passed; zero leak diagnostics; exit 0 |
| Pinned Ruff on both modified Python files | Passed; exit 0 |
| Pinned ty on the Makefile's configured targets | Passed; exit 0 |
| Ruff format check on modified test fixture | Passed; exit 0 |
| `python3 tools/validate_ticket_store.py` | 215 tickets and review dependencies validated; exit 0 |

The complete old `t068_release_gate.py` file has unrelated pre-existing Ruff
format differences and an unchanged standalone ty inferred-dict assignment
diagnostic; the **configured** check targets pass, and the modified test file
itself is formatted. No unrelated wholesale formatting or typing change was
included in this ticket.

This real PCK test uses the supplied Godot 4.8 beta3 executable as the Linux
ELF surrogate, **not official release templates**. T-105/T-106/T-180 hosted
CI, Windows runtime, physical-device and owner UX acceptance remain open.

## Raw data

The [raw evidence directory](T-215-2026-11-19-stage-inventory-raw/)
contains the fail-first trace, final focused and configured Python runs, Rust
output, real stage/launch reports, lint checks, ticket validator and per-file
SHA-256 manifest. No source or staging binaries were added to Git LFS.
