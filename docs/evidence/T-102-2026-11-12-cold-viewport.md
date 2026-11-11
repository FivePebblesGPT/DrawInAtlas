# T-102 — bounded cold dense viewport population (2026-11-12)

## Reproducibility and boundaries

- **Prior local source:** `d892ac1d548156fc4bf066711df4f552a507de78` (T-101; all T-099/T-100/T-101 patches applied). Pre-T-102 Canvas from `git show HEAD:addons/drawing/canvas.gd` is the negative control. Its GDScript source is unmodified; it was temporarily copied into the standalone staging tree and restored after each baseline run.
- **Candidate Canvas blob SHA-1:** `3ce3a013da691b021deecbf0d2bed1fe333b95c2` (`git hash-object addons/drawing/canvas.gd`). This is not a claimed hosted commit until the ticket commit is created.
- **Engine:** supplied `Godot_v4.8-beta3_linux.x86_64`, `4.8.beta3.official.c51ff06e8`; X11 `xvfb-run`, GL compatibility, Mesa 25.0.7 llvmpipe; Dummy audio. These **software-rendered post-draw callbacks** cannot attest physical display latency.
- **Fixture:** native 1024×800 window with 800×680 Canvas; two 512×512 complete signed (-256,-256) raster layers, opaque RGBA8 bottom, translucent top and a 32×32 transparent-alpha patch retaining hidden RGB. Source SHA-256 in **both variants:** `59197a2c72a8fd689599d68d842ce70527530f711e82735e4be3c365d2ad359c`. After a signed 2×2 edit and Redo in both variants: `76699b0a958a54a0645e5a6140f6cb692028f7ce30027d695e317dedfdc64495`. Undo restores the original hash. Four signed framebuffer points and hidden-RGB transparency are checked at 25/50/100% zoom, together with pan and layer visibility.

Commands (from repository root, with `GODOT=/path/to/Godot_v4.8-beta3_linux.x86_64`):

```sh
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --path drawing --import --quit
GODOT_SILENCE_ROOT_WARNING=1 xvfb-run -a "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t102_cold_dense_viewport_native.gd \
  2>&1 | tee /tmp/t102-cold-native.log
python3 tools/check_godot_model_log.py /tmp/t102-cold-native.log --marker T102_NATIVE_PASSED
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing \
  --script res://tests/t102_cold_population_smoke.gd 2>&1 | tee /tmp/t102-cold-model.log
python3 tools/check_godot_model_log.py /tmp/t102-cold-model.log --marker T102_MODEL_PASSED
```

Use `set -o pipefail` and actual process exit codes when piping commands; the on-demand workflow does. Test timings are *diagnostic only*, never CI performance thresholds. Local runs stored outside the repository under `/mnt/data/work/evidence/t102-*.log` and were not counted solely from success markers.

## Paired cold/warm results

Three cold and three warm runs at **each** zoom per invocation, no timing assertion; values are p50 / nearest-rank p95 in **milliseconds**, not frame-to-photon. The original branch was run twice, interleaved with two candidate runs. The final candidate used sparse-first occupancy enumeration and was measured again after that refinement. Distinguish first changed frame (initial partial pixels) from *complete settling* (all 16 persistent tiles).

| Run | Zoom | Cold first p50/p95 | Complete settle p50/p95 | Max per-draw CPU p95 | Warm p50/p95 |
|---|---:|---:|---:|---:|---:|
| Old A1 | 25% | 343.5 / 363.3 | 343.5 / 363.3 | 346.6 | 0.55 / 0.60 |
| Old A2 | 25% | 362.2 / 362.7 | 362.3 / 362.7 | 355.2 | 0.57 / 1.17 |
| Candidate final | 25% | 54.7 / 56.5 | 443.4 / 450.9 | 29.0 | 0.58 / 0.66 |
| Old A1 | 50% | 350.0 / 362.7 | 350.0 / 362.7 | 355.8 | 0.27 / 0.32 |
| Old A2 | 50% | 357.0 / 406.1 | 357.0 / 406.1 | 397.2 | 0.30 / 0.41 |
| Candidate final | 50% | 51.3 / 52.9 | 437.9 / 440.9 | 25.5 | 0.26 / 0.32 |
| Old A1 | 100% | 376.4 / 398.3 | 376.4 / 398.3 | 389.9 | 0.15 / 0.22 |
| Old A2 | 100% | 359.2 / 364.7 | 359.2 / 364.7 | 357.2 | 0.14 / 0.18 |
| Candidate final | 100% | 50.7 / 51.5 | 437.1 / 453.2 | 27.5 | 0.18 / 0.26 |

Two earlier candidate runs with the **less efficient** display-window iterator also passed 110/110 but settled slower (50% p50 432–566ms); one had a 25%-zoom maximum-draw p95 of **95.3ms**. Even with a ten-millisecond soft budget, one atomic 128px multi-layer composite can exceed it. **Do not assert a 16ms GPU/scan-out or 100ms total-responsiveness pass.** The final candidate is a narrower per-draw stall reduction with a demonstrated total-settling trade-off.

Full first-population requires **16 × 65,536 = 1,048,576 RGBA texture bytes**; the retained persistent cache at steady state has 16 entries (1 MiB), well below the 144-tile/9 MiB limit. The callback sampler can miss the first changing tile when switching zoom, so it reports 15 captured compositions and 983,040 sampled upload bytes for candidate trials, **not** the complete upload total; all 16 retained tiles and their final framebuffer/source pixels are checked. Transient over-budget views deliberately retain the prior complete-frame behavior, pending T-103.

Peak process `VmHWM` from `/proc` (includes seed creation and Godot runtime, **not** isolated texture memory): A1 **553,132 KiB**, A2 **554,248 KiB**, final candidate **554,016 KiB**. This does not demonstrate a process-RAM saving or reference-hardware GPU allocation ceiling.

## Controls and test scope

| Test | Outcome |
|---|---|
| Pre-T-102 real Xvfb witness | **exit 1**, `T102_NATIVE: 110 checks; 20 failed` (cold-frame/deferred and new scheduling safeguards); no parse errors, framebuffer/Undo assertions intact |
| Candidate real Xvfb witness | **exit 0**, **110/110** and `T102_NATIVE_PASSED`; strict T-094 checker **exit 0** |
| T-102 headless scheduling oracle | **exit 0**, **13/13** and strict checker **exit 0** |
| T-086 cold renderer + visible plan | **45/45** + **82/82**, exit 0 |
| T-086 real viewport | **153/153**, exit 0, after fresh standalone editor font import |

Retained local raw-log SHA-256 (rebuild independently from the commands above):

- Old A1: `22cbada7a9c9912499ed1728f6326be8a483e368c6e8285e8ee0896e2913178d`
- Old A2: `0c91b234fa33ae2196dcd3e2ad255363cb6a6296923c02605281bfeea23f38bd`
- Final candidate: `f7a342ef43afdec061a86a65eec72fa479fa53f7808ad499433b2d9e1f4cb62e`
- Headless oracle: `5b7ad8e92d675b227e54b08dfd4dbc81fb3c8e743da64cedf981c26b1781daa0`

The new headless oracle is appended to the **existing** required fast T-086 step (46 check IDs remain). The on-demand graphical workflow uses exact success markers, the shared strict log checker and raw-log artifact retention; it is **not** hosted-verified in this local session. T-086's physical-owner hardware requirement and T-095/T-096 approval remain open. T-103 retains sustained oversubscribed dense-view and memory-pressure work.

**Neighboring-test qualification:** An early T-086 native viewport rerun after package restaging failed two font checks because the standalone project had not reimported its real tracked Lato TTF assets. A fresh `--editor --import` restored normal `FontFile` loading; the subsequent **153/153**, exit 0 and strict-log exit 0 were separately recorded. This was not counted as a passing result until reimport.

An adjacent **unmodified, pre-existing T-094 replay-fixture unit test** also fails **1/13** locally: `tests/test_t094_ci_replay.py` hard-codes `4.8.beta2.official.cafc17a19` in its synthesized fixture, while `tools/verify_godot_ci_replay.py` requires `4.8 beta3`. Both involved files are unchanged from the exact T-101 source; T-102 intentionally does not change this independent CI-policy ticket. The 24 `test_t094_godot_model_log.py` contracts and 3 `test_t086_benchmark_fixtures.py` contracts pass. Do not represent the complete fast-CI replay as green.
