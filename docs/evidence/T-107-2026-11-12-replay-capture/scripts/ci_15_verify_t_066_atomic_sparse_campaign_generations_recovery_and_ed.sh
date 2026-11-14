source tools/ci_fail_late.sh
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/campaign_bundle_smoke.gd 2>&1 | tee /tmp/godot-t066-bundle.log
grep -q 'ATLAS_BUNDLE_PASSED' /tmp/godot-t066-bundle.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T066_FAILED:|ATLAS_BUNDLE_FAILED' /tmp/godot-t066-bundle.log; then ci_fail_marker 'Forbidden error marker'; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/campaign_bundle_editor_smoke.gd 2>&1 | tee /tmp/godot-t066-editor.log
grep -q 'ATLAS_BUNDLE_EDITOR_PASSED' /tmp/godot-t066-editor.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T066_EDITOR_FAILED:|ATLAS_BUNDLE_EDITOR_FAILED' /tmp/godot-t066-editor.log; then ci_fail_marker 'Forbidden error marker'; fi
ci_finish
