# GM token authoring (T-041 engineering checkpoint)

**Status:** local GM-only authoring and native persistence implemented. Player-facing publication rules and owner usability acceptance remain **unapproved**; `docs/Index.md` leaves T-041 open.

## What works

1. In the **Tools** sidebar, choose **GM token (K)**. This creates or selects an editable `TOKENS` layer on the *presented* authored detail level of the current floor. Token layers are separate from raster paint and semantic Objects; default existing saves are unchanged until the tool is used.
2. In the right inspector, choose a color, label (1–48 printable characters), and radius (3–128 board units). Click an empty board area to place a circular labeled token. The document position may be negative or fractional. **Snap to grid** is optional and uses the existing grid snapping policy.
3. Click an existing token to select it; drag to preview a new position, release to commit one history command. Click **Update selected token** in the inspector to apply label, radius and color changes. **Delete/Backspace** removes a selected token. Escape cancels a pending drag. Ctrl+Z/Ctrl+Y undo/redo these edits.
4. Layer visibility, locks, opacity, floor and detail level work like other typed layers. A cell edit mask requires the **whole token's circular bounding square** to fit within the allowed cell for placement, movement, restyling or deletion. Invisible, locked, mismatched LOD, stale-state and invalid-target edits fail without changing stored tokens.
5. **Native Save** embeds token Resources in the same validated `.scn` campaign. Each token has a stable ID, board-space center/radius, label and tint. The token layer owns the map/floor/detail context and order. Saves, backups, exact semantic digest, and LFS/Web source-to-pack portability still apply.

## Privacy and limitations

- **All tokens are GM-only today.** A layer being visible in the editor is not permission to publish. The T-039 sanitized projection builder excludes ungranted token layers and **rejects an explicit grant of a `TOKENS` layer**. This guarantees the current isolated projection proof never accepts token state, but it does **not** implement a public token overlay, object-level grants, recipient-specific filtering or live projector permission tracking.
- Automatic token labels start at `Token`; select and update to rename. A Token layer can be renamed or reordered through Layers; the layer hierarchy shows its marker count. The current prototype does not expose individual token rows or multi-token selection there.
- There is no initiative tracker, HP, collision/pathfinding, ownership/role permission, game rules, imported character images or synchronized multiplayer movement. Those are outside this ticket.
- T-039 still requires approval of who may publish which tokens and when; T-043 must verify that secret token IDs, labels, native state and pixels never cross any player rendering/export/network boundary after moving or revocation. T-041 remains open until token interaction, sizes, labels, masking and player visibility are approved hands-on.

## Verification

- `godot --headless --path . --script res://tests/token_smoke.gd` checks identity, malformed data, stable movement, edit masks, locking, undo/redo, styling, detail level isolation, native save/reload and fail-closed player projection.
- `xvfb-run -a godot --display-driver x11 --audio-driver Dummy --rendering-method gl_compatibility --path . --script res://tests/token_visual.gd` checks GM native frame pixels, live drag preview and commit.
- `tests/storage_smoke.gd` now includes a GM token Resource in its normal, backup and source/Web-pack portable fixtures.
