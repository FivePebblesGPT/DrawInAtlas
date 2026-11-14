# T-095 — buffered Hokusai native pigment delta transfer (2026-11-11)

**Scope:** `sprint/2026-11-11`, T-095 only. **Ticket:** `In Progress`,
`manual_review: true`. **Not an owner acceptance or hosted CI pass.**

## Change and independent control

`native/drawing_brush/src/lib.rs::preset_segments` formerly pushed each
changed pixel's signed `(x,y,straight-RGBA8)` triple separately into the Godot
packed array. The implementation now collects the same triples in `Vec<i32>`
and performs one packed-array conversion at the end. No changes to brush
settings, surface mutation, dirty-tile sort, quantization, native transaction
snapshots or GDScript staging were required. The default Legacy path and
NativeHard rasterization are unchanged.

Before editing the source, the **actual previous native library at local HEAD
`5174fb0b6136b185ea046f018af637333f6be8b4`** was run against the new
`drawing/tests/t095_native_preset_packed_output.gd` script under Godot
`4.8.beta3.official.c51ff06e8`, Rust 1.99.1 / godot-rust 0.5.5 / Hokusai
0.3.0, Linux x86-64. The full **ordered** stream of packed signed i32 triples,
with per-batch lengths included in the SHA-256 input, generated these fixed
goldens:

| Bundled `.myb` | Output pixels | Pre-change SHA-256 |
| --- | ---: | --- |
| `hard_round` | 69,132 | `90190a1390e89e0615c077bddb27b59cec99613c6de30b17514381f30495227a` |
| `soft` | 67,088 | `86ab6b6c7e901be85f6740166770e3310a0c76edca465df785d640b0b2e66a7d` |
| `ink` | 37,782 | `abe74096f2f4807d94491f5e054b0066e7831d64d4ef41ff4ba92f95dea6cb82` |
| `airbrush` | 68,649 | `081a34720cbb7a1b6a7fdde4ac1bedb9fbf31f380885b07c80bc540bf38cc174` |

The new binary emits the **same four full-byte hashes**: **69/69** checks.
The oracle begins/commits native preset transactions, deliberately rolls
back the middle batch, verifies byte-exact retry, and compares every batch
against an uninterrupted second instance. An intentionally corrupted native
build swapping x/y in the buffered output exits **1**, with **four hash
failures**, and the correctly rebuilt binary restores 69/69.

## Reproduction and verification

Start from an already staged standalone checkout with the real native
extension loaded before editor startup. From the repository root:

```sh
source /path/to/tooling/setup-rust-env.sh
(cd native/drawing_brush && cargo fmt --check && cargo test --offline --locked --release --lib \
  && cargo clippy --offline --locked --all-targets -- -D warnings \
  && cargo build --offline --locked --release)
cp native/drawing_brush/target/release/libdrawing_brush.so \
  drawing/addons/drawing/native/bin/libdrawing_brush.so
python3 tools/build_drawing_app.py --in-place
godot --headless --audio-driver Dummy --path drawing \
  --script res://tests/t095_native_preset_packed_output.gd
python3 tools/check_godot_model_log.py /tmp/t095-native-preset-packed-output.log \
  --marker T095_NATIVE_PRESET_PACKED_PASSED
```

For strict log validation, redirect/tee the Godot command to the listed
log first. The on-demand workflow performs this automatically and preserves
raw logs on failure. The optional
`res://tests/t095_native_preset_packed_bench.gd` is a **native-call** profiler,
not an input-to-photon test.

### Local regression results (all exit 0, required marker where defined)

| Check | Outcome |
| --- | --- |
| New real Hokusai old/new signed output + rollback oracle | 69/69 |
| Prior Hokusai export-cache oracle | 81/81 |
| Native pigment rollback on GDScript source failure | 57/57 |
| NativeHard source rollback | 113/113 |
| NativeHard preflight, scanline and packed output | 28/28, 42/42, 20/20 |
| Native fallback with installed extension | 7/7 |
| Hokusai stub bulk source delta | 126/126 |
| Independent 60px Brush coverage | 32/32 |
| Rust unit tests, Clippy and format | 6/6; both checks clean |
| Xvfb four-preset integration, released-stroke navigation | 30/30, 48/48 |
| Xvfb 5×120 actual pointer-event Hokusai witness at 786%, 60px | Exit 0, marker `T095_NATIVE_PASSED` |

The 60px Xvfb pointer witness recorded **staging p95 291.413 ms** and
**release-to-commit p95 58.395 ms**, using software rendering. It is a
single build, **not a paired end-to-end performance comparison**.

## Native-only performance and limitations

The optional eight-trial 60px profiler times `preset_segments` only,
excluding brush configuration and GDScript preview/compositor work, and
verifies identical total pixel counts. Optimized / original / optimized /
original / optimized order was used (Godot 4.8b3, same VM):

| Preset | Optimized A | Original A | Optimized B | Original B | Optimized C |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hard | 11.126 | 10.008 | 7.484 | 10.687 | 7.750 |
| Soft | 8.938 | 7.582 | 5.297 | 7.915 | 5.773 |
| Ink | 6.296 | 5.509 | 3.821 | 5.763 | 3.921 |
| Airbrush | 10.229 | 9.623 | 6.920 | 9.626 | 7.205 |

Numbers are **per-run native-call median milliseconds**, not p95 or frame
timing. The first optimized run was slower than controls; later optimized
runs were faster. Run ordering and cold-system effects remain confounders,
so these data suggest a potential warmed native throughput improvement but
**do not prove end-to-end or real-device latency improvement**.

**Unverified:** hosted CI (only the workflow declaration was updated),
Windows hardware/export, real owner device GPU/driver pointer-to-photon
latency, responsiveness to the original minute-long backlog, and explicit
owner approval. T-095 stays `In Progress`, and T-096 remains separately in
`Manual Review`. Do not mark either Done based on these local tests.
