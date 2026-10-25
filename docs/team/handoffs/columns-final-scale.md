Branch: worktree-wf_07d103dc-24e-1 (CI branch ci/columns-final-scale). Worktree: .claude/worktrees/wf_07d103dc-24e-1
Last commit: `git log -1` (main merged after the measurement runs). Code head measured: 6d8fbd72f. Pushes used: 2 of 3 (no push in this round).
CI runs: 40153993443 lean (failed, fixed); 40156382719 chromium base (success); 40156384878 chromium flag (success); 40156388674 webkit-sim base (r1, r3 ok, r2 VM lost, n=2); 40156393010 webkit-sim flag (same); 40156380619 breakpoint gate (failed, cause below).
Verified: counts and gate cause read from the run artifacts and logs, summarised in research/notes/2026/10-2x-columns-final-scale.md (Runs). Chromium and WebKit: no count win. Gate: only flex: none (flex-basis/grow/shrink) differs, desk-319 to desk-1000, nothing above 1000 px; intended look change judged as computed style.
Open: lead posts the look-review step (moot without a count win); follow-up for the lead: Lean-first gate rule for visClass L (declared changed property set, rest-rect equality still counts); layout attribution per subtree to learn why the Layout object count does not fall.

- Flag: `morph.columns:final-scale` (visClass L), layout at final width up to 1000 px, transform scale(sx,1) from --morph. TS stand-in: resize effect in index.tsx (DOM glue).
- Files outside task writes: lean/Fw.lean, lean/Fw/Ci/Trigger.lean (needs --allow), packages/contracts/golden/ci/triggers.jsonl, lean/scripts/check.sh, lean/scripts/MorphColumnsScaleGolden.lean, packages/contracts/golden/preset/look-change.candidates.jsonl.
- Read first: research/notes/2026/10-2x-columns-final-scale.md.
