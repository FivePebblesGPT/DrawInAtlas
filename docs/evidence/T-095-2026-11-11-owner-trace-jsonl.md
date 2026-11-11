# T-095 opt-in owner-device JSONL profiling — 2026-11-11

**State: engineering checkpoint only.** T-095 stays `In Progress` and
`manual_review: true`. The owner has not rechecked 60px Brush on their device.
T-096 stays independently in `Manual Review`; no owner approval or hosted CI
pass is inferred.

## Motivation and behavior

The existing native mouse-event benchmark captures only software-generated
pointer activity. To support the **actual** 512×512 / 786% / 60px Brush
reproduction, `DrawingCanvas` can now write one newline-delimited JSON record
per *successfully completed* Brush/Eraser gesture. This runs only when
`DRAWING_T095_TRACE_JSONL` is explicitly set to a `user://` destination, for
example `user://t095-owner-recheck.jsonl`. When unset, no file is opened. A
cancelled or failed-commit stroke is not recorded. The trace is intentionally
restricted to the app's local user-data directory: absolute, `res://`,
traversal (`..`) and backslash destinations are rejected.

The versioned `schema: 1` record includes zoom, width, viewport/image sizes,
backend, aggregate stage/queue/compose/upload/commit timing and bounded
chronological arrays: up to 4,096 sample-to-stage ages, up to 4,096 atomic
batch CPU times, and up to 1,024 Canvas frame/queue/post-draw samples. Its
`capture_kind: engine_timing_only` is explicit: frame callbacks **are not**
photons and Godot input receipt **is not** a physical pointer timestamp.
No image pixels, brush colors, canvas anchors, raw world/pointer coordinates,
layer names, document titles or source paths are serialized. Only selected
numeric telemetry keys are whitelisted, so later private dictionaries cannot
become captured by default. An existing trace is appended with a file-size
ceiling of 4 MiB; after reaching the ceiling, further records are skipped.
Delete or rename the file between sessions to resume capture. No network
transfer, application preference, or runtime UI action is involved.

**Owner collection:** launch the actual app with that environment variable,
make 5–10 true physical 60px Brush strokes at 786% on a new ~512×512 image,
include an initial cold stroke and warmed repeats, and attach the local JSONL.
Record OS, GPU/driver, scaling, display/window size, source layer count and
build SHA separately; the JSONL intentionally excludes machine identifiers.
Record visible preview catch-up and post-release stall on the actual screen;
consider external high-speed video if physical input-to-photon is required.
Do not compare software callback p95 to photon latency or mark T-095 Done
without explicit owner hardware acceptance.

## Independent red/green and regression checks

Pinned local tooling: Godot `4.8.beta3.official.c51ff06e8` plus the prebuilt
real Hokusai/native extension, Linux headless / Xvfb/Mesa. The new
`drawing/tests/t095_owner_trace_smoke.gd` test first failed **1 of 9** on the
previous Canvas (no opt-in records); a staged-only deliberately disabled writer
also failed **1 of 9**. After implementation, the expanded **17/17** oracle
passes with exit code 0 and a strict `T095_OWNER_TRACE_PASSED` marker. Its
checks cover default-disabled behavior, two independent append records,
versioned metadata and bounded arrays, absence of private content, cancelled
stroke suppression, path traversal rejection, unchanged RGBA8/Undo/Redo, and
rejection of a third append when the file is already above 4 MiB. Temporary
trace files are deleted after the test.

Twelve adjacent headless tests passed individually with engine exit code 0
and T-094's exact-marker checker: bounded frame phases, frame backlog,
post-draw pairing, changed-stage/post-draw, input-receipt/post-draw, no-op
redraw, duplicate-input drain, Brush coverage (32 assertions), NativeHard
source rollback (113), Hokusai pigment rollback (57), deferred staging (492),
and mixed-edit rollback (504). Xvfb native navigation passed **48/48**,
integration **30/30**, fallback **7/7**, and five complete real
`InputEventMouseMotion` 60px pointer gestures exited successfully. The
software staging p95 in this witness was **194.046 ms** and release-to-commit
p95 was **66.113 ms**. These are **not** before/after latency improvements or
physical-device acceptance metrics.

The clean standalone import with both native library and `.gdextension`
descriptor removed exited 0 and passed the new **17/17** oracle and existing
native-absent fallback **7/7**. The on-demand
`.github/workflows/godot-native-t095-brush.yml` now runs the new oracle with
T-094 strict marker validation and retains the raw log. Its inclusion does
**not** alter the required fast-CI matrix or claim hosted Actions success.

**Remaining:** owner physical-device evidence and approval, hosted Actions,
and hardware input-to-photon measurement. No status or dependency gate is
changed in this checkpoint.
