# T-141 — bounded occupied outline selection above 4096 tiles

Date: **2026-11-15**. Base: T-140 commit
`3ae72615db7acca08eab67353a7b17eba5b157f4` (Git tree
`a441ccf3e191d3ec01ad8281be788cca8d6dbc49`). Current branch's
remote baseline: `61c6f689974a848f8a7cc4040c98be418518b156`.
Godot `4.8.beta3.official.c51ff06e8`, Linux Xvfb/Mesa llvmpipe,
1920×1080 window, 1680×960 Canvas and 25% zoom for the native witness.

## Defect and bounded correction

T-140's focal square-ring fallback for >4096 occupied explicit pixel-mask
outline tiles visited all intermediate **empty** cells first. Even a fully
visible selected island at `Vector2i(38, 0)` (64px contour coordinates) could
be omitted from the 4096 candidate entries. This is outline visibility,
not selection-mask authorization. A clean detached checkout of T-140 with
identical model/native test files reproduces **2/12 failed headless** and
**4/8 failed native** assertions. The negative-control tree SHA was checked
against the actual T-140 commit before execution; an initial failed import was
resolved by a real Godot resource import before those comparisons.

For an uninverted, operation-free explicit mask with at most **8192 raw pixel
entries**, T-141 now gathers actual occupied visible 64px contour tiles, and
when there are more than 4096, ranks them in Chebyshev-distance rings from
viewport focus. Deterministic native bucket sorting avoids a prohibitively
slow global GDScript comparator sort. At most **4096** eligible contours
remain; the renderer still traces **four new tiles per frame**. Small exact
positive masks retain their established row-major order. Inverted/compound
masks and >8192 entries retain T-140's bounded conservative fallback.
Signed positions, mask truth, canonical raster pixels and Undo history are
unchanged.

The first correct global-sort prototype required **69,193 µs** to plan
4251 entries in one headless run; it was rejected and replaced by native
per-ring sorting. The final candidate took **5,432 µs** versus **3,709 µs**
for the original, incomplete fallback on the same synthetic case. These are
single-run CPU planning samples, **not** a speedup or p95 result. Exact
occupied-tile correctness is the acceptance criterion.

## Verification and reproduction

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t141_sparse_mask_overflow_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t141_sparse_mask_overflow_native.gd
python3 tools/check_godot_model_log.py MODEL.log --marker T141_OUTLINE_PASSED
python3 tools/check_godot_model_log.py NATIVE.log --marker T141_NATIVE_PASSED
PYTHONPATH=tests python3 -m unittest -v \
  test_t139_sparse_selection_outline test_t140_focal_selection_outline \
  test_t141_sparse_mask_overflow
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

| Verification | Result |
| --- | --- |
| T-141 model | **12/12 passed**, baseline 2 failures |
| T-141 software X11 framebuffer | **8/8 passed**, baseline 4 failures |
| Real framebuffer near formerly omitted 16×16 island | **28 changed pixels** |
| T-139 headless/native | **14/14** / **7/7** |
| T-140 headless/native (updated original expectation) | **17/17** / **9/9** |
| T-088 selection/clipboard headless/native | **131/131** / **51/51** |
| T-088 sparse Paste/Capture | **56/56** / **54/54** |
| T-096 large-selection/Move headless/native | **13,847/13,847** / **34/34** |
| Clean native-absent third Drawing package consumer | **passed**, independent source |
| T-139/T-140/T-141 Python contracts | **10/10** |
| Explicit typing | **456 scripts, 33 skill documents** |
| Canonical ticket validator | **141 tickets valid** |
| CI check IDs | **46 unique required IDs, unchanged** |

The original T-139/T-140 source contracts and two model expectations were
updated narrowly to distinguish a bounded exact positive-mask path from
the remaining conservative fallback. The first selection/clipboard attempts
had real missing-SVG-loader errors despite their success markers. Those runs
were **excluded**. A fresh standalone Godot resource import followed by clean
reruns passed strict log verification, without suppressing any errors.
Retained raw negative/positive and neighboring test logs are in
[`t141-occupied-outline-logs/`](t141-occupied-outline-logs/), with their
[SHA-256 manifest](T-141-2026-11-15-occupied-overflow-logs.json).

## Scope and limitations

This is a correctness improvement to the **selected** 4096 contour entries,
not complete coverage of every over-budget selected pixel. At >8192 mask
entries, the T-140 conservative path still applies. Rebuilding a bounded
explicit index each frame has a measurable cost; there is no p95, densely
populated selection performance claim or hardware input-to-photon measurement.
Software X11 framebuffer callbacks are not owner device acceptance.
T-088 remains **In Progress**; T-096 remains **Manual Review**. This ticket
is not approval of either, and the GitHub-hosted fast CI was **not run** on
these unpushed sources.
