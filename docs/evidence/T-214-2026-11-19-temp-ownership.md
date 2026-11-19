# T-214 — ownership-safe native export temporary cleanup

**2026-11-19**, PR #21 `sprint/2026-11-17`; source and raw-log SHA-256
values and process exits are in the [manifest](T-214-2026-11-19-temp-ownership-raw/manifest.json).

## Fail-first reproduction

Against the T-213 baseline, three new negative tests in
`tests/test_t201_linux_native_package.py` fail (process exit 1):

1. When the release tree contains a pre-existing `libdrawing_brush.so.tmp`
   regular file, `package()` rejects the unexpected entry but its `finally`
   unlinks that **foreign** file. The regression observes `FileNotFoundError`.
2. The same unexpected symlink is unlinked after preflight rejection even
   though its outside target remains intact.
3. The same unexpected directory triggers the expected strict rejection,
   but the cleanup `unlink` raises `IsADirectoryError`, masking the useful
   `PackageError` and preventing deterministic error handling.

The original error output is retained byte-for-byte in `fail-first.log`.
These were release-tooling failures, not native painting failures.

## Implementation

`package_linux_export.py` now reserves a unique temporary file using
`tempfile.mkstemp` (exclusive creation) **after** preflight. The returned
pathname is saved only after successful allocation; the cleanup handler
unlinks that exact owned path, or nothing if no temporary was allocated.
Copying is performed via the reserved file descriptor, then `copymode`
restores the staged library's permissions before the existing SHA-256
comparison, `os.replace`, exact-tree validation and rollback. A new
fail-first test caught the initial 0600-only `mkstemp` permission regression
(the prior shipped ELF mode was 0755 in the real fixture); the final
package has the same source/library mode. Pre-existing unexpected files, symlinks and directories remain
untouched and fail closed. An additional injected `EIO` during an incomplete
copy verifies cleanup of the allocated file and newly created directories.

## Validation (all commands local)

| Command / check | Observed result |
| --- | --- |
| Three fail-first unit cases before repair | 1 failure + 2 errors; exit 1 |
| Native-file mode regression control on initial exclusive-temp candidate | 0600 vs staged 0644; exit 1, then fixed |
| `python3 -m unittest tests.test_t201_linux_native_package` after repair | 13 tests passed, exit 0 |
| `make python-test PYTHON=python3` after final formatting | 65 tests in 7 suites, all passed, exit 0 |
| Pinned Ruff `check` on the two modified Python files | exit 0 |
| Pinned ty `check` on the same files | exit 0 |
| Pinned Ruff `format --check` on the same files | exit 0 |
| `bash tools/build_native_brush.sh --test` with offline vendored Cargo | 35 Rust tests passed, exit 0 |
| Package an unchanged, previously verified real beta3 PCK/ELF with required staged `.so` | exit 0 |
| T-068 isolated packed-app native ABI smoke (`--launch-linux`) | exit 0, native ABI verified, no exit leaks |
| `python3 tools/validate_ticket_store.py` | 214 tickets validated; exit 0 |

The real PCK inspection and two independent launch phases used the existing
Godot beta3 executable as an ELF surrogate, with a verified native library
and separate working directory/profile. **No official export template** or
Windows-native DLL/runner was available or validated. No hosted GitHub Actions
run, GPU input-to-photon benchmark, standalone release acceptance, or owner
manual review is asserted. T-105/T-106/T-180 and T-095/T-197 remain open.

## Raw evidence

The accompanying `-raw/` directory retains the fail-first and mode-failure logs, configured
Python result, Rust result, lint/format results, packager output and isolated
release report. `manifest.json` binds logs and changed source to SHA-256
values and records observed process exits.
