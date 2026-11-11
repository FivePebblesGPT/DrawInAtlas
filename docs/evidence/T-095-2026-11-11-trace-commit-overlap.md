# T-095 — isolate overlapping completed-stroke trace epochs (2026-11-11)

**Scope:** One offline analyzer correctness checkpoint, on `sprint/2026-11-11`. The app's native/GDScript Brush, Godot schema-1 exporter and runtime latency are unchanged. T-095 remains **In Progress**, `manual_review: true`; T-096 remains **Manual Review**. This is not hardware acceptance or a performance improvement.

## Failure and fix

The existing file/epoch partitioner detected only a decreasing `down_us` between consecutive records. In a single Canvas process, a *completed* gesture must be committed before the next gesture begins. Appended logs from different runs can have `next.down_us >= previous.down_us` while still satisfying `next.down_us < previous.commit_us` because a later process's monotonic clock has a different origin. The old analyzer silently pooled such incompatible timing series.

The partitioner now compares each validated new `down_us` to the **preceding committed stroke's `commit_us`**. Strict overlap creates a new one-based timestamp epoch for that file. Exact adjacency (`next.down_us == previous.commit_us`) remains in the same epoch. Each JSONL record's own down/release/commit order is validated first; the previous commit state is advanced only for validated strokes. No path, device identity or content is added to reports. Analysis output stays `t095_trace_analysis_v3` because its fields and cohort meaning remain the same; the Godot schema-1 exporter is unchanged.

The boundary identifies an **observed incompatibility with sequential completed strokes**, not proof of a process restart or hardware switch: out-of-order appended records could also cause it. Unobserved restarts remain indistinguishable, and reference-device inputs plus visual catch-up still require independent owner review.

## Red/green test

An appended file contains three 60px/786% `Legacy` strokes. Stroke 1: `down_us=1,000,000`, `commit_us=1,180,000`, release→commit **80 ms**. Stroke 2: `down_us=1,150,000` (greater than the previous down, but before its commit), release→commit **5 ms**. Stroke 3 follows stroke 2 and also measures **5 ms**.

| Analyzer | Epoch indices | Group release→commit p95 |
| --- | --- | --- |
| Previous 23-commit checkpoint | `1, 1, 1` | 80 ms, misleading pooled group |
| Updated analyzer | `1, 2, 2` | 80 ms / 5 ms, separate groups |

The new unittest **fails** on the previous implementation and passes after the fix. The entire stdlib analyzer suite passes **10/10**, exit 0. `compileall` passes. This is the on-demand workflow's existing strict `T095_TRACE_ANALYZER_PASSED` check, now including the additional contract.

## Nearby pinned-engine checks

Godot `4.8.beta3` standalone, all headless, exit code 0, strict log markers verified with `tools/check_godot_model_log.py`:

| Oracle | Assertions |
| --- | ---: |
| Owner JSONL trace exporter | 17/17 |
| Independent 60px Brush/Eraser pixels + history | 32/32 |
| NativeHard source-failure rollback | 113/113 |
| Hokusai pigment rollback | 57/57 |
| Input-receipt/preview post-draw correlation | 22/22 |

The on-demand workflow YAML and 96-ticket store validator passed. The required fast-CI matrix and T-094 fail-closed policy are unchanged. This checkpoint did not run hosted Actions, real GPU/pointer responsiveness, or physical input-to-photon tests; owner approval is still outstanding.
