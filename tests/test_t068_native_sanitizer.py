"""Pinned C++ native sanitizer and ABI failure-atomicity regression for T-068."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/benchmarks/t068_native_sanitizer.py"
EVIDENCE = ROOT / "docs/benchmarks/T068_2026-11-04_native_sanitizer.json"
spec = importlib.util.spec_from_file_location("t068_native_sanitizer", SCRIPT)
assert spec is not None and spec.loader is not None
sanitizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sanitizer)


class NativeSanitizerContracts(unittest.TestCase):
    def test_checked_evidence_and_source_pins(self) -> None:
        record = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        sanitizer.validate(record)
        self.assertEqual([p["compiler"] for p in record["profiles"]], ["g++", "clang++"])
        self.assertTrue(all(len(p["runs"]) == 2 for p in record["profiles"]))
        self.assertTrue(all(run == sanitizer.EXPECTED for p in record["profiles"]
                            for run in p["runs"]))

    def test_tampered_evidence_fails_closed(self) -> None:
        record = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        attacks = (
            lambda p: p["profiles"].pop(),
            lambda p: p["profiles"].reverse(),
            lambda p: p["profiles"][0]["runs"].pop(),
            lambda p: p["profiles"][0]["runs"][0].update(cases=255),
            lambda p: p["profiles"][0]["runs"][0].update(rejected=16),
            lambda p: p["profiles"][0]["runs"][1].update(digest="0" * 16),
            lambda p: p["profiles"][0]["runs"][0].update(checks=True),
            lambda p: p["profiles"][0].update(version=""),
            lambda p: p["sources"].update({sanitizer.SOURCES[1]: "0" * 64}),
            lambda p: p["compiler_flags"].remove("-fsanitize=address,undefined"),
            lambda p: p.update(schema=2),
            lambda p: p.update(limitations=[]),
            lambda p: p.update(untrusted=True),
        )
        for attack in attacks:
            with self.subTest(attack=attack):
                altered = copy.deepcopy(record)
                attack(altered)
                with self.assertRaises(ValueError):
                    sanitizer.validate(altered)

    def test_success_record_parser_rejects_extra_output_or_changes(self) -> None:
        correct = sanitizer.EXPECTED
        line = (f"T068_SANITIZER_OK cases={correct['cases']} checks={correct['checks']} "
                f"rejected={correct['rejected']} covered={correct['covered']} "
                f"changed={correct['changed']} digest={correct['digest']}\n")
        self.assertEqual(sanitizer.result(line), correct)
        for broken in (line + "ASAN_WARNING\n", line.replace("cases=256", "cases=255"),
                       line.replace("rejected=17", "rejected=16"), line.rstrip("\n"),
                       "T068_SANITIZER_OK\n"):
            with self.subTest(line=broken):
                with self.assertRaises(ValueError):
                    sanitizer.result(broken)

    @unittest.skipUnless(shutil.which("g++") and shutil.which("clang++"),
                         "Requires GCC and Clang ASan/UBSan runtimes")
    def test_live_sanitized_native_abis(self) -> None:
        fresh = sanitizer.screen()
        saved = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        sanitizer.validate(fresh)
        self.assertEqual([p["runs"] for p in fresh["profiles"]],
                         [p["runs"] for p in saved["profiles"]])


if __name__ == "__main__":
    unittest.main()
