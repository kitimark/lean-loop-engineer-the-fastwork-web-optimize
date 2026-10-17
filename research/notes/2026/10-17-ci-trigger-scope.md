---
id: 2026-10-17-ci-trigger-scope
kind: note
title: "CI trigger scope: every ci/** push started all five workflows; a paths filter per workflow removes 21 of 28 measured runs"
status: review
created: 2026-10-17
topics: [ci, github-actions, concurrency, paths-filter]
---

Question: why do runs queue on the free public repo, and what trigger design stops it?

## Answer

- **Cause (MEASURED).** `on: push: branches: ['ci/**', main]` with no `paths:` started every workflow on every push.
  Of 28 runs of lean, chromium-counts, breakpoint-gate and webkit-sim (8 pushes), 21 (75 %) did not touch any input
  of the workflow they started. Of 414 job-minutes, 248 (60 %) were that waste; breakpoint-gate alone is 176 of them.
- **Queueing is real (MEASURED, 2026-10-17 13:32-13:47 UTC).** Run 39036983052 (wktr, push of ci/wktr-local): job
  `wktr (j3)` started 6 s after its plan job, `wktr (j1)` after about 6 min (13:39:19), `wktr (j2)` after about 8 min
  (13:40:56). At that time 5 macOS jobs were running: sim v1 and v2 of webkit-sim run 39036078841 (ci/webkit-fix,
  started 13:19, still in progress at 13:49), sim v1 of webkit-sim run 39036982894 (an unneeded run from the same
  wktr-local push), and wktr j3 and j1. That is the Free-plan macOS limit exactly.
- **Limits (CONFIRMED, https://docs.github.com/en/actions/reference/limits, read 2026-10-17).** Free plan: 20 concurrent
  jobs in total and 5 concurrent macOS jobs, the macOS limit shared by standard and larger runners. A matrix is at most
  256 jobs. So one breakpoint-gate run (up to 22 jobs) alone saturates the 20, and one wktr (3) plus one webkit-sim (2)
  run saturates the 5 macOS.
- **Run-level queue is not where it shows.** `startedAt - createdAt` of the run is 4-5 s for 32 of 33 runs; the one
  outlier is webkit-sim at 178 s (11:37, while breakpoint-gate was running). The wait is per job, after the run starts,
  and `gh run view --json jobs` has no job-created time, so only the wktr example above gives a job queue time.
- **Fix.** Per workflow `paths:` on the push trigger, `cancel-in-progress` only on `ci/**`, `workflow_dispatch` kept.
  Applied to lean, chromium-counts, breakpoint-gate; exact blocks for webkit-sim and wktr in the handoff.

## Cost table (MEASURED from `gh run list --limit 100`, 8 pushes on 3 branches; paths as in the new triggers)

Base of a push = previous push of the same branch, or the merge base with main for the branch's first push (INFERRED
for the first pushes). The first push of ci/first-run (311b1de) is left out: its base is unknown. Runs still in
progress at the time are counted with the jobs that had finished.

| workflow | runs | runs that touched no input | job-min | job-min wasted |
|---|---|---|---|---|
| lean | 7 | 6 | 8.1 | 6.4 |
| chromium-counts | 7 | 5 | 49.6 | 34.1 |
| breakpoint-gate | 7 | 6 | 205.0 | 176.3 |
| webkit-sim | 7 | 4 | 151.7 | 31.5 |
| total | 28 | 21 | 414.4 | 248.3 |

webkit-sim job-minutes are mostly macOS (`xcode-27`; the plan and merge jobs are Linux); its two runs that never ended
by 13:49 are not counted, so its waste is a lower bound. Public repos pay nothing for the minutes; the cost is the
concurrency slots (above).

## Design

Inputs per workflow were read from the steps (`uses: ./.github/actions/...`, `working-directory`, scripts, env paths):

| workflow | paths (push) | why |
|---|---|---|
| lean | `lean/**`, `apps/site/src/breakpoints.gen.json`, setup-lean, `runner-info.sh`, own file | check.sh runs `breakgen --check` against the site table |
| chromium-counts | `packages/measure-chromium/**`, `lean/**`, `snapshot/**`, `snapshot.lock.json`, `verify-snapshot.mjs`, `runner-info.sh`, setup-lean, own file | fwcore is built from lean/; the snapshot is verified against the lock |
| breakpoint-gate | `packages/gate-breakpoints/**`, `apps/site/**`, `lean/**`, `snapshot/**`, `snapshot.lock.json`, `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, 4 gate scripts, 3 actions, own file | site build runs breakgen --check; gate reads `apps/site/src/parts` and the lock; pnpm install is frozen |

Consequences, by design: a `lean/**` change starts lean, chromium-counts and breakpoint-gate (all three build fwcore);
a docs, research, console or other-package change starts none of them.

- `concurrency: group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: ${{ startsWith(github.ref, 'refs/heads/ci/') }}`:
  a newer push on a ci branch cancels the older run, a run on main is never cancelled (it is a record).
- **main is filtered too (limit, CONFIRMED).** One `push:` key has one `paths` list; GitHub requires both `branches` and
  `paths` to match (https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax). A push to main
  that touches no input of a workflow does not run it; its result would equal the last run on the same inputs.
  A full run on any ref is `gh workflow run <name> --ref <ref>`.
- Pushes to a new branch are diffed "against the parent of the ancestor of the deepest commit pushed" (same page), so a
  new ci branch cut from main counts only its own commits (INFERRED reading; the first push below is consistent with it).
  More than 1000 commits or a diff timeout always runs the workflow.
- A merge of main into a ci branch changes everything main changed; expect a full run there.

## Verification on CI (branch ci/trigger-scope, MEASURED; webkit-sim was not edited, so it still ran each time)

| push | what changed | workflows started (run ids) |
|---|---|---|
| b5504de | the three workflow files | lean 39037616767, chromium-counts 39037616778, breakpoint-gate 39037616769 (own file matches), webkit-sim 39037616799 |
| 03f96d0 | `lean/README.md` | lean 39037820582, chromium-counts 39037820552, breakpoint-gate 39037820568, webkit-sim 39037820556. All three match `lean/**`: my first test choice was wrong, not the filter. |
| ebc878c | `packages/measure-chromium/README.md` | chromium-counts 39037882898, webkit-sim 39037883002. lean and breakpoint-gate did not start. |
| d3f5abd | same file again, about 70 s later | chromium-counts 39037958051 started; the older 39037882898 ended `cancelled` (concurrency); webkit-sim 39037958035 |

- `gh workflow run lean --ref ci/trigger-scope` started run 39038081046 (`workflow_dispatch`), so dispatch on a branch works.
- I cancelled most runs of the test pushes by hand to spare runners; their `cancelled` conclusions there are mine, except
  39037882898, which concurrency cancelled.
- Slow cancel: macOS webkit-sim run 39037820556 was still `in_progress` 4 minutes after `gh run cancel` and needed
  `--force`; a cancelled sim can hold a macOS slot for minutes.
- Side finding: webkit-sim run 39036078841 (ci/webkit-fix, since 13:19) is still running after 30 minutes and holds 2 of
  the 5 macOS slots; its owner should look at it.

Method and scripts: run list and job times from `gh run list/view --json`; changed files by `git diff --name-only`
between consecutive pushes; patterns matched as GitHub globs (`**` any, `*` not across `/`).
