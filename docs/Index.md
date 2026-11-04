# Ticket Kanban Index

**As of 2026-11-04 · `aidev`**. This index includes the historical work and the Draw/Atlas separation documentation tasks introduced since [a9a3bc2](https://github.com/FivePebblesGPT/DrawInAtlas/commit/a9a3bc23d4c03b577d00526e1993f93cac1b121c).

**Canonical state:** ticket frontmatter (`status`, `manual_review`, `depends_on`). See [ticket workflow and closure gates](TICKET_WORKFLOW.md). The [fast desktop GDScript CI policy](CI_TESTING.md) runs required Drawing/core checks before reporting failures; legacy Atlas/native/Web suites are retained but non-gating; this changes verification only, not ticket status or manual approvals. **Done** on a pre-split ticket means its original acceptance was completed, *not* that the new Drawing application/Atlas integration exists. Web ticket T-044 is archived ([full historical ticket](Archive/Web/T-044.md)).

## Kanban summary

**T-068 native sparse-brush cancellation/conflict gate (2026-11-04; In Progress):**
A **separate opt-in Godot↔C++ sparse brush publication witness** now checks
actual C++ changed-pixel records against a Godot-authored paint oracle before
publication, then exercises cancellation, stale revisions **before** and
**after** detached staging, and forged source-before pixels at an unchanged
revision. Two isolated Godot 4.8 beta 2 runs pass **37/37 assertions each**;
no rejected candidate modifies published pixels or history, and the competing
successful edit remains undoable. An independent Python RGBA8 reconstruction
and tamper validator check all four recorded cases. This is not a production
backend, parallel thread stress, hardware timing, or manual acceptance.
[T-068](Tickets/T-068.md) ·
[two-run evidence](benchmarks/T068_2026-11-04_scalar_atomicity.json).

**T-068 512/1024/2048 native sparse brush document publication (2026-11-04; In Progress):**
An opt-in **separate large-tile Godot↔C++ benchmark** now compares canonical
`DrawingEditSession.paint_path()` + commit against native sparse generation,
checked decode, detached staging and the same revision-checked commit.
One 4px horizontal stroke per 512²/1024²/2048² storage tile is independently
reconstructed to exact source-over RGBA8, including an untouched alpha-zero
hidden-RGB pixel. Two complete runs pass **146/146 correctness checks each**;
each case retains four alternating-order paired CPU timings, exact published
pixels, Undo/Redo, wire sizes, source digests and capacity rejection. Native
path medians are **slower at 1024² and 2048²** in both runs. These are
headless CPU diagnostics, **not a native-backend performance win**, physical
input-to-visible latency, VRAM or release acceptance. No production extension
or ticket status was changed. [T-068](Tickets/T-068.md) ·
[two-run raw evidence](benchmarks/T068_2026-11-04_scalar_large_publication.json).

**T-068 native four-corner Atlas scope through Godot GDExtension (2026-11-04; In Progress):**
The temporary, explicit-load Godot 4.8 beta 2 extension now exposes a checked
C++17 **native convex polygon/whole-pixel selection-mask builder**, then feeds
its returned 0/1 mask into the existing scalar sparse brush. It matches all
**15 Godot-authored 64² `AtlasFill._allows_pixel()` masks byte-for-byte** in
each of **two independent 55-check runs**, including exact edge/vertex ties,
rotation, shear, mirroring, nonuniform density, disabled/empty selections.
Every sparse brush output is validated against the selected pixel set and
independently reconstructed canonical RGBA8, preserving transparent hidden
RGB. Invalid transforms, polygon wire data, dimensions and scope flags reject
without modifying the source. This remains a **separate Atlas-scope research
screen**: the regular `DrawingSelection` path still constructs its mask in
Godot, and no production application or release loads this extension.
[T-068](Tickets/T-068.md) ·
[two-run evidence](benchmarks/T068_2026-11-04_quad_gdextension.json).

**T-068 transformed-view native sparse brush publication (2026-11-04; In Progress):**
The explicit-load, temporary Godot 4.8b2 GDExtension now verifies six
**32²/64² transformed hard-brush and mask cases** against independent
`DrawingEditSession.paint_path()` output: identity rectangle, 90° rotation
with inverted selection, sheared sparse-mask erase, mirrored crossing path,
nonuniform inverted sparse erase and zoom/pan dab. Two complete bridge runs
passed **110/110 new assertions each** with identical canonical SHA-256
outputs and sparse counts. Native output is decoded and checked against all
Godot RGBA8 bytes *before* revision-checked staging; undo/redo and capacity
rejection pass. The client computes the binary `DrawingSelection` mask and
inverts view transforms; this **does not test a native four-corner Atlas
polygon clipper** or provide physical latency or release proof. Runtime
backend and ticket status remain unchanged. [T-068](Tickets/T-068.md) ·
[two-run native evidence](benchmarks/T068_2026-11-04_scalar_transform.json).


**T-068 counterbalanced Godot/native brush publication evidence (2026-11-04; In Progress):**
The temporary opt-in Godot 4.8b2 GDExtension benchmark now alternates
**Godot-first and native-first** execution order on *fresh identical
DrawingDocument sources*. Two warmups and six paired timed trials (three per
order) cover six 32²/128²/256² short/crossing 4px strokes in each of two
independent runs. Both pass **536 correctness assertions**; exact raw
per-trial stage durations, order, phase totals, and recomputed distributions
are pinned and reject tampered evidence. An untimed Godot oracle is
precomputed before the timed pairs; sparse bytes are checked against it before
native staging. The 256² crossing-stroke run medians
were **18.955–21.991 ms canonical vs 13.371–13.631 ms native path**. This
reduces the previous fixed-order bias but does not prove a speedup: the
results remain headless CPU-only, small-sample, prepacked-geometry diagnostics
excluding rendering, GPU and physical input-to-visible latency. No production
backend, manual gate or other ticket changed. [T-068](Tickets/T-068.md) ·
[paired evidence](benchmarks/T068_2026-11-04_scalar_publication.json).


**T-068 optional scalar brush through real Godot GDExtension (2026-11-04; In Progress):**
The detached C++17 hard-brush sparse ABI now executes through the existing
**temporary, explicit-load Godot 4.8 beta 2 GDExtension** using an 8-argument,
capacity-bounded PackedByteArray/float64 path interface. Each of two runs
passed **31 scalar integration checks**, comparing its 63 changed records
(760 bytes instead of a 1,024-byte tile) byte-for-byte with an independent
`DrawingEditSession.paint_path()` on a hidden-RGB source before one
revision-checked document commit. Undo/redo, inverted-size and malformed
calls, sparse mask, zero-alpha no-op and erase are covered. Existing bridge,
revision, document, batch, sparse and marshaling suites also passed in both
runs. This is **not enabled in either app**; the test recomputes canonical
Godot output before publication and supplies pretransformed local geometry.
No real input-to-present, Windows/physical GPU, memory, or portable release
claim is made. [T-068](Tickets/T-068.md) ·
[isolated two-run evidence](benchmarks/T068_2026-11-04_scalar_gdextension.json).

**T-068 bounded scalar sparse hard-brush payload (2026-11-04; In Progress):**
A detached C++17 hard-brush kernel now emits only changed canonical RGBA8
pixels as ordered, checked 12-byte before/after records plus a 4-byte count,
using the existing isolated bridge wire format. Across two independent passes
all **56/56 small/large Godot-oracle-derived comparisons** reconstruct exact
final RGBA8; no-op paint emits four bytes. A 2048² 4px stroke produces 5,524
wire bytes versus 16 MiB full-tile output, **not a measured marshaling or GPU
speedup**. Bounded capacity and malformed/aliased buffers fail atomically.
The prototype is not linked into Godot, and hardware/release gates remain open.
[T-068](Tickets/T-068.md),
[two-run sparse evidence](benchmarks/T068_2026-11-04_scalar_deltas.json).

**T-068 scalar native hard-brush canonical RGBA8 checkpoint (2026-11-04; In Progress):**
The detached C++17 hard-brush comparator now returns both the full 0/255
gesture coverage bitmap and detached **straight-RGBA8 pixels**. Two passes
over 28 pinned Godot geometry cases show **56/56 exact coverage and RGBA8
comparisons**, including source-over, erasure, transparent hidden RGB,
selection masks, crossing and 512/1024/2048-scale strokes. The 16 small cases
match **actual Godot output hashes**; the 12 large Godot oracles supply
coverage only, with compositing independently checked on the native scaling
benchmark's patterned source. C++ rejects buffer aliases and malformed input
atomically; no Godot GDExtension, document publication, texture upload,
hardware-performance or release acceptance is claimed. [T-068](Tickets/T-068.md),
[two-run compositing evidence](benchmarks/T068_2026-11-04_scalar_rgba8.json).

**T-068 dependency-free C++ hard-brush geometry parity (2026-11-04; In Progress):**
A detached scalar C++17 pixel-center / swept-segment comparator now returns
exact binary once-per-gesture coverage with checked input buffers and local
selection masks. Compared against the real Godot 4.8b2 brush oracles, two
independent runs produce **56/56 identical masks** across sixteen 32²
brush/selection/transform cases and twelve 512²/1024²/2048² workloads.
This closes the *tested scalar geometry screen*, not the application path:
canonical small-case RGBA8 is independently reconstructed, while large cases
compare coverage on empty-source gestures. No Godot GDExtension integration,
publication/texture timing, Windows/GPU memory/p95 or portable binary proof
is claimed. [T-068](Tickets/T-068.md),
[two-run scalar evidence](benchmarks/T068_2026-11-04_scalar_hard_brush.json).


**T-068 inclusive exact polygon-edge scope checkpoint (2026-11-04; In Progress):**
The research-only Blend2D C++ four-corner mask now accepts points exactly on
convex boundary segments, consistent with Godot's boundary-inclusive polygon
predicate. Seven additional Godot-authored 64² fixtures (axis-aligned edge,
reversed winding, rotation, shear, nonuniform density, diamond and one-pixel
strip) extend the existing eight to **15 cases**. Two independent native runs
show **30/30 byte-exact masks** with zero coverage differences; the thin
boundary-aligned strip accepts exactly 64 eligible pixels. This resolves the
previous demonstrated aligned-edge mismatch for pinned cases only; floating
near-edge tolerance and broader transforms remain unproven. No runtime backend
was adopted, and physical GPU/release gates remain open.
[T-068](Tickets/T-068.md), [two-run scope evidence](benchmarks/T068_2026-11-04_blend2d_quad.json).

**T-068 native transformed four-corner scope checkpoint (2026-11-04; In Progress):**
The detached Blend2D C++ brush comparison now computes a fail-closed binary
selection mask from **all four transformed pixel corners**, with an independent
Godot `AtlasFill._allows_pixel` oracle. Two runs × eight 64² convex scope cases
(identity, rotate, shear, mirror, nonuniform density, diamond, disabled/empty)
produce **16 exact mask matches**; native composition preserves hidden RGBA8.
Fixtures intentionally avoid exact polygon boundary ties (an aligned probe
differed at 43 pixels). Neither Blend2D hard-brush geometry, Godot publication,
physical GPU/frame timing nor desktop release validation is established.
[T-068](Tickets/T-068.md), [two-run quad evidence](benchmarks/T068_2026-11-04_blend2d_quad.json).


**T-068 large-tile Godot-vs-native brush geometry checkpoint (2026-11-04; In Progress):**
A Godot 4.8b2 `DrawingEditSession` oracle at signed anchors beyond 2^53
now covers all **12 full-size 512²/1024²/2048²** Blend2D scaling workloads,
with zoom, 90° rotation, shear, masks, erasure and transparent no-op. Comparing
its independently compressed coverage against both verified native runs yields
**24 comparisons: 18 coverage non-parity and 12 canonical final-pixel
non-parity cases** at 50% A8. All six 4px-stroke comparisons match; 256px
dabs each miss 36 covered pixels, and the no-op retains exact RGBA8 despite a
coverage difference. This reuses the old native timing runs, **not** matched
Godot timing or transformed four-corner selection clipping. T-068 remains open
for those and hardware/release gates. [T-068](Tickets/T-068.md),
[comparison evidence](benchmarks/T068_2026-11-04_blend2d_large_parity.json).


**T-068 native Blend2D 512/1024/2048 scaling checkpoint (2026-11-04; In Progress):**
The pinned detached C++ A8 brush shim now accepts bounded **512², 1024² and
2048²** straight-RGBA8 tiles (including allocation and timing-pointer alias
failure guards). Four fixed 128/256-local-region gestures per size cover 4px
strokes, 256px round dabs, self-crossing sparse-mask erase and an alpha-zero
no-op. Two runs × three trials produce **24 independently reconstructed
full-output comparisons** and 72 native calls. The 2048² full output is
**16 MiB** even with only 460 changed pixels; the same hypothetical four
128² display tiles would total **256 KiB** of full updates, *not measured
Godot uploads*. Native call timings rise materially with whole-tile size;
no Godot large-brush geometry parity or end-to-end speedup is claimed.
[T-068](Tickets/T-068.md),
[two-run evidence](benchmarks/T068_2026-11-04_blend2d_scale.json).

**T-068 native Blend2D hard-brush and selection comparison (2026-11-04; In Progress):**
The pinned 0.21.2 C++ A8 path rasterizer is now screened against **16 actual
Godot-generated hard-brush fixtures** per threshold, including far signed
anchors, view-to-local transforms, inverted/sparse selections, once-per-gesture
coverage, erasing and transparent hidden RGB. Blend2D's coverage is thresholded
and selected **inside the detached native shim**, then composited once with
canonical straight-RGBA8 math (no premultiplied round-trip). Two independent
seven-trial runs produce **64 comparisons**: at alpha threshold 128, **14/16**
cases have exact Godot coverage and RGBA8; inverted-selection variants each
miss one pixel. At threshold 1, all 16 cases overpaint and 15 alter final
RGBA8 (the alpha-zero no-op remains exact). Source, fixture and native outputs
are independently checked; runtime adoption, transformed four-corner clipping,
GDExtension publication, Windows/Linux physical frame/VRAM and release gates
remain open. [T-068](Tickets/T-068.md),
[raw two-run evidence](benchmarks/T068_2026-11-04_blend2d_brush.json).

**T-068 measured Godot↔C++ transfer boundary (2026-11-04; In Progress):**
The isolated pinned Godot 4.8b2 GDExtension now runs a fail-closed transfer
microbenchmark on 32²/128²/256² canonical tiles, with one-point, sparse and
dense overlapping masked source-over workloads. Both runs pass **731/731**
marshal checks, in addition to the existing native/document witnesses. Exact
RGBA8 and sparse-delta completeness are checked against independent full-buffer
reconstruction *before timing*. For 256²/one-change, the native sparse return
is **16 bytes versus 262,144 bytes** for whole-tile output, and its call median
was **1 µs versus 15–16 µs** across the two runs; at 256²/dense, sparse was
not consistently faster. These isolated, precovered calls are **not**
canonical document-publication or physical input-to-display measurements.
[T-068](Tickets/T-068.md), [two-run evidence](benchmarks/T068_2026-11-04_gdextension_marshal.json).

**T-068 transformed Skia brush/selection oracle (2026-11-04; In Progress):**
Five new fixtures send **non-identity view-space pointer samples** through
Godot's real `DrawingEditSession` (zoom/pan, 90° rotation, x-mirroring,
nonuniform scale, shear), retaining raster-local brush width and selection
masks at signed world anchors beyond 2^53. The independently validated
schema-2 oracle checks view-to-raster inversion, canonical exact RGBA8,
unchanged hidden RGB and baseline-transform equivalence. Two pinned Skia CPU
runs now cover **32 cases**: **eight** stencil coverage non-parity cases and
**six** final-pixel non-parity cases, including the previously known
one-pixel self-crossing gap under mirroring. This is a Python inversion
and postmask screen, **not** a native transform/clip or Godot marshaling
benchmark; no backend selection or hardware acceptance is claimed.
[T-068](Tickets/T-068.md), [two-run evidence](benchmarks/T068_2026-11-04_skia_brush.json).

**T-068 pinned Skia hard-brush/selection oracle (2026-11-04; In Progress):**
A deterministic 11-case fixture is generated by the **real Godot 4.8b2
`DrawingEditSession`** at signed anchors beyond 2^53, then independently
reconstructed as exact straight-RGBA8 in Python. The optional Skia 144.1
A8 hard-stroke and direct RGBA8 screens cover dabs, axis/diagonal strokes,
self-crossing and batched overlaps, rectangle/sparse/inverted selections,
erase with hidden RGB and zero-alpha no-op. Two seven-trial runs give **22
comparisons**: **six** coverage non-parity cases (the same one-pixel miss
on each self-crossing variant per run); **four** direct RGBA8 non-parity
cases, with no changes in the zero-alpha no-op. All selected hard-pixel
single/axis/diagonal/erase cases matched; selected pixels are **postmasked
in Python**, not native Skia selection clipping. The one-pixel gap persists
even if canonical blending is applied after Skia's stencil, so Skia is not
an exact drop-in hard-brush backend. [T-068](Tickets/T-068.md),
[reproducible evidence](benchmarks/T068_2026-11-04_skia_brush.json).

**T-068 pinned Skia 144.1 CPU pixel/shape screen (2026-11-04; In Progress):**
The owner-supplied, SHA-256-verified **CPython 3.13 Linux wheel** was used
outside the repository for an optional CPU-only comparison. Two nine-trial
runs checked **126 rectangle scenarios** across 32²/64²/128² surfaces,
three transfer modes and seven operations against the checked C++ kernel and
canonical straight-RGBA8 oracle. **60** scenarios disagreed; direct
unpremultiplied RGBA8 matched six fixed-case operations and retained all
untouched hidden RGB, but zero-alpha color replacement failed and seeded
random source-over revealed two changed-pixel rounding mismatches per run.
Antialiased and hard path footprints are only capability screens, **not**
canonical brush parity. Skia remains unadopted; T-068 still needs native C++
path/marshal, physical Windows/Linux timings and release gates.
[T-068](Tickets/T-068.md), [raw evidence](benchmarks/T068_2026-11-04_skia_cpu.json).

**T-068 pinned Blend2D CPU conversion/parity screen (2026-11-04; In Progress):**
User-supplied, SHA-256-verified Blend2D **0.21.2** with bundled AsmJit
was built locally as a *manual-only* CPU compositor. Two 9-trial runs across
32²/64²/128² rectangles, six operations and two conversion scopes checked
**72 scenarios** against the existing checked C++ kernel and independent
straight-RGBA8 oracle. Opaque painting and bounded-region clear were exact;
**42** scenarios showed format/rounding mismatch. Clipping conversion to the
edit rectangle preserves all outside hidden RGB, **not** exact translucent
source-over/replace pixels. Blend2D was **not adopted**; T-068 remains open
for Skia, real shapes, portable native/physical timings, and release gates.
[T-068](Tickets/T-068.md), [raw evidence](benchmarks/T068_2026-11-04_blend2d_cpu.json).

**T-068 optional Cairo CPU comparator (2026-11-04; In Progress):**
A standalone, runtime-versioned Cairo 1.18.4 experiment tests a *third-party
CPU rasterizer* against the checked scalar C++ kernel and independent canonical
straight-RGBA8 oracle. Two 9-trial runs cover 32²/64²/128² half-tile
rectangles, opaque and translucent source-over, replacement, transparent
no-op, and clearing (**36 verified scenarios**). Opaque operations reproduce
canonical pixels, but premultiplied ARGB32 conversion destroys hidden RGB
outside painted areas and most translucent cases disagree. It is **not**
Blend2D/Skia acceptance, nor a production fallback; it runs on demand and
fast CI checks only the Python contracts. [T-068](Tickets/T-068.md),
[raw evidence](benchmarks/T068_2026-11-04_cairo_cpu.json).

**T-068 complete native sparse-delta verification (2026-11-04; In Progress):**
The isolated GDExtension adapter now independently checks the **complete**
requested change set, not just the returned delta records. A forged zero-count
or partial response cannot silently discard requested pixels or partially
publish a multi-tile edit. The targeted witness passes 173 checks per run;
fast CI validates the runner and the native test remains on demand. O(N)
canonical verification adds CPU work and no speedup is claimed. T-068's
production/native and physical-hardware gates remain open. See
[T-068](Tickets/T-068.md) and the
[sparse evidence](benchmarks/T068_2026-11-04_sparse_completeness.json).


**T-068 experimental sparse-delta GDExtension publication (2026-11-04; In Progress):**
The opt-in checked C++ bridge can return a length-prefixed sequence of
(index, exact-before, exact-after) pixel records rather than an entire RGBA8
output tile. A separate adapter validates records against the SHA-verified
source, declared operation, eligible points/mask and uniqueness before it
stages one canonical DrawingDocument history transaction across up to 16 tiles.
The isolated native witness checks whole-output parity, malformed-response
rejection, signed-64-bit bounds, lazy tile recovery and Undo/Redo, including
synthetic sparse-vs-full staging timings and return-byte counts. The bridge is
**manual-only**, with fast-CI runner contracts; it is not installed in the
application, and no physical speedup/backend approval is claimed. T-068
remains In Progress. See [T-068](Tickets/T-068.md) and the
[benchmark report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 atomic multi-tile native publication witness (2026-11-03; In Progress):**
An isolated checked C++ GDExtension now stages multiple verified native tile
outputs into **one** canonical DrawingDocument gesture, preserving one Undo/Redo
entry and per-tile signed-integer dirty regions. It caps aggregate full-tile
work at 1,048,576 pixels / 16 tiles, fails closed on corrupt/lazy sources,
duplicate targets, bad native output, revision conflicts and locked layers,
and never publishes partial batches. The dedicated **128-check** Godot witness
is manual-only; fast CI checks runner isolation without loading native code.
No production integration, performance gain, physical-hardware acceptance or
backend decision is claimed. [T-068](Tickets/T-068.md) remains In Progress.


**T-068 real DrawingDocument publication witness (2026-11-03; In Progress):**
The optional checked C++ raster GDExtension now feeds a detached native tile
through the *actual* `DrawingEditSession.apply_region()` and
`DrawingDocument._publish_edit()` path in a disposable Godot project. Two
independent runs pass **443/443** native parity, **370/370** texture-publication
and **219/219** canonical document/history checks each. Real undo/redo,
dirty regions, negative/far signed tiles, lazy digest failures, locks,
no-op and stale/concurrent commits are exercised. This is **not** production
UI/backend adoption; copying a whole tile through GDScript is intentionally
unoptimized and does not establish a native speedup. T-068 stays In Progress.
See [T-068](Tickets/T-068.md) and
[raw evidence](benchmarks/T068_2026-11-03_gdextension_document.json).

**T-068 revision-guarded experimental native publication (2026-11-03; In Progress):**
The opt-in Godot/C++ bridge now has an isolated GDScript publication adapter
that rejects stale revisions and changed source bytes, reports exact changed-
pixel bounds, preserves the caller's RGBA8 buffer and updates a full
`ImageTexture` only after a successful single-threaded commit. Two Godot
4.8b2 runs pass **443 native bridge checks and 370 publication/GL readback
checks each**, using temporary project Xvfb/Mesa for reliable texture readback;
fast CI only runs five non-native runner contracts. This is **not** production
`DrawingDocument` publication, actual dirty-subrectangle upload, hardware
latency, or final native adoption. T-068 stays In Progress. See
[T-068](Tickets/T-068.md) and [raw evidence](benchmarks/T068_2026-11-03_gdextension_revision.json).

**T-068 isolated GDExtension bridge milestone (2026-11-03; In Progress):**
A throwaway Godot 4.8 beta 2 project now compiles a bounded checked raster
batch bridge directly against the engine-generated GDExtension header. Two
runtime runs pass 443/443 exact-pixel and error-boundary checks, without
shipping or auto-loading any native library in Drawing or Atlas. The editor
scan of the experimental extension is unstable, so only an explicit isolated
runtime load is tested. Four harness contract tests run in fast CI; the full
bridge is on-demand only. Physical-device, native publication, library
comparators, and the final backend decision remain open. See
[T-068](Tickets/T-068.md) and [raw runs](benchmarks/T068_2026-11-03_gdextension_bridge.json).

**T-068 bounded native-kernel ABI checkpoint (2026-11-03; In Progress):**
The unintegrated C++ raster kernel now has opt-in length-checked delta and
full-region functions, without changing its original ABI 1. A six-test fast-CI
contract suite checks 160 seeded source/operation cases against the original
functions, output canaries, partial alias rejection, short buffers and failure
atomicity. Caller-declared byte lengths cannot authenticate foreign pointers;
no native Godot integration, physical-device evidence or backend decision is
claimed. See [T-068](Tickets/T-068.md) and the
[CPU raster report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 isolated native-thread jitter milestone (2026-11-03; In Progress):**
Two runs of the unintegrated C++ raster kernel now compare 1/2/4 concurrent
workers with private RGBA8/source and output buffers, across blend, masked
erase and exact replacement. All 36 timed cells verified exact output parity;
the 2-test native/parser contract joins fast CI. Contention p95 varied and
cannot justify adopting a multithreaded Godot backend. See
[T-068](Tickets/T-068.md) and [the benchmark report](DRAWING_CPU_RASTER_BENCHMARK.md).


**T-068 longer software-frame and Linux RSS checkpoint (2026-11-03; In Progress):** Two 21-trial-per-size native Bucket-adapter processes passed **770/770** visual/canonical checks; Linux `/proc` tracked only the actual Godot executable (VmHWM **251,288/251,420 KiB**). Empirical CPU and `frame_post_draw` medians/p95s are recorded with raw trial samples, and the manual-only workflow now captures process RSS alongside screenshots. This is not production Bucket UI, physical scan-out, per-fill memory isolation or native backend acceptance. Fast CI adds five process-profiler contract tests but no framebuffer sweeps. See [T-068](Tickets/T-068.md) and [raw evidence](benchmarks/T068_2026-11-03_fill_linux_rss.json).

**T-068 measured canonical Bucket fill-to-frame on software GL (2026-11-03; In Progress):** New targeted native `drawing_fill_frame_native.gd` sends 15 synthetic GUI click gestures through a narrow **test adapter** into the real Drawing flood-fill transaction and renderer; it verifies exact deltas, visible framebuffer pixels and atomic budget rollback. Two five-trial runs pass **96/96** (with screenshot) and **95/95** checks. Results now include CPU-dispatch, `frame_post_draw` and sampled Godot memory monitors, but **do not** represent production Bucket UI, physical input, scan-out or peak RAM/VRAM. A workflow-dispatch-only Linux/Mesa action can reproduce the witness without changing fast CI. The native-backend, hardware and comparative performance gates of [T-068](Tickets/T-068.md) remain open. See [raw evidence](benchmarks/T068_2026-11-03_bucket_frame_native.json).

**T-068 verified-fill staging (2026-11-03; In Progress):** The Drawing flood-fill path now passes its already-validated source pixel into the detached staging operation instead of re-reading that pixel from the source tile; all ordinary editing tools retain normal source reads. A new **29-check** fast-CI witness covers mixed edits in one session, budget rollback, precise hidden RGB and signed 64-bit coordinates, Undo/Redo and stale-publication refusal. The 15-suite **1,832-check** headless regression and 81-check native software-frame brush witness pass; paired CPU-only timings are encouraging but too limited for a production performance claim. T-068 native-backend, Windows/Linux physical, memory/jitter, and external-library acceptance remain open. See [T-068](Tickets/T-068.md) and the [measurement report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 unique-candidate flood-fill frontier (2026-11-03; still In Progress):**
Four-connected Bucket fills now mark each candidate when enqueued, rather
than repeatedly appending already queued positions. Work budgets count
unique examined positions, including transparent/selection boundary pixels;
original source colors, publication, masks and Undo/Redo are unchanged. A
56-check headless fixture uses an independent grid oracle and exact-budget
retry; it joins the existing fast-CI T-068 step. Two ordered baseline/follow-up
CPU microbenchmarks show **mixed** results, not a reliable latency improvement.
Native library and hardware gates remain open. See [T-068](Tickets/T-068.md)
and [CPU report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 cached and lazy-safe flood fill (2026-11-03; still In Progress):**
The bounded Drawing Bucket engine now resolves each verified source tile once
per gesture, including lazily loaded chunks. Previously resident-only lookup
could incorrectly reject a valid saved seed or stop at an unloaded neighbor.
A 30-check fast-CI witness verifies hidden-RGB pixels, missing/corrupt lazy
providers and retry, selection, exact undo/redo, signed seams and atomicity.
Two before/after microbenchmark pairs indicate lower synthetic CPU fill+commit
medians for 32²–96² pixels, but **not** confirmed input-to-present gains.
Native library evaluation and physical hardware gates remain open; this is
not a backend decision or ticket closure. See [T-068](Tickets/T-068.md) and
[CPU report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 axis-aligned hard-brush sweep geometry (2026-11-03; In Progress):**
The canonical Drawing hard brush now handles exactly horizontal and vertical
nonstationary sweeps with bounded scalar squared-distance tests, preserving
its original row-major candidate order, once-covered blending, masks and
atomic gesture publication. All oblique sweeps continue through Godot's
`Geometry2D` oracle. The new **239-check** fast-CI witness includes original
Geometry2D pixel/RGBA8 parity, signed anchors beyond 2^53, masks, history,
and 320 deterministic randomized geometry cases. A seven-sample isolated
edit+commit benchmark shows **mixed** single-run timings, not a demonstrated
end-to-end speedup. No native backend adoption or physical device results
are implied; [T-068](Tickets/T-068.md) remains **In Progress**.


**T-064 duplicate linked nested child placements (2026-11-03; In Progress):**
The nested Object inspector now offers **Duplicate selected** (Ctrl+Alt+D).
It inserts a new linked child directly above the selected sibling with a
fresh stable child ID/generation, a one-unit parent-local displacement,
independent transform/metadata/visibility and the *same* published source.
The existing structural history supports exact Undo/Redo of this instance
without copying any source artwork. Invalid/stale sources, unsafe offsets,
failed publication and the 64-child graph limit reject atomically.
`tests/object_child_duplicate_smoke.gd` passes **53/53** headless checks,
plus **54/54** targeted native Xvfb/Mesa checks with a 420px inspector
screenshot. This is placement duplication, **not** the unresolved nested
single-source Save As/export reference-versus-deep-copy policy. T-064 remains
In Progress, with owner decisions and hardware validation outstanding.
See [T-064](Tickets/T-064.md).


**T-064 labeled nested child instances (2026-11-03; In Progress):**
The nested Object inspector now permits a 64-character optional label for
**each child instance**, distinguishing repeated uses of the same published
source without renaming or copying its Drawing pixels. Label edits are
parent-owned, version-checked registry publications, share the existing
child-local Undo/Redo with structure/transforms/visibility, and preserve
unrelated metadata. The **54/54** headless witness covers failed/stale edits,
no-ops, duplicates, history, saved registry reload, portable Objects-component
copy and live inspector controls. Its **55/55** targeted native Xvfb/Mesa
witness captures a 420px inspector. The ticket remains **In Progress**:
nested single-source Save As/export graph-copy policy and owner physical UX
validation remain pending. See [T-064](Tickets/T-064.md).

**T-064 reversible sibling paint order (2026-11-03; In Progress):**
The existing nested Object inspector now offers focusable **Send backward**
and **Bring forward** actions (Ctrl+Alt+Up/Down). Later siblings paint above
and win hit-testing over earlier siblings. The operation atomically moves one
existing child record in its parent-owned ordered list, retains source pixels,
identity, transform and other siblings, and shares optimistic revisions,
transitive Atlas preview invalidation and parent-scoped Undo/Redo with the
other nested edits. A dedicated **51/51** fast-CI Godot witness verifies
rendered pixels, hit paths, cache invalidation, invalid/stale/cancelled edits,
mixed history, disk reload and inspector buttons/keyboard. The targeted native
Xvfb/Mesa run passes **52/52** with a reviewed 420px inspector screenshot.
T-064 remains **In Progress** pending nested Save As/export policy and owner
hardware review; no owner gate was inferred. See [T-064](Tickets/T-064.md).

**T-064 reversible nested child scaling (2026-11-03; In Progress):**
The Object Manager nested inspector now offers Shrink/Grow actions for
parent-local scaling of selected linked/NULL child transforms. Scaling changes
only the published affine basis, preserving source pixels, identity, local
origin and child-relative descendants. It shares stale-safe Undo/Redo with
movement, rotation, structure, visibility and NULL repair. The new **42/42**
fast-CI Godot witness exercises nested render/hit paths, rotated/mirrored
bases, veto/stale guards and disk reload; a targeted **43/43** Xvfb/Mesa run
includes a 420px native screenshot. No physical owner UX review or nested
Save As/export dependency-copy decision is implied; **T-064 stays In Progress**.
See [T-064](Tickets/T-064.md).

**T-064 nested child visibility (2026-11-03; In Progress):**
The Object Manager nested inspector now hides/shows a selected child without
removing its stable identity or source pixels. Hidden child subtrees leave
Atlas preview rendering and hit paths, while remaining selectable in the
inspector. One parent-scoped action supports Undo/Redo; stale revisions and
publication vetoes fail closed. A dedicated **39/39** headless test is in
fast CI; the targeted native inspector screenshot witness passes **40/40**.
This is engineering evidence, not physical-device or owner UX signoff;
**T-064 remains In Progress** pending single-source Save As/export policy and
remaining validation. See [T-064](Tickets/T-064.md).

**T-064 saved-campaign copy UI (2026-11-03; In Progress):**
Atlas File → Copy saved campaign… (Ctrl/Cmd+Shift+S) now clones the last
checkpoint into a fresh directory through the verified T-066 campaign-copy
operation. The original stays open; missing checkpoints, unsaved Atlas or
Drawing changes, Object Editor drafts, in-progress gestures, unsafe path
components, stale registries and existing destinations are rejected. A native
modal with parent-directory chooser supports renaming the campaign file; the
new **39/39** headless UI witness is fast-CI-gated (**40/40** with native
screenshot). A compact 420px native layout was inspected. This does **not**
select nested single-asset Save As reference-vs-deep-copy semantics or grant
owner approval. T-064 remains In Progress. See [T-064](Tickets/T-064.md).

**T-064 complete portable campaign copy (2026-11-03; In Progress):**
`AtlasCampaignStore.copy_portable` now copies a verified saved campaign to a
fresh project folder using one staged directory promotion, preserving complete
sparse Drawing generations, physical chunks, fonts, Object source history,
child identities and previous-generation recovery. A renamed campaign is
validated before publication; stale Object indexes, corrupt source roots,
symlinked components, collisions and injected copy interruption fail closed.
The dedicated **46/46** fast-CI headless witness proves independent source and
clone edits. It copies the *saved* project, not unsaved drafts, and does not
choose the still-owner-dependent nested single-asset Save As/export policy.
**T-064 remains In Progress** pending that decision and hardware review.
See [T-064](Tickets/T-064.md).

**T-064 explicit nested NULL repair (2026-11-03; In Progress):**
A missing/deleted nested Object source can now be rebound to an explicitly
selected verified source through the existing child inspector, preserving its
stable child ID, generation, parent-local transform and original missing-source
ID. Repair and parent-local Undo/Redo share one optimistic graph transaction;
indirect cycles, stale child/parent revisions and rejected publications leave
registry bytes unchanged. A dedicated **45-check** headless witness is fast-CI-
gated, with **46/46** checks in the native screenshot run. This does not decide nested
Save As/export graph-copy semantics or grant physical owner acceptance.
**T-064 remains In Progress.** See [T-064](Tickets/T-064.md).

**T-064 nested canvas pointer transforms (2026-11-03; In Progress):**
Alt+drag on a published nested child now stages a transient canvas guide and
commits one immediate-parent-local transform on release, preserving the
existing child inspector Undo/Redo timeline. Descendant rotations and the
root placement's transform are accounted for; Escape, pointer exit, focus
loss, tool/map switch, stale published index or placement and invalid paths
leave all source pixels and child transforms unchanged. The dedicated
`object_child_canvas_drag_smoke.gd` witness is fast-CI-gated (**31/31**
headless checks; **32/32** with native screenshot capture). This is **not** owner/hardware interaction
acceptance; nested Save As/export copying policy remains undecided and
T-064 remains **In Progress**. See [T-064](Tickets/T-064.md).

**T-064 published Objects-component copy (2026-11-03; In Progress):**
`AtlasObjectLibrary.copy_objects_to()` now stages checksum-verified current
published source revisions and an unchanged registry in a separate campaign
directory. Nested child IDs/transforms, source revisions, placements and NULL
bindings remain referential rather than flattened; edits in a copied campaign
remain isolated. A **37/37** real-file headless witness is fast-CI-gated.
This is not a whole-campaign Save As or the still-undecided nested asset
Save As/export policy. Direct canvas transforms and owner/hardware review also
remain open; **T-064 stays In Progress**. See [T-064](Tickets/T-064.md).

**T-064 explicit nested canvas selection (2026-11-03; In Progress):**
Alt+click on a linked nested Object in Atlas now resolves its stable child-ID
hit path, opens the existing parent-local inspector at the actual owning
parent source and selects that child. Normal click retains root selection,
repeat hits retain child Undo/Redo history, and stale map/registry or hidden
ancestors fail closed. The dedicated **21/21** headless witness is fast-CI-gated;
Xvfb/Mesa native UI and optional screenshot pass **22/22**. Direct pointer
transform gestures, nested source Save As/export policy and physical review
remain incomplete; T-064 stays In Progress. See [T-064](Tickets/T-064.md).

**T-064 reversible nested child structure editing (2026-11-03; In Progress):** The existing Atlas child inspector can now attach an explicitly chosen available Object source, remove a selected child reference without deleting its source, and undo/redo structure **and** transforms in one parent-scoped history. Restored instances retain child ID, generation and sibling order; revisions advance monotonically. The new **45/45** fast-CI witness covers cycles, stale revisions, concurrent changes, failed publication and live picker/buttons; the expanded native X11/Mesa inspector witness passes **16/16**. The source picker searches published names/IDs and shows up to 128 matches. Canvas child hit interaction, Save As/export policy and owner/hardware validation remain unfinished; T-064 stays In Progress. See [T-064](Tickets/T-064.md).

**T-064 parent-scoped nested child transform editing (2026-11-03; In Progress):** Atlas's Object Manager now opens a nested-child inspector with stable child instance selection, parent-local moves/rotations, explicit child-source editor navigation, optimistic parent-scoped undo/redo and stale/campaign-switch recovery. Its dedicated headless **45/45** edit/history test runs in fast CI, while a targeted X11/Mesa **10/10** native UI witness captures real window layout. Integrated hit-path selection, Save As/copy policy and owner/hardware acceptance remain unfinished; no other ticket or manual review state changed. See [T-064](Tickets/T-064.md).

**T-064 bounded nested composition milestone (2026-11-03; In Progress):**
The Atlas Object renderer now paints linked parent/child/grandchild sources in
stable order with composed transforms and returns stable child-ID hit paths.
Atlas map previews include the nested extents and invalidate on graph changes
or explicit source Save; deleted child sources show bounded NULL markers.
The fast-CI 36-check `object_child_render_smoke.gd` covers on-disk sources,
rotation, deep paths, alpha, and bounded failures. Nested editing UI,
per-child undo/redo, and the Save As/portable copying policy are still open;
this is **not** T-064 acceptance or owner UX approval. See [T-064](Tickets/T-064.md).

**T-064 cycle-safe nested-source graph milestone (2026-11-03; In Progress):**
Atlas now stores optional stable child-source instances in its existing
published Object registry, validates cycles/depth/IDs on mutation and load,
and persists parent-local transforms and reverse dependencies. Pixel Save
preserves child records; deletion's Remove/NULL policy applies atomically to
nested references, including stale confirmation guards. The new 56-check
headless witness is push-CI-gated. Rendering and hit paths have a separate
bounded engineering witness above; nested editing and portable Save As/export
semantics remain unfinished and cannot be claimed accepted. See [T-064](Tickets/T-064.md).


**T-065 verified metadata page loading (2026-11-03; still In Progress):**
Atlas now inspects the metadata of SHA-verified published sources without
decoding every canonical pixel tile merely to populate a browser page.
Thumbnail, Edit Source and placement paths retain full pixel validation. The
expanded 49-check disk-backed source witness tests the trust boundary; its
short 351 KB CPU diagnostic is not physical Windows/Linux performance evidence.
Owner keyboard/pointer approval remains required. See [T-065](Tickets/T-065.md).

**T-065 real-file source I/O and page cache (2026-11-03; still In Progress):**
The canonical Object Editor now parses each bounded Drawing source once to
validate both pixels and metadata from the same file snapshot. The shared
Asset Browser retains a 24-image bounded LRU across partial Atlas pages,
invalidates changed source revisions and clears previews on campaign change.
A new 31-check fast-CI witness exercises a 351 KB four-tile source and
corrupt-blob/metadata rejection; the thumbnail suite now has 62 assertions.
These are engineering tests, **not** large physical-device campaign/owner UX
acceptance. See [T-065](Tickets/T-065.md).

**T-065 large published-library paging (2026-11-03; still In Progress):**
Atlas's shared Asset Browser now filters names and stable IDs across the
**entire published registry**, instead of losing all sources after the first
512. A metadata-first search selects one 64-source page for verified file
opening/thumbnail work, with Previous/Next, clamped page navigation and a
matching-source count. The new 1,428-check fast-CI witness includes 1,301
synthetic and 66 real published sources, plus a 10,000-summary upper-bound
exercise; prior browser and Atlas registry regressions passed. The native Atlas UI
passes 12/12, and its real XTEST pointer gesture passes 19/19 again after
page controls were introduced.
Standalone portable scanning retains its separate bounded safety policy.
Physical-device/large-real-file latency and **owner UX approval** are still
outstanding; T-065 remains In Progress. See [T-065](Tickets/T-065.md).

**T-065 Atlas shared-browser drop bridge (2026-11-03; still In Progress):**
The canonical Drawing Asset Browser is now embedded as an optional Layers
section in Atlas, showing published `Objects/` sources with registry-owned
IDs, thumbnails and usage counts. Godot GUI drag tokens and a native Atlas
canvas drop target place linked instances at the exact view coordinate,
with index/path/hash/revision validation and a keyboard Place alternative.
Atlas `asset-*` identities remain distinct from the embedded Drawing
`drawing-*` IDs; neither registry nor standalone scanner was duplicated.
New 32-check headless acceptance is push-CI-gated; the original 12 native
layout/provider/drop checks pass (13 with screenshot). A subsequent targeted
**real XTEST press–move–release** witness exposed and fixed `ItemList`'s
missing drag start: it now passes **19/19** actual native gesture checks
(**20/20** with screenshot), including click-without-placement, valid canvas
drop, invalid destination and Esc rollback. Direct owner pointer/keyboard
approval, physical hardware and large-project testing remain open. See
[T-065](Tickets/T-065.md).

**T-065 Atlas-managed portable registration (2026-11-03; still In Progress):**
The Atlas Object Manager now provides explicit Import/Export file dialogs
backed by versioned registry publication, not an unregistered file copy.
Imported `.drawing` sources retain stable source identity, human-readable
name and local frame, reject duplicate/reserved IDs and stale/symlinked paths,
and do not create placements. Exports reconstruct portable metadata without
changing instance bindings. The new 33-check disk-backed import/export test is
fast-CI-gated; the manager tests pass 33 headless and 22 native checks.
Cross-app drag/drop, high-volume/physical desktop review and **owner UX signoff**
remain open. See [T-065](Tickets/T-065.md).

**T-065 Atlas linked-instance and NULL-action milestone (2026-11-03; still In Progress):**
Atlas's Layers view now opens a library-bound source manager (`Ctrl+Shift+B`)
with published-ID usage counts, explicit current-map placement, three-way
Source Delete (Remove/NULL/Cancel), and deliberate stable-ID NULL repair.
Deletion confirmations are bound to registry and instance revisions; historical
source bytes remain untouched. The 48-check on-disk transaction and original 20-check manager/17-check native
Atlas witnesses introduced that workflow; later Import/Export extensions are
documented above. Shared-browser-to-Atlas drag placement and owner UX review
remain open. See [T-065](Tickets/T-065.md).

**T-065 thumbnail and portable-copy follow-up (2026-11-03; still In Progress):** real Object source
pixels now appear as lazy, bounded 48×48 previews with a 24-image SHA-keyed
LRU and automatic invalidation after successful local Object Editor Save.
The headless thumbnail test passes 54 checks; portable file-copy safety passes
29; native source/pointer/thumbnail passes 19 (20 with optional screenshot).
Standalone copies into Atlas-managed registries remain refused; dedicated
Atlas registration is now supported by the Object Manager as described above.
Shared-browser drag/drop, large-project checks and owner UX acceptance remain open. See
[T-065](Tickets/T-065.md) and [CI policy](CI_TESTING.md).

**T-065 portable Asset Browser milestone (2026-11-03; still In Progress):** the shared Drawing workspace can now attach an `asset_browser` dock peer via Window → Asset Browser… or a host-provided portable `Objects/` root. A bounded read-only source scan, name/ID filtering, stale-file and duplicate-identity rejection, and explicit Edit Source into an Object Editor tab are covered by 37 headless and 18 native checks. The later Atlas instance/NULL manager and portable registration milestones are described above; shared-browser drag/drop and owner UX acceptance remain unfinished. The original owner keyboard/pointer acceptance is tracked as a manual gate; no approval was inferred. See [T-065](Tickets/T-065.md) and [standalone usage](../drawing/README.md).

**T-068 publication-cache follow-up (2026-11-03; still In Progress):**
`DrawingDocument` now resolves the immutable source tile once per touched
tile while validating an atomic pixel publication. A new 30-check push-CI
witness covers signed seams, hidden RGB, lazy-source errors, stale originals,
and exact undo/redo. In a three-sample headless, commit-only benchmark across
512/1024/2048 strides and 64²/128² changed regions, every median was lower
(roughly 2.7–3.6×), but staging, UI and GPU costs were not measured. No
third-party native backend or hardware gate was satisfied. See
[T-068](Tickets/T-068.md) and [the report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 source-cache follow-up (2026-11-03; still In Progress):** the detached Drawing gesture now reuses successful per-tile source resolves rather than allocating a result per covered pixel. New 31-check lazy/corrupt/atomicity/signed-seam witness is fast-CI-gated; existing 693-check mixed benchmark parity and 81-check native software-frame stress both pass in before/after pairs. Most operation medians improved but some regressed; this is **not** proof of a stable speedup or native renderer adoption. External CPU comparisons and physical-device/Windows measurements remain open. See [T-068](Tickets/T-068.md) and [the CPU raster report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 measured brush-path follow-up (2026-11-03; still In Progress):** a narrow stationary-dab fast path avoids unnecessary geometry projection for hard brushes without changing edit/storage schemas. The original geometry oracle passes 125 exact-pixel/undo tests at fractional coordinates and signed 64-bit anchors; a 693-check mixed raster benchmark matches the previous changed-pixel and undo sizes across three storage strides. Two 25-gesture native X11/Mesa stress runs (81/81 each) verify visible 4/32/64px dabs, long/crossing strokes, and expose costly large-brush CPU/frame submission, but not physical presentation. Native library comparisons and two-platform validation remain open. See [T-068](Tickets/T-068.md).

**T-015 completed (2026-11-03):** Legacy battlemat placement creation/editing, spatial hit-testing, preview overlays and actionable Focus/Open are retired. Historical placement records and link fields remain **archival only** for lossless old-fixture reads, native saves and the standalone audit; they cannot participate in live navigation or Drawing. Marker-only navigation, search, selected-cell filtering, undo/history and native saves have replacement CI coverage. The old aligned-preview acceptance witness is retained under `tests/retired_legacy/`, not claimed green. T-014's historical D0–D2 raster assertions remain a separately deferred failure. See [T-015](Tickets/T-015.md).

| Ready | In Progress | Blocked | Manual Review | Done | Archived | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 3 | 10 | 4 | 55 | 1 | 83 |

**T-078–T-083 agreed docking sequence (2026-11-03):** The right icon rail remains panel-level, with separators only between tabbed groups. **T-078 Done** (82 model assertions) supplies unique stable-ID ownership, **T-079 Done** (40 native assertions) supplies collapsible groups, icon rail and in-app flyouts, and **T-080 Done** (60 model and 68 native assertions) adds transactional tab/group drag, visible insertion/merge hints, exact Esc/focus-loss/invalid-drop rollback, scrollable tab strips and keyboard arrangement controls. **T-081 Done** (64 model, 55 native checks) supplies real Control-based movable/resizable floating hosts, tab/group reordering, ownership transfer, hide/Window recovery and viewport clamping. **T-082 Done** (62 model and 56 native checks) delivers cross-container panel/group pointer docking, ordered redock, empty-canvas detach, robust invalid/focus-loss cancellations and accessible transfer commands. **T-083 Manual Review** after versioned persistence/recovery engineering (46 headless, 63 native; 65 with screenshots), with **explicit owner UX approval still mandatory**. Docking settings now save and restore, and earlier T-059/T-056 UX gates remain open. See [docking specification](DRAWING_DOCKING_SPEC.md), [T-080](Tickets/T-080.md) and [T-083](Tickets/T-083.md).

**T-063 owner-requested refinement (historical T-063 baseline, 2026-11-02):** The shared Drawing and Object Editor tool rail now uses six packaged, keyboard-focusable SVG icons with tooltips and pressed-state feedback. **Window → Show document tabs** hides/reopens the `Untitled` document strip for the current session; hidden tabs retain Ctrl/Cmd+Tab navigation, unsaved-close protection and document/dirty status. Colors/Layers/History now **stack vertically in one scrollable right dock**, with a bounded layer tree and focus-to-History support. The native witness has **75 required checks**; clean staging includes icons. T-063 remains Done while T-059 and T-056 **manual UX gates stay open**. See [T-063](Tickets/T-063.md) and [standalone usage](../drawing/README.md).

**T-063 completed (2026-11-02):** the [shared compact Drawing top bar](../addons/drawing/editor_top_bar.gd) now provides the eight-menu File/Edit/View/Image/Layers/Select/Window/Help layout with `BarDivider`, real tool-specific options and keyboard-reachable More/chevron overflow. The resizable right dock has Colors/Layers/History tabs, show/hide controls and a History preference, while `Ctrl+Shift+S` invokes actual Save As and Ctrl+Y is the primary redo. A 52-check native X11/Mesa witness tests 1280/560 widths, 1.5x scaling, scrolling, close safety and menu actions; the independent editor and Object Editor remain intact. **T-065 Asset Browser is now Ready; T-059 owner UX approval remains outstanding.** The BarDivider layout remains an owner-*proposed* design even though this engineering prototype is implemented; no manual gate was closed.

**T-074 completed (2026-11-02):** [reusable Object Asset authoring, Save As and NULL lifecycle](OBJECT_ASSETS_WORKFLOW.md) now traces distinct internal `Drawings/` documents, portable `Objects/` sources and per-map instance IDs through private edits, source publication, bound Variant B Save As, asymmetric undo/redo, deletion and missing-source repair. [The historical raster/Objects workflow](RASTER_OBJECTS_WORKFLOW.md) is explicitly labeled pre-split. Ten code-aware documentation checks run in CI, while actual Object Asset, Object Editor, composition and campaign storage suites were rerun. **T-064 nested cycles, T-065 Asset Browser/repair and T-059 owner UX review remain unfinished**; no manual gate was closed.

**T-073 completed (2026-11-02):** the [owner-approved 99-row Drawing feature inventory](DRAWING_FEATURE_INVENTORY.md) retains **47 Essential / 34 Later / 18 Skip** without claiming all are shipped. Its minimum T-053 witness is distinguished from the still-open complete Essential baseline, and pointer/keyboard acceptance flows cite real tests versus pending T-059 owner UX. The [one-row BarDivider workspace specification](DRAW_MODULE_UI_SPEC.md) remains an owner-*proposed* layout, now implemented as a tested T-063 prototype; the Object Editor tab is implemented (T-062), while Asset Browser dock parity awaits T-065. Ten source-aware documentation checks and an eight-check **native keyboard/pointer** witness run in CI. The formerly mismapped `Ctrl+Shift+S` Save As shortcut and missing menu shortcut labels have since been corrected by T-063; no owner gate was closed.

**T-072 completed (2026-11-02):** the nine [tool and interaction workflow pages](BRUSH_WORKFLOW.md) now lead with current Drawing-owned gesture/pixel/edit behavior, Atlas-owned map/selection/global history, the available six-tool standalone palette, and an explicit historical section for legacy Atlas-era prototypes. Bucket/Line/Polygon/Wall Path/T-027 UX remain **Ready** despite their generic engine primitives or old smoke fixtures. Editable text's single-element/explicit rasterization and portable licensed fonts are documented; T-068's native edit-region interface is not mistaken for a selected library. Ten documentation checks run in CI. Some old `.scn` and candidate tool smoke tests still fail and are recorded in [T-072](Tickets/T-072.md); this ticket changes **documentation and tests only**.

**T-071 completed (2026-11-02):** the [storage format and recovery contract](DRAWING_STORAGE_CONTRACT.md), [dictionary adapter audit](DICTIONARY_CONVERSION_AUDIT.md), and [raster importer analysis](RASTER_CHUNK_IMPORT.md) distinguish today's T-066 root-pointer/immutable-generation/individual `.zst` save from historical one-file native WebP/.scn code. Explicit, executable acceptance examples cover relocating a whole project, partial-copy/missing-file rejection, corrupted and interrupted generations, stale writers, precise signed tiles, and blank detail. [[T-067]]'s future 512-stride and segmented-pack recommendations remain **not deployed**. Eight documentation checks and actual missing-chunk failure coverage were added to CI; no save-format change or owner approval is implied.

**T-070 completed (2026-11-02):** the seven [world/detail/navigation pages](MAPS_AND_GRIDS.md) now lead with the actual Option B signed-world/explicit-density contract and distinguish blank D-levels, Atlas-only overlays, grid edit masks, derived previews and independent-map floor links from retired per-hex/battlemat designs. [Search/world discovery](SEARCH_AND_WORLD_DISCOVERY.md) separates today's safe legacy Search actions from the unapproved **Find/Locate** proposal; **T-009 Manual Review and T-017 owner usability gates remain open**. Eight automated documentation checks were added to CI; targeted runtime regressions passed except the older `snapping_smoke.gd` nil-layer case, recorded in [T-070](Tickets/T-070.md). No runtime or save-format change is implied.

**T-069 completed (2026-11-02):** the seven [architecture/data-model pages](ARCHITECTURE.md) now distinguish the shipped two-project Drawing/Atlas core, Option B internal `(map,floor,detail)` registry, Object Assets/instances and T-066 sparse generations from historical `.scn`/battlemat proposals. A six-check documentation suite and CI step guard source links, approved authority, and unresolved review/performance boundaries. No migration or UX approval was implied.

**T-077 completed (2026-11-02):** [platform-specific test matrix and reviewer handoff](DRAWING_TEST_PLAN.md) distinguishes the historical milestone-6 review and latency probes from T-067 storage, T-068 CPU raster/submitted-frame and the now-measured [T-057 GPU/LOD feasibility decision](DRAWING_LOD_RENDERER_BENCHMARK.md). The generator `tools/build_t038_review_bundle.py` makes a deterministic code-only reviewer ZIP. T-038/T-056 still require **actual independent/owner review**, not automatically generated evidence; no manual-review gate was closed.

**T-068 in progress (2026-11-02):** [controlled CPU and native-frame benchmark](DRAWING_CPU_RASTER_BENCHMARK.md) includes 691 Godot checks on the latest rerun, **10 native kernel unit tests**, 128 Godot/C++ alpha-parity vectors, a 24-pixel signed-world fixture, 15 sparse-delta-only C++ timings, and **68 native X11 software-frame checks** across 21 input events. A new ABI-versioned delta-only prototype avoids copying unchanged edit buffers but remains unintegrated. Tile-run compositing provides ~16× lower CPU-frame time on the bounded fixture. Actual Blend2D/Skia performance, GDExtension integration, physical presentation and Windows hardware remain unverified; **no native dependency was adopted and T-068 is not Done**.

**T-067 completed (2026-11-02):** [controlled 256/512/1024/2048 Zstd tile and 3-layout packing benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md) includes 48 physical-layout cases, 386 Godot native checks, software framebuffer upload measurements and explicit retiling/versioning rules. **512** is recommended for a *future new-document default* and immutable shared **segmented** packs are the physical-layout target; **neither change has been deployed**. Existing versioned 256-stride documents and T-066’s verified individual-blob writer remain authoritative until separate adoption and atomic-recovery tests. No manual review gate was bypassed.

**T-066 completed (2026-11-02):** [portable generation-based sparse campaign saving](DRAWING_STORAGE_CONTRACT.md) now durably publishes the single Atlas root pointer after verifying checked manifests, compressed tiles, Object Assets, licensed fonts and recovery roots. The real editor saves and reopens Drawing documents. T-067 subsequently completed its geometry/packing benchmark; adoption of its recommended default/pack layout is separate work. T-056/T-059 owner UX gates remain open.

**T-055 completed (2026-11-02):** [Atlas canvas composition, linked Objects, input precedence and read-only previews](DRAWING_ATLAS_COMPOSITION.md) use the one canonical Drawing package with 89 headless and 18 native display checks. T-056 is now **Ready** for separate engineering/release/owner verification; its manual-review approval remains pending. T-066 subsequently implemented the versioned multi-file save.

**T-061 completed (2026-11-02):** [Atlas floor/detail Drawing registry and shared signed world mapping](DRAWING_WORLD_MAPPING.md) now prove per-detail stable IDs, sparse blank D-levels, explicit pixel densities, 64-bit viewport anchors, Object Instance detail scoping and grid/entrance overlay continuity. **T-055 subsequently completed** main-canvas composition. T-061 does not claim that composition or T-066’s multi-file atomic save.

**T-062 completed (2026-11-02):** the [shared dedicated Object Editor](Tickets/T-062.md) now uses the same Drawing workspace in standalone Drawing and an Atlas-hosted window, with private drafts, Save/Save As, captured instance identity, signed local frames, unsaved-close protection and real UI/registry/history tests. **T-064 is now Ready**; Atlas main-canvas launch/composition (T-055) subsequently completed; the Asset Browser (T-065) and owner UX review remain outstanding.

**Owner review is intentionally narrow.** `Owner` in the table marks a direct completion gate; `Via T-039` indicates inherited privacy-policy approval. Agents can research, implement and test pending dependencies, but **must not mark Done** until the relevant direct and transitive manual approvals are recorded. Approved Drawing feature scope does not mean the final UX is accepted.

**T-051 completed (2026-11-02):** [testable Drawing document/package ADR](ADR_DRAWING_DOCUMENT_CONTRACT.md) and signed-tile consumer. **T-052 completed (2026-11-02):** the [independent generic Drawing core](../addons/drawing/README.md) and an isolated Godot consumer with 150+ runtime checks. T-053 is now Done with an [independently runnable desktop Drawing project](../drawing/README.md), a portable standalone document witness, native framebuffer tests, a third generic consumer and Linux release export. T-058 is now Done with editable one-element text layers, a shared glyph compositor and explicit undoable rasterization; T-062 is now Done with a shared Object Editor and Atlas-bound Save As workflow. T-063 is now Done; T-065 is Ready. T-054 now provides tested Drawing-local and Atlas-global contextual history, one-step cross-document transfers and the Save As binding-history contract; subsequent Object Editor and Atlas canvas composition were delivered in T-062/T-055. T-060 now provides [versioned Object Assets, linked per-map instances, private Save drafts and atomic component-level Save As rebinding](../scripts/objects/README.md), including NULL placeholders and real portable-file tests. Its per-campaign object index is now captured by T-066’s portable generation snapshots. T-055 completes live Atlas composition; T-066 completes the versioned sparse campaign save. Polished UI, performance benchmarks and owner UX gates remain incomplete.

**T-075 completed (2026-11-02):** the nine [player projection and collaboration pages](PLAYER_PROJECTION_CONTRACT.md) now distinguish the currently implemented DrawingDocument/Asset/T-066 source graph from isolated legacy raster-sanitization, X11 player-window and in-process session proofs. Windows/Linux native desktop is the active target; [Web T-044](Archive/Web/T-044.md) is **Archived** without deleting its historic tests. Ten source-backed documentation tests and 375 headless plus 124 native visual checks passed. **T-039 Manual Review, T-043/T-048 blocked independent owner gates remain unchanged**; no real player-authorized projector or authenticated multiplayer is claimed.

## Tickets

| Ticket | Status | Review gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | — | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | — | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | — | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | — | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | — | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | — | — |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Manual Review | **Owner** | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | — | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | — | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | — | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Done | — | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | — | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | **Owner** | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md) |
| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Ready | — | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | — | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | — | — |
| [T-022 · Move](Tickets/T-022.md) | Done | — | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Ready | — | — |
| [T-024 · Line](Tickets/T-024.md) | Ready | — | — |
| [T-025 · Polygon](Tickets/T-025.md) | Ready | — | — |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Ready | — | — |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Ready | — | — |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | — | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | — | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | — | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | — | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | — | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | — | [T-001](Tickets/T-001.md) |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | **Owner** | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Manual Review | **Owner** | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | **Owner** | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md) |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | — | — |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Via T-039 | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | **Owner** | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md) |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Ready | — | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | — | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | — | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | — | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Ready | **Owner** | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | **Owner** | [T-051](Tickets/T-051.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | — | [T-053](Tickets/T-053.md) |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | In Progress | — | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | In Progress | **Owner** | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | — | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | — | [T-052](Tickets/T-052.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | — | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | — | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | — | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | — | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | — | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | — | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | — | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | — | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | — | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | — | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | — | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | — | [T-079](Tickets/T-079.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | — | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | — | [T-081](Tickets/T-081.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | Manual Review | **Owner** | [T-082](Tickets/T-082.md) |

## Epics

- [ ] [[E-009|E-009 · Drawing / Atlas capability separation]]
- [ ] [[E-001|E-001 · Drawing, erasing and edit history]]
- [ ] [[E-002|E-002 · Continuous chunked board and grid masks]]
- [ ] [[E-003|E-003 · Typed artwork model and persistence]]
- [ ] [[E-004|E-004 · Usable drawing and manipulation]]
- [ ] [[E-TOOLS|E-TOOLS · Familiar drawing-tool suite]]
- [ ] [[E-005|E-005 · Discovery, previews and floors]]
- [ ] [[E-006|E-006 · Authored artwork LOD and detail editing]]
- [ ] [[E-SAVE|E-SAVE · Portable multi-file save integrity]]
- [ ] [[E-007|E-007 · Local table and projector output]]
- [ ] [[E-008|E-008 · Host-authoritative collaboration]]

## Archived platform work

The Web-only [T-044 historical ticket](Archive/Web/T-044.md) is paused; native projector/privacy and collaboration tickets remain active. See [Web archive policy](Archive/Web/README.md).

## Maintaining this index

When adding or changing a ticket, keep its frontmatter and this table synchronized. Run `python3 tools/validate_ticket_store.py`; CI also checks these on repository updates. Never turn a manually gated ticket or any dependent ticket Done without the owner's explicit recorded approval.
