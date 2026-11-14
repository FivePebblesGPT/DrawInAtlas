set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/dock_persistence_smoke.gd 2>&1 | tee /tmp/godot-dock-persistence.log
grep -q 'T083_MODEL_PASSED' /tmp/godot-dock-persistence.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T083_MODEL_FAILED:' /tmp/godot-dock-persistence.log; then exit 1; fi
