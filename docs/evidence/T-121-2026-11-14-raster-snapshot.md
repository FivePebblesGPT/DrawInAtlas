# T-121: one validated byte snapshot per raster Open

**2026-11-14.** Local Linux x86-64, pinned Godot `4.8.beta3.official.c51ff06e8` (bundle 8), Xvfb/Mesa OpenGL Compatibility software renderer, branch `sprint/2026-11-14`. Remote baseline for delivery: `5b9bf460d111b11035fc71ac927a86346c5d8dd7`; prior local T-120 commit `b835781502d27360943fbe4de7d9210bcb6148e9` is **not** on that remote branch. Record the final new commit SHA once committed, rather than treating this in-progress source as a remote push.

## Defect and correction

Pre-T-121 `addons/drawing/workspace.gd` opened a filesystem `FileAccess`, read only 16 bytes and the encoded length, closed it, and called `Image.load_from_file(path)` again. Replacing the file between these two reads could cause the imported image to differ from the file whose header and byte limit were checked. Merely checking the extension did not guarantee the decoder saw those same bytes.

The new `DrawingRasterImport.load_file_image(path)` reads one bounded full input buffer with an exact read-length check. `decode_image_bytes` applies magic-byte checks and dispatches Godot PNG/WebP/JPEG memory decoders, then validates dimensions, before the shared workspace constructs a document. This preserves T-120's File→Open dispatch, original image immutability, supported extensions, and straight-RGBA8 sparse tile conversion; native `.drawing` uses its original `DrawingFileIO` path. A minimum-length PNG preflight rejects header-only corrupt input without emitting decoder errors to strict CI. The static Python contract enforces no `Image.load_from_file(path)` or second `FileAccess.open` in the workspace raster-opening path.

## Baseline-negative control

New `tests/test_t121_raster_snapshot.py` was run against the untouched T-120 implementation before source modifications: **2 FAIL + 1 ERROR** of three contract tests (no one-snapshot dispatch, no loader, no CI oracle). This is a source contract red control, **not** a claimed deterministic filesystem-race reproduction. The new 24-check Godot model verifies an immutable captured PNG byte buffer after the corresponding disk file is replaced with a different pixel image; a fresh loader request sees only the newer bytes. It also checks uppercase extension, PNG type spoofing, header-only corruption, WebP/JPEG equivalence with `Image.load_from_file`, oversize encoded and decoded image rejection, missing sources, ordinary workspace framing/pixels and failure rollback.

## Reproduction

From the repository root, with the pinned bundle's `godot` and Xvfb installed:

```bash
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/t121_raster_snapshot_smoke.gd > /tmp/t121.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t121.log --marker T121_MODEL_PASSED
godot --headless --path drawing --script res://tests/t120_unified_open_smoke.gd > /tmp/t120.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t120.log --marker T120_MODEL_PASSED
godot --headless --path drawing --script res://tests/object_discovery_smoke.gd > /tmp/t093.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t093.log --marker T093_MODEL_PASSED
godot --headless --path drawing --script res://tests/topbar_overflow_smoke.gd > /tmp/t090.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t090.log --marker T090_OVERFLOW_PASSED
T120_SCREENSHOTS=/tmp/t121-captures xvfb-run -a --server-args='-screen 0 2200x1500x24' \
  godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t120_file_object_native.gd > /tmp/t120-native.log 2>&1
python3 tools/check_native_t120_log.py /tmp/t120-native.log
python3 -m unittest discover -s tests -p 'test_t120_unified_open.py' -v
python3 -m unittest discover -s tests -p 'test_t121_raster_snapshot.py' -v
python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v
python3 tools/validate_ticket_store.py
```

**Results:** T-121 model **24/24**; T-120 model **34/34**; T-093 **56/56**; T-090 **32/32**; T-120 native software-X11 **24/24** including four framebuffer captures; Python T-120 **5/5** and T-121 **3/3**; strict explicit types **429 scripts / 33 skill documents**; clean Drawing and independent consumer **3/3** when `godot` is in `PATH`. All model/native logs passed their strict respective checkers. The import step was run **after** final staging to avoid spurious SVG loader errors from an ignored `.godot` cache that staging can remove.

The T-121/T-120/T-093/T-090 headless logs each retain **four** recognized *post-PASS* Godot resource-leak diagnostics. T-120 native retains **21** recognized *post-PASS* texture/RID leak diagnostics. These are not silently ignored or fixed, and pre-PASS script/engine errors remain failures. An intentional malformed-PNG test initially triggered real engine decoder ERROR lines before success; it was corrected to test rejection via minimum-length header preflight, **not** to relax the strict verifier. The resulting final pre-PASS logs contain no such errors.

**Not run:** hosted CI on a pushed candidate SHA, concurrent same-file writes during a single kernel read, Windows/macOS, physical GPU/stylus, owner usability or measured file-I/O speedup. No new native dependency or project schema was introduced.
