# T-108 — explicit nested Object Save As prototypes (2026-11-12)

**Status: In Progress, `manual_review: true`.** Owner has not selected a
link-vs-copy policy and no nested single-file export or user-facing flow is
approved. This is a source/test checkpoint, not a resolved product decision.

## Reproducibility and source scope

- Base: local `030b7f856b97721403d81e82028aa93c82b97a32` (T-107); last
  observed remote PR #17 head `79b8959e9eac01b3bb10a144a46407acc6901aed`.
- Engine: supplied pinned `Godot_v4.8-beta3_linux.x86_64`, identifying as
  `Godot Engine v4.8.beta3.official.c51ff06e8`.
- Source SHA-256 at test: `scripts/objects/object_library.gd`
  `8fb6dbe3b09b486c012ae7ecf002acc96ddaaec8c9b9acbe4ccb6cf7cdddb862`;
  `scripts/objects/object_draft.gd`
  `3c70725398d8afbd265a63014491da2f9542a560d315b9a223172b62a0ed4111`;
  `tests/t108_nested_save_as_policy_smoke.gd`
  `f8cacd7d1e4223c1a203de54c859ff1f028a100dc66ddf2ea4f1e38d60f586c3`.
- All runs use root Godot project with already imported class data, Dummy
  audio/headless display, fresh isolated campaign paths in `OS.get_cache_dir()`;
  success removes each fixture. Test stdout/stderr saved verbatim in
  [`T-108-2026-11-12-logs/`](T-108-2026-11-12-logs/). Exit codes were read.

## Decision comparison — not owner consent

| Choice | New source IDs | Child instance IDs | Existing child Save propagates | NULL | Portable export |
| --- | --- | --- | --- | --- | --- |
| `links` (provisional recommendation) | One fresh parent | All fresh IDs/generations; transforms kept | Yes, because source IDs remain shared | Preserved as NULL tombstone, not rebound | Full campaign+Objects component copy |
| `deep_copy` | Fresh parent and one copy of each distinct reachable published source (DAG sharing retained) | All fresh IDs/generations | No; cloned descendants have separate immutable source revisions | Preserved as NULL tombstone, not cloned | Full campaign+Objects component copy |
| No policy (current Object Editor) | None | None | Not applicable | No mutation | `NESTED_SAVE_AS` rejection; nested single-file `NESTED_EXPORT` rejection |

The test fixture uses A→B→C and A→C, signed offsets, two independent Atlas
placements, hidden-RGB straight RGBA8, one deleted/NULL child, source edits,
parent/child selection IDs, Undo/Redo and fresh project copying. It confirms
old parents and unrelated Atlas instances do not rebind; copied families
preserve shared-descendant topology and source pixel content. Explicit
`deep_copy` stages new immutable `.drawing` revisions and publishes their
registry records **once**, with optional selected-instance rebind in that
same transaction. Failed commits clean staged directories. This does not
promise cross-process filesystem race atomicity or solve single-source
nested export. The existing full portable campaign copy remains supported.

### Red control

The exact pre-T-108 `object_library.gd` and `object_draft.gd` were substituted
from `git show HEAD:<path>` into the same test checkout, with shell cleanup
restoring candidate bytes after the process. Command:

```sh
GODOT_SILENCE_ROOT_WARNING=1 timeout 18s \
  /mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64 \
  --headless --path . --script res://tests/t108_nested_save_as_policy_smoke.gd \
  > docs/evidence/T-108-2026-11-12-logs/red-original.log 2>&1
```

**Exit 1 (expected failure)**: Godot rejects the new six-argument explicit
`save_as()` calls (`Expected at most 5 but received 6`), proving the original
source lacks the policy API. Raw SHA-256:
`65e42790c85b7eda9f51d58d985909b240ddc11acd8090720cdf165f04f5ecfd`.
A parser failure is intentionally not mislabeled a successful model run.

### Green and neighbors

The new oracle:

```sh
GODOT_SILENCE_ROOT_WARNING=1 timeout 75s \
  /mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64 \
  --headless --path . --script res://tests/t108_nested_save_as_policy_smoke.gd \
  > docs/evidence/T-108-2026-11-12-logs/green-policy.log 2>&1
python3 tools/check_godot_model_log.py \
  docs/evidence/T-108-2026-11-12-logs/green-policy.log \
  --marker T108_POLICY_PASSED
```

Exit **0**, strict checker exit **0**, **42/42** assertions. Raw SHA-256
`6881d192d29343e2330e983a8bb6cc94cada1c0bb10da5c2549b569a5a696ee4`.
The following neighboring suites each ran with the same engine, a 90-second
per-process watchdog, process exit 0, exact marker, and strict log checker
exit 0:

| Suite | Assertions | Raw SHA-256 |
| --- | ---: | --- |
| `object_assets_smoke.gd` | 95 | `ba5cb71fd9be2738407dc0137705a9263de55f1739149757613963d10585af26` |
| `object_child_graph_smoke.gd` | 56 | `4730d4ac0a3516dc1cf886fdc04559733fc6169c073e19ef053488fd907ce469` |
| `object_nested_project_copy_smoke.gd` | 37 | `57ed97b38dc73e39ad27bfa7297d8533b1cdd2e14d5fab84d2fc5520420efef4` |
| `object_child_edit_smoke.gd` | 45 | `1ba8deb8d9be66e9bfc7ad1bf65129cd6beb0588e50aeadecfa1c0f44dcf64d0` |
| `object_child_null_repair_smoke.gd` | 45 | `5d469a5556db409846dd8c097c4529d4bd1927c51c93ce3b040a9b629b11c9b2` |
| `object_nested_campaign_copy_smoke.gd` | 46 | `4796903045ab5c364a3ede7af93dd7d0396b1dbdbf7fe2fd228206567f8b4828` |
| `object_child_visibility_smoke.gd` | 39 | `f43cf91a9f631e8b33903e64a833ebfef11bd9513767c8aa0f60e83020709dbe` |

A total of **405** successful model assertions (42+363) were checked across
these eight headless suites. Additionally, a native Xvfb/Mesa UI selection
witness passed 21/21 checks with strict log verification:

```sh
GODOT_SILENCE_ROOT_WARNING=1 timeout 110s xvfb-run -a \
  -s '-screen 0 1280x800x24' \
  /mnt/data/work/toolchain/Godot_v4.8-beta3_linux.x86_64 \
  --path . --rendering-method gl_compatibility --audio-driver Dummy \
  --script res://tests/object_child_canvas_select_smoke.gd
```

Exit 0, checker exit 0, marker `T064_CANVAS_CHILD_PASSED (21 checks; 0 failed)`;
raw SHA-256 `7f8c22db76e04acbecee436ff996603423eb7f0c9d193d2c376e865c74989781`.
This is software Xvfb, not owner-device acceptance. The T-108 headless
witness also checks distinct root-to-child hit paths after instance rebinding. The only runtime source changes are the opt-in library method,
draft graph-revision pin, and dedicated oracle; normal Save As and export
continue to reject undecided nested behavior. Workflow wiring adds the oracle
inside existing `ci_11b_verify_t_064_nested_object_graph`, preserving the
**46 required CI IDs**. A new hosted run on this local head was **not**
observed; the evidence is a selected local replay only.

`python3 tools/validate_ticket_store.py` validates 109 canonical tickets and
all ancestor manual gates; T-108 remains `In Progress`. `git diff --check`
is clean. No Windows or physical pointer/UI approval is claimed.

## Owner action required before Done

Decide whether **Save As on a parent with nested Object sources** should
(A) preserve live links to existing children (recommended for one-source/many
instances), or (B) deep-copy the entire reachable published dependency graph.
Confirm whether the choice should always be prompted or have a documented
user-facing default. Separately decide whether single-source portable export
should bundle a dependency manifest/files or remain unavailable in favor of
**Campaign.scn + Objects/** component copying. Then implement/test the
approved UI flow and record an explicit dated owner response; no silence or
prior generic feature-inventory acceptance satisfies this gate.
