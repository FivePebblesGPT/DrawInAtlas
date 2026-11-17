#!/usr/bin/env python3
"""Require a built GDExtension and register it before Godot editor import."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

EXTENSION = "res://addons/drawing/native/drawing_brush.gdextension"


def prepare(project: Path) -> Path:
    """Validate native assets and atomically update extension_list.cfg."""
    project = project.resolve()
    if not (project / "project.godot").is_file():
        raise ValueError(f"Not a Godot project: {project}")
    native = project / "addons/drawing/native"
    manifest = native / "drawing_brush.gdextension"
    binary = native / "bin/libdrawing_brush.so"
    for path in (manifest, binary):
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Required Brush/Eraser extension is missing or unsafe: {path}")
    text = manifest.read_text(encoding="utf-8")
    if (
        'entry_symbol = "gdext_rust_init"' not in text
        or "res://addons/drawing/native/bin/libdrawing_brush.so" not in text
    ):
        raise ValueError(f"GDExtension ABI or library mapping invalid: {manifest}")
    cache = project / ".godot"
    cache.mkdir(exist_ok=True)
    destination = cache / "extension_list.cfg"
    lines = destination.read_text(encoding="utf-8").splitlines() if destination.exists() else []
    lines = [line.strip() for line in lines if line.strip()]
    if EXTENSION not in lines:
        lines.append(EXTENSION)
    contents = "\n".join(lines) + "\n"
    if destination.is_file() and destination.read_text(encoding="utf-8") == contents:
        return destination
    temporary = destination.with_suffix(".cfg.tmp")
    temporary.write_text(contents, encoding="utf-8")
    os.replace(temporary, destination)
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    try:
        print(prepare(args.project))
    except ValueError as exc:
        parser.exit(1, f"native setup: {exc}\n")


if __name__ == "__main__":
    main()
