set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/dock_cross_smoke.gd 2>&1 | tee /tmp/godot-dock-cross.log
grep -q 'T082_CROSS_MODEL_PASSED' /tmp/godot-dock-cross.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T082_MODEL_FAILED:' /tmp/godot-dock-cross.log; then exit 1; fi
