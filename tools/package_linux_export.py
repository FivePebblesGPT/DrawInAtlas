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


def _preflight_unpacked_export(distribution: Path, source: Path, engine_copy: Path | None) -> None:
    """Validate a would-be native package without publishing to the export.

    Hardlink the existing ELF/PCK into a disposable sibling on the *same*
    filesystem so even very large packs do not need another full copy.
    The required library is linked only into this disposable projection.
    """
    # Inspect every entry (including empty directories and special nodes),
    # not only regular files. This is the same exact-tree rule as the final gate.
    try:
        inspect_distribution_entries(distribution, "linux", allow_missing_native=True,
                                     engine_copied_native=engine_copy is not None)
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


def _normalize_reexport(distribution: Path, destination: Path, engine_copy: Path,
                        expected_digest: str) -> Path:
    """Normalize a repeat Godot export without dropping the known-good native ELF.

    The engine can emit the same root-level library again when exporting into
    an already packaged directory. Validate the *exact* two-library layout,
    preflight its final one-library projection and roll back the root copy on
    any late inspection error. Never remove unrelated or mismatched bytes.
    """
    try:
        inspect_distribution_entries(
            distribution, "linux", allow_missing_native=True,
            engine_copied_native=True, preexisting_native=True,
        )
    except ReleaseError as exc:
        raise PackageError(f"Invalid re-export layout: {exc}") from exc
    if digest(engine_copy) != expected_digest:
        raise PackageError("Engine-copied native library differs from staged build")

    try:
        with tempfile.TemporaryDirectory(prefix=".native-reexport-", dir=distribution.parent) as work:
            workspace = Path(work)
            projection = workspace / "projection"
            projection.mkdir()
            for filename in (BINARY["linux"], "Drawing.pck", NATIVE_LIBRARY.as_posix()):
                target = projection / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                os.link(distribution / filename, target)
            inspect_distribution(projection, "linux")
            backup = workspace / engine_copy.name
            os.replace(engine_copy, backup)
            try:
                inspect_distribution(distribution, "linux")
            except (ReleaseError, OSError):
                os.replace(backup, engine_copy)
                raise
    except (ReleaseError, OSError) as exc:
        raise PackageError(f"Invalid Linux distribution after re-export: {exc}") from exc
    return destination


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
    root_copy = distribution / NATIVE_LIBRARY.name
    if destination.exists():
        if not destination.is_file() or digest(destination) != stage_info["native_library_sha256"]:
            raise PackageError("Existing exported native library differs from staged build")
        if root_copy.exists() or root_copy.is_symlink():
            return _normalize_reexport(
                distribution, destination, root_copy, stage_info["native_library_sha256"]
            )
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
    engine_copy = root_copy if root_copy.exists() or root_copy.is_symlink() else None
    try:
        _preflight_unpacked_export(distribution, source, engine_copy)
        if engine_copy is not None and digest(engine_copy) != stage_info["native_library_sha256"]:
            raise PackageError("Engine-copied native library differs from staged build")
        for directory in reversed(created_dirs):
            directory.mkdir()
        if engine_copy is not None:
            os.replace(engine_copy, destination)
            installed = True
            inspect_distribution(distribution, "linux")
            return destination
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
            if engine_copy is not None:
                os.replace(destination, engine_copy)
            else:
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
