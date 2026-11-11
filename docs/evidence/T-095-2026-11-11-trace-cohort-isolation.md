# T-095 — owner trace analyzer source-file cohort isolation (2026-11-11)

**Scope:** one T-095 diagnostic correctness checkpoint, not ticket closure.
The owner reference-device 60px Brush recheck, physical input-to-photon
measurement and explicit manual approval have **not** occurred. T-095 is
`In Progress`, `manual_review: true`; T-096 is independently `Manual Review`.

## Defect and contract

The first `tools/analyze_t095_trace.py` grouped every supplied JSONL record
by backend, brush width, zoom, viewport pixels and image bounds. Two distinct
input files with exactly those values are **not** proven to share a device,
driver, recording session or temperature. Thus `--json a.jsonl b.jsonl`
could pool their release-to-commit percentiles and conceal a badly lagging
device. The old behavior was reproduced by an independent test using separate
files with identical 60px/786% settings and release-to-commit durations of
**80 ms** and **5 ms**: it incorrectly produced **one** group.

The analyzer now also partitions by the **input argument's 1-based file
index**, with no user path or filename in its output. Per-stroke and group
records expose `source_file_index` and the report declares
`cohort_boundary: input_file_index_plus_brush_settings_not_verified_hardware`.
This changes **only** the offline analysis output version to
`t095_trace_analysis_v2`; the original local Godot `schema: 1` export and
Brush runtime are untouched. Human output labels file #1, #2, etc.
Records within the **same** input file continue to form one group if all
Brush settings match. An appended file can still contain multiple device
sessions, which the records cannot identify; do not infer a hardware match
from a single file, and do not interpret the report as a physical latency
or pass/fail verdict. To compare machines, collect separate files and record
OS/GPU/driver/build/cold-warm/visual response in a separate review note.

## Red/green regression and verification

- Baseline red control: `python3 -m unittest discover -s tests -p
  test_t095_trace_analyzer.py -v` on the original analyzer with the two
  added tests exited **1**, reporting **one failed false-merge assertion**
  and **one missing cohort-index error**. No output claiming a pass.
- Updated analyzer: the same command passes **8/8** Python contracts,
  including separate-file non-pooling, same-file aggregation, two-file CLI
  JSON schema v2, retained-count handling, schema/counter negatives, malformed
  second-file failure and oversize rejection. `python3 -m compileall -q`
  passes for the source and tests. Test logs retained locally.
- Existing real Godot 4.8.beta3 native owner-export regression: **17/17**
  passed with zero exit status and the exact strict marker. Adjacent
  independent brush pixel **32/32**, changed-preview receipt **22/22**,
  NativeHard source rollback **113/113**, and Hokusai pigment rollback
  **57/57** passed individually with strict-marker validation. The exporter
  `schema: 1` and production Canvas are unchanged by this commit. The
  non-gating on-demand workflow retains the exact
  `T095_TRACE_ANALYZER_PASSED` marker and raw-log upload.
- The **96-ticket** store validator passed and the on-demand workflow YAML
  parsed. These are local checks, **not** hosted CI verification.

This is a **correctness fix to the offline interpretation of traces**, not a
stroke optimization or proof that the original reported ~minute-long Brush
catch-up is resolved on the owner's device.
