source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/live_stroke_smoke.gd 2>&1 | tee /tmp/godot-t085-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t085-model.log --marker T085_MODEL_PASSED || ci_fail_marker 'T085 live-stroke model log rejected'
# T-095 60px Brush/Eraser exact-pixel and rollback oracle is mandatory;
# its pointer/framebuffer timing witness stays opt-in and software-only.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/brush_coverage_smoke.gd 2>&1 | tee /tmp/godot-t095-oracle.log
python3 tools/check_godot_model_log.py /tmp/godot-t095-oracle.log --marker T095_ORACLE_PASSED || ci_fail_marker 'T095 Brush/Eraser independent pixel oracle rejected'
# T-095 Hokusai batch delta staging must match the original pixel
# transaction path even when no optional Rust binary is installed.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/hokusai_bulk_delta_smoke.gd 2>&1 | tee /tmp/godot-t095-hokusai-delta.log
python3 tools/check_godot_model_log.py /tmp/godot-t095-hokusai-delta.log --marker T095_BULK_DELTA_PASSED || ci_fail_marker 'T095 Hokusai bulk delta model log rejected'
ci_finish
