# T-209 — T-129 required-native layer/clipboard pending-source regression

**2026-11-19; PR #21 local branch based on remote `9aa1cbe0`.** Pinned
Godot `4.8.beta3.official.c51ff06e8`, native Rust Hokusai extension and
software-X11 (Xvfb) were used. No hosted CI, Windows, physical device, or
owner signoff was exercised.

## Reproduction and bounded correction

The unchanged `drawing/tests/t129_pending_content_edit_smoke.gd` failed with
process **exit 1, `T129_PENDING_EDIT_FAILED checks=35 failures=2`**. Both
failures occurred after `await frames(2)` on assertions that the Brush must
*still be pending*, one after denied layer changes and one after denied
clipboard/text changes. With required native Hokusai it may already have
published the entire two-stroke queue by that point. The original negative
log and failing strict-marker verification are in `before.log` and
`before.strict.txt`.

The test now accepts **either** an outstanding native gesture **or** complete
publication: `doc.revision == revision + 2` **and** the relevant original
History cursor `+ 2`. A cancelled or partially published queue with no
pending stroke fails that checkpoint; an in-progress queue is still required
to finish via `await_commit()` and then satisfy the original two-transaction,
source-pixel and History checks. No test was removed or skipped: the required
marker remains `T129_PENDING_EDIT_PASSED checks=35 failures=0`.

The original guards still test layer insertion, visibility/lock, reorder,
rename, removal, Tree selection restoration and warning; clipboard
Delete/Cut/Paste, text commit/rasterize, no premature revision/history, exact
paint survival, Save/Open, structural Undo and post-commit editing. A new
Python source contract rejects the fixed-two-frame assumptions and requires
both revision and History-cursor proof. Its fail-first unit test failed before
the GDScript change. The existing CI witness and 35-check inventory are
unchanged. **No production Drawing, raster, scheduling, History, or CI workflow
code was edited.**

## Commands and recorded results

Raw process output, exits and hashes are preserved byte-for-byte in
[`T-209-2026-11-19-native-content-edit-raw/`](T-209-2026-11-19-native-content-edit-raw/).
From repository root with the supplied offline toolchain:

```sh
export GODOT_SILENCE_ROOT_WARNING=1
G=/mnt/data/toolchain/bin/godot
$G --headless --audio-driver Dummy --path drawing \
  --script res://tests/t129_pending_content_edit_smoke.gd
xvfb-run -a -s '-screen 0 1280x900x24' "$G" \
  --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path drawing \
  --script res://tests/t129_pending_content_edit_smoke.gd
python3 tools/check_godot_model_log.py headless-1.log --marker T129_PENDING_EDIT_PASSED
python3 -m unittest discover -s tests -p 'test_t129_pending_content_edit.py' -v
make python-test
python3 tests/check_explicit_types.py
PATH=/mnt/data/toolchain/rust/bin:$PATH \
  CARGO=/mnt/data/toolchain/rust/bin/cargo \
  CARGO_VENDOR_DIR=/mnt/data/toolchain/vendor \
  CARGO_NET_OFFLINE=true CARGO_TARGET_DIR=/mnt/data/work/target \
  bash tools/build_native_brush.sh --test
python3 tools/validate_ticket_store.py
```

| Verification | Result |
| --- | --- |
| Unchanged T-129 fixture | **Exit 1**, 2/35 failures; strict verifier exit 1 |
| Corrected headless ×4 | Exit 0 each, **35/35**, strict verifier exit 0 each |
| Corrected X11 ×2 | Exit 0 each, **35/35**, strict verifier exit 0 each |
| Focused Python source/CI contracts | **3/3**, exit 0; new contract fail-first confirmed |
| `make python-test` | Exit 0, **56 tests** |
| Offline native Rust | Exit 0, **35/35 tests** |
| Explicit GDScript types | Exit 0, 521 scripts/33 skill documents |
| Pinned Ruff and ty, modified test | Exit 0 / 0 |
| Pinned Ruff and ty, defined project targets | Exit 0 / 0 |
| Ticket/manual-review validator | Exit 0, **209 tickets** |

A direct `make lint` attempt could not resolve PyPI because outbound DNS was
unavailable (`make-lint.log`, exit 2). The exact pinned Ruff `0.17.5` and ty
`0.0.104` wheels were then installed **offline** from the provided bundle,
and both focused and Make-defined target sets passed. The failed network
attempt is retained; it is not reported as a passing `make lint` run.

### Neighboring checks, same native build

| Test | Exit | Witness |
| --- | ---: | --- |
| T-124 queued Brush | 0 | 78/78 |
| T-125 pending persistence | 0 | 29/29 |
| T-126 tab switching | 0 | 34/34 |
| T-127 pending history | 0 | 40/40 |
| T-128 History list | 0 | 37/37 |
| T-130 source context | 0 | 34/34 |
| T-124 routed native-X11 queue | 0 | 20/20 |
| T-089 layer structure model | 0 | 63 checks |
| T-088 selection/clipboard model | 0 | Pass marker |
| T-089 native-X11 layer structure | 0 | 36 checks |
| T-088 native-X11 selection/clipboard | **1** | **24/51 failures** |

The last T-088 witness predates this ticket and still tests a distinct
selection/clipboard/Move behavior. It reported failures against the current
required-native environment, including unchanged-pixel and file-reopen
assertions. T-209 modifies neither that test nor its production path; this
exploratory failure is retained in full and is **not** counted as green or
claimed resolved. It merits separate triage and source-exact comparison.

## Remaining gates

The repaired test gives a useful engineering signal for source-safe mutation
refusal, **not** FPS, latency, physical user input, hosted required-native CI,
or universal raster authority. T-095 and T-197 performance/owner obligations,
T-106/T-180 CI work, and T-148/T-149/T-150 native-transition requirements
remain open. No owner/manual-review gate was self-approved.
