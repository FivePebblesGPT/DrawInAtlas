# T-220 — Verify effective exported PCK project identity (2026-11-19)

## Problem, fail-first and implementation

T-216 checked the staged text `project.godot`. The exported PCK reader only
required that `project.binary` begin with the literal `ECFG`, so even a
**checksum-consistent PCK for another project** could satisfy the release gate
as long as it carried the expected file names. Six new focused regression
tests produced **12 failing false-accept assertions** before the code change;
see `fail-first.log` (nonzero exit) and `focused-final.log` (six passed).

The real Godot 4.8 beta3 exported binary config has the format `ECFG`, a u32
setting count, and a sequence of u32 UTF-8 key lengths, keys, u32 Variant byte
lengths and Variant bytes. The required `application/config/name` and
`application/run/main_scene` values use encoded String Variant type 4: u32 type,
u32 UTF-8 byte count, string and zero alignment padding. A fresh native PCK
contains nine settings, including unrelated integer and String-array Variant
types; these are skipped by their bounded byte lengths and not guessed at.

The inspector now validates table bounds and exact consumption, rejects
malformed or duplicate keys, checks canonical String Variant encoding, and
requires `Drawing` and `res://main.tscn` **in the actual exported PCK**. The
old synthetic `ECFG\0Drawing` fixture was updated to a minimally valid ECFG
binary. Existing PCK corruption, remap, checksum and name checks remain.

The new Linux packaging regression replaces `project.binary` with a valid
foreign-project ECFG while retaining the expected startup/native resources
and all checksums. The packager refuses it before `.so` installation; its
pre/post export file inventory matches byte-for-byte and no temporary
preflight directory remains (`packaging-final.log`).

## Final local validation

| Check | Result |
| --- | --- |
| Fail-first six tests | 12 false-accept assertions, exit 1 |
| New T-220 project-config tests | **6/6**, exit 0 |
| Native Linux packaging suite | **23/23**, including foreign pack rejection, exit 0 |
| Previous T-217 index suite | **10/10**, exit 0 |
| Configured `make python-test` | **101 tests** across 11 suites, exit 0 |
| Native Rust offline tests | **35/35**, exit 0 |
| Ruff 0.17.5, configured and changed files | Pass |
| ty 0.0.104, configured and changed tests | Pass |
| Ruff formatting, changed tests/fixture | Pass |
| Real Godot beta3 `Drawing.pck` | **528/528** resource checksums and binary identity verified |
| Real PCK plus required Rust ELF, isolated ABI and app boot | Both processes exit 0; reported leak diagnostics 0 |
| Ticket validator | **220 tickets**, review-dependency checks pass |

All native and Python testing used the available offline toolchain. The real
export is the retained Godot 4.8 beta3 PCK paired with the supplied Godot
executable, **not** an official Linux release-template executable. This check
is not publisher authenticity, full Variant semantics, Windows native support,
hosted CI certification, continuous FPS or owner-facing physical approval.
T-105, T-106, T-180, T-197 and manual-review statuses remain unchanged.

## Raw evidence and reproducibility

The `T-220-2026-11-19-packed-project-raw/` directory contains the fail-first,
final unit, packaging, Python, Rust, Ruff/ty, formatting, real-export and
ticket-validation logs byte-for-byte. Its `manifest.json` records source and
log SHA-256 hashes/sizes; `process-exits.json` gives commands and outcomes.
The cumulative Git/LFS mailbox is based on remote PR #21 head
`9aa1cbe0028d7f6cc64044051ef1c2f4a2ebc5d9`, not a prior local checkpoint.
