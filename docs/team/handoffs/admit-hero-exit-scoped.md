# admit-hero-exit-scoped handoff

State: branch `worktree-wf_e1d953e4-5eb-1`, last commit in the report. No CI dispatch, no push.
Read first: `docs/team/tools/trajectory-probe.md` (Admission), `lean/Fw/Preset/V2Proved.lean` (`tcell`, `trajWhy`).

Done
- Re-reduced runs 39448209903, 39452631146 (071906af, `?fw=hero.exit:scoped`), 39456741492 (071906af, A/A
  `?fw=hero.exit:faithful`), 39466179818 (45a40e7b, scoped), 39472217441 (45a40e7b, A/A) with the landed judge
  (`cli.mjs summary` on each raw file) and recorded all five with `Fw.Preset.Gen.record` (25 stored lines).
- Lean outcomes: hero pass on chromium, linux-webkit and mac-webkit in all five runs; chromium morph pass in all five;
  linux-webkit morph no verdict: coverage (071906af runs); mac-webkit morph fail in 39466179818 (scoped) and in
  39472217441 (A/A). The 071906af runs walked mac hero only.
- `Fw.Preset.Gen.linkTable`: `hero.exit:scoped` linked to row hero.exit.scoped.inline (status proved), key `k6i`.
- Ledger: `fResult` model-bug removed from row hero.exit.scoped.falsified (the bug was on the hero path, which now passes
  everywhere); `next` updated on rows hero.exit.scoped, hero.exit.scoped.falsified, hero.exit.scoped.inline.
- `Gen.run`: v2-proved stays empty. Decision row: why proved, trajectory `falsified: trajectory`, the webkit morph cell
  fails on flag-alone run 39466179818 (content new `nav.background-color` at 390, 640, 641, 1280).

Open
- The A/A run fails the same cell on the same node property (bg at 390, 1280; earn.max-width at 390, 1280). `tcell` takes
  a flag-alone fail first (`tcell_own_fail`), so no new run can pass the cell while 39466179818 is stored. Settling it
  needs a lead decision on an A/A-relative rule for the mac morph cell (not done: the judge is not widened here).
- Same failure class as preset run 39453181962: close@0 where `is-morphing` is removed (trajectory-transition-window).
- `docs/team/tools/trajectory-probe.md` has no row for these runs (outside this task's writes).

Conventions: the Bash hook refuses compound shell and `git -C`; put loops in scratch scripts. The ledger is checked
byte for byte by `apps/runner/test/ledger-merge.test.ts` (keep `": "` after each key).
