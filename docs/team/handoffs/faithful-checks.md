# Handoff faithful-checks

State: branch `worktree-wf_df082d5f-ac9-1` (base: integration head 4ebd67b7; NOT rebased on main, it is 231 commits behind and a
merge conflicts in 18 files; rebase after integrate-ports-4 lands).

What exists and is verified (MEASURED on CI, verdict by Lean):
- `lean/Fw/Faithful/{Band,Zone,Wire,Golden,Measured}.lean`: band families (allowlist), cell/zone/region verdict with
  theorems, fwcore op `faithful.verdict`, 13 goldens, generated measured theorems (`decide +kernel`).
- `packages/measure-chromium/src/faithful.mjs` (`verdict`, `lean` modes, `--check`), `test/faithful.test.mjs`.
- `results/faithful/swipe-v1.verdict.json`, `results/faithful/runs/swipe-v1/*` (R and A' baselines of CI run 39130842058).
- `results/faithful/swipe-touch-v1.finding.json`; note `research/notes/2026/10-19-faithful-checks.md`.

Result: swipe-v1 R fails y04000, y04500 (absent) and tail; control A'/A passes all three. R's page ends 240 px earlier
(4396 vs 4636 px). swipe-touch-v1: the three rewrite shards of run 39131232365 stop with "touch input did not scroll the page
after 40 moves" (run.mjs:277); no touch verdict. Findings are not patched.

Open items:
- Why R is 240 px shorter at the end and why touch cannot scroll R: not diagnosed (a follow-up task).
- Rerun both profiles after integrate-ports-4 lands and refresh: `node packages/measure-chromium/src/faithful.mjs verdict` and
  `... lean`, from stored runs (`pnpm fw ci <id> --branch ci/<b>`, `zone-baseline.mjs --target ... --run <id> --out results/faithful/runs`
  then `zone-baseline.mjs baseline --out results/faithful/runs`).
- Outside the listed paths (land --allow): `lean/Fw/Wire.lean` (import, ops list, dispatch arm), `lean/scripts/FaithfulGolden.lean`,
  `lean/scripts/check.sh` (golden job), `packages/measure-chromium/{src/faithful.mjs,test/faithful.test.mjs,package.json}` (test script).
- Cost note: two ci/faithful-checks push runs of other workflows started before the dispatch could not be cancelled (`gh run cancel` denied).

Conventions: stable-type margin is the PLAN 2t proxy (`Fw.Measure.marginOf`), not a proven zone-level bound; shape = same frames
and scrolled px; R is judged by the median of its 3 shards; skipped (quarantined, unlisted) and unbanded types never gate.

Read first: the note, then `lean/Fw/Faithful/Zone.lean`, then `results/faithful/swipe-v1.verdict.json` (`verdict.zones[].offBand`).
Commands: `cd lean && lake env lean --run scripts/FaithfulGolden.lean [--check]`; `sh lean/scripts/check.sh`.
