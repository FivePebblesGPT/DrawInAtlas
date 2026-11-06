# Manual review at milestone 6

## Usability testing

1. The map preview is terrible. The map inside the hex should be aligned to it, not a random non-transparent picture without proper zooming floating besides it.
2. What's with zooming? The hex isn't even 10% of the screen and it still zooms in. And the "Greyhaven" with tiles inside it is like a giant behemoth. We should really take lessons from leaflet about zooming, LODs, previews and such.
3. Enable automatic layer zooming by default! It's a core feature, and disabling it can help sometimes, but hurts if it's off by default.
4. Most of the tools are cluttered in the inspector, while we have a specially crafted sidebar for categorizing them. Add a tab with drawing tools, and add a grid of icons with tooltips, rather than a big list of text.
5. Using skeumorphic icons instead of text can compact **ABSURD AMOUNT OF UI SPACE**. Try to turn almost everything into an icon.
6. The Grid shape would not be edited constantly, move it to a separate settings popup, that can be opened through the toolbar.
7. What does Search do? We should look into other global world building tools.
8. Pen tool produces sharp edges on turns for some reason.
9. Cannot scroll pen's width parameter with mouse wheel.
10. Drag battlemap should not be the name of drawing tool, and it should not be accessible at the hex level. It should be more of a draggable canvas area that's also an object that can be moved and resized (with options to move the drawings or not, add move tool).
11. Why you can create a battlemat inside of a battlemat?!
12. It seems like battlemat tries to snap to tiles but not at the same time? Again it should be a movable, draggable canvas object.
13. Currently you cannopt zoom into hexes that have no map assigned to them (should be able).
14. No way to create or test floor links right now. We should postpone it, untill other featrue issues are resolved.
15. What the fuck is "Linked maps..."? Why does it has similar options to the "Grid shape"? If you actually compact the Layers tab, you can fit the link alongside the layers, like a cascade dropdown.
16. Epic: Implement Selection, Brush, Eraser, Move, Bucket, Line, Polygon, Contour, Text. Should be done similarly to popular editors like MS Paint, Aseprite, Paint.net.

Overall usability rating: unusable, probably will uncover more issues once the above are solved.

## Code review

1. Why exacly AtlasInkLayer is stored as an array of strokes, rather than a raster image?
2. Noticing to_dict methods everywhere, seems like leftovers from JSON implementation that has to be deleted.
3. Found some nasty `from_image` method in AtlasRasterLayer, that scans something pixel by pixel. Not clear what it for or what it does.
4. `terrain_layer.gd` that has `AtlasTileLayer`, interesting. So it bolts an `AtlasGrid`, and hardcodes `kind` field, which is redundant, can cause double state if both are used (kind looks like a leftover from JSON storage).
5. Found dynamic typing (`:=`) in many of the scripts. Told you not to use it. Probably those leaked through the newly installed godot skills. Fix: remove the mentions of it in the skills (TOP PRIORITY currently)
6. You know that you can comment what fields encode right?
7. `fill.gd`, `raster_brush.gd`, `selection_geometry.gd`, `stroke_eraser.gd` are looking messy, probably need simplification/readibility pass.
8. I remind you to split functions into steps with comments. Example: `raster_brush.gd` has `paint()` which is hard to read due to no step separation (looks like a bunch of vars and ifs).
9. The code you told to check looks more or less fine, but I know that's where YOU checked, and therefore I went looking elsewere.
