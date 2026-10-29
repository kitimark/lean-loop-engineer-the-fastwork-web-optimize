import Lean.Data.Json
/-!
# Premise registry: every empirical browser premise a theorem relies on has a named browser test

Lean proves "premises `⇒` conclusion". A premise about a real browser (Chromium, WebKit) is empirical: when
it is false the proof silently stops applying (that is how the base engine model overcounted, and how the gate
sampled unsettled pages). This module is the registry of those premises and the two pure checks around it.

* `registry`: per premise its id, statement (Unicode plain text), the theorems that assume it, the engines it must hold
  on, and the id of the browser test that asserts it: a `page` test (`packages/premise-tests`, run on CI on both
  engines) or, for a premise a page cannot observe, a `lane` (its test id is the CI workflow file that asserts it).
* `premiseLint`: the premises without a test (a lane premise: whose workflow file does not exist), and the tests that
  name an unknown premise (`premiseLint_sound`, `untested_of_lane_missing`).
* `flagged`: given the page-test CI results, the page premises whose test failed (or is missing) on an engine they
  need, with the theorems that assume them (`flagged_eq_nil_iff`, `flagged_of_fail`). A failing premise test is a
  finding. Lane premises are asserted by their own workflow (`not_flagged_of_lane`).
* `ackVerdict` (task premise-ack): a known finding recorded in `research/findings/ledger.json` is acknowledged
  (`acks`: premise, engine, observed class, ledger id) and keeps the lane green; the verdict is red iff some finding
  is unacknowledged or some acknowledgement is stale (`red_iff_unacked`, `ack_never_hides_new`, `changed_finding_red`,
  `stale_ack_reported`).
* `citeLint` (m175 hardening): every row of every engine golden (`packages/contracts/golden/engine/**`) cites the
  premises its value depends on (`engineCites`); a row citing nothing or an id that is neither a measured registry
  premise nor an `untestedPremises` entry fails (`uncited_row_flagged`, `bad_of_unknown`, `engineCite_ok_iff`); the
  cited untested ids are the warning list. Run by `scripts/EngineCiteLint.lean` in `check.sh`.
* `laneFailures`: the WKTR lane's assertion (`wktr-fixtures.yml` via `summarize.mjs --assert`; golden
  `packages/contracts/golden/ops/wktr-lane.jsonl`, `laneFailures_nil_iff`, `lane_old_claim_fails`).

Golden vectors (`packages/contracts/golden/ops/premise.jsonl`): the registry rows, the lint and flag cases,
the acknowledgements, the ack, ack-lint and error-class cases. The TS side (`apps/runner/src/premises.ts`, `fw premises`) is checked against them. Generate, never by hand:

```
cd lean && lake env lean --run scripts/PremiseGolden.lean           # write the file
cd lean && lake env lean --run scripts/PremiseGolden.lean --check   # fail if it is stale
```

A theorem name starting with `planned:` is a task that will state the theorem (not yet a declaration); `fw premises`
checks every other name against the Lean sources.
-/
namespace Fw.Ops.Premise
open Lean

/-- The two engines a premise is tested on. -/
inductive Engine where
  | chromium | webkit
deriving DecidableEq, Repr

/-- The engine's name in the JSON files. -/
def Engine.name : Engine → String
  | .chromium => "chromium"
  | .webkit => "webkit"

/-- How a premise is tested: a `page` test of `packages/premise-tests` (run by `premise-tests.yml`, results read by
`fw premises --results`), or a CI `lane` (a workflow of its own, for premises a Playwright page cannot observe, e.g.
WebKit's `internals.styleRecalcCount`, only exposed in WebKitTestRunner). A lane premise's `testId` is the workflow
file's path.
-/
inductive TestKind where
  | page | lane
deriving DecidableEq, Repr

/-- The test kind's name in the JSON files. -/
def TestKind.name : TestKind → String
  | .page => "page"
  | .lane => "lane"

/-- One registered premise; `kind` defaults to `page`. -/
structure Premise where
  id : String
  statement : String
  theorems : List String
  engines : List Engine
  testId : String
  kind : TestKind := .page

/-- A test as the test package declares it: its id and the premise it names. -/
structure TestRef where
  id : String
  premise : String

/-- One CI result: the test, the engine it ran on, whether its assertions held, and the error text of a failing run
(the empty string when there is none; `run.mjs` writes the first 6 lines of the thrown error).
-/
structure Result where
  testId : String
  engine : Engine
  ok : Bool
  error : String := ""

/-! ## Lint -/

/-- The test reference a registered premise expects. -/
def Premise.ref (p : Premise) : TestRef := ⟨p.testId, p.id⟩

/-- Premise `p` has a test among `ts`: one with its test id that names it. -/
def tested (ts : List TestRef) (p : Premise) : Bool :=
  ts.any fun t => t.id == p.testId && t.premise == p.id

/-- Premise `p` is covered by a test: a page premise by a declared page test (`tested`), a lane premise by an existing
workflow file, i.e. its test id is among the workflow paths `files` (the caller lists `.github/workflows/`).
-/
def covered (ts : List TestRef) (files : List String) (p : Premise) : Bool :=
  match p.kind with
  | .page => tested ts p
  | .lane => files.contains p.testId

/-- Test `t` is registered: some page premise names it as its test and is the premise `t` names. -/
def registered (ps : List Premise) (t : TestRef) : Bool :=
  ps.any fun p => p.kind == .page && p.id == t.premise && p.testId == t.id

/-- The lint result: premise ids without a test, and ids of tests that name an unknown premise. -/
structure Lint where
  untested : List String
  unknown : List String
deriving DecidableEq, Repr

/-- **The premise lint**, on the declared page tests `ts` and the existing workflow files `files`. -/
def premiseLint (ps : List Premise) (ts : List TestRef) (files : List String) : Lint where
  untested := (ps.filter fun p => !covered ts files p).map (·.id)
  unknown := (ts.filter fun t => !registered ps t).map (·.id)

/-- `covered` unfolded. -/
theorem covered_iff (ts : List TestRef) (files : List String) (p : Premise) :
    covered ts files p = true ↔
      (p.kind = .page → ∃ t ∈ ts, t.id = p.testId ∧ t.premise = p.id) ∧ (p.kind = .lane → p.testId ∈ files) := by
  cases hk : p.kind <;> simp [covered, hk, tested]

/-- **Lint soundness.** The lint is empty iff every page premise is tested, every lane premise names an existing
workflow file, and every test is registered to a page premise.

A premise without a test, a lane premise whose workflow is missing, or a test that names no page premise makes the
lint fail; nothing else does. -/
theorem premiseLint_sound (ps : List Premise) (ts : List TestRef) (files : List String) :
    premiseLint ps ts files = ⟨[], []⟩ ↔
      (∀ p ∈ ps, (p.kind = .page → ∃ t ∈ ts, t.id = p.testId ∧ t.premise = p.id) ∧
        (p.kind = .lane → p.testId ∈ files)) ∧
      (∀ t ∈ ts, ∃ p ∈ ps, p.kind = .page ∧ p.id = t.premise ∧ p.testId = t.id) := by
  have hr : ∀ t : TestRef, registered ps t = true ↔ ∃ p ∈ ps, p.kind = .page ∧ p.id = t.premise ∧ p.testId = t.id := by
    intro t; simp [registered, and_assoc]
  simp only [premiseLint, Lint.mk.injEq, List.map_eq_nil_iff, List.filter_eq_nil_iff, Bool.not_eq_true',
    Bool.not_eq_false, ← covered_iff, ← hr]

/-- The page tests the registry expects: the references of its page premises. -/
def pageRefs (ps : List Premise) : List TestRef := (ps.filter (·.kind == .page)).map Premise.ref

/-- The workflow files the registry expects: the test ids of its lane premises. -/
def laneFiles (ps : List Premise) : List String := (ps.filter (·.kind == .lane)).map (·.testId)

/-- **The registry's own references are lint-clean.** If the test package declares exactly the page tests the registry
names and exactly the workflows its lane premises name exist, the lint is empty (for any registry).

A registry cannot lint itself into a failure; only a test package or workflow set that drifts from it can. -/
theorem premiseLint_self (ps : List Premise) : premiseLint ps (pageRefs ps) (laneFiles ps) = ⟨[], []⟩ := by
  rw [premiseLint_sound]
  refine ⟨fun p hp => ⟨fun hk => ⟨p.ref, ?_, rfl, rfl⟩, fun hk => ?_⟩, fun t ht => ?_⟩
  · exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hp, by simp [hk]⟩)
  · exact List.mem_map_of_mem (List.mem_filter.mpr ⟨hp, by simp [hk]⟩)
  · obtain ⟨p, hp, rfl⟩ := List.mem_map.mp ht
    obtain ⟨hp, hk⟩ := List.mem_filter.mp hp
    exact ⟨p, hp, by simpa using hk, rfl, rfl⟩

/-- **Dropping a test is caught.** If a page premise is registered and no declared test carries its test id and names
it, the premise is in the lint's `untested` list.
-/
theorem untested_of_missing (ps : List Premise) (ts : List TestRef) (files : List String) (p : Premise) (hp : p ∈ ps)
    (hk : p.kind = .page) (h : ∀ t ∈ ts, ¬(t.id = p.testId ∧ t.premise = p.id)) :
    p.id ∈ (premiseLint ps ts files).untested := by
  refine List.mem_map.mpr ⟨p, List.mem_filter.mpr ⟨hp, ?_⟩, rfl⟩
  cases hc : covered ts files p
  · rfl
  · obtain ⟨t, ht, a, b⟩ := ((covered_iff ts files p).mp hc).1 hk
    exact absurd ⟨a, b⟩ (h t ht)

/-- **A lane premise needs its workflow.** If a lane premise's test id is not among the existing workflow files, the
premise is in the lint's `untested` list.
-/
theorem untested_of_lane_missing (ps : List Premise) (ts : List TestRef) (files : List String) (p : Premise)
    (hp : p ∈ ps) (hk : p.kind = .lane) (h : p.testId ∉ files) : p.id ∈ (premiseLint ps ts files).untested := by
  refine List.mem_map.mpr ⟨p, List.mem_filter.mpr ⟨hp, ?_⟩, rfl⟩
  cases hc : covered ts files p
  · rfl
  · exact absurd (((covered_iff ts files p).mp hc).2 hk) h

/-! ## Flagging theorems from CI results -/

/-- The premise holds on engine `e` in the results `rs`: the test ran on `e` at least once and every run passed. -/
def holds (rs : List Result) (p : Premise) (e : Engine) : Bool :=
  let m := rs.filter fun r => r.testId == p.testId && r.engine == e
  !m.isEmpty && m.all (·.ok)

/-- The premise holds on every engine it needs. -/
def premiseHolds (rs : List Result) (p : Premise) : Bool :=
  p.engines.all (holds rs p)

/-- **The flagged premises**: the page premises that do not hold on some engine they need (failed or missing). Their
`theorems` are the theorems whose proof no longer applies. Lane premises are never flagged here: no page result
exists for them; their own workflow asserts them.
-/
def flagged (ps : List Premise) (rs : List Result) : List Premise :=
  ps.filter fun p => p.kind == .page && !premiseHolds rs p

/-- `holds` unfolded: a run exists and every run passed. -/
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

/-- **Flag soundness.** Nothing is flagged iff every page premise has, on every engine it needs, a run of its test and
every such run passed.
-/
theorem flagged_eq_nil_iff (ps : List Premise) (rs : List Result) :
    flagged ps rs = [] ↔ ∀ p ∈ ps, p.kind = .page → ∀ e ∈ p.engines, holds rs p e = true := by
  simp [flagged, premiseHolds, List.filter_eq_nil_iff]

/-- **A failing premise test flags its premise.** One failing run of a page premise's test on an engine the premise
needs puts the premise (hence its theorems) in the flagged list, whatever else passed.
-/
theorem flagged_of_fail (ps : List Premise) (rs : List Result) (p : Premise) (hp : p ∈ ps) (hk : p.kind = .page)
    (e : Engine) (he : e ∈ p.engines) : p ∈ flagged ps (⟨p.testId, e, false, ""⟩ :: rs) := by
  simp only [flagged, List.mem_filter, Bool.and_eq_true, Bool.not_eq_true', premiseHolds, List.all_eq_false, hk,
    beq_self_eq_true, true_and]
  refine ⟨hp, e, he, ?_⟩
  cases h : holds (⟨p.testId, e, false, ""⟩ :: rs) p e
  · simp
  · have := ((holds_iff _ _ _).mp h).2 ⟨p.testId, e, false, ""⟩ (List.mem_cons_self ..) rfl rfl
    cases this

/-- **A missing test run flags too.** If no result exists for a page premise's test on an engine it needs, the premise
is flagged: absence is not a pass.
-/
theorem flagged_of_missing (ps : List Premise) (rs : List Result) (p : Premise) (hp : p ∈ ps) (hk : p.kind = .page)
    (e : Engine) (he : e ∈ p.engines) (h : ∀ r ∈ rs, ¬(r.testId = p.testId ∧ r.engine = e)) :
    p ∈ flagged ps rs := by
  simp only [flagged, List.mem_filter, Bool.and_eq_true, Bool.not_eq_true', premiseHolds, List.all_eq_false, hk,
    beq_self_eq_true, true_and]
  refine ⟨hp, e, he, ?_⟩
  cases hh : holds rs p e
  · simp
  · obtain ⟨⟨r, hr, a, b⟩, _⟩ := (holds_iff _ _ _).mp hh
    exact absurd ⟨a, b⟩ (h r hr)

/-- **Lane premises are not flagged from page results.** Whatever the results, a lane premise is not in the flagged
list (its workflow is its test; the lint checks the workflow exists).
-/
theorem not_flagged_of_lane (ps : List Premise) (rs : List Result) (p : Premise) (hk : p.kind = .lane) :
    p ∉ flagged ps rs := by
  simp [flagged, hk]

/-! ## The registry -/

-- Both engines.
private def both : List Engine := [.chromium, .webkit]

-- A measured stage rule of an engine model (kind `lane`): presence of the stage's counters equals membership of the
-- stage in the model's `touched` set, in every unforced frame of the `table` step set of `engine-premises.yml`; the lane
-- prints this verdict as row `<engine>.<stage>` and the `extra` step set in its own rows (`Fw.Ops.EnginePremise.Group`).
private def laneRule (id stage counters model : String) (e : Engine) (ths : List String) : Premise where
  id := id
  statement := "∀ f unforced (one change or none, no forced read) in the table step set (golden step rows with group table: a case of the property table or its idle frame; the lane judges the extra step set in rows of its own): " ++ counters ++ " run in f ↔ " ++ stage ++ " ∈ touched(" ++ model ++
    ", f) (not observed: units, forced passes, the order against the base arm)"
  theorems := ths
  engines := [e]
  testId := ".github/workflows/engine-premises.yml"
  kind := .lane

/-- **The registry.** Every empirical browser premise a Lean theorem relies on, its theorems and its test. Sources: the
gate-settle and fix-commission tasks, `Fw.Engine.Core` (`frameWorkE`, forced updates R4) and `Lessons`, and the
premises of `research/findings/ledger.json` that a static page can assert (R3, R5, `Faithful`, the `inherits` premise,
the allow-list premise AL, the write-on-change premises, IO delivery), and the grid alignment premises of
`Fw.Gate.AlignEquiv` (gate-align-equiv, `p_16` and `p_17`, page tests). Premises that need engine counters
(compositing bits, per-stage counts) stay with the engine-check lane (`fw engine-check`, tests F0-F4), except those a
CI lane of their own asserts (kind `lane`): `p_18`-`p_22`, the five engine stage rules that the
`engine-premises.yml` lane measured and found to hold (`cr.script`, `cr.style`, `cr.commit`, `wk.style`, `wk.commit`;
task engine-premise-measure); `p_23`-`p_29`, the seven stage rules that lane refuted in run 39088367495 and that
hold on its recorded cells after the model fix (`cr.layout`, `cr.props`, `cr.paint`, `cr.raster`, `cr.hits`,
`wk.layout`, `wk.props`; task engine-model-fix, `Fw.Ops.EnginePremise.cr_recorded_holds`, `wk_recorded_holds`); and
`p_32`, the WKTR style-rate premise (task wktr-p1p4), whose counter `internals.styleRecalcCount` only
WebKitTestRunner exposes. The lane rules are stated on the `table` step set, which the lane judges in rows of their own
(`Fw.Ops.EnginePremise.grouped_steps`). The `extra` step set (a clock-shim control, custom-property joins, two-box
frames; task engine-model-fix-2) is judged separately: in run 39124427211 its rows `chromium.extra.paint` and
`chromium.extra.raster` fail on `top` with `scale` and every other row holds (`Fw.Ops.EnginePremise.cr_extra_verdicts`,
`wk_extra_holds`).

The two `content-visibility` view premises of fix-commission-margin (`p_30`, `p_31`: `cv.skip-flag`, `cv.fresh-after-resize`) are page tests. So is the Typed OM margin premise `p_33` (`cv.margin-typed-om`, task cmr-margin-typed-om). The margin rule of the breakpoint gate (task cmr-margin-rect-rule, `Fw.Gate.marginStatus`) reads that premise: it decides an auto or percent margin by the node's rect only when both arms report such a value.
-/
def registry : List Premise := [
  { id := "anim.list"
    statement := "∀ s: {a | a is a running CSS animation or transition on s} ⊆ getAnimations(s) ∧ getAnimations(s) ∩ {rAF lerps} = ∅"
    theorems := ["planned:gate-settle"]
    engines := both
    testId := "prem.anim.list" },
  { id := "cv.auto-margin"
    statement := "∀ n: n ∈ subtree skipped by content-visibility:auto → getComputedStyle(n).margin = auto (unresolved, not px)"
    theorems := ["planned:gate-settle", "planned:fix-commission"]
    engines := both
    testId := "prem.cv.auto-margin" },
  { id := "cv.read-forces-lock"
    statement := "∀ n: n ∈ subtree skipped by content-visibility:auto → getComputedStyle(n).margin is the used px value (the read forces the lock open); only a display:none subtree reports auto"
    theorems := ["planned:gate-settle", "planned:fix-commission"]
    engines := both
    testId := "prem.cv.read-forces-lock" },
  { id := "frame.raf-order"
    statement := "∀ f: all rAF callbacks of frame f run before the style and layout of f, so a write in rAF is seen by the frame's own layout-time observers"
    theorems := ["Fw.Engine.frameWorkE", "Fw.Engine.frameWork_overcount", "planned:fix-commission"]
    engines := both
    testId := "prem.frame.raf-order" },
  { id := "frame.ro-same-frame"
    statement := "∀ f: a ResizeObserver callback for a size changed in f runs in f, after layout and before the next rAF"
    theorems := ["Fw.Engine.flagTotal_remove_check", "Fw.Engine.reader_removal"]
    engines := both
    testId := "prem.frame.ro-same-frame" },
  { id := "resize.lag"
    statement := "∀ w: after the viewport becomes w the layout (media queries, vw lengths) reflects w within k = 2 rAF frames"
    theorems := ["planned:gate-settle"]
    engines := both
    testId := "prem.resize.lag" },
  { id := "clock.raf-timeline"
    statement := "∀ rAF callback(t): t = document.timeline.currentTime (c = 0)"
    theorems := ["Fw.Parts.MorphTweenOpt.WaapiPremises", "Fw.Parts.MorphTweenOpt.waapi_eq_tween"]
    engines := both
    testId := "prem.clock.raf-timeline" },
  { id := "css.number-linear"
    statement := "a registered <number> property animated from a to b with linear timing has value a + (b − a)·p at progress p"
    theorems := ["Fw.Parts.MorphTweenOpt.waapi_eq_tween", "Fw.Parts.MorphTweenOpt.waapi_frame_eq"]
    engines := both
    testId := "prem.css.number-linear" },
  { id := "css.inherits-false"
    statement := "a property registered with inherits = false and set on e reads its initial value on every child d ≠ e"
    theorems := ["Fw.Parts.MorphTweenOpt.waapi_vis", "Fw.Parts.MorphTweenOpt.registrationsScoped_see"]
    engines := both
    testId := "prem.css.inherits-false" },
  { id := "dom.token-toggle-noop"
    statement := "classList.toggle(c, b) with (c ∈ classList ↔ b) changes nothing (no attribute mutation)"
    theorems := ["Fw.Parts.NavHitTest.changed_write", "Fw.Parts.NavHitTestOpt.writeOnChange_le"]
    engines := both
    testId := "prem.dom.token-toggle-noop" },
  { id := "dom.inline-same-value"
    statement := "style.setProperty(k, v) with the inline value of k already v changes nothing (no attribute mutation)"
    theorems := ["Fw.Parts.NavHitTest.changed_write", "Fw.Parts.NavHitTestOpt.writeOnChange_le"]
    engines := both
    testId := "prem.dom.inline-same-value" },
  { id := "read.forced-update"
    statement := "getBoundingClientRect, getComputedStyle, elementFromPoint return the state after all earlier writes (forced style/layout, R4)"
    theorems := ["Fw.Engine.frameWorkE", "Fw.Engine.reader_removal", "Fw.Parts.EngineScroll.forced_mono"]
    engines := both
    testId := "prem.read.forced-update" },
  { id := "hit.pointer-events"
    statement := "elementFromPoint(x, y) skips every box with pointer-events:none (AL: the allow-list equals the boxes that re-enable it)"
    theorems := ["Fw.Parts.NavHitTest.allowHit_eq_faithful", "Fw.Parts.NavHitTestOpt.elementsSkip_visSame"]
    engines := both
    testId := "prem.hit.pointer-events" },
  { id := "layout.unit-truncation"
    statement := "a CSS length x lays out as ⌊64x⌋ / 64 px (LayoutUnit, 6 fractional bits, truncation)"
    theorems := ["Fw.Parts.PeopleDeck.snap_faithful", "Fw.Parts.PeopleDeck.cr_snap_same"]
    engines := both
    testId := "prem.layout.unit-truncation" },
  { id := "io.async-delivery"
    statement := "an IntersectionObserver callback is never delivered inside the rAF callback that observes, and arrives within k = 3 frames"
    theorems := ["Fw.Parts.HeroExitOpt.sentinel_iff_pointerOff"]
    engines := both
    testId := "prem.io.async-delivery" },
  { id := "grid.normal-aspect-ratio-no-stretch"
    statement := "on a fresh load, in a 300 px grid row: a non-replaced item with a preferred aspect ratio, a definite width and height:auto (no min/max) gets its ratio height under align-self:start and fills the row under stretch; a non-replaced block item without an aspect ratio fills the row under normal (the mode table). Under normal the ratio item is engine-dependent (observed only), hence mode = other"
    theorems := ["Fw.Gate.AlignEquiv.equivSpec_sound", "Fw.Gate.AlignEquiv.modeOf_normal_ratio"]
    engines := both
    testId := "prem.grid.normal-aspect-ratio-no-stretch" },
  { id := "grid.stretch-fill-equals-start"
    statement := "on a fresh load, for every arm s and its used layout L, agrees(s, L): the content size respects min/max, the resolved grid-template-rows and row-gap are the used track sizes and gap, the item's row is one of them, and its measured offset and outer size are its placed box; tested on single-column grids where the start-aligned item fills its row and stretch gives the same box"
    theorems := ["Fw.Gate.AlignEquiv.equivSpec_sound"]
    engines := both
    testId := "prem.grid.stretch-fill-equals-start" },
  laneRule "cr.script" "script" "FireAnimationFrame, FunctionCall" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound"],
  laneRule "cr.style" "style" "UpdateLayoutTree" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound"],
  laneRule "cr.commit" "commit" "cc.Commit" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound"],
  laneRule "wk.style" "style" "styleRecalcs" "W_wk" .webkit
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound"],
  laneRule "wk.commit" "commit" "renderingUpdates" "W_wk" .webkit
    ["Fw.Engine.WebKit.base_commit", "Fw.Engine.WebKit.scroll_commit"],
  laneRule "cr.layout" "layout" "Layout" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound", "Fw.Ops.EnginePremise.cr_recorded_holds"],
  { id := "cr.props"
    statement := "∀ f unforced (one change or none, no forced read) in the table step set (golden step rows with group table: a case of the property table or its idle frame; the lane judges the extra step set in rows of its own): PrePaint runs in f ↔ props ∈ touched(W_cr, f) ∨ 0 < f.hits (every frame with a rendering update touches props, and each hit test pays one PrePaint, crWorkH; not observed: units, the number of passes)"
    theorems := ["Fw.Engine.touched_of_cover", "Fw.Engine.Chromium.crWorkH_props_ge_hits",
      "Fw.Ops.EnginePremise.cr_recorded_holds"]
    engines := [.chromium]
    testId := ".github/workflows/engine-premises.yml"
    kind := .lane },
  laneRule "cr.paint" "paint" "Paint" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound", "Fw.Ops.EnginePremise.cr_recorded_holds"],
  laneRule "cr.raster" "raster" "RasterTask" "W_cr" .chromium
    ["Fw.Engine.touched_of_cover", "Fw.Engine.run_dominates_sound", "Fw.Ops.EnginePremise.cr_recorded_holds"],
  { id := "cr.hits"
    statement := "∀ f unforced (one change or none, no forced read) in the table step set (golden step rows with group table: a case of the property table or its idle frame; the lane judges the extra step set in rows of its own): HitTest runs in f ↔ 0 < crWorkH(lane, f).hits = f.hits + (1 if layout ∈ touched(W_cr, f), else 0) (not observed: the number of hit tests)"
    theorems := ["Fw.Engine.Chromium.crWorkH_hits", "Fw.Ops.EnginePremise.cr_recorded_holds"]
    engines := [.chromium]
    testId := ".github/workflows/engine-premises.yml"
    kind := .lane },
  laneRule "wk.layout" "layout" "layoutUpdates" "W_wk" .webkit
    ["Fw.Engine.touched_of_cover", "Fw.Engine.WebKit.mem_wkStages", "Fw.Ops.EnginePremise.wk_recorded_holds"],
  laneRule "wk.props" "props" "compositingUpdates" "W_wk" .webkit
    ["Fw.Engine.touched_of_cover", "Fw.Engine.WebKit.mem_wkStages", "Fw.Ops.EnginePremise.wk_recorded_holds"],
  { id := "cv.skip-flag"
    statement := "∀ n: n is in a subtree the engine has skipped (content-visibility:auto, off screen) ↔ checkVisibility() ∧ ¬checkVisibility({contentVisibilityAuto}); after scrollIntoView and two frames the node is no longer skipped"
    theorems := ["Fw.Gate.Settle.viewCell_notRendered_iff", "Fw.Gate.Settle.skipped_after_view_only_if_brought"]
    engines := both
    testId := "prem.cv.skip-flag" },
  { id := "cv.fresh-after-resize"
    statement := "∀ n with margin-inline:auto and max-width = m: after a viewport resize while n is skipped, once n is brought into view and three frames pass, getComputedStyle(n).margin-left equals the geometry-derived margin (container width − m)/2"
    theorems := ["Fw.Gate.Settle.view_bring", "Fw.Gate.Settle.viewCell_fail_of_rendered_diff"]
    engines := both
    testId := "prem.cv.fresh-after-resize" },
  { id := "wktr_scroll_timeline_restyle"
    statement := "WKTR, one rendering update per scroll step: Δ styleRecalcCount = (μ_control, μ_timeline, μ_timeAccel) = (0, 1, 0) for a static control, a transform animation on scroll() and an accelerated time-based transform animation"
    theorems := ["Fw.Engine.WebKit.style_rate_model", "Fw.Engine.WebKit.style_rate_old_refuted"]
    engines := [.webkit]
    testId := ".github/workflows/wktr-fixtures.yml"
    kind := .lane },
  { id := "cv.margin-typed-om"
    statement := "∀ k ∈ {margin-left, margin-right, margin-inline-start, margin-inline-end}: n.computedStyleMap().get(k) is the computed value (CSSKeywordValue auto for an auto margin, a percent CSSUnitValue for a percentage, a px CSSUnitValue for a fixed length) in each of three cases: (a) n is in normal flow; (b) n is in a subtree skipped by content-visibility:auto, which is still skipped after the read; (c) n is under an ancestor with transform: scale(0.916667)"
    theorems := ["Fw.Gate.marginStatus_fixed", "Fw.Gate.marginStatus_fail_iff", "Fw.Gate.marginStatus_never_pass_over_failing_rect"]
    engines := both
    testId := "prem.cv.margin-typed-om" },
  { id := "sweep.layer-pixels"
    statement := "at the fixed progress times 0, 0.5, 1.5, 2.5 and 3.9 s, every channel of a word drawn as a gradient child two tiles (6 device-pixel-snapped word widths) wide, background-size 50% 100% repeat-x, moved by translateX under a static mask-clip:text mask is within 40 of 255 of the same word drawn with background-clip:text and background-position, and both show the colour band"
    theorems := ["Fw.Parts.PlatformSweepLayer.tiled_same_look"]
    engines := both
    testId := "prem.sweep.layer-pixels" },
  { id := "anim.keytimes"
    statement := "a paused Web Animation with linear easing and key frames at offsets 0, o₁, …, 1 (translate or a translate() scale() transform list) has, at progress p, the piecewise linear value through the key frames (the chord of the Lean track)"
    theorems := ["Fw.Parts.MorphGeom.accelerable_bands", "Fw.Parts.MorphGeom.look_bar"]
    engines := both
    testId := "prem.anim.keytimes" },
  { id := "anim.individual-transform"
    statement := "translate, scale and transform animated together on one element compose as translate, then scale, then transform (right to left), each property animating independently"
    theorems := ["Fw.Parts.MorphGeom.accelerable_bands", "Fw.Parts.MorphGeom.rect_eq"]
    engines := both
    testId := "prem.anim.individual-transform" },
  { id := "clip.nested-radius"
    statement := "two nested overflow:hidden border-radius:40px boxes, the inner one composited and moved by translate, show exactly the intersection of the two rounded rectangles: the outer one cuts its own corner, the inner one cuts its own, the straight edges hold"
    theorems := ["Fw.Parts.MorphGeom.rect_eq", "Fw.Parts.MorphGeom.noTransition_bands"]
    engines := both
    testId := "prem.clip.nested-radius" },
  { id := "backdrop.masked-ancestor"
    statement := "a backdrop-filter blur child of an overflow:hidden border-radius ancestor, composited and transformed, blurs the page behind it as the same child without that ancestor does (each channel within 12 of 255 at a stripe edge); chromium only, because Playwright's WebKit build applies no backdrop-filter (finding on the first run, webkit read the unblurred stripe at the edge), so the Simulator pixels carry the WebKit side"
    theorems := ["Fw.Parts.MorphGeom.layers_cover_anims", "Fw.Parts.MorphGeom.rect_eq"]
    engines := [.chromium]
    testId := "prem.backdrop.masked-ancestor" },
  { id := "glint.hold-pixels"
    statement := "for the left and the right dash, at 30 times after a beginElement on a paused SVG timeline (every key-time boundary of the first 5 s cycle (a sample either side of 1, 2, 3, 4, 5) and the later boundaries 6, 10, 11, 12, 15, 16 and 20, none earlier than the one before; every third reached by unpauseAnimations, setCurrentTime, pauseAnimations in one task), every channel of a strip filled by a gradient whose x1 and x2 are a ring of five animate and set pieces per attribute (fill freeze, each beginning at the end of the one before, the first also at indefinite) is within 12 of 255 of the strip filled by the two repeating animate of the original, and the colour band is drawn"
    theorems := ["Fw.Parts.PlatformGlintHold.hold_eq_faithful"]
    engines := both
    testId := "prem.glint.hold-pixels" },
  { id := "glint.compositor-pixels"
    statement := "for the left and the right dash, at 27 times after a beginElement on a paused SVG timeline (a sample either side of every key-time boundary, later cycles included) and at device pixel ratio 1 and 2, the original dash (a rounded line stroked with a gradient whose x1 and x2 are animated) and the compositor dash (a clip-path rounded clip holding one fixed gradient layer moved by a linear-easing transform animation whose keyframes are the Lean golden) differ in no pixel channel by more than 12 of 255 in the interior of the dash (x from 2 px after each end, y from one device pixel inside the top edge to one inside the bottom edge); the larger difference in the edge pixels (the round-cap columns of the ends, the partly covered top and bottom rows) is recorded as the worst difference and the look class (L above 12)"
    theorems := ["Fw.Parts.PlatformGlintCompositor.stops_eq"]
    engines := both
    testId := "prem.glint.compositor-pixels" },
  { id := "anim.shared-start"
    statement := "Web Animations on different elements, created in one task with the same startTime and duration 680 and easing cubic-bezier(1/3, 1, 2/3, 1), have the same currentTime, and each shows its keyframes at the progress 1 - (1 - t/680)^3 (within 1 px of 100)"
    theorems := ["Fw.Parts.MorphGeomTimed.timed_eq_ideal", "Fw.Parts.MorphGeomTimed.rebase_eval"]
    engines := both
    testId := "prem.anim.shared-start" },
  { id := "anim.reversal-jump"
    statement := "cancelling a running animation and starting one on the same startTime read in that task, whose first keyframe is the closed-form value of the old one at that time, shows the same translate before and after (within 0.5 px), and the new one follows the ideal tween from there"
    theorems := ["Fw.Parts.MorphGeomTimed.reverse_continuous", "Fw.Parts.MorphGeomTimed.rebase_eval"]
    engines := both
    testId := "prem.anim.reversal-jump" }
]

theorem registry_ids_nodup : (registry.map (·.id)).Nodup := by decide

/-- The page test ids are pairwise distinct: one test per page premise (lane premises share their workflow file). -/
theorem registry_testIds_nodup : ((registry.filter (·.kind == .page)).map (·.testId)).Nodup := by decide

/-- Every premise names at least one engine and at least one theorem. -/
theorem registry_nonempty : ∀ p ∈ registry, p.engines ≠ [] ∧ p.theorems ≠ [] := by decide

/-- The registry is lint-clean against its own references (`premiseLint_self`, instantiated). -/
theorem registry_lint_clean : premiseLint registry (pageRefs registry) (laneFiles registry) = ⟨[], []⟩ :=
  premiseLint_self registry

/-- The lane premises of the registry, with their workflow files: the twelve engine stage rules
(`engine-premises.yml`) and the WKTR style-rate premise (`wktr-fixtures.yml`). Changed by engine-model-fix: twelve
stage rules, was five.

Which workflow asserts each lane premise, in registry order. -/
theorem registry_laneFiles : laneFiles registry =
    List.replicate 12 ".github/workflows/engine-premises.yml" ++ [".github/workflows/wktr-fixtures.yml"] := by decide

/-- Adding workflow files keeps a premise covered: coverage is monotone in the file list. -/
theorem covered_mono (ts : List TestRef) (files files' : List String) (p : Premise) (hf : ∀ f ∈ files, f ∈ files')
    (h : covered ts files p = true) : covered ts files' p = true := by
  cases hk : p.kind <;> simp_all [covered]

/-! ## Engine golden citations (m175 hardening, task engine-golden-premise-lint)

Every row of every engine golden (`packages/contracts/golden/engine/**`) predicts a browser count from a Lean engine
model; the prediction is only as good as the empirical premises of that model. A row **cites** the premises its value
depends on. A cited id is either a registry premise with a test (`measured`: a page test, or a lane whose workflow
exists) or an `untested` engine premise: a claim the model makes that nobody has measured. The lint fails on a row
that cites nothing (`uncited_row_flagged`) or an id that is neither (`bad_of_unknown`); the untested ids a row cites
are reported as a warning list (`untested_of_cited`): the honest backlog of engine claims to measure.

How a row maps to premises (decided here, `engineCites`): the rows are the files' string fields plus `file` (the path
below `golden/engine/`). A row cites the premises of **every** citation rule whose pattern its fields match. The rules
are per golden file (a new golden file cites nothing until it is listed, so all its rows are flagged) and per engine
and stage: a row's value is the engine model's per-frame work of that stage (`frameWork` with `chromium`/`chromiumAt`,
`webkitAt`/`webkitX`), so it rests on that stage rule of that engine. The WebKit style rows whose variant runs a
transform animation on a scroll timeline (P1, P4 `scrollDriven`; hero-exit's variant) also cite the measured WKTR
premise `p_32`. No page premise is cited: no golden value is computed from a theorem that assumes one (scout sweep of
the generators, 2026-10-18: `frameWorkE`, forced reads, observers and the part theorems of `p_1`-`p_17` are only in
theorem sections). -/

/-- An engine premise that no test measures yet: a claim of a Lean engine model a golden row rests on. -/
structure Untested where
  id : String
  statement : String
  engines : List Engine

-- An untested stage rule of an engine model, from the stage, the counters and the model's name.
private def stageRule (id stage counters model : String) (e : Engine) : Untested where
  id := id
  statement := "∀ f: the per-frame counts of " ++ counters ++ " are ordered like the model's " ++ stage ++ " work " ++
    model ++ "(f)." ++ stage ++ " (zero iff zero, and ≤ / < against the base arm)"
  engines := [e]

/-- **The untested engine premises**: per engine, the stage rules of its Lean model that no lane measures, and for
Chromium the property-signature table and the mode facts of `chromium.jsonl`, none of which a test measures yet.
(Task engine-premise-measure moved five of the first 17 into `registry`; task engine-model-fix moved the seven it
refuted, `refutedPremises`, after the model fix; the five left cannot be measured with our counters.)

The engine claims the goldens still assume without a measurement. -/
-- Measuring one means a CI lane that asserts it, then moving it into `registry` as a lane premise.
def untestedPremises : List Untested := [
  stageRule "cr.comp" "comp" "census.layers, compositeFailedBits" "W_cr" .chromium,
  { id := "cr.signature"
    statement := "∀ (k, ℓ): a change of property k at placement ℓ runs exactly the stages of its signature level in chromium.jsonl"
    engines := [.chromium] },
  { id := "cr.mode"
    statement := "the lane (headless, BeginFrameControl) and real Chrome differ only as the mode rows of chromium.jsonl say (threaded animations, main frame per BeginFrame, compositor stages)"
    engines := [.chromium] },
  stageRule "wk.script" "script" "FireAnimationFrame" "W_wk" .webkit,
  stageRule "wk.paint" "paint" "Paint" "W_wk" .webkit
]

/-- **The refutations of run 39088367495, all fixed.** Per stage rule that the `engine-premises.yml` lane measured
and found false in run 39088367495 (3 independent Chromium jobs and 3 WebKit jobs with 2 passes each): the fixture
cases where every pass disagreed with the model of that run. Task engine-model-fix changed the engine models so that
every one of these cells is predicted (`Fw.Ops.EnginePremise.cr_recorded_holds`, `wk_recorded_holds`) and moved the
seven rules into `registry`.

The counterexamples that drove the engine-model-fix change. -/
def refutedPremises : List (String × List String) := [
  ("cr.layout", ["transform(none<->some)@own: set (Layout absent, model runs)"]),
  ("cr.props", ["rAF-only frame after padding@own (PrePaint runs, model absent)"]),
  ("cr.paint", ["transform(none<->some)@own", "top@own", "left@own", "margin@own (Paint absent, model runs)"]),
  ("cr.raster", ["scale@own", "filter(blur)@own (RasterTask runs, model absent)",
    "top@own", "left@own", "margin@own (RasterTask absent, model runs)"]),
  ("cr.hits", ["transform(none<->some)@none/@layer", "top@layer/@own", "left@layer/@own", "width@none/@layer/@own",
    "height@none/@layer/@own", "margin@none/@layer/@own", "padding@none/@layer/@own (HitTest runs, model absent)"]),
  ("wk.layout", ["filter@layer", "filter@own (layoutUpdates runs, model absent)"]),
  ("wk.props", ["transform@layer", "opacity@layer", "filter@layer", "background@own", "color@own", "mask@layer",
    "mask@own", "insetAbs@layer", "insetAbs@own (compositingUpdates runs, model absent)",
    "opacity@own (compositingUpdates absent, model runs)"])]

/-- **Every refuted premise is now a registry lane premise and no longer untested.** Changed by engine-model-fix:
it said that every refuted premise was still untested.

The seven refuted rules moved from the untested list into the registry. -/
theorem refuted_registered : ∀ r ∈ refutedPremises,
    r.1 ∈ (registry.filter (·.kind == .lane)).map (·.id) ∧ r.1 ∉ untestedPremises.map (·.id) := by decide

/-- A golden row as the lint reads it: the row's string-valued fields, plus `file` (its path below `golden/engine/`). -/
abbrev Row := List (String × String)

/-- A citation rule: rows whose fields include every pair of `pattern` cite `premises`. -/
structure Cite where
  pattern : List (String × String)
  premises : List String

/-- The rule applies to row `r`: for every pair `(k, v)` of its pattern, the first field `k` of `r` has value `v`.

(A key missing from `r` looks up as `none`, so the rule does not apply; an empty pattern applies to every row.)
-/
def Cite.applies (c : Cite) (r : Row) : Bool := c.pattern.all fun kv => r.lookup kv.1 == some kv.2

/-- The premises row `r` cites: the premises of every rule that applies, in rule order (repeats kept). -/
def cites (cs : List Cite) (r : Row) : List String := (cs.filter (·.applies r)).flatMap (·.premises)

/-- Id `i` names a measured premise: some registry premise with id `i` is covered (`covered`). -/
def measured (ps : List Premise) (ts : List TestRef) (files : List String) (i : String) : Bool :=
  ps.any fun p => p.id == i && covered ts files p

/-- Id `i` names an untested engine premise. -/
def assumed (us : List Untested) (i : String) : Bool := us.any (·.id == i)

/-- The citation lint result: rows citing nothing, (row, id) pairs whose id is neither measured nor untested, and the
untested ids cited (the warning list, without repeats).
-/
structure CiteLint where
  uncited : List Row
  bad : List (Row × String)
  untested : List String

/-- **The citation lint** of the golden rows `rows` under the rules `cs`, the registry `ps` with page tests `ts` and
workflow files `F`, and the untested premises `us`.
-/
def citeLint (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested) (cs : List Cite)
    (rows : List Row) : CiteLint where
  uncited := rows.filter fun r => (cites cs r).isEmpty
  bad := rows.flatMap fun r => ((cites cs r).filter fun i => !measured ps ts files i && !assumed us i).map (r, ·)
  untested := ((rows.flatMap (cites cs)).filter fun i => !measured ps ts files i && assumed us i).eraseDups

/-- The lint passes: no uncited row and no bad citation (untested citations are warnings, not failures). -/
def CiteLint.ok (l : CiteLint) : Bool := l.uncited.isEmpty && l.bad.isEmpty

/-- **An uncited row is flagged.** A golden row that no rule gives a premise is in the lint's `uncited` list. -/
theorem uncited_row_flagged (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested)
    (cs : List Cite) (rows : List Row) (r : Row) (hr : r ∈ rows) (h : cites cs r = []) :
    r ∈ (citeLint ps ts files us cs rows).uncited := by
  simp [citeLint, hr, h]

/-- **A citation of an unknown id is flagged.** If a row cites an id that is neither a measured registry premise nor an
untested premise (e.g. a registry premise whose test is missing, or a typo), the pair is in the lint's `bad` list.
-/
theorem bad_of_unknown (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested)
    (cs : List Cite) (rows : List Row) (r : Row) (i : String) (hr : r ∈ rows) (hi : i ∈ cites cs r)
    (hm : measured ps ts files i = false) (ha : assumed us i = false) :
    (r, i) ∈ (citeLint ps ts files us cs rows).bad := by
  simp only [citeLint, List.mem_flatMap, List.mem_map, List.mem_filter]
  exact ⟨r, hr, i, ⟨hi, by simp [hm, ha]⟩, rfl⟩

/-- **An untested citation is warned.** If a row cites an untested premise that no measured premise of the same id
covers, the id is in the lint's `untested` warning list.
-/
theorem untested_of_cited (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested)
    (cs : List Cite) (rows : List Row) (r : Row) (i : String) (hr : r ∈ rows) (hi : i ∈ cites cs r)
    (hm : measured ps ts files i = false) (ha : assumed us i = true) :
    i ∈ (citeLint ps ts files us cs rows).untested := by
  simp only [citeLint, List.mem_eraseDups, List.mem_filter, List.mem_flatMap, hm, ha]
  exact ⟨⟨r, hr, hi⟩, rfl⟩

/-- **Citation lint soundness.** The lint passes iff every row cites at least one premise and every cited id is a
measured registry premise or an untested premise.
-/
theorem citeLint_ok_iff (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested)
    (cs : List Cite) (rows : List Row) :
    (citeLint ps ts files us cs rows).ok = true ↔
      ∀ r ∈ rows, cites cs r ≠ [] ∧ ∀ i ∈ cites cs r, measured ps ts files i = true ∨ assumed us i = true := by
  simp only [CiteLint.ok, citeLint, Bool.and_eq_true, List.isEmpty_iff, List.filter_eq_nil_iff,
    List.flatMap_eq_nil_iff, List.map_eq_nil_iff]
  constructor
  · rintro ⟨h1, h2⟩ r hr
    refine ⟨fun h => by simpa [h] using h1 r hr, fun i hi => ?_⟩
    have := h2 r hr i hi
    cases hm : measured ps ts files i <;> cases ha : assumed us i <;> simp_all
  · intro h
    refine ⟨fun r hr => by simpa using (h r hr).1, fun r hr i hi => ?_⟩
    rcases (h r hr).2 i hi with h' | h' <;> simp [h']

/-- **Annotated rows pass.** If every id of every rule is measured or untested, the lint passes on any rows each of
which some rule cites.
-/
theorem citeLint_ok_of_annotated (ps : List Premise) (ts : List TestRef) (files : List String) (us : List Untested)
    (cs : List Cite) (rows : List Row)
    (hv : ∀ c ∈ cs, ∀ i ∈ c.premises, measured ps ts files i = true ∨ assumed us i = true)
    (h : ∀ r ∈ rows, cites cs r ≠ []) : (citeLint ps ts files us cs rows).ok = true := by
  rw [citeLint_ok_iff]
  refine fun r hr => ⟨h r hr, fun i hi => ?_⟩
  obtain ⟨c, hc, hi⟩ := List.mem_flatMap.mp hi
  exact hv c (List.mem_filter.mp hc).1 i hi

-- The WKTR lane premise's id.
private def wktrId : String := "wktr_scroll_timeline_restyle"

/-- The engine golden files the rules know (paths below `golden/engine/`), besides `chromium.jsonl`. -/
def engineFiles : List String :=
  ["countdown-strip.jsonl", "hero-accent.jsonl", "hero-exit.jsonl", "hidden-pause.jsonl", "morph-mount.jsonl",
   "morph-panel.jsonl", "nav-hittest.jsonl", "pain-notes.jsonl", "people-card.jsonl", "people-deck.jsonl",
   "resource.jsonl", "transition-start.jsonl", "webkit.jsonl"]

def crStages : List (String × String) :=
  ["script", "style", "layout", "props", "paint", "raster", "commit", "comp", "hits"].map fun s => (s, "cr." ++ s)

/-- The counted WebKit stages, each with the id of its stage rule (a registry lane premise or an untested premise). -/
def wkStages : List (String × String) :=
  ["script", "style", "layout", "props", "paint", "commit"].map fun s => (s, "wk." ++ s)

/-- **The citation rules of the engine goldens**: per listed file and engine stage the engine's stage rule, the
`chromium.jsonl` stage, signature and mode rules, and `p_32` (`wktr_scroll_timeline_restyle`) for the WebKit style
rows of the scroll-timeline variants. The per-file rules come file by file: the Chromium rules of a file, then its
WebKit rules, then the next file. A pattern `{k_1=v_1, ...}` is the list of pairs in that order.
-/
def engineCites : List Cite :=
  engineFiles.flatMap (fun f =>
    crStages.map (fun (s, i) => ⟨[("file", f), ("engine", "chromium"), ("stage", s)], [i]⟩) ++
    wkStages.map (fun (s, i) => ⟨[("file", f), ("engine", "webkit"), ("stage", s)], [i]⟩)) ++
  crStages.map (fun (s, i) => ⟨[("file", "chromium.jsonl"), ("kind", "stage"), ("stage", s)], [i]⟩) ++
  [⟨[("file", "chromium.jsonl"), ("kind", "signature")], ["cr.signature"]⟩,
   ⟨[("file", "chromium.jsonl"), ("kind", "mode")], ["cr.mode"]⟩,
   ⟨[("file", "webkit.jsonl"), ("scenario", "P1"), ("variant", "scrollDriven"), ("stage", "style")], [wktrId]⟩,
   ⟨[("file", "webkit.jsonl"), ("scenario", "P4"), ("variant", "scrollDriven"), ("stage", "style")], [wktrId]⟩,
   ⟨[("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "style")], [wktrId]⟩]

/-- Every id the rules cite is one of the 5 untested premises or a lane premise of the registry. -/
theorem engineCites_ids :
    ∀ c ∈ engineCites, ∀ i ∈ c.premises,
      i ∈ untestedPremises.map (·.id) ∨ i ∈ (registry.filter (·.kind == .lane)).map (·.id) := by
  decide +kernel

/-- The untested ids are pairwise distinct and none is a registry premise id (an untested premise is never measured). -/
theorem untested_ids_fresh :
    (untestedPremises.map (·.id)).Nodup ∧ ∀ u ∈ untestedPremises, ∀ p ∈ registry, u.id ≠ p.id := by
  decide

/-- **The rules are valid on main.** With the registry's page tests and any workflow list containing the registry's
lane workflows (`engine-premises.yml`, `wktr-fixtures.yml`), every id of every rule is measured or untested.
-/
theorem engineCites_valid (files : List String) (hf : ∀ f ∈ laneFiles registry, f ∈ files) :
    ∀ c ∈ engineCites, ∀ i ∈ c.premises,
      measured registry (pageRefs registry) files i = true ∨ assumed untestedPremises i = true := by
  intro c hc i hi
  rcases engineCites_ids c hc i hi with h | h
  · right
    obtain ⟨u, hu, rfl⟩ := List.mem_map.mp h
    exact List.any_eq_true.mpr ⟨u, hu, by simp⟩
  · left
    obtain ⟨p, hp, rfl⟩ := List.mem_map.mp h
    obtain ⟨hpm, hk⟩ := List.mem_filter.mp hp
    have hk' : p.kind = .lane := by simpa using hk
    have hl : p.testId ∈ laneFiles registry := List.mem_map.mpr ⟨p, hp, rfl⟩
    refine List.any_eq_true.mpr ⟨p, hpm, ?_⟩
    simp [covered, hk', hf _ hl]

/-- **The lint passes on main once every row is annotated**: with any workflow list containing the lane workflows, the
citation lint under `engineCites` passes iff every row is cited by some rule.
-/
-- The check `scripts/EngineCiteLint.lean` (in `check.sh`) reads the files and decides the right-hand side.
theorem engineCite_ok_iff (files : List String) (hf : ∀ f ∈ laneFiles registry, f ∈ files) (rows : List Row) :
    (citeLint registry (pageRefs registry) files untestedPremises engineCites rows).ok = true ↔
      ∀ r ∈ rows, cites engineCites r ≠ [] := by
  constructor
  · intro h r hr
    exact (((citeLint_ok_iff _ _ _ _ _ _).mp h) r hr).1
  · exact citeLint_ok_of_annotated _ _ _ _ _ _ (engineCites_valid files hf)

-- the rules mean what they say: a P1 scrollDriven style row cites the WebKit style rule and the WKTR premise,
-- a row of an unlisted file or an unknown stage cites nothing, a chromium.jsonl signature row cites the signature table
#guard cites engineCites [("file", "webkit.jsonl"), ("engine", "webkit"), ("scenario", "P1"), ("stage", "style"),
  ("variant", "scrollDriven")] == ["wk.style", "wktr_scroll_timeline_restyle"]
#guard cites engineCites [("file", "webkit.jsonl"), ("engine", "webkit"), ("scenario", "P2"), ("stage", "style"),
  ("variant", "cssTime")] == ["wk.style"]
#guard cites engineCites [("file", "new-part.jsonl"), ("engine", "webkit"), ("stage", "style")] == []
#guard cites engineCites [("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "gpu")] == []
#guard cites engineCites [("file", "chromium.jsonl"), ("kind", "signature"), ("level", "none")] == ["cr.signature"]
#guard (citeLint registry (pageRefs registry) [] untestedPremises engineCites
  [[("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "style")]]).bad.length == 2
#guard (citeLint registry (pageRefs registry) (laneFiles registry) untestedPremises engineCites
  [[("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "style")]]).untested == []
#guard (citeLint registry (pageRefs registry) (laneFiles registry) untestedPremises engineCites
  [[("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "layout")]]).untested == []
-- `wk.layout` is measured since engine-model-fix; `wk.paint` is still untested.
#guard (citeLint registry (pageRefs registry) (laneFiles registry) untestedPremises engineCites
  [[("file", "hero-exit.jsonl"), ("engine", "webkit"), ("stage", "paint")]]).untested == ["wk.paint"]
#guard (citeLint registry (pageRefs registry) (laneFiles registry) untestedPremises [⟨[], ["ghost"]⟩] [[]]).ok == false
#guard (citeLint registry (pageRefs registry) (laneFiles registry) untestedPremises engineCites
  [[("file", "x.jsonl")]]).uncited.length == 1

/-! ## The WKTR lane assertion (`wktr-fixtures.yml`)

The lane premise `p_32` is only as good as its workflow: it must fail when the fixtures measure anything else. The
decision is here; `packages/measure-wktr/fixtures/summarize.mjs --assert` ports it and is checked against the golden
`packages/contracts/golden/ops/wktr-lane.jsonl`. -/

/-- One fixture pass as `summarize.mjs` reports it: the fixture (the arm without its `-f<frames>` suffix), and the
pass's total style recalcs and rendering updates.
-/
structure LanePass where
  fixture : String
  styleRecalcs : Nat
  renderingUpdates : Nat

/-- The expected style recalcs per rendering update per asserted fixture: the triple of `WktrStyleRate.Holds`
(`μ = (0, 1, 0)`). The quarantined JS arms (`scroll-js-*`) are not asserted.
-/
def wktrExpected : List (String × Nat) := [("control", 0), ("scroll-timeline", 1), ("time-accel", 0)]

/-- A pass matches rate `μ`: it has at least one rendering update and exactly `μ` style recalcs per update. -/
def passOk (μ : Nat) (q : LanePass) : Bool := 0 < q.renderingUpdates && q.styleRecalcs == μ * q.renderingUpdates

/-- **The lane verdict**: the expected fixtures that have no pass, or a pass off their rate. Empty means the lane passes. -/
def laneFailures (exp : List (String × Nat)) (qs : List LanePass) : List String :=
  (exp.filter fun (x, μ) =>
    let m := qs.filter (·.fixture == x)
    m.isEmpty || !m.all (passOk μ)).map (·.1)

/-- **Lane verdict soundness.** The lane passes iff every expected fixture has a pass and every pass of it has its rate. -/
theorem laneFailures_nil_iff (exp : List (String × Nat)) (qs : List LanePass) :
    laneFailures exp qs = [] ↔ ∀ e ∈ exp, (∃ q ∈ qs, q.fixture = e.1) ∧
      ∀ q ∈ qs, q.fixture = e.1 → 0 < q.renderingUpdates ∧ q.styleRecalcs = e.2 * q.renderingUpdates := by
  simp only [laneFailures, List.map_eq_nil_iff, List.filter_eq_nil_iff]
  refine forall_congr' fun e => forall_congr' fun _ => ?_
  obtain ⟨x, μ⟩ := e
  simp [passOk, List.isEmpty_iff, List.filter_eq_nil_iff]

/-- **The old golden fails the lane.** If the scroll-timeline fixture measured the old claim (no style recalc, as the
goldens P1/P4 had said) on any pass with an update, the lane fails on `scroll-timeline`.
-/
theorem lane_old_claim_fails (qs : List LanePass) (ρ : Nat) (h : 0 < ρ) :
    "scroll-timeline" ∈ laneFailures wktrExpected (⟨"scroll-timeline", 0, ρ⟩ :: qs) := by
  have hq : passOk 1 ⟨"scroll-timeline", 0, ρ⟩ = false := by simp [passOk]; omega
  simp only [laneFailures, wktrExpected, List.mem_map, List.mem_filter]
  exact ⟨("scroll-timeline", 1), ⟨by simp, by simp [hq]⟩, rfl⟩

-- The measured run 39075991405 (per pass: 53 or 159 updates), and its variations.
private def measuredPasses : List LanePass :=
  [⟨"control", 0, 53⟩, ⟨"control", 0, 159⟩, ⟨"scroll-timeline", 53, 53⟩, ⟨"scroll-timeline", 159, 159⟩,
   ⟨"time-accel", 0, 53⟩, ⟨"time-accel", 0, 159⟩, ⟨"scroll-js-transform", 40, 53⟩, ⟨"scroll-js-bg", 49, 53⟩]

-- The lane cases: name and passes.
private def laneCases : List (String × List LanePass) :=
  [("measured", measuredPasses), ("empty", []),
   ("timeline-zero", measuredPasses.map fun q => if q.fixture == "scroll-timeline" then { q with styleRecalcs := 0 } else q),
   ("control-restyles", ⟨"control", 1, 53⟩ :: measuredPasses),
   ("timeline-twice", ⟨"scroll-timeline", 106, 53⟩ :: measuredPasses),
   ("no-updates", ⟨"time-accel", 0, 0⟩ :: measuredPasses),
   ("missing-time-accel", measuredPasses.filter (·.fixture != "time-accel")),
   ("quarantined-only", measuredPasses.filter fun q => q.fixture.startsWith "scroll-js")]

#guard laneFailures wktrExpected measuredPasses == []
#guard laneFailures wktrExpected [] == ["control", "scroll-timeline", "time-accel"]
#guard laneFailures wktrExpected ((laneCases.lookup "timeline-zero").getD []) == ["scroll-timeline"]
#guard laneFailures wktrExpected ((laneCases.lookup "no-updates").getD []) == ["time-accel"]
#guard laneFailures wktrExpected ((laneCases.lookup "missing-time-accel").getD []) == ["time-accel"]

-- A lane pass as JSON.
private def passJson (q : LanePass) : Json :=
  Json.mkObj [("fixture", .str q.fixture), ("styleRecalcs", (q.styleRecalcs : Json)),
    ("renderingUpdates", (q.renderingUpdates : Json))]

/-- The lane golden: one `expected` row, then per case its passes and failures.

(one compact JSON object per line, each line ending in a newline)
-/
def laneText : String :=
  let exp := Json.mkObj [("kind", "expected"), ("rates", Json.arr (wktrExpected.map fun (x, μ) =>
    Json.mkObj [("fixture", .str x), ("perUpdate", (μ : Json))]).toArray)]
  let rows := laneCases.map fun (n, qs) => Json.mkObj [("kind", "case"), ("name", .str n),
    ("passes", Json.arr (qs.map passJson).toArray), ("failures", Json.arr ((laneFailures wktrExpected qs).map Json.str).toArray)]
  String.join ((exp :: rows).map fun j => j.compress ++ "\n")

/-! ## Acknowledged findings (task premise-ack)

A failing premise test is a finding (`flagged`). Once a finding is recorded in `research/findings/ledger.json`, an
acknowledgement (`acks`) keeps the lane green for exactly that observation: the premise, the engine and the observed
class (the first non-blank line of the error, which carries the observed value). Any other finding stays red: a new
premise or engine (`ack_never_hides_new`) or a changed observation (`changed_finding_red`). An acknowledgement whose
observation is gone, e.g. because the premise now holds on that engine, is reported as stale and is red too
(`stale_ack_reported`): it must be removed. `red_iff_unacked` is the whole rule.

One exception, stated in the types: an acknowledgement marked `intermittent` (its finding appears in some CI runs and
not in others, MEASURED and recorded in its ledger entry) is never stale (`intermittent_not_stale`); it still accepts
only its exact observation, so it hides no new or changed finding either.
-/

/-- The class of an error text: its first line (lines split at `\n`) that holds a character other than space, tab,
carriage return and line feed, or `failed` when no line does (also for the empty text).
-/
def errorClass (s : String) : String :=
  ((s.splitOn "\n").find? fun l => l.any fun c => !c.isWhitespace).getD "failed"

#guard errorClass "" == "failed"
#guard errorClass " \n\t\n" == "failed"
#guard errorClass "\n  \nskipped, got 150px\n\n'150px' !== 'auto'\n" == "skipped, got 150px"
#guard errorClass "  x  " == "  x  "

/-- The observed class of premise `p` on engine `e`: `no result` when its test has no run on `e`; otherwise the error
class of the first failing run on `e`, or `passed` when every run on `e` passed.
-/
def failClass (rs : List Result) (p : Premise) (e : Engine) : String :=
  let m := rs.filter fun r => r.testId == p.testId && r.engine == e
  if m.isEmpty then "no result" else ((m.find? (!·.ok)).map (errorClass ·.error)).getD "passed"

/-- One observed finding: a premise that does not hold on an engine, and the observed class there. -/
structure Observed where
  premise : String
  engine : Engine
  cls : String
deriving DecidableEq, Repr

/-- **The observed findings**: for every flagged premise `p` (in `ps` order) and every engine `e` of `p.engines` (in
order) on which it does not hold, the premise id, the engine and the observed class.
-/
def findings (ps : List Premise) (rs : List Result) : List Observed :=
  (flagged ps rs).flatMap fun p =>
    (p.engines.filter fun e => !holds rs p e).map fun e => ⟨p.id, e, failClass rs p e⟩

/-- An acknowledgement: the premise, the engine, the observed class it accepts, the id of the entry in
`research/findings/ledger.json` that records the finding, and whether the finding is intermittent (seen in some CI
runs only).
-/
structure Ack where
  premise : String
  engine : Engine
  cls : String
  finding : String
  intermittent : Bool

/-- The observation an acknowledgement accepts. -/
def Ack.obs (a : Ack) : Observed := ⟨a.premise, a.engine, a.cls⟩

/-- A finding is acknowledged when some acknowledgement accepts exactly it (same premise, engine and class). -/
def acked (ks : List Ack) (f : Observed) : Bool := ks.any (·.obs == f)

/-- The parts of the verdict: the acknowledged findings, the unacknowledged ones, the stale acknowledgements. -/
structure AckVerdict where
  acked : List Observed
  unacked : List Observed
  stale : List Ack

/-- **The verdict on the findings `fs` under the acknowledgements `ks`**: the findings some acknowledgement accepts,
the findings none accepts, and the acknowledgements that are not intermittent and whose observation is not among the
findings (stale).
-/
def ackVerdict (ks : List Ack) (fs : List Observed) : AckVerdict where
  acked := fs.filter (acked ks)
  unacked := fs.filter fun f => !acked ks f
  stale := ks.filter fun a => !a.intermittent && !fs.contains a.obs

/-- The lane is red when some finding is unacknowledged or some acknowledgement is stale. -/
def AckVerdict.red (v : AckVerdict) : Bool := !v.unacked.isEmpty || !v.stale.isEmpty

/-- **Red iff unacknowledged (or stale).** The verdict is red exactly when some finding is accepted by no
acknowledgement, or some acknowledgement that is not intermittent accepts no finding.
-/
theorem red_iff_unacked (ks : List Ack) (fs : List Observed) :
    (ackVerdict ks fs).red = true ↔
      (∃ f ∈ fs, ∀ a ∈ ks, a.obs ≠ f) ∨ (∃ a ∈ ks, a.intermittent = false ∧ a.obs ∉ fs) := by
  simp [ackVerdict, AckVerdict.red, acked, List.filter_eq_nil_iff]

/-- A page premise that does not hold on an engine it needs yields that finding, with its observed class. -/
theorem mem_findings (ps : List Premise) (rs : List Result) (p : Premise) (e : Engine) (hp : p ∈ ps)
    (hk : p.kind = .page) (he : e ∈ p.engines) (hh : holds rs p e = false) :
    (⟨p.id, e, failClass rs p e⟩ : Observed) ∈ findings ps rs := by
  have hf : p ∈ flagged ps rs := by
    simp only [flagged, List.mem_filter, Bool.and_eq_true, Bool.not_eq_true', premiseHolds, List.all_eq_false, hk,
      beq_self_eq_true, true_and]
    exact ⟨hp, e, he, by simp [hh]⟩
  simp only [findings, List.mem_flatMap, List.mem_map, List.mem_filter]
  exact ⟨p, hf, e, ⟨he, by simp [hh]⟩, rfl⟩

/-- **A changed finding is red.** If a page premise fails on an engine it needs and no acknowledgement for that
premise and engine accepts the observed class, the finding is unacknowledged and the verdict is red.
-/
theorem changed_finding_red (ps : List Premise) (rs : List Result) (ks : List Ack) (p : Premise) (e : Engine)
    (hp : p ∈ ps) (hk : p.kind = .page) (he : e ∈ p.engines) (hh : holds rs p e = false)
    (hn : ∀ a ∈ ks, a.premise = p.id → a.engine = e → a.cls ≠ failClass rs p e) :
    (⟨p.id, e, failClass rs p e⟩ : Observed) ∈ (ackVerdict ks (findings ps rs)).unacked ∧
      (ackVerdict ks (findings ps rs)).red = true := by
  have hm := mem_findings ps rs p e hp hk he hh
  have hu : (⟨p.id, e, failClass rs p e⟩ : Observed) ∈ (ackVerdict ks (findings ps rs)).unacked := by
    simp only [ackVerdict, List.mem_filter, acked, Bool.not_eq_true', List.any_eq_false, beq_iff_eq]
    refine ⟨hm, fun a ha h => ?_⟩
    simp only [Ack.obs, Observed.mk.injEq] at h
    exact hn a ha h.1 h.2.1 h.2.2
  refine ⟨hu, ?_⟩
  simp only [AckVerdict.red, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff]
  exact Or.inl (List.ne_nil_of_mem hu)

/-- **An acknowledgement never hides a new finding.** A page premise failing on an engine it needs, with no
acknowledgement for that premise and engine (a new premise, or a known premise on a new engine), is unacknowledged and
the verdict is red, whatever else is acknowledged.
-/
theorem ack_never_hides_new (ps : List Premise) (rs : List Result) (ks : List Ack) (p : Premise) (e : Engine)
    (hp : p ∈ ps) (hk : p.kind = .page) (he : e ∈ p.engines) (hh : holds rs p e = false)
    (hn : ∀ a ∈ ks, ¬(a.premise = p.id ∧ a.engine = e)) :
    (⟨p.id, e, failClass rs p e⟩ : Observed) ∈ (ackVerdict ks (findings ps rs)).unacked ∧
      (ackVerdict ks (findings ps rs)).red = true :=
  changed_finding_red ps rs ks p e hp hk he hh fun a ha h1 h2 _ => hn a ha ⟨h1, h2⟩

/-- **A stale acknowledgement is reported.** If an acknowledgement is not intermittent and every premise of `ps` with
the acknowledged id now holds on the acknowledged engine, the acknowledgement is stale and the verdict is red (it must
be removed).
-/
theorem stale_ack_reported (ps : List Premise) (rs : List Result) (ks : List Ack) (a : Ack) (ha : a ∈ ks)
    (hi : a.intermittent = false) (hh : ∀ p ∈ ps, p.id = a.premise → holds rs p a.engine = true) :
    a ∈ (ackVerdict ks (findings ps rs)).stale ∧ (ackVerdict ks (findings ps rs)).red = true := by
  have hs : a ∈ (ackVerdict ks (findings ps rs)).stale := by
    simp only [ackVerdict, List.mem_filter, hi, Bool.not_false, Bool.true_and, Bool.not_eq_true']
    refine ⟨ha, Bool.eq_false_iff.mpr fun hc => ?_⟩
    have hm := List.contains_iff_mem.mp hc
    simp only [findings, List.mem_flatMap, List.mem_map, List.mem_filter] at hm
    obtain ⟨p, hf, e, ⟨_, he⟩, heq⟩ := hm
    simp only [Ack.obs, Observed.mk.injEq] at heq
    have hp : p ∈ ps := (List.mem_filter.mp hf).1
    have := hh p hp heq.1
    rw [← heq.2.1] at this
    simp [this] at he
  refine ⟨hs, ?_⟩
  simp only [AckVerdict.red, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff]
  exact Or.inr (List.ne_nil_of_mem hs)

/-- **An intermittent acknowledgement is never stale**, whatever the findings. -/
theorem intermittent_not_stale (ks : List Ack) (fs : List Observed) (a : Ack) (hi : a.intermittent = true) :
    a ∉ (ackVerdict ks fs).stale := by
  simp [ackVerdict, hi]

/-- The acknowledgements that cite nothing known: whose premise is no page premise of `ps`, or whose finding id is not
among the ledger ids `ids`.
-/
def ackLint (ps : List Premise) (ids : List String) (ks : List Ack) : List Ack :=
  ks.filter fun a => !(ps.any fun p => p.kind == .page && p.id == a.premise) || !ids.contains a.finding

/-- **The acknowledged findings.** Each is a premise refuted on CI (run 39102911529, Chrome Headless Shell 156.0.8078.4
and Playwright WebKit 27.2 on Linux) and recorded in `research/findings/ledger.json` under its `finding` id:
`anim.list` fails on WebKit only and intermittently (`getAnimations` did not list the short running transition in run
39102911529; it did in runs 39082835090, 39084127865, 39087188278 and 39101531977), `cv.auto-margin` fails on both
engines in all five runs (a style read forces the content-visibility lock open and returns 150px).
-/
def acks : List Ack := [
  ⟨"anim.list", .webkit, "the short transition is listed while running", "premise.anim.list", true⟩,
  ⟨"cv.auto-margin", .chromium, "skipped subtree reports unresolved auto margin, got 150px", "premise.cv.auto-margin",
    false⟩,
  ⟨"cv.auto-margin", .webkit, "skipped subtree reports unresolved auto margin, got 150px", "premise.cv.auto-margin",
    false⟩]

/-- The ledger ids the acknowledgements cite (each must be an `id` in `research/findings/ledger.json`; `fw premises`
checks it).
-/
def ackFindingIds : List String := ["premise.anim.list", "premise.cv.auto-margin"]

/-- Every acknowledgement names a registered page premise and a cited ledger id. -/
theorem acks_lint_clean : ackLint registry ackFindingIds acks = [] := by decide

-- The page premises of the registry (the only ones with page results).
private def pages : List Premise := registry.filter (·.kind == .page)

-- Every page test of the registry passing on every engine it needs.
private def allPass : List Result :=
  pages.flatMap fun p => p.engines.map fun e => ⟨p.testId, e, true, ""⟩

-- Replace the runs of test `t` on engine `e` by one run with the given outcome.
private def setRun (rs : List Result) (t : String) (e : Engine) (ok : Bool) (err : String) : List Result :=
  rs.map fun r => if r.testId == t && r.engine == e then ⟨t, e, ok, err⟩ else r

-- The error text of the failing cv.auto-margin test in run 39102911529 (both engines).
private def cvErr : String := "skipped subtree reports unresolved auto margin, got 150px\n\n'150px' !== 'auto'\n"

-- The results of run 39102911529: every page premise holds except anim.list on WebKit and cv.auto-margin on both.
private def knownRun : List Result :=
  let rs := setRun allPass "prem.anim.list" .webkit false "the short transition is listed while running"
  let rs := setRun rs "prem.cv.auto-margin" .chromium false cvErr
  setRun rs "prem.cv.auto-margin" .webkit false cvErr

-- The ack cases: result lists the ack verdict is run on.
private def ackCases : List (String × List Result) :=
  [("known-run", knownRun),
   ("known-run-retry-passed", ⟨"prem.anim.list", .webkit, true, ""⟩ :: knownRun),
   ("intermittent-absent", setRun knownRun "prem.anim.list" .webkit true ""),
   ("all-pass", allPass),
   ("new-premise", setRun knownRun "prem.frame.raf-order" .webkit false "the order differs"),
   ("new-engine", setRun knownRun "prem.anim.list" .chromium false "the short transition is listed while running"),
   ("changed-value", setRun knownRun "prem.cv.auto-margin" .webkit false "skipped subtree reports unresolved auto margin, got 151px"),
   ("changed-assertion", setRun knownRun "prem.anim.list" .webkit false "the CSS animation is listed"),
   ("now-holds-chromium", setRun knownRun "prem.cv.auto-margin" .chromium true ""),
   ("missing-run", knownRun.filter fun r => !(r.testId == "prem.anim.list" && r.engine == .webkit))]

-- The verdict of an ack case under the registry and `acks`.
private def caseVerdict (rs : List Result) : AckVerdict := ackVerdict acks (findings registry rs)

#guard (findings registry knownRun).length == 3
#guard !(caseVerdict knownRun).red && (caseVerdict knownRun).acked.length == 3
#guard ackCases.map (fun (n, rs) => (n, (caseVerdict rs).red)) ==
  [("known-run", false), ("known-run-retry-passed", false), ("intermittent-absent", false), ("all-pass", true),
   ("new-premise", true),
   ("new-engine", true), ("changed-value", true), ("changed-assertion", true), ("now-holds-chromium", true),
   ("missing-run", true)]
#guard (caseVerdict allPass).stale.length == 2 && (caseVerdict allPass).unacked.isEmpty
#guard (caseVerdict ((ackCases.lookup "new-premise").getD [])).unacked == [⟨"frame.raf-order", .webkit, "the order differs"⟩]
#guard ((caseVerdict ((ackCases.lookup "changed-value").getD [])).stale.map (·.engine)) == [.webkit]
#guard ((caseVerdict ((ackCases.lookup "missing-run").getD [])).unacked.map (·.cls)) == ["no result"]
#guard ((pages.find? (·.id == "anim.list")).map fun p => failClass knownRun p .chromium) == some "passed"
#guard acked acks ⟨"anim.list", .webkit, "the short transition is listed while running"⟩
#guard !acked acks ⟨"anim.list", .chromium, "the short transition is listed while running"⟩
#guard (ackLint registry [] acks).length == 3
#guard (ackLint registry ackFindingIds (⟨"ghost", .webkit, "x", "premise.anim.list", false⟩ :: acks)).length == 1

/-! ## Golden rows -/

-- A string list as JSON.
private def strs (l : List String) : Json := Json.arr (l.map Json.str).toArray

/-- A premise row. -/
def premiseRow (p : Premise) : Json :=
  Json.mkObj [("kind", "premise"), ("id", .str p.id), ("statement", .str p.statement), ("theorems", strs p.theorems),
    ("engines", strs (p.engines.map Engine.name)), ("testId", .str p.testId), ("testKind", .str p.kind.name)]

-- A test reference as JSON.
private def refJson (t : TestRef) : Json := Json.mkObj [("id", .str t.id), ("premise", .str t.premise)]

-- The lint cases: the test lists and workflow file lists the lint is run on.
private def lintCases : List (String × List TestRef × List String) :=
  let full := pageRefs registry
  let lanes := laneFiles registry
  let first : TestRef := (full.head?).getD ⟨"", ""⟩
  [("clean", full, lanes), ("empty", [], []), ("missing-first", full.drop 1, lanes),
   ("unknown-test", full ++ [⟨"prem.ghost", "ghost"⟩], lanes),
   ("wrong-test-id", ⟨"prem.other", first.premise⟩ :: full.drop 1, lanes),
   ("wrong-premise", ⟨first.id, "ghost"⟩ :: full.drop 1, lanes),
   ("lane-workflow-missing", full, [".github/workflows/lean.yml"]),
   ("lane-as-page-test", full ++ (registry.filter (·.kind == .lane)).map Premise.ref, lanes)]

/-- A lint row. -/
def lintRow (name : String) (ts : List TestRef) (files : List String) : Json :=
  let l := premiseLint registry ts files
  Json.mkObj [("kind", "lint"), ("name", .str name), ("tests", Json.arr (ts.map refJson).toArray),
    ("files", strs files), ("untested", strs l.untested), ("unknown", strs l.unknown)]

-- The flag cases: result lists the flagging is run on.
private def flagCases : List (String × List Result) :=
  let firstTest := (pages.head?.map (·.testId)).getD ""
  let lastTest := (pages.getLast?.map (·.testId)).getD ""
  [("all-pass", allPass), ("no-results", []),
   ("one-fail-chromium", allPass.map fun r => if r.testId == firstTest && r.engine == .chromium then { r with ok := false } else r),
   ("missing-webkit", allPass.filter fun r => !(r.testId == lastTest && r.engine == .webkit)),
   ("flaky-webkit", ⟨firstTest, .webkit, false, ""⟩ :: allPass),
   ("unknown-test-result", ⟨"prem.ghost", .chromium, false, ""⟩ :: allPass),
   ("lane-result-fails", ⟨".github/workflows/wktr-fixtures.yml", .webkit, false, ""⟩ :: allPass)]

-- A result as JSON (`error` only when non-empty).
private def resultJson (r : Result) : Json :=
  Json.mkObj ([("testId", .str r.testId), ("engine", .str r.engine.name), ("ok", .bool r.ok)] ++
    if r.error.isEmpty then [] else [("error", .str r.error)])

-- An observed finding as JSON.
private def obsJson (f : Observed) : Json :=
  Json.mkObj [("premise", .str f.premise), ("engine", .str f.engine.name), ("class", .str f.cls)]

-- An acknowledgement as JSON.
private def ackJson (a : Ack) : Json :=
  Json.mkObj [("premise", .str a.premise), ("engine", .str a.engine.name), ("class", .str a.cls),
    ("finding", .str a.finding), ("intermittent", .bool a.intermittent)]

/-- An acknowledgement row. -/
def ackRow (a : Ack) : Json :=
  Json.mkObj [("kind", "ack"), ("premise", .str a.premise), ("engine", .str a.engine.name), ("class", .str a.cls),
    ("finding", .str a.finding), ("intermittent", .bool a.intermittent)]

/-- An ack-case row: the results, the findings, and the verdict under the registry and `acks`. -/
def ackCaseRow (name : String) (rs : List Result) : Json :=
  let fs := findings registry rs
  let v := ackVerdict acks fs
  Json.mkObj [("kind", "ackcase"), ("name", .str name), ("results", Json.arr (rs.map resultJson).toArray),
    ("findings", Json.arr (fs.map obsJson).toArray), ("acked", Json.arr (v.acked.map obsJson).toArray),
    ("unacked", Json.arr (v.unacked.map obsJson).toArray), ("stale", Json.arr (v.stale.map ackJson).toArray),
    ("red", .bool v.red)]

-- The ack-lint cases: the ledger ids and acknowledgements the lint is run on.
private def ackLintCases : List (String × List String × List Ack) :=
  [("clean", ackFindingIds, acks), ("no-ledger", [], acks), ("one-id", ["premise.anim.list"], acks),
   ("unknown-premise", ackFindingIds, ⟨"ghost", .webkit, "x", "premise.anim.list", false⟩ :: acks),
   ("lane-premise", ackFindingIds, [⟨"wktr_scroll_timeline_restyle", .webkit, "x", "premise.anim.list", false⟩])]

/-- An ack-lint row. -/
def ackLintRow (name : String) (ids : List String) (ks : List Ack) : Json :=
  Json.mkObj [("kind", "acklint"), ("name", .str name), ("ids", strs ids), ("acks", Json.arr (ks.map ackJson).toArray),
    ("bad", Json.arr ((ackLint registry ids ks).map ackJson).toArray)]

-- The error-class cases.
private def errorClassCases : List String :=
  ["", " \n\t\n", cvErr, "\n  \nfirst\nsecond", "  padded  \nx", "one line"]

/-- An error-class row. -/
def errorClassRow (s : String) : Json :=
  Json.mkObj [("kind", "errorclass"), ("error", .str s), ("class", .str (errorClass s))]

/-- A flag row. -/
def flagRow (name : String) (rs : List Result) : Json :=
  Json.mkObj [("kind", "flag"), ("name", .str name), ("results", Json.arr (rs.map resultJson).toArray),
    ("flagged", Json.arr ((flagged registry rs).map fun p =>
      Json.mkObj [("premise", .str p.id), ("theorems", strs p.theorems)]).toArray)]

-- The text of the golden file: the registry rows, the lint rows, the flag rows, then the acknowledgement rows, the
-- ack cases, the ack-lint cases and the error-class cases.
private def goldenText (_ : Unit := ()) : String :=
  let rows : List Json := registry.map premiseRow ++ lintCases.map (fun (n, ts, fs) => lintRow n ts fs) ++
    flagCases.map (fun (n, rs) => flagRow n rs) ++ acks.map ackRow ++
    ackCases.map (fun (n, rs) => ackCaseRow n rs) ++ ackLintCases.map (fun (n, ids, ks) => ackLintRow n ids ks) ++
    errorClassCases.map errorClassRow
  String.join (rows.map fun j => j.compress ++ "\n")

-- The golden file, relative to `lean/`.
private def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "premise.jsonl"

/-- Writes the golden file, or compares it with the generated text and returns `fail∈{0,1}` (1 when the
file differs).
Here a missing or unreadable file reads as the empty string (so it fails). -/
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

/-- A golden line as a lint row: the string-valued fields of a JSON object in order, then `file`. -/
-- A non-object row is cited only by a rule on the file alone, and `engineCites` has none.
def rowOf (file : String) (j : Json) : Row :=
  let fs : List (String × String) := match j with
    | .obj kvs => kvs.toList.filterMap fun (k, v) => match v with | .str s => some (k, s) | _ => none
    | _ => []
  fs ++ [("file", file)]

#guard rowOf "x.jsonl" (Json.mkObj [("engine", "webkit"), ("n", (1 : Json))]) == [("engine", "webkit"), ("file", "x.jsonl")]

/-- Runs the citation lint on every non-blank line of every `*.jsonl` below `golden/engine/` (files in sorted path
order, an unparsable line read as the row `[(file, f)]`) and returns 1 iff it does not pass.
-/
-- Page tests are taken from the registry (`fw premises` checks that `packages/premise-tests` declares them).
def citeRun (root : System.FilePath) : IO Nat := do
  let dir := root / ".." / "packages" / "contracts" / "golden" / "engine"
  let paths := ((← dir.walkDir).filter (·.extension == some "jsonl")).qsort (·.toString < ·.toString)
  let pre := dir.toString ++ "/"
  let mut rows : Array Row := #[]
  for p in paths do
    let rel := (p.toString.drop pre.length).toString
    for line in (← IO.FS.readFile p).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      rows := rows.push (match Json.parse line with | .ok j => rowOf rel j | .error _ => [("file", rel)])
  let wf := root / ".." / ".github" / "workflows"
  let files := ((← wf.readDir).map fun e => ".github/workflows/" ++ e.fileName).toList
  let l := citeLint registry (pageRefs registry) files untestedPremises engineCites rows.toList
  let fmt (r : Row) : String := ", ".intercalate (r.map fun (k, v) => s!"{k}={v}")
  for r in l.uncited.take 20 do IO.println s!"engine cite: UNCITED row {fmt r}"
  for (r, i) in l.bad.take 20 do IO.println s!"engine cite: BAD citation {i} (not a measured or untested premise) in {fmt r}"
  let unt := rows.toList.filter fun r => (cites engineCites r).any fun i => l.untested.contains i
  IO.println s!"engine cite: WARNING {l.untested.length} untested engine premises, cited by {unt.length} of {rows.size} rows:"
  for i in l.untested do
    let n := (rows.toList.filter fun r => (cites engineCites r).contains i).length
    IO.println s!"  {i}: {n} rows"
  if l.ok then
    IO.println s!"engine cite: {rows.size} rows in {paths.size} files, every row cites a premise; WARNING {l.untested.length} untested engine premises cited by {unt.length} rows (list above)"
    return 0
  IO.println s!"engine cite: FAILED ({l.uncited.length} uncited rows, {l.bad.length} bad citations)"
  return 1

-- The lane golden, relative to `lean/`.
private def laneGoldenPath : System.FilePath :=
  ".." / "packages" / "contracts" / "golden" / "ops" / "wktr-lane.jsonl"

/-- Writes `golden/ops/wktr-lane.jsonl` (when `write`), or compares it with `laneText` and returns 1 iff it differs.

Here a missing or unreadable file reads as the empty string (so it fails). -/
def laneRun (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / laneGoldenPath
  if write then
    IO.FS.writeFile p laneText
    IO.println "wktr lane golden: written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != laneText then
    IO.println s!"wktr lane golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/PremiseGolden.lean)"
    return 1
  IO.println "wktr lane golden: up to date"
  return 0

-- the cases mean what their names say
#guard (premiseLint registry (pageRefs registry) (laneFiles registry)) == ⟨[], []⟩
#guard (premiseLint registry [] []).untested.length == registry.length
#guard (premiseLint registry (pageRefs registry ++ [⟨"prem.ghost", "ghost"⟩]) (laneFiles registry)).unknown == ["prem.ghost"]
#guard (premiseLint registry (pageRefs registry) [".github/workflows/lean.yml"]).untested ==
  (registry.filter (·.kind == .lane)).map (·.id)
#guard (premiseLint registry (pageRefs registry ++ (registry.filter (·.kind == .lane)).map Premise.ref)
  (laneFiles registry)).unknown == laneFiles registry
#guard (flagged registry allPass).isEmpty
#guard (flagged registry []).length == pages.length && pages.length + 13 == registry.length
#guard (flagged registry ((flagCases.lookup "one-fail-chromium").getD [])).length == 1
#guard (flagged registry ((flagCases.lookup "missing-webkit").getD [])).length == 1
#guard (flagged registry ((flagCases.lookup "unknown-test-result").getD [])).isEmpty
#guard (flagged registry ((flagCases.lookup "lane-result-fails").getD [])).isEmpty

end Fw.Ops.Premise
