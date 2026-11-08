# Ticket Kanban Index

**As of 2026-11-07 · merged owner review and ongoing validation checkpoints.** This index includes the historical work and the Draw/Atlas separation documentation tasks introduced since [a9a3bc2](https://github.com/FivePebblesGPT/DrawInAtlas/commit/a9a3bc23d4c03b577d00526e1993f93cac1b121c).

**Canonical state:** ticket frontmatter (`status`, `manual_review`, `depends_on`). See [ticket workflow and closure gates](TICKET_WORKFLOW.md). The [fast desktop GDScript CI policy](CI_TESTING.md) runs required Drawing/core checks before reporting failures; legacy Atlas/native/Web suites are retained but non-gating; this changes verification only, not ticket status or manual approvals. **Done** on a pre-split ticket means its original acceptance was completed, *not* that the new Drawing application/Atlas integration exists. Web ticket T-044 is archived ([full historical ticket](Archive/Web/T-044.md)).

## Current priority — owner Drawing review (2026-11-05)

**Standalone Drawing usability is NOT accepted.** The owner reproduced missing live paint feedback, ~1-second strokes, zoom-out lag, insufficient selection and Move, opaque/unclear canvas bounds, ineffective layer hierarchy/visibility, cramped floating docks, responsive layout defects, and poor Object discovery. `.drawing` save/open **worked** in the exercised flow; undo's monotonic internal revision is **not itself a bug**. This assessment supersedes any implication that T-053/T-063/T-078–T-083 engineering checks constitute final interactive UX approval. [Full 23-finding matrix and milestones](DRAWING_USABILITY_REVIEW_2026-11-05.md).

**Delivery order:** M0 [T-094](Tickets/T-094.md) CI restoration and independent [T-084](Tickets/T-084.md) PhotoCraft scout; M1 [T-085](Tickets/T-085.md) live strokes and [T-086](Tickets/T-086.md) incremental display/zoom; M2 [T-087](Tickets/T-087.md) visible bounds/grid, [T-088](Tickets/T-088.md) selection/Move and [T-089](Tickets/T-089.md) layers; M3 [T-090](Tickets/T-090.md) responsive chrome/menus, [T-091](Tickets/T-091.md) one-group floating docks, [T-092](Tickets/T-092.md) Colors/History, [T-093](Tickets/T-093.md) Objects; M4 separate unapproved **owner** gates [T-056](Tickets/T-056.md), [T-059](Tickets/T-059.md), [T-083](Tickets/T-083.md), [T-065](Tickets/T-065.md). T-068 remains research, not the blocking implementation prerequisite. **T-083 returns to In Progress pending corrective UX work.**

**T-094 POSIX native-signal crash log guard (2026-11-08; In Progress):**
The required model-log checker previously accepted `*_PASSED` followed by
`Bus error`, `Illegal instruction` or `Floating point exception`, including
shell-wrapped PID/line-number variants. The new fail-closed guard rejects
these after whitespace/ANSI normalization without rejecting benign
crash-related prose or accepting anything beyond exact known post-exit
Godot leak lines. Six original-checker negative controls demonstrate the
false-green, while 37 Python log/replay contracts pass. Hosted CI, physical
Windows/Linux testing and explicit owner gates remain open; T-094 stays
**In Progress**. [T-094 evidence](Tickets/T-094.md) ·
[CI policy](CI_TESTING.md).

**T-065 complete portable source-count authorization (2026-11-08; In Progress):**
At the 512-source limit the portable index previously returned a successful
partial listing, hiding later unique assets or duplicate stable IDs. It now
examines all root candidates within the existing 2,048-entry budget, detects
late duplicates, and rejects the 513th unique source with `ASSET_LIMIT` while
preserving the last authorized snapshot. The **79/79** headless model covers
real loose/versioned source files, exact limit, late duplicates, atomic failure,
visible browser error and recovery; the original source fails four added
assertions. Hardware owner review, hosted CI and cross-process filesystem
atomicity are not verified. T-065 remains **In Progress**, with `manual_review:
true` and no approval granted. [Ticket](Tickets/T-065.md).

**T-065 snapshot-authorized source access and bounded version enumeration (2026-11-07; In Progress):**
The shared Object index now requires a matching listed ID/revision/path/SHA
before Open, thumbnail, drag or Export, preventing unreviewed same-root
sources from becoming usable merely by supplying their hash. Atlas drag tokens
retain their projected metadata and require the independent registry check.
Per-source version folders now stop after **2,048** directory entries and
skip any over-budget source with a warning rather than selecting an incomplete
old revision. The expanded **55/55** index and **43/43** transfer checks pass;
original-code negative controls fail **3 + 1** new assertions. Atlas paging,
linked placement and native browser/manager regressions pass. Root-level
enumeration, cross-process filesystem races, real large-library benchmarks,
hosted CI and owner Windows/Linux review remain open. T-065 stays **In
Progress**, `manual_review: true`. [T-065 evidence](Tickets/T-065.md).

**T-065 bounded Objects/ root enumeration (2026-11-07; In Progress):**
The portable source index now enumerates a **single combined maximum of 2,048
root files and directories** without materializing unbounded lists. The
2,049th entry rejects the entire new scan (`ASSET_LIMIT`) instead of
publishing a truncated source snapshot; the previous authorized index is
unchanged. The real browser displays the specific error. The expanded
**64/64** model oracle uses an actual 2,049-entry mixed-root fixture;
the original index fails its new atomicity assertion, and related Atlas and
native browser tests pass. Large real-library behavior, hosted CI, physical
Windows/Linux review and explicit owner approval remain open. T-065 stays
**In Progress**, `manual_review: true`. [Ticket](Tickets/T-065.md).

**T-065 portable Object path-link hardening (2026-11-07; In Progress):**
The read-only Objects/ index and standalone import/export now reject
symlinks at **any ancestor**, not only the indexed filename/Objects leaf.
An already-scanned campaign redirected via a symlink fails revalidation
before Open, Import or Export; ordinary real-path relocation remains supported.
The new filesystem negative controls pass **46/46** index and **40/40**
transfer assertions; nine headless T-065 suites and three Xvfb/Mesa native
browser/manager witnesses pass. This is point-in-time filesystem checking,
**not** atomic cross-process path authorization or physical owner acceptance.
T-065 stays **In Progress** with `manual_review: true`; no owner review
has been granted. [T-065 evidence](Tickets/T-065.md).

**T-087 host-camera-change gesture cancellation (2026-11-08; In Progress):**
A programmatic camera pan during held Brush/Eraser or Select/Move input
previously mixed source-coordinate mappings in one unpublished transaction.
The camera setter now cancels only on an effective changed value, discarding
queued pixels/marquee and restoring input state; same-value and idle camera
updates retain their previous behavior. New **78/78 model** and **104/104
Xvfb native** checks pass, including a real framebuffer preview and stale
release oracle; original-source negative controls fail **4 + 4** checks.
Physical owner UX/latency, Windows/Linux devices and hosted CI remain
unverified; T-087 stays **In Progress**, with T-056/T-059 manual gates open.
[Ticket and repro](Tickets/T-087.md).

**T-085 immutable live-stroke selection boundary (2026-11-07; In Progress):**
Brush/Eraser pointer-down now freezes the complete boolean edit mask,
including holes and enabled-empty deny-all. A changed selection during
queued painting cancels the entire uncommitted preview/backlog and restores
input state; an equivalent mask is harmless, and an in-place mutation is
rejected at final commit. The new **77/77 headless** and **125/125 Xvfb native**
witnesses pass; seven new model assertions fail against the pre-fix code.
Neighboring T-088/T-095/T-096/viewport/signed-boundary regressions pass
following a fresh standalone reimport. **No physical input-to-photon evidence,
Windows/Linux owner approval, or remote CI pass is claimed.**
[T-085](Tickets/T-085.md) · [T-094 hardware matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-094 CI/acceptance baseline in progress (2026-11-06):** Remote baseline
`main` CI is red; a strict-FP/FMA-native mask reproducer is fixed in the
T-068 stress **test build**, stale T-064 documentation status assertions are
removed, and an [actionable 23-finding Linux/Windows owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md)
now preserves #22 save/open success and #23 expected monotonic revisions.
Local strict native tests, Drawing clean staging/roundtrip/Linux export,
Atlas composition, and Xvfb/Mesa software pointer checks pass. Remote CI
against this patch, owner hardware UX and pending corrective ticket findings
are **not yet passed**; T-094 stays In Progress. [Checkpoint](Tickets/T-094.md).

**T-094 fail-closed CI summary/evidence capture checkpoint (2026-11-06; In Progress):**
The fast-CI reporter now compares all expected check IDs from the committed
workflow against the GitHub step outcomes, so missing/skipped steps cannot
look green. A local physical-evidence manifest tool tracks 23 dated finding
results independently for Linux/Windows with SHA-256 artifact validation and
strict coverage mode; its generated rows begin **NOT RUN**, never auto-pass.
Reporter and manifest contracts run inside existing fail-late CI steps.
Remote patched CI, actual hardware/pointer evidence and explicit owner review
remain unverified. [T-094](Tickets/T-094.md) ·
[owner runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-094 cross-build evidence consistency (2026-11-06; In Progress):**
Physical owner manifests now reject Linux/Windows results collected from
different commits or Godot engine builds; `--expected-commit` pins the candidate
under review. Local root Atlas editor reimport clears the stale SVG-loader
errors seen in an otherwise 89/89-pass composition smoke, but post-shutdown
Godot RID leaks and missing remote CI/hardware evidence remain reported. This
does not grant physical or owner signoff.
[T-094](Tickets/T-094.md) · [runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-094 local fast-CI replay checkpoint (2026-11-06; In Progress):**
A new [offline runner](../tools/replay_godot_ci.py) replays the 46 checked-in
fast-CI Bash checks in order, preserving failure/timeout logs and SHA-256
hashes. It rejects uncommitted source for commit-specific reports, and marks
partial check selections **incomplete**, never green. Eight new regression
tests run within the existing CI documentation step. Four selected development
checks passed locally, but this does **not** replace patched GitHub Actions,
Windows/Linux physical acceptance or owner approvals.
[T-094](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 hosted-CI artifact export (2026-11-06; In Progress):**
The hosted fast-CI workflow now uploads a sanitized JSON snapshot of all
46 check outcomes (including failures), exact candidate commit, runner/Godot
build and workflow digest. The artifact follows the fail-late summary and
requires independent verification against its actual GitHub run/attempt;
the export does not turn the previous local replay into hosted CI evidence.
Nine new contracts check missing/extra/failed checks, hash/order drift and
secret-output omission. Physical owner acceptance is still outstanding.
[T-094](Tickets/T-094.md) · [CI evidence policy](CI_TESTING.md).

**T-094 local full-replay diagnostics (2026-11-06; In Progress):**
The new fast-CI runner found **35/46 passing** in the first complete local
rehearsal. Eleven model/export steps had successful assertions but were marked
failed by named Godot 4.8-beta2 post-exit resource-leak `ERROR:` diagnostics.
A shared strict, success-marker-aware log validator now rejects any runtime
fault while separately counting only known shutdown diagnostics. The Linux
release gate is likewise fail-closed and its stage uses a unique temporary
directory. All 11 affected steps have passed targeted reruns; **patched
remote CI and physical Linux/Windows owner signoff remain NOT RUN**.
[T-094](Tickets/T-094.md) · [CI evidence policy](CI_TESTING.md).

**T-094 completed local fast-CI replay (2026-11-06; In Progress):**
Committed checkpoint `c18e69b` completed **46/46** required Linux local
fast-workflow steps with Godot 4.8-beta2; the raw logs retain 56 recognized
post-exit resource-leak diagnostics across 13 steps. A separate replay
artifact auditor now checks the committed scripts, complete step order,
result metadata, summary and per-log SHA-256 against tampering; its regression
suite is part of the existing fast CI contract group. **This is not a hosted
GitHub Actions green run**, physical Windows/Linux review or owner approval.
[T-094](Tickets/T-094.md) · [CI evidence policy](CI_TESTING.md).

**T-094 dock-review metadata CI regression (2026-11-07; In Progress):**
The T-078–T-083 docking-plan documentation test incorrectly treated a literal
`manual_review_approved: true` *example in ticket prose* as an actual owner
approval. The test now inspects only canonical ticket YAML frontmatter through
the same parser used by the 94-ticket dependency validator, rejects missing
review evidence or approval on non-manual tickets, and allows explanatory
text without changing the gate. The 10/10 docking documentation contracts
and 13 T-094 local-replay contracts pass; the 60-test fast documentation
step passed in a **selected local replay**, correctly reported as **1/46
incomplete**. Five neighboring Godot dock-model suites pass after standalone
import with strict log validation. This does not verify GitHub-hosted CI,
Windows/Linux physical owner UX, or T-056/T-059/T-083 signoff; T-094 remains
In Progress. [Ticket](Tickets/T-094.md).

**T-094 compact Godot error log guard (2026-11-08; In Progress):**
The required model-log checker now rejects timestamped Godot `E 0:00:00:542`
engine diagnostics after a valid PASS marker, including ANSI-colored/indented
lines. Previously this produced false-green log verification. New negative
and real-CLI contracts preserve informational/warning rows and the precise
post-success RID/texture leak exception. Hosted CI, physical Windows/Linux
acceptance and manual owner gates remain outstanding; T-094 stays **In
Progress**. [Evidence](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 OOM/allocator-failure log guard (2026-11-07; In Progress):**
The exact-marker CI log verifier now rejects shell-wrapped `Killed`/OOM
termination, glibc `malloc`/`free` heap-corruption banners and uncaught Python
runtime headers after a `*_PASSED` marker; previously these returned a false
pass from the standalone verifier. The original checker is an independent
negative control and the **20/20** expanded Python contracts pass, including
CLI exit and benign prose/known RID leak cases. This is not hosted CI,
physical owner evidence or manual approval; T-094 remains **In Progress**.
[T-094 evidence](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 shell-wrapped crash/traceback CI guard (2026-11-07; In Progress):**
The fast-CI Godot model-log validator now rejects Bash/Dash/Sh child-process
`Segmentation fault`/`Aborted` lines with shell/PID prefixes and Python traceback
headers after an exact PASS marker. The pre-fix implementation accepted three
representative fatal logs as clean; focused tests exercise the CLI and retain
the precise post-exit RID leak allowlist. This is a CI trust checkpoint, not
hosted GitHub Actions or physical owner acceptance. T-094 remains **In Progress**.
[Ticket](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 decorated-error CI fail-closed checkpoint (2026-11-07; In Progress):**
The required model-log guard no longer accepts a success marker followed by
indented/ANSI-colored Godot `ERROR:` lines or fatal shell crash banners.
Exact-marker and literal known post-exit leak rules are unchanged; a
reproduction returned exit 0 with the prior checker and exit 1 after this
fix. The 16/16 T-094 Python contracts and the required T-073 step
pass locally (**1/46 selected, incomplete**); no new check ID, runtime
behavior, or owner approval is implied. Hosted GitHub CI, Linux/Windows physical evidence and all manual
review gates remain open. [Ticket](Tickets/T-094.md) ·
[CI policy](CI_TESTING.md).

**T-094 strict Drawing model-log consistency (2026-11-07; In Progress):**
Six T-085–T-093 fast-CI Drawing model steps still used success-substring greps
and inconsistent error handling, allowing unknown `ERROR:` output to be missed
in some steps and classifying recognized Godot shutdown RID leaks as failures
in others. All eight Godot-backed Drawing model steps now use the shared
fail-closed model-log verifier; T-089's counted `T089_MODEL_PASSED: 62 checks`
format is recognized only with a positive integer count. Focused strict-log
and replay contracts pass, and six affected model steps pass in partial local
replays (five together, T-093 separately); these are **not a complete or hosted
46-step CI pass**. T-094 and all owner manual gates remain open.
[T-094 details](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 per-zoom physical timing evidence validation (2026-11-07; In Progress):**
The owner-manifest verifier formerly accepted a physical `PASS` for #01/#15
with 25/50/100 listed but only one pooled set of five samples per timing
phase. It now requires **independent five-sample arrays per phase and per
reported zoom** (at least 45 values for three zooms), rejects malformed,
missing, extra or pooled zoom data and stale zoom claims on `NOT RUN` rows.
The 12-test owner-schema suite and 94-ticket Kanban validator pass; **no
physical run, patched hosted CI result or owner approval is inferred**.
The [physical review runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md) documents
the JSON shape; T-094 remains In Progress.
[T-094](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 per-zoom review statistics (2026-11-07; In Progress):**
A new optional `drawing_owner_evidence.py verify --timing-summary` emits
R-7-interpolated p50/p95 and sample counts by 25/50/100% zoom and timing phase
for individually validated #01/#15 physical `PASS` reports. It never prints
statistics for unrun/failed/invalid or mixed-build evidence. New negative CLI
and percentile contracts pass; **this is not a hardware measurement, owner
acceptance, or remote hosted-CI run**. Ticket status and manual gates remain
unchanged. [T-094](Tickets/T-094.md) ·
[physical review runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-086 transparent subchunk display culling (2026-11-07; In Progress):**
Source-chunk occupancy was correct but overly broad: one visible pixel plus
hidden-RGB/zero-alpha content in a 256px source chunk triggered four 128px
texture uploads on a cold software viewport. A successfully rendered empty
RGBA8 composite now retires its display occupancy/texture before upload,
while unknown occupancy, glyph fallback and detached previews stay
conservative. Re-edit, Undo/Redo and lazy-source epoch updates restore content
without losing canonical hidden RGB. The measured isolated software witness
submits **262,144 → 65,536 texture bytes** (four → one textures), while still
performing four initial CPU tile composites; this is **not** proof of a
cold-frame latency speedup. The 140/140 native X11 checks and seven T-086
headless suites pass. Physical Windows/Linux and owner gates remain unverified.
[Ticket](Tickets/T-086.md) · [CI evidence policy](CI_TESTING.md).

**T-086 density-aware sparse-source cutoff (2026-11-07; In Progress):**
The 12-stored-pixel compositor cutoff caused near-empty 256px chunks with
24–64 pixels to scan each destination run densely. A bounded density-aware
threshold now keeps those runs sparse while preserving dense/preview fallbacks.
Three paired 9-sample software CPU runs show 24 entries **2.31–2.34ms →
0.41–0.44ms**, 48 entries **2.35ms → 0.61–0.67ms**, with identical per-case
RGBA8 SHA-256 hashes; 96/256-entry controls retain dense behavior. The
expanded public-readback oracle passes **590/590** and Xvfb native framebuffer
**153/153**. The required T-086 selected CI step passes **1/46 incomplete**.
Dense/large viewport, GPU/Windows/Linux and owner acceptance remain **open**;
T-086 stays In Progress. [Evidence](Tickets/T-086.md).

**T-086 sparse stored-pixel CPU compositor (2026-11-07; In Progress):**
Cold 128px display-tile composition now iterates intersecting stored RGBA8
pixels for near-empty canonical source chunks, with a dense/short-run and
all-preview fallback; both paths use native packed-byte writes. A
256×256 two-layer, eight-pixel software CPU witness improved from
**17.2–17.6ms to 1.8–1.9ms median** across paired nine-sample runs with
identical SHA-256 output. The independent model oracle passes **270/270**,
expanded Xvfb framebuffer suite **153/153**, and required T-086 selected
fast-CI check passes locally (**1/46 incomplete**, not hosted). Real dense
cold-zoom, hardware input-to-display, transient GPU memory and owner UX
gates remain open: T-086 is **In Progress**.
[T-086 implementation and limitations](Tickets/T-086.md).

**T-086 fully erased sparse-tile cache pruning (2026-11-07; In Progress):**
A source chunk's complete erasure used to leave monotonic display occupancy
markers, causing blank 128px textures to be recomposited and uploaded again.
T-086 now probes only up to 256 touched display tiles on selective published
edits and removes the occupancy and texture entry if no visible raster/lazy
source or text bounds can cover it. Active detached previews and uncertain
coverage remain conservative. A native Xvfb/Mesa reproduction changed from
one **65,536-byte transparent texture upload** to **zero**, with Undo/Redo,
offscreen pan, preview cancellation and layer-overlap framebuffer checks.
The clean-stage native witness passes **111/111**, seven T-086 model suites
**2,420/2,420** and shared Atlas smoke **346/346**. This does **not** close
large dense cold-zoom, physical Linux/Windows latency or owner gates;
T-086 stays In Progress. [Ticket](Tickets/T-086.md).

**T-085 live-stroke engineering checkpoint (2026-11-06; In Progress):**
An immediate stationary dab and layer-correct detached Brush/Eraser preview
now render **before release**. Ordered, timestamped source-float mouse samples
are drained in bounded chunks; brush sessions use touched-pixel rollback rather
than copying three growing dictionaries every event. The new 40/40 headless
model witness and 55/55 Xvfb/Mesa native held-button framebuffer witness pass,
including 100/50/25% zoom, cancellation, crossing strokes and one-step Undo.
Software first-frame samples still reach **119.841 ms at 25%** (one trial per
zoom); the display-tile work remains T-086, and owner Windows/Linux hardware
and physical input-to-photon evidence are **not claimed**. [Checkpoint](Tickets/T-085.md).

**T-085 bounded long-stroke backlog checkpoint (2026-11-07; In Progress):**
Consecutive source-space stroke waypoints now stage in limited batches with a
soft 6 ms per-drain CPU budget and footprint-sensitive wide-brush cap, instead
of allowing a 12-segment/frame limit to defer release for 70 frames. The
expanded **61/61** headless queue/oracle/cancellation tests and **118/118**
native Xvfb/Mesa pointer/framebuffer checks pass. Paired three-trial
840-motion software strokes measure release-to-commit p50 reductions of
389→43 ms at 100%, 955→68 ms at 50% and 928→70 ms at 25%; exact RGBA8,
all delivered points and single-step Undo are verified. Three trials and
software rendering do **not** satisfy real Linux/Windows hardware or
physical input-to-photon/owner UX gates; T-085 remains In Progress.
[Details and limitations](Tickets/T-085.md).

**T-086 incremental viewport cache checkpoint (2026-11-06; In Progress):**
Persistent 128px source-space display tiles now reuse textures across
pan/zoom and update only dirty raster/preview footprints (including Undo/Redo),
with a 144-texture retained cache limit and sparse occupancy culling. A
192-tile conservative over-budget view now keeps 144 retained tiles warm and
uses 48 transient draw-command references rather than thrashing every tile.
The 27/27 headless journal/stamp and 68/68 Xvfb native RGBA8/alpha/text/seam
witnesses pass. In a reproducible 12-trial llvmpipe benchmark, warmed 25%
one-pixel-edit frames improve **253.09ms → 22.96ms median**, and idle frames
**262.93ms → 1.50ms median**; the **initial 50% zoom transition is slower**
(144.22ms → 165.52ms, one sample). No real Linux/Windows physical latency or
large dense reference-window acceptance is claimed. [Ticket and evidence](Tickets/T-086.md).

**T-086 cold-source compositor optimization (2026-11-06; In Progress):**
A bounded per-storage-row tile/preview lookup (maximum 256 references) and
opaque-RGBA8 overwrite fast path reduce repeated cold raster composition
while retaining byte-for-byte alpha parity. New 25/25 headless model checks
and the existing native framebuffer witness pass. Two isolated, checksum-
matched nine-sample paired runs improve the 256x256 two-layer opaque CPU
median from 95.95→54.58ms and 88.39→59.79ms; fractional alpha also
improves, and an all-transparent case is essentially unchanged. This is
**headless CPU-only**, not evidence that full cold zoom or real GPU/Windows
latency acceptance is complete; T-086 remains In Progress.
[Ticket/measurement](Tickets/T-086.md).

**T-086 direct indexed source-pixel CPU improvement (2026-11-06; In Progress):**
The canonical raster compositor now reads resolved sparse tile maps by linear
indices without per-pixel checked GDScript accessors; detached preview patches
remain separate and alpha/layer semantics unchanged. A new four-dense-layer
signed-seam oracle raises the T-086 cold model to **45/45** checks; the existing
68/68 native framebuffer witness passes after a clean standalone import.
Against the SHA-256-pinned immediate predecessor, two nine-sample headless
paired runs show opaque CPU medians 54.94→25.86ms and 57.19→26.89ms, with
exact output hashes. This does **not** close cold GPU zoom, dense reference
hardware or physical input-latency gates. [T-086](Tickets/T-086.md).

**T-086 frame-local visible-layer preparation (2026-11-06; In Progress):**
A cold display draw now walks the ordered visible layer tree once on its
first cache miss, not once per display tile; cache-hit redraws do not walk it.
Source revision/epoch checks reject stale preparations, and the new 82/82
headless oracle plus 69/69 native Xvfb/Mesa framebuffer checks pass. The
nine-sample repeated small CPU tile workload measures 7.56→6.58ms median,
**not** a full cold zoom or physical input-to-photon result. Large dense
hardware acceptance remains open. [T-086](Tickets/T-086.md).

**T-086 bounded sparse-layer culling (2026-11-06; In Progress):**
Planned cold renders now skip raster layers with no overlapping resident or
lazy source chunks after at most 16 signed membership probes. An active
detached preview, text, wide/unknown regions and corrupt lazy data use the
conservative resolver. New 74-check headless parity/epoch/cancellation tests
pass; 24-layer sparse CPU medians improve 1.361→0.308 ms for a 16×16 source
region. This does **not** close dense cold zoom or hardware latency acceptance.
[T-086](Tickets/T-086.md).

**T-086 frame-local preview-stamp index (2026-11-06; In Progress):**
During a held gesture, one bounded viewport-clipped index now maps changed
storage-tile generations to 128px display tiles, avoiding a repeated scan of
the full changed-key set for each zoomed-out tile. The implementation keeps
an exact fallback when its 40,000-entry cap is exceeded and retains cleared
patch generations for ghost-free previews. New headless parity/fallback tests
pass 2,146/2,146; the native framebuffer test passes 75/75. A synthetic
768-display/240-changed-tile lookup-stage median improved 55.725→0.873ms;
this is **not** complete frame, hardware or cold-zoom evidence. T-086 stays
In Progress; physical acceptance remains open.
[T-086](Tickets/T-086.md).

**T-086 shared cold-frame source-chunk references (2026-11-06; In Progress):**
Neighboring 128px display-tile renders now reuse up to 256 read-only,
revision/source-epoch-pinned canonical storage chunk references per cold
frame; no RGBA8 is duplicated and detached preview changes remain separate.
A 31/31 headless parity/invalid-source/cap witness reduced source resolves
8→2 across four adjacent display tiles; the native Xvfb framebuffer suite
passes 76/76 after clean standalone import. This does **not** prove large
dense cold-zoom or physical Windows/Linux latency, and T-086 remains
In Progress. [Ticket](Tickets/T-086.md).

**T-086 dense viewport center/pointer-focused retention (2026-11-06; In Progress):**
When a dense viewport exceeds the 144-texture retained cap, newly visited tiles
now replace the farthest visible cached tile only when nearer the active
in-canvas pointer (or viewport center); stable focus and offscreen LRU remain
bounded. New headless 15/15 and Xvfb/Mesa native 80/80 checks pass; a warmed
192-tile software view still renders 48 transient edges each redraw.
**This is not a dense-zoom throughput or physical hardware acceptance pass.**
[T-086](Tickets/T-086.md).

**T-088 sparse Copy/Move capture (2026-11-07; In Progress):**
Initial clipboard capture now walks only present signed source chunks and
stored nonzero RGBA8 cells, with exact boolean selection masks and hidden-RGB
preservation. Selected lazy chunks still verify their digests; excluded lazy
corruption is not fetched. The independent dense-readback/negative-control
model detects the old 289-chunk sweep; a seven-trial 512×512, eight-pixel
CPU-only median decreased **231,542 → 611 µs** (not input-to-photon).
The new oracle is part of the existing required T-088 CI step; physical
Windows/Linux and T-056/T-059 owner gates remain unapproved, so T-088 stays
**In Progress**. [Ticket](Tickets/T-088.md).

**T-088 sparse transparent Paste staging (2026-11-07; In Progress):**
The Drawing clipboard now stages nonzero source payload pixels directly for
sparse transparent pastes instead of rescanning a large empty selection box;
nontransparent and dense paths retain exact zero-cell clearing semantics.
A separate dense oracle passes **56/56** headless checks across hidden RGB,
boolean masks, rollback and Undo/Redo; the pinned T-088/T-096/T-085/T-086
native regressions remain green. A 512×512, six-pixel CPU staging comparison
across three paired seven-trial runs decreased from **156–158ms to 42–46µs**
per-run median, without measuring capture, GPU frames or owner input-to-photon.
The new source oracle is part of the existing required T-088 fast-CI step.
No physical/owner acceptance or T-056/T-059 manual approval is claimed;
T-088 remains **In Progress**. [Ticket](Tickets/T-088.md).

**T-088 persistent selected-pixel Move correction (2026-11-07; In Progress):**
Mouse release now retains an uncommitted detached floating mask/pixel preview.
Repeated drags accumulate signed offsets from the original source; explicit
Enter/Menu Drop or outside click commits **one** history step, while Escape,
Ctrl+Z, revision/layer change and direct host cancellation restore source.
Changing tools/selection mode or choosing clipboard/save resolves the floating
piece first. New **131/131** headless signed-mask/hidden-RGB/Undo checks,
**51/51** native Xvfb/Mesa pointer/framebuffer checks and six fail-closed
log contracts pass. The software zoom probe is 17.159ms p50/19.827ms p95
(n=4), **not** physical input-to-photon evidence. Owner PhotoCraft UX and
Linux/Windows hardware remain unaccepted; T-088 is reopened In Progress, with
T-056/T-059 manual gates untouched. Neighboring native T-085/T-086/T-090,
standalone, and shared Atlas smokes pass; unrelated T-089 native layer-pointer
fails nine assertions identically on clean remote `116afa12` in this Xvfb
setup and is not counted green. [Ticket](Tickets/T-088.md).

**T-080 clipped bottom dock drop regression (2026-11-07; Done, engineering only):**
The pre-T-082 native witness incorrectly treated a canvas release as invalid,
although canvas detach is now deliberate. It now checks genuinely invalid
outside-window drops. A separate real hit-test correction makes the last dock
**group insertion slot reachable** at the visible bottom once a tall dock is
fully scrolled, rather than silently merging into its last group. The native
Xvfb/Mesa pointer/keyboard test passes **70/70** (71/71 with screenshot),
model **60/60**; an on-demand native workflow and strict log-contract tests
capture evidence. T-081's then-failing **1/54** baseline canvas-width check was isolated
and later corrected in the T-081 checkpoint below; it is not counted as a
T-080 pass. This
neither closes T-083 nor supplies physical owner review. [T-080](Tickets/T-080.md).

**T-081 floating overlay canvas-width regression (2026-11-07; Done, engineering only):**
After compact Colors, a native T-081 witness reproduced a **2px canvas-width
jump** when floating that group: the right dock's intrinsic minimum changed
184→182px as the group left the split. A stable 192px expanded dock floor now
prevents that unrequested resizing (minimized rail remains 48px). The native
pointer/keyboard/geometry suite passes **58/58** (59/59 with one framebuffer
PNG), the headless ownership model **64/64**, and five fail-closed evidence
contracts pass. T-079/T-080/T-082/T-083/T-090/T-091/T-092 neighboring native
suites and the four shared Atlas smoke suites pass; the native run retains
only classified post-exit Godot/Mesa resource diagnostics. The new on-demand
X11 workflow does **not** constitute hosted CI or Windows/Linux physical
owner approval; T-083, T-056 and T-059 manual gates remain open.
[Ticket](Tickets/T-081.md) · [owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-091 client-boundary resize anchoring (2026-11-07; In Progress):**
Dragging a floating host's left/top/right/bottom edge past the viewport
previously moved its opposite fixed edge because whole-frame clamping was
used for an edge resize. Each moving edge is now independently clamped at
the client margin and the opposite edge remains anchored. Six new model
boundary cases pass **56/56** total; four native real-pointer Xvfb/Mesa
overdrags pass **44/44** total. The old code fails 6 model / 4 native anchor
assertions. The required T-091 model CI and on-demand native witness retain
strict pass requirements; physical Windows/Linux and T-083 owner gates stay
**PENDING**. [T-091 evidence](Tickets/T-091.md).

**T-091 repeated floating chrome and tall-host redock checkpoint (2026-11-07; In Progress):**
Queued-for-deletion floating tab strips/frames are now immediately detached on
redraw; synchronous multi-tab refreshes keep one header and active view, with
real panel identity preserved. Normal grip dragging retains host movement over
the canvas but previews a transactional group redock over the right dock even
when a tall host overlaps it; Escape and invalid drops cancel unchanged.
The new Xvfb/Mesa 1280×800 native regression passes **53/53** (or **55/55**
with two screenshots); original T-091/T-081/T-082/T-083 native suites pass.
T-080's independent native invalid-drop witness also fails on the untouched
remote baseline and is **not** counted green. Windows/Linux physical pointer,
DPI and owner approval remain pending, with no T-083 manual gate waived.
[T-091 evidence and limitations](Tickets/T-091.md).

**T-087 runtime clipping-policy change safety (2026-11-08; In Progress):**
A host changing `clip_strokes_to_image_frame` while Brush/Eraser input is
queued now cancels the old authorization transaction before installing the
new policy. Stale release cannot publish pixels/history; equivalent policy
writes preserve normal strokes and Undo. The expanded model **70/70** and
Xvfb real-pointer/native **95/95** checks pass, while the previous source
fails **6 model + 8 native** new assertions. The default unbounded Atlas
host and visual-only frame guides are unchanged; physical Windows/Linux,
hosted CI and T-056/T-059 owner signoff remain open. T-087 stays **In
Progress**. [Ticket and evidence](Tickets/T-087.md).

**T-087 live snap-mapping safety (2026-11-07; In Progress):**
Changing effective Snap mode, grid spacing or grid origin during queued
Brush/Eraser or active selection/Move dragging now cancels the incomplete
gesture before it can publish pixels or history from two coordinate mappings.
Equivalent values, grid/pixel-grid visibility, and spacing/origin adjustments
while snapping is disabled are non-destructive. New T-087 model **61/61** and
actual Xvfb/Mesa pointer/framebuffer **82/82** checks pass; pre-fix canvas
negative controls fail 2 model and 12 native assertions. T-085/T-086/T-088/
T-096, signed-boundary and shared Atlas regressions pass after a fresh font
import; the selected local CI check is **1/46 incomplete**, not hosted green.
Owner T-059/T-056 hardware and UX gates remain **PENDING** and T-087 stays
**In Progress**. [Ticket and evidence](Tickets/T-087.md).

**T-087 finite-frame Brush/Eraser and checker correction (2026-11-07; In Progress):**
PR #13's reported outside-frame painting and panning checker-phase defects
are corrected in the standalone canvas without cropping signed sparse data or
limiting Atlas hosts. Brush/Eraser begins only inside the image; the entire
swept footprint is clipped in detached staging and remains one Undo entry.
Existing off-frame pixels, hidden RGB and `.drawing` Save/Open survive.
The repeated checker uses viewport-origin UV phase so top/left/right/bottom
image edges do not shift its 16px screen cells. New T-087 model **57/57**
and Xvfb/Mesa native **64/64** checks pass; neighboring T-085/T-086/T-088
and shared Atlas checks pass after a clean import. T-059 physical owner UX
finding #02 and #16 remain **PENDING**; the earlier engineering-Done status
is reopened for corrective review, without approving manual gates.
[Ticket](Tickets/T-087.md) · [owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-087 visible standalone image bounds and independent grid (2026-11-06; historical engineering Done):**
An optional validated `.drawing` image frame records origin/size without
clipping canonical signed sparse pixels, Object Assets or Atlas document space.
Ordinary New/Open fits a visible edge and screen-space 16px checkerboard;
View controls toggle grid independently of snap and configure signed origin
and spacing. Clean-import model 47/47, native Xvfb/Mesa 36/36 (including
real pointer snap and 25/50/100/200% zoom) pass. Physical Windows/Linux
owner UX for findings 02/16 remains **PENDING**, separately gated by T-059.
[Ticket](Tickets/T-087.md) · [runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-089 layer/group corrective engineering (2026-11-06; Done):**
Tree row selection is independent from the paint target; groups are
selectable without painting, and +Layer/+Group insert relative to that row.
Clickable row eye/lock controls, keyboard reorder/indent/outdent, guarded
structural history and stable save/reopen identities are implemented in the
canonical shared package. **62/62** headless model checks and **32/32**
X11/Xvfb/Mesa software pointer/framebuffer checks pass (1120×800/880×550,
400% zoom). The 200-row paging/filter path remains bounded; Xvfb
compact-workspace (420px, 150% scale), Object Editor UI (25/25), and
workspace-keyboard regressions also pass. Atlas callers retain external chronology. Physical Windows/Linux owner acceptance for
findings #19/#20 remains **PENDING**, not inferred from CI or software rendering.
[Ticket](Tickets/T-089.md) · [runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-089 native dock-scroll witness repair (2026-11-07; engineering Done):**
The original nine native eye/lock/group assertion failures on the unchanged
remote baseline were caused by attempting clicks on the Layers Tree below the
visible dock, not by evidence of broken structural editing. A real synthetic
wheel press/release sequence now scrolls the dock before clicking, with an
explicit unchanged-document check. Imported Xvfb/Mesa **36/36** native and
**62/62** headless model checks pass, with strict fail-closed log validation;
neighboring T-090/T-091/T-092 and Atlas smoke checks pass. The T-089 workflow
and parser reject the stale 32-check marker. No production code changed and
owner findings #19/#20 still await physical Linux/Windows validation under
T-059; software green does not grant owner acceptance.
[Details](Tickets/T-089.md).

**T-092 strict hex entry (2026-11-07; In Progress):**
The Colors hex field now accepts only its documented `#RRGGBB` or
`#RRGGBBAA` formats; Godot's permissive abbreviated/bare hex parser no
longer silently changes the selected pigment. The negative control fails
3 model and 4 native assertions against the prior code. Expanded **67/67**
headless and **51/51** native Xvfb/Mesa pointer/Enter checks pass
(**55/55** with four framebuffer captures), including
zero-alpha hidden RGB, standalone selection/history, and neighboring
T-063/T-088/T-090/T-091 tests. The native verifier requires all 51 checks;
reimport of standalone icons is mandatory after staging. T-092 remains
**In Progress** for owner visual/physical Linux/Windows acceptance (finding
#11); no manual gate is approved. [Evidence](Tickets/T-092.md).

**T-092 separate FG/BG editing and compact Colors layout (2026-11-07; In Progress):**
The Colors chips now select *independent* foreground/background edit targets:
clicking BG no longer silently swaps brush pigment, and Previous BG restores
background instead of changing foreground. A short active-role label, explicit
Swap/Default, RGB**A** channels (including transparent hidden RGB), hex and
advanced/recent inputs route to the selected pigment, without touching
artwork, revision or Atlas semantics. Pinned PhotoCraft source supports the
two-target grammar, but actual PhotoCraft screenshot parity is **unverified**.
New **55/55** model and **47/47** Xvfb/Mesa native checks with four framebuffer
captures pass; T-063/T-090/T-091/T-088 and 346 Atlas smoke assertions pass.
Physical Linux/Windows and owner finding #11 remain **PENDING**; T-092 is
reopened In Progress. [Evidence](Tickets/T-092.md) ·
[owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-090 More-menu checkmark parity (2026-11-07; In Progress):**
Narrow Drawing windows moved checkable View/Window commands to More without
copying their on/off indicators. The shared top bar now reflects checked and
disabled state and synchronizes live toggles without closing/rebuilding the
popup. A 32/32 independent headless/Xvfb oracle detects 12 failures against
the original code; expanded real-pointer Xvfb tests pass 77/77. The required
T-090 step includes the fail-closed oracle inside the unchanged 46-check
inventory. Hosted CI, physical display/DPI and owner UX review remain open;
T-090 remains In Progress. [Evidence](Tickets/T-090.md) ·
[owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-090 compact tool rail and centered icons (2026-11-07; In Progress):**
The 54px/44×42px tool rail had visible left-shifted SVGs despite the
original licensed-icon pass. Shared workspace controls now use a 42px rail,
34×34px targets and explicit icon centering; SVG bytes/license remain unchanged.
A new native SVG-pixel centroid witness passes **72/72** without screenshots,
**78/78** with six captures, including 100/150/200% scale and six real tool
clicks. T-063/T-091/T-092/T-088 and shared Atlas regressions pass in Xvfb,
not physical Linux/Windows. Owner findings #03/#06 and manual UX gates remain
**PENDING**; this corrective review reopens T-090 as In Progress.
[Evidence](Tickets/T-090.md) · [owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-090 responsive chrome, menus, tabs and licensed icons (2026-11-06; engineering Done):**
Standalone `canvas_items` now expands with aspect instead of fixed-size side
pillars (tested 800×600/1280×760/1920×1080 and 150–200% UI scale on Xvfb/Mesa).
Object file actions and Close tab live in File, Window owns workspace settings,
per-tab × clicks retain nonactive-tab dirty close prompts, Ctrl+N still creates
new documents, and Brush px hover wheel/`[`/`]` update the brush width while
Shift+wheel scrolls crowded settings. The six tool SVGs are sourced byte-identically
from the bundled MIT at-icons/control family, with attribution included in both
standalone/consumer packages. A **24-check** native framebuffer/pointer run
(**29** with optional screenshots), seven focused Python contracts, the 75-check
T-063 compact native regression and eight keyboard checks pass locally.
Hardware Windows/Linux owner findings **#03/#04/#06/#08/#09 remain PENDING**;
no manual review was approved. [Ticket](Tickets/T-090.md) ·
[owner matrix](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-093 discoverable standalone Object sources (2026-11-06; engineering Done):**
File now distinguishes Drawing open, portable Object source open/new, and bitmap
import; the Asset Browser has a visible exact `Objects/` root, choose-folder
button, empty/invalid/duplicate source explanations, and opt-in recent root.
The versioned recent-folder preference is app-only and **never automatically
binds or scans** an Atlas project at launch. A 56-check headless model plus
27 native Xvfb/Mesa pointer/framebuffer checks pass locally; old T-065
portable and Atlas source tests remain separate. T-065 manual review and
owner finding #21 remain **PENDING**, and no NULL-placement policy is changed.
[Ticket](Tickets/T-093.md) · [runbook](DRAWING_OWNER_ACCEPTANCE_MATRIX.md).

**T-084 PhotoCraft source investigation completed (2026-11-06):** [report](PHOTOCRAFT_RENDERING_RESEARCH.md) pins the CPU detached live-preview document, 64x64 brush coverage, 256x256 GPU resident tiles, dirty rendering, motion batching and preview-adopt-on-commit. No runtime benchmarking was conducted in this research; do **not** conflate source architecture with proven hardware latency. T-085 is now In Progress with GDScript live-draft witnesses; T-086 is In Progress with source-space cache software witnesses; T-068 native research remains conditional.

## Kanban summary

**T-068 standalone portable-release isolation gate (2026-11-04; In Progress):**
A new source-staging, exported ELF/PE and Godot PCK verifier rejects a missing
pack, wrong x86_64 architecture, native extension sidecars, source/Atlas leakage,
and failing headless Linux starts. Fast CI invokes it on the real standalone
Linux export using a fresh working directory and disposable user profile; a
Windows export receives structural inspection only until run on Windows.
Local contracts and independent staging pass; the sandbox has no export
**templates**, so a new Linux/Windows release pass is **not claimed here**.
This does not establish physical GPU/VRAM, native-backend adoption or portable
Windows runtime acceptance. [Ticket](Tickets/T-068.md) ·
[release gate](../tools/benchmarks/t068_release_gate.py).

**T-068 counterbalanced software-frame contention witness (2026-11-04; In Progress):**
A separate opt-in Linux X11 **idle → loaded → loaded → idle** experiment runs
four fresh 25-gesture Godot 4.8b2 framebuffer witnesses (324/324 checks), with
two independently verified CPU-busy workers. Both order-specific loaded-minus-idle
contrasts are retained per workload; the two-run contrast averages range from
**+2.768 to +10.553 ms** here, opposite in direction to the earlier fixed-order
software witness. This exposes measurement sensitivity, **not a causal load penalty**:
five samples/workload/session, software llvmpipe, session drift, and no physical
pointer-to-photon/VRAM/Windows measurements remain. Source-pinned replay checks
all 100 synthetic gestures, raw timing statistics, RSS/HWM, worker activity,
GPU profile and counterbalance order. T-068 remains In Progress.
[Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_visual_counterbalanced_software.json).

**T-068 software-rendered visual-frame contention diagnostic (2026-11-04; In Progress):**
An opt-in Linux X11 experiment now runs **two fresh 25-gesture Godot 4.8b2
framebuffer witnesses**, first idle and then with a verified CPU-busy
subprocess. Both pass **81/81 canonical framebuffer/revision assertions** and
retain per-gesture dispatch/frame samples plus whole-Godot-process RSS/HWM.
The background worker consumed 185 Linux CPU ticks; all loaded-phase
five-sample frame medians were lower, a result strongly susceptible to fixed
phase order/cache effects, so no attributable speedup or jitter bound exists.
The complete source-pinned software-only record has replay/tamper checks and cannot count for physical input-to-photon,
GPU/VRAM, Windows, or native backend acceptance. T-068 remains In Progress.
[Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_visual_contention_software.json).


**T-068 Godot visual-frame and process-RSS diagnostic (2026-11-04; In Progress):**
An opt-in X11 runner now captures **25 paired synthetic input-to-`frame_post_draw` / CPU-dispatch trials**, Godot framebuffer-pixel and revision checks (81/81), and sampled **whole-Godot-process VmRSS/VmHWM**. The pinned Xvfb/Mesa llvmpipe run is **software-only**; derived medians/p95, sample maxima, source hashes, and GPU identity gates have fail-closed replay tests. This is neither a physical input-to-photon or VRAM measurement nor a native backend decision. [Ticket](Tickets/T-068.md) · [software evidence](benchmarks/T068_2026-11-04_visual_process_software.json).


**T-068 isolated Linux native process-memory screen (2026-11-04; In Progress):**
A new opt-in, source-pinned Linux `/proc` diagnostic spawns **12 fresh Python
workers** (two independent runs × scalar/Blend2D × 512/1024/2048²) for the
*same* 4px long-stroke buffers and tests exact Godot-authored coverage and
canonical RGBA8 before accepting memory samples. Preprepared buffer/worker
high-water RSS growth during the native call ranges **23.79–23.80 MiB scalar**
versus **24.40–24.52 MiB Blend2D** at 2048². This includes native temporary
allocations and process behavior, **not** isolated C++ heap, Godot RAM, VRAM,
Windows process memory or device measurements. No backend selection or ticket
closure is claimed. [Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_native_process_memory.json).


**T-068 matched scalar/Blend2D brush benchmark (2026-11-04; In Progress):**
A new opt-in, counterbalanced 2-run comparison times the **same preallocated
Python→C++ ABI call boundary** for the detached scalar brush and Blend2D 0.21.2
at threshold 128. Ten Godot-authored hard-brush cases (six 32² and four 512²)
are validated against identical canonical straight-RGBA8 inputs, paths,
selections and publication-free outputs, with five trials per backend/run.
Scalar matches **20/20** Godot coverage/pixel cases; Blend2D matches **14/20**
(the three non-parity 512² geometries repeat across both runs). This is not a
production speedup or backend decision: the Blend2D mismatches, ctypes overhead,
small samples, no hardware presentation and no Windows evidence remain. T-068
stays In Progress. [Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_matched_brush.json).

**T-068 detached scalar fast-math failure-atomicity fix (2026-11-04; In Progress):**
The C++ scalar brush coverage/RGBA8/sparse-delta research ABI now **rejects
`-Ofast` / `-ffast-math` builds at compile time**. A GCC `-Ofast` reproducer
accepted a NaN brush width (returned zero rather than an input error) and
wrote over the caller's output canary. GCC and Clang strict `-O0/-O2/-O3`
builds instead reject NaN/Inf widths and pointer samples atomically through
all three entrypoints. The full scalar/bridge/sanitizer evidence has been
regenerated against the guarded source, including two isolated Godot 4.8b2
runs per publication mode. This **does not enable or approve** a native
runtime backend or satisfy Windows/hardware acceptance; T-068 remains
In Progress. [Ticket](Tickets/T-068.md) ·
[benchmark report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 detached native ASan/UBSan checkpoint (2026-11-04; In Progress):**
A standalone C++17 harness now instruments the four-corner selection
and scalar hard-brush coverage, RGBA8 and sparse-delta ABIs with
**AddressSanitizer + UndefinedBehaviorSanitizer** under GCC and Clang.
Two runs per compiler verify **1,024 seeded small-tile cases**,
**68 failure-atomic malformed calls**, matching full/sparse RGBA8
reconstruction and output redzones. No sanitizer findings occurred
in these runs. Evidence replays are source-pinned and tamper-checked.
These tests are not arbitrary native memory safety proof or physical
input-to-visible, Windows, GPU, or release acceptance; T-068 stays
In Progress. [Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_native_sanitizer.json).

**T-068 varied-convex selection stress checkpoint (2026-11-04; In Progress):**
A separate deterministic Godot 4.8b2 `AtlasFill._allows_pixel()` oracle now
covers **96 different 24² scopes**, including 3–8-vertex convex polygons,
reversed winding, disabled/empty scopes, four raster densities, mirrored,
rotated and sheared transforms, and near-edge rectangles. The detached C++
quad mask matched **384/384 masks** (GCC `-O2` and Clang `-O3`, two complete
passes each) with zero missing or extra pixels. A source/fixture-pinned replay
rejects forged evidence and tests invalid-buffer failure atomicity; CI
regenerates the Godot oracle. This remains **research evidence**, not a
claim about arbitrary polygons, Windows, 64-bit Godot geometry, physical
latency, or native-backend approval. T-068 stays In Progress.
[Ticket](Tickets/T-068.md) ·
[evidence](benchmarks/T068_2026-11-04_quad_stress.json).

**T-068 strict GCC/Clang native selection ABI checkpoint (2026-11-04; In Progress):**
The test-only convex four-corner C++ kernel now rejects `-ffast-math` and
`-Ofast` builds: GCC fast-math can elide NaN/Inf rejection and overwrite
output buffers. Source-pinned GCC/Clang `-O0/-O2/-O3` builds matched all
**576/576 Godot oracle masks** across two passes per profile and rejected
**42/42 invalid ABI calls** without output modification. Both unsafe
compiler configurations failed at build time. Fresh Godot GDExtension runs
preserve **62/62 scope** and **153/153 publication** checks per run, twice.
This is **not** Windows/hardware performance or production backend approval;
T-068 remains In Progress.
[Ticket](Tickets/T-068.md) ·
[compiler evidence](benchmarks/T068_2026-11-04_quad_compiler_matrix.json).

**T-068 near-boundary native four-corner compatibility checkpoint (2026-11-04; In Progress):**
The detached scope kernel now follows the pinned Godot 4.8b2 float32
`Vector2` / segment-intersection **approximate boundary** behavior instead of
strict double-precision ray crossings. The **48 seeded 32² transformed
selection cases now match all 53/53 Godot masks**, twice, with **zero missed
or extra pixels**; the original 15/15 exact-edge 64² fixture still matches.
Two real isolated GDExtension runs confirm **62/62 native mask checks** and
**153/153 selection-to-`DrawingDocument` publication checks per run**,
including source-byte validation and Undo/Redo. The previous **16 cases / 247
omissions** are preserved in the
[historical strict-double evidence](benchmarks/T068_2026-11-04_quad_differential_strict_double.json)
and are not passed off as current results.
This is **not native backend acceptance**: float64 builds, arbitrary polygons,
physical latency, memory/VRAM, Windows, and portable native exports remain
unverified. T-068 stays In Progress.
[Ticket](Tickets/T-068.md) ·
[current two-run differential](benchmarks/T068_2026-11-04_quad_differential.json).

**T-068 native four-corner scope to revision-checked document publication (2026-11-04; In Progress):**
A new explicit-load, temporary Godot 4.8 beta 2 GDExtension witness
composes the already checked **native convex four-corner selection mask** with
native scalar sparse brush records, then validates and stages them through
**actual `DrawingDocument` atomic publication**. All 15 independently
Godot-authored 64² scope cases pass **153/153 checks in each of two runs**,
including exact RGBA8, hidden-RGB source preservation, one transaction,
Undo/Redo, and `NO_CHANGE` rejection without history or revision updates for
zero-record masks. A source-pinned, independently reconstructed Python replay
rejects modified geometry, pixels, source, history or assertion counts.
This is a test-only Linux extension, **not** deployed Atlas integration,
physical latency evidence, or acceptance of the native backend.
[T-068](Tickets/T-068.md) ·
[two-run evidence](benchmarks/T068_2026-11-04_quad_publication.json).

**T-068 native sparse-brush cancellation/conflict gate (2026-11-04; In Progress):**
A **separate opt-in Godot↔C++ sparse brush publication witness** now checks
actual C++ changed-pixel records against a Godot-authored paint oracle before
publication, then exercises cancellation, stale revisions **before** and
**after** detached staging, and forged source-before pixels at an unchanged
revision. Two isolated Godot 4.8 beta 2 runs pass **37/37 assertions each**;
no rejected candidate modifies published pixels or history, and the competing
successful edit remains undoable. An independent Python RGBA8 reconstruction
and tamper validator check all four recorded cases. This is not a production
backend, parallel thread stress, hardware timing, or manual acceptance.
[T-068](Tickets/T-068.md) ·
[two-run evidence](benchmarks/T068_2026-11-04_scalar_atomicity.json).

**T-068 512/1024/2048 native sparse brush document publication (2026-11-04; In Progress):**
An opt-in **separate large-tile Godot↔C++ benchmark** now compares canonical
`DrawingEditSession.paint_path()` + commit against native sparse generation,
checked decode, detached staging and the same revision-checked commit.
One 4px horizontal stroke per 512²/1024²/2048² storage tile is independently
reconstructed to exact source-over RGBA8, including an untouched alpha-zero
hidden-RGB pixel. Two complete runs pass **146/146 correctness checks each**;
each case retains four alternating-order paired CPU timings, exact published
pixels, Undo/Redo, wire sizes, source digests and capacity rejection. Native
path medians are **slower at 1024² and 2048²** in both runs. These are
headless CPU diagnostics, **not a native-backend performance win**, physical
input-to-visible latency, VRAM or release acceptance. No production extension
or ticket status was changed. [T-068](Tickets/T-068.md) ·
[two-run raw evidence](benchmarks/T068_2026-11-04_scalar_large_publication.json).

**T-068 native four-corner Atlas scope through Godot GDExtension (2026-11-04; In Progress):**
The temporary, explicit-load Godot 4.8 beta 2 extension now exposes a checked
C++17 **native convex polygon/whole-pixel selection-mask builder**, then feeds
its returned 0/1 mask into the existing scalar sparse brush. It matches all
**15 Godot-authored 64² `AtlasFill._allows_pixel()` masks byte-for-byte** in
each of **two independent 55-check runs**, including exact edge/vertex ties,
rotation, shear, mirroring, nonuniform density, disabled/empty selections.
Every sparse brush output is validated against the selected pixel set and
independently reconstructed canonical RGBA8, preserving transparent hidden
RGB. Invalid transforms, polygon wire data, dimensions and scope flags reject
without modifying the source. This remains a **separate Atlas-scope research
screen**: the regular `DrawingSelection` path still constructs its mask in
Godot, and no production application or release loads this extension.
[T-068](Tickets/T-068.md) ·
[two-run evidence](benchmarks/T068_2026-11-04_quad_gdextension.json).

**T-068 transformed-view native sparse brush publication (2026-11-04; In Progress):**
The explicit-load, temporary Godot 4.8b2 GDExtension now verifies six
**32²/64² transformed hard-brush and mask cases** against independent
`DrawingEditSession.paint_path()` output: identity rectangle, 90° rotation
with inverted selection, sheared sparse-mask erase, mirrored crossing path,
nonuniform inverted sparse erase and zoom/pan dab. Two complete bridge runs
passed **110/110 new assertions each** with identical canonical SHA-256
outputs and sparse counts. Native output is decoded and checked against all
Godot RGBA8 bytes *before* revision-checked staging; undo/redo and capacity
rejection pass. The client computes the binary `DrawingSelection` mask and
inverts view transforms; this **does not test a native four-corner Atlas
polygon clipper** or provide physical latency or release proof. Runtime
backend and ticket status remain unchanged. [T-068](Tickets/T-068.md) ·
[two-run native evidence](benchmarks/T068_2026-11-04_scalar_transform.json).


**T-068 counterbalanced Godot/native brush publication evidence (2026-11-04; In Progress):**
The temporary opt-in Godot 4.8b2 GDExtension benchmark now alternates
**Godot-first and native-first** execution order on *fresh identical
DrawingDocument sources*. Two warmups and six paired timed trials (three per
order) cover six 32²/128²/256² short/crossing 4px strokes in each of two
independent runs. Both pass **536 correctness assertions**; exact raw
per-trial stage durations, order, phase totals, and recomputed distributions
are pinned and reject tampered evidence. An untimed Godot oracle is
precomputed before the timed pairs; sparse bytes are checked against it before
native staging. The 256² crossing-stroke run medians
were **18.955–21.991 ms canonical vs 13.371–13.631 ms native path**. This
reduces the previous fixed-order bias but does not prove a speedup: the
results remain headless CPU-only, small-sample, prepacked-geometry diagnostics
excluding rendering, GPU and physical input-to-visible latency. No production
backend, manual gate or other ticket changed. [T-068](Tickets/T-068.md) ·
[paired evidence](benchmarks/T068_2026-11-04_scalar_publication.json).


**T-068 optional scalar brush through real Godot GDExtension (2026-11-04; In Progress):**
The detached C++17 hard-brush sparse ABI now executes through the existing
**temporary, explicit-load Godot 4.8 beta 2 GDExtension** using an 8-argument,
capacity-bounded PackedByteArray/float64 path interface. Each of two runs
passed **31 scalar integration checks**, comparing its 63 changed records
(760 bytes instead of a 1,024-byte tile) byte-for-byte with an independent
`DrawingEditSession.paint_path()` on a hidden-RGB source before one
revision-checked document commit. Undo/redo, inverted-size and malformed
calls, sparse mask, zero-alpha no-op and erase are covered. Existing bridge,
revision, document, batch, sparse and marshaling suites also passed in both
runs. This is **not enabled in either app**; the test recomputes canonical
Godot output before publication and supplies pretransformed local geometry.
No real input-to-present, Windows/physical GPU, memory, or portable release
claim is made. [T-068](Tickets/T-068.md) ·
[isolated two-run evidence](benchmarks/T068_2026-11-04_scalar_gdextension.json).

**T-068 bounded scalar sparse hard-brush payload (2026-11-04; In Progress):**
A detached C++17 hard-brush kernel now emits only changed canonical RGBA8
pixels as ordered, checked 12-byte before/after records plus a 4-byte count,
using the existing isolated bridge wire format. Across two independent passes
all **62/62 small/large Godot-oracle-derived comparisons** reconstruct exact
final RGBA8; no-op paint emits four bytes. A 2048² 4px stroke produces 5,524
wire bytes versus 16 MiB full-tile output, **not a measured marshaling or GPU
speedup**. Bounded capacity and malformed/aliased buffers fail atomically.
The prototype is not linked into Godot, and hardware/release gates remain open.
[T-068](Tickets/T-068.md),
[two-run sparse evidence](benchmarks/T068_2026-11-04_scalar_deltas.json).

**T-068 scalar native hard-brush canonical RGBA8 checkpoint (2026-11-04; In Progress):**
The detached C++17 hard-brush comparator now returns both the full 0/255
gesture coverage bitmap and detached **straight-RGBA8 pixels**. Two passes
over 28 pinned Godot geometry cases show **62/62 exact coverage and RGBA8
comparisons**, including source-over, erasure, transparent hidden RGB,
selection masks, crossing and 512/1024/2048-scale strokes. The 16 small cases
match **actual Godot output hashes**; the 12 large Godot oracles supply
coverage only, with compositing independently checked on the native scaling
benchmark's patterned source. C++ rejects buffer aliases and malformed input
atomically; no Godot GDExtension, document publication, texture upload,
hardware-performance or release acceptance is claimed. [T-068](Tickets/T-068.md),
[two-run compositing evidence](benchmarks/T068_2026-11-04_scalar_rgba8.json).

**T-068 dependency-free C++ hard-brush geometry parity (2026-11-04; In Progress):**
A detached scalar C++17 pixel-center / swept-segment comparator now returns
exact binary once-per-gesture coverage with checked input buffers and local
selection masks. Compared against the real Godot 4.8b2 brush oracles, two
independent runs produce **62/62 identical masks** across sixteen 32²
brush/selection/transform cases and twelve 512²/1024²/2048² workloads.
This closes the *tested scalar geometry screen*, not the application path:
canonical small-case RGBA8 is independently reconstructed, while large cases
compare coverage on empty-source gestures. No Godot GDExtension integration,
publication/texture timing, Windows/GPU memory/p95 or portable binary proof
is claimed. [T-068](Tickets/T-068.md),
[two-run scalar evidence](benchmarks/T068_2026-11-04_scalar_hard_brush.json).


**T-068 inclusive exact polygon-edge scope checkpoint (2026-11-04; In Progress):**
The research-only Blend2D C++ four-corner mask now accepts points exactly on
convex boundary segments, consistent with Godot's boundary-inclusive polygon
predicate. Seven additional Godot-authored 64² fixtures (axis-aligned edge,
reversed winding, rotation, shear, nonuniform density, diamond and one-pixel
strip) extend the existing eight to **15 cases**. Two independent native runs
show **30/30 byte-exact masks** with zero coverage differences; the thin
boundary-aligned strip accepts exactly 64 eligible pixels. This resolves the
previous demonstrated aligned-edge mismatch for pinned cases only; floating
near-edge tolerance and broader transforms remain unproven. No runtime backend
was adopted, and physical GPU/release gates remain open.
[T-068](Tickets/T-068.md), [two-run scope evidence](benchmarks/T068_2026-11-04_blend2d_quad.json).

**T-068 native transformed four-corner scope checkpoint (2026-11-04; In Progress):**
The detached Blend2D C++ brush comparison now computes a fail-closed binary
selection mask from **all four transformed pixel corners**, with an independent
Godot `AtlasFill._allows_pixel` oracle. Two runs × eight 64² convex scope cases
(identity, rotate, shear, mirror, nonuniform density, diamond, disabled/empty)
produce **16 exact mask matches**; native composition preserves hidden RGBA8.
Fixtures intentionally avoid exact polygon boundary ties (an aligned probe
differed at 43 pixels). Neither Blend2D hard-brush geometry, Godot publication,
physical GPU/frame timing nor desktop release validation is established.
[T-068](Tickets/T-068.md), [two-run quad evidence](benchmarks/T068_2026-11-04_blend2d_quad.json).


**T-068 large-tile Godot-vs-native brush geometry checkpoint (2026-11-04; In Progress):**
A Godot 4.8b2 `DrawingEditSession` oracle at signed anchors beyond 2^53
now covers all **12 full-size 512²/1024²/2048²** Blend2D scaling workloads,
with zoom, 90° rotation, shear, masks, erasure and transparent no-op. Comparing
its independently compressed coverage against both verified native runs yields
**24 comparisons: 18 coverage non-parity and 12 canonical final-pixel
non-parity cases** at 50% A8. All six 4px-stroke comparisons match; 256px
dabs each miss 36 covered pixels, and the no-op retains exact RGBA8 despite a
coverage difference. This reuses the old native timing runs, **not** matched
Godot timing or transformed four-corner selection clipping. T-068 remains open
for those and hardware/release gates. [T-068](Tickets/T-068.md),
[comparison evidence](benchmarks/T068_2026-11-04_blend2d_large_parity.json).


**T-068 native Blend2D 512/1024/2048 scaling checkpoint (2026-11-04; In Progress):**
The pinned detached C++ A8 brush shim now accepts bounded **512², 1024² and
2048²** straight-RGBA8 tiles (including allocation and timing-pointer alias
failure guards). Four fixed 128/256-local-region gestures per size cover 4px
strokes, 256px round dabs, self-crossing sparse-mask erase and an alpha-zero
no-op. Two runs × three trials produce **24 independently reconstructed
full-output comparisons** and 72 native calls. The 2048² full output is
**16 MiB** even with only 460 changed pixels; the same hypothetical four
128² display tiles would total **256 KiB** of full updates, *not measured
Godot uploads*. Native call timings rise materially with whole-tile size;
no Godot large-brush geometry parity or end-to-end speedup is claimed.
[T-068](Tickets/T-068.md),
[two-run evidence](benchmarks/T068_2026-11-04_blend2d_scale.json).

**T-068 native Blend2D hard-brush and selection comparison (2026-11-04; In Progress):**
The pinned 0.21.2 C++ A8 path rasterizer is now screened against **16 actual
Godot-generated hard-brush fixtures** per threshold, including far signed
anchors, view-to-local transforms, inverted/sparse selections, once-per-gesture
coverage, erasing and transparent hidden RGB. Blend2D's coverage is thresholded
and selected **inside the detached native shim**, then composited once with
canonical straight-RGBA8 math (no premultiplied round-trip). Two independent
seven-trial runs produce **64 comparisons**: at alpha threshold 128, **14/16**
cases have exact Godot coverage and RGBA8; inverted-selection variants each
miss one pixel. At threshold 1, all 16 cases overpaint and 15 alter final
RGBA8 (the alpha-zero no-op remains exact). Source, fixture and native outputs
are independently checked; runtime adoption, transformed four-corner clipping,
GDExtension publication, Windows/Linux physical frame/VRAM and release gates
remain open. [T-068](Tickets/T-068.md),
[raw two-run evidence](benchmarks/T068_2026-11-04_blend2d_brush.json).

**T-068 measured Godot↔C++ transfer boundary (2026-11-04; In Progress):**
The isolated pinned Godot 4.8b2 GDExtension now runs a fail-closed transfer
microbenchmark on 32²/128²/256² canonical tiles, with one-point, sparse and
dense overlapping masked source-over workloads. Both runs pass **731/731**
marshal checks, in addition to the existing native/document witnesses. Exact
RGBA8 and sparse-delta completeness are checked against independent full-buffer
reconstruction *before timing*. For 256²/one-change, the native sparse return
is **16 bytes versus 262,144 bytes** for whole-tile output, and its call median
was **1 µs versus 15–16 µs** across the two runs; at 256²/dense, sparse was
not consistently faster. These isolated, precovered calls are **not**
canonical document-publication or physical input-to-display measurements.
[T-068](Tickets/T-068.md), [two-run evidence](benchmarks/T068_2026-11-04_gdextension_marshal.json).

**T-068 transformed Skia brush/selection oracle (2026-11-04; In Progress):**
Five new fixtures send **non-identity view-space pointer samples** through
Godot's real `DrawingEditSession` (zoom/pan, 90° rotation, x-mirroring,
nonuniform scale, shear), retaining raster-local brush width and selection
masks at signed world anchors beyond 2^53. The independently validated
schema-2 oracle checks view-to-raster inversion, canonical exact RGBA8,
unchanged hidden RGB and baseline-transform equivalence. Two pinned Skia CPU
runs now cover **32 cases**: **eight** stencil coverage non-parity cases and
**six** final-pixel non-parity cases, including the previously known
one-pixel self-crossing gap under mirroring. This is a Python inversion
and postmask screen, **not** a native transform/clip or Godot marshaling
benchmark; no backend selection or hardware acceptance is claimed.
[T-068](Tickets/T-068.md), [two-run evidence](benchmarks/T068_2026-11-04_skia_brush.json).

**T-068 pinned Skia hard-brush/selection oracle (2026-11-04; In Progress):**
A deterministic 11-case fixture is generated by the **real Godot 4.8b2
`DrawingEditSession`** at signed anchors beyond 2^53, then independently
reconstructed as exact straight-RGBA8 in Python. The optional Skia 144.1
A8 hard-stroke and direct RGBA8 screens cover dabs, axis/diagonal strokes,
self-crossing and batched overlaps, rectangle/sparse/inverted selections,
erase with hidden RGB and zero-alpha no-op. Two seven-trial runs give **22
comparisons**: **six** coverage non-parity cases (the same one-pixel miss
on each self-crossing variant per run); **four** direct RGBA8 non-parity
cases, with no changes in the zero-alpha no-op. All selected hard-pixel
single/axis/diagonal/erase cases matched; selected pixels are **postmasked
in Python**, not native Skia selection clipping. The one-pixel gap persists
even if canonical blending is applied after Skia's stencil, so Skia is not
an exact drop-in hard-brush backend. [T-068](Tickets/T-068.md),
[reproducible evidence](benchmarks/T068_2026-11-04_skia_brush.json).

**T-068 pinned Skia 144.1 CPU pixel/shape screen (2026-11-04; In Progress):**
The owner-supplied, SHA-256-verified **CPython 3.13 Linux wheel** was used
outside the repository for an optional CPU-only comparison. Two nine-trial
runs checked **126 rectangle scenarios** across 32²/64²/128² surfaces,
three transfer modes and seven operations against the checked C++ kernel and
canonical straight-RGBA8 oracle. **60** scenarios disagreed; direct
unpremultiplied RGBA8 matched six fixed-case operations and retained all
untouched hidden RGB, but zero-alpha color replacement failed and seeded
random source-over revealed two changed-pixel rounding mismatches per run.
Antialiased and hard path footprints are only capability screens, **not**
canonical brush parity. Skia remains unadopted; T-068 still needs native C++
path/marshal, physical Windows/Linux timings and release gates.
[T-068](Tickets/T-068.md), [raw evidence](benchmarks/T068_2026-11-04_skia_cpu.json).

**T-068 pinned Blend2D CPU conversion/parity screen (2026-11-04; In Progress):**
User-supplied, SHA-256-verified Blend2D **0.21.2** with bundled AsmJit
was built locally as a *manual-only* CPU compositor. Two 9-trial runs across
32²/64²/128² rectangles, six operations and two conversion scopes checked
**72 scenarios** against the existing checked C++ kernel and independent
straight-RGBA8 oracle. Opaque painting and bounded-region clear were exact;
**42** scenarios showed format/rounding mismatch. Clipping conversion to the
edit rectangle preserves all outside hidden RGB, **not** exact translucent
source-over/replace pixels. Blend2D was **not adopted**; T-068 remains open
for Skia, real shapes, portable native/physical timings, and release gates.
[T-068](Tickets/T-068.md), [raw evidence](benchmarks/T068_2026-11-04_blend2d_cpu.json).

**T-068 optional Cairo CPU comparator (2026-11-04; In Progress):**
A standalone, runtime-versioned Cairo 1.18.4 experiment tests a *third-party
CPU rasterizer* against the checked scalar C++ kernel and independent canonical
straight-RGBA8 oracle. Two 9-trial runs cover 32²/64²/128² half-tile
rectangles, opaque and translucent source-over, replacement, transparent
no-op, and clearing (**36 verified scenarios**). Opaque operations reproduce
canonical pixels, but premultiplied ARGB32 conversion destroys hidden RGB
outside painted areas and most translucent cases disagree. It is **not**
Blend2D/Skia acceptance, nor a production fallback; it runs on demand and
fast CI checks only the Python contracts. [T-068](Tickets/T-068.md),
[raw evidence](benchmarks/T068_2026-11-04_cairo_cpu.json).

**T-068 complete native sparse-delta verification (2026-11-04; In Progress):**
The isolated GDExtension adapter now independently checks the **complete**
requested change set, not just the returned delta records. A forged zero-count
or partial response cannot silently discard requested pixels or partially
publish a multi-tile edit. The targeted witness passes 173 checks per run;
fast CI validates the runner and the native test remains on demand. O(N)
canonical verification adds CPU work and no speedup is claimed. T-068's
production/native and physical-hardware gates remain open. See
[T-068](Tickets/T-068.md) and the
[sparse evidence](benchmarks/T068_2026-11-04_sparse_completeness.json).


**T-068 experimental sparse-delta GDExtension publication (2026-11-04; In Progress):**
The opt-in checked C++ bridge can return a length-prefixed sequence of
(index, exact-before, exact-after) pixel records rather than an entire RGBA8
output tile. A separate adapter validates records against the SHA-verified
source, declared operation, eligible points/mask and uniqueness before it
stages one canonical DrawingDocument history transaction across up to 16 tiles.
The isolated native witness checks whole-output parity, malformed-response
rejection, signed-64-bit bounds, lazy tile recovery and Undo/Redo, including
synthetic sparse-vs-full staging timings and return-byte counts. The bridge is
**manual-only**, with fast-CI runner contracts; it is not installed in the
application, and no physical speedup/backend approval is claimed. T-068
remains In Progress. See [T-068](Tickets/T-068.md) and the
[benchmark report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 atomic multi-tile native publication witness (2026-11-03; In Progress):**
An isolated checked C++ GDExtension now stages multiple verified native tile
outputs into **one** canonical DrawingDocument gesture, preserving one Undo/Redo
entry and per-tile signed-integer dirty regions. It caps aggregate full-tile
work at 1,048,576 pixels / 16 tiles, fails closed on corrupt/lazy sources,
duplicate targets, bad native output, revision conflicts and locked layers,
and never publishes partial batches. The dedicated **128-check** Godot witness
is manual-only; fast CI checks runner isolation without loading native code.
No production integration, performance gain, physical-hardware acceptance or
backend decision is claimed. [T-068](Tickets/T-068.md) remains In Progress.


**T-068 real DrawingDocument publication witness (2026-11-03; In Progress):**
The optional checked C++ raster GDExtension now feeds a detached native tile
through the *actual* `DrawingEditSession.apply_region()` and
`DrawingDocument._publish_edit()` path in a disposable Godot project. Two
independent runs pass **443/443** native parity, **370/370** texture-publication
and **219/219** canonical document/history checks each. Real undo/redo,
dirty regions, negative/far signed tiles, lazy digest failures, locks,
no-op and stale/concurrent commits are exercised. This is **not** production
UI/backend adoption; copying a whole tile through GDScript is intentionally
unoptimized and does not establish a native speedup. T-068 stays In Progress.
See [T-068](Tickets/T-068.md) and
[raw evidence](benchmarks/T068_2026-11-03_gdextension_document.json).

**T-068 revision-guarded experimental native publication (2026-11-03; In Progress):**
The opt-in Godot/C++ bridge now has an isolated GDScript publication adapter
that rejects stale revisions and changed source bytes, reports exact changed-
pixel bounds, preserves the caller's RGBA8 buffer and updates a full
`ImageTexture` only after a successful single-threaded commit. Two Godot
4.8b2 runs pass **443 native bridge checks and 370 publication/GL readback
checks each**, using temporary project Xvfb/Mesa for reliable texture readback;
fast CI only runs five non-native runner contracts. This is **not** production
`DrawingDocument` publication, actual dirty-subrectangle upload, hardware
latency, or final native adoption. T-068 stays In Progress. See
[T-068](Tickets/T-068.md) and [raw evidence](benchmarks/T068_2026-11-03_gdextension_revision.json).

**T-068 isolated GDExtension bridge milestone (2026-11-03; In Progress):**
A throwaway Godot 4.8 beta 2 project now compiles a bounded checked raster
batch bridge directly against the engine-generated GDExtension header. Two
runtime runs pass 443/443 exact-pixel and error-boundary checks, without
shipping or auto-loading any native library in Drawing or Atlas. The editor
scan of the experimental extension is unstable, so only an explicit isolated
runtime load is tested. Four harness contract tests run in fast CI; the full
bridge is on-demand only. Physical-device, native publication, library
comparators, and the final backend decision remain open. See
[T-068](Tickets/T-068.md) and [raw runs](benchmarks/T068_2026-11-03_gdextension_bridge.json).

**T-068 bounded native-kernel ABI checkpoint (2026-11-03; In Progress):**
The unintegrated C++ raster kernel now has opt-in length-checked delta and
full-region functions, without changing its original ABI 1. A six-test fast-CI
contract suite checks 160 seeded source/operation cases against the original
functions, output canaries, partial alias rejection, short buffers and failure
atomicity. Caller-declared byte lengths cannot authenticate foreign pointers;
no native Godot integration, physical-device evidence or backend decision is
claimed. See [T-068](Tickets/T-068.md) and the
[CPU raster report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 isolated native-thread jitter milestone (2026-11-03; In Progress):**
Two runs of the unintegrated C++ raster kernel now compare 1/2/4 concurrent
workers with private RGBA8/source and output buffers, across blend, masked
erase and exact replacement. All 36 timed cells verified exact output parity;
the 2-test native/parser contract joins fast CI. Contention p95 varied and
cannot justify adopting a multithreaded Godot backend. See
[T-068](Tickets/T-068.md) and [the benchmark report](DRAWING_CPU_RASTER_BENCHMARK.md).


**T-068 longer software-frame and Linux RSS checkpoint (2026-11-03; In Progress):** Two 21-trial-per-size native Bucket-adapter processes passed **770/770** visual/canonical checks; Linux `/proc` tracked only the actual Godot executable (VmHWM **251,288/251,420 KiB**). Empirical CPU and `frame_post_draw` medians/p95s are recorded with raw trial samples, and the manual-only workflow now captures process RSS alongside screenshots. This is not production Bucket UI, physical scan-out, per-fill memory isolation or native backend acceptance. Fast CI adds five process-profiler contract tests but no framebuffer sweeps. See [T-068](Tickets/T-068.md) and [raw evidence](benchmarks/T068_2026-11-03_fill_linux_rss.json).

**T-068 measured canonical Bucket fill-to-frame on software GL (2026-11-03; In Progress):** New targeted native `drawing_fill_frame_native.gd` sends 15 synthetic GUI click gestures through a narrow **test adapter** into the real Drawing flood-fill transaction and renderer; it verifies exact deltas, visible framebuffer pixels and atomic budget rollback. Two five-trial runs pass **96/96** (with screenshot) and **95/95** checks. Results now include CPU-dispatch, `frame_post_draw` and sampled Godot memory monitors, but **do not** represent production Bucket UI, physical input, scan-out or peak RAM/VRAM. A workflow-dispatch-only Linux/Mesa action can reproduce the witness without changing fast CI. The native-backend, hardware and comparative performance gates of [T-068](Tickets/T-068.md) remain open. See [raw evidence](benchmarks/T068_2026-11-03_bucket_frame_native.json).

**T-068 verified-fill staging (2026-11-03; In Progress):** The Drawing flood-fill path now passes its already-validated source pixel into the detached staging operation instead of re-reading that pixel from the source tile; all ordinary editing tools retain normal source reads. A new **29-check** fast-CI witness covers mixed edits in one session, budget rollback, precise hidden RGB and signed 64-bit coordinates, Undo/Redo and stale-publication refusal. The 15-suite **1,832-check** headless regression and 81-check native software-frame brush witness pass; paired CPU-only timings are encouraging but too limited for a production performance claim. T-068 native-backend, Windows/Linux physical, memory/jitter, and external-library acceptance remain open. See [T-068](Tickets/T-068.md) and the [measurement report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 unique-candidate flood-fill frontier (2026-11-03; still In Progress):**
Four-connected Bucket fills now mark each candidate when enqueued, rather
than repeatedly appending already queued positions. Work budgets count
unique examined positions, including transparent/selection boundary pixels;
original source colors, publication, masks and Undo/Redo are unchanged. A
56-check headless fixture uses an independent grid oracle and exact-budget
retry; it joins the existing fast-CI T-068 step. Two ordered baseline/follow-up
CPU microbenchmarks show **mixed** results, not a reliable latency improvement.
Native library and hardware gates remain open. See [T-068](Tickets/T-068.md)
and [CPU report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 cached and lazy-safe flood fill (2026-11-03; still In Progress):**
The bounded Drawing Bucket engine now resolves each verified source tile once
per gesture, including lazily loaded chunks. Previously resident-only lookup
could incorrectly reject a valid saved seed or stop at an unloaded neighbor.
A 30-check fast-CI witness verifies hidden-RGB pixels, missing/corrupt lazy
providers and retry, selection, exact undo/redo, signed seams and atomicity.
Two before/after microbenchmark pairs indicate lower synthetic CPU fill+commit
medians for 32²–96² pixels, but **not** confirmed input-to-present gains.
Native library evaluation and physical hardware gates remain open; this is
not a backend decision or ticket closure. See [T-068](Tickets/T-068.md) and
[CPU report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 axis-aligned hard-brush sweep geometry (2026-11-03; In Progress):**
The canonical Drawing hard brush now handles exactly horizontal and vertical
nonstationary sweeps with bounded scalar squared-distance tests, preserving
its original row-major candidate order, once-covered blending, masks and
atomic gesture publication. All oblique sweeps continue through Godot's
`Geometry2D` oracle. The new **239-check** fast-CI witness includes original
Geometry2D pixel/RGBA8 parity, signed anchors beyond 2^53, masks, history,
and 320 deterministic randomized geometry cases. A seven-sample isolated
edit+commit benchmark shows **mixed** single-run timings, not a demonstrated
end-to-end speedup. No native backend adoption or physical device results
are implied; [T-068](Tickets/T-068.md) remains **In Progress**.


**T-064 duplicate linked nested child placements (2026-11-03; In Progress):**
The nested Object inspector now offers **Duplicate selected** (Ctrl+Alt+D).
It inserts a new linked child directly above the selected sibling with a
fresh stable child ID/generation, a one-unit parent-local displacement,
independent transform/metadata/visibility and the *same* published source.
The existing structural history supports exact Undo/Redo of this instance
without copying any source artwork. Invalid/stale sources, unsafe offsets,
failed publication and the 64-child graph limit reject atomically.
`tests/object_child_duplicate_smoke.gd` passes **53/53** headless checks,
plus **56/56** targeted native Xvfb/Mesa checks with a 420px inspector
screenshot. This is placement duplication, **not** the unresolved nested
single-source Save As/export reference-versus-deep-copy policy. T-064 remains
In Progress, with owner decisions and hardware validation outstanding.
See [T-064](Tickets/T-064.md).


**T-064 labeled nested child instances (2026-11-03; In Progress):**
The nested Object inspector now permits a 64-character optional label for
**each child instance**, distinguishing repeated uses of the same published
source without renaming or copying its Drawing pixels. Label edits are
parent-owned, version-checked registry publications, share the existing
child-local Undo/Redo with structure/transforms/visibility, and preserve
unrelated metadata. The **56/56** headless witness covers failed/stale edits,
no-ops, duplicates, history, saved registry reload, portable Objects-component
copy and live inspector controls. Its **62/62** targeted native Xvfb/Mesa
witness captures a 420px inspector. The ticket remains **In Progress**:
nested single-source Save As/export graph-copy policy and owner physical UX
validation remain pending. See [T-064](Tickets/T-064.md).

**T-064 reversible sibling paint order (2026-11-03; In Progress):**
The existing nested Object inspector now offers focusable **Send backward**
and **Bring forward** actions (Ctrl+Alt+Up/Down). Later siblings paint above
and win hit-testing over earlier siblings. The operation atomically moves one
existing child record in its parent-owned ordered list, retains source pixels,
identity, transform and other siblings, and shares optimistic revisions,
transitive Atlas preview invalidation and parent-scoped Undo/Redo with the
other nested edits. A dedicated **51/51** fast-CI Godot witness verifies
rendered pixels, hit paths, cache invalidation, invalid/stale/cancelled edits,
mixed history, disk reload and inspector buttons/keyboard. The targeted native
Xvfb/Mesa run passes **52/52** with a reviewed 420px inspector screenshot.
T-064 remains **In Progress** pending nested Save As/export policy and owner
hardware review; no owner gate was inferred. See [T-064](Tickets/T-064.md).

**T-064 reversible nested child scaling (2026-11-03; In Progress):**
The Object Manager nested inspector now offers Shrink/Grow actions for
parent-local scaling of selected linked/NULL child transforms. Scaling changes
only the published affine basis, preserving source pixels, identity, local
origin and child-relative descendants. It shares stale-safe Undo/Redo with
movement, rotation, structure, visibility and NULL repair. The new **42/42**
fast-CI Godot witness exercises nested render/hit paths, rotated/mirrored
bases, veto/stale guards and disk reload; a targeted **43/43** Xvfb/Mesa run
includes a 420px native screenshot. No physical owner UX review or nested
Save As/export dependency-copy decision is implied; **T-064 stays In Progress**.
See [T-064](Tickets/T-064.md).

**T-064 nested child visibility (2026-11-03; In Progress):**
The Object Manager nested inspector now hides/shows a selected child without
removing its stable identity or source pixels. Hidden child subtrees leave
Atlas preview rendering and hit paths, while remaining selectable in the
inspector. One parent-scoped action supports Undo/Redo; stale revisions and
publication vetoes fail closed. A dedicated **39/39** headless test is in
fast CI; the targeted native inspector screenshot witness passes **40/40**.
This is engineering evidence, not physical-device or owner UX signoff;
**T-064 remains In Progress** pending single-source Save As/export policy and
remaining validation. See [T-064](Tickets/T-064.md).

**T-064 saved-campaign copy UI (2026-11-03; In Progress):**
Atlas File → Copy saved campaign… (Ctrl/Cmd+Shift+S) now clones the last
checkpoint into a fresh directory through the verified T-066 campaign-copy
operation. The original stays open; missing checkpoints, unsaved Atlas or
Drawing changes, Object Editor drafts, in-progress gestures, unsafe path
components, stale registries and existing destinations are rejected. A native
modal with parent-directory chooser supports renaming the campaign file; the
new **39/39** headless UI witness is fast-CI-gated (**40/40** with native
screenshot). A compact 420px native layout was inspected. This does **not**
select nested single-asset Save As reference-vs-deep-copy semantics or grant
owner approval. T-064 remains In Progress. See [T-064](Tickets/T-064.md).

**T-064 complete portable campaign copy (2026-11-03; In Progress):**
`AtlasCampaignStore.copy_portable` now copies a verified saved campaign to a
fresh project folder using one staged directory promotion, preserving complete
sparse Drawing generations, physical chunks, fonts, Object source history,
child identities and previous-generation recovery. A renamed campaign is
validated before publication; stale Object indexes, corrupt source roots,
symlinked components, collisions and injected copy interruption fail closed.
The dedicated **46/46** fast-CI headless witness proves independent source and
clone edits. It copies the *saved* project, not unsaved drafts, and does not
choose the still-owner-dependent nested single-asset Save As/export policy.
**T-064 remains In Progress** pending that decision and hardware review.
See [T-064](Tickets/T-064.md).

**T-064 explicit nested NULL repair (2026-11-03; In Progress):**
A missing/deleted nested Object source can now be rebound to an explicitly
selected verified source through the existing child inspector, preserving its
stable child ID, generation, parent-local transform and original missing-source
ID. Repair and parent-local Undo/Redo share one optimistic graph transaction;
indirect cycles, stale child/parent revisions and rejected publications leave
registry bytes unchanged. A dedicated **45-check** headless witness is fast-CI-
gated, with **46/46** checks in the native screenshot run. This does not decide nested
Save As/export graph-copy semantics or grant physical owner acceptance.
**T-064 remains In Progress.** See [T-064](Tickets/T-064.md).

**T-064 nested canvas pointer transforms (2026-11-03; In Progress):**
Alt+drag on a published nested child now stages a transient canvas guide and
commits one immediate-parent-local transform on release, preserving the
existing child inspector Undo/Redo timeline. Descendant rotations and the
root placement's transform are accounted for; Escape, pointer exit, focus
loss, tool/map switch, stale published index or placement and invalid paths
leave all source pixels and child transforms unchanged. The dedicated
`object_child_canvas_drag_smoke.gd` witness is fast-CI-gated (**31/31**
headless checks; **32/32** with native screenshot capture). This is **not** owner/hardware interaction
acceptance; nested Save As/export copying policy remains undecided and
T-064 remains **In Progress**. See [T-064](Tickets/T-064.md).

**T-064 published Objects-component copy (2026-11-03; In Progress):**
`AtlasObjectLibrary.copy_objects_to()` now stages checksum-verified current
published source revisions and an unchanged registry in a separate campaign
directory. Nested child IDs/transforms, source revisions, placements and NULL
bindings remain referential rather than flattened; edits in a copied campaign
remain isolated. A **37/37** real-file headless witness is fast-CI-gated.
This is not a whole-campaign Save As or the still-undecided nested asset
Save As/export policy. Direct canvas transforms and owner/hardware review also
remain open; **T-064 stays In Progress**. See [T-064](Tickets/T-064.md).

**T-064 explicit nested canvas selection (2026-11-03; In Progress):**
Alt+click on a linked nested Object in Atlas now resolves its stable child-ID
hit path, opens the existing parent-local inspector at the actual owning
parent source and selects that child. Normal click retains root selection,
repeat hits retain child Undo/Redo history, and stale map/registry or hidden
ancestors fail closed. The dedicated **21/21** headless witness is fast-CI-gated;
Xvfb/Mesa native UI and optional screenshot pass **22/22**. Direct pointer
transform gestures, nested source Save As/export policy and physical review
remain incomplete; T-064 stays In Progress. See [T-064](Tickets/T-064.md).

**T-064 reversible nested child structure editing (2026-11-03; In Progress):** The existing Atlas child inspector can now attach an explicitly chosen available Object source, remove a selected child reference without deleting its source, and undo/redo structure **and** transforms in one parent-scoped history. Restored instances retain child ID, generation and sibling order; revisions advance monotonically. The new **45/45** fast-CI witness covers cycles, stale revisions, concurrent changes, failed publication and live picker/buttons; the expanded native X11/Mesa inspector witness passes **16/16**. The source picker searches published names/IDs and shows up to 128 matches. Canvas child hit interaction, Save As/export policy and owner/hardware validation remain unfinished; T-064 stays In Progress. See [T-064](Tickets/T-064.md).

**T-064 parent-scoped nested child transform editing (2026-11-03; In Progress):** Atlas's Object Manager now opens a nested-child inspector with stable child instance selection, parent-local moves/rotations, explicit child-source editor navigation, optimistic parent-scoped undo/redo and stale/campaign-switch recovery. Its dedicated headless **45/45** edit/history test runs in fast CI, while a targeted X11/Mesa **10/10** native UI witness captures real window layout. Integrated hit-path selection, Save As/copy policy and owner/hardware acceptance remain unfinished; no other ticket or manual review state changed. See [T-064](Tickets/T-064.md).

**T-064 bounded nested composition milestone (2026-11-03; In Progress):**
The Atlas Object renderer now paints linked parent/child/grandchild sources in
stable order with composed transforms and returns stable child-ID hit paths.
Atlas map previews include the nested extents and invalidate on graph changes
or explicit source Save; deleted child sources show bounded NULL markers.
The fast-CI 36-check `object_child_render_smoke.gd` covers on-disk sources,
rotation, deep paths, alpha, and bounded failures. Nested editing UI,
per-child undo/redo, and the Save As/portable copying policy are still open;
this is **not** T-064 acceptance or owner UX approval. See [T-064](Tickets/T-064.md).

**T-064 cycle-safe nested-source graph milestone (2026-11-03; In Progress):**
Atlas now stores optional stable child-source instances in its existing
published Object registry, validates cycles/depth/IDs on mutation and load,
and persists parent-local transforms and reverse dependencies. Pixel Save
preserves child records; deletion's Remove/NULL policy applies atomically to
nested references, including stale confirmation guards. The new 56-check
headless witness is push-CI-gated. Rendering and hit paths have a separate
bounded engineering witness above; nested editing and portable Save As/export
semantics remain unfinished and cannot be claimed accepted. See [T-064](Tickets/T-064.md).


**T-065 verified metadata page loading (2026-11-03; still In Progress):**
Atlas now inspects the metadata of SHA-verified published sources without
decoding every canonical pixel tile merely to populate a browser page.
Thumbnail, Edit Source and placement paths retain full pixel validation. The
expanded 49-check disk-backed source witness tests the trust boundary; its
short 351 KB CPU diagnostic is not physical Windows/Linux performance evidence.
Owner keyboard/pointer approval remains required. See [T-065](Tickets/T-065.md).

**T-065 real-file source I/O and page cache (2026-11-03; still In Progress):**
The canonical Object Editor now parses each bounded Drawing source once to
validate both pixels and metadata from the same file snapshot. The shared
Asset Browser retains a 24-image bounded LRU across partial Atlas pages,
invalidates changed source revisions and clears previews on campaign change.
A new 31-check fast-CI witness exercises a 351 KB four-tile source and
corrupt-blob/metadata rejection; the thumbnail suite now has 62 assertions.
These are engineering tests, **not** large physical-device campaign/owner UX
acceptance. See [T-065](Tickets/T-065.md).

**T-065 large published-library paging (2026-11-03; still In Progress):**
Atlas's shared Asset Browser now filters names and stable IDs across the
**entire published registry**, instead of losing all sources after the first
512. A metadata-first search selects one 64-source page for verified file
opening/thumbnail work, with Previous/Next, clamped page navigation and a
matching-source count. The new 1,428-check fast-CI witness includes 1,301
synthetic and 66 real published sources, plus a 10,000-summary upper-bound
exercise; prior browser and Atlas registry regressions passed. The native Atlas UI
passes 12/12, and its real XTEST pointer gesture passes 19/19 again after
page controls were introduced.
Standalone portable scanning retains its separate bounded safety policy.
Physical-device/large-real-file latency and **owner UX approval** are still
outstanding; T-065 remains In Progress. See [T-065](Tickets/T-065.md).

**T-065 Atlas shared-browser drop bridge (2026-11-03; still In Progress):**
The canonical Drawing Asset Browser is now embedded as an optional Layers
section in Atlas, showing published `Objects/` sources with registry-owned
IDs, thumbnails and usage counts. Godot GUI drag tokens and a native Atlas
canvas drop target place linked instances at the exact view coordinate,
with index/path/hash/revision validation and a keyboard Place alternative.
Atlas `asset-*` identities remain distinct from the embedded Drawing
`drawing-*` IDs; neither registry nor standalone scanner was duplicated.
New 32-check headless acceptance is push-CI-gated; the original 12 native
layout/provider/drop checks pass (13 with screenshot). A subsequent targeted
**real XTEST press–move–release** witness exposed and fixed `ItemList`'s
missing drag start: it now passes **19/19** actual native gesture checks
(**20/20** with screenshot), including click-without-placement, valid canvas
drop, invalid destination and Esc rollback. Direct owner pointer/keyboard
approval, physical hardware and large-project testing remain open. See
[T-065](Tickets/T-065.md).

**T-065 Atlas-managed portable registration (2026-11-03; still In Progress):**
The Atlas Object Manager now provides explicit Import/Export file dialogs
backed by versioned registry publication, not an unregistered file copy.
Imported `.drawing` sources retain stable source identity, human-readable
name and local frame, reject duplicate/reserved IDs and stale/symlinked paths,
and do not create placements. Exports reconstruct portable metadata without
changing instance bindings. The new 33-check disk-backed import/export test is
fast-CI-gated; the manager tests pass 33 headless and 22 native checks.
Cross-app drag/drop, high-volume/physical desktop review and **owner UX signoff**
remain open. See [T-065](Tickets/T-065.md).

**T-065 Atlas linked-instance and NULL-action milestone (2026-11-03; still In Progress):**
Atlas's Layers view now opens a library-bound source manager (`Ctrl+Shift+B`)
with published-ID usage counts, explicit current-map placement, three-way
Source Delete (Remove/NULL/Cancel), and deliberate stable-ID NULL repair.
Deletion confirmations are bound to registry and instance revisions; historical
source bytes remain untouched. The 48-check on-disk transaction and original 20-check manager/17-check native
Atlas witnesses introduced that workflow; later Import/Export extensions are
documented above. Shared-browser-to-Atlas drag placement and owner UX review
remain open. See [T-065](Tickets/T-065.md).

**T-065 thumbnail and portable-copy follow-up (2026-11-03; still In Progress):** real Object source
pixels now appear as lazy, bounded 48×48 previews with a 24-image SHA-keyed
LRU and automatic invalidation after successful local Object Editor Save.
The headless thumbnail test passes 54 checks; portable file-copy safety passes
29; native source/pointer/thumbnail passes 19 (20 with optional screenshot).
Standalone copies into Atlas-managed registries remain refused; dedicated
Atlas registration is now supported by the Object Manager as described above.
Shared-browser drag/drop, large-project checks and owner UX acceptance remain open. See
[T-065](Tickets/T-065.md) and [CI policy](CI_TESTING.md).

**T-065 portable Asset Browser milestone (2026-11-03; still In Progress):** the shared Drawing workspace can now attach an `asset_browser` dock peer via Window → Asset Browser… or a host-provided portable `Objects/` root. A bounded read-only source scan, name/ID filtering, stale-file and duplicate-identity rejection, and explicit Edit Source into an Object Editor tab are covered by 37 headless and 18 native checks. The later Atlas instance/NULL manager and portable registration milestones are described above; shared-browser drag/drop and owner UX acceptance remain unfinished. The original owner keyboard/pointer acceptance is tracked as a manual gate; no approval was inferred. See [T-065](Tickets/T-065.md) and [standalone usage](../drawing/README.md).

**T-068 publication-cache follow-up (2026-11-03; still In Progress):**
`DrawingDocument` now resolves the immutable source tile once per touched
tile while validating an atomic pixel publication. A new 30-check push-CI
witness covers signed seams, hidden RGB, lazy-source errors, stale originals,
and exact undo/redo. In a three-sample headless, commit-only benchmark across
512/1024/2048 strides and 64²/128² changed regions, every median was lower
(roughly 2.7–3.6×), but staging, UI and GPU costs were not measured. No
third-party native backend or hardware gate was satisfied. See
[T-068](Tickets/T-068.md) and [the report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 source-cache follow-up (2026-11-03; still In Progress):** the detached Drawing gesture now reuses successful per-tile source resolves rather than allocating a result per covered pixel. New 31-check lazy/corrupt/atomicity/signed-seam witness is fast-CI-gated; existing 693-check mixed benchmark parity and 81-check native software-frame stress both pass in before/after pairs. Most operation medians improved but some regressed; this is **not** proof of a stable speedup or native renderer adoption. External CPU comparisons and physical-device/Windows measurements remain open. See [T-068](Tickets/T-068.md) and [the CPU raster report](DRAWING_CPU_RASTER_BENCHMARK.md).

**T-068 measured brush-path follow-up (2026-11-03; still In Progress):** a narrow stationary-dab fast path avoids unnecessary geometry projection for hard brushes without changing edit/storage schemas. The original geometry oracle passes 125 exact-pixel/undo tests at fractional coordinates and signed 64-bit anchors; a 693-check mixed raster benchmark matches the previous changed-pixel and undo sizes across three storage strides. Two 25-gesture native X11/Mesa stress runs (81/81 each) verify visible 4/32/64px dabs, long/crossing strokes, and expose costly large-brush CPU/frame submission, but not physical presentation. Native library comparisons and two-platform validation remain open. See [T-068](Tickets/T-068.md).

**T-015 completed (2026-11-03):** Legacy battlemat placement creation/editing, spatial hit-testing, preview overlays and actionable Focus/Open are retired. Historical placement records and link fields remain **archival only** for lossless old-fixture reads, native saves and the standalone audit; they cannot participate in live navigation or Drawing. Marker-only navigation, search, selected-cell filtering, undo/history and native saves have replacement CI coverage. The old aligned-preview acceptance witness is retained under `tests/retired_legacy/`, not claimed green. T-014's historical D0–D2 raster assertions remain a separately deferred failure. See [T-015](Tickets/T-015.md).

| Ready | In Progress | Blocked | Manual Review | Done | Archived | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 3 | 10 | 4 | 55 | 1 | 83 |

**T-078–T-083 agreed docking sequence (2026-11-03):** The right icon rail remains panel-level, with separators only between tabbed groups. **T-078 Done** (82 model assertions) supplies unique stable-ID ownership, **T-079 Done** (40 native assertions) supplies collapsible groups, icon rail and in-app flyouts, and **T-080 Done** (60 model and 68 native assertions) adds transactional tab/group drag, visible insertion/merge hints, exact Esc/focus-loss/invalid-drop rollback, scrollable tab strips and keyboard arrangement controls. **T-081 Done** (64 model, 55 native checks) supplies real Control-based movable/resizable floating hosts, tab/group reordering, ownership transfer, hide/Window recovery and viewport clamping. **T-082 Done** (62 model and 56 native checks) delivers cross-container panel/group pointer docking, ordered redock, empty-canvas detach, robust invalid/focus-loss cancellations and accessible transfer commands. **T-083 Manual Review** after versioned persistence/recovery engineering (46 headless, 63 native; 65 with screenshots), with **explicit owner UX approval still mandatory**. Docking settings now save and restore, and earlier T-059/T-056 UX gates remain open. See [docking specification](DRAWING_DOCKING_SPEC.md), [T-080](Tickets/T-080.md) and [T-083](Tickets/T-083.md).

**T-063 owner-requested refinement (historical T-063 baseline, 2026-11-02):** The shared Drawing and Object Editor tool rail now uses six packaged, keyboard-focusable SVG icons with tooltips and pressed-state feedback. **Window → Show document tabs** hides/reopens the `Untitled` document strip for the current session; hidden tabs retain Ctrl/Cmd+Tab navigation, unsaved-close protection and document/dirty status. Colors/Layers/History now **stack vertically in one scrollable right dock**, with a bounded layer tree and focus-to-History support. The native witness has **75 required checks**; clean staging includes icons. T-063 remains Done while T-059 and T-056 **manual UX gates stay open**. See [T-063](Tickets/T-063.md) and [standalone usage](../drawing/README.md).

**T-063 completed (2026-11-02):** the [shared compact Drawing top bar](../addons/drawing/editor_top_bar.gd) now provides the eight-menu File/Edit/View/Image/Layers/Select/Window/Help layout with `BarDivider`, real tool-specific options and keyboard-reachable More/chevron overflow. The resizable right dock has Colors/Layers/History tabs, show/hide controls and a History preference, while `Ctrl+Shift+S` invokes actual Save As and Ctrl+Y is the primary redo. A 52-check native X11/Mesa witness tests 1280/560 widths, 1.5x scaling, scrolling, close safety and menu actions; the independent editor and Object Editor remain intact. **T-065 Asset Browser is now Ready; T-059 owner UX approval remains outstanding.** The BarDivider layout remains an owner-*proposed* design even though this engineering prototype is implemented; no manual gate was closed.

**T-074 completed (2026-11-02):** [reusable Object Asset authoring, Save As and NULL lifecycle](OBJECT_ASSETS_WORKFLOW.md) now traces distinct internal `Drawings/` documents, portable `Objects/` sources and per-map instance IDs through private edits, source publication, bound Variant B Save As, asymmetric undo/redo, deletion and missing-source repair. [The historical raster/Objects workflow](RASTER_OBJECTS_WORKFLOW.md) is explicitly labeled pre-split. Ten code-aware documentation checks run in CI, while actual Object Asset, Object Editor, composition and campaign storage suites were rerun. **T-064 nested cycles, T-065 Asset Browser/repair and T-059 owner UX review remain unfinished**; no manual gate was closed.

**T-073 completed (2026-11-02):** the [owner-approved 99-row Drawing feature inventory](DRAWING_FEATURE_INVENTORY.md) retains **47 Essential / 34 Later / 18 Skip** without claiming all are shipped. Its minimum T-053 witness is distinguished from the still-open complete Essential baseline, and pointer/keyboard acceptance flows cite real tests versus pending T-059 owner UX. The [one-row BarDivider workspace specification](DRAW_MODULE_UI_SPEC.md) remains an owner-*proposed* layout, now implemented as a tested T-063 prototype; the Object Editor tab is implemented (T-062), while Asset Browser dock parity awaits T-065. Ten source-aware documentation checks and an eight-check **native keyboard/pointer** witness run in CI. The formerly mismapped `Ctrl+Shift+S` Save As shortcut and missing menu shortcut labels have since been corrected by T-063; no owner gate was closed.

**T-072 completed (2026-11-02):** the nine [tool and interaction workflow pages](BRUSH_WORKFLOW.md) now lead with current Drawing-owned gesture/pixel/edit behavior, Atlas-owned map/selection/global history, the available six-tool standalone palette, and an explicit historical section for legacy Atlas-era prototypes. Bucket/Line/Polygon/Wall Path/T-027 UX remain **Ready** despite their generic engine primitives or old smoke fixtures. Editable text's single-element/explicit rasterization and portable licensed fonts are documented; T-068's native edit-region interface is not mistaken for a selected library. Ten documentation checks run in CI. Some old `.scn` and candidate tool smoke tests still fail and are recorded in [T-072](Tickets/T-072.md); this ticket changes **documentation and tests only**.

**T-071 completed (2026-11-02):** the [storage format and recovery contract](DRAWING_STORAGE_CONTRACT.md), [dictionary adapter audit](DICTIONARY_CONVERSION_AUDIT.md), and [raster importer analysis](RASTER_CHUNK_IMPORT.md) distinguish today's T-066 root-pointer/immutable-generation/individual `.zst` save from historical one-file native WebP/.scn code. Explicit, executable acceptance examples cover relocating a whole project, partial-copy/missing-file rejection, corrupted and interrupted generations, stale writers, precise signed tiles, and blank detail. [[T-067]]'s future 512-stride and segmented-pack recommendations remain **not deployed**. Eight documentation checks and actual missing-chunk failure coverage were added to CI; no save-format change or owner approval is implied.

**T-070 completed (2026-11-02):** the seven [world/detail/navigation pages](MAPS_AND_GRIDS.md) now lead with the actual Option B signed-world/explicit-density contract and distinguish blank D-levels, Atlas-only overlays, grid edit masks, derived previews and independent-map floor links from retired per-hex/battlemat designs. [Search/world discovery](SEARCH_AND_WORLD_DISCOVERY.md) separates today's safe legacy Search actions from the unapproved **Find/Locate** proposal; **T-009 Manual Review and T-017 owner usability gates remain open**. Eight automated documentation checks were added to CI; targeted runtime regressions passed except the older `snapping_smoke.gd` nil-layer case, recorded in [T-070](Tickets/T-070.md). No runtime or save-format change is implied.

**T-069 completed (2026-11-02):** the seven [architecture/data-model pages](ARCHITECTURE.md) now distinguish the shipped two-project Drawing/Atlas core, Option B internal `(map,floor,detail)` registry, Object Assets/instances and T-066 sparse generations from historical `.scn`/battlemat proposals. A six-check documentation suite and CI step guard source links, approved authority, and unresolved review/performance boundaries. No migration or UX approval was implied.

**T-077 completed (2026-11-02):** [platform-specific test matrix and reviewer handoff](DRAWING_TEST_PLAN.md) distinguishes the historical milestone-6 review and latency probes from T-067 storage, T-068 CPU raster/submitted-frame and the now-measured [T-057 GPU/LOD feasibility decision](DRAWING_LOD_RENDERER_BENCHMARK.md). The generator `tools/build_t038_review_bundle.py` makes a deterministic code-only reviewer ZIP. T-038/T-056 still require **actual independent/owner review**, not automatically generated evidence; no manual-review gate was closed.

**T-068 in progress (2026-11-02):** [controlled CPU and native-frame benchmark](DRAWING_CPU_RASTER_BENCHMARK.md) includes 691 Godot checks on the latest rerun, **10 native kernel unit tests**, 128 Godot/C++ alpha-parity vectors, a 24-pixel signed-world fixture, 15 sparse-delta-only C++ timings, and **68 native X11 software-frame checks** across 21 input events. A new ABI-versioned delta-only prototype avoids copying unchanged edit buffers but remains unintegrated. Tile-run compositing provides ~16× lower CPU-frame time on the bounded fixture. Actual Blend2D/Skia performance, GDExtension integration, physical presentation and Windows hardware remain unverified; **no native dependency was adopted and T-068 is not Done**.

**T-067 completed (2026-11-02):** [controlled 256/512/1024/2048 Zstd tile and 3-layout packing benchmark](DRAWING_CHUNK_GEOMETRY_BENCHMARK.md) includes 48 physical-layout cases, 386 Godot native checks, software framebuffer upload measurements and explicit retiling/versioning rules. **512** is recommended for a *future new-document default* and immutable shared **segmented** packs are the physical-layout target; **neither change has been deployed**. Existing versioned 256-stride documents and T-066’s verified individual-blob writer remain authoritative until separate adoption and atomic-recovery tests. No manual review gate was bypassed.

**T-066 completed (2026-11-02):** [portable generation-based sparse campaign saving](DRAWING_STORAGE_CONTRACT.md) now durably publishes the single Atlas root pointer after verifying checked manifests, compressed tiles, Object Assets, licensed fonts and recovery roots. The real editor saves and reopens Drawing documents. T-067 subsequently completed its geometry/packing benchmark; adoption of its recommended default/pack layout is separate work. T-056/T-059 owner UX gates remain open.

**T-055 completed (2026-11-02):** [Atlas canvas composition, linked Objects, input precedence and read-only previews](DRAWING_ATLAS_COMPOSITION.md) use the one canonical Drawing package with 89 headless and 18 native display checks. T-056 is now **Ready** for separate engineering/release/owner verification; its manual-review approval remains pending. T-066 subsequently implemented the versioned multi-file save.

**T-061 completed (2026-11-02):** [Atlas floor/detail Drawing registry and shared signed world mapping](DRAWING_WORLD_MAPPING.md) now prove per-detail stable IDs, sparse blank D-levels, explicit pixel densities, 64-bit viewport anchors, Object Instance detail scoping and grid/entrance overlay continuity. **T-055 subsequently completed** main-canvas composition. T-061 does not claim that composition or T-066’s multi-file atomic save.

**T-062 completed (2026-11-02):** the [shared dedicated Object Editor](Tickets/T-062.md) now uses the same Drawing workspace in standalone Drawing and an Atlas-hosted window, with private drafts, Save/Save As, captured instance identity, signed local frames, unsaved-close protection and real UI/registry/history tests. **T-064 is now Ready**; Atlas main-canvas launch/composition (T-055) subsequently completed; the Asset Browser (T-065) and owner UX review remain outstanding.

**Owner review is intentionally narrow.** `Owner` in the table marks a direct completion gate; `Via T-039` indicates inherited privacy-policy approval. Agents can research, implement and test pending dependencies, but **must not mark Done** until the relevant direct and transitive manual approvals are recorded. Approved Drawing feature scope does not mean the final UX is accepted.

**T-051 completed (2026-11-02):** [testable Drawing document/package ADR](ADR_DRAWING_DOCUMENT_CONTRACT.md) and signed-tile consumer. **T-052 completed (2026-11-02):** the [independent generic Drawing core](../addons/drawing/README.md) and an isolated Godot consumer with 150+ runtime checks. T-053 is now Done with an [independently runnable desktop Drawing project](../drawing/README.md), a portable standalone document witness, native framebuffer tests, a third generic consumer and Linux release export. T-058 is now Done with editable one-element text layers, a shared glyph compositor and explicit undoable rasterization; T-062 is now Done with a shared Object Editor and Atlas-bound Save As workflow. T-063 is now Done; T-065 is Ready. T-054 now provides tested Drawing-local and Atlas-global contextual history, one-step cross-document transfers and the Save As binding-history contract; subsequent Object Editor and Atlas canvas composition were delivered in T-062/T-055. T-060 now provides [versioned Object Assets, linked per-map instances, private Save drafts and atomic component-level Save As rebinding](../scripts/objects/README.md), including NULL placeholders and real portable-file tests. Its per-campaign object index is now captured by T-066’s portable generation snapshots. T-055 completes live Atlas composition; T-066 completes the versioned sparse campaign save. Polished UI, performance benchmarks and owner UX gates remain incomplete.

**T-075 completed (2026-11-02):** the nine [player projection and collaboration pages](PLAYER_PROJECTION_CONTRACT.md) now distinguish the currently implemented DrawingDocument/Asset/T-066 source graph from isolated legacy raster-sanitization, X11 player-window and in-process session proofs. Windows/Linux native desktop is the active target; [Web T-044](Archive/Web/T-044.md) is **Archived** without deleting its historic tests. Ten source-backed documentation tests and 375 headless plus 124 native visual checks passed. **T-039 Manual Review, T-043/T-048 blocked independent owner gates remain unchanged**; no real player-authorized projector or authenticated multiplayer is claimed.

## Owner recheck — 2026-11-08

**T-095 returned to In Progress.** Owner reports 60px Brush catch-up is still too slow and pan/zoom while a *released* stroke is draining cancels it. The 2026-11-07 Xvfb performance gains remain valid as controlled software evidence, **not** successful physical UX acceptance. `DrawingCanvas` conflates an active held stroke and a post-release queued session when zoom/camera/middle-pan cancel by `session != null`; preserve source-space pending work across **viewport-only** navigation after release. Plan for custom/textured brush stamps without claiming they are implemented. [T-095 remediation and acceptance](Tickets/T-095.md). T-096 remains in Manual Review with no new owner verdict.

**T-095 Hokusai staging checkpoint (2026-11-08; In Progress):**
The optional native `.myb` brush now prevalidates an entire pixel-delta batch
and source tiles before mutation; dirty previews update at tile granularity,
without per-pixel rollback journals. In a controlled 60px, 120-motion,
five-stroke Xvfb comparison, Hokusai CPU staging p95 fell from **1271.973 ms**
to **691.732 ms** with exact old-path pixel parity in the new **57/57**
batch-delta oracle and adjacent tests. The same-run Legacy staging p95 was
**225.456 ms**, and full application/owner-device responsiveness is not
accepted. T-095 retains `manual_review: true`, status **In Progress**.
[Evidence](evidence/T-095-2026-11-08-hokusai.md) · [ticket](Tickets/T-095.md).

**T-095 bounded sustained-input buffer checkpoint (2026-11-09; In Progress):**
The Canvas now compacts an already-drained input prefix during a continuous
pointer backlog without dropping queued source-space positions, timestamps
or an active interpolated target. A new **31/31** strict-log oracle covers
6,000 interleaved input events, a 1,600-point Brush stroke, post-release
camera/tool navigation, exact independent RGBA8 parity and Undo/Redo.
Original-source negative controls fail. The five-stroke 60px software
benchmark remains approximately unchanged; this bounds retained input memory,
**not physical Brush latency**. Hosted CI and owner acceptance remain open.
T-095 stays **In Progress**, `manual_review: true`; T-096 remains in separate
Manual Review. [Evidence](evidence/T-095-2026-11-09-input-queue-compaction.md) ·
[ticket](Tickets/T-095.md).

**T-095 bounded input-latency telemetry (2026-11-09; In Progress):**
The sustained-stroke queue fix still left an **unbounded** per-waypoint
`sample_to_stage_us` array and final deep-copy. Short gestures keep full
latency history; long gestures now retain the chronological latest **4,096**
ages, with exact lifetime count and worst age. A new **22/22** oracle paints
4,602 waypoints with exact RGBA8/history parity, tests 15,000 latency records
and fails against the old source (4,602 retained versus the new 4,096 cap).
This bounds profiler memory, **not raster latency**: two five-stroke Xvfb
controls showed no staging speedup. T-095 remains **In Progress** with
`manual_review: true`; hosted CI and owner-device acceptance are outstanding,
and T-096 remains independently in Manual Review.
[Evidence](evidence/T-095-2026-11-09-bounded-latency-telemetry.md) ·
[ticket](Tickets/T-095.md).

**T-095 default Legacy Brush tile/source lookup checkpoint (2026-11-09; In Progress):**
The common `DrawingEditSession._stage()` now reuses one signed storage-tile
key and integer local offset for source reads, previews and rollback, reading
verified immutable source pixels directly from the resident sparse map. A
session-cached shift/mask handles power-of-two tile strides; irregular strides
retain signed floor division. An independent **4,193/4,193** source-read and
history oracle covers seven strides, negative/>32-bit anchors, selection holes,
transparent source RGB, per-stroke coverage, commit and Undo/Redo. A separate
**86/86** original-`Geometry2D` oracle protects oblique 60px Brush/Eraser
coverage. In a same-machine 5×120-motion **actual Legacy pointer** Xvfb/Mesa
comparison, staging p95 fell **168.123→148.419ms** (~11.7%). This does
**not** prove owner-device responsiveness or acceptable release latency;
no physical review was performed. Adjacent native, navigation and viewport
regressions pass locally (viewport fonts required a clean reimport). T-095
remains **In Progress**, `manual_review: true`; T-096's Manual Review is
unaffected. [Evidence](evidence/T-095-2026-11-09-legacy-stage-lookup.md) ·
[ticket](Tickets/T-095.md).

**T-095 signed power-of-two Hokusai tile staging (2026-11-09; In Progress):**
The native-delta path now maps signed global pixels to the common power-of-two
storage tile using exact arithmetic shift/mask, while retaining signed floor
division for arbitrary strides. An independent **422/422** oracle compares
the old pixel-staging path across ten tile sizes, signed 64-bit anchors,
selection holes, alpha, preview, canonical history and Undo/Redo.
Two controlled 60px/786% five-stroke Xvfb/Mesa pairs reduced Hokusai staging
p95 **201.491→183.443ms** and **204.460→186.535ms** (~9%);
Legacy remains faster at 167.412ms p95. This is software CPU evidence, **not** physical input-to-photon or owner acceptance.
Neighboring native, navigation, viewport and fallback tests pass locally;
CI/export checks remain open. T-095 stays **In Progress**, `manual_review: true`,
T-096 stays independently in Manual Review, and PR #16 remains unmerged.
[Evidence](evidence/T-095-2026-11-09-signed-tile-shift.md) ·
[ticket](Tickets/T-095.md).

**T-095 direct tile-local native commit (2026-11-09; In Progress):**
Hokusai-only commits now avoid generating and reparsing global `"x,y"`
pixel keys before publishing the detached preview. A shared atomic
installation routine preserves exact canonical history, region bounds,
revision guards and Undo/Redo; mixed edit APIs keep the original path.
The **56/56** independent history/preview oracle, 126/126 Hokusai oracle,
30/30 native preset, 48/48 navigation, 153/153 viewport (after reimport)
and fresh no-native 6/6 fallback pass. In paired five-stroke 60px/786%
Xvfb tests, release→commit p95 fell **75.081→43.258ms**, confirmed at
42.107ms, but full-gesture staging p95 remained ~206ms and was still slower
than Legacy's 155.529ms. No hosted CI or physical hardware acceptance;
T-095 stays **In Progress**, `manual_review: true`. T-096's review is
independent. [Evidence](evidence/T-095-2026-11-09-direct-tile-commit.md) ·
[ticket](Tickets/T-095.md).

**T-095 cached native fixed-point pixel export (2026-11-09; In Progress):**
Hokusai's Rust dirty-tile exporter now skips expensive linear→sRGB conversion
for unchanged fix15 pixels and exports only byte-different RGBA8 values. A
full-input preflight prevents an invalid later point from mutating native
stroke state. Two offline Rust tests, Clippy, and **81/81** frozen pre-change
native `.myb` delta-stream checks pass (hard/soft/ink/airbrush), along with
selection, preview, navigation and framebuffer regressions. In a same-machine
5×120-motion Xvfb control, native export CPU p95 changed **35.184→25.035ms**,
but full-gesture staging p95 **237.346→253.152ms** did not improve; Legacy
is still faster. The native raw cache costs 32 KiB extra per touched 64px
tile. No hosted CI or hardware response evidence; T-095 remains **In Progress**,
`manual_review: true`, and T-096 independently remains **Manual Review**.
[Evidence](evidence/T-095-2026-11-09-native-raw-pixel-export.md) ·
[ticket](Tickets/T-095.md).

**T-095 sparse detached-preview compositor checkpoint (2026-11-09; In Progress):**
Small native/legacy live-paint patches previously triggered a full 128px
display tile scan even with only a handful of source/preview pixels. Bounded
sparse union composition now honors source-over, preview erasure and signed
64-bit tile coordinates; dense previews retain the existing scan. An
independent **133/133** byte-exact compositor oracle passes along with
Hokusai (126/126), hard Brush, blend, navigation, preset and viewport checks.
A controlled 128×128 sparse-preview CPU median fell **2611→608µs (~4.3×)**;
this is **not** the 60px sustained-stroke result. In the actual 5×120-event
Hokusai pointer benchmark, compositor p95 changed only **16.710→16.562ms**,
and Hokusai remains behind Legacy in staging. Owner real-device acceptance,
hosted CI and clean export remain unverified. T-095 stays **In Progress**,
`manual_review: true`; T-096's separate review is untouched.
[Evidence](evidence/T-095-2026-11-09-sparse-preview-compositor.md) ·
[ticket](Tickets/T-095.md).

**T-095 native tile-run buffering checkpoint (2026-11-09; In Progress):**
The optional Hokusai preflight no longer fetches, extends and reassigns its
per-tile `PackedInt32Array` for every native pigment pixel. Contiguous tile
runs accumulate locally, flushing only on tile changes or at batch end;
revisiting a tile preserves native ordering. The independent signed-source,
preview, mixed-edit, rollback and Undo/Redo oracle passes **126/126**,
including a full 4,096-pixel tile and cross-tile returns. In a controlled
5×120 mouse-motion Xvfb run, staging p95 fell **235.533→215.324ms**
(~8.6%), but Legacy was **172.477ms**. Native preset, post-release navigation,
missing-binary and adjoining rendering regressions pass locally. No owner
hardware acceptance, hosted CI, or pressure/custom-brush performance is
claimed; T-095 stays **In Progress**, `manual_review: true`, and T-096's
independent review gate remains unchanged.
[Evidence](evidence/T-095-2026-11-09-tile-run-buffer.md) ·
[ticket](Tickets/T-095.md).

**T-095 native preflight cached-key / transparent blend checkpoint (2026-11-09; In Progress):**
The optional Hokusai pigment path now caches its last signed-64-bit storage
tile key across clustered deltas and uses allocation-free rectangular clipping.
Opaque source and transparent destination RGBA8 blending skip arithmetic only
where byte-exact; independent **114,688** old-equation comparisons and the
expanded **119/119** dense signed-tile/selection/mixed-edit delta oracle pass.
In a paired 5×120 actual mouse-motion Xvfb/Mesa witness, Hokusai stage CPU
p95 fell **275.158→239.448ms (~13%)**, compositor frame CPU p95
**21.848→16.808ms (~23%)**. Hokusai remains slower than Legacy and has no
owner-device approval; T-095 **In Progress**, `manual_review: true`; T-096
independently remains in Manual Review.
[Evidence](evidence/T-095-2026-11-09-cached-tile-preflight.md) ·
[ticket](Tickets/T-095.md).

**T-095 exact RGBA8 blend / tile-read fast path (2026-11-09; In Progress):**
The opt-in Hokusai path now uses directly indexed immutable source tile
pixels and an allocation-free, byte-exact scalar RGBA8 source-over blend
(shared with ordinary Brush and renderer). A **98,304-pair independent
old-equation oracle** passes, along with the 101/101 native delta oracle,
32/32 Brush source oracle, 30/30 preset, 48/48 released-stroke navigation,
17/17 signed seam, and 153/153 viewport native checks. In a same-machine
5×120 mouse-motion Xvfb comparison, Hokusai stage p95 fell
**347.704→281.002 ms** and frame-composition p95 **29.247→21.833 ms**,
but release p95 did not materially improve; it remains slower than Legacy.
**No owner hardware/UX acceptance or hosted CI result; T-095 stays
`In Progress` with `manual_review: true`.**
[Evidence](evidence/T-095-2026-11-09-blend.md) · [ticket](Tickets/T-095.md).

**T-095 deferred tile-local staging (2026-11-08; In Progress):**
Prevalidated native pigment deltas now use signed storage-tile keys and integer
local pixel offsets, deferring global-key history materialization until commit.
The 101-check parity/rollback oracle and neighboring native Brush/navigation,
missing-binary and viewport regressions pass. On the same Xvfb 60px/786%
5×120-movement workload, Hokusai staging p95 fell **580.815→369.368 ms**,
but commit p95 increased, and Legacy staging still takes only **168.023 ms**.
This is **not** owner-device responsiveness evidence. **T-095 remains In
Progress with manual review required; T-096 remains independently in Manual
Review.** [Checkpoint evidence](evidence/T-095-2026-11-08-hokusai-tile-local.md).

## Next-sprint handoff — 2026-11-07

**2026-11-08 T-095 follow-up:** An optional pinned offline Rust/Hokusai GDExtension prototype is staged alongside the default legacy path. The new capture/drain/commit lifecycle prevents pan/zoom from cancelling post-release Brush backlog; targeted source-byte, Undo/Redo, 4 `.myb` preset, selection-hole, and missing-native fallback checks pass. In five-stroke Xvfb comparisons the NativeHard software stage p95 was 139.976ms versus Legacy 159.339ms, but Hokusai `.myb` stage p95 was **934.532ms**. No owner-device paint latency acceptance, Windows/export support or PR merge is implied. [Evidence](evidence/T-095-2026-11-08-hokusai.md).

**Owner verified the chunk-edge filtering artifact gone** after PR #14 (the separate physical benchmark/acceptance gates are not implied). Leave the repaired tile sampling and high-zoom pixel grid in the merged baseline; the pixel grid is **enabled by default** above 600% zoom, with an independent View toggle. [T-095](Tickets/T-095.md) now has an implemented, independent-oracle-tested 60px Brush staging optimization and paired Xvfb/Mesa evidence; its 2026-11-08 physical owner recheck **failed** (strokes still lag and pending strokes are canceled by navigation); **In Progress**, not Done. [T-096](Tickets/T-096.md) now implements exact large-mask contours and reusable floating Move capture with independent exact-pixel oracles, multi-zoom native pointer/framebuffer witnesses and a controlled software before/after profile; it is **Manual Review**, not Done, until physical owner UX acceptance.

**T-096 large-mask contours and cached floating Move (2026-11-07; Manual Review):** The previous >4096-cell enclosing-box fallback is replaced by viewport-clipped exact boolean mask boundaries (including disconnected islands and subtract holes), plus a bounded progressive cache for explicit pixel masks. The floating Move keeps one immutable capture and stages only nonzero selected source pixels per pointer offset, preserving hidden RGB, multiple drags and a single drop history step. Eight independent same-offset legacy/new detached-edit comparisons are byte-identical. The pinned Xvfb/Mesa native suite passes **34/34** actual viewport-delivered pointer/framebuffer checks at 25%/400%/786%, with software input receipt-to-preview-submit CPU p95 **12.093ms** and pointer-to-postdraw callback p95 **47.638ms**; nearby T-085/T-086/T-088/T-095 suites pass. These do **not** constitute physical GPU input-to-photon or owner approval. [T-096](Tickets/T-096.md) · [paired evidence](evidence/T-096-2026-11-07-selection.md).

**T-094 full local replay and T-068 fixture repair (2026-11-07; In Progress):** The isolated pinned Godot 4.8-beta2 fast-CI replay now reports **46/46 required checks executed and passed**. A prior **45/46** complete replay exposed T-068's fixture generator reading the old T-095 `_covered` field; the witness now reads signed integer `_covered_rows` and regenerates all 16 pinned Godot/Skia cases **byte-for-byte**. The targeted fixture test (9 available contracts, one opt-in live-Skia skip), T-094 log contracts (14/14), T-062 headless Save-and-Close (26 checks), T-095/T-096 required source oracles, and Kanban validator (96 tickets) pass. This **local `--allow-dirty` replay is not hosted or commit-attested CI**; Windows/Linux physical owner UX and manual gates remain open. [T-094 evidence](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

**T-094 required source-oracle and log-integrity checkpoint (2026-11-07; In Progress):** The 46-step fast desktop CI now includes the **T-095** 60px Brush/Eraser exact source/rollback oracle in its existing T-085 step and the **T-096** large-mask/Move oracle in its existing T-088 step. The shared strict log verifier now rejects incomplete fractions (`44/45`), nonzero-failure summary counts and deceptive success-marker suffixes, not just missing markers and runtime errors. T-094 also repairs a stale T-053 standalone assertion count, standardizes the T-096 watchdog, and avoids the Godot beta's negative-position save dialog error **only on headless displays** while preserving normal desktop centering. Pinned local replays passed these two affected steps (32/32 Brush and 13,847/13,847 selection oracle assertions) and the T-073 documentation/CI-contract step; **3/46 is incomplete**, not a full or hosted green result. Physical owner hardware and T-095/T-096 manual gates remain open; **T-094 stays In Progress**. [T-094 evidence](Tickets/T-094.md) · [CI policy](CI_TESTING.md).

## Tickets

| Ticket | Status | Review gate | Hard dependencies |
| --- | --- | --- | --- |
| [T-001 · Explicit types and corrected skill guidance](Tickets/T-001.md) | Done | — | — |
| [T-002 · Continuous chunked-canvas model](Tickets/T-002.md) | Done | — | — |
| [T-003 · Aligned transparent detail previews](Tickets/T-003.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-004 · Viewport-appropriate zoom and artwork LOD](Tickets/T-004.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-005 · Automatic artwork LOD on by default](Tickets/T-005.md) | Done | — | [T-004](Tickets/T-004.md) |
| [T-006 · Categorized sidebar drawing palette](Tickets/T-006.md) | Done | — | — |
| [T-007 · Compact recognizable icon controls](Tickets/T-007.md) | Done | — | — |
| [T-008 · Toolbar-opened grid settings popup](Tickets/T-008.md) | Done | — | — |
| [T-009 · Search and world discovery purpose](Tickets/T-009.md) | Manual Review | **Owner** | — |
| [T-010 · Smooth pen turns](Tickets/T-010.md) | Done | — | — |
| [T-011 · Mouse-wheel pen width](Tickets/T-011.md) | Done | — | — |
| [T-012 · Replace battlemats with authored local detail](Tickets/T-012.md) | Done | — | [T-002](Tickets/T-002.md), [T-004](Tickets/T-004.md) |
| [T-013 · Projector framing object](Tickets/T-013.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-022](Tickets/T-022.md) |
| [T-014 · Retire battlemat creation controls](Tickets/T-014.md) | Done | — | [T-012](Tickets/T-012.md), [T-006](Tickets/T-006.md) |
| [T-015 · Remove obsolete model code (save migration waived)](Tickets/T-015.md) | Done | — | [T-012](Tickets/T-012.md) |
| [T-016 · Coherent detail-editing snapping](Tickets/T-016.md) | Done | — | [T-012](Tickets/T-012.md), [T-019](Tickets/T-019.md) |
| [T-017 · Revisit floor-link authoring/testing](Tickets/T-017.md) | Blocked | **Owner** | [T-003](Tickets/T-003.md), [T-004](Tickets/T-004.md), [T-012](Tickets/T-012.md), [T-018](Tickets/T-018.md), [E-TOOLS](Epics/E-TOOLS.md) |
| [T-018 · Compact layer/object/link hierarchy](Tickets/T-018.md) | Ready | — | [T-006](Tickets/T-006.md), [T-012](Tickets/T-012.md) |
| [T-019 · Selection and selection masks](Tickets/T-019.md) | Done | — | [T-002](Tickets/T-002.md) |
| [T-020 · Brush](Tickets/T-020.md) | Done | — | — |
| [T-021 · Eraser](Tickets/T-021.md) | Done | — | — |
| [T-022 · Move](Tickets/T-022.md) | Done | — | [T-019](Tickets/T-019.md), [T-012](Tickets/T-012.md) |
| [T-023 · Bucket](Tickets/T-023.md) | Ready | — | — |
| [T-024 · Line](Tickets/T-024.md) | Ready | — | — |
| [T-025 · Polygon](Tickets/T-025.md) | Ready | — | — |
| [T-026 · Editable open/closed wall paths](Tickets/T-026.md) | Ready | — | — |
| [T-027 · Editable text and small-text culling](Tickets/T-027.md) | Ready | — | — |
| [T-028 · Ink representation decision](Tickets/T-028.md) | Done | — | — |
| [T-029 · Dictionary conversion audit and cleanup](Tickets/T-029.md) | Done | — | — |
| [T-030 · Raster import/chunk conversion clarity](Tickets/T-030.md) | Done | — | — |
| [T-031 · Tile-layer naming and type authority](Tickets/T-031.md) | Done | — | — |
| [T-032 · Field encodings and invariants](Tickets/T-032.md) | Done | — | — |
| [T-033 · Fill readability](Tickets/T-033.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-034 · Raster brush readability](Tickets/T-034.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-035 · Selection geometry readability](Tickets/T-035.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-036 · Stroke eraser readability](Tickets/T-036.md) | Done | — | [T-001](Tickets/T-001.md), [T-037](Tickets/T-037.md) |
| [T-037 · Commented function-step convention](Tickets/T-037.md) | Done | — | [T-001](Tickets/T-001.md) |
| [T-038 · Broader code-only review](Tickets/T-038.md) | Manual Review | **Owner** | [T-033](Tickets/T-033.md), [T-034](Tickets/T-034.md), [T-035](Tickets/T-035.md), [T-036](Tickets/T-036.md) |
| [T-039 · Player projection and privacy contract](Tickets/T-039.md) | Manual Review | **Owner** | [E-003](Epics/E-003.md), [E-004](Epics/E-004.md), [E-006](Epics/E-006.md), [E-SAVE](Epics/E-SAVE.md) |
| [T-040 · GM/player views and calibration](Tickets/T-040.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-013](Tickets/T-013.md) |
| [T-041 · Tokens](Tickets/T-041.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md) |
| [T-042 · Fog and reveal](Tickets/T-042.md) | Blocked | Via T-039 | [T-039](Tickets/T-039.md), [T-019](Tickets/T-019.md) |
| [T-043 · Player-output privacy acceptance](Tickets/T-043.md) | Blocked | **Owner** | [T-040](Tickets/T-040.md), [T-041](Tickets/T-041.md), [T-042](Tickets/T-042.md) |
| [T-044 · Web-compatible player fallback — archived](Tickets/T-044.md) | Archived | — | — |
| [T-045 · Authoritative sessions and commands](Tickets/T-045.md) | Blocked | Via T-039 | [E-007](Epics/E-007.md), [T-039](Tickets/T-039.md) |
| [T-046 · Roles and filtered replication](Tickets/T-046.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-039](Tickets/T-039.md) |
| [T-047 · Reconnect and resynchronization](Tickets/T-047.md) | Blocked | Via T-039 | [T-045](Tickets/T-045.md), [T-046](Tickets/T-046.md) |
| [T-048 · Collaboration acceptance](Tickets/T-048.md) | Blocked | **Owner** | [T-046](Tickets/T-046.md), [T-047](Tickets/T-047.md), [T-043](Tickets/T-043.md) |
| [T-049 · Raster-first authoring defaults and semantic-vector tools](Tickets/T-049.md) | Ready | — | [T-028](Tickets/T-028.md), [T-050](Tickets/T-050.md) |
| [T-050 · Retire palette-cell TerrainLayer artwork](Tickets/T-050.md) | Done | — | [T-028](Tickets/T-028.md), [T-031](Tickets/T-031.md) |
| [T-051 · Finalize shared/copy, coordinates and project contracts](Tickets/T-051.md) | Done | — | — |
| [T-052 · Independent Drawing core and generic layer groups](Tickets/T-052.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-053 · Independent Drawing Godot project in monorepo](Tickets/T-053.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-054 · Global history navigates to edit origin](Tickets/T-054.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-055 · Compose Drawing in Atlas, input and previews](Tickets/T-055.md) | Done | — | [T-053](Tickets/T-053.md), [T-054](Tickets/T-054.md), [T-060](Tickets/T-060.md), [T-061](Tickets/T-061.md), [T-062](Tickets/T-062.md) |
| [T-056 · Validate isolation, shared assets, LOD and saves](Tickets/T-056.md) | Ready | **Owner** | [T-055](Tickets/T-055.md), [T-058](Tickets/T-058.md) |
| [T-057 · Native map rendering/LOD feasibility spike](Tickets/T-057.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-058 · One text object per editable layer and rasterization](Tickets/T-058.md) | Done | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-059 · Approved Drawing feature scope; implement and validate UX](Tickets/T-059.md) | Ready | **Owner** | [T-051](Tickets/T-051.md) |
| [T-060 · Reusable Object Assets and linked instances](Tickets/T-060.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-061 · Floor layer groups, world coordinates and blank LOD](Tickets/T-061.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-062 · Object Editor, Save and Save As](Tickets/T-062.md) | Done | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-058](Tickets/T-058.md) |
| [T-063 · Compact Drawing UI and BarDivider overflow](Tickets/T-063.md) | Done | — | [T-053](Tickets/T-053.md) |
| [T-064 · Nested Object Assets with cycle-safe references](Tickets/T-064.md) | In Progress | — | [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-065 · Asset Browser and NULL-placeholder workflow](Tickets/T-065.md) | In Progress | **Owner** | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-063](Tickets/T-063.md) |
| [T-066 · Sparse multi-file floor/detail DrawingDocument persistence](Tickets/T-066.md) | Done | — | [T-051](Tickets/T-051.md), [T-052](Tickets/T-052.md) |
| [T-067 · Benchmark larger chunk geometry and packed storage](Tickets/T-067.md) | Done | — | [T-051](Tickets/T-051.md) |
| [T-068 · Evaluate native drawing rasterization and compositing](Tickets/T-068.md) | In Progress | — | [T-052](Tickets/T-052.md) |
| [T-069 · Reconcile architecture and typed model docs](Tickets/T-069.md) | Done | — | — |
| [T-070 · Reconcile world, authored detail and navigation docs](Tickets/T-070.md) | Done | — | — |
| [T-071 · Sparse multi-file Drawing storage and recovery docs](Tickets/T-071.md) | Done | — | — |
| [T-072 · Drawing tools and interaction workflows](Tickets/T-072.md) | Done | — | — |
| [T-073 · Approved feature inventory and proposed UX](Tickets/T-073.md) | Done | — | — |
| [T-074 · Object Asset authoring and NULL placeholders](Tickets/T-074.md) | Done | — | — |
| [T-075 · Native projector, privacy and collaboration docs](Tickets/T-075.md) | Done | — | — |
| [T-076 · Kanban index and manual-review closure validation](Tickets/T-076.md) | Done | — | — |
| [T-077 · Performance, code review and validation handoff docs](Tickets/T-077.md) | Done | — | — |
| [T-078 · Panel architecture and state](Tickets/T-078.md) | Done | — | [T-063](Tickets/T-063.md) |
| [T-079 · Collapsible dock and grouped icon rail](Tickets/T-079.md) | Done | — | [T-078](Tickets/T-078.md) |
| [T-080 · Tab and group reordering](Tickets/T-080.md) | Done | — | [T-079](Tickets/T-079.md) |
| [T-081 · Floating tabbed panel containers](Tickets/T-081.md) | Done | — | [T-080](Tickets/T-080.md) |
| [T-082 · Cross-container panel and group docking](Tickets/T-082.md) | Done | — | [T-081](Tickets/T-081.md) |
| [T-083 · Docking layout persistence and owner UX validation](Tickets/T-083.md) | In Progress | **Owner** | [T-082](Tickets/T-082.md) |

| [T-084 · Scout PhotoCraft live-paint pipeline](Tickets/T-084.md) | Done | — | [T-052](Tickets/T-052.md) |
| [T-085 · Real-time strokes and smooth input](Tickets/T-085.md) | In Progress | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-086 · Incremental viewport cache and zoom](Tickets/T-086.md) | In Progress | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-087 · Visible image edge, transparency and grid](Tickets/T-087.md) | In Progress | — | [T-053](Tickets/T-053.md) |
| [T-088 · Selection masks, clipboard and Move](Tickets/T-088.md) | In Progress | — | [T-052](Tickets/T-052.md), [T-053](Tickets/T-053.md) |
| [T-089 · Layer hierarchy, row eye/lock and undo](Tickets/T-089.md) | Done | — | [T-053](Tickets/T-053.md) |
| [T-090 · Responsive UI, menu, tabs and brush wheel](Tickets/T-090.md) | In Progress | — | [T-063](Tickets/T-063.md) |
| [T-091 · Single-group floating dock and width recovery](Tickets/T-091.md) | In Progress | — | [T-082](Tickets/T-082.md) |
| [T-092 · Compact Colors and History preferences](Tickets/T-092.md) | In Progress | — | [T-063](Tickets/T-063.md) |
| [T-093 · Discoverable Object source/open workflows](Tickets/T-093.md) | Done | — | [T-053](Tickets/T-053.md), [T-060](Tickets/T-060.md), [T-062](Tickets/T-062.md) |
| [T-094 · Restore CI and owner acceptance evidence](Tickets/T-094.md) | In Progress | — | [T-053](Tickets/T-053.md), [T-055](Tickets/T-055.md), [T-063](Tickets/T-063.md) |
| [T-095 · Eliminate 60px Brush latency](Tickets/T-095.md) | In Progress | Tile-run buffered Hokusai preflight and exact-pixel oracle verified in software; still slower than Legacy, owner device/review gate outstanding | [T-053](Tickets/T-053.md) |
| [T-096 · Accurate selection contours and responsive Move](Tickets/T-096.md) | Manual Review | Owner physical selection/Move UX recheck | [T-053](Tickets/T-053.md) |

## Epics

- [ ] [[E-009|E-009 · Drawing / Atlas capability separation]]
- [ ] [[E-001|E-001 · Drawing, erasing and edit history]]
- [ ] [[E-002|E-002 · Continuous chunked board and grid masks]]
- [ ] [[E-003|E-003 · Typed artwork model and persistence]]
- [ ] [[E-004|E-004 · Usable drawing and manipulation]]
- [ ] [[E-TOOLS|E-TOOLS · Familiar drawing-tool suite]]
- [ ] [[E-005|E-005 · Discovery, previews and floors]]
- [ ] [[E-006|E-006 · Authored artwork LOD and detail editing]]
- [ ] [[E-SAVE|E-SAVE · Portable multi-file save integrity]]
- [ ] [[E-007|E-007 · Local table and projector output]]
- [ ] [[E-008|E-008 · Host-authoritative collaboration]]

## Archived platform work

The Web-only [T-044 historical ticket](Archive/Web/T-044.md) is paused; native projector/privacy and collaboration tickets remain active. See [Web archive policy](Archive/Web/README.md).

## Maintaining this index

When adding or changing a ticket, keep its frontmatter and this table synchronized. Run `python3 tools/validate_ticket_store.py`; CI also checks these on repository updates. Never turn a manually gated ticket or any dependent ticket Done without the owner's explicit recorded approval.
