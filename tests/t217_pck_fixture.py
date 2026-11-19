"""Minimal Godot 4.8 PCK-v4 fixture used by release-gate tests."""

from __future__ import annotations

import hashlib
import struct

DEFAULT_FILES = {
    "project.binary": b"ECFG\x00Drawing",
    "main.tscn": b"[gd_scene format=3]\n",
    "addons/drawing/native/drawing_brush.gdextension": (
        b'[configuration]\nentry_symbol = "gdext_rust_init"\n'
        b'[libraries]\nlinux.debug.x86_64 = "res://addons/drawing/native/bin/libdrawing_brush.so"\n'
        b'linux.release.x86_64 = "res://addons/drawing/native/bin/libdrawing_brush.so"\n'
    ),
    "tests/native_extension_ready.gd": b"extends SceneTree\n",
}


def make_pck(files: dict[str, bytes] | None = None) -> bytes:
    """Build the bounded, unencrypted PCK v4 layout emitted by Godot beta3."""
    resources = DEFAULT_FILES if files is None else files
    header = bytearray(112)
    struct.pack_into("<4sIIIIIQQ", header, 0, b"GDPC", 4, 4, 8, 0, 2, 112, 0)
    payload = bytearray(header)
    entries: list[bytes] = []
    for name, data in sorted(resources.items()):
        offset = len(payload) - 112
        payload.extend(data)
        encoded_name = name.encode("utf-8")
        encoded_name += b"\x00" * (-len(encoded_name) % 4)
        entries.append(
            struct.pack("<I", len(encoded_name))
            + encoded_name
            + struct.pack("<QQ", offset, len(data))
            + hashlib.md5(data).digest()
            + struct.pack("<I", 0)
        )
    index_offset = len(payload)
    payload.extend(struct.pack("<I", len(entries)))
    for entry in entries:
        payload.extend(entry)
    struct.pack_into("<Q", payload, 32, index_offset)
    return bytes(payload)
