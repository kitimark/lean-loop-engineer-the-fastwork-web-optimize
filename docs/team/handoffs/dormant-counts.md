# dormant-counts handoff

- Branch worktree-wf_7d3b3dee-d5c-1, worktree .claude/worktrees/wf_7d3b3dee-d5c-1 of the main checkout, started from 1c493c313.
- Last commit: see `git log -1` (WIP e25fc688b: Lean module, reducer, golden, wiring).
- CI runs (no new dispatch, none pushed by this branch):
  - webkit base cb4bec8 40196215217 complete, filed
  - webkit flag morph.mount:shift-dormant cb4bec8 40196227509: VM 3 success, VMs 1 and 2 in progress at last check; not filed yet
  - webkit flag at 1fac415 40171948671 complete, filed (cross-commit supplementary arm only)
  - chromium base 40171939293 and flag 40171969469 (swipe-touch-v1, 1fac415) complete, filed
- Verified: `lake build Fw.Parts.DormantCounts` green; golden regenerated from results/dormant-counts/zones.json.
- Open: file run 40196227509 (`pnpm -s fw run --target rewrite --engines webkit --fw morph.mount:shift-dormant --from-run webkit=40196227509 --sha cb4bec8`), add it to zones.json via
  `node results/dormant-counts/reduce.mjs --store the main checkout .fw-console/store --out results/dormant-counts/zones.json webkit/base=40196215217 webkit/flag=40196227509 webkit/flag@1fac415=40171948671 chromium/base=40171939293 chromium/flag=40171969469`,
  regenerate the golden (`gen []` in lean/), write note 10-2x-dormant-counts.md, ledger cells and notes row, run tests, dry land, review ready.
- Read first: lean/Fw/Parts/DormantCounts.lean header, results/dormant-counts/reduce.mjs.
- Conventions: one sample = one VM (WebKit) or one counts run (Chromium); a step under 1 percent is no win or loss.
