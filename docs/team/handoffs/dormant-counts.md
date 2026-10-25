# dormant-counts handoff

- Branch worktree-wf_7d3b3dee-d5c-1, worktree .claude/worktrees/wf_7d3b3dee-d5c-1 of the main checkout, started from 1c493c313.
- Last commit: see `git log -1` on the branch (data, note and ledger committed; checks and land steps follow).
- CI runs (this branch dispatched none and pushed no ci/* branch):
  - webkit base cb4bec8 40196215217: complete, filed
  - webkit flag morph.mount:shift-dormant cb4bec8 40196227509: complete, success, 3 VMs; read from gh run download because the
    `fw run --from-run` filing hung for over an hour (same for sibling tasks); not in the store unless that process finished
  - webkit flag at 1fac415 40171948671: complete, filed (cross-commit supplementary arm only)
  - chromium base 40171939293 and flag 40171969469 (swipe-touch-v1, 1fac415): complete, filed
- Verified: Lean module builds, golden equals the Lean output from results/dormant-counts/zones.json, note and ledger written.
- Verdicts: WebKit no-win in hero, finish and rest (n 3 VMs each); Chromium win in hero only (FunctionCall -2.0 %), finish and rest no-win.
- Default arm runs faithful (apps/site/src/registry/resolve.ts:84, apps/site/src/parts/morph.mount/part.json:10).
- Writes outside the task list: lean/Fw/Console/LandSpeed.lean (checkShReads gets results/dormant-counts/zones.json),
  and its generated copies apps/runner/src/land-reads.gen.ts and packages/contracts/golden/console/land-speed.jsonl.
  Siblings that read results/** from Lean will touch the same list; the merge is additive.
- Open: dry land, review ready (see the report). Rerun reduce.mjs only if a filed store copy of 40196227509 is wanted:
  `node results/dormant-counts/reduce.mjs --store <main checkout>/.fw-console/store --out results/dormant-counts/zones.json webkit/base=40196215217 webkit/flag=40196227509 webkit/flag@1fac415=40171948671 chromium/base=40171939293 chromium/flag=40171969469`
  then regenerate the golden with `Fw.Parts.DormantCounts.gen []` from lean/.
- Conventions: one sample = one VM (WebKit) or one counts run (Chromium); a step under 1 percent is no win or loss.
- Read first: lean/Fw/Parts/DormantCounts.lean header, research/notes/2026/10-2x-dormant-counts.md.
