# dormant-counts handoff

- Branch worktree-wf_7d3b3dee-d5c-1, worktree .claude/worktrees/wf_7d3b3dee-d5c-1 of the main checkout, started from 1c493c313.
- Last commit: 1e2af8088 (data, note, ledger, golden); lead review fixes on top.
- CI runs (this branch dispatched none and pushed no ci/* branch):
  - webkit base cb4bec8 40196215217: complete, filed
  - webkit flag morph.mount:shift-dormant cb4bec8 40196227509: complete, success, 3 VMs; read from gh run download because the
    `fw run --from-run` filing took over an hour (same for sibling tasks); the filing has since finished
  - webkit flag at 1fac415 40171948671: complete, filed (cross-commit supplementary arm only)
  - chromium base 40171939293 and flag 40171969469 (swipe-touch-v1, 1fac415): complete, filed
- Verified: Lean module builds, golden equals the Lean output from results/dormant-counts/zones.json, note and ledger written.
- Verdicts: WebKit no-win in hero, finish and rest (n 3 VMs each); Chromium win in hero only (FunctionCall -2.0 %), finish and rest no-win.
- Default arm runs faithful (apps/site/src/registry/resolve.ts:84, apps/site/src/parts/morph.mount/part.json:10).
- No write outside the task list: the golden carries the reduced data as its first line, so check.sh reads no results/ file.
- Dry land: VERDICT dry dormant-counts; review ready: VERDICT review-ready dormant-counts review. To refresh the data: run reduce.mjs (usage in its header; the five arms are
  webkit/base=40196215217 webkit/flag=40196227509 webkit/flag@1fac415=40171948671 chromium/base=40171939293 chromium/flag=40171969469),
  then `Fw.Parts.DormantCounts.gen ["--from", "../results/dormant-counts/zones.json"]` from lean/.
- Conventions: one sample = one VM (WebKit) or one counts run (Chromium); a step under 1 percent is no win or loss.
- Read first: lean/Fw/Parts/DormantCounts.lean header, research/notes/2026/10-2x-dormant-counts.md.
