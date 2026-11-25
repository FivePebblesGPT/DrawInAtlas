# T-283 — Fast CI T-137 contract repair, 2026-11-23

## Baseline and cause

- Checkout: `sprint/2026-11-23-godot-beta4`, starting commit `7907b404`.
  Verified remote `main` at `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- The original `python3 -m unittest tests.test_t137_preview_cold_population -v`
  failed **2/3 tests**: `test_real_regressions_cover_fallback_and_settlement`
  demanded `Redo restores blue source pixel`, and
  `test_existing_ci_inventory_and_fail_closed_logs` demanded
  `T137_NATIVE_PASSED checks=18 failures=0`.
- T-266's current X11 witness checks `Redo completes bounded cold display
  repopulation` followed by `Redo restores exact canonical source and visible
  framebuffer pixel`; its workflow and Make target already require **19**.
  This was a stale Python source/CI contract, not a reproduced compositor defect.

## Current implementation and validation

Only the Python source contract was repaired. It now retains the complete
15-check headless model and all 46 fast-CI step IDs; the X11 success log
requires exactly 19 checks, no engine errors, no duplicates, and no failure
marker. A new contract asserts settlement precedes Redo pixel verification,
and that verification reads **both `DrawingDocument.read_pixel` and the X11
framebuffer**, rather than trusting a source-only or stale display value.

| Witness | Result | Raw record |
| --- | --- | --- |
| T-137 Python + T-266 Python | 10/10 pass | [neighboring Python log](T-283-2026-11-23-cold-preview-ci-raw/python-neighbors.log) |
| T-135/T-136/T-137/T-266 Python | 16/16 pass | [complete Python log](T-283-2026-11-23-cold-preview-ci-raw/python-neighbors.log) |
| T-137 headless model | 15/15 pass | [headless](T-283-2026-11-23-cold-preview-ci-raw/model-t137.log) |
| T-137 real software-X11 | 19/19 pass | [X11](T-283-2026-11-23-cold-preview-ci-raw/native-t137.log) |
| T-086 adjacent real software-X11 | 153/153 pass | [X11](T-283-2026-11-23-cold-preview-ci-raw/neighbor-t086.log) |
| Source mutant: remove settled-Redo label | 1 expected assertion failure | [mutation controls](T-283-2026-11-23-cold-preview-ci-raw/mutant.log) |
| Source mutant: remove canonical pixel read | 1 expected assertion failure | [mutation controls](T-283-2026-11-23-cold-preview-ci-raw/mutant.log) |
| Ticket-store validator | 283 tickets, gates valid | [validation](T-283-2026-11-23-cold-preview-ci-raw/ticket-validation.log) |

Reproduction commands (from repo root with the bundled Godot binary in PATH):

```sh
python3 -m unittest tests.test_t135_sparse_viewport \
  tests.test_t136_preview_sparse_union \
  tests.test_t137_preview_cold_population tests.test_t266_viewport_ci -v

godot --headless --path drawing \
  --script res://tests/t137_preview_cold_population_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t137_preview_cold_population_native.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/viewport_cache_native.gd
python3 tools/validate_ticket_store.py
```

Environment: bundled `Godot 4.8.beta4.official.b070e63b1`,
`godot-rust` compiled extension loaded (API 4.7, runtime 4.8 beta4), Debian
software Xvfb / Mesa 25.0.7 llvmpipe, OpenGL Compatibility. The root-runner,
V-Sync and two T-137 headless RID/ObjectDB cleanup warnings are retained in
raw logs. Both pointer/framebuffer software witnesses exited 0. The log
validators were also run against the captured native/model logs.

## Boundaries

This is a **test-contract repair only**. It does not change the renderer,
manual-review statuses, native extension, CI schedule or visual layout.
The older T-137 18-check evidence remains historically valid for that prior
version; T-266's 19-check version is the required current witness. No hosted
CI was executed on this local commit. T-086 first-population and physical
latency/cache performance, T-149 native display seams, T-094/T-180 hosted
acceptance and T-250 owner UX review remain open.
