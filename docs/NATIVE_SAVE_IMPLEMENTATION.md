# Native single-file campaign implementation (pending Godot verification)

This change introduces a binary `*.scn` PackedScene containing a data-only root,
owned map nodes and embedded Resource-backed domain objects. The persisted
campaign Resource owns campaign metadata, links and placements; its runtime map
registry is reconstructed from owned map nodes by stable ID. Editor/viewer nodes
are never packed.

Each canonical raster chunk stores embedded lossless WebP bytes, dimensions and
SHA-256 RGBA8 pixel identity. Its decoded Image is a non-exported runtime field.
The proposed WebP codec remains **provisional** until the local agent completes
comparative benchmarks (native Image vs WebP vs raw/Zstd) as AD-10 requires.

`AtlasCampaignStore` stores a primary `.scn`, verified adjacent `.bak.scn`, and
staged `.pending.scn`/`.bak.pending.scn` candidates. Candidate bytes are
reloaded through an isolated temporary Godot resource path before promotion.
Validation includes the existing domain validators, an exact RGBA8 hash for
all chunks, a canonical semantic digest, native version checks and a restricted
external dependency set (shipped `res://scripts/*.gd`).

**Verification still required:** Godot 4.8-beta1 parsing and headless regression
runs, native framebuffer/interaction acceptance, Web export, actual target OS
rename overwrite behavior, data-file portability, and the full AD-10 raster
benchmark matrix. This sandbox does not contain the source checkout or engine.
Do not represent static script checks as successful engine validation.

These new save files deliberately do not import/migrate v1-v6 JSON campaigns.
Existing JSON fixtures and clipboard-format compatibility helpers may remain
in the domain and tests but are not user save formats.
