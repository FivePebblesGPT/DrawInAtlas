set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/dock_drag_smoke.gd 2>&1 | tee /tmp/godot-dock-drag.log
grep -q 'T080_DOCK_DRAG_MODEL_PASSED' /tmp/godot-dock-drag.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T080_MODEL_FAILED:' /tmp/godot-dock-drag.log; then exit 1; fi
