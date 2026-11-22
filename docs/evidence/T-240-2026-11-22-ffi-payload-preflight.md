# T-240 — Native tile transport whole-batch preflight

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Verified remote PR #22 baseline:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Environment: bundled Godot 4.8 beta3 on Linux x86-64, offline vendored
Rust/GDExtension; native-X11 under Xvfb (not physical owner hardware).

## Fail-first control and correction

`drawing/tests/t240_native_ffi_payload_preflight.gd` tests two-descriptor
batches whose first entry is a valid 64px RGBA8 tile and whose later entry
contains an invalid three-byte packed buffer. With the previous native
binary it reports `T240_FFI_PREFLIGHT_RESULT checks=32 failures=4`:
recorded and untracked adoption plus detached history account for the
first tile before rejecting the later malformed one; token replay reaches
the history snapshot comparison rather than rejecting the malformed length
at its FFI boundary.

A shared Rust descriptor preflight now validates the entire batch, including
signed bounds, duplicate coordinates, types, and `0`/full-stride RGBA8
lengths **before** any `PackedByteArray.as_slice().to_vec()` conversions.
Native edit and detached replay source/snapshot accounting occurs only after
all descriptors are valid. Earlier tile copy/accounting stays zero if a
later entry is malformed. The same safety check protects token replay.
Valid empty/whole-tile source semantics are retained.

**Fixed native binary:** `T240_FFI_PREFLIGHT_PASSED checks=32 failures=0`.
The witness also proves recorded/untracked edit behavior, native token
Undo/Redo after rejection, transparent hidden RGB, and revision/history
atomicity. The negative control is not a claim of measured RSS savings;
it proves that earlier buffers were accounted for by the old FFI and are
not copied into Rust vectors by the fixed FFI on malformed batches.

## Local regression evidence

- Rust: `cargo test --offline --locked --target x86_64-unknown-linux-gnu` — **36/36**.
- New native GDExtension witness — **32/32**.
- T-229 native history budget — **18/18**; T-231 direct transfer budget — **24/24**.
- T-237 detached replay preflight — **40/40**; T-239 token ordering — **36/36**.
- Native tile ABI — **312/312**; T-230/T-232/T-233 bootstrap — **33/34/37**.
- Atlas native tile history — **43/43**; detached replay — **21/21**.
- Native-X11 Canvas cutover — **46/46**, zero tile-pixel-stream FFI calls.
- Strict Godot model log, required CI source contract, ticket-store and
  Git diff validation checked locally.

No hosted GitHub Actions run, owner physical review, or T-148/T-149 closure
is claimed by this child ticket.
