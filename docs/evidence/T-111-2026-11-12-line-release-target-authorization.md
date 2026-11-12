# T-111 — Line release uses live Resource authorization (2026-11-12)

## Revision and one-ticket boundary

- Baseline: local clean T-110 commit `a78440042a8235f20765ba04df6d9156cfcf70f6`; original Canvas blob `5fb34f77fe8fc059696848732ce00247e95c5ec2`.
- Candidate Canvas blob: `333f152138e8dd20a01c4250cccddb50e352e53b`. Both runs reused the same checkout and
  `tests/t111_line_release_authorization_smoke.gd` bytes. No remote push or
  hosted CI was attempted; PR #17's last confirmed remote HEAD is
  `79b8959e9eac01b3bb10a144a46407acc6901aed`.
- Engine: pinned `4.8.beta3.official.c51ff06e8`, Linux/headless and
  Xvfb/Mesa llvmpipe GL Compatibility (`--audio-driver Dummy`). This is
  software-rendered interaction evidence, not owner-device approval.

## Defect and resolution

At pointer-down the Atlas Line captured map/floor/layer *IDs* and an exact
`AtlasEditScope` copy. A lock, visibility change, different presented detail,
or replacement Resource reusing the same ID did not invalidate that snapshot.
The release guard could emit `stroke_requested` under a target no longer
eligible for a paint gesture, possibly changing source and creating history.

The change captures typed `AtlasMapDocument`, `AtlasFloor` and
`AtlasRasterLayer` references at press. Release requires the **same** live
objects, the same current active layer, editability, presentation and the
exact copy of the edit mask. Invalid releases follow the existing
`cancel_edit()` + `line_rejected` path without publishing pixels/history;
ordinary unchanged release keeps the existing one-step Undo/Redo. No API,
format, default style, snapping or user-facing policy decision changes.

## Reproduction and regression commands

```bash
GODOT=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
# Save candidate Canvas, restore exact T-110 Canvas from Git, then run:
git show a78440042a8235f20765ba04df6d9156cfcf70f6:scripts/interface/canvas.gd > scripts/interface/canvas.gd
timeout --signal=TERM --kill-after=5s 120s "$GODOT" --headless --path . \
  --script res://tests/t111_line_release_authorization_smoke.gd
# Restore saved candidate Canvas and run the same command; check the log:
python3 tools/check_godot_model_log.py <candidate-log> \
  --marker T111_LINE_GATE_PASSED
# Existing real-pointer graphical Line witness:
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  xvfb-run -a "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/line_visual.gd
python3 tools/check_godot_model_log.py <visual-log> \
  --marker ATLAS_LINE_VISUAL_PASSED
python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
```

The original Canvas **exited 1**: `T111_LINE_GATE_FAILED (49 checks, 20
failures)`. The candidate **exited 0** and passed **49/49** plus the strict
log verifier (exit 0). The six changed-authority fixtures are: mid-drag lock,
hide, detail-level move, same-ID raster replacement, same-ID floor replacement
and same-ID map replacement. The test also checks detached preview, absence of
stroke emission, rejected history, cleanup, fresh valid release and exact
Undo/Redo. The Xvfb Line witness passed **20/20** and strict verification;
Atlas canonical composition passed **89/89** with four known post-success
Godot leak diagnostics retained. Bucket neighbor passed **50/50**.

## Retained failures and limitations

The older `tests/line_smoke.gd` emits `ATLAS_LINE_FAILED checks=126
failures=1` on **both** the unmodified T-110 Canvas and the T-111 Canvas:
`native save roundtrip preserves line` fails. Their retained raw logs have
identical SHA-256. Thus this is **not** counted as a passing neighbor, but
also is not introduced by this change. The existing `polygon_smoke.gd` also
fails its two native-save checks on this beta3 local environment; these
broader save issues require their own investigation. The T-111 candidate's
focused history/pixel oracle and native visual test pass independently.

This narrow release-authorization ticket is Done with `manual_review: false`;
**T-024 remains Ready**, with its owner endpoint/constraint/style/cancellation
interaction choices expressly unapproved. There is no Windows/device input
validation, no owner approval, no hosted candidate result and no claim of
complete Atlas legacy authoring-suite health. Required CI still has 46 IDs.

## Retained raw logs and SHA-256

Every successful Godot log also had a process exit code of 0. Both the new
model and graphical logs passed the exact T-094 verifier (exit 0).

| Log | Scope | Process exit | SHA-256 |
| --- | --- | ---: | --- |
| `original-source-negative.log` | T-110 Canvas, 49-check negative control | 1 | `50662e6ee38a7d4924abf6f105121b78f0557ec34064b0af5589ed13ceda1bbc` |
| `candidate-headless.log` | T-111 candidate, 49-check authoring oracle | 0 | `8032edddf153bbcce750a6e3297b8d92b025e1173a85e3d2730c7a0ea4b8ad5a` |
| `candidate-xvfb-line.log` | Xvfb/Mesa real-pointer Line framebuffer witness | 0 | `2d29e49fd56bd3ebcb1ca2946dec82bf86ba0bf0318ceafc2f82cf49510ed23c` |
| `candidate-composition.log` | Atlas T-055 composition neighbor | 0 | `fe1f9bc3ab98816d73b5b9ad629082f6831e268b769e425fff4a8b21924e404c` |
| `candidate-bucket-neighbor.log` | Bucket neighbor | 0 | `31303fff9f8f0a2e4f629a1e3fa3aeec342dda455cddc502815b4a26ef2298d7` |
| `original-legacy-line-save.log` | T-110 baseline Line legacy Save/Open test | 1 | `86160af48e5f02edac773cb281e4267216d50ae978a344b1ca9fe2749439cf31` |
| `candidate-legacy-line-save.log` | T-111 candidate Line legacy Save/Open test | 1 | `86160af48e5f02edac773cb281e4267216d50ae978a344b1ca9fe2749439cf31` |
| `candidate-polygon-save.log` | Polygon neighbor Save/Open | 1 | `91b5bc459234d12d8b38b0c06738b8dae2c2f940ec72d9c26d5ae5b4c9cdc238` |
