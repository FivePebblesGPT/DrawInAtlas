#!/usr/bin/env python3
"""T-067 reproducible Zstd/physical-layout benchmark on deterministic RGBA8 worlds.

The native library is used with Zstd level 3; the Godot compatibility witness
verifies the on-disk frames with FileAccess.COMPRESSION_ZSTD. No pip modules.

Run: python3 tools/benchmarks/chunk_geometry.py --output /tmp/t067-results
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import struct
import tempfile
import time
from collections import OrderedDict, defaultdict
from dataclasses import dataclass
from typing import Iterator

STRIDES = (256, 512, 1024, 2048)
SEED = 670021
LEVEL = 3
FRAME_PREFIX = struct.Struct('<Q')


class Zstd:
    """Calls the same native Zstandard format as Godot's ZSTD PackedByteArray."""

    def __init__(self) -> None:
        library = ctypes.util.find_library('zstd')
        if not library:
            raise RuntimeError('libzstd is required for the benchmark')
        self.lib = ctypes.CDLL(library)
        self.lib.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
        self.lib.ZSTD_compressBound.restype = ctypes.c_size_t
        self.lib.ZSTD_compress.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
        self.lib.ZSTD_compress.restype = ctypes.c_size_t
        self.lib.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                              ctypes.c_void_p, ctypes.c_size_t]
        self.lib.ZSTD_decompress.restype = ctypes.c_size_t
        self.lib.ZSTD_isError.argtypes = [ctypes.c_size_t]
        self.lib.ZSTD_isError.restype = ctypes.c_uint

    def compress(self, source: bytes) -> bytes:
        target = ctypes.create_string_buffer(self.lib.ZSTD_compressBound(len(source)))
        data = ctypes.create_string_buffer(source)
        result = self.lib.ZSTD_compress(target, len(target), data, len(source), LEVEL)
        if self.lib.ZSTD_isError(result):
            raise RuntimeError('Zstd compression failed')
        return target.raw[:result]

    def decompress(self, payload: bytes, expected: int) -> bytes:
        target = ctypes.create_string_buffer(expected)
        data = ctypes.create_string_buffer(payload)
        result = self.lib.ZSTD_decompress(target, expected, data, len(payload))
        if self.lib.ZSTD_isError(result) or result != expected:
            raise RuntimeError('Zstd size or checksum mismatch')
        return target.raw


@dataclass(frozen=True)
class Layer:
    name: str
    origin: tuple[int, int]
    size: tuple[int, int]
    pixels: bytes | None
    density: int = 1
    marks: tuple[tuple[int, int], ...] = ()


def make_sources() -> dict[str, tuple[Layer, ...]]:
    width, height = 2304, 1408
    gradient = bytearray(width * height * 4)
    for y in range(height):
        # Smooth gradient mixed with sharp art boundaries and transparent RGB.
        row = bytearray()
        for x in range(width):
            row.extend(((x // 7 + y // 11) & 255, (x // 13 + 3 * y) & 255,
                        ((x + y) // 9) & 255, 0 if (x + y) % 19 == 0 else 255))
        gradient[y * width * 4:(y + 1) * width * 4] = row
    strokes = bytearray(width * height * 4)
    # Long crossing ink paths with sparse transparent regions.
    for y in range(height):
        for band in range(3):
            x = (17 * y + band * 613) % width
            for delta in range(-3, 4):
                if 0 <= x + delta < width:
                    off = (y * width + x + delta) * 4
                    strokes[off:off + 4] = bytes((30 + band * 45, y & 255, 190, 180))
        if y % 59 < 5:
            for x in range(128, width - 128):
                off = (y * width + x) * 4
                strokes[off:off + 4] = b'\x33\xa1\x55\xff'
    rng = random.Random(SEED)
    texture = rng.randbytes(1152 * 896 * 4)
    marks = tuple(((-1 if i % 2 else 1) * (1_300_000 + 19_213 * i),
                   (-1 if i % 3 else 1) * (2_000_000 + 10_009 * i)) for i in range(22))
    very_far = ((2**53 + 993, -(2**53 + 1987)), (-2**53 - 99, 2**53 + 777))
    return {
        'dense': (
            Layer('terrain', (-384, -128), (width, height), bytes(gradient)),
            Layer('ink', (-384, -128), (width, height), bytes(strokes)),
        ),
        'texture': (Layer('imported', (77, -95), (1152, 896), texture, 2),),
        'sparse': (Layer('remote-marks', (0, 0), (0, 0), None, 1, marks + very_far),),
        'mixed': (
            Layer('terrain', (-384, -128), (width, height), bytes(gradient)),
            Layer('remote-marks', (0, 0), (0, 0), None, 1, marks),
            Layer('imported', (77, -95), (1152, 896), texture, 2),
        ),
    }


def floor_tile(position: int, stride: int) -> int:
    return position // stride


def tile_coordinates(layer: Layer, stride: int) -> Iterator[tuple[int, int]]:
    if layer.pixels is None:
        coords: set[tuple[int, int]] = set()
        for x, y in layer.marks:
            for ox in range(-2, 3):
                for oy in range(-2, 3):
                    coords.add((floor_tile(x + ox, stride), floor_tile(y + oy, stride)))
        yield from sorted(coords)
        return
    x, y = layer.origin
    w, h = layer.size
    for ty in range(y // stride, (y + h - 1) // stride + 1):
        for tx in range(x // stride, (x + w - 1) // stride + 1):
            yield tx, ty


def make_tile(layer: Layer, stride: int, tx: int, ty: int) -> bytes:
    out = bytearray(stride * stride * 4)
    if layer.pixels is None:
        for x, y in layer.marks:
            for py in range(y - 2, y + 3):
                if py // stride != ty:
                    continue
                for px in range(x - 2, x + 3):
                    if px // stride == tx:
                        off = ((py - ty * stride) * stride + (px - tx * stride)) * 4
                        out[off:off + 4] = b'\xa0\x21\x19\x00' if px == x else b'\x10\x88\xf7\xee'
        return bytes(out)
    sx, sy = layer.origin
    w, h = layer.size
    left, right = max(sx, tx * stride), min(sx + w, (tx + 1) * stride)
    top, bottom = max(sy, ty * stride), min(sy + h, (ty + 1) * stride)
    for py in range(top, bottom):
        src = ((py - sy) * w + left - sx) * 4
        dst = ((py - ty * stride) * stride + left - tx * stride) * 4
        out[dst:dst + (right - left) * 4] = layer.pixels[src:src + (right - left) * 4]
    return bytes(out)


def digest(raw: bytes, stride: int) -> str:
    return hashlib.sha256(f'{stride},{stride}:RGBA8:'.encode() + raw).hexdigest()


def percentile(items: list[float], fraction: float) -> float:
    ordered = sorted(items)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] if ordered else 0.0


def stats(items: list[float]) -> dict[str, float]:
    return {'median_ms': round(statistics.median(items), 3) if items else 0.0,
            'p95_ms': round(percentile(items, 0.95), 3)}


def system_info() -> dict[str, str | int]:
    cpu = platform.processor() or platform.machine()
    ram_mib = 0
    if Path('/proc/cpuinfo').exists():
        for line in Path('/proc/cpuinfo').read_text(errors='replace').splitlines():
            if line.startswith('model name'):
                cpu = line.split(':', 1)[1].strip()
                break
    if Path('/proc/meminfo').exists():
        for line in Path('/proc/meminfo').read_text(errors='replace').splitlines():
            if line.startswith('MemTotal:'):
                ram_mib = int(line.split()[1]) // 1024
                break
    return {'os': platform.platform(), 'python': platform.python_version(),
            'processor': cpu, 'cpu_logical': os.cpu_count() or 0,
            'ram_mib': ram_mib, 'filesystem': 'container filesystem; inspect df -T',
            'seed': SEED, 'zstd_level': LEVEL}


def physical_size(path: Path) -> int:
    return sum(getattr(p.stat(), 'st_blocks', 0) * 512 or p.stat().st_size
               for p in path.rglob('*') if p.is_file())


def write_file(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def pack_layout(folder: Path, scheme: str, chunks: dict[str, dict], codec: Zstd,
                stride: int) -> dict:
    """Write actual files, index, verify each frame by reading its recorded offset."""
    refs: list[tuple[str, str, str]] = []
    unique: dict[str, bytes] = {}
    groups: dict[str, list[str]] = defaultdict(list)
    for key, record in chunks.items():
        d = record['sha256']
        refs.append((key, d, record['document']))
        unique[d] = record['compressed']
        groups[record['document']].append(key)
    index: dict = {'schema': 't067-simulated-v1', 'stride': stride, 'scheme': scheme,
                   'references': {}, 'blobs': {}}
    writes = 0
    started = time.perf_counter_ns()
    if scheme == 'individual':
        for d, payload in sorted(unique.items()):
            rel = f'chunks/{d[:2]}/{d}.zst'
            write_file(folder / rel, payload)
            index['blobs'][d] = [rel, 0, len(payload)]
            writes += 1
        for key, d, _ in refs:
            index['references'][key] = d
    elif scheme == 'document_pack':
        (folder / 'packs').mkdir(parents=True, exist_ok=True)
        for doc, keys in sorted(groups.items()):
            rel = f'packs/{doc}.pack'
            with (folder / rel).open('wb') as file:
                for key in sorted(keys):
                    d = chunks[key]['sha256']
                    payload = chunks[key]['compressed']
                    file.write(FRAME_PREFIX.pack(len(payload)))
                    position = file.tell()
                    file.write(payload)
                    index['references'][key] = [rel, position, len(payload), d]
            writes += 1
    elif scheme == 'shared_pack':
        rel = 'packs/global.pack'
        (folder / 'packs').mkdir(parents=True, exist_ok=True)
        with (folder / rel).open('wb') as file:
            for d, payload in sorted(unique.items()):
                file.write(FRAME_PREFIX.pack(len(payload)))
                position = file.tell()
                file.write(payload)
                index['blobs'][d] = [rel, position, len(payload)]
        writes += 1
        for key, d, _ in refs:
            index['references'][key] = d
    else:
        raise ValueError(scheme)
    contents = json.dumps(index, separators=(',', ':'), sort_keys=True).encode('utf-8')
    write_file(folder / 'index.json', contents)
    writes += 1
    wall_ms = (time.perf_counter_ns() - started) / 1e6
    files = [p for p in folder.rglob('*') if p.is_file()]
    io_reads = 0
    for key, d, _ in refs:
        pointer = index['references'][key]
        rel, offset, length = index['blobs'][d] if isinstance(pointer, str) else pointer[:3]
        with (folder / rel).open('rb') as reader:
            reader.seek(offset)
            payload = reader.read(length)
            io_reads += 1
        if hashlib.sha256(payload).hexdigest() != chunks[key]['compressed_sha256']:
            raise AssertionError('Packed payload digest mismatch')
        if codec.decompress(payload, stride * stride * 4) != chunks[key]['raw']:
            raise AssertionError('Packed payload does not decode byte-exactly')
    selected = sorted(index['references'])[:min(8, len(index['references']))]
    repeated_reads: list[float] = []
    # The first pass is process-cold but may still hit the OS page cache: no
    # unsupported claim of flushing kernel caches or cold physical storage.
    for _pass in range(2):
        start = time.perf_counter_ns()
        for key in selected:
            pointer = index['references'][key]
            ref = index['blobs'][pointer] if isinstance(pointer, str) else pointer[:3]
            with (folder / ref[0]).open('rb') as reader:
                reader.seek(ref[1])
                payload = reader.read(ref[2])
            if len(payload) != ref[2]:
                raise AssertionError('Viewport read was truncated')
            if len(codec.decompress(payload, stride * stride * 4)) != stride * stride * 4:
                raise AssertionError('Viewport tile failed decode')
        repeated_reads.append(round((time.perf_counter_ns() - start) / 1e6, 3))
    return {'scheme': scheme, 'files': len(files), 'index_bytes': len(contents),
            'viewport_8_tiles_process_first_ms': repeated_reads[0],
            'viewport_8_tiles_warm_ms': repeated_reads[1],
            'payload_bytes': sum(p.stat().st_size for p in files),
            'fs_allocated_bytes': physical_size(folder), 'write_calls': writes,
            'reopen_calls': io_reads, 'cold_write_ms': round(wall_ms, 3)}


def benchmark_workload(workload: str, layers: tuple[Layer, ...], stride: int,
                       base: Path, codec: Zstd, repeats: int) -> dict:
    chunks: dict[str, dict] = {}
    encoded = 0
    encode_times: list[float] = []
    decode_times: list[float] = []
    raw_size = stride * stride * 4
    for layer in layers:
        for tx, ty in tile_coordinates(layer, stride):
            raw = make_tile(layer, stride, tx, ty)
            key = f'{layer.name}:{tx},{ty}'
            d = digest(raw, stride)
            for _ in range(repeats):
                before = time.perf_counter_ns()
                compressed = codec.compress(raw)
                encode_times.append((time.perf_counter_ns() - before) / 1e6)
                before = time.perf_counter_ns()
                restored = codec.decompress(compressed, raw_size)
                decode_times.append((time.perf_counter_ns() - before) / 1e6)
                if restored != raw or digest(restored, stride) != d:
                    raise AssertionError('RGBA8 bytes/hidden RGB were altered')
            chunks[key] = {'sha256': d, 'compressed_sha256': hashlib.sha256(compressed).hexdigest(),
                           'compressed': compressed, 'raw': raw, 'document': layer.name}
            encoded += len(compressed)
    layouts = []
    for scheme in ('individual', 'document_pack', 'shared_pack'):
        layouts.append(pack_layout(base / scheme, scheme, chunks, codec, stride))
    return {'workload': workload, 'stride': stride, 'layer_count': len(layers),
            'logical_tiles': len(chunks), 'unique_blobs': len({c['sha256'] for c in chunks.values()}),
            'allocated_rgba_bytes': len(chunks) * raw_size,
            'encoded_tile_bytes': encoded,
            'encoded_bytes_per_tile': round(encoded / max(len(chunks), 1), 1),
            'encode': stats(encode_times), 'decode': stats(decode_times),
            'encode_mib_s': round((raw_size * len(encode_times)) / max(1, sum(encode_times)) / 1048576 * 1000, 1),
            'decode_mib_s': round((raw_size * len(decode_times)) / max(1, sum(decode_times)) / 1048576 * 1000, 1),
            'layouts': layouts}


def measured_edit_rewrite(result: dict, source_root: Path, codec: Zstd) -> dict:
    """Measure update of one tile and the I/O amplification of each layout.

    Simulates an immutable new version (append/replace packed container via staging).
    Atlas's real root rename fault tests run separately in Godot.
    """
    stride = result['stride']
    prefix = source_root
    measured: dict[str, dict] = {}
    for layout in result['layouts']:
        scheme = layout['scheme']
        folder = prefix / scheme
        index = json.loads((folder / 'index.json').read_bytes())
        target_key = sorted(index['references'])[0]
        ref = index['references'][target_key]
        loc = index['blobs'][ref] if isinstance(ref, str) else ref[:3]
        with (folder / loc[0]).open('rb') as f:
            f.seek(loc[1]); raw = codec.decompress(f.read(loc[2]), stride * stride * 4)
        modified = bytearray(raw)
        modified[0:4] = b'\x93\x77\x11\x00' if raw[0:4] != b'\x93\x77\x11\x00' else b'\x90\x41\x80\xff'
        new_payload = codec.compress(bytes(modified))
        started = time.perf_counter_ns()
        if scheme == 'individual':
            staged = folder / 'chunks' / 'changed.zst'
            write_file(staged, new_payload)
            byte_writes = len(new_payload)
            write_calls = 1
        elif scheme == 'document_pack':
            source = folder / loc[0]
            new = folder / 'packs' / 'changed.pack'
            # An immutable replacement must copy all of this document's old pack.
            old_bytes = source.read_bytes()
            write_file(new, old_bytes + FRAME_PREFIX.pack(len(new_payload)) + new_payload)
            byte_writes = new.stat().st_size
            write_calls = 1
        else:
            # An immutable shared pack with a new generation cannot modify its old pack.
            # Model a delta pack: an extra file and index reference instead of rewriting all history.
            new = folder / 'packs' / 'changed-delta.pack'
            write_file(new, FRAME_PREFIX.pack(len(new_payload)) + new_payload)
            byte_writes = new.stat().st_size
            write_calls = 1
        measured[scheme] = {'new_blob_bytes': len(new_payload), 'payload_write_bytes': byte_writes,
                            'payload_write_calls': write_calls,
                            'payload_write_ms': round((time.perf_counter_ns()-started)/1e6, 3)}
    return measured


def cache_trace(result: dict, capacity: int) -> dict:
    """Bounded LRU replay on viewport tile access, read amplification only."""
    stride = result['stride']
    count = result['logical_tiles']
    view_tiles = min(count, 16)
    sequence = list(range(view_tiles)) * 3
    # Pan away and return, including a mixed-document view in the access pattern.
    sequence.extend(range(max(0, count - view_tiles), count))
    sequence.extend(range(view_tiles))
    cache: OrderedDict[int, None] = OrderedDict()
    bytes_in_cache = 0
    misses = hits = evictions = 0
    entry_bytes = stride * stride * 4
    for key in sequence:
        if key in cache:
            hits += 1
            cache.move_to_end(key)
            continue
        misses += 1
        cache[key] = None
        bytes_in_cache += entry_bytes
        while bytes_in_cache > capacity or len(cache) > 64:
            cache.popitem(last=False)
            bytes_in_cache -= entry_bytes
            evictions += 1
    return {'budget_mib': capacity // 1048576, 'hits': hits,
            'misses': misses, 'evictions': evictions}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--repeats', type=int, default=3)
    ap.add_argument('--strides', type=int, nargs='+', default=list(STRIDES))
    ap.add_argument('--workloads', nargs='+', default=['dense', 'texture', 'sparse', 'mixed'])
    args = ap.parse_args()
    if args.repeats < 1 or any(s not in STRIDES for s in args.strides):
        ap.error('repeats >=1 and strides in 256/512/1024/2048 required')
    args.output.mkdir(parents=True, exist_ok=True)
    raw = make_sources()
    if any(w not in raw for w in args.workloads):
        ap.error('unsupported workload')
    codec = Zstd()
    results: list[dict] = []
    with tempfile.TemporaryDirectory(prefix='t067-physical-') as tmp:
        for stride in args.strides:
            for workload in args.workloads:
                layers = raw[workload]
                root = Path(tmp) / f'{workload}-{stride}'
                print(f'T067 {workload:7s} stride={stride:4d}', flush=True)
                data = benchmark_workload(workload, layers, stride, root, codec, args.repeats)
                data['edit_rewrite'] = measured_edit_rewrite(data, root, codec)
                data['cache_trace'] = [cache_trace(data, cap * 1048576) for cap in (8, 32, 128)]
                results.append(data)
    output = {'schema': 't067-geometry-benchmark-v1', 'system': system_info(),
              'repeat_count': args.repeats, 'results': results}
    # A tiny bridge payload permits a real Godot reader to prove the ctypes
    # Zstd frames are usable as unchanged DrawingChunkStore payloads.
    fixture_stride = 512
    fixture_bytes = make_tile(raw['sparse'][0], fixture_stride, *next(tile_coordinates(raw['sparse'][0], fixture_stride)))
    fixture_digest = digest(fixture_bytes, fixture_stride)
    (args.output / 'codec-fixture.zst').write_bytes(codec.compress(fixture_bytes))
    (args.output / 'codec-fixture.json').write_text(json.dumps({'stride': fixture_stride,
        'sha256': fixture_digest, 'decoded_bytes': len(fixture_bytes),
        'compressed_sha256': hashlib.sha256((args.output / 'codec-fixture.zst').read_bytes()).hexdigest()},
        indent=2) + '\n')
    (args.output / 'measurements.json').write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    lines = ['workload,stride,scheme,logical_tiles,raw_mib,encoded_mib,files,index_bytes,project_mib,fs_allocated_mib,write_calls,update_write_kib,encode_median_ms,encode_p95_ms,decode_median_ms,decode_p95_ms,viewport_8_tile_first_ms,viewport_8_tile_warm_ms']
    for row in results:
        for layout in row['layouts']:
            edit = row['edit_rewrite'][layout['scheme']]
            lines.append(','.join(map(str, [row['workload'], row['stride'], layout['scheme'],
                row['logical_tiles'], round(row['allocated_rgba_bytes'] / 1048576, 3),
                round(row['encoded_tile_bytes'] / 1048576, 3), layout['files'],
                layout['index_bytes'], round(layout['payload_bytes'] / 1048576, 3),
                round(layout['fs_allocated_bytes'] / 1048576, 3), layout['write_calls'],
                round(edit['payload_write_bytes'] / 1024, 1), row['encode']['median_ms'],
                row['encode']['p95_ms'], row['decode']['median_ms'], row['decode']['p95_ms'], layout['viewport_8_tiles_process_first_ms'],
                layout['viewport_8_tiles_warm_ms']])))
    (args.output / 'measurements.csv').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'T067_GEOMETRY_PASSED ({len(results)} workload/stride cases, {len(lines)-1} layout cases)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
