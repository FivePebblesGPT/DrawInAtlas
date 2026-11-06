# T-039 — Player-output projection and privacy contract (approval candidate)

## Current Drawing/Atlas privacy boundary (T-075, 2026-11-02)

**Desktop Windows/Linux is the active product target.** T-044's single-window/Web fallback is **Archived** ([ticket](Archive/Web/T-044.md)); the `open_embedded` prototype and old Web tests remain historical engineering evidence, **not** a supported browser release or a second active privacy-acceptance path. The approved owner decisions for publication are still pending at [T-039](Tickets/T-039.md); the independent player-output/privacy signoff at [T-043](Tickets/T-043.md) is still blocked.

The active Atlas editor now composes generic `DrawingDocument` raster/text/group content through `AtlasDrawingRegistry` for each `(map_id, floor_id, detail_id)`, with linked `AtlasObjectLibrary` sources and instances and T-066's portable `Campaign.atlas.json` generation store (see [world mapping](DRAWING_WORLD_MAPPING.md), [Object Assets](OBJECT_ASSETS_WORKFLOW.md) and [storage](DRAWING_STORAGE_CONTRACT.md)). **The sanitizer below does not consume that new composed Drawing/Asset graph.** It accepts a legacy `AtlasMapDocument`/`AtlasCampaign` with `AtlasLayer` grants and emits a detached sanitized legacy campaign for the isolated test harness. A successful legacy grant test is not evidence that new Drawing pixels, editable text, fonts, Object Asset variants, NULL placeholders or previews can safely reach a projector.

**Threat and required bridge:** a trusted GM-only policy controller must explicitly authorize a bounded, current map/floor/detail snapshot *before* rendering, export or network serialization. Deny by default if any referenced Drawing layer, linked asset, text/font, fog, token, policy revision or cache entry cannot be filtered and verified. Never send a `DrawingDocument`, `AtlasDrawingRegistry`, `AtlasObjectLibrary`, GM canvas texture, `AtlasPreviewCache`, save manifest, or private asset ID to a player surface. Copying a frame to an untrusted display or transport is irreversible; revocation must prevent *subsequent* frames, including frozen and in-flight frames, but cannot recall pixels already copied outside the app. The actual player publishing bridge, controls and privacy acceptance are **not implemented**.

**Status (2026-11-01): proposed; NOT an accepted player privacy policy or a working projector.** The confirmed design in [[E-007]] is a movable, resizable frame on the GM board that controls **player framing only**. Projector-window size and physical tabletop calibration are separate from the frame and from artwork transforms. Production integration of T-013/T-040–T-043 remains gated on the product decisions below and acceptance of the core UX; T-044 (Web fallback) is Archived.

## Audience and explicit trust boundary

| Audience | May inspect | Must not receive |
| --- | --- | --- |
| GM/editor | Full authorized campaign content, source layer names/IDs, links, edit drafts, private notes, editor caches | Nothing restricted by this player policy (GM use is local/trusted) |
| Local player/projector | Only an explicitly granted, independently copied output **for the selected board, floor and authored detail level** | Unapproved raster chunks, objects, text, image props, other floors/LOD groups, references, secret map names/tags, links, selections, drafts, cached editor thumbnails, private tokens, unrevealed imagery |
| Future remote player | Same output boundary, plus host-side role/operation authorization | Canonical campaign/resources/serialized GM graph or unfiltered network events |

These are **proposed grants**, not stored user permissions. There is currently **no player audience field, public/private layer flag or approved per-object publishing policy**. T-042 adds a floor-wide, GM-authored fog rectangle model and a conservative raster-only sanitization proof, but its policy is **not yet approved**. T-041 now supplies stable, persisted GM-only `AtlasToken` records in `TOKENS` layers, but **no permission to publish them**: the T-039 capture boundary excludes ungranted tokens and explicitly denies a grant for a token layer. In particular, editor `layer.visible` is **not** publication authorization, and `AtlasPreviewCache`'s `audience` string only separates cache keys; it does not filter pixels or data. A plugin or renderer must never treat `get_image(..., "player")` as permission to publish the returned image.

## Implemented, isolated proof boundary

`AtlasPlayerProjection.build_capture_input(source_document, floor_id, detail_level, granted_layer_ids)` creates a new `AtlasCampaign` containing **one** sanitized map and no links, placements or source campaign metadata. Its public-grant input is a set of whole, stable layer IDs, supplied by a **trusted** GM policy controller, not by the player client. Empty grants produce a blank board. Unknown/duplicate IDs, missing floors, invalid detail levels, duplicate source-layer IDs, nonresident raster chunks, or invalid granted artwork **reject the entire request** (`null`, which callers must render as a neutral blank frame). No fallback to the canonical document is allowed.

The map/floor/layer names and IDs are replaced, as are tags, measurement labels and editor grid visibility. Only valid selected-LOD and visible/positive-opacity layers explicitly in the grant set are deep-copied, preserving their compositor order, transforms, alpha and pixel bytes. The copy is detached: mutations in either version cannot alter the other. Entire `Objects` layers include **all** contained text and embedded image props; whole `Raster` layers include **all** pixels. Therefore **a layer with mixed public/private content must not be granted**. With fog enabled, T-042 now filters authorized raster pixel bytes outside revealed regions *before* they enter capture input. Any grant of a fogged Objects layer fails closed; it does not yet securely clip individual text, paths or props. Token grants remain rejected. The player window is still isolated from production controls. No player UI or network transport uses this proof boundary yet.

`tests/fog_smoke.gd` and native `tests/fog_visual.gd` now cover the limited raster-fog filter on D0/D1 and actual framebuffer pixels. `tests/player_projection_contract_smoke.gd` asserts serialized data exclusion, no default grants, wrong-floor/LOD rejection, copy isolation, invalid metadata rejection, and the cache audience pitfall. `tests/player_projection_visual.gd` verifies a native image rendered through a **sanitized campaign**, where allowed red pixels appear and withheld green pixels do not, and that no grants yield a blank rendered frame. These tests prove this limited whole-layer filter, **not** the future end-to-end projector privacy contract.

## Boundary to implement after approval

1. **Trusted policy source:** define how a GM marks entire layers and individual objects public/private; permission changes must be explicit, logged and validated. No implicit publication from editor-visible layers. Document behavior for objects that move between layers, private notes embedded in public objects, and a missing/corrupt policy (deny).
2. **Player draw model:** authorize the map/floor/LOD, filtered raster/semantic objects, permitted grid settings, fog and token overlay, then generate a detached immutable player input. Never pass `AtlasMapDocument`, `AtlasCampaign`, preview caches, edit drafts, selection chrome or GM Canvas texture directly across the audience boundary. No owner-only hidden content should reach player render/capture inputs, not just be drawn behind an opaque overlay.
3. **Frame and camera:** T-013's GM-board frame tracks the player output aspect ratio. Moving it pans, resizing it changes the shown document rectangle at unchanged artwork coordinates. GM and player cameras can diverge. A proposed **follow** mode tracks the frame live; **freeze** holds a *previously authorized* image and camera only until a visibility/permission/fog change, after which it must be blanked or rebuilt through the current policy. No stale secret pixels may remain on a second monitor.
4. **Fog/visibility:** fog must filter or occlude every relevant LOD and derivative preview; decide whether opaque cover is sufficient for a local projector versus filtering source pixels before any export/network byte path. Cross-floor and cross-LOD grants are independent; a different detail group must not reveal the same secret via a preview.
5. **Cache lifetime:** split/label entries by audience **and policy revision**, map, floor, LOD, crop and content signature; after any grant revocation, token movement, fog change or private/public edit, discard untrusted player imagery and in-flight render requests. `AtlasPreviewCache` remains editor-only unless this is implemented. Never reuse a cached GM image under a different audience string.
6. **Output/export/transport:** sanitize first, render second. Future network replicators must serialize only filtered DTOs and approved image bytes. Native projectors may render sanitized input in a separate `SubViewport`/window. The archived Web fallback proof is retained as historical evidence only; no Web downgrade or editor capture is approved. Explicit cancellation and blank-frame behavior on renderer errors/disconnects.
7. **Calibration:** output-window pixels, physical cell-size calibration and board frame width are separate. The only accepted frame relationship so far is its matching aspect ratio; no physical DPI assumptions or implicit artwork scaling.

## Test/acceptance matrix for T-043

| Input change | Required observation (player render **and** serialized/cached data) |
| --- | --- |
| Grant omitted, invalid/stale or revoked | Output blank/denied; forbidden IDs, names, raster hashes and bytes absent; old frozen image invalidated |
| Secret raster behind/above permitted paint | Secret pixels absent even if overlapped, panned, resized or zoomed |
| Private text, vector paths, embedded image props | No private data in authorized object list, pixel output or metadata |
| D0 public / D1 private, or different floors | No cross-LOD or cross-floor bleed during zoom, navigation or previews |
| Fog edits or reveal/hide undo/redo | Output reflects current reveal state without exposing obscured canonical content through previews |
| Secret tokens or labels move | Unauthorized state never emitted or reintroduced from a stale capture |
| Permission toggles while rendering or frozen | In-flight old images rejected and caches cleared before another public frame |
| GM-only linked maps and reference previews | No private links, map titles, previews, or reference images in output inputs |
| Native separate display vs archived Web proof | Windows/Linux native source filtering and physical-display/privacy tests remain pending; archived Web proof provides no current release acceptance |

## Decisions needed from the owner before production wiring

- **Publication granularity:** whole layers only at first, or individual objects/raster regions from the start? Is a separate explicit Public layer required?
- **Player metadata:** may players see grid type, distance units, map/floor names, any labels, links or thumbnails? Default here is **no** unless specifically granted.
- **Fog and secrets:** is local projector compositing of fully opaque fog acceptable, or must secret pixels be absent from every intermediate GPU image as well? Network payloads must always be filtered.
- **Follow/freeze:** should freeze blank immediately on revoke/fog changes (recommended), and how should users resume follow? Is freeze part of undo history or session-only?
- **Persistence:** where do layer/object grants, privacy revisions and player-framing session defaults live, and what is the migration policy for existing saves? The proof adds **no persisted fields**.
- **Audience scope:** is a co-GM a fully trusted editor or an intermediate permission role? The latter depends on T-045/T-046.

Until these decisions are accepted, **T-039 stays open** in [[Index]], and the new proof boundary is not a guarantee that the current GM editor is safe to project. The project's older [[PRODUCT_DESIGN]] projector proposals are informative, not acceptance of these decisions.
