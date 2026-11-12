set -euo pipefail
# A fresh isolated stage is required even on repeated CI replays.
release_root="$(mktemp -d "${TMPDIR:-/tmp}/drawing-dist.XXXXXXXX")"
trap 'rm -rf "$release_root"' EXIT
python3 tools/build_drawing_app.py --output "$release_root/project"
godot --headless --editor --path "$release_root/project" --import --quit
godot --headless --path "$release_root/project" --export-release Linux "$release_root/Drawing.x86_64"
test -s "$release_root/Drawing.x86_64"
test -s "$release_root/Drawing.pck"
# Font bytes ship as imported .fontdata, not raw .ttf.
# Probe the exported PCK rather than editor source files.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path "$release_root" --main-pack "$release_root/Drawing.pck" \
  --script "$release_root/project/tests/packaged_fonts_smoke.gd" \
  2>&1 | tee /tmp/godot-export-fonts.log
python3 tools/check_godot_model_log.py /tmp/godot-export-fonts.log --marker DRAWING_PACK_FONT_PASSED
# Inspect the exported ELF/PCK and launch with a disposable HOME/CWD.
python3 tools/benchmarks/t068_release_gate.py \
  --stage "$release_root/project" --linux "$release_root" \
  --launch-linux --output /tmp/t068-standalone-linux-release.json
