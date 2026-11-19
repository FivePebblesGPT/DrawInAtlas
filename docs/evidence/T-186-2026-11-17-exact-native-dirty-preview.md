# T-186 — Batch-local native preview invalidation (2026-11-17)

## Outcome and exact scope

**One bounded change retained:** Rust's active native tile edit now exposes
`batch_dirty_tiles(transaction)` with rectangles for pixels *actually modified
by the most recent successful stage*. The cumulative `dirty_tiles(transaction)`
remains authoritative for atomic commit, Undo/Redo and transaction history.
`DrawingEditSession` stamps only changed 128px display tiles intersecting those
batch-local rectangles; previously changed display stamps remain in the index.
No-op batches no longer restamp old tiles. Native RGBA8 preview cache entries are
cleared only for changed storage tiles. The existing capped index falls back to
conservative storage-tile stamps on oversized/nonstandard/unsafe inputs.

This avoids full recomposition of unchanged 128px neighbors inside a dirty
256px storage tile. **No Canvas visibility budget was reduced**: already-warm
textures are still rendered every frame and updated whenever their actual
pixels change (T-181); cold content and bounded focal LRU are unchanged.
Source, alpha, erasure, masks, signed storage, import and native history paths
are unchanged. A separate newly added Rust map stores at most 128 per-batch
rectangles, bounded by the existing `MAX_ACTIVE_TILES` limit. The Canvas
retains its preexisting `MAX_PREVIEW_DISPLAY_KEYS=4096` cap. This is not a
whole-compositor rewrite or a claim of physical device comfort.

`DRAWING_T186_CUMULATIVE_COUNTERFACTUAL=1` is an **opt-in diagnostic only**:
it uses the previous cumulative-stamp/invalidate-all behavior through the
same native library, script, input workload and renderer for direct A/B
measurement; production defaults to exact changes. The flag does not alter
native source output or commit semantics. Retain it for reproducibility, not
as an alternative supported painting backend.

## Provenance, comparator and raw evidence

- **Dependency:** T-185's [fresh current-workspace profile](T-185-2026-11-17-current-workspace-profile.md), including its four complete processes, ranked compositor hotspot and failed-exit disclosures. Initial current-turn baseline is also in
  [`T-186-2026-11-17-raw/initial/baseline/`](T-186-2026-11-17-raw/initial/baseline/).
- **Matched counterfactual:** `matched/legacy` (env flag) versus
  `matched/exact` (default), back-to-back, same checkout, compiled library SHA-256
  `01f0e056c5beb07d6ff05d2ad08f61ddba61ce7605c91f668ce151f51580bca9`,
  four bundled preset SHA-256 identities recorded in both full-workspace
  `summary.json` files and same 96px Hard Round preset. Both runs use virtual
  AMD EPYC 9V74, Linux 6.18.57, Python 3.13.5, pinned Godot 4.8 beta3,
  Xvfb 1280×900×24, software llvmpipe / GL compatibility, and 512² signed
  raster canvas. No hardware FPS/input-to-photon measurement is claimed.
- **Source and integrity:** both comparison modes used the same working-tree
  `canvas.gd`, `edit_session.gd`, `workspace.gd`, native binary, benchmark
  scripts and MyPaint presets. Hashes for both modes are in
  [`matched/legacy/workspace/summary.json`](T-186-2026-11-17-raw/matched/legacy/workspace/summary.json)
  and [`matched/exact/workspace/summary.json`](T-186-2026-11-17-raw/matched/exact/workspace/summary.json).
  After capturing the matched A/B, the opt-in T-185 *diagnostic* revisited-entry
  counter was moved before preview stamping, restoring its historical meaning;
  it does not change rendered pixels, dirty choices or the native library.
  The final focused tests were rerun after that correction. The final native
  release rebuild reproduced the **same** library SHA-256 shown above.
- **Raw logs, timed zero exit records, run summaries:**
  [`matched/legacy/`](T-186-2026-11-17-raw/matched/legacy/) and
  [`matched/exact/`](T-186-2026-11-17-raw/matched/exact/) contain both rapid
  96px runs (two cold processes, one warm process with two strokes) and one
  full-workspace process (eight cases) **per comparator**. All six rapid
  processes, two workspace processes and strict validators exited zero. Every
  rapid run independently verified full 262,144 pixel coverage, source SHA,
  five framebuffer points, hidden RGB, mask, cancel/retry, native Undo/Redo.
  All eight full-workspace cases per process verified native source/revision,
  clip/coverage and Eraser; no source digest changed between comparator modes.
- **Discarded/incomplete evidence:** a *prior*, non-A/B initial baseline
  attempted two workspace processes; one had a confirmed zero exit; the other
  emitted all case markers but its `.time` remained empty at outer timeout.
  The second is preserved in `initial/baseline/workspace/workspace-1.log` and
  `.time`, **excluded** from matched statistics. The broad `make check` attempt
  is also preserved in `checks/make-check.log`; it was interrupted during
  Atlas editor import and is **not called a successful whole-suite exit**.

The `matched` full-workspace runs are only **n=1 process per mode** (eight
scenarios each). Within-process frame p50/p95 below describe the observed
post-draw callback intervals, *not* p95 over independent host runs. An earlier
independently captured candidate process and baseline process corroborate the
large reduction in composition/upload requests, but do not turn this into an
owner-hardware acceptance. A repeated cross-run T-185 baseline (four accepted
processes) also exists in T-185's evidence; do not pool differing snapshots
into a fabricated independent matched sample.

## Full Drawing workspace — frame cadence and critical path

Mouse motion, held stationary preview, Eraser, 54% and 100% zoom, warm and cold
cache all run through real `main.tscn` workspace, native tile store and
software rendering. Each matched process exercised the same eight scenarios
and produced validated source hashes, frame callbacks and RSS.

| Full-workspace case | Cumulative Canvas compose CPU, legacy → exact (ms) | Requested texture uploads, legacy → exact (MB) | Frame-postdraw interval p50 / p95, legacy → exact (ms) | ≥83.33ms frame intervals, legacy → exact |
| --- | ---: | ---: | ---: | ---: |
| 54% cold Brush | 754.8 → **270.3** | 9.63 → **3.47** | 28.3 / 122.9 → **9.7 / 71.0** | 7/27 → **1/33** |
| 54% warm overlap Brush | 800.1 → **239.1** | 9.70 → **3.47** | 62.7 / 119.2 → **7.6 / 63.0** | 7/23 → **0/39** |
| 54% stationary held Brush | 617.4 → **184.1** | 9.70 → **3.15** | 8.0 / 85.7 → **11.4 / 53.2** | 2/31 → **0/28** |
| 54% warm Eraser | 797.4 → **284.8** | 9.70 → **3.47** | 46.2 / 117.4 → **8.9 / 75.5** | 7/25 → **1/29** |
| 100% cold Brush | 744.2 → **287.5** | 9.63 → **3.47** | 31.3 / 110.6 → **12.8 / 78.4** | 7/27 → **1/28** |
| 100% warm overlap | 654.1 → **269.7** | 9.70 → **3.47** | 53.4 / 90.5 → **24.1 / 72.4** | 4/25 → **1/24** |
| 100% stationary held | 538.2 → **200.9** | 9.70 → **3.15** | 9.6 / 81.3 → **14.4 / 62.0** | 0/26 → **0/27** |
| 100% warm Eraser | 793.9 → **303.4** | 9.70 → **3.47** | 13.9 / 117.5 → **10.9 / 76.2** | 7/26 → **1/26** |

For 54% cold Brush, composition CPU is ~64% lower, requested texture upload
bytes ~64% lower, postdraw p95 interval ~42% lower, and the ≥83ms frame
fraction drops from 7/27 to 1/33. At the observed p95 frame period,
122.9ms corresponds to ~8.1 FPS-equivalent and 71.0ms to ~14.1
FPS-equivalent for those intervals; these are **not** physical sustained FPS. These counters measure Godot CPU/API work
and engine callbacks; GPU transfer completion and actual monitor scanout were
not sampled. The marked source digest/oracle remains identical.

**Queue and delayed-release checks:** At 54% cold, first-preview submit/postdraw
were **35.5/43.1 ms → 48.0/54.5 ms** (both *slower* in this run), and oldest
pending input age p95 **11.2 → 13.6 ms**. No hidden claim that every latency
improves; the input producer is engine paced. Peak pending-count remains 1.
Release→commit **9.5 → 7.8 ms**, release→settled postdraw **122.7 → 107.0 ms**,
and full paced-gesture down→settled **1237.9 → 750.9 ms**. At warm overlap,
release→settled **140.6 → 79.1 ms**, and total **1361.3 → 726.4 ms**.
The native tile-store per-gesture export delta is **10.75 → 6.82 MB** in all
full-workspace cases; these are *deltas* from cumulative counters, not raw
lifetime totals. Native stage CPU remains approximately 80–100ms per stroke;
work has not simply moved into commit latency. Matched workspace peak RSS was
**324,156 KiB legacy versus 323,940 KiB exact**, and no unbounded display
cache or additional RGBA tile mirror was introduced.

## Separate, pinned 96px/512² rapid T-146 benchmark

The acceptance metric remains **`total_to_postdraw_ms`**, with 100 injected
chronological pointer events, hard-round 96px, native clip/coverage and real
postdraw callback. This is *not* the paced full-workspace gesture above.
Percentiles use 2 cold strokes from separate processes and 2 warm strokes
in one process **per mode**; these small, interpolation-free rank quantiles
should not be read as confidence limits.

| Fixed rapid metric | Legacy cold p50 / p95 | Exact cold p50 / p95 | Legacy warm p50 / p95 | Exact warm p50 / p95 |
| --- | ---: | ---: | ---: | ---: |
| **Total→postdraw (ms)** | 663.4 / 704.6 | **517.3 / 621.9** | 616.2 / 814.8 | **612.8 / 660.2** |
| Release→commit (ms) | 619.5 / 644.4 | **403.7 / 479.5** | 565.1 / 734.9 | **493.3 / 522.8** |
| Cumulative compose CPU (ms) | 249.5 / 385.1 | **184.1 / 232.6** | 348.5 / 457.7 | **230.5 / 231.0** |

All eight independent cold/warm stroke source SHA-256 digests are identical,
`6df89cc96336...`; all Hokusai runs passed full mask, hidden-RGB,
source, Undo/Redo, clip, framebuffer and cancel/retry oracles. Warm p50 is
essentially unchanged here; warm p95 and the composition work improve. The
**≤250ms milestone and preferred ≤200ms stretch are not met** by either cold
or warm p50/p95. Do **not** revise the metric, substitute a CPU-only substage,
or promote software-X11 results to physical approval. T-187 carries the next
separate measured path; T-095 and T-152 physical/post-consolidation gates remain.

## Correctness, reproducibility, and limitations

- **Rust unit tests:** 26 passed, including `t186_batch_dirty_tracks_actual_changed_pixels_not_cumulative_history` (first changed tile, identical no-op, second disjoint dirty pixel, cumulative rect, signed tile, Undo/Redo). Last-batch storage remains bounded, is refreshed only after a successful stage, and cannot replace cumulative history publication.
- **T-186 graphical X11 regression:** 14/14 passed. A real native 16px mouse Brush changes one signed 128px half of a 256px source tile; the exact stamp index lists only the changed display tile, the other warm tile retains its framebuffer pixels, a subsequent cross-half stroke refreshes both, and native source + Undo/Redo survive. The test initially failed because its stationary pointer-down had generated no batch; the test now sends an actual movement. The original cumulative index would fail the exact-key assertion. This regression is added to `make test-graphical` after T-181.
- **T-181 graphical warm-tile retention:** 19/19 passed, no moving-frame holes. The retained warm images still update; the cold budget is unchanged.
- **Native integration:** 312 native tile checks, 32 Hokusai Brush integration checks, 42 standalone smoke, 16 bundled-preset controls and 43 Atlas history checks all exited zero separately. Rapid T-146 adds independent source/mask/hidden RGB/cancel/retry/Undo/Redo/full framebuffer checks. Rust, direct Godot and Xvfb outputs are in `checks/`.
- **Broad `make check`:** Python tests and Ruff/ty passed, native compilation and Drawing import completed, but the external sandbox timeout interrupted the Atlas editor import; **no successful full `make check` exit is claimed**. Explicit standalone/Atlas native history tests were then executed directly and passed. The raw interrupted log is retained rather than hidden.
- **Manual/release gates:** no user signoff is inferred. T-095 reference-device 60/96px usability, T-151/T-152 later post-consolidation gate, T-148/T-149 universal tile/history authority, T-105 Windows/export and independent review remain open.

### Reproduction

```sh
# Real native release extension must already be imported/staged into Drawing.
GODOT=.build/toolchains/<sha>/bin/godot
DRAWING_T186_CUMULATIVE_COUNTERFACTUAL=1 python3 tools/run_t185_profile.py \
  --godot "$GODOT" --output /tmp/t186-old-workspace --trials 1 --timeout 45
python3 tools/run_t185_profile.py \
  --godot "$GODOT" --output /tmp/t186-exact-workspace --trials 1 --timeout 45
DRAWING_T186_CUMULATIVE_COUNTERFACTUAL=1 python3 tools/run_t146_hokusai_bench.py \
  --godot "$GODOT" --output /tmp/t186-old-rapid --cold 2 --warm 2 --timeout 45
python3 tools/run_t146_hokusai_bench.py \
  --godot "$GODOT" --output /tmp/t186-exact-rapid --cold 2 --warm 2 --timeout 45
make test-graphical TOOLCHAIN=bundle BUNDLE=/absolute/path/to/toolchain.tar.zst
```

This closes **T-186's one measured optimization**, **not** the remaining
250/200ms performance target, hardware acceptance or universal architecture.
