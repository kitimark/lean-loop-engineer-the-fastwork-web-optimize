# Fable: can per-part optimization run in parallel now? (2026-10-19 08:25 +0700)

Read: research/findings/ledger.json (48 rows), lego plan §D-§G, work-graph M5 rows, model-checks handoff,
contracts.gen.json (34 parts: g1 10, g2 14, g4 engine.scroll, 9 solo; pageLevel = engine.scroll, morph.tween),
Fw/Engine/Compose.lean (frame_le_append_units, someLt_append_units, passes_not_compositional, lego_swap_*),
ci-inventory.md, `gh run list` (refreeze 39184638066 counts done/classify queued, 39184646781 queued, gate 39184687325
running, 2 gates queued for ci/morph-tween-inherit). Mac load 35-50 on 8 cores.

## Answer for the user (5 bullets)
- Yes for Lean and TS: proofs for the ~20 partly/not-proved rows and the TS variants for proved flags touch disjoint
  files per part, need no CI, and can all start now (one lane per part or contract group). The refreeze blocks none of it.
- No for verdicts: every measured win/no-win is "variant vs frozen base". The base is being refrozen right now
  (content changed PaintImage/DecodeImage); anything dispatched before it finishes queues behind it on the 20-job pool
  and compares to a stale base. Earliest verdict dispatch ~10:00.
- Measurement after 10:00 is parallel but queue-bound: 3 counts dispatches at once (27 jobs) take ~10-12 min a batch;
  the 6 flags worth measuring fit in 2 batches (~25 min). One combined run per profile covers only the units-type wins
  of parts in different groups (Compose: units add, passes do not).
- Never parallel: engine.scroll (batched) and morph.tween (waapi) are page-level by Contract, plus every passes-type
  win (hidden-pause x3, panel rest, hit-skip): these are judged only on the whole page, in the wave-2 run.
- Worth it: nav.hitTest elements-skip/hit-skip, hero.countdown hidden-skip, morph.tween waapi (after the inherits fix),
  people.card shrink, morph.panel rest, commission forced-layout. Skip the 11 no-win and 12 trade rows: record them as
  findings with their cheap "why" lemma, no variants, no runs.

## A. Lean-only, parallel now (no CI, one lane per file owner)
| lane | parts / rows | writes (disjoint) | deliverable |
|---|---|---|---|
| L1 nav-hittest-lean | n3 hitSkip_eq_of_morph_le, n5 no-op toggle | lean/Fw/Parts/NavHitTestOpt.lean, nav-hittest.jsonl | 2 theorems + regenerated golden |
| L2 countdown-lean | n8 spring partition (#guard), fixed-cadence E-s, drift/aimed-chain | HeroCountdownOpt.lean, HeroCountdown.lean | closes n8 roll-ca (partly) and clock-aligned (finding) |
| L3 commission-lean | n22 total-pass lemma; union-passes stays in Compose (owner compose-lean) | CommissionTyping.lean | n22 partly -> proved; unblocks T3 |
| L4 accent-lean | n15 E sub-variant via HiddenPause, ramp_vis | HeroAccentOpt.lean, HeroAccent.lean | wipe-E proved or refuted |
| L5 people-lean | n16 still-tail scenario spec, n17 work-only, n18 flip_work_lt, n19 alpha999/st6 work-only | PeopleCardOpt.lean, PeopleCarousel.lean, PeopleO.lean | proposals (L) get their theorem, flags stay off |
| L6 webkit-rules | Resident transitions, effect-stack, size-container interleave, contents kind (n11,n12,n14,n17,n20) | lean/Fw/Engine/WebKit.lean only | one owner for the shared table; part lanes cite it |
| L7 scene-lean | n25 no-oscillation, unhide-frame, toggle-frame | HiddenPause.lean | model-only; measured in wave 2 |
| running | model-bug-fixes waits for the refrozen rewrite classes (D); morph-tween-inherit (MorphTweenOpt) | Chromium.lean, Keys.lean / MorphTweenOpt | unchanged |
Ledger rows: each lane appends its own rows (merge driver); never edit another lane's row. Do not start trade/no-win
lanes (n6 raster_path, n10 rigidity, n23 band_eq_bgpos, n24 glint_translate): report "modelled, not proved" per §F.

## B. TS variants, parallel now where files are disjoint
| lane | flag | writes | note |
|---|---|---|---|
| running proved-flags-ts | n16 people.card:shrink, n21 pain.notes:arm, n5 (no-win, drop) | parts/people.card, pain.notes variant files + part.json, Fw/Preset/Gen.lean, golden/preset | n8 clock, n15 steps already out |
| running panel-rest-n11 | n11 morph.panel:rest | parts/platform, morph.panel, Gen.lean | after morph-tween-inherit |
| T3 commission-variant | n22 commission.typing forced-layout (mqGate/roLineCount/writeOnChange) | parts/commission.typing/** | after L3; golden from Lean |
| T4 countdown-hidden | n8 hidden-skip (variant-hidden-pause row, ev 726cc17b) | parts/hero.countdown/** | after L2 if the golden changes, else now |
Blocked on files: anything under morph.* , nav/index.tsx, App.tsx, overlays (morph-group-integrate round 2) and
morph.tween/** (morph-tween-inherit). people.* and hero.* content lanes are integrated, so their part folders are free.

## C. CI measurement per flag (after the refreeze; free pool, 20 Linux jobs)
| option | jobs | wall (idle pool) | what it decides | cost / blocker |
|---|---|---|---|---|
| C1 one whole-page run per flag (rewrite, 3 runs, image_run reused) | 9 per flag; 3 at once = 27 | 7.5 min alone; 10-12 min per batch of 3; 6 flags = 2 batches ~25 min | F3/F4 per flag vs frozen base, any win type | no edit; 13 at once queued 39-50 min, so cap 3 |
| C2 flag matrix in one dispatch (shared setup) | 6 + 3 x flags; 6 flags = 24 | ~15 min | same as C1 | edits chromium-counts.yml + Keys goldenRuns: same file as counts-only, ~2 h + a land; not before C3 |
| C3' one combined run per profile (v2-proved + new flags) | 9 per profile, 2 profiles = 18 | 8-10 min | per-part attribution only for units wins (elements-skip hits, waapi rAF, pain arm, strip layers, shrink script) of parts in distinct groups or solo (frame_le_append_units, someLt_append_units); passes wins absorbed | already planned for wave 2 |
| gate (once per wave) | ~10 | 16 min idle, p90 52 | boxes/visual both engines | 2 gates only |
Recommend C1 for people.card shrink (g1), morph.panel rest and hidden-skip (passes), nav elements-skip re-run on the
new base; C3' for the rest in wave 2. C2 only if counts-only's owner folds it into the same yml edit.

## D. Must wait for the wave-1 refreeze (~09:30-10:00)
All F3/F4 verdicts (every C row), model-bug-fixes re-judge (classes.frozen rewrite arm is stale: FunctionCall not
frame-exact), variant-regate (n11), hidden-pause F3 rows (n14), engine-check per part zone, counts-only pilot
(part pages borrow the whole-page frozen classes). Never parallel (page-level by Contract or passes-type): n1
batched, n9 waapi, hidden-pause x3, n11 rest, n3 hit-skip: whole-page combined run only.

## Schedule now -> C3 (23:15)
| when | Mac lanes (<= 8; lake builds <= 4 at once, load 35-50) | CI (<= 3 counts dispatches + 1 gate at once) |
|---|---|---|
| 08:30-10:00 | running: morph-group-integrate, morph-tween-inherit, proved-flags-ts, lead integrate-wave-1; start L1, L3, L6 (+L2 when a slot frees) | refreeze counts x2 profiles + gate finish; nothing new dispatched |
| 10:00-13:00 | model-bug-fixes starts (refrozen classes); panel-rest-n11 after inherit lands; T3 after L3; L4, L5, L7 as slots free | batch 1: people.card:shrink, morph.panel:rest, nav.hitTest:elements-skip (27 jobs, ~12 min) |
| 13:00-16:00 | lands of L1-L7, T3, T4; part-stage if morph-group-integrate landed | batch 2: hero.countdown:hidden-skip, morph.tween:waapi (fixed), commission.typing variant (if T3 landed) |
| 17:00-19:30 | lead integrate-wave-2 | 1 gate; combined run per profile (18 jobs) + G2 run (9) |
| 19:30-23:15 | engine-check verdicts, ledger rows, C3 | Lean CI per land only |
Deadlines: Lean lanes report by 15:00 (wave-2 cut 17:00); a lane missing 15:00 lands after C3 as "modelled".
Limits accepted: WebKit model-only; touch profile no data if the lane fails again; I5 INFERRED; attribution of
passes wins stays whole-page.

## Adversarial check (reviewer) and lead decisions

Issues and fixes:
1. `docs/team/work-graph.json`, T4: either fold T4 into `proved-flags-ts`, or make T4 depend on `proved-flags-ts`.
2. `docs/team/work-graph.json`, `panel-rest-n11`: add `proved-flags-ts` to its deps.
3. L1, L4, L5, L7: either drop their `packages/contracts/golden/engine/*.jsonl` writes until `counts-only` lands, or move the golden regeneration into `counts-only`'s scope. Any part-golden change goes through the `contract-rows-from-code` owner.
4. Ledger: one ledger writer per wave (the lead, or `model-bug-fixes`). Lanes report their rows in the handoff instead of editing the ledger. n16 stays with `proved-flags-ts`.
5. L1, L7 and any lane resting on model counts: start them after `model-bug-fixes` lands. L6 lands last, or is cut. Only pure logic and spec theorems (n22 total-pass, n8 #guard partition, n18 flip) start now.
6. C3': drop per-part attribution for g1 and g2 flags. Attribute only solo or cross-group pairs, and only once `contract-rows-from-code` verifies the rows. Otherwise use C1.
7. C1: run `hero.countdown:hidden-skip` and `morph.panel:rest` on `fixture-rest`, and `morph.tween:waapi` on a profile that pushes the morph (`swipe-wheel-v1` or touch). Recount jobs per (flag x profile).
8. CI: cap at 2 counts dispatches while any gate is running. Put `gh run list` queue checks in the schedule.
9. Batch 1: dispatch counts after the refreeze. Judge them only after `classes.frozen.json` is refrozen. Shrink goes into batch 2, after `proved-flags-ts` lands.
10. "Worth it": label n11 rest "Chromium trade; WebKit win model-only", or drop it. Remove L6's trade/no-win rows. Mark L1 n5 as a "why" finding only. Fix the counts to 13 / 11 / 1.
11. Text: say "page-level and passes flags: whole-page C1 or combined run only, never per-part attribution".
12. Remove `variant-regate` from D. Mark T3 as "gate at risk (commission-resize CUT)".
13. Schedule: reserve slots for `part-stage`, then `counts-only`, then `contract-rows-from-code` before any L lane. Cap at 8 lanes and 4 lake builds.

Bottom line:
- Go: Lean spec work that does not depend on the Chromium model (L3, the n8 partition in L2, the n18/n19 specs in L5) can start now, each lane on its own file.
- Change: T4, `panel-rest-n11` and every golden-regenerating lane collide with `proved-flags-ts`, `counts-only` or `contract-rows-from-code`. Re-sequence or fold them as in fixes 1-4.
- Change: the combined run cannot attribute anything per part. Every listed units win sits in g1 or g2 with another candidate. Use C1 per flag on that part's own profile (`fixture-rest` for countdown/panel, not swipe-v1 for waapi).
- Change: judge verdicts only after `model-bug-fixes` refreezes the classes and after the shrink and arm variants land, so realistically after ~11:00. Cap counts dispatches at 2 while gates run.
- Change: give the `integrate-wave-2` critical path (`part-stage`, `counts-only`, `contract-rows-from-code`) Mac slots before the optional L lanes. Label n11 rest as a Chromium trade.

Files: docs/team/work-graph.json, packages/contracts/golden/parts/contracts.gen.json, research/findings/ledger.json, docs/team/handoffs/model-checks.md, .github/workflows/chromium-counts.yml, .gitattributes, lean/Fw/Engine/Compose.lean

Lead decisions: start lean-specs-now (one lane, the model-independent specs); per-flag C1 verdicts become flag-verdicts-c1 after the refreezes; panel-rest-n11 waits for proved-flags-ts; T4 folded into proved-flags-ts; one ledger writer per wave; critical-path lanes (part-stage, counts-only, contract-rows-from-code) keep their Mac slots first.
