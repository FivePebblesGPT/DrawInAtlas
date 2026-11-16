# T-161 — sign-safe public Drawing anchors

**Date:** 2026-11-16 · **Branch:** `sprint/2026-11-15` · **Ticket:** [T-161](../Tickets/T-161.md), **Done locally**. Parent [T-148](../Tickets/T-148.md) remains **In Progress**; T-149/T-150 stay Blocked. Godot version is bundled **4.8 beta3** with the local real Hokusai/libmypaint Rust GDExtension. All results are local software-only verification; no hosted CI or T-095 owner/hardware acceptance is claimed.

## Failure and change

`DrawingDocument.begin_edit`, `DrawingRenderer.render` and `DrawingRasterImport.import_image` used `abs(anchor) > 2^60`. On this Godot beta, `abs(INT64_MIN)` is the same negative `INT64_MIN`, and the invalid input passes. Additionally, the renderer added `origin_x + view.position.x` **before** it checked the origin, so `INT64_MAX + 1` could wrap to `INT64_MIN` and also pass. In the old code, a 1px viewport could return a successful image from an impossible coordinate; gesture creation likewise returned a usable session for the extreme.

The updated `SignedTiles.document_anchor_in_range(x,y)` compares both signed axes against inclusive `±2^60` and is shared by all three APIs. The renderer validates the raw 64-bit origin *before* adding the 32-bit `Rect2i` position, and checks the translated world point again. These checks do not change the independent Godot consumer `±2^52` tile/pixel projection limit or relax native Rust authority. Existing historical non-native `±2^60` anchor endpoints remain accepted until Legacy is retired separately.

## Fail-first, native authority and compatibility

The **same** `drawing/tests/t161_signed_public_anchor_bounds.gd` was run before and after the source edit, after a successful standalone Godot editor import. Before the fix, it exited **1**: `T161_SIGNED_ANCHOR_RESULT checks=47 failures=7`. All seven failures were specific to negative signed 64-bit extremes on both axes in gesture, viewport and image import, plus viewport `INT64_MAX + 1`. After the fix it exited **0**: `T161_SIGNED_ANCHOR_PASSED checks=47 failures=0`. The regression starts with a real Hokusai Hard Round gesture and native Undo token. It tests signed `INT64_MIN`/`INT64_MAX`, ±(2^60+1) on both axes and an addition-overflow origin, then proves rejected calls preserve the document revision, pending dirty state, source tiles, native history token and exact Undo/Redo. It also checks both inclusive historical ±2^60 non-native gesture/view endpoints and a normal image-import local Undo/Redo.

## Final verification

| Check | Observed |
| --- | --- |
| T-161 real-native regression | **47/47**, exit 0, success marker |
| Pre-fix identical regression | **7 failures / 47**, exit 1 (expected) |
| Rust unit tests | **23/23**, exit 0 |
| rustfmt / strict Clippy / pinned offline release build | Pass, exit 0 |
| Native tile contract | **312/312**, exit 0 |
| T-154–T-160, external-source and native-history fixtures | Pass |
| Historical root signed-64-bit lazy-cache fixtures | Pass unchanged |
| Root Atlas/Object/text/detached history fixtures | Pass |
| Graphical Canvas under Xvfb/llvmpipe | **46/46**, zero tile pixel-stream FFI calls |
| Hokusai 96px 512² full-canvas graphical witness | **262,144/262,144** covered; one software-X11 trial `total_p95_ms=979.112`, `target_met=false` |
| Ticket store and CI YAML | **161 tickets valid**; parsed workflow |

**33/33 final suite invocations** report process exit 0 and explicit success markers for Godot fixture runs; raw logs are retained under [T-161 raw evidence](T-161-2026-11-16-public-anchors-raw/summary.tsv). The first attempted matrix invocation omitted the bundle's vendored Cargo config and used a Godot editor progress marker not present in this version; these were setup/marker errors, not Rust compilation or editor-import failures. The corrected Rust commands use `--config /mnt/data/work/t153-cargo-config.toml` pointing at the bundled vendored sources; all Rust builds/tests pass. The original console diagnostic is retained separately to avoid hiding the first-run issue. No change was made to the Rust implementation, and the T-095 physical-device latency gate is not evaluated by the single software trial.

## Reproduction

```bash
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --editor --import --quit --path drawing
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t161_signed_public_anchor_bounds.gd
python3 tools/validate_ticket_store.py
(cd docs/evidence/T-161-2026-11-16-public-anchors-raw && sha256sum -c SHA256SUMS)
```

[Raw run table](T-161-2026-11-16-public-anchors-raw/summary.tsv) · [pre-fix fail-first log](T-161-2026-11-16-public-anchors-raw/diagnostics/pre-fix-t161.log) · [checksum manifest](T-161-2026-11-16-public-anchors-raw/SHA256SUMS).
