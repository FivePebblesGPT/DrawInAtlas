set -euo pipefail
python3 -m unittest discover -s tests -p test_t068_fill_process_profile.py
python3 -m unittest discover -s tests -p test_t068_native_thread_jitter.py
python3 -m unittest discover -s tests -p test_t068_checked_abi.py
python3 -m unittest discover -s tests -p test_t068_bridge_runner.py
python3 -m unittest discover -s tests -p test_t068_scalar_gdextension.py
python3 -m unittest discover -s tests -p test_t068_scalar_atomicity.py
python3 -m unittest discover -s tests -p test_t068_scalar_publication.py
python3 -m unittest discover -s tests -p test_t068_scalar_large_publication.py
python3 -m unittest discover -s tests -p test_t068_scalar_transform.py
python3 -m unittest discover -s tests -p test_t068_quad_gdextension.py
python3 -m unittest discover -s tests -p test_t068_quad_publication.py
python3 -m unittest discover -s tests -p test_t068_cairo_cpu.py
python3 -m unittest discover -s tests -p test_t068_blend2d_cpu.py
python3 -m unittest discover -s tests -p test_t068_blend2d_brush.py
python3 -m unittest discover -s tests -p test_t068_matched_brush.py
python3 -m unittest discover -s tests -p test_t104_backend_decision.py
python3 tools/benchmarks/t104_backend_decision.py --verify
python3 -m unittest discover -s tests -p test_t068_native_memory.py
python3 -m unittest discover -s tests -p test_t068_visual_device.py
python3 -m unittest discover -s tests -p test_t068_visual_contention.py
python3 -m unittest discover -s tests -p test_t068_visual_counterbalanced.py
python3 -m unittest discover -s tests -p test_t068_release_gate.py
python3 -m unittest discover -s tests -p test_t068_blend2d_scale.py
python3 -m unittest discover -s tests -p test_t068_blend2d_large_parity.py
python3 -m unittest discover -s tests -p test_t068_scalar_hard_brush.py
python3 -m unittest discover -s tests -p test_t068_scalar_rgba8.py
python3 -m unittest discover -s tests -p test_t068_scalar_deltas.py
T068_QUAD_GODOT=godot python3 -m unittest discover -s tests -p test_t068_blend2d_quad.py
T068_QUAD_GODOT=godot python3 -m unittest discover -s tests -p test_t068_quad_differential.py
T068_QUAD_GODOT=godot python3 -m unittest discover -s tests -p test_t068_quad_stress.py
python3 -m unittest discover -s tests -p test_t068_quad_compiler_matrix.py
python3 -m unittest discover -s tests -p test_t106_oracle_engine_compat.py
python3 -m unittest discover -s tests -p test_t068_scalar_strict_fp.py
python3 -m unittest discover -s tests -p test_t068_native_sanitizer.py
python3 -m unittest discover -s tests -p test_t068_skia_cpu.py
T068_GODOT=godot python3 -m unittest discover -s tests -p test_t068_skia_brush.py
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_dab_geometry_smoke.gd 2>&1 | tee /tmp/godot-t068-dab.log
grep -q 'T068_DAB_PASSED' /tmp/godot-t068-dab.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_DAB_FAILED:' /tmp/godot-t068-dab.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_axis_sweep_smoke.gd 2>&1 | tee /tmp/godot-t068-axis-sweep.log
grep -q 'T068_AXIS_SWEEP_PASSED' /tmp/godot-t068-axis-sweep.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_AXIS_SWEEP_FAILED:' /tmp/godot-t068-axis-sweep.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_edit_tile_cache_smoke.gd 2>&1 | tee /tmp/godot-t068-tile-cache.log
grep -q 'T068_TILE_CACHE_PASSED' /tmp/godot-t068-tile-cache.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_TILE_CACHE_FAILED:' /tmp/godot-t068-tile-cache.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_fill_tile_cache_smoke.gd 2>&1 | tee /tmp/godot-t068-fill-cache.log
grep -q 'T068_FILL_CACHE_PASSED' /tmp/godot-t068-fill-cache.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_FILL_CACHE_FAILED:' /tmp/godot-t068-fill-cache.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_fill_frontier_smoke.gd 2>&1 | tee /tmp/godot-t068-frontier.log
grep -q 'T068_FRONTIER_PASSED' /tmp/godot-t068-frontier.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_FRONTIER_FAILED:' /tmp/godot-t068-frontier.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_fill_verified_stage_smoke.gd 2>&1 | tee /tmp/godot-t068-verified-stage.log
grep -q 'T068_VERIFIED_STAGE_PASSED' /tmp/godot-t068-verified-stage.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_VERIFIED_STAGE_FAILED:' /tmp/godot-t068-verified-stage.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_publication_tile_cache_smoke.gd 2>&1 | tee /tmp/godot-t068-publication.log
grep -q 'T068_PUBLICATION_PASSED' /tmp/godot-t068-publication.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T068_PUBLICATION_FAILED:' /tmp/godot-t068-publication.log; then exit 1; fi
