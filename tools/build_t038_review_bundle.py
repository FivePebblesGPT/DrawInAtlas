#!/usr/bin/env python3
"""Create a deterministic, tracked-source-only reviewer bundle for T-038.

The archive contains code, not project documentation, Git metadata or fonts.
Run from a clean checkout so the scope matches the recorded commit.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PREFIXES = (
    "scripts/",
    "tests/",
    "prefab/",
    "addons/drawing/",
    "drawing/scripts/",
    "drawing/tests/",
    "tools/benchmarks/",
)
SOURCE_SUFFIXES = {".gd", ".tscn", ".cpp", ".h", ".hpp"}


def selected_source_paths(root: Path) -> list[Path]:
    """Return a sorted allowlist of tracked, ordinary source files.

    Parameters
    ----------
    root : Path
        Git repository root to bundle.

    Returns
    -------
    list[Path]
        Repo-relative paths matching the narrow source-only scope.

    Raises
    ------
    ValueError
        A selected path is a symlink, unreadable or missing.
    """
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True,
        check=True,
    )
    paths: list[Path] = []
    for raw in result.stdout.split(b"\0"):
        if not raw:
            continue
        rel = Path(raw.decode("utf-8", errors="strict"))
        if not any(rel.as_posix().startswith(prefix) for prefix in SOURCE_PREFIXES):
            continue
        if rel.suffix not in SOURCE_SUFFIXES:
            continue
        candidate = root / rel
        if candidate.is_symlink() or not candidate.is_file():
            raise ValueError(f"Non-regular source file: {rel}")
        paths.append(rel)
    return sorted(paths, key=lambda path: path.as_posix())


def build_bundle(root: Path, destination: Path) -> int:
    """Build the source-only ZIP without modifying the working tree."""
    paths = selected_source_paths(root)
    if not paths:
        raise ValueError("No tracked source files found")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for rel in paths:
            info = ZipInfo(rel.as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, (root / rel).read_bytes(), compress_type=ZIP_DEFLATED)
    return len(paths)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Destination ZIP path")
    args = parser.parse_args()
    number = build_bundle(ROOT, args.output.resolve())
    print(f"T038_SOURCE_ONLY_BUNDLE_PASSED ({number} tracked code files)")


if __name__ == "__main__":
    main()
