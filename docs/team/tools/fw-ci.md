# fw ci

`fw ci <run id> | --branch ci/<x> [--workflow chromium-counts] [--store <dir>]` pulls a finished CI run into the artifact store.
A run id or `--branch` is required; without one it exits 64 with the usage (a `main` push runs no measurement, so there
is no default branch). With `--branch` and no run id: the latest run of the workflow on that branch. The store is `$FW_CONSOLE_DIR/store` (default `.fw-console/store`) unless `--store`.

- Every gh call (list, view, download; also `fw run` and `fw watch`) goes through `ghCharged` (`@fw/gh-budget`): fwcore's `ci.budget.*` decides
  whether gh runs, and a wait or stop means gh is not started. `fw ci` and `fw run` sleep through a wait; a stop throws (exit 1).
- Downloads only `chromium-counts-*` and `chromium-classes` (not the image or fwcore artifacts) with `gh run download`.
- One store key per target in the run (a `both` run files two keys). fwcore `store.manifest` validates and keys it: target, preset, profile,
  git sha, image. Profile and image come from the shards (`counts.json`, `image-id.txt`); preset and flags from the rewrite query.
- Entries per key: `r<n>/*` (the shards of that target), `classes/*` (chromium-classes/<target>), `ci.json` (run id, head sha, conclusion).
- Refuses (exit 2, nothing stored): other workflow, run not completed or not success, a shard job that failed, a missing shard artifact
  or classes dir, shards that disagree on profile, query, target or image.
- Idempotent: the same run again prints `unchanged` and writes nothing. A different run with an already-stored key is refused, not overwritten.
- TS stand-in (Lean op `store.ciRun` wanted): `selectCiRun`, `searchConfig` in `apps/runner/src/ci.ts`; table tests in `apps/runner/test/ci.test.ts`.
- Chromium only; WebKit waits for webkit-green.

## Waiting for CI: `fw ci wait`, `fw ci budget`

- `pnpm fw ci wait <runId>` or `pnpm fw ci wait --branch ci/<task> [--workflow <name>] [--sha S] [--since EPOCH] [--timeout S]`.
  Blocks on the shared poller's local file (0 GitHub calls of its own, however many waiters), then makes one charged
  `gh run view <id> --json jobs` per finished decisive run (cached per run id) and lets fwcore decide (`ci.verdict`, Lean
  `Fw.Ci.Verdict.pass_iff`): a run passes only if its guard decided `run`, some other job ran, every job that ran
  succeeded, and no job stopped at its `stale:` step. It prints `run <id> <workflow> <conclusion> -> <pass|fail|not-run>
  (<reason>)`; a not-run reason starts with its tag: `unwanted`, `stale`, `landed`, `unchanged` (Lean `Skip`).
  - `--branch` without `--workflow` (the default after `fw ci push`): every lane the commit's message requests, plus
    `lean` (fwcore `ci.required`), must have a pass run **for that exact commit**; no skip counts, `unchanged` and
    `lean` included (round 5, `wait_needs_default_pass`). A lane that did not run, or has no run 300 s after the
    commit's runs finished, is not a pass (Lean `combine_requested_never_pass`, `missing_never_pass`). The last line is
    `lanes <a,b> -> <verdict>`. The message is read from git only. When it cannot be read (the sha is not in the local
    object store), the request is unknown: exit 4 at once with `lanes ? -> not-run (unknown request ...)` (Lean
    `unknown_request_never_pass`); fetch the commit and wait again.
  - `--branch --workflow <name>`: the newest run of that workflow on the branch created after the commit (one run).
  - Exit 0 pass, 1 a run failed, **4 not run** (GitHub may still say `success`), 3 timeout (default 540 s) or the poller
    stopped (call it again), 2 gh could not find the run, 64 usage. Run it in the background; do not loop.
- `pnpm fw ci budget [--json|--resume|--probe]` shows the request budget (0 requests; `--probe` is one charged call).
- Never `gh run watch`, never a gh loop, never `gh api`. `fw run` waits the same way: after a dispatch it waits for the newest run of the
  workflow created after the previous newest one (a branch wait), and for `--from-run` a run wait; it throws when the run fails.
- Tests: `apps/runner/test/run-budget.test.ts` (fake gh of `packages/gh-budget`): 1 vs 10 waiters make the same gh calls; no gh call is made
  while the budget says wait or stop.

## Which workflows a `ci/*` push starts, and how to run the one you will read

- Round 3 (task `ci-own-trigger`, Lean `Fw.Ci.Intent.decision`): no workflow has `on.push.paths`, so every push to `ci/*`
  creates a run of every workflow (a `main` push: of the seeders' workflows only) and its first job `guard` decides (`.github/scripts/changed-inputs.mjs`).
  On a `ci/*` push it runs the jobs iff, in this order (the first failing one is the skip tag):
  `unwanted` the head commit asks for the lane (or it is the default lane `lean`); `stale` the commit is still the branch
  tip (`git ls-remote`; unreadable counts as the tip); `landed` the commit is not on main yet; `unchanged` some file that
  differs from main on the WHOLE branch (merge-base..HEAD, content not main's: Lean `effective`) is an input; round 5:
  `lean` never skips as `unchanged` on `ci/*` (`lean_never_unchanged`). The tip therefore always runs every requested
  lane whose inputs differ from main, and `lean` on every tip not on main (`tip_starts`, `tip_lean_always`); a later push that reverts part of the branch cannot hide what the branch still
  carries (`tip_history_free`). A merge of main adds nothing (`merge_starts_nothing`).
- A `main` push starts only the workflows of the cache seeders (Lean `Fw.Ci.Trigger.seeders`: `lean.yml` job `lean`,
  the Lake cache; `premise-tests.yml` job `engine`, the gate-engine caches). Such a run goes on iff its own diff
  (before..HEAD) passes the coarse globs (`pushPaths`: each cone as `lean/Fw/**`, `lean/*.lean`;
  `main_keeps_paths_rule`), and then runs only the guard and the seeders (`mainRuns_iff`). No workflow has a schedule
  (`no_crons`). Dispatches always run.
- The inputs are the rows of `table` in `lean/Fw/Ci/Trigger.lean`; `fwcore` users depend on the import cone of
  `Main.lean`, not on `lean/**`. To change one: edit `table`, `cd lean && lake test -- --write-ci-trigger-golden`, then
  `node scripts/ci-paths.mjs --write`. The land check `apps/runner/test/ci-triggers.test.ts` fails on any other edit.
- **Rule for agents: a ci/* push starts only the lanes its head commit asks for.** Push with
  `pnpm fw ci push --branch ci/<task> --lanes <lane>[,<lane>...]` (lanes are the workflow file stems: `lean`, `wktr`,
  `webkit-sim`, `breakpoint-gate`, ...). It adds an empty commit `ci: request [ci:<lane>] ...` when HEAD does not
  already ask for exactly those lanes, previews with the guard's own rule over the branch (fresh `origin/main`) which of
  them will start, refuses (exit 2) when a named lane would be skipped (its wait could never pass; Lean `pushOk`,
  `skipped_named_refused`) or when HEAD is already the tip (a re-push creates no run), and pushes (never forced).
  `--partial` pushes when at least one named lane starts (the wait then ends not-run). `--lanes none` asks for no lane
  (lean still runs if lean inputs differ from main); `--dry` only previews. Then wait:
  `pnpm fw ci wait --branch ci/<task>`. lean's inputs (Lean `table`, lean row) include every `../` path that
  `lean/scripts/*.sh` reads; `node scripts/ci-paths.mjs --check` fails when one is missing.
  - The token is `[ci:<lane>]` anywhere in the head commit message, any case. `lean` (ubuntu, never macOS:
    `default_no_macos`) is always wanted and has no guard `if:`. Do not write `[ci:` in prose in a commit message.
  - The request commits are empty commits; keep them: they land on main with the branch.
  - A requested lane whose inputs equal main on the branch is skipped `unchanged`; to re-run it, dispatch it:
    `gh workflow run <lane>.yml --ref ci/<task>` (a record: it always runs). Dispatch also for inputs (`-f key=value`).
  - Nothing is cancelled on `ci/*` (Lean `Fw.Ci.Cancel.ci_never_cancelled`): every heavy job's group holds the run id
    on `ci/*` and dispatches, the ref on `main` pushes (the seeders' main runs queue); no job sets `cancel-in-progress`. Instead the
    first steps of every heavy job re-check the tip (`tip re-check`, then `stale: a newer push is the branch tip` fails
    the job when a newer push moved it), and every later step that uses `always()`/`failure()`/`cancelled()` also needs
    `steps.stale.outcome == 'skipped'` (`stale_never_works`). An older push may so use a runner for a minute; it never
    reports a pass (`stale_never_pass`).
  - You should not need `gh run cancel`. If a run you did not ask for does work, report it (a guard bug).

## Second reader: CircleCI (pilot)

`pnpm fw ci wait --provider circleci (--pipeline ID | --branch ci/<task>) [--out DIR]` waits on a CircleCI pipeline (polls every 120 s or more, honours Retry-After) and exits 0 pass, 1 fail, 3 timeout, 4 not run, 5 pilot stop rule. It makes no GitHub call. Setup and the other commands: `docs/team/tools/circleci.md`.
