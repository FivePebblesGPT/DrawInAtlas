source tools/ci_fail_late.sh
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/t015_retirement_smoke.gd 2>&1 | tee /tmp/godot-t015-retirement.log
grep -q 'ATLAS_T015_RETIREMENT_PASSED' /tmp/godot-t015-retirement.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:' /tmp/godot-t015-retirement.log; then ci_fail_marker 'Forbidden error marker'; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/links_smoke.gd 2>&1 | tee /tmp/godot-t015-links.log
grep -q 'ATLAS_LINKS_PASSED' /tmp/godot-t015-links.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:' /tmp/godot-t015-links.log; then ci_fail_marker 'Forbidden error marker'; fi
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/linked_maps_ui_smoke.gd 2>&1 | tee /tmp/godot-t015-link-ui.log
grep -q 'ATLAS_LINKED_MAPS_UI_PASSED' /tmp/godot-t015-link-ui.log
if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:' /tmp/godot-t015-link-ui.log; then ci_fail_marker 'Forbidden error marker'; fi
# Active archival-boundary and modern navigation witnesses: former
# spatial placement previews are deliberately not an authoring surface.
for witness in \
    't015_archived_geometry_smoke.gd:ATLAS_T015_ARCHIVE_PASSED' \
    'overview_smoke.gd:ATLAS_OVERVIEW_PASSED' \
    'layer_hierarchy_smoke.gd:ATLAS_LAYER_HIERARCHY_PASSED' \
    'search_stale_actions_smoke.gd:ATLAS_SEARCH_STALE_PASSED' \
    'organization_ui_smoke.gd:ATLAS_ORGANIZATION_UI_PASSED' \
    'references_ui_smoke.gd:ATLAS_REFERENCES_UI_PASSED'; do
  file="${witness%%:*}"
  marker="${witness#*:}"
  log="/tmp/godot-t015-${file%.gd}.log"
  timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script "res://tests/$file" 2>&1 | tee "$log"
  grep -q "$marker" "$log"
  if grep -E 'SCRIPT ERROR:|^ERROR:|FAILED:' "$log"; then ci_fail_marker 'Forbidden error marker'; fi
done
ci_finish
