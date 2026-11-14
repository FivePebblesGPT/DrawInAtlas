# T-095 offline owner-device JSONL analysis — 2026-11-11

**Engineering checkpoint only.** T-095 remains `In Progress`, `manual_review: true`.
Neither the owner reference hardware nor hosted GitHub Actions has been
validated; T-096 retains its independent `Manual Review` status.

## Motivation, format and operator procedure

The previous opt-in `DRAWING_T095_TRACE_JSONL=user://t095-owner-recheck.jsonl`
export captured timings for real Brush input, but required manual parsing of
bounded arrays and callback records. This checkpoint adds a **stdlib-only,
read-only** offline analyzer, `tools/analyze_t095_trace.py`, for the existing
`schema: 1`, `capture_kind: engine_timing_only` records. No Canvas input,
brush model, exporter format, or production runtime path changes.

After collecting a trace on the **actual owner device**, copy its JSONL file
to a local analysis machine and run from the repository root:

```sh
python3 tools/analyze_t095_trace.py /path/to/t095-owner-recheck.jsonl
python3 tools/analyze_t095_trace.py --json /path/to/t095-owner-recheck.jsonl > t095-analysis.json
```

Multiple paths may be supplied to compare strokes collected in one or more
sessions. The output groups only like-for-like **backend, width, zoom, viewport
and image bounds**; a group reports the first observed release-to-commit time
separately, without assuming a session or cold-start boundary. The text and
machine-readable outputs label every measurement as **Godot engine timing,
not physical input-to-photon latency**. There is no invented pass/fail timing
threshold and no automated approval.

The tool reports a nearest-rank p50/p95, retained maximum and retained/total
counts for stage sample ages, stage-batch CPU, Canvas draw/compositor/texture,
input backlog and matched render callback intervals. Every percentile is
computed **only from retained samples**, which may be a recent subset of the
full gesture (4,096 stage samples / 1,024 frames). When a lifetime count is
available, the analysis marks truncation and reports the exporter's exact
lifetime maxima separately. An absent callback or undisplayed frame sample
is **unavailable**, never manufactured as a zero-delay success. The complete
stroke's release-to-commit interval is calculated from the original Godot
monotonic receipt/release/commit timestamps.

Input validation fails closed on incompatible schemas, nonfinite/negative
values, nonmonotonic gesture timestamps, impossible counts, invalid JSONL,
oversized sample windows and oversized records. The analyzer reads files only;
it does **not** open or modify the application, upload data, or inspect canvas
pixels/names. Although input traces intentionally exclude document names,
users should still review any trace before sharing it.

Owner still needs to separately record OS, GPU/driver, scaling, build SHA,
layer count, initial cold stroke vs warmed strokes, and observed visual delay.
Godot's input callback timestamps are **not physical pointer timestamps**;
`frame_post_draw` is **not panel scanout**. Explicit owner hardware recheck of
60px Brush catch-up and post-release navigation is the ticket's unresolved
acceptance gate.

## Verification and independent failure controls

- Python 3.13: `python3 -m unittest discover -s tests -p
  test_t095_trace_analyzer.py -v` — **6/6 tests passed**. Contracts cover
  retained vs lifetime counts, nearest-rank p50/p95, missing callbacks vs true
  zero delays, empty histories, grouping, invalid schemas/counts/units,
  malformed second line with no partial success, and oversized records.
- Existing real Godot exporter (pinned `4.8.beta3.official.c51ff06e8`):
  created **two completed 60px Legacy Brush strokes** using the actual
  `DrawingCanvas` commit path, then parsed their JSONL with the new CLI.
  Both records parsed successfully; the real fixture exposed a valid
  `[0, 0]` empty-image bounds edge case that is now accepted. No draw callback
  occurred in this headless gesture, and the CLI explicitly reported those
  timing distributions as unavailable. The temporary fixture and trace were
  removed; they are not bundled in the commit.
- Negative input controls: incompatible schema/capture kind, invalid JSON,
  impossible callback totals and a >4 MiB record all raise `TraceError` with
  a failing process exit; the malformed-second-line command emits no partial
  report. The on-demand native workflow now executes the six Python contracts
  with `pipefail`, exact `T095_TRACE_ANALYZER_PASSED` marker verification via
  the existing T-094 fail-closed checker, and raw-log retention even on later
  job failure. The required fast-CI matrix is unchanged.

**Remaining:** actual owner reference-device trace, corresponding human visual
judgment and explicit manual acceptance, plus hosted Actions verification.
No performance improvement, input-to-photon measurement, ticket closure or
review approval is claimed.
