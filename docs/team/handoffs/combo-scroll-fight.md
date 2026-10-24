branch: worktree-wf_98d6c3e4-107-1 (CI pushes go to ci/device-replay: the workflow only triggers on that name)
worktree: .claude/worktrees/wf_98d6c3e4-107-1 (under the main checkout)
last commit: see git log; push 4 (the last) follows this commit
CI runs: 40128362520 failed (build: morph.countdown:strip needs hero.countdown:strip); 40129128571 device-replay success (push 3: before/after, 6 legs, artifacts combo-<leg>); push 4: device-replay 40130709244 success at b557cd0a0 (artifacts combo-<leg>: before/after), lean 40130709158
state: cause CONFIRMED (a reopen in a move the page cannot cancel pins at the scroll position and the frame writer then fights the native scroll; needs morph.end.release); fix = hold bit (Lean Fw.Parts.ComboScroll wstep, TS morph.tween/end.logic.ts moveStep/frameOut); golden packages/contracts/golden/parts/combo-scroll.jsonl replayed by apps/site/src/registry/combo-scroll.test.ts.
verified: run 40130709244 (instant start): user's flags 11 of 16 replays fought before, 0 of 16 after; release alone 13 of 16 before; release-less arms 0; all release arms 0 after. Final checks: see the report.
open: review gate, dry land. Pushes used: 4 of 4 (the first went to ci/combo-scroll-fight, which the workflow ignores). Follow-ups: toolbar-resize fight at y ~1859 (separate), waapi drivers, faithful arm keeps the original pin fight.
read first: research/notes/2026/10-2x-combo-scroll-fight.md, lean/Fw/Parts/ComboScroll.lean, packages/measure-webkit/src/replay/combo-*.mjs.
workflow note: after run 40130709244 the combo job got needs [guard, replay] and max-parallel 1 (the Lean width table holds one job per workflow, land check land-overflow-widths); commands unchanged, that shape is unrun (all 4 pushes used).
