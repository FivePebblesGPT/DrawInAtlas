# T-164 — signed image-import extent preflight

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` ·
**Ticket:** [T-164](../Tickets/T-164.md), Done locally. T-148 remains In
Progress; T-149 is blocked, and T-095 requires independent reference-device
measurement and owner review. Runs use the Godot 4.8 beta3 bundle,
the real Rust/Hokusai GDExtension and software-X11; hosted CI was not run.

## Defect and scope

`DrawingRasterImport.import_image` already checked the starting signed image
anchor against inclusive `±2^60`, but not the image's *last* pixel. As a
result, importing a 2×2 image at `(+2^60, 0)`, `(0, +2^60)` or at both
positive edges passed the anchor test and could publish pixels beyond the
public document limit. This was not a native brush defect: it affects the
non-Brush image raster producer and can reach lazy source resolution and
edit/history publication before any error.

The guard now checks `(left + width - 1, top + height - 1)` after the existing
safe first-anchor/pixel-budget checks, before image duplication, decoding,
source resolution or `begin_edit`. Those prior bounds make i64 addition safe.
Overhangs fail `COORD_RANGE` without document mutation. Imports entirely
inside either signed endpoint still work on non-native historical documents,
whereas a previously attached native store retains its stricter `±2^52`
publication boundary. The patch does not change the Hokusai ABI, rasterizer,
shared revision protocol, or historical coordinate policy.

## Fail-first control and positive witness

`drawing/tests/t164_image_import_extent_bounds.gd` was executed **before**
restaging the modified source into the standalone Drawing project (the
unmodified T-163 `raster_import.gd` was still staged). Process exit **1**,
`T164_IMAGE_EXTENT_RESULT checks=26 failures=10`: five intended rejection
checks and five source/revision/dirty/history isolation checks failed across
non-native and native documents. The test was corrected once for a test-only
API typo (`read_pixel64` → `read_pixel`) **before** saving the included
negative-control log; the implementation was still untouched. It was then
run with the updated staged import module: exit **0**,
`T164_IMAGE_EXTENT_PASSED (26 checks; 0 failed)`.

The fixture exercises positive overflow on each axis, joint positive
endpoints, invalid negative starting anchors, successful 2×2 imports at
positive `+2^60` *last* pixels and negative `-2^60` *first* pixels,
real-native Hokusai stroke/history token survival, same revision/display
source epoch/dirty/history and source-resolution counters after rejected
imports, canonical Rust tile-byte preservation, and exact local/native
Undo/Redo. Its historical non-native image endpoint checks ensure this is
not a premature T-150 Legacy retirement.

## Final verification matrix

| Check | Observed |
| --- | --- |
| New T-164 fixture | **26/26**, exit 0, explicit success marker |
| Pre-fix control | **10/26 failed** as expected, exit 1 |
| Offline pinned Rust unit tests | **24/24**, pass |
| rustfmt, strict Clippy, release build | Pass |
| Existing T-154–T-163 / native tile/source/history contracts | Pass, including **312/312** native tile assertions |
| Existing sparse clipboard capture/paste, signed public anchors | Pass |
| Atlas/Object, detached history, text and root tile-cache regressions | Pass |
| Graphical Canvas cutover (software X11) | **46/46**; pass |
| 96px Hokusai 512×512 fill witness (software X11) | **262,144/262,144 pixels**; single-run `total_p95_ms=357.555`, `target_met=false` |
| Ticket store and required-native workflow YAML | **164 tickets valid**; YAML parses |

**39/39 final invocations passed** with process exit 0 and expected positive
markers. See [per-command summary](T-164-2026-11-16-image-extents-raw/summary.tsv),
[raw logs](T-164-2026-11-16-image-extents-raw/), and their verified
[SHA-256 manifest](T-164-2026-11-16-image-extents-raw/SHA256SUMS).
The 357.555 ms X11 run is a single software measurement, not physical
input-to-photon p95 and **not** T-095 acceptance. This narrow child does not
complete T-148's native ownership, unblock T-149 or establish hosted CI green.

## Reproduction

```sh
source /mnt/data/archive_unpacked/godot_bundle/setup-rust-env.sh
export CARGO_TARGET_DIR=/mnt/data/work/cargo-target
cargo test --manifest-path native/drawing_brush/Cargo.toml --locked --offline --lib --config /mnt/data/work/t153-cargo-config.toml
cargo clippy --manifest-path native/drawing_brush/Cargo.toml --all-targets --locked --offline --config /mnt/data/work/t153-cargo-config.toml -- -D warnings
cargo build --manifest-path native/drawing_brush/Cargo.toml --locked --offline --release --config /mnt/data/work/t153-cargo-config.toml
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy --path drawing --script res://tests/t164_image_import_extent_bounds.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-164-2026-11-16-image-extents-raw && sha256sum -c SHA256SUMS)
```

The Godot executable and offline Cargo config are supplied with the
corresponding development bundle; project exports and hosted CI were not run.
