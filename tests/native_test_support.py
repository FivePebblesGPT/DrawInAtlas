"""Distinguish the required production engine from opt-in research extensions."""

from pathlib import Path


def experimental_extensions(root: Path) -> list[Path]:
    production = {
        root / "addons/drawing/native/drawing_brush.gdextension",
        root / "drawing/addons/drawing/native/drawing_brush.gdextension",
    }
    return [path for path in root.rglob("*.gdextension")
            if path not in production and ".build" not in path.relative_to(root).parts]
