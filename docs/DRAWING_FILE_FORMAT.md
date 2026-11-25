# Standalone Drawing file format (T-310)

The default writer is binary. The format-neutral `drawing-document-v1`
manifest remains the shared authority; there is no second raster owner.
`DrawingDocument.export_manifest()` checks the native save projection before
`DrawingFileIO` reads its canonical tiles, checks their SHA-256 fingerprints,
and acknowledges durable references through `mark_published()` after the
same-directory pending file is successfully renamed.

## Physical envelope

All header integers are unsigned little-endian 32-bit values. The fixed
56-byte header is followed by exactly `stored length` bytes.

| Byte offset | Size | Meaning |
|---:|---:|---|
| 0 | 8 | ASCII `DIADRAW2` |
| 8 | 4 | Envelope version, currently 1 |
| 12 | 4 | Compression: 0 = raw, 1 = Zstandard |
| 16 | 4 | Uncompressed payload byte length |
| 20 | 4 | Stored payload byte length |
| 24 | 32 | SHA-256 of stored payload |
| 56 | variable | Raw or compressed Godot binary Variant dictionary |

The typed payload uses `standalone_schema: drawing-standalone-v2` and
`blob_encoding: raw-rgba8`. The `document` dictionary uses the existing
logical schema with signed integer chunk coordinates, ordered tree and
stable identities. `blobs` maps canonical SHA-256 (stride, format and exact
straight RGBA8 bytes) to `PackedByteArray`; duplicate fingerprints are
written once. Sparse chunks are not expanded into a flat canvas. The same
record supports editable text and typed semantic Object data, `font_assets`
(licensed font bytes, SHA-256, OFL text), optional `image_frame` and
`object_source` metadata. Native text/frame position encodings remain as in
the existing logical record. Hidden RGB at alpha zero is not discarded.

The writer uses Godot's object-free Variant marshaling and built-in Zstandard
compression over the entire payload, not a separate compressed stream per
tile. If compression fails to reduce size, it stores raw bytes. Repeated
metadata, sparse pixels and font data therefore compress together. There
are no serialized Godot Object instances, RID/Callable/Signal records or
arbitrary resource reconstruction. The wire version pins this marshaling
contract to the tested Godot runtime; a future incompatible marshaling
change requires a new envelope version and reader.

## Validation and compatibility

- Stored file and uncompressed payload: each at most 128 MiB; 4096 layers,
  4096 referenced chunks, 4096 distinct blobs, 128 MiB expanded referenced
  RGBA8 and 128 MiB unique RGBA8. Counts and lengths are checked before
  decompressing or materializing the corresponding raster data. Metadata
  nesting is limited to 64 levels after Variant decode. The Godot marshaler
  is used without permission to deserialize Objects; the digest is an
  integrity check, not authentication or a sandbox for untrusted files.
- Version, compression, exact lengths and stored checksum must agree;
  a binary header never falls through to the JSON parser on failure.
  The decompressed length and consumption of exactly one Variant are checked.
  Every referenced tile is validated eagerly, including distant tiles and
  deduplicated references. Font bytes and license are checked against the
  known bundled font identity. Unknown schema, invalid tree, missing blobs,
  corrupted bytes or invalid frame reject without publishing a document.
- `drawing-standalone-v1` JSON/base64 files remain readable with the same
  canonical record rules, now also subject to the common expanded-raster
  budget. No migration on read, no bulk rewrite, and no mandatory conversion.
  Explicit Save writes binary; older app versions cannot read new binary
  files. Retain originals when exchanging with older versions. Historically
  valid unusually large deduplicated files above the new expansion budget
  fail explicitly rather than risking uncontrolled eager materialization.
- The browser, linked source loader and portable transfers parse the same
  captured bytes whose digest is authorized. A linked graph charges the
  maximum of stored, decoded and referenced raster bytes per unique source
  against its existing 128 MiB total admission budget. The graph depth,
  visit and authorization rules are unchanged.
- The T-066 Atlas campaign generation, sparse multi-file layout and immutable
  registry-owned Object revision encoding remain unchanged: the registry
  explicitly selects the legacy writer. Portable Object exports may use the
  new binary format. The in-memory `DrawingFileIO.encode()` default remains
  legacy for existing consumers; `encode(document, true)` provides typed
  payloads. T-148/T-149 native publication and persistence consolidation
  retain their existing gates.
- Save uses a same-directory `.pending-<id>` file and rename. Validation or
  write/rename failure leaves the old file and dirty state unchanged;
  failed staging is cleaned up. Open never rewrites the source. This is not
  a new backup-generation system, random-access/lazy decompression, crash
  durability guarantee or cross-process writer lock. Whole-payload compression
  and validation are synchronous; large-file performance and Windows
  portability still require measurement.

See [T-310 measurements and validation](evidence/T-310-2026-11-25-binary-drawing.md).
