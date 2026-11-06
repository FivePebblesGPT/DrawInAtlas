---
type: archive
archived: 2026-10-30
original_path: docs/NATIVE_SAVE_BENCHMARKS.md
---

> [!info] Historical measurements
> These fixture results remain evidence for their recorded implementation, not proof of the revised canvas/LOD model's performance. See [[E-SAVE]], [[T-002]] and [[T-004]] for current work and [[Index]] for completion.

<!-- Original report; relative links rebased only. -->
# Native raster benchmark and AD-10 decision

**Measured:** 2026-10-29, local Arch Linux x86-64 workstation, standard Godot
**4.8.beta1.official.4d10419ca**, headless. These are local synthetic workloads,
not user-campaign performance guarantees or remote CI measurements.

## AD-10 addendum: selected representation

**Select embedded lossless WebP chunks with whole-scene ResourceSaver compression.**
All candidates passed exact dimensions/RGBA8 hash checks, including transparent
nonzero RGB, negative chunk positions, partial edge chunks, and an independent
second load whose pixel mutation did not change the other instance.

WebP gave the smallest raster-heavy files and slightly less working memory than
per-chunk Zstd, at a higher encode/decode cost. Native Images were faster and used
less memory, but their compressed detail container was 8.73 MB versus WebP's
6.90 MB. Per-chunk Zstd was faster than WebP but still larger. This follows the
approved preference for size/memory before small CPU improvements, with the actual
costs exposed below. It is not a claim that WebP is fastest or best on every image.

Container compression reduces the ink/layer fixture from 252,693 to about 38,600
bytes. It saves little on raster-heavy WebP (and adds about 0.08% in the detail
fixture), but the metadata savings justify enabling it consistently. No arbitrary
acceptance threshold or campaign-size limit has been invented.

## Reproduce and interpret

From the repository root, after importing with the exact beta engine:

```bash
python3 tests/benchmarks/run_raster_codec.py --engine /path/to/godot
python3 tests/benchmarks/run_raster_codec.py --engine /path/to/godot --store
# Optional: --fixture sparse|ink|multi|detail; --repeats N (default 3)
```

The stdlib Python driver requires Linux GNU `/usr/bin/time` for peak RSS. Each
sample runs in a fresh process; tables use medians of three samples per cell.
GDScript can also run an individual cell directly:

```bash
godot --headless --path . --script res://tests/benchmarks/raster_codec.gd -- detail webp compressed
godot --headless --path . --script res://tests/benchmarks/raster_codec.gd -- detail store compressed
```

Codec containers embed the same actual Resource-backed domain/map graph plus a
controlled benchmark payload Resource; they are **not production-format campaign
files**. The graph's chunk references remain constant across alternatives. Save
time includes payload encoding, packing and ResourceSaver; load time includes
fresh loading, instantiation, metadata comparison, pixel decoding and hashing.
WebP encoding uses the production helper, including its immediate decode/fidelity
check; this is an API-path comparison rather than isolated codec-library timing.
Source Images remain live and decoded Images are retained, representing editable
working sets rather than a compressed-only cache. Fixture construction and engine
startup are excluded from wall-time measurements. They are included in process
peak memory. Filesystem/page caches are warm, not cold-device measurements.

`OS.get_static_memory_usage()` captures fixture/encoded/loaded working memory;
`OS.get_static_memory_peak_usage()` and GNU time capture whole-process static and
resident peaks. Static and RSS are different measurements, not additive values.
The JSON output includes all working-memory samples and second-load timings.

Fixtures:

- **sparse:** 273×269 RGBA8, four chunks, sparse alpha but nonzero hidden RGB,
  40 small strokes. 293,748 raw pixel bytes.
- **ink:** 32 ink layers, 2,048 two-point strokes, no raster payload. Codec labels
  are controls here; small compressed-size variations are serializer identifiers.
- **multi:** four maps × two independent floors, eight 769×513 raster layers,
  96 chunks, 320 strokes; 12,623,904 raw pixel bytes. Several floors intentionally
  repeat pixel content, exposing the cost of absent global payload deduplication.
- **detail:** 2049×1537 detailed seeded gradient/noise/alpha art, 63 chunks,
  40 strokes; 12,597,252 raw pixel bytes. This is generated texture detail, not a
  benchmark of an actual photographed/painted user map.

Every raster fixture has affine placement, negative coordinates, 256-pixel
boundaries and partial edges. The storage acceptance fixture separately tests
cyclic graph links, multiple entrances, placements and high-precision settings.

## Codec-container matrix

Sizes are bytes; wall times are milliseconds; memory is MiB. “Packed” means
`ResourceSaver.FLAG_COMPRESS`, not image/GPU compression. Load2 is a second fresh
resource load in the same process while the first remains live.

| Fixture | Codec | Packed | Bytes | Save | Load | Load2 | Peak static | Peak RSS |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sparse | Image | no | 304005 | 2.24 | 1.77 | 1.64 | 84.25 | 139.55 |
| sparse | Image | yes | 188271 | 3.79 | 2.15 | 2.02 | 84.25 | 139.96 |
| sparse | WebP | no | 120224 | 20.07 | 3.26 | 3.09 | 84.25 | 141.80 |
| sparse | WebP | yes | 113769 | 20.13 | 3.29 | 3.20 | 84.25 | 142.27 |
| sparse | raw | no | 303272 | 1.92 | 1.55 | 1.60 | 84.25 | 139.73 |
| sparse | raw | yes | 188443 | 4.17 | 2.70 | 2.17 | 84.25 | 140.27 |
| sparse | Zstd | no | 175952 | 4.07 | 2.05 | 1.93 | 84.25 | 140.17 |
| sparse | Zstd | yes | 167903 | 4.58 | 2.08 | 1.99 | 84.25 | 140.40 |
| ink | Image | no | 252693 | 20.23 | 12.55 | 11.53 | 90.61 | 148.79 |
| ink | Image | yes | 38631 | 15.81 | 10.67 | 10.29 | 90.72 | 148.88 |
| ink | WebP | no | 252693 | 18.58 | 11.99 | 11.79 | 90.57 | 148.70 |
| ink | WebP | yes | 38647 | 15.45 | 10.02 | 11.01 | 90.70 | 149.37 |
| ink | raw | no | 252693 | 18.11 | 12.29 | 11.55 | 90.56 | 149.02 |
| ink | raw | yes | 38605 | 15.50 | 9.84 | 10.30 | 90.67 | 148.86 |
| ink | Zstd | no | 252693 | 17.95 | 12.86 | 11.60 | 90.57 | 148.66 |
| ink | Zstd | yes | 38614 | 17.65 | 9.68 | 11.45 | 90.70 | 149.04 |
| multi | Image | no | 12727780 | 53.70 | 51.84 | 55.09 | 118.42 | 172.35 |
| multi | Image | yes | 8404238 | 141.13 | 72.37 | 73.55 | 118.45 | 172.84 |
| multi | WebP | no | 6958183 | 441.11 | 106.06 | 114.07 | 130.92 | 185.57 |
| multi | WebP | yes | 6924456 | 459.75 | 111.54 | 115.83 | 130.95 | 185.66 |
| multi | raw | no | 12710395 | 55.54 | 57.86 | 50.51 | 118.27 | 172.38 |
| multi | raw | yes | 8402575 | 136.36 | 76.83 | 77.68 | 118.45 | 173.32 |
| multi | Zstd | no | 7181559 | 145.19 | 75.48 | 73.98 | 131.49 | 186.67 |
| multi | Zstd | yes | 7046008 | 174.65 | 74.98 | 82.07 | 131.52 | 187.13 |
| detail | Image | no | 12642743 | 56.13 | 49.18 | 49.06 | 116.36 | 173.12 |
| detail | Image | yes | 8726006 | 136.44 | 76.86 | 70.50 | 116.37 | 172.92 |
| detail | WebP | no | 6890483 | 444.96 | 106.03 | 109.62 | 129.27 | 185.91 |
| detail | WebP | yes | 6895791 | 457.73 | 101.26 | 110.42 | 129.28 | 186.49 |
| detail | raw | no | 12631331 | 47.54 | 55.64 | 54.63 | 116.43 | 172.36 |
| detail | raw | yes | 8663197 | 130.18 | 70.98 | 75.33 | 116.44 | 173.25 |
| detail | Zstd | no | 7217967 | 149.78 | 69.44 | 68.47 | 129.89 | 187.00 |
| detail | Zstd | yes | 7121639 | 160.75 | 74.74 | 73.85 | 129.90 | 186.78 |

For the compressed detail container, fixture static memory is about 91.38 MiB.
Keeping one freshly loaded editable graph adds approximately 12.5 MiB with
Image/raw, 19.0 MiB with WebP or 19.3 MiB with per-chunk Zstd. The latter two
retain compressed bytes **and** decoded working pixels. Holding a second graph
increases memory again; peak RSS is not the incremental cost of one load.

## Actual production store

These use the real `AtlasCampaignStore`: isolated snapshot, encoding, integrity
checks, verified staging and activation. “Overwrite” additionally validates the
old head and rotates/replaces its backup. Load includes complete domain/digest/
pixel validation. Both loaded campaigns remain live when working memory is sampled.
Unlike codec-container timing, these are the application-facing transaction costs.

| Fixture | Primary bytes | Historical JSON + unique WebP bytes | Initial save ms | Overwrite ms | Load ms | Load2 ms | Working static MiB | Peak static MiB | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sparse | 113481 | 115433 | 41.09 | 52.32 | 5.41 | 5.54 | 80.58 | 84.40 | 143.35 |
| ink | 38695 | 160673 | 151.29 | 247.85 | 42.17 | 41.69 | 90.34 | 96.50 | 153.73 |
| multi | 6917021 | 4338058 | 1121.02 | 1441.87 | 164.18 | 163.76 | 131.27 | 183.37 | 236.60 |
| detail | 6890647 | 6868679 | 1070.90 | 1372.98 | 160.40 | 157.55 | 129.15 | 179.90 | 236.59 |

The historical size is reconstructed using the former v6 canonical JSON/checksum
envelope and one WebP per unique pixel hash (baseline `a7bdd27`). It is **size
context only**, not a remeasurement of legacy transaction latency or peak memory;
its calculation runs outside production timed regions. Primary sizes exclude
backup/staging files in both formats. Working/static peaks are captured before
the legacy-size calculation; process RSS includes the whole benchmark process.

Repeated content explains the multi-map size regression: the old store globally
deduplicated content-addressed sidecars, while native chunks currently embed
their payloads independently. In that fixture one-file storage costs about 59%
more primary space. No global native payload deduplication is claimed.

Full-file rewrites remain synchronous. Benchmarks do not establish an upper
campaign-size bound, cold-disk performance, browser memory behavior or low-memory
device support. Real user campaigns much larger than these fixtures should be
measured before promising responsive saves. Backup/pending/temporary resource
paths can require several file generations of disk space. None of these results
changes the accepted single-primary-file architecture.
