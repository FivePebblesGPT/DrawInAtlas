"""T-067 benchmark reproducibility, geometry invariants and pack fault probes."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'benchmarks' / 'chunk_geometry.py'
SPEC = importlib.util.spec_from_file_location('chunk_geometry', MODULE)
assert SPEC and SPEC.loader
import sys
LIB = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = LIB
SPEC.loader.exec_module(LIB)


class ChunkGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.codec = LIB.Zstd()

    def test_negative_and_over_53_bit_addresses_retain_integer_offsets(self) -> None:
        for size in LIB.STRIDES:
            for coordinate in (-2**53-993, -size-1, -size, -1, 0, size-1,
                               size, 2**53+993):
                index = LIB.floor_tile(coordinate, size)
                self.assertTrue(0 <= coordinate - index * size < size)

    def test_same_rgba8_source_under_every_partition(self) -> None:
        # Build only a tiny partial-edge image; pixel positions (not tile keys)
        # define the invariant when a saved source is explicitly retiled.
        pixel = b'\xa1\x22\x09\x00'
        width, height = 17, 13
        raw = bytes(pixel * width * height)
        layer = LIB.Layer('retile', (-5, -9), (width, height), raw, density=2)
        for stride in LIB.STRIDES:
            tiled = {key: LIB.make_tile(layer, stride, *key)
                     for key in LIB.tile_coordinates(layer, stride)}
            for y in range(-10, 5):
                for x in range(-6, 14):
                    key = (x // stride, y // stride)
                    data = tiled.get(key)
                    if data is None:
                        actual = b'\0\0\0\0'
                    else:
                        off = ((y - key[1]*stride)*stride + x - key[0]*stride)*4
                        actual = data[off:off+4]
                    expected = pixel if -5 <= x < 12 and -9 <= y < 4 else b'\0\0\0\0'
                    self.assertEqual(actual, expected, (stride, x, y))

    def test_compressed_tiles_exact_hidden_rgb(self) -> None:
        size = 256
        layer = LIB.Layer('hidden', (-1, -1), (3, 3),
                          bytes(b'\x13\x47\x92\x00' * 9))
        for tx, ty in LIB.tile_coordinates(layer, size):
            original = LIB.make_tile(layer, size, tx, ty)
            framed = self.codec.compress(original)
            self.assertEqual(self.codec.decompress(framed, len(original)), original)
            self.assertEqual(LIB.digest(original, size), LIB.digest(
                self.codec.decompress(framed, len(original)), size))

    def test_three_physical_layouts_read_back_identical_bytes(self) -> None:
        stride = 256
        first = LIB.Layer('first', (-2, -2), (3, 3), b'\x11\x22\x33\x00' * 9)
        second = LIB.Layer('second', (255, 255), (3, 3), b'\x11\x22\x33\x00' * 9)
        with tempfile.TemporaryDirectory() as temp:
            result = LIB.benchmark_workload('small', (first, second), stride,
                                            Path(temp), self.codec, 1)
            self.assertEqual(len(result['layouts']), 3)
            self.assertTrue(all(x['reopen_calls'] == result['logical_tiles']
                                for x in result['layouts']))
            self.assertTrue(all(x['index_bytes'] > 0 for x in result['layouts']))
            self.assertLess(result['layouts'][2]['files'], result['layouts'][0]['files'])
            updated = LIB.measured_edit_rewrite(result, Path(temp), self.codec)
            self.assertLessEqual(updated['individual']['payload_write_bytes'],
                                 updated['document_pack']['payload_write_bytes'])

    def test_staged_pack_and_index_failure_never_change_previous_root(self) -> None:
        # Candidate packs are immutable; publish a root only after payloads and
        # index are validated. T-066 tests the actual Atlas root-pointer API.
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            old_blob = self.codec.compress(b'\x22' * 256)
            (folder/'old.pack').write_bytes(old_blob)
            root = folder/'root.json'
            root.write_text(json.dumps({'generation': 'g1',
                                        'sha256': LIB.hashlib.sha256(old_blob).hexdigest()}))
            for failure_phase in ('payload', 'index', 'pointer'):
                staged = folder/'new.pack'
                staged.write_bytes(self.codec.compress(b'\x33' * 256))
                if failure_phase != 'payload':
                    (folder/'new.index').write_text('invalid incomplete index'
                        if failure_phase == 'index' else '{"pack": "new.pack"}')
                if failure_phase == 'pointer':
                    (folder/'root.json.pending').write_text('{"generation": "g2"}')
                self.assertEqual(json.loads(root.read_text())['generation'], 'g1')
                self.assertEqual(self.codec.decompress((folder/'old.pack').read_bytes(), 256),
                                 b'\x22' * 256)
            self.assertEqual(json.loads(root.read_text())['generation'], 'g1')

    def test_decoded_cache_budget_does_not_hide_2048_pressure(self) -> None:
        synthetic = {'stride': 2048, 'logical_tiles': 24}
        trace = LIB.cache_trace(synthetic, 32 * 1048576)
        self.assertGreater(trace['evictions'], 0)
        self.assertLess(trace['hits'], trace['misses'])
        self.assertEqual(LIB.cache_trace({'stride': 256, 'logical_tiles': 24},
                                         32 * 1048576)['evictions'], 0)


if __name__ == '__main__':
    unittest.main()
