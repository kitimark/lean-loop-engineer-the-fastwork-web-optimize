branch: worktree-wf_c1542959-5ca-1
worktree: .claude/worktrees/wf_c1542959-5ca-1
last commit: see `git log -1` on the branch (round 3: merge of main b38d582 with the review fixes)
CI runs: 40156078840 trajectory dispatch by the lead (complete, success; `?fw=hero.exit:threaded` at main fbca417)

State: delivered inside the graph writes.
- `lean/Fw/Preset/Gen.lean` `lookDecisions`: `hero.exit:threaded` accepted 2026-10-24, `hero.accent:draw-nolayout`
  rejected 2026-10-24; the `draw-nolayout-full` row of accent-look-refused is reused.
- Run 40156078840 recorded with `Fw.Preset.Gen.record` on top of main's file (main's 6 `hero:scene-pause` rows stay at
  lines 54-59, the 5 new rows follow at lines 60-64): hero fail
  on chromium, linux-webkit and mac-webkit; morph pass on chromium and mac-webkit. The verdict is `falsified: trajectory`.
- Entry decision `Gen.entry`: not yet. Blockers: proofs, gate chromium, gate webkit, q6. The evidence string names
  each run with its engine and outcome. Theorems: `threaded_not_yet`, `gate_blocked_of_own_fail`, `entry_enter_iff`,
  `entry_notYet_of_unmet`, `ok_of_enter`, `q6_open`.
- Ledger: the `hero-exit-threaded (v6, KD#2)` row gains `flag` and `userDecision`. There is one `visual` note per
  entry for this task (that row and throttle-lift), and the threaded note now cites run 40156078840.
- Report: `docs/report/v2-report.md` section 4.11, with the per-engine table of run 40156078840.

Verified: q6 evidence names `Fw.Engine.PathPremises.c3o`/`c3v`; report morph cells state 0 new and the undecided/red
counts. Gen.run regenerated the goldens after the record. check.sh and the package tests run through fw slot.
Open: the probe fails the hero path on all three engines, while the user saw the same look on the iPhone (hero card
opacity apart on every engine).
The inferred cause is the original's one-scroll-event lag, which is question q6 in task hero-exit-q6. The run's
summaries stay out of git because results/ is not in this task's writes; download them with `gh run download 40156078840`.
Read first: `Gen.entry`, `threadedEvidence`, `gate_blocked_of_own_fail`, then report section 4.11.
