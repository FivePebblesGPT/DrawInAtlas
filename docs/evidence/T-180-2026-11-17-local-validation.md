# T-180 — Local system, reproducibility and cold offline evidence

Date: **2026-11-17** (some raw commands use 2026-11-16 UTC).
Branch: `build/reproducible-toolchain`, PR [#20](https://github.com/FivePebblesGPT/DrawInAtlas/pull/20).
Base: `30e68fca7ded6bb2e5c8f4ea12604d3c33713c8c`.
Corrections: `fbf752c875c34cd5b859d3a256a73ab1b4c7bf2d`,
`bdcf1c8d98453ba704673ec7fe16237ef275e3fb`.

**T-180 remains In Progress.** Native/offline acceptance is demonstrated locally
and in the green dedicated hosted workflow; four broader desktop/native-transition
and packaging failures remain, as recorded below.
Neither T-095 physical-hardware acceptance nor T-105 Windows acceptance is granted.

## Delivered artifact

Local file (ignored build output):

```text
.build/bundles/drawing-toolchain-linux-x86_64.tar.zst
263487525 bytes = 251.281285 MiB
compression: zstd -19 -T1
upload limit: 524288000 bytes = 500 MiB (enforced before publication)
SHA-256: 3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2
```

One transferable archive; **no generated external checksum sidecar**. Internal
`bundle-manifest.json` lists every payload file's SHA-256, platform, toolchain
lock hash and Cargo.lock hash. The complete 2,428-entry tar inventory was checked:
its only top-level entries are `bin/`, `rust/`, `vendor/`, `wheels/` and
`bundle-manifest.json`. It contains **no DrawInAtlas checkout, Python runtime,
application `.so`, Cargo target directory or Godot import cache**. Transfer the
source separately. Vendored third-party source is intentional offline input.

Ordinary consumer prerequisites remain Make, Bash, Python, zstd, `cc`, glibc
and Godot's distribution runtime libraries. No Nix or Docker dependency was added.
Bubblewrap is used only by the explicit isolation validator.

## Build provenance and repeatability

Each run installed Rust into an independent temporary `RUSTUP_HOME` and used
an independent Cargo home and uv validation cache. No manually assembled bundle8
or existing compiled DrawInAtlas binary was used. Runs 2–4 reused only the
official Godot/uv archives after checking their committed hashes; their download
caches were separate (`TOOLCHAIN_DOWNLOAD_CACHE=.build/downloads-{second,third,fourth}`).

| Run | Output | SHA-256 | Compressed bytes | Exit |
| --- | --- | --- | ---: | ---: |
| 1 | `first.tar.zst` | `2201b57e3f04b0a138bac4e10908bb8df3ac7f442888f59445b21d5c4c0bcf26` | 263487549 | 0 |
| 2 | `second.tar.zst` | `b65068e26edfb157779d45caba950ef6c920b710c1fe36f0b88e80979ce4acfc` | 263487940 | 0 |
| 3, normalized | `third.tar.zst` | `3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2` | 263487525 | 0 |
| 4, normalized | `fourth.tar.zst` | `3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2` | 263487525 | 0 |
| Ubuntu hosted, normalized | workflow `43984960775` | `3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2` | 263487525 | 0 |

The first two manifests differed in **one file only**:
`rust/lib/rustlib/components`. rustup's concurrent component installation wrote
`cargo` / `clippy` in different orders. Sorting this non-semantic registry and
normalizing permissions eliminated the observed difference. Archive ordering,
owner/group and timestamps are also fixed. uv's random-ID mutable cache is no
longer an archive input; source-pinned universal wheels replace it.

**Byte identity is demonstrated for two independent clean builds on the owner
host and a fresh Ubuntu 24.04 GitHub runner.** The Ubuntu build used Python
3.12.3 rather than 3.14.10 and still produced the same archive. This is an
observed match for those environments, not an assertion for arbitrary hosts or
compiler/archive-tool versions. The final artifact was copied unchanged from
run 3; removing the old external sidecar did not change its bytes.

Exact generation commands, with the cache environment noted above:

```sh
make bundle BUNDLE_OUT=.build/bundles/first.tar.zst
make bundle BUNDLE_OUT=.build/bundles/second.tar.zst \
  GODOT_ARCHIVE=.build/downloads/godot-4.8-beta3.zip \
  UV_ARCHIVE=.build/downloads/uv-linux-x86_64.tar.gz
# Repeat the second command with third/fourth output and fresh cache names.
sha256sum .build/bundles/third.tar.zst .build/bundles/fourth.tar.zst
make bundle-verify
```

Source hashes:

```text
toolchain.lock.toml  600c10d2b84b0a00e677fd0c4df0ffea4d590e10f80650fa4cde910c5280e08e
Cargo.lock          db5cd25d683236684955ede495a4326a4c470678d2713fef650ed0b066ccee80
official Godot zip  5595db30bbad4d3076d132ebc8ebafb02aafc3958dc2f730fcbfdab9ea51313c
official uv tar.gz  5acfd9177cfecf0bf87578f059728215ccc884388988f55f7a65041b57387d91
```

## Exact local environment

| Component | Installed/system mode | Bundle mode |
| --- | --- | --- |
| OS / architecture | Arch Linux, x86-64, kernel `7.3.4-1-cachyos` | Same kernel; isolated network/filesystem/home |
| glibc | 2.44 | Consumer's glibc 2.44 |
| Python | `/usr/bin/python3`, 3.14.10 | Consumer's Python 3.14.10; no managed download |
| Godot | `/home/t0ast/.local/bin/godot`, `4.8.beta3.official.c51ff06e8` | Same official Godot release |
| rustc | 1.100.0 (`0ef1bc386`, 2026-11-09) | 1.99.1 (`58cf8f9c3`, 2026-10-13) |
| Cargo | 1.100.0 (`3acc79c0c`) | 1.99.1 (`5f94df478`) |
| Hokusai | 0.3.0, Cargo.lock | Same vendored source |
| uv | 0.13.8 (`3d97a6aad`, distribution build) | Official 0.13.8 Linux GNU build |
| Ruff / ty | 0.17.5 / 0.0.104 via uv | Same pins from internal wheels |
| Make / tar / zstd | 4.4.1 / 1.35 / 1.5.7 | OS prerequisites |
| cc | GCC 16.2.1 | OS linker/compiler prerequisite |

`ldd` resolved both Godot/Rust and the native extension without missing libraries.
This proves the owner host's ABI, not all Linux distributions. The hosted run
also verifies the bundle and cold compilation on Ubuntu 24.04. Universal
`py3-none` wheels remove Python-minor-specific cache identities; both Python
3.14.10 and hosted 3.12.3 passed cold offline lint. Other minors remain untested.

## Successful local checks

| Command / witness | Exit | Result |
| --- | ---: | --- |
| `make doctor TOOLCHAIN=system` | 0 | Installed Godot/Rust/Cargo/uv paths and versions printed |
| `make test TOOLCHAIN=system` | 0 | 25 Rust tests; native brush 32; native tiles 312; Atlas history 43 checks |
| `make check TOOLCHAIN=system` (final delivery configuration) | 0 | 17 bootstrap tests, Ruff, ty, Rust format/test, both projects, standalone 42 checks |
| `python3 -m unittest discover -s tests -p 'test_*.py'` | 0 | 544 tests, 16 documented opt-in skips |
| `python3 tests/check_explicit_types.py` | 0 | Owned GDScript / examples |
| `python3 tools/validate_ticket_store.py` | 0 | Ticket/index consistency and open manual gates |
| Real Wayland `t148_canvas_tile_cutover_x11.gd` | 0 | 46 checks, zero failures; real native tile FFI, painting, erasing, history and `.drawing` Save/Open |
| `make drawing` / `make atlas` through `local.mk` executable paths containing spaces, with `GODOT_ARGS='--headless --quit-after 2'` | 0 | Build/import/launch commands complete |

Both real GUIs were separately observed in a virtual KWin Wayland session.
Drawing showed native paint, erase and History cursor 1/2 → 2/2 for Undo/Redo;
Atlas launched and painted/erased its sample board. These interactive processes
were deliberately terminated by session cleanup; no natural exit code is
claimed for that separate observation. The graphical native Canvas test exited
normally. Its renderer selected **Mesa 26.2.6 / Intel Iris Xe**, not a physical
RTX3070/tablet input-to-photon test. Raw screenshots and app logs are retained.

System `doctor` initially rejected Rust 1.100.0 because it incorrectly required
the bundle pin. It now accepts the crate's Rust >=1.94 baseline while bundle mode
remains pinned. Command-line assignment precedence over `local.mk` is verified:
an explicit nonexistent `GODOT` overrides the working local setting and fails.

## Cold offline acceptance, single archive only

```sh
python3 tools/check_offline_toolchain.py \
  --bundle .build/bundles/drawing-toolchain-linux-x86_64.tar.zst \
  --output /tmp/opencode/t180-cold-single-file
```

Exit **0**. The copy contains source plus **one archive**, with no sidecar or
prior `.so`, Cargo targets, `.godot` state or user caches. The source path and
archive name contain spaces. Bubblewrap hides the original `/home` and `/root`,
provides a fresh HOME, clears inherited environment and disables networking.
A direct connection to `1.1.1.1:443` returns `ENETUNREACH` (101).

Inside isolation, `CARGO`, `RUSTC`, `GODOT`, `UV` and `RUSTC_WRAPPER` deliberately
point at unavailable host programs. Bundle mode selects its actual executables
and removes the wrapper. Cargo uses vendored sources with `--offline --locked`;
uv uses `UV_OFFLINE=1`, no index, internal wheels and no Python downloads.

Every command exits 0: `make doctor`, `make bundle-verify`, `make bundle-check`,
two consecutive `make lint` invocations, then another `make bundle-verify`.
The cold native release compilation is visible in the raw output; so are the
25 Rust / 32 brush / 312 tile / **42 standalone Save/Open** / 43 Atlas checks.
The repeated lint and final integrity check prove uv does not mutate the sealed
payload. The kernel network namespace rules out downloads independently of
tool-specific offline settings. Earlier cold runs are retained too.

## Failure handling and caching

All expected failures remain failures; none silently chooses installed tools.
Shell `make` errors below use exit 2; their Python/engine child uses exit 1.

| Probe | Observed result |
| --- | --- |
| Bad/empty external checksum supplied as a negative fixture | Rejected before extraction; external checksums are not generated or needed for normal use |
| Corrupt zstd bytes | Exit 2 with zstd/`toolchain:` diagnostics, no traceback |
| `../`, absolute paths, symlink, hardlink, FIFO tar members | Rejected by streaming extractor |
| Mutated payload / malformed manifest / wrong platform | Rejected by manifest and platform validation |
| Actual modified toolchain.lock.toml in disposable consumer | Exit 2, different-toolchain-lock message |
| Actual modified Cargo.lock in disposable consumer | Exit 2, different-Cargo-lock message; restoring both locks returns exit 0 |
| Missing bundled Cargo/rustc/Godot/uv | Exit 2; missing/unexpected manifest entry; no host fallback |
| Invalid ELF native library | Godot startup/load error and required-class check exits 1 |
| Missing `.so` / missing or invalid `.gdextension` | Explicit staging/registration error, exit 1 |
| Wrong Godot API/version fixture | Explicit version rejection before import/launch |
| Godot script error but engine exits 0 | Wrapper rejects it; bootstrap regression covers the case |
| Compressed 500 MiB and 500 MiB + 1 byte | Boundary accepted / oversize rejected; simulated oversized compressor output also preserves the previous artifact and cleans its temporary file |
| Extra repository directory in bundle staging | Archive publication rejected; one internal file manifest, no generated external sidecar |

For caching, touching only canonical GDScript followed by `make native` produces
**no Rust compilation** and leaves the staged `.so` mtime unchanged. Temporarily
editing Rust source recompiles `drawing-brush` (2.24 seconds); the probe edit was
removed and the restored source rebuilt successfully. Native staging copies
only changed bytes, and extension-list registration avoids redundant writes.

## Hosted CI and remaining gates

At `fbf752c8`, the new bundle was built from scratch and verified on Ubuntu 24.04.
The cold test failed before any compilation because bubblewrap loopback setup
was denied (`Failed RTM_NEWADDR: Operation not permitted`). The next revision
adds the disposable runner's AppArmor user-namespace setting and a preflight
before spending time generating the bundle.

At `bdcf1c8d`, [workflow 43984960775](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/43984960775)
is **SUCCESS** (job `133710625081`, completed `2026-11-17T00:16:05Z`). The
namespace preflight passed after changing the disposable runner setting.
The fresh bundle build produced the exact same SHA-256 and size as runs 3/4.
The transferred single archive and source then passed all seven commands in
the cold consumer's `results.json`: network denial, doctor, verification,
native/standalone/Atlas tests, two offline lint runs, final integrity verification.
Doctor records Python **3.12.3**, bundled Rust **1.99.1**, official Godot/uv and
both native binaries initially **missing** before cold compilation. Rust's
25 tests and Godot's 32/312/42/43-check suites all pass. Ticket validation also
passes on that SHA.

The [first repaired desktop run](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/43983436571)
improved from the baseline **30/46 to 42/46**. Its remaining four strict failures
are retained, rather than suppressing checks or restoring a production fallback:

- T-085 / queued/history fixtures still assume Legacy brush geometry/dabs, and
  `hokusai_bulk_delta_smoke.gd` preloads deleted `t147_scripted_session_bridge.gd`.
- T-087 image-frame fixtures still fail post-camera/policy-change gesture assertions.
- The Linux export test cannot load the exported native library, and its old
  `t068_release_gate.py` explicitly forbids native libraries / copies only ELF/PCK.
- T-066's historical signed-coordinate save fixture crosses the newer safe
  signed projection boundary.

These are T-148/T-150 native-transition and T-105/T-106/T-107 coverage/portability
follow-ups, not evidence of a green complete editor. T-180 stays In Progress;
no merge request is made. [The final code's desktop run](https://github.com/FivePebblesGPT/DrawInAtlas/actions/runs/43984960709)
retains the same **42/46** result and the same four failed check IDs; these are
not suppressed by the separate green T-180 workflow. The historical bundle8 was unavailable in the local
Downloads/Documents search and has not been newly certified.

## Raw evidence

Unabridged command stdout/stderr, commands with exit codes/timing, failed baseline
checks, generated archive inventories, local negative/caching probes, cold-consumer
logs, hosted logs and GUI screenshots are packaged in
[`raw/T-180-2026-11-17-toolchain.tar.zst`](raw/T-180-2026-11-17-toolchain.tar.zst).
This is a small **test-evidence** archive, separate from the transferable toolchain.
Extract it with `tar --zstd -xf ...` and inspect `local/commands.jsonl`,
`local/probes.json`, `t180-cold-single-file/results.json` and individual `.log` files.
