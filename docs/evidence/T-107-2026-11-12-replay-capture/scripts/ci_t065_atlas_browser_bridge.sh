set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/asset_browser_atlas_smoke.gd 2>&1 | tee /tmp/godot-t065-atlas-browser.log
python3 tools/check_godot_model_log.py /tmp/godot-t065-atlas-browser.log --marker T065_ATLAS_BROWSER_PASSED
