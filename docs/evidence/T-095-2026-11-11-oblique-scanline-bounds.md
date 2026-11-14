# T-095 — Conservative oblique scanline candidate bounds (2026-11-11)

**State:** engineering checkpoint only; `T-095` stays **In Progress** with
`manual_review: true`. The owner-rejected 60px Brush responsiveness and real
physical-device input-to-photon acceptance are **not** resolved by this test.
`T-096` is still separately in Manual Review. No push, hosted Actions or owner
review was performed.

## Defect/CPU opportunity

The retained Legacy hard-Brush/Eraser path used Godot's exact
`Geometry2D.get_closest_point_to_segment()` for each *uncovered* candidate in
the complete swept-segment bounding rectangle. A long 60px diagonal can have
many candidates which cannot possibly be inside its capsule (e.g. corners of
a ~400×400 box around a long 45-degree stroke). This affects 60px drawing
and may add staging CPU while the pointer queue drains.

`DrawingEditSession._paint_oblique_scanlines()` now bounds X per raster row:
for a pixel within radius of any segment point, its Y coordinate must be
within radius of that segment point's Y, and its X coordinate within radius
of that point's X. Intersect the induced Y-parameter interval with `[0, 1]`,
then widen the interpolated X range by `radius + 4` pixels. The extra four
pixels are a **conservative numerical guard**, not a new coverage predicate.
Actual acceptance still invokes the existing original `Geometry2D` nearest
point and squared distance for *every candidate inside the conservative
window*. This avoids changing exact edge rounding. The 1,000,000-view-pixel
coordinate guard from the axis optimization retains the full reference scan
for high-magnitude float32 coordinates; Y deltas under 0.001 also retain the
original full rectangle to avoid ill-conditioned division. Stationary and
axis-aligned implementations are untouched. Rectangle candidate limits,
recursive splitting, tile source reads, detached edits and rollback are not
relaxed.

## Independent correctness / negative control

New native-independent script:
`drawing/tests/t095_oblique_scanline_bounds_smoke.gd`.

- **513/513** assertions, exit **0**, exact
  `T095_OBLIQUE_SCANLINE_PASSED` under pinned local Godot
  `4.8.beta3.official.c51ff06e8`.
- Twenty-two oblique cases, including all diagonal directions,
  near-horizontal/vertical, fractional widths `0.75`, `1`, `1.25`, `7`,
  `8`, `17`, `31.3`, and `60`, multiple-segment paths, 5,000-candidate
  recursive splitting, clipping, selection hole and region, and an
  above-10-million-view-coordinate fallback.
- Signed world anchors beyond 32 bits, 7/30/64-pixel storage strides,
  transparent/hidden-RGB and partial-alpha source seeds.
- **Independent oracle** traverses the *entire original rectangle* and
  calls `Geometry2D.get_closest_point_to_segment` and ordinary `_stage()`;
  it does **not** reuse the new per-row interval or the tile-local publisher.
  Comparisons include changed-pixel counts, detached preview RGBA8 bytes,
  committed source, canonical before/after history, Undo and Redo.
- **Negative control:** In the staged-only Drawing addon replace the oblique
  `radius + 4.0` broad window with `radius * 0.25`. The same earlier
  20-case oracle exits **1** and fails **55/466** assertions, including
  changed counts, preview, history and Redo. Restore canonical source via
  `python3 tools/build_drawing_app.py --in-place`; it passes **466/466**.
  The final expanded 22-case oracle passes **513/513**.

## Measured local CPU (not UX or native benefit)

Linux Xvfb/Mesa-compatible local headless Godot beta3; same Linux runner,
Godot process fresh for each block. Optional script
`drawing/tests/t095_oblique_scanline_bench.gd` paints **nine fresh
512×512 documents**, one 60px long diagonal each, with native-independent
Legacy `paint_path`, same source-color and clip. The control stages the exact
pre-optimization canonical `edit_session.gd` from the five-commit local HEAD
**only inside the generated Drawing package**. The canonical addon was not
edited in the control. The optimized source was restaged afterward, and the
Oracle rerun. Every repetition publishes exactly **36,438** changed pixels.

| Order | Stage-only median / min / max (ms) | Changed pixels |
| --- | --- | --- |
| Optimized 1 | **156.566 / 149.399 / 162.187** | 36,438 each |
| Original control | 184.701 / 169.283 / 201.910 | 36,438 each |
| Optimized 2 | **158.213 / 149.619 / 184.662** | 36,438 each |

The full synthetic 130-waypoint reference benchmark was **mixed**:
oblique median 506.797ms control versus 519.254ms optimized, and axis/dab
samples were also noisy. This optimization targets long diagonals, not all
segments. The unpaired five-stroke **real mouse-event Xvfb** witness at
786% zoom, 60px Legacy Brush and 120 motions/stroke exits **0** with staged
samples, preview and commit parity: staging p95 **188.823ms**,
release-to-commit p95 **62.191ms**, input-receipt-to-stage p95 **141.138ms**,
compose p95 **20.972ms**, upload p95 **0.608ms**, peak pending **20**.
**No whole-gesture speedup is demonstrated**, and llvmpipe/post-draw
counters cannot measure physical input-to-photon latency.

## Neighboring regressions and CI scope

Strict-marker selected local headless checks passed: original 60px
coverage **32/32**, original oblique geometry **86/86**, axis scanlines
**278/278**, source/preview reference cache **626/626**, tile-key cache
**33,037/33,037**, deferred Brush **492/492**, NativeHard source rollback
**113/113**, Hokusai source rollback **57/57**, export cache **81/81**,
native integration **30/30**, native fallback **7/7**, and input queue
compaction **31/31**. Mixed-edit rollback printed **504/504** in a
combined suite but that overall command timed out; it is **not** counted as
a separate clean process pass in this checkpoint. Model runner exit codes,
strict markers and the new independent oracle are the primary evidence.

The **on-demand**, non-gating `godot-native-t095-brush.yml` now checks the
exact `T095_OBLIQUE_SCANLINE_PASSED` marker using
`tools/check_godot_model_log.py` and retains `/tmp/t095-oblique-scanlines.log`.
A fresh native-absent standalone output (built with `--output`, with
`addons/drawing/native` removed before first editor import) returned editor
import exit **0**, **513/513** independent oblique checks and native-absent
fallback **7/7**, both exit **0**. The local native-present fallback also
passed **7/7**. This confirms the optimization requires no Rust library.

No required fast-CI check ID was modified. Hosted GitHub Actions, hardware
pointer/input-to-photon latency, original minute-long owner reproduction,
and the owner's explicit acceptance remain unverified.

## Reproduce

```bash
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_oblique_scanline_bounds_smoke.gd
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_oblique_scanline_bench.gd
xvfb-run -a -s '-screen 0 1280x900x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/brush_latency_native.gd
```

For the proposed next T-095 step, collect paired pointer/frame timing and
physical input-to-photon evidence on the **owner's actual GPU/display** rather
than adopting this isolated CPU improvement as UX approval.
