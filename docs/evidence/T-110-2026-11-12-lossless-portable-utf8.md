# T-110 — byte-exact portable source UTF-8 authorization

**Date:** 2026-11-12. **Scope:** one independent child of T-065, not owner
acceptance. **Base source:** local T-109
`e490355d02abb17ebc5adfbe499aa0ec39785141`; PR #17's last verified
remote SHA was `79b8959e9eac01b3bb10a144a46407acc6901aed`.
**Engine:** pinned Godot `4.8.beta3.official.c51ff06e8` on Linux.

## Red control and fix

The original index decodes captured `.drawing` bytes with
`PackedByteArray.get_string_from_utf8()`, which produces a replacement
character for `0xff` inside a JSON name. Godot then accepts that altered
Unicode string as valid JSON, while the index advertises the SHA-256 of the
original malformed byte stream. If a second valid file has the same source
ID, the malformed file can suppress its entry. The original portable Import
also validates decoded JSON but then copies the malformed byte stream into
`Objects/`; a subsequent index scan cannot safely authorize it.

The new index checks `decoded.to_utf8_buffer() == captured_bytes` **before**
any source authorization. Its SHA-256 is still calculated by `HashingContext`
from the original, bounded byte buffer; no on-disk path rehash is substituted
for that identity. The transfer copy performs the same lossless UTF-8 check
on the captured buffer before creating a `.pending` file. It returns
`SOURCE_UTF8` on failure; no new published source remains. Valid multibyte
Unicode, hidden RGB, signed bounds, revisions and original digest checks are
unchanged. This uses point-in-time reads, not a cross-process filesystem lock.

`drawing/tests/t110_lossless_source_utf8_smoke.gd` creates real portable
sources in an isolated temporary folder. It proves that malformed bytes can
still appear to be a valid decoded JSON envelope (otherwise this would be a
trivial syntax error), then checks rejection, a legitimate duplicate's
continued visibility, the old selected digest's invalidation, valid Unicode
name and SHA-256 parity, rejected Import without publication, and normal
byte-for-byte Unicode Export. Fixture cleanup is asserted.

Using the **exact T-109 source bytes**, both recorded by their SHA-256:

- Index: `00be020e19f7f5a3fa35b30551702b05a7de0b563e31047bd7334149f3dded3e`
- Transfer: `7b0c52c71c74cdec40a1510ea7172d6302edba3329306fce1df2b4ff7f49d2b3`

The negative control exits **1** with **7/20** failed assertions, including
accepting an invalid source and publishing it on Import. The candidate exits
**0**, reports `T110_UTF8_PASSED (20 checks, 0 failures)`, and passes the
T-094 strict model-log verifier. Godot prints `Unicode parsing error` for
these intentionally malformed fixtures; those diagnostics are retained, not
suppressed or counted as success markers. No crash or unrelated `ERROR:` line
was accepted by the strict checker.

## Commands and regressions

From repo root with the pinned Godot binary:

```sh
GODOT_SILENCE_ROOT_WARNING=1 timeout --signal=TERM --kill-after=3s 70s \
  /path/to/Godot_v4.8-beta3_linux.x86_64 --headless --audio-driver Dummy \
  --path . --script res://drawing/tests/t110_lossless_source_utf8_smoke.gd \
  > /tmp/t110-utf8.log 2>&1
python3 tools/check_godot_model_log.py /tmp/t110-utf8.log --marker T110_UTF8_PASSED
python3 tests/check_explicit_types.py
python3 tools/validate_ticket_store.py
```

All these candidate checks exited **0**. Neighboring headless tests executed
with process-exit checks **and** the exact strict markers, see
[`T-110-2026-11-12-logs/manifest.json`](T-110-2026-11-12-logs/manifest.json):

| Test | Result |
| --- | --- |
| T-110 source UTF-8 | 20/20, exit 0 |
| T-109 512/513 real-directory scale | 32/32, exit 0 |
| T-065 browser / transfer / real-I/O / thumbnails | All strict markers passed, exit 0 |
| T-065 Atlas/portable registry | Strict markers passed, exit 0 |
| T-065 source manager | 33/33, exit 0 (isolated retry after aggregate batch timeout) |
| T-065 Xvfb/Mesa real pointer browser | 19/19, exit 0 |
| GDScript explicit-type audit | 420 project scripts and 33 skills checked |
| Ticket and manual-gate validation | 110 tickets validated |

The Xvfb browser test ran after `tools/build_drawing_app.py --in-place` and a
successful Godot beta3 standalone editor import, using Dummy audio and
software OpenGL. Its original raw log includes **13 known post-exit resource
leak diagnostics** which the shared checker counts and retains. This does
not imply clean renderer teardown or physical input-to-photon evidence.

## 512-source diagnostic performance comparison (not a speedup)

Use `T109_SCAN_ROOT` with the **same 512-source directory** printed by the
T-109 retained-fixture witness and run
`drawing/tests/t109_scan_benchmark.gd` nine times *inside each process*.
The exact T-109 and candidate index sources were alternated in four fresh
Godot processes; the benchmark validates 512 IDs and one late selected ID
in every scan. p95 is nearest rank. Process peak RSS was **not** recorded;
`OS.get_static_memory_usage` is engine-tracked, not RSS/VRAM.

| Source order | Scan p50 (ms) | Scan p95 (ms) |
| --- | ---: | ---: |
| T-109 baseline 1 | 210.705 | 316.798 |
| T-110 candidate 1 | 244.710 | 266.055 |
| T-109 baseline 2 | 255.975 | 281.740 |
| T-110 candidate 2 | 224.166 | 305.720 |

The alternate string-hashing micro-variant was discarded; the final patch
retains T-109's original raw-byte `HashingContext`. The results do **not**
establish faster indexing, lower memory, real-world filesystem throughput or
hardware acceptance. Extra UTF-8 validation is a bounded CPU/memory cost
for rejecting inconsistent source bytes.

## Gating and portability

The required fast workflow uses the new 20-check model under the existing
`ci_t065_asset_browser_model` step with `set -euo pipefail`, watchdog,
exact-marker verifier and raw log retention; **46 required check IDs** are
unchanged. The on-demand physical owner acceptance, Windows path handling,
network/cross-process filesystem atomicity and hosted CI on this local
candidate have **not** been exercised. T-065 stays `In Progress`,
`manual_review: true`, and T-108 retains its unapproved policy gate.
