# Standalone Drawing desktop application (T-053)

The tracked `drawing/project.godot` and `drawing/main.tscn` are a **second
Godot project**, independent of Atlas's root `project.godot`. The single
editable Drawing engine lives at **`addons/drawing/`**, not in this directory.
The standalone build stages those exact source bytes under its own `res://`.
Never hand-edit generated `drawing/addons/` or copy it into source control.

## Run the standalone app

From the repository root:

```sh
python3 tools/build_drawing_app.py --in-place
godot --editor --path drawing
godot --path drawing
```

Clean/release build omitting all Atlas content:

```sh
mkdir -p /tmp/drawing-out
python3 tools/build_drawing_app.py --output /tmp/drawing-out/drawing
godot --headless --editor --path /tmp/drawing-out/drawing --import --quit
godot --headless --path /tmp/drawing-out/drawing --script res://tests/standalone_smoke.gd
godot --headless --path /tmp/drawing-out/drawing --export-release Linux /tmp/drawing-release.x86_64
```

The output directory must be empty and outside the repository. The build copies
only the standalone `project.godot`, scenes, app scripts, tests, export presets
and the canonical package's `.gd` and `.gd.uid` files. The third generic
consumer is staged through `tools/build_drawing_contract_consumer.py --fixture
drawing_package_consumer --output /tmp/consumer` and also has no Atlas source.
Linux/Windows export presets target x86_64 desktop; Windows export requires
its Godot template on the build host.

## Working with the editor

- **File** New, Open, Save, Save As use independent `.drawing` files; multiple
  documents open as tabs with a dirty `*` indicator.
- **Tools** Brush, Eraser, Select (drag rectangle), Move (drag previously selected
  pixels), Pan (left drag); middle drag pans in any tool. Scroll zooms around
  the pointer. A 1–96px brush-width field, optional generic 8px snap and color
  picker control the Drawing core's gestures.
- **Layer** Add group, add raster, toggle visibility, remove selected; tree
  selection chooses a raster paint target. Undo and redo apply to raster gestures.
  The **Record selection changes in Undo History** checkbox (OFF by default)
  optionally adds completed selections as separate clean, reversible steps;
  content undo restores layer/selection/tool context regardless of the toggle.
  Structural layer operations are dirty but are not yet undoable (T-063 and
  follow-up layer feature work).
- **Keyboard** Ctrl/Cmd+N, O, S, Z, Shift+Z, Y for New, Open, Save,
  Undo, Redo. Hover status reports revision, dirty state, zoom and layer ID.

## File format and boundaries

The app's single-file `.drawing` schema `drawing-standalone-v1` wraps the shared
`DrawingDocument.export_manifest()` tree and inline base64 **straight RGBA8**
chunks addressed by SHA-256 of dimension + format + original pixel bytes.
Chunk coordinates are signed decimal strings on disk (no 64-bit truncation
through JSON floats). Load validates the **whole** tree, every referenced blob,
and each canonical fingerprint before showing the document. Missing/corrupt
chunks fail closed; zero alpha's hidden RGB bytes are preserved. Files are
currently capped at 128 MiB and 4096 chunks; writes use a same-directory
`*.pending-<id>` then rename, preserving dirty state if the write fails.

This is a **standalone-specific** format, not the planned Atlas campaign
multi-file sparse manifest/chunk root, generational atomic publication,
retention, backup, migration or recovery from T-066. It is not yet a complete
production drawing editor: text/object authoring, advanced tool/options layout,
full structural history and performance/native acceleration belong to later
tickets. T-059 and T-056 still own hands-on owner UX acceptance.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v
# Native framebuffer, via Xvfb on Linux:
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/native_pointer.gd
```

T-060 notes: `.drawing` semantic objects now preserve non-Object Godot Variant
values with a checksummed payload; older JSON records remain readable.
