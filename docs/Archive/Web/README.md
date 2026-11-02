# Paused Web work

**Status:** archived and out of the active release plan as of 2026-11-02, at the owner's request. Reactivation requires a deliberate platform/architecture decision.

## Archived ticket
- [[T-044|T-044 · Web-compatible player-output fallback]] — browser-compatible player output and browser-runtime acceptance; preserved with its historical engineering checkpoint.

## Explicit boundaries
- **Desktop Drawing and Atlas** are the current supported product direction. Native rendering alternatives can be evaluated without a Web compatibility constraint.
- This archive **does not remove existing source code, test fixtures or documentation evidence**. Actual Web-only code cleanup, if desired, is a separate engineering task.
- Privacy filtering, local projector/native player output and token/fog behavior in [[E-007]] are **not archived** merely because they previously offered an optional Web fallback.
- Don't treat a previously passing Web export artifact as a supported browser runtime or active release requirement. If Web returns, reopen a current ticket with runtime tests, export/dependency verification and acceptance criteria.
