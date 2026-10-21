# pool-fallback (lean-prover)

**State:** branch `worktree-wf_3ed64005-563-1`. Rule `lean/Fw/Ci/Pool/Fallback.lean` (`Fw.Ci.Pool.Fallback`), wire
`lean/Fw/Ci/Pool/FallbackWire.lean` (`Fw.Wire.CiPool`, ops `ci.poolRoute`, `ci.poolConsts`, registered in
`lean/Fw/Ci/Wire.lean`), golden `packages/contracts/golden/ci/pool-fallback.jsonl` (`lean/scripts/PoolFallbackGolden.lean`,
`--check` row in `lean/scripts/check.sh`), CLI `fw ci pool route|consts` (`apps/runner/src/ci-pool.ts`), test
`apps/runner/test/ci-pool.test.ts`, doc `docs/team/tools/ci-pool.md`. `Fw.Ci.Provider` and `Caps.lean` untouched.

**Verified:** check.sh green, runner tests green (2196), ci-paths test green, axioms propext/Quot.sound only.
Theorems: route order (`route_run_cases`, `route_stale`, `gh_first`, `gh_of_wait`, `gh_overflow_bounded`,
`unknown_wait_not_github`, `degraded_not_github`), CircleCI (`circle_rule`, `circle_charged_at_timeout`,
`circle_credits_le`, `circle_extends_provider_route`), `bitrise_off_never`, `wpe_rule`, `apple_only_never_linux`,
`route_wait`, `route_done`, `old_never_waits`, `phase1_github_or_wait`, `enterprise_caps`; tick (`step_perm`,
`step_waiting`, `wait_resolves`, `step_done`, `never_exceeds_quota`); ticks (`admit_nodup`, `drive_ids`,
`dispatch_nodup`); results (`result_identity`, `no_pool_apple_wpe`, `poolKey_via`).

**6-vs-5 peak:** resolved; the 6th job ran no step (queued, cancelled). Limit 5 CONFIRMED by the GitHub limits doc.
Details in the tool doc.

**Open:** dispatch wiring and the poller tick (ci-route); live `ghRemainingS`/`ghQueuedAhead` reading; `ghWaitMaxS`
sweep (pool-replay); `bitriseConc`/`bitriseMaxMin` are UNKNOWN placeholders; one `Provider` type with Telemetry;
series admission (queuedAhead) folded into `step` only.

**Conventions:** `Via` is local to the route (Provider keeps two constructors); every run reserves `t.credits`
(nonzero only for CircleCI, charged at cap + setup, not p90).

**Read first:** `docs/team/tools/ci-pool.md`, then the theorem list in `Fallback.lean`.
