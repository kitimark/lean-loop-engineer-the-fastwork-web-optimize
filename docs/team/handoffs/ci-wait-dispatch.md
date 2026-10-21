# ci-wait-dispatch: handoff

State: branch worktree-wf_e007c264-660-4. Commits: 4ced7032 (Lean + TS twin + golden), 14b16d48 (workflows, fw run, stripper,
docs), a9832776 and 5fdb0b4e (CI push commits). Green here: lean/scripts/check.sh, packages/gh-budget test (68),
apps/runner test (1680, incl. typecheck), scripts/ci-paths.test.mjs (53).

Delivered (follow-up numbers from the graph title)
1. Code and Lean agree on dispatch: Lean `Dispatch.dispatch_any_sha` (the head sha plays no part); `relevant` in
   packages/gh-budget/src/wait.ts no longer cuts a wanted run by sha or `since` (test: dispatch on another sha is found).
2. `Want.dispatch workflow nonce`; `dispatchWorkflows` = trajectory-probe, breakpoint-gate, chromium-counts, webkit-sim (golden
   `workflows` line, TS `DISPATCH_WORKFLOWS`). `parseWait` refuses `--nonce` for any other workflow. Theorem per branch:
   dispatch_never_push, _other_nonce, _bad_nonce, _unknown_workflow, _selects, _any_sha. The other workflows keep no nonce.
3. Hint: Lean `dispatchOnly` (+3 theorems, golden `hint` lines), TS `dispatchOnly`/`hintOf`, printed on a push-wait timeout.
4. scripts/ci-paths.test.mjs `stripComment` tracks quotes; limit stated in its docstring (a lone apostrophe keeps comment text).
5. `fw run` count lanes and `--gate` dispatch with a fresh nonce and wait with `want: dispatch` (apps/runner/src/run.ts
   `dispatchAndWait`); no run list before the dispatch any more. `--trajectory` keeps `findDispatched`/Lean `pick`.
6. CI: push of ci/ci-wait-dispatch. Run 39529994249 (a9832776) was skipped `unchanged` (no trajectory-probe input differed
   from main); run 39530080105 (5fdb0b4e, engines=playwright-webkit widths=390): guard, site, `probe playwright-webkit 390`,
   `merge playwright-webkit` success; `fw ci wait` picked it (exit 0, pass).

NOT delivered: the apple leg. `probe-apple` and `merge-apple` run only on `workflow_dispatch` (trajectory-probe.yml line 475), so a
push cannot exercise them; both were skipped in 39530080105. Command in open[0].

Writes beyond the task list: lean/Fw/Store/Layout.lean (`Lane.inputs` gained "nonce" for chromium-counts, webkit-sim,
breakpoint-gate; LaneInputs --check demands it), .github/workflows/{breakpoint-gate,chromium-counts,webkit-sim}.yml (nonce
input + run-name), trajectory-probe.yml (comment), packages/gh-budget/src/index.ts, apps/runner/test/run-budget.test.ts.
TS stand-ins (until a fwcore op): packages/gh-budget/src/want.ts, apps/runner/src/run-pick.ts (both replayed against golden).
Read first: Dispatch.lean section "Which run does a wait mean?", then `dispatchAndWait` in run.ts.
