import Fw.Measure.Freeze
import Fw.Measure.Splits
/-!
# Class handling: types quarantined by design, and types on one arm only (task n1-lean)

Two cases the class tables of the Chromium lane meet (research note 2026-10-17
"hittest-and-spk-q", sections 1.4 and 3):

* **Quarantined by design.** `trace.HitTest.overlayAdDetector` counts the hit tests of Chromium's
  overlay-ad detector, which fires on a wall-clock cap, so how many frames see it depends on
  wall time, not on the page. Its *role* is `byDesign` whatever level the runs give it: it is never
  a gate type and never a finding (`roleOf_byDesign_iff`, `overlay_not_gate`).
* **Present on one arm only.** The original (A) and the rewrite (R) are classified separately; a
  type can occur on one arm and not on the other (R has no overlay-ad slot, say). Within one arm a
  type missing from a workflow run counts as quarantined there (`Freeze.levelIn`, the run did not
  show it reliably); across the arms an absent type is *not* quarantine: an arm that never records
  the type reads 0 in every frame, and `classify` gives that series `det` (`classifyU_absent`). So
  the cross-arm level is the worse of the two arm levels, with an absent arm counting as `det`
  (`crossLevel_eq`, `crossLevel_classify`).

The roles go to the `role` field of each `measure.freeze` row; `measure.arms` gives the cross-arm
level and role of every type. The `measure.classify` reply is unchanged.
-/
namespace Fw.Measure.Arms
open Fw.Measure Fw.Measure.Freeze

/-! ## Types quarantined by design -/

/-- The overlay-ad detector's hit-test type.

$$\mathrm{overlay} = \texttt{"trace.HitTest.overlayAdDetector"}$$
-/
def overlay : String := "trace.HitTest.overlayAdDetector"

/-- **The types quarantined by design**, each with its reason.

$$\mathrm{byDesign} = [(\mathrm{overlay},\ \text{reason})]$$
-/
def byDesign : List (String × String) :=
  [(overlay, "browser work on a wall-clock cap (OverlayInterstitialAdDetector::MaybeFireDetection), not page work")]

/-- Whether a type is quarantined by design.

$$\operatorname{isBD}(\tau) \iff \exists \rho:\ (\tau, \rho) \in \mathrm{byDesign}$$
-/
def isByDesign (ty : String) : Bool := byDesign.any (·.1 == ty)

/-- The reason a type is quarantined by design (`none` for any other type).

$$\operatorname{reason}(\tau) = \begin{cases} \rho & (\tau, \rho) \text{ is the first pair of byDesign with type } \tau \\ \bot & \text{no pair of byDesign has type } \tau \end{cases}$$
-/
def reasonOf (ty : String) : Option String := (byDesign.find? (·.1 == ty)).map (·.2)

/-- What a type does in the comparison of the arms.

$$\mathrm{Role} = \{\mathrm{gate}, \mathrm{finding}, \mathrm{byDesign}\}$$
-/
inductive Role where
  | gate
  | finding
  | byDesign
deriving Repr, DecidableEq

/-- **The role of a type** of level `l`: `byDesign` for a type quarantined by design (whatever
`l`), else `finding` for a quarantined type, else `gate`.

$$\operatorname{role}(\tau, l) = \begin{cases} \mathrm{byDesign} & \operatorname{isBD}(\tau) \\ \mathrm{finding} & \text{else if } l = \mathrm{quar} \\ \mathrm{gate} & \text{otherwise} \end{cases}$$
-/
def roleOf (ty : String) (l : Level) : Role :=
  if isByDesign ty then .byDesign else if l == .quar then .finding else .gate

/-- The gate types of a frozen table: the types of the rows whose role is `gate`, in row order.

$$\operatorname{gates}(F) = [\, r.\tau \mid r \in F,\ \operatorname{role}(r.\tau, r.\mathrm{cls}) = \mathrm{gate} \,]$$
-/
def gateTypes (rows : List FRow) : List String :=
  (rows.filter fun r => roleOf r.type r.cls == .gate).map (·.type)

/-- The number of rows of each role: (gate, finding, byDesign).

$$\operatorname{roles}(F) = \big(|[\,r \in F \mid \operatorname{role}(r) = \mathrm{gate}\,]|,\ |[\,r \in F \mid \operatorname{role}(r) = \mathrm{finding}\,]|,\ |[\,r \in F \mid \operatorname{role}(r) = \mathrm{byDesign}\,]|\big),\quad \operatorname{role}(r) = \operatorname{role}(r.\tau, r.\mathrm{cls})$$
-/
def roleTally (rows : List FRow) : Nat × Nat × Nat :=
  let rs := rows.map fun r => roleOf r.type r.cls
  ((rs.filter (· == .gate)).length, (rs.filter (· == .finding)).length, (rs.filter (· == .byDesign)).length)

#guard roleOf overlay .det == .byDesign && roleOf overlay .quar == .byDesign
#guard roleOf "trace.HitTest" .quar == .finding && roleOf "trace.HitTest" .stable == .gate
#guard roleOf "trace.Paint" .det == .gate
#guard gateTypes [⟨overlay, .det, 0, 0, [], none⟩, ⟨"a", .quar, 3, 3, [], none⟩, ⟨"b", .stable, 1, 1, [], none⟩] == ["b"]
#guard roleTally [⟨overlay, .det, 0, 0, [], none⟩, ⟨"a", .quar, 3, 3, [], none⟩, ⟨"b", .stable, 1, 1, [], none⟩] == (1, 1, 1)
#guard reasonOf overlay |>.isSome
#guard reasonOf "trace.HitTest" == none

/-! ## Cross-arm level -/

/-- The level of a type in a class table, `none` when the table has no entry for it.

$$\operatorname{at}(T, \tau) = \begin{cases} e.\mathrm{cls} & \operatorname{entry}(T, \tau) = e \\ \bot & \operatorname{entry}(T, \tau) = \bot \end{cases}$$
-/
def levelAt? (tb : Table) (ty : String) : Option Level := (entry? tb ty).map (·.cls)

/-- **The cross-arm level** of a type from its level on arm A and on arm R (`none` = the arm has
no entry): the worse of the two when both have one, the one present when only one has it.

$$\operatorname{cross}(a, b) = \begin{cases} a \curlyvee b & a \ne \bot,\ b \ne \bot \\ a & a \ne \bot,\ b = \bot \\ b & a = \bot,\ b \ne \bot \\ \bot & a = b = \bot \end{cases}$$
-/
def crossLevel : Option Level → Option Level → Option Level
  | some x, some y => some (x.worse y)
  | some x, none => some x
  | none, some y => some y
  | none, none => none

#guard crossLevel (some .det) (some .stable) == some .stable
#guard crossLevel (some .quar) none == some .quar && crossLevel none (some .det) == some .det
#guard crossLevel none none == none

/-! ## Proofs: roles -/

/-- A type is `byDesign` exactly when it is listed, whatever its level.

$$\forall \tau, l:\ \operatorname{role}(\tau, l) = \mathrm{byDesign} \iff \operatorname{isBD}(\tau)$$
-/
theorem roleOf_byDesign_iff (τ : String) (l : Level) : roleOf τ l = .byDesign ↔ isByDesign τ = true := by
  unfold roleOf
  by_cases h : isByDesign τ = true
  · simp [h]
  · by_cases hq : l = .quar <;> simp [h, hq]

/-- A type gates exactly when it is not quarantined by design and its level is not `quar`.

$$\forall \tau, l:\ \operatorname{role}(\tau, l) = \mathrm{gate} \iff \lnot \operatorname{isBD}(\tau) \land l \ne \mathrm{quar}$$
-/
theorem roleOf_gate_iff (τ : String) (l : Level) :
    roleOf τ l = .gate ↔ isByDesign τ = false ∧ l ≠ .quar := by
  unfold roleOf
  by_cases h : isByDesign τ = true
  · simp [h]
  · by_cases hq : l = .quar <;> simp [h, hq]

/-- A type is a finding exactly when it is not quarantined by design and its level is `quar`.

$$\forall \tau, l:\ \operatorname{role}(\tau, l) = \mathrm{finding} \iff \lnot \operatorname{isBD}(\tau) \land l = \mathrm{quar}$$
-/
theorem roleOf_finding_iff (τ : String) (l : Level) :
    roleOf τ l = .finding ↔ isByDesign τ = false ∧ l = .quar := by
  unfold roleOf
  by_cases h : isByDesign τ = true
  · simp [h]
  · by_cases hq : l = .quar <;> simp [h, hq]

/-- The gate types are the types of the rows that are neither quarantined by design nor
quarantined.

$$\forall F, \tau:\ \tau \in \operatorname{gates}(F) \iff \exists r \in F:\ r.\tau = \tau \land \lnot \operatorname{isBD}(\tau) \land r.\mathrm{cls} \ne \mathrm{quar}$$
-/
theorem mem_gateTypes (rows : List FRow) (τ : String) :
    τ ∈ gateTypes rows ↔ ∃ r ∈ rows, r.type = τ ∧ isByDesign τ = false ∧ r.cls ≠ .quar := by
  simp only [gateTypes, List.mem_map, List.mem_filter, beq_iff_eq, roleOf_gate_iff]
  constructor
  · rintro ⟨r, ⟨hr, hb, hq⟩, rfl⟩
    exact ⟨r, hr, rfl, hb, hq⟩
  · rintro ⟨r, hr, rfl, hb, hq⟩
    exact ⟨r, ⟨hr, hb, hq⟩, rfl⟩

/-- **The overlay-ad type never gates**, whatever the frozen table.

$$\forall F:\ \mathrm{overlay} \notin \operatorname{gates}(F)$$
-/
theorem overlay_not_gate (F : List FRow) : overlay ∉ gateTypes F := by
  rw [mem_gateTypes]
  rintro ⟨_, _, _, hb, _⟩
  exact absurd hb (by decide)

/-- Every type quarantined by design is a split type of `Fw.Measure.Splits` (it exists only
because of the containment split).

$$\forall \tau\, \rho:\ (\tau, \rho) \in \mathrm{byDesign} \Rightarrow \exists s \in \mathrm{splits}:\ s.\mathrm{key} = \tau$$
-/
theorem byDesign_split : ∀ τ ρ, (τ, ρ) ∈ byDesign → ∃ s ∈ Splits.splits, s.key = τ := by
  intro τ ρ hp
  simp only [byDesign, List.mem_singleton, Prod.mk.injEq] at hp
  obtain ⟨rfl, -⟩ := hp
  exact ⟨_, List.mem_cons_self .., rfl⟩

/-- A listed type has a reason.

$$\forall \tau:\ \operatorname{isBD}(\tau) \iff \operatorname{reason}(\tau) \ne \bot$$
-/
theorem isByDesign_iff_reason (τ : String) : isByDesign τ = true ↔ (reasonOf τ).isSome := by
  simp [isByDesign, reasonOf, List.find?_isSome]

/-- The roles add up to the number of rows.

$$\forall F:\ \operatorname{roles}(F) = (g, f, b) \;\Rightarrow\; g + f + b = |F|$$
-/
theorem roleTally_sum (F : List FRow) : (roleTally F).1 + (roleTally F).2.1 + (roleTally F).2.2 = F.length := by
  simp only [roleTally]
  induction F with
  | nil => rfl
  | cons r rs ih =>
    simp only [List.map_cons, List.filter_cons, List.length_cons]
    cases roleOf r.type r.cls <;> simp <;> omega

/-! ## Proofs: cross-arm level -/

/-- `det` is the identity of `worse` on both sides.

$$\forall l:\ \mathrm{det} \curlyvee l = l \ \land\ l \curlyvee \mathrm{det} = l$$
-/
theorem worse_det (l : Level) : Level.worse .det l = l ∧ l.worse .det = l := by
  cases l <;> decide

/-- **Cross-arm level, closed form.** When some arm has an entry, the cross-arm level is the worse
of the two arm levels, an arm without an entry counting as `det`.

$$\forall a, b:\ (a \ne \bot \lor b \ne \bot) \;\Rightarrow\; \operatorname{cross}(a, b) = (a \text{ or } \mathrm{det}) \curlyvee (b \text{ or } \mathrm{det})$$
-/
theorem crossLevel_eq (a b : Option Level) (h : a ≠ none ∨ b ≠ none) :
    crossLevel a b = some ((a.getD .det).worse (b.getD .det)) := by
  cases a <;> cases b <;> simp_all [crossLevel, worse_det]

/-- The cross-arm level does not depend on which arm is A.

$$\forall a, b:\ \operatorname{cross}(a, b) = \operatorname{cross}(b, a)$$
-/
theorem crossLevel_comm (a b : Option Level) : crossLevel a b = crossLevel b a := by
  cases a with
  | none => cases b <;> rfl
  | some x =>
    cases b with
    | none => rfl
    | some y => cases x <;> cases y <;> decide

/-- **One arm only: the present arm decides.** A type with an entry on one arm only gets that
arm's level, so an absent arm never makes it quarantined.

$$\forall l:\ \operatorname{cross}(l, \bot) = l \ \land\ \operatorname{cross}(\bot, l) = l$$
-/
theorem crossLevel_one_arm (l : Level) : crossLevel (some l) none = some l ∧ crossLevel none (some l) = some l :=
  ⟨rfl, rfl⟩

/-- Every frame of a list of count lists without key `τ` reads 0 for `τ`.

$$\forall \mathcal{C}, \tau:\ \tau \notin \operatorname{keys}(\mathcal{C}) \;\Rightarrow\; \forall C \in \mathcal{C}:\ \operatorname{countIn}(C, \tau) = 0$$
-/
theorem countIn_absent (τ : String) : ∀ css : List Counts, τ ∉ keysOf css → ∀ cs ∈ css, countIn cs τ = 0
  | [], _, _, h => by simp at h
  | c :: css, hk, cs, h => by
    have ⟨h0, hrest⟩ := countIn_eq_zero_of_not_mem_foldr τ c (keysOf css) hk
    rcases List.mem_cons.mp h with rfl | h
    · exact h0
    · exact countIn_absent τ css hrest cs h

/-- Two series that are 0 in every frame differ in no frame.

$$\forall a, b:\ (\forall x \in a:\ x = 0) \land (\forall y \in b:\ y = 0) \;\Rightarrow\; \operatorname{diff}(a, b) = 0$$
-/
theorem diffFrames_zero : ∀ (a b : Series), (∀ x ∈ a, x = 0) → (∀ y ∈ b, y = 0) → diffFrames a b = 0
  | [], [], _, _ => by simp [diffFrames]
  | x :: xs, [], ha, hb => by
    simp [diffFrames, ha x (by simp), diffFrames_zero xs [] (fun z hz => ha z (by simp [hz])) hb]
  | [], y :: ys, ha, hb => by
    simp [diffFrames, hb y (by simp), diffFrames_zero [] ys ha (fun z hz => hb z (by simp [hz]))]
  | x :: xs, y :: ys, ha, hb => by
    simp [diffFrames, ha x (by simp), hb y (by simp),
      diffFrames_zero xs ys (fun z hz => ha z (by simp [hz])) (fun z hz => hb z (by simp [hz]))]

/-- **An absent type is deterministic.** If no frame of any run of an arm carries type `τ`, the
unit-aware classification of its series is `det`.

$$\forall p, q, u, \mathcal{R}, \tau:\ \tau \notin \operatorname{keys}(\operatorname{flatten}(\mathcal{R})) \;\Rightarrow\; \operatorname{classify}_{p,q}(u, [\operatorname{series}_\tau(r)]_{r \in \mathcal{R}}) = \mathrm{det}$$
-/
theorem classifyU_absent (p : Policy) (q : PxTol) (u : TypeUnit) (runs : List (List Counts)) {τ : String}
    (hk : τ ∉ keysOf runs.flatten) : classifyU p q u (runs.map (seriesOf τ)) = .deterministic := by
  have hz : ∀ s ∈ runs.map (seriesOf τ), ∀ x ∈ s, x = 0 := by
    intro s hs x hx
    obtain ⟨run, hrun, rfl⟩ := List.mem_map.mp hs
    obtain ⟨cs, hcs, rfl⟩ := List.mem_map.mp hx
    exact countIn_absent τ runs.flatten hk cs (List.mem_flatten.mpr ⟨run, hrun, hcs⟩)
  unfold classifyU
  rw [classify_det_iff]
  intro a ha b hb
  exact diffFrames_zero a b (hz a ha) (hz b hb)

/-- The level of a type in the class table of one arm: the level of its `classifyU` class when the
arm's frames carry it, `none` when they do not.

$$\forall p, q, \mathcal{R}, \tau:\ \operatorname{at}(\operatorname{table}_{p,q}(\mathcal{R}), \tau) = \begin{cases} \operatorname{lvl}\big(\operatorname{classify}_{p,q}(\operatorname{unit}(\tau), R_\tau)\big) & \tau \in \operatorname{keys}(\operatorname{flatten}(\mathcal{R})) \\ \bot & \text{otherwise} \end{cases},\quad R_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{R}}$$
-/
theorem levelAt_tableOf (p : Policy) (q : PxTol) (runs : List (List Counts)) (τ : String) :
    levelAt? (tableOf p q runs) τ =
      if τ ∈ keysOf runs.flatten then some (levelOf (classifyU p q (unitOf τ) (runs.map (seriesOf τ))))
      else none := by
  have hmem : (∃ e, (τ, e) ∈ tableOf p q runs) ↔ τ ∈ keysOf runs.flatten := by
    rw [← classifyAllU_types p q]
    simp only [tableOf, List.mem_map, Prod.mk.injEq]
    constructor
    · rintro ⟨_, r, hr, hty, _⟩
      exact ⟨r, hr, hty⟩
    · rintro ⟨r, hr, hty⟩
      exact ⟨_, r, hr, hty, rfl⟩
  by_cases hk : τ ∈ keysOf runs.flatten
  · simp only [hk, ↓reduceIte]
    have hs : (entry? (tableOf p q runs) τ).isSome := (entry_isSome_iff _ _).2 (hmem.2 hk)
    have hw := worstOf_single_classify p q runs hk
    rw [worstOf_single] at hw
    obtain ⟨e, he⟩ := Option.isSome_iff_exists.mp hs
    simp only [levelIn, he] at hw
    simp [levelAt?, he, hw]
  · simp only [hk, ↓reduceIte]
    have hn : (entry? (tableOf p q runs) τ).isSome = false := by
      rw [Bool.eq_false_iff]
      intro hs
      exact hk (hmem.1 ((entry_isSome_iff _ _).1 hs))
    unfold levelAt?
    cases he : entry? (tableOf p q runs) τ with
    | none => rfl
    | some _ => simp [he] at hn

/-- **Cross-arm level from the counts.** For a type that some arm carries, the cross-arm level of
the two arm tables is the worse of the two `classifyU` levels, each over its own arm's runs; the
arm without the type contributes `det` (its series reads 0 in every frame).

$$\forall p, q, \mathcal{A}, \mathcal{B}, \tau:\ \tau \in \operatorname{keys}(\operatorname{flatten}(\mathcal{A})) \cup \operatorname{keys}(\operatorname{flatten}(\mathcal{B})) \;\Rightarrow\; \operatorname{cross}\big(\operatorname{at}(\operatorname{table}_{p,q}(\mathcal{A}), \tau),\ \operatorname{at}(\operatorname{table}_{p,q}(\mathcal{B}), \tau)\big) = \mathrm{some}\Big(\operatorname{lvl}\big(\operatorname{classify}_{p,q}(\operatorname{unit}(\tau), A_\tau)\big) \curlyvee \operatorname{lvl}\big(\operatorname{classify}_{p,q}(\operatorname{unit}(\tau), B_\tau)\big)\Big),\quad A_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{A}},\ B_\tau = [\operatorname{series}_\tau(r)]_{r \in \mathcal{B}}$$
-/
theorem crossLevel_classify (p : Policy) (q : PxTol) (as bs : List (List Counts)) (τ : String)
    (h : τ ∈ keysOf as.flatten ∨ τ ∈ keysOf bs.flatten) :
    crossLevel (levelAt? (tableOf p q as) τ) (levelAt? (tableOf p q bs) τ) =
      some ((levelOf (classifyU p q (unitOf τ) (as.map (seriesOf τ)))).worse
        (levelOf (classifyU p q (unitOf τ) (bs.map (seriesOf τ))))) := by
  rw [levelAt_tableOf, levelAt_tableOf]
  by_cases ha : τ ∈ keysOf as.flatten <;> by_cases hb : τ ∈ keysOf bs.flatten
  · simp [ha, hb, crossLevel]
  · simp [ha, hb, crossLevel, classifyU_absent p q _ bs hb, levelOf, worse_det]
  · simp [ha, hb, crossLevel, classifyU_absent p q _ as ha, levelOf, worse_det]
  · simp [ha, hb] at h

end Fw.Measure.Arms
