# T-095 — NativeHard packed-output transfer (2026-11-11)

**Branch:** `sprint/2026-11-11`. **Scope:** T-095 only, `In Progress`,
`manual_review: true`. This is a local software engineering checkpoint.
T-096 remains separately in Manual Review, without owner approval.

## Cause and change

The NativeHard Rust GDExtension already computes correct once-only coverage,
prevalidates all candidate rectangles and journals new coverage for rejected
GDScript source reads. In `hard_segments`, however, every accepted pixel was
emitted through *two* Godot `PackedInt32Array::push` operations. On a 60px
long diagonal that is 58,350 push operations crossing the native/API
container boundary. The new code appends ordered signed coordinates to an
ordinary `Vec<i32>` and converts it to `PackedInt32Array` once. Neither native
geometry, candidate budget, transparent or RGBA8 blending, layer previews,
transaction ownership nor the default Legacy path changed.

A proposed alternate packed-u64 coverage hash was tested but **discarded**:
its preliminary software medians did not show an improvement. No part of
that experiment is included in the commit.

## Reproduction and controlled order variation

Pinned Godot `4.8.beta3.official.c51ff06e8`, godot-rust 0.5.5, Hokusai
0.3.0, offline Cargo/Rust 1.99.1, Linux x86-64. Build with
`bash tools/build_native_brush.sh /path/to/extracted/tooling`, stage canonical
sources with `python3 tools/build_drawing_app.py --in-place`, and preimport
with the native extension present. Run:

```sh
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy \
  --path drawing --script res://tests/t095_native_hard_packed_output.gd
python3 tools/check_godot_model_log.py /tmp/t095-native-hard-packed-output.log \
  --marker T095_NATIVE_HARD_PACKED_OUTPUT_PASSED
```

The oracle independently rasterizes full-rectangle original f32 capsules,
compares the **entire ordered `PackedInt32Array`** (not just counts), and checks
crossing / returning segments, complete pairs, emptied repeat dabs and
native `begin_hard_batch`/`rollback_hard_batch`/`commit_hard_batch` semantics.
It passes **20/20** with both old and changed binaries: initial output
**29,175 pixels**, crossing path **39,152 new pixels**. A first version of
this oracle incorrectly expected no new pixels on the *return sweep*; the
independent original-geometry reference correctly found additional pixels.
That test assumption was fixed before the final pass.

The existing optional
`res://tests/t095_native_hard_scanline_bench.gd` invokes two points within a
384×384 clip at width 60px, cold trial excluded and 10 measured calls, native
coverage and output transfer only. Each run produced **29,175 pixels**:

| Build / invocation order | Median native call | p95 native call |
|---|---:|---:|
| Original baseline #1 | 3.529 ms | 5.599 ms |
| Original baseline #2 | 3.221 ms | 3.396 ms |
| Optimized #1 | 2.642 ms | 3.034 ms |
| Optimized #2 | 2.774 ms | 3.870 ms |
| Original recheck #1 | 3.358 ms | 7.405 ms |
| Original recheck #2 | 3.189 ms | 3.474 ms |

The original recheck was compiled from the repository's prior HEAD source,
then the optimized source and library were restored and staged. Timing varies
between runs; the repeated lower optimized median supports an isolated
native-call improvement only. Do **not** extrapolate to screen redraw,
held-button responsiveness or physical input-to-photon latency.

## Adjacent local tests and remaining gates

- Offline Rust unit tests **6/6**, `cargo clippy -- -D warnings` and rustfmt pass.
- Native output oracle **20/20**, existing scanlines **42/42**, NativeHard
  preflight **28/28**, NativeHard source rollback **113/113**, Hokusai pigment
  rollback **57/57**, native export cache **81/81**, and 60px independent Brush
  source coverage **32/32**, all exit 0 with their expected markers.
- Xvfb real-extension integration **30/30**, released-stroke navigation
  **48/48**, and five-gesture 60px pointer witness exited 0. They are
  software-rendered tests, not owner hardware acceptance.
- Fresh standalone output with the native `.gdextension` and `.so` removed
  imported with editor exit 0; its native-absent fallback passed **7/7**.
- The on-demand native workflow now requires a strict log marker for the new
  oracle and retains its raw log. **Hosted Actions not verified.** The 46
  fast required check IDs are unchanged, as is the fail-closed CI policy.

**Outstanding:** owner-reported long 60px Brush catch-up on actual display /
GPU/driver, explicit manual acceptance and input-to-photon profiling. T-095
must not be moved to Done or Manual Review solely on this software result.
