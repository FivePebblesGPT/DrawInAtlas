"""T-121 raster Open must decode the capped bytes it validated, not reopen a path."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RasterSnapshotContracts(unittest.TestCase):
    def test_open_uses_single_snapshot_reader(self) -> None:
        workspace = (ROOT / "addons/drawing/workspace.gd").read_text()
        opening = workspace.split("func _open_raster_file(path: String) -> void:", 1)[1].split(
            "\nfunc _ask_open() -> void:", 1
        )[0]
        self.assertIn("DrawingRasterImport.load_file_image(path)", opening)
        self.assertNotIn("Image.load_from_file(path)", opening)
        self.assertNotIn("FileAccess.open(path", opening)

    def test_reader_bounds_bytes_before_decoding_once(self) -> None:
        source = (ROOT / "addons/drawing/raster_import.gd").read_text()
        read = source.split("static func load_file_image(", 1)[1].split(
            "\nstatic func ", 1
        )[0]
        self.assertIn("64 * 1024 * 1024", read)
        self.assertIn("get_length()", read)
        self.assertIn("get_buffer(byte_count)", read)
        self.assertIn("source_bytes.size() != byte_count", read)
        self.assertIn("decode_image_bytes(source_bytes", read)
        self.assertNotIn("Image.load_from_file(", source)

    def test_original_and_new_oracles_in_fast_ci(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        self.assertIn("t120_unified_open_smoke.gd", workflow)
        self.assertIn("t121_raster_snapshot_smoke.gd", workflow)
        self.assertIn("test_t121_raster_snapshot.py", workflow)


if __name__ == "__main__":
    unittest.main()
