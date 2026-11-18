# T-202 — native-safe signed campaign-save fixture

**Date:** 2026-11-19. **Base:** PR #21 `9aa1cbe0` with six locally applied
handoff commits ending at `8dd0c256`; changes are not pushed. Godot
`4.8.beta3.official.c51ff06e8`, Linux x86_64, native Hokusai GDExtension
already registered; root and standalone Drawing test projects. This is a
local model/native integration witness, not hosted CI or physical testing.

## Reproduction and fail-first

```
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --path . \
  --script res://tests/campaign_bundle_smoke.gd
```

Before the repair: exit **1**, `ATLAS_BUNDLE_FAILED (74 checks, 1 failures)`.
The failing assertion demanded that the authored `(2^53+1, -2^53-1)` pixel
be persisted; actual `DrawingDocument.export_manifest()` returned
`Raster source outside safe signed projection bounds`. The failure was
**not** a codec corruption or a loss of stored data. See `fail-first.log`.

After the repair: exit **0**, `ATLAS_BUNDLE_PASSED (91 checks, 0 failures)`.
A generated sparse pixel `(edge, -edge)` where
`edge = SignedTiles.MAX_PROJECTION_PIXEL_COORD - 2 * tile_stride - 1`
is saved, reopened, and compared against the exact 0-alpha hidden-RGB value.
A separate later attempt to edit `(2^53+1, -2^53-1)` remains representable
in the non-native direct in-memory model but **cannot be saved**: `COORD_RANGE`,
unchanged published root string, dirty source and old generation pixel
preserved. The subsequent original corruption and missing-blob tests still
pass. This does not prove generic safe `int64` raster persistence outside
`±2^52`; such publication is explicitly forbidden by T-158/T-159.

## Direct validation (recorded process exits)

| Run | Exit | Passed checks |
| --- | ---: | ---: |
| Root campaign bundle, repaired | 0 | 91/91 |
| Root campaign editor bundle | 0 | 23/23 |
| Root Atlas storage | 0 | 77/77 |
| Standalone T-158 native signed lazy tiles | 0 | 24/24 |
| Standalone T-159 native signed replay | 0 | 39/39 |
| `make python-test` (7 suites) | 0 | 56/56 |
| `test_t071_storage_docs.py` | 0 | 8/8 |

All scripts used the supplied Godot executable, `--headless`, existing
compiled native library and project-specific paths. The command/output
records and process codes are retained in
[raw evidence](T-202-2026-11-19-signed-save-fixture-raw/); compare
`fail-first.log`, `final-bundle.log`, and `exits.tsv`. The timing lines in
these fixtures are same-machine diagnostic prints, **not** latency evidence.

## Scope limit

Only a test fixture and its ticket/CI handoff documentation change. No
native source, on-disk schema, compositor, brush, clipboard or source RGBA
contract was modified. The future hosted fast-desktop replay (T-106),
official native export/Windows coverage (T-180/T-105), and owner/hardware
review remain outstanding. Git mailbox verification is recorded at handoff.
