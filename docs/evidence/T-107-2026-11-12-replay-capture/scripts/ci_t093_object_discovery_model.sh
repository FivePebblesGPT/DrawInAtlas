source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/object_discovery_smoke.gd 2>&1 | tee /tmp/godot-t093-discovery-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t093-discovery-model.log --marker T093_MODEL_PASSED || ci_fail_marker 'T093 Object discovery model log rejected'
python3 -m unittest discover -s tests -p 'test_t093_object_discovery.py' -v
ci_finish
