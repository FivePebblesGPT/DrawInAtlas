# T-325 external transfer Redo ownership

2026-11-26, `sprint/2026-11-25`; verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `e034feb6` (T-324).
Pinned Godot 4.8.beta4.official.b070e63b1, bundled native extension.

## Fail-first and correction

The initial native two-document test failed 22/159 assertions. Structural
Undo/Redo imported/retired sources and restored sibling order using ordinary
branching operations, which erased unrelated native Redo tokens on one or
both documents. Later detached replay could erase unrelated applied tokens
as well. Semantic-only removal preflight skipped the busy/stale native
owner, so a failed Undo could advance the source through compensation.
The first correction passed 159/159; the expanded final witness passed
190/190, covering raster and semantic Move/Copy, rejected busy/stale
transfers, exact signed hidden RGB, retained applied/future tokens, actual
host branch disposal, and pending script edits without a native attachment.

Drawing's structural import, removal and reorder APIs retain their default
branching behavior. External callers can opt into preserving unrelated
native Redo, only after verifying external ownership, no unpublished edit
and a current attached native revision. AtlasDrawingTransfer uses this mode
for import, retirement, sibling order, and existing compensating operations.
It uses existing `publish_subtree_history_source_revision(..., false)`,
`retire_layers_revision(..., false)` and metadata revision operations; no
Rust ABI change. The real command owner already releases abandoned native
raster tokens after a successful new command (T-322). Removal preflight
now checks pending edits and revision before the no-raster early return.

## Verification

- `make test-transfer-redo-ownership TOOLCHAIN=bundle BUNDLE=...` exit 0;
  both project imports, native readiness and 190/190 checks. Integrated into
  ordinary `make test` and chronological history CI.
- Adjacent Atlas headless: T-170 30/30, T-172 33/33, T-148 native history
  43/43, T-322 142/142, T-245 126/126, T-246 206/206, T-247 259/259,
  Drawing chronological history 101/101.
- Adjacent Drawing headless: T-175 27/27, T-179 62/62, T-314 35/35,
  T-324 96/96. All twelve neighboring processes exited zero without
  failure markers.
- Explicit typing (648 project scripts, 33 skill documents), 29 Python CI
  contract checks (T-211/T-228/T-287), ticket-store validation and diff check.

## Boundaries

This does not retain tokens belonging to the actual transferred/retired
layer; that lifecycle still relies on detached snapshots. Cross-document
publication and compensation are not a single native transaction. The
native ABI's existing bounds and ordinary local branch semantics are
unchanged. No UI appearance change or new Rust code. Physical performance,
Windows compatibility and hosted CI remain unverified. T-148 remains In
Progress and T-250 remains Manual Review.
