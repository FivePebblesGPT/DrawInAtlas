set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/asset_browser_real_io_smoke.gd 2>&1 | tee /tmp/godot-t065-real-io.log
grep -q 'T065_REAL_IO_PASSED' /tmp/godot-t065-real-io.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_REAL_IO_FAILED:' /tmp/godot-t065-real-io.log; then exit 1; fi
