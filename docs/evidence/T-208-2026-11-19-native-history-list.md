# T-208 — required-native History-list pending Brush regression repair

**2026-11-19 · PR #21 local only; GitHub head `9aa1cbe0`.** Godot
`4.8.beta3.official.c51ff06e8`, pinned native Hokusai/Rust extension,
headless and software-X11 via Xvfb. No physical pointing device, hosted CI,
Windows export or owner approval was exercised.

## Reproduced failure and bounded correction

The untouched `drawing/tests/t128_history_list_pending_smoke.gd` exited **1**
with **8/37 failed assertions**. Both prior-history setup strokes used a
stationary 3px Brush dab. Native Hokusai did not necessarily produce pixels
or an Undo candidate, so the test had no two older History rows and several
subsequent navigation claims failed. The test also required a blocked
History-list jump to leave input pending *after exactly two frames*, which
rejects a legal full native queue publication. The fail-first process is
preserved as `before.log`.

The existing History-list production guard was **not modified**. Both setup
strokes now sweep a **24px** Brush through the specified source pixels, with
separate native History transactions. The two-frame assertion now accepts
**either** a still-pending transaction **or** two fully published queued
transactions with both document revision and History cursor advanced by two.
It rejects a partial or cancelled publication. The unchanged 37 assertions
still verify rejected backward/forward list selection, actual selected-row
restoration, actionable warning, same-row no-op, pending queue integrity,
atomic chronology, exact RGBA8 Undo/Redo, previous source preservation,
and `.drawing` Save/Open. The required CI marker remains
`T128_HISTORY_LIST_PASSED checks=37 failures=0`.

`tests/test_t128_history_list_pending.py` now rejects the obsolete
3px/no-motion/fixed-two-frame fixture and keeps the original source guard
and workflow-marker contracts. Importing the shared log verifier as a
`tools` module also makes its focused Ruff and ty checks resolvable without
changing the CI invocation.

## Reproducible validation

The immutable raw process logs, exit tables, and hashes are in
[`T-208-2026-11-19-native-history-list-raw/`](T-208-2026-11-19-native-history-list-raw/).
Use these commands from the repository root with the installed pinned tools:

```sh
export GODOT_SILENCE_ROOT_WARNING=1
G=/mnt/data/toolchain/bin/godot
$G --headless --audio-driver Dummy --path drawing \
  --script res://tests/t128_history_list_pending_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' "$G" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t128_history_list_pending_smoke.gd
python3 tools/check_godot_model_log.py headless-1.log --marker T128_HISTORY_LIST_PASSED
python3 -m unittest discover -s tests -p 'test_t128_history_list_pending.py' -v
make python-test
python3 tests/check_explicit_types.py
PATH=/mnt/data/toolchain/rust/bin:$PATH \
CARGO=/mnt/data/toolchain/rust/bin/cargo \
CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor \
CARGO_NET_OFFLINE=true CARGO_TARGET_DIR=/mnt/data/work/target \
  bash tools/build_native_brush.sh --test
python3 tools/validate_ticket_store.py
```

| Validation | Exit / result |
| --- | --- |
| Unchanged T-128 fixture | **1**, `T128_HISTORY_LIST_FAILED checks=37 failures=8` |
| Final headless ×4 | **0 each**, 37/37, strict verifier exit 0 |
| Final software-X11 ×2 | **0 each**, 37/37, strict verifier exit 0 |
| T-128 Python CI/source contracts | **0**, 3/3 |
| Native Rust (offline, pinned) | **0**, 35/35 |
| Project Python (`make python-test`) | **0**, all defined suites pass |
| Explicit GDScript types | **0**, pass |
| Focused Ruff and ty | **0 / 0** |
| Defined project Ruff and ty targets | **0 / 0** |
| Ticket validator | **0**, 208 tickets and review gates |

### Neighboring suites

| Unchanged native Drawing regression | Process exit | Recorded marker |
| --- | ---: | --- |
| T-124 queued stroke | 0 | 78/78 |
| T-125 pending persistence | 0 | 29/29 |
| T-126 tab switch | 0 | 34/34 |
| T-127 Undo/Redo | 0 | 40/40 |
| T-130 source context | 0 | 34/34 |
| T-129 pending content edits | **1** | **2/35 failures** |

The T-129 failure is an independent historical regression, not a successful
T-208 result. This ticket repairs a *test oracle*, not production History
handling, native rasterization, responsiveness, physical FPS, or a hosted CI
build. T-095 and T-197 remain performance/owner gates, and T-106/T-180,
T-148/T-149/T-150 remain separate release/native authority work. No manual
review was self-approved.

## Integrity

`sha256.txt` records the SHA-256 of every raw output file, including baseline
and successful process logs; the raw `.log` whitespace is preserved by an
explicit `.gitattributes` rule. All six successful Godot process exits and
strict-marker results are individually recorded in `runs.tsv`; the neighbor
results are recorded in `neighbors.tsv`.
