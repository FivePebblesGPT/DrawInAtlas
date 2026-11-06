---
id: E-SAVE
type: epic
priority: P1
---
# Native-save gate — integrity through model cleanup

## Baseline and reopening
The single-file native save implementation was previously verified and merged. Its reports and benchmark evidence are archived. The gate is reopened for the persistence impact of [[T-029]] and the model decisions in [[E-003]], not because the review demonstrated a new file-corruption defect.

## Ticket
- [[T-029|Audit/remove obsolete dictionary conversion paths and revalidate native saves]]

## Acceptance
- Retain the accepted native single-file direction unless a separate decision changes it.
- Model cleanup preserves exact artwork, identity, native values, isolated mutable copies, undo and recoverable activation.
- Replace required cloning/validation responsibilities before removing their dictionary adapters.
- Re-run meaningful native roundtrip, recovery and compatible-installation checks after relevant changes; decide any native schema change explicitly.

## Historical evidence
[[Archive/2026-10-30/NATIVE_SAVE_IMPLEMENTATION|Native-save report]] · [[Archive/2026-10-30/NATIVE_SAVE_BENCHMARKS|AD-10 measurements]]. Completion: [[Index]].
