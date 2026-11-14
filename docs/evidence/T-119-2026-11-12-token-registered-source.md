# T-119 — GM Token campaign registry authorization

| Provenance | Pinned value |
| --- | --- |
| Date | 2026-11-12 |
| Original Git HEAD | `b121762bcd784a4c6c12d57dfe03fdc4a417732a` (T-118) |
| Original Canvas blob | `32b80e09b6187dea48f03ce8053b90c25c7d47e7` |
| Original Editor blob | `4f6ef4e6ccc5dd2da18dd5f8df0bf1ca546247d5` |
| Candidate Canvas blob | `df8c547921a842e01bd5aa69ce395496ae5dcc4f` |
| Candidate Editor blob | `6615e64ab8062be20330b156d3cf4a995dd5d6a1` |
| Godot | `4.8.beta3.official.c51ff06e8` |
| Environment | Linux headless and Xvfb/Mesa llvmpipe, Dummy audio; no physical owner-device or player-output acceptance |

## Independent failure and fix

The existing Token gesture guard retained the exact map, floor and Token layer
Resources, source bytes and selection mask, but failed to check that those
Resources remained in the campaign's **registered** map/floor graph. The
Editor history command resolves a Token target **by ID**. A same-ID/byte
replacement can therefore inherit a held token move, mutate the newly
registered layer and append history even though the Canvas is still holding
the old map/floor pointers. Removed registry entries can also emit invalid
edit events. Immediate Token creation, deletion and direct Editor commands
have a related detached-reference gap.

The newly introduced `tests/t119_token_registered_target_smoke.gd` was run
first against the **unchanged** T-118 Canvas/Editor; it exited **1** with
**19/47** failed checks (the last `T119_TOKEN_FAILED: 47 checks` is only the
summary, not a 20th failed assertion). These fail on exact same-ID map/floor
replacements/removals, replacement campaign owner, stale dispatched events,
replaced token bytes, and direct create/delete/Editor edit attempts. The
strict log verifier correctly rejects the red run.

The patch captures and clears `_token_campaign_at_press` alongside existing
Token context and requires the registered campaign's original map and floor
at every drag update/release. It denies new placements and deletion from
unregistered Canvas resources. The Editor `_edit_token()` command boundary
independently requires the Canvas and Editor to share the same registered
campaign/map/floor before constructing an ID-addressed edit. Rejected drags
clear the preview and selection and emit the pre-existing guidance.

The candidate exits **0**, prints `T119_TOKEN_PASSED: 47 checks`, and passes
the T-094 strict log checker. All rejected drags preserve source dictionaries,
no edit request and the history cursor. A valid Token drag with an unrelated
registered map still commits one transaction, Undo restores the old position
and Redo restores the new position. Existing cell-mask/source/layer protection
remains covered by `token_smoke.gd`.

The expanded real graphical `token_visual.gd` additionally proves that a
pending visible preview disappears after a same-ID registered-map replacement,
that original **and** replacement token snapshots/history remain unchanged,
and that a fresh pointer gesture commits after owner restoration. It passes
**15/15** under Xvfb/Mesa with a strict verified success marker. This is a
software framebuffer witness, not input-to-photon timing on owner hardware.

## Exact reproducibility commands

Run from the repository root with pinned Godot and a clean Atlas import:

```sh
GODOT=/path/to/Godot_v4.8-beta3_linux.x86_64
# Red: restore only the two T-118 Canvas/Editor files in an isolated
# checkout; run the NEW test, expect process exit 1 and strict rejection.
timeout 120s "$GODOT" --headless --path . \
  --script res://tests/t119_token_registered_target_smoke.gd \
  > token-red.log 2>&1

# Green candidate, with exit-code verification before checking its log:
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 120s \
  "$GODOT" --headless --audio-driver Dummy --path . \
  --script res://tests/t119_token_registered_target_smoke.gd \
  > token-green.log 2>&1
python3 tools/check_godot_model_log.py token-green.log --marker T119_TOKEN_PASSED

# X11 graphical witness (use xvfb-run/Mesa for a software-only test):
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=5s 150s \
  xvfb-run -a -s '-screen 0 1280x900x24' "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path . \
  --script res://tests/token_visual.gd > token-visual.log 2>&1
python3 tools/check_godot_model_log.py token-visual.log \
  --marker ATLAS_TOKEN_VISUAL_PASSED

python3 tools/validate_ticket_store.py
python3 tests/check_explicit_types.py
python3 -m unittest discover -s tests -p test_t094_godot_model_log.py
python3 -m unittest discover -s tests -p test_t094_ci_replay.py
```

The red log was captured before modifying the Canvas and Editor, using the
same new test (without Dummy audio or the root-warning silence flag). The passing logs below have both a confirmed process **exit 0**
and strict log-verifier **exit 0**; no success marker alone is treated as a
pass. Godot's Xvfb V-Sync warning is not suppressed or misreported as an
`ERROR`-free hardware certification.

## Retained raw evidence

All seven raw logs are committed verbatim in
`docs/evidence/T-119-2026-11-12-logs/` with these SHA-256 digests:

| Log | Outcome | Process/verifier exits | SHA-256 |
| --- | --- | --- | --- |
| `token-original-red.log` | T-118, 19/47 failed | 1 / rejection expected | `5b0ae7af4b979328a5aa659aa1ae250a948dcc919707c7a3d3842837fd4f8150` |
| `token-registered-green.log` | T-119, 47/47 | 0 / 0 | `2ea8a15a73cf286223a5e04a84147223bbd7c31ed3f152a9aca9e8da76a5909c` |
| `token-visual-native.log` | Xvfb token framebuffer, 15/15 | 0 / 0 | `faaf01109a69d33bf974bf8b1b82c3110e349cbff3f61ab110ebbe4f11539cf5` |
| `token-neighbor.log` | Token semantics/privacy exclusion, 51/51 | 0 / 0 | `1ef6a31605cea895da9bd36d202436376d34a939d87ef7a8d5aba03eb44d75c9` |
| `selection-neighbor.log` | Atlas selection, 226/226 | 0 / 0 | `f2fdf25fa6de391d955b6a5e0c60ed1acd61f1553ebc414e12f4a70dd84456ec` |
| `wall-owner-neighbor.log` | Wall registered ownership, 91/91 | 0 / 0 | `e39bc356f61706e43cefc93c3b55898f92038afbed13b808a81f8c254dcb339a` |
| `atlas-composition.log` | Atlas composition, 89/89 | 0 / 0 | `6239636c02d7c865a5cbf632384356139509c689e03407d4ca3f9403fe863dd0` |

The atlas-composition log retains the **four recognized post-success Godot
resource-leak diagnostics**. The strict checker reports them separately and
does not suppress unknown failures or claim clean renderer teardown.

## CI, dependencies, and owner gates

The existing **required** T-055 composition check runs the 47-assertion
headless oracle with a separate watchdog and strict raw-log retention, adding
**no** new required check ID (46 remain). The
`.github/workflows/godot-native-t119-token.yml` workflow offers an
independent **on-demand** Xvfb pointer/framebuffer run and retains its log.
Both workflows are only configured here; a new GitHub-hosted run has **not**
been observed on this local commit.

T-119 is Done as an independent source-authorization fix with a completed
T-028 dependency. Its parent/related **T-041 remains Blocked on T-039**'s
manual privacy decision. No player-token publication, owner-device UX,
privacy approval or physical input-to-photon latency is claimed. No manual
review flag was modified.
