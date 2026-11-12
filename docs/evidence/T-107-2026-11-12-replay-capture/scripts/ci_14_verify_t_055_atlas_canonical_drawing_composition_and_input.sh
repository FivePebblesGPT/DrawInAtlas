set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/drawing_composition_smoke.gd 2>&1 | tee /tmp/godot-t055-composition.log
python3 tools/check_godot_model_log.py /tmp/godot-t055-composition.log --marker T055_COMPOSITION_PASSED
