# T-113 — Same-ID Bucket preview release authorization

**Date:** 2026-11-12. **Repository baseline:** local T-112 commit
`32a6647de4543c3a7b7ab51b8769d932db578d8b`, with remote PR #17 last
confirmed at `79b8959e9eac01b3bb10a144a46407acc6901aed`. **Engine:**
Godot `4.8.beta3.official.c51ff06e8`, Linux x86-64, native Dummy audio and
Xvfb/Mesa llvmpipe for the real pointer witness. No hosted CI, physical
input-to-photon or owner UX result is inferred.

## Failure mechanism and exact negative control

The T-112 `AtlasArtworkEditor.commit_preview_fill()` checked only map/floor
**IDs**, active layer ID, selected-mask equality and the original raster
`to_dict()` snapshot. A new map or floor Resource with the **same** IDs and
pixel/metadata bytes therefore passed the preflight even when it had replaced
the original in the campaign. The subsequent `AtlasLayerEdit` resolved its
target by ID and committed to the changed registry, contaminating the new
source and appending history after an unauthorized press.

The independent `tests/t113_bucket_resource_identity_smoke.gd` keeps one
isolated live Atlas Editor and stages a detached fill before each of five
registry/target changes:

1. Replace the registered floor **and** the Canvas floor with a different
   same-ID, same-byte Resource.
2. Replace the registered map **and** Canvas map/floor with the equivalent map.
3. Replace the registered map but leave Canvas pointing at the original map.
4. Replace the map's registered floor but leave Canvas pointing at its former
   floor.
5. Replace the campaign owner referenced by the Canvas while preserving the
   same map and floor Resources.

After each release the oracle compares the target's complete serialized
source, verifies the exact Undo-command identity, and requires the preview to
be discarded. A fresh authorized fill after restoring the original graph
must still commit and roundtrip exact raster bytes through one Undo/Redo.
The test creates no production source files and uses no texture timing
assertions.

**Red:** the test run against the exact original T-112
`scripts/interface/artwork_editor.gd` blob
`59535f41b3eff5bfb998103c4b81cfba65adfd90` exits **1**, failing
**10/29** assertions (source and Undo protection for all five cases). All
unrelated positive controls remain passing. This is not a success-marker pass.

**Green:** the candidate source blob
`82a5e381590593fc876836c329913f95b1a15f95` exits **0** and passes
**29/29**. The strict verifier accepts its exact
`T113_BUCKET_PASSED: 29 checks` marker, with no unrecognized errors.

## Minimal implementation

The pending preview now stores the live campaign, map and floor Resource
references in addition to the existing IDs, source dictionary, and immutable
mask. Before release the editor requires the **same** Resource objects and
requires `campaign.get_map(map_id)` and `map.floor_by_id(floor_id)` to still
resolve those precise objects. Cancellation, invalidation and commit clear
all captured Resource references. Unrelated-layer edits can still replace the
raster *layer* Resource through valid history while the unchanged source
snapshot authorizes the pending fill; this patch intentionally avoids
unconditionally pinning the layer object. The replacement/alpha/tolerance and
preview timing policies are untouched.

## Commands and results

Run from the repository root with the pinned Godot binary:

```bash
GODOT=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$GODOT" --headless --path . \
  --script res://tests/t113_bucket_resource_identity_smoke.gd \
  > bucket_resource_candidate_green.log 2>&1
python3 tools/check_godot_model_log.py bucket_resource_candidate_green.log \
  --marker T113_BUCKET_PASSED
# To obtain the negative control, temporarily substitute the original
# T-112 artwork_editor.gd blob and rerun the identical command, then restore.

GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$GODOT" --headless --path . --script res://tests/bucket_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 130s \
  xvfb-run -a "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/bucket_visual.gd
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
python3 -m unittest discover -s tests -p test_t094_godot_model_log.py -q
python3 -m unittest discover -s tests -p test_t094_ci_replay.py -q
```

**Verified exit codes:** all green Godot processes, both Python contract
suites, ticket validation, explicit typing and workflow inventory exited 0;
negative control exited 1 by design. The existing Bucket smoke/visual
scripts print their *historical* `(N checks)` format, which is not among the
T-094 exact-marker grammar forms. Their successful process exits and literal
success lines were inspected; they are **not** claimed to have passed the
strict log checker. The **new** T-113 oracle, T-111 and portable Line/Polygon
neighbors and Atlas composition were strictly verified. The composition
log retains four recognized Godot post-success resource-leak diagnostics.

| Retained raw log in `docs/evidence/raw/T-113/` | Exit | Result | SHA-256 |
| --- | ---: | --- | --- |
| `bucket_resource_old_red.log` | 1 | Expected 10/29 failures | `852199603b63ca9720072d7d7968a1ea5ff5286eb3de5cdf6fc070e9f0fece40` |
| `bucket_resource_candidate_green.log` | 0 | 29/29, strict | `0641679554209786c98dbc34b2f75bb263ea6285f40ce0a1072756602d3dd114` |
| `bucket_smoke.log` | 0 | 50/50, historical marker | `799363a834426d43a97b7c5cc64f9597bda679fac4d492377085cfde0eb5f344` |
| `bucket_visual.log` | 0 | 24/24, Xvfb historical marker | `7ba6c1cf26e05b31deddac2949a023aab8bfdf7f4a85e0fdb2ccd470e7ed72f5` |
| `line_resource_regression.log` | 0 | 49/49, strict | `9fe0c8a2405e654de5618e48303a58f3a739f1363b10fd77a52669b2c087c43e` |
| `line_portable_regression.log` | 0 | 128/128, strict | `298289bd4fb0b6b6a4f357ff052b649a604fe4f10390282b7103212c622b6346` |
| `polygon_portable_regression.log` | 0 | 70/70, strict | `c0dcf8edf9000de5db4318d412e7e19c1c0fa43b3e4610b077941dabc433e282` |
| `atlas_composition.log` | 0 | 89/89, strict; 4 known exit leaks | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |
| `t094_log_contracts.log` | 0 | 24 Python checks | `932face450b2e7cc74ff3dee524ca60b858a694416225f8b4f577cb567c4f9dc` |
| `t094_replay_contracts.log` | 0 | 14 Python checks | `2ce07eb74efeb081c26d19246f0305b1da4107d1c82d03271016b87312da693b` |
| `ticket_validation.log` | 0 | 113 tickets, gates valid | `09e3260179848ce1bb6933198f8b59da9c2c994d5bdc2084d30ae4647cc27489` |
| `explicit_types.log` | 0 | 422 project scripts | `f0e2242000aa168cd19007dc78cba571255645a0f4e2e9c0c64f3270eda4e5fc` |
| `ci_inventory.log` | 0 | 46 unique CI IDs, YAML parsed | `85220ac2bdd159a8403e882da94ee5157d03f35322a9694cff9d6120b79bf537` |

The existing required check
`ci_14_verify_t_055_atlas_canonical_drawing_composition_and_input` now runs
the T-113 oracle with a separate watchdog/log and strict T-094 verifier; no
new check ID is introduced. `docs/Tickets/T-023.md` stays Ready, with its
explicit fill behavior/style acceptance unapproved. Physical Linux/Windows
interaction, hosted CI on the new commit and any other owner gates remain open.
