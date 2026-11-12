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


def stage(destination: Path, in_place: bool = False, *, without_native: bool = False) -> Path:
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
    fonts = PACKAGE / "fonts"
    (staged / "fonts").mkdir(exist_ok=True)
    for source in fonts.iterdir():
        if source.is_symlink():
            raise ValueError("Bundled fonts must not be symbolic links")
        if source.is_file() and source.suffix in {".ttf", ".txt"}:
            shutil.copy2(source, staged / "fonts" / source.name)
    # The icon-only Drawing tool rail must work in staged/exported consumers;
    # its SVGs are packaged with the canonical engine rather than Atlas assets.
    icons = PACKAGE / "icons"
    icon_destination = staged / "icons"
    icon_destination.mkdir(parents=True, exist_ok=True)
    # License follows the six MIT at-icons SVGs in every isolated consumer.
    license_file = icons / "LICENSE.at-icons.txt"
    if license_file.is_symlink() or not license_file.is_file():
        raise ValueError("Drawing icon attribution is missing or unsafe")
    shutil.copy2(license_file, icon_destination / license_file.name)
    for source in sorted(icons.glob("*.svg")):
        if source.is_symlink():
            raise ValueError("Drawing icons must not be symbolic links")
        shutil.copy2(source, icon_destination / source.name)
    # Preset text is deliberately small and platform-neutral. Its upstream
    # attribution must accompany every separately staged Drawing application.
    brushes = PACKAGE / "brushes"
    if brushes.exists():
        if brushes.is_symlink() or not brushes.is_dir():
            raise ValueError("Invalid bundled brush directory")
        brush_destination = staged / "brushes"
        brush_destination.mkdir(exist_ok=True)
        for source in brushes.iterdir():
            if source.is_symlink():
                raise ValueError("Bundled brushes cannot be symbolic links")
            if source.is_file() and source.suffix in {".myb", ".dep5", ".md"}:
                shutil.copy2(source, brush_destination / source.name)

    # The optional GDExtension is only registered when its Linux binary was
    # actually built. Never ship a manifest with a broken missing-library path.
    native = PACKAGE / "native"
    manifest = native / "drawing_brush.gdextension"
    binary = native / "bin" / "libdrawing_brush.so"
    if native.is_symlink() or manifest.is_symlink() or binary.is_symlink():
        raise ValueError("Native extension paths cannot be symbolic links")
    if not without_native and manifest.exists() != binary.exists():
        raise ValueError("Native extension manifest and library must be staged together")
    if not without_native and manifest.exists():
        native_destination = staged / "native"
        (native_destination / "bin").mkdir(parents=True, exist_ok=True)
        shutil.copy2(manifest, native_destination / manifest.name)
        shutil.copy2(binary, native_destination / "bin" / binary.name)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--in-place", action="store_true")
    target.add_argument("--output", type=Path)
    parser.add_argument("--without-native", action="store_true",
                        help="Produce a portable Drawing consumer without optional native binaries")
    args = parser.parse_args()
    print(stage(APP if args.in_place else args.output, args.in_place,
                without_native=args.without_native))


if __name__ == "__main__":
    main()
