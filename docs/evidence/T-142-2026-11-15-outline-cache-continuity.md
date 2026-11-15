# T-142 — preserve selected contour cache overlap during an in-window pan

**Date:** 2026-11-15. **Source baseline:** T-141 final Git tree
`2caa39b9e8c76c3d6be48aae6944a0e679b9c3cb`. **Remote baseline:**
`61c6f689974a848f8a7cc4040c98be418518b156`. **Engine:**
`4.8.beta3.official.c51ff06e8`; Linux Godot X11 under Xvfb/Mesa llvmpipe,
1920×1080 root, 1680×960 Drawing canvas, 25% zoom. Not owner hardware.

## Reproduction and correction

T-140 made an over-budget contour cache follow a changed camera focus by
clearing **all** 4096 retained contour entries, even when the old and new
camera-centered plans overlapped almost completely. A 64-source-pixel camera
pan within an unchanged selection tile window invalidated already traced
selection outlines; the four-new-contours-per-frame budget then needed up to
hundreds of subsequent draws to redisplay distant, still-eligible contours.

The new reconciliation routine is called before tracing. A genuinely changed
selection tile window still invalidates the full cache. An in-window focus
shift with **4096** eligible candidates instead builds a bounded membership
set of the new plan, discards only no-longer-eligible tiles, and keeps the
previously traced contours for overlapping tile IDs. Newly eligible tiles
remain subject to the unchanged four-contours-per-frame creation cap and
4096-entry retained cache limit. Mask changes continue to clear the cache
through `set_selection_mask`; the mask itself is never modified.

### Independent red/green controls

The **unchanged T-141 Git tree** was staged in a separate checkout with
identical new witness files and an actual Godot resource import. Its headless
model reports `T142_OUTLINE_NEGATIVE checks=1 failures=1` (the new guarded
reconciliation API is absent). In the real X11 framebuffer, the unchanged
Canvas fails **3/11** assertions: the previously traced distant contour
vanishes, its cache is discarded, and the far-island pixels disappear from
the framebuffer. Its frame pixel difference is **0** after clearing the mask.
Neither negative run is counted green.

The corrected candidate passes **13/13** headless assertions and **11/11**
real X11 assertions, with strict post-success log checks. For one camera
shift of exactly one 64px tile, **4046/4096** previously cached contours
remain in the new plan, and **50** slots are available for newly focal tiles.
The native test deliberately seeds valid cached empty contours plus the
actual distant 16×16 selected island; it tests post-pan continuity without
requiring 1024 preliminary draw callbacks. The distant island remains
outlined, with **28 changed framebuffer pixels** when the mask is subsequently
cleared. The document has no raster tiles or extra history throughout.

## Commands

```sh
python3 tools/build_drawing_app.py --in-place
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --editor --path drawing --import --quit
/path/to/Godot_v4.8-beta3_linux.x86_64 --headless --audio-driver Dummy --path drawing \
  --script res://tests/t142_outline_cache_model.gd
xvfb-run -a /path/to/Godot_v4.8-beta3_linux.x86_64 \
  --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t142_outline_cache_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T142_OUTLINE_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T142_NATIVE_PASSED
PYTHONPATH=tests python3 -m unittest -v \
  test_t139_sparse_selection_outline test_t140_focal_selection_outline \
  test_t141_sparse_mask_overflow test_t142_outline_cache_reuse
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

| Local verification | Result |
| --- | --- |
| Unchanged T-141 model and real X11 negative controls | 1/1 model failure (missing fix); **3/11** native failures |
| T-142 model / real X11 framebuffer | **13/13** / **11/11**, strict logs |
| T-139/T-140/T-141 models | **14/14**, **17/17**, **12/12** |
| T-139/T-140/T-141 X11 witnesses | **7/7**, **9/9**, **8/8** |
| T-088 selection/clipboard (after fresh asset import) | **131/131** headless; native passed |
| T-088 sparse Paste/Capture | **56/56**, **54/54** |
| T-096 large selection / Move | **13,847/13,847**; native passed |
| Independent native-absent Drawing consumer | Successfully staged/imported; standalone smoke passed |
| Python T-139–T-142 contracts | **14/14** |
| Explicit typing | **458 scripts**, 33 skill documents |
| Canonical ticket/CI inventory | **142 tickets**; 46 unique required CI IDs |

One early T-088 model run printed its success marker but contained missing-SVG
loader errors and was **excluded**. A fresh standalone project resource import
fixed the test environment; its subsequent headless model and both native
selection witnesses passed strict log validation. The original excluded log
is retained as evidence, not reclassified as successful. Recognized Godot
post-exit RID/texture leak diagnostics remain visible in the raw logs.

The 18 retained logs are in [`t142-outline-cache-logs/`](t142-outline-cache-logs/)
and individually SHA-256 recorded in
[`T-142-2026-11-15-contour-cache-logs.json`](T-142-2026-11-15-contour-cache-logs.json).

## Boundaries

This is deterministic software framebuffer continuity for a deliberately
over-budget selection. It is **not** a general CPU speedup, full coverage of
all 4096+ selection tiles, physical input-to-photon proof, hosted CI success,
or owner UX approval. T-088 remains In Progress, T-096 remains Manual Review,
T-095 and hosted CI gates remain open. No manual-review frontmatter changes.
