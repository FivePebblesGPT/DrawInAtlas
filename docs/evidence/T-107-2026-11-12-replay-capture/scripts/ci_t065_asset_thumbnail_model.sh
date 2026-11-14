set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/asset_browser_thumbnails_smoke.gd 2>&1 | tee /tmp/godot-t065-thumbnails.log
python3 tools/check_godot_model_log.py /tmp/godot-t065-thumbnails.log --marker T065_THUMBNAILS_PASSED
