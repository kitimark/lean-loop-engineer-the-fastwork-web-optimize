Branch: worktree-wf_1f25b75f-c5b-1 (CI ref ci/nav-cta-webkit-match). Worktree: .claude/worktrees/wf_1f25b75f-c5b-1. Last sha: `git log -1`.
CI runs (3 of 3 pushes used): 40852349397 visual-diff success (label metrics differ 3 px between Linux engines); 40855407833 success (geometricPrecision did not help);
40858439757 success (head 07a9b1285, label slot 5.7em: the numbers in the note); lean 40852349320 success.
Finding: the cause is the known WebKit never-starts-padding-inline transition (ledger n=73); the snapshot original differs on WebKit too, so the fix is the existing
flag `nav:earn-logical` (accepted 2026-10-25, proved in Fw.Parts.NavEarnWebkit and NavEarnCurve, not in a preset). The default page still shows the mismatch: the lead decides on the preset.
Verified (MEASURED): Linux Chromium against Playwright WebKit, 17 times, exit and entry, 1280 and 390, faithful and logical (run 40858439757): 1280 logical within the Lean bound on
every frame (worst 163 of 256), faithful over it; 390 both arms over the absolute bound (78) on every frame because the settled frame already differs 121-124 px between
the Linux engines (logical worst 148, faithful entry 1338); Chromium faithful vs logical 0 px. macOS local debug (not a result): 390 logical worst 62, passes.
Open: the 390 bound is not met on the Linux pair (floor); a 390 judgement needs macOS WebKit (trajectory-probe frames lane, apple legs) or a floor-relative bound (new Lean rule);
no iPhone check; whether nav:earn-logical goes into a preset.
Done: Lean frameBound (NavEarnWebkit + golden row), packages/premise-tests/src/earn-frames.mjs, earn-frames-compare.mjs, test/earn-frames.test.mjs, a step in
.github/workflows/visual-diff.yml (shoot job, shard s0, artifacts earn-frames-<engine>; shoot filter gained @fw/premise-tests), Trigger.lean visual-diff input, triggers.jsonl,
results/nav-cta-webkit-match/summary.json, note research/notes/2026/10-2x-nav-cta-webkit-match.md, ledger note on n=73.
Read first: research/notes/2026/10-2x-nav-cta-webkit-match.md, then packages/premise-tests/src/earn-frames.mjs.
Round 2: earn frames step is dispatch-only (input earnframes), trigger row regenerated, local runs labelled debug, with-text column added to the note. No pushes in round 2.
Open follow-ups from review: padL vs curve golden; BAND from golden; per-width verdict; faithful-arm test assertion in earn-frames test.
