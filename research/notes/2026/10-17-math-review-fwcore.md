---
title: Math review of the fwcore declarations (math view vs Lean)
date: 2026-10-17
status: CONFIRMED
---

# Math review of `lean/Fw` (fwcore) at 9367dea

`lean/` has not changed between 9367dea and ae0a06c. This review continues `10-17-math-review-fw-spec.md`, which
covered 72 declarations of the kickoff sketch. Reviewer: math-reviewer (read-only); the lead committed this record.

## Method
- Scope: every declaration the math view exports (`Fw.*`, not `Fw.Wire`) that is new, or whose docstring changed
  versus `research/kickoff/05-lean-sketch/Fw/Spec`. Cost, Flags, Stage and Verdict are byte-identical to the sketch
  and were not re-reviewed. Lease and Frames were checked by diff.
- For each declaration the reviewer wrote the math from the Lean body or statement first, then compared it clause by
  clause with the docstring's `$$` block. Checked: quantifiers and domains, every hypothesis, ≤ vs <, Nat floor
  division and ∸, empty lists, `find?` = first match, `erase` = first occurrence, fold order, Bool `= true`, and the
  direction of ⇒/⇔.
- Limits: sources were read directly. `lake build`/`mathview` was not run (read-only; a build writes `.lake/`), so
  autoTex was not used. Docstrings sit in the same files, so blinding was by discipline, not by stripping them.

## Counts (156 reviewed)
| Module | Reviewed | $$ math | English |
|---|---|---|---|
| Frames | 5 (tickAt, tickAt_120_us, tickAt_mono, tickAt60_ge2_iff, tick_ge5_iff English) | 5 agree | ok |
| Lease | 3 (quantifiers added: requeue_keeps_place, renew_never_shortens, release_fifo) | 3 agree | ok |
| Null | 24 | 24 agree | 5 disagree |
| Screen | 13 | 13 agree | ok |
| DeviceQueue | 23 | 23 agree | 1 disagree |
| ArtifactKey | 15 | 15 agree | ok |
| Console | 60 | 60 agree | 1 disagree |
| Board | 13 | 13 agree | ok |
| Total | 156 | 156 agree, 0 disagree | 7 disagree |

The theorem count matches the 93 reported by lean-core (Cost has 3; a grep hit at Cost.lean:95 is docstring prose).

## Disagreements (all in the English; the $$ math is right)
1. `Null.land_null_prob`, `null_prob_5v5`, `null_prob_3v3`: "with no real difference ... probability exactly 1/70"
   is stated unconditionally. Fix: "If the 8 values are distinct and every labeling is equally likely (the L3
   premise), a false 'better' has probability exactly 1/70; with ties it is at most 1/70 (`null_bound_4v4_5v5`)."
   Same for 1/252 and 1/20.
2. `Null.null_bound_4v4_5v5`: "(equality for the distinct ranks is `land_null_prob` …)", but those theorems are about
   `falseBetterProb`. No theorem says `pAt(⟨0..k−1⟩, m, n) = falseBetterProb(m, n)`, i.e.
   `sel f b (range k) = ranks f b`. It is true by inspection. Fix: add that lemma, or say "equals by inspection, not
   proved".
3. `Null.falseBetterProb` Edge: "|arr(m+n,n)| = C(m+n,n) ≥ 1 always" is true but unproved; only (6,3), (8,4) and
   (10,5) are evaluated. Fix: state it as unproved, or prove `arr_length` (see Gap B).
4. `Console.apply_idem`: the English adds "the second delivery is reported as a duplicate or with the same refusal".
   The theorem is about states only; the outcome claim is true but unproved. Fix: drop the clause, or add
   `(step (apply s e) e).2 = .accepted true ∨ (step (apply s e) e).2 = (step s e).2`.
5. `DeviceQueue.aged_beats_newer`: the headline "No starvation" claims more than the theorem. It is an aging lemma:
   it says nothing about older jobs, and `dispatch`'s `fits` filter can keep a job that fits no window waiting
   forever. Fix: "**Aging.** … (a key lemma, not starvation-freedom of `dispatch`)".

## What the Null results do and don't prove
- Proved: for any m, n and any v ∈ ℤ^{m+n} (ties allowed), `winsAt ≤ 1` and `pAt ≤ 1/|arr(m+n,n)|`. Also
  `pAt ≤ 1/70` (4v4) and `pAt ≤ 1/252` (5v5), because the lengths 70 and 252 are proved.
  `falseBetterProb = pNull` = 1/20, 1/70, 1/252 for 3v3, 4v4 and 5v5 only.
- Gap A (the module doc understates it): "exactly one winning labeling" holds only for the canonical ranks *and* only
  at (3,3), (4,4), (5,5), all by `decide`, not for general m, n. Fix in the `## With ties` section and the README:
  "proved only for the ranks 0..m+n−1 at 3v3, 4v4, 5v5".
- Gap B (new): the section heading, the module text "so … at most 1/C(m+n,n)" and the README "`pAt ≤ 1/C(m+n,n)`"
  rely on |arr(m+n,n)| = C(m+n,n), which is unproved for general m, n. The wire's `pNull` and `multiplicity` ops
  therefore have no proved bound outside 4v4 and 5v5 (3v3 is bounded through decide). Fix: write 1/|arr(m+n,n)| in
  these places, or prove `(arr k n).length = choose k n` (easiest through a Pascal-defined binomial).
- Gap (2), that exchangeable runs make every labeling equally likely, is stated honestly as the L3 modeling premise.

## Wording notes (math agrees; optional)
- Free variables in the LaTeX, read as ∀ (the same issue Review 2 of the sketch found in Lease): Null mem_sel,
  count_le_of_imp, eq_of_imp_count, exists_true_false, mem_arr (k, n), arr_nodup, pAt_le (m, n ∈ ℕ missing).
  Screen leRun_spec, screen_sound, screen_worse. DeviceQueue pickFrom_mem, pickFrom_min, pick_mem, pick_min,
  dispatch_sound, dispatch_conserving, tick_kills_at_end. ArtifactKey key_sound. Console step_seen, refused_keeps,
  reject_keeps, accepted_may, unauthorized_rejected, only_user_answers, landed_fact_accepted, mapCards_inv,
  built_resets, stale_mono, stale_live. Board landed_not_stale, running_not_stale, row_land_iff, needsYou_open.
- `Null.arr`: write "false :: arr(k,n)" as map(false :: ·, arr(k,n)).
- `Null.better_labeling_unique`: {0,1}^{|v|} → {false,true}^{|v|}.
- `Null.winsAt_le_one` English: "of the C(m+n,n) labelings" → "of the labelings in arr(m+n,n)" (Gap B).
- `DeviceQueue.tick`: add parentheses (t₀+dur(j) ≤ now ∨ e ≤ now). Either reading gives the same function.
- `Console.check` / `cardRefusal`: some rows elide their conditions ("step exists", "L; Σ;"); they match the rows
  above.

## Agreed ($$ math), 156
Frames: tickAt, tickAt_120_us, tickAt_mono, tickAt60_ge2_iff, tick_ge5_iff.
Lease: requeue_keeps_place, renew_never_shortens, release_fifo.
Null: arr, ranks, wins, falseBetterProb, choose, pNull, land_null_prob, null_prob_5v5, null_prob_3v3, multOk,
mult_4v4, sel, mem_sel, count_le_of_imp, eq_of_imp_count, exists_true_false, better_labeling_unique, mem_arr,
arr_nodup, winsAt, winsAt_le_one, pAt, pAt_le, null_bound_4v4_5v5.
Screen: Counts, Run, dot, cost, leVec, leRun, Result, shapeEq, screen, dot_mono, leRun_spec, screen_sound,
screen_worse.
DeviceQueue: Job, A, eff, before, before_total, before_trans, before_refl, pickFrom, pick, pickFrom_mem,
pickFrom_min, pick_mem, pick_min, aged_beats_newer, Phone, dispatchHoL, fits, dispatch, dispatch_busy,
dispatch_sound, dispatch_conserving, tick, tick_kills_at_end.
ArtifactKey: Input, Val, Artifact, key, update, stale_iff, stale, stale_spec, enc, dec, dec_enc, enc_inj, fields,
fields_inj, key_sound.
Console: Actor, Actor.name, StepKind, RunKind, StepStatus, StepStatus.name, StepStatus.isOpen, RunStatus, Card,
Step, Run, Body, EvType, EvType.name, Body.type, Event, State, mayList, may, ready, touch, cardRefusal, cardStep,
cardOf, mapCards, mapSteps, stepRefusal, check, accept, Outcome, step, apply, project, Stage, stage, stale,
step_seen, refused_keeps, reject_keeps, apply_idem, accepted_may, unauthorized_rejected, only_user_answers,
landed_fact_accepted, project_append, CardInv, Inv, touch_inv, cardStep_inv, mapCards_inv, inv_init, accept_inv,
apply_inv, project_inv, land_requires, landReq_ready, review_independent, built_resets, stale_mono, stale_live.
Board: staleMs, next, stepAction, NeedsYou, needs, BoardCard, boardCard, Board, board, landed_not_stale,
running_not_stale, row_land_iff, needsYou_open.
