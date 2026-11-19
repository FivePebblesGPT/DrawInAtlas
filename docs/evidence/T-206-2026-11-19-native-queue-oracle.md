# T-206 — restore required-native T-124 chronological queued-stroke regression

**2026-11-19; PR #21 local candidate.** Base GitHub PR head `9aa1cbe0`;
this ticket follows ten already packaged local commits. Godot
`4.8.beta3.official.c51ff06e8` on Linux x86-64, pinned offline Hokusai/Rust
GDExtension, and Xvfb/Mesa llvmpipe for raw-pointer framebuffer tests.
No physical input, Windows or hosted GitHub CI was exercised.

## Fail-first: two obsolete historical assumptions

| Original fixture | Exit | Evidence |
| --- | ---: | --- |
| `t124_queued_brush_smoke.gd` | 1 | **12/69** failures, all four queued Brush/Eraser cases fail at two-transaction pixel parity, first Undo and final Redo against the retired `DrawingEditSession.paint_path` raster algorithm |
| `t124_queued_brush_native.gd` | 1 | **6/19** failures; the 190-point predecessor completes during the newer 256-segment release drain, so the second raw pointer stroke is no longer deferred. Remaining failures compare against the same retired rasterizer and expect an exact opaque framebuffer pigment. |

Both tests remain part of the required CI inventory; old results were not
reclassified as success. The production queue and native rasterizer were
**not changed**. The legacy edit-session API can still be independently tested
in its own scope; it cannot serve as an exact Hokusai pixel oracle.

## Exact source/time-native control

`drawing/tests/t206_native_queued_reference.gd` creates a **different
DrawingDocument and Canvas** with the same required Hokusai engine, disconnects
its post-draw callback, commits two strokes **sequentially** and checks each
native revision/history step. The live Canvas queue is not used by the reference.

- The headless test records the actual first press, native-accepted motions,
  and release including `press_us`, `_sample_times_us` and explicit release
  timestamp. A queued second stroke is captured from its deferred source/time
  buffers before promotion; for a held successor, it additionally captures
  actual active-canvas motion and release after promotion.
- The X11 test now routes **840 actual mouse events** for the predecessor,
  not a short stroke that can finish synchronously. It reads every accepted
  source point and receipt, and snapshots the deferred pointer samples before
  promotion. Godot can route an extra endpoint motion at button-up; the test
  records and replays that real event, rather than rewriting the sample count.
- Both tests replay frozen first/second width, ABGR pigment, hard-round preset,
  tool identity and selection (including the headless mask's excluded hole).
  Resulting source is compared byte-for-byte after both commits, both Undo
  operations and both Redo operations; negative changed-width reference must
  diverge. Both final strokes must change actual source pixels.
- Existing queue overflow/error, predecessor fault injection, source
  authorization and navigation-after-release checks remain intact. The
  X11 fixture continues to require actual Godot GUI dispatch and framebuffer
  pigmentation, not merely a headless source render.
- `tests/test_t124_queued_stroke_ci.py` also enforces the native reference
  instead of legacy `paint_path` while preserving the strict CI marker names.

The reference shares the same native rasterizer, so this establishes
**chronological queue and parameter parity**, not independent artistic
correctness. The X11 runner is software-rendered: these tests establish
neither physical mouse-to-photon timing nor full hardware FPS.

## Reproducible validation

```sh
G=/mnt/data/toolchain/bin/godot
export GODOT_SILENCE_ROOT_WARNING=1
$G --headless --audio-driver Dummy --path drawing \
  --script res://tests/t124_queued_brush_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' "$G" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t124_queued_brush_native.gd
python3 tools/check_godot_model_log.py <log> --marker T124_QUEUED_PASSED
python3 tools/check_godot_model_log.py <log> --marker T124_NATIVE_PASSED
python3 -m unittest discover -s tests -p 'test_t124_queued_stroke_ci.py'
make python-test
# Rust offline: tools/build_native_brush.sh --test with bundled Cargo/vendor
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

| Validation | Exit | Result |
| --- | ---: | --- |
| Final headless runs 1–4 | 0 each | **78/78**, each; frozen Brush/Eraser queue, release vs held, overflow and history |
| Final native-X11 runs 1–3 | 0 each | **20/20**, each; 840 raw predecessor events, true queued successor, framebuffer and native parity |
| Strict Godot marker checks | 0 each | Both headless and X11 markers accepted without script errors |
| T-124 CI-source tests | 0 | 3/3 |
| Toolchain Python (`make python-test`) | 0 | **56/56**, seven groups |
| Offline native Rust | 0 | **35/35** |
| Explicit GDScript types | 0 | 520 scripts and 33 skill documents |
| Project-defined Ruff/ty targets | 0 each | Both passed |
| Ticket-store validator | 0 | **206 tickets**, statuses, dependencies and manual-review gates |

A deliberately wider exploratory `ruff check tests` reported 69 existing
historical style findings in unrelated test files. It was **not** the
repository's defined lint target and is preserved as a non-green exploratory
result (`ruff.log`), not presented as a pass or as a T-206 regression.
The initial post-refactor CI-source test also correctly failed until it
followed the extracted shared helper; its fail-first test log is retained.

### Neighboring unmodified headless regressions

| Test | Exit | Marker |
| --- | ---: | --- |
| T-125 pending persistence | 0 | 29/29 |
| T-126 tab switch | 0 | 34/34 |
| T-130 source context | 0 | 34/34 |
| T-085 live model | 0 | `T085_MODEL_PASSED` |
| T-087 image frame | 0 | `T087_MODEL_PASSED` |
| T-127 pending history | **1** | 7/40 assertions fail |
| T-128 History list | **1** | 8/37 assertions fail |
| T-129 pending content edits | **1** | 2/35 assertions fail |

T-127/T-128/T-129 failures remain **open, not silently repaired or waived**.
Their raw process exits are preserved for independent follow-up. Hosted
T-106/T-180, T-095/T-197 physical performance and T-148/T-149/T-150
native-transition gates remain open; no owner review was self-approved.

## Byte-exact evidence

Raw logs, both fail-first witnesses, all final process exits, successful
regression runs, the exploratory lint warning, and intermediate corrections
are under [`T-206-2026-11-19-native-queue-oracle-raw/`](T-206-2026-11-19-native-queue-oracle-raw/).
They are kept unmodified, with a scoped raw-whitespace `.gitattributes` rule.

- Headless fixture SHA-256: `7c95750d699d4928a9005de2e1ef3b4a1a7291990c74588bfde6f924bf1e79b3`.
- Native-X11 fixture SHA-256: `438bc80bf8bbde6f4a10c81ec1fd6c044d593085ca6280ff9ee9fb49902bd682`.
- Shared reference SHA-256: `d87954a6741d8fd1e4c79269b949d9e520f385289af7a1f753a5ab6f6072932a`.
- Required `libdrawing_brush.so` SHA-256: `dcaf73fa6e0b113f76aa12d6072a598406dea19e5a12a026db47334df2e45074`.
- Raw fail-first logs SHA-256: headless `ca77d687cf1c1cfa81f57af4cd59b7c986bc8abd4740495f52533f9b9430dcbc`; X11 `772dc7c59d80d314b3b78c30b5ba81064e6371594dcddf900ce66e6b86b7b4c6`.
- Raw final sample logs SHA-256: headless `c15f08d6be1b1a3e6478e5170b679acfe07dbb2c9adf74f3fb94c9d608e7d5c0`; X11 `06b1a78c71c2b9a925e4b119ca70d77d38782da9be196421290f614d98b1ce14`.
