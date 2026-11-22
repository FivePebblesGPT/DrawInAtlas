"""T-263: exercise the real Make live-stroke recipe under its declared shell.

The fixture replaces only native build/import prerequisites and external tool
processes; it keeps the original Make recipe, pipelines, and verifier order.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LiveStrokeMakeShellTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="t263-live-make-")
        self.addCleanup(self.temp_dir.cleanup)
        self.tmp = Path(self.temp_dir.name)
        self.calls = self.tmp / "calls.txt"
        self.restricted_shell = self._script(
            "posix-sh-without-pipefail",
            """#!/bin/sh
# Emulate older POSIX shells that reject the bash-specific pipefail option.
case "$*" in
  *pipefail*) echo 'pipefail is not available in this shell' >&2; exit 97 ;;
esac
exec /bin/sh "$@"
""",
        )
        self.shell_injection = self.tmp / "older-shell.mk"
        self.shell_injection.write_text(f"SHELL := {self.restricted_shell}\n")
        self.override = self.tmp / "override.mk"
        self.override.write_text(
            "# Only the native prerequisites are stubbed; the real target is retained.\n"
            "native stage-drawing import-drawing import-atlas:\n\t@:\n"
        )
        self.tool = self._script(
            "fake-tool",
            """#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$T263_CALLS"
case "$*" in
  *live_stroke_smoke.gd*)
    if [ "${T263_MODE:-}" = model-crash ]; then exit 41; fi
    echo 'T085_MODEL_PASSED'
    ;;
  *live_stroke_native.gd*)
    if [ "${T263_MODE:-}" = native-crash ]; then exit 42; fi
    echo 'T085_NATIVE_PASSED'
    ;;
  *) exit 43 ;;
esac
""",
        )
        self.checker = self._script(
            "fake-python",
            """#!/bin/sh
set -eu
printf 'check:%s\\n' "$1" >> "$T263_CALLS"
if [ "${T263_MODE:-}" = verifier-crash ] && [ "$1" = tools/check_native_t085_log.py ]; then
  exit 44
fi
if [ "${T263_MODE:-}" = model-crash ] || [ "${T263_MODE:-}" = native-crash ]; then
  # Deliberately accept a missing marker: only pipefail catches this.
  exit 0
fi
case "$1" in
  tools/check_godot_model_log.py) grep -qx T085_MODEL_PASSED "$2" ;;
  tools/check_native_t085_log.py) grep -qx T085_NATIVE_PASSED "$2" ;;
  *) exit 45 ;;
esac
""",
        )
        self._script(
            "xvfb-run",
            """#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
  case "$1" in
    -a|--server-args=*) shift ;;
    *) break ;;
  esac
done
exec "$@"
""",
        )

    def _script(self, name: str, contents: str) -> Path:
        file = self.tmp / name
        file.write_text(contents)
        file.chmod(0o755)
        return file

    def _run_make(self, mode: str = "good", *, restricted_shell: bool = False) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        self.calls.unlink(missing_ok=True)
        env = dict(os.environ)
        env.update(
            PATH=f"{self.tmp}:{env['PATH']}",
            T263_CALLS=str(self.calls),
            T263_MODE=mode,
        )
        args = [
            "make", "--no-print-directory",
            *(["-f", str(self.shell_injection)] if restricted_shell else []),
            "-f", "Makefile", "-f", str(self.override),
            "test-live-stroke", f"WITH_TOOL={self.tool}", f"PYTHON={self.checker}",
        ]
        result = subprocess.run(args, cwd=ROOT, env=env, text=True,
                                capture_output=True, timeout=30, check=False)
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        return result, calls

    def test_successful_model_and_x11_commands_reach_both_verifiers(self) -> None:
        result, calls = self._run_make()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 4, calls)
        self.assertIn("res://tests/live_stroke_smoke.gd", calls[0])
        self.assertEqual(calls[1], "check:tools/check_godot_model_log.py")
        self.assertIn("res://tests/live_stroke_native.gd", calls[2])
        self.assertEqual(calls[3], "check:tools/check_native_t085_log.py")

    def test_bash_specific_recipe_overrides_older_posix_shell(self) -> None:
        result, calls = self._run_make(restricted_shell=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 4, calls)

    def test_headless_failure_does_not_get_masked_by_tee_or_checker(self) -> None:
        result, calls = self._run_make("model-crash")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1, calls)
        self.assertIn("res://tests/live_stroke_smoke.gd", calls[0])

    def test_x11_failure_does_not_get_masked_by_tee_or_checker(self) -> None:
        result, calls = self._run_make("native-crash")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 3, calls)
        self.assertIn("res://tests/live_stroke_native.gd", calls[2])

    def test_verifier_failure_aborts_the_target(self) -> None:
        result, calls = self._run_make("verifier-crash")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 4, calls)
        self.assertEqual(calls[-1], "check:tools/check_native_t085_log.py")


if __name__ == "__main__":
    unittest.main()
