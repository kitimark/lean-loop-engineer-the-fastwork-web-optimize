# land-speed-lean handoff

**State.** `lean/Fw/Console/LandSpeed.lean` has 32 theorems and no sorry. Axioms are within {propext, Classical.choice, Quot.sound}. It is imported from `lean/Fw.lean`. The golden file `packages/contracts/golden/console/land-speed.jsonl` has 32 lines. `lean/scripts/check.sh` is green, with mathview reporting 0 failing. Commit: the land-speed-lean commit on this worktree branch.

**What it proves** (spec: research/notes/2026/10-18-land-speed.md, P2-P5):
- (a) Cache: `cache_sound`, `cachedRun_eq`, `integrity_push`, `undeclared_refutes`. checksFor: `skip_sound`, `selected_of_mem`, `readsOnly_within`, `mem_selectChecks`. `NoCollision` is an explicit premise.
- (b) Lint: `lint_modular`, `mkey_sound`, `mkey_congr`, `lintAll_nil_iff`.
- (c) Pre-lock: `pre_eq_old`, `pre_eq_old_iff` (equal iff HEAD = main0), `pre_moved`, `pre_commit_checked`, `evidence_irrelevant`. On the Land repo model: `preLand_eq_old`, `preLand_commit_exact` (reuses `land_commit_exact`), `preLand_moved`. Runner decision: `prelockAction_pre`, `prelockAction_fallback`.
- (d) Verdict: `seq_eq_all`, `all_perm`, `verdict_perm` (completion order does not matter), `verdict_pass_iff`, `verdict_jobs_pass_iff`, `verdict_fail_final`.

**Golden ops for the land.ts implementers.** `landSpeed.select` uses `selectChecks` with PathCheck globs. `landSpeed.prelock` uses `prelockAction`: ff, refuse, recheck or fallback. `landSpeed.verdict` uses `verdict`: pass, fail(ids) or pending(ids). `landSpeed.cache` returns the first stored entry for a digest. `landSpeed.premise` holds the premise rows. To regenerate the file, run a two-line script `import Fw.Console.LandSpeed` / `def main := Fw.Console.LandSpeed.writeGolden` with `lake env lean --run` from `lean/`.

**Empirical premises** (`premises` in the module). Fw.Ops.Premise is not on main yet, so these rows use the same (id, statement, theorems, test) shape. Merge them into its registry once it lands. Its `engines` field is browser-only, so these premises need a CI lane instead.
- land.readsOnly: land-inputs test (an undeclared golden change selects check.sh) plus a CI strace of reads.
- land.readsWithin: checksFor is checked against the landSpeed.select golden.
- land.noCollision: an assumption about sha256. Not tested.
- land.coneLocal: a grep gate in check-partial.sh plus a CI diff of the incremental lint against the full mathview.
- land.lintOrder: the same CI diff. The mathview sort key must become total.
- land.nonInterfere: CI strace of each stage-2 job.
- land.checkDeterministic: CI runs check.sh twice on the same commit.
- land.mergeTreeReproduces: replay of the last 30 lands (30/30 MEASURED).
- land.checkedWorktreeExact: test that an untracked imported .lean file is cleaned or refused.

**Open items**
- Unify (a) with gate-speed-ci's generic `lean/Fw/Ops/Cache.lean` (cache_sound, key_complete) once both are on main. (a) is self-contained here on purpose.
- Nothing runs `checkGolden` in `lake test` yet. Wire it into `lean/FwTestMain.lean`, which was outside my writes, as Timing does.
- `checkShReads` is a proposal. checksfor-inputs owns the final declared-reads list and should edit it in Lean.
- land-prelock adds the HEAD guard on `Land.begin`. `preLand` already models it.

**Read first:** the module docstring of LandSpeed.lean, then sections (c) and (d).
