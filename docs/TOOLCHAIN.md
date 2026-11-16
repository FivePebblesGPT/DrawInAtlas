# Reproducible Linux toolchains and one-command builds (T-180)

DrawInAtlas requires a Rust/Hokusai GDExtension. A source checkout without the
native library is **not** a working painting application. GNU Make is the entry
point; Cargo still owns incremental Rust compilation and Godot owns imports.

## Linux x86-64: developer's installed tools

Requires GNU Make, Python >=3.11, Bash, Rust >=1.94 with Cargo/rustfmt,
Godot 4.8 beta3 and (for linting) uv.

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

    make drawing TOOLCHAIN=system GODOT=/opt/Godot_v4.8-beta3_linux.x86_64

The system mode checks tool versions with `make doctor` but does not promise
identical binaries across machines. GNU Make assignments override local.mk,
which overrides defaults. No Nix, Docker or global Python packages are needed.

## Build a new offline bundle on a connected Linux x86-64 host

Required builder prerequisites: GNU Make, Python >=3.11, `rustup`, GNU tar,
`zstd`, internet access, and a compatible system Python used to warm the uv
cache. No existing DrawInAtlas toolchain bundle is necessary.

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
    .build/bundles/drawing-toolchain-linux-x86_64.tar.zst.sha256

`toolchain.lock.toml` is the version/source manifest. It pins official Godot
and uv release URLs and SHA-256 hashes, Rust 1.99.1, Ruff/ty versions and the
Linux target triple. Rust distribution components are obtained by `rustup`
for the pinned Rust version; rustup verifies upstream component checksums.
Crates come from `native/drawing_brush/Cargo.lock` via `cargo vendor --locked`.
The bundle packages a Rust installation, Godot executable, uv executable,
Cargo vendor directory, and warmed uv cache; **it does not package Python or
compiled DrawInAtlas binaries**.

The generator writes a per-file SHA-256 manifest and archive SHA-256 sidecar.
A transferred archive is checked before use and checked against both the
current toolchain lockfile and Cargo.lock after extraction. The output is
relocatable and built outside the Git tree in ignored `.build/` directories.
The archive itself is a derived, replaceable build artifact; keep a copy in
releases/backups to survive upstream deletion.

Archive ordering, ownership and timestamps are normalized. This is not a
claim of byte-identical rebuilds across hosts: compare two clean archive
SHA-256 hashes to establish that property separately. Verify uv cache
portability, Rust glibc/runtime requirements, and any host-dependent compiler
components on the actual consumer host before declaring the bundle portable.

## Use the bundle on a new sandbox

Supply one `.tar.zst` archive and the checked-out source:

    make doctor TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst
    make drawing TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst
    make test TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64.tar.zst

`TOOLCHAIN=auto` (the default) selects bundle mode when `BUNDLE` is set;
otherwise it uses installed tools. The generated bundle is verified, unpacked
into `.build/toolchains/<archive-sha256>/`, and reused. Cargo is then invoked
with `--offline --locked` and the vendored registry. uv runs with
`UV_OFFLINE=1`, `--no-managed-python`, and pinned Ruff/ty versions from the
manifest; Python is the local compatible system executable selected by
`PYTHON=/path/to/python3`.

The old `Godot_v4.8b3_rust_hokusai_bundle8.tar.zst` remains usable as a
transition input if its SHA-256 matches the committed historic checksum.
The old archive cannot be *regenerated* from its assembled bytes; `make
bundle` creates the new source-defined format instead.

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

This PR's source and structural tests were written without a functioning
container execution service. **No archive build, off-network rebuild, lint
result, X11 launch, Godot smoke pass, or byte-reproducibility claim is made.**
The local-agent handoff in `docs/T-180_LOCAL_AGENT_HANDOFF.md` is a required
acceptance step before merging or marking T-180 Done.
