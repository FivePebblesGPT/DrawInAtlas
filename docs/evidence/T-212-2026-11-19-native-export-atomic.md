# T-212 — failure-atomic required-native Linux export packaging

**2026-11-19**, PR #21 `sprint/2026-11-17`, offline Linux x86-64,
Godot `4.8.beta3.official.c51ff06e8`. All raw logs, hashes and process exits
are in [the evidence directory](T-212-2026-11-19-native-export-raw/).

## Failure reproduced first

`python3 -m unittest discover -s tests -p 'test_t201_linux_native_package.py' -v`
returned **exit 1, two failures out of seven tests** against the prior
`tools/package_linux_export.py`:

1. `test_rejected_export_does_not_leave_partially_installed_library`: a
   distribution containing an extra `.so` failed final inspection **after**
   receiving `addons/drawing/native/bin/libdrawing_brush.so`. An invalid
   `Drawing.pck` has the same late-rejection hazard.
2. `test_late_distribution_rejection_rolls_back_new_native`: a simulated
   inspector failure after publication left the new native library behind.

Both failures are preserved in `fail-first.log`. No production raster source
or release-library contents are changed by the fix.

## Fix and integrity contract

The packager validates the **exact** proposed ELF/PCK/native file inventory in
an auto-cleaned candidate export before publishing the `.so`. Candidate
ELF/PCK files use same-filesystem hardlinks rather than copying the full
executable and pack. The native source uses a hardlink when possible and a
byte-exact copy on `EXDEV`. The existing strict `inspect_distribution`
remains the validation authority. Symlinks and extra/missing artifacts still
fail closed, and a mismatched existing `.so` remains untouched.

After verified publication, a new failure in the final inspection removes
**only** the just-installed library and any directories this call created.
Temporary files and preflight candidates are deleted. A separate injected
post-install error asserts that inspection was run twice and the failed
export is restored without native artifacts. The copy and digest checks
remain unchanged.

## Completed tests and executable witness

| Command / witness | Result |
| --- | --- |
| `python3 -m unittest discover -s tests -p 'test_t201_linux_native_package.py' -v` | **8/8, exit 0** (three new tests) |
| `python3 -m unittest discover -s tests -p 'test_t068_release_gate.py' -v` | **5/5, exit 0** |
| `python3 -m unittest discover -s tests -p 'test_t105_portability.py' -v` | **10/10, exit 0** |
| `make python-test PYTHON=python3` | **59 tests across seven suites, exit 0** |
| `bash tools/build_native_brush.sh --test` with pinned offline Rust/vendored Cargo | **35/35, exit 0** |
| Pinned Ruff 0.17.5 `check` and `format --check` on changed Python files | **exit 0** |
| Pinned ty 0.0.104 `check` on changed Python files | **exit 0** |
| `tools/build_drawing_app.py --output`, Godot beta3 editor `--import`, `--export-pack Linux` | **three exit-0 processes** |
| `tools/package_linux_export.py --stage ... --linux ...` | **exit 0**, staged/exported real `.so` same SHA |
| `tools/benchmarks/t068_release_gate.py --launch-linux` | **exit 0**: isolated ABI + application launch, zero post-exit leaks |
| `python3 tools/validate_ticket_store.py` | **212 ticket files, dependency/manual-gate checks passed** |

The **real native library** was 2,649,984 bytes, SHA-256
`dcaf73fa6e0b113f76aa12d6072a598406dea19e5a12a026db47334df2e45074`.
The exported PCK digest was
`19ccf70f362399f5b191373c19c41bfca63c04352f6f9853228815de642e398f`.
The isolated smoke reported `native_abi_verified=true`, independent work
and user profile, no source-project fallback, and no post-exit leaks.
Full file hashes and logs are in `manifest.json` and `release-report.json`.

## Boundaries

The runtime witness pairs a real exported PCK and the supplied **Godot
editor executable as a surrogate**. No official Godot Linux release template
was installed or tested in this environment. Windows DLL/export, hosted
GitHub CI exact-head pass, T-150 native-transition acceptance, physical
performance and manual owner review are **not** established. T-105/T-106/
T-180 remain In Progress; T-197's pacing target is unaffected.
