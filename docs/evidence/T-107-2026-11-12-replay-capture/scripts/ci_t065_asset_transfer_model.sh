set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/asset_browser_transfer_smoke.gd 2>&1 | tee /tmp/godot-t065-transfers.log
grep -q 'T065_TRANSFERS_PASSED' /tmp/godot-t065-transfers.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_TRANSFER_FAILED:' /tmp/godot-t065-transfers.log; then exit 1; fi
