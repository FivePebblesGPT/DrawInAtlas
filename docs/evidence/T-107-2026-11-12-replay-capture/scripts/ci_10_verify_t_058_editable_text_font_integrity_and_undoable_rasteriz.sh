source tools/ci_fail_late.sh
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_text_smoke.gd 2>&1 | tee /tmp/godot-drawing-text.log
python3 tools/check_godot_model_log.py /tmp/godot-drawing-text.log --marker DRAWING_TEXT_PASSED || ci_fail_marker 'DRAWING_TEXT_PASSED log rejected'
python3 tools/build_drawing_app.py --in-place
# Staging refreshes font files: let Godot generate their imported FontFile resources.
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/text_editor_smoke.gd 2>&1 | tee /tmp/godot-drawing-text-ui.log
python3 tools/check_godot_model_log.py /tmp/godot-drawing-text-ui.log --marker DRAWING_TEXT_UI_PASSED || ci_fail_marker 'DRAWING_TEXT_UI_PASSED log rejected'
ci_finish
