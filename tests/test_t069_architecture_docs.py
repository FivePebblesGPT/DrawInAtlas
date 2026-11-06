"""T-069 documentation contract tests for the canonical Drawing/Atlas split.

These checks validate source links, evidence boundaries, and vocabulary. They do
not mistake documentation checks for UX approval or runtime verification.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
PAGES = (
    "ARCHITECTURE.md",
    "PRODUCT_DESIGN.md",
    "DATA_MODEL.md",
    "LAYER_HIERARCHY.md",
    "INK_REPRESENTATION_DECISION.md",
    "TERRAIN_LAYER_DECISION.md",
    "LEGACY_PLACEMENT_MIGRATION.md",
)
AUTHORITY = "DECISIONS_DRAWING_ATLAS_2026-11-01"


class ArchitectureDocsTests(unittest.TestCase):
    """Guard the approved vocabulary against obsolete prototype claims."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.pages = {name: (DOCS / name).read_text(encoding="utf-8") for name in PAGES}

    def test_all_scoped_pages_cite_the_decision_and_limit_claims(self) -> None:
        for name, content in self.pages.items():
            with self.subTest(page=name):
                self.assertIn(f"[[{AUTHORITY}]]", content)
                self.assertIn("2026-11-02", content)
                self.assertRegex(content, r"(?i)implement|current|now")
                self.assertRegex(content, r"(?i)pending|historical|propos|not yet")
        self.assertTrue((DOCS / f"{AUTHORITY}.md").is_file())

    def test_every_changed_markdown_link_resolves(self) -> None:
        for name, content in self.pages.items():
            for dest in re.findall(r"\]\(([^)]+)\)", content):
                if dest.startswith(("https://", "http://", "mailto:")):
                    continue
                path = dest.split("#", 1)[0]
                if not path:
                    continue
                with self.subTest(page=name, link=dest):
                    self.assertTrue((DOCS / name).parent.joinpath(path).is_file())

    def test_real_owners_and_source_paths_exist(self) -> None:
        for rel in (
            "drawing/project.godot", "addons/drawing/document.gd",
            "addons/drawing/layer_node.gd", "scripts/campaign/drawing_registry.gd",
            "scripts/campaign/world_space.gd", "scripts/objects/object_library.gd",
            "scripts/objects/object_instance.gd", "scripts/persistence/campaign_bundle.gd",
        ):
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file())
        architecture = self.pages["ARCHITECTURE.md"]
        for owner in ("addons/drawing/", "drawing/project.godot", "drawing_registry.gd",
                      "campaign_bundle.gd", "Object Asset", "Object Instance"):
            self.assertIn(owner, architecture)

    def test_option_b_not_per_hex_or_per_floor_drawing_types(self) -> None:
        for name in ("ARCHITECTURE.md", "PRODUCT_DESIGN.md", "DATA_MODEL.md", "LAYER_HIERARCHY.md"):
            text = self.pages[name]
            with self.subTest(page=name):
                self.assertIn("DrawingDocument", text)
                self.assertIn("floor", text.lower())
                self.assertIn("detail", text.lower())
                self.assertIn("Object Asset", text)
                self.assertRegex(text, r"(?i)no per-hex|not a per-hex|never owns a separate drawing")
        self.assertIn("signed", self.pages["DATA_MODEL.md"])
        self.assertIn("density", self.pages["PRODUCT_DESIGN.md"])

    def test_save_migration_and_unimplemented_boundaries_are_explicit(self) -> None:
        model = self.pages["DATA_MODEL.md"]
        self.assertIn("Campaign.atlas.json", model)
        self.assertIn(".zst", model)
        self.assertIn("historical", model.lower())
        self.assertIn("no historical user-save migration", model.lower())
        self.assertIn("T-067", model)
        self.assertIn("T-068", model)
        self.assertIn("not an active user migration", self.pages["LEGACY_PLACEMENT_MIGRATION.md"])
        self.assertIn("T-064", self.pages["LAYER_HIERARCHY.md"])
        self.assertIn("T-065", self.pages["LAYER_HIERARCHY.md"])
        product = self.pages["PRODUCT_DESIGN.md"]
        for gate in ("T-009", "T-039", "T-043", "T-056", "T-059"):
            self.assertIn(gate, product)
        self.assertIn("T-049", self.pages["INK_REPRESENTATION_DECISION.md"])
        self.assertIn("T-050", self.pages["TERRAIN_LAYER_DECISION.md"])

    def test_historical_designs_are_not_presented_as_current_apis(self) -> None:
        architecture = self.pages["ARCHITECTURE.md"]
        self.assertLess(architecture.index("What actually runs"), architecture.index("Historical conceptual"))
        self.assertIn("illustrative pseudotypes", architecture)
        self.assertIn("prototype", self.pages["INK_REPRESENTATION_DECISION.md"].lower())
        self.assertIn("historical conceptual", self.pages["DATA_MODEL.md"].lower())
        self.assertIn("historical", self.pages["LEGACY_PLACEMENT_MIGRATION.md"].lower())
        self.assertIn("historical", self.pages["TERRAIN_LAYER_DECISION.md"].lower())


if __name__ == "__main__":
    unittest.main()
