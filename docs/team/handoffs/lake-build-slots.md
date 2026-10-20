# Handoff: lake-build-slots

**State:** branch `worktree-wf_6c3ae4fd-86e-2`, last code commit 395f47a8 (the handoff commit follows it). `sh lean/scripts/check.sh` is green
there. apps/runner `pnpm test` passes 1437/1437. `node --test scripts/ci-paths.test.mjs` passes 41/41 and
`scripts/lake-slot.test.mjs` passes 7/7.

**What exists:**
- `lean/Fw/Sched/LakeSlot.lean` defines the pools `[full, cap 4]`, `S = 2` and `bound n = n + 4` (12 on the 8-core Mac).
  It has the Admit `budget` and `item` and `gen` / `gen ["--check"]` for `packages/contracts/golden/sched/lake-slot.gen.sh`.
- Theorems: `held_threads_le` (distinct slots hold at most `bound n` threads), `held_within_budget` (Admit `used` stays
  within budget for every Res), `further_waits`, `second_full_waits`, `solo_full`, `bound_eq`, `bound_hw`.
- `scripts/lake-slot.sh <cmd>` locks one `<git common dir>/lake-slot/<i>` file at a time (lockf on macOS, flock on Linux; exit 75
  means busy).
  - Slot 0 keeps the caller's pool, slot 1 sets `LEAN_NUM_THREADS=4`, and with both busy it retries every second.
  - `LAKE_SLOT` set means a nested call; `LAKE_SLOT_DIR` overrides the dir.
- Call sites go through the wrapper: `scripts/fwcore-build.sh`, the check.sh build stage, and the land axiom lint.
  The lint's argv lives in Lean, `Fw.Console.LandDry.Lint.argv`, and the golden `land-dry.jsonl` is regenerated from it.
- New reads are declared in `land.ts` CHECK_SH_READS, `LandSpeed.checkShReads` and the lean.yml row of `Fw.Ci.Trigger` (goldens regenerated).

**Verified (local debug runs on a loaded Mac; spans have tool `lake-slot/bench` in main's `.fw-console/timings.jsonl`):**
- Solo 12-module build, median of 3 at load ~13: plain 4.90 s, wrapped 5.00 s (within noise). Wrapper startup is 13.0 ms (`sh -c true` takes 5.6 ms).
- Two overlapping builds: plain peaks at 16 lean children and 6.3 GB RSS; wrapped peaks at 12/11 children and 4.7/4.3 GB.

**Open items:**
- Lean LSP workers and agents' ad-hoc `lake build` calls run without a slot. The follow-up is a lean-prover instruction to use the wrapper.
- The Linux `flock` branch has not been run (the Mac has no flock); CI runs check.sh on Linux.
- If lockf fails with any code other than 75, the wrapper returns that code; it does not fall back to an unslotted run.
- `hw = 8` is the dev Mac's core count. A CI runner with fewer cores still gets 4 threads in slot 1.

**Read first:** `lean/Fw/Sched/LakeSlot.lean`, `scripts/lake-slot.sh`, `scripts/lake-slot.test.mjs`.
