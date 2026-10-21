# local-adaptive-queue handoff

State: branch `worktree-wf_d4f933d8-5ab-1`, round 2 (r1 blocker fixed); main merged; check.sh green via the slot.

Verified:
- `lean/Fw/Sup/Adapt.lean`: controller (`step_range`, `step_change_spaced`, `changes_spaced`, `step_overload`,
  `step_under`, `swap_static_never_trips`), holders (`live_never_recovered`, `renew_*`, `release_*`), admission
  (`verdict_admit_fits`, `verdict_admit_under_n`, `verdict_admit_head`, `verdict_admit_sim_exclusive`,
  `verdict_no_overtake`, `leanThreads_*`; `starved` skips a Simulator ticket while the Simulator is held:
  `starved_iff`, `starved_skips_blocked_sim`, `verdict_not_older_of_sim_blocked`), Simulator (`simBoot_iff`, `sim_*`), stop (`stop_*`), cache (`cacheHit_*`).
- `lean/Fw/Sup/AdaptGolden.lean` writes `packages/contracts/golden/sup/adapt.jsonl` (99 cases, 12 ops; r1 reviewer scenario "old sim ticket blocked by a sim holder"); check.sh job
  "sup-adapt golden check".
- `apps/runner/src/slot-core.ts` (TS stand-in) replays every golden case in `apps/runner/test/slot.test.ts`.
- Stale `state.lock` recovery renames the lock aside, re-reads its owner, removes it if dead, moves it back if live
  (`recoverStale`, tests "state lock recovery"). Residual: release still removes `state.lock` by path.
- `fw slot run` was run by hand: TERM was ignored by the child, KILL followed after the 5 s grace, exit 137, and the
  holder was released.
Open (follow-ups, outside the pinned unit):
- Console view of N, queue and waits; migrate the sim-lock.sh callers (measure-engineer.md, measure-webkit
  device.mjs, gate-breakpoints); `fw slot sim --apply` in `fw watch`; retire heavy-lock; busy-hour measurement.
- r1 follow-ups: review-cache records are unauthenticated and the key omits env and Node version (add
  `process.version` and an env digest to `CacheKey`, or record the producer); link `verdict_head_admitted` to
  `Fw.Sup.Props.head_job_granted_by` or say in slot.md why it is a separate model; Simulator rules are advisory, and
  `simIdleSince` must start at the first unheld sighting of a booted device, not 0, before `--apply` joins `fw watch`.
- Recalibrate the footprints and controller targets from more sampler windows.

Conventions: Lean first. Change `Fw.Sup.Adapt`, regenerate with
`printf 'import Fw.Sup.AdaptGolden\n#eval Fw.Sup.Adapt.gen []\n' | lake env lean --stdin` (in lean/), then mirror the
change in slot-core.ts. Tests inject `Deps` and never boot the Simulator or read the real state.
Read first: `docs/team/tools/slot.md`, then `lean/Fw/Sup/Adapt.lean`.
