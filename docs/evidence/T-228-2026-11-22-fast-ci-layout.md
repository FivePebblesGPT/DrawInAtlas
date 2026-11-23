# T-228 — Fast-desktop strict release staging and dependency assertions

**2026-11-22 · branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Verified remote PR #22 head before modifications:**
`b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146` (unchanged during local work).
Local work builds on T-221/T-222/T-226/T-223/T-224/T-225/T-227.

## Before: independently reproduced red tests

- The new `tests/test_t228_fast_ci_contract.py` failed with
  `Release step missing isolated contract: mkdir -p "$release_root/dist"`.
  The job exported into `$release_root` while it already contained `project/`;
  `tools/package_linux_export.py` rejects that extra directory. The strict
  package validator itself was correct and was **not** weakened.
- `python3 -m unittest discover -s tests -p 'test_t078_t083_docking_plan.py' -v`
  failed the `test_all_six_tickets_have_ordered_hard_dependencies` subtest
  for T-083, because it demanded the obsolete exact singleton YAML field.
  The real T-083 frontmatter contains T-082, T-091 and T-222–T-225.

## After: targeted repairs and controls

- `.github/workflows/godot-check.yml` stage remains `project/`; a clean
  sibling `dist/` receives the export. All ELF/PCK existence assertions,
  native install, font/PCK smoke and strict release launcher use `dist/`.
  The script path for the source-side font smoke stays within `project/`.
  Check IDs, `set -euo pipefail`, fail-late and model-log markers are retained.
- `tests/test_t201_linux_native_package.py` now constructs the exact bad
  `project/` directory in the export root: package preflight rejects it
  without publishing a native ELF; removal makes the identical strict
  package distribution succeed. Other unusual-entry rejection tests remain.
- The new T-228 workflow tests check every distribution consumer, reject
  the old mixed-root layout and a wrong packager target. The required CI
  release step runs these source-level tests.
- `tests/test_t078_t083_docking_plan.py` uses `parse_ticket().dependencies`
  to assert the historical predecessor, no duplicate edges and all five
  additional explicit T-083 prerequisites. The owner-review test is retained.

## Local validation

| Command | Result |
| --- | --- |
| `python3 -m unittest discover -s tests -p 'test_t228_fast_ci_contract.py' -v` | 3/3 passed, includes 2 negative controls |
| `python3 -m unittest discover -s tests -p 'test_t078_t083_docking_plan.py' -v` | 10/10 passed (previously red for T-083) |
| `python3 -m unittest discover -s tests -p 'test_t201_linux_native_package.py' -v` | 24/24 passed |
| `python3 -m unittest discover -s tests -p 'test_t068_release_gate.py' -v` | 6/6 passed |
| `python3 -m unittest discover -s tests -p 'test_t217_pck_index.py'` | 10/10 passed |
| `python3 -m unittest discover -s tests -p 'test_t218_pck_payload_integrity.py'` | 5/5 passed |
| `python3 -m unittest discover -s tests -p 'test_t219_pck_resource_names.py'` | 5/5 passed |
| `python3 -m unittest discover -s tests -p 'test_t220_pck_project_identity.py'` | 6/6 passed |
| `python3 tools/validate_ticket_store.py` | 228 canonical tickets validated |
| `git diff --check` | passed |

**Not claimed:** a full Godot release export, because local Godot 4.8 beta3
export templates are not installed; an exact-head hosted GitHub CI run, native
Windows release or physical owner UX approval. A historical PR #22 workflow
failure is not equivalent to a current post-fix CI result. T-106/T-180 and
T-083 retain their independent gates.
