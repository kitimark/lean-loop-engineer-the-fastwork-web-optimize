branch: worktree-wf_676fdfb3-77c-1
worktree: .claude/worktrees/wf_676fdfb3-77c-1
last commit: 15e25d9dc (last code change; the handoff commit follows it on the branch)
CI runs: none new; re-read of 40203753344 (base), 40237508223, 40236516819, 40236472868, 40236462082 artifacts
verified: Lean module and golden build; JS twin replays golden; CLI reproduces the platform-attribution Chromium table
  (24 of 24 verdicts, 18 of 24 counter lists; see the research note)
open: six cells list different counters than the platform-attribution note (lead decides whether to edit that note);
  package.json test:run does not list the new test (it is imported from test/offscreen.test.mjs)

Read first: research/notes/2026/10-2x-chromium-window-reader.md, then lean/Fw/Measure/OffscreenWindows.lean.

What exists:
- lean/Fw/Measure/OffscreenWindows.lean: end frame, push windows, per-window verdict (reuses Offscreen judge).
- lean/Fw/Measure/OffscreenWindowsGolden.lean: synthetic cases; writes packages/contracts/golden/measure/offscreen-windows.jsonl.
- packages/measure-chromium/src/offscreen-windows.mjs (JS twin plus counts.json glue) and offscreen-windows-cli.mjs.
- packages/measure-chromium/test/offscreen-windows.test.mjs.
- check.sh job "offscreen-windows golden check"; Trigger.lean lean.yml row; triggers.jsonl regenerated from Lean.

Conventions:
- Windows: approach e-34..e, end 0-19, 20-59, 60-119, 120+ (to last), finish e-34..last; last = total - 30.
- `less` prints base min to flag max; `more` prints base max to flag min. Absent counter in a frame = 0.
- swipe-touch-v1 only. WebKit VM counting is offscreen-vm-count.

Regenerate the golden: `#eval Fw.Measure.OffscreenWindowsGolden.write "../packages/contracts/golden/measure/offscreen-windows.jsonl"` in a file importing it, run from lean/ with `lake env lean --stdin`.
Regenerate triggers: `cd lean && lake test -- --write-ci-trigger-golden`.
