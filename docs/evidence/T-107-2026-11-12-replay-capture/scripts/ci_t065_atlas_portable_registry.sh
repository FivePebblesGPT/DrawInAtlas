set -euo pipefail
timeout --signal=TERM --kill-after=5s 120s godot --headless --path . --script res://tests/object_portable_registry_smoke.gd 2>&1 | tee /tmp/godot-t065-portable-registry.log
grep -q 'T065_PORTABLE_PASSED' /tmp/godot-t065-portable-registry.log
if grep -E 'SCRIPT ERROR:|^ERROR:|T065_PORTABLE_FAILED:' /tmp/godot-t065-portable-registry.log; then exit 1; fi
