# T-144 — reuse bounded selection-outline eligibility plans

**Date:** 2026-11-15. **Base:** unchanged T-143 Git tree
`dbdf052d4bfaec5e17d5d932228a93eb3a70b2bf`; remote branch baseline
`61c6f689974a848f8a7cc4040c98be418518b156`.
**Engine:** pinned `4.8.beta3.official.c51ff06e8` (Linux x86-64).
**Renderer:** headless model and Xvfb X11/OpenGL llvmpipe native framebuffer;
root 1920×1080, Canvas 1680×960 at 25% zoom. This is **not** physical GPU,
Windows, tablet/stylus, or input-to-photon verification.

## Reproduced cost and correction

T-141 enumerates selected pixels (up to 8192 dictionary keys) and constructs a
focal-first bounded 4096-contour candidate plan. T-143 reuses traced contours
as the camera pans, but a stable 4300-point selection still recomputed the
candidate list **on every deferred draw**, often hundreds of times at only
four newly traced contours per frame. The new plan retains the same capped
candidate array for an unchanged selection generation, exact clipped source
footprint and camera focal tile. Callers receive a duplicate; context changes
rebuild the plan. In-place `set_mask` or combination increments a selection
mutation epoch and invalidates the traced cache as well. Direct inversion,
operation-count and pixel-key-count changes are checked conservatively.

This does not change selection mask truth, tile ordering, fallback bounds,
RGBA8 source bytes, history, or the four-contour/frame and 4096-contour caps.
No new persistent file format or native dependency is introduced.

### Independent red and green controls

| Witness | Unchanged T-143 | T-144 candidate |
| --- | --- | --- |
| Headless plan model | **10/16 failures**; 24 warm plans median **5517 µs**, p95 6562 µs | **16/16 passed**; 24 warm plans median **2 µs**, p95 2 µs |
| Real native X11 framebuffer | **3/9 failures**, including repeated deferred planning | **9/9 passed**; 28 pixels of true overlay/framebuffer difference |
| Cached plan builds | No cache, repeated full recomputation | One build during stationary progressive rendering; single rebuild after pan |

Both negative controls were run from an independently restored checkout
at the **unchanged T-143 tree** with only the new test scripts added. Each
process finished with a nonzero test exit, and the failure markers are
retained. A first candidate framebuffer attempt used only 1px islands that
were too small to survive 25% screen sampling; the final native oracle uses a
16×16 center island and compares actual rendered pixels after deselection.
A later native negative-control run also corrected the test's handling of
a missing, baseline-only diagnostic field to obtain a complete **3/9** result.

This measurement isolates **only candidate-plan construction**; it is not a
full-frame CPU benchmark, a total contour construction speedup, or a claim of
roughly equivalent UI latency improvement. The 8192-key/4096-tile limits and
fallback still govern full-size/compound selection behavior.

## Adjacent verification

| Verification | Local result |
| --- | --- |
| T-139/T-140/T-141/T-142/T-143 headless models | 14/14, 17/17, 12/12, 13/13, 14/14; strict logs |
| T-139/T-140/T-141/T-142/T-143 native X11 | 7/7, 9/9, 8/8, 11/11, 10/10; strict logs |
| T-088 selection/clipboard | 131/131 headless; native success; strict logs |
| T-088 sparse Paste and Capture | 56/56, 54/54; strict logs |
| T-096 large-selection and native Move | Headless 13,847/13,847; native success; strict logs |
| Independent native-absent Drawing consumer | Import and standalone **42/42**; strict log |
| T-139–T-144 Python source/CI contracts | **19/19** passed |
| Explicit typing | **462 scripts, 33 skill docs** passed |
| Canonical ticket store | **144 tickets validated**, review gates preserved |
| CI workflows | Both YAML files parse; **46 unique required fast-check IDs** |

The first headless T-088 clipboard smoke reported success but contained
**missing SVG-loader errors**; it was excluded from strict passes. A fresh
Godot resource import fixed the environment, and the clean rerun passed.
The independent native-absent consumer retained **four recognized Godot
post-success RID/texture leak diagnostics**; the log verifier did not hide
them. Hosted CI has not been rerun for this local source.

## Reproduction

```sh
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --audio-driver Dummy \
  --path drawing --script res://tests/t144_outline_plan_model.gd
xvfb-run -a /path/to/Godot_v4.8-beta3_linux.x86_64 \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t144_outline_plan_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T144_MODEL_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T144_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t14*.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

All red/green, neighboring, import, Python, typing and consumer outputs are
retained under [`t144-outline-plan-logs/`](t144-outline-plan-logs/). Their
individual SHA-256 digests are recorded in
[`T-144-2026-11-15-log-sha256.json`](T-144-2026-11-15-log-sha256.json).

## Review boundary

T-144 is independently complete for bounded planning throughput. T-088 remains
**In Progress** and T-096 **Manual Review**. T-086/T-095 hardware/latency,
T-106/T-107 hosted CI and other owner gates remain open. Neither local
software renderer timings nor successful keyboard/pointer models constitute
owner physical-device acceptance.
