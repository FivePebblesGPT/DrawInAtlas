#!/usr/bin/env bash
# Compile the optional native addon from the supplied, checksum-verified
# offline tooling archive. No system Rust or network dependency.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
bundle="${1:-${DRAWING_RUST_TOOLING:-}}"
if [[ -z "$bundle" ]]; then
  echo "usage: $0 /path/to/extracted/Godot_v4.8b3_rust_hokusai_bundle8" >&2
  exit 2
fi
bundle="$(cd -- "$bundle" && pwd -P)"
test -s "$bundle/setup-rust-env.sh"
test -d "$bundle/rust-hokusai/vendor"
source "$bundle/setup-rust-env.sh"
export CARGO_NET_OFFLINE=true
workspace="$root/native/drawing_brush"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$workspace/target}"
export CARGO_BUILD_TARGET=x86_64-unknown-linux-gnu
export CARGO_INCREMENTAL=0
# A clean clone contains only pinned manifests/lock. The vendored source path
# is injected from the user's extracted archive rather than hard-coded in git.
config="$(mktemp)"
trap 'rm -f "$config"' EXIT
printf '[source.crates-io]\nreplace-with = "vendored-sources"\n' >"$config"
printf '[source.vendored-sources]\ndirectory = "%s"\n' "$bundle/rust-hokusai/vendor" >>"$config"
printf '[net]\noffline = true\n' >>"$config"
cd "$workspace"
cargo --config "$config" build --offline --locked --release
cargo --config "$config" fmt -- --check
target="$root/addons/drawing/native"
mkdir -p "$target/bin"
cp -- "$CARGO_TARGET_DIR/x86_64-unknown-linux-gnu/release/libdrawing_brush.so" \
  "$target/bin/libdrawing_brush.so"
cp -- "$workspace/drawing_brush.gdextension.template" "$target/drawing_brush.gdextension"
echo "Native addon available at $target (Linux x86-64, Godot 4.7 API)."
