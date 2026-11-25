# T-289 — preflight flood-fill geometry and RGBA8 before lazy I/O

**Runtime:** Linux x86-64, official Godot 4.8.beta4 `b070e63b1`, bundled
Rust-backed `DrawingNativeTiles` extension, `sprint/2026-11-23-godot-beta4`.
Remote `main` baseline `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
No hosted CI or physical-device/owner acceptance is claimed.

## Fail-first and repair

Initially `flood_fill()` resolved the seed's lazy chunk even if `_stage()`
would reject its view-relative coordinate or unsigned RGBA8. The native
witness `tests/t289_fill_preflight.gd` registers **two real lazy blobs**:
valid `(0,0)` and invalid-but-registered global tile `(67108864,0)`.
Against the original method the witness exited 1 with **13 failures/23**:
out-of-range source loading, incorrect absent-seed error, invalid-color
source fetch, materialized tile, and violated fetch count on retry.

Production change: the method checks its seed against `_stage()`'s strict
`-1073741824 < x,y < 1073741824` and checks `0 <= rgba <= 0xffffffff`
*before* `_fill_source_pixel()` or materialization. The valid case still
sees one source read, exactly one native transaction, untouched source prior
to publication, and exact hidden-RGB Undo/Redo.

## Execution

From repository root, with the bundled executable:

```bash
G=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$G" --headless --path . \
  --script res://tests/t289_fill_preflight.gd
python3 tools/check_godot_model_log.py /mnt/data/t289-required-ci.txt \
  --marker T289_FILL_PREFLIGHT_PASSED
python3 -m unittest discover -s tests -p 'test_t289_fill_preflight_ci.py' -v
python3 tools/validate_ticket_store.py
```

| Check | Result |
| --- | --- |
| Before native fixture | Exit 1; 13 failures / 23 assertions |
| Corrected native fixture | Exit 0; **23/23** |
| Required-CI strict log gate | Pass; exact marker and no runtime error |
| Native fill frontier | **56/56** |
| Native lazy fill tile cache | **39/39** |
| Native verified mixed-stage fill | **36/36** |
| Native publication cache | **30/30** |
| Python required-CI inventory | **1/1** |

Raw text output is retained under
[`T-289-2026-11-23-fill-preflight/`](T-289-2026-11-23-fill-preflight/).

## Limits

This changes no display or panel layout, so visual owner acceptance is
irrelevant to this bounded validation milestone. Native authority over all
raster producers, required fast-desktop GitHub CI, physical input-to-frame
latency, Windows releases, and the owner T-250 review remain independent
and explicitly **unapproved**.
