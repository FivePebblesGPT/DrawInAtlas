set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_edit_smoke.gd 2>&1 | tee /tmp/godot-t064-child-edit.log
grep -q 'T064_CHILD_EDIT_PASSED' /tmp/godot-t064-child-edit.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_EDIT_FAILED:' /tmp/godot-t064-child-edit.log; then exit 1; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_structure_smoke.gd 2>&1 | tee /tmp/godot-t064-child-structure.log
grep -q 'T064_CHILD_STRUCTURE_PASSED' /tmp/godot-t064-child-structure.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_STRUCTURE_FAILED:' /tmp/godot-t064-child-structure.log; then exit 1; fi
# Repair retained NULL children through the same optimistic graph
# boundary and reversible parent-scoped history (no owner UX gate).
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_null_repair_smoke.gd 2>&1 | tee /tmp/godot-t064-child-null-repair.log
grep -q 'T064_CHILD_REPAIR_PASSED' /tmp/godot-t064-child-null-repair.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_REPAIR_FAILED:' /tmp/godot-t064-child-null-repair.log; then exit 1; fi
# Uniform child scaling shares the optimistic transform timeline.
# A native inspector screenshot is targeted, never fast push CI.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_scale_smoke.gd 2>&1 | tee /tmp/godot-t064-child-scale.log
grep -q 'T064_CHILD_SCALE_PASSED' /tmp/godot-t064-child-scale.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_SCALE_FAILED:' /tmp/godot-t064-child-scale.log; then exit 1; fi
# T-064 sibling paint order uses the same atomic graph/history path;
# no native framebuffer suite is added to the fast push job.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_order_smoke.gd 2>&1 | tee /tmp/godot-t064-child-order.log
grep -q 'T064_CHILD_ORDER_PASSED' /tmp/godot-t064-child-order.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_ORDER_FAILED:' /tmp/godot-t064-child-order.log; then exit 1; fi
# Optional labels distinguish repeated child instances without renaming
# their shared source; no native framebuffer suite runs on fast CI.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_label_smoke.gd 2>&1 | tee /tmp/godot-t064-child-label.log
grep -q 'T064_CHILD_LABEL_PASSED' /tmp/godot-t064-child-label.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_LABEL_FAILED:' /tmp/godot-t064-child-label.log; then exit 1; fi
# Duplicate only a linked child *placement* with fresh identity;
# explicit nested source Save As remains owner-policy gated.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_duplicate_smoke.gd 2>&1 | tee /tmp/godot-t064-child-duplicate.log
grep -q 'T064_CHILD_DUPLICATE_PASSED' /tmp/godot-t064-child-duplicate.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_DUPLICATE_FAILED:' /tmp/godot-t064-child-duplicate.log; then exit 1; fi
# T-064 child visibility is a reversible, parent-scoped graph edit;
# hidden descendants are excluded from rendering and pointer hits.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_visibility_smoke.gd 2>&1 | tee /tmp/godot-t064-child-visibility.log
grep -q 'T064_CHILD_VISIBILITY_PASSED' /tmp/godot-t064-child-visibility.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CHILD_VISIBILITY_FAILED:' /tmp/godot-t064-child-visibility.log; then exit 1; fi
# Alt+click must resolve the correct nested parent through the live
# Atlas canvas, without resetting child-local history or map context.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_canvas_select_smoke.gd 2>&1 | tee /tmp/godot-t064-child-canvas.log
grep -q 'T064_CANVAS_CHILD_PASSED' /tmp/godot-t064-child-canvas.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CANVAS_CHILD_FAILED:' /tmp/godot-t064-child-canvas.log; then exit 1; fi
# Alt+drag moves a published child only on release; all cancellation,
# stale-index and nested ancestor-coordinate cases are checked here.
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_child_canvas_drag_smoke.gd 2>&1 | tee /tmp/godot-t064-child-drag.log
grep -q 'T064_CANVAS_DRAG_PASSED' /tmp/godot-t064-child-drag.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T064_CANVAS_DRAG_FAILED:' /tmp/godot-t064-child-drag.log; then exit 1; fi
