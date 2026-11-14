"""T-123: source/CI contracts for predecoder raster dimensions and one snapshot."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RasterPredecodeBoundsContracts(unittest.TestCase):
    def test_all_supported_codecs_preflight_before_decoder(self) -> None:
        source = (ROOT / "addons/drawing/raster_import.gd").read_text()
        decode = source.split("static func decode_image_bytes(", 1)[1].split(
            "\nstatic func import_image(", 1
        )[0]
        self.assertLess(decode.index("_declared_dimensions(source_bytes, kind)"),
                        decode.index("Image.new()"))
        self.assertLess(decode.index("if not bounds.ok:"), decode.index("Image.new()"))
        for loader in ("load_png_from_buffer", "load_webp_from_buffer", "load_jpg_from_buffer"):
            self.assertIn(loader, decode)
        self.assertNotIn("Image.load_from_file", source)

    def test_header_guards_are_bounded_and_format_aware(self) -> None:
        source = (ROOT / "addons/drawing/raster_import.gd").read_text()
        self.assertIn("_big_endian_u32(source_bytes, 16)", source)
        self.assertIn('"IHDR".to_ascii_buffer()', source)
        for marker in ('"VP8 "', '"VP8L"', '"VP8X"', "chunk_size", "riff_size"):
            self.assertIn(marker, source)
        self.assertIn("source_bytes.size() - offset", source)
        self.assertIn("found_sof", source)
        self.assertIn("width > 4096 or height > 4096", source)
        self.assertIn("width * height > 16777216", source)
        self.assertIn("source_bytes.size() > 64 * 1024 * 1024", source)

    def test_existing_snapshot_and_open_regressions_remain_gating(self) -> None:
        workflow = (ROOT / ".github/workflows/godot-check.yml").read_text()
        for expected in (
            "t120_unified_open_smoke.gd",
            "t121_raster_snapshot_smoke.gd",
            "t123_raster_predecode_bounds_smoke.gd",
            "test_t123_raster_predecode_bounds.py",
            "T123_MODEL_PASSED",
        ):
            self.assertIn(expected, workflow)
        self.assertIn("--marker T123_MODEL_PASSED", workflow)
        self.assertIn("ci_finish", workflow)

    def test_oracle_has_undecodable_oversize_and_real_image_controls(self) -> None:
        oracle = (ROOT / "drawing/tests/t123_raster_predecode_bounds_smoke.gd").read_text()
        for expected in (
            "png_header(4097, 1)",
            'webp_header("VP8 ", 4097, 1)',
            'webp_header("VP8L", 1, 4097)',
            'webp_header("VP8X", 4097, 1)',
            "jpeg_header(4097, 1)",
            "app._open_file(path)",
            "app.tabs.size() == 0",
            "original.save_png(path)",
            "original.save_webp(path, true, 1.0)",
            "original.save_jpg(path, 1.0)",
            "T123_MODEL_PASSED",
        ):
            self.assertIn(expected, oracle)


if __name__ == "__main__":
    unittest.main()
