# T-133 — Standalone operating-system window-close safety (2026-11-15)

## Problem and bounded change

`DrawingWorkspace` already refused File → Close Tab/Save when the Canvas had
unpublished Brush/Eraser input. The standalone `drawing/main.tscn`, however,
had no `NOTIFICATION_WM_CLOSE_REQUEST` handler and left the engine's default
`SceneTree.auto_accept_quit` enabled. The operating-system window close could
bypass document dirtiness and cancel the entire process while paint was still
being staged. The same problem affected other unsaved Drawing and Object tabs.

The canonical shared workspace now installs a quit guard **only when the
workspace is the SceneTree root's direct child** (standalone Drawing). The
engine's previous quit policy is restored when that workspace leaves the tree.
The OS request first checks the existing T-125 pending-stroke guard, then
walks tabs in reverse order using the preexisting Save/Discard/Cancel dialog,
never auto-approving a dirty document. The next tab is inspected only after
its predecessor has been explicitly saved or discarded. Cancel or a cancelled
Save As clears the entire quit intent. The Save confirmation is hidden before
the asynchronous save chooser opens, avoiding two exclusive dialogs at once.
Atlas's embedded Drawing workspace never changes the application's quit policy.

No raster/clipboard format, brush geometry, file serialization or native
backend changed. The 46 required fast-CI check IDs remain unchanged.

## Negative control and candidate

- **Reference source:** exact T-132 parent Git tree
  `438c60e216920c65852aee78363c9fce30ce0956`, independently checked in
  `/mnt/data/work/t132_clean_replay`. Only the new test script was copied
  into that checkout; no candidate runtime code was present.
- **Engine:** supplied Godot `4.8.beta3.official.c51ff06e8`, Linux x86-64.
- **Red command:** `godot --headless --audio-driver Dummy --path drawing
  --script res://tests/t133_window_quit_smoke.gd` (after standalone staging
  and Godot editor import) exited **1**: `T133_WINDOW_QUIT_FAILED checks=9
  failures=4`. It detected the missing standalone quit-policy override and
  window-quit continuation. The red control uses an early method-existence
  gate to avoid inventing a nonexistent baseline API; these are four genuine
  *missing-behavior* failures, not 4 failures out of a full 31-check run.
- **Red log SHA-256:**
  `d42ced917d9edb004572b700e59abd57653a07ccb88217d39e2da58331d1f22c`.
- **Candidate command:** the same headless test on the changed source exited
  **0**, printing `T133_WINDOW_QUIT_PASSED checks=31 failures=0`. Strict
  `tools/check_godot_model_log.py --marker T133_WINDOW_QUIT_PASSED` passed,
  retaining four recognized **post-success** Godot RID-leak diagnostics.
- **Green log SHA-256:**
  `b2def1b72764b445892952dabab947d84d9e1b663c0f9b2deb7cd0d1db330e29`.

The oracle drives a released long Brush until the Canvas confirms unpublished
work. It sends `NOTIFICATION_WM_CLOSE_REQUEST` and verifies unchanged tab,
document revision and pending input, with an actionable refusal. After the
frame-budgeted stroke commits, the same notification opens a dirty-document
confirmation. Cancel retains the document and revokes the quit intent.
A second scenario checks embedded-Atlas policy isolation. A third tests
three tabs: a saved tab closes without prompting, a dirty tab can Cancel
without destroying either remaining document, Save As commits one specific
tab's exact RGBA8 (`0xff123456` at 11,12), and the remaining dirty tab is
only removed after explicit Discard. A final attempt clears the quit state. A fourth scenario covers the standalone
Object Editor: cancelling Close leaves its dirty private source intact, while
choosing Save publishes a reopenable `.drawing` Object before closing the tab.

## Software-native and adjacent verification

The same 31-assertion test exited zero under Xvfb/X11/OpenGL Compatibility:

```sh
xvfb-run -a -s '-screen 0 1280x800x24' \
  godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t133_window_quit_smoke.gd
python3 tools/check_godot_model_log.py /tmp/t133-native.log \
  --marker T133_WINDOW_QUIT_PASSED
```

Native log SHA-256:
`7ff37c541f81c882f2486b6839ec25488addd661d8603aec83307bd73732b04f`.
Strict verification retained 14 known post-success texture/RID leak lines;
no parser/script/model errors or unexpected engine errors were ignored.
The test is **scripted window-close notification** in native X11, not a
physical desktop window manager close/button acceptance or a hardware
input-to-photon measurement.

Completed neighboring Godot tests (same supplied engine, headless):

| Test | Result |
| --- | --- |
| T-124 chronological queued Brush | 69/69 |
| T-125 pending Save/Close | 29/29 |
| T-126 tab switch | 34/34 |
| T-127 Undo/Redo | 40/40 |
| T-128 History-list jump | 37/37 |
| T-131 Object metadata | 21/21 |
| T-132 Save As callback ownership | 34/34 |
| Standalone + Object Editor UI | Passed; Object Editor 26/26 |
| Native T-124 queued Brush | 19/19, process exit zero |
| Native T-120 File/Object menus | Passed strict T-120 native log verifier |
| Independent native-absent Drawing consumer | Build/import passed; standalone 42/42 |

Python source/CI contracts and explicit typing are independently checked.
These are **local** results; no hosted GitHub all-46 pass, physical Brush
latency, Windows runner, or owner UX approval is implied.

## Reproduction commands

```sh
cd <repo>
python3 tools/build_drawing_app.py --in-place
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy \
  --editor --path drawing --import --quit
GODOT_SILENCE_ROOT_WARNING=1 godot --headless --audio-driver Dummy \
  --path drawing --script res://tests/t133_window_quit_smoke.gd \
  > /tmp/t133-window.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t133-window.log \
  --marker T133_WINDOW_QUIT_PASSED
grep -Fqx 'T133_WINDOW_QUIT_PASSED checks=31 failures=0' /tmp/t133-window.log
python3 -m unittest discover -s tests -p test_t133_window_quit.py -v
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

Do not report global sprint completion: T-095 and numerous independent
manual, device and hosted-CI gates remain open.
