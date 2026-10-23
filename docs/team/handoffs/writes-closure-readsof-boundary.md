# writes-closure-readsof-boundary

- Branch: worktree-wf_8a2bc754-9d5-1 (worktree .claude/worktrees/wf_8a2bc754-9d5-1)
- Work commit: 412e175f5; main 069aa37ce merged after it; dry land `VERDICT dry writes-closure-readsof-boundary`;
  review gate `VERDICT review-ready writes-closure-readsof-boundary review`
- CI runs: none (all checks local: check.sh, vitest, node tests)
- Verified: check.sh green (axiom check 0 failing); @fw/runner 3181/3181 incl. tsc; @fw/contracts 11/11; ci-paths
  56/56; `node scripts/ci-paths.mjs --check` and `--plan-time --check` ok; `fw plan lint` on main's graph: 0
  writesClosure errors (1 unrelated error: polish-commit-failsafe trailerNoEvidence)
- Open: none inside the graph row's writes.

## What changed
- (1) Lean `readsFrom b s` (`readsOf s = readsFrom true s`): a `../` starts a read only at a word start (text start or
  after a `readStop` char); a `/../` inside a word reads `none`; another `../` inside a word reads nothing. Theorems
  `readsFrom_seg`, `readsFrom_start`, `readsFrom_cons`, `readsFrom_word`, `readsFrom_true_eq`, `readsOf_mid_dotdot`
  (`x ++ "/../" ++ y` reads `[none]`). `jsSpace`/`readStop` now use `Char` lists so `decide` proves `readStop_dot`.
  JS twin: ci-paths.mjs `READ` regex in `leanScriptPaths`; new golden gap vector `lean/scripts/b.sh`; test
  "x/../y is refused ..." in apps/runner/test/plan-closure.test.ts.
- (2) Lean `calm d l` = not `Fw.Obs.Timing.contended {loadMax := calmLoad}`; `calm_iff`, `mem_calmDurs`;
  `timeTable` takes `(durMs, load floor)` pairs and keeps calm runs. Golden row `timeParams` (calmLoad 4, window 30) is
  read by ci-paths `timeParams`. plan.md refreshed from main's `.fw-console/timings.jsonl`: 114 samples, 58 calm
  (30 before in the window, 10 with the check).
- (3) ci-paths.mjs `Run:` line lists `--plan-time [--refresh <timings.jsonl>] [--check]`.

## Read first
`lean/Fw/Plan/WritesClosure.lean` `readsFrom`, `readsOf_mid_dotdot`, `calm`, `timeTable`; ci-paths.mjs `READ`,
`timeParams`, `planTimeBlock`.
