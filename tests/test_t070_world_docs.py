"""Contract guard for T-070 world/detail/navigation documentation.

Tests check current evidence separately from historical proposal text. They are
not substitutes for T-009 or T-017 owner acceptance or real UX testing.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
PAGES = (
    "MAPS_AND_GRIDS.md",
    "AUTHORED_LOCAL_DETAIL.md",
    "SEMANTIC_ZOOM.md",
    "ZOOM_AND_ARTWORK_LOD.md",
    "LINKED_MAPS.md",
    "GRID_SNAPPING.md",
    "SEARCH_AND_WORLD_DISCOVERY.md",
)
AUTHORITY = "[[DECISIONS_DRAWING_ATLAS_2026-11-01]]"


class WorldNavigationDocsTests(unittest.TestCase):
    """Guard the installed architecture and unresolved product decisions."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.pages = {name: (DOCS / name).read_text(encoding="utf-8") for name in PAGES}

    def test_all_pages_use_decision_authority_and_current_first(self) -> None:
        for name, content in self.pages.items():
            with self.subTest(page=name):
                self.assertIn(AUTHORITY, content)
                self.assertIn("T-070 (2026-11-02)", content)
                self.assertLess(content.index("T-070 (2026-11-02)"), content.index("Historical") if "Historical" in content else len(content))
                self.assertIn("DrawingDocument", content)
                self.assertIn("(map_id, floor_id, detail_id)", content)
                self.assertRegex(content, r"(?i)(historical|legacy)")

    def test_links_resolve_locally(self) -> None:
        for name, content in self.pages.items():
            for destination in re.findall(r"\]\(([^)]+)\)", content):
                if destination.startswith(("https://", "http://", "mailto:")):
                    continue
                relative = destination.split("#", 1)[0]
                if relative:
                    with self.subTest(page=name, link=destination):
                        self.assertTrue((DOCS / name).parent.joinpath(relative).is_file())
            for wikilink in re.findall(r"\[\[([^\]]+)\]\]", content):
                target = wikilink.split("|", 1)[0].split("#", 1)[0]
                if not target or target in {"Index"}:
                    continue
                if re.fullmatch(r"(?:T-\d{3}|E-\d{3}|E-TOOLS|E-SAVE)", target):
                    folder = "Tickets" if target.startswith("T-") else "Epics"
                    self.assertTrue((DOCS / folder / f"{target}.md").is_file(), (name, target))
                else:
                    self.assertTrue((DOCS / f"{target}.md").is_file(), (name, target))

    def test_option_b_and_signed_density_consistent(self) -> None:
        for name, content in self.pages.items():
            text = content.split("### Historical", 1)[0].lower()
            with self.subTest(page=name):
                self.assertIn("1024", text)
                self.assertRegex(text, r"densit(?:y|ies)")
                self.assertIn("signed", text)
                self.assertIn("floor", text)
                if name in ("MAPS_AND_GRIDS.md", "AUTHORED_LOCAL_DETAIL.md", "LINKED_MAPS.md"):
                    self.assertRegex(text, r"(?:per-hex|no hex receives its own|no new per-cell)")
        source = (ROOT / "scripts/campaign/world_space.gd").read_text()
        self.assertIn("const TICKS_PER_UNIT: int = 1024", source)
        self.assertIn("func world_to_pixel", source)
        registry = (ROOT / "scripts/campaign/drawing_registry.gd").read_text()
        self.assertIn("func ensure_detail", registry)
        self.assertIn("func document_at", registry)

    def test_blank_detail_and_overlays_are_not_conflated(self) -> None:
        for name, content in self.pages.items():
            text = content.split("### Historical", 1)[0].lower()
            with self.subTest(page=name):
                self.assertIn("d1", text)
                self.assertIn("d0", text)
                self.assertIn("grid", text)
                self.assertIn("entrance", text)
                self.assertRegex(text, r"(?s)(no d0 underlay|no d0 artwork|no d0|without d0)")

    def test_camera_lod_preview_and_navigation_have_distinct_owners(self) -> None:
        for name in ("SEMANTIC_ZOOM.md", "ZOOM_AND_ARTWORK_LOD.md", "LINKED_MAPS.md"):
            text = self.pages[name].split("### Historical", 1)[0].lower()
            with self.subTest(page=name):
                self.assertIn("camera", text)
                self.assertIn("preview", text)
                self.assertIn("entrance", text)
                self.assertIn("d-level", text)
        navigator = (ROOT / "scripts/navigation/map_navigator.gd").read_text()
        self.assertIn("const MAX_ZOOM: float = 24.0", navigator)
        lod = (ROOT / "scripts/navigation/artwork_lod.gd").read_text()
        self.assertIn("const ENTER_COVERAGE: float = 0.65", lod)
        self.assertIn("const EXIT_COVERAGE: float = 0.45", lod)

    def test_snapping_and_masks_do_not_define_map_ownership(self) -> None:
        snap = self.pages["GRID_SNAPPING.md"].split("### Historical", 1)[0]
        for phrase in ("addons/drawing/snap.gd", "AtlasWorldSpace.snap_ticks", "edit mask", "floor division"):
            self.assertIn(phrase, snap)
        self.assertTrue((ROOT / "addons/drawing/snap.gd").is_file())
        self.assertTrue((ROOT / "scripts/campaign/world_space.gd").is_file())
        self.assertTrue((ROOT / "tests/snapping_smoke.gd").is_file())

    def test_search_current_and_proposed_actions_are_not_mixed(self) -> None:
        text = self.pages["SEARCH_AND_WORLD_DISCOVERY.md"]
        current = text.split("### Existing T-009 investigation", 1)[0]
        for required in ("**Search**", "**Find**", "**Focus source anchor**", "**Locate**",
                         "**Open details**", "Manual Review", "not been owner-approved",
                         "tests/search_stale_actions_smoke.gd", "[[T-017]]"):
            self.assertIn(required, current)
        self.assertIn("requires T-009 owner decision", current)
        self.assertIn("proposed", current.lower())
        ticket = (DOCS / "Tickets/T-009.md").read_text()
        self.assertIn('status: "Manual Review"', ticket)
        self.assertIn("manual_review: true", ticket)
        self.assertIn('status: "Blocked"', (DOCS / "Tickets/T-017.md").read_text())

    def test_current_storage_is_not_mislabeled_as_scn_only(self) -> None:
        for name in ("MAPS_AND_GRIDS.md", "AUTHORED_LOCAL_DETAIL.md", "LINKED_MAPS.md"):
            current = self.pages[name].split("### Historical", 1)[0]
            with self.subTest(page=name):
                self.assertIn("Campaign.atlas.json", current) if name != "AUTHORED_LOCAL_DETAIL.md" else self.assertIn("multi-file", current)
                self.assertIn(".scn", current)
                self.assertRegex(current.lower(), r"(historical|legacy)")


if __name__ == "__main__":
    unittest.main()
