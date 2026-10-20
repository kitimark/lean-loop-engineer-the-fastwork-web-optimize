# fw land: pre-lock protocol

`fw land <branch> --task <id>` (apps/runner/src/land.ts). Lean: `Fw.Console.LandSpeed` (`pre_eq_old_iff`, `preLand_commit_exact`,
`prelockAction_fallback`), `Fw.Console.Land` (`landTip`).

1. **Before the lock** (no lock, the main checkout is untouched and free for the lead):
   `main0 = HEAD`; `T = git -c attr.tree=main0 merge-tree --write-tree main0 tip`; `C = commit-tree` with parents `[main0, tip]` and the
   `Task:` trailer; C is checked out in a persistent land worktree `.claude/land-wt/<n>/` (gitignored, one slot per concurrent land,
   `.lake` and `node_modules` kept warm, everything else `git clean -fdx`-ed); the evidence edit is applied there and C re-made from the
   edited tree (the checked tree is the committed tree); conflict-marker grep; then `checksFor` (check-dag) run in the land worktree.
2. **Under the lock** (sub-second, span "lock held", 5 s ceiling): `prelockAction(HEAD, main0, verdict, attempt, retries)`:
   `ff` -> Lean `console.landCommit` (lock ours, HEAD = main0) -> `git merge --ff-only C`; `refuse` -> main untouched;
   `recheck` (main moved) -> release, redo against the new main, at most `retries` (3) times; `fallback` -> the old locked protocol
   (merge --no-commit in the main checkout, checks there, commit). A conflict also falls back (it then refuses as before).
3. **land-guard** only refuses commits during the ff instant (or during a fallback land's open merge).
4. `prelock: false` (option) = the old protocol only. The card fast-forward path (no `--task`) is unchanged.

## The remote tier waits on the land lane (task land-wait)

Step 1's checks split by `console.landTier`: the local tier runs in the land worktree as before; the remote tier (the heavy suites)
does not run on this Mac. `fw land` pushes `ci/land-<task>-<sha7>` (a `[ci:land]` marker commit on C; a new name per C, so never a
force push), waits with `fw ci wait` (no CPU: one sleeping child per slice) and asks `console.landRemote` (Lean
`Fw.Console.LandRemote`, golden `land-remote.jsonl`) for the verdict over the local result and the normalized lane runs.
- A lane run counts only for the sha and the `laneDigest` (tier + remote check ids) it printed: its job step is named
  `lane: sha=.. digest=..` (land.yml); a pass for another sha or suite list is ignored. Any provider's fail refuses.
- Fallback is explicit, never silent: provider unavailable -> try the next allowed provider, else the remote tier runs on this Mac
  and the log says `remote: running the remote tier on this Mac instead (<reason>)`. Cancelled or timed out: same.
- **A completed failed lane run always refuses (incident 2026-10-19, run 39338755874, task preview-e2e).** After the waiter returns, with any exit
  code, the adapter reads the run's own record (`gh run view`; the run id comes from the waiter output or `gh run list --branch
  <ci/land-..> --commit <marker>`). Lean `laneState` (`console.landLaneState`) makes the state `fail` when the run completed with
  conclusion `failure`, whatever the exit code; the waiter's exit decides only for runs without such a record. Theorems
  `verdict_completed_failure_refuses`, `verdict_no_local_after_failure`; golden per waiter exit 0..5 in `land-remote.jsonl`. A bound
  fail is never followed by `remote: running the remote tier on this Mac instead`.
- Every remote line (`remote: ...`, including `remote: verdict <kind> reason=<reason>` and the fallback line) goes to the land log
  file `.fw-console/land-logs/<task>-<sha7>.log` and to stderr as they happen, whether or not the land passes; they are not repeated in the result lines `fw land` prints at the end.
- `fw ci wait` exit 3 means a run still going only when its output says `timed out after`; a stopped poller or a refused gh call
  is `unavailable` (no retry on a refusal). After any exit but a plain timeout the adapter reads the land workflow's own run (`--workflow land`; a view whose `workflowName` is not the lane is dropped, so another workflow's run on the commit never decides): first the waiter's cached facts (gh-budget runs-status file, `meta/<id>.jobs.json`; no budget), then at most a list and a view, bounded by the slice deadline and the abort signal. Accepted limit: if the budget refuses those calls and no cached record exists, the waiter's outcome stands (fallback to the local tier), logged as `land run record not read (<reason>)`. A `running` poll that returns before its slice is slept out, so waiting costs no CPU.
- Before the push, `scripts/scrub.mjs --range origin/main <C>` scans the lines the push adds (home paths, Claude session/project paths and encoded home paths such as `-Users-<name>-`, the run-time account name, LAN IPs, emails, ...);
  a hit makes the provider `unavailable` with `personal-data scan refused ...` and the remote tier runs here. If `origin/main` is
  missing the scan fails the same way (closed). The waiter runs in its own process group; an abort stops the whole group.
- The lane step runs only when the suites step ran and has a 40-hex sha and a digest in its name; an empty name binds nothing
  and the failed run refuses (`remote-lane-failed`).
- A failing local tier ends the wait and refuses. Spans: `remote push`, `remote queue`, `remote lane`, `local tier`.
- `remote: false` (option) and an injected `checks` run everything here. The fallback protocol (locked) stays all-local.
- Providers: GitHub is complete; the CircleCI adapter is a stub (`unavailable`), a follow-up after circleci-pilot lands.
TS stand-ins: `normalizeGithub` (the state is Lean's `laneState`), `awaitRemote`, `runTiered` (glue around the Lean verdict; tests in `land-remote.test.ts`).

TS stand-in, marked for Lean replacement: `prelockAction` (no fwcore op yet); checked against the `landSpeed.prelock` golden.
First-in-first-out landing: `land-queue.md`.

## The lane runs as parallel legs (task land-lane-speed)

`land.yml` job `land` is a matrix over the legs Lean names (`Fw.Console.LandLegs`, `lean/land-legs.txt`: `suites-a suites-b chromium
playwright-webkit`). Every leg checks out, builds fwcore and selects the same checks (`fw checks --affected --tier remote --leg <name>`),
then does only its part, so the wall time of the lane is the slowest leg:
- `suites-a` runs `apps/runner`, `packages/gate-breakpoints`, `measure-chromium`, `engine-check`, `e2e-preview`; `suites-b` runs `apps/console-api`
  and `packages/gh-budget` (Lean `shardA`/`shardB`; `shards_perm`, `shards_disjoint`, `suites_cover`: no check dropped or run twice).
- An engine leg runs the preview browser suite on its engine iff the selection holds the e2e-preview check (`engineRuns`;
  `chromium_runs_of_selected`, `webkit_runs_of_selected`, `engines_idle_of_unselected`). The browser is installed only then
  (`LANE leg=<name> engine=<bool> checks=<n>`); without the check the leg ends after the selection.
- All legs print the same `LANE digest=` (the whole remote tier) and the same `lane: sha=.. digest=..` step; `bind` reads any job's step.
- Verdict over all legs: GitHub's run conclusion is failure when any leg failed (`fail-fast: false`, so every leg reports). For a run GitHub
  called `success`, the adapter hands the conclusions of every job but the guard to `console.landLegsVeto` (Lean `legsVeto`) and takes
  its answer: a record without per-job conclusions (no cached conclusions, a job without one) or with no leg says nothing and does not veto
  (`legsVeto_none`, `legsVeto_empty`); otherwise the run is vetoed iff `legsOk` refuses (`legsVeto_fail`, `legsVeto_all_pass`,
  `legsVeto_iff`), so a `success` run with a leg that did not pass is `fail`. `legsPass` in `land-remote.ts` only builds that input and replays
  the answer. Golden `land-legs.jsonl`; TS only replays it (`apps/runner/test/land-legs.test.ts`, which also holds the matrix in land.yml equal to `land-legs.txt`).
- WebKit leg cache: the gate-engine action restores the apt `.deb` files and the Playwright browser directory; a `ci/*` run reads only its own
  branch's and `main`'s caches, and the keys name the runner image version, so after an image bump `main`'s seed is stale and every land misses
  (MEASURED, run ids in the handoff `docs/team/handoffs/land-legs-followups.md`). Re-seed with
  `gh workflow run premise-tests.yml --ref main` (the `engine` job saves both caches on `main`; no cron by `Fw.Ci.Trigger.no_crons`).
- Cost: one runner per leg (free runners; four per land, the engine legs idle after setup when no browser suite is selected). Numbers and
  the phases that remain: `research/notes/2026/10-20-land-lane-speed.md`. Not changed: the local tier already starts with the push.

## `--dry` and verdict lines

Hand-back rule: before an agent hands a branch back it merges `main` into it and runs `pnpm fw land <branch> --task <id>
[--allow <glob>]... --dry`, and hands back only when the last line is `VERDICT dry <id>` (exit 0). Other kinds are fixed
first: `stale` = merge main again (or, when the REFUSED line starts with `fwcore-stale:`, run `sh scripts/fwcore-build.sh` in the main checkout; the branch is fine), `scope` = declare the write or pass `--allow`, `reads` = declare the read in the
premise, `conflict` = resolve. Lean `handback_pass_land_pass`: if the dry land passes and main has not moved, the real
land's scope, merge and reads stages pass.

`pnpm fw land <branch> --task <id> --dry` runs the real land's cheap stages on the same merge-tree commit: stale base (the branch must contain main), scope, merge and conflict markers, and the static reads test (`land-inputs.test.ts`) when the change selects the `reads-scan` check (its own cheap check, `vitest run test/land-inputs.test.ts`; selected by any change to a path any check declares as input, Lean `LandSpeed.scan_selected`). It takes no lock, writes no queue entry and never moves main; the checks run in a land worktree slot (a pid claim). Lean: `Fw.Console.LandDry` (`dry_pass_land_pass`, `dry_refusal_is_land_refusal`, `handback_pass_land_pass`).

Every `fw land` prints a last line `VERDICT <kind> <task>` and exits with a code per kind (Lean `Fw.Console.LandVerdict`):

| kind | exit | meaning |
|---|---|---|
| done, dry, queued, empty | 0 | landed, dry land passes, queued, the branch has no commit of its own (nothing to land) |
| busy 10, dirty 11 | 10, 11 | retryable: the lock or the main checkout is in the way |
| scope 12, reads 13, conflict 14, checks 15, stale 16, lint 17 | 12-17 | fix the branch (lint: a fast lint failed; stale: or, when the REFUSED line starts with `fwcore-stale:`, run `sh scripts/fwcore-build.sh` in the main checkout, the branch is fine) |
| unknown | 2 | anything else |

Scripts read the word after `VERDICT` or the exit code, never prose. A dry run (also one that throws or is refused before any stage) prints
exactly one `VERDICT` line, last: `fw.ts` prints the lines Lean `dryRun` returns for the seven stage outcomes that `land.ts` computes
(Lean `dryRun_one_verdict`; a thrown exception is the outcome `threw`, kind `unknown`). Not proved: that `land.ts` computes the outcomes
truthfully (tests only). A non-dry land prints its VERDICT line in `fw.ts` as before (tests, not a theorem).

### The dry land's fast lints

After the reads stage the dry land runs, in the merge-tree worktree (never the main checkout), the fast lints that refused real lands:
`node scripts/ci-paths.mjs --check` (0.1 s) and, when the change touches `lean/`, the axiom check the way `lean/scripts/check.sh` runs it
(`lean/scripts/axiom-check.sh`: an incremental `lake build`, then no `sorryAx` and only the standard axioms; no `fwtest`, no tests). A failure is `VERDICT lint` (exit 17). Which lints run is Lean `lintPlan`. Order (Lean `Outcome.first`): exception, stale, empty (no own commits), scope, conflict, reads,
lint, dry (`kind_spec`: the kind is the first failing stage in that order); `dry_pass_all`: dry means every one of them passed. A real
land prints `lint` too when a failed check reports only the `check.sh` stages `lake build` / `axiom check` (Lean `checkFailKind`,
`dry_kind_is_real_kind`); the real land has no `ci-paths` check, so a `ci-paths` failure has no real counterpart. Glue: `dryLintArgv` in `apps/runner/src/land.ts`; tests inject `dryLints`.
Cost: see the handoff note `docs/team/handoffs/land-dry-full.md`. TS stand-in `apps/runner/src/land-verdict.ts`, checked against `packages/contracts/golden/console/land-dry.jsonl`.


## Refusal reasons and the fwcore preflight (task land-queue-why)
- Every queue refusal carries a reason. An attempt that throws is kind `unknown`; the runner keeps the exception message, prints `REFUSED: <message>` to stderr before the `VERDICT` line, writes it as `reason` in the `res` line of `land-queue.jsonl`, and appends `queue: REFUSED: <message>` to the task's newest log under `.fw-console/land-logs` (`<task>-queue.log` when the task has none). An empty message becomes `no message`. A refusal that `fw land` already explained (its own `REFUSED:` line) is recorded but not printed twice. Lean: `Fw.Console.LandQueue.reasonOf_nonempty`, `reasonOf_keeps`; golden ops `landQueue.reason` and `landQueue.refusalReason` (`refusal_has_reason`: every refusal kind gets a non-empty reason; the queue calls the TS mirror `refusalReason`). The task's land log is matched by exact name (`<task>-<sha7>.log`).
- Preflight (real lands only, not `--dry`, not with `FW_LAND_CHECKS`): before any check, `fwcorePreflight` compares the commit in the main checkout's `lean/.lake/build/bin/fwcore.commit` (counted only when the binary's sha256 is the recorded one) with `main`. No record, or a record of another commit with a change under `lean/` or to `scripts/fwcore-build.sh` since, refuses at once with kind `stale` and the reason `fwcore-stale: run sh scripts/fwcore-build.sh`. Lean: `fwcoreStale` with one theorem per branch (`fwcoreStale_noRecord`, `fwcoreStale_moved`, `fwcoreFresh_same`, `fwcoreFresh_unmoved`); golden op `landQueue.fwcoreStale`. A tree without `scripts/fwcore-build.sh` is skipped. Cause of the 2026-10-20 incident: a stale binary failed mid-run with `unknown op console.landDigest`.
