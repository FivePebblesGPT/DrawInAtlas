# T-201 — required-native Linux export packaging and isolation

**2026-11-19 — narrow tooling ticket Done.** Source `sprint/2026-11-17`,
Godot `4.8.beta3.official.c51ff06e8`, provided immutable offline Rust/uv/Godot
bundle, Linux x86_64. See [raw logs and hash manifest](T-201-2026-11-19-linux-native-export-raw/).

## Fail-first and real native witness

1. On the existing full Drawing project, `godot --headless --path drawing
   --export-pack Linux .../Drawing.pck` succeeded (exit 0) and included the
   `drawing_brush.gdextension` manifest. Running that PCK with the current
   beta3 executable **without** the sibling native ELF exited 1: `Can't open
   dynamic library .../bin/libdrawing_brush.so`; the smoke printed
   `NATIVE_EXTENSION_MISSING`. Copying the canonical Rust ELF to the exact
   manifest path and running again exited 0 with `NATIVE_EXTENSION_READY`.
2. Four initial unit cases failed before the package module existed.
   A fifth symlink rejection case was added afterward.
   They now verify same-sha copied bytes, PCK+ABI isolation, rejection of
   unexpected/incorrect ELF and additional libraries, manifest/ABI mismatches,
   symlinks and false success without registered native classes. All five pass.
3. A **fresh independent Drawing stage** was generated from the canonical
   sources, imported with the official supplied beta3 editor (exit 0), and
   exported as a PCK (exit 0). The new packaging CLI installed the original
   native ELF (exit 0), then the release gate copied the ELF/PCK/loader into a
   clean profile and ran both native ABI and main app boot (exit 0).
   `tools/benchmarks/t105_release_residency.py --runs 2 --frames 30` also
   passed and independently verified its report. This is a process/memory
   packaging witness, **not** physical mouse-to-photon or frame-rate evidence.

| Strict witness | Result |
| --- | --- |
| Native source/shared digest | `222a010ec3744d7dcbd3425579cb43cc29eb9b892997d4f319dd951a4a344a63` (stage = distribution) |
| Fresh native PCK | `e899dab2c61bdbb1102282eedda6cd592b2e8568d78d504cca46ec0cc32f8753` |
| T-201 fail-first | Import error for missing required package module |
| T-201 negative/positive unit cases | 5/5 passed |
| Updated historical T-068 release inspection tests | 5/5 passed |
| Updated T-105 portability tests | 10/10 passed |
| `make python-test` | All suites passed (toolchain/profile/T-198/T-199/T-068/T-105/T-201) |
| Bundled Rust `build_native_brush.sh --test` | 35/35 passed |
| Drawing native brush integration | 32/32 passed |
| Native class ABI | `NATIVE_EXTENSION_READY`, exit 0 |
| `make lint TOOLCHAIN=bundle` | Ruff and ty passed |
| Native Linux process CPU/RSS | 2 runs, report verifier passed; not a physical GPU measurement |

The isolated loader explicitly supplies `--path` to the copied distribution
while retaining an unrelated process CWD and separate HOME/XDG. Without this,
Godot 4.8 beta3's shared-library loader resolved the manifest-relative ELF
against the caller CWD (observed failing in the temporary PCK witness).

## Limitations and handoff

This environment has **no official Linux export templates**. An actual
`godot --headless --export-release Linux` returned **exit 1** and named the
missing files `linux_debug.x86_64` / `linux_release.x86_64` under
`export_templates/4.8.beta3/`. The successful packed-app runtime above uses
**the supplied editor executable as a surrogate**. It validates the real
GDExtension/PCK path and isolated executable behavior, but not the official
Linux release template or a desktop launcher invoked from arbitrary CWD.
The updated strict CI steps must be checked on their actual hosted head.
Windows stage inspection remains a structural **non-native** historical
witness, not a Windows alpha build; T-105/T-150 remain open.

No benchmark throughput, source RGBA, history, Windows coverage or owner
review is claimed. T-180 remains In Progress for final README/CI/export
alignment and T-106 for hosted green, T-095/T-197 for responsiveness.
