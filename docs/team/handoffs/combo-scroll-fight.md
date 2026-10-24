branch: worktree-wf_98d6c3e4-107-1 (CI pushes go to ci/device-replay: the workflow only triggers on that name)
worktree: .claude/worktrees/wf_98d6c3e4-107-1 (under the main checkout)
last commit: see git log; push 4 (the last) follows this commit
CI runs: 40128362520 failed (build: morph.countdown:strip needs hero.countdown:strip); 40129128571 device-replay success (push 3: before/after, 6 legs, artifacts combo-<leg>); push 4 run id in the note once known
state: cause CONFIRMED (a reopen in a move the page cannot cancel pins at the scroll position and the frame writer then fights the native scroll; needs morph.end.release); fix = hold bit (Lean Fw.Parts.ComboScroll wstep, TS morph.tween/end.logic.ts moveStep/frameOut); golden packages/contracts/golden/parts/combo-scroll.jsonl replayed by apps/site/src/registry/combo-scroll.test.ts.
verified: run 40129128571 before vs after on user/end3/release arms: 12 of 16 passes had script writes before, 0 of 16 after; check.sh green, site tests, typecheck, ci-paths, land-inputs.
open: push 4 (harness start now instant + morph opens/closes column + per-arm summary), note research/notes/2026/10-2x-combo-scroll-fight.md, ledger row, review gate, dry land. Follow-ups: toolbar-resize fight at y ~1859 (separate), waapi drivers, faithful arm keeps the original pin fight.
read first: research/notes/2026/10-2x-combo-scroll-fight.md, lean/Fw/Parts/ComboScroll.lean, packages/measure-webkit/src/replay/combo-*.mjs.
