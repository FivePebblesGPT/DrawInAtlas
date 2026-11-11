# T-101 — optional NativeHard tile-local dispatch, not physical latency acceptance (2026-11-12)

**Scope:** One small optional NativeHard implementation ticket after local T-100
`bee34f04580b64c4f54cb6e05ab497a81b04b736` (its parent remote
`79b8959e9eac01b3bb10a144a46407acc6901aed` remains the current
unmerged PR #17 HEAD at the time checked). T-097 is Done; T-095 is still
`In Progress`, `manual_review: true`; T-096 is still `Manual Review`.
This evidence is from a local working tree, not hosted CI or physical input
hardware. The prior local T-099/T-100 commit diff is included in the
cumulative mailbox against that remote HEAD.

## Baseline profile and narrow change

Pinned runtime: Linux Godot `4.8.beta3.official.c51ff06e8`, software
Xvfb `1280x900x24`, Mesa 25.0.7 llvmpipe, OpenGL compatibility, Dummy
audio; real local optional Rust GDExtension `DrawingNativeBrush` built from
the pinned offline Hokusai/godot-rust workspace in the supplied bundle.
`drawing/tests/t095_full_canvas_brush_native.gd` is an actual 100-event
Godot mouse-down/move/up, 96px full-red, 512x512, one-Undo witness. The
unmodified T-100 NativeHard pointer run reported **1396ms** staging CPU,
**1196ms** commit CPU, **834ms** compositor CPU, **79** previews and
**4676ms** input-to-postdraw. The existing T-095 60px Hokusai preset profile
showed **~14–15ms** native Hokusai CPU versus **~173–232ms** staging CPU
within five repeated strokes. These are software/engine boundaries.

`addons/drawing/edit_session.gd` now chooses between `_stage_brush_tile()` and
the original generic `_stage()` **before** iterating NativeHard's verified
packed coordinate stream. It avoids 65k–262k extra GDScript dispatch calls
and per-pixel fast-path checks. It **does not** change swept geometry,
coverage, output format, source blend, batch size, soft 6ms drain budget,
Rust ABI, Hokusai pigment conversion, preset semantics or native
availability. The mixed-edit route retains `_stage(..., internal_brush=true)`
and the same journaling + native rollback. A proposed inline Hokusai blend
shortcut was measured locally, provided no reliable benefit, and was
removed rather than becoming an undocumented semantic change.

Source SHA-256 for changed `addons/drawing/edit_session.gd`:
`7f9327814bfdbb75fa27129deab64254e26ec1b3d64dc11e6bc9c9b100e2e2d6`.

## Red/green control and exact source/canonical parity

New `drawing/tests/t101_native_hard_dispatch_smoke.gd` sends deterministic
packed NativeHard coordinates through an instrumented subclass and an
independent generic `_stage` reference. It covers **5,035 assertions**:
four signed-anchor variants (masked/unmasked Brush and Eraser), hidden RGB,
translucent source, one revision and canonical history maps, committed RGBA8
rendering, Undo/Redo, native begin/commit/rollback counts, an injected
late source-tile failure after a valid earlier pixel, preview restoration,
identical retry and mixed public-edit fallback. No native extension is
required for this synthetic packed-output oracle; the same actual GDExtension
is separately tested below.

- T-100 source staged into the standalone app: **exit 1**, 5,031/5,035;
  the four new *native-only dispatch bypass* assertions failed. Original
  mixed/public stage and all source/history parity checks still passed.
  Raw negative-control log SHA-256:
  `12a63d0efe5fccd1d1abd8ff19a2d7f0f3bc5a648655e64751f4035ce320e517`.
- Candidate source: **exit 0**, 5,035/5,035; exact
  `T101_NATIVE_DISPATCH_PASSED`, strict T-094 log checker **exit 0**.
  Final raw-log SHA-256:
  `b5de0830c168c06a801a79c9f02127890744efe16178c1828cbdfcad7a308ecc`.

The on-demand `godot-native-t095-brush.yml` runs this oracle with
`set -euo pipefail`, `timeout`, exact marker validation and raw log
retention. No required fast-CI checks were added or changed.

## Matched software CPU controls, not a strict responsiveness pass

`drawing/tests/t101_native_hard_dispatch_bench.gd` prebuilds exactly
65,536 integer coordinate pairs (one new 256px tile) once per
process, then times `paint_path_native_hard()` with the *same* packed
coordinates and a transactional stub on each of **seven fresh edit sessions**.
It checks the exact 65,536 changed-pixel count and discards every transient
preview. Times are GDScript/native-ABI handoff and stage CPU only; they
**exclude native raster computation, renderer, frame presentation and input**.

| Source variant | Headless seven-trial stage CPU p50 / p95 / max (ms) | Process/checker |
| --- | ---: | --- |
| T-100 baseline (generic per-pixel dispatch) | 284.175 / 415.862 / 415.862 | 0/0 |
| T-101 final candidate (dispatch hoisted once) | **232.521 / 309.358 / 309.358** | 0/0 |
| T-101 repeat run | 242.008 / 253.297 / 253.297 | 0/0 |

The first same-host comparison reduces isolated median stage CPU by
**~18%**; a separate repeat gives ~15% compared with the baseline median.
These small warm-process cohorts are diagnostic, not stable hardware timing
promises. Baseline and candidate returned exactly 65,536 changed pixels.

The independent real GDExtension 96px/Xvfb mouse witness was run with
**three cold processes per original/candidate**, all exit 0 with strict
`T095_FULL_CANVAS_PASSED`, 100 received mouse events, 296 segments, four
256px tile SHA-256 hashes, framebuffer red pixels, one Undo and Redo:

| Variant / run | Stage CPU (ms) | Whole stroke postdraw (ms) | Release→commit (ms) | Changed previews | Max drain CPU (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| T-100 original 1 | 1355.711 | 4617.641 | 4499.574 | 80 | 14.996 |
| T-100 original 2 | 1397.211 | 4807.850 | 4677.908 | 80 | 27.519 |
| T-100 original 3 | 1313.159 | 4780.169 | 4629.543 | 80 | 15.834 |
| T-101 final 1 | 1283.408 | 4434.302 | 4323.024 | 76 | 21.960 |
| T-101 final 2 | 1338.881 | 4788.085 | 4658.268 | 78 | 27.348 |
| T-101 final 3 | 1371.913 | 5082.188 | 4963.466 | 80 | 21.894 |

Median stage CPU **1355.7 → 1338.9ms** (~1%), but **whole-stroke
median 4780.2 → 4788.1ms** (slightly worse); a candidate total reached
5082.2ms. This is an isolated NativeHard dispatch optimization **not an
established real-pointer speedup**, and does not erase multi-second latency
or the >6ms per-call soft-budget overruns. The 100ms owner goal fails.

Unmodified Hokusai .myb preset path: actual 60px pointer benchmark with
five strokes passed, source, preview, 120+ input samples, Undo/Redo. Its
candidate p50/p95 staging CPU was **197.658/220.967ms**, release p50/p95
**27.521/29.455ms**, frame draw p50/p95 **7.579/19.555ms**; the baseline
five-stroke Hokusai staging p50/p95 was **189.698/247.770ms** and release
p50/p95 **29.000/30.228ms**. These variable, nonidentical successive
strokes show no reliable preset-path speedup. The data did **not** justify
a separate Hokusai code change.

## Correctness, transaction, fallback and build portability

All listed selected tests used the pinned beta3 binary, raw logs and exact
process exit 0. Where an exact marker exists, the T-094 strict log checker
also exited 0:

| Test | Passed assertions / exit status |
| --- | --- |
| T-101 native-only/mixed dispatch | 5035/5035, 0/0 strict |
| T-101 packed staging CPU diagnostic | 7 valid trials, 0/0 strict |
| NativeHard real source read atomic/rollback | 113/113, 0/0 strict |
| Actual Hokusai pigment source read atomic/rollback | 57/57, 0/0 strict |
| NativeHard packed complete ordered source delta | 20/20, 0/0 strict |
| Hokusai packed pigment output parity | 69/69, 0/0 strict |
| Hokusai signed bulk RGBA8 delta parity | 126/126, 0/0 strict |
| Signed non-power-of-two/native tile shifts | 422/422, 0/0 strict |
| Canonical native tile publication | 56/56, 0/0 strict |
| Legacy tile publication | 519/519, 0/0 strict |
| T-100 sparse publication history | 197/197, 0/0 strict |
| Native integration/Hokusai four `.myb` presets | 30/30, process 0 (no exact marker) |
| No-native clean import and fallback after removing optional staged extension | 7/7, process 0 (`native=false`) |

A clean standalone build copied into an external directory and imported
successfully with **no `addons/drawing/native` directory nor extension
registry**, after removal of the optional staged GDExtension: no-native
fallback printed `checks=7 failures=0 native=false`. Native-present fallback
also passed 7/7 with `native=true`. The project still ships only the original
optional extension surface; no new ABI or dependency needed rebuilding.
`tools/validate_ticket_store.py`: **109 tickets and gates validated**.

**Independent final working-tree recheck (same pinned beta3, before commit):**
T-101 synthetic dispatch **5,035/5,035**, seven-trial isolated stage CPU
**p50 231.236ms / p95 261.454ms**, and T-100 publisher **197/197** all
exited 0 and passed exact T-094 marker verification. Real native-present
source rollback **113/113**, pigment rollback **57/57**, native packed delta
**20/20**, Hokusai packed pigment **69/69**, tile publication **56/56**,
and graphical NativeHard full-red **262,144/262,144 pixels**, one Undo/Redo
also exited 0 with strict markers. The latter measured **5486.558ms** for
the gesture, **1457.282ms** stage CPU and **29.961ms** maximum drain call;
it is **not** a new frame-time or total-gesture pass. A first graphical
Hokusai rerun printed its successful marker but did not return before the
outer command watchdog, and is **not** counted as a passing process. The
subsequent independent five-stroke Hokusai retry returned **process 0**,
passed the strict marker check, and measured stage p50/p95
**197.166/209.029ms** and release p50/p95 **30.066/31.503ms**.
All rerun raw logs are retained outside the repository under
`/mnt/data/work/evidence/t101/reverify/`. Neither run claims physical
input-to-photon performance.

## Reproduction

```sh
# From repository root after extracting the supplied Godot beta3 toolchain:
GODOT=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
python3 tools/build_drawing_app.py --in-place
"$GODOT" --headless --editor --path drawing --import --quit

# Deterministic independent source, signed/masked, rollback and Undo/Redo:
timeout 120s "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t101_native_hard_dispatch_smoke.gd \
  > /tmp/t101-dispatch.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t101-dispatch.log \
  --marker T101_NATIVE_DISPATCH_PASSED

# Opt-in CPU-only diagnostic (no CI speed threshold):
timeout 120s "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t101_native_hard_dispatch_bench.gd \
  > /tmp/t101-bench.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t101-bench.log \
  --marker T101_NATIVE_DISPATCH_BENCH_PASSED

# Real optional GDExtension required, source-hashed 96px/512px pointer witness:
DRAWING_BRUSH_BACKEND=NativeHard T095_FULL_CANVAS_RUNS=1 \
  timeout 120s xvfb-run -a -s '-screen 0 1280x900x24' \
  "$GODOT" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t095_full_canvas_brush_native.gd \
  > /tmp/t101-pointer.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t101-pointer.log \
  --marker T095_FULL_CANVAS_PASSED

DRAWING_BRUSH_BACKEND=Hokusai timeout 120s xvfb-run -a \
  -s '-screen 0 1280x900x24' "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/brush_latency_native.gd \
  > /tmp/t101-hokusai.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t101-hokusai.log \
  --marker T095_NATIVE_PASSED

python3 tools/validate_ticket_store.py
```

No physical Windows/Linux owner input-to-photon measurement, hosted Actions
success, device-level frame pacing or T-095/T-096 approval is claimed. This
Done ticket is for a bounded native-only CPU-path refactor with independent
red/green source parity; final product latency review remains separately open.
