# local-adaptive-queue handoff

State: branch `worktree-wf_d4f933d8-5ab-1`; main merged in; check.sh green through `fw slot run --kind check`.

Verified:
- `lean/Fw/Sup/Adapt.lean`: controller (`step_range`, `step_change_spaced`, `changes_spaced`, `step_overload`,
  `step_under`, `swap_static_never_trips`), holders (`live_never_recovered`, `renew_*`, `release_*`), admission
  (`verdict_admit_fits`, `verdict_admit_under_n`, `verdict_admit_head`, `verdict_admit_sim_exclusive`,
  `verdict_no_overtake`, `leanThreads_*`), Simulator (`simBoot_iff`, `sim_*`), stop (`stop_*`), cache (`cacheHit_*`).
- `lean/Fw/Sup/AdaptGolden.lean` writes `packages/contracts/golden/sup/adapt.jsonl` (96 cases, 12 ops); check.sh job
  "sup-adapt golden check".
- `apps/runner/src/slot-core.ts` (TS stand-in) replays every golden case in `apps/runner/test/slot.test.ts`.
- `fw slot run` was run by hand: TERM was ignored by the child, KILL followed after the 5 s grace, exit 137, and the
  holder was released.

Open (follow-ups, outside the pinned unit):
- Console view of N, queue and waits (console-web, watch-collect), after step-threads lands.
- Migrate the sim-lock.sh callers: `.claude/agents/measure-engineer.md`, `packages/measure-webkit/src/device.mjs`,
  packages/gate-breakpoints.
- Run `fw slot sim --apply` from the `fw watch` tick, and retire heavy-lock into the slot.
- Measure busy-hour load before and after the change. Bound FIFO waits at trace level (sup-fairness
  `head_job_granted_by`).
- Recalibrate the footprints and controller targets from more sampler windows.

Conventions: Lean first. Change `Fw.Sup.Adapt`, regenerate with
`printf 'import Fw.Sup.AdaptGolden\n#eval Fw.Sup.Adapt.gen []\n' | lake env lean --stdin` (in lean/), then mirror the
change in slot-core.ts. Tests inject `Deps` and never boot the Simulator or read the real state.

Read first: `docs/team/tools/slot.md`, then `lean/Fw/Sup/Adapt.lean`.
