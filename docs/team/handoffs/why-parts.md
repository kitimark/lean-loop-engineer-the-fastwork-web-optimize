# why-parts (lean-prover) handoff

State: branch worktree-agent-af93a122a80a92130, commits 07b01a9..(this commit) on top of main 2a3bc0d.
- Parts migrated to `frameWorkE` via lean/Fw/Parts/EndFlags.lean (frameE_le_of_total, frameWorkE_eq_of_dirty,
  touched_of_le_same_forced, frameE_*_mono); every old `frameWork` theorem is kept, the E versions sit beside it.
- Verdict changes under frameWorkE: EngineScroll batching can be worse by 1 (total_batch_worse_iff,
  batch_worse_example; refutes the n=22 "never more" claim; n=1 stays no-win). PeopleCard forced-read margin 2 -> 1
  (gate_forced_marginE vs gate_forced_margin_old), still strict; style ties when the frame dirties style
  (gate_forced_tieE). All other parts unchanged (NavHitTestOpt, PainNotes, MorphMountOpt, read-free parts).
- NavHitTestOpt: swipe-v1 hit-skip golden rows corrected to =o (hitSkip_eq_orig); toggle_noop closes n=5.
- Golden.lean: forcedCounts/forcedCountsBatched rows are forced-only; pilot batched total style is 2/1, not 1/0
  (pilot_batched_rows_forced_only). Generated output unchanged (diffed); no row kind added because
  packages/contracts/golden/parts and apps/site are outside this task's writes.
- Ledger: 21 of 40 Fw.Parts missingWhy closed (4 via Fw.Engine.claim_ne_dominates_of_layers with the layer
  premise added to `premises`), 2 partial (n=21 magnitude: ticksIn bound + WebKit cite; n=18 FLIP: PeopleO model),
  17 open (engine models, cites, new modules: see each entry's `needs`). Names are fully qualified.

Conventions: ledger edited by Python script (indent 1, ensure_ascii False, no trailing newline); closed entries
are removed from missingWhy and the theorem names added to leanFor/leanAgainst; partial ones get
`needs: "PROVED X; remaining: ..."`. Edits kept inside existing files (integrate-ports renames
PeopleCard/PeopleDeck/PainNotes/HeroAccent to *Opt).

Open items for the lead:
- check.sh fails only at mathview lint on Fw.Measure.SelfCheck.maxDiff_zero_iff (dangling-where), present on main;
  build, test, wire replay and breakgen are green.
- Add a `totalCounts` row kind (EngineScroll.total) to engine.scroll.spec.jsonl and apps/site engine.scroll logic.
- Fw.Engine.Lessons are still stated over frameWork; Fw.Engine.* missingWhy were out of scope.

Read first: lean/Fw/Parts/EndFlags.lean, PeopleCard.lean section EndPass, EngineScroll.lean section "Total passes".
