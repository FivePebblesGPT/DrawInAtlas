source tools/ci_fail_late.sh
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_editor_smoke.gd 2>&1 | tee /tmp/godot-object-editor.log
python3 tools/check_godot_model_log.py /tmp/godot-object-editor.log --marker OBJECT_EDITOR_PASSED || ci_fail_marker 'OBJECT_EDITOR_PASSED log rejected'
python3 tools/build_drawing_app.py --in-place
# Staged licensed fonts must be imported before UI text editing.
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/object_editor_ui_smoke.gd 2>&1 | tee /tmp/godot-object-editor-ui.log
python3 tools/check_godot_model_log.py /tmp/godot-object-editor-ui.log --marker DRAWING_OBJECT_UI_PASSED || ci_fail_marker 'DRAWING_OBJECT_UI_PASSED log rejected'
ci_finish
