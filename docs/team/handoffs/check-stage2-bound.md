# check-stage2-bound handoff (branch worktree-wf_fe8c7e16-30d-1)

State: `lean/scripts/check.sh` runs its 46 stage-2 jobs inside one Lake slot, through a FIFO token gate of width
`stage2Width slot cores`. That width is the slot's pool threads (8 for slot 0, 4 for slot 1), capped at the online cores.
`scripts/lake-slot.sh` with no command prints a usage line and exits 64.
- Lean `Fw.Sched.LakeSlot` defines `perJob`, `width`, `stage2Width`, `Holder` and `procs`. Theorems:
  `holders_within_bound` (holders on distinct slots run at most `bound hw` = 12 lean processes), `stage2_with_build`,
  `capped_stage2_with_build`, `stage2Width_le_width`, `stage2Width_le_cores` and `stage2Width_pos` (the gate never has
  width 0). The generated `packages/contracts/golden/sched/lake-slot.gen.sh` adds `LAKE_SLOT_WIDTHS` and
  `LAKE_SLOT_WIDTH_CASES`; the shell test checks `lake_slot_hold` against every case.
- `scripts/lake-slot-lib.sh` adds `lake_slot_hold`, `lake_slot_gate`, `lake_slot_run` and `lake_slot_release`. Cores
  come from `getconf _NPROCESSORS_ONLN`, or from `LAKE_SLOT_CORES` in tests. Jobs in check.sh are ordered longest first.
- CI MEASURED: run 39446358540 (sha 0aa35b65, temporary bench), attempts 1-6, ubuntu-24.04-arm with 4 CPUs.

  | measure | before (unbounded) | width 8 | cap = 4 |
  |---|---|---|---|
  | in-run stage-2 group, 18 paired trios, mean | 33.3 s | 33.9 s | 29.2 s |
  | peak lean processes | 38 | 7 | 4 |
  | peak summed RSS | 19.0-21.0 GB | 8.1-8.8 GB | 6.3 GB |

  - Cap vs before: 18 of 18 trios are faster; median -4.0 s.
  - Main-pass check.sh: before 32.7 / 34.9 / 35.7 s (attempts 1, 3, 5); cap 29.5 / 30.7 / 30.3 s (attempts 2, 4, 6).
  - Width 8 without the cap is about 3% slower (run 39440589251, 12 pairs). Mechanism: on 4 cores, the critical-path
    props lint shares the CPU with 7 jobs for longer.
- The final design (sha 1c086d74) is green on CI in run 39454230214, with a parallel group of 29.8 s.
- Local DEBUG overlap: a slotted clean build plus check.sh peaks at 12 lean processes (9.5 GB), against 46 (17.9 GB) before.
- Open: `lake serve` and ad-hoc `lake` calls are not slotted; `hw = 8` is fixed in Lean; OS threads inside a lean
  process are not bounded; gen.sh is outside the task's write list; the land-lane leg move is task land-check-remote.
- Read first: the `stage2Width` section of lean/Fw/Sched/LakeSlot.lean, then lake-slot-lib.sh `lake_slot_hold`.
