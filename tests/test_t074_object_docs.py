"""T-074: Object Asset authoring docs track the actual registry and review gates.

These tests guard source/instance identity, save/rebind/NULL contracts and the
boundary between implemented registry calls and still-planned nested/UI work.
Runtime behavior is independently covered by the Godot object tests.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
RASTER = (DOCS / "RASTER_OBJECTS_WORKFLOW.md").read_text(encoding="utf-8")
WORKFLOW = (DOCS / "OBJECT_ASSETS_WORKFLOW.md").read_text(encoding="utf-8")
LIBRARY = (ROOT / "scripts/objects/object_library.gd").read_text(encoding="utf-8")
INSTANCE = (ROOT / "scripts/objects/object_instance.gd").read_text(encoding="utf-8")
BRIDGE = (ROOT / "scripts/objects/object_editor_bridge.gd").read_text(encoding="utf-8")


class ObjectDocumentationContractTests(unittest.TestCase):
    def test_two_document_domains_and_real_source_paths(self) -> None:
        for content in (RASTER, WORKFLOW):
            with self.subTest(document=content[:40]):
                for marker in ("DrawingDocument", "Drawings/", "Objects/", "Fonts/", "T-066"):
                    self.assertIn(marker, content)
        self.assertIn('Objects/<asset-id>/vNNNNNN.drawing', WORKFLOW)
        self.assertIn("Campaign.atlas.json", WORKFLOW)
        self.assertIn("AtlasDrawingRegistry", WORKFLOW)
        self.assertIn("AtlasObjectLibrary", WORKFLOW)
        self.assertIn("no tab for each internal document", WORKFLOW)
        self.assertIn("no Atlas types", WORKFLOW)

    def test_original_raster_workflow_is_explicitly_historical(self) -> None:
        self.assertLess(RASTER.index("## Current Drawing/Atlas boundary"),
                        RASTER.index("## Historical raster/Objects prototype"))
        historical = RASTER.split("## Historical raster/Objects prototype", 1)[1]
        self.assertIn("AtlasObjectsLayer", historical)
        self.assertIn("AtlasInkLayer", historical)
        self.assertIn("WebP", historical)
        self.assertIn("not the current Drawing engine", RASTER)
        self.assertIn("T-074", RASTER)

    def test_source_and_instance_id_fields_match_code(self) -> None:
        for field in ("id", "generation", "source_id", "map_id", "floor_id",
                      "detail_id", "transform", "visible", "revision", "placeholder"):
            with self.subTest(field=field):
                self.assertRegex(INSTANCE, rf"var {field}: ")
        for phrase in ("asset ID", "instance ID", "generation token", "source_id",
                       "map/floor/detail", "affine"):
            self.assertIn(phrase, WORKFLOW)
        for api in ("create_asset", "place", "instance_info", "source_id"):
            self.assertIn(api, LIBRARY)

    def test_draft_publication_and_bound_save_as_match_apis(self) -> None:
        for signature in ("func begin_draft(", "func save_draft(", "func save_as(",
                          "func _publish_variant_and_bind(", "func _put_binding("):
            self.assertIn(signature, LIBRARY)
        for signature in ("func open_from_instance(", "func open_source(",
                          "func _origin_valid(", "func _save(", "func _save_as("):
            self.assertIn(signature, BRIDGE)
        for phrase in ("private", "only after Save", "stale", "instance-I", "instance-J",
                       "asset-A", "asset-B", "revision 2", "Save As"):
            self.assertIn(phrase, WORKFLOW)
        self.assertIn("one registry publication/history command", WORKFLOW)

    def test_variant_retention_and_deleted_variant_failure(self) -> None:
        for phrase in ("undo", "redo", "zero linked instances", "same asset-B ID",
                       "deleted", "fails closed", "no Atlas rebind"):
            self.assertIn(phrase, WORKFLOW)
        history_suite = (ROOT / "tests/object_assets_smoke.gd").read_text(encoding="utf-8")
        self.assertIn("new_timeline.redo()", history_suite)
        self.assertIn('delete_asset(String(retry.value), "remove")', history_suite)
        self.assertIn("undo retains reopenable B", history_suite)

    def test_delete_policy_contract_and_missing_source_handling(self) -> None:
        for policy in ('"cancel"', '"remove"', '"null"'):
            self.assertIn(policy, LIBRARY)
            self.assertIn(policy, WORKFLOW)
        for source_fragment in ("func delete_asset(", "next_instances.erase(instance_id)",
                                "next_instances[instance_id].placeholder = true",
                                "next_instances[instance_id].revision += 1",
                                '"status": "NULL"', '"marker_local_bounds"'):
            self.assertIn(source_fragment, LIBRARY)
        for phrase in ("Remove references/placements", "Keep visible NULL placeholders",
                       "source ID", "bounded", "same-name", "repair", "not yet implemented"):
            self.assertIn(phrase, WORKFLOW)

    def test_nested_graph_is_staged_not_claimed_as_shipped(self) -> None:
        nested = (DOCS / "Tickets/T-064.md").read_text(encoding="utf-8")
        self.assertIn('status: "Ready"', nested)
        for phrase in ("T-064", "A→A", "A→B→C→A", "transitively", "not implemented"):
            self.assertIn(phrase, WORKFLOW)
        self.assertIn("T-064", RASTER)
        self.assertNotIn("func add_child_asset(", LIBRARY)
        self.assertNotIn("func _detect_asset_cycle(", LIBRARY)

    def test_browser_ui_and_owner_gates_are_not_marked_shipped(self) -> None:
        for ticket, status in (("T-063", "Done"), ("T-064", "Ready"),
                               ("T-065", "Ready"), ("T-059", "Ready"),
                               ("T-056", "Ready")):
            with self.subTest(ticket=ticket):
                self.assertIn(f'status: "{status}"',
                              (DOCS / f"Tickets/{ticket}.md").read_text(encoding="utf-8"))
                self.assertIn(ticket, WORKFLOW)
        self.assertIn("Asset Browser", WORKFLOW)
        self.assertIn("not yet shipped", WORKFLOW)
        self.assertIn("choice **dialog is only planned**", WORKFLOW)
        self.assertIn("T-059", RASTER)

    def test_documented_witnesses_exist(self) -> None:
        for rel in ("tests/object_assets_smoke.gd", "tests/object_editor_smoke.gd",
                    "drawing/tests/object_editor_ui_smoke.gd", "tests/campaign_bundle_smoke.gd",
                    "tests/test_t074_object_docs.py"):
            with self.subTest(test=rel):
                self.assertTrue((ROOT / rel).is_file())
                self.assertIn(rel, WORKFLOW)
        self.assertIn("godot --headless --path . --script", WORKFLOW)

    def test_markdown_links_resolve_and_workflow_not_review_gated(self) -> None:
        for name, content in (("RASTER_OBJECTS_WORKFLOW.md", RASTER),
                              ("OBJECT_ASSETS_WORKFLOW.md", WORKFLOW)):
            for dest in re.findall(r"\]\(([^)]+)\)", content):
                if dest.startswith(("http://", "https://", "mailto:")):
                    continue
                relative = dest.split("#", 1)[0]
                if relative:
                    with self.subTest(page=name, link=dest):
                        self.assertTrue((DOCS / relative).is_file())
        ticket = (DOCS / "Tickets/T-074.md").read_text(encoding="utf-8")
        self.assertIn('manual_review: false', ticket)
        self.assertIn('depends_on: []', ticket)
        self.assertIn('status: "Done"', ticket)
        self.assertIn("Worked example", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
