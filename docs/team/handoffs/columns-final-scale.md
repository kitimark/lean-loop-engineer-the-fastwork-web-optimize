Branch: worktree-wf_07d103dc-24e-1 (CI branch ci/columns-final-scale). Worktree: .claude/worktrees/wf_07d103dc-24e-1
Last commit: see `git log -1`. Code head measured: 6d8fbd72f (main merged after the measurement runs). Pushes used: 2 of 3 (no push in this round). Round 2 (final): corrected per review round 1 (per-zone WebKit table, 314 px limit); no code change, no push.
Verified: counts and gate cause read from the run artifacts and logs, summarised in research/notes/2026/10-2x-columns-final-scale.md (Runs). Chromium and WebKit: no count win. Gate: only flex: none (flex-basis/grow/shrink) differs, desk-319 to desk-1000, nothing above 1000 px; intended look change judged as computed style.
Open: no look-review step (no count win); follow-up for the lead: Lean-first gate rule for visClass L (declared changed property set, rest-rect equality still counts); layout attribution per subtree to learn why the Layout object count does not fall.

- Flag: `morph.columns:final-scale` (visClass L), layout at final width up to 1000 px, transform scale(sx,1) from --morph. TS stand-in: resize effect in index.tsx (DOM glue).
- Read first: research/notes/2026/10-2x-columns-final-scale.md.
