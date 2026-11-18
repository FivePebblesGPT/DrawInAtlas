#!/usr/bin/env python3
"""Install the required native Rust library beside an exported standalone PCK.

Godot's PCK contains the .gdextension manifest, not the loadable ELF. This
step is separate from the fail-closed release verifier and never overwrites a
mismatched existing library. A Windows export needs its own native ABI gate.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

# Direct CLI execution has tools/ on sys.path, while a package import does not.
# Use one rooted import path so static checking and both modes agree.
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.benchmarks.t068_release_gate import (  # noqa: E402
    NATIVE_LIBRARY,
    ReleaseError,
    digest,
    inspect_distribution,
    inspect_stage,
)


class PackageError(ValueError):
    """Refuse incomplete or inconsistent native distributions."""


def package(stage: Path, distribution: Path) -> Path:
    """Copy only the pinned-stage native bytes into the exported Linux layout."""
    try:
        stage_info = inspect_stage(stage)
    except ReleaseError as exc:
        raise PackageError(f"Invalid native source stage: {exc}") from exc
    if not distribution.is_dir() or distribution.is_symlink():
        raise PackageError("Linux distribution directory is missing or unsafe")
    source = stage / NATIVE_LIBRARY
    destination = distribution / NATIVE_LIBRARY
    if any(path.is_symlink() for path in (destination, *destination.parents)
           if path == distribution or distribution in path.parents):
        raise PackageError("Native destination cannot follow a symlink")
    if destination.exists():
        if not destination.is_file() or digest(destination) != stage_info["native_library_sha256"]:
            raise PackageError("Existing exported native library differs from staged build")
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".tmp")
        if temporary.exists() or temporary.is_symlink():
            raise PackageError("Temporary exported native destination already exists")
        try:
            shutil.copyfile(source, temporary)
            if digest(temporary) != stage_info["native_library_sha256"]:
                raise PackageError("Exported library checksum mismatch after copy")
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    try:
        inspect_distribution(distribution, "linux")
    except ReleaseError as exc:
        raise PackageError(f"Invalid Linux distribution after packaging: {exc}") from exc
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--linux", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(package(args.stage, args.linux))
    except PackageError as exc:
        parser.exit(1, f"Native Linux packaging failed: {exc}\n")


if __name__ == "__main__":
    main()
