# hero-relayout-boundary handoff

## State
- Branch `worktree-wf_6bf5744f-815-1`, worktree `.claude/worktrees/wf_6bf5744f-815-1`, CI `ci/hero-relayout-boundary`.
- Last commit: see `git log -1` (main merged at 3a88ec475); measured CSS unchanged since 0537be1.
- CI runs: chromium-counts base 40268899311, flag 40268902395 (success, sha 0537be1); breakpoint-gate 40271199102
  (success, sha 26bd7b1); webkit-sim base 40271367353 and flag 40271370582 (in progress at 06:06 UTC, sha 26bd7b1).

## Verified
- `lean/Fw/Parts/HeroContainOpt.lean` theorems, golden `hero-contain.jsonl`, FlagDelta allowlist (merged with main's
  platform.sweep rows; flag-delta and triggers goldens regenerated), gate-breakpoints tests 789 pass.
- Chromium hero-exit window, Lean cmp/judge: Layout same, RecalcStyle same, Paint same, totalObjects less, verdict
  gain (`results/hero-relayout-boundary/chromium.json`, `extract-chromium.mjs` is a TS stand-in).

## Open
- WebKit: wait, then `gh run download <id> -D <empty dir>` per run; read with
  `node results/hero-relayout-boundary/read-webkit.mjs results/hero-relayout-boundary/webkit.json base=<dirs> flag=<dirs>`
  (dirs = the `webkit-sim-r<k>` artifact dirs); fewer than 3 VMs means undecided with n.
- Note WebKit section, ledger `webkit` field, check.sh, dry land, review ready.

## Conventions
- Flag CSS: `[data-fw-variant='contain'] > .hero { contain: size layout; }` at the end of hero.module.css.
- Chromium window = zones y00000 and y00500; WebKit window = scroll y 0 to 1000 (`read-webkit.mjs`).

## Read first
- `research/notes/2026/10-20-hero-relayout-boundary.md`, `lean/Fw/Parts/HeroContainOpt.lean` §3-5.
