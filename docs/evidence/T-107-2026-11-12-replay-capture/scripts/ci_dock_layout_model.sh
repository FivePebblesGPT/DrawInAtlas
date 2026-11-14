set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://drawing/tests/dock_layout_smoke.gd 2>&1 | tee /tmp/godot-dock-layout.log
python3 tools/check_godot_model_log.py /tmp/godot-dock-layout.log --marker DRAWING_DOCK_MODEL_PASSED
