"""T-071 storage-document truthfulness checks against implemented source.

These checks guard published versus historical versus proposed behavior. Real
save/load/fault-injection behavior is verified by campaign_bundle_smoke.gd.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SCOPED = (
    "DICTIONARY_CONVERSION_AUDIT.md",
    "RASTER_CHUNK_IMPORT.md",
    "DRAWING_STORAGE_CONTRACT.md",
)
DECISIONS = "[[DECISIONS_DRAWING_ATLAS_2026-11-01]]"


class StorageDocsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pages = {name: (DOCS / name).read_text(encoding="utf-8") for name in SCOPED}

    def test_approved_authority_and_current_first(self) -> None:
        for name, content in self.pages.items():
            with self.subTest(page=name):
                self.assertIn(DECISIONS, content)
                self.assertIn("T-071", content)
                self.assertIn("T-066", content)
                self.assertLess(content.index("T-071"), content.index("Historical") if "Historical" in content else len(content))
                self.assertIn("Drawings/", content)
                self.assertIn("Objects/", content)
                self.assertIn("Fonts/", content)

    def test_legacy_native_and_import_baselines_are_marked(self) -> None:
        audit = self.pages["DICTIONARY_CONVERSION_AUDIT.md"]
        legacy = self.pages["RASTER_CHUNK_IMPORT.md"]
        for content in (audit, legacy):
            self.assertIn("## Historical", content)
            self.assertIn("AtlasRasterChunk", content)
            self.assertIn("256", content)
            self.assertIn("WebP", content)
            self.assertIn(".scn", content)
            self.assertIn(".zst", content.split("## Historical", 1)[0])
        self.assertIn("AtlasCampaignBundle", audit)
        self.assertIn("DrawingBundleManifest", audit)
        self.assertIn("DrawingRasterImport.import_image", legacy)
        self.assertIn("revision-checked", legacy)
        self.assertIn("128", legacy.split("## Historical", 1)[0])

    def test_current_physical_schema_and_code_owners(self) -> None:
        contract = self.pages["DRAWING_STORAGE_CONTRACT.md"]
        bundle = (ROOT / "scripts/persistence/campaign_bundle.gd").read_text()
        manifest = (ROOT / "addons/drawing/bundle_manifest.gd").read_text()
        chunk = (ROOT / "addons/drawing/chunk_store.gd").read_text()
        for needle in ("atlas-campaign-root-v1", "atlas-campaign-generation-v1",
                       "drawing-sparse-manifest-v1", "Campaign.atlas.json",
                       "Campaign.atlas.bak.json", "generation.json", ".zst"):
            self.assertIn(needle, contract)
        self.assertIn('const ROOT_SCHEMA: String = "atlas-campaign-root-v1"', bundle)
        self.assertIn('const GENERATION_SCHEMA: String = "atlas-campaign-generation-v1"', bundle)
        self.assertIn('const SCHEMA: String = "drawing-sparse-manifest-v1"', manifest)
        self.assertIn('"Drawings/chunks/%s/%s.zst"', chunk)
        for source in ("scripts/campaign/drawing_registry.gd", "scripts/persistence/campaign_bundle.gd",
                       "addons/drawing/raster_import.gd", "addons/drawing/bundle_manifest.gd",
                       "addons/drawing/chunk_store.gd"):
            self.assertTrue((ROOT / source).is_file(), source)

    def test_import_edit_and_storage_strides_are_distinct(self) -> None:
        source = (ROOT / "addons/drawing/raster_import.gd").read_text()
        self.assertIn("region_edge: int = 128", source)
        self.assertIn("for y: int in range(0, height, region_edge)", source)
        for name in ("RASTER_CHUNK_IMPORT.md", "DRAWING_STORAGE_CONTRACT.md"):
            text = self.pages[name]
            with self.subTest(page=name):
                self.assertIn("128", text)
                self.assertIn("tile_stride", text)
                self.assertIn("GPU", text)
                self.assertIn("512", text)
                self.assertRegex(text, r"(?i)(not deployed|not a.*deployed|neither is deployed|still uses individual)")
        self.assertIn("256/512/1024/2048", self.pages["DICTIONARY_CONVERSION_AUDIT.md"])

    def test_signed_address_and_byte_integrity(self) -> None:
        contract = self.pages["DRAWING_STORAGE_CONTRACT.md"]
        manifest = (ROOT / "addons/drawing/bundle_manifest.gd").read_text()
        for needle in ("RGBA8", "hidden RGB", "SHA-256", "9007199254740993",
                       "-9007199254740993", "decimal", "lazily"):
            self.assertIn(needle.lower(), contract.lower())
        self.assertIn('chunk["coord"] = [str(coords[0]), str(coords[1])]', manifest)
        self.assertIn("DrawingRasterTile.digest_rgba8", (ROOT / "addons/drawing/chunk_store.gd").read_text())

    def test_failure_matrix_has_reproducible_oracle(self) -> None:
        contract = self.pages["DRAWING_STORAGE_CONTRACT.md"]
        fixture = (ROOT / "tests/campaign_bundle_smoke.gd").read_text()
        self.assertIn("## Reproducible portability and failure acceptance — T-071", contract)
        for heading in ("Whole-directory relocation", "Partial copy", "Missing or damaged referenced chunk",
                        "Interrupted new generation", "Failed write or root-pointer rename",
                        "Concurrent editors", "Large signed coordinates", "Unpainted authored detail"):
            self.assertIn(heading, contract)
        for method in ("_portable_assets_and_fonts", "_corruption_and_precision", "_failures_and_sparse"):
            self.assertIn(method, contract)
            self.assertIn(f"func {method}", fixture)
        for reference in ("reject_root", "reject_generation", "STALE_ROOT", "recovered",
                          "Fonts/lato-regular-v1.ttf", "9007199254740993"):
            self.assertIn(reference, fixture + (ROOT / "scripts/persistence/campaign_bundle.gd").read_text())
        self.assertIn("godot --headless --path . --script res://tests/campaign_bundle_smoke.gd", contract)
        self.assertIn("res://tests/campaign_bundle_editor_smoke.gd", contract)

    def test_unsupported_safety_claims_are_excluded(self) -> None:
        contract = self.pages["DRAWING_STORAGE_CONTRACT.md"].lower()
        for caution in ("not a universal guarantee", "power-loss", "partial copy", "deployed shared pack",
                        "no migration", "automatic orphan", "relative"):
            self.assertIn(caution.lower(), contract)
        self.assertIn("T-056/T-059", self.pages["DRAWING_STORAGE_CONTRACT.md"])
        self.assertIn('status: "In Progress"', (DOCS / "Tickets/T-068.md").read_text())

    def test_all_markdown_links_and_wiki_references_resolve(self) -> None:
        for name, content in self.pages.items():
            for url in re.findall(r"\]\(([^)]+)\)", content):
                if url.startswith(("https://", "http://", "mailto:")):
                    continue
                relative = url.split("#", 1)[0]
                if relative:
                    with self.subTest(page=name, url=url):
                        self.assertTrue((DOCS / name).parent.joinpath(relative).is_file())
            for target in re.findall(r"\[\[([^\]]+)\]\]", content):
                text = target.split("|", 1)[0].split("#", 1)[0]
                if text.startswith("T-"):
                    path = DOCS / "Tickets" / f"{text}.md"
                elif text.startswith("E-"):
                    path = DOCS / "Epics" / f"{text}.md"
                else:
                    path = DOCS / f"{text}.md"
                with self.subTest(page=name, wikilink=target):
                    self.assertTrue(path.is_file())


if __name__ == "__main__":
    unittest.main()
