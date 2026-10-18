# Handoff: engine-model-fix-2

State: branch `worktree-wf_a1287381-4b7-2` (head: `git log -1`). CI branch `ci/engine-model-fix-2` at 6bf5957;
engine-premises run 39124427211 is read and recorded.

Done
- Salvage ffb08e3 (`worktree-wf_b37180a7-494-2`): nothing copied. Its engine work landed with engine-model-fix
  (898c416, d25f3199). The 3 remaining diffs: a Chromium docstring that says "scale on own layer ppFull" (refuted by
  run 39088367495), another wording of `CrLevel.max`, and a `Parts/Golden.lean` main that EngineGoldens replaces.
- `Fw.Parts.MorphPanelOpt.wk_cross_claim`, `wk_cross_le`, `wk_cross_resident`: in the model, WebKit dominance over a
  whole rest/toggle/fade swipe. The ledger (n=11) still claims rest frames only until the variant is measured.
- check.sh stage "engine goldens check" runs `lean/scripts/EngineGoldens.lean`: each of the 12 golden/engine/*.jsonl
  must equal its Lean generator, and a file without a generator fails. `--write` regenerates the files.
- Engine-premises fixture: a `timer` act, `more` (extra boxes `e<step>_<j>`), 7 Chromium and 3 WebKit extra steps.
  Results: `Fw.Ops.EnginePremise.cr_extra_cells` (exactly 5 mismatches: the timer frame shows no script and no props;
  the top+scale join shows no paint and no raster; top@own+scale@own shows no raster) and `wk_extra_holds`.
  Write-up: research/notes/2026/10-18-engine-premises.md, "Follow-up".
- The lane rules in `Fw.Ops.Premise` are now stated on the table steps. Docstrings of `CrLevel.max`, `chromiumAt` and
  `PainNotes.cr_idle_tick` name the refutation. Ledger n=21 has a note and a premise.

Read first: the note's "Follow-up" section, then `cr_extra_cells` in lean/Fw/Ops/EnginePremise.lean.

Conventions
- Recorded theorems stay on the table steps (`crSteps0`, `wkSteps0`); new runs get their own record and theorem.
- `stepRow` emits `more` only when it is non-empty, so old golden rows stay byte-identical.

Open items
- The model does not split rAF callbacks from timer callbacks. A timer-only frame is over-counted (PrePaint), and the
  script counters do not see the empty timer callback.
- No rule for Chromium incomparable levels: `layoutMove` with `raster` showed less work than both the join and the
  union predict. The mechanism is untested.
- Measure rewrite+?fw=morph.panel:rest (variant-regate) to lift n=11 from rest frames to the whole swipe.
- No agent tool was available to spawn the checker, so the docstrings were reviewed against the 6-point list by me.
