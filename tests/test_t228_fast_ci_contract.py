"""The required Linux release job must stage and export to separate trees.

This is a source-level workflow contract; final CI acceptance needs a hosted run.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/godot-check.yml"


def release_step(source: str) -> str:
    """Isolate the required fail-late release step, not optional workflows."""
    match = re.search(
        r"(?ms)^      - name: Verify T-053 standalone Linux release package\n"
        r"(.*?)(?=^      - name:|\Z)",
        source,
    )
    if match is None:
        raise AssertionError("Required T-053 Linux release step is missing")
    return match.group(1)


def assert_isolated_release_step(step: str) -> None:
    """Reject exports mixed with the source project or inconsistent consumers."""
    required = (
        'python3 tools/build_drawing_app.py --output "$release_root/project"',
        'mkdir -p "$release_root/dist"',
        'godot --headless --editor --path "$release_root/project" --import --quit',
        '--export-release Linux "$release_root/dist/Drawing.x86_64"',
        'test -s "$release_root/dist/Drawing.x86_64"',
        'test -s "$release_root/dist/Drawing.pck"',
        '--stage "$release_root/project" --linux "$release_root/dist"',
        '--path "$release_root/dist" --main-pack "$release_root/dist/Drawing.pck"',
        '--script "$release_root/project/tests/packaged_fonts_smoke.gd"',
        '--launch-linux --output /tmp/t068-standalone-linux-release.json',
    )
    for expression in required:
        if expression not in step:
            raise AssertionError(f"Release step missing isolated contract: {expression}")
    if step.count('--stage "$release_root/project" --linux "$release_root/dist"') != 2:
        raise AssertionError("Packager and final verifier must both inspect the isolated export")
    for unexpected in (
        '"$release_root/Drawing.x86_64"',
        '"$release_root/Drawing.pck"',
        '--linux "$release_root"',
    ):
        if unexpected in step:
            raise AssertionError(f"Export still points to stage parent: {unexpected}")


class RequiredFastCiLayoutTests(unittest.TestCase):
    def test_required_release_exports_to_clean_sibling_directory(self) -> None:
        assert_isolated_release_step(release_step(WORKFLOW.read_text(encoding="utf-8")))

    def test_old_mixed_project_export_is_rejected(self) -> None:
        step = release_step(WORKFLOW.read_text(encoding="utf-8"))
        regression = step.replace("$release_root/dist", "$release_root")
        with self.assertRaisesRegex(AssertionError, "isolated contract|stage parent"):
            assert_isolated_release_step(regression)

    def test_mismatched_package_target_is_rejected(self) -> None:
        step = release_step(WORKFLOW.read_text(encoding="utf-8"))
        regression = step.replace(
            '--stage "$release_root/project" --linux "$release_root/dist"',
            '--stage "$release_root/project" --linux "$release_root"',
            1,
        )
        with self.assertRaisesRegex(AssertionError, "Packager and final verifier"):
            assert_isolated_release_step(regression)


if __name__ == "__main__":
    unittest.main()
