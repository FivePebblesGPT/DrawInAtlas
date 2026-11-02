#!/usr/bin/env python3
"""Stage a clean Godot consumer from the canonical Drawing package (T-051).

This intentionally does not build the full standalone Drawing application (T-053).
The full canonical source tree is staged byte-for-byte for independent consumers.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "addons" / "drawing"


def stage(output: Path, fixture_name: str = "drawing_contract_consumer") -> Path:
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

    # Strict file-type allowlist: no Atlas application, autoloads, scenes or assets.
    fixture = ROOT / "tests" / "fixtures" / fixture_name
    if fixture_name not in {"drawing_contract_consumer", "drawing_core_consumer"}:
        raise ValueError("Unsupported isolated test consumer")
    sources = {
        source: target / "addons" / "drawing" / source.name
        for source in sorted(PACKAGE.iterdir())
        if source.is_file() and (source.name.endswith(".gd") or source.name.endswith(".gd.uid"))
    }
    sources.update({
        fixture / "project.godot.txt": target / "project.godot",
        fixture / "main.tscn.txt": target / "main.tscn",
        fixture / "main.gd.txt": target / "main.gd",
    })
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
    parser.add_argument("--fixture", choices=("drawing_contract_consumer", "drawing_core_consumer"), default="drawing_contract_consumer")
    args = parser.parse_args()
    print(stage(args.output, args.fixture))


if __name__ == "__main__":
    main()
