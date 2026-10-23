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
- **A running or green lane is never refused as failed (task land-wait-final; incidents run 39576215019 on 2026-10-20 and run 39612772041 on
  2026-10-21).** Cause (INFERRED: neither waiter output was recovered; the timestamps fit, land log ended 14:09:23Z, run concluded success 14:09:07Z): the
  waiter child exited 1 without a verdict (a crash), and `waitState 1` was `fail`. Lean `laneState` now reads the run's own record first: completed failure or an unknown
  conclusion -> `fail`; status not `completed` -> `running` whatever the exit (in progress, wait error); completed success -> the per-job
  conclusions decide (`legsOk`), also after exit 1; no record -> the waiter, where exit 1 is `fail` only with a `-> fail` line in its output
  (else `running`: exit 1 without the line, exit 2 and exit 3 are wait errors, polled again until the deadline; theorems `laneState_wait_error_running`, `verdict_wait_error_waits`). A non-pass waiter on a cached record without job conclusions reads the full `gh run view` (the production cache hit never decides alone). A run that outlives `deadlineS` is `timeout`, verdict `remote-timeout-run-locally`, never
  `remote-lane-failed` (theorem `verdict_timeout_not_fail`). Theorems `laneState_completed_failure`, `_completed_unknown`, `_in_progress`,
  `_all_success`, `_one_failure`, `_wait_error`; goldens in `land-remote.jsonl`. A refusal line names the run id, the failed legs and the check ids of
  each: `remote tier: the land lane failed for <sha7> (github:fail) [github: run <id>, failed legs: suites-a failure [checks ...]]`.
- Every remote line (`remote: ...`, including `remote: verdict <kind> reason=<reason>` and the fallback line) goes to the land log
  file `.fw-console/land-logs/<task>-<sha7>.log` and to stderr as they happen, whether or not the land passes; they are not repeated in the result lines `fw land` prints at the end.
- `fw ci wait` exit 3 means a run still going only when its output says `timed out after`; a stopped poller or a refused gh call
  is a wait error, `running` (polled again, no retry storm: the slice sleep applies). After any exit but a plain timeout the adapter reads the land workflow's own run (`--workflow land`; a view whose `workflowName` is not the lane is dropped, so another workflow's run on the commit never decides): first the waiter's cached facts (gh-budget runs-status file, `meta/<id>.jobs.json`; no budget), then at most a list and a view, bounded by the slice deadline and the abort signal. Accepted limit: if the budget refuses those calls and no cached record exists, a waiter exit 1 without `-> fail`, exit 2 or exit 3 stays `running` and is polled once per slice until `deadlineS` marks it `timeout` (verdict `remote-timeout-run-locally`); other exits are `unavailable`; logged as `land run record not read (<reason>)`. A `running` poll that returns before its slice is slept out, so waiting costs no CPU.
- Before the push, `scripts/scrub.mjs --range origin/main <C>` scans the lines the push adds (home paths, Claude session/project paths and encoded home paths such as `-Users-<name>-`, the run-time account name, LAN IPs, emails, ...);
  a hit makes the provider `unavailable` with `personal-data scan refused ...` and the remote tier runs here. If `origin/main` is
  missing the scan fails the same way (closed). The waiter runs in its own process group; an abort stops the whole group.
- The lane step runs only when the suites step ran and has a 40-hex sha and a digest in its name; an empty name binds nothing
  and the failed run refuses (`remote-lane-failed`).
- A failing local tier ends the wait and refuses. Spans: `remote push`, `remote queue`, `remote lane`, `local tier`.
- `remote: false` (option) and an injected `checks` run everything here. The fallback protocol (locked) stays all-local.
- Providers: GitHub first; CircleCI takes the legs GitHub has no free job slot for (section "The land overflows to CircleCI").
TS stand-ins: `normalizeGithub` (the state is Lean's `laneState`), `awaitRemote`, `runTiered` (glue around the Lean verdict; tests in `land-remote.test.ts`).

TS stand-in, marked for Lean replacement: `prelockAction` (no fwcore op yet); checked against the `landSpeed.prelock` golden.
First-in-first-out landing: `land-queue.md`.

## The lane runs as parallel legs (task land-lane-speed)

`land.yml` job `land` is a matrix over the legs Lean names (`Fw.Console.LandLegs`, `lean/land-legs.txt`: `check-sh suites-a suites-b chromium
playwright-webkit`). Every leg checks out, builds fwcore and selects the same checks (`fw checks --affected --tier remote --leg <name>`),
then does only its part, so the wall time of the lane is the slowest leg:
- `check-sh` runs `sh lean/scripts/check.sh` (task land-check-remote): the Lean gate script is in the remote tier (`remoteIds`, `check_sh_remote`), so
  it no longer runs on this Mac; `install` and the reads scan are the only gates left in the local tier (`gates_local`). The leg gets the toolchain
  and the Lake cache from `setup-lean` like `lean.yml`. The script prints no test summary, so its exit code is its verdict (Lean
  `LandTier.summaryless`, `effectiveSkipped_summaryless`; op `console.landLane` with `check`; `laneVerdict` is unchanged). The local tier starts
  with `sh scripts/fwcore-build.sh` when a local check is an fwcore user and no phase-1 build succeeded (Lean `localPlan`,
  `core_user_has_build`). The local fallback (`remote: false`, CI unavailable) runs it here again.
- `suites-a` runs `apps/runner`, `packages/gate-breakpoints`, `measure-chromium`, `engine-check`, `e2e-preview`; `suites-b` runs `apps/console-api`
  and `packages/gh-budget` (Lean `shardA`/`shardB`; `shardC` = the script; `shards_perm`, `shards_nodup`, `shards_disjoint`, `shardC_disjoint`, `legs_cover`, `legs_nodup`: no check dropped or run twice).
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
  branch's and `main`'s caches. The keys are the Playwright version, the Ubuntu release, the architecture and the engine; the runner image
  version is not in them, so the two image versions the fleet runs share one key. `main` seeds them through the premise-tests `engine` job on each
  `main` push (no cron by `Fw.Ci.Trigger.no_crons`). Re-seed by hand (`gh workflow run premise-tests.yml --ref main`) only after a Playwright bump.
  Measurements: `docs/team/handoffs/land-legs-followups.md`.
- Cost: one runner per leg (free runners; four per land, the engine legs idle after setup when no browser suite is selected). Numbers and
  the phases that remain: `research/notes/2026/10-20-land-lane-speed.md`. Not changed: the local tier already starts with the push.

## The land overflows to CircleCI (task land-lane-circleci)

GitHub Actions runs every leg of the land lane unless it has no free job slot for them; the legs it cannot take run on CircleCI.
- **Rule (Lean `Fw.Ci.Overflow`, fwcore ops `ci.overflow`, `ci.overflowCombine`, `ci.overflowSettle`, golden `packages/contracts/golden/ci/overflow.jsonl`).** Slots
  are 20 (`ghCap`) minus the widths of the workflow runs now queued or running (`widths`: one row per `.github/workflows` name, an unlisted
  name counts 4; a finished job still counts, the safe side). A row is the most jobs one run of that workflow holds at once, derived from the
  workflow file (the heaviest set of jobs no two of which are ancestor and descendant, each job at most its matrix size, its `max-parallel` and
  5 on macOS; a `fromJSON` matrix at the largest its planner allows) by `apps/runner/test/land-overflow-widths.test.ts`, which fails when a
  matrix, a job or a workflow grows past its row, and when a row is not the derived value. The first legs that fit stay on GitHub, in matrix order; the rest go to CircleCI
  only if CircleCI is usable (status fresh and healthy, a checkout key, and the legs' credits, the credits spent, the storage overage past 2 GB-month at 420 credits per GB-month, counted with the overflow's own Lake cache save, and the reserve fit the pool: `budgetFits`). Storage alone never refuses while the budget fits (`storage_alone_never_refuses`, `reason_not_storage`; `budgetFits_iff` gives the exact room), and the wait on CircleCI legs stops only on the 1 h cap or a 10 min queue (Lean `landStops`, which holds no storage reason: `storage_not_mem_landStops`). Theorems: `github_first`
  (no overflow while GitHub has room), `overflow_only_when_full`, `never_both` (a leg is on one provider), `verdict_same` (one bound pass is
  judged alike on either provider). A degraded Actions status moves every leg (`github-degraded`). `reason` says which branch decided.
- **Facts (`apps/runner/src/land-overflow.ts`).** The slot count is one `gh run list --limit 100` (never `gh api`), cached in the gh-budget
  directory for 120 s, no retry on a refusal (unreadable means GitHub first). It is up to 120 s old, reads **this repository only** and sees only
  **the newest 100 runs**, so a run of another repository of the account and an older run still going are not counted: the slot count can
  under-count (named limits; the account-wide use of the 20 job slots is not visible to it). The CircleCI facts are read only when the first answer moves a leg: the console's
  `/api/ci-status`, the key check and the credit and storage ledger of `scripts/circleci.mjs` (storage is Lean `storageNow`: saves of the last 30 days, caches and workspaces at 15 days, artifacts at 30). The test flag `FW_LAND_FORCE_FULL=1` marks GitHub full.
- **One marker, two lanes.** Both providers use the same `ci/land-<task>-<sha7>` branch and marker commit (pushed once, `makePusher`). A
  land with legs on both says which GitHub gets in the marker message (`[legs:a,b]`); `land.yml`'s guard turns that into a matrix `exclude`.
  A land with no leg on GitHub leaves out `[ci:land]`, so GitHub starts nothing. The GitHub adapter passes a partial land only if the run has
  a job `land (<leg>)` for each leg it was given (`legsCovered`).
- **CircleCI.** The land job restores a Lake cache (key `lake-v1-arm64-<toolchain+manifest hash>-<Lean source hash>`, prefix fallback) and saves it
  only when the key changed (`job.sh lake-gate` halts before `save_cache` otherwise); a warm leg takes 48-215 s against 420-576 s cold (MEASURED,
  `research/notes/2026/10-2x-circleci-lean-cache.md`; one save is about 292 MiB, 307 thousandths of a GB-month at the 30-day ledger bound). `.circleci/config.yml` has one workflow per leg (parameter `legs`, `lane == land`, branch `ci/*`); `.circleci/job.sh` runs the
  same `fw checks --affected --tier remote --leg` entry and writes `lane.json` (`{leg, sha, digest, engine, rc}`). The adapter triggers
  through `scripts/circleci.mjs` (token from the Keychain, never printed), waits at 120 s or slower, reads `vcs.revision` and the
  artifacts, and binds a pass only to a sha and digest every leg printed (`normalizeCircle`). Groups are waited for on their own and
  combined by fwcore (`awaitGroups`: refuse, else local, else a wait or try, else accept (Lean `pickKind`)).
- **A CircleCI start that fails** (no adapter, the key check, the branch push or the trigger throws, so no pipeline exists) re-dispatches its
  legs on GitHub, on the branch `ci/land-<task>-<sha7>-again`, never on the local tier (Lean `Overflow.settle`, op `ci.overflowSettle`,
  theorem `failed_start_covered_once`: every leg is run exactly once, none twice, none dropped; test: `awaitGroups` in
  `land-overflow.test.ts`). The failed group's verdict is dropped, so the local tier runs the remote checks only if GitHub cannot be started
  either. Before this fix a trigger failure after the plan ran the whole remote tier locally. A pipeline that started and then failed is a
  refusal, not a second run.
- **Limits.** Linux legs only; no hedge; macOS lanes are follow-ups (tasks ci-route, pool-fallback). Credits count only pipelines this
  Mac fetched (rolling 30 days). An aborted CircleCI pipeline is not cancelled. If one provider's group says local, the whole remote tier
  runs here. `ghPrev` (the last Actions flag) is not tracked yet.
- **Proof by hand.** `FW_LAND_FORCE_FULL=1 node apps/runner/src/land-probe.ts [--rev <sha>]` lands HEAD (or `--rev`, e.g. a commit made with `git commit-tree HEAD^{tree} -p main -p HEAD`, so the legs select what a land selects and run the browser suite) through this path on a probe branch (no merge).
- TS stand-ins: the status-to-active filter in `readSlots`, `markerMessage`, `legsCovered`, the sha and digest uniformity in `normalizeCircle`
  (tests in `land-overflow.test.ts`; the rule itself is replayed from the Lean golden).

## `--dry` and verdict lines

Hand-back rule: before an agent hands a branch back it merges `main` into it and runs `pnpm fw land <branch> --task <id>
[--allow <glob>]... --dry`, and hands back only when the last line is `VERDICT dry <id>` (exit 0). Other kinds are fixed
first: `stale` = only a REFUSED line starting with `fwcore-stale:` (a branch behind main no longer gives it): run `sh scripts/fwcore-build.sh` in the main checkout; the branch is fine, `scope` = declare the write or pass `--allow`, `reads` = declare the read in the
premise, `conflict` = resolve. Lean `handback_pass_land_pass`: if the dry land passes and main has not moved, the real
land's scope, merge and reads stages pass.

`pnpm fw land <branch> --task <id> --dry` runs the real land's cheap stages on the same merge-tree commit: a branch behind main is merged with `git merge-tree --write-tree` (no checkout; clean = checked on the merged diff, conflict = `VERDICT conflict`; Lean `LandDry.never_stale`), scope, merge and conflict markers, and the static reads test (`land-inputs.test.ts`) when the change selects the `reads-scan` check (its own cheap check, `vitest run test/land-inputs.test.ts`; selected by any change to a path any check declares as input, Lean `LandSpeed.scan_selected`). It takes no lock, writes no queue entry and never moves main; the checks run in a land worktree slot (a pid claim). Lean: `Fw.Console.LandDry` (`dry_pass_land_pass`, `dry_refusal_is_land_refusal`, `handback_pass_land_pass`).

Every `fw land` prints a last line `VERDICT <kind> <task>` and exits with a code per kind (Lean `Fw.Console.LandVerdict`):

| kind | exit | meaning |
|---|---|---|
| done, dry, queued, empty | 0 | landed, dry land passes, queued, the branch has no commit of its own (nothing to land) |
| busy 10, dirty 11 | 10, 11 | retryable: the lock or the main checkout is in the way |
| scope 12, reads 13, conflict 14, checks 15, stale 16, lint 17, rebuild 18, install 19 | 12-19 | fix the branch (lint: a fast lint failed; stale: or, when the REFUSED line starts with `fwcore-stale:`, run `sh scripts/fwcore-build.sh` in the main checkout, the branch is fine; rebuild: the queue's fwcore rebuild after the previous land failed, run `sh scripts/fwcore-build.sh` in the main checkout and re-queue, the branch is fine; install: the land worktree's `pnpm install` failed offline and online, check the network and `pnpm-lock.yaml`, then re-run) |
| unknown | 2 | anything else |

A new land worktree runs `pnpm install --offline --frozen-lockfile` first; only when that fails it runs the online `pnpm install --frozen-lockfile` (one try, no retry loop). If both fail the land is refused with `VERDICT install` (exit 19, `REFUSED: install failed in <dir>: ...`) instead of continuing into checks on an incomplete `node_modules`. Lean `Fw.Console.LandVerdict.installKind` with `installKind_offline_ok`, `installKind_online_ok`, `installKind_both_fail`, `installKind_refusal`; golden op `landVerdict.install`; TS `landInstall` in `apps/runner/src/land.ts` follows `installKind` from `land-verdict.ts`. The dry land's Lean `dryRun` has an `install` stage between `conflict` and `reads` (`DStage.install`, `Outcome.installs`); a failed install ends the log after `dry: conflict ok` with `VERDICT install`.

A reused land worktree (`.claude/land-wt/N`) keeps its `node_modules`, so it carries a lockfile stamp: `land.ts` clears the stamp before every install and, after a successful install, writes the sha256 of `pnpm-lock.yaml` to `node_modules/.fw-lock-stamp` (inside the worktree, outside git). Before the checks, `landInstallStamped` compares it with the lockfile at the checked-out commit and installs when the worktree is new, the stamp is missing, or the hashes differ (incident `inc-land-wt-lock-drift`: the land's own diff no longer has to touch a lockfile). Lean `installNeeded` / `installStep` with `installStep_checks_see_current_stamp` (no refusal means the stamp equals the checked-out lockfile hash), `installStep_refusal` (refusal is `install` and leaves no stamp, since a failed install may have rewritten `node_modules`), `installStep_refused_next_land_installs` (the next land installs), `installNeeded_reused_behind`, `installNeeded_reused_unstamped`, `installNeeded_new`; golden op `landVerdict.installStamp`; TS stand-in `installStep` in `apps/runner/src/land-verdict.ts`. Each install try has a 10-minute timeout and the REFUSED line ends with the stderr tail of the offline and the online try. Accepted limits: the stamp is lost with `node_modules`; the lockfile hash is the only trigger (a hand edit of `node_modules` is not seen); the timeout is fixed.

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

Generated-file freshness (task `dry-gen-fresh`, incident `inc-dry-gen-stale`): when the change touches an input of the part footprint
generator (Lean `footprintInput`: `apps/site/src/parts/**`, `apps/site/src/App.tsx`, `apps/site/scripts/part-footprint.mjs`,
`lean/Fw/Parts/FootprintData.lean`, `packages/contracts/golden/parts/footprint.gen.json`) and the tree has the script, the lint stage
also runs `node apps/site/scripts/part-footprint.mjs --check` (about 1 s), between `ci-paths` and the axiom check. Proved:
`gen_selected` (a generator input selects the check), `lintPlan_old` and `lintPlan_noScript` (no generator input, or no script: the
plan before this task), `gen_stale_refuses` (a failing footprint check is never `dry`), and `dry_pass_land_pass_planned` /
`dry_refusal_is_land_refusal_planned` (both guarantees with the planned lint stage). The real land reports the same failure as
`checks` (`pnpm --filter ./apps/site test`, `footprint.test.ts`). Fix: `node apps/site/scripts/part-footprint.mjs --write`, then
regenerate the Lean outputs that read `FootprintData` (`lake env lean --run scripts/ContractsGolden.lean --check ...` in `check.sh`
also compares `footprint-diff.gen.json` and `Fw/Parts/FootprintRows.lean`). Limits: only generators with a `--check` mode; `ci-paths`
was already a lint.
Cost: see the handoff note `docs/team/handoffs/land-dry-full.md`. TS stand-in `apps/runner/src/land-verdict.ts`, checked against `packages/contracts/golden/console/land-dry.jsonl`.


## Refusal reasons and the fwcore preflight (task land-queue-why)
- Every queue refusal carries a reason. An attempt that throws is kind `unknown`; the runner keeps the exception message, prints `REFUSED: <message>` to stderr before the `VERDICT` line, writes it as `reason` in the `res` line of `land-queue.jsonl`, and appends `queue: REFUSED: <message>` to the task's newest log under `.fw-console/land-logs` (`<task>-queue.log` when the task has none). An empty message becomes `no message`. A refusal that `fw land` already explained (its own `REFUSED:` line) is recorded but not printed twice. Lean: `Fw.Console.LandQueue.reasonOf_nonempty`, `reasonOf_keeps`; golden ops `landQueue.reason` and `landQueue.refusalReason` (`refusal_has_reason`: every refusal kind gets a non-empty reason; the queue calls the TS mirror `refusalReason`). The task's land log is matched by exact name (`<task>-<sha7>.log`).
- Preflight (real lands only, not `--dry`, not with `FW_LAND_CHECKS`): before any check, `fwcorePreflight` compares the commit (or the commit of `main` with the recorded tree, form `tree <id> <sha256>`) in the main checkout's `lean/.lake/build/bin/fwcore.commit` (counted only when the binary's sha256 is the recorded one) with `main`. No record, or a record of another commit with a change under `lean/` or to `scripts/fwcore-build.sh` since, refuses at once with kind `stale` and the reason `fwcore-stale: run sh scripts/fwcore-build.sh`. Lean: `fwcoreStale` with one theorem per branch (`fwcoreStale_noRecord`, `fwcoreStale_moved`, `fwcoreFresh_same`, `fwcoreFresh_unmoved`); golden op `landQueue.fwcoreStale`. A tree without `scripts/fwcore-build.sh` is skipped. Cause of the 2026-10-20 incident: a stale binary failed mid-run with `unknown op console.landDigest`.

Finding (task land-fwcore-once, closed): a prep job that builds fwcore once for the four legs cut runner time 43% but made a lean land 76 s slower (477 s to 553 s, runs 39369049545 and 39370530353), because the legs' builds already ran in parallel; not shipped. Why: `Fw.Ops.WallTime.wallPrep_ge`; note `research/notes/2026/10-20-land-fwcore-once.md`.

## The queue rebuilds fwcore after a land that changed it (task land-queue-fwcore-rebuild)
- Incident 2026-10-20: after `land-fwcore-once` landed a `lean/` change, the three entries queued behind it were each refused `fwcore-stale`; a manual `sh scripts/fwcore-build.sh` between them let all land.
- Now `fw land --queue`, after an entry ends `done`, takes the paths merged by that land (diff of main before and after). If one is under `lean/` or is `scripts/fwcore-build.sh`, the runner runs `sh scripts/fwcore-build.sh` in the main checkout (span `fw land` / `fwcore rebuild (queue)`) before the next dequeue. Its duration adds to the queue wall time.
- Rebuild fails: the next entry is recorded with kind `rebuild` (exit 18, reason `fwcore-rebuild-failed: ...`), never `stale`; the queue stops and later entries stay pending.
- Lean: `Fw.Console.LandQueue.afterLand` with one theorem per branch (`afterLand_noRebuild`, `afterLand_noLeanChange`, `afterLand_notDone`, `afterLand_rebuilt`, `afterLand_rebuilt_fresh` (over `RebuildOut`/`rebuildOk`: exit 0 and the record names main; the runner checks the weaker conclusion, exit 0 and a non-stale preflight), `afterLand_stop`, `stopKind_rebuild`); golden op `landQueue.afterLand`; TS `afterLand` in `apps/runner/src/land-verdict.ts` is checked against it; the glue is the `head`/`diff`/`rebuild` options of `runQueue`.
- Rebuild glue: ok = exit 0 and `fwcorePreflight(main)` finds no refusal (a build that exits 0 without recording is kind `rebuild`); `git diff --no-renames`; a diff error counts as a core change; a failed rebuild with nothing pending still prints the REFUSED line.

## PUSH-DUE: push main when the land legs would rebuild fwcore (task land-seed-due)
- Land legs restore the Lake cache that `lean.yml` saved on the last main push (`land.yml` never saves). When main drifts
  from origin/main, every leg rebuilds fwcore: 155-173 s per leg at 64 unpushed first-parent commits, 0-1 s with the
  exact key (MEASURED, runs 39692711054, 39695811244, 39696729476 against 39369095720).
- After a land that moved main, `fw land` computes the lag: the paths of `git diff --name-only --no-renames origin/main
  main` that the cache key in `.github/actions/setup-lean/action.yml` hashes (`lean/lean-toolchain`,
  `lean/lake-manifest.json`, `lean/lakefile.toml`, `lean/*.lean`, `lean/Fw/**`, `lean/FwTest/**`). When the lag is
  over 5, the last result lines are a prose line and `PUSH-DUE <n>`. Without an `origin/main` ref no line is printed.
  The line never changes the verdict or the exit code. Under `--queue` the result lines go to stderr; a direct land
  prints them to stdout before the `VERDICT` line.
- On `PUSH-DUE` the lead scans `origin/main..main` for personal data, then runs `git push origin main`. Agents never
  push main.
- Lean: `Fw.Console.LandSpeed.seedDue` (`seedDue_iff`, `seedDue_false_iff`, `seedDue_mono`, `seedDue_zero`,
  `seedDue_five`, `seedDue_six`) and `seedLag` (`seedLag_eq_zero_iff`, `seedLag_cons_key`, `seedLag_cons_other`,
  `seedLag_append`, `seedLag_le`); golden ops `landSpeed.seedDue` (lags 0, 5, 6) and `landSpeed.seedLag`, checked by
  the `land-speed golden check` stage of `lean/scripts/check.sh`. The TS mirror (`seedLag`, `seedDue`, `SEED_READS` in
  `apps/runner/src/land.ts`) replays the golden in `apps/runner/test/land-seed-due.test.ts`, which also asserts that
  `SEED_READS` equals the key's `hashFiles` globs.

## The render guard refuses media outside snapshot/ in the branch history (task land-render-guard)
- Incident 2026-10-21: a branch committed Fastwork page renders (PNG, one with a person's photo) under `results/`, then `git rm`-ed them. `fw land` lands by merge commit, so the blobs would have reached main's history and the public push.
- Now every `fw land` (real and `--dry`), after the stale and empty checks and before the scope check and any check, pins the branch tip as `sha` and reads every commit of `main..sha` with `git log -z --no-renames --name-status --diff-merges=first-parent --format='commit %H'` and asks fwcore `console.landRenderGuard`. A path is refused when its commit stores a blob there (every status but `D`; an unknown letter counts), its extension is in the one media table (image, font, video, audio) and it is neither under `snapshot/` nor on `Fw.Land.RenderGuard.allowlist`. The refusal is kind `scope` (exit 12), one `REFUSED: render guard:` line listing `<path> (<media>) in <commit>` per hit. A failing `git log` or an fwcore without the op refuses too (kind `unknown`).
- Only the checked tip is merged: the pre-lock commit, the locked fallback (`git merge --no-ff --no-commit <sha>`) and the card fast-forward (`git merge --ff-only <sha>`) all take `sha`, never the branch name, so a commit that lands on the branch while the checks run stays out of main.
- History-wide: a later removal does not clear the refusal. Fix: move the other changes to a new branch from main without those commits, or add the path with its reason to the allowlist (a Lean change, reviewed).
- Lean `Fw.Land.RenderGuard`: `refusal_survives_later`, `removal_keeps_refusal`, `removal_keeps_refusal_prefix` (the newest-first order `git log` emits: the removal before the add), `allowed_never_refuses`, `snapshot_never_refuses`, `media_refuses`, `nonmedia_hit_none`, `refuses_append`. Golden `packages/contracts/golden/land/render-guard.jsonl`; tests `apps/runner/test/land-render-guard.test.ts` (temp repo: add then remove, snapshot pass, rename out of snapshot/, a merge that adds a render, a render committed on the branch during a check in the pre-lock fallback and the card fast-forward, which main never gets).
- Accepted limits: media type by extension only (`x.png.gz` passes; trailing white space after the extension is trimmed, so `hero.png ` is refused; two extension-only gaps pass the guard: a trailing dot, `hero.png.`, and a non-ASCII trailing space, `hero.png` + U+00A0, which the trim does not remove); the behind check, the scope diff, the render guard and every merge read the pinned `sha`, never the branch name (task land-sha-pin); the allowlist was seeded from main's tracked media outside `snapshot/` on 2026-10-21, which is none; main's existing history is not rewritten.

## The same guard runs before any push but main (task ci-push-render-guard)
- Incident: branch `ci/image-audit` published 102 derived Fastwork image copies to the public origin before any land. `fw land` never saw them.
- Hook point: the git `pre-push` hook `scripts/hooks/pre-push`, picked over a `pnpm fw ci push` command because agents already run plain `git push origin ci/<name>` and a command is opt-in per push, a hook runs on every plain `git push` unless `--no-verify` is given. `scripts/wt-prep.sh:29` already sets `core.hooksPath scripts/hooks`, so no package.json change.
- It reads the hook's stdin and acts on every pushed ref except `refs/heads/main` (other branches and tags alike; deletions and `main` pass). For each it runs `apps/runner/src/ci-push.ts`, which calls land.ts `renderGuard` (fwcore `console.landRenderGuard`, unchanged) over `origin/main..<pushed sha>` and prints `REFUSED: ci push render guard: ... <path> (<media>) in <commit>`, exit 1. No network: the base is the local `origin/main`; a missing base or fwcore refuses with the reason.
- History-wide like the land: a later removal does not clear it. Fix: a new branch from main without those commits.
- Test: `apps/runner/test/ci-push-render-guard.test.ts` (temp repo with a bare origin: add then push refused, removal still refused, clean and `snapshot/` branches push, a main push passes; a tag and a non-ci branch carrying a render are refused).
- Limits: extension-only (as the land guard); `git push --no-verify` bypasses the hook. `core.hooksPath` is in the shared config (wt-prep.sh:29), so it applies to every worktree, but the relative path resolves in each worktree's own checkout: a worktree whose branch predates this land has no `scripts/hooks/pre-push` and is unprotected until it merges main (the lead tells open worktrees).

## Phase 1: when the local fwcore build runs (task land-phase1-slow)
Phase 1 of `fw land` builds fwcore in the merge-tree worktree (span `fwcore build (phase 1)`) to learn the new binary's digest, which selects the
fwcore users. Lean `LandTier.phase1Build` skips it when every changed build read is build-free (`buildFree`: `lean/scripts/**`, `lean/golden/**`,
`lean/README.md`, `lean/land-filter.txt`, `lean/land-legs.txt`; no default Lake target reads them, checked by `apps/runner/test/land-phase1.test.ts`).
Theorems: `phase1Build_of_input` (a changed build input always builds), `skip_binMoved`, `skip_selection`, `skip_binary_equal` (premise
`land.binaryOfInputs`), `skip_keeps_local_build` (a local fwcore user still builds in the local plan), `built_selection`. Golden: `land-phase1.jsonl`.
The post-land `scripts/fwcore-build.sh` is unchanged. A change to a Lean module or the lakefile still builds: the closure of `Fw` covers every module.

## Local tests with a declared read set (task land-tier-compose-test)

A test inside a land-lane-only suite was invisible to the local tier and the dry land. Incident
`inc-local-tier-misses-compose`: lands of hero-exit-threaded-port (run 39674287486), toolbar-throttle-probe (39685526491) and
platform-shrink-mq (39688115785) failed at CI `suites-b` on `apps/console-api/test/compose.test.ts` because each branch registered a
flag variant in a `part.json` with no row in `research/findings/ledger.json` (class `unrated`, `Compose.classBy`).

- Lean `Fw.Console.LandTier.localTests`: single test files with a declared read set (`composeReads`: every
  `apps/site/src/parts/*/part.json`, the registry, `research/findings/ledger.json`, console-api source, the compose test and golden, the
  `fwcore` binary). `selectLocal` is `LandSpeed.selectChecks` over them; `selects_reader` proves that a changed path in a read set selects
  the test, `selects_only_reader` that nothing else does. Golden `packages/contracts/golden/console/land-tier-local.jsonl`.
- `apps/runner/src/land.ts`: `LOCAL_TESTS` (id `console-api:compose`, tier `onMac`, a `fwcore` user) is a candidate check, so the real
  land's local tier runs it, and the dry land runs the selected ones after the fast lints (a failure is `VERDICT lint`, the output names
  `test/compose.test.ts`). Test: `apps/runner/test/land-tier.test.ts`.
- Limits: a test with undeclared reads stays on the CI tier only; read sets are written by hand.
  TS stand-ins: the dry land's local-test step (Lean `lintPlan` does not list it; the real land reports the same failure as `checks`).

The CLI prints a dry land through `dryLandReport` (`land.ts`, Lean `dryRun` plus `exitCode`): a failed dry install shows the stage lines up to `dry: conflict ok` and then `VERDICT install` (no special branch), and the real land's exit is `landExit(res)`. A reused land worktree is cleaned once (after checkout, before prep); a new one once after prep.

## Workflow lint

Incident `inc-workflow-dup-key`: a merge kept the key `SEARCH` twice in one `env` block of
`.github/workflows/trajectory-probe.yml`, and GitHub refused the file because no land check read workflow files.

- Check `workflow-lint` (`sh scripts/check-workflows.sh`) runs `actionlint`. Selected when a changed path is `.github/workflows/*.yml`,
  `.github/workflows/*.yaml` or `scripts/check-workflows.sh` (Lean `Fw.Ci.WorkflowLint.select`, theorems `yml_selects`, `yaml_selects`,
  `script_selects`; golden `packages/contracts/golden/ci/workflow-lint.jsonl`, checked by `apps/runner/test/land-workflow.test.ts`).
  The dry land runs it too (`LOCAL_GATES` in `land.ts`).
- Verdict (Lean `verdict`, TS stand-in `workflowVerdict` in `apps/runner/src/land-checks-workflow.ts`): the kinds `syntax-check` and
  `expression` fail (exit 1; the duplicated env key is `syntax-check`, theorem `dup_key_fails`); every other kind, `shellcheck` included,
  is a warning printed without failing (`warnings_never_fail`). A missing `actionlint` refuses with
  `REFUSED workflow-lint: actionlint is not installed (brew install actionlint)` and exit 3, never a pass (`missing_refuses`).
- Accepted finding: `webkit-sim.yml` lists `''` as a `choice` option of the fault input, GitHub accepts it and actionlint says "string
  should not be empty". Changing the option would change the dispatch contract, so the finding is accepted for that file and message only
  (`accepted`, `accepted_is_file_scoped`).
- Tier: local (not on the remote allowlist `remoteIds`). The GitHub-hosted runners are not known to carry `actionlint`, so the check
  runs where `fw land` runs. The remote tier needs a runner install step first.
