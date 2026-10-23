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
- (1) Lean `readsFrom b s` (`readsOf s = readsFrom true s`): a `../` at a word start (text start or after a
  `readStop` char) reads its word; any other `../` reads `none` (refused, fails closed), so `x/../y`, `G=../x`,
  `a../b` and `.../c` are refused. Theorems `readsFrom_start`, `readsFrom_mid`, `readsFrom_cons`, `readsFrom_seg`,
  `readsFrom_word`, `readsFrom_true_eq`, `readsOf_word`, `readsOf_inner_up`, `readsOf_mid_dotdot`. JS twin:
  ci-paths.mjs `READ` (a match without capture is null); golden gap rows `lean/scripts/b.sh`, `lean/scripts/v.sh`;
  test "a ../ inside a word is refused ..." in apps/runner/test/plan-closure.test.ts. No real lean/scripts/*.sh
  has an inner `../` (0 refused reads on the repo).
- (2) Lean `calm d l` = not `Fw.Obs.Timing.contended {loadMax := calmLoad}`; `calm_iff`, `mem_calmDurs`;
  `timeTable` takes `(durMs, load floor)` pairs and keeps calm runs. Golden row `timeParams` (calmLoad 4, window 30) is
  read by ci-paths `timeParams`. plan.md refreshed from main's `.fw-console/timings.jsonl`: 114 samples, 58 calm
  (30 before in the window, 10 with the check).
- (3) ci-paths.mjs `Run:` line lists `--plan-time [--refresh <timings.jsonl>] [--check]`.

## Read first
`lean/Fw/Plan/WritesClosure.lean` `readsFrom`, `readsOf_mid_dotdot`, `calm`, `timeTable`; ci-paths.mjs `READ`,
`timeParams`, `planTimeBlock`.
