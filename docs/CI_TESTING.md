# Godot GDScript CI — run all checks, then fail

The **Godot GDScript checks** job in `.github/workflows/godot-check.yml` runs its independent verification steps even when an earlier step fails. It reports failures once all checks have been attempted, avoiding the stop-at-first-failure cycle seen in CI runs #113, #115 and the later T-014 failure.

## Behavior

- Checkout and installation of the pinned Godot 4.8 beta 2 engine are prerequisites. Without a usable checkout/engine, no meaningful script tests can run. Job cancellation still stops the workflow.
- Every subsequent check has an explicit, unique `ci_*` step ID, `if: ${{ !cancelled() }}` and `continue-on-error: true`. This lets the next check execute even when the preceding check's original outcome was failure. The main-project editor import still occurs **before** main-project GDScript smoke tests.
- Steps containing multiple independent test invocations or `for suite in ...` loops source `tools/ci_fail_late.sh`. The helper collects nonzero commands and failed output-marker assertions but continues through the rest of that step, returning a failing status at the end. Dependent operations (for example, a Web export after an import) may still produce cascading failures if a prerequisite artifact was not generated.
- The final **Summarize CI failures** step runs `tools/report_godot_ci.py`. It checks `steps.*.outcome`, **not** `conclusion` (which may be rewritten to success by `continue-on-error`). It writes a compact GitHub step summary listing failed or skipped checks and exits nonzero if any check failed. Consequently, the workflow remains **red**, never silently green, and identifies all recorded failures together.
- The report step runs after the optional Web build artifact upload. Upload failures are counted like other recorded checks.

## Reproduce the guards locally

```bash
python3 -m unittest discover -s tests -p 'test_godot_ci_order.py' -v
python3 -m unittest discover -s tests -p 'test_godot_ci_fail_late.py' -v
python3 tools/validate_ticket_store.py
```

These guards validate workflow ordering, continue-on-failure coverage, group-level Bash failure collection, and final outcome aggregation. They **do not** substitute for running the full Godot/native/Web suite on GitHub.

CI policy changes here do not change a feature ticket's implementation or approve any manual UX/review gate. All previously blocked or pending tickets remain in their recorded Kanban states.
