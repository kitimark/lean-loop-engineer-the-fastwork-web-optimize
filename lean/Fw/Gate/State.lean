import Fw.Gate.Items
import Fw.Gate.Reach
/-!
# One sampled state of the breakpoint gate (port of `envDeviations`, `truthItems` and the row
verdicts in `packages/gate-breakpoints/src/verdict.mjs` / `summary.mjs`)

A state is one probe or one sweep stop: the requested environment, and for each arm (original and
rewrite) what the page reported (viewport, media features, matchMedia truth) and the parts.

* `envDeviations`: which requested features an arm did not deliver; the state is *achieved* when
  neither arm deviates. Device width may differ when both widths are on the same side of every
  device-width edge, since no media condition can tell them apart.
* `truthItems`: per matchMedia key, orig = rewrite (`ar`); orig = rewrite = Lean's expected value
  (`lean`, only when achieved and a vector exists, else `na`); the legacy `max-`/`min-` text against
  the range text on each arm (`legacy`, where a legacy text exists); the same `ar` and `lean`
  checks for the neutral queries.
* `rowVerdicts`: the three matchMedia rows, then one row per part, each by the rule of
  `Fw.Gate.Rule`.
* `reqReason`/`stateReach`: with a port in the context, a request the port cannot produce
  (`Fw.Gate.Reach`) makes every row `unreachable`.
* `evalState.verdict`: the rollup of all rows, part rows included (a part failure fails the state).
* `tally`/`blockCell`: a table cell over the probe or stop verdicts of a block or sweep.

Proved: `envDeviations_eq_nil_iff`, `truthItems_lean_na` (without an achieved environment the
`=Lean` row is not comparable), `truthItems_ar_iff`, `evalState_part_row` (a part's row is its
`partVerdict`), `evalState_part_fail` (a failing part fails the state), `evalState_unreachable_iff`
(unreachable exactly by the reach rule), `matrix_reqReason` (the request-form rule agrees with
`envReason` on every probe and port), `tally_perm` and `blockCell_perm` (a cell does not depend on
the order of its rows).
-/
namespace Fw.Gate

/-! ## Environment -/

/-- The environment a probe or stop asks for. -/
structure Requested where
  width : Rat
  height : Rat
  deviceWidth : Rat
  dpr : Rat
  hover : String
  pointer : String
  reducedMotion : String
  colorScheme : String
  deriving Repr, Inhabited

/-- What the page reports about its viewport (`none` = not reported). -/
structure Viewport where
  innerHeight : Option Rat
  screenWidth : Option Rat
  dpr : Option Rat
  deriving Repr, Inhabited

/-- Media features as the page observes them (`none` = not reported). -/
structure Observed where
  widthExact : Option Bool
  hoverHover : Option Bool
  hoverNone : Option Bool
  pointerFine : Option Bool
  pointerCoarse : Option Bool
  reducedMotion : Option Bool
  dark : Option Bool
  deriving Repr, Inhabited

/-- `a ≤ n` with an unreported `a` counting as false (as JS `undefined <= n`).

A missing width is on neither side. -/
def leOpt : Option Rat → Rat → Bool
  | some a, n => decide (a ≤ n)
  | none, _ => false

/-- Two widths are on the same side of every edge `n` (of the pairs `[n, n+1]`).

No device-width condition can tell them apart; a missing width `a = ⊥` has `le(a, n)` false, so it matches
only a `b` above every edge. -/
def sameSide (a : Option Rat) (b : Rat) (edges : List Rat) : Bool :=
  edges.all fun n => leOpt a n == decide (b ≤ n)

/-- The eight environment checks, in report order, with whether each holds.

What "achieved" means, one
feature at a time. -/
def envChecks (q : Requested) (v : Viewport) (o : Observed) (edges : List Rat) : List (String × Bool) :=
  [("width", o.widthExact == some true),
   ("height", v.innerHeight == some q.height),
   ("deviceWidth", v.screenWidth == some q.deviceWidth || sameSide v.screenWidth q.deviceWidth edges),
   ("dpr", v.dpr == some q.dpr),
   ("hover", if q.hover == "hover" then o.hoverHover == some true && o.hoverNone == some false
             else o.hoverNone == some true && o.hoverHover == some false),
   ("pointer", if q.pointer == "fine" then o.pointerFine == some true && o.pointerCoarse == some false
               else o.pointerCoarse == some true && o.pointerFine == some false),
   ("reducedMotion", (q.reducedMotion == "reduce") == (o.reducedMotion == some true)),
   ("colorScheme", (q.colorScheme == "dark") == (o.dark == some true))]

/-- The checks that fail, by name, in report order.

Which requested features an arm did not deliver. -/
def envDeviations (q : Requested) (v : Viewport) (o : Observed) (edges : List Rat) : List String :=
  (envChecks q v o edges).filterMap fun c => if c.2 then none else some c.1

/-- No deviation exactly when every check holds.

An arm achieves its environment when all eight features are as requested. -/
theorem envDeviations_eq_nil_iff (q : Requested) (v : Viewport) (o : Observed) (edges : List Rat) :
    envDeviations q v o edges = [] ↔ ∀ c ∈ envChecks q v o edges, c.2 = true := by
  unfold envDeviations
  rw [List.filterMap_eq_nil_iff]
  constructor
  · intro h c hc
    have := h c hc
    cases hb : c.2
    · simp [hb] at this
    · rfl
  · intro h c hc
    simp [h c hc]

/-! ## matchMedia truth -/

/-- A matchMedia value as recorded: absent (`⊥`), `null`, or a boolean. -/
abbrev TVal := Option (Option Bool)

/-- Recorded matchMedia values by key, in the run's key order. -/
abbrev TMap := List (String × Option Bool)

/-- One arm's matchMedia record: the range texts, the legacy texts and the neutral queries. -/
structure TruthRaw where
  truth : TMap
  legacy : TMap
  neutral : TMap
  deriving Repr, Inhabited

/-- The kind of a truth item. -/
inductive TCls
  | ar | lean | legacy | neutralAR | neutralLean
  deriving DecidableEq, Repr, Inhabited

/-- One truth item: kind, key, original and rewrite values, expected value, status. -/
structure TItem where
  cls : TCls
  key : String
  a : TVal
  b : TVal
  expect : TVal
  status : Status
  deriving DecidableEq, Repr, Inhabited

/-- Equal or differ.

A yes/no check as a status. -/
def eqS (c : Bool) : Status := if c then .equal else .differ

/-- The truth items of one range-text key `k` with original value `x`: the rewrite arm `r`, the original's
legacy texts `oLegacy`, Lean's expected values `E` (if any) and whether the requested environment was achieved.

Three checks per media condition. -/
def truthKey (r : TruthRaw) (oLegacy : TMap) (ex : Option TMap) (ach : Bool) (k : String)
    (x : Option Bool) : List TItem :=
  let a : TVal := some x
  let b := r.truth.lookup k
  [⟨.ar, k, a, b, none, eqS (a == b)⟩] ++
  (match ex, ach with
   | some m, true => [⟨.lean, k, a, b, m.lookup k, eqS (a == m.lookup k && b == m.lookup k)⟩]
   | some m, false => [⟨.lean, k, a, b, m.lookup k, .na⟩]
   | none, _ => [⟨.lean, k, a, b, some none, .na⟩]) ++
  (match oLegacy.lookup k with
   | some (some l) =>
     [⟨.legacy, k, some (some l), r.legacy.lookup k, some none,
       eqS (some (some l) == a && r.legacy.lookup k == b)⟩]
   | _ => [])

/-- The truth items of one neutral key.

Two checks per neutral query. -/
def neutralKey (r : TruthRaw) (exN : Option TMap) (ach : Bool) (k : String) (x : Option Bool) :
    List TItem :=
  let a : TVal := some x
  let b := r.neutral.lookup k
  [⟨.neutralAR, k, a, b, none, eqS (a == b)⟩] ++
  (match exN, ach with
   | some m, true => [⟨.neutralLean, k, a, b, m.lookup k, eqS (a == m.lookup k && b == m.lookup k)⟩]
   | _, _ => [⟨.neutralLean, k, a, b, some none, .na⟩])

/-- All truth items of a state: per range-text key of the original, then per neutral key.

The matchMedia comparisons of one state. -/
def truthItems (o r : TruthRaw) (ex exN : Option TMap) (ach : Bool) : List TItem :=
  o.truth.flatMap (fun e => truthKey r o.legacy ex ach e.1 e.2) ++
  o.neutral.flatMap (fun e => neutralKey r exN ach e.1 e.2)

/-- Without an achieved environment, every check against Lean's value is `na`.

Lean's expected values are only compared where the requested environment was delivered. -/
theorem truthItems_lean_na (o r : TruthRaw) (ex exN : Option TMap) (it : TItem)
    (h : it ∈ truthItems o r ex exN false) (hc : it.cls = .lean ∨ it.cls = .neutralLean) :
    it.status = .na := by
  simp only [truthItems, List.mem_append, List.mem_flatMap] at h
  rcases h with ⟨e, -, h⟩ | ⟨e, -, h⟩
  · simp only [truthKey, List.mem_append, List.mem_singleton] at h
    rcases h with (rfl | h) | h
    · simp at hc
    · cases ex <;> simp only [List.mem_singleton] at h <;> rw [h]
    · split at h
      · simp only [List.mem_singleton] at h; subst h; simp at hc
      · simp at h
  · simp only [neutralKey, List.mem_append, List.mem_singleton] at h
    rcases h with rfl | h
    · simp at hc
    · rw [h]

/-- Without a Lean vector for the environment, every check against Lean's value is `na`, whether or not the environment was achieved.

A sweep stop whose environment no matrix probe has (`expectFor` finds none) compares the two arms with each other only; its Lean rows are not comparable, which is a fact about the environment, not a pass. -/
theorem truthItems_lean_na_no_vector (o r : TruthRaw) (ach : Bool) (it : TItem)
    (h : it ∈ truthItems o r none none ach) (hc : it.cls = .lean ∨ it.cls = .neutralLean) :
    it.status = .na := by
  simp only [truthItems, List.mem_append, List.mem_flatMap] at h
  rcases h with ⟨e, -, h⟩ | ⟨e, -, h⟩
  · simp only [truthKey, List.mem_append, List.mem_singleton] at h
    rcases h with (rfl | h) | h
    · simp at hc
    · rw [h]
    · split at h
      · simp only [List.mem_singleton] at h; subst h; simp at hc
      · simp at h
  · simp only [neutralKey, List.mem_append, List.mem_singleton] at h
    rcases h with rfl | h
    · simp at hc
    · rw [h]

/-- An orig = rewrite item is equal exactly when the two values are the same.

The original and the rewrite must agree on every media query. -/
theorem truthItems_ar_iff (o r : TruthRaw) (ex exN : Option TMap) (ach : Bool) (it : TItem)
    (h : it ∈ truthItems o r ex exN ach) (hc : it.cls = .ar ∨ it.cls = .neutralAR) :
    (it.status = .equal ↔ it.a = it.b) := by
  have key : ∀ (k : String) (a b : TVal), (eqS (a == b) = .equal ↔ a = b) := by
    intro k a b
    by_cases hab : a = b
    · simp [eqS, hab]
    · have : (a == b) = false := by simpa using hab
      simp [eqS, this, hab]
  simp only [truthItems, List.mem_append, List.mem_flatMap] at h
  rcases h with ⟨e, -, h⟩ | ⟨e, -, h⟩
  · simp only [truthKey, List.mem_append, List.mem_singleton] at h
    rcases h with (rfl | h) | h
    · exact key e.1 _ _
    · split at h <;> simp only [List.mem_singleton] at h <;> subst h <;> simp at hc
    · split at h
      · simp only [List.mem_singleton] at h; subst h; simp at hc
      · simp at h
  · simp only [neutralKey, List.mem_append, List.mem_singleton] at h
    rcases h with rfl | h
    · exact key e.1 _ _
    · split at h <;> simp only [List.mem_singleton] at h <;> subst h <;> simp at hc

/-! ## Rows of the table -/

/-- The three matchMedia rows and the truth kinds each judges.

How truth items are grouped into rows. -/
def truthRows : List (String × List TCls) :=
  [("matchMedia orig=rewrite", [.ar, .neutralAR]),
   ("matchMedia =Lean", [.lean, .neutralLean]),
   ("matchMedia legacy text", [.legacy])]

/-- The verdict of every row for one state: the matchMedia rows, then the parts in order.

One state's column of the table. -/
def rowVerdicts (ti : List TItem) (parts : List (String × List PItem)) : List (String × Verdict) :=
  truthRows.map (fun rc => (rc.1, cellVerdict ((ti.filter fun t => rc.2.contains t.cls).map (·.status)))) ++
  parts.map fun p => (p.1, cellVerdict (p.2.map (·.status)))

/-! ## One state -/

/-- One arm of a state. -/
structure Arm where
  viewport : Viewport
  observed : Observed
  truth : TruthRaw
  parts : List (String × PartRaw)
  deriving Repr, Inhabited

/-- One state: requested environment, both arms, Lean's expected values (when a vector exists). -/
structure StateIn where
  requested : Requested
  orig : Arm
  rewrite : Arm
  expect : Option TMap
  expectNeutral : Option TMap
  deriving Repr, Inhabited

/-- What every state is judged against: the skips, the covered parts in order, the recorded
properties, the device-width edges, and the engine port (`none`: no reach claim).
-/
structure Ctx where
  anchors : Anchors
  parts : List PartSpec
  props : List (String × PartProps)
  edges : List Rat
  port : Option Port := none
  deriving Repr, Inhabited

/-! ## Reach of a requested environment -/

/-- The `hover` keyword as a Lean value (`none` for any other text).

Parses the requested hover keyword. -/
def hoverOf : String → Option Fw.Site.Breakpoints.Hover
  | "hover" => some .hover
  | "none" => some .none
  | _ => none

/-- The `pointer` keyword as a Lean value (`none` for any other text).

Parses the requested pointer keyword. -/
def pointerOf : String → Option Fw.Site.Breakpoints.Pointer
  | "none" => some .none
  | "coarse" => some .coarse
  | "fine" => some .fine
  | _ => none

/-- Whether the requested (hover, pointer) pair is a primary pair of the port; an unknown keyword
makes no claim (true).

Only a recognised pair can be ruled out. -/
def pairIn (pt : Port) (q : Requested) : Bool :=
  match hoverOf q.hover, pointerOf q.pointer with
  | some h, some k => pt.pairs.contains (h, k)
  | _, _ => true

/-- The reach rule on a requested environment (rational width and DPR).

Why the port cannot produce this request, or none. -/
def reqReason (pt : Port) (q : Requested) : Option Reason :=
  pt.reason (pairIn pt q) (q.width.den == 1) ((q.width * q.dpr).den == 1)

/-- The reach of a state: none without a port, else the reach rule on its request.

A state is unreachable only on a named port. -/
def stateReach (c : Ctx) (s : StateIn) : Option Reason := c.port.bind fun pt => reqReason pt s.requested

/-- A Lean length as a rational number.

The exact value of a probe length. -/
def pxRat (x : Fw.Site.Breakpoints.Px) : Rat := (x.num : Rat) / x.den

/-- The request a matrix probe makes (as the generator prints it).

A probe environment in the gate's request form. -/
def requestOf (e : Fw.Site.Breakpoints.Env) : Requested :=
  ⟨pxRat e.width, pxRat e.height, pxRat e.deviceWidth, pxRat e.dpr,
   Fw.Site.Breakpoints.Feature.hoverKw e.hover, Fw.Site.Breakpoints.Feature.pointerKw e.pointer,
   Fw.Site.Breakpoints.Feature.motionKw e.motion, Fw.Site.Breakpoints.Feature.schemeKw e.scheme⟩

/-- The request form agrees with the proved reach of every matrix probe, on every port.

The rule the gate runs on requests is the one `Fw.Gate.Reach` proves facts about. -/
theorem matrix_reqReason :
    ∀ pt ∈ [Port.chromium, .webkitApple, .webkitGLib], ∀ p ∈ Fw.Site.Breakpoints.matrix,
      reqReason pt (requestOf p.env) = envReason pt p.env := by
  decide +kernel

/-- The evaluation of one state; `rows` are all `unreachable r` when the state's reach is `r`, and
`verdict` rolls up every row, part rows included.
-/
structure StateOut where
  devO : List String
  devR : List String
  achieved : Bool
  truth : List TItem
  parts : List (String × List PItem)
  rows : List (String × Verdict)
  compared : List (String × Nat)
  reach : Option Reason
  verdict : Verdict
  deriving Repr, Inhabited

/-- An item is compared when it is not information and not `na`.

The items a cell's verdict counts. -/
def isCompared (it : PItem) : Bool := it.cls != .info && it.status != .na

/-- An item fails when it is neither `equal` nor `na`.

The items listed under failures. -/
def failsS (s : Status) : Bool := s != .na && s != .equal

/-- An item of an evaluated state is listed as failing when the state is reachable and the item fails.

An unreachable state lists no failing item. -/
def StateOut.itemFails (e : StateOut) (s : Status) : Bool := e.reach.isNone && failsS s

/-- The items of every covered part in one state.

Each covered part, judged on both
arms. -/
def stateParts (c : Ctx) (o r : List (String × PartRaw)) : List (String × List PItem) :=
  c.parts.map fun sp =>
    (sp.id, partItems c.anchors sp (o.lookup sp.id) (r.lookup sp.id) ((c.props.lookup sp.id).getD []))

/-- The rows of a state given its reach: every row `unreachable r` when the reach is `r`, else the
rows unchanged.

An unreachable state has no pass, fail or NC row. -/
def reachRows (reach : Option Reason) (rows : List (String × Verdict)) : List (String × Verdict) :=
  match reach with
  | some r => rows.map fun x => (x.1, .unreachable r)
  | none => rows

/-- Evaluate one state: deviations, achieved, truth items, part items, row verdicts (unreachable on
the state's port when its reach says so), compared counts, reach, and the state verdict over all rows
(matchMedia rows and part rows).

The whole
judgement of one probe or sweep stop. -/
def evalState (c : Ctx) (s : StateIn) : StateOut :=
  let devO := envDeviations s.requested s.orig.viewport s.orig.observed c.edges
  let devR := envDeviations s.requested s.rewrite.viewport s.rewrite.observed c.edges
  let ach := devO.isEmpty && devR.isEmpty
  let ti := truthItems s.orig.truth s.rewrite.truth s.expect s.expectNeutral ach
  let ps := stateParts c s.orig.parts s.rewrite.parts
  let reach := stateReach c s
  let rows := reachRows reach (rowVerdicts ti ps)
  { devO, devR, achieved := ach, truth := ti, parts := ps, rows,
    compared := ps.map fun p => (p.1, p.2.countP isCompared), reach,
    verdict := rollup (rows.map (·.2)) }

/-- The row of a part is its part verdict, on a reachable state.

The table shows exactly the part rule for every covered part. -/
theorem evalState_part_row (c : Ctx) (s : StateIn) (sp : PartSpec) (h : sp ∈ c.parts)
    (h0 : stateReach c s = none) :
    (sp.id, partVerdict c.anchors sp (s.orig.parts.lookup sp.id) (s.rewrite.parts.lookup sp.id)
      ((c.props.lookup sp.id).getD [])) ∈ (evalState c s).rows := by
  simp only [evalState, h0, reachRows, rowVerdicts, stateParts, List.mem_append, List.map_map]
  right
  exact List.mem_map.mpr ⟨sp, h, rfl⟩

/-- The state verdict is the rollup of its rows.

Every row, part rows included, enters the state verdict. -/
theorem evalState_verdict (c : Ctx) (s : StateIn) :
    (evalState c s).verdict = rollup ((evalState c s).rows.map (·.2)) := rfl

/-- A state fails exactly when one of its rows fails.

One failing row, matchMedia or part, fails the state. -/
theorem evalState_fail_iff (c : Ctx) (s : StateIn) :
    (evalState c s).verdict = .fail ↔ ∃ x ∈ (evalState c s).rows, x.2 = .fail := by
  rw [evalState_verdict, rollup_fail_iff, List.mem_map]

/-- A state passes exactly when some row passes and none fails.

A state passes only if no row, part rows included, fails. -/
theorem evalState_pass_iff (c : Ctx) (s : StateIn) :
    (evalState c s).verdict = .pass ↔
      (∃ x ∈ (evalState c s).rows, x.2 = .pass) ∧ ∀ x ∈ (evalState c s).rows, x.2 ≠ .fail := by
  rw [evalState_verdict, rollup_pass_iff, List.mem_map, List.mem_map]
  exact and_congr Iff.rfl ⟨fun h x hx he => h ⟨x, hx, he⟩, fun h ⟨x, hx, he⟩ => h x hx he⟩

/-- **A part failure never gives pass** (review finding on the gap harness): on a reachable state, a
failing covered part fails the state.

Engine.scroll, nav.hitTest, hero.countdown and hero.exit count as much as the matchMedia rows. -/
theorem evalState_part_fail (c : Ctx) (s : StateIn) (sp : PartSpec) (h : sp ∈ c.parts)
    (h0 : stateReach c s = none)
    (hf : partVerdict c.anchors sp (s.orig.parts.lookup sp.id) (s.rewrite.parts.lookup sp.id)
      ((c.props.lookup sp.id).getD []) = .fail) :
    (evalState c s).verdict = .fail :=
  (evalState_fail_iff c s).mpr ⟨_, evalState_part_row c s sp h h0, hf⟩

/-- On an unreachable state every row and the verdict are `unreachable` with the state's reason.

A cell the port cannot produce is neither pass, fail nor NC. -/
theorem evalState_unreachable (c : Ctx) (s : StateIn) (r : Reason) (h : stateReach c s = some r) :
    (∀ x ∈ (evalState c s).rows, x.2 = .unreachable r) ∧ (evalState c s).verdict = .unreachable r := by
  have hrows : ∀ x ∈ (evalState c s).rows, x.2 = .unreachable r := by
    intro x hx
    simp only [evalState, h, reachRows, List.mem_map] at hx
    obtain ⟨y, _, rfl⟩ := hx
    rfl
  refine ⟨hrows, ?_⟩
  have hne : (evalState c s).rows.map (·.2) ≠ [] := by
    simp [evalState, h, reachRows, rowVerdicts, truthRows]
  have hall : ∀ v ∈ (evalState c s).rows.map (·.2), v.isUnreachable = true := by
    intro v hv
    obtain ⟨x, hx, rfl⟩ := List.mem_map.mp hv
    rw [hrows x hx]; rfl
  obtain ⟨r', hr'⟩ := (rollup_unreachable_iff _).mpr ⟨hne, hall⟩
  have hm := rollup_unreachable_mem _ r' hr'
  obtain ⟨x, hx, hx2⟩ := List.mem_map.mp hm
  rw [hrows x hx] at hx2
  cases hx2
  rw [evalState_verdict]; exact hr'

/-- A state is unreachable exactly when its reach names a reason.

Unreachable comes only from the proved reach rule, never from the measured rows. -/
theorem evalState_unreachable_iff (c : Ctx) (s : StateIn) :
    (∃ r, (evalState c s).verdict = .unreachable r) ↔ (stateReach c s).isSome := by
  cases h : stateReach c s with
  | some r => exact ⟨fun _ => rfl, fun _ => ⟨r, (evalState_unreachable c s r h).2⟩⟩
  | none =>
    simp only [Option.isSome_none, Bool.false_eq_true, iff_false]
    rintro ⟨r, hr⟩
    rw [evalState_verdict] at hr
    have hm := rollup_unreachable_mem _ r hr
    obtain ⟨x, hx, hx2⟩ := List.mem_map.mp hm
    simp only [evalState, h, reachRows, rowVerdicts, List.mem_append, List.mem_map] at hx
    rcases hx with ⟨y, _, rfl⟩ | ⟨y, _, rfl⟩
    all_goals
      dsimp only at hx2
      have := congrArg Verdict.isUnreachable hx2
      rw [cellVerdict_isUnreachable] at this; cases this

/-- Sweep hysteresis: items compared and items differing or missing, the state after a sequence
against a fresh load.

How much of the page a resize sequence leaves different from a fresh load. -/
def stale (c : Ctx) (after fresh : List (String × PartRaw)) : Nat × Nat :=
  let items := (stateParts c after fresh).flatMap (·.2)
  (items.countP isCompared,
   items.countP fun it => it.cls != .info && (it.status == .differ || it.status == .missing))

/-! ## Table cells -/

/-- A block cell: not run when the block has no probes, else the tally of its probe verdicts.

A block that ran nothing is shown as not run, not as not comparable. -/
def blockCell (vs : List Verdict) : Option Tally := if vs.isEmpty then none else some (tally vs)

/-- A tally does not depend on the order of the rows it counts.

Probe order within a block never changes a cell. -/
theorem tally_perm (vs ws : List Verdict) (h : vs.Perm ws) : tally vs = tally ws := by
  simp only [tally, rollup_perm vs ws h, h.countP_eq]

/-- A block cell does not depend on the order of its probes.

The table is the same whatever order the probes ran in. -/
theorem blockCell_perm (vs ws : List Verdict) (h : vs.Perm ws) : blockCell vs = blockCell ws := by
  unfold blockCell
  have : vs.isEmpty = ws.isEmpty := by
    cases vs <;> cases ws <;> simp_all <;>
      exact absurd h.length_eq (by simp)
  rw [this, tally_perm vs ws h]

/-! ## Examples -/

private def exReq : Requested := ⟨1440, 900, 1440, 1, "hover", "fine", "no-preference", "light"⟩
private def exVp : Viewport := ⟨some 900, some 1440, some 1⟩
private def exObs : Observed := ⟨some true, some true, some false, some true, some false, some false, some false⟩

#guard envDeviations exReq exVp exObs [500] == []
#guard envDeviations exReq { exVp with screenWidth := some 1512 } exObs [500, 1200] == []
#guard envDeviations exReq { exVp with screenWidth := some 1512 } exObs [1500] == ["deviceWidth"]
#guard envDeviations exReq { exVp with innerHeight := some (1801 / 2) } { exObs with dark := some true } [] ==
  ["height", "colorScheme"]
#guard envDeviations { exReq with hover := "none", pointer := "coarse" } exVp exObs [] == ["hover", "pointer"]
#guard envDeviations exReq ⟨none, none, none⟩ ⟨none, none, none, none, none, none, none⟩ [] ==
  ["width", "height", "dpr", "hover", "pointer"]

private def exT : TruthRaw := ⟨[("a", some true), ("b", some false)], [("a", some true), ("b", none)], [("print", some false)]⟩
private def exT2 : TruthRaw := ⟨[("a", some true), ("b", some true)], [("a", some false), ("b", none)], [("print", some false)]⟩

#guard (truthItems exT exT (some [("a", some true), ("b", some false)]) (some [("print", some false)]) true).map
  (fun t => (t.key, t.status)) ==
  [("a", .equal), ("a", .equal), ("a", .equal), ("b", .equal), ("b", .equal), ("print", .equal), ("print", .equal)]
#guard (truthItems exT exT2 none none true).map (fun t => (t.key, t.status)) ==
  [("a", .equal), ("a", .na), ("a", .differ), ("b", .differ), ("b", .na), ("print", .equal), ("print", .na)]
#guard (rowVerdicts (truthItems exT exT2 none none true) []).map (·.2) == [.fail, .nc, .fail]
#guard (rowVerdicts (truthItems exT exT (some []) (some []) true) []).map (·.2) == [.pass, .fail, .pass]
#guard (rowVerdicts (truthItems exT exT (some []) (some []) false) []).map (·.2) == [.pass, .nc, .pass]
#guard blockCell [] == none
#guard blockCell [.pass, .nc, .fail] == some ⟨.fail, 1, 2, 0⟩
#guard blockCell [.unreachable .primaryPair, .pass] == some ⟨.pass, 0, 1, 1⟩
#guard hoverOf "hover" == some .hover && hoverOf "none" == some .none && hoverOf "x" == none
#guard pointerOf "fine" == some .fine && pointerOf "coarse" == some .coarse && pointerOf "none" == some .none &&
  pointerOf "" == none
#guard pairIn .webkitApple exReq && !pairIn .webkitApple { exReq with hover := "none", pointer := "fine" } &&
  pairIn .webkitApple { exReq with hover := "?", pointer := "fine" }
#guard reqReason .webkitApple exReq == none
#guard reqReason .webkitGLib { exReq with hover := "hover", pointer := "coarse" } == some .primaryPair
#guard reqReason .webkitApple { exReq with width := 1201 / 2, dpr := 2 } == some .wholeWidth
#guard reqReason .chromium { exReq with width := 1201 / 2, dpr := 5 / 4 } == some .widthDpr
#guard reqReason .chromium { exReq with width := 1201 / 2, dpr := 2 } == none
#guard stateReach default { (default : StateIn) with requested := { exReq with hover := "none" } } == none
#guard reachRows (some .wholeWidth) [("a", .pass), ("b", .fail)] ==
  [("a", .unreachable .wholeWidth), ("b", .unreachable .wholeWidth)]
#guard reachRows none [("a", .pass)] == [("a", .pass)]
#guard (evalState { (default : Ctx) with port := some .webkitApple }
  { (default : StateIn) with requested := { exReq with hover := "hover", pointer := "coarse" } }).verdict ==
  .unreachable .primaryPair
#guard (evalState default { (default : StateIn) with requested := exReq }).verdict == .nc
#guard isCompared ⟨.box, "r", 0, "x", .differ, false⟩ && !isCompared ⟨.info, "r", 0, "x", .na, true⟩
#guard failsS .missing && failsS .differ && !failsS .equal && !failsS .na
#guard ({ (default : StateOut) with reach := none }).itemFails .differ
#guard !({ (default : StateOut) with reach := some .wholeWidth }).itemFails .differ
#guard !({ (default : StateOut) with reach := none }).itemFails .equal

end Fw.Gate
