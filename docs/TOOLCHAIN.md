# Reproducible Linux toolchains and one-command builds (T-180)

DrawInAtlas requires a Rust/Hokusai GDExtension. A source checkout without the
native library is **not** a working painting application. GNU Make is the entry
point; Cargo still owns incremental Rust compilation and Godot owns imports.

## Linux x86-64: developer's installed tools

Requires GNU Make, Python >=3.11, Bash, Rust >=1.94 with Cargo/rustfmt,
Godot 4.8 beta4 and (for linting) uv.

    cp local.mk.example local.mk
    # Update paths in local.mk, or pass explicit command-line overrides.
    make doctor
    make drawing                 # Build native, stage, import, launch
    make atlas                   # Build native, root import, launch
    make test                    # Native-present integration smoke
    make python-test             # Stdlib bootstrap tests
    make lint                    # Ruff + ty (uv)
    make check                   # Unit, lint, Godot smoke

Example without local.mk:

    make drawing TOOLCHAIN=system GODOT=/opt/Godot_v4.8-beta4_linux.x86_64

The system mode checks tool versions with `make doctor` but does not promise
identical binaries across machines. GNU Make assignments override local.mk,
which overrides defaults. No Nix, Docker or global Python packages are needed.

## Build a new offline bundle on a connected Linux x86-64 host

Required builder prerequisites: GNU Make, Python >=3.11,<3.16, `rustup`, GNU tar,
`zstd`, internet access, and a compatible system Python used to validate the
pinned Python tools. No existing DrawInAtlas toolchain bundle is necessary.

    make bundle
    make bundle-verify
    make bundle-check

To reuse previously downloaded **official source archives** instead of
fetching again, pass optional `GODOT_ARCHIVE=/path/to/Godot...zip` and
`UV_ARCHIVE=/path/to/uv-...tar.gz` to `make bundle`. Their hashes must match
`toolchain.lock.toml` even when the local download cache already exists.
An arbitrary installed Godot executable is supported for system development,
but not silently embedded into the version-locked bundle.

The output defaults to:

    .build/bundles/drawing-toolchain-linux-x86_64.tar.zst

The **T-180 Rebuildable Linux native toolchain** GitHub Actions workflow also
uploads the verified archive as the `drawing-toolchain-linux-x86_64` artifact.

`toolchain.lock.toml` is the version/source manifest. It pins official Godot
and uv release URLs and SHA-256 hashes, Rust 1.99.1, Ruff/ty versions and the
Linux target triple. Rust distribution components are obtained by `rustup`
for the pinned Rust version; rustup verifies upstream component checksums.
Crates come from `native/drawing_brush/Cargo.lock` via `cargo vendor --locked`.
The bundle packages a private Rust installation, Godot executable, uv executable,
Cargo vendor directory, checksum-pinned universal Ruff/ty wheels, and the
standalone `bin/git_lfs_mbox.py` mailbox utility from `tools/git_lfs_mbox.py`;
**it does not package Python or compiled DrawInAtlas binaries**.

The generator uses **`zstd -19 -T1`** and rejects compressed output larger than
**500 MiB (524,288,000 bytes)** before publishing it. It writes a per-file
SHA-256 manifest **inside** the archive. It prints the archive-level SHA-256
to the build log; no external checksum sidecar or DrawInAtlas repository is
packaged or generated. Transfer the source checkout separately.
A transferred archive is checked before use and checked against both the
current toolchain lockfile and Cargo.lock after extraction. The output is
relocatable and built outside tracked source in ignored `.build/` directories.
The archive itself is a derived, replaceable build artifact; keep a copy in
releases/backups to survive upstream deletion.

Archive ordering, ownership, permissions and timestamps are normalized, as is
rustup's concurrently written component registry. No mutable uv cache or virtual
environment is shipped. Compare two clean archive SHA-256 hashes before claiming
byte identity; matching results on one host do not prove cross-host identity.
Verify Rust/glibc/runtime requirements on the actual consumer distribution.

## Use the bundle on a new sandbox

The consumer still needs GNU Make, Bash, zstd, system Python >=3.11,<3.16,
a C linker/toolchain (`cc`), and the distribution's ordinary glibc/graphics
runtime libraries. Those OS prerequisites are not embedded into the archive.

Supply one `.tar.zst` archive and the checked-out source:

    make doctor TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst
    make drawing TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst
    make test TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst

`TOOLCHAIN=auto` (the default) selects bundle mode when `BUNDLE` is set;
otherwise it uses installed tools. The generated bundle is verified, unpacked
into `.build/toolchains/<archive-sha256>/`, and reused. Cargo is then invoked
with `--offline --locked` and the vendored registry. uv runs with
`UV_OFFLINE=1`, `UV_NO_INDEX=1`, `--no-managed-python`, and pinned Ruff/ty wheels
from the bundle. Its writable cache lives separately in `.build/runtime/`;
repeated linting never mutates the verified archive payload. Python is the local
compatible system executable selected by
`PYTHON=/path/to/python3`.

### Exchange patches and Git LFS objects

The bundle includes `bin/git_lfs_mbox.py` for packing, inspecting and unpacking
offline patch transfers. Invoke it with system Python explicitly so it uses
the installed `zstd` fallback without resolving its uv script dependencies:

```bash
python3 /path/to/extracted-toolchain/bin/git_lfs_mbox.py --help
git format-patch --stdout BASE..HEAD > changes.mbox
python3 /path/to/extracted-toolchain/bin/git_lfs_mbox.py pack changes.mbox --repo .
python3 /path/to/extracted-toolchain/bin/git_lfs_mbox.py inspect changes.lfsmbox.tar.zst
python3 /path/to/extracted-toolchain/bin/git_lfs_mbox.py unpack changes.lfsmbox.tar.zst --repo . --apply
```

Git and Git LFS must be installed for applying/hydrating LFS patches. The utility
removes the extracted `.mbox` after a successful `--apply`, preserving it when
applying fails or when `--apply` is omitted. It also reads alternate DrawInAtlas
`bundle.json` exports. Its bytes are covered by
the toolchain archive's internal checksum manifest. The checked-in copy comes
from the standalone [git_lfs_mbox gist](https://gist.github.com/FivePebblesGPT/f9ac329f8537151441535027758ff5a5)
and includes the DrawInAtlas compatibility and successful-apply cleanup changes.

The old `Godot_v4.8b3_rust_hokusai_bundle8.tar.zst` checksum is retained for
historical verification. The archive contains beta3 and cannot satisfy the
current engine pin. Use `make bundle` to build the current archive from the
locked upstream sources.

For a cold network-isolated acceptance run (optional **bubblewrap** validator
dependency; ordinary builds do not require it):

    python3 tools/check_offline_toolchain.py \
      --bundle .build/bundles/drawing-toolchain-linux-x86_64.tar.zst \
      --output /tmp/t180-cold-consumer

This copies only source plus archive to a new directory, excludes all generated
native/Cargo/Godot state, hides host home directories, disables networking, sets
host-tool overrides to nonexistent executables, and runs doctor, verification,
native tests and two lint passes. Both source and bundle paths contain spaces.
It retains raw logs and `results.json`. `bundle-verify` / `bundle-check` accept
`BUNDLE=...`; otherwise they use `BUNDLE_OUT`. Set `GODOT_ARGS` to pass launch
arguments (for example `GODOT_ARGS='--quit-after 120'`).

## Native extension import and diagnostics

`make drawing` always:

1. Compiles `libdrawing_brush.so` using the selected Cargo toolchain.
2. Stages the canonical addon into `drawing/addons/drawing`.
3. Requires the manifest and nonempty library file; never silently uses
   GDScript Brush/Eraser fallback.
4. Adds `res://addons/drawing/native/drawing_brush.gdextension` to the
   project's `.godot/extension_list.cfg` **before** editor import.
5. Imports and launches Godot.

`make test` additionally exercises the actual native Brush/Eraser and tile
contracts; the native-absent fixture alone is not acceptable proof of loading.
If Godot still says `Required native Brush/Eraser extension unavailable`,
use `make doctor`, inspect Godot's import/load diagnostics, and run
`ldd addons/drawing/native/bin/libdrawing_brush.so`.

For negative tests only, `tools/build_drawing_app.py --without-native` may
stage a deliberately broken native-absent consumer. Normal staging fails if
the extension is missing. Windows and exported releases remain outside this
Linux build proof; preserve the separate T-105 portability gate.

## Local validation status

The initial implementation was unexecuted. Local Linux validation now includes
system Rust 1.100.0, Godot 4.8 beta3, a new source-built Rust 1.99.1 bundle,
network-isolated cold native compilation and repeated offline Ruff/ty runs.
The real Wayland GUI/native Canvas test passed 46 checks, including tile FFI,
Brush/Eraser, Undo/Redo and portable Save/Open. Early archive builds differed
only in rustup component-list order; after normalization two clean builds match
SHA-256 `3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2`
and **263,487,525 bytes (251.281285 MiB)**. This is demonstrated local byte
identity, also matched by the fresh Ubuntu 24.04 / Python 3.12.3
[green hosted cold-native run](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/43984960775),
not a blanket guarantee for arbitrary hosts. See [raw validation evidence](evidence/T-180-2026-11-17-local-validation.md).
T-180 stays In Progress for remaining desktop native-transition/export
coverage (42/46); the dedicated toolchain workflow is green.
T-095 physical input and T-105 Windows gates remain open.

## Standalone Linux release inspection (T-201 through T-217)

`python3 tools/package_linux_export.py --stage STAGE --linux EXPORT` requires
an actual native-registered Drawing stage and a separate Godot 4.8 Linux
ELF/PCK export. Packaging preflights an isolated candidate distribution and
must not modify the export on rejection. The release inspector
`tools/benchmarks/t068_release_gate.py` now examines the PCK v4 resource
index, not just its `GDPC` prefix: the startup scene (or valid compiled remap),
`project.binary`, native Rust `.gdextension` mapping and native ABI smoke must
be packed with matching payload hashes. Run with `--launch-linux` to verify
native class registration and an isolated application boot. The index check
is structural only; it cannot establish physical latency or certify Windows
native packaging, official release-template operation, or hosted CI.
