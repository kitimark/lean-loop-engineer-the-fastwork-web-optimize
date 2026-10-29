# geom-recalc-bisect handoff (checkpoint 3, push 3 of max 3 being sent)

- Branch: worktree-wf_02ef56dc-a11-1 (CI branch ci/geom-recalc-bisect)
- Worktree: .claude/worktrees/wf_02ef56dc-a11-1
- Last commit: see the branch log (push 3: stage 3 pauser arms bs-pause dash/other; kill trimmed to smil)
- CI runs: wktr 40805577147 (push 1) = success, results/geom-recalc-bisect/r1 (stage 1: Lean overall named div#root > page-root; no single child of page-root drops the rate: children kept 66-117 per 100, hide page-root 18-20, hide div#root 0; obs arm: site rAF subscribers and mutations people#style / pain#data-fw-pain-dark fire in only 10-18 of ~120 frames, recalcs 91-98 of 119).
  wktr 40808745010 (push 2, stage 2: kill-feature + show-only arms, Lean carrier/holder) = success (results/geom-recalc-bisect/r2: carrier kill/smil in 3 of 3 jobs; holder several/incomplete).
  wktr push 3 run id: see ci/geom-recalc-bisect (stage 3: which svg group ticks, Lean pauser) = running.
- Temporary: .github/workflows/wktr.yml has `--modes bisect-thr-off` in the accel step. REVERT before land (git checkout main -- .github/workflows/wktr.yml).

## Verified
- Lean lean/Fw/Device/RecalcBisect.lean (decision + proofs + golden), golden packages/contracts/golden/device/recalc-bisect.jsonl (38 lines), TS reader packages/measure-wktr/src/recalc-bisect.mjs replays it (test/recalc-bisect.test.mjs). measure-wktr tests: 108 pass.
- Probe arms bs-* (mid-page.mjs) smoke-tested in headless Chromium only (shape, not a result).
- triggers.jsonl regenerated from Lean.

## Open
- Read push-3 results into results/geom-recalc-bisect/r3, name the svg group (pauser), WebKit path @862f17d, fix proposal (platform.glint:hold-freeze). No push left.
- Note research/notes/2026/10-2x-geom-recalc-bisect.md, ledger entry, check.sh, ci-paths test, land-inputs test, runner ledger vitest, plan lint, dry land, fw review ready.

## Conventions
- Results go to results/geom-recalc-bisect/r1.. (j<n>.json, tally.txt, verdict.txt); pnpm -s fw ci <runId> fetches.
- Read first: lean/Fw/Device/RecalcBisect.lean header, research/notes/2026/10-2x-geom-recalc-source.md.
