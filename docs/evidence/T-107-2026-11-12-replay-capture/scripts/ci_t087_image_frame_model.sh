source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/image_frame_smoke.gd 2>&1 | tee /tmp/godot-t087-frame-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t087-frame-model.log --marker T087_MODEL_PASSED || ci_fail_marker 'T087_MODEL_PASSED log rejected'
ci_finish
