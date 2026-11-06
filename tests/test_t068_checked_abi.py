"""T-068: bounded native C ABI and failure-atomicity witness (not Godot integration)."""
from __future__ import annotations

import ctypes
from pathlib import Path
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "benchmarks" / "t068_raster_kernel.cpp"
U8 = ctypes.c_uint8
I32 = ctypes.c_int32
U64 = ctypes.c_uint64


class Delta(ctypes.Structure):
    _fields_ = [("index", ctypes.c_uint32), ("before", ctypes.c_uint32),
                ("after", ctypes.c_uint32)]


class NativeCheckedBufferTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.directory = tempfile.TemporaryDirectory(prefix="t068-checked-")
        library_path = Path(cls.directory.name) / "libchecked.so"
        subprocess.run(["g++", "-std=c++17", "-O2", "-fPIC", "-shared", "-Wall",
                        "-Wextra", "-Werror", str(SOURCE), "-o", str(library_path)],
                       check=True, capture_output=True, text=True)
        cls.kernel = ctypes.CDLL(str(library_path))
        cls.kernel.draw_kernel_abi_version.restype = ctypes.c_uint32
        cls.kernel.draw_kernel_checked_api_version.restype = ctypes.c_uint32
        base = [ctypes.POINTER(U8), U64, I32, I32, ctypes.POINTER(I32), U64,
                I32, ctypes.c_uint32, I32, ctypes.POINTER(U8), U64,
                ctypes.POINTER(Delta), U64, I32]
        cls.kernel.draw_batch_deltas_checked.argtypes = base
        cls.kernel.draw_batch_deltas_checked.restype = I32
        cls.kernel.draw_batch_checked.argtypes = base[:2] + [ctypes.POINTER(U8), U64] + base[2:]
        cls.kernel.draw_batch_checked.restype = I32
        cls.kernel.draw_batch_deltas.argtypes = [ctypes.POINTER(U8), I32, I32,
            ctypes.POINTER(I32), I32, ctypes.c_uint32, I32, ctypes.POINTER(U8),
            ctypes.POINTER(Delta), I32]
        cls.kernel.draw_batch_deltas.restype = I32
        cls.kernel.draw_batch.argtypes = [ctypes.POINTER(U8), ctypes.POINTER(U8), I32, I32,
            ctypes.POINTER(I32), I32, ctypes.c_uint32, I32, ctypes.POINTER(U8),
            ctypes.POINTER(Delta), I32]
        cls.kernel.draw_batch.restype = I32

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def make_case(self, width: int = 8, height: int = 8, count: int = 16) -> dict:
        pixels = width * height
        source = (U8 * (pixels * 4))(*((i * 31 + 7) % 256 for i in range(pixels * 4)))
        points = (I32 * (count * 2))(*(n for i in range(count)
            for n in (i % width, (i // width) % height)))
        mask = (U8 * pixels)(*((i % 5) != 0 for i in range(pixels)))
        output = (U8 * (pixels * 4))(*(0xAB for _ in range(pixels * 4)))
        deltas = (Delta * max(1, count))()
        for d in deltas:
            d.index = d.before = d.after = 0xDEADBEEF
        return {"source": source, "source_bytes": ctypes.sizeof(source),
                "output": output, "output_bytes": ctypes.sizeof(output),
                "width": width, "height": height,
                "points": points, "point_bytes": ctypes.sizeof(points),
                "count": count, "rgba": 0x7F1166AA, "operation": 0,
                "mask": mask, "mask_bytes": ctypes.sizeof(mask),
                "deltas": deltas, "delta_bytes": ctypes.sizeof(deltas),
                "delta_capacity": count}

    def invoke(self, case: dict, *, sparse: bool = False) -> int:
        fields = ["source", "source_bytes"]
        if not sparse:
            fields += ["output", "output_bytes"]
        fields += ["width", "height", "points", "point_bytes", "count", "rgba",
                   "operation", "mask", "mask_bytes", "deltas", "delta_bytes",
                   "delta_capacity"]
        func = (self.kernel.draw_batch_deltas_checked if sparse
                else self.kernel.draw_batch_checked)
        return int(func(*(case[name] for name in fields)))

    def test_legacy_abi_unchanged_and_byte_parity(self) -> None:
        self.assertEqual(self.kernel.draw_kernel_abi_version(), 1)
        self.assertEqual(self.kernel.draw_kernel_checked_api_version(), 1)
        randomizer = random.Random(680201)
        for iteration in range(160):
            case = self.make_case(count=24)
            for i in range(len(case["source"])):
                case["source"][i] = randomizer.randrange(256)
            case["rgba"] = randomizer.getrandbits(32)
            case["operation"] = iteration % 3
            case["mask"][:] = bytes(randomizer.randrange(2) for _ in range(64))
            # Include duplicate pixels and occasional completely transparent sources.
            if iteration % 4 == 0:
                case["rgba"] &= 0x00FFFFFF
            for sparse in (True, False):
                checked = self.invoke(case, sparse=sparse)
                old_output = (U8 * 256)()
                old_deltas = (Delta * 24)()
                args = [case["source"]]
                if not sparse:
                    args += [old_output]
                args += [8, 8, case["points"], 24, case["rgba"],
                         case["operation"], case["mask"], old_deltas, 24]
                legacy = int((self.kernel.draw_batch_deltas if sparse
                              else self.kernel.draw_batch)(*args))
                with self.subTest(iteration=iteration, sparse=sparse):
                    self.assertEqual(checked, legacy)
                    self.assertEqual(bytes(case["deltas"])[:max(0, checked) * 12],
                                     bytes(old_deltas)[:max(0, legacy) * 12])
                    if not sparse:
                        self.assertEqual(bytes(case["output"]), bytes(old_output))

    def test_short_buffers_and_null_lengths_are_atomic(self) -> None:
        for sparse in (False, True):
            for name in (["source_bytes", "point_bytes", "mask_bytes", "delta_bytes"] +
                         ([] if sparse else ["output_bytes"])):
                case = self.make_case()
                case[name] -= 1
                before = (bytes(case["source"]), bytes(case["output"]),
                          bytes(case["deltas"]))
                with self.subTest(name=name, sparse=sparse):
                    self.assertEqual(self.invoke(case, sparse=sparse), -5)
                    self.assertEqual(before, (bytes(case["source"]),
                                              bytes(case["output"]), bytes(case["deltas"])))
            for field, byte_field in (("mask", "mask_bytes"), ("points", "point_bytes"),
                                      ("deltas", "delta_bytes")):
                case = self.make_case()
                case[field] = None
                self.assertEqual(self.invoke(case, sparse=sparse), -5,
                                 f"Unexpected success with null {field} and nonzero length")
            case = self.make_case()
            case["source"] = ctypes.cast(ctypes.c_void_p((1 << (ctypes.sizeof(ctypes.c_void_p) * 8)) - 2),
                                         ctypes.POINTER(U8))
            self.assertEqual(self.invoke(case, sparse=sparse), -5)

    def test_overlapping_output_or_deltas_rejected(self) -> None:
        for sparse in (True, False):
            for target in ("source", "mask", "points"):
                case = self.make_case()
                case["deltas"] = ctypes.cast(case[target], ctypes.POINTER(Delta))
                self.assertEqual(self.invoke(case, sparse=sparse), -6,
                                 f"Deltas aliased {target}")
        for target in ("source", "points", "mask", "deltas"):
            case = self.make_case()
            case["output"] = ctypes.cast(case[target], ctypes.POINTER(U8))
            self.assertEqual(self.invoke(case), -6, f"Output aliased {target}")
        # An interior output pointer also aliases the source region.
        case = self.make_case()
        case["output"] = ctypes.cast(ctypes.byref(case["source"], 4), ctypes.POINTER(U8))
        self.assertEqual(self.invoke(case), -6)

    def test_exact_capacity_never_writes_canaries(self) -> None:
        for sparse in (True, False):
            case = self.make_case(count=16)
            output_with_guard = (U8 * (256 + 16))(*(0xA5 for _ in range(272)))
            deltas_with_guard = (Delta * 17)()
            deltas_with_guard[16].index = 0xCAFEF00D
            deltas_with_guard[16].before = 0x12345678
            deltas_with_guard[16].after = 0x7F7F7F7F
            case.update(output=output_with_guard, output_bytes=256,
                        deltas=deltas_with_guard, delta_bytes=16 * 12)
            self.assertGreaterEqual(self.invoke(case, sparse=sparse), 0)
            self.assertEqual(bytes(output_with_guard)[256:], bytes([0xA5] * 16))
            self.assertEqual((deltas_with_guard[16].index,
                              deltas_with_guard[16].before,
                              deltas_with_guard[16].after),
                             (0xCAFEF00D, 0x12345678, 0x7F7F7F7F))

    def test_negative_result_is_failure_atomic(self) -> None:
        for sparse in (False, True):
            for modification, expected in (({"points": (I32 * 2)(-1, 0), "count": 1,
                                            "point_bytes": 8}, -2),
                                           ({"delta_capacity": 0, "delta_bytes": 0}, -3),
                                           ({"operation": 4}, -1),
                                           ({"width": 2049}, -1)):
                case = self.make_case()
                case.update(modification)
                before = (bytes(case["source"]), bytes(case["output"]),
                          bytes(case["deltas"]))
                self.assertEqual(self.invoke(case, sparse=sparse), expected)
                self.assertEqual(before, (bytes(case["source"]),
                                          bytes(case["output"]), bytes(case["deltas"])))

    def test_empty_batch_and_unchanged_transparent_pixels(self) -> None:
        for sparse in (False, True):
            case = self.make_case(count=0)
            case.update(points=None, point_bytes=0, deltas=None, delta_bytes=0,
                        delta_capacity=0, mask=None, mask_bytes=0)
            self.assertEqual(self.invoke(case, sparse=sparse), 0)
            if not sparse:
                self.assertEqual(bytes(case["source"]), bytes(case["output"]))
            case = self.make_case(count=3)
            case.update(rgba=0, operation=0, mask=None, mask_bytes=0)
            self.assertEqual(self.invoke(case, sparse=sparse), 0)
            if not sparse:
                self.assertEqual(bytes(case["source"]), bytes(case["output"]))


if __name__ == "__main__":
    unittest.main()
