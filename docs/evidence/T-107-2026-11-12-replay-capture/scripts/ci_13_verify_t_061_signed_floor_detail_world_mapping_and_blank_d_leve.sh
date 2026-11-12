set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_world_mapping_smoke.gd 2>&1 | tee /tmp/godot-world-mapping.log
grep -q 'T061_WORLD_MAPPING_PASSED' /tmp/godot-world-mapping.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T061_FAILED:' /tmp/godot-world-mapping.log; then exit 1; fi
