# T-120: canonical File/Object menus and unified image Open

**2026-11-14 · Engineering Done, not owner physical-UX approval.** Branch `sprint/2026-11-14`; baseline remote `5b9bf460d111b11035fc71ac927a86346c5d8dd7`. Pinned Linux x86-64 Godot **4.8.beta3** from bundle 8, with software X11/Xvfb/Mesa for the graphical witness. This is the one-ticket corrective change requested after the 11-11 sprint. T-053 and T-093 direct prerequisites were already Done; T-120 has `manual_review: false`.

## Implementation and observable behavior

- `addons/drawing/workspace.gd` provides exactly five top-level File commands in order: **New**, **Open…**, **Save**, **Save As…**, **Close Tab**, keeping Ctrl+N/O/S/Shift+S/W. **Object** is a separate top-level menu with **New Source**, **Open Source…**, **Rename Source…**, **Save Source As…**, **Browse Sources…**. Ordinary File has no `Object ›` pseudo-entries, and the old image-import action/chooser is removed.
- The single Open `FileDialog` filters `.drawing`, `.png`, `.webp`, `.jpg` and `.jpeg`. `.drawing` still follows `DrawingFileIO.open_with_frame`; raster files follow the existing `DrawingRasterImport.import_image` to create a new raster layer and frame in an ordinary **unsaved** Drawing tab. Transparent-only input retains its explicit frame. No Object session, Atlas placement, publisher or binding is created by raster Open.
- Encoded rasters have a 64-MiB cap, format-specific header preflight, decoder check, 4096-per-side and 16,777,216-pixel limits. Error paths leave the tab collection untouched. First Save opens the `.drawing` destination chooser, and Save writes a `.drawing` without overwriting the raster; a source SHA-256 hash is compared before/after. Existing dirty-close prompts, new tabs, Object Browser and `.drawing` roundtrip are exercised.
- `addons/drawing/editor_top_bar.gd` adds the Object menu without duplicating commands. When narrower than the available row width, More retains hidden commands as `Object › …` (plus prior View/Window checkable/disabled parity). Its layout uses the actual available ancestor Control widths, not an overflowing minimum from the child Container. Existing UI/source-browser help and the standalone README reflect the new commands.

## Local verification and strict oracles

| Witness | Result | Main coverage |
| --- | ---: | --- |
| `drawing/tests/t120_unified_open_smoke.gd` | **34/34** | File/Object exact command sets, single native FileDialog dispatch, PNG exact 15 canonical RGBA8 pixels, WebP/JPEG, transparent frame, immutable source hash, `.drawing` reopen, malformed/missing/oversized/unsupported inputs, Object isolation |
| `drawing/tests/t120_file_object_native.gd` | **24/24** with screenshots; **20/20** without | X11 pointer-opened File/Object menus, single chooser, Ctrl+O/N/S/Shift+S/W, dirty-close confirmation, real imported frame and roundtrip, constrained-window More command identity and Asset Browser dispatch, four framebuffer captures |
| `tests/test_t120_unified_open.py` | **5/5** | Static menu/dispatcher/staging/CI contracts; verifier rejects missing/duplicated/spoofed PASS, pre-success or unexpected errors and incomplete checks |
| T-093 Object discovery headless | **56/56** | Prior separate Object-source create/open/browse and raster compatibility |
| T-090 overflow headless | **32/32** | View/Window checkmarks, disabled commands, overflow callable identity |
| T-063 native compact workspace | **75/75** | Unrelated toolbar, menus, shortcuts and field behavior |
| T-090 native responsive workspace | **77/77** | Resizing/scaling, real More pointer-open, checkmarks, scroll and tab close |
| T-092 native Colors/History | **51/51** | Independent palette and history interactions |
| T-093 native Object discovery | **27/27** | Source browser, explicit root selection and native canvas |
| `tests/test_drawing_app.py` | **3/3** | Clean isolated standalone build plus third-party canonical package consumer |

Reproduction from the repository root (after the pinned bundle has provided `godot`):

```bash
python3 tools/build_drawing_app.py --in-place
# Import after staging so SVG/font class caches exist; otherwise the run may
# emit unrelated missing-resource errors from a stale ignored .godot folder.
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/t120_unified_open_smoke.gd \
  2>&1 | tee /tmp/t120-model.log
python3 tools/check_godot_model_log.py /tmp/t120-model.log --marker T120_MODEL_PASSED
mkdir -p /tmp/t120-screenshots
T120_SCREENSHOTS=/tmp/t120-screenshots xvfb-run -a --server-args='-screen 0 2200x1500x24' \
  godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
  --path drawing --script res://tests/t120_file_object_native.gd \
  2>&1 | tee /tmp/t120-native.log
python3 tools/check_native_t120_log.py /tmp/t120-native.log
python3 -m unittest discover -s tests -p 'test_t120_unified_open.py' -v
python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v
python3 tools/validate_ticket_store.py
```

The in-repository `.github/workflows/godot-check.yml` integrates the T-120 headless witness and Python contracts **inside the existing T-093 fast check**, preserving the 46 required-check inventory. The on-demand `.github/workflows/godot-native-t093-object-sources.yml` also runs the native T-120 witness and stores logs/screenshots. Both use strict log verifiers; a marker alone cannot conceal failures.

## Known limits and boundaries

- Godot emitted **four** known RID-allocation diagnostics after the T-120 headless PASS and **21** GL texture/RID diagnostics after the native PASS. They remain explicitly reported by the verifiers; no pre-PASS runtime errors, child crashes, missing markers or other unexpected error lines were accepted.
- In an intentionally **below-minimum 300px** native window (project minimum is 800px), a many-row `PopupMenu` may cover the More trigger. The native test opens it using an actual pointer press, inspects the popup and its command IDs, dispatches the already-registered Browse Sources action, and releases after closing; it does **not** assert a conventional full down/up click on a visible More item in this unsupported narrow geometry. Native T-090 was updated to use the same constrained-width witness; its checks remain 77/77. At ordinary 1280px desktop width File and Object both open with actual pointer clicks.
- Tests use Linux software framebuffer and synthetic pointer/key input, not a physical GPU, tablet or stylus. The four captured screenshots are local test evidence, not owner-facing approval. No hosted GitHub CI run, physical-device acceptance, Windows/macOS runtime, measured lag improvement or native brush-engine switch is claimed.
- T-059 and T-056 retain owner UX/integration review; T-090's remaining chrome scope and T-095/T-068 latency/backend work remain independent. T-093's original status and historical evidence are unchanged.
