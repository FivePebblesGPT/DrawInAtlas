#!/usr/bin/env python3
"""Stage a clean Godot consumer from the canonical Drawing package (T-051).

This intentionally does not build the full standalone Drawing application (T-053).
Only a small, real package primitive and a third-party consumer are shipped.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "drawing" / "package"
FIXTURE = ROOT / "tests" / "fixtures" / "drawing_contract_consumer"


def stage(output: Path) -> Path:
    """Copy the allowlisted package and consumer sources into an external project.

    Parameters
    ----------
    output:
        Empty, existing directory outside the repository root. Its parent must
        exist; the caller owns the resulting directory and may delete it.

    Returns
    -------
    Path
        Path to the staged project.

    Raises
    ------
    ValueError
        When the destination is unsafe or already contains files.
    """
    target = output.resolve()
    if target == ROOT or ROOT in target.parents:
        raise ValueError("Staging inside the Atlas checkout risks res:// collisions")
    if target.exists() and (not target.is_dir() or any(target.iterdir())):
        raise ValueError("Target must be absent or an empty directory")
    if not target.parent.is_dir():
        raise ValueError("Target parent does not exist")

    # Strict allowlist: no Atlas application, autoloads, plugins, scenes or assets.
    sources = {
        PACKAGE / "signed_tiles.gd": target / "addons" / "drawing" / "signed_tiles.gd",
        FIXTURE / "project.godot.txt": target / "project.godot",
        FIXTURE / "main.tscn.txt": target / "main.tscn",
        FIXTURE / "main.gd.txt": target / "main.gd",
    }
    for source in sources:
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Required source must be a regular file: {source}")

    for source, destination in sources.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="External empty directory")
    args = parser.parse_args()
    print(stage(args.output))


if __name__ == "__main__":
    main()
