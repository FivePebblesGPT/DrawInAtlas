# Drawing artwork color contract (T-306)

Drawing and the shared Atlas Object Editor use **straight, encoded sRGB RGBA8** for artwork. Alpha is linear coverage, never a transfer-encoded color component. Native tile storage, signed coordinates, undo/redo and native `.drawing` serialization preserve all four bytes, including RGB at alpha zero. This is a working-space contract, not a full color-management system or a promise of monitor calibration.

## Boundaries

| Boundary | Representation and arithmetic |
| --- | --- |
| ColorPicker, exact RGB/hex, foreground/background, raster/text colors | Encoded sRGB channels; canonical values are rounded/clamped to 8 bits. ColorPicker changes select pigment without changing document history. |
| Native Hokusai Brush/Eraser | Decode encoded RGB with the piecewise sRGB transfer function **before** computing Hokusai's internal linear-RGB HSV settings. Hokusai works in linear premultiplied fixed point. The existing quantizer unpremultiplies and applies the inverse sRGB transfer exactly once. Opacity and alpha stay linear. |
| Native tile publication, ordinary raster and text source-over, layer compositing, JPEG matte | Existing source-over arithmetic on encoded RGB bytes with linear alpha, not linear-light layer blending. For example, white at alpha 128 over opaque black gives 128, not 188. This preserves established editing/history and file semantics; do not mix in another conversion without an explicit compositing-policy change. |
| Godot preview and display | RGBA8 ImageTexture, SDR 2D GL Compatibility; both project configs keep HDR 2D off. The actual software framebuffer is checked against known encoded swatches and a neutral ramp, plus X11 screen capture. Checkerboard/frame chrome is not part of exported artwork. |
| Native save and import from decoded RGBA8 | All straight bytes preserved; hidden RGB can be stripped only from the detached visible composite (not stored pixels). Existing saved drawings are not retroactively recolored by the corrected Brush adapter. |

## Raster file interchange

PNG with an sRGB declaration roundtrips encoded RGBA8 and alpha exactly. Godot 4.8 beta4's PNG encoder already emits the standard `sRGB` chunk with perceptual rendering intent (0). PNG `gAMA` without that declaration can be transformed by the decoder: the independent `gAMA=1` fixture uses a power-1/2.2 approximation, not an exact piecewise sRGB conversion. Alpha is unchanged. Do not run an additional unconditional transfer conversion over decoded bytes.

Godot's bounded PNG, WebP and JPEG decoders **do not color-manage arbitrary embedded ICC profiles**. Independent 16×16 RGB(64,128,192) fixtures carry a linear transfer profile with sRGB primaries and D65 white. LittleCMS conversion would produce approximately (137,188,225); the pinned Godot decoder returns (64,128,192) for all three. Decoded samples are treated as sRGB. Convert non-sRGB images (e.g. Adobe RGB or Display P3) to sRGB using a color-managed editor before importing; profiles are neither preserved nor converted by native Drawing files. This is a deliberate limitation of the current codec boundary, not an assertion that all source profiles are sRGB.

- Lossless WebP preserves the **visible composite** RGBA8, with the codec's default sRGB interpretation and no embedded ICC profile. Lossy WebP can change RGB; alpha remains linear.
- JPEG uses ordinary unprofiled JFIF output with sRGB sample intent; lossy RGB is approximate and the opaque matte uses the existing encoded-space compositor. Other readers must assume sRGB for matching appearance. The exporter does not attach ICC or EXIF color-space profiles to JPEG/WebP.
- No CMYK, HDR, wide-gamut working space, ICC editing, profile-preserving import, or OS/monitor calibration workflow is provided. Physical monitor appearance, GPU drivers and Windows portability are not established by a software framebuffer test.

## Repeat the independent witnesses

`make test-srgb` builds/imports the required pinned native extension and runs the T-306 model, actual standalone X11 window and actual Atlas Object Editor. `T306_SCREENSHOTS=/absolute/path` captures their real rendered previews/committed frames. The model checks known native pigments, all 256 encoded channel/alpha values, signed storage, hidden RGB, save/reopen, source-over, decoder metadata behavior and encoded format roundtrips. The graphical witnesses compare actual pixels (not two LUT implementations) and demonstrate picker-to-native Brush preview/commit and software display. T-190 remains the separate exact quantizer parity check; historical evidence is not rewritten.
