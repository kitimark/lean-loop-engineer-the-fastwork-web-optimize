---
id: 2026-10-2x-ci-state-burst
kind: note
title: "fw ci state finds runs inside a push burst: absent only past a 1000-id margin (Lean Fw.Ci.State)"
status: review
created: 2026-10-25
topics: [ci, tooling, lean]
---

# ci-state-burst: no "unknown" for a run hidden at a page boundary

## Answer first

- `fw ci state 40100783726 --branch ci/earn-webkit-smooth` prints `complete` (MEASURED 2026-10-25).
- `stateStep` returns absent only when a full page holds an id more than `burst` = 1000 below the target (Lean
  `Fw.Ci.State.step`, `absent_witness`, `absent_never_in_burst`). Otherwise it grows 100, 400, 1000 (`go_terminates`: 3
  reads), and a run within the first 1000 entries of a Bounded list is found (`present_found`).
- MEASURED: `gh run list --limit 400` on the branch returns 129 rows, and the most a later-listed id exceeds an earlier one
  is 345. `burst` = 1000 is INFERRED (an assumed margin, about 3x the observed max).
- The order inside a burst changes between calls (MEASURED: 40100783726 was entry 106 at build time and entry 87 on
  2026-10-25), so main's old rule also prints complete today; the golden case `realPage100` is the evidence that tells the
  two rules apart.
- Runs past entry 1000 print unknown (exhausted). gh ordering is taken as observed, not from GitHub source.

## Cause (CONFIRMED)

One push starts about 20 workflow runs. Their ids are not in the order `gh run list` returns them, so a full page of 100
can end inside a burst and hold an id smaller than a run listed after the boundary. The old rule read that smaller id as
proof the run was absent and printed `unknown`; build-review gates then marked valid runs failed (40100783726 for
earn-logical-proof, 40125463870 for unthrottle-follow).

## Limits

- `present_found` models each page as a prefix of one fixed list; gh reorders a burst between calls, so the verdict holds
  call by call only when each page is Bounded (follow-up: state it per page).
- The superseded `Fw.Ci.StateList` model still holds the old rule (follow-up: remove it).
