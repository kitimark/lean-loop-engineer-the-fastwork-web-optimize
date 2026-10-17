import Fw.Gate.Compare
/-!
# The items of one part (port of `partItems` in `packages/gate-breakpoints/src/verdict.mjs`)

`anchors.json` declares, per part, the roles to compare (each with a reason): which box dimensions
(`dims`, optionally relative to the first box of a reference role, `boxRel`), and which properties
are not compared: a role's own `skipProps`, the named `skipSets`, and the global `skipPrefixes`
(each with a reason). For one sampled state the original arm `o` and the rewrite arm `r` give, per
role, a count and the items found; their items are paired by index.

Per role the items are: one `count` item; then, for each index below both lengths, one `box` item
per declared dimension, one `style` item per compared property (the rewrite-declared properties
minus the skips, in order) and one `info` item per property only the original declares (minus the
skip prefixes). An `info` item has status `na`, so it never takes part in a verdict. A role missing
on either arm gives one `count` item with status `missing`.

Proved here: a status is `na` exactly for `info` items (`partItems_na_iff`); a part passes exactly
when some compared item exists and every compared item is equal (`partVerdict_pass_iff`), and fails
exactly when one compared item is not equal (`partVerdict_fail_iff`); a style item's property is
never skipped (`partItems_style_not_skipped`); changing a skipped property on either arm changes no
status (`partItems_skip_invariant`, `partVerdict_setStyle`); the order of the roles does not change
the verdict (`partVerdict_perm`).
-/
namespace Fw.Gate

/-! ## The declarations of `anchors.json` -/

/-- A property prefix that is never compared, with the reason (`style.skipPrefixes`).

$$q = (\mathit{pre},\ \mathit{why}) \in \mathrm{String} \times \mathrm{String}$$
-/
structure SkipPrefix where
  pre : String
  why : String
  deriving Repr, Inhabited

/-- A named set of properties a role may opt out of, with the reason (`style.skipSets`).

$$S = (\mathit{name},\ P,\ \mathit{why}) \in \mathrm{String} \times \mathrm{String}^{*} \times \mathrm{String}$$
-/
structure SkipSet where
  name : String
  props : List String
  why : String
  deriving Repr, Inhabited

/-- Boxes of a role are taken relative to the box of item `index` of `role`.

$$b = (\rho,\ i) \in \mathrm{String} \times \mathbb N$$
-/
structure BoxRel where
  role : String
  index : Nat
  deriving Repr, Inhabited, DecidableEq

/-- One compared role of a part, with its reason.

$$r = (\rho,\ b,\ D,\ N_{\mathrm{sets}},\ N_{\mathrm{props}},\ \mathit{why}) \in \mathrm{String} \times \mathrm{BoxRel}_\bot \times (\mathrm{String}^{*})^{3} \times \mathrm{String}$$
-/
structure RoleSpec where
  role : String
  boxRel : Option BoxRel
  dims : List String
  skipSets : List String
  skipProps : List String
  why : String
  deriving Repr, Inhabited

/-- One part: its id and its roles, in declared order.

$$\pi = (\mathit{id},\ [r_1, \dots, r_k]) \in \mathrm{String} \times \mathrm{RoleSpec}^{*}$$
-/
structure PartSpec where
  id : String
  roles : List RoleSpec
  deriving Repr, Inhabited

/-- The global skip declarations.

$$A = (Q,\ \mathcal S) \in \mathrm{SkipPrefix}^{*} \times \mathrm{SkipSet}^{*}$$
-/
structure Anchors where
  skipPrefixes : List SkipPrefix
  skipSets : List SkipSet
  deriving Repr, Inhabited

/-! ## What the runner collects for one arm -/

/-- A box in CSS px (exact decimals as recorded).

$$q = (x,\ y,\ w,\ h) \in \mathbb Q^{4}$$
-/
structure Rect where
  x : Rat
  y : Rat
  w : Rat
  h : Rat
  deriving Repr, Inhabited, DecidableEq

/-- One element of a role: its box (when the role has dimensions) and its computed style.

$$e = (q,\ \sigma) \in \mathrm{Rect}_\bot \times (\mathrm{String} \times \mathrm{String})^{*}$$
-/
structure Item where
  rect : Option Rect
  style : List (String × String)
  deriving Repr, Inhabited

/-- One role on one arm: the element count and the elements collected.

$$R = (n,\ [e_1, \dots, e_m]) \in \mathbb N \times \mathrm{Item}^{*}$$
-/
structure RoleRaw where
  count : Nat
  items : List Item
  deriving Repr, Inhabited

/-- One part on one arm, by role.

$$\mathrm{PartRaw} = (\mathrm{String} \times \mathrm{RoleRaw})^{*}$$
-/
abbrev PartRaw := List (String × RoleRaw)

/-- The properties the run recorded for a role: declared by the rewrite (`restated`, compared) and
declared by the original only (`originOnly`, information).

$$(P_{\mathrm{restated}},\ P_{\mathrm{originOnly}}) \in \mathrm{String}^{*} \times \mathrm{String}^{*}$$
-/
structure RoleProps where
  restated : List String
  originOnly : List String
  deriving Repr, Inhabited

/-- The recorded properties of a part, by role.

$$\mathrm{PartProps} = (\mathrm{String} \times \mathrm{RoleProps})^{*}$$
-/
abbrev PartProps := List (String × RoleProps)

/-- The kind of an item.

$$\mathrm{Cls} = \{\mathrm{count},\ \mathrm{box},\ \mathrm{style},\ \mathrm{info}\}$$
-/
inductive Cls
  | count | box | style | info
  deriving DecidableEq, Repr, Inhabited

/-- One item of a part: kind, role, index (`-1` for a count), key, status, and for `info` items
whether the two values differ.

$$it = (\mathit{cls},\ \rho,\ i,\ k,\ s,\ \delta) \in \mathrm{Cls} \times \mathrm{String} \times \mathbb Z \times \mathrm{String} \times \mathrm{Status} \times \mathbb B$$
-/
structure PItem where
  cls : Cls
  role : String
  idx : Int
  key : String
  status : Status
  differs : Bool
  deriving DecidableEq, Repr, Inhabited

/-! ## Which properties are compared -/

/-- The skip prefixes.

$$\operatorname{prefixes}(A) = [\,q.\mathrm{pre} \mid q \in A.\mathrm{skipPrefixes}\,]$$

The prefixes every role skips. -/
def prefixes (a : Anchors) : List String := a.skipPrefixes.map (·.pre)

/-- A property is skipped if it is one of the names, or is a prefix `q` or starts with `q-`.

$$\operatorname{skipped}(p, N, Q) \iff p \in N \ \vee\ \exists q \in Q,\ p = q \vee q\texttt{-} \sqsubseteq p$$

Skipped properties are left out of the comparison. -/
def isSkipped (p : String) (names pres : List String) : Bool :=
  names.contains p || pres.any fun q => p == q || p.startsWith (q ++ "-")

/-- The names a role skips: its own `skipProps`, then the properties of its named `skipSets`.

$$\operatorname{skipNames}(A, \rho) = \rho.\mathrm{skipProps} \mathbin{+\!\!+} \textstyle\bigoplus_{s \in \rho.\mathrm{skipSets}} \operatorname{props}_A(s)$$

where $\operatorname{props}_A(s) = S.P$ for the first $S \in A.\mathcal S$ (in list order) with $S.\mathit{name} = s$, and
$\operatorname{props}_A(s) = [\,]$ if there is none. A role's own skips and those of the sets it names (an undeclared set adds nothing). -/
def skipNames (a : Anchors) (rs : RoleSpec) : List String :=
  rs.skipProps ++ rs.skipSets.flatMap fun s => ((a.skipSets.find? (·.name == s)).map (·.props)).getD []

/-- The compared properties of a role: the rewrite-declared ones that are not skipped, in order.

$$\operatorname{compared}(A, \rho, R) = [\,p \in R \mid \neg\operatorname{skipped}(p, \operatorname{skipNames}(A, \rho), \operatorname{prefixes}(A))\,]$$

What the rewrite restates, minus the declared skips. -/
def comparedProps (a : Anchors) (rs : RoleSpec) (restated : List String) : List String :=
  restated.filter fun p => !isSkipped p (skipNames a rs) (prefixes a)

/-- The information-only properties: declared by the original only, minus the skip prefixes.

$$\operatorname{infoProps}(A, O) = [\,p \in O \mid \neg\operatorname{skipped}(p, [\,], \operatorname{prefixes}(A))\,]$$

Shown for information, never judged. -/
def infoProps (a : Anchors) (originOnly : List String) : List String :=
  originOnly.filter fun p => !isSkipped p [] (prefixes a)

/-! ## Items -/

/-- A named dimension of a box.

$$\operatorname{dim}(r, d) = \begin{cases} r.d & d \in \{x, y, w, h\} \\ \bot & \text{otherwise} \end{cases}$$

Unknown dimension names have no value. -/
def dimOf (r : Rect) : String → Option Rat
  | "x" => some r.x
  | "y" => some r.y
  | "w" => some r.w
  | "h" => some r.h
  | _ => none

/-- A box relative to a reference box (position only), or as is when there is none.

$$\operatorname{rel}(r, \bot) = r, \qquad \operatorname{rel}(r, q) = (r.x - q.x,\ r.y - q.y,\ r.w,\ r.h)$$

Positions are compared relative to the reference element. -/
def relRect (r : Rect) : Option Rect → Rect
  | some q => { r with x := r.x - q.x, y := r.y - q.y }
  | none => r

/-- One dimension of an item's (relative) box.

$$\operatorname{boxDim}(i, q, d) = \operatorname{dim}(\operatorname{rel}(i.\mathrm{rect}, q), d) \quad (\bot \text{ if } i \text{ has no box})$$

The number a box item compares. -/
def boxDim (it : Item) (ref : Option Rect) (d : String) : Option Rat :=
  it.rect.bind fun r => dimOf (relRect r ref) d

/-- The items at one index of a role: boxes, compared styles, then information.

$$\operatorname{itemAt}_{\rho, C, I, q_o, q_r}(i, x, y) = [\operatorname{box}_d \mid d \in \rho.\mathrm{dims}] \mathbin{+\!\!+} [\operatorname{style}_p \mid p \in C] \mathbin{+\!\!+} [\operatorname{info}_p \mid p \in I]$$

with $\operatorname{box}_d = (\mathrm{box}, \rho.\mathrm{role}, i, d, \operatorname{boxStatus}(\operatorname{boxDim}(x, q_o, d), \operatorname{boxDim}(y, q_r, d)), \mathrm{false})$,
$\operatorname{style}_p = (\mathrm{style}, \rho.\mathrm{role}, i, p, \operatorname{styleStatus}(x_p, y_p), \mathrm{false})$ and
$\operatorname{info}_p = (\mathrm{info}, \rho.\mathrm{role}, i, p, \mathrm{na}, \neg\operatorname{styleValueEq}(x_p, y_p))$, where $x_p$ is the
value of the first entry of $x.\sigma$ with key $p$ ($\bot$ if absent), and likewise $y_p$.

One element pair yields its box, style and information items. -/
def itemAt (rs : RoleSpec) (cmp info : List String) (refO refR : Option Rect) (i : Nat)
    (io ir : Item) : List PItem :=
  rs.dims.map (fun d => ⟨.box, rs.role, i, d, boxStatus (boxDim io refO d) (boxDim ir refR d), false⟩) ++
  cmp.map (fun p => ⟨.style, rs.role, i, p, styleStatus (io.style.lookup p) (ir.style.lookup p), false⟩) ++
  info.map (fun p => ⟨.info, rs.role, i, p, .na, !styleValueEq (io.style.lookup p) (ir.style.lookup p)⟩)

/-- Pair two item lists by index, up to the shorter length.

$$\operatorname{pairs}(f, i, [x_0, \dots], [y_0, \dots]) = f(i, x_0, y_0) \mathbin{+\!\!+} f(i{+}1, x_1, y_1) \mathbin{+\!\!+} \cdots \quad (\min(|xs|, |ys|) \text{ terms})$$

Elements beyond the shorter arm are covered by the count item only. -/
def pairs (f : Nat → Item → Item → List PItem) : Nat → List Item → List Item → List PItem
  | i, x :: xs, y :: ys => f i x y ++ pairs f (i + 1) xs ys
  | _, _, _ => []

/-- The reference box of a role on one arm: item `index` of the reference role, if any.

$$\operatorname{ref}(P, b) = P[b.\mathrm{role}].\mathrm{items}[b.\mathrm{index}].\mathrm{rect} \quad (\bot \text{ if any step is absent})$$

Where relative boxes are measured from. -/
def refRect (pr : Option PartRaw) (b : Option BoxRel) : Option Rect :=
  b.bind fun b => (pr.bind (·.lookup b.role)).bind fun rr => (rr.items[b.index]?).bind (·.rect)

/-- The items of one role: a count, then the paired items; a role absent on either arm gives one
`missing` count.

$$\operatorname{roleItems}(A, \rho, \mathit{pr}, q_o, q_r, o, r) = \begin{cases} (\mathrm{count}, \rho.\mathrm{role}, -1, \texttt{count}, \operatorname{countStatus}(o.n, r.n), \mathrm{false}) :: \operatorname{pairs}(\operatorname{itemAt}_{\rho, C, I, q_o, q_r}, 0, o.\mathrm{items}, r.\mathrm{items}) & o \ne \bot \wedge r \ne \bot \\ [\,(\mathrm{count}, \rho.\mathrm{role}, -1, \texttt{count}, \mathrm{missing}, \mathrm{false})\,] & \text{otherwise} \end{cases}$$

where $C = \operatorname{compared}(A, \rho, R)$ with $R = \mathit{pr}.P_{\mathrm{restated}}$ if $\mathit{pr} \ne \bot$ else $[\,]$, and
$I = \operatorname{infoProps}(A, O)$ with $O = \mathit{pr}.P_{\mathrm{originOnly}}$ if $\mathit{pr} \ne \bot$ else $[\,]$. A role is compared element by element once both arms have it. -/
def roleItems (a : Anchors) (rs : RoleSpec) (props : Option RoleProps) (refO refR : Option Rect) :
    Option RoleRaw → Option RoleRaw → List PItem
  | some o, some r =>
    ⟨.count, rs.role, -1, "count", countStatus o.count r.count, false⟩ ::
      pairs (itemAt rs (comparedProps a rs ((props.map (·.restated)).getD []))
        (infoProps a ((props.map (·.originOnly)).getD [])) refO refR) 0 o.items r.items
  | _, _ => [⟨.count, rs.role, -1, "count", .missing, false⟩]

/-- All items of one part: the roles' items in declared order.

$$\operatorname{partItems}(A, P, o, r, \Pi) = \textstyle\bigoplus_{\rho \in P.\mathrm{roles}} \operatorname{roleItems}(A, \rho, \Pi[\rho], \operatorname{ref}(o, \rho.b), \operatorname{ref}(r, \rho.b), o[\rho], r[\rho])$$

where $x[\rho]$ is the value of the first entry with key $\rho.\mathrm{role}$ in the association list $x$, $\bot$ if there is
none or $x = \bot$. Everything one part compares in one state. -/
def partItems (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps) :
    List PItem :=
  spec.roles.flatMap fun rs =>
    roleItems a rs (props.lookup rs.role) (refRect o rs.boxRel) (refRect r rs.boxRel)
      (o.bind (·.lookup rs.role)) (r.bind (·.lookup rs.role))

/-- The verdict of one part in one state: the rule over its items' statuses.

$$\operatorname{partVerdict}(A, P, o, r, \Pi) = \operatorname{cell}([\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A, P, o, r, \Pi)\,])$$

One table cell of a part for one probe or stop. -/
def partVerdict (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps) :
    Verdict :=
  cellVerdict ((partItems a spec o r props).map (·.status))

/-! ## Membership -/

/-- Every paired item comes from one pair.

$$\forall f, i, xs, ys, it,\quad it \in \operatorname{pairs}(f, i, xs, ys) \implies \exists j, x, y,\ it \in f(j, x, y)$$

Pairing adds no items of its own. -/
theorem mem_pairs {f : Nat → Item → Item → List PItem} {i : Nat} {xs ys : List Item} {it : PItem}
    (h : it ∈ pairs f i xs ys) : ∃ j x y, it ∈ f j x y := by
  induction xs generalizing i ys with
  | nil => simp [pairs] at h
  | cons x xs ih =>
    cases ys with
    | nil => simp [pairs] at h
    | cons y ys =>
      simp only [pairs, List.mem_append] at h
      rcases h with h | h
      · exact ⟨i, x, y, h⟩
      · exact ih h

/-- Every item of a role, and how its status is made.

$$\forall A, \rho, \mathit{props}, q_o, q_r, o, r,\ \forall it \in \operatorname{roleItems}(A, \rho, \mathit{props}, q_o, q_r, o, r),\quad it.\mathrm{role} = \rho.\mathrm{role} \wedge \begin{cases} it.\mathrm{cls} = \mathrm{count} \wedge \exists m, n \in \mathbb N,\ it.\mathrm{status} \in \{\operatorname{countStatus}(m, n), \mathrm{missing}\} \\ \vee\ it.\mathrm{cls} = \mathrm{box} \wedge \exists x, y \in \mathbb Q_\bot,\ it.\mathrm{status} = \operatorname{boxStatus}(x, y) \\ \vee\ it.\mathrm{cls} = \mathrm{style} \wedge it.\mathrm{key} \in \operatorname{compared}(A, \rho, \mathit{props}.\mathrm{restated}) \wedge \exists x, y,\ it.\mathrm{status} = \operatorname{styleStatus}(x, y) \\ \vee\ it.\mathrm{cls} = \mathrm{info} \wedge it.\mathrm{key} \in \operatorname{infoProps}(A, \mathit{props}.\mathrm{originOnly}) \wedge it.\mathrm{status} = \mathrm{na} \end{cases}$$

(an absent $\mathit{props}$ reads as empty lists). Each item kind gets its status from its own comparison. -/
theorem mem_roleItems {a : Anchors} {rs : RoleSpec} {props : Option RoleProps}
    {refO refR : Option Rect} {o r : Option RoleRaw} {it : PItem}
    (h : it ∈ roleItems a rs props refO refR o r) :
    it.role = rs.role ∧
    ((it.cls = .count ∧ ∃ m n, it.status = countStatus m n ∨ it.status = .missing) ∨
     (it.cls = .box ∧ ∃ x y, it.status = boxStatus x y) ∨
     (it.cls = .style ∧ it.key ∈ comparedProps a rs ((props.map (·.restated)).getD []) ∧
        ∃ x y, it.status = styleStatus x y) ∨
     (it.cls = .info ∧ it.key ∈ infoProps a ((props.map (·.originOnly)).getD []) ∧
        it.status = .na)) := by
  unfold roleItems at h
  split at h
  · simp only [List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨rfl, .inl ⟨rfl, _, _, .inl rfl⟩⟩
    · obtain ⟨j, x, y, hj⟩ := mem_pairs h
      simp only [itemAt, List.mem_append, List.mem_map] at hj
      rcases hj with (⟨d, -, rfl⟩ | ⟨p, hp, rfl⟩) | ⟨p, hp, rfl⟩
      · exact ⟨rfl, .inr (.inl ⟨rfl, _, _, rfl⟩)⟩
      · exact ⟨rfl, .inr (.inr (.inl ⟨rfl, hp, _, _, rfl⟩))⟩
      · exact ⟨rfl, .inr (.inr (.inr ⟨rfl, hp, rfl⟩))⟩
  · simp only [List.mem_singleton] at h
    subst h
    exact ⟨rfl, .inl ⟨rfl, 0, 0, .inr rfl⟩⟩

/-! ## Properties -/

/-- Exactly the information items are `na`.

$$\forall A, \mathit{spec}, o, r, \mathit{props},\ \forall it \in \operatorname{partItems}(A, \mathit{spec}, o, r, \mathit{props}),\quad it.\mathrm{status} = \mathrm{na} \iff it.\mathrm{cls} = \mathrm{info}$$

Every count, box and style item takes part in the verdict; no information item does. -/
theorem partItems_na_iff (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps)
    (it : PItem) (h : it ∈ partItems a spec o r props) : it.status = .na ↔ it.cls = .info := by
  simp only [partItems, List.mem_flatMap] at h
  obtain ⟨rs, -, h⟩ := h
  have hn := status_ne_na
  obtain ⟨-, h⟩ := mem_roleItems h
  rcases h with ⟨hc, m, n, hs | hs⟩ | ⟨hc, x, y, hs⟩ | ⟨hc, -, x, y, hs⟩ | ⟨hc, -, hs⟩
  · rw [hc, hs]; exact ⟨fun e => absurd e (hn none none none none m n).2.2, fun e => (nomatch e)⟩
  · rw [hc, hs]; exact ⟨fun e => (nomatch e), fun e => (nomatch e)⟩
  · rw [hc, hs]; exact ⟨fun e => absurd e (hn none none x y 0 0).2.1, fun e => (nomatch e)⟩
  · rw [hc, hs]; exact ⟨fun e => absurd e (hn x y none none 0 0).1, fun e => (nomatch e)⟩
  · rw [hc, hs]; exact ⟨fun _ => rfl, fun _ => rfl⟩

/-- A part passes exactly when it compared something and every compared item is equal.

$$\forall A, \mathit{spec}, o, r, \mathit{props},\quad \operatorname{partVerdict} = \mathrm{pass} \iff (\exists it \in \mathcal I,\ it.\mathrm{cls} \ne \mathrm{info}) \wedge \forall it \in \mathcal I,\ it.\mathrm{cls} \ne \mathrm{info} \implies it.\mathrm{status} = \mathrm{equal}$$

where $\mathcal I = \operatorname{partItems}(A, \mathit{spec}, o, r, \mathit{props})$. A part's cell passes iff all its compared items pass. -/
theorem partVerdict_pass_iff (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps) :
    partVerdict a spec o r props = .pass ↔
      (∃ it ∈ partItems a spec o r props, it.cls ≠ .info) ∧
      ∀ it ∈ partItems a spec o r props, it.cls ≠ .info → it.status = .equal := by
  have hna := partItems_na_iff a spec o r props
  unfold partVerdict
  rw [cellVerdict_pass_iff]
  simp only [List.mem_map]
  constructor
  · rintro ⟨⟨s, ⟨it, hit, rfl⟩, hs⟩, hall⟩
    refine ⟨⟨it, hit, fun hc => ?_⟩, fun it' hit' hc => ?_⟩
    · have := (hna it hit).mpr hc; rw [this] at hs; cases hs
    · rcases hall _ ⟨it', hit', rfl⟩ with h | h
      · exact absurd ((hna it' hit').mp h) hc
      · exact h
  · rintro ⟨⟨it, hit, hc⟩, hall⟩
    refine ⟨⟨it.status, ⟨it, hit, rfl⟩, hall it hit hc⟩, ?_⟩
    rintro s ⟨it', hit', rfl⟩
    by_cases hc' : it'.cls = .info
    · exact .inl ((hna it' hit').mpr hc')
    · exact .inr (hall it' hit' hc')

/-- A part fails exactly when one compared item is not equal.

$$\forall A, \mathit{spec}, o, r, \mathit{props},\quad \operatorname{partVerdict} = \mathrm{fail} \iff \exists it \in \operatorname{partItems}(A, \mathit{spec}, o, r, \mathit{props}),\ it.\mathrm{cls} \ne \mathrm{info} \wedge it.\mathrm{status} \ne \mathrm{equal}$$

One differing or missing count, box or style item fails the cell. -/
theorem partVerdict_fail_iff (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps) :
    partVerdict a spec o r props = .fail ↔
      ∃ it ∈ partItems a spec o r props, it.cls ≠ .info ∧ it.status ≠ .equal := by
  have hna := partItems_na_iff a spec o r props
  unfold partVerdict
  rw [cellVerdict_fail_iff]
  simp only [List.mem_map]
  constructor
  · rintro ⟨s, ⟨it, hit, rfl⟩, h1, h2⟩
    exact ⟨it, hit, fun hc => h1 ((hna it hit).mpr hc), h2⟩
  · rintro ⟨it, hit, hc, he⟩
    exact ⟨it.status, ⟨it, hit, rfl⟩, fun h => hc ((hna it hit).mp h), he⟩

/-- A style item's property is never skipped for its role, and an information item's property
never carries a skip prefix.

$$\forall A, \mathit{spec}, o, r, \mathit{props},\ \forall it \in \operatorname{partItems}(A, \mathit{spec}, o, r, \mathit{props}),\quad \bigl(it.\mathrm{cls} = \mathrm{style} \implies \exists \rho \in \mathit{spec}.\mathrm{roles},\ \rho.\mathrm{role} = it.\mathrm{role} \wedge \neg\operatorname{skipped}(it.\mathrm{key}, \operatorname{skipNames}(A, \rho), \operatorname{prefixes}(A))\bigr) \wedge \bigl(it.\mathrm{cls} = \mathrm{info} \implies \neg\operatorname{skipped}(it.\mathrm{key}, [\,], \operatorname{prefixes}(A))\bigr)$$

Declared skips never reach the comparison. -/
theorem partItems_style_not_skipped (a : Anchors) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (it : PItem) (h : it ∈ partItems a spec o r props) :
    (it.cls = .style → ∃ rs ∈ spec.roles, rs.role = it.role ∧
        isSkipped it.key (skipNames a rs) (prefixes a) = false) ∧
    (it.cls = .info → isSkipped it.key [] (prefixes a) = false) := by
  simp only [partItems, List.mem_flatMap] at h
  obtain ⟨rs, hrs, h⟩ := h
  obtain ⟨hrole, h⟩ := mem_roleItems h
  rcases h with ⟨hc, -⟩ | ⟨hc, -⟩ | ⟨hc, hk, -⟩ | ⟨hc, hk, -⟩ <;> rw [hc] <;>
    refine ⟨fun e => ?_, fun e => ?_⟩ <;> try cases e
  · refine ⟨rs, hrs, hrole.symm, ?_⟩
    simp only [comparedProps, List.mem_filter, Bool.not_eq_eq_eq_not, Bool.not_true] at hk
    exact hk.2
  · simp only [infoProps, List.mem_filter, Bool.not_eq_eq_eq_not, Bool.not_true] at hk
    exact hk.2

/-! ## Skipped properties never change a status -/

/-- Two items agree off a property: the same box, and the same value for every other property.

$$x \approx_p y \iff x.\mathrm{rect} = y.\mathrm{rect} \wedge \forall q \ne p,\ x[q] = y[q]$$

What changing one property leaves alone. -/
def AgreeOff (p : String) (x y : Item) : Prop :=
  x.rect = y.rect ∧ ∀ q, q ≠ p → x.style.lookup q = y.style.lookup q

/-- Apply an item change to every element of one role.

$$\operatorname{mapRole}_{\rho, g}(P) = [\,(k, R') \mid (k, R) \in P\,],\quad R' = \begin{cases} (R.n, [\,g(x) \mid x \in R.\mathrm{items}\,]) & k = \rho \\ R & k \ne \rho \end{cases}$$

Edit one role on one arm (every entry with key $\rho$, if the key repeats). -/
def mapRole (ρ : String) (g : Item → Item) (pr : PartRaw) : PartRaw :=
  pr.map fun e => if e.1 = ρ then (e.1, { e.2 with items := e.2.items.map g }) else e

/-- Set (or remove) one computed-style property of an element.

$$\operatorname{setStyle}_{p, v}(x) = (x.q,\ \sigma'),\quad \sigma' = \begin{cases} (p, s) :: [\,e \in x.\sigma \mid e.1 \ne p\,] & v = s \ne \bot \\ [\,e \in x.\sigma \mid e.1 \ne p\,] & v = \bot \end{cases}$$

so the box is kept, $\operatorname{setStyle}_{p, v}(x)[p] = v$ and $\operatorname{setStyle}_{p, v}(x)[q] = x[q]$ for $q \ne p$
(lookup of the first entry, $\bot$ if absent), with $v \in \mathrm{String}_\bot$; $v = \bot$ removes $p$. Change a single
property value. -/
def setStyle (p : String) (v : Option String) (x : Item) : Item :=
  { x with style := (match v with | some s => [(p, s)] | none => []) ++ x.style.filter (·.1 != p) }

/-- Dropping the entries of one key leaves the other keys' values.

$$\forall p, q, st,\quad q \ne p \implies \operatorname{lookup}(q, [\,e \in st \mid e.1 \ne p\,]) = \operatorname{lookup}(q, st)$$

Removing a property hides no other property. -/
theorem lookup_filter_ne (p q : String) (h : q ≠ p) (st : List (String × String)) :
    (st.filter (·.1 != p)).lookup q = st.lookup q := by
  induction st with
  | nil => rfl
  | cons e es ih =>
    obtain ⟨k, v⟩ := e
    by_cases hk : k = p
    · subst hk
      have : (q == k) = false := by simpa using h
      simp [List.lookup_cons, this, ih]
    · have hk' : (k != p) = true := by simpa using hk
      simp only [List.filter_cons, hk', ite_true, List.lookup_cons, ih]

/-- Setting a property changes no box and no other property.

$$\forall p, v, x,\quad \operatorname{setStyle}_{p, v}(x) \approx_p x$$

The edit is local to its property. -/
theorem setStyle_agree (p : String) (v : Option String) (x : Item) : AgreeOff p (setStyle p v x) x := by
  refine ⟨rfl, fun q hq => ?_⟩
  have hb : (q == p) = false := by simpa using hq
  cases v <;> simp [setStyle, List.lookup_cons, hb, lookup_filter_ne p q hq]

/-- A role looked up after `mapRole` is the role looked up before, changed only if it is $\rho$.

$$\forall \rho, g, P, k,\quad \operatorname{mapRole}_{\rho, g}(P)[k] = \begin{cases} P[k] \text{ with items } g(\cdot) & k = \rho \\ P[k] & k \ne \rho \end{cases}$$

Editing one role leaves the others alone. -/
theorem lookup_mapRole (ρ : String) (g : Item → Item) (pr : PartRaw) (k : String) :
    (mapRole ρ g pr).lookup k =
      (pr.lookup k).map fun rr => if k = ρ then { rr with items := rr.items.map g } else rr := by
  induction pr with
  | nil => rfl
  | cons e es ih =>
    obtain ⟨k', rr⟩ := e
    simp only [mapRole, List.map_cons] at ih ⊢
    by_cases hk : k = k'
    · subst hk
      by_cases hρ : k = ρ <;> simp [hρ]
    · have hb : (k == k') = false := by simpa using hk
      by_cases hρ : k' = ρ
      · subst hρ; simp [List.lookup_cons, hb, ih]
      · simp [hρ, List.lookup_cons, hb, ih]

/-- A change that keeps every box keeps every reference box.

$$\forall \rho, g, P, b,\quad (\forall x,\ g(x).\mathrm{rect} = x.\mathrm{rect}) \implies \operatorname{ref}(\operatorname{mapRole}_{\rho, g}(P), b) = \operatorname{ref}(P, b)$$

Style edits never move the reference. -/
theorem refRect_mapRole (ρ : String) (g : Item → Item) (hg : ∀ x, (g x).rect = x.rect)
    (pr : Option PartRaw) (b : Option BoxRel) :
    refRect (pr.map (mapRole ρ g)) b = refRect pr b := by
  cases b with
  | none => rfl
  | some b =>
    cases pr with
    | none => rfl
    | some pr =>
      simp only [refRect, Option.map_some, Option.bind_some, lookup_mapRole]
      cases pr.lookup b.role with
      | none => rfl
      | some rr =>
        simp only [Option.map_some, Option.bind_some]
        split
        · simp only [List.getElem?_map]
          cases rr.items[b.index]? with
          | none => rfl
          | some x => simp [hg]
        · rfl

/-- Changing the elements of both arms keeps the paired statuses when it keeps each pair's.

$$\forall f, h_1, h_2,\quad \bigl(\forall i, x, y,\ \operatorname{st}(f(i, h_1 x, h_2 y)) = \operatorname{st}(f(i, x, y))\bigr) \implies \forall i, xs, ys,\ \operatorname{st}(\operatorname{pairs}(f, i, h_1(xs), h_2(ys))) = \operatorname{st}(\operatorname{pairs}(f, i, xs, ys))$$

where $\operatorname{st}$ lists the statuses. Pairing respects element-wise invariance. -/
theorem pairs_congr (f : Nat → Item → Item → List PItem) (h₁ h₂ : Item → Item)
    (hf : ∀ i x y, (f i (h₁ x) (h₂ y)).map (·.status) = (f i x y).map (·.status)) :
    ∀ (i : Nat) (xs ys : List Item),
      (pairs f i (xs.map h₁) (ys.map h₂)).map (·.status) = (pairs f i xs ys).map (·.status) := by
  intro i xs
  induction xs generalizing i with
  | nil => intro ys; rfl
  | cons x xs ih =>
    intro ys
    cases ys with
    | nil => rfl
    | cons y ys => simp only [List.map_cons, pairs, List.map_append, hf, ih]

/-- The statuses at one index depend only on the boxes and the compared properties.

$$\forall \mathit{rs}, C, I, \mathit{refO}, \mathit{refR}, i, x, x', y, y',\quad \bigl(x.\mathrm{rect} = x'.\mathrm{rect} \wedge y.\mathrm{rect} = y'.\mathrm{rect} \wedge (\forall q \in C,\ x[q] = x'[q] \wedge y[q] = y'[q])\bigr) \implies \operatorname{st}(\operatorname{itemAt}_{\mathit{rs}, C, I, \mathit{refO}, \mathit{refR}}(i, x, y)) = \operatorname{st}(\operatorname{itemAt}_{\mathit{rs}, C, I, \mathit{refO}, \mathit{refR}}(i, x', y'))$$

where $\operatorname{st}(L) = [\,it.\mathrm{status} \mid it \in L\,]$ and $x[q]$ is the first style entry of $x$ with key $q$ ($\bot$ if
absent). Information properties never touch a status. -/
theorem itemAt_congr (rs : RoleSpec) (cmp info : List String) (refO refR : Option Rect) (i : Nat)
    (x x' y y' : Item) (hx : x.rect = x'.rect) (hy : y.rect = y'.rect)
    (hs : ∀ q ∈ cmp, x.style.lookup q = x'.style.lookup q ∧ y.style.lookup q = y'.style.lookup q) :
    (itemAt rs cmp info refO refR i x y).map (·.status) =
      (itemAt rs cmp info refO refR i x' y').map (·.status) := by
  simp only [itemAt, List.map_append, List.map_map]
  congr 1
  congr 1
  · apply List.map_congr_left
    intro d _
    simp [boxDim, hx, hy]
  · apply List.map_congr_left
    intro q hq
    simp [(hs q hq).1, (hs q hq).2]

/-- `flatMap` only looks at the elements of its list.

$$\forall l, f, g,\quad (\forall x \in l,\ f(x) = g(x)) \implies \operatorname{flatMap}(f, l) = \operatorname{flatMap}(g, l)$$

Equal pieces give equal concatenations. -/
theorem flatMap_congr' {α β : Type} {l : List α} {f g : α → List β} (h : ∀ x ∈ l, f x = g x) :
    l.flatMap f = l.flatMap g := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.flatMap_cons, h x (List.mem_cons_self ..),
      ih (fun y hy => h y (List.mem_cons_of_mem _ hy))]

/-- Changing a skipped property, on either arm and in any element of its role, changes no status.

$$\forall A, P, o, r, \Pi, \rho, p, g_1, g_2,\quad \bigl(\forall x,\ g_1(x) \approx_p x \wedge g_2(x) \approx_p x\bigr) \wedge \bigl(\forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = \rho \implies \operatorname{skipped}(p, \operatorname{skipNames}(A, \sigma), \operatorname{prefixes}(A))\bigr)$$
$$\implies [\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A, P, \operatorname{mapRole}_{\rho, g_1}(o), \operatorname{mapRole}_{\rho, g_2}(r), \Pi)\,] = [\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A, P, o, r, \Pi)\,]$$

Skipped properties are never compared, so they can never fail a cell. -/
theorem partItems_skip_invariant (a : Anchors) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (ρ p : String) (g₁ g₂ : Item → Item)
    (hg₁ : ∀ x, AgreeOff p (g₁ x) x) (hg₂ : ∀ x, AgreeOff p (g₂ x) x)
    (hskip : ∀ rs ∈ spec.roles, rs.role = ρ → isSkipped p (skipNames a rs) (prefixes a) = true) :
    (partItems a spec (o.map (mapRole ρ g₁)) (r.map (mapRole ρ g₂)) props).map (·.status) =
      (partItems a spec o r props).map (·.status) := by
  simp only [partItems, List.map_flatMap]
  apply flatMap_congr'
  intro rs hrs
  rw [refRect_mapRole ρ g₁ (fun x => (hg₁ x).1), refRect_mapRole ρ g₂ (fun x => (hg₂ x).1)]
  have hlo : (o.map (mapRole ρ g₁)).bind (·.lookup rs.role) =
      (o.bind (·.lookup rs.role)).map fun rr =>
        if rs.role = ρ then { rr with items := rr.items.map g₁ } else rr := by
    cases o <;> simp [lookup_mapRole]
  have hlr : (r.map (mapRole ρ g₂)).bind (·.lookup rs.role) =
      (r.bind (·.lookup rs.role)).map fun rr =>
        if rs.role = ρ then { rr with items := rr.items.map g₂ } else rr := by
    cases r <;> simp [lookup_mapRole]
  rw [hlo, hlr]
  cases o.bind (·.lookup rs.role) with
  | none => simp [roleItems]
  | some oo =>
    cases r.bind (·.lookup rs.role) with
    | none => simp [roleItems]
    | some rr =>
      simp only [Option.map_some, roleItems, List.map_cons]
      congr 1
      · by_cases hρ : rs.role = ρ <;> simp [hρ]
      · by_cases hρ : rs.role = ρ
        · simp only [hρ, ite_true]
          apply pairs_congr
          intro i x y
          apply itemAt_congr
          · exact (hg₁ x).1
          · exact (hg₂ y).1
          · intro q hq
            have hqp : q ≠ p := by
              intro e
              subst e
              simp only [comparedProps, List.mem_filter] at hq
              rw [hskip rs hrs hρ] at hq
              simp at hq
            exact ⟨(hg₁ x).2 q hqp, (hg₂ y).2 q hqp⟩
        · simp only [hρ, ite_false]

/-- Setting one skipped property to any value on both arms keeps the verdict.

$$\forall A, P, o, r, \Pi, \rho, p, v, w,\quad \bigl(\forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = \rho \implies \operatorname{skipped}(p, \operatorname{skipNames}(A, \sigma), \operatorname{prefixes}(A))\bigr) \implies \operatorname{partVerdict}(A, P, \operatorname{mapRole}_{\rho, \operatorname{setStyle}_{p,v}}(o), \operatorname{mapRole}_{\rho, \operatorname{setStyle}_{p,w}}(r), \Pi) = \operatorname{partVerdict}(A, P, o, r, \Pi)$$

where $v, w \in \mathrm{String}_\bot$, $o, r \in \mathrm{PartRaw}_\bot$, and $\operatorname{mapRole}$ is applied through the option
($\bot \mapsto \bot$). A skipped property never fails a cell, whatever its value on either arm. -/
theorem partVerdict_setStyle (a : Anchors) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (ρ p : String) (v w : Option String)
    (hskip : ∀ rs ∈ spec.roles, rs.role = ρ → isSkipped p (skipNames a rs) (prefixes a) = true) :
    partVerdict a spec (o.map (mapRole ρ (setStyle p v))) (r.map (mapRole ρ (setStyle p w))) props =
      partVerdict a spec o r props := by
  unfold partVerdict
  rw [partItems_skip_invariant a spec o r props ρ p _ _ (setStyle_agree p v) (setStyle_agree p w) hskip]

/-- The order in which a part lists its roles does not change its verdict.

$$\forall A, \mathit{spec}, \mathit{spec}', o, r, \mathit{props},\quad \mathit{spec}.\mathrm{roles} \sim \mathit{spec}'.\mathrm{roles} \implies \operatorname{partVerdict}(A, \mathit{spec}, o, r, \mathit{props}) = \operatorname{partVerdict}(A, \mathit{spec}', o, r, \mathit{props})$$

Reordering the anchors of a part never changes its cell. -/
theorem partVerdict_perm (a : Anchors) (spec spec' : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (h : spec.roles.Perm spec'.roles) :
    partVerdict a spec o r props = partVerdict a spec' o r props := by
  unfold partVerdict partItems
  apply cellVerdict_perm
  exact ((h.flatMap_right _).map _)

/-! ## Well-formed declarations -/

/-- Every skip and every role carries a reason, every named skip set exists, and every box
reference names a role of the same part.

$$\operatorname{wf}(A, \mathcal P) \iff \begin{aligned}[t] & (\forall q \in A.\mathrm{skipPrefixes},\ q.\mathrm{why} \ne \varepsilon) \ \wedge\ (\forall s \in A.\mathrm{skipSets},\ s.\mathrm{why} \ne \varepsilon) \ \wedge \\ & \bigl(\forall P \in \mathcal P,\ \forall \rho \in P.\mathrm{roles},\ \rho.\mathrm{why} \ne \varepsilon \wedge (\forall n \in \rho.\mathrm{skipSets},\ \exists s \in A.\mathrm{skipSets},\ s.\mathrm{name} = n) \wedge (\forall b,\ \rho.\mathrm{boxRel} = b \implies \exists \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = b.\mathrm{role})\bigr) \end{aligned}$$

No comparison is dropped without a stated reason. -/
def wellFormed (a : Anchors) (ps : List PartSpec) : Bool :=
  a.skipPrefixes.all (fun q => !q.why.isEmpty) && a.skipSets.all (fun s => !s.why.isEmpty) &&
  ps.all fun p => p.roles.all fun rs =>
    !rs.why.isEmpty && rs.skipSets.all (fun n => a.skipSets.any (·.name == n)) &&
    rs.boxRel.all fun b => p.roles.any (·.role == b.role)

/-! ## Examples -/

private def exA : Anchors :=
  ⟨[⟨"animation", "x"⟩], [⟨"layoutDerived", ["width", "height"], "x"⟩]⟩
private def exSpec : PartSpec :=
  ⟨"p", [⟨"root", none, ["x", "w"], ["layoutDerived"], ["transform"], "x"⟩]⟩
private def exProps : PartProps :=
  [("root", ⟨["color", "width", "transform", "animation-name", "top"], ["font-size", "animation"]⟩)]
private def exItem (x : Rat) (color top fs : String) : Item :=
  ⟨some ⟨x, 0, 10, 10⟩, [("color", color), ("top", top), ("font-size", fs), ("width", "1px")]⟩
private def exArm (n : Nat) (its : List Item) : Option PartRaw := some [("root", ⟨n, its⟩)]

#guard comparedProps exA exSpec.roles[0]! ["color", "width", "transform", "animation-name", "top"] ==
  ["color", "top"]
#guard isSkipped "animation" [] ["animation"] && isSkipped "animation-delay" [] ["animation"] &&
  !isSkipped "animations" [] ["animation"]
#guard (partItems exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 1 [exItem (2/5) "red" "0px" "2px"])
  exProps).map (fun it => (it.key, it.status, it.differs)) ==
  [("count", .equal, false), ("x", .equal, false), ("w", .equal, false), ("color", .equal, false),
   ("top", .equal, false), ("font-size", .na, true)]
#guard partVerdict exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 1 [exItem 0 "red" "0px" "1px"]) exProps == .pass
#guard partVerdict exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 1 [exItem 1 "red" "0px" "1px"]) exProps == .fail
#guard partVerdict exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 2 [exItem 0 "red" "0px" "1px"]) exProps == .fail
#guard partVerdict exA exSpec none (exArm 1 []) exProps == .fail
#guard partVerdict exA ⟨"p", []⟩ none none exProps == .nc
#guard wellFormed exA [exSpec]
#guard !wellFormed exA [⟨"p", [⟨"root", none, [], ["nope"], [], "x"⟩]⟩]
#guard !wellFormed exA [⟨"p", [⟨"root", some ⟨"other", 0⟩, [], [], [], "x"⟩]⟩]
#guard !wellFormed exA [⟨"p", [⟨"root", none, [], [], [], ""⟩]⟩]
-- only `info` differs: still a pass
#guard partVerdict exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 1 [exItem 0 "red" "0px" "9px"]) exProps == .pass

end Fw.Gate
