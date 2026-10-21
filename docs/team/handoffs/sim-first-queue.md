# sim-first-queue handoff

State: branch `worktree-wf_4f44dcb1-f19-1`, main merged, check.sh green via the slot; runner tests green.
Verified:
- `lean/Fw/Sup/Adapt.lean`: Simulator priority (`yieldsToSim`, why `drain` and `simFirst`, `verdict_sim_never_older`,
  `admit_keeps_simInv`: every admission keeps "sim held implies at most one other holder", `sim_not_starved`), the old
  lock as a holder (`withLegacy`, `verdict_legacy_blocks_sim`), the idle clock (`simIdleNext`, `simDue`,
  `sim_first_sighting_keeps`, `sim_shutdown_only_unheld`), builder admission (`admitBuild_iff`, `agentsSeen_stale`).
- Golden `packages/contracts/golden/sup/adapt.jsonl` (141 cases, 19 ops), replayed by `slot.test.ts`.
- `slot.ts`: acquire polls and release run the Simulator check (every booted device, under the state lock);
  `fw slot held`; `fw slot admit --kind build` (VERDICT line, exit 0/75). `sim-lock.sh` gives its directory back while
  a slot sim holder is live (test drives the real script); `fw slot acquire --kind sim` keeps its interface and exits.
- MEASURED Simulator pass under contention (UTC 2026-10-22, one window; iPhone 17 booted, Safari opened a local page):

| time | stage | load (1 min) | free MB | n | holders / queue |
|---|---|---|---|---|---|
| 20:12:58 | my sim ticket queued behind another agent's | 13.1 | 8519 | 2 | sim / sim; admit build: wait simWaits |
| 20:13:13 | my sim admitted at release (11 s wait) | 13.9 | 7864 | 2 | sim, check / none |
| 20:15:04 | booted (bootstatus 71 s), Safari open | 266 | 5734 | 1 | sim, check / check |
| 20:16:23 | 3 min in | 447 | 6062 | 1 | sim / check, test, test |
| 20:16:36 | shut down, released | 405 | 8519 | 1 | none / check, test, test |

  During boot, 185 runnable processes were Simulator runtime processes: the load comes from the Simulator itself, and
  the controller halved `n` to 1 so the queued work waited. Other worktrees still ran main's slot code then. At 20:28:56
  an acquire poll of my test ticket shut down an iPhone 17e left booted and unheld since 20:17 (idle clock, 600 s).
Open (follow-ups): `admit` in `build-review.js`; the Simulator check in `fw watch` (it runs only on slot polls and
releases); thresholds from one busy window; Simulator footprint not reduced; hand-booted devices are shut down too.

Conventions: Lean first, regenerate the golden as in `local-adaptive-queue.md`, mirror in slot-core.ts;
`State.simIdleSince` stays for older checkouts. Read first: `docs/team/tools/slot.md`, then `lean/Fw/Sup/Adapt.lean`.
