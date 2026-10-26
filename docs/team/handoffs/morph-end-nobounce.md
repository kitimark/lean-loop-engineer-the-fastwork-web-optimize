branch: worktree-wf_2ef78aa3-7da-1 (CI branch ci/morph-end-nobounce)
worktree: .claude/worktrees/wf_2ef78aa3-7da-1 (under the repo root)
last commit: 3c5ac115f (push 2 of 2 used; no more pushes)

Push 1 (1ccd16b69) failed in every `site` job: the build bans a prerendered <style> tag. Push 2 (3c5ac115f) delivers the rule through
styles/reset.css (`html:has([data-fw-nobounce]) { overscroll-behavior-y: none }`) and a `data-fw-nobounce` attribute on the page root.

CI runs at 3c5ac115f:
- breakpoint-gate both engines, fw=morph.end.nobounce:on: 40283431992 success
- chromium-counts swipe-touch-v1 rewrite 3 runs, flag: 40283424333; same-commit default: 40283428442; Lean reader
  offscreen-windows-cli.mjs: every window noGain, no metric differs (6 windows usable, end frame 574 on all 6 runs)
- toolbar-throttle (Simulator toolbar lane, 8 jobs of default + nobounce): running, run id from `gh run list --branch ci/morph-end-nobounce`
- lean (push): running
Failed push-1 runs (site build): 40282634661 toolbar, 40282669758 gate, 40282673015 and 40282681173 chromium.

Verified: Lean MorphEndNobounce.lean; golden morph-end-nobounce.jsonl; check.sh green at the first commit; apps/site test, measure-webkit test.
Open: read the toolbar lane, write research/notes/2026/10-2x-morph-end-nobounce.md, fill the ledger row, final check.sh, merge main, plan lint, dry land.
Not done: push-cycle replay (push-cycle-separate not landed; the lane has no flag arm; a push budget of 2 is used).
