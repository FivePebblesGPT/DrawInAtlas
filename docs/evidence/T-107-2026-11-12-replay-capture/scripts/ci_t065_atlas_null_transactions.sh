set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_asset_repair_smoke.gd 2>&1 | tee /tmp/godot-t065-null-transactions.log
grep -q 'T065_ASSET_REPAIR_PASSED' /tmp/godot-t065-null-transactions.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_ASSET_REPAIR_FAILED:' /tmp/godot-t065-null-transactions.log; then exit 1; fi
