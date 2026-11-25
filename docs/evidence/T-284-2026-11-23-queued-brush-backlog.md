# T-284 — Deterministic queued Brush CI backlog, 2026-11-23

## Provenance and diagnosis

- Source branch: `sprint/2026-11-23-godot-beta4`, parent commit
  `a7511b27bf1efb3b90a89104d5bd37b60b47e84a`; remote `main`
  `bbae76c33a6066582b2cd89e07cc3246fef942ce` verified at ticket start.
- The hosted fast-desktop run for merged PR #22 (`45215183959`, beta3)
  produced `T124_QUEUED_FAILED: overflow guard starts with backlog`,
  `...excess input fails visibly...`, `...original released stroke still
  finishes`, and `...pending second release held before failed commit`,
  followed by `Invalid access to property or key 'expected_revision' ... Nil`.
- The original 210-point beta4 fixture **passed locally (78/78)**; no
  current production defect was reproduced. The failure mechanism is a
  precondition hazard: `finish_gesture` may consume up to 256 segments
  synchronously, leaving no pending predecessor when the next press arrives.
- The patch uses 840 distinct samples along the same curve, guaranteeing
  at least 840 segment visits regardless of native brush speed, rather
  than inserting arbitrary sleeps or disabling the fast release drain.
  Fault injection now fails closed if the predecessor is missing.

## Tests and retained artifacts

Run from the repository root using bundled `godot` (4.8.beta4.official.b070e63b1)
with compiled mandatory `libdrawing_brush.so` loaded. Godot was launched as
root in a sandbox, so the harmless root warning is retained in raw logs.

| Witness | Result | Logs |
| --- | --- | --- |
| Original 210-input beta4 fixture | 78/78 passed; historical hosted beta3 still failed | [baseline](T-284-2026-11-23-queued-brush-raw/original-beta4.log) |
| Revised 840-input fixture | **4 runs × 78/78 passed** | [run 1](T-284-2026-11-23-queued-brush-raw/queued-run1.log), [run 2](T-284-2026-11-23-queued-brush-raw/queued-run2.log), [run 3](T-284-2026-11-23-queued-brush-raw/queued-run3.log), [run 4](T-284-2026-11-23-queued-brush-raw/queued-run4.log) |
| 12-sample failure control | Exit 1, 50 detected failures, no `SCRIPT ERROR` | [mutant](T-284-2026-11-23-queued-brush-raw/short-predecessor-mutant.log) |
| Real software-X11 pointer + framebuffer | **20/20** passed | [X11](T-284-2026-11-23-queued-brush-raw/queued-x11.log) |
| T-085 live-stroke headless | 81/81 passed | [T-085](T-284-2026-11-23-queued-brush-raw/live-stroke.log) |
| T-125 pending persistence | 29/29 passed | [T-125](T-284-2026-11-23-queued-brush-raw/persistence.log) |
| T-126 pending tab switch | 34/34 passed | [T-126](T-284-2026-11-23-queued-brush-raw/tab-switch.log) |
| T-127 pending history | 40/40 passed | [T-127](T-284-2026-11-23-queued-brush-raw/history.log) |
| Python T-124/T-125/T-126/T-127 | 13/13 passed | [contracts](T-284-2026-11-23-queued-brush-raw/python.log) |
| Ticket-store validator | 284 tickets, gates intact | [validator](T-284-2026-11-23-queued-brush-raw/tickets.log) |

Example reproducible commands:

```sh
GODOT=/path/to/bundled/godot
"$GODOT" --headless --audio-driver Dummy --path drawing \
  --script res://tests/t124_queued_brush_smoke.gd
xvfb-run -a "$GODOT" --display-driver x11 \
  --rendering-method gl_compatibility --audio-driver Dummy --path drawing \
  --script res://tests/t124_queued_brush_native.gd
python3 -m unittest discover -s tests -p 'test_t124_queued_stroke_ci.py' -v
python3 tools/validate_ticket_store.py
```

The deliberate mutation was performed only temporarily; the original
840-sample source was restored before final validation and commit.

## Boundaries

The 20-check X11 test exercises routed pointer events and checks actual
software framebuffer and canonical source pixels; it is not a human visual
inspection or owner hardware latency benchmark. This change only hardens
one regression test. No Rust/GDScript runtime code, release template,
CI workflow scheduling, or visual UI was changed. The beta3 hosted failure
is historical; **no new hosted beta4 run was observed**. T-085, T-094,
T-149, T-180 and T-250 remain open as recorded in their authoritative tickets.
