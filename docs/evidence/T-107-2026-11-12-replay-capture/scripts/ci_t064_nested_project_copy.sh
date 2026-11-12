set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_nested_project_copy_smoke.gd 2>&1 | tee /tmp/godot-t064-project-copy.log
python3 tools/check_godot_model_log.py /tmp/godot-t064-project-copy.log --marker T064_PROJECT_COPY_PASSED
# A saved portable campaign copy includes all retained Drawing/Objects/
# Fonts generations, verified before one destination directory rename.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_nested_campaign_copy_smoke.gd 2>&1 | tee /tmp/godot-t064-campaign-copy.log
python3 tools/check_godot_model_log.py /tmp/godot-t064-campaign-copy.log --marker T064_CAMPAIGN_COPY_PASSED
# Atlas File > Copy saved campaign routes through the same verified API.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_nested_campaign_copy_ui_smoke.gd 2>&1 | tee /tmp/godot-t064-copy-ui.log
python3 tools/check_godot_model_log.py /tmp/godot-t064-copy-ui.log --marker T064_COPY_UI_PASSED
