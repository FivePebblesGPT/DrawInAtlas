# T-092 — current native Colors/History engineering closure (2026-11-22)

## Scope and approval boundary

Current local checkout of PR #22, starting from remote `7b1fd306` plus
unpublished T-251/T-252/T-253/T-254/T-087/T-090 commits. This ticket
revalidates the existing standalone Colors/History/preferences implementation
under the mandatory Hokusai-only native extension, adds a real Atlas-hosted
History/Preferences test, and repairs the **on-demand** CI workflow for a clean
checkout. **No production Drawing or Atlas feature implementation changed.**

The current UI uses the owner-directed inline native ColorPicker and compact
FG/Swap/BG/recent strip from T-226/T-252, not the superseded collapsed
Advanced picker / Restore previous swatches recorded in T-092's older notes.
The selection-history preference stays under Edit → Preferences, disabled by
default, and not in a History panel row. History displays its own action
cursor (`n / m`) while retaining monotonically increasing internal revisions.

**Engineering Done does not mean owner-approved:** T-250 remains at **Manual
Review**; T-059's actual-screen Drawing UX, T-056's integration acceptance,
Windows/physical Linux devices and hosted GitHub runs remain unverified.

## Reproduced problem and corrected CI contract

- Previously, `.github/workflows/godot-native-t092-color-history.yml`
  staged/imported Drawing without installing Rust or building the required
  native GDExtension. No tracked `.so` exists in a clean checkout. The on-demand
  job therefore could not reliably exercise its advertised native witness.
- Added pinned Rust **1.99.1** (`toolchain.lock.toml`) and `make build
  TOOLCHAIN=system`, which builds the canonical extension and imports both
  Drawing and Atlas consumers. It also runs the headless Colors/History
  model, the standalone X11 screenshot/gesture tests and the new Atlas-hosted
  X11 History test with strict marker/log verification and uploaded logs.
- Added contract assertions to `tests/test_t092_color_history.py` **before**
  changing the workflow; five new assertions initially failed against the
  previous CI configuration, then all six Python cases passed after repair.
- The local environment has no crates.io network access: a first raw system
  build failed trying to fetch crates; rerunning the same `make build` target
  with `CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor` and
  `CARGO_NET_OFFLINE=true` built the native Rust library, imported Drawing and
  Atlas, and returned `NATIVE_EXTENSION_READY` for both. GitHub runners can
  fetch dependencies normally; this is not proof of hosted Actions success.

## New Atlas integration witness

`tests/t092_atlas_history_native.gd` uses a real software-X11 window and the
same embedded `addons/drawing/workspace.gd` component with a live
`AtlasCampaign`, `AtlasDrawingRegistry`, `AtlasEditHistory` and one Rust-native
raster transaction. It explicitly attaches that host-owned DrawingDocument to
the shared workspace UI and verifies:

- History shows `History owned by host`, has no local command rows and disables
  standalone Undo/Redo buttons; the status shows `history 0/0`, not an Atlas
  internal revision disguised as an undo cursor.
- Selection-history preference toggles propagate across open tabs but cannot
  fabricate local history, invalidate the Atlas native token, or mutate
  existing pixels. UI-only BG hexadecimal edit preserves zero-alpha RGB,
  while foreground Brush paint remains unchanged.
- Clicking a host-owned History placeholder is inert. Atlas global Undo/Redo
  still restores and reapplies an exact signed-coordinate native pixel with
  hidden RGB; local History stays empty throughout.

The test reports `T092_ATLAS: 21 checks; 0 failures` and a unique
`T092_ATLAS_PASSED` marker. It is **integration testing**, not a physical owner
walkthrough or proof of standalone native Preferences-modal pointer delivery.

## Local validation — Godot 4.8.beta3.official.c51ff06e8

Linux x86_64, Xvfb + Mesa llvmpipe software OpenGL 4.5, Godot's dummy audio
driver; default 1280×800, 190px dock, 150% UI scale, 300×440 floating Color
host. Source/screenshots are in the local run, not part of this patch archive.

| Suite | Observed result |
| --- | --- |
| T-092 standalone Colors/History model | **66/66**, no errors |
| T-092 native X11, 4 screenshots | **57/57**, no errors |
| T-092 new Atlas-hosted History/selection preference X11 | **21/21**, no errors |
| T-226 Colors model / native X11 / Atlas native | **21/21 · 39/39 · 17/17** |
| T-252 Colors model / native X11 / Atlas native | **56/56 · 35/35 · 31/31** |
| T-083 dock persistence X11 | **63/63** |
| T-090 responsive workspace X11 | **83/83** |
| T-254 flyout X11 | **178/178** (separate independent rerun exited 0) |
| T-092 Python contract tests | **6/6** after five fail-first assertions |
| Ticket-store validator | **254 tickets**, dependency/review gates valid |

The long sweep's outer shell timed out at the final T-254 boundary. An
independent follow-up T-254 invocation subsequently **exited 0** with
`178 checks; 0 failures` and `T254_FLYOUT_NATIVE_PASSED`. The T-092 and
Atlas suites themselves exited successfully. The explicit-typing audit also
passed on **576 project GDScript files and 33 skill documents**. Ticket-store
validation passed **254 tickets** with all manual gates preserved.

## Remaining physical/manual gates

The updated UI still needs comparison with the owner's checked-in concept
(`docs/assets/drawing-ux-2026-11-22/DrawInAtlasColorPanelConcept.png`) on the
actual device, including modal Preferences pointer focus, 150–200% monitor
scaling and Windows/Linux behavior. These are **T-250/T-059/T-056** review
requirements; this engineering ticket grants none of their approvals.
