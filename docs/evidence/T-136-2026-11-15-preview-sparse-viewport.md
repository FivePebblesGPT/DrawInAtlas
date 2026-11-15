# T-136 — complete preview/committed sparse display traversal

Date: 2026-11-15. Branch: `sprint/2026-11-14`.
Pinned engine: **Godot 4.8.beta3.official.c51ff06e8**, Linux x86-64,
Mesa llvmpipe software OpenGL in Xvfb. No physical display, stylus, real
GPU scanout or owner reference-hardware acceptance.

## Problem and exact negative control

T-135's committed sparse draw visits only occupied 128px display tiles, but
its preview guard forces a full visible row/column traversal whenever a
`DrawingEditSession` is detached. A 1% zoom, 512×384 Canvas displays **120,701
source-space display cells** while the witness has only two occupied cells,
one committed and one draft. The committed cache and the detached preview
index are already bounded and complete; the full scan is redundant.

A detached Git worktree at the immediate prior commit
`96a0b7ca9f7124805119333a755670aaa054f2f1` was staged with the **same
new native witness**, imported using the supplied beta3 engine, and run three
times. It fails **four of 26** assertions every time: indexed preview not
enabled, all 120,701 cells examined, updated preview not bounded, and
restored complete occupancy not indexed. Its real signed-color framebuffer,
cancel and history controls still pass; the test exits 1 as expected.
The old `_sparse_visible_draw_rows` signature also rejects the additional
preview arguments in the new model; it cannot supply the union behavior.

The candidate `DrawingCanvas._sparse_visible_draw_rows()` accepts a complete
preview-generation dictionary only when `_preview_index_for_draw()` returns
`indexed: true`. It merges the canonical committed occupancy keys with
preview-only keys, discards duplicates, validates exact canonical signed
coordinates and positive integer stamps, and preserves previous row/column
ordering. A failed/incomplete index, unknown source occupancy, cap overflow,
malformed keys or dense view returns to the **original complete scan**; normal
dense views short-circuit before copying a large occupancy dictionary.
Neither persistent source nor `ImageTexture` format, alpha blending,
cache budget (144 × 128² × RGBA8 = 9 MiB), cold scheduling, source epochs or
Undo transaction structure changes.

## Native framebuffer and sampled work

The native witness creates a committed signed red Brush dab and stages a
separate **uncommitted** blue Brush dab in an empty display tile using an
actual `DrawingEditSession`. It attaches that detached session to the Canvas
for the renderer test while disabling synthetic pointer draining; it is **not
an OS pointer-latency or input-event benchmark**. It verifies the staged blue
is visible before document publication, signed red/blue survive zoom changes,
new preview generations cannot reuse stale rows, unknown occupancy uses the
conservative path, cancellation erases only blue preview, and a fresh commit,
Undo, Redo preserve exact framebuffer/source pixels. The retained cache remains
at or below 144 entries. The new model covers malformed/noncanonical keys,
zero-generation invalidation, duplicates, edge clipping and empty sources.

Every repeated native run records seven warm CPU durations from
`DrawingCanvas._draw()` at **1% programmatic zoom**. At 1% the baseline's
full preview scan uses 120,701 display cells; the candidate examines two.

| Seven-sample p50 CPU time | Trial 1 | Trial 2 | Trial 3 |
| --- | ---: | ---: | ---: |
| Original T-135 Canvas | 109.163 ms | 107.244 ms | 108.804 ms |
| T-136 union candidate | 0.076 ms | 0.084 ms | 0.084 ms |

Original p95 across trials: **116.993, 116.380, 115.138 ms**. Candidate p95:
**0.198, 0.102, 0.109 ms**. Each test uses the same Canvas size, image,
zoom, session, sampling schedule and pinned engine. CPU scheduler and software
renderer jitter remain uncontrolled. These are *per-draw CPU callback* times,
not full wall frames, typical 25/50/100% zoom, actual pointer-to-preview
latency, memory reduction or physical input-to-photon timing. The test's
fallback check intentionally runs at 25% zoom to avoid spending time in the
known expensive but safe all-cell scan.

[JSON measurements, source SHA-256 and each complete log checksum](T-136-2026-11-15-preview-sparse-results.json). Raw positive and negative logs:
[`t136-preview-sparse-logs/`](t136-preview-sparse-logs/).

## Reproduction and verification commands

```sh
python3 tools/build_drawing_app.py --in-place
# A fresh source stage may need Godot's resource/font import first.
godot --headless --editor --path drawing --import --quit
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t136_preview_sparse_union_model.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t136_preview_sparse_union_native.gd
python3 tools/check_godot_model_log.py /path/to/model.log --marker T136_UNION_PASSED
python3 tools/check_godot_model_log.py /path/to/native.log --marker T136_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t136_preview_sparse_union.py' -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

- **Focused:** T-136 headless **18/18**, native **26/26** (all three
  measured candidate runs plus later independent rerun), strict log checks,
  Python source/CI contracts **3/3**.
- **Adjacent viewport/rendering:** T-135 headless **16/16**, native **23/23**;
  original T-086 native framebuffer **153/153**; T-102 cold, T-103 focal,
  T-086 viewport cache/focus/preview-index, cold/sparse/shared/visible-plan
  renderer model suites passed with zero exit and strict log checks.
  T-098's legacy preview-display test separately reports **27/27**, using its
  original bare success marker rather than the newer counted marker format.
- **Package:** a freshly built/imported independent `--without-native`
  Drawing consumer passes its standalone **42/42** smoke and strict log
  check; Godot's four known post-exit RID/texture leak diagnostics are kept
  visible and classified, not deleted.
- **CI scope:** T-136's 18-check model and Python contracts are inside the
  existing required T-086 workflow step, with the 26-check native witness in
  its existing on-demand workflow. The **46 required check IDs** are unchanged.
  A fresh hosted run has **not** been observed.

**Closure boundary:** T-136 is Done for this isolated, byte-exact and
measurable synthetic sparse-preview traversal. T-086 remains In Progress for
normal-zoom, dense/cold and owner hardware behavior; T-095 still requires
explicit owner approval. No other manual gate changes status.
