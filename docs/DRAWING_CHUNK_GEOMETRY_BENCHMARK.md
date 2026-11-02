# T-067 — Drawing sparse chunk geometry and packing benchmark

**Run:** 2026-11-02, `aidev`, Godot **4.8.beta2** (`cafc17a19`), Linux 6.18.57 x86_64, container/overlayfs, **AMD EPYC 9V74** (5 visible vCPUs), **5.8 GiB** memory, Zstandard 1.5.7, 4 KiB filesystem blocks. The software upload probe used **Mesa 25.0.7 llvmpipe** OpenGL compatibility rendering in Xvfb, *not* a discrete GPU. Native Windows, physical-drive power loss and real GPU VRAM were not measurable here. CPU scheduling, OS page cache and overlayfs make timings machine-dependent; these are samples, not performance guarantees.

**Decision: prefer 512×512 for *new* generic Drawing documents in the next storage-default implementation, and a content-addressed, immutable, shared **segmented** pack + validated index as the physical-layout direction.** Retain the already shipped `drawing-sparse-manifest-v1` and its recorded per-document strides; **do not silently retile an existing saved document**. `AtlasDrawingRegistry` and `DrawingDocument` currently default to 256 and T-066 currently writes individual `.zst` files. This research ticket **does not claim the future 512 default or pack writer is deployed**. Changing those defaults and implementing pack publication requires separate implementation, atomic-generation recovery tests and a Windows validation pass. Keep the current proven T-066 writer until that work is complete.

## Reproduction and raw evidence

Run from the repository root (no third-party Python packages; `libzstd` and Godot are required):

```bash
python3 tools/benchmarks/chunk_geometry.py --output /tmp/t067-data --repeats 3
python3 -m unittest discover -s tests -p test_chunk_geometry.py -v
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --path . --script res://tests/chunk_geometry_codec_smoke.gd -- --folder /tmp/t067-data
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --path . --script res://tests/chunk_geometry_benchmark.gd -- --output /tmp/t067-data/native-godot.json
xvfb-run -a godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  --script res://tests/chunk_geometry_upload_benchmark.gd -- \
  --output /tmp/t067-data/upload-software.json
```

The Python benchmark's native Zstd level 3 frames round-trip through Godot's `PackedByteArray.decompress(COMPRESSION_ZSTD)` **and vice versa**. The model uses real compressed byte streams and actual physical files; it is **not** a measurement of an implemented packed-format parser or pack publisher. The Godot test separately uses the real `DrawingDocument`, `DrawingEditSession`, `DrawingRenderer` and T-066 `AtlasCampaignBundle` APIs. All source content is deterministically generated with seed `670021`; raw intermediate images are not required to replay.

- [All 48 physical-layout comparisons and per-case timings (CSV)](benchmarks/T067_2026-11-02_layouts.csv)
- [Full 16 geometry/workload results, cache and edit amplification (JSON)](benchmarks/T067_2026-11-02_layouts.json)
- [Godot signed-world, history, sparse-save benchmark (JSON)](benchmarks/T067_2026-11-02_native.json)
- [Mesa software-GL upload timings (JSON)](benchmarks/T067_2026-11-02_upload.json)

Workloads: two 2304×1408 dense continuous layers (gradient artwork with transparent nonzero RGB, and long crossing strokes); a 1152×896 high-entropy imported texture at density 2; **24** tiny isolated marks beyond ±1.3 million pixels including coordinates beyond ±2⁵³; and a mixed three-document project. All tile variants sample identical underlying coordinates/pixels. Partial edges, signed floor division, hidden RGB, exact RGBA8 decode, density metadata, and retiling invariants are checked. Cache simulations replay 8/32/128 MiB bounded LRUs, maximum 64 resident tiles; these are *simulated access patterns*, not Godot profiler measurements. Save tests use three successive real campaign generations with a one-pixel edit per generation and correct reopened bytes. Native hard-brush tests use 13 swept gestures crossing **signed x/y chunk boundaries** with camera anchors beyond 2⁵³, then undo/redo and bounded 24×24 viewport draws.

## Compressed footprint, sparse inflation, file overhead

The following table includes raw decoded **allocation** for all occupied logical tiles (not actual process RSS). Encoded bytes sum tile Zstd frames, excluding index. Physical files count includes a JSON index. `individual` is the *existing-style* global content-addressed file layout; `document pack` is one file per document; `shared pack` is one indexed, globally deduplicated file. **Pack layouts are isolated prototypes, not current T-066 writes.**

| Workload | Tile | Logical tiles | Allocated RGBA8 | Zstd payload | Individual files | Document-pack files | Shared-pack files |
|---|---:|---:|---:|---:|---:|---:|---:|
| Dense | 256 | 120 | 30 MiB | 2,405 KiB | 121 | 3 | 2 |
| Dense | 512 | 40 | 40 MiB | 2,465 KiB | 41 | 3 | 2 |
| Dense | 1024 | 18 | 72 MiB | 2,502 KiB | 19 | 3 | 2 |
| Dense | 2048 | 8 | 128 MiB | 2,558 KiB | 9 | 3 | 2 |
| Sparse marks | 256 | 24 | 6 MiB | 1.3 KiB | 25 | 2 | 2 |
| Sparse marks | 512 | 24 | 24 MiB | 2.0 KiB | 25 | 2 | 2 |
| Sparse marks | 1024 | 24 | 96 MiB | 4.3 KiB | 25 | 2 | 2 |
| Sparse marks | 2048 | 24 | 384 MiB | 13.4 KiB | 25 | 2 | 2 |
| Mixed | 256 | 107 | 26.8 MiB | 6,419 KiB | 108 | 4 | 2 |
| Mixed | 512 | 51 | 51 MiB | 6,481 KiB | 52 | 4 | 2 |
| Mixed | 1024 | 35 | 140 MiB | 6,525 KiB | 36 | 4 | 2 |
| Mixed | 2048 | 28 | 448 MiB | 6,582 KiB | 29 | 4 | 2 |

**Compression improved neither in dense nor mixed data when the tile grew:** larger partial-edge allocations inflated Zstd payloads slightly. In sparse isolated marks, the number of logical tiles **did not decrease** at all, so 2048 costs **64×** the decoded working set of 256. For dense artwork, 512 reduces tile/file count by 67% at +33% decoded allocation; for mixed content, 512 halves files at roughly 1.9× allocation. On the mixed project, individual files occupy **6,724 KiB** of filesystem blocks at 256 and **6,660 KiB** at 512; shared-pack prototypes occupy **6,440 KiB** and **6,496 KiB** respectively. On the sparse workload, 25 tiny files require **104 KiB** of allocated blocks regardless of stride, whereas a shared indexed pack needs **12 KiB** at 256/512. Sparse file-count relief is much better addressed by packing than by increasing tile dimension.

At 512, the mixed project's index shrinks from **12,521 bytes** (individual) to **9,691 bytes** (shared) and file count falls from **52 to 2**. Document packs can have slightly smaller indexes but require rewriting an entire immutable document pack for one edit: the imported-texture case rewrites **~4.1 MiB** for a changed ~162 KiB blob; an append-only *delta segment* in a shared pack writes ~162 KiB plus frame/index overhead. These payload-only microbenchmarks **exclude** the actual generation manifest, flush, verification, rename and root pointer work; do not mistake their sub-millisecond measurements for committed-save latency. **No permanent mutable shared pack** should be used in a generation-based save.

## Native latency, cache, RSS, software framebuffer

The following three-generation real Atlas save timings are on a nearly empty campaign with a one-pixel edit before every generation. `p95` of 3 saves is simply the maximum sample. Native edit/viewport are median of **13** sweeps. **Viewport** is Drawing CPU compositor time for 24×24 pixels, not GPU presentation. RSS is `/usr/bin/time -v` peak for a **fresh Godot process per stride**, including engine overhead.

| Tile | Committed save median / p95 | Swept edit median / p95 | CPU viewport median | 32 MiB cache capacity | Process peak RSS | Full RGBA8 texture |
|---:|---:|---:|---:|---:|---:|---:|
| 256 | 11.7 / 11.9 ms | 0.85 / 1.17 ms | 3.30 ms | 64 tiles (entry cap) | 159 MiB | 0.25 MiB |
| 512 | 25.7 / 25.9 ms | 0.83 / 1.04 ms | 3.17 ms | 32 tiles | 161 MiB | 1 MiB |
| 1024 | 89.7 / 90.5 ms | 0.88 / 1.02 ms | 3.26 ms | 8 tiles | 179 MiB | 4 MiB |
| 2048 | 300.9 / 302.0 ms | 0.83 / 0.91 ms | 3.31 ms | 2 tiles | 252 MiB | 16 MiB |

The current gesture history stores changed pixels rather than a full decoded tile: the native test reports **598 changed pixels over 13 strokes** per size and exactly one undo/redo step per stroke. Serializing the two per-pixel delta dictionaries (a **wire-size proxy, not heap allocation**) requires **65,104 bytes total**, with a maximum of **5,008 bytes per gesture**, at *every* stride. The Godot sparse editor's edit/undo times were therefore nearly independent of storage stride in this bounded test. The **save path is not**: a one-pixel change can materialize a whole large chunk, making 2048 poor for interactive persistence. The cache model's mixed-project repeated pan access has **0 hits/80 misses at 1024 and 2048** with its 32 MiB LRU, versus **48 hits/32 misses at 256/512**; this is a model, not a real viewport trace. Measured native peak RSS also rises with tile size. Direct per-operation undo heap allocation, high-depth histories, VRAM and true GPU frame times still require the broader T-068/T-057 profiling.

Software-GL `ImageTexture.update` median time for full buffers was **0.020 / 0.042 / 0.171 / 0.966 ms** at 256/512/1024/2048. `force_draw` was typically ~2–3 ms but had a 26-ms outlier at 256. Because the driver is Mesa llvmpipe and VSync unavailable, none of these figures establish discrete-GPU bandwidth or VRAM performance. Godot's `ImageTexture.update` uploads the **full tile**, not the 4px brush's changed rectangle. Preserve a distinct smaller edit/delta/texture-update region under T-068.

## Recommendation, versioning and retiling plan

1. **Default geometry target: 512×512**, after the code/default transition is implemented and performance-tested separately. 256 remains valid and may be better for widely scattered marks or tight memory. 1024 may be an explicit **per-document** choice for exceptionally dense contiguous art after profiling and an adequate cache/save budget; it is **not** the universal default. Do **not** choose 2048 by default: 16 MiB decoded/tile, sparse inflation, cache churn and large synchronous saves are poor trade-offs here. Do not introduce auto-adaptive per-tile dimensions.
2. **Physical layout target: immutable, content-addressed shared *segmented* packs + an index.** Segment blobs by generation/shard to bound incremental write amplification; map `(document ID, layer ID, signed tile x/y)` to `(canonical SHA-256, segment ID, offset, compressed length, compressed hash, stride)`. A versioned manifest must hash/validate every referenced pack index and physical payload; a single atomic generation-root pointer publishes only fully staged, verified segments. Never mutate a segment reachable from a prior valid root. Keep old segments/generations while undo/recovery references exist. Pack indexes need bounded offsets, size and path validation, hash collision handling, input caps and independent fault-injection tests. The **already working individual `.zst` CAS writer** remains authoritative until this design is implemented and proven. A single mutable whole-project pack or copying a multi-MiB per-document pack on every 1px edit is not recommended.
3. **Document stride invariant:** `drawing-sparse-manifest-v1` already records `tile_stride`; each loaded document retains its stored stride for its entire editing lifetime. Stable layer IDs and world pixel coordinates are independent of tile partitioning and of Atlas map/floor/detail IDs. No implicit stride choice based on the current code default, source machine, or zoom. Density must remain a separate rational pixels-per-map-unit field.
4. **Explicit atomic retiling only:** require an intact current savepoint, no active gesture, and a strategy for outstanding history references (or postpone until history is checkpointed). Iterate **all** old tile values including transparent pixels with nonzero RGB, mapping signed global pixel `old_tx * old_stride + local_x` (and y) to `new_tx = floor_div(global_x, new_stride)`, `new_local = global_x - new_tx * new_stride`; keep metadata, exact source bytes, document ID, layer IDs, order and density unchanged. Do not allocate all-zero target tiles. Stage and verify all replacement chunks and manifests as a **new immutable campaign generation** before switching the root. Keep the old generation recoverable, detect concurrent writers, and do not rewrite in-place or assume that an interrupted retiling is safe. Round-trip pixel/hash, signed-boundary and old-generation recovery tests must precede rollout. Existing 256 documents stay 256 unless explicitly retiled; no historic `.scn` migration is required.
5. **Next engineering verification:** implement an optional 512 default under the shared package's constructor and Atlas registry without changing opened versioned documents; benchmark near-live memory and synchronous save budget before deployment. Introduce physical segmented packs only under a separate storage change, rerun T-066 crash/recovery and clean independent Drawing consumer tests, validate on Windows/Linux hardware, and pair with T-068 (small dirty/edit regions) and T-057 (GPU/LOD). No owner UX acceptance or native-library adoption is implied by this benchmark.

## Acceptance and limits

The deterministic 48-layout matrix, 386 native checks, 6 benchmark unit tests, native codec roundtrip, measured software-GL uploads, and T-066’s existing staged-write/root-failure tests support this **engineering geometry and physical-layout recommendation**. Actual compositor microbenchmarks measure a bounded CPU viewport, not a large multi-layer GPU stress test; real cold-disk cache flushing, filesystem `fsync` after a physical power loss, packed-format production code, a representative Windows machine, and discrete GPU VRAM remain **unverified**. Do not claim that synthetic pack timings prove production pack safety. This research ticket is independent of the review-gated T-056/T-059 UX acceptance work.
