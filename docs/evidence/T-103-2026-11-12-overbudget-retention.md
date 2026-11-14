# T-103 — over-budget dense viewport focal retention (2026-11-12)

## Scope, revision, and environment

- **Compared source:** exact local prior commit `cea49c901c641fd1477e5245720c426eff16be5b` (T-102), with the original `addons/drawing/canvas.gd` copied into **only** the staged standalone project between runs and restored afterward. Baseline Canvas is obtained with `git show cea49c9:addons/drawing/canvas.gd`.
- **Candidate source blob:** `10a1c2a08b5be6edee02d046e13eea3fb9e33944` (`git hash-object addons/drawing/canvas.gd`). Commit attribution follows the T-103 local commit; not a hosted run.
- **Engine:** pinned `4.8.beta3.official.c51ff06e8` from `Godot_v4.8-beta3_linux.x86_64`, X11 `xvfb-run`/Mesa 25.0.7 llvmpipe with GL compatibility and Dummy audio. Linux container `/proc` HWM includes document construction and all Godot/Mesa allocations. **None of these are physical Windows/Linux input-to-photon or GPU VRAM data.**
- **Document and display:** 192 signed `128×128` full raster source chunks covering `[-1024,1024) × [-768,768)`, plus 48 translucent source chunks on a second raster layer. Canonical straight RGBA8; `register_lazy_chunk()` verifies each SHA-256 when resolved. 1080×800 Canvas in 1230×920 X11 window; 25%, 50%, 100%, 50%, 25%, 50% views, with **two real middle-button pan sequences per zoom**, plus a real wheel-up/wheel-down round trip. Source hashes, framebuffer samples, signed mask edits, hidden RGB, layer visibility, atomic Undo/Redo and standalone `DrawingFileIO.save()`/`open()` are checked independently.
- **Cache:** persistent hard cap 144 × 128×128×4 = **9,437,184 bytes (9 MiB)**; the 192-tile source view forces an overflow of 48 at 25/50%. Frame-local references including transient draws reached 12,582,912 bytes (12 MiB), not retained between draws. The published source is never downsampled, replaced by a preview LOD or changed by pan/zoom.

## Implementation and negative control

The old `_reserve_display_slot()` scanned the entire persistent cache for **every** full-budget miss, to find an offscreen or most-distant resident tile. With a moving focal point and dozens of transient uploads this repeats a 144-entry distance scan unnecessarily. The new metadata-only `_focal_retention_plan()` deterministically chooses at most 144 of the nearest *occupied* visible keys **once per draw**. A sorted discard list serves misses without rescanning; an entry evicted before its earlier draw coordinate is reached survives in `evicted_for_frame`, preventing an avoidable rerender or a missing pixel. The list skips keys retired by alpha-zero culling. It uses only the existing bounded display occupancy index, never a full document pixel scan. If the view is small, occupancy unknown, the preview active, the viewport spans more than 65,536 display positions, or more than 4,096 occupied candidates are encountered, the original conservative LRU remains intact.

Negative controls on the **exact unmodified T-102 Canvas**, without editing its source:

| Witness | Prior T-102 | T-103 candidate |
| --- | --- | --- |
| `t103_retention_plan_smoke.gd` | exit **1**, absent focal-planner assertion fails | exit **0**, **13/13**, strict T-094 log check exit 0 |
| `t103_overbudget_viewport_native.gd` final real-wheel fixture | exit **1**, **149/150**; only added focal-plan assertion fails | exit **0**, **150/150**, strict log check exit 0 |
| Signed RGBA source before/after Undo/Redo and Save/reopen | exact parity | exact parity |

Original signed layered center SHA-256 (baseline and candidate): `dc10ae9e1f5d3e6d9a6bdb7a4c6c89931a6bd5770c2e302218eb181f648e02e0`. After the independent signed dot/Redo: `767ddbdef8710b11e7d6462249c1d1a39055d01bb78571118842085ac91c22a7`. The selected/masked paint step is independently Undo/Redo-tested, and a transparent pixel retaining `0x005a01ee` straight RGBA survives portable Save/reopen without blackening the framebuffer.

## Software frame and memory evidence

One 18-frame sample includes 3 snapshots at each of six zoom positions after an initial full cold draw, with real pan input. p95 is nearest-rank; for 18 samples it equals the largest observation. **Milliseconds are Godot draw CPU or call-to-`frame_post_draw` diagnostics**, not delivered physical frames.

| Matched final fixture | Original T-102 | T-103 |
| --- | ---: | ---: |
| Initial dense cold Canvas CPU | 6,196.10 ms | 3,867.26 ms |
| Initial callback interval | 6,368.84 ms | 3,932.61 ms |
| Subsequent draw CPU p50 | 269.88 ms | 233.04 ms |
| Subsequent draw CPU p95 / max | 403.96 ms | 331.67 ms |
| Subsequent callback interval p50 | 287.82 ms | 247.24 ms |
| Subsequent callback interval p95 / max | 425.97 ms | 390.45 ms |
| Subsequent full-tile upload bytes (18 samples) | 49,610,752 | 47,185,920 |
| Subsequent transient textures | 687 | 672 |
| Retained persistent tiles | 144 | 144 |
| `/proc` HWM | 1,150,036 KiB | 1,150,708 KiB |
| Planned over-budget frames, foreground evictions, reuse of evicted entries | 0 / 0 / 0 | 15 / 48 / 25 |

An independent earlier matched pair (before the real-wheel/warm-up fixture refinement) showed **240.95ms vs 202.82ms draw CPU p50**. In a further T-103 rerun with the final fixture, draw CPU p50 was **210.65ms**, initial cold CPU **3,735ms**, and **150/150** assertions passed. The change reduces repeated cache-selection work and some rerendering/uploads, **not** the retained 9 MiB limit; process RAM remains about 1.1 GiB. Some candidate cold trials exceeded 4 seconds and a previous 18-frame sample had a **4.48s** maximum including cold population. The soft draw budget cannot turn large transient composites into a guaranteed 16ms frame. Raw timing across Xvfb/llvmpipe software runs is noisy, and neither cold stalls nor owner-device responsiveness has been accepted.

## Reproduction and verification

From the repository root (run with process exit codes checked and actual full-output logs retained):

```sh
GODOT=/path/to/Godot_v4.8-beta3_linux.x86_64
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --path drawing --import --quit
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing \
  --script res://tests/t103_retention_plan_smoke.gd > /tmp/t103-model.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t103-model.log --marker T103_MODEL_PASSED
GODOT_SILENCE_ROOT_WARNING=1 xvfb-run -a "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t103_overbudget_viewport_native.gd > /tmp/t103-native.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t103-native.log --marker T103_NATIVE_PASSED
python3 tools/validate_ticket_store.py
```

When switching to the **old** baseline, replace only `drawing/addons/drawing/canvas.gd` with `git show cea49c9:addons/drawing/canvas.gd`; restore the T-103 staged Canvas afterward. The baseline is intentionally red on focal-plan availability even though the pixel, masking and save checks remain green. Do **not** use that red process as a successful CI control. No fixed timing threshold is used in CI.

Actual scoped log outcomes:

- T-103 model: **13/13**, process exit 0, strict log exit 0. Original source: process exit 1, one expected assertion failure.
- T-103 X11: **150/150**, process exit 0, strict log exit 0. Original source: process exit 1, **149/150**.
- T-102 cold scheduler model: **13/13**, process exit 0, strict log exit 0.
- T-102 X11 cold dense viewport: **110/110**, process exit 0, strict log exit 0 (after staged editor import).
- Existing T-086 native viewport: **153/153**, process exit 0, strict log exit 0.
- Other neighbors: focal retention **15/15**, cold renderer **45/45**, visible-plan **82/82**, viewport/preview models and selection/clipboard pass process exit and exact strict markers. An initial clipboard log check with a **wrong caller-supplied expected marker** failed; rechecking the unchanged passing log against its correct `T088_MODEL_PASSED` marker returned 0. This is not treated as a source failure.
- Ticket-store validator: **109 tickets**, success; the fast workflow's **46 check IDs** are not increased. The on-demand workflow retains both T-103 raw logs via `if: always()`.

Selected raw logs SHA-256 (the logs remain in the local external evidence folder, **not shipped inside the mailbox**):

```text
Original final 150-check X11: 77650568b31eca88d61d24efb8080b08ed0c4ce1976dd87d32a5542d514bb8d6
Candidate final 150-check X11: dcbbdf1991c6de2571d562530534758e09edaf41fe1eb6a8d8eb942d943fdf2a
Candidate last 150-check X11: dfaa63530dba50ecb1c27827352e0850c8e3fd32b22a8507240d0986455eec98
Original headless absent-method control: 6680b2d5c3f6d4278081e46100640b31c42593f1e12f896c45ffca62697b5541
Candidate headless model: c61ed18e5262fedc5b81d84e907bffa886e61ab292bde321addb579d7397252d
T-102 X11 neighbor: 6321f2958ed8a65ea7f390f89f9ad2ee36fb4675220d18760577e4af677c1a9a
T-086 X11 neighbor: 412888a631a685844abf0f64b6833ee32493f5346ae24dee62249ae322343930
```

**Outstanding independent gates:** T-086 stays In Progress pending owner reference Windows/Linux hardware with real input response and memory/zoom stress; T-095 stays In Progress with manual review true, and T-096 stays Manual Review. The T-094 host-run status and physical display scan-out are not inferred from this software test. No owner acceptance, PR merge, or native binary update is claimed.
