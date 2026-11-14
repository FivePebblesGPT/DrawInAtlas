# Drawing owner acceptance — reproducible 23-finding runbook

**Prepared 2026-11-06, T-094.** This is an *execution plan*, not a successful re-review. The [2026-11-05 owner findings](DRAWING_USABILITY_REVIEW_2026-11-05.md) remain authoritative for the reported behavior; the scope of corrective tickets is approved for work, **not** the completed interactive UX. A passing headless smoke is never substituted for a physical pointer/display observation. Treat each row's state as a current evidence boundary, not a prediction.

## Reproducible environments and evidence form

1. Use the exact candidate PR commit (not an earlier `main` or local archive) and record `git rev-parse HEAD`, clean/unmodified canonical `addons/drawing/`, `godot --version` (target **4.8.beta3**), OS/build, CPU, GPU/renderer/driver, monitor scale/DPI, physical pointer model, window size, and display refresh rate. Build with `python3 tools/build_drawing_app.py --in-place`, then `godot --headless --editor --path drawing --import --quit`, then `godot --path drawing`. Run separately on **physical Linux and Windows**; an Xvfb/Mesa llvmpipe result must be labeled *software-only*, never as a physical GPU witness.
2. Use a fresh disposable workspace/profiles, with a known 256×256 transparent RGBA8 test document, a second opaque background, and three overlapping raster layers (top/middle/bottom) so eraser and non-top-layer compositing are visible. Also verify negative coordinates and a second file with a published reusable Object source. Record the exact `.drawing` SHA-256 before/after Save/Open; do not include private campaign files in public evidence. For viewport tests run 1280×720, 1366×768 and 1920×1080 at 100% and 150% UI scale; for stroke/zoom run 100%, 50%, 25% even if a safe test-only zoom path must enable the current 25% clamp.
3. For each row collect **before and after** screen recording with visible pointer/button state, before-release framebuffer readback when relevant, an exact pixel comparison or command result, a failure/repro log, and a named native test path. Record observations as `PASS`, `FAIL`, or `NOT RUN` separately for Linux and Windows, with the test commit/OS/GPU/size/DPI/zoom. For pointer/paint performance record per-phase samples and **median/p95** for down→first-uncommitted-visible-pixel, motion→visible-pixel, release→commit and frame submission; do not call frame submission physical input-to-photon latency.
4. The existing `drawing/tests/standalone_smoke.gd` is a headless model/GUI dispatch witness (including an exact `.drawing` roundtrip), and `drawing/tests/native_pointer.gd` is an earlier native pointer witness. Neither establishes continuous uncommitted paint, Windows presentation latency, or all 23 outcomes. Re-run the full standalone and Atlas regression when the dependent implementation milestones land. Keep every outstanding review gate unapproved until the owner explicitly accepts the demonstrated result.

## T-107 evidence readiness (not an owner result)

The [T-107 readiness ledger](evidence/T-107-2026-11-12-readiness.json) verifies
all 23 ticket/action links and records every current Linux/Windows physical
outcome as **NOT RUN**. Its archived 46/46 replay is a prior **local,
unattributed** diagnostic, not a successful GitHub Actions run on the new
candidate. Source and model tests do not change the owner states in this
runbook; the historical Save/Open pass (#22) and internal revision explanation
(#23) remain separate from physical interactive re-review.

## Recording physical results without implied signoff

T-094 includes a **local, non-uploading** evidence helper. Its templates are
explicitly `NOT RUN` for every finding; a test runner must never manufacture a
PASS. On each **actual hardware** test host, from the same source checkout:

```sh
python3 tools/drawing_owner_evidence.py init --os Linux --output /tmp/drawing-owner-linux.json
# On Windows, use: --os Windows --output path/to/drawing-owner-windows.json
# Fill environment fields, each finding's observed outcome, and evidence.
python3 tools/drawing_owner_evidence.py verify /tmp/drawing-owner-linux.json
# Optional: calculate the verified, per-zoom timing statistics for #01/#15.
python3 tools/drawing_owner_evidence.py verify --timing-summary /tmp/drawing-owner-linux.json
python3 tools/drawing_owner_evidence.py verify --require-complete \
  --expected-commit "$(git rev-parse HEAD)" \
  /path/to/drawing-owner-linux.json /path/to/drawing-owner-windows.json
```

`verify` checks all 23 IDs and current ticket mappings, rejects missing or
duplicate outcomes, requires a physical display/OS/device/Godot/commit/
window/scale/refresh/timestamp for any `PASS` or `FAIL`, and SHA-256 checks
every relative screenshot/log/video artifact against the exact bytes beside
the JSON. A `NOT RUN` row cannot contain old observations or artifacts.
Findings #01/#15 additionally need **separate timing samples at 25%, 50%
and 100% zoom**—at least five samples **per zoom and phase**, not five pooled
samples shared between zoom levels. In these two `PASS` rows, set
`zooms_percent: [25, 50, 100]` and populate `timings_ms` as a map from zoom
strings (`"25"`, `"50"`, `"100"`) to objects containing three arrays:
`down_to_preview_ms`, `motion_to_preview_ms`, and `release_to_commit_ms`.
Each array contains at least five finite nonnegative millisecond values.
Additional recorded zooms need their own complete measurements; missing or
unreported zoom keys, old pooled timing arrays, duplicate/malformed zooms,
and stale zoom claims on a `NOT RUN` row are rejected. For example, the
following is a **shape illustration only, not observed performance evidence**:

```json
{
  "zooms_percent": [25, 50, 100],
  "timings_ms": {
    "25": {"down_to_preview_ms": [1, 2, 3, 4, 5], "motion_to_preview_ms": [1, 2, 3, 4, 5], "release_to_commit_ms": [1, 2, 3, 4, 5]},
    "50": {"down_to_preview_ms": [1, 2, 3, 4, 5], "motion_to_preview_ms": [1, 2, 3, 4, 5], "release_to_commit_ms": [1, 2, 3, 4, 5]},
    "100": {"down_to_preview_ms": [1, 2, 3, 4, 5], "motion_to_preview_ms": [1, 2, 3, 4, 5], "release_to_commit_ms": [1, 2, 3, 4, 5]}
  }
}
```

Use `verify --timing-summary` to report the **sample count**, **p50 (median)**
and **p95** independently for each phase and each zoom on *validated PASS*
findings #01/#15. The calculation uses the R-7 linear-interpolation
percentile (`index = (n - 1) × p/100` on sorted samples); with only five
samples, p95 is interpolated 80% of the way from the fourth to the fifth,
not a guarantee about a real-time worst case. A `NOT RUN` or `FAIL` finding
prints no positive timing result, and an invalid or mixed-build report is
rejected *before* statistics are printed. This command **does not obtain
samples itself** or attest physical display latency; run on actual hardware,
record per-zoom **median/p95** and the timing method in `observed`, and keep
the original timestamped observations/artifacts for inspection. Godot frame
callbacks still are not physical input-to-photon proof.
The strict switch requires 23 physical `PASS` rows on *each* OS. A failed or
incomplete run is retained as a real `FAIL`/`NOT RUN`, never silently excluded.
When aggregating observed Linux/Windows results, the tool rejects **different
commit SHAs or Godot builds**, even if both JSON files individually validate.
Pass `--expected-commit` with the full tested target SHA to prevent a complete
report for an older, unintended revision. `NOT RUN` templates can coexist with
partial observations without impersonating a tested build.

The helper is a **format/integrity check**, not a cryptographic hardware or
owner-identity attestation; its `physical_display` field is self-reported.
Commit-specific OS evidence must still be independently reviewed with the
owner, and separate `manual_review: true` gates must be changed only with
explicit owner authorization. Keep private campaigns, personally identifying
screenshots, and platform-generated credentials out of Git and CI artifacts.

## Finding-by-finding owner check

In the **State** column, `PENDING` means a target ticket still owes a fresh interactive witness; `OWNER PASS / REGRESSION` is the reported positive tested flow, not universal file compatibility; `MODEL EXPECTED / UI PENDING` separates correct internal revision semantics from the unresolved display issue. The **Expected** column is the concrete pass criterion, not an assertion of current behavior. Each row must eventually receive a dated Linux/Windows result in owner review evidence.

| # | Target ticket | Physical action / setup | Expected result and native witness to add or rerun | Existing evidence limit | State |
| --- | --- | --- | --- | --- | --- |
| 01 | T-085, T-086 | On middle layer, hold 4px Brush still, then drag before release; test eraser too | First dab and motion visible **while held** without committing source/history; native framebuffer and timing 100/50/25% | T-085 Xvfb/Mesa held-button frame and layer-aware model pass; physical OS/GPU input-to-photon still untested | PENDING |
| 02 | T-087 | New transparent 256² frame over neutral workspace; pan to every corner | Distinct image edge and checkerboard, signed sparse pixels still valid; native framebuffer corners | T-087: 47/47 imported standalone model, 36/36 Xvfb/Mesa native checker/frame/pointer checks at 25/50/100/200%; physical OS/GPU owner result still NOT RUN | PENDING |
| 03 | T-090 | Resize physical window 1920×1080→1280×720, 100/150% scale | No letterbox/black side bars, usable tools and canvas; native window screenshots | T-090: 800×600/1280×760/1920×1080 software framebuffer edges and 1.5/2.0-scale screenshots pass; physical Linux/Windows NOT RUN | PENDING |
| 04 | T-090 | Hover brush-size field and wheel both directions, then paint | Value changes predictably or clearly routes to document zoom by documented design; native wheel/input readback | T-090: Xvfb real hovered wheel increment/decrement plus Shift+wheel and [/] keyboard checks pass; physical Linux/Windows NOT RUN | PENDING |
| 05 | T-088 | Select painted shape in two nonempty layers and drag boundary | Selection visibly limits edits and shows usable controls; native selection mask/pixel witness | T-088 model 131/131 and Xvfb/Mesa native 51/51 verify marquee/hole/keyboard plus persistent floating Move; physical hardware+owner NOT RUN | PENDING |
| 06 | T-090 | Inspect toolbar SVG icons at 100/150% and active/disabled states | Cohesive size/stroke/contrast and recorded licensing; screenshots + resource review | T-090 2026-11-07: 42px rail/34×34 controls, centered original MIT SVGs; Xvfb framebuffer centroids verified at 100/150/200% and six direct tool clicks (72/72 without captures, 78/78 with captures); physical/owner visuals NOT RUN | PENDING |
| 07 | T-091, T-083 | Resize a dock, close app gracefully, reopen same profile | Exact persisted usable dock width; native cold-relaunch layout snapshot | T-091 Xvfb/Mesa 36/36 dispatches a splitter drag, checks the saved width before shutdown and cold-relaunch recovery, including narrow-window persistence; physical hardware NOT RUN | PENDING |
| 08 | T-090 | Open File, Window and Object operations via menus and shortcuts | Discoverable commands grouped correctly and functioning; native menu dispatch screenshot | T-090: native popup item grouping, Ctrl+N and menu actions pass on Xvfb; owner physical interaction NOT RUN | PENDING |
| 09 | T-090 | Open two files; inspect tab strip, close via tab × | No detached far-right × or extraneous +; correct unsaved-close prompt | T-090: 24 native pointer/framebuffer checks (+5 PNG captures) include nonactive tab ×, dirty cancellation and saved close; owner physical NOT RUN | PENDING |
| 10 | T-091 | Float dock groups via drag and inspect nested tabs | Exactly one tabbed group per floating host; move between hosts safely | T-091 model 42/42, Xvfb/Mesa 36/36 and 2026-11-07 native multitab/redock 55/55 with two PNG readbacks verify one tab strip across same-frame redraw and unique views; owner physical review NOT RUN | PENDING |
| 11 | T-092 | Open Colors swatch on 1280×720 and 150% UI scale | Compact usable popup that does not occlude editor; native screenshot | T-092 2026-11-07: 55/55 model + 43/43 Xvfb/Mesa native (47/47 with four PNGs); separate selectable FG/BG pigment chips, explicit Swap/Default, hex/RGBA incl. zero-alpha hidden RGB, selected-role label, 190px dock + 150% and floating Colors. PhotoCraft 0.20.2 toolbar source cross-checked, executable Colors visuals NOT verified; physical hardware owner review NOT RUN | PENDING |
| 12 | T-091 | Float dock; grip drag, × close, resize each edge and corner | Minimal grip+tabs+× header, edge/corner resizing, subtle corner hint; native pointer/screenshot | T-091 Xvfb/Mesa 36/36 checks grip+tabs+×, all eight resize edges/corners, hide/recover and 1.5×; added 55/55 tall-host normal-grip redock/Escape and PNG evidence, physical Windows/Linux pointer discovery NOT RUN | PENDING |
| 13 | T-088 | Select nonempty mask, click truly blank canvas with Select | Deselects without selecting single pixel; inspect native selection state | T-088 Xvfb native click-empty/deselect assertions pass; physical owner NOT RUN | PENDING |
| 14 | T-088 | Create mask, paint/erase across mask edge on non-top layer | Independent selection channel constrains exact RGBA8 edits; compare framebuffer and layer bytes | T-088 mask now wired to live brush/eraser; model hole/alpha and Xvfb held-stroke witnesses pass; physical owner NOT RUN | PENDING |
| 15 | T-085, T-086 | Draw fast loops/self-crossing curve at 100/50/25% | All delivered samples/endpoints preserved, continuous visual motion, per-stage p50/p95 recorded | T-085 software 100/50/25% sample and p50/p95 recorded; hardware rapid strokes pending, T-086 68/68 Xvfb tile/alpha/text/overflow checks and 12-trial 25% software frames pass; hardware dense-window latency remains untested | PENDING |
| 16 | T-087 | Toggle Show Grid and Snap independently while zooming/panning | Grid visibility independent from snap, 8px snap observable and named; native pixel/coordinate check | T-087 Xvfb grid-line deltas after pan/zoom and native snapped mouse click pass; physical Windows/Linux UX result still NOT RUN | PENDING |
| 17 | T-088 | Select a painted region, choose Move, drag to empty area | Drag preview, exact translation, one Undo and Redo; native pointer + before/after pixels | T-088 2026-11-07 Xvfb 51/51 demonstrates after-release floating framebuffer, second drag, Enter drop, Escape cancel, one Undo/Redo; physical owner NOT RUN | PENDING |
| 18 | T-088 | With mask, Delete/Cut/Copy/Paste/Move then Undo/Redo | Correct clipboard pixels/alpha/mask constraint and edit history; native model + GUI witness | T-088 131/131 model preserves hidden RGB/seams/holes across repeated Move and Xvfb 51/51 keeps Ctrl+C/X/V/Delete roundtrip; physical owner NOT RUN | PENDING |
| 19 | T-089 | With 3 overlapping layers, toggle each row eye and lock | Inline eye/lock work and alter composite/edit eligibility predictably; screenshots/pixels | T-089 2026-11-07: 62/62 model and 36/36 Xvfb/Mesa native checks; repaired witness scrolls the real outer dock with paired wheel press/release before actual per-row eye/lock pointer clicks (earlier 9 failures were off-window clicks). Composition, edit denial and save/open still checked; physical Windows/Linux owner NOT RUN | PENDING |
| 20 | T-089 | Select nested group/layer, use +Layer/+Group and reorder | Correct parent and sibling position, structural Undo/Redo, stable IDs; native hierarchy smoke | T-089 model/native cover group vs paint target, consistent insertion, keyboard reorder, 205-row paging, structural undo/redo, stable IDs after file reopen and Object Editor; physical owner NOT RUN | PENDING |
| 21 | T-093, T-065 | Locate reusable object by folder/browser, open source in editor | Discoverable source, safe empty/NULL handling, editable source identity; native browser + Atlas integration | T-093: 56/56 model, 27/27 Xvfb/Mesa browser/root/pointer/framebuffer checks; T-065 portable and Atlas browser smokes pass. Separate OS FileDialog click, physical Windows/Linux source browsing, missing/NULL placement and explicit owner response NOT RUN | PENDING |
| 22 | T-094 | Paint then Save `.drawing`, close/open, check hidden RGB, IDs and undo | Byte-exact RGBA8 including transparent hidden RGB, stable IDs, clean savepoint, corruption rejected; `drawing/tests/standalone_smoke.gd` | Owner reported one successful flow, not every file | OWNER PASS / REGRESSION |
| 23 | T-092 | Paint, Undo, compare displayed history cursor and internal revision | History cursor moves backward while internal revision remains monotonic; native History dock screenshot | T-092: public history labels and cursor/total replace raw document revision in status; Xvfb 34/34 Undo/Redo readback confirms cursor decrements while internal revision increases; physical/owner re-review NOT RUN | MODEL EXPECTED / UI PENDING |

**T-080 post-T-082 docking evidence (2026-11-07, owner still PENDING):**
The native pointer test (70/70, or 71/71 with one framebuffer PNG) now
confirms that an invalid off-window drop is a no-op while the canvas remains
a valid T-082 detach destination, and a long last dock group offers an
*after-last-group* insertion when scrolled to the clipped bottom. The model
passes 60/60, with T-082/T-091 and T-083 neighboring regressions passing.
The T-081 native width assertion failed on that then-unchanged baseline;
it was subsequently repaired and reverified in the T-081 checkpoint below.
Software Xvfb evidence is not an approved physical Linux/Windows T-083
docking UX walkthrough.

**T-081 floating-host canvas-width corrective evidence (2026-11-07,
T-083 owner review still PENDING):** The earlier 1/54 native test failure
was reproducible: floating Colors reduced the right dock minimum from
184px to 182px and widened the canvas by 2px without user splitter input.
A stable 192px expanded-dock minimum now prevents this; native real-pointer
**58/58** (59/59 with one framebuffer PNG), T-081 ownership model **64/64**
and 5 fail-closed contracts pass on Godot 4.8 beta 2 Xvfb/Mesa. This does
not replace the separate physical Linux/Windows group-docking, narrow/
HiDPI and owner walkthrough under T-083, T-056 or T-059.

**T-087 PR #13 corrective evidence (2026-11-07, still owner PENDING):**
The original #02 frame check now also requires a wide Brush/Eraser stroke
from the image into the workspace to affect only in-frame pixels, while
preexisting off-frame sparse artwork still saves and reopens. Checker phase
must stay fixed at all four image/pan edges and all zooms. Signed model
**57/57** and Xvfb/Mesa native framebuffer/pointer **64/64** checks pass
(Godot 4.8 beta 2, 560×460 window, 310×260 canvas, 50/100/200% checker
pan sweeps; original 25–200% visibility check). This **does not** grant
physical Windows/Linux owner acceptance, replace T-059/T-056 or imply
that direct Atlas edits are framed.

## Gate and result handling

`T-056` (standalone/Atlas hands-on), `T-059` (full inventory UX), `T-065` (Object discovery), and `T-083` (revised docking) remain `manual_review: true` and require distinct **owner** responses; this runbook does not satisfy them. `T-085` through `T-093` own corrective implementations and new native witnesses, rather than T-094 preemptively marking their findings fixed. Every future checked result should append: `(date, ticket, commit, OS, renderer/GPU, viewport/DPI, zoom, action, expected, observed, test/log/screenshot or pixel hash, reviewer decision)`. If any row fails, retain the failure and link an open follow-up ticket; do not silently relabel it as a pass.
