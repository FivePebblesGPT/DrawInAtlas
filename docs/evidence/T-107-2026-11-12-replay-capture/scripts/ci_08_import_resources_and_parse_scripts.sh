set -euo pipefail
godot --headless --path . --editor --import --quit 2>&1 | tee /tmp/godot-import.log
if grep -E 'SCRIPT ERROR:|^ERROR:|Parse Error:|Compile Error:' /tmp/godot-import.log; then exit 1; fi
