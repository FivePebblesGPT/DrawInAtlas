# Drawing / Atlas verification and reviewer handoff (T-077)

**State at `a1d6a38`, 2026-11-02:** this is an **executable test plan**, not an assertion that every platform or acceptance gate has passed. The canonical package is `addons/drawing/`; Atlas uses root `project.godot`, while standalone Drawing uses `drawing/project.godot` and a staged copy of the same package. See [the owner-approved decisions](DECISIONS_DRAWING_ATLAS_2026-11-01.md), [contract](ADR_DRAWING_DOCUMENT_CONTRACT.md), [ticket workflow](TICKET_WORKFLOW.md) and [Kanban](Index.md). Use the **checked-out revision** when reporting results, not historical check counts.

## Preconditions and evidence rules

- Work from a clean checkout of the **intended** `aidev` commit with Git LFS populated (`git lfs pull`; `git lfs fsck`). If the checkout contains unrelated changes, record them and test an isolated clone/worktree rather than discarding them. CI success cannot be assumed without querying its actual run.
- Godot **4.8 beta 2** and matching desktop export templates are the repository's tested baseline. Record `godot --version`, OS, CPU, graphics driver/GPU, terminal output, commit SHA, editor vs release build, and whether the test had a native display. Do not call an Xvfb/Mesa result a Windows or hardware-GPU result.
- A process exit code alone is insufficient: require its suite's `*_PASSED` marker, **zero failures**, and no `SCRIPT ERROR:` or `ERROR:` lines (unless an explicit, reviewed fault-injection test expects them). Run known fragile suites in a fresh process. Do not silently discount failures; reproduce on a clean baseline and document the difference.
- Save exact command lines, logs and generated JSON/CSV as external evidence. Never place private campaign data, unpublished Object Assets or user fonts in reviewer bundles. Standalone/Atlas testing may use deterministic synthetic fixtures.

## Linux: reproducible command set

Run from the repository root. `xvfb-run` provides an offscreen *real* X11/GL context; `--headless` does **not** validate pointer events, GPU uploads, screenshots or editor focus.

```bash
set -euo pipefail
export GODOT="${GODOT:-godot}"
"$GODOT" --version
python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
"$GODOT" --headless --editor --path . --import --quit
"$GODOT" --headless --path . --script res://tests/drawing_composition_smoke.gd
"$GODOT" --headless --path . --script res://tests/drawing_world_mapping_smoke.gd
"$GODOT" --headless --path . --script res://tests/drawing_history_smoke.gd
"$GODOT" --headless --path . --script res://tests/drawing_text_smoke.gd
"$GODOT" --headless --path . --script res://tests/object_assets_smoke.gd
"$GODOT" --headless --path . --script res://tests/object_editor_smoke.gd
"$GODOT" --headless --path . --script res://tests/campaign_bundle_smoke.gd
"$GODOT" --headless --path . --script res://tests/campaign_bundle_editor_smoke.gd
python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v
python3 tools/build_drawing_app.py --output /tmp/drawing-t077-clean
"$GODOT" --headless --editor --path /tmp/drawing-t077-clean --import --quit
"$GODOT" --headless --path /tmp/drawing-t077-clean --script res://tests/standalone_smoke.gd
python3 tools/build_drawing_contract_consumer.py --fixture drawing_package_consumer --output /tmp/drawing-t077-consumer
"$GODOT" --headless --editor --path /tmp/drawing-t077-consumer --import --quit
"$GODOT" --headless --path /tmp/drawing-t077-consumer
# Require the DRAWING_THIRD_CONSUMER_PASSED marker and zero failures.
```

The `/tmp/drawing-t077-*` outputs must **not exist** before `--output`; remove them between repeats, or choose fresh output paths. The third consumer runs its own `main.gd`, reports `DRAWING_THIRD_CONSUMER_PASSED` and quits; never infer success from an import alone. Require `DRAWING_STANDALONE_PASSED`, `T055_COMPOSITION_PASSED`, `T061_WORLD_MAPPING_PASSED`, `ATLAS_BUNDLE_PASSED` and `DRAWING_THIRD_CONSUMER_PASSED` from their respective commands. For source-side Drawing text/UI tests, use `python3 tools/build_drawing_app.py --in-place`, **then reimport staged fonts**, and run `drawing/tests/text_editor_smoke.gd` and `drawing/tests/object_editor_ui_smoke.gd` under `--path drawing`. The build's `drawing/addons/` is generated; do not edit it.

```bash
xvfb-run -a "$GODOT" --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_composition_visual.gd
xvfb-run -a "$GODOT" --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_world_visual.gd
xvfb-run -a "$GODOT" --display-driver x11 --audio-driver Dummy \
  --rendering-method gl_compatibility --path . \
  --script res://tests/drawing_latency_visual.gd
```

For **export**, follow [Drawing's documented build/export procedure](../drawing/README.md) and verify both generated executable and `.pck`, then run `drawing/tests/packaged_fonts_smoke.gd` **against the exported PCK**, not the editor import directory. Use fresh output directories. A successful Linux export is not evidence of a tested Windows binary.

## Windows: separate desktop acceptance path

Use the **same commit**, licensed assets and exact serialized fixtures as Linux, with Godot 4.8 beta 2 Windows **console** executable and matching export templates. Substitute the actual path for the placeholder; these instructions are a future test procedure, **not a claim this CI ran on Windows**.

```powershell
$Godot = 'C:\path\to\Godot_v4.8-beta2_win64_console.exe'
& $Godot --version
py -3 tools/validate_ticket_store.py
py -3 tests/check_explicit_types.py
& $Godot --headless --editor --path . --import --quit
& $Godot --headless --path . --script res://tests/drawing_composition_smoke.gd
& $Godot --headless --path . --script res://tests/drawing_world_mapping_smoke.gd
& $Godot --headless --path . --script res://tests/campaign_bundle_smoke.gd
py -3 tools/build_drawing_app.py --output "$env:TEMP\drawing-t077-clean"
& $Godot --headless --editor --path "$env:TEMP\drawing-t077-clean" --import --quit
& $Godot --headless --path "$env:TEMP\drawing-t077-clean" --script res://tests/standalone_smoke.gd
```

Use a **fresh** `%TEMP%` staging path for each run. For every command inspect `$LASTEXITCODE` and the suite pass/failure marker; stop on failures. Repeat critical UI paths in a **real Windows window** (not `--headless`): paint, erase, pan, high-zoom grid/entrance overlays, switch D0 ↔ blank D1, Object Editor Save/Save As and undo/redo, cancel/out-of-window release, closing dirty documents, and Windows Drawing/Atlas exports. Record measured GPU driver, RAM and display results separately from Mesa software GL. Browser/Web is archived, not a required native acceptance target.

## Required acceptance matrix and failure injections

| Feature or boundary | Reproducible witness | What must be asserted | Evidence still needed |
| --- | --- | --- | --- |
| Package isolation | `build_drawing_app.py` into **empty external directory**, `standalone_smoke.gd`; `build_drawing_contract_consumer.py` | Standalone and third consumer import without Atlas sources, one canonical Drawing engine, no duplicated editable package | Windows clean consumer and full Windows release execution |
| Sparse signed world & detail LOD | `drawing_world_mapping_smoke.gd`, `drawing_world_visual.gd` | Signed negative seams and far coordinates, per-detail density, D0/D1 alignment, **blank** missing D1 (no inherited D0 raster), grid/entrance overlays still active | Large real-map memory/LOD hardware capture |
| Atlas input & preview | `drawing_composition_smoke.gd`, `drawing_composition_visual.gd` | Brush/eraser affect only correct detail; edit target frozen across navigation; same-entrance double-click vs painting; preview read-only; Object instances compose at transforms | Hands-on UX judgement under T-056 |
| Exact source integrity | `standalone_smoke.gd`, `drawing_text_smoke.gd`, `campaign_bundle_smoke.gd` | Byte-for-byte **straight RGBA8**, including hidden RGB under alpha=0, signed tile IDs, stable layer/document IDs, edit undo/redo, text remains editable until explicit rasterize | Windows exported-file cross-load |
| Multi-file save & relocation | `campaign_bundle_smoke.gd`, `campaign_bundle_editor_smoke.gd` | A new generation root references hashed `Drawings/`, `Objects/` and legal fonts by **relative** IDs; copy complete campaign tree to a different location and reopen unchanged | Real disk power-loss durability beyond process fault injection |
| Save failure/corruption & recovery | `campaign_bundle_smoke.gd` fault-injection cases | Fail **before** root publication → previous generation opens; corrupt/missing latest generation → prior complete generation recovers or error is explicit; stale writer blocked; symlink/path escapes rejected | Cross-filesystem and cold-disk `fsync`/power-loss campaign |
| Object draft and identity | `object_assets_smoke.gd`, `object_editor_smoke.gd` | Draft private until Save; shared source updates links on publication; Save As rebinds only origin instance; undo retains saved new asset; NULL/missing reference is bounded | Final asset browser UX T-065, nested dependencies T-064 |
| History context | `drawing_history_smoke.gd` and `drawing_history_editor_smoke.gd` | Single chronological Atlas gesture, restores map/floor/detail/tool/selection; zoom unchanged and camera pans only to reveal; stale revisions reject replay | Owner-facing navigation judgment T-056 |
| Performance dimensions | T-067/T-068 raw JSON/CSV, `drawing_raster_backend_benchmark.gd`, `drawing_latency_visual.gd` | Separate compressed save stride, edit/dirty region, GPU upload tile; record median/**p95**, peak RSS, exact pixel parity; label CPU-only vs submitted-frame proxy | Real Windows/Linux hardware, GDExtension + Blend2D/Skia benchmarks T-068; map GPU stress T-057 |

The T-066 suite performs **controlled programmatic** missing-generation, corrupt-index, interrupted-save, portable-copy and stale-writer tests. For manual rehearsal, use disposable **synthetic** campaigns: save generations A then B, copy the *entire* campaign tree, delete/corrupt only B's generation index in the copy, open and verify A or a clear failure, then verify the untouched source still opens B. Do **not** damage real user campaigns. Copying only `.scn` or only `Drawings/` is intentionally **not** a supported complete campaign copy. A present but corrupt blob must not be silently replaced with an unrelated image.

## Benchmarks: three independent questions

1. [**T-067** storage/packing](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md) tested 256/512/1024/2048 storage strides and prototype individual/document/shared layouts. The 512px **future default** and immutable segmented packs are recommendations only; the working T-066 writer still uses per-blob `.zst`. Compressed bytes, file count, save latency, memory and cache churn are **not** FPS or input-to-display times.
2. [**T-068** CPU edit/compositing](DRAWING_CPU_RASTER_BENCHMARK.md) measured the original versus optimized GDScript compositor, an **unintegrated scalar C++** bounded batch/delta kernel and X11 synthetic-input→`frame_post_draw` as a submitted-frame proxy. Blend2D/Skia and GDExtension runtime overhead are **unmeasured**; no new backend is shipped. Source RGBA8/hidden RGB and one-hit brush semantics remain gates.
3. [**T-057** native GPU/LOD](Tickets/T-057.md) remains **Ready**: derived display LOD, GPU draw/upload scheduling and peak VRAM on large maps must be measured independently. Software GL `ImageTexture.update()` uploads the **entire** texture; a small dirty edit region is not automatically a partial GPU transfer.

Do not combine times from different machines/runs to claim a speedup. State sample count, cache conditions, renderer, timestamps, exact test revision and operations before discussing bottlenecks.

## Independent review versus autonomous engineering

**T-038 — code readability:** hand an unfamiliar reviewer a **separate code-only ZIP** containing tracked `.gd`, `.tscn` and native prototype `.cpp` sources, not this plan, `.agents`, README, other documentation, chat history, or Git metadata. Build it from a clean checkout:

```bash
python3 tools/build_t038_review_bundle.py --output /tmp/drawing-code-review.zip
python3 -m unittest discover -s tests -p 'test_t077_handoff.py' -v
```

Supply the SHA-256, source revision and scope **out of band**. Ask the reviewer, from code alone, to explain ownership, board/pixel/chunk units, detached versus shared state, commit/abort/undo boundaries and error paths; request `path:line`, concrete uncertainty, impact and a proposed minimal change. The implementer may resolve technical issues autonomously; the **independent reviewer has not been engaged by generating a ZIP**, and **only explicit owner acceptance** may close T-038. See [historical review notes](ManualReview_2026-10-30.md) and [readability guidance](CODE_READIBILITY.md).

**T-056 — owner UX acceptance:** deliver **two independently launchable applications**, an exact commit/build matrix, synthetic sample campaign, saved/reopened drawing and asset fixtures, native capture/screencast and a short hands-on script (create→paint→select→undo→save→reopen, switch detail, Save As object, preview, resolve missing files). Provide failures and differences across Windows/Linux, rather than pre-filling a signoff. T-056 requires explicit owner approval with `manual_review_approved: true` and `review_evidence:` recorded **after** the decision. T-059's separate final UX gate also remains open. Do not mark them Done based on automated tests, a generated reviewer archive or historical scope approval.

**Handoff checklist:** record commit SHA and archive checksum; machine/OS/Godot/renderer; exact source and exported artifacts; isolation proof; per-suite pass markers/failures; file copy/recovery evidence; performance source raw files with units; external comparator status; review findings/signoff **or pending owner actions**; open tickets (notably T-038, T-056, T-057, T-068). Keep these attached to the relevant tickets; do not rewrite historic reports as newly completed tests.
