# trajectory-stable-followups

- Branch `worktree-wf_e50be261-576-1`, worktree `.claude/worktrees/wf_e50be261-576-1`; work commits d6e48189d, cd625fdf5, merged main.
- No CI run made: every claim below reads existing runs or re-reduces run 39926829451 offline (dev check).

## Verified
- `byMFam` (`src/trajectory/reduce.mjs`) judges the whole family in one walk from per-pass pieces (window, envelope,
  settled ref, `origFirst`); `byMFamEach` is the one-member-at-a-time definition. Test `byMFam equals byMFamEach`: 928
  golden cases, all four phases, original doubled into one more pass; a mutation (members keep every pass) fails it.
- Offline, merged raw of run 39926829451: 39.8 s before, 9.5 s shared; `units` byte-identical (CLEAN, 14416 units).
- CLI: every refused input, `summary` without raw files, `merge` without legs or with disagreeing legs, and an unknown
  command exit 2 (`laneExit` refused); test `cli: a refused input ...`.
- Lean `nil_not_mem_family`: a first pass on an empty original is outside `laneOf_stable_extra`.
- Doc `docs/team/tools/trajectory-probe.md` check 2: Linux WebKit open gap p50 120 to 183 ms over 10 runs (table with
  run ids); Simulator lag rows (run 39511908073) carry frame marks (open gap p50 30.0 / 31.4 ms) but no unit samples.

## Open
- CI reduce-step time of the merge step not re-measured on CI (offline only).
- A Simulator lane needs a new timed `webkit-sim` pass reading `m`, the probe properties and `t0` per frame.

## Read first
- `docs/team/tools/trajectory-probe.md` check 2 (Leave-one-out band, WebKit cadence, WebKit Simulator rows), check 3.
