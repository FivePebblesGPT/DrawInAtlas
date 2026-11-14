source tools/ci_fail_late.sh
python3 tools/build_drawing_app.py --in-place
godot --headless --editor --path drawing --import --quit
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/viewport_cache_smoke.gd 2>&1 | tee /tmp/godot-t086-cache-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-cache-model.log --marker T086_MODEL_PASSED || ci_fail_marker 'T086 viewport model log rejected'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/viewport_cache_focus_smoke.gd 2>&1 | tee /tmp/godot-t086-cache-focus.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-cache-focus.log --marker T086_FOCUS_PASSED || ci_fail_marker 'T086 dense viewport retention priority witness error'
# T-102 bounded cold scheduling: signed focal priority, dirty/preview
# invalidation and conservative over-budget/unknown occupancy fallback.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/t102_cold_population_smoke.gd 2>&1 | tee /tmp/godot-t102-cold-population.log
python3 tools/check_godot_model_log.py /tmp/godot-t102-cold-population.log --marker T102_MODEL_PASSED || ci_fail_marker 'T102 cold population scheduling log rejected'
# T-103 software-only over-budget focal preselection and safe fallbacks.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/t103_retention_plan_smoke.gd 2>&1 | tee /tmp/godot-t103-retention.log
python3 tools/check_godot_model_log.py /tmp/godot-t103-retention.log --marker T103_MODEL_PASSED || ci_fail_marker 'T103 focal retention planner rejected'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/renderer_cold_tile_smoke.gd 2>&1 | tee /tmp/godot-t086-cold-model.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-cold-model.log --marker T086_COLD_PASSED || ci_fail_marker 'T086 cold renderer parity witness error'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/renderer_sparse_pixel_smoke.gd 2>&1 | tee /tmp/godot-t086-sparse-pixels.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-sparse-pixels.log --marker T086_SPARSE_PIXEL_PASSED || ci_fail_marker 'T086 sparse source-pixel oracle rejected'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/renderer_visible_plan_smoke.gd 2>&1 | tee /tmp/godot-t086-visible-plan.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-visible-plan.log --marker T086_PLAN_PASSED || ci_fail_marker 'T086 visible-layer plan parity witness error'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/renderer_shared_chunks_smoke.gd 2>&1 | tee /tmp/godot-t086-shared-chunks.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-shared-chunks.log --marker T086_SHARED_PASSED || ci_fail_marker 'T086 shared source-chunk cache parity witness error'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/renderer_sparse_layer_smoke.gd 2>&1 | tee /tmp/godot-t086-sparse-layers.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-sparse-layers.log --marker T086_SPARSE_PASSED || ci_fail_marker 'T086 sparse-layer source culling parity witness error'
timeout --signal=TERM --kill-after=5s 120s godot --headless --path drawing --script res://tests/viewport_preview_index_smoke.gd 2>&1 | tee /tmp/godot-t086-preview-index.log
python3 tools/check_godot_model_log.py /tmp/godot-t086-preview-index.log --marker T086_PREVIEW_INDEX_PASSED || ci_fail_marker 'T086 bounded preview index parity witness error'
python3 -m unittest discover -s tests -p 'test_t086_benchmark_fixtures.py' -v || ci_fail_marker 'T086 historical fixture integrity contract failure'
ci_finish
