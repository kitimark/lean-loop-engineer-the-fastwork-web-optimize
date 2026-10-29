Branch: worktree-wf_1f25b75f-c5b-1 (CI ref ci/nav-cta-webkit-match). Worktree: .claude/worktrees/wf_1f25b75f-c5b-1. Last sha: `git log -1`.
CI runs: 40852349397 visual-diff (push 1 of 3, head 2ae7abb96) in progress; 40852349320 lean success.
Finding (MEASURED locally, Playwright WebKit 27.2 vs Chrome 155, real built site and snapshot original): the cause is already known and already has a flag.
The faithful rule (and the unmodified snapshot) lists `padding-inline`; WebKit never starts that transition (ledger n=73, Styleable.cpp:553-566@862f17d), so the
earn side padding snaps 0 -> 24 px in the flip frame and the language button jumps 48 px. `nav:earn-logical` (listed longhands) eases it like Chromium; accepted by
the user 2026-10-25, but not in a preset, so the default page still shows the mismatch.
Done: Lean frame bound (NavEarnWebkit frameThreshold 40, framePermille 2, frameAllowed, golden row frameBound); packages/premise-tests/src/earn-frames.mjs (capture:
real nav.module.css + site font, hero-pill flip, every animation seeked to t, exit and entry, 1280 and 390, faithful and logical, 17 times, text-hidden screenshots
for the verdict) and earn-frames-compare.mjs (Chromium vs WebKit per frame; Chromium faithful vs logical); test/earn-frames.test.mjs; a step in visual-diff.yml shoot
job (shard s0 only) uploading artifact earn-frames-<engine>.
Open: read the artifacts of run 40852349397 (gh run download -n earn-frames-chromium / earn-frames-playwright-webkit), run the compare, note, ledger, checks, dry land.
Read first: packages/premise-tests/src/earn-frames.mjs, then research/notes/2026/10-2x-nav-cta-webkit-match.md (once written).
