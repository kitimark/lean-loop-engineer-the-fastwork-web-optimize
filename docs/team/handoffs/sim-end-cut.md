# Handoff sim-end-cut (checkpoint 3, results in, checks running)

- Branch: worktree-wf_e8817152-d6f-1; worktree: .claude/worktrees/wf_e8817152-d6f-1; CI branch: ci/sim-end-cut
- Last commit: see `git log -1` (tip pushed to CI: 2afff9f6b, tokens `[ci:webkit-sim] [end-floor] [end-floor-vms:3] [end-cut]`; results commit 3990e7420; main merged after)
- CI runs: webkit-sim 41173075281 (35807f6bc) failed at the site build (platform:faded-pause conflicts with platform.sweep:offscreen-pause);
  webkit-sim 41173535319 (2afff9f6b) success, 3 jobs x 1 round; lean 41173535375 (2afff9f6b) success.
- Results: `results/sim-end-cut/r1/` (job1..3.json, job1..3-log.txt, rows.txt, table.txt, cut.txt). Note: research/notes/2026/10-31-sim-end-cut.md. Ledger row added (task sim-end-cut).
- Finding (negative): v2p, parks, pauses, both all read 200 per 100 at end and back in 3 of 3 jobs. Prediction held for parks alone and pauses alone, missed for both.
  Census: hero.exit:threaded-park did not engage (13 view animations remain) and platform.sweep:offscreen-pause left 2 of 4 sweep loops running; the other three flags took effect.
- Verified: Lean module `lean/Fw/Device/SimEndCut.lean`, golden `packages/contracts/golden/device/sim-end-cut.jsonl`, TS stand-in `packages/measure-webkit/src/sim-end-cut.mjs`
  equals the golden; measure-webkit tests (1075), ci-paths test (56) and runner land-inputs test (73) pass after the merge of main; plan lint shows no writesClosure for sim-end-cut.
- Open: check.sh result after the merge, dry land, review ready (see the final report). Follow-up candidate in the note section 6 (hero park engage after an instant jump; track every sweepDoc element).

## State
- Arms (sim-end-floor.mjs CUT_ARMS): v2p, parks, pauses, both; pauses and both drop platform:faded-pause (conflict). Report: `sim-end-floor-cli.mjs cut job1.json job2.json job3.json --out results/sim-end-cut/r1`.

## Read first
- research/notes/2026/10-31-sim-end-cut.md, lean/Fw/Device/SimEndCut.lean.
