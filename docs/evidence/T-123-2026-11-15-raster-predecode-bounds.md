# T-123 — reject oversized raster dimensions before decoder allocation

**Date:** 2026-11-15. **Base:** `sprint/2026-11-14`, local parent
`6ffe987e71a6379b1a439ca87c9db501debfebc1` (T-122 still unpushed),
remote baseline `61c6f689974a848f8a7cc4040c98be418518b156`.
**Engine:** supplied bundle 8 `Godot_v4.8-beta3_linux.x86_64`, reporting
`4.8.beta3.official.c51ff06e8`. Python 3; Linux headless and Xvfb/Mesa
software Compatibility renderer. Tests do not measure real hardware latency.

## Defect and failing control

The T-121 decoder acquired one 64-MiB-capped byte snapshot, checked only the
PNG signature/WebP RIFF marker/JPEG SOI marker, then called the Godot codec.
Only *after* that allocation did it reject decoded dimensions beyond 4096px
per side or 16,777,216 pixels. An encoded cap alone does not bound the
uncompressed pixel count of a highly compressible raster.

A new fail-first Godot oracle was staged against the unmodified T-121 runtime:

```sh
python3 tools/build_drawing_app.py --in-place --without-native
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing \
  --script res://tests/t123_raster_predecode_bounds_smoke.gd
```

**Negative control:** exit **1**, **14 of 42 assertions failed**, including
oversized PNG widths/heights, WebP VP8/VP8L/VP8X dimensions and JPEG SOF,
invalid IHDR/VP8 signature/JPEG segment metadata. The pre-change source
returned DECODE or called codecs instead of rejecting from bounded headers;
several deliberately incomplete WebP frames emitted decoder errors. This
asserts an unsafe ordering, **not** a demonstrated OOM or a claimed
reproduction of a gigapixel allocation.

## Implemented guard

- `DrawingRasterImport._declared_dimensions` reads PNG IHDR, WebP RIFF's
  VP8/VP8L/VP8X first image chunk, or JPEG marker segments through the first
  SOF. It checks marker and chunk lengths against **the same captured bytes**,
  rejects zero/oversized geometry, and never decodes an image when preflight
  fails. Direct byte-decode callers also observe the 64-MiB input cap.
- Existing Godot `load_png_from_buffer` / `load_webp_from_buffer` /
  `load_jpg_from_buffer` remain the authoritative decoders of legal input,
  with post-decode dimension equality enforced. Neither the DrawingDocument
  transaction nor `.drawing` save schema changed.
- T-120's `Image header is invalid` error text is preserved on bad PNG data.
  An initial neighbor run caught that wording mismatch (**33/34**); the
  corrected runtime passed **34/34** without changing the historical test.
- New Godot smoke + Python contracts are in the existing T-093 required CI
  step. Required CI **step-ID inventory stays 46**; strict fail-late log
  verification and the T-107 pinned historical replay are unchanged.

## Local passing tests

Commands run with the supplied beta3 `godot` binary; headless model logs were
checked by `tools/check_godot_model_log.py` with the exact stated marker.

| Gate | Result |
| --- | --- |
| `drawing/tests/t123_raster_predecode_bounds_smoke.gd` | **41/41**, `T123_MODEL_PASSED`, exit 0, strict log pass |
| `drawing/tests/t120_unified_open_smoke.gd` | **34/34**, `T120_MODEL_PASSED`, exit 0, strict log pass |
| `drawing/tests/t121_raster_snapshot_smoke.gd` | **24/24**, `T121_MODEL_PASSED`, exit 0, strict log pass |
| `drawing/tests/object_discovery_smoke.gd` | **56/56**, `T093_MODEL_PASSED`, exit 0, strict log pass |
| `drawing/tests/t120_file_object_native.gd` | **24/24** with four framebuffer captures, Xvfb/Mesa, `T120_NATIVE_PASSED`, exit 0, strict native log pass |
| `test_t123_raster_predecode_bounds.py` | 4/4 |
| `test_t120_unified_open.py` / `test_t121_raster_snapshot.py` / `test_t093_object_discovery.py` | 5/5 + 3/3 + 3/3 |
| `test_drawing_app.py` / `test_drawing_contract.py` | 3/3 + 7/7, including fresh independent staged Godot consumers |
| `test_t090_responsive_workspace.py` | 9/9 |
| `test_godot_ci_fail_late.py` / `test_godot_ci_order.py` | 8/8 + 1/1 |
| `test_t107_evidence_audit.py` / `test_t094_owner_matrix.py` / `test_t094_ci_replay.py` | 10/10 + 4/4 + 14/14 |
| `test_t094_godot_model_log.py` | 24/24 |
| `tests/check_explicit_types.py` | 430 project scripts and 33 skill docs audited |
| `tools/validate_ticket_store.py` | All **123 tickets** and closure dependencies valid |

Representative commands:

```sh
python3 tools/build_drawing_app.py --in-place --without-native
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/t123_raster_predecode_bounds_smoke.gd \
  > /tmp/t123-model.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t123-model.log --marker T123_MODEL_PASSED
python3 -m unittest discover -s tests -p 'test_t123_raster_predecode_bounds.py' -v
GODOT_AUDIO_DRIVER=Dummy xvfb-run -a -s '-screen 0 1280x800x24' \
  godot --audio-driver Dummy --path drawing --rendering-method gl_compatibility \
  --script res://tests/t120_file_object_native.gd > /tmp/t120-native.log 2>&1
python3 tools/check_native_t120_log.py /tmp/t120-native.log
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

The first native run had **20/20 application assertions** but its strict
checker flagged an unrelated *startup* ALSA `ERR_CANT_OPEN` in this container.
Running the exact test with Godot's explicit `--audio-driver Dummy` yielded
**24/24** including the four optional framebuffer captures and passed the
strict verifier. No log suppression or broad exception was added. Known
**post-success** Godot RID/texture leaks remain reported and classified
separately (four headless diagnostic groups, 20 native groups).

## Boundaries and remaining work

This fix rejects out-of-budget *declared* raster dimensions before decoding;
it is not a formal worst-case CPU/transient-memory guarantee for the decoders
of in-budget images. Single-file reads still lack atomicity against writes to
the same open inode. Hosted GitHub CI has not been rerun on this local commit.
Physical Windows/Linux owner acceptance, T-056/T-059 UX signoff, and the
T-095/T-068 latency/native evaluation are unaffected.
