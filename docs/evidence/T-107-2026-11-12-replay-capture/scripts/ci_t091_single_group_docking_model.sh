source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/dock_single_group_smoke.gd 2>&1 | tee /tmp/godot-t091-dock-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t091-dock-model.log --marker T091_MODEL_PASSED || ci_fail_marker 'T091 docking model log rejected'
python3 -m unittest discover -s tests -p 'test_t091_dock.py' -v
ci_finish
