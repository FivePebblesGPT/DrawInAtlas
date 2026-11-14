source tools/ci_fail_late.sh
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_history_smoke.gd 2>&1 | tee /tmp/godot-drawing-history.log
grep -q 'DRAWING_HISTORY_PASSED' /tmp/godot-drawing-history.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:|failed;' /tmp/godot-drawing-history.log; then ci_fail_marker 'Forbidden error marker'; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_history_editor_smoke.gd 2>&1 | tee /tmp/godot-drawing-history-editor.log
grep -q 'DRAWING_HISTORY_EDITOR_PASSED' /tmp/godot-drawing-history-editor.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:' /tmp/godot-drawing-history-editor.log; then ci_fail_marker 'Forbidden error marker'; fi
ci_finish
