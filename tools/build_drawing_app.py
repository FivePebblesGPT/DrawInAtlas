#!/usr/bin/env python3
"""Build an Atlas-free standalone Drawing Godot project from canonical sources.

Use --in-place for local development in drawing/; this only modifies the
ignored drawing/addons/drawing staging directory, never canonical addon files.
For release/CI use --output pointing to an external empty directory.
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "drawing"
PACKAGE = ROOT / "addons" / "drawing"


def stage(destination: Path, in_place: bool = False) -> Path:
    """Copy the allowlisted app and canonical package; reject unsafe targets."""
    output = destination.resolve()
    if in_place:
        if output != APP or not APP.is_dir():
            raise ValueError("--in-place only supports the tracked drawing directory")
    elif output == ROOT or ROOT in output.parents or (output.exists() and any(output.iterdir())):
        raise ValueError("Output must be an empty external directory")
    if not output.parent.is_dir():
        raise ValueError("Output parent does not exist")
    sources = [p for p in APP.rglob("*") if p.is_file() and
               (p == APP / "project.godot" or p == APP / "main.tscn" or p == APP / "export_presets.cfg" or
                p.is_relative_to(APP / "scripts") or p.is_relative_to(APP / "tests"))]
    if any(p.is_symlink() for p in sources):
        raise ValueError("App source cannot be a symlink")
    if not in_place:
        for source in sources:
            target = output / source.relative_to(APP)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    staged = output / "addons" / "drawing"
    if in_place and staged.exists():
        shutil.rmtree(staged)
    staged.mkdir(parents=True, exist_ok=True)
    for source in sorted(PACKAGE.iterdir()):
        if source.is_symlink():
            raise ValueError("Package source cannot be a symlink")
        if source.is_file() and source.name.endswith((".gd", ".gd.uid")):
            shutil.copy2(source, staged / source.name)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--in-place", action="store_true")
    target.add_argument("--output", type=Path)
    args = parser.parse_args()
    print(stage(APP if args.in_place else args.output, args.in_place))


if __name__ == "__main__":
    main()
