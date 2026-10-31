# Editable text — T-027 implementation candidate

## Interaction proposal (owner approval pending)

- Choose **Text (T)** in the Tools sidebar, then click the current **visible, unlocked ink layer** to place text. Click inside an existing text object's rendered bounds with Text selected to reopen it instead of creating a second object. Text supports multiline input.
- The in-editor dialog edits **content**, **font family** (Sans / Serif / Monospace), **font size** (6–256 board units), **Bold**, **Italic**, and **RGBA color**. Apply is one history command; Cancel or Escape discards changes. The dialog explicitly suppresses global tool shortcuts while typing; the underlying canvas cannot receive pointer edits through the overlay.
- Body text is **persistently editable**, including after save/load and clipboard transfer. This is an intentional difference from Paint.NET's normally rasterized text. A saved text object is one selected ink-layer object; it can be moved, uniformly scaled and rotated using existing selection transforms. Whole-object erase (not cut glyph fragments) preserves editability of surviving labels. Layers, masks, detail-level visibility and undo behave like other ink objects.
- Position is the top-left baseline-independent **board-space origin** of the text box. Rendering uses Godot's multiline font API. Fonts come from the operating system when available, falling back to Godot's standard font on platforms without those families (notably Web). Size is always stored in board units; rotate/scale changes update stored metadata rather than bake pixels.
- Text renders only when **font size × viewport zoom ≥ 9 screen pixels**, regardless of detail level. A native framebuffer check showed the same 20-unit text culled at 0.4× (8 px) and readable at 0.5× (10 px). This is a proposed readability threshold, subject to manual device/display tuning. Culling affects only presentation: it never removes text or affects selection, persistence, references, or edit-target availability. D0 and D1 checks exercise same-coordinate independently authored text.
- Existing saves and ink strokes retain their shape; new text adds `text`, `font_family`, `text_bold`, `text_italic`, and optional `text_rotation` fields to the existing validated ink-object record. The same fields are copied and serialized for native saves and versioned ink clipboard payloads. Empty/malformed/oversized text and unsupported style metadata are rejected rather than flattened.

## Verification and limitations

Tests: `tests/text_smoke.gd` (47 assertions: schema, edit and history, eraser isolation, clipboard, masks, moves/rotation, D0/D1, native save) and `tests/text_visual.gd` (15 assertions: native pointer, modal screenshot, cull threshold, D0/D1 and 800×600 layout). Both are in CI.

No curved text, per-character formatting, justification, embedded font packaging, text-on-path, or arbitrary non-uniform scaling. Font selection depends on system availability, and screen-space readability must be reviewed on real displays. **Approval of the placement/edit controls, font/style policy and 9 px threshold is required before marking T-027 complete.**
