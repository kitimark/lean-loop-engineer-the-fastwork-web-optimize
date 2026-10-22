# cc-storage-count handoff

- Branch `worktree-wf_34bfd889-b9c-1`, worktree `.claude/worktrees/wf_34bfd889-b9c-1`; round 2 commits 8d6ed7d3 (landStops + wait flag), merge of main b7bd725b, 938fea05 (docstring; check.sh green there). Dry: `VERDICT dry cc-storage-count`; review ready: `VERDICT review-ready`.
- CI runs: none (the unit is Lean + TS + goldens; no CI lane needed).
- Verified at the merge of main 623bcf1c: `sh lean/scripts/check.sh` green via the slot (provider 184, overflow 53 golden lines up to date; axiom check 0 failing); `pnpm --filter runner test` 2581 passed (tsc included); `pnpm --filter contracts test` 11 passed; `node --test scripts/circleci.test.mjs scripts/ci-paths.test.mjs` 126 passed.

## State
- Round 1 blocker fixed: Lean `Fw.Ci.Provider.landStops` (cap and queue only) with `storage_not_mem_landStops`, `landStops_eq_filter`, `landStops_storage_free`, `landStops_eq_stops`, cap/queue iff; golden op `landStop` (9 rows, one at 1297).
- `scripts/circleci.mjs` `landStops` follows Lean; `pollOnce` applies it and reads no ledger when `ctx.storageStop === false`; `realCircle.wait` passes `storageStop: false` (`apps/runner/src/land-overflow.ts`).
- Test `apps/runner/test/land-overflow.test.ts` "the land-lane wait applies Lean landStops": ledger at 1297, forceFull, legs to CircleCI, wait returns 0 with no POST; the pilot wait on the same ledger returns 5. Fails with the flag removed (checked).
- `Fw.Ci.Overflow.budgetFits_iff` (exact room for the storage overage); `PoolTier.State.fb` docstring says why no own save is charged (webkit-sim saves no cache).
- Earlier: `storageNow`, `storageCredits`, `ownSaveMilli`, `budgetFits` with storage overage, `State.fb` charge, wire field `ccStorageCredits`.

## Open
- All changed files are in the graph writes (r282); `land-remote.ts` is unchanged.
- Follow-ups: re-route a pending leg during a GitHub incident; `.circleci/config.yml` Lake save policy; CircleCI on an empty free pool UNKNOWN (reserve covers it); "overage draws from the free pool" INFERRED.

## Read first
`lean/Fw/Ci/Provider.lean` (`landStops`, storage section), `lean/Fw/Ci/Overflow.lean` `budgetFits`, `scripts/circleci.mjs` `pollOnce`.
