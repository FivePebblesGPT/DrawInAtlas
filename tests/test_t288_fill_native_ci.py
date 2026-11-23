"""T-288: the optional fill-to-frame runner must build real native tile authority."""

from __future__ import annotations

import re
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-native-t068-fill.yml"
LOCK = ROOT / "toolchain.lock.toml"
MAKEFILE = ROOT / "Makefile"


def validate_fill_workflow(text: str) -> None:
    """Reject a runner that would profile an unregistered or wrong native engine."""
    lock = tomllib.loads(LOCK.read_text(encoding="utf-8"))
    godot_pin = re.sub(r"^(\d+\.\d+)\.(beta\d+)$", r"\1.0-\2", lock["godot"]["version"])
    # The pinned 4.8.beta4 lock maps to the setup-godot 4.8.0-beta4 version.
    if len(re.findall(r"(?m)^\s+version: " + re.escape(godot_pin) + r"\s*$", text)) != 1:
        raise ValueError("fill runner must use the toolchain's pinned Godot version")
    if not re.search(r"(?m)^\s+toolchain: " + re.escape(lock["rust"]["version"]) + r"\s*$", text):
        raise ValueError("fill runner must install the pinned Rust compiler")
    steps = re.split(r"(?m)^      - (?=name:|uses:)", text)
    build = [i for i, step in enumerate(steps) if "make build TOOLCHAIN=system" in step]
    profiling = [i for i, step in enumerate(steps) if "tools/benchmarks/t068_fill_process_profile.py" in step]
    if len(build) != 1 or len(profiling) != 1 or build[0] >= profiling[0]:
        raise ValueError("fill runner must build before sampling the native framebuffer")
    if "set -euo pipefail" not in steps[build[0]]:
        raise ValueError("native build must fail closed")
    if not re.search(r"(?m)^\s+run: \|\s*$", steps[build[0]]):
        raise ValueError("native build must be an executable CI step")
    if "NATIVE_EXTENSION_READY" not in (ROOT / "addons/drawing/native_extension_probe.gd").read_text():
        raise ValueError("native startup probe was removed")
    make = MAKEFILE.read_text(encoding="utf-8")
    for required in ("build: import-drawing import-atlas", "stage-drawing: native",
                     "import-atlas: native", "tools/prepare_native_project.py",
                     "res://tests/native_extension_ready.gd", "bash tools/build_native_brush.sh"):
        if required not in make:
            raise ValueError(f"native build contract changed: {required}")


class FillNativeCiTests(unittest.TestCase):
    def test_real_on_demand_workflow_builds_registered_native_engine(self) -> None:
        validate_fill_workflow(WORKFLOW.read_text(encoding="utf-8"))

    def test_missing_or_reordered_native_preflight_is_rejected(self) -> None:
        source = WORKFLOW.read_text(encoding="utf-8")
        build_step = re.search(r"(?ms)^      - name: Build mandatory native.*?(?=^      - name:|\Z)", source)
        self.assertIsNotNone(build_step)
        assert build_step is not None
        for mutation in (
            source.replace("make build TOOLCHAIN=system", "true"),
            source.replace("make build TOOLCHAIN=system", "make stage-drawing TOOLCHAIN=system"),
            source.replace("set -euo pipefail", "set -e", 1),
            source.replace("version: 4.8.0-beta4", "version: 4.8.0-beta3"),
            source.replace("toolchain: 1.99.1", "toolchain: 1.100.0"),
            source.replace(build_step.group(), "").replace("      - name: Upload measured evidence", build_step.group() + "      - name: Upload measured evidence"),
        ):
            with self.subTest(mutation=mutation[:80]), self.assertRaises(ValueError):
                validate_fill_workflow(mutation)


if __name__ == "__main__":
    unittest.main()
