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

## Preventing hung Godot script processes

Godot 4.8 beta 2 can log a GDScript runtime error in a deferred `SceneTree`
smoke-test callback without reaching that script's final `quit()`. Previously,
such tests occupied their GitHub Actions step indefinitely even though the
log already displayed `SCRIPT ERROR`.

Each Godot `--script` invocation now runs under GNU `timeout` with a
5-second forced-kill grace period. Headless scripts have a **120-second** limit;
native Xvfb scripts have **240 seconds**. A timeout exits with status 124,
fails the individual test step (or is collected by `tools/ci_fail_late.sh` in
a multi-test step), and leaves later independent checks runnable. The final
summary remains red when any test failed or timed out. Editor import and
release packaging are separate prerequisites, not subject to these per-script
limits.

`tests/test_godot_ci_fail_late.py` guards that every scripted Godot
invocation retains its watchdog. T-016 exposed this case in
`tests/snapping_smoke.gd` when a stale legacy stroke assertion attempted to
dereference a null object; the smoke now verifies canonical Drawing pixels.
