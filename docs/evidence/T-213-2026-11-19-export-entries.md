# T-213 — exact filesystem entry validation for native exports

**2026-11-19**, PR #21 `sprint/2026-11-17` on Linux x86-64. Evidence and
individual source/log SHA-256 values are recorded in
[the raw manifest](T-213-2026-11-19-export-entries-raw/manifest.json).

## Reproduction before the fix

Two new unit methods produced **6 failing subtests** (exit 1) against the
unmodified T-212 packaging/inspection code. `inspect_distribution` ignored
an unexpected empty directory or FIFO on **both** Linux and Windows. The
packager similarly accepted both and published a new native library without
rejecting their presence. `fail-first.log` retains the original output.

## Fix and invariants

A shared `inspect_distribution_entries` function iterates all export nodes,
not just `Path.is_file()` results. Only expected regular ELF/PCK/native
files and the necessary native-directory ancestors are permitted. Symbolic
links, unregistered empty directories, FIFOs and other non-regular entries
are rejected; missing required artifacts fail. The Linux preflight uses the
same directory policy but permits its not-yet-installed native ELF to be
absent. After preflight the existing byte/ABI/digest and rollback checks are
still authoritative. Rejected packaging leaves its initial tree intact.

No release artifact was modified in place for the successful runtime test;
that test inspected and launched an existing, independently verified beta3
PCK/ELF/native trio under a fresh isolated profile.

## Validation

| Check | Result |
| --- | --- |
| New regression tests on baseline | 6 failures across 2 methods; exit 1 |
| Final release gate + native packaging unit tests | **15/15**, exit 0 |
| T-105 portability tests | **10/10**, exit 0 |
| `make python-test PYTHON=python3` | **61 across seven configured suites**, exit 0 |
| Native `build_native_brush.sh --test` using vendored offline Cargo | **35/35**, exit 0 |
| Ruff 0.17.5 on four changed Python files | exit 0 |
| ty 0.0.104 on configured release-package source/test targets | exit 0 |
| `t068_release_gate.py --launch-linux` on real existing PCK/native | exit 0; `native_abi_verified=true`; zero exit leaks |
| `validate_ticket_store.py` and Git diff | run after documentation update |

The older, previously unformatted release-gate/test files still fail a
*whole-file* Ruff `format --check` because of unrelated formatting present
before T-213. An exploratory standalone ty invocation against the older
`tools/benchmarks/t068_release_gate.py` still reports its existing inferred
`report["linux"]["runtime"]` typing error. Neither is counted as a green
check; scoped Ruff lint and configured ty targets pass. The Windows release
check remains structural only, not a Windows-native runtime acceptance.

## Open gates

No official Godot release-template binary, Windows native DLL/export,
hosted GitHub CI success, GPU timing or owner physical interaction review was
validated. T-105/T-106/T-180/T-197 and native transition tickets remain open.
