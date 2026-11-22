# T-234 — Native tile-publication preflight evidence

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Remote baseline:** PR #22 `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Local Linux x86-64, bundled Godot 4.8 beta3 and compiled Rust extension.

## Reproduction and fix

`drawing/tests/t234_native_publication_preflight.gd` before production patch:
**10 failures / 24 initial checks**; the expanded 32-check fixture
fails **13 checks** against the same original implementation. A six-tile
2048px native publication exceeded 256 MiB of source/after/replay spans
but reached `_resolve_chunk` rather than rejecting. A valid first tile followed by malformed RGBA8, noncanonical ID,
invalid dirty rectangle or missing source likewise invoked the first source
provider before detecting the later invalid descriptor.

The publisher now validates the whole descriptor set and freezes tile bytes,
bounds and expected source identities before resolving any source. It rejects
reentrant changes after provider callbacks without advancing the document or
returning a publishable draft. This is a conservative transfer envelope, not
an RSS measurement or proof of total-process allocation bounds.

## Local validation

| Witness | Result |
| --- | --- |
| T-234 fail-first control | 13 expected failures / 32 expanded pre-fix checks (initial fixture: 10/24) |
| T-234 final (includes four reentrant mutations) | 32/32 passed |
| T-148 native document publication | 56/56 passed |
| T-148 tile ABI | 312/312 passed |
| T-148 persistent document | 44/44 passed |
| T-148 external raster adoption | 28/28 passed |
| T-148 Atlas native history | 43/43 passed |
| T-233 first pixel native bootstrap | 37/37 passed |
| T-231 direct transfer budget | 24/24 passed |
| T-148 native-X11 Canvas cutover | 46/46 passed; `tile_pixel_stream_calls=0` |
| Bundled Rust unit tests | 36/36 passed |
| Required-native CI source contract | 8/8 passed |
| Ticket store, workflow YAML, strict Godot log | 234 valid tickets; passed |

The valid test covers alpha-zero hidden RGB, exact dirty rectangle,
nonpublishing dry-run and precisely one prepared document install. The
invalid input tests verify zero lazy callback invocations, unchanged pixels,
revision and native attachment. This record does **not** establish owner
hardware responsiveness, hosted CI on an updated PR head, or universal
native ownership. T-148 and T-095 remain open; T-149 remains Blocked.
