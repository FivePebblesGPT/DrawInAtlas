# T-112 — Atlas Line/Polygon tests use the published portable generation

**Date:** 2026-11-12. **Baseline source:** clean local T-111 commit
`4bb8f2a116293211b708876dad93381d39e6561a` (PR #17 remote HEAD
`79b8959e9eac01b3bb10a144a46407acc6901aed`).
**Engine:** pinned `4.8.beta3.official.c51ff06e8` on Linux, headless and
Xvfb/Mesa llvmpipe for the Polygon visual neighbor. No physical-display
or hosted GitHub Actions result is inferred.

## Red control and cause

The unmodified Line and Polygon suites invoke `editor._on_save()` and then
`AtlasCampaignStore.load_campaign(editor.save_path)` (the retired one-file
`.scn` codec). Editor Save instead publishes a versioned portable root
`campaign.atlas.json` and staged sparse generations, not `campaign.scn`.
The original tests exited **1**: Line **126 checks / 1 failure**, Polygon
**68 checks / 2 failures**. They were previously (correctly) reported red;
they did not demonstrate a production Save failure.

## Narrow change and green control

The same tool gestures and Undo/Redo checks now call
`AtlasCampaignStore.load_portable_result(editor.save_path)` and require the
real Editor's successful-generation status, nonempty generation identity,
root file presence, **absence of a legacy head**, and exact metadata plus
Raster RGBA-chunk dictionary equality. After Save, Undo changes the live
source while the independently loaded generation remains unchanged.

The new Line suite exits **0 (128/128)**, Polygon exits **0 (70/70)**; both
pass T-094 strict raw-log verification. The existing source eligibility
(T-111), canonical composition (T-055), actual Editor portable Save/Load
(T-066), and native Polygon graphical neighbors also pass. No production
code or serialized format is modified. This repairs CI regression coverage
only; manual Line/Polygon interaction acceptance is still open.

## Commands and verification boundaries

```bash
GODOT=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$GODOT" --headless --audio-driver Dummy --path . \
  --script res://tests/line_smoke.gd > line.log 2>&1
python3 tools/check_godot_model_log.py line.log --marker ATLAS_LINE_PASSED
# Repeat for tests/polygon_smoke.gd with marker ATLAS_POLYGON_PASSED.
# Repeat for drawing_composition_smoke.gd, t111_line_release_authorization_smoke.gd,
# and campaign_bundle_editor_smoke.gd using each test's exact success marker.
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$GODOT" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path . --script res://tests/polygon_visual.gd
python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
```

Process exit codes below were captured independently; a printed marker alone
is never a pass. The T-055 composition test printed four **recognized,
retained post-exit Godot resource-leak diagnostics**, which the strict log
checker classified; no claim of clean teardown is made.

| Retained log in `docs/evidence/raw/T-112/` | Test | Process exit | SHA-256 |
| --- | --- | ---: | --- |
| `line_old_loader_red.log` | T-111 old Line suite | 1 | `9642ec6e7605c139544711ee67efa9df039264dce93524a91833acf8953d9e25` |
| `polygon_old_loader_red.log` | T-111 old Polygon suite | 1 | `07678e61a91f67789df19ee08394c3bedbf5d19e49fdee39aad32e23c1808d81` |
| `line_smoke.log` | T-112 portable Line | 0 | `298289bd4fb0b6b6a4f357ff052b649a604fe4f10390282b7103212c622b6346` |
| `polygon_smoke.log` | T-112 portable Polygon | 0 | `c0dcf8edf9000de5db4318d412e7e19c1c0fa43b3e4610b077941dabc433e282` |
| `drawing_composition_smoke.log` | Atlas canonical composition | 0 | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `t111_line_release_authorization_smoke.log` | Line release eligibility | 0 | `9fe0c8a2405e654de5618e48303a58f3a739f1363b10fd77a52669b2c087c43e` |
| `campaign_bundle_editor_smoke.log` | Native Editor portable Save/Load | 0 | `572fb6d280fe102cb84c1f8f29124db09da2899be38efcbb986b7fcca6adef3d` |
| `polygon_visual.log` | Xvfb/Mesa Polygon pointer+framebuffer | 0 | `12b316990582bd359fa61f1958bf9df1f3737db7537657b781f6ae781c6b3438` |

Both new tests were run with the same pinned executable as their baseline
negative controls; only the test assertions and workflow/docs changed.
All six green process logs had exit code **0** and strict verifier exit code
**0**. The two old-loader negative controls exited **1** by design.

**Integration:** existing required check
`ci_14_verify_t_055_atlas_canonical_drawing_composition_and_input` now
executes Line and Polygon under separate timeouts and exact-marked raw logs;
**46/46 expected required CI check IDs remain present**. The fast workflow
was not run on GitHub for this local commit. Local indexed CI and source
typing checks do not satisfy any owner/physical-device review gate.
