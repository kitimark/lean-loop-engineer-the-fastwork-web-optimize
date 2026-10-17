import Fw.Gate.Items
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
* `tally`/`blockCell`: a table cell over the probe or stop verdicts of a block or sweep.

Proved: `envDeviations_eq_nil_iff`, `truthItems_lean_na` (without an achieved environment the
`=Lean` row is not comparable), `truthItems_ar_iff`, `evalState_part_row` (a part's row is its
`partVerdict`), `tally_perm` and `blockCell_perm` (a cell does not depend on the order of its
rows).
-/
namespace Fw.Gate

/-! ## Environment -/

/-- The environment a probe or stop asks for.

$$\mathit{req} = (W,\ H,\ W_{\mathrm{dev}},\ \mathit{dpr},\ \mathit{hover},\ \mathit{pointer},\ \mathit{motion},\ \mathit{scheme}) \in \mathbb Q^{4} \times \mathrm{String}^{4}$$
-/
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

/-- What the page reports about its viewport (`none` = not reported).

$$v = (\mathit{innerHeight},\ \mathit{screenWidth},\ \mathit{dpr}) \in \mathbb Q_\bot^{3}$$
-/
structure Viewport where
  innerHeight : Option Rat
  screenWidth : Option Rat
  dpr : Option Rat
  deriving Repr, Inhabited

/-- Media features as the page observes them (`none` = not reported).

$$o = (\mathit{widthExact},\ \mathit{hoverHover},\ \mathit{hoverNone},\ \mathit{pointerFine},\ \mathit{pointerCoarse},\ \mathit{reducedMotion},\ \mathit{dark}) \in \mathbb B_\bot^{7}$$
-/
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

$$\operatorname{le}(a, n) \iff a \ne \bot \wedge a \le n$$

A missing width is on neither side. -/
def leOpt : Option Rat → Rat → Bool
  | some a, n => decide (a ≤ n)
  | none, _ => false

/-- Two widths are on the same side of every edge $n$ (of the pairs $[n, n+1]$).

$$\operatorname{sameSide}(a, b, E) \iff \forall n \in E,\ (a \le n) = (b \le n)$$

No device-width condition can tell them apart. -/
def sameSide (a : Option Rat) (b : Rat) (edges : List Rat) : Bool :=
  edges.all fun n => leOpt a n == decide (b ≤ n)

/-- The eight environment checks, in report order, with whether each holds.

$$\begin{aligned} \mathrm{width} &: \mathrm{widthExact} = \top \\ \mathrm{height} &: \mathrm{innerHeight} = q.h \\ \mathrm{deviceWidth} &: \mathrm{screenWidth} = q.\mathrm{dw} \vee \operatorname{sameSide}(\mathrm{screenWidth}, q.\mathrm{dw}, E) \\ \mathrm{dpr} &: \mathrm{dpr} = q.\mathrm{dpr} \\ \mathrm{hover} &: (\mathrm{hoverHover}, \mathrm{hoverNone}) = \begin{cases} (\top, \bot) & q.\mathrm{hover} = \texttt{hover} \\ (\bot, \top) & \text{otherwise} \end{cases} \\ \mathrm{pointer} &: (\mathrm{pointerFine}, \mathrm{pointerCoarse}) = \begin{cases} (\top, \bot) & q.\mathrm{pointer} = \texttt{fine} \\ (\bot, \top) & \text{otherwise} \end{cases} \\ \mathrm{reducedMotion} &: (q.\mathrm{rm} = \texttt{reduce}) \iff \mathrm{reducedMotion} = \top \\ \mathrm{colorScheme} &: (q.\mathrm{cs} = \texttt{dark}) \iff \mathrm{dark} = \top \end{aligned}$$

(an unreported value satisfies no equation). What "achieved" means, one feature at a time. -/
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

$$\operatorname{dev}(q, v, o, E) = [\,n \mid (n, \mathit{ok}) \in \operatorname{envChecks}(q, v, o, E),\ \neg \mathit{ok}\,]$$

Which requested features an arm did not deliver. -/
def envDeviations (q : Requested) (v : Viewport) (o : Observed) (edges : List Rat) : List String :=
  (envChecks q v o edges).filterMap fun c => if c.2 then none else some c.1

/-- No deviation exactly when every check holds.

$$\forall q, v, o, E,\quad \operatorname{dev}(q, v, o, E) = [\,] \iff \forall c \in \operatorname{envChecks}(q, v, o, E),\ c.\mathit{ok}$$

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

/-- A matchMedia value as recorded: absent ($\bot$), `null`, or a boolean.

$$\mathrm{TVal} = (\mathbb B_\bot)_\bot$$
-/
abbrev TVal := Option (Option Bool)

/-- Recorded matchMedia values by key, in the run's key order.

$$\mathrm{TMap} = (\mathrm{String} \times \mathbb B_\bot)^{*}$$
-/
abbrev TMap := List (String × Option Bool)

/-- One arm's matchMedia record: the range texts, the legacy texts and the neutral queries.

$$(T,\ T_{\mathrm{legacy}},\ T_{\mathrm{neutral}}) \in \mathrm{TMap}^{3}$$
-/
structure TruthRaw where
  truth : TMap
  legacy : TMap
  neutral : TMap
  deriving Repr, Inhabited

/-- The kind of a truth item.

$$\mathrm{TCls} = \{\mathrm{AR},\ \mathrm{lean},\ \mathrm{legacy},\ \mathrm{neutralAR},\ \mathrm{neutralLean}\}$$
-/
inductive TCls
  | ar | lean | legacy | neutralAR | neutralLean
  deriving DecidableEq, Repr, Inhabited

/-- One truth item: kind, key, original and rewrite values, expected value, status.

$$t = (\mathit{cls},\ k,\ a,\ b,\ e,\ s) \in \mathrm{TCls} \times \mathrm{String} \times \mathrm{TVal}^{3} \times \mathrm{Status}$$
-/
structure TItem where
  cls : TCls
  key : String
  a : TVal
  b : TVal
  expect : TVal
  status : Status
  deriving DecidableEq, Repr, Inhabited

/-- Equal or differ.

$$\operatorname{eqS}(c) = \begin{cases} \mathrm{equal} & c \\ \mathrm{differ} & \neg c \end{cases}$$

A yes/no check as a status. -/
def eqS (c : Bool) : Status := if c then .equal else .differ

/-- The truth items of one range-text key `k` with original value `x`.

$$\begin{aligned} \mathrm{ar} &: \operatorname{eqS}(a = b) \\ \mathrm{lean} &: \begin{cases} \operatorname{eqS}(a = e_k \wedge b = e_k) & e \ne \bot \wedge \mathit{ach} \\ \mathrm{na} & \text{otherwise} \end{cases} \\ \mathrm{legacy} &: \operatorname{eqS}(\ell^o_k = a \wedge \ell^r_k = b) \quad \text{only if } \ell^o_k \text{ is a boolean} \end{aligned}$$

with $a = x$, $b = r_k$. Three checks per media condition. -/
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

$$\mathrm{neutral.ar} : \operatorname{eqS}(a = b), \qquad \mathrm{neutral.lean} : \begin{cases} \operatorname{eqS}(a = e_k \wedge b = e_k) & e \ne \bot \wedge \mathit{ach} \\ \mathrm{na} & \text{otherwise} \end{cases}$$

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

$$\operatorname{truthItems}(o, r, e, e^N, \mathit{ach}) = \textstyle\bigoplus_{(k, x) \in o.\mathrm{truth}} \operatorname{truthKey}(k, x) \mathbin{+\!\!+} \bigoplus_{(k, x) \in o.\mathrm{neutral}} \operatorname{neutralKey}(k, x)$$

The matchMedia comparisons of one state. -/
def truthItems (o r : TruthRaw) (ex exN : Option TMap) (ach : Bool) : List TItem :=
  o.truth.flatMap (fun e => truthKey r o.legacy ex ach e.1 e.2) ++
  o.neutral.flatMap (fun e => neutralKey r exN ach e.1 e.2)

/-- Without an achieved environment, every check against Lean's value is `na`.

$$\forall o, r, e, e^N,\ \forall it \in \operatorname{truthItems}(o, r, e, e^N, \bot),\quad it.\mathrm{cls} \in \{\mathrm{lean}, \mathrm{neutral.lean}\} \implies it.\mathrm{status} = \mathrm{na}$$

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

/-- An orig = rewrite item is equal exactly when the two values are the same.

$$\forall it \in \operatorname{truthItems}(o, r, e, e^N, \mathit{ach}),\quad it.\mathrm{cls} \in \{\mathrm{ar}, \mathrm{neutral.ar}\} \implies (it.\mathrm{status} = \mathrm{equal} \iff it.a = it.b)$$

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

$$\begin{aligned} \text{orig=rewrite} &: \{\mathrm{ar}, \mathrm{neutral.ar}\} \\ \text{=Lean} &: \{\mathrm{lean}, \mathrm{neutral.lean}\} \\ \text{legacy text} &: \{\mathrm{legacy}\} \end{aligned}$$

How truth items are grouped into rows. -/
def truthRows : List (String × List TCls) :=
  [("matchMedia orig=rewrite", [.ar, .neutralAR]),
   ("matchMedia =Lean", [.lean, .neutralLean]),
   ("matchMedia legacy text", [.legacy])]

/-- The verdict of every row for one state: the matchMedia rows, then the parts in order.

$$\operatorname{rows}(T, \Pi) = [\,(n, \operatorname{cell}([\,t.\mathrm{status} \mid t \in T,\ t.\mathrm{cls} \in K\,])) \mid (n, K) \in \mathrm{truthRows}\,] \mathbin{+\!\!+} [\,(p, \operatorname{cell}([\,it.\mathrm{status} \mid it \in I\,])) \mid (p, I) \in \Pi\,]$$

One state's column of the table. -/
def rowVerdicts (ti : List TItem) (parts : List (String × List PItem)) : List (String × Verdict) :=
  truthRows.map (fun rc => (rc.1, cellVerdict ((ti.filter fun t => rc.2.contains t.cls).map (·.status)))) ++
  parts.map fun p => (p.1, cellVerdict (p.2.map (·.status)))

/-! ## One state -/

/-- One arm of a state.

$$\alpha = (v,\ o,\ T,\ \Pi) \in \mathrm{Viewport} \times \mathrm{Observed} \times \mathrm{TruthRaw} \times (\mathrm{String} \times \mathrm{PartRaw})^{*}$$
-/
structure Arm where
  viewport : Viewport
  observed : Observed
  truth : TruthRaw
  parts : List (String × PartRaw)
  deriving Repr, Inhabited

/-- One state: requested environment, both arms, Lean's expected values (when a vector exists).

$$\sigma = (\mathit{req},\ \alpha_O,\ \alpha_R,\ E,\ E_{\mathrm{neutral}}) \in \mathrm{Requested} \times \mathrm{Arm}^{2} \times \mathrm{TMap}_\bot^{2}$$
-/
structure StateIn where
  requested : Requested
  orig : Arm
  rewrite : Arm
  expect : Option TMap
  expectNeutral : Option TMap
  deriving Repr, Inhabited

/-- What every state is judged against: the skips, the covered parts in order, the recorded
properties, and the device-width edges.

$$c = (A,\ [\pi_1, \dots, \pi_k],\ \mathit{props},\ [n_1, \dots, n_j]) \in \mathrm{Anchors} \times \mathrm{PartSpec}^{*} \times (\mathrm{String} \times \mathrm{PartProps})^{*} \times \mathbb Q^{*}$$
-/
structure Ctx where
  anchors : Anchors
  parts : List PartSpec
  props : List (String × PartProps)
  edges : List Rat
  deriving Repr, Inhabited

/-- The evaluation of one state.

$$(\mathit{dev}_O,\ \mathit{dev}_R,\ \mathit{achieved},\ T,\ \Pi,\ \mathit{rows},\ \mathit{compared}) \in (\mathrm{String}^{*})^{2} \times \mathbb B \times \mathrm{TItem}^{*} \times (\mathrm{String} \times \mathrm{PItem}^{*})^{*} \times (\mathrm{String} \times \mathrm{Verdict})^{*} \times (\mathrm{String} \times \mathbb N)^{*}$$
-/
structure StateOut where
  devO : List String
  devR : List String
  achieved : Bool
  truth : List TItem
  parts : List (String × List PItem)
  rows : List (String × Verdict)
  compared : List (String × Nat)
  deriving Repr, Inhabited

/-- An item is compared when it is not information and not `na`.

$$\operatorname{compared}(it) \iff it.\mathrm{cls} \ne \mathrm{info} \wedge it.\mathrm{status} \ne \mathrm{na}$$

The items a cell's verdict counts. -/
def isCompared (it : PItem) : Bool := it.cls != .info && it.status != .na

/-- An item fails when it is neither `equal` nor `na`.

$$\operatorname{fails}(s) \iff s \ne \mathrm{na} \wedge s \ne \mathrm{equal}$$

The items listed under failures. -/
def failsS (s : Status) : Bool := s != .na && s != .equal

/-- The items of every covered part in one state.

$$\operatorname{stateParts}(C, o, r) = [\,(P.\mathrm{id}, \operatorname{partItems}(A, P, o[P], r[P], \Pi_P)) \mid P \in C.\mathrm{parts}\,]$$

Each covered part, judged on both arms. -/
def stateParts (c : Ctx) (o r : List (String × PartRaw)) : List (String × List PItem) :=
  c.parts.map fun sp =>
    (sp.id, partItems c.anchors sp (o.lookup sp.id) (r.lookup sp.id) ((c.props.lookup sp.id).getD []))

/-- Evaluate one state: deviations, achieved, truth items, part items, row verdicts, compared counts.

$$\mathit{ach} \iff \operatorname{dev}(q, o) = [\,] \wedge \operatorname{dev}(q, r) = [\,], \qquad \operatorname{rows} = \operatorname{rows}(\operatorname{truthItems}(o, r, e, e^N, \mathit{ach}), \operatorname{stateParts}(C, o, r))$$

The whole judgement of one probe or sweep stop. -/
def evalState (c : Ctx) (s : StateIn) : StateOut :=
  let devO := envDeviations s.requested s.orig.viewport s.orig.observed c.edges
  let devR := envDeviations s.requested s.rewrite.viewport s.rewrite.observed c.edges
  let ach := devO.isEmpty && devR.isEmpty
  let ti := truthItems s.orig.truth s.rewrite.truth s.expect s.expectNeutral ach
  let ps := stateParts c s.orig.parts s.rewrite.parts
  { devO, devR, achieved := ach, truth := ti, parts := ps, rows := rowVerdicts ti ps,
    compared := ps.map fun p => (p.1, p.2.countP isCompared) }

/-- The row of a part is its part verdict.

$$\forall C, s, P \in C.\mathrm{parts},\quad (P.\mathrm{id}, \operatorname{partVerdict}(A, P, o[P], r[P], \Pi_P)) \in \operatorname{evalState}(C, s).\mathrm{rows}$$

The table shows exactly the part rule for every covered part. -/
theorem evalState_part_row (c : Ctx) (s : StateIn) (sp : PartSpec) (h : sp ∈ c.parts) :
    (sp.id, partVerdict c.anchors sp (s.orig.parts.lookup sp.id) (s.rewrite.parts.lookup sp.id)
      ((c.props.lookup sp.id).getD [])) ∈ (evalState c s).rows := by
  simp only [evalState, rowVerdicts, stateParts, List.mem_append, List.map_map]
  right
  exact List.mem_map.mpr ⟨sp, h, rfl⟩

/-- Sweep hysteresis: items compared and items differing or missing, the state after a sequence
against a fresh load.

$$\operatorname{stale}(C, a, f) = \bigl(|\{it \mid \operatorname{compared}(it)\}|,\ |\{it \mid it.\mathrm{cls} \ne \mathrm{info} \wedge it.\mathrm{status} \in \{\mathrm{differ}, \mathrm{missing}\}\}|\bigr) \quad \text{over } \textstyle\bigoplus_P \operatorname{partItems}(A, P, a[P], f[P], \Pi_P)$$

How much of the page a resize sequence leaves different from a fresh load. -/
def stale (c : Ctx) (after fresh : List (String × PartRaw)) : Nat × Nat :=
  let items := (stateParts c after fresh).flatMap (·.2)
  (items.countP isCompared,
   items.countP fun it => it.cls != .info && (it.status == .differ || it.status == .missing))

/-! ## Table cells -/

/-- A block cell: not run when the block has no probes, else the tally of its probe verdicts.

$$\operatorname{blockCell}(vs) = \begin{cases} \bot\ (\text{not run}) & vs = [\,] \\ \operatorname{tally}(vs) & \text{otherwise} \end{cases}$$

A block that ran nothing is shown as not run, not as not comparable. -/
def blockCell (vs : List Verdict) : Option Tally := if vs.isEmpty then none else some (tally vs)

/-- A tally does not depend on the order of the rows it counts.

$$\forall vs, ws,\quad vs \sim ws \implies \operatorname{tally}(vs) = \operatorname{tally}(ws)$$

Probe order within a block never changes a cell. -/
theorem tally_perm (vs ws : List Verdict) (h : vs.Perm ws) : tally vs = tally ws := by
  simp only [tally, rollup_perm vs ws h, h.countP_eq]

/-- A block cell does not depend on the order of its probes.

$$\forall vs, ws,\quad vs \sim ws \implies \operatorname{blockCell}(vs) = \operatorname{blockCell}(ws)$$

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
#guard blockCell [.pass, .nc, .fail] == some ⟨.fail, 1, 2⟩
#guard isCompared ⟨.box, "r", 0, "x", .differ, false⟩ && !isCompared ⟨.info, "r", 0, "x", .na, true⟩
#guard failsS .missing && failsS .differ && !failsS .equal && !failsS .na

end Fw.Gate
