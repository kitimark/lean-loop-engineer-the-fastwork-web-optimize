import Fw.Gate.Compare
/-!
# The items of one part (port of `partItems` in `packages/gate-breakpoints/src/verdict.mjs`)

`anchors.json` declares, per part, the roles to compare (each with a reason): which box dimensions
(`dims`, optionally relative to the first box of a reference role, `boxRel`), and which properties
are not compared: a role's own `skipProps`, the named `skipSets`, and the global `skipPrefixes`
(each with a reason). A role may also name `skipIfInline` properties: such a property is left out of one pair only
when the original's element sets it inline (`Item.inline`), so it is still compared on every other pair.
For one sampled state the original arm `o` and the rewrite arm `r` give, per
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

A part may declare variant roles (`variantRoles`): under a rewrite variant that changes its element structure on purpose,
one role is replaced by a rewrite-only role judged by its count against the original's count of a named role. Proved:
every other item is unchanged (`partItems_variant`, `partItems_variant_others`), the replaced role is not judged and the
new one is judged by count alone (`partItems_variant_role`, `variantCount_equal_iff`, `variantCount_missing`), and a part
with no variant role is judged as before (`partItems_variant_none`).
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

$$r = (\rho,\ b,\ D,\ N_{\mathrm{sets}},\ N_{\mathrm{props}},\ N_{\mathrm{inline}},\ \mathit{why}) \in \mathrm{String} \times \mathrm{BoxRel}_\bot \times (\mathrm{String}^{*})^{4} \times \mathrm{String}$$

$N_{\mathrm{inline}}$ (`skipIfInline`) names the properties skipped on a pair only where the original's element sets them inline.
-/
structure RoleSpec where
  role : String
  boxRel : Option BoxRel
  dims : List String
  skipSets : List String
  skipProps : List String
  skipIfInline : List String
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

$$e = (q,\ \sigma,\ \iota) \in \mathrm{Rect}_\bot \times (\mathrm{String} \times \mathrm{String})^{*} \times \mathrm{String}^{*}$$

$\iota$ (`inline`) lists the properties the element's own `style` attribute sets; the runner records it only for the
properties a role names in `skipIfInline`.
-/
structure Item where
  rect : Option Rect
  style : List (String × String)
  inline : List String
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

$$\operatorname{skipNames}(A, \rho) = \rho.\mathrm{skipProps} \mathbin{+\!\!+} \textstyle\bigoplus_{s \in \rho.\mathrm{skipSets}} \operatorname{props}_A(s),\quad \operatorname{props}_A(s) = \begin{cases} S.P & S \text{ is the first element of } A.\mathcal S \text{ (in list order) with } S.\mathit{name} = s \\ [\,] & \text{there is none} \end{cases}$$

A role's own skips and those of the sets it names (an undeclared set adds nothing). -/
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

/-- The compared properties at one pair: the role's compared ones, minus those it skips where the original sets them inline.

$$\operatorname{cmpAt}_{\rho}(C, x) = [\,p \in C \mid \neg(p \in \rho.\mathrm{skipIfInline} \wedge p \in x.\iota)\,]$$

A property named in `skipIfInline` is dropped only for an original element that sets it inline, and stays for every other. -/
def cmpAt (rs : RoleSpec) (cmp : List String) (io : Item) : List String :=
  cmp.filter fun p => !(rs.skipIfInline.contains p && io.inline.contains p)

/-- A property that is compared and not named in `skipIfInline` is compared on every pair, whatever the original sets inline.

$$p \in C \wedge p \notin \rho.\mathrm{skipIfInline} \implies p \in \operatorname{cmpAt}_\rho(C, x)$$

The inline rule never skips a property that the role did not name. -/
theorem cmpAt_not_named (rs : RoleSpec) (cmp : List String) (io : Item) (p : String) (hp : p ∈ cmp)
    (hn : p ∉ rs.skipIfInline) : p ∈ cmpAt rs cmp io := by
  simp [cmpAt, hp, hn]

/-- A named property is compared on every pair whose original element does not set it inline.

$$p \in C \wedge p \notin x.\iota \implies p \in \operatorname{cmpAt}_\rho(C, x)$$

No blanket skip: the property is dropped only where the original set it inline. -/
theorem cmpAt_not_inline (rs : RoleSpec) (cmp : List String) (io : Item) (p : String) (hp : p ∈ cmp)
    (hn : p ∉ io.inline) : p ∈ cmpAt rs cmp io := by
  simp [cmpAt, hp, hn]

/-- A named property that the original sets inline is dropped.

$$p \in \rho.\mathrm{skipIfInline} \wedge p \in x.\iota \implies p \notin \operatorname{cmpAt}_\rho(C, x)$$

The raised original element is not judged on that property. -/
theorem cmpAt_inline_dropped (rs : RoleSpec) (cmp : List String) (io : Item) (p : String)
    (hs : p ∈ rs.skipIfInline) (hi : p ∈ io.inline) : p ∉ cmpAt rs cmp io := by
  simp [cmpAt, hs, hi]

/-- Every property that `cmpAt` keeps is one of the role's compared properties.

$$p \in \operatorname{cmpAt}_\rho(C, x) \implies p \in C$$

The inline rule only removes. -/
theorem cmpAt_subset (rs : RoleSpec) (cmp : List String) (io : Item) (p : String)
    (h : p ∈ cmpAt rs cmp io) : p ∈ cmp := (List.mem_filter.mp h).1

/-- The items at one index of a role: boxes, compared styles, then information.

$$\operatorname{itemAt}_{\rho, C, I, q_o, q_r}(i, x, y) = [\operatorname{box}_d \mid d \in \rho.\mathrm{dims}] \mathbin{+\!\!+} [\operatorname{style}_p \mid p \in \operatorname{cmpAt}_\rho(C, x)] \mathbin{+\!\!+} [\operatorname{info}_p \mid p \in I],\quad \text{where } \operatorname{box}_d = (\mathrm{box}, \rho.\mathrm{role}, i, d, \operatorname{boxStatus}(\operatorname{boxDim}(x, q_o, d), \operatorname{boxDim}(y, q_r, d)), \mathrm{false}),\ \operatorname{style}_p = (\mathrm{style}, \rho.\mathrm{role}, i, p, \operatorname{styleStatus}(x_p, y_p), \mathrm{false}),\ \operatorname{info}_p = (\mathrm{info}, \rho.\mathrm{role}, i, p, \mathrm{na}, \neg\operatorname{styleValueEq}(x_p, y_p)),\ x_p = \text{the value of the first entry of } x.\sigma \text{ with key } p \text{ (} \bot \text{ if absent)},\ y_p = \text{likewise for } y$$

One element pair yields its box, style and information items. -/
def itemAt (rs : RoleSpec) (cmp info : List String) (refO refR : Option Rect) (i : Nat)
    (io ir : Item) : List PItem :=
  rs.dims.map (fun d => ⟨.box, rs.role, i, d, boxStatus (boxDim io refO d) (boxDim ir refR d), false⟩) ++
  (cmpAt rs cmp io).map (fun p => ⟨.style, rs.role, i, p, styleStatus (io.style.lookup p) (ir.style.lookup p), false⟩) ++
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

$$\operatorname{roleItems}(A, \rho, \mathit{pr}, q_o, q_r, o, r) = \begin{cases} (\mathrm{count}, \rho.\mathrm{role}, -1, \texttt{count}, \operatorname{countStatus}(o.n, r.n), \mathrm{false}) :: \operatorname{pairs}(\operatorname{itemAt}_{\rho, C, I, q_o, q_r}, 0, o.\mathrm{items}, r.\mathrm{items}) & o \ne \bot \wedge r \ne \bot \\ [\,(\mathrm{count}, \rho.\mathrm{role}, -1, \texttt{count}, \mathrm{missing}, \mathrm{false})\,] & \text{otherwise} \end{cases},\quad \text{where } C = \operatorname{compared}(A, \rho, R),\ I = \operatorname{infoProps}(A, O),\ R = \begin{cases} \mathit{pr}.P_{\mathrm{restated}} & \mathit{pr} \ne \bot \\ [\,] & \mathit{pr} = \bot \end{cases},\ O = \begin{cases} \mathit{pr}.P_{\mathrm{originOnly}} & \mathit{pr} \ne \bot \\ [\,] & \mathit{pr} = \bot \end{cases}$$

A role is compared element by element once both arms have it. -/
def roleItems (a : Anchors) (rs : RoleSpec) (props : Option RoleProps) (refO refR : Option Rect) :
    Option RoleRaw → Option RoleRaw → List PItem
  | some o, some r =>
    ⟨.count, rs.role, -1, "count", countStatus o.count r.count, false⟩ ::
      pairs (itemAt rs (comparedProps a rs ((props.map (·.restated)).getD []))
        (infoProps a ((props.map (·.originOnly)).getD [])) refO refR) 0 o.items r.items
  | _, _ => [⟨.count, rs.role, -1, "count", .missing, false⟩]

/-- All items of one part: the roles' items in declared order.

$$\operatorname{partItems}(A, P, o, r, \Pi) = \textstyle\bigoplus_{\rho \in P.\mathrm{roles}} \operatorname{roleItems}(A, \rho, \Pi[\rho], \operatorname{ref}(o, \rho.b), \operatorname{ref}(r, \rho.b), o[\rho], r[\rho]),\quad \text{where } x[\rho] = \text{the value of the first entry with key } \rho.\mathrm{role} \text{ in the association list } x,\ \bot \text{ if there is none or } x = \bot$$

Everything one part compares in one state. -/
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
      · exact ⟨rfl, .inr (.inr (.inl ⟨rfl, cmpAt_subset _ _ _ _ hp, _, _, rfl⟩))⟩
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

$$\forall A, \mathit{spec}, o, r, \mathit{props},\quad \operatorname{partVerdict}(A, \mathit{spec}, o, r, \mathit{props}) = \mathrm{pass} \iff (\exists it \in \mathcal I,\ it.\mathrm{cls} \ne \mathrm{info}) \wedge \forall it \in \mathcal I,\ it.\mathrm{cls} \ne \mathrm{info} \implies it.\mathrm{status} = \mathrm{equal},\quad \text{where } \mathcal I = \operatorname{partItems}(A, \mathit{spec}, o, r, \mathit{props})$$

A part's cell passes iff all its compared items pass. -/
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

$$\operatorname{setStyle}_{p, v}(x) = (x.q,\ \sigma',\ x.\iota),\quad \sigma' = \begin{cases} (p, s) :: [\,e \in x.\sigma \mid e.1 \ne p\,] & v = s \ne \bot \\ [\,e \in x.\sigma \mid e.1 \ne p\,] & v = \bot \end{cases}$$

so the box and the inline list are kept, $\operatorname{setStyle}_{p, v}(x)[p] = v$ and $\operatorname{setStyle}_{p, v}(x)[q] = x[q]$ for $q \ne p$
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

$$\forall f, h_1, h_2,\quad \bigl(\forall i, x, y,\ \operatorname{st}(f(i, h_1 x, h_2 y)) = \operatorname{st}(f(i, x, y))\bigr) \implies \forall i, xs, ys,\ \operatorname{st}(\operatorname{pairs}(f, i, \operatorname{map}(h_1, xs), \operatorname{map}(h_2, ys))) = \operatorname{st}(\operatorname{pairs}(f, i, xs, ys)),\quad \text{where } \operatorname{st}(L) = [\,it.\mathrm{status} \mid it \in L\,],\ \operatorname{map}(h, xs) = [\,h(x) \mid x \in xs\,]$$

Pairing respects element-wise invariance. -/
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

$$\forall \mathit{rs}, C, I, \mathit{refO}, \mathit{refR}, i, x, x', y, y',\quad \bigl(x.\mathrm{rect} = x'.\mathrm{rect} \wedge x.\iota = x'.\iota \wedge y.\mathrm{rect} = y'.\mathrm{rect} \wedge (\forall q \in C,\ x[q] = x'[q] \wedge y[q] = y'[q])\bigr) \implies \operatorname{st}(\operatorname{itemAt}_{\mathit{rs}, C, I, \mathit{refO}, \mathit{refR}}(i, x, y)) = \operatorname{st}(\operatorname{itemAt}_{\mathit{rs}, C, I, \mathit{refO}, \mathit{refR}}(i, x', y')),\quad \text{where } \operatorname{st}(L) = [\,it.\mathrm{status} \mid it \in L\,],\ x[q] = \text{the first style entry of } x \text{ with key } q \text{ (} \bot \text{ if absent)}$$

Information properties never touch a status. -/
theorem itemAt_congr (rs : RoleSpec) (cmp info : List String) (refO refR : Option Rect) (i : Nat)
    (x x' y y' : Item) (hx : x.rect = x'.rect) (hxi : x.inline = x'.inline) (hy : y.rect = y'.rect)
    (hs : ∀ q ∈ cmp, x.style.lookup q = x'.style.lookup q ∧ y.style.lookup q = y'.style.lookup q) :
    (itemAt rs cmp info refO refR i x y).map (·.status) =
      (itemAt rs cmp info refO refR i x' y').map (·.status) := by
  have hc : cmpAt rs cmp x = cmpAt rs cmp x' := by simp only [cmpAt, hxi]
  simp only [itemAt, List.map_append, List.map_map, hc]
  congr 1
  congr 1
  · apply List.map_congr_left
    intro d _
    simp [boxDim, hx, hy]
  · apply List.map_congr_left
    intro q hq
    have hq' := hs q (cmpAt_subset _ _ _ _ hq)
    simp [hq'.1, hq'.2]

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

$$\forall A, P, o, r, \Pi, \rho, p, g_1, g_2,\quad \bigl(\forall x,\ g_1(x) \approx_p x \wedge g_2(x) \approx_p x \wedge g_1(x).\iota = x.\iota\bigr) \wedge \bigl(\forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = \rho \implies \operatorname{skipped}(p, \operatorname{skipNames}(A, \sigma), \operatorname{prefixes}(A))\bigr)$$
$$\implies [\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A, P, \operatorname{mapRole}_{\rho, g_1}(o), \operatorname{mapRole}_{\rho, g_2}(r), \Pi)\,] = [\,it.\mathrm{status} \mid it \in \operatorname{partItems}(A, P, o, r, \Pi)\,]$$

Skipped properties are never compared, so they can never fail a cell. -/
theorem partItems_skip_invariant (a : Anchors) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (ρ p : String) (g₁ g₂ : Item → Item)
    (hg₁ : ∀ x, AgreeOff p (g₁ x) x) (hg₂ : ∀ x, AgreeOff p (g₂ x) x)
    (hi₁ : ∀ x, (g₁ x).inline = x.inline)
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
          · exact hi₁ x
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

$$\forall A, P, o, r, \Pi, \rho, p, v, w,\quad \bigl(\forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = \rho \implies \operatorname{skipped}(p, \operatorname{skipNames}(A, \sigma), \operatorname{prefixes}(A))\bigr) \implies \operatorname{partVerdict}(A, P, \operatorname{mapRole}_{\rho, \operatorname{setStyle}_{p,v}}(o), \operatorname{mapRole}_{\rho, \operatorname{setStyle}_{p,w}}(r), \Pi) = \operatorname{partVerdict}(A, P, o, r, \Pi),\quad \text{where } v, w \in \mathrm{String}_\bot,\ o, r \in \mathrm{PartRaw}_\bot,\ \operatorname{mapRole} \text{ is applied through the option } (\bot \mapsto \bot)$$

A skipped property never fails a cell, whatever its value on either arm. -/
theorem partVerdict_setStyle (a : Anchors) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (ρ p : String) (v w : Option String)
    (hskip : ∀ rs ∈ spec.roles, rs.role = ρ → isSkipped p (skipNames a rs) (prefixes a) = true) :
    partVerdict a spec (o.map (mapRole ρ (setStyle p v))) (r.map (mapRole ρ (setStyle p w))) props =
      partVerdict a spec o r props := by
  unfold partVerdict
  rw [partItems_skip_invariant a spec o r props ρ p _ _ (setStyle_agree p v) (setStyle_agree p w)
    (fun _ => rfl) hskip]

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

/-! ## Variant roles -/

/-- A role that a rewrite variant puts in place of another one, with the reason (`anchors.json` `variantRoles`).

$$w = (v,\ \rho_{\mathrm{rep}},\ \rho_{\mathrm{new}},\ \rho_{\mathrm{of}},\ \mathit{why}) \in \mathrm{String}^{5}$$

Under variant $v$ the role $\rho_{\mathrm{rep}}$ is not judged, and the rewrite-only role $\rho_{\mathrm{new}}$ is judged by
its count alone, against the original's count of role $\rho_{\mathrm{of}}$. -/
structure VariantRole where
  variant : String
  replaces : String
  role : String
  countOf : String
  why : String
  deriving Repr, Inhabited, DecidableEq

/-- The variant role a part's declared variant selects: the first entry with that variant name.

$$\operatorname{sel}(W, v) = \begin{cases} \bot & v = \bot \\ \text{the first } w \in W \text{ (in list order) with } w.v = v & v \ne \bot \text{ and one exists} \\ \bot & \text{otherwise} \end{cases}$$

A part whose variant has no entry (`faithful`, an undeclared variant, or none read) is judged by its plain roles. -/
def variantRole (ws : List VariantRole) (v : Option String) : Option VariantRole :=
  v.bind fun v => ws.find? (·.variant == v)

/-- The count-only role spec of a variant role: no box, no skips.

$$\operatorname{countRole}(w) = (w.\rho_{\mathrm{new}},\ \bot,\ [\,],\ [\,],\ [\,],\ [\,],\ w.\mathit{why})$$

The new role's only item is its count. -/
def countRole (w : VariantRole) : RoleSpec := ⟨w.role, none, [], [], [], [], w.why⟩

/-- The part spec under a variant role: the replaced role removed, the count-only role appended.

$$\operatorname{vSpec}(w, P) = (P.\mathit{id},\ [\,\sigma \in P.\mathrm{roles} \mid \sigma.\mathrm{role} \ne w.\rho_{\mathrm{rep}}\,] \mathbin{+\!\!+} [\operatorname{countRole}(w)])$$

Which roles a part judges under the variant. -/
def variantSpec (w : VariantRole) (spec : PartSpec) : PartSpec :=
  ⟨spec.id, spec.roles.filter (·.role != w.replaces) ++ [countRole w]⟩

/-- Put a count with no items under key `k` (or remove `k` when there is no count).

$$\operatorname{setCount}(k, c, P) = \begin{cases} (k, (n, [\,])) :: [\,e \in P \mid e.1 \ne k\,] & c = n \in \mathbb N \\ [\,e \in P \mid e.1 \ne k\,] & c = \bot \end{cases}$$

Every other key keeps its entries. -/
def setCount (k : String) (c : Option Nat) (pr : PartRaw) : PartRaw :=
  (match c with | some n => [(k, (⟨n, []⟩ : RoleRaw))] | none => []) ++ pr.filter (·.1 != k)

/-- The original arm under a variant role: the new role carries the original's count of $\rho_{\mathrm{of}}$.

$$\operatorname{vOrig}(w, P) = \operatorname{setCount}(w.\rho_{\mathrm{new}},\ c,\ P),\quad c = \begin{cases} P[w.\rho_{\mathrm{of}}].n & P[w.\rho_{\mathrm{of}}] \ne \bot \\ \bot & \text{otherwise} \end{cases},\quad P[k] = \text{the first entry of } P \text{ with key } k$$

The original has no element of the new role; its reference count is that of the role it stands for. -/
def variantOrig (w : VariantRole) (pr : PartRaw) : PartRaw :=
  setCount w.role ((pr.lookup w.countOf).map (·.count)) pr

/-- The rewrite arm under a variant role: the new role keeps its count and drops its elements.

$$\operatorname{vRew}(w, P) = \operatorname{setCount}(w.\rho_{\mathrm{new}},\ c,\ P),\quad c = \begin{cases} P[w.\rho_{\mathrm{new}}].n & P[w.\rho_{\mathrm{new}}] \ne \bot \\ \bot & \text{otherwise} \end{cases}$$

Only the count of the new role is judged. -/
def variantRewrite (w : VariantRole) (pr : PartRaw) : PartRaw :=
  setCount w.role ((pr.lookup w.role).map (·.count)) pr

/-- The status of a variant role: the original's count of $\rho_{\mathrm{of}}$ against the rewrite's count of
$\rho_{\mathrm{new}}$.

$$\operatorname{vCount}(w, o, r) = \begin{cases} \operatorname{countStatus}(o[w.\rho_{\mathrm{of}}].n,\ r[w.\rho_{\mathrm{new}}].n) & o[w.\rho_{\mathrm{of}}] \ne \bot \wedge r[w.\rho_{\mathrm{new}}] \ne \bot \\ \mathrm{missing} & \text{otherwise} \end{cases}$$

where $x[k]$ is the first entry with key $k$ of the part $x$, $\bot$ if there is none or $x = \bot$. The one item the new
role adds. -/
def variantCount (w : VariantRole) (o r : Option PartRaw) : Status :=
  match o.bind (·.lookup w.countOf), r.bind (·.lookup w.role) with
  | some x, some y => countStatus x.count y.count
  | _, _ => .missing

/-- The part spec under an optional variant role.

$$\operatorname{vSpec}_\bot(\bot, P) = P, \qquad \operatorname{vSpec}_\bot(w, P) = \operatorname{vSpec}(w, P)$$

No variant role leaves the spec as is. -/
def variantSpecOpt : Option VariantRole → PartSpec → PartSpec
  | none, spec => spec
  | some w, spec => variantSpec w spec

/-- The original arm under an optional variant role.

$$\operatorname{vOrig}_\bot(\bot, P) = P, \qquad \operatorname{vOrig}_\bot(w, P) = \operatorname{vOrig}(w, P)$$

No variant role leaves the arm as is. -/
def variantOrigOpt : Option VariantRole → PartRaw → PartRaw
  | none, pr => pr
  | some w, pr => variantOrig w pr

/-- The rewrite arm under an optional variant role.

$$\operatorname{vRew}_\bot(\bot, P) = P, \qquad \operatorname{vRew}_\bot(w, P) = \operatorname{vRew}(w, P)$$

No variant role leaves the arm as is. -/
def variantRewriteOpt : Option VariantRole → PartRaw → PartRaw
  | none, pr => pr
  | some w, pr => variantRewrite w pr

/-- A variant role is well formed for a part: it has a variant name and a reason, the replaced role and the counted role
are roles of the part, and the new role is neither a role of the part nor a box reference of one.

$$\operatorname{wfV}(P, w) \iff w.v \ne \varepsilon \wedge w.\mathit{why} \ne \varepsilon \wedge (\exists \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = w.\rho_{\mathrm{rep}}) \wedge (\exists \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} = w.\rho_{\mathrm{of}}) \wedge \forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} \ne w.\rho_{\mathrm{new}} \wedge \forall b,\ \sigma.b = b \implies b.\mathrm{role} \ne w.\rho_{\mathrm{new}}$$

A variant role names what it replaces and what it counts, and adds a fresh name. -/
def variantWellFormed (spec : PartSpec) (w : VariantRole) : Bool :=
  !w.variant.isEmpty && !w.why.isEmpty && spec.roles.any (·.role == w.replaces) &&
    spec.roles.any (·.role == w.countOf) &&
    spec.roles.all fun rs => rs.role != w.role && rs.boxRel.all (·.role != w.role)

/-- The new role's name is fresh in the part: no role and no box reference uses it.

$$\operatorname{fresh}(w, P) \iff \forall \sigma \in P.\mathrm{roles},\ \sigma.\mathrm{role} \ne w.\rho_{\mathrm{new}} \wedge \forall b,\ \sigma.b = b \implies b.\mathrm{role} \ne w.\rho_{\mathrm{new}}$$

The premise of the variant theorems. -/
def Fresh (w : VariantRole) (spec : PartSpec) : Prop :=
  ∀ rs ∈ spec.roles, rs.role ≠ w.role ∧ ∀ b, rs.boxRel = some b → b.role ≠ w.role

/-- A well-formed variant role has a fresh name.

$$\forall P, w,\quad \operatorname{wfV}(P, w) \implies \operatorname{fresh}(w, P)$$

The decoder's check gives the theorems' premise. -/
theorem fresh_of_wellFormed (spec : PartSpec) (w : VariantRole) (h : variantWellFormed spec w = true) :
    Fresh w spec := by
  simp only [variantWellFormed, Bool.and_eq_true, List.all_eq_true] at h
  intro rs hrs
  have h1 := h.2 rs hrs
  simp only [bne_iff_ne, ne_eq, Option.all_eq_true] at h1
  refine ⟨h1.1, fun b hb => ?_⟩
  have := h1.2 b hb
  simpa using this

/-- Removing the entries of one key leaves every other key's first entry.

$$\forall k, j, P,\quad j \ne k \implies [\,e \in P \mid e.1 \ne k\,][j] = P[j]$$

A generic form of `lookup_filter_ne`. -/
theorem lookup_filter_ne_raw {β : Type} (k j : String) (h : j ≠ k) (pr : List (String × β)) :
    (pr.filter (·.1 != k)).lookup j = pr.lookup j := by
  induction pr with
  | nil => rfl
  | cons e es ih =>
    obtain ⟨k', v⟩ := e
    by_cases hk : k' = k
    · subst hk
      have : (j == k') = false := by simpa using h
      simp [List.lookup_cons, this, ih]
    · have hk' : (k' != k) = true := by simpa using hk
      simp only [List.filter_cons, hk', ite_true, List.lookup_cons, ih]

/-- A key looked up after `setCount`.

$$\forall k, c, P, j,\quad \operatorname{setCount}(k, c, P)[j] = \begin{cases} (n, [\,]) & j = k \wedge c = n \\ \bot & j = k \wedge c = \bot \\ P[j] & j \ne k \end{cases}$$

Only key $k$ changes. -/
theorem lookup_setCount (k : String) (c : Option Nat) (pr : PartRaw) (j : String) :
    (setCount k c pr).lookup j = if j = k then c.map (fun n => (⟨n, []⟩ : RoleRaw)) else pr.lookup j := by
  by_cases hj : j = k
  · subst hj
    have hnil : (pr.filter (·.1 != j)).lookup j = none := by
      induction pr with
      | nil => rfl
      | cons e es ih =>
        obtain ⟨k', v⟩ := e
        by_cases hk : k' = j
        · subst hk; simpa [List.filter_cons] using ih
        · have hk' : (k' != j) = true := by simpa using hk
          have hb : (j == k') = false := by simpa using Ne.symm hk
          simp only [List.filter_cons, hk', ite_true, List.lookup_cons, hb, ih]
    cases c <;> simp [setCount, hnil]
  · have hb : (j == k) = false := by simpa using hj
    cases c <;> simp [setCount, List.lookup_cons, hb, hj, lookup_filter_ne_raw k j hj]

/-- Every item of a role carries that role's name.

$$\forall A, \rho, \mathit{props}, q_o, q_r, o, r,\ \forall it \in \operatorname{roleItems}(A, \rho, \mathit{props}, q_o, q_r, o, r),\quad it.\rho = \rho.\mathrm{role}$$

The role of an item names the spec it came from. -/
theorem roleItems_role {a : Anchors} {rs : RoleSpec} {props : Option RoleProps} {refO refR : Option Rect}
    {o r : Option RoleRaw} {it : PItem} (h : it ∈ roleItems a rs props refO refR o r) : it.role = rs.role :=
  (mem_roleItems h).1

/-- A filtered role list's items are the filtered items, when each kept role yields the same items.

$$\forall l, q, F, F', p,\quad \bigl(\forall x \in l,\ (q(x) \implies F'(x) = [\,it \in F(x) \mid p(it)\,]) \wedge (\neg q(x) \implies [\,it \in F(x) \mid p(it)\,] = [\,])\bigr) \implies \textstyle\bigoplus_{x \in [y \in l \mid q(y)]} F'(x) = [\,it \in \bigoplus_{x \in l} F(x) \mid p(it)\,]$$

A helper for the variant theorem. -/
theorem flatMap_filter_eq {α β : Type} (l : List α) (q : α → Bool) (F F' : α → List β) (p : β → Bool)
    (h : ∀ x ∈ l, (q x = true → F' x = (F x).filter p) ∧ (q x = false → (F x).filter p = [])) :
    (l.filter q).flatMap F' = (l.flatMap F).filter p := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    have ih' := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    have hx := h x (List.mem_cons_self ..)
    cases hq : q x
    · simp [hq, List.flatMap_cons, List.filter_append, hx.2 hq, ih']
    · simp [hq, List.flatMap_cons, List.filter_append, hx.1 hq, ih']

/-- **Under a variant role the part's items are its plain items without the replaced role, then one count item.**

$$\forall A, w, P, o, r, \Pi,\quad \operatorname{fresh}(w, P) \implies \operatorname{partItems}(A, \operatorname{vSpec}(w, P), \operatorname{vOrig}(w, \cdot)(o), \operatorname{vRew}(w, \cdot)(r), \Pi) = [\,it \in \operatorname{partItems}(A, P, o, r, \Pi) \mid it.\rho \ne w.\rho_{\mathrm{rep}}\,] \mathbin{+\!\!+} [\,(\mathrm{count}, w.\rho_{\mathrm{new}}, -1, \texttt{count}, \operatorname{vCount}(w, o, r), \mathrm{false})\,]$$

where $o, r \in \mathrm{PartRaw}_\bot$ and the arm maps are applied through the option ($\bot \mapsto \bot$). Every other item,
its order, key and status included, is the one the plain spec gives. -/
theorem partItems_variant (a : Anchors) (w : VariantRole) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (hf : Fresh w spec) :
    partItems a (variantSpec w spec) (o.map (variantOrig w)) (r.map (variantRewrite w)) props =
      (partItems a spec o r props).filter (·.role != w.replaces) ++
        [⟨.count, w.role, -1, "count", variantCount w o r, false⟩] := by
  have hlo : ∀ k, k ≠ w.role → (o.map (variantOrig w)).bind (·.lookup k) = o.bind (·.lookup k) := by
    intro k hk; cases o <;> simp [variantOrig, lookup_setCount, hk]
  have hlr : ∀ k, k ≠ w.role → (r.map (variantRewrite w)).bind (·.lookup k) = r.bind (·.lookup k) := by
    intro k hk; cases r <;> simp [variantRewrite, lookup_setCount, hk]
  have href : ∀ (pr : Option PartRaw) (g : PartRaw → PartRaw), (∀ k, k ≠ w.role →
      (pr.map g).bind (·.lookup k) = pr.bind (·.lookup k)) →
      ∀ b : Option BoxRel, (∀ x, b = some x → x.role ≠ w.role) → refRect (pr.map g) b = refRect pr b := by
    intro pr g hg b hb
    cases b with
    | none => rfl
    | some b =>
      simp only [refRect, Option.bind_some]
      rw [hg b.role (hb b rfl)]
  simp only [partItems, variantSpec, List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil]
  congr 1
  · apply flatMap_filter_eq
    intro rs hrs
    have hfr := hf rs hrs
    refine ⟨fun hq => ?_, fun hq => ?_⟩
    · rw [href o _ hlo rs.boxRel hfr.2, href r _ hlr rs.boxRel hfr.2, hlo rs.role hfr.1, hlr rs.role hfr.1]
      symm
      rw [List.filter_eq_self]
      intro it hit
      rw [roleItems_role hit]
      exact hq
    · rw [List.filter_eq_nil_iff]
      intro it hit
      rw [roleItems_role hit]
      simp only [bne_eq_false_iff_eq] at hq
      simp [hq]
  · have ho : (o.map (variantOrig w)).bind (·.lookup w.role) =
        (o.bind (·.lookup w.countOf)).map fun x => (⟨x.count, []⟩ : RoleRaw) := by
      cases o with
      | none => rfl
      | some pr =>
        simp only [Option.map_some, Option.bind_some, variantOrig, lookup_setCount, ite_true]
        cases pr.lookup w.countOf <;> rfl
    have hr : (r.map (variantRewrite w)).bind (·.lookup w.role) =
        (r.bind (·.lookup w.role)).map fun x => (⟨x.count, []⟩ : RoleRaw) := by
      cases r with
      | none => rfl
      | some pr =>
        simp only [Option.map_some, Option.bind_some, variantRewrite, lookup_setCount, ite_true]
        cases pr.lookup w.role <;> rfl
    simp only [countRole, refRect, ho, hr, variantCount]
    cases o.bind (·.lookup w.countOf) <;> cases r.bind (·.lookup w.role) <;> rfl

/-- **Every other item of a part is unchanged by a variant role.**

$$\forall A, w, P, o, r, \Pi,\quad \operatorname{fresh}(w, P) \implies [\,it \in \mathcal I_w \mid it.\rho \ne w.\rho_{\mathrm{rep}} \wedge it.\rho \ne w.\rho_{\mathrm{new}}\,] = [\,it \in \mathcal I \mid it.\rho \ne w.\rho_{\mathrm{rep}} \wedge it.\rho \ne w.\rho_{\mathrm{new}}\,]$$

$$\text{with}\quad \mathcal I_w = \operatorname{partItems}(A, \operatorname{vSpec}(w, P), \operatorname{vOrig}(w, \cdot)(o), \operatorname{vRew}(w, \cdot)(r), \Pi),\quad \mathcal I = \operatorname{partItems}(A, P, o, r, \Pi)$$

The items of every role other than the replaced and the new one, with their statuses, are the same list. -/
theorem partItems_variant_others (a : Anchors) (w : VariantRole) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (hf : Fresh w spec) :
    (partItems a (variantSpec w spec) (o.map (variantOrig w)) (r.map (variantRewrite w)) props).filter
        (fun it => it.role != w.replaces && it.role != w.role) =
      (partItems a spec o r props).filter (fun it => it.role != w.replaces && it.role != w.role) := by
  rw [partItems_variant a w spec o r props hf, List.filter_append, List.filter_filter]
  simp only [List.filter_cons, List.filter_nil, bne_self_eq_false, Bool.and_false, Bool.false_eq_true,
    ite_false, List.append_nil]
  congr 1
  funext it
  cases it.role != w.replaces <;> simp

/-- **Under a variant role the replaced role is not judged and the new role is judged by its count against the
counted role.**

$$\forall A, w, P, o, r, \Pi,\quad \operatorname{fresh}(w, P) \wedge w.\rho_{\mathrm{rep}} \ne w.\rho_{\mathrm{new}} \implies [\,it \in \mathcal I_w \mid it.\rho = w.\rho_{\mathrm{rep}}\,] = [\,] \wedge [\,it \in \mathcal I_w \mid it.\rho = w.\rho_{\mathrm{new}}\,] = [\,(\mathrm{count}, w.\rho_{\mathrm{new}}, -1, \texttt{count}, \operatorname{vCount}(w, o, r), \mathrm{false})\,]$$

$$\text{with}\quad \mathcal I_w = \operatorname{partItems}(A, \operatorname{vSpec}(w, P), \operatorname{vOrig}(w, \cdot)(o), \operatorname{vRew}(w, \cdot)(r), \Pi)$$

For `hero.countdown` under `strip` ($\rho_{\mathrm{rep}} = $ `face`,
$\rho_{\mathrm{new}} = $ `strip`, $\rho_{\mathrm{of}} = $ `digit`) the faces are not judged and the strips are judged by
count against the original's digits. -/
theorem partItems_variant_role (a : Anchors) (w : VariantRole) (spec : PartSpec) (o r : Option PartRaw)
    (props : PartProps) (hf : Fresh w spec) (hne : w.replaces ≠ w.role) :
    (partItems a (variantSpec w spec) (o.map (variantOrig w)) (r.map (variantRewrite w)) props).filter
        (·.role == w.replaces) = [] ∧
      (partItems a (variantSpec w spec) (o.map (variantOrig w)) (r.map (variantRewrite w)) props).filter
        (·.role == w.role) = [⟨.count, w.role, -1, "count", variantCount w o r, false⟩] := by
  rw [partItems_variant a w spec o r props hf, List.filter_append, List.filter_append, List.filter_filter,
    List.filter_filter]
  have hn : (w.role == w.replaces) = false := by simpa using Ne.symm hne
  constructor
  · rw [List.append_eq_nil_iff]
    refine ⟨List.filter_eq_nil_iff.mpr fun it _ => by cases h : it.role == w.replaces <;> simp_all, ?_⟩
    simp [hn]
  · have hnone : (partItems a spec o r props).filter (fun it => it.role == w.role && it.role != w.replaces) = [] := by
      rw [List.filter_eq_nil_iff]
      intro it hit
      simp only [partItems, List.mem_flatMap] at hit
      obtain ⟨rs, hrs, hit⟩ := hit
      rw [roleItems_role hit]
      simp [(hf rs hrs).1]
    simp only [hnone, List.nil_append, List.filter_cons, beq_self_eq_true, ite_true, List.filter_nil]

/-- A variant role's count is equal exactly when both counts exist, agree and are positive.

$$\forall w, o, r,\quad \operatorname{vCount}(w, o, r) = \mathrm{equal} \iff \exists x, y,\ o[w.\rho_{\mathrm{of}}] = x \wedge r[w.\rho_{\mathrm{new}}] = y \wedge x.n = y.n \wedge y.n \ne 0$$

The new role passes only when the rewrite has as many as the original's counted role, and some. -/
theorem variantCount_equal_iff (w : VariantRole) (o r : Option PartRaw) :
    variantCount w o r = .equal ↔ ∃ x y, o.bind (·.lookup w.countOf) = some x ∧
      r.bind (·.lookup w.role) = some y ∧ x.count = y.count ∧ y.count ≠ 0 := by
  unfold variantCount
  cases o.bind (·.lookup w.countOf) <;> cases r.bind (·.lookup w.role) <;> simp [countStatus]
  · split <;> rename_i h
    · simp only [reduceCtorEq, false_iff, not_and]; omega
    · split <;> simp_all

/-- A variant role with a count absent on either arm is missing.

$$\forall w, o, r,\quad o[w.\rho_{\mathrm{of}}] = \bot \vee r[w.\rho_{\mathrm{new}}] = \bot \implies \operatorname{vCount}(w, o, r) = \mathrm{missing}$$

An absent count never passes. -/
theorem variantCount_missing (w : VariantRole) (o r : Option PartRaw)
    (h : o.bind (·.lookup w.countOf) = none ∨ r.bind (·.lookup w.role) = none) :
    variantCount w o r = .missing := by
  unfold variantCount
  rcases h with h | h <;> rw [h] <;> split <;> simp_all

/-- No variant role leaves the part's items as they are.

$$\forall A, P, o, r, \Pi,\quad \operatorname{partItems}(A, \operatorname{vSpec}_\bot(\bot, P), \operatorname{vOrig}_\bot(\bot, \cdot)(o), \operatorname{vRew}_\bot(\bot, \cdot)(r), \Pi) = \operatorname{partItems}(A, P, o, r, \Pi)$$

Every part without a declared variant role is judged as before. -/
theorem partItems_variant_none (a : Anchors) (spec : PartSpec) (o r : Option PartRaw) (props : PartProps) :
    partItems a (variantSpecOpt none spec) (o.map (variantOrigOpt none)) (r.map (variantRewriteOpt none)) props =
      partItems a spec o r props := by
  cases o <;> cases r <;> rfl

/-! ## Examples -/

private def exA : Anchors :=
  ⟨[⟨"animation", "x"⟩], [⟨"layoutDerived", ["width", "height"], "x"⟩]⟩
private def exSpec : PartSpec :=
  ⟨"p", [⟨"root", none, ["x", "w"], ["layoutDerived"], ["transform"], [], "x"⟩]⟩
private def exProps : PartProps :=
  [("root", ⟨["color", "width", "transform", "animation-name", "top"], ["font-size", "animation"]⟩)]
private def exItem (x : Rat) (color top fs : String) : Item :=
  ⟨some ⟨x, 0, 10, 10⟩, [("color", color), ("top", top), ("font-size", fs), ("width", "1px")], []⟩
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
#guard !wellFormed exA [⟨"p", [⟨"root", none, [], ["nope"], [], [], "x"⟩]⟩]
#guard !wellFormed exA [⟨"p", [⟨"root", some ⟨"other", 0⟩, [], [], [], [], "x"⟩]⟩]
#guard !wellFormed exA [⟨"p", [⟨"root", none, [], [], [], [], ""⟩]⟩]
-- only `info` differs: still a pass
#guard partVerdict exA exSpec (exArm 1 [exItem 0 "red" "0px" "1px"]) (exArm 1 [exItem 0 "red" "0px" "9px"]) exProps == .pass

private def exSpecI : PartSpec := ⟨"p", [⟨"root", none, [], [], [], ["color"], "x"⟩]⟩
private def exPropsI : PartProps := [("root", ⟨["color"], []⟩)]
private def exItemI (color : String) (inl : List String) : Item := ⟨none, [("color", color)], inl⟩
-- an inline-skipped property: compared where the original sets nothing inline
#guard partVerdict exA exSpecI (exArm 1 [exItemI "red" []]) (exArm 1 [exItemI "blue" []]) exPropsI == .fail
-- skipped where the original sets it inline: the pair has no other item, so the cell is a pass through the count alone
#guard partVerdict exA exSpecI (exArm 1 [exItemI "red" ["color"]]) (exArm 1 [exItemI "blue" []]) exPropsI == .pass
-- the rewrite's inline list is never read
#guard partVerdict exA exSpecI (exArm 1 [exItemI "red" []]) (exArm 1 [exItemI "blue" ["color"]]) exPropsI == .fail
-- one raised card and one that is not: the second is still compared
#guard partVerdict exA exSpecI (exArm 2 [exItemI "red" ["color"], exItemI "red" []])
  (exArm 2 [exItemI "blue" [], exItemI "blue" []]) exPropsI == .fail
#guard partVerdict exA exSpecI (exArm 2 [exItemI "red" ["color"], exItemI "red" []])
  (exArm 2 [exItemI "blue" [], exItemI "red" []]) exPropsI == .pass

private def exW : VariantRole := ⟨"strip", "face", "strip", "digit", "x"⟩
private def exSpecV : PartSpec :=
  ⟨"c", [⟨"digit", none, [], [], [], [], "x"⟩, ⟨"face", none, [], [], ["transform"], [], "x"⟩]⟩
private def exPropsV : PartProps := [("face", ⟨["opacity"], []⟩), ("strip", ⟨["transform"], []⟩)]
private def exItemV (op : String) : Item := ⟨none, [("opacity", op), ("transform", "none")], []⟩
private def exOrigV : Option PartRaw := some [("digit", ⟨2, []⟩), ("face", ⟨20, List.replicate 2 (exItemV "1")⟩)]
private def exRewV (strips : Nat) : Option PartRaw :=
  some [("digit", ⟨2, []⟩), ("face", ⟨0, []⟩), ("strip", ⟨strips, List.replicate strips (exItemV "0")⟩)]
private def variantVerdict (w : Option VariantRole) (o r : Option PartRaw) : Verdict :=
  partVerdict exA (variantSpecOpt w exSpecV) (o.map (variantOrigOpt w)) (r.map (variantRewriteOpt w)) exPropsV

#guard variantRole [exW] (some "strip") == some exW
#guard variantRole [exW] (some "faithful") == none && variantRole [exW] none == none && variantRole [] (some "strip") == none
#guard variantWellFormed exSpecV exW
#guard !variantWellFormed exSpecV { exW with replaces := "nope" } && !variantWellFormed exSpecV { exW with countOf := "nope" } &&
  !variantWellFormed exSpecV { exW with role := "digit" } && !variantWellFormed exSpecV { exW with why := "" }
#guard variantVerdict none exOrigV (exRewV 2) == .fail
#guard variantVerdict (some exW) exOrigV (exRewV 2) == .pass
#guard variantVerdict (some exW) exOrigV (exRewV 3) == .fail
#guard variantVerdict (some exW) exOrigV (some [("digit", ⟨2, []⟩)]) == .fail
#guard (partItems exA (variantSpec exW exSpecV) (exOrigV.map (variantOrig exW)) ((exRewV 2).map (variantRewrite exW))
  exPropsV).map (fun it => (it.role, it.key, it.status)) == [("digit", "count", .equal), ("strip", "count", .equal)]

end Fw.Gate
