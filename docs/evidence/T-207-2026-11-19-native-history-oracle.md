# T-207 — Native Hokusai pending Undo/Redo fixture revalidation

**2026-11-19 · local PR #21; remote baseline `9aa1cbe0`.** Engine:
Godot `4.8.beta3.official.c51ff06e8`, native `libdrawing_brush.so`,
Linux x86-64, headless and Xvfb/Mesa software-X11. Neither physical input
nor hosted CI or Windows was used.

## Fail-first and actual contract

The unchanged historical `drawing/tests/t127_pending_history_smoke.gd` exited
**1** with **7/40** failed checks (see byte-exact `before.log`). Five failures
followed from an unpainted 3px stationary dab used as an Undo candidate; two
were assertions that unfinished native input **must** still be pending after
exactly two process frames. T-127's production Undo/Redo guard remained in
place, refusing actions while a native stroke was genuinely pending. The
historical Legacy raster and two-frame timing expectations were not valid
oracles for the current Hokusai engine.

The new fixture moves a **24px** Hokusai Brush across the original pixel and
requires real committed source alpha before testing history. Both initial
Undo and initial Redo refusals now verify that **revision and history cursor**
remain unchanged; direct actions, menu/keyboard shortcuts and History buttons
still use the original guard, and the existing warning checks remain intact.
After exactly two drain frames, either a stroke is still pending **or** the
entire expected ordered transaction sequence has published (revision **and**
history cursor advanced by two for the queued Undo scenario, one for the
new-branch Redo scenario). The subsequent wait and checks still require exact
final transaction counts, independent source pixels, prior pixel preservation,
Undo/Redo chronological behavior, complete 256×256 RGBA8 equality after Redo,
and byte-equal Save/Open output. No partial final transaction counts are
accepted. The CI marker remains **`T127_HISTORY_PASSED checks=40 failures=0`**.

`tests/test_t127_pending_history.py` adds a source contract rejecting the
stationary Legacy dab and old frame-lifetime assertions. No product workspace,
Canvas, native engine or CI workflow is modified.

## Reproducible commands and exits

The supplied toolchain and existing staged native library were used. Logs are
captured under [`T-207-2026-11-19-native-history-oracle-raw/`](T-207-2026-11-19-native-history-oracle-raw/).
The `runs.tsv` and `neighbors.tsv` files contain the actual process exits,
not marker-only assumptions. `sha256.txt` records raw-file integrity.

```sh
export GODOT_SILENCE_ROOT_WARNING=1
G=/mnt/data/toolchain/bin/godot
$G --headless --audio-driver Dummy --path drawing \
  --script res://tests/t127_pending_history_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' "$G" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t127_pending_history_smoke.gd
python3 tools/check_godot_model_log.py headless-1.log --marker T127_HISTORY_PASSED
python3 -m unittest discover -s tests -p 'test_t127_pending_history.py'
make python-test
python3 tests/check_explicit_types.py
# Rust: with pinned Cargo, local vendor and CARGO_TARGET_DIR:
CARGO=/mnt/data/toolchain/rust/bin/cargo \
CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor CARGO_NET_OFFLINE=true \
CARGO_TARGET_DIR=/mnt/data/work/target bash tools/build_native_brush.sh --test
python3 tools/validate_ticket_store.py
```

| Check | Process exit and verified result |
| --- | --- |
| Original T-127 fixture | **1**, `T127_HISTORY_FAILED checks=40 failures=7` |
| Final headless ×4 | **0 each**, 40/40, strict log verifier pass |
| Final software-X11 ×2 | **0 each**, 40/40, strict log verifier pass |
| T-127 Python source/CI contract | **0**, **4/4** |
| Native Rust (offline, pinned vendor) | **0**, **35/35** |
| Toolchain Python (`make python-test`) | **0**, **56/56** |
| Explicit GDScript types | **0**, 521 project scripts, 33 skill documents |
| Pinned Ruff/ty project lint targets | **0 / 0** |
| Focused Ruff on edited Python test | **0** |
| Ticket-store validator | **0**, **207** tickets and manual gates |

The first native Rust test invocation lacked `rustc` on PATH and exited 101;
rerun with the bundled Rust `bin` directory on PATH passed 35/35. The final
`rust-tests.log` contains the corrected zero-exit run. The first focused
Ruff invocation found a pre-existing import-order issue in the touched Python
test, which was corrected; the retained final `t127-ruff.log` passes. Neither
transient tooling configuration issue changed production code.

### Neighboring unchanged regressions

| Native Drawing suite | Exit | Result |
| --- | ---: | --- |
| T-124 queued Brush | 0 | 78/78 |
| T-125 persistence | 0 | 29/29 |
| T-126 tabs | 0 | 34/34 |
| T-130 source context | 0 | 34/34 |
| Required-native Drawing integration | 0 | `T095_NATIVE_BRUSH_RESULT checks=32 failures=0` |
| T-124 real pointer/X11 queue | 0 | 20/20 |
| T-128 History list | **1** | **8/37** failures |
| T-129 pending content edits | **1** | **2/35** failures |

The T-128 and T-129 failures are *not* attributed to or fixed by T-207;
they remain separate regression repairs. Both are retained with their actual
error lines and exits. This ticket neither optimizes runtime performance nor
establishes 200ms p95, sustained display FPS, physical responsiveness,
Windows compatibility, hosted green CI or owner UX acceptance.

## Integrity

- Final native Hokusai witness SHA-256: `578fcde5b9fa4c85760ce995c6094c415e12d2e4ed8232d5e2114543ab15a043`.
- Native library SHA-256: `dcaf73fa6e0b113f76aa12d6072a598406dea19e5a12a026db47334df2e45074`.
- Fail-first raw log SHA-256: `e30aad51aed9b9ca337e7b55b8dd312a46f373a81848849300120ff784accffd`.
- Final representative headless log SHA-256: `484fd31e6d843bf169978f0ff1cd5a11a155d83c86f8add095a75a8476ac0e21`.
- Final representative X11 log SHA-256: `4533c64832ca3c32631c2ad07184deeb24d16501915d20d2834364e67def9942`.

Raw Godot warnings after expected blocked Undo/Redo actions are retained
byte-for-byte; they do not constitute crash or assertion failures. The
strict verifier accepts all final T-127 process logs. No manual-review gate
was self-approved.
