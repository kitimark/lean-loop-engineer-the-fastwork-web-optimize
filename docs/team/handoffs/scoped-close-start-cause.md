# Handoff: scoped-close-start-cause (round 3, final design round)
State: branch `worktree-wf_da1a1d10-06c-1`, content commit bafd7523 (the handoff is the commit after it). Not pushed to
`ci/scoped-close-start-cause` (the lead's 10 queued runs sit on its head).
Decision: none of (a), (b), (c) is taken. (b) is refuted for the judge as written; (a) waits on B; (c) is excluded at
equal m_prev (start = bgRed(m_prev) in every arm); whether scoped shifts m_prev is B. Judge (`Trajectory.lean`) and parts unchanged.
Claims, each on its own (note `research/notes/2026/10-21-scoped-close-start-cause.md`):
- Identity: close-start red = `bgRed(m_prev)`, 240/240 cells within 0.38. Lean `closeStartOk` in `HeroExitCloseStart.lean`
  with `closeStartOk_self`, `closeStartOk_rejects_target` (bgRed m < 254.5), `_rejects_below`, `_rejects_above`, golden list
  `closeStartCases`. `closegap.mjs` check 3 = this rule per cell; full output of 39466179818, 39472217441, 39508414669,
  39508421419 in `research/notes/2026/10-21-scoped-close-start-cause.closegap-output.txt`.
- Tolerance 0.5: sample j reads the before-change style at progress 0 (fresh runs red_j = red_i within 0.001, 120/120;
  the stored runs differ by up to 0.33, so "240/240" is NOT true and is not claimed); 0.11 is m quantisation; stored
  excess to 0.38 unexplained.
- Perf INFERRED: fresh flag-alone p 0.12 is the confirmatory number; pooled 0.013 includes the hypothesis run; 390 is high
  in A/A too (block table in the note); close-phase frame intervals equal within each run; reader-write cause dropped.
- Earn INFERRED g-driven with exceptions; all 120 fresh cells listed in the note (max-width 33.7 px at g 43 and g 154).
- LAG and checks 1-2 are superseded by check 3 (code kept, pinned by the test, not claims).
Deviations: pooled p is now file-order independent (blocks sorted), so it reads 0.0126 / 0.0202 (was 0.011 / 0.019).
Verified: `sh lean/scripts/check.sh` green; gate-breakpoints 435/435, 0 skipped; ci-paths 49/49; runner land-inputs 55/55.
Ledger (the lead edits): `hero.exit.scoped.inline`: "pending B (perf) and C (earn start rule)".
Open: B run-level permutation on 5 vs 5 fresh runs at one headSha; C earn close-start rule; A identity judge rule (after
B and C; add m_i > cut and m_j <= cut checks against `Fw.Parts.Nav.morphingCut`).
Writes: lean/Fw/Parts/HeroExitCloseStart.lean, packages/gate-breakpoints/{src/trajectory/closegap.mjs,test/closegap.test.mjs},
the note, the output file, this handoff. No work-graph edit.
Read first: the note, then `HeroExitCloseStart.lean` (closeStartOk), then the output file.
