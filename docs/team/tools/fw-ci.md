# fw ci

`fw ci [<run id>] [--workflow chromium-counts] [--branch main] [--store <dir>]` pulls a finished CI run into the artifact store.
No run id: the latest run of the workflow on the branch. The store is `$FW_CONSOLE_DIR/store` (default `.fw-console/store`) unless `--store`.

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
  Blocks on the shared poller's local file (0 GitHub calls of its own, however many waiters), follows the NEWEST run per workflow on the
  branch, prints `run <id> <workflow> <conclusion>`. Exit 0 every decisive run succeeded, 1 a run failed, 3 timeout (default 540 s) or the
  poller stopped (call it again), 2 gh could not find the run, 64 usage. Run it in the background; do not loop.
- `pnpm fw ci budget [--json|--resume|--probe]` shows the request budget (0 requests; `--probe` is one charged call).
- Never `gh run watch`, never a gh loop, never `gh api`. `fw run` waits the same way: after a dispatch it waits for the newest run of the
  workflow created after the previous newest one (a branch wait), and for `--from-run` a run wait; it throws when the run fails.
- Tests: `apps/runner/test/run-budget.test.ts` (fake gh of `packages/gh-budget`): 1 vs 10 waiters make the same gh calls; no gh call is made
  while the budget says wait or stop.

## Which workflows a `ci/*` push starts, and how to run the one you will read (tasks `ci-trigger-lean`, `ci-own-trigger`)

- A push to `ci/*` starts a workflow only if THIS push changed one of its declared inputs to something other than main's
  content (Lean `Fw.Ci.Trigger.starts_iff`, `merge_starts_nothing`): a merge of main starts nothing; a later push that
  does not touch the inputs does not start it again. The inputs are the rows of `table` in `lean/Fw/Ci/Trigger.lean`;
  `fwcore` users depend on the import cone of `Main.lean`, not on `lean/**`. The generated `on.push.paths` are coarse and
  stable: each cone is written as `lean/Fw/**`, `lean/*.lean` (`pushPaths`, task `ci-cone-glob`), so a new module changes no
  workflow file. Every workflow's first job `guard` computes the precise cone from the checkout and applies the exact rule
  (`.github/scripts/changed-inputs.mjs`); the other jobs wait for it. Sound: `coarse_sound`, `push_filter_passes`.
- To change a trigger: edit `table` in `lean/Fw/Ci/Trigger.lean`, `cd lean && lake test -- --write-ci-trigger-golden`, then
  `node scripts/ci-paths.mjs --write`. The land check `apps/runner/test/ci-triggers.test.ts` fails on any other edit of `on.push`.
- **Rule for agents: a ci/* push starts only the lanes its head commit asks for (task `ci-own-trigger`, Lean
  `Fw.Ci.Intent`).** Push with `pnpm fw ci push --branch ci/<task> --lanes <lane>[,<lane>...]` (lanes are the workflow
  file stems: `lean`, `wktr`, `webkit-sim`, `breakpoint-gate`, ...). It adds an empty commit `ci: request [ci:<lane>] ...`
  when HEAD does not already ask for exactly those lanes, previews with the guard's own rule which of them will start
  (fresh `origin/main`), refuses (exit 2) when none would, and pushes (never forced). `--lanes none` pushes without a run;
  `--dry` only previews. Then wait: `pnpm fw ci wait --branch ci/<task> --workflow <lane>`.
  - The token is `[ci:<lane>]` anywhere in the head commit message, any case. A message with no `[ci:` at all starts only
    the default lane `lean` (ubuntu, never macOS: `default_no_macos`); any `[ci:` turns the default off, so name `lean`
    too if you want it. Do not write `[ci:` in prose in a commit message.
  - A requested lane still starts only if this push changed one of its inputs (unchanged inputs: nothing to re-run; the
    helper says so). To re-run a lane on an unchanged branch, dispatch it: `gh workflow run <lane>.yml --ref ci/<task>`
    (a dispatch is a record: it always runs). Dispatch also for inputs (`-f key=value`), as before; the push does not
    start that lane unless you name it, so there is no push-plus-dispatch duplicate to cancel.
  - A newer push on the same branch cancels the in-flight runs of every workflow whose paths it touches (workflow
    concurrency), even when it does not request them; put the tokens on your newest push. A run whose commit is already
    on main, or that a newer push superseded, skips its jobs at the guard (`landed_never_runs_heavy`,
    `superseded_never_runs_heavy`).
  - You should not need `gh run cancel` any more. If a run you did not ask for starts, report it (a guard bug), do not
    just cancel it.
