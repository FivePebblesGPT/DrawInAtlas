# Native raster ticket reconciliation — 2026-11-15

This is a **planning-only** change after the owner's explicit alpha architecture decision. No Rust/native implementation, release, benchmark or physical UX gate is claimed complete. Ticket YAML status remains authoritative; this document explains why older text/status was changed.

## Architecture decision

- Run real 96px Hokusai hard-round full-canvas test first ([T-146](Tickets/T-146.md)); compare latency and coverage without demanding Legacy pixel equality.
- Rust's existing shared `DrawingNativeBrush` becomes **one** hard/preset stroke engine ([T-147](Tickets/T-147.md)). Rust owns source tile buffers, masks, blending, copy-on-write, transaction preflight, rollback and undo ([T-148](Tickets/T-148.md)).
- Godot retains UI/pointer reception, layer and metadata controls, workspace/Atlas orchestration and GPU texture submission. Interfaces are **batched samples in; bounded dirty tile handles/packed RGBA8 out** ([T-149](Tickets/T-149.md)), not per-pixel FFI/GDScript edit dictionaries.
- Retire Legacy and native-free brush fallback without migration code ([T-150](Tickets/T-150.md)). Alpha builds may break temporarily; final supported native builds still need tests. Profile the new architecture ([T-151](Tickets/T-151.md)) before optimizing measured hotspots ([T-152](Tickets/T-152.md)).

## Active ticket changes

| Ticket | New decision | Reason |
| --- | --- | --- |
| [T-068](Tickets/T-068.md) | In Progress; Rust-first mandatory direction, T-151 evidence dependency | 2026-11-12 optimized-GDScript default was a historical decision |
| [T-085](Tickets/T-085.md) | In Progress; native batched input revalidation after T-149 | Retain live-preview/input goals; retire instruction to keep GDScript Brush baseline |
| [T-086](Tickets/T-086.md) | In Progress; revalidate Godot texture cache against native dirty tiles | 192px full-render baseline is historically obsolete; hardware zoom/cache gates remain |
| [T-088](Tickets/T-088.md) | In Progress; Rust mask seam after T-149 | Keep selection/clipboard/Move semantics, not GDScript per-pixel Brush authorization |
| [T-094](Tickets/T-094.md), [T-106](Tickets/T-106.md), [T-107](Tickets/T-107.md) | In Progress; final required-native CI after T-150 | Retain T-122 immutable historical 46-log proof, replace Legacy/native-free live workflow and recount required checks |
| [T-095](Tickets/T-095.md) | In Progress; hard T-152 dependency, owner manual gate unchanged | Historic exact Legacy geometry is not Hokusai acceptance; physical latency remains |
| [T-096](Tickets/T-096.md) | **Manual Review → Blocked**; T-149 hard dependency, `manual_review: true` unchanged | Physical owner signoff should follow revalidated native Move/mask/preview behavior |
| [T-105](Tickets/T-105.md) | In Progress; required-native Windows/Linux export+RSS/VRAM after T-150 | Native-absent release was an earlier historical experiment, not the future artifact |
| [T-104](Tickets/T-104.md) | **Done unchanged**, now explicitly historical | Keep benchmark facts, not outdated optional-native recommendation |

## Historical completed work

[T-084](Tickets/T-084.md) and [T-097–T-101](Tickets/T-097.md) remain **Done**, with their historical benchmarks/evidence intact. Their GDScript-first or Legacy-specific implementation is deliberately not mandatory in the future runtime. NativeHard/Hokusai correctness remains *per mode* (coverage, preview/save/Undo, rollback), not forced cross-mode pixel identity. Display and safety contracts from T-102/T-103/T-124–T-145 still matter and should be adapted at T-149/T-150.

## Preserved independent gates

- T-095: actual owner hardware large-Brush input-to-visible and release responsiveness, explicit signoff.
- T-096: full-size physical selection/Move UX acceptance after native revalidation, no implied signoff from old framebuffer oracles.
- T-056/T-059/T-065/T-083 and T-039/T-043/T-048: respective owner/privacy/UX decisions unaffected.
- T-105: supported Windows/Linux **required-native** exports and memory; do not claim Windows result from Linux.
- T-094/T-106/T-107: fresh hosted green on actual future native branch SHA; historical 46 IDs remain pinned to their old workflow.
- T-088/T-086: correct native mask, clipboard/Move/viewport integration and real-device presentation.

## Scope of this commit

Ticket/Index documentation only. The previous verbose Index remains as [dated history](Index-History-2026-11-15.md); all 152 canonical tickets remain indexed once. This audit does not mark an unfinished implementation or owner gate Done.
