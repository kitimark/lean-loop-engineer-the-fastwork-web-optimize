import Lean.Data.Json
/-!
# Premise registry: every empirical browser premise a theorem relies on has a named browser test

Lean proves "premises $\Rightarrow$ conclusion". A premise about a real browser (Chromium, WebKit) is empirical: when
it is false the proof silently stops applying (that is how the base engine model overcounted, and how the gate
sampled unsettled pages). This module is the registry of those premises and the two pure checks around it.

* `registry`: per premise its id, statement (LaTeX), the theorems that assume it, the engines it must hold on, and the
  id of the browser test that asserts it (`packages/premise-tests`, run on CI on both engines).
* `premiseLint`: the premises without a test, and the tests that name an unknown premise (`premiseLint_sound`).
* `flagged`: given the CI results, the premises whose test failed (or is missing) on an engine they need, with the
  theorems that assume them (`flagged_eq_nil_iff`, `flagged_of_fail`). A failing premise test is a finding.

Golden vectors (`packages/contracts/golden/ops/premise.jsonl`): the registry rows, lint cases and flag cases. The TS
side (`apps/runner/src/premises.ts`, `fw premises`) is checked against them. Generate, never by hand:

```
cd lean && lake env lean --run scripts/PremiseGolden.lean           # write the file
cd lean && lake env lean --run scripts/PremiseGolden.lean --check   # fail if it is stale
```

A theorem name starting with `planned:` is a task that will state the theorem (not yet a declaration); `fw premises`
checks every other name against the Lean sources.
-/
namespace Fw.Ops.Premise
open Lean

/-- The two engines a premise is tested on.

$$\mathrm{Engine} = \{\mathrm{chromium},\ \mathrm{webkit}\}$$
-/
inductive Engine where
  | chromium | webkit
deriving DecidableEq, Repr

/-- The engine's name in the JSON files.

$$\operatorname{name}(\mathrm{chromium}) = \texttt{chromium},\quad \operatorname{name}(\mathrm{webkit}) = \texttt{webkit}$$
-/
def Engine.name : Engine → String
  | .chromium => "chromium"
  | .webkit => "webkit"

/-- One registered premise.

$$p = (\mathrm{id},\ \mathrm{statement},\ \mathrm{theorems},\ \mathrm{engines},\ \mathrm{testId})$$
-/
structure Premise where
  id : String
  statement : String
  theorems : List String
  engines : List Engine
  testId : String

/-- A test as the test package declares it: its id and the premise it names.

$$t = (\mathrm{id},\ \mathrm{premise})$$
-/
structure TestRef where
  id : String
  premise : String

/-- One CI result: the test, the engine it ran on, and whether its assertions held.

$$r = (\mathrm{testId},\ e,\ \mathrm{ok})$$
-/
structure Result where
  testId : String
  engine : Engine
  ok : Bool

/-! ## Lint -/

/-- The test reference a registered premise expects.

$$\operatorname{ref}(p) = (p.\mathrm{testId},\ p.\mathrm{id})$$
-/
def Premise.ref (p : Premise) : TestRef := ⟨p.testId, p.id⟩

/-- Premise `p` has a test among `ts`: one with its test id that names it.

$$\operatorname{tested}(ts, p) \iff \exists t \in ts:\ t.\mathrm{id} = p.\mathrm{testId} \land t.\mathrm{premise} = p.\mathrm{id}$$
-/
def tested (ts : List TestRef) (p : Premise) : Bool :=
  ts.any fun t => t.id == p.testId && t.premise == p.id

/-- Test `t` is registered: some premise names it as its test and is the premise `t` names.

$$\operatorname{registered}(ps, t) \iff \exists p \in ps:\ p.\mathrm{id} = t.\mathrm{premise} \land p.\mathrm{testId} = t.\mathrm{id}$$
-/
def registered (ps : List Premise) (t : TestRef) : Bool :=
  ps.any fun p => p.id == t.premise && p.testId == t.id

/-- The lint result: premise ids without a test, and ids of tests that name an unknown premise.

$$\mathrm{Lint} = (\mathrm{untested},\ \mathrm{unknown})$$
-/
structure Lint where
  untested : List String
  unknown : List String
deriving DecidableEq, Repr

/-- **The premise lint.**

$$\operatorname{lint}(ps, ts) = \big(\,[p.\mathrm{id} \mid p \in ps,\ \neg\operatorname{tested}(ts, p)],\ [t.\mathrm{id} \mid t \in ts,\ \neg\operatorname{registered}(ps, t)]\,\big)$$
-/
def premiseLint (ps : List Premise) (ts : List TestRef) : Lint where
  untested := (ps.filter fun p => !tested ts p).map (·.id)
  unknown := (ts.filter fun t => !registered ps t).map (·.id)

/-- **Lint soundness.** The lint is empty iff every premise is tested and every test is registered.

$$\operatorname{lint}(ps, ts) = (\varnothing, \varnothing) \iff \big(\forall p \in ps\ \exists t \in ts:\ t.\mathrm{id} = p.\mathrm{testId} \land t.\mathrm{premise} = p.\mathrm{id}\big) \land \big(\forall t \in ts\ \exists p \in ps:\ p.\mathrm{id} = t.\mathrm{premise} \land p.\mathrm{testId} = t.\mathrm{id}\big)$$

A premise without a test, or a test that names no premise, makes the lint fail; nothing else does. -/
theorem premiseLint_sound (ps : List Premise) (ts : List TestRef) :
    premiseLint ps ts = ⟨[], []⟩ ↔
      (∀ p ∈ ps, ∃ t ∈ ts, t.id = p.testId ∧ t.premise = p.id) ∧
      (∀ t ∈ ts, ∃ p ∈ ps, p.id = t.premise ∧ p.testId = t.id) := by
  simp only [premiseLint, Lint.mk.injEq, List.map_eq_nil_iff, List.filter_eq_nil_iff, tested, registered,
    Bool.not_eq_true', List.any_eq_false, Bool.and_eq_true, beq_iff_eq, Classical.not_forall, Classical.not_not]
  constructor
  · rintro ⟨h1, h2⟩
    exact ⟨fun p hp => by simpa [and_left_comm] using h1 p hp, fun t ht => by simpa [and_left_comm] using h2 t ht⟩
  · rintro ⟨h1, h2⟩
    exact ⟨fun p hp => by simpa [and_left_comm] using h1 p hp, fun t ht => by simpa [and_left_comm] using h2 t ht⟩

/-- **The registry's own references are lint-clean.** If the test package declares exactly the tests the registry
names, the lint is empty (for any registry).

$$\operatorname{lint}\big(ps,\ [\operatorname{ref}(p) \mid p \in ps]\big) = (\varnothing, \varnothing)$$

A registry cannot lint itself into a failure; only a test package that drifts from it can. -/
theorem premiseLint_self (ps : List Premise) : premiseLint ps (ps.map Premise.ref) = ⟨[], []⟩ := by
  rw [premiseLint_sound]
  refine ⟨fun p hp => ⟨p.ref, List.mem_map_of_mem hp, rfl, rfl⟩, fun t ht => ?_⟩
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp ht
  exact ⟨p, hp, rfl, rfl⟩

/-- **Dropping a test is caught.** If a premise is registered and no declared test carries its test id and names it,
the premise is in the lint's `untested` list.

$$p \in ps \land (\forall t \in ts:\ \neg(t.\mathrm{id} = p.\mathrm{testId} \land t.\mathrm{premise} = p.\mathrm{id})) \Rightarrow p.\mathrm{id} \in \operatorname{lint}(ps, ts).\mathrm{untested}$$
-/
theorem untested_of_missing (ps : List Premise) (ts : List TestRef) (p : Premise) (hp : p ∈ ps)
    (h : ∀ t ∈ ts, ¬(t.id = p.testId ∧ t.premise = p.id)) : p.id ∈ (premiseLint ps ts).untested := by
  simp only [premiseLint, List.mem_map, List.mem_filter, Bool.not_eq_true', tested, List.any_eq_false,
    Bool.and_eq_true, beq_iff_eq]
  exact ⟨p, ⟨hp, fun t ht => h t ht⟩, rfl⟩

/-! ## Flagging theorems from CI results -/

/-- The premise holds on engine `e` in the results `rs`: the test ran on `e` at least once and every run passed.

$$\operatorname{holds}(rs, p, e) \iff \big(\exists r \in rs:\ r.\mathrm{testId} = p.\mathrm{testId} \land r.\mathrm{engine} = e\big) \land \big(\forall r \in rs:\ r.\mathrm{testId} = p.\mathrm{testId} \land r.\mathrm{engine} = e \Rightarrow r.\mathrm{ok}\big)$$
-/
def holds (rs : List Result) (p : Premise) (e : Engine) : Bool :=
  let m := rs.filter fun r => r.testId == p.testId && r.engine == e
  !m.isEmpty && m.all (·.ok)

/-- The premise holds on every engine it needs.

$$\operatorname{premiseHolds}(rs, p) \iff \forall e \in p.\mathrm{engines}:\ \operatorname{holds}(rs, p, e)$$
-/
def premiseHolds (rs : List Result) (p : Premise) : Bool :=
  p.engines.all (holds rs p)

/-- **The flagged premises**: those that do not hold on some engine they need (failed or missing). Their `theorems`
are the theorems whose proof no longer applies.

$$\operatorname{flagged}(ps, rs) = [\,p \in ps \mid \neg\operatorname{premiseHolds}(rs, p)\,]$$
-/
def flagged (ps : List Premise) (rs : List Result) : List Premise :=
  ps.filter fun p => !premiseHolds rs p

/-- `holds` unfolded: a run exists and every run passed.

$$\operatorname{holds}(rs, p, e) \iff (\exists r \in rs:\ r.\mathrm{testId} = p.\mathrm{testId} \land r.\mathrm{engine} = e) \land (\forall r \in rs:\ r.\mathrm{testId} = p.\mathrm{testId} \Rightarrow r.\mathrm{engine} = e \Rightarrow r.\mathrm{ok} = \top)$$
-/
theorem holds_iff (rs : List Result) (p : Premise) (e : Engine) :
    holds rs p e = true ↔
      (∃ r ∈ rs, r.testId = p.testId ∧ r.engine = e) ∧
      ∀ r ∈ rs, r.testId = p.testId → r.engine = e → r.ok = true := by
  simp only [holds, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, List.all_eq_true,
    List.mem_filter, beq_iff_eq, ne_eq, List.eq_nil_iff_forall_not_mem]
  constructor
  · rintro ⟨h1, h2⟩
    refine ⟨?_, fun r hr a b => h2 r ⟨hr, a, b⟩⟩
    exact Classical.byContradiction fun hc => h1 (fun r hr => hc ⟨r, hr.1, hr.2.1, hr.2.2⟩)
  · rintro ⟨⟨r, hr, a, b⟩, h⟩
    exact ⟨fun hn => hn r ⟨hr, a, b⟩, fun r hr => h r hr.1 hr.2.1 hr.2.2⟩

/-- **Flag soundness.** Nothing is flagged iff every premise has, on every engine it needs, a run of its test and
every such run passed.

$$\operatorname{flagged}(ps, rs) = [\,] \iff \forall p \in ps\ \forall e \in p.\mathrm{engines}:\ \operatorname{holds}(rs, p, e)$$
-/
theorem flagged_eq_nil_iff (ps : List Premise) (rs : List Result) :
    flagged ps rs = [] ↔ ∀ p ∈ ps, ∀ e ∈ p.engines, holds rs p e = true := by
  simp [flagged, premiseHolds, List.filter_eq_nil_iff]

/-- **A failing premise test flags its premise.** One failing run of the test on an engine the premise needs puts the
premise (hence its theorems) in the flagged list, whatever else passed.

$$p \in ps \land e \in p.\mathrm{engines} \Rightarrow p \in \operatorname{flagged}\big(ps,\ (p.\mathrm{testId}, e, \bot) :: rs\big)$$
-/
theorem flagged_of_fail (ps : List Premise) (rs : List Result) (p : Premise) (hp : p ∈ ps) (e : Engine)
    (he : e ∈ p.engines) : p ∈ flagged ps (⟨p.testId, e, false⟩ :: rs) := by
  simp only [flagged, List.mem_filter, Bool.not_eq_true', premiseHolds, List.all_eq_false]
  refine ⟨hp, e, he, ?_⟩
  cases h : holds (⟨p.testId, e, false⟩ :: rs) p e
  · simp
  · have := ((holds_iff _ _ _).mp h).2 ⟨p.testId, e, false⟩ (List.mem_cons_self ..) rfl rfl
    cases this

/-- **A missing test run flags too.** If no result exists for the premise's test on an engine it needs, the premise is
flagged: absence is not a pass.

$$p \in ps \land e \in p.\mathrm{engines} \land (\forall r \in rs:\ \neg(r.\mathrm{testId} = p.\mathrm{testId} \land r.\mathrm{engine} = e)) \Rightarrow p \in \operatorname{flagged}(ps, rs)$$
-/
theorem flagged_of_missing (ps : List Premise) (rs : List Result) (p : Premise) (hp : p ∈ ps) (e : Engine)
    (he : e ∈ p.engines) (h : ∀ r ∈ rs, ¬(r.testId = p.testId ∧ r.engine = e)) : p ∈ flagged ps rs := by
  simp only [flagged, List.mem_filter, Bool.not_eq_true', premiseHolds, List.all_eq_false]
  refine ⟨hp, e, he, ?_⟩
  cases hh : holds rs p e
  · simp
  · obtain ⟨⟨r, hr, a, b⟩, _⟩ := (holds_iff _ _ _).mp hh
    exact absurd ⟨a, b⟩ (h r hr)

/-! ## The registry -/

-- Both engines.
private def both : List Engine := [.chromium, .webkit]

/-- **The registry.** Every empirical browser premise a Lean theorem relies on, its theorems and its test. Sources: the
gate-settle and fix-commission tasks, `Fw.Engine.Core` (`frameWorkE`, forced updates R4) and `Lessons`, and the
premises of `research/findings/ledger.json` that a static page can assert (R3, R5, `Faithful`, the `inherits` premise,
the allow-list premise AL, the write-on-change premises, IO delivery), and the grid alignment premises of `Fw.Gate.AlignEquiv` (gate-align-equiv). Premises that need engine counters
(compositing bits, per-stage counts) stay with the engine-check lane (`fw engine-check`, tests F0-F4).

$$\operatorname{registry} = [p_1, \dots, p_{17}]$$
-/
def registry : List Premise := [
  { id := "anim.list"
    statement := r"\forall s:\ \{a \mid a \text{ is a running CSS animation or transition on } s\} \subseteq \texttt{getAnimations}(s) \ \land\ \texttt{getAnimations}(s) \cap \{\text{rAF lerps}\} = \varnothing"
    theorems := ["planned:gate-settle"]
    engines := both
    testId := "prem.anim.list" },
  { id := "cv.auto-margin"
    statement := r"\forall n:\ n \in \text{subtree skipped by } \texttt{content-visibility:auto} \Rightarrow \texttt{getComputedStyle}(n).\mathrm{margin} = \texttt{auto} \text{ (unresolved, not px)}"
    theorems := ["planned:gate-settle", "planned:fix-commission"]
    engines := both
    testId := "prem.cv.auto-margin" },
  { id := "cv.read-forces-lock"
    statement := r"\forall n:\ n \in \text{subtree skipped by } \texttt{content-visibility:auto} \Rightarrow \texttt{getComputedStyle}(n).\mathrm{margin} \text{ is the used px value (the read forces the lock open); only a } \texttt{display:none} \text{ subtree reports } \texttt{auto}"
    theorems := ["planned:gate-settle", "planned:fix-commission"]
    engines := both
    testId := "prem.cv.read-forces-lock" },
  { id := "frame.raf-order"
    statement := r"\forall f:\ \text{all rAF callbacks of frame } f \text{ run before the style and layout of } f,\ \text{so a write in rAF is seen by the frame's own layout-time observers}"
    theorems := ["Fw.Engine.frameWorkE", "Fw.Engine.frameWork_overcount", "planned:fix-commission"]
    engines := both
    testId := "prem.frame.raf-order" },
  { id := "frame.ro-same-frame"
    statement := r"\forall f:\ \text{a ResizeObserver callback for a size changed in } f \text{ runs in } f,\ \text{after layout and before the next rAF}"
    theorems := ["Fw.Engine.flagTotal_remove_check", "Fw.Engine.reader_removal"]
    engines := both
    testId := "prem.frame.ro-same-frame" },
  { id := "resize.lag"
    statement := r"\forall w:\ \text{after the viewport becomes } w \text{ the layout (media queries, } \texttt{vw}\text{ lengths) reflects } w \text{ within } k = 2 \text{ rAF frames}"
    theorems := ["planned:gate-settle"]
    engines := both
    testId := "prem.resize.lag" },
  { id := "clock.raf-timeline"
    statement := r"\forall \text{rAF callback}(t):\ t = \texttt{document.timeline.currentTime} \ \ (c = 0)"
    theorems := ["Fw.Parts.MorphTweenOpt.WaapiPremises", "Fw.Parts.MorphTweenOpt.waapi_eq_tween"]
    engines := both
    testId := "prem.clock.raf-timeline" },
  { id := "css.number-linear"
    statement := r"\text{a registered } \texttt{<number>} \text{ property animated from } a \text{ to } b \text{ with linear timing has value } a + (b-a)\,p \text{ at progress } p"
    theorems := ["Fw.Parts.MorphTweenOpt.waapi_eq_tween", "Fw.Parts.MorphTweenOpt.waapi_frame_eq"]
    engines := both
    testId := "prem.css.number-linear" },
  { id := "css.inherits-false"
    statement := r"\text{a property registered with } \mathrm{inherits}=\bot \text{ and set on } e \text{ reads its initial value on every child } d \ne e"
    theorems := ["Fw.Parts.MorphTweenOpt.waapi_vis"]
    engines := both
    testId := "prem.css.inherits-false" },
  { id := "dom.token-toggle-noop"
    statement := r"\texttt{classList.toggle}(c, b) \text{ with } c \in \texttt{classList} \iff b \text{ changes nothing (no attribute mutation)}"
    theorems := ["Fw.Parts.NavHitTest.changed_write", "Fw.Parts.NavHitTestOpt.writeOnChange_le"]
    engines := both
    testId := "prem.dom.token-toggle-noop" },
  { id := "dom.inline-same-value"
    statement := r"\texttt{style.setProperty}(k, v) \text{ with the inline value of } k \text{ already } v \text{ changes nothing (no attribute mutation)}"
    theorems := ["Fw.Parts.NavHitTest.changed_write", "Fw.Parts.NavHitTestOpt.writeOnChange_le"]
    engines := both
    testId := "prem.dom.inline-same-value" },
  { id := "read.forced-update"
    statement := r"\texttt{getBoundingClientRect},\ \texttt{getComputedStyle},\ \texttt{elementFromPoint} \text{ return the state after all earlier writes (forced style/layout, R4)}"
    theorems := ["Fw.Engine.frameWorkE", "Fw.Engine.reader_removal", "Fw.Parts.EngineScroll.forced_mono"]
    engines := both
    testId := "prem.read.forced-update" },
  { id := "hit.pointer-events"
    statement := r"\texttt{elementFromPoint}(x,y) \text{ skips every box with } \texttt{pointer-events:none} \text{ (AL: the allow-list equals the boxes that re-enable it)}"
    theorems := ["Fw.Parts.NavHitTest.allowHit_eq_faithful", "Fw.Parts.NavHitTestOpt.elementsSkip_visSame"]
    engines := both
    testId := "prem.hit.pointer-events" },
  { id := "layout.unit-truncation"
    statement := r"\text{a CSS length } x \text{ lays out as } \lfloor 64x \rfloor / 64 \text{ px (LayoutUnit, 6 fractional bits, truncation)}"
    theorems := ["Fw.Parts.PeopleDeck.snap_faithful", "Fw.Parts.PeopleDeck.cr_snap_same"]
    engines := both
    testId := "prem.layout.unit-truncation" },
  { id := "io.async-delivery"
    statement := r"\text{an IntersectionObserver callback is never delivered inside the rAF callback that observes, and arrives within } k = 3 \text{ frames}"
    theorems := ["Fw.Parts.HeroExitOpt.sentinel_iff_pointerOff"]
    engines := both
    testId := "prem.io.async-delivery" },
  { id := "grid.normal-aspect-ratio-no-stretch"
    statement := r"\text{on a fresh load, in a 300 px grid row: a non-replaced item with a preferred aspect ratio, a definite width and } \texttt{height:auto} \text{ (no min/max) gets its ratio height under } \texttt{align-self:start} \text{ and fills the row under } \texttt{stretch}\text{; a non-replaced block item without an aspect ratio fills the row under } \texttt{normal} \text{ (the } \operatorname{mode} \text{ table). Under } \texttt{normal} \text{ the ratio item is engine-dependent (observed only), hence } \operatorname{mode} = \mathrm{other}"
    theorems := ["Fw.Gate.AlignEquiv.equivSpec_sound", "Fw.Gate.AlignEquiv.modeOf_normal_ratio"]
    engines := both
    testId := "prem.grid.normal-aspect-ratio-no-stretch" },
  { id := "grid.stretch-fill-equals-start"
    statement := r"\text{on a fresh load, for every arm } s \text{ and its used layout } L,\ \operatorname{agrees}(s, L) \text{: the content size respects min/max, the resolved } \texttt{grid-template-rows} \text{ and } \texttt{row-gap} \text{ are the used track sizes and gap, the item's row is one of them, and its measured offset and outer size are its placed box; tested on single-column grids where the } \texttt{start}\text{-aligned item fills its row and } \texttt{stretch} \text{ gives the same box}"
    theorems := ["Fw.Gate.AlignEquiv.equivSpec_sound"]
    engines := both
    testId := "prem.grid.stretch-fill-equals-start" }
]

/-- The premise ids are pairwise distinct.

$$\operatorname{ids}(\mathrm{registry}) \text{ has no repeats}$$
-/
theorem registry_ids_nodup : (registry.map (·.id)).Nodup := by decide

/-- The test ids are pairwise distinct: one test per premise.

$$\operatorname{testIds}(\mathrm{registry}) \text{ has no repeats}$$
-/
theorem registry_testIds_nodup : (registry.map (·.testId)).Nodup := by decide

/-- Every premise names at least one engine and at least one theorem.

$$\forall p \in \mathrm{registry}:\ p.\mathrm{engines} \ne [\,] \land p.\mathrm{theorems} \ne [\,]$$
-/
theorem registry_nonempty : ∀ p ∈ registry, p.engines ≠ [] ∧ p.theorems ≠ [] := by decide

/-- The registry is lint-clean against its own references (`premiseLint_self`, instantiated).

$$\operatorname{lint}(\mathrm{registry}, [\operatorname{ref}(p) \mid p \in \mathrm{registry}]) = (\varnothing, \varnothing)$$
-/
theorem registry_lint_clean : premiseLint registry (registry.map Premise.ref) = ⟨[], []⟩ :=
  premiseLint_self registry

/-! ## Golden rows -/

-- A string list as JSON.
private def strs (l : List String) : Json := Json.arr (l.map Json.str).toArray

/-- A premise row.

$$\operatorname{row}(p) = \{\mathrm{kind}{:}\,\texttt{premise},\ \mathrm{id}, \mathrm{statement}, \mathrm{theorems}, \mathrm{engines}, \mathrm{testId}\}$$
-/
def premiseRow (p : Premise) : Json :=
  Json.mkObj [("kind", "premise"), ("id", .str p.id), ("statement", .str p.statement), ("theorems", strs p.theorems),
    ("engines", strs (p.engines.map Engine.name)), ("testId", .str p.testId)]

-- A test reference as JSON.
private def refJson (t : TestRef) : Json := Json.mkObj [("id", .str t.id), ("premise", .str t.premise)]

-- The lint cases: the test lists the lint is run on.
private def lintCases : List (String × List TestRef) :=
  let full := registry.map Premise.ref
  let first : TestRef := (full.head?).getD ⟨"", ""⟩
  [("clean", full), ("empty", []), ("missing-first", full.drop 1), ("unknown-test", full ++ [⟨"prem.ghost", "ghost"⟩]),
   ("wrong-test-id", ⟨"prem.other", first.premise⟩ :: full.drop 1),
   ("wrong-premise", ⟨first.id, "ghost"⟩ :: full.drop 1)]

/-- A lint row.

$$\operatorname{row}(ts) = \{\mathrm{kind}{:}\,\texttt{lint},\ \mathrm{tests} = ts,\ \mathrm{untested},\ \mathrm{unknown}\}$$
-/
def lintRow (name : String) (ts : List TestRef) : Json :=
  let l := premiseLint registry ts
  Json.mkObj [("kind", "lint"), ("name", .str name), ("tests", Json.arr (ts.map refJson).toArray),
    ("untested", strs l.untested), ("unknown", strs l.unknown)]

-- Every test of the registry passing on every engine it needs.
private def allPass : List Result :=
  registry.flatMap fun p => p.engines.map fun e => ⟨p.testId, e, true⟩

-- The flag cases: result lists the flagging is run on.
private def flagCases : List (String × List Result) :=
  let firstTest := (registry.head?.map (·.testId)).getD ""
  let lastTest := (registry.getLast?.map (·.testId)).getD ""
  [("all-pass", allPass), ("no-results", []),
   ("one-fail-chromium", allPass.map fun r => if r.testId == firstTest && r.engine == .chromium then { r with ok := false } else r),
   ("missing-webkit", allPass.filter fun r => !(r.testId == lastTest && r.engine == .webkit)),
   ("flaky-webkit", ⟨firstTest, .webkit, false⟩ :: allPass),
   ("unknown-test-result", ⟨"prem.ghost", .chromium, false⟩ :: allPass)]

-- A result as JSON.
private def resultJson (r : Result) : Json :=
  Json.mkObj [("testId", .str r.testId), ("engine", .str r.engine.name), ("ok", .bool r.ok)]

/-- A flag row.

$$\operatorname{row}(rs) = \{\mathrm{kind}{:}\,\texttt{flag},\ \mathrm{results} = rs,\ \mathrm{flagged} = [(p.\mathrm{id}, p.\mathrm{theorems}) \mid p \in \operatorname{flagged}(\mathrm{registry}, rs)]\}$$
-/
def flagRow (name : String) (rs : List Result) : Json :=
  Json.mkObj [("kind", "flag"), ("name", .str name), ("results", Json.arr (rs.map resultJson).toArray),
    ("flagged", Json.arr ((flagged registry rs).map fun p =>
      Json.mkObj [("premise", .str p.id), ("theorems", strs p.theorems)]).toArray)]

-- The text of the golden file: the registry rows, the lint rows, the flag rows.
private def goldenText : String :=
  let rows : List Json := registry.map premiseRow ++ lintCases.map (fun (n, ts) => lintRow n ts) ++
    flagCases.map (fun (n, rs) => flagRow n rs)
  String.join (rows.map fun j => j.compress ++ "\n")

-- The golden file, relative to `lean/`.
private def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "premise.jsonl"

/-- Writes the golden file, or compares it with the generated text and returns $\mathrm{fail}\in\{0,1\}$ (1 when the
file differs):
$$\mathrm{run}(\mathit{root}, \mathit{write}) = \begin{cases} 0 & \mathit{write} \lor \mathrm{read}(\mathit{root}/\mathit{path}) = \mathrm{goldenText} \\ 1 & \text{otherwise.}\end{cases}$$ -/
def run(root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    IO.FS.writeFile p goldenText
    IO.println s!"premise golden: {registry.length} premises, written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != goldenText then
    IO.println s!"premise golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PremiseGolden.lean)"
    return 1
  IO.println s!"premise golden: {registry.length} premises, up to date"
  return 0

-- the cases mean what their names say
#guard (premiseLint registry ((lintCases.lookup "clean").getD [])) == ⟨[], []⟩
#guard (premiseLint registry []).untested.length == registry.length
#guard (premiseLint registry ((lintCases.lookup "unknown-test").getD [])).unknown == ["prem.ghost"]
#guard (flagged registry allPass).isEmpty
#guard (flagged registry []).length == registry.length
#guard (flagged registry ((flagCases.lookup "one-fail-chromium").getD [])).length == 1
#guard (flagged registry ((flagCases.lookup "missing-webkit").getD [])).length == 1
#guard (flagged registry ((flagCases.lookup "unknown-test-result").getD [])).isEmpty

end Fw.Ops.Premise
