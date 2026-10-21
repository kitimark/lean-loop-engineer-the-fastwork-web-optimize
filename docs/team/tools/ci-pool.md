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

The measured peak of 6 concurrent macOS jobs (2026-10-20 18:21:30Z, 136 s) counted job 118800606953 (trajectory-probe, `probe apple (playwright-webkit, macos-26) 640_1280`), which ran no step: it was queued, then cancelled. By step times the peak is 5 (MEASURED, 114 macOS jobs of runs created 2026-10-19 to 2026-10-21). The limit is 5 concurrent macOS jobs on Free, Pro and Team, 50 on Enterprise, shared across standard and larger runners (CONFIRMED, docs.github.com/en/actions/reference/limits, "Job concurrency limits for GitHub-hosted runners"). `phase1.ghMacCap` is 5.

## Not wired yet

The route is not called by any workflow or poller. Dispatch wiring and the poller tick (ci-route), live slot reading (`ghRemainingS` from running jobs), the `ghWaitMaxS` sweep (pool-replay) and one `Provider` type with Telemetry are follow-ups.
