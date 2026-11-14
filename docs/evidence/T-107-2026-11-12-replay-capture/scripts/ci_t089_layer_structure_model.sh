source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/layer_structure_smoke.gd 2>&1 | tee /tmp/godot-t089-layers-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t089-layers-model.log --marker T089_MODEL_PASSED || ci_fail_marker 'T089 layers model log rejected'
ci_finish
