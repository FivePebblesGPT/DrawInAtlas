set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_assets_smoke.gd 2>&1 | tee /tmp/godot-object-assets.log
grep -q 'OBJECT_ASSETS_PASSED' /tmp/godot-object-assets.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:|OBJECT_ASSETS_FAILED:' /tmp/godot-object-assets.log; then exit 1; fi
