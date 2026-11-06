"""T-072: authoritative current tool workflow vs retained Atlas-era proposals.

These checks intentionally rely on checked-in source and ticket frontmatter rather
than historical smoke-test totals. Runtime behavior is covered by Godot suites.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
PAGES = {
    "BRUSH_WORKFLOW.md": ("Brush", "paint_path", "T-020"),
    "ERASER_WORKFLOW.md": ("Eraser", "paint_path", "T-021"),
    "BUCKET_WORKFLOW.md": ("Bucket", "flood_fill", "T-023"),
    "LINE_WORKFLOW.md": ("Line", "paint_path", "T-024"),
    "POLYGON_WORKFLOW.md": ("Polygon", "paint_polygon", "T-025"),
    "WALL_PATHS_WORKFLOW.md": ("Wall Path", "AtlasEditablePath", "T-026"),
    "MOVE_WORKFLOW.md": ("Move", "move_selection", "T-022"),
    "SELECTION_AND_EDIT_MASKS.md": ("Select", "DrawingSelection", "T-019"),
    "TEXT_WORKFLOW.md": ("Text", "commit_text", "T-027"),
}
CANONICAL_UI = ("Brush", "Eraser", "Select", "Move", "Text", "Pan")
PENDING = ("BUCKET_WORKFLOW.md", "LINE_WORKFLOW.md", "POLYGON_WORKFLOW.md", "WALL_PATHS_WORKFLOW.md")


def source(filename: str) -> str:
    return (ROOT / filename).read_text(encoding="utf-8")


class ToolWorkflowDocsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pages = {name: source(f"docs/{name}") for name in PAGES}

    def test_all_nine_authoritative_current_first_and_archived(self) -> None:
        for name, content in self.pages.items():
            with self.subTest(page=name):
                self.assertIn("current Drawing/Atlas workflow (T-072)", content.splitlines()[0])
                self.assertIn("47 Essential / 34 Later / 18 Skip", content)
                self.assertIn("DRAWING_FEATURE_INVENTORY.md", content)
                self.assertIn("DECISIONS_DRAWING_ATLAS_2026-11-01.md", content)
                self.assertIn("## Historical Atlas-era workflow", content)
                self.assertLess(content.index("## Current "), content.index("## Historical"))
                self.assertIn("legacy", content.lower())
                self.assertIn("**Witnesses:**", content)
                self.assertIn("tests/", content)
                self.assertIn("T-068", content)

    def test_canonical_tool_palette_matches_documented_availability(self) -> None:
        workspace = source("addons/drawing/workspace.gd")
        self.assertIn('for name: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]', workspace)
        for name, content in self.pages.items():
            before = content.split("## Historical", 1)[0]
            with self.subTest(page=name):
                self.assertIn("**Brush, Eraser, Select, Move, Text, Pan**", before)
        for name in PENDING:
            before = self.pages[name].split("## Historical", 1)[0]
            self.assertRegex(before, r"(?i)(NOT shipped|Not shipped)")
            self.assertIn("Ready", before)
        self.assertNotIn('"Bucket"', workspace.split('for name: String in [', 1)[1].split(']:', 1)[0])

    def test_pending_tool_tickets_are_not_marked_completed(self) -> None:
        for name in PENDING:
            ticket = PAGES[name][2]
            self.assertIn('status: "Ready"', source(f"docs/Tickets/{ticket}.md"))
        self.assertIn('status: "Ready"', source("docs/Tickets/T-027.md"))
        self.assertIn('status: "In Progress"', source("docs/Tickets/T-068.md"))
        self.assertIn('status: "Done"', source("docs/Tickets/T-058.md"))
        for name in PENDING:
            self.assertIn("legacy", self.pages[name].lower())

    def test_edit_session_api_matches_workflow_examples(self) -> None:
        edit = source("addons/drawing/edit_session.gd")
        doc = source("addons/drawing/document.gd")
        for method in ("paint_path", "paint_polygon", "flood_fill", "apply_region", "commit", "cancel"):
            self.assertIn(f"func {method}(", edit)
        self.assertIn("func begin_edit(", doc)
        self.assertIn("_covered", edit)
        self.assertIn("if once and _covered.has(key)", edit)
        self.assertIn("if selection != null and not selection.allows(", edit)
        self.assertIn("apply_region(Rect2i, PackedByteArray)", self.pages["BRUSH_WORKFLOW.md"])
        self.assertIn("hidden RGB", self.pages["ERASER_WORKFLOW.md"])
        self.assertIn("once", self.pages["BRUSH_WORKFLOW.md"])
        self.assertIn("four-connected", self.pages["BUCKET_WORKFLOW.md"])
        self.assertIn("filled", self.pages["POLYGON_WORKFLOW.md"])

    def test_local_global_history_and_selection_opt_in(self) -> None:
        doc = source("addons/drawing/document.gd")
        workspace = source("addons/drawing/workspace.gd")
        atlas = source("scripts/editing/history.gd")
        self.assertIn("record_selection_history: bool = false", doc)
        self.assertIn("record_selection_history: bool = false", workspace)
        self.assertIn("func set_external_history(", doc)
        self.assertIn("func commit_drawing(", atlas)
        for content in self.pages.values():
            before = content.split("## Historical", 1)[0]
            for term in ("set_external_history(true)", "commit_drawing()", "OFF by default", "preserves zoom"):
                self.assertIn(term, before)

    def test_text_creation_and_rasterization_contract(self) -> None:
        text = self.pages["TEXT_WORKFLOW.md"].split("## Historical", 1)[0]
        doc = source("addons/drawing/document.gd")
        for method in ("commit_text", "rasterize_text"):
            self.assertIn(f"func {method}(", doc)
            self.assertIn(f"{method}()", text)
        for word in ("first successful", "exactly one", "Cancel", "same", "undoable", "Lato OFL",
                     "license", "unsupported glyphs", "missing/corrupt", "T-058", "T-027"):
            self.assertIn(word.lower(), text.lower())
        self.assertTrue((ROOT / "addons/drawing/fonts/OFL-1.1.txt").is_file())
        self.assertTrue((ROOT / "drawing/tests/packaged_fonts_smoke.gd").is_file())

    def test_selection_and_move_do_not_claim_legacy_affine_or_lasso(self) -> None:
        selection = self.pages["SELECTION_AND_EDIT_MASKS.md"].split("## Historical", 1)[0]
        move = self.pages["MOVE_WORKFLOW.md"].split("## Historical", 1)[0]
        self.assertIn("DrawingClipboard", move)
        self.assertIn("DrawingSelection", selection)
        self.assertIn("OFF by default", selection)
        self.assertIn("rectangular", selection)
        self.assertIn("whole `AtlasRasterLayer` affine-transform", move)
        self.assertIn("does **not** claim Paint.NET lasso", selection)
        self.assertIn("func move_selection(", source("addons/drawing/clipboard.gd"))

    def test_witness_files_referred_by_docs_exist(self) -> None:
        for name, content in self.pages.items():
            before = content.split("## Historical", 1)[0]
            paths = re.findall(r"`((?:drawing/)?tests/[\w./-]+\.gd)`", before)
            self.assertGreaterEqual(len(paths), 2, name)
            for test_path in paths:
                with self.subTest(page=name, witness=test_path):
                    self.assertTrue((ROOT / test_path).is_file(), test_path)

    def test_resolved_local_markdown_and_wikilinks(self) -> None:
        for name, content in self.pages.items():
            for target in re.findall(r"\]\(([^)]+)\)", content):
                if target.startswith(("https://", "http://", "mailto:")):
                    continue
                relative = target.split("#", 1)[0]
                if relative:
                    with self.subTest(page=name, link=target):
                        self.assertTrue((DOCS / relative).is_file(), target)
            for target in re.findall(r"\[\[([^\]]+)\]\]", content):
                ref = target.split("|", 1)[0].split("#", 1)[0]
                if ref.startswith("T-"):
                    path = DOCS / "Tickets" / f"{ref}.md"
                elif ref.startswith("E-"):
                    path = DOCS / "Epics" / f"{ref}.md"
                else:
                    path = DOCS / f"{ref}.md"
                with self.subTest(page=name, wiki=ref):
                    self.assertTrue(path.is_file(), path)

    def test_no_shipped_native_claim_and_historical_single_file_qualified(self) -> None:
        for name, content in self.pages.items():
            before = content.split("## Historical", 1)[0]
            for claim in ("no native backend is selected", "T-068", "historical", "T-066", "Drawings/"):
                if claim == "historical":
                    claim = "older Atlas"
                self.assertIn(claim.lower(), before.lower(), name)
            self.assertIn("## Historical", content)


if __name__ == "__main__":
    unittest.main()
