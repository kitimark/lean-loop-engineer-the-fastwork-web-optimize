# Fable synthesis: parts as Lego, parallel lanes, revised plan (PLAN rev 11 input)

Base: PLAN rev 10; inventory of 33 parts at ci/page-root-clip 785a0748; two Fable plans (deadline-first, platform-first). Checks done against the repo: pain.notes has no read of `.commission-card` (grep over apps/site/src/parts/pain.notes: none, CONFIRMED); `Fw.Engine.Core.frameWork` counts units with `List.countP` over `f.changes` and `frame_le_of_cover` already splits the change list by permutation + `countP_append` (Core.lean:158-166,394-404, CONFIRMED). Times: now 2026-10-19 ~00:40 +0700; C3 23:15 (22.5 h); text freeze 10-20 11:15; report 13:15.

## A. Answer to the user

- The idea is right on the build side and already half built: every part has its own folder, `part.json` variants, a Lean module and golden vectors, and a Lean-scoped gate row. Parts can be swapped with `?fw=part:variant` today.
- Two things are wrong in the expectation and we fix them by proof, not by more measurement:
  1. A part cannot be measured alone against the original, because the original is one page. Rewrite-vs-original checks (breakpoint gate, faithful bands) stay whole-page. Measured: scoping the gate to one part saves nothing (528 s vs 517 s).
  2. A part can be measured alone against its own faithful variant (F3/F4 model checks, work comparison), and that is where the pipeline time goes today (one whole-page counts run per flag, 7-50 min each). A Lean composition theorem makes one combined run stand for all independent flags, and a small part page per scenario replaces the per-flag whole-page run.
- What you saw missing is content, not architecture: hero copy, pictures, logos, CTA handlers, the end-of-page panel inside the nav, Thai/locale links. Content lanes run in parallel now, no theorem needed; they do refreeze the counts base once.
- Lean stays in every part: faithful spec + golden (exists), (vis)/(work) theorem pair (exists or partly), plus two new items per part: a Contract row (declared inputs/outputs, independence decided by `decide`) and a units/passes tag on its work theorem.
- By the deadline you will see: a content-complete page (real copy, pictures from the unmodified snapshot, brand marks, CTAs opening signup/drawer, morph panel hosted in the nav), v2-proved as the default preset with ~6 more proved flags, the Lean Contract + Compose modules landed, pilot part-page measurements for two parts and one combined run, and a report table per part: ported/content state, pair status, Contract row, F3/F4 verdict, what was skipped and why. Not before the deadline: WebKit part lane, per-part gate, Thai locale.

## B. Independence map

Premise I (Lean `Fw.Parts.Contract.Independent P Q`, decidable), P independent of Q iff:
- I1 DOM-disjoint change targets (own anchor subtree).
- I2 layout-local: P's variant changes no box outside P; witnessed by the gate PL1 rows (boxes equal variant vs faithful) and `boxes.gen.json` heights per width band, so sibling page offsets are unchanged.
- I3 outputs(P) ∩ inputs(Q) = ∅ over `Signal = {scrollY, vw, vh, clock, pointer, morphPhase, cssVar n, className n, rect n, scenePaused}`.
- I4 no forced-layout chain across P and Q in the ordered rAF list (`Fw.Parts.EngineScroll.forced`, `forced_append_writes`).
- I5 layer state of P's boxes fixed by neighbours (overlap compositing). INFERRED; cite Chromium layerization overlap and WebKit `RenderLayerCompositor` in the module before any claim uses it; until then I5 is a recorded premise, not a theorem.

Independent parts (I1-I4 by code; I5 premise):

| part | declared inputs | outputs | note |
|---|---|---|---|
| hero.countdown | clock | none | requires rule to morph.countdown:strip is config-level (`Rule.holds`), not a signal |
| nav.hitTest | scrollY, pointer, className is-hero-pill/is-morphing | none | nav classes are stage-set inputs |
| nav.langMenu | pointer | none | inside nav |
| hero.accent | clock | none | width transition inside h1; I2 via h1 PL1 row |
| hero.orbit, hero.deck, hero.cue | cssVar --exit-opacity, scrollY | none | consumers; independent given hero.exit's variable contract unchanged |
| pain.notes | scrollY, own rect | none | commission-card read CONFIRMED absent |
| commission.typing | clock | none | inside commission frame |
| platform.sweep/glint/entries/marquee/stageBg | clock, scenePaused, cssVar --morph-fade | none | inside platform |
| morph.mount | rect platform, scrollY | one DOM insertion | under declared rect input |
| overlays.signup, overlays.drawer | open event | none | portals, closed by default |
| people.o, people.deck, people.carousel | scrollY, vh | none | carousel owns hero pill CSS: a shared stylesheet dependency, not runtime; any pill CSS move is G1 |

Coupled groups (one gate row set, one counts run, one integration task each):
- G1 hero/threshold: hero.exit (order 10, writes --exit-opacity) → hero children; people.card (0.72, writes is-pain-dark on pain); pain; nav (is-hero-pill at 0.72); nav.hitTest reads nav classes. The 0.72 constant is defined once in Lean; n6 carries the consumer contract as hypothesis.
- G2 morph: morph.mount (101) → morph.tween (110, writes --morph on nav, --morph-fade on platform) → morph.panel (host = nav) → morph.countdown, morph.columns; engine.scene pauses platform. Largest visible gap. Scenario `push` (morph phase 0..1).
- G3 page-offset chain: margin-top -100svh overlaps; contract = boxes.gen.json per width + gate PL1 at every breakpoint; measured once per integration wave, whole page.
- G4 cross-cutting: engine.scroll (batched), engine.scene (hidden-pause): page-level claims by construction; measured only on whole-page preset runs.
- G5 commission ↔ resize: 57 excused readings stay excused (Fw.Gate.Exit); limit.
- Content-only lanes: no theorem (class E by construction: same DOM shape, CSS values restated); they trigger one base refreeze.

## C. Lego platform, minimal slice, Lean contract

Three Lean pieces first, then glue.

1. `lean/Fw/Parts/Contract.lean`: `Signal`, `PartSpec {id, group, order : Option Nat, inputs outputs : List Signal, layoutLocal : Bool, box : BandHeight}`, table for the 33 ids (each row cites file:line), `Independent` decidable, `groups_partition : ∀ P Q, group P ≠ group Q → Independent P Q` by `decide`, `scenariosFor : PartSpec → List Profile` (clock-only → fixture-rest; scroll → swipe over the group's span; morph → push). Generates `packages/contracts/golden/parts/contracts.gen.json`, `packages/measure-chromium/scenarios.gen.json`, and the stub box CSS.

2. `lean/Fw/Engine/Compose.lean` over any `Engine P M` (Chromium and WebKit instances are corollaries). Statements (docstrings carry these):

   - `FrameIn.append`: $f_1 \mathbin{+\!\!+} f_2$ with changes $c_1 \mathbin{+\!\!+} c_2$, compAnims $a_1 + a_2$.
   - `frameWork_append_units`: $$\forall s,\; \mathrm{units}_s(W(f_1 \mathbin{+\!\!+} f_2)) = \mathrm{units}_s(W(f_1)) + \mathrm{units}_s(W(f_2))$$ (from `List.countP_append`).
   - `touched_append`: $$\mathrm{touched}(f_1 \mathbin{+\!\!+} f_2) = \mathrm{touched}(f_1) \cup \mathrm{touched}(f_2)$$
   - `frame_le_append` (composition of work theorems): $$W(v_1) \preceq W(o_1) \;\wedge\; W(v_2) \preceq W(o_2) \;\Rightarrow\; W(v_1 \mathbin{+\!\!+} v_2) \preceq W(o_1 \mathbin{+\!\!+} o_2)$$ on the units components and on forced passes; proof via `frame_le_of_cover` with the permutation $o = m \mathbin{+\!\!+} \mathit{rest}$ partitioned by part.
   - `someLt_append_units`: $$\exists s,\ \mathrm{units}_s(v_1) < \mathrm{units}_s(o_1) \;\Rightarrow\; \exists s,\ \mathrm{units}_s(v_1 \mathbin{+\!\!+} v_2) < \mathrm{units}_s(o_1 \mathbin{+\!\!+} o_2)$$ strictness survives only through units.
   - `passes_not_compositional` (counterexample theorem, the lesson): $$\exists f_1\, g_1\, f_2:\ s \notin \mathrm{touched}(g_1) \wedge s \in \mathrm{touched}(f_1) \wedge s \in \mathrm{touched}(f_2) \;\wedge\; \mathrm{pass}_s(g_1 \mathbin{+\!\!+} f_2) = \mathrm{pass}_s(f_1 \mathbin{+\!\!+} f_2)$$ a part that drops a stage pass saves nothing on the page while any other part touches that stage in the frame. This is the INFERRED shape of the hidden-pause UpdateLayoutTree ≤o refutation (1851 vs 1850); model-bug-fixes checks it.
   - `visible_append_of_boxes_eq` (Fw.Engine.Visual): $$\big(\forall i,\ \mathrm{boxes}_i(o)=\mathrm{boxes}_i(v)\big) \wedge \big(\forall i,\ \mathrm{vis}(\mathrm{scene}_i(o)) = \mathrm{vis}(\mathrm{scene}_i(v))\ \text{inside } \mathrm{boxes}_i\big) \;\Rightarrow\; \mathrm{vis}(\mathrm{scene}(o)) = \mathrm{vis}(\mathrm{scene}(v))$$ the premise is exactly the per-part gate PL1 rows.
   - `lego_swap_sound`: under `Independent P Q` for all Q ≠ P, swapping P's variant leaves every other part's FrameIn change list equal, hence their `frameWork` and scene equal.

3. `lean/Fw/Measure/Compose.lean` F6: $$\Big|\Delta_{\text{combined}}(z) - \sum_{P:\ \mathrm{zone}(P)\ni z} \Delta_P(z)\Big| \le \mathrm{margin}(\mathrm{class}(z))$$ per zone and stage; verdict pass/bug as `EngineCheck.verdict`; a bug is an independence-premise failure filed per part, never a widened margin. Unit of decision = (part, stage, zone).

Glue (TS, checked against Lean goldens, no decision logic):
- `apps/site/src/stage/`: `PartStage` mounts one part or group under a fake `ScrollEnv` (y/vw/vh from stage params, real `MotionClock`), sets declared inputs (custom properties, classes, fixed-size neighbour stubs keeping page geometry and a composited neighbour for I5); route `?only=<id>&stage=y:N,vh:N,vw:N,morph:F`; `App.tsx` → `partsList` rendering page or stage; prerender adds the `?only=` searches.
- Ablation variant `stub` (type `ablation` exists, registry/types.ts:4) in each section `part.json`: gen-shells emits box CSS for all sections; the stub emits the part's write-signals as constants. `?fw=part:stub` resolves without registry changes.
- `apps/site/scripts/lint-part-io.mjs`: every `setProperty`/`classList`/`dataset` write outside the anchor must be a declared output; first run lists undeclared writes as findings.
- `chromium-counts.yml` inputs `only`, `scenario`, matrix cap 6 (12 fanned runs took 39-50 min, MEASURED). `Fw.Engine.Keys.RunMeta.only` with `runKey_inj` and `golden_base_unique` re-proved before engine-check reads new keys. engine-check `--zones-by-part` and `--compose`.
- Not built: per-part gate, per-part faithful-checks, WebKit part lane, engine.scroll refactor.

## D. Lanes to launch now (≤ 8 concurrent)

Review tiers: T1 lead reads diff + Lean CI green; T2 T1 + one checker pass; T3 T2 + gate/counts evidence. Hard cut = stop and report state as is.

| id | parts | base | writes | pinned unit | threat model (must catch / need not) | accepted limits | deliverable | tier | hard cut |
|---|---|---|---|---|---|---|---|---|---|
| compose-lean | Fw.Engine | main | lean/Fw/Engine/Compose.lean, lean/Fw.lean | one theorem | catch: a composition claim that holds for passes; need not: engine-specific constants | over any Engine; I5 unproved | the 7 statements in C proved, LaTeX docstrings; `passes_not_compositional` first | T2 | 08:00 |
| contract-lean | all 33 | ci/page-root-clip (re-check after integrate-ports-4 lands) | lean/Fw/Parts/Contract.lean, contracts.gen.json, scenarios.gen.json | one PartSpec row | catch: an undeclared output or a wrong group; need not: content fidelity | I5 recorded, pain.notes rect absent CONFIRMED | table, Independent, groups_partition, scenariosFor; types pinned by 02:40 | T2 | 06:00 |
| content-hero | hero, hero.countdown labels, orbit, deck, cue, accent strokes, nav logo | integrate branch wave-1 | apps/site/src/parts/hero*/**, nav logo asset ref | one part's content | catch: copied Fastwork code or a changed DOM shape; need not: counts | pictures served from unmodified snapshot assets; stand-in waves → path data restated | real copy/labels/pictures; handoff | T1 + gate in wave | 07:00 |
| content-people-pain-commission | people.*, pain, commission, commission.typing | wave-1 | apps/site/src/parts/people*/**, pain*/**, commission*/**, engine.scene selector list | one part's content | same as above; also content-visibility deferral must not move boxes (PL1) | commission resize excused stays | avatars/covers/posts, o glyph, 3 deck panels, drawings, why-bring onClick → overlays.drawer, deferral for people/pain | T1 + gate in wave | 07:00 |
| morph-group-integrate | G2 + overlays wiring + brand glyphs | wave-2 | apps/site/src/parts/morph.*/**, nav/index.tsx host slot, overlays glyphs, App.tsx wiring | the group | catch: --morph not reaching the panel, columns outside backdrop, debug tray left; need not: new variants | fallback: panel in nav with placeholder columns, listed | panel hosted in nav with writerRef+backdrop, 21 snapshot images, CTAs (nav Join, hero, commission) open signup/drawer, tray + MUI Menu removed; MorphPanel/MorphTween goldens unchanged | T3 (own gate + counts) | 15:00 |
| proved-flags-ts | n5 nav write-on-change, n8 clock-aligned, n16 people.card shrink, n21 pain.notes arm, n15 accent steps, n11 panel rest | wave-2 | the 6 parts' logic + part.json, registry/presets/v2-proved.json, default preset | one flag | catch: TS diverging from the golden; need not: new proofs | judged on the combined run only | 6 variants passing golden tests; v2-proved extended and default (PLAN §12 decision for the lead) | T2 | 15:00 |
| model-bug-fixes | nav.hitTest FunctionCall per-frame, morph.columns/scene UpdateLayoutTree, morph.mount LayoutCount, morph.tween waapi FireAnimationFrame | main, re-judged after wave-1 refreeze | lean/Fw/Engine/{Chromium,Keys}.lean rows, classes.frozen.json rewrite arm, ledger rows | one prediction row | catch: a widened class to pass; need not: WebKit | per-frame vs sum decided in Lean (`judgeClass`) | rows fixed with Chromium f842f52 cites; check UpdateLayoutTree case against `passes_not_compositional` | T2 | 17:00 |
| faithful-checks-rerun + lego-glue (same measure-engineer, sequential) | zones y04000/y04500/tail; stage, stub, lint, counts-only, engine-check zones | main after page-root-clip | faithful-checks branch rebase, anchors.json scrollWidth row + Lean gate table; apps/site/src/stage/**, registry/only.ts, gen-shells.mjs, lint-part-io.mjs, chromium-counts.yml, engine-check | one zone verdict / one pilot part page | catch: touch lane silently no data; a key collision mixing arms; need not: WebKit | touch listed as no data if it fails again; pilot = hero.countdown, nav.hitTest, then G2 | faithful verdict after page-root-clip; pilot 2 part pages × 1 scenario + 1 combined v2-proved run; F6 statement wired | T3 | 19:00 (glue after C3 reported as pilot) |

Lead-only: integrate-wave-1 (~07:00-10:00: content lanes + faithful anchor; one gate both engines; base refreeze counts × 2 profiles, ≤ 3 concurrent), integrate-wave-2 (~17:00-19:30: morph group, flags, glue, model fixes; one gate; combined counts per profile + G2 run; engine-check per part zone; F6 pilot). plan-rev11 (plan-editor, 2 h, after compose-lean and contract-lean statements are fixed, not proved): PLAN §4.8 composition (units compose, passes do not), §6.8 part contract, §10.7 Lego lanes + C3 slice. report-draft-3 after C3 (researcher, 5 h): per-part table, independent vs coupled, runs-per-flag before/after, not-done list.

Concurrency: 7 teammates + plan-editor = 8; lead landing budget ~12 landings ≈ 4 lead-h, batched by wave.

## E. What stops being measured, what remains

Stops (proof replaces measurement):

| was measured | replaced by | condition |
|---|---|---|
| one whole-page counts run per flag (7-50 min each, 12 fanned → 39-50 min) | `frame_le_append` + `someLt_append_units`: one combined run per profile for all independent flags; part page (~2 min shard) per (part, scenario) for F3/F4 | pair proved, Contract row Independent of all parts outside its group, win tagged `units` |
| gate re-run for sibling parts after one part changes | `scope_sound` + `lego_swap_sound` | certificate holds; variant of sibling unchanged |
| visual re-check of untouched parts | `visible_append_of_boxes_eq` | PL1 boxes equal (gate row) |
| re-measurement at each width | band theorems; gate checks boxes once per wave | — |
| WebKit Simulator counts | model-only, named limit per part | F5 blocked, stated |
| phone sessions | none before the report | — |

Still measured, when:
- Breakpoint gate, whole page, both engines, 124 probes: once per integration wave (2 gates total). PL1 boxes at every breakpoint are the G3 contract and are not proved.
- faithful-checks bands R vs A, swipe-v1 and swipe-touch-v1: once after page-root-clip lands and again after wave-1 content (images move R). The 645×1398 run is not comparable; discard.
- Combined-preset whole-page counts run per profile: F6 and F3/F4 for all independent flags (one run, not one per flag); plus one G2 run; plus G4 engine.* flags (page-level by construction).
- Base refreeze after content fill (PaintImage/DecodeImage change), before any flag is re-judged.
- F3/F4 themselves: a proof is about the model; the 4 refutations show the model needs checking. Proofs shrink the page F3/F4 run on, never replace them.
- Passes-type wins (hidden-pause, scene pausing, panel blur→none): reported as part-local; page win only if every part in the frame leaves the stage untouched. State this before text freeze; it shrinks the v2-proved story honestly.

CI budget to C3: 2 gates (32-80 min wall), 6-8 counts runs at ≤ 3 concurrent, 2 faithful runs, 2 pilot part runs, Lean CI per landing (14 min, parallel). All free runners.

## F. Work-graph edit (docs/team/work-graph.json)

Add tasks (id, deps, writes):
1. `compose-lean` — deps: none — lean/Fw/Engine/Compose.lean, lean/Fw.lean.
2. `contract-lean` — deps: none (base ci/page-root-clip; re-check after integrate-ports-4) — lean/Fw/Parts/Contract.lean, packages/contracts/golden/parts/contracts.gen.json, packages/measure-chromium/scenarios.gen.json.
3. `content-hero` — deps: integrate-ports-4, page-root-clip — apps/site/src/parts/hero*/**, nav logo ref.
4. `content-people-pain-commission` — deps: integrate-ports-4, page-root-clip — apps/site/src/parts/people*/**, pain*/**, commission*/**, engine.scene selectors.
5. `integrate-wave-1` (lead) — deps: 3, 4, faithful-checks-rerun anchor — integration branch, gate, refreeze counts.
6. `morph-group-integrate` — deps: page-root-clip — apps/site/src/parts/morph.*/**, nav host slot, overlays glyphs, App.tsx.
7. `proved-flags-ts` — deps: contract-lean (table) — 6 parts' logic + part.json, registry/presets/v2-proved.json.
8. `model-bug-fixes` — deps: integrate-wave-1 (refrozen base), compose-lean (`passes_not_compositional`) — lean/Fw/Engine/{Chromium,Keys}.lean, classes.frozen.json, ledger rows.
9. `faithful-checks-rerun` — deps: page-root-clip — faithful-checks branch, anchors.json + Lean gate table scrollWidth row, results/faithful.
10. `part-io-lint` — deps: contract-lean — apps/site/scripts/lint-part-io.mjs, pnpm lint.
11. `part-stage` — deps: contract-lean, page-root-clip — apps/site/src/stage/**, registry/only.ts, App.tsx partsList, 4 part.json `stub`, gen-shells.mjs, entry-server prerender.
12. `counts-only` — deps: part-stage — .github/workflows/chromium-counts.yml, measure-chromium host --search, lean/Fw/Engine/Keys.lean RunMeta.only (+runKey_inj), engine-check keys.
13. `compose-check` — deps: compose-lean, counts-only — lean/Fw/Measure/Compose.lean, engine-check --compose — after_c3: true.
14. `integrate-wave-2` (lead) — deps: 6, 7, 8, 10, 11, 12 (12 may land as pilot) — gate, combined counts, G2 counts, engine-check per zone.
15. `plan-rev11` — deps: compose-lean, contract-lean statements — docs/plan/PLAN.md, docs/plan/loop-plan.html, work-graph.json.
16. `report-draft-3` — deps: integrate-wave-2 (C3 numbers) — docs report; frozen 11:15.
17. `part-stage-webkit` — deps: webkit-sim-rewrite, part-stage — parked, after_c3.

Cuts (status cut, reason):
- `commission-resize`: 57 readings stay excused; limit.
- `webkit-sim-rewrite` counts for the report; WebKit model-only.
- per-part gate load saving: refuted (528 vs 517 s), never a task.
- Thai locale, SEO locale links P8: not done, invisible.
- new variants for partly-proved parts (hero.exit threaded, people.deck cqi, accent-wipe/boil-ca, typing container-type, sweep/glint): reported modelled/not proved, flags off.
- proposals class L (CM, constant glass, FLIP, st6, typing chunks): not built.
- `proof-hero-exit` drops from the C3 path if part-stage needs the part-builder slot (PLAN §10.6 order unchanged).
- pixel-spot, phone sessions: none before the report.
- Anything missing wave-2 by 17:00 keeps wave-1 state and is listed; no third gate.

## G. Checkpoint impact and report sections

- C3 (23:15): decision uses per-flag whole-page F3/F4 already on main plus the combined-run F3/F4 per part zone from wave-2; pilot part-page F3/F4 for hero.countdown and nav.hitTest as method demonstration; F6 reported as pilot or "statement landed, run after C3". v2-proved default preset with the 6 added flags counts only if proved-flags-ts lands in wave-2. Passes-type wins reclassified before C3.
- C4 (text freeze 11:15, report 13:15): new report sections: §4.8 composition lesson (units compose, passes do not; `passes_not_compositional` as the Lean "why"); §6.8 part Contract table (33 rows, independent vs 5 groups); per-part table (ported/content, pair status, Contract, units/passes tag, F3/F4 verdict, skipped and why); pipeline-time accounting (runs per flag before: 1 whole-page/flag, 7-50 min; after: 1 combined/profile + ~2 min part shards); not-done list from F cuts; limits (I5 INFERRED, WebKit model-only, touch no data if it fails, 57 resize readings excused).
- Risks that move checkpoints: wave-1 refreeze late → every flag verdict waits (mitigation: land by 10:00, ≤ 3 concurrent counts); G2 slips → fallback panel-in-nav with placeholder columns; `RunMeta.only` without re-proved `runKey_inj` → key collisions mix arms (counts-only cannot land before the proof); gate p90 42 min → two gates only.
