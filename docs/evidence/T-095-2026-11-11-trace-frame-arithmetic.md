# T-095 — owner trace frame-clock arithmetic (2026-11-11)

**Scope and gate:** One T-095-only offline diagnostic correctness checkpoint
on `sprint/2026-11-11`. T-095 remains **In Progress** with
`manual_review: true`; T-096 remains independently **Manual Review**.
No real-device acceptance, runtime speedup, hosted CI result, or remote push
is claimed.

## Defect and implementation

The schema-1 Godot Canvas exporter measures frame completion, a matched
`frame_post_draw` callback, earliest pixel-changing stage completion, and
input receipt using the same monotonic clock. The analyzer previously
validated observation counts and optional callback presence but did not
validate their **arithmetic**. A corrupted JSONL frame could therefore
claim, for example, a 2,000µs stage→Canvas interval, 2,500µs Canvas→callback,
and 4,400µs stage→callback (the correct sum is 4,500µs), misleading
physical-device troubleshooting. Exported frame timestamp and queue-depth
fields could also be ill-typed or negative without being rejected.

`tools/analyze_t095_trace.py` now validates every known exported frame
field as a nonnegative JSON integer, checks monotonic differences when the
corresponding raw timestamps exist, verifies callback sums for stage and
receipt intervals, and rejects a receipt recorded after its stage completion.
Absent optional fields stay absent; the analyzer does **not** invent zero
latency or claim physical input-to-photon measurements. The Godot exporter,
Brush code and analyzer output schema `t095_trace_analysis_v3` are unchanged.

## Red/green controls and regression results

The new `test_frame_phase_timestamp_arithmetic_is_consistent` contract first
failed **eight of eight** malformed-phase cases against the prior analyzer:
callback delay/timestamp disagreement; stage and receipt callback sums;
stage completion and input receipt contradictions; a string queue depth;
and a negative frame timestamp. A valid paired sample was also tested.
With the fix, all **12/12** Python contracts pass with exit 0 and a clean log;
`compileall` passes. On-demand CI retains the strict
`T095_TRACE_ANALYZER_PASSED` marker and raw log, with an updated step label.

Godot `4.8.beta3.official.c51ff06e8`, local isolated runs:

| Test | Result |
| --- | --- |
| Schema-1 owner trace exporter | 17/17, exit 0, strict marker |
| 60px/786% Xvfb actual pointer witness | 5/5 strokes, exit 0, strict marker |
| Real pointer trace parsed by new analyzer | 5 records, 274 frames, 150 matched callbacks |
| Independent Brush pixel/history | 32/32, exit 0, strict marker |
| NativeHard source-read rollback | 113/113, exit 0, strict marker |
| Hokusai pigment rollback | 57/57, exit 0, strict marker |
| Input receipt / preview callback parity | 22/22, exit 0, strict marker |
| Ticket/dependency validation | 96 tickets valid |

The Xvfb/Mesa witness recorded staging p95 **187.948ms** and
release→commit p95 **69.247ms**. These are software-renderer diagnostics,
not physical-device input-to-photon, a controlled speedup, or acceptance.
No traced user canvas data or generated Godot UIDs are committed.

## Remaining gate

Reference hardware, OS/GPU/driver/scaling, observed visual catch-up,
release backlog and explicit owner review remain pending. Required fast CI
and T-094 strict log policy are unchanged; hosted GitHub Actions were not
verified. The owner-approved PR #14 seam fix must remain intact.
