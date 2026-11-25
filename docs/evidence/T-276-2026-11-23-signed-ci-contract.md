# T-276 — T-066 signed storage CI contract (2026-11-23)

## Baseline and failure

- Local worktree base: `7bf64734` on `sprint/2026-11-23-godot-beta4`;
  latest verified remote `main` at execution: `bbae76c33a6066582b2cd89e07cc3246fef942ce`.
- GitHub Actions squashed-main fast desktop run `45215183959`, job
  `137834298556`: T-066 atomic sparse campaign generations failed alongside
  independent T-085, T-086, T-053, T-068 and pre-T-275 T-063 failures.
- Fail-first locally under Godot `4.8.beta4.official.b070e63b1` with native
  `DrawingNativeTiles`: `ATLAS_BUNDLE_FAILED (91 checks, 3 failures)`. The
  `>2^53` edit could not commit; attempting to assert that the still-valid
  source failed Save was incorrect. See [fail-first log](T-276-2026-11-23-signed-ci-raw/fail-first.log).
- No source-code fix is needed: `DrawingDocument._publish_edit` already
  bounds native publication before adopting an out-of-range pixel;
  `DrawingDocument.export_manifest()` verifies source ownership and bounds.
  The old fixture was written before this stronger direct-edit path.

## Corrected model

1. Persist a legal near-`±2^52` sparse tile containing transparent hidden
   RGB; reopen and verify its exact original bytes.
2. Start a gesture with the historical `>2^53` signed anchor. Accept refusal
   from staging or commit (`COORD`/`COORD_RANGE`). Prove revision, dirty state,
   tile identities and published root are unchanged; cancel any open session.
3. For an independent negative cold-Save witness, rename the layer to create
   a legitimate dirty revision, then **test-only** insert an out-of-range
   internal tile. Clean documents otherwise reuse immutable manifests without
   exporting. Assert rejected Save (`STALE_SOURCE`/`COORD_RANGE`) does not
   update the root or clear dirty status. Remove the invalid tile and verify
   source export is again authorized.
4. Reopen the prior generation and verify transparent hidden-RGB pixels;
   continue original missing/compressed-corrupt chunk and path tests.

This does not authorize user edits outside native bounds, nor imply that
untracked internal mutation is a supported product API. The test only
establishes defensive rejection of damaged projections at two seams.

## Reproducible local commands and results

`GODOT` below is the executable in the uploaded
`drawing-toolchain-linux-x86_64` bundle. The repository's Rust native
extension is already built and loaded. All commands run at repository root.

```bash
GODOT=/mnt/data/unpacked/drawing-toolchain-linux-x86_64/bin/godot
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/campaign_bundle_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/campaign_bundle_editor_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script res://tests/storage_smoke.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t158_signed_lazy_tile_bounds.gd
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path drawing --script res://tests/t159_signed_replay_publication_bounds.gd
python3 -m unittest discover -s tests -p 'test_t071_storage_docs.py' -v
python3 tools/validate_ticket_store.py
```

| Witness | Process outcome |
| --- | --- |
| T-066 bundle, original fixture | 91 assertions, 3 failures, exit 1 |
| T-066 bundle, final repaired fixture | **97/97**, exit 0, no forbidden markers |
| T-066 bundle editor | **23/23**, exit 0 |
| Atlas storage | Initial run **abort 134 without assertion/log**; isolated rerun **77/77**, exit 0 |
| T-158 signed lazy/native tiles | **24/24**, exit 0 |
| T-159 signed replay | **39/39**, exit 0 |
| T-071 storage documentation Python | **8/8**, exit 0 |
| Ticket-store validation | **276 tickets**, dependencies and review gates valid |

[Raw command outputs and process exits](T-276-2026-11-23-signed-ci-raw/results.tsv)
retain the original fail-first, final native, editor, storage and Python
markers alongside this summary. The storage-smoke intermittent process
abort was recorded in T-202 and is
**not** diagnosed or fixed by T-276. Its separately passing rerun does not
make a claim of deterministic overall CI stability. The current hosted
workflow was not rerun on this local commit. There is no visual UI change,
owner UX approval, platform release signoff or full native-raster authority
claim here.
