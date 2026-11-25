# T-275 — workspace CI contracts / owner-gate sync (2026-11-23)

## Baseline and cause

- Worktree base: `5980ada47b78f68a5e901077b9fa584e79668999`
  (`sprint/2026-11-23-godot-beta4`), including T-273/T-274.
- Latest verified remote `main` at inspection:
  `bbae76c33a6066582b2cd89e07cc3246fef942ce`, the owner squash of PR #22.
- GitHub Actions fast desktop run `45215183959`, `smoke-and-desktop`
  job `137834298556`, completed **failure**. `Verify T-063 compact Drawing
  workspace and shortcut contract` fails precisely at
  `tests/test_t063_workspace_docs.py:95`, expecting `status: "Ready"` in
  `T-056.md`, while canonical frontmatter is `Blocked` with a hard `[[T-250]]`
  dependency. The fast workflow has other independent failures; this does
  not represent a clean CI run.
- Fail-first locally: `python3 -m unittest discover -s tests -p
  'test_t063_workspace_docs.py' -v` → **8/9 passing** (one status assertion
  failure); corresponding T-072 workflow test → **9/10 passing**, also
  because five pending tool tickets and T-027 changed from Ready to Blocked.
- Fail-first native T-063 X11 on the existing beta4 build → **72/73**:
  `narrow root and drawing canvas fit actual window rather than clipping`
  asserted `canvas.size.x > 140` at 560px; current actual width 134px.

## Change and verification

- `tests/test_t063_workspace_docs.py`: use the ticket-store parser to check
  real T-250 dependencies and manual-review requirements rather than fixed
  intermediate statuses. If the gate has no recorded approval, T-056 and
  T-065 must not be Done. T-059's own review remains independently required.
- `tests/test_t072_tools_docs.py`: use the same parser for current T-023–027
  `T-250` dependencies, assert still unshipped and not Done; do not require
  Ready when Blocked/In Progress are legitimate states. The test does not
  auto-approve the gate or alter product scope.
- `drawing/tests/compact_workspace_smoke.gd`: replace the fixed numeric
  canvas-width oracle with a real Canvas `grab_focus`/`has_focus` check,
  visible-in-tree and enabled mouse filter. No fixed canvas size is blessed.
  Native pointer-motion simulation after resizing was **inconclusive**:
  `root.push_input()` did not update `pointer_known` while the physical X11
  cursor remained outside the 560px window. Therefore no new narrow-window
  *pointer* acceptance claim is made; no source/runtime UI code was changed.
- Actual beta4 X11 framebuffer `/mnt/data/t275-x11/drawing-560.png` was
  **opened and visually inspected**, showing narrow checkerboard Canvas at
  left and expanded right panel on a 560×600 root. This is a visual
  observation, not an owner signoff or a numeric geometry oracle. The
  workspace screenshot is not added to source control.

## Final local commands and outcome

| Command / suite | Result |
| --- | --- |
| `python3 -m unittest discover -s tests -p 'test_t063_workspace_docs.py' -v` | 9/9 pass |
| `python3 -m unittest discover -s tests -p 'test_t072_tools_docs.py' -v` | 10/10 pass |
| `xvfb-run ... godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/compact_workspace_smoke.gd` | 73/73 pass, `T063_WORKSPACE_PASSED` |
| `python3 tools/validate_ticket_store.py` | 275 tickets validated, review gates enforced |

The Godot witness uses the compiled Rust-backed extension with Godot
`4.8.beta4.official.b070e63b1`, Xvfb and Mesa llvmpipe. The current 560px
Canvas may be visually narrow; accepting its appearance belongs to T-250,
not automated T-275. T-056, T-059 and T-065 remain unapproved. The hosted
fast workflow has not been rerun on this local commit.
