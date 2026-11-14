# T-095 — appended owner trace observable clock-epoch isolation (2026-11-11)

**Scope:** one offline diagnostic correctness checkpoint; the Brush runtime and
`DRAWING_T095_TRACE_JSONL` schema-1 exporter have **not** changed. T-095 remains
**In Progress** with `manual_review: true`, and T-096 remains independently
**Manual Review**. There is no owner-device responsiveness measurement, hosted
CI verification or owner approval in this checkpoint.

## Defect and boundary

The previous analyzer correctly separated *different files*, but grouped all
matching Brush reproduction settings *within one file*. The exporter appends
records, and a Godot process restart can reset the `Time.get_ticks_usec()`
epoch. An appended file can therefore contain strokes from different launches,
possibly different devices, without any change in Brush width or viewport.
Grouping those strokes silently can conceal a slow owner session.

The analyzer now tracks `down_us` per input file. A **strict decrease** starts
a new one-based `timestamp_epoch_index`; subsequent strokes with the same
Brush settings are aggregated only within the same input file **and** epoch.
A new file always starts epoch 1. No file paths, coordinates or device identity
are added to output. This is a *detected clock reset*, **not** a verified
session/device identity: a restart without decreasing timestamps, a device
switch without a reset, or an appended stream reordered by another writer
cannot be disambiguated. Retained percentiles remain engine observations, not
physical input-to-photon measurements.

The analyzer output is `t095_trace_analysis_v3` with `timestamp_epoch_index`
and `cohort_boundary:
input_file_and_observed_timestamp_epoch_plus_brush_settings_not_verified_hardware`.
The original local Godot `schema: 1` export format is unchanged.

## Red/green regression

Four otherwise identical 60px/786% strokes were written to one local JSONL
file, with monotonic down timestamps inside each pair and a decrease at the
pair boundary. The first pair had release-to-commit **80 ms** each; the
second pair **5 ms** each.

| Analyzer | Groups | Nearest-rank release→commit p95 |
| --- | ---: | --- |
| Previous committed version, v2 | 1 | 80 ms (mixed cohort) |
| Updated version, v3 | 2 | 80 ms, 5 ms (separate epochs 1, 2) |

The new unittest failed against the old analyzer because it had no epoch
boundary; after implementation, the complete **9/9** stdlib analyzer suite
passed with exit code 0. The suite still checks same-file uninterrupted
aggregation, per-file cohorts, absent callbacks, retained-window accounting,
invalid records, oversized lines and CLI failure without partial output.
`python3 -m compileall -q` passed, and the analyzer's raw test log passes the
existing T-094 strict marker checker with exactly one
`T095_TRACE_ANALYZER_PASSED` marker.

## Neighboring tests and gate status

Pinned `Godot_v4.8-beta3_linux.x86_64` headless tests, all exit 0 and pass
exact strict success markers:

- Owner JSONL export: **17/17** (`T095_OWNER_TRACE_PASSED`)
- Independent 60px Brush pixel/Undo oracle: **32/32** (`T095_ORACLE_PASSED`)
- NativeHard source rollback: **113/113** (`T095_NATIVE_HARD_SOURCE_ATOMIC_PASSED`)
- Hokusai pigment rollback: **57/57** (`T095_NATIVE_PIGMENT_ATOMIC_PASSED`)
- Changed-preview input/post-draw correlation: **22/22** (`T095_PREVIEW_INPUT_POSTDRAW_PASSED`)

The strict checker initially used the wrong marker name for the Brush test;
the test log itself exited 0 with `T095_ORACLE_PASSED`, and its log passed after
checking the correct marker. The YAML parser and the 96-ticket store validator
also passed. Only the non-gating on-demand analyzer step name changes; the
required fast-CI matrix, review gates and no-unverified-pass policy remain
unchanged. No renderer or pointer latency speedup is claimed.
