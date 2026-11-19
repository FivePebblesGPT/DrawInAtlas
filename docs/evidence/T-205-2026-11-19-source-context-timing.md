# T-205 — required-native pending source-context timing regression

**2026-11-19; PR #21 local candidate.** Remote baseline `9aa1cbe0`, with the nine previously delivered local patches replayed. Runtime: Godot `4.8.beta3.official.c51ff06e8`, Linux x86-64, required locally built Hokusai GDExtension; X11 uses Xvfb/Mesa software rendering. No physical pointer/display, Windows or hosted GitHub CI.

## Failure and invariant

The untouched `drawing/tests/t130_pending_source_context_smoke.gd` fails **exactly 1/34** assertions, process **exit 1**: `Deselect cannot invalidate source on later frame`. It expected `Canvas.has_pending_stroke()` to remain true after exactly two Godot frames. The native engine can legitimately drain and atomically commit both queued gestures within that window. This timing prediction is not part of T-130's integrity requirement.

The replacement single assertion accepts **only** these two states after the window:

1. The original nonempty selection mask is still byte/geometry-equivalent and at least one native stroke is still pending; **or**
2. The same original mask is unchanged and both native transactions have committed, reflected by document revision **and** history position advancing by two.

No early selected-mask mutation or partially published session is accepted. All preceding checks still verify the refusal occurs *while pending*, leaves the native queue intact, preserves revision/history, and displays an actionable message. Subsequent checks still require completion, both source paths' painted pixels, a post-commit Deselect, Save/Open, standalone image-frame refusal and Object-frame refusal. **All 34 assertions, the existing required CI marker and production Painting/Workspace source are unchanged.**

## Reproducible tests

The native Rust library was compiled fully offline with the provided pinned Rust/vendor toolchain, then staged into standalone Drawing; the Godot beta3 editor import and `native_extension_ready.gd` exited zero. The pre-fix run was created by temporarily replacing the new two-state assertion with the original one, running the same engine and restored source, then re-running the repaired source. Environment includes `GODOT_SILENCE_ROOT_WARNING=1`.

```sh
G=/mnt/data/toolchain/bin/godot
$G --headless --audio-driver Dummy --editor --path drawing --import --quit
$G --headless --audio-driver Dummy --path drawing --script res://tests/native_extension_ready.gd
# Before: exact original assertion restored temporarily; exit 1, 34 checks, 1 failure
$G --headless --audio-driver Dummy --path drawing --script res://tests/t130_pending_source_context_smoke.gd
# After: fixed assertion; four independent exit-0 headless runs
xvfb-run -a -s '-screen 0 1280x900x24' $G --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t130_pending_source_context_smoke.gd
# After: two independent exit-0 X11 runs
python3 tools/check_godot_model_log.py headless-1.log --marker T130_CONTEXT_PASSED
python3 -m unittest discover -s tests -p 'test_t130_pending_source_context.py'
make python-test
python3 tests/check_explicit_types.py
# Rust: tools/build_native_brush.sh --test, offline vendor+locked target
python3 tools/validate_ticket_store.py
```

| Run | Exit | Marker and assertion result |
| --- | ---: | --- |
| Original two-frame assertion | **1** | `T130_CONTEXT_FAILED checks=34 failures=1` |
| Patched headless 1–4 | **0 each** | `T130_CONTEXT_PASSED checks=34 failures=0`, each |
| Patched native-X11 1–2 | **0 each** | `T130_CONTEXT_PASSED checks=34 failures=0`, each |
| Strict required model-log parser | 0 | Exactly one recognized success marker; no forbidden script errors |
| T-130 Python source/CI contracts | 0 | 2/2 |
| Toolchain Python | 0 | **56/56**, seven groups |
| Rust native extension tests | 0 | **35/35** |
| Explicit GDScript types | 0 | 520 scripts and 33 skill documents |
| Ruff / ty (pinned offline wheels) | 0 / 0 | Both passed |
| Ticket validator | 0 | 205 tickets; status, dependencies and manual gates validated |

### Neighboring local headless checks (unaltered)

| Regression | Exit | Result |
| --- | ---: | --- |
| T-124 queued Brush | **1** | 12/69 failures, historical exact-pixel and Undo/Redo oracle |
| T-125 pending Save/Close | 0 | 29/29 |
| T-126 pending tab switch | 0 | 34/34 |
| T-127 pending history | **1** | 7/40 failures |
| T-128 History list | **1** | 8/37 failures |
| T-129 pending content edit | **1** | 2/35 failures, remaining next-frame scheduling assumptions |
| T-085 native live-stroke model | 0 | 81/81 |
| T-087 image-frame model | 0 | 82/82 |

These failures are **not** treated as valid test passes, repaired incidentally, or proof of production bugs; they require independent diagnosis before status changes. T-106/T-180 remain In Progress and their hosted inventory remains open. T-095 hardware owner acceptance, T-148/T-149/T-150 architecture, 200ms p95 and real FPS gates remain open.

## Byte-preserved evidence

All raw logs and a machine-readable neighboring-exit list are under [`T-205-2026-11-19-source-context-timing-raw/`](T-205-2026-11-19-source-context-timing-raw/). Repeated headless logs are identical in content; all six actual command exits were recorded separately. The logs are retained byte-for-byte, with a `.gitattributes` raw-whitespace exception.

- Corrected `drawing/tests/t130_pending_source_context_smoke.gd` SHA-256: `4c82024d5b25a7506cc76e6af3a81a5c9a10575b809ee499c177c36d2042cefe`.
- Offline native `libdrawing_brush.so` SHA-256: `dcaf73fa6e0b113f76aa12d6072a598406dea19e5a12a026db47334df2e45074`.
- Fail-first `before.log` SHA-256: `37575837f2d7e0105895313c86f2096c3eff2af0ebd7331f511e24b957d81697`.
- Each of four headless logs SHA-256: `3be18ff326a66b01283574bf4d38896ba6b21a9dbfd0f92668c4166f3843c425`.
- Each of two software-X11 logs SHA-256: `18f91d546598d5e0effa712b48c53aa565f6c4b6754ab56d52f9c63cd9cfe45f`.
- `neighbors-exits.txt` SHA-256: `41e3af96b6176fd17c882bd7aeb9a6fbbfe37a8acd1f43b1287304b1fa380abc`.

**Scope:** One historical test-oracle correction, not an application optimization, hosted-CI green claim or manual-review decision.
