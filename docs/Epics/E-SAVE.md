---
id: E-SAVE
type: epic
priority: P1
---
# Portable campaign save integrity — native file with adjacent assets

## Baseline and reopening
The earlier **single-file native campaign save** implementation was previously verified and merged. Its reports and benchmark evidence are archived. The gate is reopened for the persistence impact of [[T-029]] and the model decisions in [[E-003]], not because the review demonstrated a new file-corruption defect.

## Ticket
- [[T-029|Audit/remove obsolete dictionary conversion paths and revalidate native saves]]

## Acceptance
- Retain the accepted native single-file direction unless a separate decision changes it.
- Model cleanup preserves exact artwork, identity, native values, isolated mutable copies, undo and recoverable activation.
- Replace required cloning/validation responsibilities before removing their dictionary adapters.
- Re-run meaningful native roundtrip, recovery and compatible-installation checks after relevant changes; decide any native schema change explicitly.

## Historical evidence
[[Archive/2026-10-30/NATIVE_SAVE_IMPLEMENTATION|Native-save report]] · [[Archive/2026-10-30/NATIVE_SAVE_BENCHMARKS|AD-10 measurements]]. Completion: [[Index]].

## Later save-scope decision — 2026-11-01
The owner confirmed **no historical user saves require migration**. The architecture work in [[E-009]] is therefore **not** blocked by loading old prototype .scn schemas or preserving prior serialized Resource paths. Preserve high-integrity **new-format** roundtrips, identity, recovery, atomic write and corruption-detection behavior. Past native-save tests remain useful engineering evidence but old-save compatibility is not an acceptance gate. Keep the eventual Drawing standalone/Atlas project format choice explicit under [[T-051]].

## Superseding portable multi-file Object Asset direction — 2026-11-02
The owner now explicitly requires an **`Objects/` folder beside the campaign file**, to move/copy with the campaign. Therefore the prior statement “retain single-file direction” applies to the **campaign file itself only**, *not* the entirety of a portable campaign. Reusable Object Assets will be external relative files; map artwork may remain inside the native campaign file until the DrawingDocument boundary is approved (T-051).

### New acceptance
- Moving or copying the campaign file **with** its sibling `Objects/` preserves stable asset IDs, nested asset references, instance transforms, fonts and object selection. Copying the campaign file **alone** must report missing assets clearly instead of silently substituting them.
- Save newly authored Object Asset edits only on the Object Editor's **Save** action; unsaved drafts must never leak to other instances or persisted files.
- Save As through Atlas instance A: safely persist B and rebind A; if interrupted/crashed during either operation, recover to an explicit coherent state (old binding or new B+binding) without truncating source. B remains saved after undo.
- New project storage must distinguish **campaign dirty state** from changes in the external Object Asset library and font resources. No false “clean” state after a retained new asset or failed save.
- Prevent directory traversal and unintended asset paths outside portable project roots; define rename/case-collision and duplicate-ID behavior.
- Preserve project portability for bundled fonts; choose whether fonts are native embedded resources or `Fonts/` sidecars after licensing review. Do not bundle unlicensed OS fonts.
- Historical user-save migration remains **not required**. New-format roundtrip, isolation, atomic writes and failed-save recovery are required.
