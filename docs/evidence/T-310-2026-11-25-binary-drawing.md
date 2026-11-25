# T-310 — binary Drawing storage evidence (2026-11-25)

Base implementation `e33c204b`, pinned Godot `4.8.beta4.official.b070e63b1`
and required native Rust extension, Linux x86_64 software-display environment.
No UI design changed. The actual native File/Object and linked-source pointer
regressions were exercised; this is not owner, Windows, physical GPU or hosted
CI signoff.

## Reproducible measurements

`drawing/tests/t310_binary_drawing.gd` generates deterministic synthetic
fixtures rather than relying on unavailable user drawings. Sparse: 64 unique
128×128 tiles, two nonzero samples each (including hidden RGB). Dense: 64
128×128 tiles, seeded uniformly random RGBA8 (4 MiB). Layer-heavy: 16 sparse
128×128 tiles, 303 layers including root, artwork, ink, 96 groups, 96 blank
raster layers, 96 Object layers and 12 editable text layers with the same
licensed italic font; includes hidden and locked layers. The original JSON
codec is selected explicitly by the legacy option in the same build. Each
pair uses a fresh process, five warm-source Save/Open trials, full manifest
and pixel equivalence after each Open. Save/Open medians include synchronous
encoding/decoding, validation and filesystem I/O; GNU time process peak RSS
includes Godot startup, native extension, fixtures, validation and five trials,
not isolated allocator peak or a physical hardware performance guarantee.

| Fixture | Codec | File bytes | Save median ms | Open median ms | Peak RSS KiB |
|---|---|---:|---:|---:|---:|
| Sparse | JSON | 5,608,721 | 75.267 | 155.092 | 236,240 |
| Sparse | Binary | 6,088 | 16.155 | 32.344 | 174,392 |
| Dense | JSON | 5,608,720 | 78.458 | 151.445 | 236,396 |
| Dense | Binary | 4,206,021 | 34.967 | 52.537 | 181,616 |
| Layer-heavy | JSON | 2,456,578 | 30.543 | 70.196 | 196,908 |
| Layer-heavy | Binary | 344,641 | 16.333 | 27.177 | 171,192 |

Measured savings: 99.89%, 25.01% and 85.97% respectively. Dense noise is
intentionally incompressible; its improvement mostly removes base64 overhead.
Sparse reduction is data-dependent, not a claim every real drawing shrinks
99.89%. Whole-payload compression is a simple reversible default selected
for this measured workload; it uses temporary buffers and cannot random-access
individual tiles. The format uses raw fallback rather than inflating noisy
content. No lossy pixel quantization was used.

```sh
make test-binary-drawing TOOLCHAIN=system
# After import, using the same pinned Godot:
for fixture in sparse dense layers; do
  for codec in legacy binary; do
    /usr/bin/time -f 'MAX_RSS_KIB=%M' godot --headless --path drawing \
      --script res://tests/t310_binary_drawing.gd -- "$fixture" "$codec"
  done
done
```

## Verification

Fail-first: a standalone SceneTree constructed a `DrawingDocument` (stride
16), called `DrawingFileIO.save`, then checked `get_file_as_bytes(path).slice(0,8)`
against `DIADRAW2`. All four touched staged package dependencies restored to
`e33c204b` produced `binary=false`, exit 1, with no compilation failures;
corrected package produced `binary=true`, exit 0. The signature assertion is
also retained in `standalone_smoke.gd`.

`make test-binary-drawing TOOLCHAIN=bundle BUNDLE=<supplied bundle>` passed
307/307 checks, with strict log marker and mandatory native extension readiness.
Tests cover actual file signature, sparse/deduplicated payloads, signed tile
positions, hidden RGB, exact editable text/rotation/font and semantic object
records, old JSON reading and explicit conversion, corrupt/truncated/oversize
file and expansion limits, unknown versions, extra Variant bytes, nonportable
objects, missing/invalid chunks and fonts, atomic staging failures and retry,
Object identity/frame, and the linked-source expansion budget. All six benchmark
processes also passed their exactness assertions (four × 138, two × 282).

Adjacent successful tests: standalone 43/43, Object Editor UI 26/26,
T-065 real legacy I/O 49/49, Asset Browser 79/79, transfers 43/43, thumbnails
62/62, T-148 document tile publication 56/56, persistent native document 44/44,
metadata native revision 61/61, external raster adoption 28/28, Drawing text
60/60, world mapping 125/125, Atlas Object assets 95/95, portable registry
33/33, Atlas native tile history 43/43, native linked drag/drop 40/40, native
File/Object 21/21. Transfer initially failed because a copied file was still
required to be UTF-8; replaced that check with the captured-byte envelope
parser. The legacy-only T-065 I/O benchmark deliberately retains its JSON
fixture; the Object UI damaged-frame fixture now alters the binary envelope.
The old T-120 graphical witness initially failed a fixed total menu count
(before Text was added); the actual independent File/Object labels and
pointer behavior are now asserted instead. The rerun passed.

Source format and limitations: [Drawing file format](../DRAWING_FILE_FORMAT.md).
T-148/T-149 authority and T-059/T-250 owner gates remain open. No physical
hardware, Windows, hosted CI or arbitrary third-party Godot version validation.
