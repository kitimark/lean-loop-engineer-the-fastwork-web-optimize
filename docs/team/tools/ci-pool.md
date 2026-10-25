# fw ci pool: the macOS fallback route

`pnpm fw ci pool route --state <json|@file> --reqs <json|@file> [--cfg phase1|enterprise] [--over <json|@file>] [--json]` prints one line per request (`run <via>/<os> <class> <engine> timeout <m> min, <c> credits`, `wait`, or `done stale|notRun`) and a summary. `pnpm fw ci pool consts [--cfg ...]` prints the configuration and the source of each constant. Both are glue over the fwcore ops `ci.poolRoute` and `ci.poolConsts` (wire `lean/Fw/Ci/Pool/FallbackWire.lean`, shapes in its module doc). The rule is Lean `Fw.Ci.Pool.Fallback`; the golden is `packages/contracts/golden/ci/pool-fallback.jsonl` (`lean/scripts/PoolFallbackGolden.lean`, replayed in `apps/runner/test/ci-pool.test.ts`).

Shapes. `ci.poolRoute` request: `cfg`? (`phase1` default, `enterprise`), `over`? (any Cfg field; `circleCaps` an object lane → minutes), `state` `{ghMacBusy, ghTotalBusy, ghQueuedAhead?, ghDegraded?, ghRemainingS? ([s] or null: unknown), circleBusy?, bitriseBusy?, circleCreditsLeft?}` (absent counts 0), `reqs` `[{sha, lane, cfg, rep, attempt?, engine, image, capMin?, ageS?, current?}]` (`engine` one of `iosSimSafari wktrIosSim pwWebkitMac pwWebkitWpe`; `capMin` defaults to the lane's `Fw.Ci.Pool.Caps` row, an unknown lane without it is an error; `current` defaults to true; an invalid key is an error). Reply: `macFree`, `expWaitS` (n or null), `ghOk` (before the first request), `log` `[{sha, lane, cfg, rep, attempt, decision: run|wait|done, target?: {via, os, cls, engine, timeoutMin, credits}, outcome?}]`, counts `sent`, `waiting`, `done`, and `state` after the tick. `ci.poolConsts` request `cfg`?, `over`?; reply `cfg` and `sources` `[{constant, status, source}]`.

Route order, first match wins (`route`, `route_run_cases`):
1. Not the branch tip: `done stale` (`route_stale`).
2. GitHub macOS when GitHub is not degraded and a slot is free, or the expected wait is known and under `ghWaitMaxS` (1200 s). An unknown wait never goes to GitHub (`gh_first`, `gh_of_wait`, `gh_overflow_bounded`, `unknown_wait_not_github`, `degraded_not_github`). The expected wait is the `(ghQueuedAhead+1)`-th smallest remaining time of our running macOS jobs (`expWaitS`).
3. CircleCI `m4pro.medium` for a lane in `circleMacAllow` with a measured m4pro cap ≤ 10 min, a free CircleCI slot and credits for the enforced timeout (cap + 3 min setup), charged at that timeout, not at p90 (`circle_rule`, `circle_charged_at_timeout`, `circle_credits_le`, `circle_extends_provider_route`: `Fw.Ci.Provider.route` gives `circleci` on the same input).
4. Bitrise only when `bitriseOn` (`bitrise_rule`, `bitrise_off_never`).
5. Linux Playwright WebKit (WPE) on `ubuntu-24.04-arm` only for a lane in `wpeTolerant` and not in `ghOnly` (`wpe_rule`, `apple_only_never_linux`; `gate-gaps` is in `ghOnly` until it is split).
6. Otherwise `wait` while the request is younger than `waitMaxS` (7200 s), else `done notRun` (`route_wait`, `route_done`, `old_never_waits`).

Phase 1 (`phase1`) has every fallback allowlist empty and Bitrise off, so it yields GitHub macOS, a wait or a terminal row (`phase1_github_or_wait`). `enterprise` changes only `ghMacCap` 5 → 50 and `ghTotalCap` 20 → 500 (`enterprise_caps`).

Over one tick (`step`, requests in order, each against the state the earlier ones left):
- Every request lands in exactly one of sent, waiting, done (`step_perm`); a waiting request is current and younger than `waitMaxS`, so a tick where every request is that old leaves none waiting (`step_waiting`, `wait_resolves`); done rows are `stale` or `notRun` (`step_done`).
- Slot and concurrency caps hold and credits are conserved: final credits + charged credits = initial credits (`never_exceeds_quota`).
- Over many ticks with a durable insert (`admit`), no (key, attempt) is dispatched twice (`dispatch_nodup`). A GitHub dispatch is final: the route has no re-route step.

Results: a result row carries the provider, class and engine of its dispatch (`result_identity`); the pool key holds the engine, so Apple and WPE results never pool (`no_pool_apple_wpe`), and two providers pool only for a lane in `crossPoolOk` (`poolKey_via`).

## The 6-vs-5 macOS peak (resolved)

The measured peak of 6 concurrent macOS jobs (2026-10-20 18:21:30Z, 136 s) counted job 118800606953 (trajectory-probe, `probe apple (playwright-webkit, macos-26) 640_1280`), which ran no step: GitHub never acquired a hosted runner for it (annotation: not acquired by Runner of type hosted even after multiple attempts; macOS arm64 capacity notice) and cancelled it after 21.4 min (MEASURED, gh run view). By step times the peak is 5. Jobs over our own cap of 5 do queue (max cap wait 72.3 min, 10-20-macos-pool.md), so this cancellation is a GitHub capacity failure, not the cap. (MEASURED, 114 macOS jobs of runs created 2026-10-19 to 2026-10-21). The limit is 5 concurrent macOS jobs on Free, Pro and Team, 50 on Enterprise, shared across standard and larger runners (CONFIRMED, docs.github.com/en/actions/reference/limits, "Job concurrency limits for GitHub-hosted runners"). `phase1.ghMacCap` is 5.

## The three-tier route: GitHub, then Codemagic, then CircleCI (task macos-pool-7)

`pnpm fw ci pool tier --state <json|@file> --reqs <json|@file> [--over <json|@file>] [--json]` runs the fwcore op `ci.poolTier` (rule Lean `Fw.Ci.PoolTier`, wire `lean/Fw/Ci/PoolTierWire.lean`, golden `packages/contracts/golden/ci/pool-tier.jsonl` from `lean/scripts/PoolGolden.lean`, replayed in `apps/runner/test/ci-pool-tier.test.ts`). `pnpm fw ci pool tier-consts` prints `pool7`, the macOS cap and the source of each constant.

Shapes. The state is the `ci.poolRoute` state plus `cmBusy` (Codemagic builds running), `cmUsed` (Codemagic minutes this month, pending builds at their cap), `ccSpent` (CircleCI credits this month) and `ccStorage` (CircleCI storage, MB); its `circleCreditsLeft` is not read, the route computes it from `ccSpent`. `over` takes any `ci.poolRoute` Cfg field and `cmOn`, `cmCls`, `cmConc`, `cmCapMin`, `cmAllow`. Each log row has `decision` `codemagic`, `run`, `wait` or `done` and `via` (`github`, `codemagic`, `circleci`, `bitrise` or null). The reply also has `counts` per provider, `inflight`, `macCap`, `cmOk` (for the first request), `ccLeft` (credits left after the storage overage) and `ccStorageCredits` (`Fw.Ci.Provider.storageCredits` of `ccStorage`).

`pool7` is `phase1` with `webkit-sim` allowed on CircleCI `m4pro.medium` (cap 40 min) and on Codemagic `mac_mini_m2` (1 concurrent, cap 40 min). For each request, first match wins:
1. GitHub as in `Fw.Ci.Pool.Fallback` (stale, a free slot or a known short wait). GitHub always comes first (`github_first`, `route_base`).
2. Codemagic, when `cmOn`, the lane is in `cmAllow`, fewer than `cmConc` builds run and `Fw.Ci.Codemagic.poolOk` holds (`cmUsed + cap <= 400`, `cap <= 40`; `route_cm_iff`). Codemagic is tried before CircleCI (`codemagic_before_circleci`).
3. The `Fw.Ci.Pool.Fallback` route with CircleCI credits left = `Fw.Ci.Overflow.classLeft` (pool minus the 20 % reserve minus `ccSpent` minus the storage overage `storageCredits ccStorage`: storage past the 2 GB-month Free allowance costs 420 credits per GB-month from the same pool). Storage alone never empties the CircleCI allowlist (`fb_storage_within_allow`).

Each provider's stop rule refuses on its own: GitHub never runs a 6th macOS job (`gh_line`), Codemagic never passes 400 minutes or a 40-minute cap (`cm_line`, `cm_refuses_over`), CircleCI never spends into the reserve (`cc_credits_line`) or runs unless its credits, the credits spent, the storage overage and the reserve fit the pool (`cc_storage_line`), Bitrise never runs while off (`bitrise_line`). Over a tick that starts within the caps, at most 7 jobs are in flight: 5 GitHub, 1 Codemagic, 1 CircleCI (`cap_7`). A result counts once for its key whatever provider and class ran it (`counted_relabel`, `result_counts_any_provider`).

`pnpm fw ci pool dispatch --branch ci/<name> --state ... --reqs ... [--go]` fills `cmUsed`, `cmBusy` (`node scripts/codemagic.mjs facts`), `ccSpent` and `ccStorage` (the CircleCI ledger) where the state leaves them out, prints one line per request, and with `--go` runs `node scripts/codemagic.mjs trigger --pool --branch B` for a Codemagic row and `node scripts/circleci.mjs trigger --lane L --branch B` for a CircleCI row. GitHub rows need no command: the push of the branch runs them. Exit 5 means a provider's own stop rule refused at trigger time.

Live run, 2026-10-22, branch `ci/macos-pool-7` (MEASURED: `gh run view` job times, Codemagic `build.json`). Both dispatches had GitHub at 5 of 5 macOS slots, Codemagic 46 and 66 minutes used, CircleCI 3575 credits and storage 1297 thousandths of a GB-month. Each time the route gave Codemagic one request and made the next wait: the CircleCI storage line is 1000 (`cc_storage_line`), so no CircleCI pipeline was started (that line is gone; the same ledger gives 650, `storage_20261021`). At 07:01:15Z six macOS jobs ran at once: five on GitHub (three of them ours: webkit-sim run 39734101098, wktr 39734101164, wktr-fixtures 39734101121); both of these runs end failure because their later jobs stopped stale at the tip re-check after the second push, while the jobs running at 07:01:15Z (wktr j1, fixtures j2) passed and Codemagic build 6ad9b3b25a4232c65cf47752. Under the 30-day count of that day the seventh slot stayed closed.

## Dispatch-time route in `fw run` (task pool-dispatch-poller)

On 2026-10-25 `fw run` sent every macOS job to GitHub, so count runs queued behind the 5 slots while the Codemagic slot idled (`codemagic.yaml` was a one-cell pilot). A `webkit-sim` count job of a routable target (Lean `ci.poolCell`: `original`, `rewrite`; not `both`), on a pushed `ci/*` ref with at least 2 VMs, goes through the Lean route first (`apps/runner/src/ci-pool-tier.ts`, `realRoute`):

1. Facts: `gh run list --status in_progress` plus `gh run view --json jobs` for the in-progress macOS workflows (`ghMacBusy` = macOS jobs in progress or queued, `obs.macIs`), and `node scripts/codemagic.mjs facts` (`cmUsed`, `cmBusy`). `ghRemainingS` stays unknown, so a full GitHub never counts as a short wait.
2. Route: fwcore `ci.poolTier` with CircleCI closed (`circleMacAllow: []`). GitHub first, Codemagic only when GitHub is full, stop at 400 of 500 minutes (Lean: `github_first`, `cm_refuses_over`, `cm_cells_budget`, `rewrite_routable`, `both_not_routable`).
3. Cells the route sends to Codemagic run as `codemagic.yaml` variables (`FW_VM=v<k>` or `r<k>` as Lean's `measure.simPlan` names the cells, `FW_SESSIONS`, `FW_TARGET`, `FW_SEARCH` for the rewrite query, via `trigger --vars`; an empty value travels as `none` because Codemagic refuses an empty variable, build 6addffe5); at most `vms - 1` cells leave GitHub, the GitHub run keeps v1.. and the telemetry pieces. The GitHub run is dispatched with the remaining count, then GitHub and Codemagic are awaited together. The artifacts land in `webkit-sim-v<k>/` as `gh run download` would put them, `webkit-classes` is merged locally over every VM (`mergeClasses`), and the Codemagic build `sha` must equal the target sha.
3a. The rewrite cell builds the site itself from the same commit: `codemagic.yaml` installs the pinned elan (sha256 checked), `pnpm install --frozen-lockfile --filter '@fw/site...'`, `pnpm --filter @fw/site build [--config <query>]`, verifies the snapshot, prints `node scripts/codemagic.mjs site-digest apps/site/dist/aot` (artifact `site-digest.txt`) and serves that build. After the GitHub run, `place` downloads its `site-dist` artifact, digests it the same way and asks Lean `ci.poolCell` whether the cell is filed: only with two equal, non-empty digests (`rewrite_filed_needs_digest`, `rewrite_mismatch_refused`, `rewrite_no_cm_digest_refused`, `rewrite_no_gh_digest_refused`; the original arm needs none, `original_filed`). A refused cell fails the run (the target is not routable for that commit); rerun with `--no-route`.
4. Events: `<console dir>/ci-route.jsonl` (runner log, not console `events.jsonl`): `ci.route` (cells, codemagic, github, per-cell rows, busy, facts), `ci.route.skip` (why), `ci.codemagic.build` (build, vm, status, startedAt, finishedAt, createdAt, minutes), `ci.codemagic.refused`, `ci.site.digest` (vm, both digests, filed). No author, email or token fields. The ledger row of `fetch` carries the same times.

`fw run ... --no-route` keeps every cell on GitHub. A refused trigger (exit 5) or a failed Codemagic build fails the run.

### Toolchain identity of a Codemagic cell (final design round)
- `codemagic.yaml` pins `xcode: 27.1`, the Xcode of the GitHub `xcode-27` image; `FW_IOS_BUILD` and the `check-simulator` refusal pin the runtime.
- Key = `{macosBuild, xcodeBuild, runtimeBuild, cpus, memsize}` read from each cell's `tools.txt` (the three builds, then the two bare numbers of `sysctl -n hw.ncpu hw.memsize`; webkit-sim.yml and codemagic.yaml both print them). Lean `ci.cellMerged` (PoolTier.lean `cellMerged`) merges a cell only when its key equals the key of the GitHub cell v1 (r1 for the rewrite arm) and every component is non-empty. TypeScript parses and passes keys, never compares them.
- A refused cell is filed aside: `refused/webkit-sim-<vm>/` and, in `webkit-classes/refused/`, `<vm>-classes.md` and `<vm>-key.json`. Event `ci.cell.platform {vm, ref, key, merged, hw}` in `ci-route.jsonl`.
- A Codemagic build whose record carries no commit sha is refused.
- Limits: hardware is in the key since task cross-pool-pooling (the 3 cpu GitHub cell and the 8 cpu Codemagic cell never merge directly); merged cells can only demote rows (worst wins); no claim of equal counts across pools; GitHub VMs' keys are not cross-checked; no auto-pin when the GitHub image moves. TS stand-in: `mergeClasses` (the webkit-sim.yml merge job), the site-digest walk, the `tools.txt`/facts readers.

#### Paired rewrite run, outcome (a) (MEASURED, n=1 per side, commit f438f8623)
GitHub webkit-sim run 40211928946 cell r1 against the Codemagic cell r1 (Codemagic build 6ade316d, pinned image xcode 27.1). Keys equal and complete (macOS 26A434, Xcode 27A9275, runtime 24A434), so Lean `ci.cellMerged` merges the cell; site digests equal (GitHub run 40211928946 site-dist against the Codemagic site-digest.txt; ca7745e4f918...). Hardware (recorded, not keyed): GitHub 3 cpus, Codemagic 8 cpus / 12 GiB (mac_mini_m2).
Class diff, row by row (GitHub class -> Codemagic class): 20 of 104 rows differ, none only on one side. GitHub 39 quarantined / 52 deterministic / 13 stable; Codemagic 27 / 59 / 18. The cause is not attributed (n=1 per side). Count equality across pools is not claimed; a merged cell can only demote rows (worst wins). By the final-design-round rule this goes to a re-plan (hardware key, k pairs), not into this branch.
- census|layerCount|per state: quarantined -> stable
- census|layerCount|y=0: quarantined -> stable
- census|backing memory bytes (sum)|y=0: quarantined -> stable
- census|layerCount|y=1500: deterministic -> stable
- census|layerCount|y=5267: stable -> deterministic
- census|backing memory bytes (sum)|per state: quarantined -> stable
- census|layers with reason (gone)|per state: quarantined -> stable
- census|layers with reason overlap|per state: deterministic -> stable
- census|layers with reason transformWithCompositedDescendants|per state: stable -> quarantined
- scroll|RecalculateStyles|total: quarantined -> stable
- scroll|Layout|total: quarantined -> stable
- scroll|Paint|total: quarantined -> stable
- scroll|Composite|total: stable -> deterministic
- scroll|ObserverCallback|total: stable -> deterministic
- scroll|InvalidateLayout|total: quarantined -> deterministic
- scroll|Composite|per 500 px zone: stable -> deterministic
- scroll|ObserverCallback|per 500 px zone: quarantined -> deterministic
- scroll|Composite|per step: quarantined -> deterministic
- scroll|RenderingFrame|per step: quarantined -> deterministic
- scroll|ObserverCallback|per step: quarantined -> deterministic

## Cross-pool pooling (task cross-pool-pooling)
Why: equal toolchain keys still gave 20 of 104 class differences (MEASURED, n=1, above), and the hardware differed (3 vCPU M1 against 8 cpu / 12 GiB). Lean `Fw.Ci.PoolTier`:
- Hardware is in the key (`Hw {cpus, memsize}`); `complete` needs both above 0. Theorems `cellMerged_hw_refused`, `cellMerged_cpus_refused`, `cellMerged_memsize_refused`, `measured_pair_not_merged` (the measured pair is not merged).
- Row decision (`rowUse`, op `ci.poolRows`): direct when the cells merge; paired when at least `kReq` = 3 pinned pairs (one GitHub cell and one Codemagic cell of one commit) agree in class on that row and carry exactly the current ref and cell keys; else refused. Each row is decided alone; the paired class is the worst seen (`pairedClass_ge`). Theorems: `pooled_too_few`, `pooled_disagree`, `pooled_ghKey_mismatch`, `pooled_cmKey_mismatch`, `rowUse_few_pairs_refused`, `rowUse_disagree_refused`.
- Budget: `pairsAffordable used k` is `used + 40 k <= 400`; `pairsReachable used = min 3 ((400 - used) / 40)`. At 166 used, k = 5 fits (`k5_fits_166`), k = 6 does not. If the budget cannot cover k, the reply's `reachable` is the k reached and the decision stays "not pooled".
- Re-route (`reroutePlan`, op `ci.reroute`): a queued GitHub job moves when it has waited 300 s and is the only unfinished cell of its run; the plan is `step` over the movable requests, so `reroute_budget`, `reroute_slots`, `reroute_cap_7` hold. Glue `rerouteQueued` (ci-pool-tier.ts): trigger Codemagic first, cancel the GitHub run only after the trigger succeeded.
- Pair records: `place` writes `<console dir>/ci-pairs/<sha7>-<target>-<vm>-<build>.json` for each refused cell and `webkit-classes/refused/<vm>-pooled-rows.json` (the `ci.poolRows` reply) when the three builds agree.
- `fw ci state cm:<24 hex>` prints `running`, `complete` or `failed` (scripts/codemagic.mjs `state --build`); `fw review ready` accepts `cm:<24 hex>` as run evidence (Lean `runIdOf`).
- TS stand-ins: `classRowsOf` (codemagic.mjs `classRows`), the pair files, `rerouteTick` (queued rows and their age; the move is Lean's), `hwOf`.
- Accepted limits: one Codemagic slot; Codemagic hardware varies within an instance_type (recorded per build); CircleCI is closed for macOS; no paid runners; k pairs are bounded by the minute budget.

## Not wired yet

The poller calls `env.reroute` (packages/gh-budget/src/poller.ts `rerouteTick`) with the still-queued runs of each list; the runner does not set that hook in production yet, so `rerouteQueued` runs only where a caller sets it. Live slot reading (`ghRemainingS`), the `ghWaitMaxS` sweep (pool-replay) and one `Provider` type with Telemetry are follow-ups. Spooling `ci-route.jsonl` into console events is a follow-up.
