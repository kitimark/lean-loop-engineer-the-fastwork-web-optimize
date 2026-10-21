# ci-push-probe-inputs (with fw-run-dispatch-pick): handoff, round 2

State: branch worktree-wf_06230cac-6e8-1. Commits: 9701601e (all fixes), 8a26f39d (run-pick test filter), b71d1847 (CI push commit).
Verified: lean/scripts/check.sh green; apps/runner test (1665), packages/gh-budget test (65), scripts/ci-paths.test.mjs (52),
ci-push.test.mjs, trajectory-line.test.mjs green. CI: one run, push, chromium + width 390 (ONE leg): run 39522707053, job
`merge chromium` success, `fw ci wait --workflow trajectory-probe --sha b71d1847...` picked it (exit 0).

Round 1 fixes
1. Trigger.lean trajectory-probe.yml row now lists trajectory-line.mjs, its test and golden/ci/triggers.jsonl. New ci-paths test
   `scriptsNamed`: every .github/scripts/* path in a workflow (comments left out) must match that workflow's Lean inputs. It also
   found two older gaps, fixed in Lean: land.yml lacked land-base.sh, wktr.yml lacked changed-inputs.test.mjs.
2. One-leg merge: each leg uploads `artifact-name.txt`; `merge` / `merge-apple` move a single download under legs/<name>/
   (download with merge-multiple false). Proved by run 39522707053.
3. `fw ci wait --branch --workflow` selects by identity: push = event push + head sha prefix of --sha; `--nonce n` = the dispatch whose
   title carries the nonce. Lean `Fw.Ci.Dispatch.wanted/select` + 7 theorems (one per branch), golden `select` lines in
   golden/ci/dispatch.jsonl, TS twin packages/gh-budget/src/want.ts (TS stand-in until a fwcore op), used by wait.ts `relevant`
   (Target.want). The poller list now also reads `event,displayTitle`. fw ci wait lives in packages/gh-budget (not apps/runner).
4. `pnpm fw ci push` prints needsLane / refused before the push (`probeNotes`, scripts/ci-push.mjs; refused stops with exit 2).

Accepted limits: a plain `git push origin ci/x` reports nothing (said in trajectory-probe.md and the preamble); `--gate` and the
count lanes of `fw run` keep the newest-run rule (Target.want absent); an old runs-status file without event/displayTitle selects no
run until the next poller tick.

Writes beyond the task list: packages/gh-budget/{src/cli,poller,state,wait,want}.ts and tests, scripts/ci-push.mjs(+test),
apps/runner/test/run-pick.test.ts, lean/Fw/Ci/Dispatch.lean, golden dispatch.jsonl. Read first: Dispatch.lean section "Which run does a wait mean?".
