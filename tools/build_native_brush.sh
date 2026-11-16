#!/usr/bin/env bash
# Native GDExtension compilation for system or Make-selected offline toolchains.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TRIPLE="x86_64-unknown-linux-gnu"
COMMAND="build"
if [[ "${1:-}" == "--test" ]]; then
  COMMAND="test"
  shift
fi
if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "Required native painting extension currently supports Linux x86-64 only" >&2
  exit 2
fi

# Historical direct invocation remains usable; Make passes env instead.
if [[ $# -gt 0 ]]; then
  bundle="$(cd -- "$1" && pwd -P)"
  source "$bundle/setup-rust-env.sh"
  export CARGO_VENDOR_DIR="$bundle/rust-hokusai/vendor"
  export CARGO_NET_OFFLINE=true
fi

CARGO="${CARGO:-cargo}"
WORKSPACE="$ROOT/native/drawing_brush"
TARGET_DIR="${CARGO_TARGET_DIR:-$WORKSPACE/target}"
export CARGO_TARGET_DIR="$TARGET_DIR"
export CARGO_INCREMENTAL=0
args=(--locked --target "$TRIPLE")
if [[ "$COMMAND" == "build" ]]; then
  args+=(--release)
fi
config=""
if [[ -n "${CARGO_VENDOR_DIR:-}" ]]; then
  [[ -d "$CARGO_VENDOR_DIR" ]] || { echo "Missing Cargo vendor directory: $CARGO_VENDOR_DIR" >&2; exit 2; }
  config="$(mktemp)"
  trap 'rm -f "$config"' EXIT
  # Cargo TOML accepts escaped backslash and quote characters in source paths.
  vendor_escaped="${CARGO_VENDOR_DIR//\\/\\\\}"
  vendor_escaped="${vendor_escaped//\"/\\\"}"
  printf '[source.crates-io]\nreplace-with = "vendored-sources"\n' > "$config"
  printf '[source.vendored-sources]\ndirectory = "%s"\n' "$vendor_escaped" >> "$config"
  printf '[net]\noffline = true\n' >> "$config"
  args=(--offline "${args[@]}")
  "$CARGO" --config "$config" "$COMMAND" "${args[@]}" --manifest-path "$WORKSPACE/Cargo.toml"
else
  "$CARGO" "$COMMAND" "${args[@]}" --manifest-path "$WORKSPACE/Cargo.toml"
fi
if [[ "$COMMAND" == "test" ]]; then
  exit 0
fi
"$CARGO" fmt --manifest-path "$WORKSPACE/Cargo.toml" -- --check

binary="$TARGET_DIR/$TRIPLE/release/libdrawing_brush.so"
[[ -s "$binary" ]] || { echo "Native build did not produce $binary" >&2; exit 1; }
destination="$ROOT/addons/drawing/native"
mkdir -p "$destination/bin"
cp -- "$binary" "$destination/bin/libdrawing_brush.so"
cp -- "$WORKSPACE/drawing_brush.gdextension.template" "$destination/drawing_brush.gdextension"
printf 'Required native Brush/Eraser: %s\n' "$destination/bin/libdrawing_brush.so"
