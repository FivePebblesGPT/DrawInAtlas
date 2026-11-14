# T-117 — Wall Path registered-target authorization

**Date:** 2026-11-12
**Remote PR #17 HEAD:** `79b8959e9eac01b3bb10a144a46407acc6901aed` (unchanged at evidence capture)
**Exact local baseline (T-116):** `830846ecddcfc5b31e292a2ba65e8e520019d574`
**Original Canvas Git blob:** `55075f9a84a5d3bef083d4bbb426db26e42363f6`
**Candidate Canvas Git blob:** `32b80e09b6187dea48f03ce8053b90c25c7d47e7`
**New oracle Git blob:** `e33ce71cca3a2e39cdae98de01239d1d635b7f4f`
**Engine:** `Godot 4.8.beta3.official.c51ff06e8`, Linux headless and Xvfb/Mesa graphical, Dummy audio. Not an owner physical-device or hosted-CI result.

## Actual defect and red/green control

Wall Path uses an `AtlasEditScope`, map/floor/layer Resource references, and layer eligibility while constructing a path or dragging one vertex. The old `_wall_context_matches()` did not check that the campaign still owned the same map and floor Resources. A same-ID/byte replacement or removal from their registries could authorize stale path commands. The direct insert/delete/restyle actions also lacked a registration check.

The new independent oracle exercises five held-draft detachment types, three held-vertex-drag detachment types, and two directly edited detached targets. It counts `path_edit_requested` emissions, `wall_rejected` events, exact floor serialization, history cursor, transient preview state, and matching Resource identities. Valid registered edits, changing an unrelated map, an open path, vertex movement, and Undo/Redo stay supported.

- **Red:** with the exact T-116 Canvas restored, the new test exited **1** and failed **23/85** executed assertions. Failed checks observed real command emissions/history changes after detach; this is not a simulated static source search.
- **Green:** changed Canvas exited **0**, printed `T117_WALL_PASSED: 91 checks` and passed the strict T-094 model-log verifier (`0`). The per-path count differs because the old code proceeds into extra stale mutations; no count parity is asserted.
- **Historical neighboring control:** `tests/wall_paths_smoke.gd` exits **1**, failing the same four of 78 assertions on both versions: style change, style Redo, retired native Save/Open, and scope-changed vertex drag. This ticket does **not** fix or conceal those pre-existing failures. The two raw logs are byte-identical.
- **Graphical:** `tests/wall_paths_visual.gd` passed **20/20** with Xvfb/Mesa and exact success-marker verification. T-111 Line, T-113 Bucket, T-114 Polygon, and T-055 Atlas composition also exited **0** and passed strict logs. Atlas composition emitted four recognized *post-success* Godot leak warnings, retained in its raw log.
- **Static/tooling:** `python3 tests/check_explicit_types.py` passed (425 scripts and 33 skill documents), `tools/validate_ticket_store.py` passed (117 tickets), T-094 strict log contracts **24/24**, local CI replay contracts **14/14**. Workflow YAML parsed and retained **46 unique `ci_` IDs**.

## Commands (exit codes explicitly checked)

```bash
cd /mnt/data/work/DrawInAtlas.11-12
G=/mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64
# Red: temporarily use the exact T-116 Canvas (blob above), restore the
# candidate immediately afterward. The new oracle exits 1, as expected.
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 150s \
  "$G" --headless --path . --script res://tests/t117_wall_registered_target_smoke.gd
# Green (0):
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$G" --headless --audio-driver Dummy --path . \
  --script res://tests/t117_wall_registered_target_smoke.gd > wall-t117-green.log 2>&1
python3 tools/check_godot_model_log.py wall-t117-green.log --marker T117_WALL_PASSED
# Graphical (0):
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 150s \
  xvfb-run -a "$G" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path . --script res://tests/wall_paths_visual.gd > wall-visual.log 2>&1
python3 tools/check_godot_model_log.py wall-visual.log --marker ATLAS_WALL_PATHS_VISUAL_PASSED
python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p "test_t094_godot_model_log.py"
python3 -m unittest discover -s tests -p "test_t094_ci_replay.py"
```

## Exact retained raw logs and digests

All paths below are relative to `docs/evidence/T-117-2026-11-12-logs/`. SHA-256 hashes cover the exact committed bytes. A test is marked green only when the Godot process and the strict marker checker both return `0`.

| File | Scope | Outcome | SHA-256 |
| --- | --- | --- | --- |
| `wall-previous-red.log` | T-116 Canvas, new oracle | exit 1; 85 checks, 23 failed | `265042434e1c7043d2872b820ace6eaa80206ea32f31994a1d94ea15f6931578` |
| `wall-t117-green.log` | T-117 Canvas, new oracle | exit 0; 91/91; strict pass | `e39bc356f61706e43cefc93c3b55898f92038afbed13b808a81f8c254dcb339a` |
| `wall-previous-neighbor.log` | T-116 Canvas, historical wall smoke | exit 1; 78 checks, 4 failed | `d78ed40f309619199596c9e874188d5da849af8b0d6a8ce6fbb69036b0f61e43` |
| `wall-neighbor.log` | T-117 Canvas, historical wall smoke | exit 1; same 4 of 78 failed | `d78ed40f309619199596c9e874188d5da849af8b0d6a8ce6fbb69036b0f61e43` |
| `wall-visual.log` | T-117 graphical Wall | exit 0; 20/20; strict pass | `f68a16389683a11d2f0b960882b5dbb5b952488cea814c4e5e70610dc6b8efeb` |
| `line-t111.log` | T-111 Line ownership | exit 0; strict pass | `9fe0c8a2405e654de5618e48303a58f3a739f1363b10fd77a52669b2c087c43e` |
| `bucket-t113.log` | T-113 Bucket ownership | exit 0; strict pass | `0641679554209786c98dbc34b2f75bb263ea6285f40ce0a1072756602d3dd114` |
| `polygon-t114.log` | T-114 Polygon ownership | exit 0; strict pass | `829ed7f656815389561d20103b898f0f990134cf10ff56a7a44cc6fa09a0a7e7` |
| `atlas-composition.log` | T-055 Atlas composition | exit 0; 89/89; strict pass (4 known post-exit leaks) | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |

## Gate boundaries

The change leaves T-026 Ready for explicit owner review of point operations, styling, mask semantics and additive editable path representation. It does not modify serialization or authorize such decisions. The new oracle is appended inside the existing required T-055 CI step rather than creating a new required check. CI on the *new local commit* and real Linux/Windows owner-device UX remain unverified. There is no remote push or merge in this evidence.
