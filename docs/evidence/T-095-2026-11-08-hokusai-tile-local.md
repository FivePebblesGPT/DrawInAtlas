# T-095 follow-up — tile-local deferred Hokusai staging (2026-11-08)

**Scope:** one engineering checkpoint for `T-095` on the existing
`sprint/2026-11-07` branch / PR #16. `manual_review: true` and `In Progress`
remain unchanged; this is **not** owner-device acceptance or a shipped default
brush. Prior checkpoint: [tile-batch preflight](T-095-2026-11-08-hokusai.md).

## Change and correctness model

`DrawingEditSession.paint_path_hokusai` now groups *prevalidated* native
RGBA8 triples by signed 64-bit storage-tile key, with integer local pixel
offsets. Accepted source tiles are fully resolved before mutation. Repeated
native pigment batches write detached `_preview_tiles` offsets directly and
keep a running changed-pixel count. They do **not** allocate or hash global
`"x,y"` pixel keys for each quantized dab. Canonical `_before`/`_after` keys
are reconstructed once at commit, against the immutable source tile, retaining
exact straight-alpha bytes and the existing `DrawingDocument._publish_edit`
transaction/Undo contract. The renderer reads the same preview offsets as
before. Equal-pixel repeats do not invalidate display textures unnecessarily.

The unusual case of mixing Hokusai with a different edit API materializes
native changes **before** the other operation takes its rollback snapshot.
Subsequent Hokusai deltas use the original canonical-keyed path for that
mixed gesture. Selection holes, hidden RGB, sparse negative coordinates,
64-bit anchor offsets, erasing/cancellation, and original-source compositing
are unchanged. Failed coordinate/source preflight does not mutate a prior
batch; a later lazy source-read failure in a mixed region request restores
all previous native deltas. This is still a Godot-main-thread implementation;
no threading or new document format was introduced.

## Paired Xvfb CPU evidence

Toolchain: checked supplied archive SHA-256
`0886d42efe896cd5ba0dc9c82b684a6b68efa9d3537b833dc0efedd00b0b70b1`;
Godot 4.8 beta2 `cafc17a19`, Hokusai 0.3.0, godot-rust 0.5.5, offline Rust
1.99.1, 1280×900×24 Xvfb/Mesa OpenGL compatibility renderer.
`drawing/tests/brush_latency_native.gd` synthesizes real Godot mouse
press/motion/release input: **5 strokes, 120 motion samples per stroke,
60px Brush, 786% zoom, 512×512 image**, with preview/framebuffer readback.
For the control, only `addons/drawing/edit_session.gd` was swapped back to the
preceding two-commit checkpoint; both used the same built native library.
After staging/import the optimized file was restored. The run sequence was
**optimized → previous → optimized confirmation → Legacy**, with fresh Xvfb
processes. See [raw per-stroke rows](T-095-2026-11-08-hokusai-tile-local.csv).

Nearest-rank p95 from five observations per run; **milliseconds**, not
physical input-to-photon latency:

| Hokusai 60px | Previous batch-staging | Tile-local first | Tile-local confirmation | Legacy reference¹ |
| --- | ---: | ---: | ---: | ---: |
| Stage CPU p50 | 574.750 | 357.379 | 339.012 | 163.472 |
| Stage CPU p95 | **580.815** | **366.512** | **369.368** | **168.023** |
| Release→commit p95 | 68.824 | 103.938 | 79.739 | 62.946 |
| Per-stroke commit CPU p95 | 68.765 | 103.867 | 79.673 | 62.470 |
| Sum of stage+commit p95² | 648.649 | 446.225 | 449.041 | 230.493 |
| Compositor CPU sum p95 | 710.680 | 663.229 | 670.793 | 326.658 |
| Texture-upload CPU sum p95 | 10.512 | 11.398 | 9.605 | 6.237 |
| Maximum queued samples | 4 | 4 | 4 | 19 |

¹ Legacy uses a distinct hard-circle brush algorithm, not an equivalent
Hokusai pigment model. Its input path is the same but output footprints differ.
² A diagnostic sum of separate cumulative CPU counters per stroke, **not**
wall-clock total time, and not additive with framebuffer compositor times.

The tile-local p95 **stage CPU fell ~36%** relative to this same-machine
previous implementation (580.815→369.368ms), and p95 aggregate stage+commit
CPU fell ~31%. The improvement moves some work to commit: release→commit p95
rose in both optimized runs. At the second optimized checkpoint, Hokusai
staging was still **~2.2× slower than Legacy** and compositor CPU was roughly
twice Legacy. The previous owner rejection remains valid. The separate
2026-11-08 measured 691.732ms p95 was in a different process/environment
capture and is **not** treated as the paired denominator for this change.

## Regressions and limits

- Expanded `drawing/tests/hokusai_bulk_delta_smoke.gd`: **101/101 checks**,
  both native present and missing, including byte-exact old per-pixel oracle,
  repeated no-op deltas and preview generations, 64-bit signed anchors,
  transparent pigment and source opacity, masking holes, mixed Hokusai →
  `apply_region` → Hokusai, rollback after an injected later source-chunk
  failure, one transaction and Undo/Redo.
- `native_brush_integration.gd`: **30/30**, real hard/soft/ink/airbrush `.myb`
  rendering; `native_brush_fallback.gd`: **6/6** with and without extension.
- `stroke_navigation_native.gd`: **48/48**, pointer release/backlog → zoom,
  middle-pan, toolbar Pan and camera changes; no silent cancellation.
- `brush_coverage_smoke.gd`: **32/32** hard-brush source oracle.
- `live_stroke_native.gd`: **125/125**, `pixel_boundary_native.gd`:
  **17/17** existing signed-edge regression (known Godot exit RID warnings).
- `viewport_cache_native.gd`: **153/153** after a **fresh** standalone
  `--editor --import`; an earlier run was invalid because the staging copy
  had stale font imports. Do not suppress the initial failed attempt in logs.
- `python3 tools/validate_ticket_store.py`: **96 tickets valid**, review
  dependency gates intact. The on-demand T-095 workflow already runs the
  independent delta and hard-brush oracles with the shared fail-closed
  `check_godot_model_log.py` policy.

**Still required:** hardware input-to-photon/pointer latency at 60px/786%,
owner UX signoff, constrained per-frame compositor/texture work, sustained
large strokes/pressure device tests, Windows and native export packaging,
and hosted CI results. No `manual_review_approved` has been set; leave
T-095 `In Progress`, T-096 in independent `Manual Review`, and do not merge PR
#16 based on these software results.
