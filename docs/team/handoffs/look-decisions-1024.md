branch: worktree-wf_c1542959-5ca-1
worktree: .claude/worktrees/wf_c1542959-5ca-1
last commit: see `git log -1` on the branch (work commit 610cddfa0, then handoff and merge of main)
CI runs: none (no push; no dispatch)

State: delivered inside the graph writes.
- `lean/Fw/Preset/Gen.lean` `lookDecisions`: `hero.exit:threaded` accepted 2026-10-24, `hero.accent:draw-nolayout`
  rejected 2026-10-24 (both review `done`, no material); the `draw-nolayout-full` row of accent-look-refused is reused.
- `decisionKept` keeps any non-`kept` verdict on a registered flag (`decisionKept_of_settled`, `_of_rejected`,
  `_of_accepted`, `settled_of_decisionKept`).
- Entry decision: `EntryReq`, `entryReqs`, `reqMet`, `blockers`, `entry`, `q6Answer` (none = open). Theorems
  `entry_enter_iff`, `entry_notYet_of_unmet`, `ok_of_enter`, `q6_open`, `threaded_look_met`, `threaded_proofs_unmet`,
  `threaded_not_yet`. The decisions golden carries `entry` on the hero.exit:threaded row: not yet, blockers proofs,
  gate chromium, gate webkit, q6.
- Ledger: the `hero-exit-threaded (v6, KD#2)` row gains `flag` and `userDecision`; one `visual` note per entry
  (that row and engine.scroll:throttle-lift) for this task. The draw-nolayout userDecision is unchanged (reused).
- Report: `docs/report/v2-report.md` section 4.11 (decisions, phone numbers, entry table, preset delta none).

Verified: check.sh green (axiom check 0 failing), Gen.run --check up to date, @fw/contracts, @fw/console-api, @fw/site
tests, ci-paths, runner land-inputs.
Open: q6 has no recorded answer anywhere in the repo (searched research/, docs/, results/, review feedback); set
`Gen.q6Answer` to its source once answered. Trajectory gate rows for hero.exit:threaded are missing on both engines
(dispatch command in the report). A link in `Gen.linkTable` and a `proved` ledger row are needed for the proofs item.
Read first: `Gen.entry` and `threadedEvidence`, then section 4.11 of the report.
