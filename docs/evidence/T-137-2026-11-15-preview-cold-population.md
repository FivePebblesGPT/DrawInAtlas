# T-137 — bounded cold population with a detached preview

Date: 2026-11-15. Branch: `sprint/2026-11-14`. Engine:
**Godot 4.8.beta3.official.c51ff06e8**, Linux x86-64; native framebuffer
via Xvfb / Mesa llvmpipe OpenGL compatibility, not a hardware GPU or
input-to-photon measurement.

## Why this work is independent

After T-136, a detached Brush/Move preview has a bounded, validated display
stamp index when its metadata is complete. However the T-102 cold planner
immediately returned `{}` when a session was active, forcing all cold
committed and preview display textures to compose in one synchronous frame.
The new planner reuses the T-136 **validated** sparse signed union when it
fits the 144-entry retained texture cache, then uses the T-102 focal order
and four-composite, 10 ms soft budget. Generation/owner mismatches are
cold even if the cached entry otherwise appears clean. All other preview
cases and dense/unknown occupancy retain the original complete traversal.

This change intentionally permits a cold framebuffer to fill progressively;
no source bytes or Undo state are changed by scheduling. Each tile still
composites atomically; an expensive individual tile can overrun the budget.

## Exact negative control and paired native result

The 18-check native witness creates nine committed signed Brush dabs and one
detached uncommitted dab, with a 600×450 Canvas at 50% programmatic zoom.
Conservative storage-chunk occupancy covers 34 of 80 display cells; the
complete preview index includes four display stamps. The same test and
pinned software renderer were run with the T-136 version of `canvas.gd`
from `b43b30fca1432f623f845ffe42442db0338d90ce` and with T-137.
The baseline fails **three of 18** scheduling assertions; all its pixel
and history controls pass. The candidate passes **18/18**. Both test
processes exit with the corresponding nonzero/zero code.

| First cold draw, one observation | Original T-136 | T-137 candidate |
| --- | ---: | ---: |
| CPU `_draw()` callback | 99.335 ms | 11.158 ms |
| Textures composited | 34 | 3 |
| Deferred cold tiles | 0 | 31 |
| Budgeted | No | Yes |
| Draw callbacks until settlement (test-driven) | 2 | 10 |

**This is scheduling, not total work reduction:** the candidate spreads
compositing over later frames, and it may take *longer* to display the final
cold image. The test disables the synthetic gesture drain and manually
requests subsequent draws; in the application `_process()` queues a redraw
while cold work remains. Numbers are single software-run samples; no p50/p95
or real pointer-to-visible/hardware claim follows. `draw_cpu_us` measures
CPU submission, not completed GPU scanout.

The same native test also checks that the preview-only blue pixel appears
after settlement while `DrawingDocument.revision` and the canonical source
remain unchanged, a committed red pixel stays visible, cancellation removes
only the draft, and a fresh blue commit survives exact Undo/Redo. The retained
GPU tile cache stays below 144 entries. The 15-check model tests signed
focal order, valid preview owner/generation reuse, stale cache invalidation,
unknown committed occupancy, invalid/noncanonical keys, missing preview index,
and over-capacity fallback.

## Verification commands

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t137_preview_cold_population_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t137_preview_cold_population_native.gd
python3 tools/check_godot_model_log.py /path/to/model.log --marker T137_COLD_PASSED
python3 tools/check_godot_model_log.py /path/to/native.log --marker T137_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t137_preview_cold_population.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

- **Focused:** T-137 headless **15/15**, native X11 **18/18**; strict model
  and native logs; new Python source/CI contracts **3/3**.
- **Adjacent headless:** T-102 cold, T-103 focal retention, T-135 and T-136
  sparse enumeration, T-086 viewport cache/focus/preview-index/cold/pixel/
  visible-plan suites passed with zero exits.
- **Adjacent native:** T-135 **23/23**, T-136 **26/26**, T-102 cold dense
  **110/110**, T-086 original framebuffer **153/153** (after normal fresh
  Godot font-resource import). Initial T-086 test before import failed two
  font-loader assertions, unrelated to renderer scheduling, and is not
  reported green.
- **Independent package:** Native-absent standalone Drawing consumer builds,
  imports and passes its smoke (42/42); no optional native library required.
- **CI:** The 15-check model and three Python contracts live inside the
  existing T-086 required step, with the 18-check native witness in its
  existing on-demand workflow. Exactly 46 unique required check IDs remain.

All post-exit Godot RID/resource-leak warnings stay visible in the raw logs;
strict validation rejects script errors or any unrecognized runtime errors.
No physical GPU/device test, hosted all-green CI result, or owner approval is
inferred. Parent T-086 and manually gated T-095 remain **In Progress**.

[Log checksums and source hashes](T-137-2026-11-15-preview-cold-results.json) ·
[Retained raw logs](t137-preview-cold-logs/).
