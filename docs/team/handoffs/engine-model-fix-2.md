# Handoff: engine-model-fix-2

State: round 2 on branch `worktree-wf_e748d0e8-1d8-1` (head: `git log -1`), on top of round 1 (60177601). CI branch
`ci/engine-model-fix-2` at 6bf5957; engine-premises run 39124427211 is read and recorded. No new CI run in round 2.

Done
- Round 2 (lead list 1-4), option (a) for item 1: the timer step ran the clock shim (clock-shim.js:38,59 run inside the
  driver's evaluate, run.mjs:108), not a Chromium timer task. Act is now `shimTimer` (golden id/act `shimTimer`),
  expected as an idle frame; all REFUTED/MEASURED timer claims withdrawn (ledger n=21 premise and note, chromiumAt,
  cr_idle_tick, cr_timer_names, note). `cr_extra_cells` now has 3 mismatches.
- Step sets: `Group` (table/extra), `crGrouped`/`wkGrouped`, `stepsOf`, `grouped_steps`; every golden step row has
  `group`. premise-verdict.mjs judges each set alone: rows `<engine>.<stage>` (table) and `<engine>.extra.<stage>`;
  a row without a known group throws. `cr_extra_verdicts` states the extra rows of run 39124427211.
- Re-run on run 39124427211 artifacts: all 8 Chromium / 4 WebKit table rows hold; extra rows hold except
  chromium.extra.paint (1 mismatch) and chromium.extra.raster (2), as cr_extra_verdicts says.
- `join_ne_union_iff`: over CrLevel.all, join stages exceed the union only for {layoutMove, raster} (decide).

Read first: the note's "Follow-up" section, then `Group`..`grouped_steps` and `cr_extra_verdicts` in
lean/Fw/Ops/EnginePremise.lean.

Conventions
- Recorded theorems stay on the table steps (`crSteps0`, `wkSteps0`); new runs get their own record and theorem.
- A new step set is a new `Group` constructor plus a GROUPS entry in premise-verdict.mjs (the test pins both).

Open items
- A Chromium timer step needs a native timer task (save the native setTimeout before the shim installs, then prove
  from Chromium source and the harness that it runs as its own task); until then the timer base rule is OPEN.
- No rule for Chromium incomparable levels: `layoutMove` with `raster` showed less work than join and union predict.
- Measure rewrite+?fw=morph.panel:rest (variant-regate) to lift n=11 from rest frames to the whole swipe.
- No agent tool was available to spawn the checker; docstrings were checked against the 6-point list by me.
