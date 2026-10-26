branch: worktree-wf_ffa8b2be-91c-1 (CI branch ci/platform-attribution, pushed 063b150fb, 86b876ba4; no more pushes needed)
worktree: .claude/worktrees/wf_ffa8b2be-91c-1
last commit: see `git log -1`
state: all CI runs finished and read; note, ledger notes, tests, check.sh green; main merged (Trigger.lean and triggers.jsonl: main's side plus the offscreen-webkit.jsonl path, golden regenerated from Lean).

CI runs: Chromium base 40203753344, sweep 40237508223, glint 40236516819, entries 40236472868, marquee 40236462082 (success).
WebKit sim: base 40203774734 (r2, r3) + 40236531932 (r1); sweep 40237513521, glint 40236465002 (3 VMs); entries 40236534457 (r1 lost, 2 VMs); marquee 40236475717 (r3 lost, 2 VMs).

result: research/notes/2026/10-2x-platform-attribution.md (answer first). Ledger notes on findings 70, 71, 25 (task platform-attribution).
verified: Lean probe class + WebKit zone verdict goldens (check.sh green), measure-webkit, site, runner tests green; land.ts reads declared (apps/site probes.jsonl, measure-webkit offscreen.mjs).
open: none for the unit; step-2 variants (sweep first, glint approach-bounded, entries after a 3-VM rerun) are later tasks; phone pass belongs to phone-compose-counts.
scratch: scratchpad/pat/ (wk/ holds downloaded artifacts, log/wk.md the WebKit table).
