---
id: 2026-10-17-lean-everywhere-inventory
kind: note
title: "Lean everywhere it pays: inventory of every v2 decision, proof levels, a Lean console brain, and a Lean-first rollout"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:research-lean-inventory]
topics: [lean, console, automation, architecture, proofs]
links:
  plan: docs/plan/PLAN.md (rev 3, read only; not edited)
  notes:
    - research/kickoff/05-lean-proofs-and-backend.md
    - research/kickoff/06-architecture-and-tooling.md
    - research/kickoff/08-chat-forensics/README.md
    - research/kickoff/10-automation-and-proof/01-v1-console-manual-work.md
  scratch: research/kickoff/10-automation-and-proof/lean-scratch/03-inventory/
  v1: ../fastwork-com-web-optimize @ eae1bb99 (read only)
---

# Lean everywhere it pays: an inventory of v2's decisions, and a Lean-first plan

**Status words.**
- **MEASURED**: I ran it on this Mac today; the command is in §9.
- **CONFIRMED**: read in a cited file or source.
- **INFERRED**: my design choice or estimate; a spike or the bug ledger must still check it.

**Labels in this note.** Inventory rows are named `st.N` (statistics), `cm.N` (cost model), `fl.N` (flags),
`pa.N` (parity), `ex.N` (experiment and landing), `co.N` (console), `dq.N` (queues and devices), `ar.N`
(artifacts), `op.N` (agent operations), `w.N` (wire), `x.N` (not provable). These names do not clash with the
plan's labels (Q, Day, M, G, V-, TL, PL, SPK, K, R, class W/SM/X/P).

**How to read the math.** Every proved statement in this note comes with a math line. The Lean is in the scratch
files, if you want it.

| Symbol | Read it as |
|---|---|
| `A ⇒ B` | if A holds, then B holds |
| `A ⇔ B` | A holds exactly when B holds |
| `∀ x ∈ X` / `∃ x ∈ X` | for every x in X / for at least one x in X |
| `#{x ∈ X : P(x)}` | how many elements of X satisfy P |
| `⌊a/b⌋`, `⌈a/b⌉` | a/b rounded down / up |
| `x ≤ y` on vectors | every component of x is ≤ the same component of y |
| `L₁ ++ L₂` | list L₁ followed by list L₂ |
| `v[i ↦ w]` | v with the entry for i changed to w |
| `S ⊆ T`, `S ∩ T = ∅` | every element of S is in T; S and T share no element |
| `ℚ`, `ℕ` | exact fractions; whole numbers 0, 1, 2, … |

> **Verification fixes (2026-10-17).** (1) The `#math_doc` sync check did **not** keep math and Lean in sync: a
> retag alone passed, definition bodies were not hashed, and imported modules were skipped (MEASURED, three probes).
> §6 now adopts note 04's deep-hash pipeline with a reviewer-owned sign-off file. (2) "Requirement 1 becomes a
> theorem" was overstated: this sketch has no actors, so anyone could answer your step. §0 item 3 is restated over
> the `may` table, and the production reducer merges note 02's semantics (`ConsoleV2.lean`) with this sketch's data
> structures. (3) L1 is split into **L1-pure (54)** and **L1-conditional (30)**, each conditional row naming its L3
> premise; four L3 rows were added (x.15-x.18) and JSON decoding moved from L3 into L1. (4) The phone queue no
> longer blocks the head of the line: `dispatch` starts the most urgent job **that fits**, with a
> work-conservation theorem and a hard stop at the window end (MEASURED, builds). (5) The grind probe result was
> reported backwards; corrected in §4.4. (6) Two math lines a reader would misread (st.12, the `enc` header) are
> fixed.

---

## 0. Answer first

1. **Inventory (§2).** I list **87 decisions, state machines and pure functions** in the v2 design (PLAN rev 3 §3-§9,
   notes 05 and 06, plus the console requirements). I classify them as follows (INFERRED):
   - **L1: 84.** Implemented and proved in Lean, and run through `fwcore`; TypeScript only does the IO. Split
     (after verification) into:
     - **L1-pure: 54.** The decision and its inputs are both internal to the console (events, ids, enums, counts the
       console itself produced). The theorem is the whole guarantee.
     - **L1-conditional: 30.** The decision is proved, but its real-world meaning also needs an L3 premise that the
       row names (an engine transcription, a parser, data integrity, completeness of observation, an identity, a
       judgement). The theorem is the guarantee *given* that premise.
   - **L2: 3.** A Lean spec plus a TS or browser copy, kept equal by tests: the site's flag resolver (checked on its
     **whole** finite domain, which is as strong as a proof for that registry version), the JSON wire codecs, and
     the console-web optimistic preview.
   - **L3: 18 categories, not provable.** These are engines, pixels, devices, numeric fitting, YAML and CSS parsing,
     hashing assumptions, human and LLM judgement, IO, the clock, completeness of observation, actor identity,
     completeness of declared dependencies, and "answered / complete" judgements. §3 says why each one is L3. Each
     L3 item feeds an L1 decision through a narrow, checked input.

   Rev 3 proved 4 modules (Frames, Verdict, Flags, Cost/screen). This inventory moves the console reducer, both
   queues, the artifact store's keys and plan, landing, parity bands, licences, spawn-guard, path check, the usage
   meter and the JSON decoders for hook payloads, usage records and the Vite manifest into L1 as well.
2. **Architecture (§4). Recommendation: yes, make `fwcore` the console brain.** It would be a long-lived, stateful
   Lean process. It holds the reducer state, the queues and the gates, and answers every decision and projection.
   console-api stays a thin TypeScript shell: it does HTTP, SSE, appends to `events.jsonl`, spawns processes and runs
   watcher probes. Speed is not a concern (MEASURED here):
   - 100,000 console events applied in **0.28 s** (2.8 µs each; 0.41-0.54 s on the verification re-run, same
     order; to be re-measured on the merged reducer);
   - Node → `fwcore` round trip **17.6 µs**;
   - cold start **29 ms**;
   - a full replay after a crash takes under a second.

   **One trap, MEASURED.** Read-modify-write of the state through an `IO.Ref` (`get` then `set`) copies the whole
   hash map on every event. That made the same 100k events take **19.2 s instead of 0.28 s**. The fix is one line
   (`modifyGet`), plus a speed-budget test.
3. **Requirement 1 (no hand-kept status), restated precisely.** The status a user sees is a pure fold of the event
   log. **Row fields change only through events whose actor the `may` table allows; the agent-allowed events are
   exactly the agent rows of the merged catalogue (note 01 §5: card open, park, wait, ask-lead, hand-back result,
   review verdict, job requests, kb and bug commands); notes are inert.** Agents *do* change row fields, but only
   through those typed, refusable events, never by writing a field. What is proved:
   - in this sketch: `note_preserves_needsYou` (an agent's note can never change what the console asks you to do)
     and `answer_at_most_once` (a step is answered at most once, on any log, even with duplicate deliveries);
   - in note 02's `ConsoleV2.lean`: `unauthorized_rejected`, `only_user_answers` (only you can answer a step), and
     `review_independent`;
   - **to prove** on the merged reducer: `agent_events_only` (an event whose actor is an agent changes a row field
     only if its type is in the agent rows of `may`).

   This sketch alone does **not** show requirement 1: it has no actor or authority, so `post`, `start`, `answer` and
   `cancel` are accepted from anyone (CONFIRMED by reading `Auto/Console.lean`), and `note_preserves_needsYou` holds
   trivially because `note` does nothing by construction. The production module therefore merges note 02's
   semantics (actors, cards, authority, landing) with this sketch's data structures (`HashMap`/`HashSet`,
   `modifyGet`); the 100k benchmark is re-run on the merged reducer (note 02's list-based `seen` is O(n) per event,
   so its replay would be O(n²), INFERRED far slower than 0.28 s at 100k events).

   v1 agents made 4,914 `status.mjs set` calls (MEASURED). I-145 is the v1 incident where a board row still said
   "waiting on you" 16 minutes after you had decided, because the row depended on an agent's update.
4. **Sketches (§5).** Three sketches build on Lean 4.35.0, with no `sorry` and only the standard axioms:
   - the console reducer, 9 theorems;
   - the device queue (priority with aging, no starvation, mutual exclusion, booked window), 10 theorems;
   - artifact keys (an encoding that cannot collide, and minimal invalidation), 6 theorems.

   Together that was 510 lines; after the queue fix (12 theorems in the device queue now) it is 575. They took 1, 2
   and 3 build iterations, and about 40-50 s of wall-clock time each. On 11 probe goals, a one-line `grind` proof
   worked for 10.

   I also built a math↔Lean tag check (`#math_doc`). **Verification showed it does not keep them in sync** (§6): it
   detects that a statement's printed form changed, but a retag alone passes, definition bodies are invisible, and
   imported modules are skipped. §6 replaces it with note 04's pipeline.
5. **Rollout (§7).** Rev 3 said "MVP only, go/no-go at M4". This note replaces that with **Lean-first, module by
   module, with a demotion rule and evidence**:
   - the console core and queues are L1 from M0-M1;
   - each L1 module ships with **mutants**: v1 bugs put back on purpose, which must break `lake build`;
   - the bug ledger records, per module, what caught each bug;
   - a module that costs too much without catching anything is demoted to L2 by a decision record. Lean as a whole
     is not on trial at M4.

---

## 1. Why the scope widens (evidence)

- **v1 agents kept the console up to date by hand.** Over v1's 105,638 Bash tool calls (MEASURED, unique tool-use
  ids):
  - 4,914 called `status.mjs set`;
  - **28,696 (27 %)** called one of v1's coordination tools (`status`, `finding`, `incident`, `console`, `lock`,
    `wait`);
  - 6,423 called `lock.mjs status`. [08] B14 counts 6,424, because it also counts Monitor calls.

  Sibling note [10-01] counts this work in depth: 10.9 % of tool turns were pure upkeep, and 31 % of the lead's.
- **The status board's own incidents were mostly about hand-kept state.** I-044, I-058, I-108, I-145, I-152, I-162,
  I-183, I-248 and I-265 are rows that were stale, wrong or impossible to clear because they depended on agent
  updates. For example, I-145: rows "depend on agent updates, not on the proposal/console/lock events the tools
  already have". (Titles CONFIRMED in `v1:console/incidents.json`; the selection of 9 out of 25 regex matches is
  INFERRED.)
- **The scheduler failed in ways a theorem names.** These incidents are CONFIRMED via [05 §3]:
  - I-011: a short lane starved;
  - I-041: exclusivity broken;
  - I-049: readers starved;
  - I-091: a renew shortened a lease;
  - I-113: a re-queue lost its place;
  - I-122 and I-123: a lease expired in the middle of a user step;
  - I-185: "queue does not follow board priority: the lead made 89 hand moves on 10-04".
- **Rev 3 already moved status into a projection** (PLAN §2.2 "Drop": one writer, events, status as a projection).
  But the projection, the queues and the gates are TS "with unit tests" (PLAN §3.3, §3.4). The new requirement
  ("prove as much as possible") and the measured cost (§4.2) both say they can be Lean, at little extra cost.

---

## 2. Inventory (part a + b)

Columns:
- **Math**: what is proved, or decided by a function whose properties are proved.
- **Lvl**: L1, L2 or L3.
- **Lean**: module · theorem names. **P** = already proved in `05-lean-sketch`. **S** = proved in this note's
  scratch (§5). Names without a mark are planned.
- **M**: the milestone where the module lands (§7).

Where a row needs an IO input (counts, pixels, probes), the input is L3 and the decision on it is L1. The input
arrives as a typed record, so the theorem is about every possible input.

### 2.1 Statistics and frames (`Fw/Spec/Frames`, `Verdict`, `Stats`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| st.1 | Frame ticks at rate r (Hz), dt in µs | `k_r(dt) = ⌊(2·r·dt + 10⁶) / (2·10⁶)⌋` (round half up); `k₁₂₀(dt) ≥ 5 ⇔ dt ≥ 37 500`; `k₁₂₀(dt) ≥ 7 ⇔ dt ≥ 54 167`; `a ≤ b ⇒ k(a) ≤ k(b)`; add the same for r = 60 (the iPhone) | L1 | Frames · `tick_ge5_iff`, `tick_ge7_iff`, `tick_mono` (P); `tick60_*` | M0 |
| st.2 | Threshold counts and twins | `t ≤ t′ ⇒ #{x > t′} ≤ #{x > t}`; `#{x : k(x) ≥ 5} = #{x > 37 499}` | L1 | `countAbove_antitone`, `tick5_eq_countAbove` (P) | M0 |
| st.3 | Near bands | `(30, 38] ∩ (46, 54] = ∅`; every frame lies in at most one band | L1 | `near_disjoint` (`decide`) | M0 |
| st.4 | Twin sensitivity | `sens(t) ⇔ v(t−4) ≠ v(t) ∨ v(t+4) ≠ v(t)`; `¬sens(t) ⇒ v(t−4) = v(t) = v(t+4)` | L1 | `twin_stable` | M0 |
| st.5 | One median (v1 had two) | `med(X)` = middle of `sort(X)` (mean of the two middle values, in ℚ, for even n); `med(π(X)) = med(X)` for every reordering π; `min X ≤ med X ≤ max X`; `med(X + c) = med(X) + c` | L1 | Stats · `med_perm`, `med_bounds`, `med_shift` | M0 |
| st.6 | Non-overlap verdict | `better ⇒ ∀ y ∈ V, ∀ x ∈ C : y < x`; `better ⇒ |C| ≥ 3 ∧ |V| ≥ 3`; swapping C and V turns better into worse; "higher is better" on x = "lower is better" on −x | L1 | `better_sound`, `better_needs_runs`, `swap_better`, `verdict_higher_eq_lower_neg` (P) | M0 |
| st.7 | Null rate of the landing verdict | runs exchangeable, no ties ⇒ `P(better) = 1 / C(m+n, n)`; 4v4: `1/70`; 5v5: `1/252` | L1 | `land_null_prob` (enumeration, `decide`) | M0 |
| st.8 | Sequential ABBA rule | `win ⇒ U = 0 ⇒ verdict = better`: the two rules can never contradict | L1 | `abba_win_implies_better` | M4 |
| st.9 | Hodges–Lehmann shift | `HL(C, V) = med{ v − c : v ∈ V, c ∈ C }`; `HL(C, V + a) = HL(C, V) + a` | L1 | `hl_shift` | M4 |
| st.10 | Multiplicity | a landing is allowed ⇔ `k · p_null ≤ 1/20` (so 4v4 allows k ≤ 3); `P(∃ false win among k comparisons) ≤ k · p_null` (union bound, by counting finite sets) | L1 | `multiplicity_gate`; `union_bound` | M0 / M4 |
| st.11 | Determinism class per count type | `class = deterministic` if all runs equal, `stable` if `max − min ≤ tol`, else `quarantined`; deterministic ⇒ stable; `tol ≤ tol′` ⇒ the class never gets worse | L1 | Stats · `det_class_mono` | M1 |
| st.12 | Validation metrics (V-c, V-d, V-e) | Spearman `ρ = 1 − 6·Σd² / (n(n² − 1))` exactly in ℚ (no ties); sign agreement `sign(p̂) = sign(m)` where `|p̂| > band`; the size band **is defined as the ℚ test** `max(p/m, m/p) ≤ 13499/10000`. It *approximates* `|log(p/m)| ≤ 0.3` but is not the same test: `e^0.3 = 1.34986…`, so ratios in `(1.34986…, 1.3499]` pass the ℚ test and would fail the log test | L1 | Stats · `spearman`, `ratio_band_iff` | M3 |
| st.13 | Block validity (heat, Low Power Mode) | block accepted ⇒ one thermal class throughout ∧ no Low Power Mode | L1-cond (thermal class and LPM come from the device: x.8) | `block_ok_sound` | M3 |

### 2.2 Cost model, screening and calibration status (`Fw/Spec/Cost`, `Screen`, `Model`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| cm.1 | Deployed model is monotone | `c ≥ 0 ∧ x ≤ x′ ⇒ T_c(x) ≤ T_c(x′)`, where `T = κ + Σ c_j·x_j + Σ d_j·1[x_j > 0]`, `k = max(1, ⌈T/I⌉)` and `p90` over frames | L1 | Cost · `mainUs_mono` (P, linear part); `deployed_mono` | M2 |
| cm.2 | Screening soundness (class W) | `∀ f : x^var_f ≤ x^base_f` (per frame, aligned) ⇒ `∀ c ≥ 0, ∀ f : T_c(x^var_f) ≤ T_c(x^base_f)`, and the same for p90 | L1-cond (counts: x.2; alignment: cm.7) | Screen · `screen_sound` | M2 |
| cm.3 | WebKit frame model | `dt = max(T_req, W + F + U + δ)` with `F = max(s²·Ap/R_cg, Bn/R_alloc)` is monotone in every count. A `#guard` keeps a counterexample showing the old `− overlap` form is **not** monotone | L1-cond (model: L3, x.1; the formula is an engine transcription) | Cost · `webkit_mono` | M3 |
| cm.4 | Budgets and vsyncs | `B(r) = ⌊10⁶ / r⌋`; `B(30) ≥ 2·B(60) − 1`; `k(T) = max(1, ⌈T/I⌉)` is monotone | L1 | `budget_lpm`, `vsyncs_mono` | M1 |
| cm.5 | Fit **certificate checker** (the fit itself is L3) | `deploy(c) = ok ⇒ ∀ j : c_j ≥ 0` (so cm.1 and cm.2 apply), with c in ℚ; optional NNLS check: `∇_j ≥ −ε ∧ |c_j·∇_j| ≤ ε` | L1 | Model · `deploy_nonneg` | M3 |
| cm.6 | Model status ladder | `uncalibrated → ranks-only` only if V-c ∧ V-d rows exist; `→ sizes` only if V-e also holds; two device disagreements ⇒ `retired`; status never rises without its evidence rows | L1 | Model · `status_needs_rows` | M3 |
| cm.7 | Frame alignment by content anchor | align(frames, anchors) is order-preserving; equal anchor sequences ⇒ the identity alignment | L1-cond (anchors extracted: x.2) | Screen · `align_mono`, `align_id` | M2 |
| cm.8 | Uncounted-family rule | features(diff) ∩ {filter, backdrop-filter, image or asset, font, new animation, mix-blend, group opacity} ≠ ∅ ⇒ class ≠ W | L1-cond (model: L3, x.1, the family list is an engine transcription; diff parsing: x.9) | Classes · `uncounted_not_W` | M2 |
| cm.9 | Licence for model stand-in | `licensed(cls, build, t) ⇔` 5 of 5 blind verdicts agree ∧ 0 sign disagreements ∧ `t − t_cal ≤ 14 d` ∧ `build = build_cal` ∧ fewer than 2 out-of-band spot-checks; class SM landed without the device ⇒ licensed at land time | L1 | Licence · `sm_land_needs_licence` | M3 |
| cm.10 | Spot-check schedule | after every 5 device-free landings a blind spot-check job is queued: landings since the last spot-check ≤ 5 | L1 | Licence · `spot_every_5` | M3 |

### 2.3 Flags, registry and presets (`Fw/Spec/Flags`, `Fw/Gen/Registry`, `Presets`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| fl.1 | Every part has exactly one variant | `Config = Part → Variant`: true by construction | L1 | (P, by type) | M2 |
| fl.2 | Resolve is sound | `resolve(R, req) = ok c ⇒` every variant exists, and every requires/conflicts rule holds | L1 | `resolve_sound` (P) | M2 |
| fl.3 | One-part A/B isolation | `c(p) ≠ v ⇒ diff(c, c[p ↦ v]) = {p}` | L1 | `override_diff` (P) | M2 |
| fl.4 | The checked-in registry is valid | `wellFormed(registry) = true`, checked by `decide` on the registry generated from `part.json` | L1 | `registry_ok` | M2 |
| fl.5 | Presets and resolution order | the `extends` graph has no cycles ⇒ resolution terminates; the URL beats the preset, which beats the default (the last writer wins) | L1 | Presets · `extends_acyclic`, `url_wins` | M2 |
| fl.6 | Canonical config for the hash | `canon(c) = canon(c′) ⇔ c = c′` (sorted, injective; the hash is x.5) | L1 | `canon_inj` | M2 |
| fl.7 | Ablation sets | every set has a positive arm and ≥ 1 negative sibling on the same base | L1 | `ablation_wf` | M2 |
| fl.8 | Ablation fairness | boxes equal ∧ script and layout counts equal ∧ paint/raster `≤`, with at least one `<` | L1-cond (counts: x.2) | `fair_iff` | M2 |

### 2.4 Parity and part lifecycle (`Fw/Spec/Parity`, `Part`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| pa.1 | Parity bands | PL1 `|b_R − b_A| ≤ 1/2 px`; PL2 `|s_R − s_A| ≤ 10⁻³`; PL5 `|R − A| ≤ max(2, 5 %·A)` (style/layout), `max(2, 10 %·A)` (paint/raster), `R = A` for rAF, forced layouts and layers; all in ℚ; a wider tolerance never turns a pass into a fail | L1-cond (numbers: x.2) | Parity · `band_mono` | M2 |
| pa.2 | Pixel tier decision | `tier(diff, AA)` ∈ T0…T3; more differing pixels ⇒ the tier is never better | L1-cond (pixel diff: x.6) | Parity · `tier_mono` | M2 |
| pa.3 | Part promotion | promoted ⇒ every level its kind requires has passed; `faithful-with-delta` ⇒ time box expired ∧ delta recorded | L1 | Part · `promoted_sound` | M2 |
| pa.4 | Transfer check | `∀ stages s : sign(Δ_R,s) = sign(Δ_A,s)`; cannot be overlaid ⇒ "transfer unchecked" ⇒ class ≠ W | L1-cond (Δ per stage: x.2) | Parity · `transfer_gate` | M2 |
| pa.5 | Compositor gate (optimized variants) | pass ⇔ `compositeFailed = 0` ∧ layers = layerBudget ∧ no filter animation ∧ no scroll-linked writes, unless waived | L1-cond (trace flags: x.1, x.2) | Parity · `comp_gate_iff` | M2 |
| pa.6 | Style-injection guard (MUI) | pass ⇔ no style insertion has a timestamp after `markMeasureStart` | L1-cond (the recording sees every insertion: x.15) | Parity · `no_late_style` | M2 |

### 2.5 Experiment lifecycle and landing (`Fw/Spec/Stage`, `Land`, `Classes`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| ex.1 | Stage lifecycle | the **same `Stage` type as note 02** (`ConsoleV2.lean`): question → build → screen → review → (device) → landReady → land, derived from evidence keyed by commit; a new build sends the card back to screen; device is skipped only when the class does not need it; the stage advances only on its own evidence | L1 | Console · `built_resets` (proved in 02), `stage_own_evidence`, `device_iff_class` | M1 |
| ex.2 | Prediction before data | in every log: `attach(card, data)` accepted ⇒ `predict(card)` was accepted earlier | L1 | Stage · `predict_first` | M1 |
| ex.3 | Landing classifier | `class = W ⇒` per-frame dominance in both engines ∧ uncounted-family rule passes ∧ no style diff (until WKTR) ∧ transfer has the same sign ∧ parity met ∧ layers in budget; X features ⇒ class X | L1 | Classes · `w_sound`, `x_forced` | M2 |
| ex.4 | `land_requires` | `landed ∧ ¬violation ⇒` screen passed ∧ reviewer accepted ∧ (device verdict as declared ∨ licensed(class)) ∧ `k·p ≤ 1/20` ∧ card complete; a `landed` git fact is never refused, and without an accepted request it sets `violation` | L1-cond ("card complete" is a judgement: x.18) | Land · `land_requires` (core proved in 02's `ConsoleV2.lean`) | M2 |
| ex.5 | Signatures | question signed by lead; review by reviewer; device by user; land by lead; reviewer ≠ owner ∧ reviewer ∉ builders | L1-cond (the signer's identity: x.16) | Console · `review_independent` (proved in 02's `ConsoleV2.lean`), `signer_ok` | M1 |
| ex.6 | Time boxes | `requests(agent, task) > box ⇒` a decision record is needed before the next step; a region's box counts all of its parts | L1-cond (counts from op.3, x.15) | Budget · `box_blocks` | M1 |
| ex.7 | Land queue | one lander; fast-forward only; FIFO by ready time; never two lands at once; a land that fails its gate leaves the queue | L1 | Land · `land_fifo`, `land_excl` | M1 |

### 2.6 Console reducer and projections (`Fw/Console/*`) — requirement 1

The console state is `S_n = apply(…apply(S₀, e₁)…, e_n)`. Every row below is a function of the log (and `now`,
which is also an event field).

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| co.1 | Replay is exact | `replay(L₁ ++ L₂) = replayFrom(replay(L₁), L₂)`: a snapshot plus the tail equals a full replay | L1 | `replay_append` (**S**) | M0 |
| co.2 | Duplicate delivery is harmless | `apply(apply(S, e), e) = apply(S, e)` | L1 | `apply_idem` (**S**) | M0 |
| co.3 | Step lifecycle | pending → active → answered \| skipped \| cancelled, plus "start over"; `answered` is absorbing; `#{accepted answer(k)} ≤ 1` on every log; "Done" is refused on parts the runner ends (I-059) | L1 | `stepNext_answered`, `answer_at_most_once` (**S**); `done_refused_runner` | M0 |
| co.4 | "Needs you" is derived | `needsYou(S) ⇔ ∃` open step ∨ open proposal ∨ open decision; e = agent note ⇒ `needsYou(apply(S, e)) = needsYou(S)` | L1 | `note_preserves_needsYou` (**S**) | M0 |
| co.5 | Status row | `row(card) = (stage, owner, next action, ETA, now − t_last, needsYou + action)` is a function of (log, now) only; an agent changes a row field only through an event type in the agent rows of `may` (no event type is "write field X") | L1 | Rows · `row_of_log` (by construction), `agent_events_only` | M1 |
| co.6 | "Waiting for" | `waitingFor ∈ {lead-land, lead-ruling, device, user, agent:x, none}` = f(stage, open jobs, open steps, open `wait.started`, open `decision.requested`) | L1 | Rows · `waiting_derived` | M1 |
| co.7 | Thread routing | every thread has exactly one assignee tier (I-175); one question per thread; a close needs your "answered" click or a typed `thread.close` | L1-cond (whether a reply answered: x.18) | Threads · `one_tier` | M1 |
| co.8 | Proposals | open → decided(accepted \| rejected) \| withdrawn; decided at most once; decided ⇒ the rows that wait on it leave "needs you" in the same event (I-145) | L1-cond (every decision emits its close event: x.15) | Proposals · `decide_once`, `decide_clears` | M1 |
| co.9 | Notice coalescer | at most one notice per (source, kind) per window W; applying the coalescer twice changes nothing | L1 | Notices · `coalesce_le1` | M1 |
| co.10 | Stall watcher | `stalled(a, now) ⇔` a background task ended at t₁ ∧ no event from a after t₁ ∧ `now − t₁ > θ`; exactly one wake message per stall episode | L1-cond (liveness signals: x.15) | Watch · `one_wake` | M1 |
| co.11 | Alarm precision gate | an alarm reaches you only if `TP / (TP + FP) ≥ 9/10` on a labelled replay | L1-cond (labels: x.10) | Watch · `alarm_gate` | M1 |
| co.12 | `contractsVersion` | `v_req ≠ v_server ⇒` refused ("rebase") | L1 | Wire · `version_refuse` | M0 |
| co.13 | Digests | exactly one digest per card stage-change event | L1 | Rows · `one_digest` | M1 |
| co.14 | Bug ledger | every entry has `kind ∈ {request, incident}`; per-module counts by "caught by" are a fold of the ledger (§7.2) | L1 | Ledger · `tally_fold` | M0 |

### 2.7 Queues, devices, sessions (`Fw/Spec/DeviceQueue`, `RunQueue`, `Lease`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| dq.1 | Phone priority with aging | `base(j) = R·class(j) + rank(j)`; `eff_t(j) = base(j) − min(base(j), ⌊(t − enq(j))/A⌋)`; `pick_t(Q) ∈ Q` and `∀ k ∈ Q : pick_t(Q) ≼_t k` | L1 | `pick_mem`, `pick_min` (**S**) | M0 |
| dq.2 | No starvation | `t ≥ enq(j) + A·base(j) ∧ seq(j) < seq(k) ⇒ j ≺_t k`: once a job has aged, no job that arrived later passes it | L1 | `aged_beats_newer` (**S**) | M0 |
| dq.3 | Mutual exclusion | at most one job runs on the phone (by construction); busy ⇒ `dispatch` does nothing | L1 | `dispatch_busy` (**S**) | M0 |
| dq.4 | Booked window, no head-of-line blocking, hard stop | job started at t ⇒ `s ≤ t ∧ t + dur(j) ≤ e` for your booked session `[s, e]`, and **no queued job that also fits goes before it**; phone free ∧ window open ∧ nothing started ⇒ no queued job fits (work conservation); `e ≤ now ⇒` nothing runs after the tick at `now` (a job still running at `e` is killed, so actual run time, which is IO, cannot overrun the window) | L1-cond (a tick is delivered at `e`: x.14) | `dispatch_sound`, `dispatch_conserving`, `tick_kills_at_end` (**S**) | M0 |
| dq.5 | Bounded wait (over a whole trace) | jobs end within `dur` ⇒ `wait(j) ≤ A·base(j) + Σ_{k older than j} dur(k)` | L1 (liveness, harder) | `bounded_wait` | M1 |
| dq.6 | Lease and user step | a hand-over happens ⇒ the owner's step is not on the phone ∨ the grace period has expired (I-122, I-123) | L1 | Lease · `no_handover_on_step` | M1 |
| dq.7 | Re-plug steps | at most one open re-plug step at any time | L1 | DeviceWatch · `replug_le1` | M1 |
| dq.8 | Preflight | probe results → {ok, auto-repair, one get-ready step}; at most one get-ready step per session | L1-cond (probes: x.8) | Preflight · `one_get_ready` | M1 |
| dq.9 | Session bookings | accepted bookings never overlap: `[s₁, e₁) ∩ [s₂, e₂) = ∅` | L1 | Sessions · `no_overlap` | M1 |
| dq.10 | Timing lane | one run at a time; a run whose window had a host-load sample above θ is marked contaminated | L1-cond (load sampling: x.8) | RunQueue · `excl`, `contaminated_iff` | M1 |
| dq.11 | Experiment order is your list | order = sort by (your rank, seq); no agent event type changes a rank; a manual move is an event with a reason | L1 | Priority · `agents_cannot_reorder` | M1 |

### 2.8 Artifacts and the build (`Fw/Spec/ArtifactKey`, `Plan`, `Store`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| ar.1 | Key soundness | `enc(x) = enc(y) ⇒ x = y`; equal stored keys ⇒ the same inputs with the same values (given x.5) | L1-cond (sha256: x.5) | `enc_inj`, `key_sound` (**S**) | M1 |
| ar.2 | Minimal invalidation | `w ≠ v(i) ⇒ (key_v(a) ≠ key_{v[i ↦ w]}(a) ⇔ i ∈ deps(a))`; `stale(A, i) = {a ∈ A : i ∈ deps(a)}`. Bumping tool X's `semantics` invalidates exactly X's artifacts. This is minimality **with respect to the declared deps**; soundness (no stale reuse) needs the declared deps to be complete | L1-cond (declared deps complete: x.17) | `stale_iff`, `stale_spec` (**S**) | M1 |
| ar.3 | `servedHash` closure | `closure(route)` = the smallest set that contains the entry and is closed under imports, dynamic imports, css and assets; editing file f changes `servedHash(route)` ⇔ `f ∈ closure(route)` | L1-cond (the manifest lists every import: x.17; its JSON is decoded in fwcore, w.4) | Plan · `closure_least`, `served_iff` | M1 |
| ar.4 | `fw plan` | `hits ∪ todo = requested`, `hits ∩ todo = ∅`, `hits ⊆ store` | L1 | Plan · `plan_partition` | M1 |
| ar.5 | Golden-semantics gate | output changed ∧ no `semantics` bump ⇒ fail; refactor (same output) ⇒ pass, no invalidation | L1 | Plan · `golden_gate` | M1 |
| ar.6 | Timing samples | append-only: `samples_t ⊆ samples_{t′}` for `t ≤ t′`; the verdict reads all samples except those the contamination rule drops | L1 | Store · `append_only`, `no_cherry_pick` | M1 |
| ar.7 | Cache prune | `pruned ∩ evidence = ∅`; afterwards size ≤ cap, or only evidence is left | L1 | Store · `prune_keeps_evidence` | M1 |

### 2.9 Agent operations (`Fw/Ops/*`)

| # | Item | Math | Lvl | Lean | M |
|---|---|---|---|---|---|
| op.1 | Spawn-guard | over every accepted spawn sequence: teammates ≤ 3; live names are unique; any 10-minute window has ≤ 6 spawns per spawner; an editing `subagent_type` without isolation is denied; `fable` needs the ask path. This bounds **the spawns the PreToolUse hook sees** | L1-cond (every spawn passes the hook: x.15) | Spawn · `teammates_le3`, `names_unique`, `rate_le6` | M0 |
| op.2 | Land-time path check | allowed ⇒ `∀ p ∈ diff, ∃ g ∈ globs(role) : match(g, p)`; glob facts: `**` matches any suffix, `*` never crosses `/` | L1-cond (git diff: x.8) | Paths · `check_sound`, `glob_star_noslash` | M0 |
| op.3 | Usage meter dedupe | `dedupe` keeps the last stream record per message id; it is idempotent and does not depend on file order; `total = Σ` over unique ids. The meter **defines** the cache-write total as `w := w₅ₘ + w₁ₕ`; it does not claim `w₅ₘ + w₁ₕ` equals the API's own `cache_creation_input_tokens`, because that is a property of API data and it fails in v1 (MEASURED: 2 of 248,672 usage records have the total 0 with `w₁ₕ` = 1790; command in §9). A mismatch is logged as a data error | L1-cond (transcript records: x.8; decoded in fwcore, w.4) | Usage · `dedupe_idem`, `dedupe_perm`, `total_def` | M0 |
| op.4 | Price and budget caps | `$ = Σ tokens × price` in ℚ; milestone spend > 115 % of cap ⇒ stop; lead > $50/day ⇒ alarm; weekly use > 80 % ⇒ alert | L1 | Budget · `stop_rule` | M0 |
| op.5 | Roster check | the roster table equals the set of agent files (compared field by field) | L1-cond (YAML parsing: x.9) | Roster · `roster_eq` | M1 |
| op.6 | Knowledge-store rules | two live cards with the same `mechanism` and opposite statuses ⇒ lint fails; claim status ∈ the 5-word vocabulary | L1-cond (YAML parsing: x.9) | Kb · `no_contradiction` | M1 |
| op.7 | Wait policy | expected wait ≥ 1 h, or unknown ⇒ write a handoff note and exit; the waking event spawns a fresh agent with that note | L1 | Ops · `wait_policy` | M1 |

### 2.10 Level 2 (spec in Lean, implementation elsewhere, differential tests)

| # | Item | Why it is not L1 | Test |
|---|---|---|---|
| w.1 = fl.9 | The site's flag resolver | It runs in the browser, before any network call. Lean has no maintained JS backend (INFERRED: none found in [05 §2]) | **Exhaustive, not sampled**: the domain is finite (registry × presets × single-part overrides), so `fwcore flags.enumerate` emits every (preset, part, variant) override with its expected resolution, and the JS resolver is checked on all of them. For that registry version this is as strong as a proof. Random fast-check cases remain only for multi-part URL overrides |
| w.2 | JSON wire codecs (zod ⇄ Lean `deriving ToJson/FromJson`) | Two languages read the same bytes | Golden fixtures emitted by `fwcore samples`, byte-equal round trips both ways (PLAN §3.2, §5.4) |
| w.3 | console-web optimistic preview (for example, greying out an invalid flag combination) | UI latency | The same oracle test as w.1. Rule: the server's answer always wins |
| ~~w.4~~ → **L1-cond** | JSON decoding of hook payloads, transcript usage records and the Vite manifest | Moved to L1 after verification: `fwcore` already decodes JSON with `deriving FromJson` (`Bench.lean`). A typed decoder that **refuses unknown shapes**, plus golden fixtures of the recorded schemas. Only the format assumption ("Claude Code / Vite send this shape") stays L3 (x.9) | Golden fixtures; refusals are logged as `input.rejected` |

**Counts (after verification).** Tables 2.1-2.9 hold 83 rows, and w.4 moves up: **84 L1** = **54 L1-pure** + **30
L1-cond** (st.13; cm.2, cm.3, cm.7, cm.8; fl.8; pa.1, pa.2, pa.4, pa.5, pa.6; ex.4, ex.5, ex.6; co.7, co.8, co.10,
co.11; dq.4, dq.8, dq.10; ar.1, ar.2, ar.3; op.1, op.2, op.3, op.5, op.6; w.4). **3 L2** (w.1, w.2, w.3). 87 items in
all, plus **18 L3 categories** in §3. (w.1 is the same item as fl.9. The first version counted "83 L1, 4 L2, 14 L3"
and did not separate the conditional rows, which overstated what is proved.)

---

## 3. Level 3: what cannot be proved, and why

| # | Item | Why not provable | How it is checked instead | The L1 decision it feeds |
|---|---|---|---|---|
| x.1 | Engine behaviour: vsync quantization, layer promotion, compositor rules, WebKit's 60 Hz hint | A proof about our transcription of an engine rule cannot catch a transcription error (PLAN §5.1) | Rule cards with source file:line@commit; table tests against `compositeFailed` or WKTR | cm.8, pa.5, ex.3 |
| x.2 | Work counts from CDP and Inspector; timeline segments | They come from a running browser | Determinism per count type (st.11), V-a, V-b, V-n | cm.2, pa.1 |
| x.3 | Coefficient fitting (NNLS, constrained τ = 0.9 quantile) | Floating-point numeric optimization | Calibration and holdouts; **checked by the L1 certificate cm.5 before it is deployed** | cm.1, cm.2, cm.6 |
| x.4 | Exchangeability and independence of runs | A statistical assumption about the world | A/A runs, ABBA order, the contamination flag | st.7, st.10 |
| x.5 | sha256 has no collisions on our inputs | A cryptographic assumption, not a theorem | Stated once as an assumption; the encoding under it is proved injective (ar.1) | ar.1-ar.3, fl.6 |
| x.6 | Pixels, screenshots, pixel diffs | Image processing on engine output | Playwright, v1 tiers against A/A | pa.2 |
| x.7 | The React parts, `ScrollEngine`, `MotionClock` | They run in the browser, per frame; no Lean → JS path (w.1) | Parity PL0-PL6, harness routes | fl, pa |
| x.8 | IO: HTTP and SSE, file append and fsync, processes, git, Docker, usbmux, WDA, iwdp, Instruments | Effects in the outside world | Thin adapters with contract suites (fake vs real), `fwcore replay` as a runtime monitor (§4.3) | all |
| x.9 | Parsing: CSS diffs and YAML frontmatter; and the *format assumption* for JSON inputs (hook payloads, transcripts, Vite manifest) | CSS and YAML parsing stay in the TS ecosystem (postcss, yaml). JSON **decoding** is now L1 (w.4); only the assumption that the producer sends the documented shape is L3 | Golden files; the parsed record is typed; unknown JSON shapes are refused | cm.8, op.5, op.6, ar.3, op.3 |
| x.10 | Human judgement: your swipe, look decisions, reviewer "accept" | Judgement | The blind protocol; signatures are events (ex.5) | ex.4, cm.9 |
| x.11 | LLM agent behaviour | Not a formal object | Enforcers read events only (PLAN §2.2); the meter | op.1, ex.6 |
| x.12 | console-web rendering | A UI | Playwright checks of the console; it shows only what `fwcore` projected | co.5 |
| x.13 | `fwcore`'s own speed | A runtime property | Speed-budget test in `lake test` (100k events < 1 s) — the trap in §4.2 | §4 |
| x.14 | The clock | Real time | The single writer stamps `now` on each event; the core never reads a clock, so replay is exact; console-api delivers a `tick` at every window end | co.1, co.10, dq.* |
| x.15 | Completeness of observation: every spawn, commit, hook event, style insertion and decision-close is seen | A hook that does not fire, a commit made with hooks off, or an adapter that forgets an event is invisible to Lean | Reconcilers that re-read the source of truth (git refs, transcripts); adapter tests "every decision emits its close event"; SPK-t | op.1, ex.6, co.8, co.10, pa.6 |
| x.16 | Actor identity and authentication | Who sent a CLI request is decided outside Lean | The PreToolUse capability hook (HMAC over agent type, tool-use id and command) verified by console-api (note 02 §6.4); spoof tests | ex.5, every `may` row |
| x.17 | Declared dependencies are complete | `stale_iff` is minimal w.r.t. the declared deps; if a tool reads an undeclared input, a stale artifact can be reused | A **hermetic run** that records the inputs a tool actually read and fails when they are not a subset of its declared deps | ar.2, ar.3 |
| x.18 | "Answered" and "complete" judgements | Whether a reply answered a question, or a card is complete, is human or LLM judgement | Your click ("answered / not answered"), a typed `thread.close --reason`, the reviewer's verdict | co.7, ex.4 |

---

## 4. Architecture (part c): should the console core be a Lean program?

### 4.1 The options

| | (A) Rev 3 | (B) **`fwcore` as the console brain** (recommended) | (C) Full Lean server | (D) Lean spec + TS reducer |
|---|---|---|---|---|
| Reducer, queues, gates, projections | TS with unit tests; Lean only for verdict, ticks, flags, screen | Lean (L1), held in a long-lived `fwcore serve` | Lean, with `Std.Http` | TS, with differential tests against Lean (L2) |
| TS does | everything except 4 decisions | HTTP, SSE, append to `events.jsonl`, spawning processes, watcher probes, hook bridges | nothing | everything |
| Guarantee | 4 decisions proved | the running reducer *is* the proved function | same as B | agreement on sampled traces only |
| Two implementations to keep in sync | no | no | no | yes, for every rule |
| Risk | v1's bug class (hand-written queues and boards) stays in TS | a young Lean data-structure library; the uniqueness trap (§4.2) | `Std.Http` is six months out of `Internal`, has no WebSocket and no DB binding [05 §2] | drift; double the work (Cedar needed this only because Rust was required [05 §5]) |

### 4.2 Measurements (MEASURED today, `lean-scratch/03-inventory/`)

| What | Value |
|---|---|
| 100k console events (post, start, note, answer × 25k steps) piped through `autobench`, warm | **0.28-0.29 s** (2.8-2.9 µs/event); first, cold-cache run 1.55-2.0 s |
| Same, with the state read by `r.get` and written back by `r.set` | **19.2 s** (66× slower): the `HashMap` is shared, so every `insert` copies it |
| Node 24.14 → `autobench` sequential round trip, 20k events | **17.6 µs** each (note 05 measured ≈141 µs with its own harness; I did not rerun that harness, so the difference is not explained, INFERRED) |
| One request, including process start | 29 ms |
| Clean `lake build` of the scratch project (no dependencies) | 6.3 s; one module re-checked in 0.4-0.6 s |
| `autobench` binary | 101 MB (same as note 05: the runtime plus `Lean.Data.Json` are linked statically) |

v1 load for scale: about 500 `status.mjs set` calls a day (4,914 over the run, MEASURED). Even a hundred times
v1's event rate is a few milliseconds of `fwcore` time a day.

### 4.3 The shape

```
console-web (shadcn) ──HTTP/SSE──▶ console-api (Node 24, Hono)
                                     1. stamp {eid, now}; 2. append to events.jsonl (fsync);
                                     3. send to fwcore serve; 4. publish the projection delta over SSE
pnpm fw verbs, git hooks, Claude Code hooks, watchers ──POST /events──▶ (same path)
                                     │ JSON lines, request ids, timeout + restart (PLAN §3.2)
                                     ▼
                           fwcore serve (Lean, one process, single-threaded)
                             State := fold of the log (co.*, dq.*, ex.*, ar.*, op.*)
                             ops: event → {accepted | refused(reason), changed rows}
                                  query → projections (rows, steps, queues, plan)
                                  decide → stateless decisions (verdict, screen, resolve, …)
```

- **Append first, then apply.** A refused event is still logged. Replay refuses it again in the same way (co.1), so a
  crash between steps 2 and 3 is harmless: on restart, console-api streams the log back in (100k events in 0.3 s).
- **Time is data** (x.14). Timeouts such as lease expiry and stall detection are `tick` events, which are logged too.
- **Runtime monitor.** Nightly, `fwcore replay events.jsonl` runs, and the hash of its projection must equal the live
  one. That catches shell bugs (a lost write, a double apply). This is [05 §4.4]'s monitor, now covering the
  whole console.
- **Requirement 1 in this shape.** Agents never call a status command. Status changes only through events:
  - events made as a side effect of real work: `fw gate`, `fw run`, `fw land`, a commit, a measurement artifact;
  - hook events: spawn, stop, usage;
  - your actions in console-web;
  - the agent-allowed typed judgement events of the merged catalogue (note 01 §5: card open, park, wait, ask-lead,
    hand-back result, review verdict), each refusable by the reducer.

  Notes are inert (co.4). An agent's changes to row fields are therefore limited to the `may` table's agent rows
  (`agent_events_only`, to prove on the merged reducer).

### 4.4 Can agents work in Lean fast enough? (MEASURED in §5, INFERRED beyond it)

- The three sketches took 1-3 build iterations each. Every failure was small and local:
  - a leftover `1 + 0 ≤ 1` goal;
  - `simp` made no progress;
  - a `rw` given a conjunction;
  - deprecated names (`if_true`, `String.mk`).
- **`grind` (Lean 4.35) closed 10 of 11 probe goals with a one-line proof**, including:
  - lex-order transitivity and totality;
  - the aging lemma, with `Nat` division;
  - the `HashMap.getElem?_insert` reasoning in `apply_keeps_answered`;
  - the two-way `stale_iff` (`GrindProbe2.lean` h2, one line);
  - `induction … <;> grind` for `answer_at_most_once` (given its two helper lemmas).

  The one it missed (corrected after verification; the first version reported it backwards) was the `∀` part of
  **`pickFrom_min`** by `induction … <;> grind` (`GrindProbe2.lean` h3, the error at l.10:37). The manual proof is
  `Auto/DeviceQueue.lean` l.64-86.
- Liveness over whole traces (dq.5, bounded wait) is harder than safety. [05 §6.6] already warned of this. Budget
  1-2 agent-days for it, or state it as the key lemma plus a counted argument (what §5 does).
- Agents keep the tooling from [05 §2.1]: `lean-lsp-mcp` (goals, `lean_multi_attempt`, `lean_verify`) and Serena
  `lean4` (SPK-k).
- **Productivity cost of (B).** A console feature becomes "a Lean module change plus a shell or UI change". The TS
  console-builder cannot change behaviour alone. Mitigation: pair `lean-<module>` with `console-<feature>` on one
  branch. The math lines (§6) are the contract the UI reads.

### 4.5 Risks of (B) and their mitigations

| Risk | Mitigation |
|---|---|
| `fwcore` crash takes the console down | Restart and replay take under 1 s; console-api queues events while it restarts and fails nothing silently (PLAN §3.2 items 1-3) |
| The uniqueness trap (66×, MEASURED) | The IO loop is ~30 lines and uses `modifyGet`; `lake test` has a speed budget (100k events < 1 s); `seen` is a `HashSet`, not a list (note 02's list-based sketch would be O(n²) per replay) |
| Data-structure lemma names change on toolchain bumps (`Std.HashMap` API) | Pin the toolchain; bump in one PR (PLAN R11); prefer `grind` proofs, which do not name lemmas |
| Wrong spec, correct proof (PLAN R6) | The docstring math plus a reviewer sign-off on the deep statement hash, enforced by the build (§6, note 04); mutants (§7.2) |
| Every console change needs Lean skill | Lean-first role pairing (§4.4); demotion rule (§7.3) |
| The 101 MB binary | Irrelevant locally |

**Recommendation: (B).** It removes the bug class v1 actually had (hand-written queues and boards, 40 scheduler
incidents, 9 hand-kept-status incidents) at measured costs well inside budget. (D) doubles the work. (C) fights the
ecosystem. (A) leaves exactly v1's failure areas in unproved TS.

---

## 5. Sketches (part d)

All of them are in `research/kickoff/10-automation-and-proof/lean-scratch/03-inventory/`, a self-contained Lake
project. They have no dependencies and use toolchain `leanprover/lean4:v4.35.0`. `05-lean-sketch` was not modified.

| Sketch | File | Lines | Theorems | `#guard` examples | Build iterations to green | Wall clock from start of writing to green (MEASURED, model time) |
|---|---|---|---|---|---|---|
| 1. Console reducer | `Auto/Console.lean` | 212 | 9 | 4 | 2 | ≈ 49 s |
| 2. Device queue | `Auto/DeviceQueue.lean` | 236 (171 before the fix) | 12 (10 before) | 8 (4 before) | 1, plus 2 for the fix | ≈ 39 s (fix not timed) |
| 3. Artifact keys | `Auto/ArtifactKey.lean` | 127 | 6 | 3 | 3 | ≈ 42 s |
| Math↔Lean tag check (§6; superseded) | `Auto/MathDoc.lean` | 50 | — | demo + mutant | 4 (API names on 4.35) | not timed separately |

What was checked on every proved theorem:
- `#print axioms` lists only `propext`, `Classical.choice` and `Quot.sound` (`Axioms.lean`);
- the policy grep finds no `sorry`, `native_decide`, `implemented_by` or `unsafe`.

The wall-clock column measures model time. Each sketch had a known design from this note; production modules with
wire ops and more cases will take longer (INFERRED: 0.5-1 agent-hour per module).

**Sketch 1: console reducer.**
- **Model.** Steps live in a `Std.HashMap`, and seen event ids in a `Std.HashSet`, so the proofs are about the data
  structures the executable really uses.
- **Theorems:**
  - `replay_append` (co.1);
  - `apply_idem` (co.2);
  - `stepNext_answered`, `apply_keeps_answered`, `apply_answer_sets`, `answers_after_answered` and
    **`answer_at_most_once`**: `∀ log, ∀ S : #{accepted answer(k) in log} ≤ 1`;
  - **`note_preserves_needsYou`**.
- **Limits.** Proposals, threads and cards are not modelled. I-059 is not encoded. **There is no actor or
  authority**, so this sketch does not show requirement 1 by itself; the merged module takes note 02's semantics.

**Sketch 2: device queue.**
- **Model.** `before t j k` is the order `≼_t` (most urgent first). `pick` folds over the queue and keeps the best
  job so far.
- **Theorems:**
  - `before_total`, `before_trans`;
  - `pick_mem`, `pick_min`;
  - **`aged_beats_newer`** (no starvation: an aged job goes before, and is never passed by, any job that arrived
    later);
  - `dispatch_busy` (mutual exclusion);
  - **`dispatch_sound`**: the started job is a queued job, fits your booked window, and no queued job that also
    fits goes before it;
  - **`dispatch_conserving`** (added after verification): a free phone in an open window that starts nothing has
    no queued job that fits, so a short user step is never kept waiting behind a long job that does not fit (the
    first version started nothing in that case, the I-011 "short lane starves" class);
  - **`tick_kills_at_end`**: at or after the window end, nothing runs.
- **Examples (`#guard`):**
  - a fresh user step beats an older spot-check;
  - a fully aged spot-check beats a brand-new user step;
  - a 900 s job does not start in a 600 s window;
  - window 600 s, an aged 900 s spot-check and a 120 s user step: the old `dispatchHoL` starts nothing, the fixed
    `dispatch` starts the user step;
  - the tick at the window end stops a running job.
- **Limit.** The full trace bound dq.5 is not proved; this sketch proves its key lemma.

**Sketch 3: artifact keys.**
- **Model.** `key_v(a) = ⟨(i, v(i)) : i ∈ deps(a)⟩`. The bytes are a length-prefixed encoding,
  `enc(x₁, …, xₙ) = ⟨|x₁|⟩ ⧺ x₁ ⧺ ⋯ ⧺ ⟨|xₙ|⟩ ⧺ xₙ` (each field's length, then the field; ⧺ is concatenation), and
  `dec` is its decoder.
- **Theorems:**
  - `dec_enc`: `dec(enc(x)) = x`;
  - `enc_inj`: equal bytes ⇒ equal field lists;
  - `fields_inj`;
  - **`key_sound`**: equal encoded keys ⇒ the same deps and the same values;
  - **`stale_iff`**: minimal invalidation, as in ar.2;
  - `stale_spec`: the stale list is exactly the filter.
- **Examples (`#guard`):** a semantics bump of X marks `[artX]`; an engine bump marks both artifacts.
- **Assumption.** sha256 (x.5) is assumed, not proved.

---

## 6. Requirement 3: math you can read, kept in sync by the build

**The first prototype (`#math_doc`) does not keep math and Lean in sync.** Each theorem's docstring carried a line
`math[<tag>]: <formula>`, where `<tag>` was a 16-bit FNV-1a hash of the pretty-printed statement, and
`#math_doc <namespace>` printed the table and failed on a missing line or a changed tag. Verification ran three
probes from `lean-scratch/03-inventory` (MEASURED):
1. **Retag only.** In `MathDemoMut.lean`, changing the tag to the new value `f52c` while leaving the math as
   `t ≤ t'` (the Lean now says `t < t'`) builds green. The check notices that a statement changed, but it does not
   make anyone re-read the math; whoever edits the theorem can retag it.
2. **Definition bodies are invisible.** The tag hashes the printed type, which names definitions such as `needsYou`
   but not their bodies. Changing `def needsYou … (· > 100)` to `(· < 5)` keeps tag `14f3` and passes. Yet the
   definitions (`may`, `stage`, `ready`, `eff`) are most of the spec.
3. **Imported modules are skipped.** `#math_doc Auto` in a file that imports `Auto` prints an empty table and
   passes: the loop iterates `env.constants.map₂`, which holds only the current file's constants. A central
   `#math_doc Fw` would pass vacuously.

**Replacement (adopted for rev 5): note 04's pipeline, with these properties.**
- **All `Fw` modules.** The exporter (`lake exe mathview`) imports the compiled `Fw` environment and walks
  `env.constants.toList`, keeping constants whose module (`env.getModuleIdxFor?`) is under `Fw`.
- **Deep hash.** The statement hash covers the statement **and** the transitive closure of the bodies of the
  non-theorem definitions it references inside `Fw` (`Expr.getUsedConstants`, recursively). Note 04 §2.4 MEASURED
  that changing `minRuns := 3` to `4` changes the hash of `better_needs_runs` although its printed signature is
  identical. 64-bit hashes, not 16.
- **The sign-off is owned by the reviewer, not by the editor.** The accepted hash per declaration lives in a
  reviewer-owned file (`docs/proofs/signoff.json`, or note 04's `math.lock.json`: `name → {stmtHash, mathHash,
  reviewed}`), writable only by the math-reviewer role through `mathview accept`, or by you through console-web.
  An agent that edits a theorem cannot re-sign it.
- **Definitions too.** Every `def` you read (for example `may`, `stage`, `ready`, `stale`, `eff`) gets its own math
  line, so a body change shows up as a stale *definition* entry, not only as stale theorems.
- **Generated page.** `lake exe mathview` builds the page you read (math, English line, status chips; the Lean
  collapsed for reviewers). It is regenerated on every build and never edited by hand.
- A toolchain bump can change hashes; `mathview accept --toolchain-bump` re-accepts only entries whose signature
  text and mechanical LaTeX are unchanged, and that PR gets one review.

## 7. Staged rollout (part e): Lean-first, with evidence

### 7.1 Modules by milestone (replaces PLAN §3.4 Lean row, §5.1 tiers and Q12)

| Milestone | Lean modules (inventory rows) | Why then |
|---|---|---|
| **M0** (Day 1-5) | Hardened wire + `fwcore serve` loop with request ids, the blank-line reply and `modifyGet` (w.2, co.12); JSON decoders for hook payloads and usage records (w.4); **Console core** (merged reducer: note 02's actors, cards, authority and landing on this sketch's data structures): co.1-co.5, co.14 (steps are the Day 4-5 console feature); Frames, Verdict, null rate, multiplicity gate (st.1-st.7, st.10 gate); **DeviceQueue** dq.1-dq.4 (the first phone or Simulator step needs it); **Ops**: op.1 spawn-guard, op.2 path check, op.3-op.4 meter and budget (the hooks go in on Day 3); **`mathview` lint + reviewer sign-off gate** (note 04) | Everything a console step, a hook or a verdict touches is proved before you are asked anything |
| **M1** (Day 6-13) | Artifact keys, plan, store (ar.1-ar.7); rows and projections, threads, proposals, notices, stall watcher, digests (co.5-co.13); queues dq.5-dq.11; stage lifecycle, predict-first, signatures, time boxes, land queue (ex.1, ex.2, ex.5-ex.7); determinism class (st.11); budgets and vsyncs (cm.4); ops op.5-op.7 | The artifact store and run builder arrive in M1; the console skeleton reads only projections |
| **M2** (Day 14-18) | Flags and presets (fl.1-fl.8) + the w.1 oracle; parity and part lifecycle (pa.1-pa.6); screen, alignment, uncounted families, landing classifier, `land_requires` (cm.1, cm.2, cm.7, cm.8, ex.3, ex.4) | The pilot parts are the first users |
| **M3** (Day 19-23) | Model ladder, fit certificate, WebKit model, licence, spot-checks, validation metrics, block validity (cm.3, cm.5, cm.6, cm.9, cm.10, st.12, st.13) | Calibration starts |
| **M4** (Day 24-33) | Sequential ABBA, Hodges–Lehmann, union bound (st.8, st.9, st.10 theorem); **per-module evidence review** (§7.3), not a go/no-go | Used from M5 on |
| **M5-M6** | Only modules that an incident or a new decision calls for | — |

Budget (INFERRED). Rev 3 gives `lean` $280 (PLAN §8.4). The modules above are about 20 Lean files, roughly
4-6k lines: the sketches average 170 lines per area, and production adds wire ops and cases. Estimate
**$700-1,100**, mostly in M0-M2. Most of it moves from console-builder TS work that Lean now does. You chose speed
over token savings, so this fits.

### 7.2 Evidence: the bug ledger plus mutants

- **Ledger** (`results/bugs/ledger.jsonl`, reduced by co.14). Each entry has:
  - `{kind: request|incident, module, level: L1|L2|L3, caughtBy: proof|build-mutant|property-test|adapter-test|replay-monitor|user|escaped, wouldProofCatch: yes|no|n/a}`;
  - **escaped logic bugs in L1 modules (PLAN V-m: target 0)**, kept separate from adapter bugs.
- **Mutants.** Each L1 module ships `FwTest/Mutants/<module>/*.patch`: v1 bugs put back on purpose. A
  `lake test` step applies each patch and expects `lake build` to fail ([05 §0 item 3] did this by hand for I-091
  and I-113). The kill rate must be 100 %; a surviving mutant means the theorem has no teeth. Seed list:

  | Incident | Mutant | Must break |
  |---|---|---|
  | I-091 | renew shortens the lease | renew theorem |
  | I-113 | re-queue loses its place | re-queue theorem |
  | I-145 | a needs-you flag an agent can set | `note_preserves_needsYou` |
  | I-059 | Done accepted on a runner-ended part | co.3 |
  | I-185 | queue ignores priority | `pick_min` |
  | I-011 | no aging | `aged_beats_newer` |
  | I-011 (variant) | head-of-line blocking: start nothing when the most urgent job does not fit | `dispatch_conserving` |
  | I-041 | two holders at once | `dispatch_busy` |
  | (design) | a semantics bump that misses one artifact | `stale_iff` |
  | (design) | the old `− overlap` cost form | cm.3 |

### 7.3 Demotion rule (replaces "go/no-go at M4")

A module drops from L1 to L2 by a decision record when either condition holds:
- its proofs cost more than **1 agent-day on each of two consecutive changes** while the ledger shows 0 bugs caught
  by its proofs or mutants;
- it blocks a console feature for more than 1 working day.

Demotion means the Lean spec stays as the oracle, and a TS implementation runs under the w.1-style differential
test. At M4, the lead reviews the per-module table (caught by proof, by mutant, by test; escaped; cost) and writes
one decision record per demotion. Lean as a whole is not on trial.

---

## 8. Proposed changes to the plan (for the plan owner; PLAN.md not edited)

Superseded by `docs/plan/rev5-delta.md`, which merges this list with notes 01, 02 and 04. The main ones from here:
- **§3.3.** Default "in `fwcore`" now also covers bookkeeping: queues, projections, the plan's set difference.
  Priority is a proved function (dq.1).
- **§3.1 and §3.2.** `fwcore serve` is stateful and the projection source.
- **§3.4.** The Lean row becomes §7.1.
- **§5.1.** The inventory replaces the tier table.
- **§5.3.** Every theorem and every definition you read has docstring math; the build checks the deep hash against
  the reviewer-owned sign-off (§6).
- **Q12.** Lean-first with demotion.
- **§1.2 V-l and V-m.** Extended to every L1 module, plus a mutant kill rate of 100 %.
- **§8.4.** The Lean column rises to $700-1,100.
- **§11.** Two new risks: the uniqueness trap, and re-accepting hashes after a toolchain bump.

---

## 9. Reproduce

```sh
# Sketches, axioms, grind probes, math sync (lean-scratch/03-inventory)
cd research/kickoff/10-automation-and-proof/lean-scratch/03-inventory
~/.elan/bin/lake build                                 # proofs + #guard; 6.3 s clean
~/.elan/bin/lake env lean Axioms.lean                  # only propext / Classical.choice / Quot.sound
~/.elan/bin/lake env lean GrindProbe.lean              # 7 one-line grind proofs, no errors
~/.elan/bin/lake env lean GrindProbe2.lean             # 1 error at l.10:37: grind fails on h3, pickFrom_min's ∀ part
~/.elan/bin/lake env lean MathDemo.lean                # prints the math table
~/.elan/bin/lake env lean MathDemoMut.lean             # fails: "statement changed … re-tag the math"
grep -nE '\bsorry\b|native_decide|implemented_by|unsafe' Auto/*.lean   # no output

# Speed (MEASURED 0.28-0.29 s warm; 17.6 µs per Node round trip)
node gen-events.mjs > events100k.jsonl
/usr/bin/time -p ./.lake/build/bin/autobench < events100k.jsonl > /dev/null
node bench-roundtrip.mjs ./.lake/build/bin/autobench events100k.jsonl
# The 19.2 s variant: Bench-shared-ref.lean.txt (r.get, then r.set) copied over Bench.lean, then rebuild

# v1 counts (MEASURED; raw transcripts, never printed)
RAW=<v1 transcripts dir>
find $RAW -name '*.jsonl' -print0 | xargs -0 cat \
 | jq -c 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | {id: .id, c: .input.command}' \
 | sort -u > v1-bash.jsonl
wc -l < v1-bash.jsonl                                                    # 105638 unique Bash tool calls
grep -Ec 'status\.mjs set' v1-bash.jsonl                                 # 4914
grep -Ec 'tools/(status|finding|incident|console|lock|wait)\.mjs' v1-bash.jsonl   # 28696
grep -Ec 'lock\.mjs status' v1-bash.jsonl                                # 6423 ([08] B14: 6424 incl. Monitor)
# op.3: cache-write split vs the API total (2 of 248,672 records disagree)
find $RAW -name '*.jsonl' -print0 | xargs -0 cat | grep '"cache_creation"' \
 | jq -r 'select(.type=="assistant")|.message.usage|select(.cache_creation!=null)|if ((.cache_creation.ephemeral_5m_input_tokens//0)+(.cache_creation.ephemeral_1h_input_tokens//0))==(.cache_creation_input_tokens//0) then "eq" else "neq" end' \
 | sort | uniq -c
# v1 status-board incidents (25 regex matches; 9 selected by hand as hand-kept-status cases)
jq -r '.[] | "\(.id)\t\(.title)"' ../fastwork-com-web-optimize/console/incidents.json | grep -iE 'status|board|stale'
```

## 10. Open questions for you

1. Do you accept **(B) `fwcore` as the console brain**? The console's behaviour would be written in Lean; the TS
   side would only move data. The alternative is rev 3's TS console, with Lean for 4 decisions.
2. Is **the math page** (generated from docstrings, LaTeX rendered as MathML, one entry per theorem and definition,
   the build blocks an entry whose deep hash the reviewer has not signed) the format you want to read?
3. **Aging step A** for the phone queue: the sketch uses A = 300 s per priority level. A spot-check (class 3) then
   overtakes newly arriving user steps after about 25 h of waiting at the sketch's R = 100. Do you want a faster
   bound, for example at most 2 h for any job?
4. Do you accept the **demotion rule** (§7.3) in place of "Lean go/no-go at M4"?

## Sources

- Plan and kickoff notes:
  - `docs/plan/PLAN.md` rev 3: §2.2, §3.1-§3.4, §4.3, §5.1-§5.4, §6.2-§6.6, §8.2-§8.5, §9.2, §10, §12 Q12.
  - [05] `research/kickoff/05-lean-proofs-and-backend.md`: §0, §1, §2, §2.1, §3, §4.4, §5, §6.
  - [06] `research/kickoff/06-architecture-and-tooling.md`: §2.5, §3.1-§3.4.
  - [08] `research/kickoff/08-chat-forensics/README.md`: lines 51, 65, 86, 273-288, B14 at l.749-750.
  - [10-01] `research/kickoff/10-automation-and-proof/01-v1-console-manual-work.md`: §1.1.
  - [10-02]: the sibling event-design note, referenced by name only.
- Lean sketch 05: `research/kickoff/05-lean-sketch/`:
  - `Fw/Spec/{Frames,Verdict,Flags,Cost,Stage,Lease}.lean`;
  - `Fw/Wire.lean`;
  - `Main.lean`, l.7-10 (blank lines get no reply).
- v1, read only, at `eae1bb99`:
  - `tools/status.mjs` l.1-60: the agent-maintained status protocol, with 14 states and `set` at every transition;
  - `CLAUDE.md` l.383-390, l.455: "report your workstream's state at every transition", "set your board row before
    any wait";
  - `tools/lib/phone-step.mjs` l.1-25: the step and lease rules, I-123;
  - `console/incidents.json`: I-011, I-041, I-044, I-049, I-058, I-059, I-091, I-108, I-113, I-122, I-123, I-145,
    I-152, I-162, I-175, I-183, I-185, I-248, I-265.
- Lean 4.35.0 toolchain (`~/.elan`):
  - `Std.HashMap` lemma `getElem?_insert`;
  - `IO.Ref.modifyGet`;
  - `Lean.findDocString?`;
  - `#print axioms`;
  - deprecations seen: `if_true` → `ite_true`, `String.mk` → `String.ofList`.
- Scratch, this note: `research/kickoff/10-automation-and-proof/lean-scratch/03-inventory/`. The files are:
  - `Auto/{Console,DeviceQueue,ArtifactKey,MathDoc}.lean`;
  - `Axioms.lean`, `GrindProbe.lean`, `GrindProbe2.lean`;
  - `MathDemo.lean`, `MathDemoMut.lean`;
  - `Bench.lean`, `Bench-shared-ref.lean.txt`;
  - `gen-events.mjs`, `bench-roundtrip.mjs`.
