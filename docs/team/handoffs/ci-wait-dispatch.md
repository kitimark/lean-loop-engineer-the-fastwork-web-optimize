# ci-wait-dispatch: handoff (round 2)

State: branch worktree-wf_e007c264-660-4, last code commit 16267322 (after merge af281d80). Green at 16267322:
lean/scripts/check.sh, packages/gh-budget 70, apps/runner 1684 (incl. tsc), scripts/ci-paths.test.mjs 54.

Round 1 (4ced7032 Lean+TS twin+golden, 14b16d48 workflows/fw run/stripper/docs): identity waits, `Want.dispatch workflow nonce`,
`dispatchWorkflows`, `dispatchOnly` hint, `dispatch_any_sha`. Round 2 fixes, by finding
1. Apple one-leg: `pnpm -s fw run --trajectory --engines playwright-webkit --widths 390 --ref ci/ci-wait-dispatch` (one dispatch, nonce
   c4d36930f4a6719f) -> run 39542978747 at 16267322, event workflow_dispatch, title matches. `fw ci wait --nonce` picked it: pass.
   Jobs: probe apple (playwright-webkit, macos-26) 390 success, probe playwright-webkit 390 success, merge playwright-webkit success,
   merge apple (playwright-webkit) success.
3. Lean `runNameFor`; golden `workflows` line has `runNames`; `runNameProblems` in scripts/ci-paths.mjs (part of `run`) fails on a
   `name:` or `run-name:` that differs; test with each drift. No yml edited this round.
4. `fw run` sends `-f nonce` only when `git show <ref>:.github/workflows/<file>` declares it (`declaresNonce`); else the old pick
   (newest run created after the dispatch) and the log says so. Tests with a stub fwcore, none skipped.
5. Lean `selectOne` (One: found/absent/ambiguous; theorems per branch, `foldl_max_mem`), golden `one` lines; TS `selectOne`,
   `ambiguousIds`; `relevant` keeps no run and the wait returns code 2 ("matches several runs"), never the newest.
6. Window limit stated (wait.ts Target doc, cli usage, fw-ci.md): the poller reads runs created at or after `--since`; a dispatch
   created earlier is never read, pass an earlier `--since`. The test is renamed to the reachable claim.
7. Subjects for the lead at land (reword the two round 1 commits): a9832776 -> "ci: trajectory probe push (playwright-webkit 390;
   apple leg is dispatch-only, not run)"; 5fdb0b4e -> same plus "(trajectory-probe.yml comment edit to pass the unchanged guard)".

Open
- One dispatched run per workflow with a nonce exists only for trajectory-probe (39542978747). breakpoint-gate, chromium-counts and
  webkit-sim run-names and nonce inputs have never run on CI. Command, by the lead: `pnpm -s fw run --gate --engines chromium
  --ref ci/ci-wait-dispatch` (and a count run per lane); the run-name text is checked by ci-paths, not by a run.
- Workflows outside `dispatchWorkflows` keep no nonce (accepted limit).
Writes beyond the task list: Layout.lean (`Lane.inputs` + "nonce", merged with main's `lag`), the three yml files (nonce input,
run-name), trajectory-probe.yml comment, gh-budget index.ts, run-budget.test.ts, scripts/ci-paths.mjs. TS stand-ins: want.ts,
run-pick.ts, `declaresNonce` (replayed or tested, no fwcore op). Read first: Dispatch.lean "Which run does a wait mean?".
