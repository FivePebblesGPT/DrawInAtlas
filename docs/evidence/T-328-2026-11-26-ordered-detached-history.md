# T-328 chronological detached history retention

2026-11-26, `sprint/2026-11-25`; verified PR #24 remote head
`79bf892fbab44ab7670655dca1b448e41788aae9`, local parent `e7e17c2e` (T-327).
Pinned Godot 4.8.beta4.official.b070e63b1 and bundled native toolchain.

## Fail-first and correction

The first real-native regression failed 6 of 406 checks. Both standalone
and Atlas record 65 consecutive signed, hidden-RGB edits on the same tile,
causing the oldest native token to be genuinely evicted by the 64-entry
limit. Traversing that oldest command destroyed all 64 newer Redo tokens.
The first corrected run passed 406/406; expanded final run passed 558/558.

Chronological replay explicitly distinguishes ordered owner-driven detached
replay from arbitrary detached recovery. The former preserves both native
stacks, rejects any still-retained token or negative token, shares the exact
canonical byte, active transaction, memory, revision and descriptor fences,
and creates no fabricated native token for the evicted event. The local
cursor and Atlas command owner use this checked path. Unordered recovery
continues conservatively invalidating native history. Tests cover repeated
traversal, stale, malformed and busy failures, and genuine branch disposal.
The older Hokusai fixture now removes the actual old token rather than
rewriting its ID; it retains the newer native token and exact stroke bytes.
An independent Rust test checks preservation of both stacks with an
interior detached event and validates failed attempts and exact retries.

## Verification

- `make test-ordered-detached-history TOOLCHAIN=bundle BUNDLE=/tmp/dia-toolchain`
  exit 0 after importing both projects: 558/558 checks and 48/48 Rust tests.
- Adjacent Atlas: T-148 detached replay 22/22, detached bootstrap 34/34,
  reentrant replay 26/26, payload 20/20, native Atlas history 43/43,
  Object source 38/38; T-322 142/142, T-325 190/190, T-326 96/96,
  T-327 91/91, chronological history 101/101.
- Adjacent Drawing: T-156 38/38, T-229 18/18, T-230 33/33, T-237 40/40,
  T-239 36/36, T-321 64/64, native tiles 312/312, T-310 binary 307/307.
  All 19 neighboring processes exited zero without failure markers.
- Explicit typing: 651 scripts and 33 skill documents; 35 Python CI contract
  checks passed. Ticket-store validation: 328 tickets and review gates.
- Required CI and ordinary Make test target include the new regression.

## Boundaries

The native history window is unchanged; older detached deltas remain in the
host timeline. Chronological ordering is a trusted command-owner contract,
not an independently verified Rust global timeline. Detached recovery without
that contract keeps its original token-invalidation behavior. No UI changes;
physical performance, Windows and hosted CI remain unverified. Local LFS
unavailable; stage only explicit source, documentation and test changes,
not hydrated existing assets. T-148 In Progress, T-250 Manual Review.
