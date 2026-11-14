source tools/ci_fail_late.sh
python3 -m unittest discover -s tests -p 'test_t090_responsive_workspace.py' -v
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/topbar_overflow_smoke.gd 2>&1 | tee /tmp/godot-t090-overflow.log
python3 tools/check_godot_model_log.py /tmp/godot-t090-overflow.log --marker T090_OVERFLOW_PASSED || ci_fail_marker 'T090 overflow checkmark and command parity rejected'
ci_finish
