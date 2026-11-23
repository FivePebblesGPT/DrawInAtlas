# T-271 — Required-native Object-source discovery and Atlas identity CI

## Before / fail-first

PR #22 local base `154e0e6d`, with the last observed remote head
`7b1fd306` (23 unpushed commits at the start of this task). The T-093
on-demand workflow built a standalone Drawing copy but **did not build the
mandatory Rust Hokusai extension**, which is not tracked in Git. It did not
import Atlas or test the Atlas consumer of the shared source browser.

The new `tests/test_t271_object_source_ci.py` failed against that workflow and
absent Make target (12 workflow/target assertions plus one missing-target
exception). With required-native setup and Atlas coverage, it and the existing
T-093 contracts pass 6/6. The contracts reject short/duplicate/error native
logs, enforce explicit counts and check native compilation before any UI run.

## Work delivered

- Pinned Godot 4.8 beta 3 and Rust 1.99.1 in the T-093 on-demand workflow,
  delegated native compilation plus standalone/Atlas staging/import to
  `make build TOOLCHAIN=system`, and required all test logs to survive
  failure with an unconditional artifact upload.
- Required T-093 first-use root/portability model **56**, source browser
  real-X11 **27**, T-120 native File/Object menu **20**, and a new Atlas
  source identity/framebuffer consumer test **24** assertions. Existing
  T-093/T-120 strict native log verifiers remain unchanged.
- `tests/t271_atlas_object_sources_native.gd` exercises real X11 toggle,
  source row and Open clicks; an Atlas-generated asset ID distinct from the
  input document ID; exact signed alpha-zero hidden RGB after opening;
  dedicated Object Editor without map instance placement; unchanged Atlas
  map, global history and savepoint; immutable published source bytes; and
  refusal to reuse the source row's authorization token after a file changes.
- `make test-object-sources` includes native build, both Godot imports and
  all four strict Bash `pipefail` test/log steps. The historic Python T-093
  contract now recognizes Make's required-native imports instead of requiring
  literal inline `--import --quit` workflow text.

This ticket makes **no production Drawing, Atlas, or Rust source changes**.

## Actual local verification

Platform: offline Linux x86-64, bundled Rust 1.99.1/Cargo vendor directory,
Godot 4.8 beta 3 (`c51ff06e8`), Mesa llvmpipe/OpenGL compatibility and X11
via Xvfb 2200×1500×24. All native framebuffer tests use software rendering.

| Witness | Observed result |
| --- | --- |
| T-093 model | 56/56 passed, exit 0 |
| T-093 standalone native X11 | 27/27 passed, exit 0 |
| T-120 File/Object native X11 | 20/20 passed, exit 0 |
| New T-271 Atlas native X11 | 24/24 passed, exit 0 |
| Neighbor T-065 Atlas browser native | 12/12 passed, exit 0 |
| Neighbor T-065 Atlas Object source manager native | 22/22 passed, exit 0 |
| Neighbor T-065 Atlas browser model | 32/32 passed, exit 0 |
| New + historic T-093 Python workflow/log contracts | 6/6 passed |
| Ruff 0.17.5 / ty 0.0.104 on changed Python tests | Passed |
| Explicit GDScript typing audit | 595 project scripts, 33 skills passed |
| Ticket store and manual dependency gates | 271 tickets validated |

The full `make test-object-sources` invocation compiled native Rust and imported
both Drawing and Atlas; both emitted `NATIVE_EXTENSION_READY`. Its combined
log contained all four passing test summaries, but this container's outer
command wrapper timed out before returning an exit code. A second invocation
with imports already completed (`make -o import-drawing -o import-atlas
 test-object-sources`) **returned exit 0** and passed all four strict
verifiers, including the strengthened 24-check Atlas test. Do not interpret the first wrapper
timeout as an end-to-end verified Make exit.

Reproduction with the supplied offline toolchain:

```sh
export PATH=/path/to/toolchain/rust/bin:$PATH
export CARGO_VENDOR_DIR=/path/to/toolchain/vendor CARGO_NET_OFFLINE=true
make test-object-sources TOOLCHAIN=system \
  GODOT=/path/to/toolchain/bin/godot CARGO=/path/to/toolchain/rust/bin/cargo
python3 -m unittest tests.test_t093_object_discovery tests.test_t271_object_source_ci
python3 tools/validate_ticket_store.py
```

## Explicit boundaries

The on-demand GitHub Actions workflow was not run on GitHub. The synthetic
X11 events do not cover the platform-native FileDialog inside its own Window,
physical Windows/Linux clicks or owner preferences. **T-065 Asset Browser,
T-059 overall Drawing UX and T-250 Drawing-before-Atlas owner review remain
open**, as do T-094/T-180 hosted CI/release acceptance. No review approval
is inferred from these tests.
