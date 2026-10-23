# people-title-crash-fix: handoff

Branch: worktree-wf_c7f678ea-d01-1 (CI branch ci/people-title-crash-fix)
Worktree: .claude/worktrees/wf_c7f678ea-d01-1
Last commit: see git log (work at 87a084d81, main merged)
CI runs: none yet (first push pending)

State: Lean `lean/Fw/Parts/PeopleOBlock.lean` (check.sh green, site tests 6498 pass) and flag `people.o:block`
(`apps/site/src/parts/people.o/{o.module.css,index.tsx,part.json}`), footprint and v2-proved decisions regenerated.
Probe `packages/measure-chromium/probes/people-title-crash.json` (copy to profiles/ on the ci branch only; remove before land).
Decision: option inline-block (as a block with declared width) because Lean proves the same box, stage, transition, line box and
position (baseline is not read for flex-start/center); `text-wrap: wrap` lives in people.card (outside this task's writes) and changes
breaks when the title wraps. Flag, not default: the faithful variant stays the restated original.
Open: gate (fw=people.o:block) both engines, visual-diff base vs flag on playwright-webkit, stock Chrome probe at 1280 with the flag.
