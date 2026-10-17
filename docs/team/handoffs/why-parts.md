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

## Merge (why-parts-merge = this branch + main after why-engines)
- Only research/findings/ledger.json conflicted. Resolved by a field-level 3-way merge per finding (keyed by list
  position; n/part/candidate equal on all sides, since `n` repeats): a field one side changed takes that side;
  leanFor/leanAgainst/premises = union (no name dropped); missingWhy = items kept by both sides plus each side's
  additions (an item removed by either side counts as closed); a mechanism both extended = base + why-parts suffix +
  why-engines suffix (`why-engines:` labelled). missingWhy 61 base -> 21 closed here, 14 by why-engines (no overlap),
  8 new parts-level remainders from why-engines -> 34 open.
- Both-changed findings: n=3, n=4, n=7, n=8 (cd-roll-ca), n=16, n=20, n=24. No contradiction: they differ in measure
  (style passes vs units, layout moved vs pre-paint saved). why-parts closed none of the 8 new why-engines
  Fw.Parts remainders (n=4, 8, 11x2, 13, 16, 19, 20); they stay open.
- Semantic conflict: main's dangling-where lint failed on Fw.Parts.NavHitTestOpt.goldenRows (q defined after $$);
  q_n moved into the $$ block as a cases split. check.sh green; incidents lint 0 errors.
