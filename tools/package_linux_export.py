#!/usr/bin/env python3
"""Install the required native Rust library beside an exported standalone PCK.

Godot's PCK contains the .gdextension manifest, not the loadable ELF. This
step is separate from the fail-closed release verifier and never overwrites a
mismatched existing library. A Windows export needs its own native ABI gate.
"""

from __future__ import annotations

import argparse
import errno
import os
import shutil
import sys
import tempfile
from pathlib import Path

# Direct CLI execution has tools/ on sys.path, while a package import does not.
# Use one rooted import path so static checking and both modes agree.
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.benchmarks.t068_release_gate import (  # noqa: E402
    BINARY,
    NATIVE_LIBRARY,
    ReleaseError,
    digest,
    inspect_distribution,
    inspect_distribution_entries,
    inspect_stage,
)


class PackageError(ValueError):
    """Refuse incomplete or inconsistent native distributions."""


def _preflight_unpacked_export(distribution: Path, source: Path) -> None:
    """Validate a would-be native package without publishing to the export.

    Hardlink the existing ELF/PCK into a disposable sibling on the *same*
    filesystem so even very large packs do not need another full copy.
    The required library is linked only into this disposable projection.
    """
    # Inspect every entry (including empty directories and special nodes),
    # not only regular files. This is the same exact-tree rule as the final gate.
    try:
        inspect_distribution_entries(distribution, "linux", allow_missing_native=True)
    except ReleaseError as exc:
        raise PackageError(f"Invalid pre-package export layout: {exc}") from exc
    expected = {BINARY["linux"], "Drawing.pck"}
    with tempfile.TemporaryDirectory(prefix=".native-preflight-", dir=distribution) as work:
        temporary_distribution = Path(work)
        for filename in sorted(expected):
            os.link(distribution / filename, temporary_distribution / filename)
        native = temporary_distribution / NATIVE_LIBRARY
        native.parent.mkdir(parents=True)
        try:
            os.link(source, native)
        except OSError as exc:
            if exc.errno != errno.EXDEV:
                raise
            shutil.copyfile(source, native)
        inspect_distribution(temporary_distribution, "linux")


def package(stage: Path, distribution: Path) -> Path:
    """Install an exact native ELF, leaving rejected distributions unchanged."""
    try:
        stage_info = inspect_stage(stage)
    except ReleaseError as exc:
        raise PackageError(f"Invalid native source stage: {exc}") from exc
    if not distribution.is_dir() or distribution.is_symlink():
        raise PackageError("Linux distribution directory is missing or unsafe")
    source = stage / NATIVE_LIBRARY
    destination = distribution / NATIVE_LIBRARY
    if any(
        path.is_symlink()
        for path in (destination, *destination.parents)
        if path == distribution or distribution in path.parents
    ):
        raise PackageError("Native destination cannot follow a symlink")
    if destination.exists():
        if not destination.is_file() or digest(destination) != stage_info["native_library_sha256"]:
            raise PackageError("Existing exported native library differs from staged build")
        try:
            inspect_distribution(distribution, "linux")
        except ReleaseError as exc:
            raise PackageError(f"Invalid Linux distribution after packaging: {exc}") from exc
        return destination

    # Failed PCK, executable, or unexpected-artifact validation must never
    # install a new native library into a rejected export.
    created_dirs: list[Path] = []
    parent = destination.parent
    while parent != distribution:
        if not parent.exists():
            created_dirs.append(parent)
        parent = parent.parent
    installed = False
    temporary: Path | None = None
    try:
        _preflight_unpacked_export(distribution, source)
        for directory in reversed(created_dirs):
            directory.mkdir()
        # Reserve a fresh, exclusive temporary file. A fixed .so.tmp name
        # could belong to another process or be an invalid pre-existing export
        # entry; failed packaging must never remove someone else's bytes.
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
        )
        temporary = Path(temporary_name)
        with os.fdopen(descriptor, "wb") as output_stream, source.open("rb") as input_stream:
            shutil.copyfileobj(input_stream, output_stream)
        # mkstemp starts at 0600; restore the staged library's permissions so
        # a valid export remains readable by consumers running as other users.
        shutil.copymode(source, temporary)
        if digest(temporary) != stage_info["native_library_sha256"]:
            raise PackageError("Exported library checksum mismatch after copy")
        os.replace(temporary, destination)
        installed = True
        inspect_distribution(distribution, "linux")
    except (ReleaseError, OSError, PackageError) as exc:
        # A post-install inspector failure must not leak even a valid native
        # binary into a rejected distribution. Preserve any prior export.
        if installed:
            destination.unlink(missing_ok=True)
        if isinstance(exc, PackageError):
            raise
        raise PackageError(f"Invalid Linux distribution after packaging: {exc}") from exc
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        # Only remove directories this invocation created.
        for directory in created_dirs:
            try:
                directory.rmdir()
            except OSError:
                pass
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
