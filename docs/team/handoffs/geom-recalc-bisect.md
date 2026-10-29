# geom-recalc-bisect handoff (checkpoint 1, after push 1 of max 3)

- Branch: worktree-wf_02ef56dc-a11-1 (CI branch ci/geom-recalc-bisect)
- Worktree: .claude/worktrees/wf_02ef56dc-a11-1
- Last commit: 5f37a54eb
- CI runs: wktr 40805577147 (push 1, [ci:wktr] [accel], 3 jobs) = running. Other workflows skipped by design.
- Temporary: .github/workflows/wktr.yml has `--modes bisect-thr-off` in the accel step. REVERT before land (git checkout main -- .github/workflows/wktr.yml).

## Verified
- Lean lean/Fw/Device/RecalcBisect.lean (decision + proofs + golden), golden packages/contracts/golden/device/recalc-bisect.jsonl (38 lines), TS reader packages/measure-wktr/src/recalc-bisect.mjs replays it (test/recalc-bisect.test.mjs). measure-wktr tests: 108 pass.
- Probe arms bs-* (mid-page.mjs) smoke-tested in headless Chromium only (shape, not a result).
- triggers.jsonl regenerated from Lean.

## Open
- Read push-1 results, name the carrier (or the next probe), WebKit path @862f17d, fix proposal.
- Note research/notes/2026/10-2x-geom-recalc-bisect.md, ledger entry, check.sh, ci-paths test, land-inputs test, runner ledger vitest, plan lint, dry land, fw review ready.

## Conventions
- Results go to results/geom-recalc-bisect/r1.. (j<n>.json, tally.txt, verdict.txt); pnpm -s fw ci <runId> fetches.
- Read first: lean/Fw/Device/RecalcBisect.lean header, research/notes/2026/10-2x-geom-recalc-source.md.
