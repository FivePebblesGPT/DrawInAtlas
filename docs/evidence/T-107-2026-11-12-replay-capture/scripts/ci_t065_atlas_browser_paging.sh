set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/asset_browser_atlas_paging_smoke.gd 2>&1 | tee /tmp/godot-t065-atlas-paging.log
grep -q 'T065_PAGING_PASSED' /tmp/godot-t065-atlas-paging.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_PAGING_FAILED:' /tmp/godot-t065-atlas-paging.log; then exit 1; fi
