#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13,<3.14"
# dependencies = ["zstandard>=0.23,<1"]
# ///
"""Transport git-format-patch mailboxes and their Git LFS objects offline.

Runs under Python 3.13 with a uv-managed zstandard dependency. When invoked
with an already-configured Python interpreter, the `zstd` executable is an
optional fallback for environments where the Python package is unavailable.

The default bundle is a streaming TAR+Zstandard .lfsmbox.tar.zst archive.
Legacy .lfsmbox ZIP64 archives remain readable and can be created using
--format zip. The original mailbox is preserved byte-for-byte.

Sender:
    git format-patch --stdout origin/main..HEAD > changes.mbox
    ./git_lfs_mbox.py pack changes.mbox --repo .

Receiver:
    git lfs install --local
    ./git_lfs_mbox.py unpack changes.lfsmbox.tar.zst --repo . --apply
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
from typing import BinaryIO, Iterator
import tempfile
import zipfile
import zlib

try:
    import zstandard as zstd
except ImportError:  # Direct Python invocation can fall back to the zstd CLI.
    zstd = None

FORMAT_NAME = "git-lfs-mbox"
FORMAT_VERSION = 1
DEFAULT_EXTENSION = ".lfsmbox.tar.zst"
MBX_ENTRY = "patches.mbox"
MANIFEST_ENTRY = "manifest.json"
BUF_SIZE = 1024 * 1024
MAX_MANIFEST_BYTES = 8 * 1024 * 1024
OID_RE = re.compile(rb"^\+oid sha256:([0-9a-f]{64})\r?\n?$")
VALID_OID_RE = re.compile(r"[0-9a-f]{64}\Z")
HUNK_RE = re.compile(rb"^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(?: |\r|\n|$)")


class BundleError(Exception):
    """Invalid or incomplete LFS patch bundle."""


@dataclass(frozen=True, slots=True)
class LfsObject:
    oid: str
    size: int
    included: bool

    def archive_name(self) -> str:
        return f"objects/{self.oid}"

    def local_path(self, store: Path) -> Path:
        return store / self.oid[:2] / self.oid[2:4] / self.oid


def git(repo: Path, *args: str, optional: bool = False) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        raise BundleError("Git is required but was not found in PATH") from exc
    if result.returncode:
        if optional:
            return None
        raise BundleError(
            f"git {' '.join(args)} failed in {repo}: "
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout.strip()


def find_lfs_store(repo: Path, override: Path | None) -> Path:
    if override is not None:
        return override.expanduser().resolve()
    root = Path(git(repo, "rev-parse", "--show-toplevel") or ".").resolve()
    env = git(root, "lfs", "env", optional=True)
    if env:
        for line in env.splitlines():
            if line.startswith("LocalMediaDir="):
                media_dir = Path(line.partition("=")[2]).expanduser()
                if not media_dir.is_absolute():
                    media_dir = root / media_dir
                return media_dir.resolve()
    # Works without Git LFS for standard repositories, including linked worktrees.
    result = git(root, "rev-parse", "--path-format=absolute", "--git-path", "lfs/objects")
    assert result is not None
    return Path(result).resolve()


def added_lfs_oids(mbox_path: Path) -> set[str]:
    """Find added pointer OID lines *inside unified Git diff hunks*.

    Detecting +oid lines (rather than complete pointer blocks) also handles
    one-line LFS pointer edits where the version and size are unchanged, and
    format-patch produced with --unified=0. Lines in commit messages, removed
    lines, and mail headers are intentionally ignored.
    """
    found: set[str] = set()
    in_diff = False
    in_hunk = False
    old_left = 0
    new_left = 0
    with mbox_path.open("rb") as stream:
        for line in stream:
            if line.startswith(b"diff --git "):
                in_diff = True
                in_hunk = False
                continue
            if not in_diff:
                continue
            match = HUNK_RE.match(line)
            if match:
                # Track line counts so diff-like text *inside* a hunk is not
                # mistaken for the start of another Git diff or patch header.
                header = match.group(0)
                head = re.match(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", header)
                assert head is not None
                old_left = int(head.group(2) or b"1")
                new_left = int(head.group(4) or b"1")
                in_hunk = True
                continue
            if not in_hunk:
                continue
            if line.startswith(b"\\ No newline at end of file"):
                continue
            if old_left == 0 and new_left == 0:
                in_hunk = False
                continue
            if line.startswith(b"+"):
                if new_left <= 0:
                    raise BundleError("Malformed mailbox: extra addition beyond hunk length")
                new_left -= 1
                match = OID_RE.fullmatch(line)
                if match:
                    found.add(match.group(1).decode("ascii"))
            elif line.startswith(b"-"):
                if old_left <= 0:
                    raise BundleError("Malformed mailbox: extra deletion beyond hunk length")
                old_left -= 1
            elif line.startswith(b" "):
                if old_left <= 0 or new_left <= 0:
                    raise BundleError("Malformed mailbox: excess context in hunk")
                old_left -= 1
                new_left -= 1
            else:
                # A Git binary patch or any other non-hunk section.
                in_hunk = False
    return found


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(BUF_SIZE):
            digest.update(chunk)
            total += len(chunk)
    return digest.hexdigest(), total


def verify_local_object(path: Path, spec: LfsObject) -> bool:
    if not path.is_file():
        return False
    if path.stat().st_size != spec.size:
        return False
    digest, size = sha256_file(path)
    return digest == spec.oid and size == spec.size


def load_have(path: Path | None) -> set[str]:
    if path is None:
        return set()
    seen: set[str] = set()
    with path.open("r", encoding="ascii") as stream:
        for lineno, line in enumerate(stream, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if not VALID_OID_RE.fullmatch(line):
                raise BundleError(f"Invalid SHA-256 object ID in {path}:{lineno}")
            seen.add(line)
    return seen


def compression_for(path: Path) -> int:
    """Avoid wasting CPU recompressing JPEG/MP4/archives and similar files."""
    with path.open("rb") as stream:
        sample = stream.read(256 * 1024)
    if len(sample) < 1024:
        return zipfile.ZIP_STORED
    compressed = zlib.compress(sample, level=1)
    return zipfile.ZIP_DEFLATED if len(compressed) < len(sample) * 0.95 else zipfile.ZIP_STORED


def zip_stream_file(
    archive: zipfile.ZipFile,
    entry: str,
    path: Path,
    compression: int,
) -> tuple[str, int]:
    info = zipfile.ZipInfo(entry)
    info.compress_type = compression
    info.external_attr = 0o100600 << 16
    digest = hashlib.sha256()
    count = 0
    with path.open("rb") as src, archive.open(info, "w", force_zip64=True) as dest:
        while block := src.read(BUF_SIZE):
            dest.write(block)
            digest.update(block)
            count += len(block)
    return digest.hexdigest(), count


def write_atomic_text(path: Path, value: str, *, force: bool) -> None:
    path = path.expanduser().resolve()
    if path.exists() and not force:
        raise BundleError(f"Refusing to overwrite {path} (use --force)")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".lfsmbox-", delete=False) as out:
            temporary = Path(out.name)
            out.write(value)
        os.replace(temporary, path)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)



def bundle_kind(path: Path) -> str:
    """Detect container format from magic bytes, never from its suffix."""
    with path.open("rb") as source:
        magic = source.read(4)
    if magic == b"\x28\xb5\x2f\xfd":
        return "zst"
    if magic[:2] == b"PK":
        return "zip"
    raise BundleError("Unknown bundle format: expected Zstandard TAR or legacy ZIP64")


def default_mailbox_name(bundle: Path) -> str:
    name = bundle.name
    for suffix in (".lfsmbox.tar.zst", ".lfsmbox.zst", ".tar.zst", ".lfsmbox", ".zst"):
        if name.endswith(suffix):
            return name[: -len(suffix)] + ".mbox"
    return bundle.stem + ".mbox"


def require_zstd_binary() -> str:
    binary = shutil.which("zstd")
    if binary is None:
        raise BundleError(
            "Zstandard support requires the uv-managed 'zstandard' Python package "
            "or the zstd executable on PATH. Run the script through its uv shebang."
        )
    return binary


@contextmanager
def zstd_writer(path: Path, level: int) -> Iterator[BinaryIO]:
    """Yield a streaming Zstandard writer; uv's Python package is preferred."""
    if zstd is not None:
        with path.open("wb") as dest:
            with zstd.ZstdCompressor(level=level, write_checksum=True).stream_writer(
                dest, closefd=False
            ) as writer:
                yield writer
        return
    binary = require_zstd_binary()
    with path.open("wb") as dest:
        proc = subprocess.Popen(
            [binary, f"-{level}", "-q", "-c"], stdin=subprocess.PIPE,
            stdout=dest, stderr=subprocess.PIPE,
        )
        try:
            assert proc.stdin is not None and proc.stderr is not None
            yield proc.stdin
            proc.stdin.close()
            error = proc.stderr.read().decode("utf-8", "replace").strip()
            if proc.wait() != 0:
                raise BundleError(f"Zstandard compression failed: {error}")
        except BaseException:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
            raise
        finally:
            if proc.stdin is not None and not proc.stdin.closed:
                proc.stdin.close()
            if proc.stderr is not None:
                proc.stderr.close()


@contextmanager
def zstd_reader(path: Path) -> Iterator[BinaryIO]:
    """Yield a streaming Zstandard decoder and validate full compressed input."""
    if zstd is not None:
        with path.open("rb") as source:
            with zstd.ZstdDecompressor().stream_reader(
                source, read_across_frames=True, closefd=False
            ) as reader:
                yield reader
                # Validate any checksum at the end of the frame; reject huge junk
                # following the TAR end marker instead of processing unbounded data.
                drain_zstd_trailer(reader)
        return
    binary = require_zstd_binary()
    proc = subprocess.Popen(
        [binary, "-d", "-q", "-c", str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    try:
        assert proc.stdout is not None and proc.stderr is not None
        yield proc.stdout
        drain_zstd_trailer(proc.stdout)
        proc.stdout.close()
        error = proc.stderr.read().decode("utf-8", "replace").strip()
        if proc.wait() != 0:
            raise BundleError(f"Zstandard decompression failed: {error}")
    except BaseException:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        raise
    finally:
        if proc.stdout is not None:
            proc.stdout.close()
        if proc.stderr is not None:
            proc.stderr.close()


def drain_zstd_trailer(source: BinaryIO) -> None:
    remaining_limit = 1024 * 1024
    while chunk := source.read(min(BUF_SIZE, remaining_limit + 1)):
        remaining_limit -= len(chunk)
        if remaining_limit < 0:
            raise BundleError("Oversized trailing data after TAR end marker")


def parse_manifest_data(raw: bytes) -> tuple[dict, list[LfsObject]]:
    """Validate the shared manifest used by both ZIP and TAR+Zstandard."""
    if len(raw) > MAX_MANIFEST_BYTES:
        raise BundleError("Manifest exceeds maximum size")
    try:
        manifest = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as exc:
        raise BundleError("Malformed JSON manifest") from exc
    if (not isinstance(manifest, dict) or manifest.get("format") != FORMAT_NAME
            or type(manifest.get("version")) is not int
            or manifest["version"] != FORMAT_VERSION):
        raise BundleError("Unknown or unsupported bundle format/version")
    metadata = manifest.get("mbox")
    if (not isinstance(metadata, dict) or metadata.get("name") != MBX_ENTRY
            or not isinstance(metadata.get("original_name"), str)
            or not isinstance(metadata.get("sha256"), str)
            or not VALID_OID_RE.fullmatch(metadata["sha256"])
            or type(metadata.get("size")) is not int or metadata["size"] < 0):
        raise BundleError("Invalid mailbox metadata")
    records = manifest.get("objects")
    if not isinstance(records, list):
        raise BundleError("Malformed objects list")
    objects: list[LfsObject] = []
    previous_oid = ""
    for record in records:
        if not isinstance(record, dict):
            raise BundleError("Invalid object record")
        oid, size, included = record.get("oid"), record.get("size"), record.get("included")
        if (not isinstance(oid, str) or not VALID_OID_RE.fullmatch(oid)
                or type(size) is not int or size < 0 or type(included) is not bool):
            raise BundleError("Invalid object ID, size, or inclusion flag")
        if oid <= previous_oid:
            raise BundleError("Object IDs must be sorted and unique")
        objects.append(LfsObject(oid, size, included))
        previous_oid = oid
    return manifest, objects


def manifest_for(mbox: Path, mbox_sha: str, mbox_size: int,
                 specs: list[LfsObject]) -> dict:
    return {
        "format": FORMAT_NAME,
        "version": FORMAT_VERSION,
        "mbox": {
            "name": MBX_ENTRY,
            "original_name": mbox.name,
            "sha256": mbox_sha,
            "size": mbox_size,
        },
        "objects": [
            {"oid": spec.oid, "size": spec.size, "included": spec.included}
            for spec in specs
        ],
    }


def manifest_bytes(manifest: dict) -> bytes:
    return json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def parse_tar_manifest(raw: bytes) -> tuple[dict, list[LfsObject], str | None]:
    """Normalize the alternate DrawInAtlas exporter metadata for verification."""
    if len(raw) > MAX_MANIFEST_BYTES:
        raise BundleError("Manifest exceeds maximum size")
    try:
        metadata = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as exc:
        raise BundleError("Malformed JSON manifest") from exc
    if not isinstance(metadata, dict) or metadata.get("format") != "drawinatlas-git-lfs-mbox-v1":
        manifest, objects = parse_manifest_data(raw)
        return manifest, objects, None
    diff_sha = metadata.get("complete_diff_sha256")
    if not isinstance(diff_sha, str) or not VALID_OID_RE.fullmatch(diff_sha):
        raise BundleError("Invalid complete diff checksum")
    pointers = metadata.get("lfs_pointers")
    if not isinstance(pointers, list):
        raise BundleError("Malformed LFS pointers list")
    by_oid: dict[str, LfsObject] = {}
    for pointer in pointers:
        if not isinstance(pointer, dict):
            raise BundleError("Invalid LFS pointer record")
        oid, size = pointer.get("oid"), pointer.get("size")
        if (not isinstance(oid, str) or not VALID_OID_RE.fullmatch(oid)
                or type(size) is not int or size < 0):
            raise BundleError("Invalid LFS pointer ID or size")
        spec = LfsObject(oid, size, True)
        if oid in by_oid and by_oid[oid] != spec:
            raise BundleError("Inconsistent sizes for duplicate LFS pointer")
        by_oid[oid] = spec
    if (type(metadata.get("lfs_object_count")) is not int
            or metadata["lfs_object_count"] != len(by_oid)):
        raise BundleError("LFS object count disagrees with pointers")
    # This exporter records hashes but leaves mailbox size in the TAR header.
    normalized = manifest_for(Path("commits.mbox"), metadata.get("mailbox_sha256"), 0,
                              [by_oid[oid] for oid in sorted(by_oid)])
    manifest, objects = parse_manifest_data(manifest_bytes(normalized))
    return manifest, objects, diff_sha


class HashingReader:
    """Record the actual bytes supplied to a streaming TAR writer."""

    def __init__(self, source: BinaryIO) -> None:
        self.source = source
        self.sha = hashlib.sha256()
        self.size = 0

    def read(self, size: int = -1) -> bytes:
        chunk = self.source.read(size)
        self.sha.update(chunk)
        self.size += len(chunk)
        return chunk

    def verify(self, oid: str, size: int, *, entry: str) -> None:
        if self.size != size or self.sha.hexdigest() != oid:
            raise BundleError(f"Invalid or modified source {entry}: SHA-256/size mismatch")


def tar_add_bytes(archive: tarfile.TarFile, name: str, data: bytes) -> None:
    member = tarfile.TarInfo(name)
    member.mode = 0o600
    member.size = len(data)
    member.mtime = 0
    archive.addfile(member, io.BytesIO(data))


def tar_add_verified(archive: tarfile.TarFile, name: str, source: Path,
                     sha: str, size: int) -> None:
    member = tarfile.TarInfo(name)
    member.mode = 0o600
    member.size = size
    member.mtime = 0
    with source.open("rb") as raw:
        reader = HashingReader(raw)
        archive.addfile(member, reader)
        reader.verify(sha, size, entry=str(source))


def write_zst_bundle(temp: Path, mbox: Path, store: Path,
                     specs: list[LfsObject], level: int) -> tuple[str, int]:
    mbox_sha, mbox_size = sha256_file(mbox)
    manifest = manifest_for(mbox, mbox_sha, mbox_size, specs)
    with zstd_writer(temp, level) as compressed:
        with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as tar:
            tar_add_bytes(tar, MANIFEST_ENTRY, manifest_bytes(manifest))
            tar_add_verified(tar, MBX_ENTRY, mbox, mbox_sha, mbox_size)
            for spec in specs:
                if spec.included:
                    tar_add_verified(tar, spec.archive_name(), spec.local_path(store),
                                     spec.oid, spec.size)
    return mbox_sha, mbox_size


def extract_stream_verified(source: BinaryIO, dest: Path, *, sha256: str,
                            size: int, force: bool) -> bool:
    """Verify a stream and atomically materialize it at its destination."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        raise BundleError(f"Refusing to write through a symlink: {dest}")
    spec = LfsObject(sha256, size, True)
    exists_verified = dest.is_file() and verify_local_object(dest, spec)
    if dest.exists() and not exists_verified and not force:
        raise BundleError(f"Existing file differs from verified bundle: {dest} (use --force)")
    temporary: Path | None = None
    try:
        digest = hashlib.sha256()
        count = 0
        with tempfile.NamedTemporaryFile(dir=dest.parent, prefix=".lfsmbox-", delete=False) as out:
            temporary = Path(out.name)
            while chunk := source.read(BUF_SIZE):
                count += len(chunk)
                if count > size:
                    raise BundleError(f"Uncompressed entry exceeds expected size: {dest}")
                digest.update(chunk)
                if not exists_verified:
                    out.write(chunk)
        if count != size or digest.hexdigest() != sha256:
            raise BundleError(f"SHA-256 or size mismatch in archive entry {dest}")
        if exists_verified:
            return False
        os.replace(temporary, dest)
        return True
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def read_zst_bundle(bundle: Path, *, store: Path | None = None,
                    mbox: Path | None = None, force: bool = False) -> tuple[dict, list[LfsObject], int, int]:
    """Validate a stream sequentially; optionally install objects and mailbox.

    The standard format starts with manifest and mailbox, then sorted objects.
    The alternate DrawInAtlas format has a fixed layout with informational
    members and a complete diff. No member paths are used as filesystem paths.
    """
    manifest: dict | None = None
    objects: list[LfsObject] = []
    object_by_name: dict[str, LfsObject] = {}
    expected_order: list[str] = []
    seen: list[str] = []
    manifest_entry = MANIFEST_ENTRY
    mailbox_entry = MBX_ENTRY
    diff_sha: str | None = None
    installed = cached = 0
    temporary: Path | None = None
    try:
        with zstd_reader(bundle) as raw:
            with tarfile.open(fileobj=raw, mode="r|", format=tarfile.PAX_FORMAT) as tar:
                for member in tar:
                    if not member.isfile() or member.name.startswith("/") or                             member.name.startswith("./") or ".." in member.name.split("/"):
                        raise BundleError(f"Unsafe TAR entry: {member.name}")
                    if member.name in (MANIFEST_ENTRY, "bundle.json") and not seen:
                        if member.size > MAX_MANIFEST_BYTES:
                            raise BundleError("Manifest exceeds maximum size")
                        data_source = tar.extractfile(member)
                        assert data_source is not None
                        manifest, objects, diff_sha = parse_tar_manifest(
                            data_source.read(MAX_MANIFEST_BYTES + 1)
                        )
                        manifest_entry = member.name
                        if diff_sha is not None:
                            mailbox_entry = "commits.mbox"
                            expected_order = [manifest_entry, "README.txt", mailbox_entry,
                                              "complete.diff", "git_lfs_mbox.py"]
                            object_by_name = {
                                f"lfs/objects/{obj.oid[:2]}/{obj.oid[2:4]}/{obj.oid}": obj
                                for obj in objects
                            }
                        else:
                            expected_order = [manifest_entry, mailbox_entry]
                            object_by_name = {obj.archive_name(): obj for obj in objects if obj.included}
                        expected_order += list(object_by_name)
                        if store is not None:
                            for obj in objects:
                                if not obj.included and not verify_local_object(obj.local_path(store), obj):
                                    raise BundleError(
                                        f"Missing peer-known LFS object {obj.oid} in {store}\n"
                                        "Request a complete bundle (without --have)."
                                    )
                    if manifest is None:
                        raise BundleError("TAR bundle must start with manifest.json or bundle.json")
                    next_index = len(seen)
                    if next_index >= len(expected_order) or member.name != expected_order[next_index]:
                        raise BundleError(f"Unexpected TAR entry or ordering: {member.name}")
                    if member.name == manifest_entry:
                        seen.append(member.name)
                        continue
                    data_source = tar.extractfile(member)
                    assert data_source is not None
                    if diff_sha is not None and member.name in ("README.txt", "git_lfs_mbox.py"):
                        # Informational members are never extracted or executed.
                        pass
                    elif diff_sha is not None and member.name == "complete.diff":
                        verify_tar_stream(data_source, diff_sha, member.size)
                    elif member.name == mailbox_entry:
                        metadata = manifest["mbox"]
                        if diff_sha is not None:
                            metadata["size"] = member.size
                        if member.size != metadata["size"]:
                            raise BundleError("TAR mailbox size disagrees with manifest")
                        if mbox is not None:
                            mbox.parent.mkdir(parents=True, exist_ok=True)
                            with tempfile.NamedTemporaryFile(
                                dir=mbox.parent, prefix=".lfsmbox-", delete=False,
                            ) as temp_file:
                                temporary = Path(temp_file.name)
                            extract_stream_verified(
                                data_source, temporary, sha256=metadata["sha256"],
                                size=member.size, force=True,
                            )
                            if added_lfs_oids(temporary) != {obj.oid for obj in objects}:
                                raise BundleError("Mailbox LFS pointer IDs do not match bundle manifest")
                        else:
                            verify_tar_stream(data_source, metadata["sha256"], member.size)
                    else:
                        # Incremental manifests may omit objects; find the actual
                        # spec by its validated canonical archive name.
                        obj = object_by_name[member.name]
                        if member.size != obj.size:
                            raise BundleError(f"TAR object size disagrees with manifest: {obj.oid}")
                        if store is not None:
                            if extract_stream_verified(
                                data_source, obj.local_path(store), sha256=obj.oid,
                                size=obj.size, force=force,
                            ):
                                installed += 1
                            else:
                                cached += 1
                        else:
                            verify_tar_stream(data_source, obj.oid, obj.size)
                    seen.append(member.name)
        if manifest is None or seen != expected_order:
            raise BundleError("Incomplete TAR bundle or missing expected entries")
        if mbox is not None:
            assert temporary is not None
            if mbox.exists() and not force:
                raise BundleError(f"Refusing to overwrite {mbox} (use --force)")
            os.replace(temporary, mbox)
        cached += sum(not o.included for o in objects)
        return manifest, objects, installed, cached
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def verify_tar_stream(source: BinaryIO, sha256: str, size: int) -> None:
    digest = hashlib.sha256()
    count = 0
    while chunk := source.read(BUF_SIZE):
        count += len(chunk)
        if count > size:
            raise BundleError("TAR entry exceeds manifest size")
        digest.update(chunk)
    if count != size or digest.hexdigest() != sha256:
        raise BundleError("SHA-256 or size mismatch in TAR archive")

def pack(args: argparse.Namespace) -> None:
    mbox: Path = args.mbox.expanduser().resolve()
    output = args.output or Path(mbox.name.removesuffix(".mbox") + (
        DEFAULT_EXTENSION if args.format == "zst" else ".lfsmbox"
    ))
    out: Path = output.expanduser().resolve()
    if not mbox.is_file():
        raise BundleError(f"Mailbox is not a file: {mbox}")
    if out == mbox:
        raise BundleError("Bundle output cannot replace the input mailbox")
    if out.exists() and not args.force:
        raise BundleError(f"Refusing to overwrite {out} (use --force)")
    repo = args.repo.expanduser().resolve()
    store = find_lfs_store(repo, args.store)
    have = load_have(args.have)
    oids = sorted(added_lfs_oids(mbox))
    specs: list[LfsObject] = []
    for oid in oids:
        local = store / oid[:2] / oid[2:4] / oid
        if not local.is_file():
            raise BundleError(
                f"Missing LFS object {oid}\n  {local}\n"
                "Run 'git lfs fetch' in the sending repository, or check --repo/--store."
            )
        specs.append(LfsObject(oid, local.stat().st_size, oid not in have))
    out.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=out.parent, prefix=".lfsmbox-", delete=False) as tmp:
            temporary = Path(tmp.name)
        if args.format == "zst":
            mbox_sha, mbox_size = write_zst_bundle(temporary, mbox, store, specs, args.level)
        else:
            with zipfile.ZipFile(temporary, "w", allowZip64=True, compresslevel=4) as archive:
                mbox_sha, mbox_size = zip_stream_file(
                    archive, MBX_ENTRY, mbox, zipfile.ZIP_DEFLATED
                )
                for spec in specs:
                    if not spec.included:
                        continue
                    src = spec.local_path(store)
                    digest, size = zip_stream_file(
                        archive, spec.archive_name(), src, compression_for(src)
                    )
                    if digest != spec.oid or size != spec.size:
                        raise BundleError(f"Invalid or modified LFS source {src}")
                archive.writestr(
                    MANIFEST_ENTRY,
                    manifest_bytes(manifest_for(mbox, mbox_sha, mbox_size, specs)),
                    compress_type=zipfile.ZIP_DEFLATED,
                )
        if out.exists() and not args.force:
            raise BundleError(f"Refusing to overwrite {out} (use --force)")
        os.replace(temporary, out)
        print(f"Bundle: {out} ({'TAR+Zstandard' if args.format == 'zst' else 'ZIP64'})")
        print(f"Mailbox: {mbox_size:,} bytes, SHA-256 {mbox_sha}")
        print(f"LFS objects: {len(specs)} referenced, {sum(s.included for s in specs)} bundled, "
              f"{sum(not s.included for s in specs)} omitted via --have")
        print(f"Archive: {out.stat().st_size:,} bytes")
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)

def parse_manifest(archive: zipfile.ZipFile) -> tuple[dict, list[LfsObject]]:
    entries = archive.infolist()
    names = [entry.filename for entry in entries]
    if len(names) != len(set(names)):
        raise BundleError("Archive contains duplicate ZIP entry names")
    if MANIFEST_ENTRY not in names or MBX_ENTRY not in names:
        raise BundleError("Not a git-lfs-mbox bundle (missing manifest or mailbox)")
    if archive.getinfo(MANIFEST_ENTRY).file_size > MAX_MANIFEST_BYTES:
        raise BundleError("Manifest exceeds maximum size")
    raw = archive.read(MANIFEST_ENTRY)
    try:
        manifest = json.loads(raw)
    except (ValueError, UnicodeDecodeError) as exc:
        raise BundleError("Malformed JSON manifest") from exc
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT_NAME or \
       type(manifest.get("version")) is not int or manifest["version"] != FORMAT_VERSION:
        raise BundleError("Unknown or unsupported bundle format/version")
    metadata = manifest.get("mbox")
    if not isinstance(metadata, dict) or metadata.get("name") != MBX_ENTRY:
        raise BundleError("Invalid mailbox metadata")
    if not isinstance(metadata.get("original_name"), str) or \
       not isinstance(metadata.get("sha256"), str) or \
       not VALID_OID_RE.fullmatch(metadata["sha256"]) or \
       type(metadata.get("size")) is not int or metadata["size"] < 0:
        raise BundleError("Invalid mailbox size/checksum in manifest")
    if archive.getinfo(MBX_ENTRY).file_size != metadata["size"]:
        raise BundleError("Mailbox length does not match ZIP metadata")
    records = manifest.get("objects")
    if not isinstance(records, list):
        raise BundleError("Malformed objects list")
    objects: list[LfsObject] = []
    previous_oid = ""
    expected_names = {MANIFEST_ENTRY, MBX_ENTRY}
    for record in records:
        if not isinstance(record, dict):
            raise BundleError("Invalid object record")
        oid, size, included = record.get("oid"), record.get("size"), record.get("included")
        if not isinstance(oid, str) or not VALID_OID_RE.fullmatch(oid) or \
           type(size) is not int or size < 0 or type(included) is not bool:
            raise BundleError("Invalid object ID, size, or inclusion flag")
        if oid <= previous_oid:
            raise BundleError("Object IDs must be sorted and unique")
        previous_oid = oid
        spec = LfsObject(oid, size, included)
        objects.append(spec)
        if included:
            expected_names.add(spec.archive_name())
            if spec.archive_name() not in names:
                raise BundleError(f"Missing bundled object {oid}")
            if archive.getinfo(spec.archive_name()).file_size != size:
                raise BundleError(f"ZIP size disagrees with manifest for {oid}")
    if set(names) != expected_names:
        raise BundleError("Unexpected ZIP entries (potentially unsafe paths or unlisted content)")
    # No special file types; these are data entries only.
    for entry in entries:
        mode = entry.external_attr >> 16
        if entry.is_dir() or (mode & 0o170000) not in (0, 0o100000):
            raise BundleError(f"Unsafe ZIP entry type: {entry.filename}")
        if entry.flag_bits & 1:
            raise BundleError("Encrypted ZIP entries are unsupported")
    return manifest, objects


def extract_verified(
    archive: zipfile.ZipFile, member: str, dest: Path, *, sha256: str,
    size: int, force: bool,
) -> bool:
    """Stream ZIP member to same-filesystem temp and atomically replace dest.

    Return False when an already-valid destination makes extraction unnecessary.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        raise BundleError(f"Refusing to write through a symlink: {dest}")
    spec = LfsObject(sha256, size, True)
    if dest.exists():
        if not dest.is_file():
            raise BundleError(f"Destination is not a regular file: {dest}")
        if verify_local_object(dest, spec):
            return False
        elif not force:
            raise BundleError(f"Existing file differs from verified bundle: {dest} (use --force)")
    tmp_path: Path | None = None
    try:
        digest = hashlib.sha256()
        count = 0
        with tempfile.NamedTemporaryFile(dir=dest.parent, prefix=".lfsmbox-", delete=False) as tmp:
            tmp_path = Path(tmp.name)
            with archive.open(member, "r") as src:
                while block := src.read(BUF_SIZE):
                    count += len(block)
                    if count > size:
                        raise BundleError(f"Uncompressed entry exceeds expected size: {member}")
                    digest.update(block)
                    tmp.write(block)
        if digest.hexdigest() != sha256 or count != size:
            raise BundleError(f"SHA-256 or size mismatch in archive entry {member}")
        os.replace(tmp_path, dest)
        return True
    finally:
        if tmp_path:
            tmp_path.unlink(missing_ok=True)


def unpack(args: argparse.Namespace) -> None:
    bundle = args.bundle.expanduser().resolve()
    repo = args.repo.expanduser().resolve()
    store = find_lfs_store(repo, args.store)
    mbox = args.output.expanduser().resolve() if args.output else \
        Path.cwd() / default_mailbox_name(bundle)
    if bundle == mbox:
        raise BundleError("Cannot overwrite the source bundle")
    if mbox.exists() and not args.force:
        raise BundleError(f"Refusing to overwrite {mbox} (use --force)")
    kind = bundle_kind(bundle)
    if kind == "zst":
        _, objects, installed, cached = read_zst_bundle(
            bundle, store=store, mbox=mbox, force=args.force
        )
        print(f"Mailbox: {mbox}")
        print(f"LFS objects: {installed} installed, {cached} already present/omitted")
        print(f"LFS cache: {store}")
    else:
        with zipfile.ZipFile(bundle, "r", allowZip64=True) as archive:
            manifest, objects = parse_manifest(archive)
            # Omitted objects are safe only if the receiver actually has them.
            for spec in objects:
                if not spec.included and not verify_local_object(spec.local_path(store), spec):
                    raise BundleError(
                        f"Missing peer-known LFS object {spec.oid} in {store}\n"
                        "Request a complete bundle (without --have) or provide that object first."
                    )
            # Verify mailbox before exposing any patch to the caller.
            metadata = manifest["mbox"]
            mbox.parent.mkdir(parents=True, exist_ok=True)
            mbox_temp: Path | None = None
            try:
                with tempfile.NamedTemporaryFile(dir=mbox.parent, prefix=".lfsmbox-", delete=False) as tmp:
                    mbox_temp = Path(tmp.name)
                extract_verified(
                    archive, MBX_ENTRY, mbox_temp, sha256=metadata["sha256"],
                    size=metadata["size"], force=True
                )
                actual_oids = added_lfs_oids(mbox_temp)
                if actual_oids != {spec.oid for spec in objects}:
                    raise BundleError("Mailbox LFS pointer IDs do not match bundle manifest")
                installed = 0
                cached = 0
                for spec in objects:
                    if not spec.included:
                        cached += 1
                        continue
                    target = spec.local_path(store)
                    if extract_verified(
                        archive, spec.archive_name(), target,
                        sha256=spec.oid, size=spec.size, force=args.force,
                    ):
                        installed += 1
                    else:
                        cached += 1
                if mbox.exists() and not args.force:
                    raise BundleError(f"Refusing to overwrite {mbox} (use --force)")
                os.replace(mbox_temp, mbox)
                print(f"Mailbox: {mbox}")
                print(f"LFS objects: {installed} installed, {cached} already present/omitted")
                print(f"LFS cache: {store}")
            finally:
                if mbox_temp:
                    mbox_temp.unlink(missing_ok=True)
    if args.apply:
        if objects and (git(repo, "lfs", "version", optional=True) is None or
                        not git(repo, "config", "--get", "filter.lfs.process", optional=True)):
            raise BundleError(
                "Git LFS filters are not installed in the receiving repository. "
                f"Run 'git -C {repo} lfs install --local' and then "
                f"'git -C {repo} am --3way {mbox}'. The mailbox and objects are ready."
            )
        print(f"Applying using git am --3way {mbox} ...", flush=True)
        result = subprocess.run(["git", "-C", str(repo), "am", "--3way", str(mbox)], check=False)
        if result.returncode:
            raise BundleError(
                f"git am failed with exit code {result.returncode}; "
                "the mailbox is preserved. Resolve and 'git am --continue', or 'git am --abort'."
            )
        mbox.unlink()
        print(f"Removed applied mailbox: {mbox}")
    else:
        print(f"Next: git -C {repo} am --3way {mbox}")


def inspect(args: argparse.Namespace) -> None:
    bundle = args.bundle.expanduser().resolve()
    kind = bundle_kind(bundle)
    if kind == "zst":
        manifest, objects, _, _ = read_zst_bundle(bundle)
    else:
        with zipfile.ZipFile(bundle) as archive:
            manifest, objects = parse_manifest(archive)
    print(f"Container: {'TAR+Zstandard' if kind == 'zst' else 'ZIP64'}")
    print(f"Bundle: {bundle}")
    print(f"Mailbox: {manifest['mbox']['original_name']} "
          f"({manifest['mbox']['size']:,} bytes)")
    print(f"Mailbox SHA-256: {manifest['mbox']['sha256']}")
    print(f"LFS objects referenced: {len(objects)}")
    print(f"LFS objects included: {sum(o.included for o in objects)}")
    print(f"LFS objects omitted: {sum(not o.included for o in objects)}")
    print(f"Total referenced payload: {sum(o.size for o in objects):,} bytes")
    print(f"Bundle size: {bundle.stat().st_size:,} bytes")
    if args.list:
        for obj in objects:
            print(f"{'included' if obj.included else 'omitted':8} {obj.size:>12} {obj.oid}")


def inventory(args: argparse.Namespace) -> None:
    store = find_lfs_store(args.repo.expanduser().resolve(), args.store)
    object_ids: set[str] = set()
    if store.is_dir():
        # Only accept files at the canonical two-level SHA-256 LFS media path.
        for directory in store.iterdir():
            if directory.is_symlink() or not directory.is_dir() or not re.fullmatch(r"[0-9a-f]{2}", directory.name):
                continue
            for shard in directory.iterdir():
                if shard.is_symlink() or not shard.is_dir() or not re.fullmatch(r"[0-9a-f]{2}", shard.name):
                    continue
                for path in shard.iterdir():
                    oid = path.name
                    if path.is_file() and not path.is_symlink() and VALID_OID_RE.fullmatch(oid) and \
                       oid.startswith(directory.name + shard.name):
                        object_ids.add(oid)
    output = args.output.expanduser().resolve()
    write_atomic_text(output, "# SHA-256 LFS objects present in receiver cache\n" +
                      "".join(f"{oid}\n" for oid in sorted(object_ids)), force=args.force)
    print(f"Inventory: {output} ({len(object_ids):,} objects; existence only, not rehashed)")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    p_pack = sub.add_parser("pack", help="Make a bundle from a git format-patch mbox")
    p_pack.add_argument("mbox", type=Path, help="Mailbox created by git format-patch --stdout")
    p_pack.add_argument("-o", "--output", type=Path,
                        help="Output bundle (default: <mbox-name>.lfsmbox.tar.zst)")
    p_pack.add_argument("--format", choices=("zst", "zip"), default="zst",
                        help="Container format: tar.zst (default) or legacy ZIP64")
    p_pack.add_argument("--level", type=int, choices=range(1, 20), metavar="1..19",
                        default=3, help="Zstandard compression level (default: 3)")
    p_pack.add_argument("--repo", type=Path, default=Path("."), help="Sending Git repository")
    p_pack.add_argument("--store", type=Path, help="Override LFS objects directory")
    p_pack.add_argument("--have", type=Path, help="Inventory file from receiver; omit those objects")
    p_pack.add_argument("--force", action="store_true", help="Overwrite existing bundle")
    p_pack.set_defaults(func=pack)

    p_unpack = sub.add_parser("unpack", help="Verify mailbox and seed destination LFS object cache")
    p_unpack.add_argument("bundle", type=Path, help="Input .lfsmbox.tar.zst or legacy .lfsmbox bundle")
    p_unpack.add_argument("-o", "--output", type=Path, help="Output .mbox file (default: derived from bundle name)")
    p_unpack.add_argument("--repo", type=Path, default=Path("."), help="Receiving Git repository")
    p_unpack.add_argument("--store", type=Path, help="Override LFS objects directory")
    p_unpack.add_argument("--apply", action="store_true",
                          help="Run git am --3way, then remove the mailbox on success")
    p_unpack.add_argument("--force", action="store_true", help="Overwrite existing mailbox or corrupt cached LFS object")
    p_unpack.set_defaults(func=unpack)

    p_inspect = sub.add_parser("inspect", help="Show bundle contents without extracting")
    p_inspect.add_argument("bundle", type=Path)
    p_inspect.add_argument("--list", action="store_true", help="List individual SHA-256 object IDs")
    p_inspect.set_defaults(func=inspect)

    p_inventory = sub.add_parser("inventory", help="List existing receiver LFS objects for incremental sends")
    p_inventory.add_argument("-o", "--output", type=Path, required=True)
    p_inventory.add_argument("--repo", type=Path, default=Path("."))
    p_inventory.add_argument("--store", type=Path)
    p_inventory.add_argument("--force", action="store_true")
    p_inventory.set_defaults(func=inventory)
    return p


def main() -> int:
    args = parser().parse_args()
    try:
        args.func(args)
        return 0
    except (BundleError, OSError, zipfile.BadZipFile, tarfile.TarError, EOFError) + \
            ((zstd.ZstdError,) if zstd is not None else ()) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
