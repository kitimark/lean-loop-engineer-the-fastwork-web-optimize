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

## Verdicts (parseable)

One row per declaration, generated by the lead from this record and `lake exe mathview` at 9367dea (lean/ unchanged
through c3f904b). `stmtHash` is mathview's statement hash; a different hash in a later export means the review is stale.
Rows marked "fw-spec review" are declarations byte-identical to the sketch, covered by `10-17-math-review-fw-spec.md`.

| Declaration | Verdict | stmtHash | Note |
|---|---|---|---|
| `Fw.Frames.tickAt` | agree | 9906956 |  |
| `Fw.Frames.tickAt_120_us` | agree | 340669113260178198 |  |
| `Fw.Frames.tickAt_mono` | agree | 15029885088810845927 |  |
| `Fw.Frames.tickAt60_ge2_iff` | agree | 4980845157517735669 |  |
| `Fw.Frames.tick_ge5_iff` | agree | 17808547414382358929 |  |
| `Fw.Lease.requeue_keeps_place` | agree | 16816686428849740674 |  |
| `Fw.Lease.renew_never_shortens` | agree | 11532715869426380806 |  |
| `Fw.Lease.release_fifo` | agree | 16833007519581390145 |  |
| `Fw.Null.arr` | agree | 2156174291 |  |
| `Fw.Null.ranks` | agree | 357802052 |  |
| `Fw.Null.wins` | agree | 9906956 |  |
| `Fw.Null.falseBetterProb` | disagree | 860301984 | Edge "|arr|=C(m+n,n)" unproved |
| `Fw.Null.choose` | agree | 9906956 |  |
| `Fw.Null.pNull` | agree | 860301984 |  |
| `Fw.Null.land_null_prob` | disagree | 7959650623826516976 | English: add distinct values + L3 premise |
| `Fw.Null.null_prob_5v5` | disagree | 18075036907877158627 | same as land_null_prob |
| `Fw.Null.null_prob_3v3` | disagree | 6489614198802959727 | same as land_null_prob |
| `Fw.Null.multOk` | agree | 779128612 |  |
| `Fw.Null.mult_4v4` | agree | 13281717278337209155 |  |
| `Fw.Null.sel` | agree | 1962648466 |  |
| `Fw.Null.mem_sel` | agree | 265976095466000211 |  |
| `Fw.Null.count_le_of_imp` | agree | 3203879953 |  |
| `Fw.Null.eq_of_imp_count` | agree | 1807836024 |  |
| `Fw.Null.exists_true_false` | agree | 3957103838 |  |
| `Fw.Null.better_labeling_unique` | agree | 16412428810120312908 |  |
| `Fw.Null.mem_arr` | agree | 5155449431602400388 |  |
| `Fw.Null.arr_nodup` | agree | 4314025201853021758 |  |
| `Fw.Null.winsAt` | agree | 4056716477 |  |
| `Fw.Null.winsAt_le_one` | agree | 13636951606155557958 |  |
| `Fw.Null.pAt` | agree | 466032021 |  |
| `Fw.Null.pAt_le` | agree | 15759822915449477623 |  |
| `Fw.Null.null_bound_4v4_5v5` | disagree | 13590118229325669411 | link pAt = falseBetterProb unproved |
| `Fw.Screen.Counts` | agree | 3931117990 |  |
| `Fw.Screen.Run` | agree | 3931117990 |  |
| `Fw.Screen.dot` | agree | 1487585882052653602 |  |
| `Fw.Screen.cost` | agree | 2821775390702982551 |  |
| `Fw.Screen.leVec` | agree | 3404251123261958087 |  |
| `Fw.Screen.leRun` | agree | 296069016519484562 |  |
| `Fw.Screen.Result` | agree | 3931117990 |  |
| `Fw.Screen.shapeEq` | agree | 296069016519484562 |  |
| `Fw.Screen.screen` | agree | 8590010153517848661 |  |
| `Fw.Screen.dot_mono` | agree | 6198807085049899700 |  |
| `Fw.Screen.leRun_spec` | agree | 4317423620043076293 |  |
| `Fw.Screen.screen_sound` | agree | 4893661066027004847 |  |
| `Fw.Screen.screen_worse` | agree | 4520597471776880158 |  |
| `Fw.DeviceQueue.Job` | agree | 3931117990 |  |
| `Fw.DeviceQueue.A` | agree | 421340980 |  |
| `Fw.DeviceQueue.eff` | agree | 10230672460258272730 |  |
| `Fw.DeviceQueue.before` | agree | 10482837440426051999 |  |
| `Fw.DeviceQueue.before_total` | agree | 14982916797613497830 |  |
| `Fw.DeviceQueue.before_trans` | agree | 11326935383363397694 |  |
| `Fw.DeviceQueue.before_refl` | agree | 1499504341171385974 |  |
| `Fw.DeviceQueue.pickFrom` | agree | 1696878009667371695 |  |
| `Fw.DeviceQueue.pick` | agree | 13057481506187592411 |  |
| `Fw.DeviceQueue.pickFrom_mem` | agree | 16251276072432502774 |  |
| `Fw.DeviceQueue.pickFrom_min` | agree | 13753620637482727604 |  |
| `Fw.DeviceQueue.pick_mem` | agree | 998680076973344239 |  |
| `Fw.DeviceQueue.pick_min` | agree | 3776949175604853632 |  |
| `Fw.DeviceQueue.aged_beats_newer` | disagree | 15459606977995552882 | "No starvation" overclaims; aging lemma |
| `Fw.DeviceQueue.Phone` | agree | 3931117990 |  |
| `Fw.DeviceQueue.dispatchHoL` | agree | 16832978777630894550 |  |
| `Fw.DeviceQueue.fits` | agree | 12665765667286608773 |  |
| `Fw.DeviceQueue.dispatch` | agree | 16832978777630894550 |  |
| `Fw.DeviceQueue.dispatch_busy` | agree | 5996288796174135247 |  |
| `Fw.DeviceQueue.dispatch_sound` | agree | 12218688316977063020 |  |
| `Fw.DeviceQueue.dispatch_conserving` | agree | 8192037010574851540 |  |
| `Fw.DeviceQueue.tick` | agree | 16832978777630894550 |  |
| `Fw.DeviceQueue.tick_kills_at_end` | agree | 6102650412667366667 |  |
| `Fw.ArtifactKey.Input` | agree | 3931117990 |  |
| `Fw.ArtifactKey.Val` | agree | 3931117990 |  |
| `Fw.ArtifactKey.Artifact` | agree | 3931117990 |  |
| `Fw.ArtifactKey.key` | agree | 16495432929422781827 |  |
| `Fw.ArtifactKey.update` | agree | 6394976648278173983 |  |
| `Fw.ArtifactKey.stale_iff` | agree | 8839363598463750151 |  |
| `Fw.ArtifactKey.stale` | agree | 5087041798046961134 |  |
| `Fw.ArtifactKey.stale_spec` | agree | 7310964024858838491 |  |
| `Fw.ArtifactKey.enc` | agree | 3192381862 |  |
| `Fw.ArtifactKey.dec` | agree | 54199525 |  |
| `Fw.ArtifactKey.dec_enc` | agree | 9304799820995388515 |  |
| `Fw.ArtifactKey.enc_inj` | agree | 14161140904087141416 |  |
| `Fw.ArtifactKey.fields` | agree | 2429457918599251949 |  |
| `Fw.ArtifactKey.fields_inj` | agree | 8551042355961202046 |  |
| `Fw.ArtifactKey.key_sound` | agree | 1180814373860987346 |  |
| `Fw.Console.Actor` | agree | 3931117990 |  |
| `Fw.Console.Actor.name` | agree | 4236979017643660544 |  |
| `Fw.Console.StepKind` | agree | 3931117990 |  |
| `Fw.Console.RunKind` | agree | 3931117990 |  |
| `Fw.Console.StepStatus` | agree | 3931117990 |  |
| `Fw.Console.StepStatus.name` | agree | 908057620857126368 |  |
| `Fw.Console.StepStatus.isOpen` | agree | 3740692994265680298 |  |
| `Fw.Console.RunStatus` | agree | 3931117990 |  |
| `Fw.Console.Card` | agree | 3931117990 |  |
| `Fw.Console.Step` | agree | 3931117990 |  |
| `Fw.Console.Run` | agree | 3931117990 |  |
| `Fw.Console.Body` | agree | 3931117990 |  |
| `Fw.Console.EvType` | agree | 3931117990 |  |
| `Fw.Console.EvType.name` | agree | 16522585071708160181 |  |
| `Fw.Console.Body.type` | agree | 12269600272230389826 |  |
| `Fw.Console.Event` | agree | 3931117990 |  |
| `Fw.Console.State` | agree | 3931117990 |  |
| `Fw.Console.mayList` | agree | 9429006674815212559 |  |
| `Fw.Console.may` | agree | 793693537858079497 |  |
| `Fw.Console.ready` | agree | 8618850859136216168 |  |
| `Fw.Console.touch` | agree | 7150041366363367621 |  |
| `Fw.Console.cardRefusal` | agree | 8236380120697394169 |  |
| `Fw.Console.cardStep` | agree | 16647411640621106511 |  |
| `Fw.Console.cardOf` | agree | 17169019999699888105 |  |
| `Fw.Console.mapCards` | agree | 3092080940455074001 |  |
| `Fw.Console.mapSteps` | agree | 1064049945598828754 |  |
| `Fw.Console.stepRefusal` | agree | 7124550042045566906 |  |
| `Fw.Console.check` | agree | 15525871426033652860 |  |
| `Fw.Console.accept` | agree | 7445676242733002620 |  |
| `Fw.Console.Outcome` | agree | 3931117990 |  |
| `Fw.Console.step` | agree | 853485501465248946 |  |
| `Fw.Console.apply` | agree | 7445676242733002620 |  |
| `Fw.Console.project` | agree | 1688358852754568032 |  |
| `Fw.Console.Stage` | agree | 3931117990 |  |
| `Fw.Console.stage` | agree | 14867802963673984221 |  |
| `Fw.Console.stale` | agree | 13740217760088569609 |  |
| `Fw.Console.step_seen` | agree | 14915868186065857208 |  |
| `Fw.Console.refused_keeps` | agree | 17583266435552637075 |  |
| `Fw.Console.reject_keeps` | agree | 2648021860265739531 |  |
| `Fw.Console.apply_idem` | disagree | 3457108694390581116 | English claims the outcome; only the state is proved |
| `Fw.Console.accepted_may` | agree | 3788779216404152911 |  |
| `Fw.Console.unauthorized_rejected` | agree | 7476724112126248501 |  |
| `Fw.Console.only_user_answers` | agree | 16272176427751620566 |  |
| `Fw.Console.landed_fact_accepted` | agree | 7264281319390737123 |  |
| `Fw.Console.project_append` | agree | 7747409617618887339 |  |
| `Fw.Console.CardInv` | agree | 16196636504166953969 |  |
| `Fw.Console.Inv` | agree | 16318709459258729739 |  |
| `Fw.Console.touch_inv` | agree | 13975287979603891115 |  |
| `Fw.Console.cardStep_inv` | agree | 23421886666465752 |  |
| `Fw.Console.mapCards_inv` | agree | 16293827612537708154 |  |
| `Fw.Console.inv_init` | agree | 8603671072214533227 |  |
| `Fw.Console.accept_inv` | agree | 6693087585866354203 |  |
| `Fw.Console.apply_inv` | agree | 6790945493301593466 |  |
| `Fw.Console.project_inv` | agree | 4858353583979154964 |  |
| `Fw.Console.land_requires` | agree | 17207673567451833543 |  |
| `Fw.Console.landReq_ready` | agree | 8287143498129087046 |  |
| `Fw.Console.review_independent` | agree | 10611440595662392748 |  |
| `Fw.Console.built_resets` | agree | 11911687894591051117 |  |
| `Fw.Console.stale_mono` | agree | 3129061074166289019 |  |
| `Fw.Console.stale_live` | agree | 15962886855132078421 |  |
| `Fw.Console.staleMs` | agree | 421340980 |  |
| `Fw.Console.next` | agree | 9161328591552871020 |  |
| `Fw.Console.stepAction` | agree | 11721541215856321128 |  |
| `Fw.Console.NeedsYou` | agree | 3931117990 |  |
| `Fw.Console.needs` | agree | 892457763929437669 |  |
| `Fw.Console.BoardCard` | agree | 3931117990 |  |
| `Fw.Console.boardCard` | agree | 910454699975192097 |  |
| `Fw.Console.Board` | agree | 3931117990 |  |
| `Fw.Console.board` | agree | 18164736976520485792 |  |
| `Fw.Console.landed_not_stale` | agree | 7533175139842912656 |  |
| `Fw.Console.running_not_stale` | agree | 15847615884454301378 |  |
| `Fw.Console.row_land_iff` | agree | 5531654149564628976 |  |
| `Fw.Console.needsYou_open` | agree | 7477213801324521095 |  |
| `Fw.Cost.Work` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.CompWork` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.UnitCost` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.Work.le` | agree | 15688347165246218563 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.mainUs` | agree | 1006983463416959682 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.mainUs_mono` | agree | 7640927096249106378 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.Frame` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.compositorOnly_same_main` | agree | 1695255401883868189 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.onTime` | agree | 16352575833336500171 | unchanged from the sketch; fw-spec review |
| `Fw.Cost.onTime_of_le` | agree | 3151598026436177714 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Part` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Part.all` | agree | 6534359109927213873 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Part.mem_all` | agree | 8061654892025063640 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Variant` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Config` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Rule` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Rule.holds` | agree | 5305813276293511872 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Registry` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.Config.ok` | agree | 5267265243250278066 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.defaults` | agree | 1018580093605231237 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.override` | agree | 6846819683931839330 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.resolve` | agree | 2390536876719709841 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.resolve.check` | agree | 12789841647039819085 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.resolve_sound` | agree | 18405045438012829514 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.diff` | agree | 8979959907134457077 | unchanged from the sketch; fw-spec review |
| `Fw.Flags.override_diff` | agree | 15610252728745241236 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.tick` | agree | 2546708756 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.tick_ge7_iff` | agree | 14775492709290641977 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.tick_mono` | agree | 8540657410495091322 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.countAbove` | agree | 536311525 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.countAbove_antitone` | agree | 10765457812830221029 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.tick5_eq_countAbove` | agree | 515561235601517241 | unchanged from the sketch; fw-spec review |
| `Fw.Frames.countAbove34_sub_tick5` | agree | 13528625481791266076 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.Owner` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.Lease` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.State` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.Cmd` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.Reply` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.promote` | agree | 6910776561756269798 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.step` | agree | 11191959094519035431 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.Inv` | agree | 1991170135498497022 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.inv_init` | agree | 9753072084603072938 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.promote_inv` | agree | 6493420316181985183 | unchanged from the sketch; fw-spec review |
| `Fw.Lease.step_inv` | agree | 12195134911330661036 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Stage` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Stage.idx` | agree | 12403792711535391926 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Stage.next` | agree | 16817444879908134725 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Attribution` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Role` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Card` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.gateOk` | agree | 7404832376311082871 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.Topic` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.advance` | agree | 4799925100763589475 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.advance_one` | agree | 18097674385251243667 | unchanged from the sketch; fw-spec review |
| `Fw.Stage.enter_F` | agree | 13913524606191841395 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.Dir` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.Verdict` | agree | 3931117990 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.below` | agree | 1012569840 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.minRuns` | agree | 421340980 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.verdict` | agree | 5375120254389847728 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.below_spec` | agree | 9196443680782924005 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.better_sound` | agree | 9064569543793763486 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.better_needs_runs` | agree | 1230331855713331017 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.below_antisymm` | agree | 14736305800455809597 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.swap_better` | agree | 437448802551005207 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.below_neg` | agree | 15921591590230619641 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.verdict_higher_eq_lower_neg` | agree | 1979148451827388441 | unchanged from the sketch; fw-spec review |
| `Fw.Verdict.better_sound_higher` | agree | 8799349358806521901 | unchanged from the sketch; fw-spec review |
