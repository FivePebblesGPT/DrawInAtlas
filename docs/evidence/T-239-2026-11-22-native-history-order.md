# T-239 — Retained native host history order

**Date:** 2026-11-22. **Branch:** `sprint/2026-11-20-selection-dock-colors-brushes`.
**Last verified PR #22 remote head:** `b8a2980d0cd11f1b4ff7e7e1aa8f8c984ce81146`.
Local Linux x86-64, bundled Godot 4.8 beta3 and vendored Rust/GDExtension.

## Fail-first reproduction

Two *disjoint* direct raster edits were committed with `external_history=true`.
Both native tokens remained in Rust's Undo stack. Asking the host to Undo the
**older** delta (or Redo the **later** delta after unwinding both) made
`has_history_token` return false because that token was not at the top. The
document then called `replay_detached_history` even though the token was still
retained. The unrelated newer edit's RGBA8 could remain intact, so the
source-byte checks accepted the detached replacement and cleared the live
Rust history stacks. A correct later chronological Undo/Redo could no longer
use its token.

The final `drawing/tests/t239_native_history_order.gd` was run with the
original `HEAD:addons/drawing/document.gd` staged in the standalone project,
then the fixed document was restored and rerun against the same Rust binary:

- Previous document: `T239_HISTORY_ORDER_RESULT checks=36 failures=10`.
- Fixed document: `T239_HISTORY_ORDER_PASSED checks=36 failures=0`.

This negative control isolates the **document replay dispatch**; it uses the
new side-effect-free presence-query method in the native extension in both
cases. The native test also confirms that Undo and Redo rejection happens
before any lazy source callback, does not advance either revision, and leaves
all existing native tokens usable in chronological order.

## Correction

Rust exposes `has_retained_history_token(transaction)` as an O(64) read-only
query across both retained history stacks, distinct from
`has_history_token(transaction, revision, undo)`, which tests the next
eligible event. If a current native store retains the requested non-top token,
`_replay_native_tile_delta` returns `HISTORY_ORDER` **before resolving any
source** and rechecks after callbacks. Only missing, truly evicted, or
explicitly token-free history can take the checked detached replay path.
No tokens are invented, and the existing 64-entry native history bound is
unchanged.

A 66-edit sequence verifies that an evicted **positive** token remains
replayable from its detached snapshot. Another fixture verifies token-free
recovery, valid ordered Undo/Redo, and transparent alpha-zero hidden RGB.
The test does not assert that a host-provided token-free or evicted snapshot
is part of a correctly ordered *global host* timeline; that remains the host's
responsibility.

## Local validation

| Check | Result |
| --- | --- |
| T-239 negative control and final | 10 expected failures / 36 of 36 pass |
| 14 neighboring standalone and Atlas native/history suites | 578/578 pass |
| Entire selected headless matrix including T-239 | 15/15 suites, 614/614 assertions |
| Rust native unit tests (vendored offline toolchain) | 36/36 pass |
| Native-X11 Canvas cutover (software Mesa) | 46/46 pass; zero per-pixel tile-stream FFI calls |
| Required-native CI source contracts | 13/13 pass |
| Ticket-store validation | 239 tickets valid |
| Workflow YAML, Rust formatting, Git diff | Pass |

The new workflow assertion executes the real native-Godot test and verifies
`T239_HISTORY_ORDER_PASSED checks=36 failures=0`. Local tests are **not**
evidence of a new hosted GitHub CI run or physical device performance.
T-148 remains In Progress, T-149 Blocked; no owner/manual-review gate was
closed.
