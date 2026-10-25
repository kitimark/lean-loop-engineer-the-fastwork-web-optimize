# Handoff: pool-dispatch-poller (console-builder)

Branch `worktree-wf_2de28e7d-882-1`, worktree `.claude/worktrees/wf_2de28e7d-882-1`, ci branch `ci/pool-dispatch-poller`. Last commit: see `git log -1` (merge of main on top of e15c56c43).

CI runs: lean 40194602056 (queued at checkpoint 1), webkit-sim push run 40194602049 (success; guard skip, no sim ran). No newer push after e15c56c43 yet; no GitHub twin or Codemagic run exists.
Codemagic: NOT triggered. The worktree has no `.local/codemagic.json` or ledger; the sandbox denied copying them from the main checkout.

Verified (local, via slot): apps/runner 113 files / 3549 tests green incl. typecheck; `node --test scripts/ci-paths.test.mjs scripts/codemagic.test.mjs` 82 pass; `sh lean/scripts/check.sh` green; `fw plan lint` 0 errors, no writesClosure line for this task.
Dry land: `VERDICT scope pool-dispatch-poller`: `scripts/codemagic.mjs` and `scripts/codemagic.test.mjs` are outside the task's writes (the trigger `--vars` and the ledger build times live there). The lead adds them to the graph row (not edited here), then reruns the dry.

Done: Lean cell theorems (PoolTier.lean); `codemagic.yaml` takes the cell as variables; `fw run` routes a webkit-sim count job through `ci.poolTier` (`realRoute` in `apps/runner/src/ci-pool-tier.ts`, hook `RunDeps.route` in `run.ts`), triggers the Codemagic cells, awaits them with the GitHub run, files them, merges classes locally; events in `<console dir>/ci-route.jsonl`; `--no-route`; docs in `docs/team/tools/ci-pool.md`.
Open: paired run. From a checkout with the app id: copy `.local/codemagic.json` and the ledger; GitHub twin `pnpm fw run --target original --engines webkit --runs 1 --ref ci/pool-dispatch-poller --no-route`; Codemagic cell `node scripts/codemagic.mjs trigger --pool --branch ci/pool-dispatch-poller --vars '{"FW_TARGET":"original","FW_PRESET":"original","FW_FW":"","FW_VM":"v1","FW_SESSIONS":"1"}'`, `wait --build <id> --out <dir>` (>= 120 s), then `node scripts/codemagic.mjs compare`.
Follow-ups: re-route of already queued GitHub jobs (no re-route step in the Lean route); rewrite arm on Codemagic (needs the site build); spool `ci-route.jsonl` into console events.
Read first: docs/team/tools/ci-pool.md (section "Dispatch-time route"), then `realRoute` in ci-pool-tier.ts.
