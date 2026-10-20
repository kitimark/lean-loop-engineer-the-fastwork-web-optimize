# Handoff: lake-build-slots

**State:** branch `worktree-wf_6c3ae4fd-86e-2`, round 2. Code commit d3d2598b (bench spans, CI run 39423547036), then
one commit with the lock-tool test and this handoff (CI run on it below). `sh lean/scripts/check.sh` green at the final commit; apps/runner `pnpm test`
1437/1437; `scripts/ci-paths.test.mjs` 41/41; `scripts/lake-slot.test.mjs` 9/9.

**What exists:**
- `lean/Fw/Sched/LakeSlot.lean`: pools `[full, cap 4]`, `pick` (first free slot), `bound n = n + 4` (12 here).
  Theorems: `held_threads_le`, `pick_within_bound`, `pick_free`, `pick_none`, `pick_solo`, `held_within_budget`,
  `further_waits`, `second_full_waits` (full-pool token), `solo_full`, `bound_eq`, `bound_hw`. Generates `golden/sched/lake-slot.gen.sh`.
- `scripts/lake-slot.sh`: opens fd 9 on `<git common dir>/lake-slot/<i>`, locks it with `lockf`/`flock` in fd mode, then
  execs the command (no inner sh, exit status is the command's). Sourced form `LAKE_SLOT_LIB=1 . lake-slot.sh; (lake_slot <root> cmd)`.
  A build that waited writes the span `lake-slot/wait`.
- Call sites (all sourced): `scripts/fwcore-build.sh` (so check.sh and the land queue) and the land axiom lint (`Fw.Console.LandDry.Lint.argv`).
- CI: lean.yml runs `node --test scripts/lake-slot.test.mjs` on Linux; apps/runner `test/ci-triggers.test.ts` runs it on a land.
- Premise `land.binaryOfLean` names the wrapper files as not changing the binary bytes (INFERRED).

**Verified** (spans `lake-slot/bench`, commit d3d2598, main's `.fw-console/timings.jsonl`; local debug runs, load 7-33,
solo on a scratch `LAKE_SLOT_DIR`; pairs alternate order; delta = slot - plain):
- No-op `fwcore-build.sh` (`same-root`): median 296 vs 297 ms, paired delta 0 ms, slot slower in 18/40; A/A -1 ms, 7/20 (supersedes the biased group `noop fwcore-build`).
- No-op bare `lake build` vs the lint form: 188 vs 192.5 ms, +4.5 ms, 29/40. That is the fixed cost (lockf + sourcing + one fork).
- Clean: 10 small pairs 7262 vs 7482 ms, +81.5 ms, 5/10; 5 `Admit.lean` pairs 145 vs 148 s, +2.1 s, 4/5 (load noise).
- CI lean.yml run 39423547036 (d3d2598) green: Linux wrapper tests 8/8, check.sh `lake build` stage through flock.

**Open items:**
- LSP workers and ad-hoc `lake build` calls run without a slot (follow-up: lean-prover instruction to use the wrapper).
- Threads inside each lean process are not bounded; `hw = 8` is the dev Mac's core count. Fixed cost per build: one
  `lockf`/`flock` spawn plus sourcing, ~3-5 ms on the dev Mac (accepted).
- `fwcore-build.sh` hashes the 75 MB binary twice on a no-op; one hash would save far more than the wrapper costs.

**Read first:** `lean/Fw/Sched/LakeSlot.lean`, `scripts/lake-slot.sh`, `scripts/lake-slot.test.mjs`.
