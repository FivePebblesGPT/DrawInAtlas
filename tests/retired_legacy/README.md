# Historical tests — retired spatial placement renderer

`references_ui_footprints_legacy.gd.txt` is preserved from before T-015's runtime
retirement. It tests parent/child maps projected onto the same canvas using
`AtlasPlacement`, a product behavior superseded by independent Drawing/Atlas
maps and marker-only navigation. **Do not run it as an active acceptance gate**
or count its old geometry/pixel expectations as passed. It is kept for forensic
comparison, not silently deleted or rewritten as a pass.

The current `tests/references_ui_smoke.gd` instead checks that no spatial
reference capture or footprint navigation is reachable while active markers,
exact arrival and Back still work. The archived placement data codec and
standalone read-only audit remain separate testable compatibility paths.
