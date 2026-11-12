set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_render_smoke.gd 2>&1 | tee /tmp/godot-t064-child-render.log
grep -q 'T064_CHILD_RENDER_PASSED' /tmp/godot-t064-child-render.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_RENDER_FAILED:' /tmp/godot-t064-child-render.log; then exit 1; fi
