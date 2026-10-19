# ci-wait-lean handoff

State: branch `worktree-wf_cbc5b0eb-d56-1`; see the final commit in `git log -1`.

Done (Lean first, `lean/Fw/Ci/Budget.lean`):
- P_min 30 → 10. The interval is split into `hourGap`, `minuteGap` and `spread`. Guards: P = 10 at one page and
  12 at two pages (tick cost 4, minute gap 12); `ceilDiv 3600 10 * 4 ≤ share .tick`.
- (f) `firstRead`/`firstRead_bound`, `interval_clock`, `headroom_clock`, `listed_within` (liveness: the tick
  happens at x = t0 + P, at once or after waiting for the interval, and covers every watched run), `interval_eq_Pmin`,
  `listed_within_Pmin` (listed ≤ f + P_min; the waiter sees it before f + P_min + d + slice). `slice = 2`.
- (g) `ghLimit = 5000` (per user account, all tokens), `margin = 2000`, `isCorrection`, `wsum_all`,
  `budget_all_entries`: all entries plus u uncharged calls ≤ ghLimit when corrections + u ≤ margin (an assumption).
- (h) `Headers.resource` and `bucket`: only `x-ratelimit-resource: core` updates remaining/reset, and the remaining
  count is the min within one reset. Theorems: `bucket_core_only`, `charge_bucket`, `remaining_no_rise`.
- Wire: headers JSON has `resource`; limits JSON has `slice`. Goldens were regenerated with
  `lake test -- --write-ci-budget-golden`.
- TS: the fake gh sends `X-Ratelimit-Resource: core`; `SLICE` is exported and checked against limits.json.
  `timing-ci.ts` books calls with `ghCost` (jobs view 3). `land.ts` `ciLines` goes through `chargedOnce`
  (`ci.budget.reserve`, `ghCost`). `run-budget.test.ts` reads P_min from limits.json; a new test books `ciLines` at 3.

Verified: `lake build`, `lake test`, the gh-budget `pnpm test` (36/36), the runner `pnpm test`,
`node --test scripts/ci-paths.test.mjs`, `sh lean/scripts/check.sh`.

Open / follow-ups:
- `ghCost` (apps/runner/src/run.ts) is a TS stand-in with no Lean golden.
- Not done: Bash `gh` loops that wait-guard allows (ci-wait-lag), and ETag conditional polling.
- No latency number (λ, lag) is claimed; the measurement contradicts the model.
- The docstring `checker` was not spawned: this agent has no spawn tool.

Read first: Budget.lean sections (f)–(h) at the end of the file, then Wire.lean `limitsJson`/`headersJson`.
