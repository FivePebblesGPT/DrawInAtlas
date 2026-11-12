set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/dock_float_smoke.gd 2>&1 | tee /tmp/godot-dock-float.log
grep -q 'T081_FLOAT_MODEL_PASSED' /tmp/godot-dock-float.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T081_MODEL_FAILED:' /tmp/godot-dock-float.log; then exit 1; fi
