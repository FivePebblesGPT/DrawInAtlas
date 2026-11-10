# T-095 — deferred Brush / mixed-edit rollback safety (2026-11-09)

## Defect and scope

The preceding T-095 deferred swept-Brush optimization keeps RGBA8 changes in
`DrawingEditSession._preview_tiles` and only materializes global pixel keys
when mixed edit APIs need them. `fill_rect()`, `apply_region()`,
`paint_polygon()` and `flood_fill()` called `_materialize_hokusai_preview()`
before taking their rollback snapshots but omitted
`_materialize_brush_preview()`. The first `_stage()` of the mixed operation
materialized the already-valid Brush *after* the old dictionaries had been
copied. A late lazy-tile read failure then restored the empty prior dicts and
rebuilt an empty preview, discarding the valid Brush edit.

The fix materializes both deferred backends before each mixed operation's
rollback snapshot. These four paths now preserve pre-existing Brush pixels
under the same failure/rollback semantics as canonical pixel-key sessions. It
does not alter the native engine, swept geometry, selection semantics or the
canonical document format.

## Reproduction / independent oracle

`drawing/tests/t095_mixed_edit_rollback_smoke.gd` opens two independent
`DrawingDocument` instances, one with the deferred Brush path and one pinned
to the original canonical pixel-key path (`_brush_tile_publish = false`). For
each of the four APIs and storage strides **16 and 32**, it:

1. Seeds a contiguous nontransparent source row for Flood Fill, then paints a
   valid initial Brush dab. Both sessions have identical detached previews.
2. Registers a deliberately unavailable *later* lazy source tile, after the
   mixed operation has staged changes in earlier tiles.
3. Asserts both operations fail, original Brush change count and preview are
   unchanged, and no document pixels are published.
4. Removes the deliberately injected failure and either retries the same
   operation, or immediately commits **only** the preceding valid Brush.
5. Compares exact RGBA8 rendered output, canonical history `before`/`after`
   dictionaries, atomic commit, Undo and Redo against the original publisher.

All coordinates use anchors (+2,147,483,648, −2,147,483,648), exercising
signed 64-bit document-coordinate mapping. Tests observe the preview in a safe
window while the lazy tile is unavailable; the full region is compared after
removing that artificial read failure.

### Original-source negative control

With the original committed `addons/drawing/edit_session.gd` temporarily
staged in `drawing/addons/drawing/` *only* for the test, the oracle exited 1:

```text
T095_MIXED_ROLLBACK_FAILED checks=428 failures=96
```

The previous source failed change-count, preview, history, or Redo assertions.
After re-staging the fixed canonical source:

```text
T095_MIXED_ROLLBACK_PASSED checks=504 failures=0
```

A fresh standalone project with the optional GDExtension omitted **before**
first Godot import also passed all **504/504** oracle checks and the **6/6**
Legacy missing-binary fallback check. The exact marker was verified by
`tools/check_godot_model_log.py` (fail-closed).

## Neighboring local checks

- Deferred Brush old-path parity: **492/492**; Legacy tile history: **519/519**.
- Legacy 60px source oracle: **32/32**; Geometry2D oblique oracle: **86/86**.
- Hokusai pixel delta: **126/126**; tile-commit history: **56/56**;
  sparse-preview: **133/133**; long input queue: **31/31**.
- Xvfb/Mesa: native preset integration **30/30**, post-release navigation
  **48/48**, native live-stroke passed, viewport cache **153/153** after clean
  standalone asset import.
- Pixel-boundary framebuffer emitted **17 checks, 0 failed** but its process
  exited nonzero with Godot GL/RID resource-leak shutdown diagnostics. It is
  **not** represented as a clean process pass.
- `python3 tools/validate_ticket_store.py` and CI workflow YAML validation
  run locally. Hosted GitHub Actions is not included in these observations.

## Acceptance and limitations

The changed path applies to mixed edit APIs within one detached gesture
transaction; it is a correctness fix, **not a faster 60px Brush benchmark**.
No physical input-to-photon latency or owner acceptance is inferred from
headless or Xvfb tests. Preserve T-095 `In Progress`, `manual_review: true`,
and T-096's independent Manual Review. PR #16 must not be merged based on
this result alone.
