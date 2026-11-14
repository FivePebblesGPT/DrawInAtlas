# T-105 — native-absent Linux export and Windows/MSVC verification harness

**Recorded:** 2026-11-12. **Ticket:** T-105, **In Progress** (not Done).
**Tested source basis:** local `26be514b36fa36ca8f24901cffe209c0cb55624b`
(T-104), with the uncommitted T-105 worktree changes; original hosted PR #17
head `79b8959e9eac01b3bb10a144a46407acc6901aed` was checked separately.
The source is not assigned an invented pre-commit candidate SHA.

## Acceptance boundary

This checkpoint is **not** cross-platform completion or adoption of a new
backend. The independent standalone Linux export **was actually built and
executed**. Real Windows/MSVC CI, a Windows exported app, full released-editor
pointer+publication parity, device RAM/VRAM, and physical input-to-photon
p50/p95 remain **not tested**. Neither a workflow definition nor a Linux
worker RSS proxy proves them. T-068 stays In Progress; T-095 retains
`manual_review: true` and T-096 stays Manual Review. No approval or merge.

## Pinned environment and exact Linux release procedure

- Linux x86-64 kernel 6.18.57, Debian GCC 14.2.0, Clang 17.0.0;
  pinned `Godot 4.8.beta3.official.c51ff06e8`, engine SHA-256
  `746a2bc89508d07801fe9ba9bbeaad5be0c74e05f13867977b314f2457f42701`.
- The user-provided beta3 templates tar SHA-256:
  `d79c56f41ec51d29b3557f429c2ba10edb4f3e3d81305cfcecb57adb24fb5b5d`,
  containing `linux_release.x86_64` and `linux_debug.x86_64`.
  Templates installed in the isolated profile's Godot `export_templates/4.8.beta3/`.
- `python3 tools/build_drawing_app.py --output /mnt/data/work/t105-tools/stage2 --without-native`
  **exit 0**, independently allowlists the Drawing consumer and omits its
  optional GDExtension even if a developer's addon was already compiled.
  `t068_release_gate.inspect_stage()` passes: 397 staged+imported files,
  font-license SHA-256 `5004fe34082ed15d8276d2f7992bfb130830e5bc0306a2e96dd6eb6263f476b`.
- `godot --headless --path "$STAGE" --editor --import` **exit 0**;
  `godot --headless --path "$STAGE" --export-release Linux "$DIST/Drawing.x86_64"`
  **exit 0**. Raw logs are retained in `t105-raw-logs/linux-{import,export}.log`.
- `python3 tools/benchmarks/t068_release_gate.py --stage "$STAGE" --linux "$DIST" --launch-linux`
  **exit 0**, inspecting ELF architecture + PCK header and isolated release launch,
  not merely editor sources. The release has no experimental native extension.
  `Drawing.x86_64` is 76,950,280 bytes, SHA-256
  `9a0cb0897395e812305f65b7fa2b5ba55e9dfc85146308a36ec9a196ae909182`;
  `Drawing.pck` is 2,478,568 bytes, SHA-256
  `fb481770c4a85e678e0195abd798474c3e4d9d9e1f79bebd2bf709d96471a3fe`.
  Isolated launch had **four recognized Godot RID shutdown leak diagnostics**,
  preserved in the result, not described as clean resource teardown.
- `python3 tools/benchmarks/t105_release_residency.py --stage "$STAGE" --distribution "$DIST" --runs 3 --frames 120 --output docs/benchmarks/T105_2026-11-12_linux_export_residency.json`
  **exit 0**; `--verify --output ...` **exit 0**. Every trial is a new exported
  executable with copied binary+PCK, isolated HOME/XDG and workdir, a strict
  zero-exit Godot log check, sampled `/proc/<godot_pid>/status` VmRSS/VmHWM,
  and child OS user/system CPU via `resource.getrusage(RUSAGE_CHILDREN)` deltas.
  This measures **actual exported Godot process memory**, not isolated native
  C++ allocation or GPU VRAM. Metrics are *startup + 120 headless idle frames*;
  **they do not measure Brush input, publication or photons**.

| Linux exported process (3 independent launches) | p50 | p95/max |
| --- | ---: | ---: |
| Elapsed wall (ms) | 1,846.204 | 1,993.585 |
| Child user CPU (ms) | 790.851 | 797.204 |
| Child system CPU (ms) | 160.597 | 388.260 |
| Process VmHWM (KiB) | 148,200 | 148,352 |
| VmHWM (MiB) | 144.73 | 144.88 |

The report records all three raw observations, actual `VmRSS`, HWM,
CPU time and shutdown-diagnostic counts (4, 4, 4). CPU p50/p95 are **launch**
CPU, not `T-095` full-gesture latency; physical GPU/VRAM cannot be inferred
from headless or llvmpipe measurements.

## Detached candidate parity, negative controls, and Windows scope

The historical scalar hard-brush and convex-scope `.cpp` bytes are unchanged
from T-104, deliberately preserving the old T-068 pinned SHA oracle.
T-105's `t105_windows_msvc.py` generates a deterministic **test-only**
source adapter from those original bytes. It explicitly exports
`t068_quad_scope_mask` from the Windows DLL and refuses MSVC `_M_FP_FAST`.
The GCC **red control** compiles each original source with synthetic
`-D_M_FP_FAST=1` (exit 0); the adapted source fails under that define
(exit nonzero with the expected strict-FP error), and both original and adapted
sources already reject GCC `-Ofast`. The adapter adds **no shipped DLL**.

A pinned Linux compiler-matrix run (exit 0) reported **six GCC/Clang strict
profiles, 576 byte-exact mask assertions, 42 failed-input atomic rejection
checks and two disallowed fast-math builds rejected**. Detached T-104 parity
replay (exit 0) and contracts (6/6) still pass. The exact data for the
cross-platform candidate workloads remains T-104's decision report; do not
attribute its Linux isolated worker `/proc` memory to the Godot process here.

The on-demand workflow `godot-native-t105-portability.yml` has **two** jobs:
Linux beta3 exported-process replay, and an independent Windows Server 2022
MSVC `cl.exe /fp:strict` build of the detached scalar/quad ABI with the pinned
Godot signed and masked coverage, straight-RGBA8/hidden-RGB, input immutability,
`/fp:fast` rejection and Windows native-absent PE/PCK export/launch + OS
peak working-set measurements. It uses pinned beta3 templates and retains
raw logs/artifacts with `if: always()`. **It was not dispatched or hosted-
verified at this SHA**; Windows results are explicitly absent. No fake
Windows field or equivalent Linux proxy can set T-105 Done.

## Additional local checks and raw records

- `python3 -m unittest discover -s tests -p test_t105_portability.py -v`:
  **10/10 pass**, includes report tampering, unpinned C++ source, forged Windows/VRAM completion,
  native-absent staging, explicit generated-export symbol and before/after
  strict-FP negative control.
- `python3 -m unittest discover -s tests -p test_t068_release_gate.py -v`:
  **5/5 pass**. The existing release-gate fixture now explicitly stages
  `without_native=True` so developer-built extensions cannot taint its
  required portable release contract. The initial unmodified fixture failed
  2 cases on this native-present worktree; the corrected opt-out test passes.
- `python3 -m unittest discover -s tests -p test_t068_scalar_strict_fp.py -v`:
  **2/2 pass**. `test_t068_quad_compiler_matrix.py` **3/3 pass**.
- Pinned standalone headless source publication:
  `godot --headless --path "$STAGE" --script res://tests/t100_sparse_publication_smoke.gd`
  **exit 0**, `check_godot_model_log.py --marker T100_SPARSE_PUBLICATION_PASSED`
  **exit 0**. All 197 pixel/history assertions pass, including signed/masked
  Brush/Eraser, hidden RGB, source rollback and Undo/Redo. This runs in
  the **standalone Godot source project**, not the exported release.
- `native_brush_fallback.gd` on the same native-free project **exit 0**,
  `checks=7 failures=0 native=false`.
- Ticket/dependency validator: `python3 tools/validate_ticket_store.py`
  **exit 0**, 109 tickets; no manual approval changed.

**Raw logs retained:** `t105-raw-logs/`, with the Linux staging/import,
export, source history oracles and command/test outputs. The JSON report
hash and the raw-log hashes can be checked independently against the files;
all MSVC and Windows exported outcomes remain unobserved.

## What T-105 still requires before Done

Run and retain hosted Windows/MSVC evidence on the **exact candidate commit**;
verify actual Windows DLL masks/RGBA8, rejection and PE/PCK launch, with full
process CPU/working-set p50/p95 and controlled source revision. Complete the
released editor's signed/masked pointer-to-publish+Undo parity and obtain
physical-device RAM/VRAM samples where supported; do not replace the
requested process/VRAM facts with detached worker HWM. Record credible cold/
warm end-to-end comparisons or a reasoned not-measurable status with an
explicit acceptance decision. T-105 remains **In Progress** until those gates
are met. T-068 must not close from this Linux-only result.

### Retained raw-log SHA-256 manifest

| Raw record | SHA-256 |
| --- | --- |
| `linux-export.log` | `4a02adf5d7fd21bfdfe4eadc64c915426f03c6c0e5935aaeebfed88934922d32` |
| `linux-import.log` | `f11dbab271f024b541c32c8afa404d0caa923be9dd9684d655ae3e19563c6d46` |
| `msvc-guard-red-green.txt` | `a7d517746df1adb8db602023b213913b34d8ea49628b8889c9b7a6c5fb2df102` |
| `quad-live.log` | `494f796e498ca84f730f00a3a9b7c93a510d083864079912523c8096642ad1a8` |
| `quad-python-tests.log` | `6dd1ef3174f4520af3f24f1026d3237e495bb1cc4aa9520b74006180d202b71c` |
| `release-tests.log` | `9dc51be0c8289fb6f6f301ceeb82a193cbfeff8d8383a30f5da72adf119d1e54` |
| `standalone-no-native.log` | `d0338ceca410ae4062565842f7d18ce6f1843490d12f94ab4b2f1ee34ae9b75c` |
| `standalone-publication.log` | `9ff8bd24cbb45fddd7bc42c4f7b9e9570f4255b893bf89035bf7f7b796c58a59` |
| `strict-fp-tests.log` | `3bee584e3ea8a4ae8612b0cdf90d453ffe25453dcbb9d45d714766650a04d785` |
| `t105-python-tests.log` | `4c75173a46d1d4a152845970e74a50f2244eb2a7caaad50ded4a53802dbc18b1` |
