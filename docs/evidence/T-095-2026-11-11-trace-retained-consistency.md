# T-095 — owner trace retained-history consistency (2026-11-11)

**Ticket and gate:** T-095 P0, In Progress, `manual_review: true` on
`sprint/2026-11-11`. T-053 is Done; T-096 remains independently Manual
Review. No hardware acceptance or Done transition is claimed. The GitHub
branch remained at `f9e54fdfc81fb72840023665694fb24b55fb220e` when
checked. No push/merge.

## Defect and bounded change

`tools/analyze_t095_trace.py` validated window sizes, lifetime totals and
some callback-count inequalities, but accepted contradictory retained data.
In particular, a recent input-stage sample could exceed the reported lifetime
maximum, a recent pending-input-age sample could exceed the lifetime maximum,
and retained frame callbacks could outnumber the corresponding lifetime
matched count. A preview callback could also appear without a matched Canvas
draw. Such records would produce misleading low-worst-case or false-callback
reports from an owner's physical-device run.

The offline analyzer now fails closed on those contradictions and on
changed-preview callback counts greater than changed-preview submissions.
The fix does **not** alter the Godot JSONL exporter (schema 1), Brush output,
rendering, input queue, performance or analyzer output schema v3. It does not
infer physical input-to-photon timing.

## Red/green and local tests

- Before the analyzer fix, the new unittest failed **five** subcases out of
  eight inconsistent records: understated source/queue maxima, impossible
  retained callback count, orphaned stage callback and input callback without
  a matched frame. Three additional corruptions were already rejected by
  existing checks. This is a deliberately failing test control, not a green
  runtime test.
- After the fix, the stdlib Python analyzer suite passed **11/11**; all
  eight incompatible records were rejected and existing valid fixtures and
  cross-file/timestamp-epoch tests continued to pass. Python compileall passed.
- Godot `4.8.beta3.official.c51ff06e8` standalone, exit zero and strict
  marker/log verification: owner JSONL exporter **17/17**, independent
  Brush pixel/history oracle **32/32**, NativeHard rollback **113/113**,
  Hokusai pigment rollback **57/57**, receipt-to-preview correlation
  **22/22**. A local strict-check command initially used an incorrect
  marker for the Brush oracle; rerunning against its actual
  `T095_ORACLE_PASSED` marker passed.
- The Xvfb/Mesa 60px/786% actual pointer-event witness completed five
  strokes (`T095_NATIVE_PASSED`). Its opt-in schema-1 JSONL output contained
  five records, including **272 retained Canvas frames and 150 matched**
  post-draw callbacks across the strokes. The corrected analyzer accepted
  all five and kept them in one per-file/per-epoch cohort. One separate
  headless exporter capture also parsed two completed records. These are
  software-renderer checks, not owner-device measurements.
- The existing on-demand CI test step requires the same strict
  `T095_TRACE_ANALYZER_PASSED` marker; no required fast CI checks or T-094
  error policies were relaxed.

## Remaining decision

The owner's ~3-second/one-minute Brush catch-up reproduction, real GPU
compositor/driver and physical input-to-photon timing are untested here.
Owner review and explicit acceptance remain required; T-095 stays In
Progress. Do not interpret improved trace validation as responsiveness.
