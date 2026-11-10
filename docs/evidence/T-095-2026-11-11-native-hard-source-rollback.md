# T-095 — 2026-11-11 NativeHard/GDScript source-read rollback

## Scope, decision and environment

- Work remains on `sprint/2026-11-11`. Remote base before this checkpoint:
  `f9e54fdfc81fb72840023665694fb24b55fb220e`; the previous local
  `ad2c55f` pigment rollback checkpoint is included in the cumulative delivery.
- T-095 is **In Progress**, `manual_review: true`, with completed T-053
  prerequisite. T-096 remains independently in Manual Review. No owner approval,
  hosted Actions pass, physical input-to-photon evidence, or PR merge is claimed.
- Linux software checks use the supplied Godot `4.8.beta3.official.c51ff06e8`,
  pinned offline Rust 1.99.1, godot-rust 0.5.5, Hokusai 0.3.0 and the locally
  compiled `DrawingNativeBrush` GDExtension. The native binary/build caches
  are **not** committed.

## Failing real-native control before implementation

`drawing/tests/t095_native_hard_source_atomic.gd` constructs independent
real-GDExtension/source-document pairs. After a successful initial NativeHard
sweep, the fault-injected document rejects its **second** newly resolved source
storage tile in the next sweep. Because the old native `hard_segments` already
mutated its covered-pixel set and previous point, the existing GDScript paint
journal restored the *preview* but could not restore native coverage. The
same batch on retry then omitted pixels; merely skipping it also changed a
later swept segment's start point and generated different coverage.

On the unmodified addon/native binary, the first Brush-only control failed
**7 of 53** checks (same-batch retry, following pigment/coverage, signed
committed RGBA8 and Redo; plus skip-failed-batch coverage, commit and Redo).
The rejected source call itself correctly returned `INJECTED_TILE` after two
source resolutions. Thus the failing assertions are native/GDScript rollback
parity, not synthetic malformed Rust input, device performance, or a fabricated
error from an unavailable native class.

## Fix

- NativeHard has `begin_hard_batch`, `commit_hard_batch` and
  `rollback_hard_batch`. It snapshots only its prior segment endpoint and
  journals **only newly inserted** coverage coordinates during a pending
  GDScript sample batch. Rejection removes those coordinates, restores the
  endpoint and leaves older accepted coverage intact. A successful batch
  discards its journal. No full accumulated coverage-set clone is made.
- `DrawingEditSession.paint_path_native_hard` begins a native batch before
  requesting points; it rolls back on native error, invalid delta shape or
  any source/selection/staging failure. It acknowledges native coverage only
  after the entire GDScript staging loop succeeds. Existing local GDScript
  rollback continues to preserve preceding accepted preview/history.
- `DrawingCanvas` requires all three methods before selecting NativeHard;
  older real binaries fall back to Legacy **at gesture start**. Direct calls
  through `DrawingEditSession` reject an incompatible real binary without
  staging. Scripted deterministic native oracles retain their prior contract.
  The previous Hokusai transaction API and its separate rollback are untouched.
- No new brush presets, stamp formats, document serialization, selection
  behavior, exported native binaries or status changes are introduced.

## Verification completed locally

- The expanded real-native Brush **and Eraser** witness passes **113/113**.
  Each tests reject-then-retry and reject-then-skip, clipped signed input,
  large positive/negative 64-bit document anchors, original translucent and
  hidden-RGB source pixels, boolean selection holes, no partial preview,
  canonical commit, Undo and Redo against independent engine/document pairs.
- NativeHard whole-batch invalid-input/clip control **28/28**; Hokusai
  pigment rollback **57/57**; native preset integration **30/30**; native
  export cache **81/81**; Hokusai delta **126/126**; signed native shift
  **422/422**; source Brush oracle **32/32**.
- Deferred Legacy brush stage **492/492**; Legacy publish **519/519**;
  failed mixed-edit recovery **504/504**; sparse preview **133/133**;
  native tile publish **56/56**; bounded stage batch **29/29**; queue
  compaction **31/31**; latency ring **22/22**; stage result ownership
  **30/30**; oblique geometry **86/86**; signed stage tile lookup
  **4193/4193**; existing live-stroke model passed.
- Rust unit tests **5/5** (including new per-batch journal rollback),
  offline locked release build, `cargo fmt --check` and
  `cargo clippy --all-targets -- -D warnings` pass.
- Native-present Canvas/fallback **7/7**; actual preceding real native binary
  without the NativeHard transaction API **8/8**, selecting Legacy while
  retaining the Hokusai path and rejecting a direct incompatible session call
  before staging. The compatible binary was rebuilt/restored. A separate
  clean staged project with **no GDExtension** imported and passed fallback
  **7/7** with process code 0.
- Xvfb/Mesa `stroke_navigation_native.gd` **48/48**; 60px/786% actual
  mouse-input `brush_latency_native.gd` exited 0 (`T095_NATIVE_PASSED`),
  five 120-motion strokes, stage p50 **180.852 ms**, p95 **188.052 ms**;
  release-to-commit p50 **57.517 ms**, p95 **68.327 ms**;
  `max_pending=22`. These **are not paired before/after speed measurements**.
  The PR #14 signed pixel seam witness asserts **17/17** and its process
  exited 0, but the raw log retains Godot GL/RID shutdown leak diagnostics;
  it is not described as a diagnostic-clean exit.
- On-demand workflow adds the strict native source-read witness with marker
  `T095_NATIVE_HARD_SOURCE_ATOMIC_PASSED` and uploads its raw log. It does
  not expand or change the 46 required fast-CI check IDs. Hosted workflow
  execution is unverified.

## Remaining gates

The owner's physical 60px Brush catch-up rejection still controls. These
checks do not establish a physical motion-to-photon budget, Windows/macOS
export compatibility, acceptable custom-stamp headroom, or explicit owner
re-acceptance. T-095 stays **In Progress**, with manual review required;
T-096's separate Manual Review cannot be self-approved.
