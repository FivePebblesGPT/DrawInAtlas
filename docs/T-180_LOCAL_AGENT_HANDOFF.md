# T-180 Local-agent handoff — finish and validate toolchain PR

**Execution follow-up (2026-11-17):** Most checks below have now been executed;
read [the detailed validation and raw evidence](evidence/T-180-2026-11-17-local-validation.md)
before repeating work. T-180 remains In Progress for the recorded hosted/native
transition and packaging gates. The delivered toolchain is a single zstd-19
archive, below 500 MiB, with internal checksums and no repository or external sidecar.

You are the local implementation/validation agent for DrawInAtlas. The user
squash-merged PR #19 onto `main` at
`30e68fca7ded6bb2e5c8f4ea12604d3c33713c8c`. Continue on branch
`build/reproducible-toolchain` (new PR; do **not** rebase onto old sprint
history). Follow `docs/Index.md`, `docs/Tickets/T-180.md`,
`docs/TOOLCHAIN.md` and dependency/manual review gates.

## Objective

Turn the committed Make + portable bundle implementation into a verified,
maintainable, one-command workflow. You may fix all code within T-180 required
to make it work; do not treat test failures as approval to relax native
correctness. The single source of truth for toolchain versions is
`toolchain.lock.toml`. No Nix or Docker dependency is permitted.

## Work order

1. Inspect the branch diff against squashed `main`. Check for accidental
   regressions, stale README/CI commands and missing metadata.
2. Run `python3 -m unittest discover -s tests -p 'test_toolchain_build.py'`;
   test archive traversal, integrity and native registration.
3. In **system** mode verify the actual local Godot 4.8 beta3, Rust, uv,
   Python version and exact paths (`make doctor TOOLCHAIN=system`).
   Build and launch Drawing from clean generated state, verify the real
   `DrawingNativeBrush` and `DrawingNativeTiles` classes load and a
   Brush/Eraser gesture paints, erases, undoes and redoes. Verify Atlas too.
4. Regenerate a NEW bundle with `make bundle` with the previous manually
   assembled bundle moved aside; do not import old Rust vendor or libraries
   by accident. Check artifact sources/hashes, Rust installation, cargo vendor
   output, uv cache and system-Python minor compatibility. Fix any problems
   (e.g., rustup relocation, empty wheel cache, zstd availability).
5. Run `make bundle-verify`, then `make bundle-check` in a fresh disposable
   environment. Enforce offline network isolation where available, as well
   as `CARGO_NET_OFFLINE=true`, uv offline and no Python downloads.
   Delete/rename prior `.build/target`, Godot .godot caches, and native .so
   before the test to exclude stale successes.
6. Repeat clean `make bundle` twice with independent fresh caches. Record
   SHA-256 of both archives and explain any nondeterminism rather than
   reporting byte-reproducibility without evidence.
7. Check `make lint` (Ruff and ty via uv) and `make check`. Adjust the
   Python tooling baseline based on the **actual** system Python minor,
   never force-download a Python runtime into an offline sandbox.
8. Exercise the old checked v8 archive as a compatibility input, if still
   available, and diagnose its actual directory layout. Do not copy its
   manually assembled binary into the new source-generated archive.
9. Inspect and update the native CI workflow so current required-native
   checks use the same Make entry points where practical. Replace obsolete
   native-absent smoke assumptions without silently discarding coverage.
10. Finish README, `docs/TOOLCHAIN.md`, T-180 and `docs/Index.md`; save raw
    command outputs and SHA-256 evidence. Run ticket validator. Commit fixes
    with Conventional Commits and
    `Co-authored-by: OpenAI Codex <codex@openai.com>` and push onto the
    existing PR branch.

## Required failure-mode tests

- Missing/bad .so or .gdextension and wrong Godot API: explicit fail before
  claiming successful Drawing launch.
- Mismatched lockfile / Cargo.lock / corrupt archive SHA / unsafe tar path.
- Cold cache versus repeated invocation: no unnecessary Rust rebuild from
  GDScript-only changes; no stale native artifact after Rust source edits.
- Paths with spaces, local.mk overrides, Make command-line precedence,
  archive moved between directories.
- Bundle-only Rust, Godot and uv even when system tools differ.
- Native-present integration smoke, standalone Save/Open and Atlas history.
- Windows unsupported path is diagnosed, not silently marked green.

## Evidence and handoff

Report exact Linux/GLIBC/Python/Godot/Rust/uv versions, each command and exit
code, whether the real GUI was observed, outputs/hashes of both archives,
GitHub commit(s), and any remaining blockers. Update T-180 status to Done only
when all acceptance checks actually pass. Keep T-095 owner hardware input
latency and T-105 Windows portability approvals open. Do not claim
that software-X11 CI proves physical input-to-photon latency.

Known initial constraint: this ChatGPT session could write/read GitHub via
the connector but its container and Python execution services returned
internal errors. Thus the first branch commit is an **unexecuted
implementation candidate**, not validated build evidence.
