set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_source_manager_smoke.gd 2>&1 | tee /tmp/godot-t065-source-manager.log
grep -q 'T065_MANAGER_PASSED' /tmp/godot-t065-source-manager.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_MANAGER_FAILED:' /tmp/godot-t065-source-manager.log; then exit 1; fi
