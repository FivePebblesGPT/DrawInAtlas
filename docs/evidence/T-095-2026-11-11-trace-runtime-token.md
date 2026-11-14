# T-095 — anonymous trace runtime boundaries (2026-11-11)

**Scope:** one T-095-only trace-correctness checkpoint on branch
`sprint/2026-11-11`; status stays **In Progress**, `manual_review: true`.
No owner-device physical acceptance, hosted CI pass, remote push or
whole-gesture latency improvement is claimed. T-096 remains Manual Review.

## Reproduction and root cause

`tools/analyze_t095_trace.py` previously partitioned one appended JSONL
file only when the next `down_us` preceded the previous committed stroke.
Two Canvas launches can append to one file while their monotonic clocks
happen to rise continuously. Matching canvas settings then silently pool
incompatible sessions, hiding a slow reference run behind fast records.

Independent control: two 60px/786% strokes with 80ms release-to-commit,
followed by two with 5ms, all with increasing `down_us` and identical
reproduction settings. The **previous analyzer grouped all four** with
80ms p95. The updated analyzer returns two groups with p95 **80ms/5ms**.

## Implementation and privacy boundary

`addons/drawing/canvas.gd` lazily generates a fresh 16-byte token using
Godot `Crypto.generate_random_bytes()` only after an explicit valid
`DRAWING_T095_TRACE_JSONL=user://...` opt-in. Each Canvas uses a stable
128-bit lowercase-hex token during its lifetime; a different Canvas gets a
new token. Schema-1 records gain optional `trace_session_id`; the existing
export format, bounded 4 MiB local file, 4096/1024 retained histories,
cancellation semantics and Brush pixel path are unchanged. No OS, user,
GPU, document name, input position, or stable device identifier is used.

The offline analyzer checks token shape, begins a new observed epoch when
a token changes (including transitions to/from legacy token-free traces),
and retains the earlier overlap/reset fallback for legacy records. It
outputs schema `t095_trace_analysis_v4`, never emits tokens in human or
JSON reports, and still separates distinct input files. A token marks only
a **Canvas runtime**, not proven physical hardware, machine or process.
Random-token coincidence is negligibly likely but not a proof of identity.

## Local red/green evidence

Pinned engine: Godot 4.8.beta3 official, Linux headless.

| Test | Result |
| --- | --- |
| Prior analyzer on same-clock control | one invalid 4-stroke cohort, p95 80ms |
| Updated stdlib Python contracts | 13/13, exit 0 |
| Previous Canvas staged temporarily | 2 token assertions fail, exit 1 |
| Real Canvas schema-1 JSONL oracle | 21/21, exit 0 |
| 60px independent Brush pixel oracle | exit 0, strict marker |
| Preview input/post-draw correlation | exit 0, strict marker |
| Frame-phase history | exit 0, strict marker |
| NativeHard rollback | exit 0, strict marker |
| Hokusai rollback | exit 0, strict marker |
| Clean standalone native-absent import | exit 0, no script errors |
| Native-absent real-export oracle | 21/21, exit 0, strict marker |
| Native-absent fallback | 7/7, exit 0 |
| Real 60px/786% Xvfb mouse-event witness | 5/5 strokes, strict `T095_NATIVE_PASSED` |
| Real JSONL parsed by analysis v4 | 5 strokes, one token-bearing runtime cohort |

All negative-control substitutions were confined to staged test files and
restored before final verification. No generated Godot `.gd.uid` files or
JSONL test traces are to be committed. The on-demand strict marker policy
remains unchanged. Owner reference-device testing, OS/GPU/driver/scaling
notes and explicit manual approval are still required.

The five-stroke 120-motion-per-stroke Xvfb/Mesa benchmark retained 270
Canvas frames and 150 matched engine post-draw callbacks. Its measured
staging p95 was **176.651ms**, release-to-commit p95 **59.273ms**. The first
log-verification attempt used a nonexistent marker; checking the script's
actual `T095_NATIVE_PASSED` marker succeeded with the same exit-0 log.
These are local llvmpipe engine observations, **not** owner-device or
physical input-to-photon measurements. The raw JSONL remains outside Git.
