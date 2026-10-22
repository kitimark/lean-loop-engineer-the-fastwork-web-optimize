# cc-storage-count handoff

- Branch `worktree-wf_34bfd889-b9c-1`, worktree `.claude/worktrees/wf_34bfd889-b9c-1`; commits 05b7d8ae (Lean), d5d399fa (TS), merge of main, docs + this note.
- CI runs: none (the unit is Lean + TS + goldens; no CI lane needed).
- Verified at the merge of main: `sh lean/scripts/check.sh` green via the slot (provider 175, overflow 53, pool-tier 20 golden lines up to date; axiom check 0 failing); `pnpm --filter runner test` 2556 passed; `pnpm --filter contracts test` 11 passed; `node --test scripts/ci-paths.test.mjs scripts/circleci.test.mjs` 125 passed.

## State
- Lean `Fw.Ci.Provider`: `storageNow` (rows in the 30-day window, caches/workspaces 15 days, artifacts 30), `storageAllowMilli` 2000, `storageStopMilli` 1000 (in-job stop only), `storageCredits` (420 per GB-month past the allowance), `ownSaveMilli` 235, `SavePolicy` with `policyWindowCredits`. `storage_20261021`: the 2026-10-21 ledger gives 650.
- `Fw.Ci.Overflow.budgetFits` charges run credits + spent + storage overage (with the own save) + reserve against the pool; `storage_alone_never_refuses`, `reason_not_storage`, `storage_over_budget_keeps_github`, `overflow_20261021` (all legs to CircleCI).
- `Fw.Ci.PoolTier`: `State.fb` subtracts the storage overage from credits left; `cc_storage_line`, `fb_storage_within_allow`; wire field `ccStorageCredits` replaces `ccStorageClear`.
- TS: `scripts/circleci.mjs` `storageNow`/`storageCredits`/`ledgerRows` follow Lean; `apps/runner/src/land-overflow.ts` passes storage as `storageNow`.

## Open
- Files outside the graph writes: `lean/Fw/Ci/PoolTierWire.lean`, `lean/scripts/{Provider,Overflow,Pool}Golden.lean`, `docs/team/tools/{ci-pool,land,circleci}.md`.
- Follow-ups: re-route a pending leg to CircleCI during a GitHub incident (after land-leg-pending); `.circleci/config.yml` Lake save policy (Lean `SavePolicy` exists, config not changed); whether CircleCI stops builds on an empty free pool is UNKNOWN (reserve covers it); "overage draws from the free pool" is INFERRED.

## Read first
`lean/Fw/Ci/Provider.lean` (storage section near `storageAllowMilli`), `lean/Fw/Ci/Overflow.lean` `budgetFits`, `research/notes/2026/10-2x-cc-fallback-why.md`.
