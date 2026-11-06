"""T-075: publication and collaboration docs never overclaim isolated proofs.

Tests ground the nine pages in actual class boundaries, test witnesses, ticket
frontmatter and the current project platform; they do not approve privacy policy.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
FILES = (
    "PLAYER_PROJECTION_CONTRACT.md",
    "PLAYER_OUTPUT_WORKFLOW.md",
    "PROJECTOR_FRAME_WORKFLOW.md",
    "TOKEN_WORKFLOW.md",
    "FOG_WORKFLOW.md",
    "AUTHORITATIVE_SESSIONS.md",
    "ROLE_FILTERED_REPLICATION.md",
    "RECONNECT_RESYNCHRONIZATION.md",
    "COLLABORATION_ACCEPTANCE.md",
)
CONTENTS = {name: (DOCS / name).read_text(encoding="utf-8") for name in FILES}


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class ProjectionCollaborationDocumentationTests(unittest.TestCase):
    def test_each_page_leads_with_current_scope_and_archived_web(self) -> None:
        for name, content in CONTENTS.items():
            with self.subTest(page=name):
                self.assertIn("T-075, 2026-11-02", content)
                self.assertLess(content.index("T-075, 2026-11-02"), 220)
                self.assertIn("Windows/Linux", content)
                self.assertIn("T-044", content)
                self.assertIn("Archived", content)
                self.assertIn("DrawingDocument", content)
                self.assertIn("AtlasDrawingRegistry", content)
                self.assertIn("AtlasObjectLibrary", content)
                self.assertIn("T-066", content)
                self.assertIn("T-039", content)
                self.assertIn("T-043", content)

    def test_implementation_types_are_real_and_presentation_stays_legacy(self) -> None:
        self.assertIn("class_name DrawingDocument", source("addons/drawing/document.gd"))
        self.assertIn("class_name AtlasDrawingRegistry", source("scripts/campaign/drawing_registry.gd"))
        self.assertIn("class_name AtlasObjectLibrary", source("scripts/objects/object_library.gd"))
        projection = source("scripts/presentation/player_projection.gd")
        output = source("scripts/presentation/player_output_session.gd")
        self.assertIn("class_name AtlasPlayerProjection", projection)
        self.assertIn("AtlasCampaign", projection)
        self.assertIn("AtlasMapDocument", projection)
        self.assertNotIn("AtlasDrawingRegistry", projection)
        self.assertNotIn("AtlasObjectLibrary", projection)
        self.assertIn("AtlasPlayerProjection.build_capture_input", output)
        self.assertIn("AtlasHostSession", source("scripts/collaboration/host_session.gd"))
        for name in ("PLAYER_PROJECTION_CONTRACT.md", "PLAYER_OUTPUT_WORKFLOW.md",
                     "ROLE_FILTERED_REPLICATION.md", "COLLABORATION_ACCEPTANCE.md"):
            with self.subTest(page=name):
                self.assertIn("legacy", CONTENTS[name].lower())
                self.assertIn("not", CONTENTS[name].lower())

    def test_web_is_archived_but_historical_proof_kept(self) -> None:
        self.assertIn('status: "Archived"', source("docs/Tickets/T-044.md"))
        self.assertTrue((DOCS / "Archive/Web/T-044.md").is_file())
        output = CONTENTS["PLAYER_OUTPUT_WORKFLOW.md"]
        self.assertIn("## Archived T-044", output)
        self.assertIn("open_embedded", output)
        self.assertIn("historical", output.lower())
        self.assertIn("open_embedded", source("scripts/presentation/player_output_session.gd"))
        self.assertNotIn("T-044 owns Web output", output)

    def test_generation_storage_not_single_file_save(self) -> None:
        bundle = source("scripts/persistence/campaign_bundle.gd")
        for marker in ('".atlas.json"', '"campaign.scn"'):
            self.assertIn(marker, bundle)
        for name in ("TOKEN_WORKFLOW.md", "FOG_WORKFLOW.md",
                     "ROLE_FILTERED_REPLICATION.md"):
            with self.subTest(page=name):
                self.assertIn("campaign.scn", CONTENTS[name])
                self.assertIn("legacy", CONTENTS[name].lower())
        self.assertIn("Campaign.atlas.json", CONTENTS["TOKEN_WORKFLOW.md"])
        self.assertIn("Campaign.atlas.json", CONTENTS["FOG_WORKFLOW.md"])

    def test_no_privacy_grant_from_preview_or_edit_visibility(self) -> None:
        projection = CONTENTS["PLAYER_PROJECTION_CONTRACT.md"]
        self.assertIn("AtlasPreviewCache", projection)
        self.assertIn("layer.visible", projection)
        self.assertIn("deny", projection.lower())
        self.assertIn("Object Asset", projection)
        self.assertIn("fog", CONTENTS["FOG_WORKFLOW.md"].lower())
        self.assertIn("not", CONTENTS["TOKEN_WORKFLOW.md"].lower())
        self.assertIn("private", CONTENTS["TOKEN_WORKFLOW.md"].lower())
        self.assertIn("frozen", CONTENTS["PLAYER_OUTPUT_WORKFLOW.md"])

    def test_frame_and_native_test_window_are_not_connected_publish(self) -> None:
        frame = CONTENTS["PROJECTOR_FRAME_WORKFLOW.md"]
        self.assertIn("AtlasProjectorFrame", frame)
        self.assertIn("session-only", frame)
        self.assertIn("not wired", frame)
        self.assertIn("AtlasPlayerOutputSession", frame)
        self.assertIn("not a connected main-editor Publish command",
                      CONTENTS["PLAYER_OUTPUT_WORKFLOW.md"])
        self.assertIn("class_name AtlasProjectorFrame",
                      source("scripts/presentation/projector_frame.gd"))
        self.assertIn("class_name AtlasPlayerOutputSession",
                      source("scripts/presentation/player_output_session.gd"))

    def test_network_proofs_are_in_process_not_authenticated(self) -> None:
        for name in ("AUTHORITATIVE_SESSIONS.md", "ROLE_FILTERED_REPLICATION.md",
                     "RECONNECT_RESYNCHRONIZATION.md", "COLLABORATION_ACCEPTANCE.md"):
            with self.subTest(page=name):
                content = CONTENTS[name].lower()
                self.assertIn("in-process", content)
                self.assertIn("authenticated", content)
                self.assertIn("not", content)
                self.assertIn("t-048", content)
        self.assertIn("token_move", CONTENTS["AUTHORITATIVE_SESSIONS.md"])
        self.assertIn("png_base64", CONTENTS["ROLE_FILTERED_REPLICATION.md"])
        self.assertIn("retired-handle", CONTENTS["RECONNECT_RESYNCHRONIZATION.md"])
        self.assertIn("TextureRect", CONTENTS["COLLABORATION_ACCEPTANCE.md"])

    def test_all_owner_and_independent_review_gates_remain_unapproved(self) -> None:
        for ident, status, manual in (
            ("039", "Manual Review", "true"),
            ("043", "Blocked", "true"),
            ("048", "Blocked", "true"),
        ):
            with self.subTest(ticket=ident):
                ticket = source(f"docs/Tickets/T-{ident}.md")
                self.assertIn(f'status: "{status}"', ticket)
                self.assertIn(f"manual_review: {manual}", ticket)
                self.assertNotIn("manual_review_approved: true", ticket)
        doc_ticket = source("docs/Tickets/T-075.md")
        self.assertIn('status: "Done"', doc_ticket)
        self.assertIn("manual_review: false", doc_ticket)
        self.assertIn("depends_on: []", doc_ticket)

    def test_runtime_witnesses_exist_and_stay_distinct(self) -> None:
        witnesses = (
            "player_projection_contract_smoke.gd", "player_projection_visual.gd",
            "player_output_session_smoke.gd", "player_output_session_visual.gd",
            "player_privacy_acceptance_smoke.gd", "player_privacy_acceptance_visual.gd",
            "projector_frame_smoke.gd", "projector_frame_visual.gd",
            "token_smoke.gd", "token_visual.gd", "fog_smoke.gd", "fog_visual.gd",
            "authoritative_session_smoke.gd", "filtered_replication_smoke.gd",
            "reconnect_resync_smoke.gd", "collaboration_acceptance_smoke.gd",
            "collaboration_acceptance_visual.gd",
        )
        combined = "\n".join(CONTENTS.values())
        for name in witnesses:
            with self.subTest(witness=name):
                self.assertTrue((ROOT / "tests" / name).is_file())
                self.assertIn(name[:-3], combined)

    def test_local_markdown_links_resolve(self) -> None:
        for name, content in CONTENTS.items():
            for url in re.findall(r"\]\(([^)]+)\)", content):
                if url.startswith(("https://", "http://", "mailto:")):
                    continue
                stem = url.split("#", 1)[0]
                if stem:
                    with self.subTest(page=name, target=url):
                        self.assertTrue((DOCS / stem).is_file())


if __name__ == "__main__":
    unittest.main()
