source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/color_history_smoke.gd 2>&1 | tee /tmp/godot-t092-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t092-model.log --marker T092_MODEL_PASSED || ci_fail_marker 'T092 Colors/History model log rejected'
python3 -m unittest discover -s tests -p 'test_t092_color_history.py' -v
ci_finish
