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
godot --headless --editor --path drawing --import --quit
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

Optional T-068 distribution gate after an export into `/tmp/drawing-dist`
containing `Drawing.x86_64` and `Drawing.pck`:

```sh
python3 tools/benchmarks/t068_release_gate.py \
  --stage /tmp/drawing-out/drawing --linux /tmp/drawing-dist \
  --launch-linux --output /tmp/drawing-release-validation.json
```

This requires Godot export templates. The Linux check runs the exported
executable from a clean working directory and user profile, not the source
project. A Windows `.exe`/`.pck` may be structurally checked with `--windows`
but requires an actual Windows runtime pass for acceptance. This tool does not
measure physical pointer-to-photon latency or GPU/VRAM usage.

The output directory must be empty and outside the repository. The build copies
only the standalone `project.godot`, scenes, app scripts, tests, export presets
and the canonical package's `.gd`, `.gd.uid` and licensed font files. The third generic
consumer is staged through `tools/build_drawing_contract_consumer.py --fixture
drawing_package_consumer --output /tmp/consumer` and also has no Atlas source.
Linux/Windows export presets target x86_64 desktop; Windows export requires
its Godot template on the build host.

## Working with the editor

- **File** New, Open, Save, Save As use independent `.drawing` files; **Ctrl/Cmd+Shift+S opens Save As**, with Ctrl/Cmd+Y as the primary redo shortcut (Shift+Z alias). The eight-menu compact header keeps File/Edit/View visible and moves additional commands into More at narrow widths; per-tool options scroll through chevrons or wheel rather than wrapping. Multiple
  documents open as tabs with a dirty `*` indicator. To remove the row labeled
  `Untitled`, uncheck **Window → Show document tabs**; use Ctrl/Cmd+Tab or
  Ctrl/Cmd+Shift+Tab to change documents without the strip. The active filename
  and dirty marker remain in the status bar; visibility resets on app restart.
- **Tools** The compact left rail has icon-only, keyboard-focusable Brush,
  Eraser, Select, Move, Text and Pan buttons; hover or focus for tool names.
  Brush, Eraser, Select (drag rectangle), Move (drag previously selected
  pixels), Pan (left drag); middle drag pans in any tool. Scroll zooms around
  the pointer. A 1–96px brush-width field, optional generic 8px snap and color
  picker control the Drawing core's gestures.
- **Layer** Add group, add raster, toggle visibility, remove selected; tree
  selection chooses a raster paint target. Undo and redo apply to raster gestures.
  The History dock's **Record selection changes in Undo History** checkbox (OFF by default)
  optionally adds completed selections as separate clean, reversible steps;
  content undo restores layer/selection/tool context regardless of the toggle.
  Structural layer operations are dirty but are not yet undoable (follow-up layer feature work).
- **Keyboard** Ctrl/Cmd+N/O/S, Ctrl/Cmd+Shift+S, Z, Y (Shift+Z alias), W for New/Open/Save/Save As/Undo/Redo/Close. Status reports cursor pixel coordinates, visible canvas dimensions and zoom. The right Colors/Layers/History dock stacks independently collapsible groups and scrolls at short heights. Use **Window → Minimize/expand panel dock** (or the dock's own button) to switch between the expanded groups and a narrow icon rail. Each attached panel has an icon with a tooltip; adjacent icons in a group share one flyout/tab set, while a separator denotes a different group. The flyout overlays the drawing canvas without changing its layout or creating an OS window; click the active icon to close it. Collapse and active tab state survive minimize/restore during the session. **Drag a panel icon** to another tab position, another group, or a between-group insertion marker; **drag the ↕ handle** to reorder or merge its whole group. The in-app hint appears only for valid drops; Esc and leaving the dock cancel without layout changes. The group **⋮ Arrange** menu provides keyboard-accessible move/split/merge actions. On a focused panel icon use `Ctrl+Alt+Left/Right` to reorder, `Ctrl+Alt+Up/Down` to move to an adjacent group and `Ctrl+Alt+S` to split; on a focused ↕ handle, `Ctrl+Alt+Shift+Up/Down` reorders groups. Large tab strips scroll horizontally, and dragging near the top/bottom of the dock scrolls through offscreen group targets. Use **Window → Float selected dock group** after focusing a dock tab/group handle (otherwise the first attached group is chosen) to move all its current tabs into a floating **in-app Control**. Drag the host's ⠿ title grip to move, its ◢ lower-right grip to resize, and its floating tab icons to reorder within the host; each floating group's ⋮ menu also moves, splits and merges local groups. Close × **hides** the host without redocking or discarding its panels; **Window → Show hidden floating panels** recovers every hidden host. Each host can contain multiple ordered groups, independently collapsed. Drag a floating tab or whole group onto the expanded dock, a minimized-rail group gap, or another floating host to transfer the **original** panel(s), preserving relative tab order. Drop on the bare canvas to create an in-app floating host; Esc or an invalid drop leaves both sides unchanged. The dock and floating-host ⋮ menus offer keyboard-accessible cross-container moves; a focused floating tab can use Ctrl+Alt+D, or focused group handle Ctrl+Alt+Shift+D, to redock at the end of the right dock. The original floating container disappears when all its groups have moved away. Dock/group/flyout/floating-host layout is now saved across application relaunches as a **workspace preference** (never inside `.drawing` documents). **Window → Reset workspace layout** restores Colors/Layers/History singleton groups and resets floating hosts without discarding edits. Settings are stored in the Godot user data directory (`user://drawing-workspace-dock-v1.json`); corrupt/unsupported files return to safe defaults, and offscreen hosts are clamped on restart or resize. Hidden floating panels still recover from Window. A host that embeds the shared editor can override `layout_settings_path` to isolate separate workspaces, and can register optional panels by stable ID before restore. The complete Drawing feature inventory and Asset Browser implementation remain separate tickets; **T-083 awaits explicit owner UX review**, and automated tests do not approve it.

## Standalone image frame, checkerboard and grid (T-087)

New ordinary Drawing tabs start with a **512×512 image frame at (-256,-256)**,
fit to the viewport. A thin visible edge separates the intended image extent
from the darker surrounding workspace. A two-tone transparency checkerboard
appears **only behind the frame**, with **16-pixel squares in screen space**:
zooming changes image pixel scale, not checker square size. It is a UI backdrop,
not a raster layer or exported pixel data. Sparse pixels **outside the frame**
remain editable, visible and saved; the frame is deliberately **not a crop**.

- **Image → Drawing image frame…** changes the signed image origin and positive
  width/height (up to 1,000,000 px). This is a metadata-only edit, flagged as
  unsaved until a successful Save. It does **not** scale, resample, clip, erase,
  resize source tiles, or change the canonical document revision/history.
  Actual destructive crop/resize is not implemented; a later dedicated feature
  must specify how to handle outside pixels and history before offering it.
- **View → Show grid** toggles source-space lines inside the image frame;
  **View → Grid spacing and origin…** chooses 2–4096 source pixels and signed
  X/Y origin. The Brush/Eraser/Select/Move/Text tool option **Snap** is
  independent of grid visibility. At very small zooms, closely spaced grid
  lines are visually thinned to whole multiples of the chosen spacing to
  avoid subpixel clutter; snapping still uses every actual intersection.
  The status bar reports cursor, image origin/size, grid spacing/origin and
  snap state. Grid/snap toggles and spacing are per-tab *session* preferences,
  not `.drawing` raster data; object/world/Atlas grids are not modified.
- New-format `.drawing` envelopes may include an optional `image_frame` with
  **signed decimal-string origin** and validated integer size. Old files without
  it still load: the workspace computes a conservative guide around occupied
  source tiles/text (minimum 512px); extremely distant sparse content falls
  back to the default centered guide, **without discarding any pixels**. Object
  Asset `origin`/`bounds` continue using their own existing semantics, and
  generic Atlas canvas consumers default to no standalone image frame.

Verification after staging and editor import:

```sh
godot --headless --path drawing --script res://tests/image_frame_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/image_frame_native.gd
```

The second test captures real X11/Mesa framebuffer pixels and delivers mouse
input through a Godot viewport. It is a **software-only** witness; physical
Windows/Linux owner usability still belongs to the separate review gates.

## File format and boundaries

The app's single-file `.drawing` schema `drawing-standalone-v1` wraps the shared
`DrawingDocument.export_manifest()` tree, optional non-destructive image
frame metadata, and inline base64 **straight RGBA8**
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
production drawing editor: the compact T-063 layout does not implement
all approved tools/advanced options, and full structural history and
performance/native acceleration belong to later tickets. T-058 now supplies standalone editable text and explicit rasterization. T-059 and T-056 still own hands-on owner UX acceptance.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_drawing_app.py' -v
# Native framebuffer, via Xvfb on Linux:
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/native_pointer.gd
```

T-060 notes: `.drawing` semantic objects now preserve non-Object Godot Variant
values with a checksummed payload; older JSON records remain readable.

## Live paint-preview verification (T-085)

Brush and Eraser show a detached, layer-correct draft while the left button
is still pressed, including the stationary first dab. Raw canvas-source
samples are queued and timestamped, then staged in bounded frames. A long
release may finish its queue over subsequent frames before the single normal
commit; **Esc cancels**, changing tool/layer/document/zoom cancels, and
releasing outside the canvas finishes the captured path. No uncommitted bytes
are written to `.drawing`. Brush footprint is outlined at the pointer.

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/live_stroke_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/live_stroke_native.gd
```

The Xvfb framebuffer test samples pixels **while mouse-down remains active**
at 100%, 50% and 25% zoom. It is software rendering only and does not replace
physical Windows/Linux usability validation or T-086's dirty-tile viewport
cache. See [T-085 evidence](../docs/Tickets/T-085.md).

## Source-aligned viewport cache (T-086)

Viewport redraws reuse persistent 128×128 source-space `ImageTexture` tiles
(up to 144 retained; approximately 9 MiB of RGBA8 texture payload). Zoom/pan
rescale native Godot texture quads; small edits/Undo/Redo invalidate only
intersecting cached display tiles. Rendering still composites the canonical
RGBA8 source in layer order, including uncommitted detached Brush/Eraser
pixels; cancellation does not publish history. Empty source tiles are skipped
through bounded occupancy metadata. A Godot `ImageTexture.update()` refreshes
one **whole 128px display texture**, not a partial upload. All sizes are
editor-display/cache quantities and do not alter sparse storage tile stride.

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/viewport_cache_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing --script res://tests/viewport_cache_native.gd
python3 tools/benchmarks/t086_compare_viewport.py --godot godot
```

The native check uses a **software framebuffer**. The benchmark compares the
pinned pre-cache T-085 code to the current implementation under the same Xvfb
Mesa process profile, at 100/50/25% zoom. It reports CPU composition, full
texture bytes uploaded, software frame submission, and process HWM, **not**
physical input-to-photon or GPU VRAM. The cache keeps a 9MiB retained-texture
payload bound; when a dense/unknown viewport exceeds 144 tiles, extra textures
are transient and can exceed that limit for one submitted frame, but in-view
retained entries avoid full-cache LRU churn. First-time zoom-out population
may still be slow. See [T-086 measurements](../docs/Tickets/T-086.md).

## Editable text (T-058)

Choose **Text** then click the canvas to open a text dialog; **Cancel** or an
empty commit does not create a layer. The first successful commit atomically
creates one text layer/element. Select that text layer and use Text to edit
its content, point size, Regular/Bold/Italic font, color, alignment and
rotation. The Layer menu's **Rasterize text layer** command explicitly converts
editable text to ordinary pixels; Undo restores the original text and stable
layer ID. Paint/Erase can then edit the rasterized layer. Layer names and label
contents can be searched in the paged Layers view (200 rows per page).

Only Lato Regular/Bold/Italic are bundled, under `addons/drawing/fonts/`
(SIL Open Font License 1.1). The standalone `.drawing` file carries the
referenced font's full bytes and license, with a pinned identity and SHA-256.
In desktop exports, Godot stores imported `.fontdata` rather than a readable raw
`.ttf` file; the codec extracts the unchanged source bytes from the `FontFile`
resource, and the export preset includes the OFL license as an extra asset.
Missing/modified fonts fail explicitly, while unsupported glyphs show a visible
`?` replacement with a `GLYPH_FALLBACK` warning; original editable text is intact.
Arbitrary system fonts are never silently embedded. The same glyph atlas CPU path is used for
editable preview and rasterization so their RGBA8 output matches exactly at
native pixel density. Advanced typography, full Unicode fallback and Atlas-wide Object Editor integration remain downstream work.

```sh
# Import after each fresh --in-place staging to rebuild FontFile resources.
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/text_editor_smoke.gd
xvfb-run -a godot --display-driver x11 --rendering-method gl_compatibility \
  --path drawing --script res://tests/native_text.gd
```

Validate the font bundle **inside an exported Linux `.pck`** after building
`/tmp/drawing-dist/Drawing.pck` from `/tmp/drawing-dist/project`:

```sh
godot --headless --path /tmp/drawing-dist \
  --main-pack /tmp/drawing-dist/Drawing.pck \
  --script /tmp/drawing-dist/project/tests/packaged_fonts_smoke.gd
```

## Object Editor tabs (T-062)

The **Object** menu can open a new or existing object source in a dedicated
Drawing document tab using the **same** shared canvas, raster, selection,
editable text and layer-group tools. Object tabs display their own stable
source ID and revision; unsaved changes to content, name, origin and bounds
show `*`. **Save** publishes the current source; **Save As** from standalone
Drawing saves a distinct portable `.drawing` source with fresh document/layer
IDs and no Atlas binding. The Object menu includes rename, signed origin,
optional bounds guides, close tab and a Save/Discard/Cancel unsaved-close
prompt. File-native Object metadata (`drawing-object-source-v1`) is optional
inside the standard `.drawing` wrapper and is validated on load. Opening it
as a regular drawing still reads its pixels. Object bounds guide the author
but do not clip sparse pixels or discard transparent RGB.

The canonical drawing canvas and workspace scripts now reside **only** under
`addons/drawing/`, not `drawing/scripts/`; this allows Atlas's host window
to use exactly the same Drawing UI. In Atlas, the
`AtlasObjectEditorWindow` injects source publication and captured instance
selection through `AtlasObjectEditorBridge`; ordinary source Save refreshes
all linked placements and instance-launched Save As publishes B and rebinds
only the origin, with one Atlas history command. Undo retains the saved B.

**Asset Browser (T-065 engineering preview):** Choose **Window → Asset Browser…**
and select an existing absolute `Objects/` directory from a portable project.
The resulting panel is a normal, movable/collapsible dock peer of Colors,
Layers and History. It searches source *names* and stable *IDs*, lists loose
`Objects/*.drawing` and the newest `Objects/<id>/vNNNNNN.drawing`, and opens
selected sources in an independent Object Editor tab via **Edit Source**.
The source path appears as a tooltip; **Refresh** rechecks the folder. A
host embedding this workspace may set `initial_asset_browser_root` before
`add_child()` so the panel is registered before the T-083 layout restore.
The browser currently indexes source metadata on explicit refresh. Visible
rows render transparent 48×48 thumbnails from actual source pixels with a
bounded 192×192 center crop for oversized frames; a missing/empty authoring
frame previews a 128×128 neighborhood of the Object origin. At most two new
thumbnails are decoded per process frame; a 24-image content-hash cache is
invalidated on refresh or successful local Object Editor publication. External
changes require **Refresh** and cannot be opened from a stale listing. This
is **not yet** an Atlas instance-placement, source-deletion or NULL-repair UI.
**Import…** copies a separate valid `.drawing` into a standalone portable
`Objects/` root under its embedded stable ID; it refuses duplicate identities
and an Atlas-managed registry root because that requires campaign registration.
**Export…** writes the selected indexed source as a new portable `.drawing`
file, rejecting stale source bytes and existing destinations rather than
silently replacing files. Both commands use ordinary Godot file dialogs, not
a web runtime, and never delete artwork or create Atlas instances. Do not use source names as IDs
or take its list as authorization to delete unused variants. Atlas placement
and NULL repair/delete policy are still T-065 work; no automatic asset
relinking, deletion or publication is triggered by browsing.

**Atlas host behavior (T-065):** In Atlas's **Layers** sidebar, use
**Browse published Object sources** to see registry-backed assets and usage,
then drag an Object source over the map or select it and choose **Place at
view center**. The source creates one linked Atlas instance at the drop
coordinate, not another Drawing document. **Edit Source** opens the shared
Object Editor. Atlas's separate **Object Assets and missing links…** manager
owns campaign Import/Export, Source Delete (Remove/NULL/Cancel) and deliberate
NULL repair. A registry asset ID need not equal the embedded Drawing document
ID; the browser retains both, and Atlas validates path/hash/revision before
placement. The shared browser does not auto-import an unknown source.
Actual physical pointer gesture acceptance, large-library review and explicit
owner UX approval are still pending under T-065.

Atlas main-canvas `Edit Source` integration, instance placement, complete
Asset Browser/NULL management and campaign-wide atomic saves remain scoped
to T-055/T-065/T-066, respectively. The
Object Editor's initial UI is a reversible engineering implementation; owner
acceptance remains under T-056/T-059.

```sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
godot --headless --path drawing --script res://tests/object_editor_ui_smoke.gd
```
