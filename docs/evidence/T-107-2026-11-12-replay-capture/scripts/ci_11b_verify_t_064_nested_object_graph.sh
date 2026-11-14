set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_graph_smoke.gd 2>&1 | tee /tmp/godot-t064-child-graph.log
grep -q 'T064_CHILD_GRAPH_PASSED' /tmp/godot-t064-child-graph.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_GRAPH_FAILED:' /tmp/godot-t064-child-graph.log; then exit 1; fi
