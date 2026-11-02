"""Executable T-051 package-boundary and conceptual registry checks.

The consumer tests real shared signed-tile code; it does not simulate a full
DrawingDocument or assert that T-052/T-066 are already implemented.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parents[1]
SPEC = spec_from_file_location(
    "build_drawing_contract_consumer", ROOT / "tools" / "build_drawing_contract_consumer.py"
)
assert SPEC is not None and SPEC.loader is not None
BUILDER = module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class RegistryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = json.loads(
            (ROOT / "docs" / "examples" / "drawing_document_registry.json").read_text()
        )

    def test_two_floors_with_two_details_and_no_duplicate_document_id(self) -> None:
        floors = self.registry["floors"]
        self.assertEqual(len(floors), 2)
        self.assertEqual([len(floor["details"]) for floor in floors], [2, 2])
        ids = [detail["document_id"] for floor in floors for detail in floor["details"]]
        self.assertEqual(len(set(ids)), 4)
        self.assertEqual({document["id"] for document in self.registry["documents"]}, set(ids))

    def test_blank_detail_is_sparse_with_distinct_density(self) -> None:
        ground = self.registry["floors"][0]["details"]
        self.assertEqual(ground[0]["density"], [1, 1])
        self.assertEqual(ground[1]["density"], [2, 1])
        blank = next(document for document in self.registry["documents"]
                     if document["id"] == ground[1]["document_id"])
        self.assertFalse(ground[1]["authored"])
        self.assertEqual(blank["chunks"], [])
        self.assertEqual(blank["layer_ids"], [])
        self.assertTrue(all(num > 0 and den > 0
                            for floor in self.registry["floors"]
                            for detail in floor["details"]
                            for num, den in [detail["density"]]))

    def test_nonblank_signed_chunk_coordinates_and_unique_layers(self) -> None:
        layer_ids = [layer for document in self.registry["documents"]
                     for layer in document["layer_ids"]]
        self.assertEqual(len(layer_ids), len(set(layer_ids)))
        for document in self.registry["documents"]:
            for chunk in document["chunks"]:
                x, y = chunk.split(",")
                self.assertEqual(chunk, f"{int(x)},{int(y)}")


class PackageIsolationTests(unittest.TestCase):
    def test_source_is_generic_and_contains_no_atlas_reference(self) -> None:
        source = (ROOT / "drawing" / "package" / "signed_tiles.gd").read_text()
        self.assertNotIn("Atlas", source)
        self.assertNotIn("res://scripts/", source)
        self.assertNotIn("class_name", source)
        self.assertIn("positive_divisor", source)

    def test_stage_requires_external_empty_output(self) -> None:
        with self.assertRaises(ValueError):
            BUILDER.stage(ROOT / "build" / "consumer")
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "consumer"
            output.mkdir()
            (output / "dont-overwrite.txt").write_text("keep")
            with self.assertRaises(ValueError):
                BUILDER.stage(output)
            self.assertEqual((output / "dont-overwrite.txt").read_text(), "keep")

    def test_only_allowlisted_sources_are_staged_byte_identically(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            project = BUILDER.stage(Path(temp) / "consumer")
            relpaths = {str(p.relative_to(project)) for p in project.rglob("*") if p.is_file()}
            self.assertEqual(relpaths, {
                "project.godot", "main.tscn", "main.gd", "addons/drawing/signed_tiles.gd"
            })
            self.assertEqual(
                (project / "addons/drawing/signed_tiles.gd").read_bytes(),
                (ROOT / "drawing/package/signed_tiles.gd").read_bytes()
            )
            godot_project = (project / "project.godot").read_text()
            self.assertNotIn("[autoload]", godot_project)
            self.assertNotIn("[editor_plugins]", godot_project)
            self.assertNotIn("Atlas", (project / "main.gd").read_text())

    def test_isolated_godot_consumer_exercises_real_package(self) -> None:
        godot = shutil.which("godot")
        if godot is None:
            self.skipTest("Godot not installed; run this test in the Godot CI job")
        with tempfile.TemporaryDirectory() as temp:
            project = BUILDER.stage(Path(temp) / "consumer")
            imported = subprocess.run(
                [godot, "--headless", "--editor", "--path", str(project), "--import", "--quit"],
                capture_output=True, text=True, timeout=75, check=False,
            )
            self.assertEqual(imported.returncode, 0, imported.stdout + imported.stderr)
            self.assertNotIn("SCRIPT ERROR", imported.stdout + imported.stderr)
            ran = subprocess.run(
                [godot, "--headless", "--path", str(project), "--quit-after", "40"],
                capture_output=True, text=True, timeout=75, check=False,
            )
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertIn("DRAWING_CONTRACT_CONSUMER_PASSED", ran.stdout)
            self.assertNotIn("SCRIPT ERROR", ran.stdout + ran.stderr)


if __name__ == "__main__":
    unittest.main()
