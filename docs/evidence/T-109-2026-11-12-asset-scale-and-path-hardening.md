# T-109 — Portable Objects/ index and transfer hardening (2026-11-12)

**State:** T-109 Done for its independent on-disk safety scope; T-065 remains
`In Progress`, `manual_review: true` without owner acceptance.

## Sources, setup and negative control

- Starting local commit: `445c98432ba3197f02b165da38e1c99cd515e604` (T-108); last
  confirmed PR #17 remote head: `79b8959e9eac01b3bb10a144a46407acc6901aed`.
- Pinned Godot `4.8.beta3.official.c51ff06e8`, Linux headless and Xvfb/Mesa,
  native-absent Drawing staging. Re-run each command and capture the process
  **exit code** before applying `tools/check_godot_model_log.py`.
- Source SHA-256 after the final tests:

| Source | SHA-256 |
| --- | --- |
| `addons/drawing/asset_browser_index.gd` | `00be020e19f7f5a3fa35b30551702b05a7de0b563e31047bd7334149f3dded3e` |
| `addons/drawing/asset_browser_transfer.gd` | `7b0c52c71c74cdec40a1510ea7172d6302edba3329306fce1df2b4ff7f49d2b3` |
| `addons/drawing/object_editor_file.gd` | `fdb9be496c170acbc1cf692ba431dd4514949c721df3048db7366301acd14e4a` |
| `drawing/tests/t109_asset_browser_scale_smoke.gd` | `a5f600c8faa2fce3648954df1c43bfb63df87c09bbd8976dda6260534d83bcb1` |
| `drawing/tests/t109_scan_benchmark.gd` | `fd4305ad1f5fc0aebe4df14ad72c4d18bbd99a7d5fc9b45d81e105afb7ab7c6f` |
| `tools/test_t065_x11_pointer.py` | `e0c0df9212c92e34d59a01089b733f1ab142a3626e6bf0211e800f6b7dfbab24` |
| `tests/object_source_manager_native.gd` | `7e14b27b1e228981cb6e76cb92ade0bbedde5a2239efef40369a4b34d5e4e66a` |

The negative control temporarily substituted **exact T-108** source bytes for
`asset_browser_index.gd`, `asset_browser_transfer.gd` and
`object_editor_file.gd`, restored every candidate byte with a shell trap,
then ran the new real-directory oracle under a 25-second watchdog.
**Exit 124** (expected red, because Godot did not stop after a script error):
`T109_SCALE_FAILED: Import fails on stale root rather than using its spare capacity`,
and `Invalid call to function '_copy_to_new_file' ... Expected 2 argument(s)`.
This proves the old code both accepted a changed root from a displayed
511-source snapshot and lacked the digest-pinned copy boundary. A runtime
error or watchdog exit is **not** a successful model check; see the full
`docs/evidence/T-109-2026-11-12-logs/t109-red-original.log`.

## New on-disk oracle (32 assertions)

```sh
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=4s 100s \
  /path/to/Godot_v4.8-beta3_linux.x86_64 --headless --audio-driver Dummy \
  --path . --script res://drawing/tests/t109_asset_browser_scale_smoke.gd \
  > /tmp/t109-scale.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t109-scale.log --marker T109_SCALE_PASSED
```

Actual process **exit 0**, strict checker **exit 0**, `T109_SCALE_PASSED
(32 checks, 0 failures)`. Five on-disk 512-source scans (including imported
source) have no dropped IDs; the 513th unique file returns `ASSET_LIMIT` and
leaves the prior index intact. A late duplicate suppresses both ambiguous
paths. The test also covers 26 real thumbnail previews against a 24-image
cache, a selected-source symlink replacement and restore, 511-slot stale
Import without partial publication, a forced wrong expected Export SHA,
accurate byte-pinned Export, and campaign move/rename with explicit rescan.
The isolated test fixture is deleted unless `T109_KEEP_FIXTURE=1` is set,
which prints the retained `T109_FIXTURE_OBJECTS` path for repeatable benchmarking.
No user source is deleted by the implementation.

## Paired same-directory 512-source scan CPU and memory

Two alternating process pairs ran against **the exact same on-disk 512-file
folder**, substituting only the original T-108 or T-109 index source. The
benchmark itself validates source count and identifiers in every trial and
reports 9 ordered scan samples per process. Times are *synchronous Godot CPU
wall measurements* for the source index, not physical browser rendering or
input-to-photon. Metrics are descriptive, never pass/fail thresholds.

```sh
T109_SCAN_ROOT=/absolute/path/to/Objects GODOT_SILENCE_ROOT_WARNING=1 \
  /usr/bin/time -f 'PEAK_RSS_KB=%M WALL_SECONDS=%e EXIT=%x' \
  timeout 45s /path/to/Godot_v4.8-beta3_linux.x86_64 --headless \
  --audio-driver Dummy --path . \
  --script res://drawing/tests/t109_scan_benchmark.gd
```

| Pair | Scan CPU p50 (ms) | p95 (ms) | Engine-tracked memory p50 (MiB) | Process peak RSS (MiB) |
| --- | ---: | ---: | ---: | ---: |
| baseline 1 | 99.849 | 129.560 | 81.38 | 146.54 |
| baseline 2 | 144.481 | 212.176 | 81.38 | 147.02 |
| candidate 1 | 210.954 | 316.647 | 81.39 | 149.07 |
| candidate 2 | 205.426 | 214.710 | 81.39 | 148.50 |

**Trade-off:** snapshot-bound decoding/hashing is slower than T-108's
separately reopened content/hash on small sources. It is a deliberate
identity-integrity change, **not a speedup**. Both variants stay under the
existing 512/2,048 source/candidate bounds; observed process high-water
remains ~146–149 MiB. `OS.get_static_memory_usage` tracks Godot allocations,
not RSS; GNU `/usr/bin/time` peak RSS is a per-process Linux high-water mark.
Neither is VRAM or a real customer-campaign sample. Source bytes were
captured and decoded once, then hashed from that same buffer; the selected
SHA is checked again at Open/preview/export. Cross-process filesystem swaps
and atomic no-replace renames remain **point-in-time limitations**, not a
security guarantee of an open file descriptor lease.

## Neighboring source, native and owner-gate coverage

The existing headless browser, thumbnail, transfer, real-I/O, Atlas paging,
asset repair, source manager and nested NULL repair model suites exited 0 and
passed the exact-marker log checker. The Xvfb standalone browser (selection,
keyboard focus, Object Editor Open), Atlas browser (linked drag token and
Editor Open), and source-manager (Place, Keep NULL, repair, Import/Export)
also exited 0 with strict checks. A **real XTEST OS pointer** driver delivered
select/drag, cancelled and Esc-cancelled gestures; 19 checks passed. The
pointer harness sets Godot Dummy audio and the native source-manager witness
closes an exclusive Delete modal before invoking Import, matching the real
custom-action callback. These are local software pointer tests, not owner
Windows/Linux device approval.

The red in-process native setup (standalone SVG imports unfinished) and the
old native source-manager exclusive-modal conflict were corrected without
suppressing any error logs. Known Godot **post-success leak** diagnostics
are retained in successful native/headless logs and are explicitly reported
by the T-094 strict verifier; they do not imply clean shutdown.

Actual raw logs, SHA-256 and exit metadata are in
[`T-109-2026-11-12-logs/`](T-109-2026-11-12-logs/). A machine-readable
[`manifest.json`](T-109-2026-11-12-logs/manifest.json) records expected
markers; process exit codes and raw hashes were checked in the harness.

| Raw log | Type | Process exit | SHA-256 |
| --- | --- | ---: | --- |
| `t064-null.log` | model | 0 | `5d469a5556db409846dd8c097c4529d4bd1927c51c93ce3b040a9b629b11c9b2` |
| `t065-atlas-native.log` | model | 0 | `06eceff6086964b27a9160671651ee5824adf8006c69c2c63b95b901129bd45f` |
| `t065-atlas.log` | model | 0 | `dbea4914f6efeb228f5c770555b5b71cc90ede7134207d6629768da948178d62` |
| `t065-browser.log` | model | 0 | `f5ecfd3d92df1e4d207f6f9ac6d1a7f199979816f6a2f6492676bdcba551953b` |
| `t065-io.log` | model | 0 | `bf88c7f43c7b8a451c9a1ef74999098caaea07bc8e1a7b75bcbd1b1ba179dac6` |
| `t065-manager-native.log` | model | 0 | `7f9bf930a204acdbb0a6fae37d9e39cc9e7ac82834e95cee69f68bd3fb0fed31` |
| `t065-native.log` | model | 0 | `c230818eb57f805cedd2ba7dc27d68785a8569064028586bcdb549874e4ba2c3` |
| `t065-paging.log` | model | 0 | `cf634e7e852a208abfeb7c5405df1abd37c7353ecaad2c06711748d0ba1ea91d` |
| `t065-repair.log` | model | 0 | `7fc800d865158ec2a76145960776f8456bf8296604359c8b8441500028dfd4c6` |
| `t065-source.log` | model | 0 | `862c672570fceb3788233dcbed393f710e6cef11577888183ace45f1f24e8843` |
| `t065-thumb.log` | model | 0 | `66db20b9371bf5ff13346a9689cf475c5c25304f99b87c3da9c0d900a0840e39` |
| `t065-transfer.log` | model | 0 | `74af768ee389491e2d9e92d63cf7539bf5a6af87a868d82b171347fdd7120157` |
| `t065-xtest-pointer.log` | model | 0 | `a1f673fa15a999e46621101d8ae94a8a1386865e36538b64ebe6e264af87dab3` |
| `t109-benchmark-baseline-1.log` | benchmark | 0 | `ae3ed943f7d32c2f34185ee4723984167915309145d63d4408990ddbe8c1f841` |
| `t109-benchmark-baseline-2.log` | benchmark | 0 | `abc97940900bf17ae2405cb0b8496eaf0a788f274268e18d785579c5e0369869` |
| `t109-benchmark-candidate-1.log` | benchmark | 0 | `0be425b53ae2b042d6c248bc23a1b1f22811a5b34cf4ed5bd1bcbbab091dab74` |
| `t109-benchmark-candidate-2.log` | benchmark | 0 | `4646cff1d078307e56efd43710225ba0be9768cf845870e56ce33029a87caa0a` |
| `t109-red-original.log` | negative_control | 124 | `7f278752088839f2cd87da2a6650911959e90adaa84d36e1a8a100f60f2e120c` |
| `t109-scale.log` | model | 0 | `ab78e9f2ca01411e326ddeaca6e05fb920815ba21fccfe11367d11910d918f92` |
| `t109-standalone-import.log` | model | 0 | `dc4f213cb0b1a3ef1e028cf137edcd8f8b64935085a7995cf6082b5e2e1a3fb6` |

## Workflow and acceptance boundary

The existing required `ci_t065_asset_browser_model` step now runs the 32-check
T-109 oracle with `set -euo pipefail`, a 120-second watchdog, and the exact
T-094 success-marker checker; **46 required CI IDs remain unchanged**.
`python3 tools/validate_ticket_store.py` validates all 109 tickets. A fresh
hosted CI run for the local candidate, real large production campaign,
Windows path behavior, cross-process atomic rename/no-clobber and final T-065
owner keyboard/pointer acceptance have **not** been verified. The existing
nested Save As policy remains owner-gated under T-108.
