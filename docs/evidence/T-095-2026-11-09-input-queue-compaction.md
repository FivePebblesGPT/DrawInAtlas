# T-095 — bounded consumed-pointer prefix during sustained strokes

**Engineering checkpoint, 2026-11-09.** Ticket remains `In Progress`,
`manual_review: true`. The 2026-11-08 owner hardware rejection remains
controlling. PR #16 is not accepted or merged. This checkpoint addresses
sustained input-buffer memory, not physical display latency or raster speed.

## Defect and implementation

`DrawingCanvas._samples` and `_sample_times_us` previously retained all already
staged entries until a drain callback happened to consume the *entire* queue.
When producers continually append pointer events while a consumer stays behind,
this all-empty condition may never occur, so array memory grows with elapsed
stroke length rather than outstanding work. Historical completion times are
already stored separately for profiling; retaining consumed source waypoints is
unnecessary.

At the end of each atomic `_drain_segments` call, the new
`_compact_sample_queue()` preserves the previous empty-queue clearing behavior
and additionally removes a consumed prefix once at least **256** samples have
been dequeued and the prefix is at least half the retained array. Both arrays
are sliced at the identical index; the next queued point, its recorded arrival
time, and any **partially interpolated target** (`_segment_target` and
`_target_arrival_us`) are preserved. Captured positions are still source-space;
all delivered samples are staged in order and contribute to the same atomic
commit. No user-visible raster, brush size, brush mode or camera policy changed.
The threshold amortizes array-copy cost and avoids copying tiny queues.

New per-gesture diagnostics `max_sample_buffer` and `sample_compactions` make
retained-buffer pressure visible independently of the existing `max_pending`
metric. They are not driver event-loss or GPU-present measurements.

## Independent regression

The new `drawing/tests/t095_input_queue_compaction_smoke.gd` passed **31/31**
checks with Godot `4.8.beta2.official.cafc17a19` in a local headless session.
It checks:

- An existing interpolated segment target remains intact while exactly 310 of
  600 input records are removed; the remaining 290 points/timestamps are in
  their original order; no premature repeated copy occurs.
- A 6,000-event interleaved producer/consumer sequence with a persistent
  300-sample backlog retains fewer than 900 array entries, compacts repeatedly,
  and preserves all 300 outstanding positions/timestamps exactly.
- An actual DrawingCanvas Brush session queues 1,600 input points, drains a
  partial prefix, then releases and changes zoom, camera and toolbar tool.
  It commits once; all 1,602 input records including down/release have stage
  completion timestamps, and the resulting RGBA8 render is byte-for-byte
  identical to an independently constructed, unsliced DrawingEditSession path
  using a subtraction-hole selection. Undo/Redo output is identical.

A negative control with the original unbounded `canvas.gd` fails the new
compaction assertions and the strict model-log validator rejects its output.
The positive run prints one `T095_QUEUE_COMPACTION_PASSED checks=31 failures=0`
marker; the fail-closed verifier accepts that log.

## Neighboring tests and software timing

Selected existing regressions passed locally: hard-brush source geometry
**32/32**, original oblique geometry **86/86**, live-stroke model, Hokusai
bulk deltas, signed source tile oracle **4,193/4,193**, released-stroke
navigation **48/48**, native preset integration **30/30**, live-stroke native,
and viewport cache native **153/153**. A fresh standalone build with the
native extension removed *before first import* also passes the **31/31** queue
oracle and **6/6** Legacy fallback checks without an extension-load error.
The canonical ticket validator
reports **96 valid** tickets and unchanged review gates.

The standard real-mouse-dispatch synthetic **60px Legacy, 786% zoom,
5 strokes × 120 motions** workload under 1280×900 Xvfb/Mesa software
rendering still passes. New source staging p95 was **146.880 ms** and
release-to-commit p95 was **69.274 ms**; a nearby pre-change run measured
**145.801 ms** and **63.267 ms**, respectively. No speedup is claimed:
these short VM measurements vary, and the 256-consumed-point compaction
threshold does not normally trigger in a 120-motion stroke. The benefit is
avoiding unbounded *retained* queue memory during longer, continuously
backlogged captures. The new test does not establish physical input-to-photon
latency, sustained multi-minute owner-device performance, or hosted CI.

## Reproduction and review gate

```sh
python3 tools/build_drawing_app.py --in-place
# Run with the pinned Godot 4.8 beta 2 binary:
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_input_queue_compaction_smoke.gd
python3 tools/check_godot_model_log.py /tmp/t095-queue-compaction.log \
  --marker T095_QUEUE_COMPACTION_PASSED
```

The on-demand `godot-native-t095-brush.yml` now saves that log and requires
its strict success marker. Full hosted CI, physical mouse/GPU latency and
explicit owner re-acceptance remain open. Do not close T-095, change Hokusai's
opt-in default, or conflate T-096's independent Manual Review gate.
