# T-180 — Build toolchain implementation checkpoint

**Date:** 2026-11-17. **Branch:** `build/reproducible-toolchain`.
**Baseline:** squashed PR #19 on `main` at
`30e68fca7ded6bb2e5c8f4ea12604d3c33713c8c`.

Implemented: source-pinned Godot/uv artifact URLs and checksums; Rust and
Cargo version policy; Make developer targets; online bundle generator;
vendored/offline Rust and uv cache paths; safe bundle extraction and
SHA-256 manifest; native-required staging and Godot extension registration;
stdlib unit fixture for corrupt manifests, archive traversal and idempotence.

**Executed locally here:** GitHub source reads/writes and release metadata
verification only. Container and Python command execution both returned
internal errors. **No test process pass, launch, offline rebuild, or
archive-byte reproducibility is claimed.** The PR must remain unapproved
until the checks in the local handoff are performed and their raw command
results recorded here.

Known risks to test: relocatability of copied rustup toolchain, uv cache
portability across Python minors, archive file ordering and hash repeatability,
legacy bundle8 layout discovery, pinned Godot beta registration behavior,
Cargo vendor configuration path quoting, and any old CI workflow depending
on native-absent standalone staging.
