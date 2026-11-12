source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/selection_clipboard_smoke.gd 2>&1 | tee /tmp/godot-t088-selection-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t088-selection-model.log --marker T088_MODEL_PASSED || ci_fail_marker 'T088_MODEL_PASSED log rejected'
# T-088 sparse transparent Paste must match a separate dense source oracle.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/selection_sparse_paste_smoke.gd 2>&1 | tee /tmp/godot-t088-sparse-paste.log
python3 tools/check_godot_model_log.py /tmp/godot-t088-sparse-paste.log --marker T088_SPARSE_PASTE_PASSED || ci_fail_marker 'T088 sparse paste source oracle rejected'
# T-088 capture must skip empty source tiles and preserve lazy-source failures.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/selection_sparse_capture_smoke.gd 2>&1 | tee /tmp/godot-t088-sparse-capture.log
python3 tools/check_godot_model_log.py /tmp/godot-t088-sparse-capture.log --marker T088_SPARSE_CAPTURE_PASSED || ci_fail_marker 'T088 sparse capture source oracle rejected'
# T-096 exact large-mask contours/Move source oracle is mandatory;
# real pointer/display and owner acceptance remain separate.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/selection_large_smoke.gd 2>&1 | tee /tmp/godot-t096-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t096-model.log --marker T096_MODEL_PASSED || ci_fail_marker 'T096 large selection and Move oracle rejected'
ci_finish
