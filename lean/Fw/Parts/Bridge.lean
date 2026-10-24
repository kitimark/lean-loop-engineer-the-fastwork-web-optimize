import Fw.Engine.Compose
import Fw.Parts.Contract

/-!
# Bridge from the contract rows to the Lego swap, and page passes never increase
`Indep` of `Fw.Engine.Compose` becomes `Flow` (no non-`quiet` path); the 12 isolated `codeParts` rows swap alone; the
literal `Independent → Indep` fails on the listed pairs; a strict part pass saving never raises page passes (S3).
-/

namespace Fw.Parts.Bridge

open Fw.Engine Fw.Parts.Contract

/-! ## One-way independence -/

/-- `P`'s variant cannot change `Q` directly: I1, I2 and I4 of the pair hold, and no effective output of `P` affects an
input of `Q`.

It is `Independent` without the signal flow from `Q` back to `P`. -/
def quiet (P Q : PartSpec) : Bool :=
  i1 P Q && i2 P Q && !((effOut P).any fun o => Q.inputs.any (affects o)) && i4 P Q

/-- `Independent` is `quiet` plus no signal flow from `Q` to `P`.

The one-way relation drops exactly the reverse half of I3. -/
theorem independent_eq_quiet (P Q : PartSpec) :
    independent P Q = (quiet P Q && !((effOut Q).any fun o => P.inputs.any (affects o))) := by
  unfold independent quiet i3
  cases i1 P Q <;> cases i2 P Q <;> cases i4 P Q <;> cases ((effOut P).any fun o => Q.inputs.any (affects o)) <;>
    cases ((effOut Q).any fun o => P.inputs.any (affects o)) <;> rfl

/-- Independent parts are quiet towards each other.

The first half of `independent_eq_quiet`. -/
theorem quiet_of_independent {P Q : PartSpec} (h : Independent P Q) : quiet P Q = true := by
  rw [Independent, independent_eq_quiet, Bool.and_eq_true] at h
  exact h.1

/-! ## Flow over a part list -/

/-- A direct influence edge in part list `ps`: two distinct positions in range whose parts are not quiet.

`ps[i] = P` means position `i < |ps|` holds part `P`; an index out of range has no edges. -/
def Edge (ps : List PartSpec) (i j : Nat) : Prop :=
  i ≠ j ∧ ∃ P Q, ps[i]? = some P ∧ ps[j]? = some Q ∧ quiet P Q = false

/-- Reachability in `ps`: the reflexive-transitive closure of `Edge`.

Every position reaches itself. -/
inductive Reach (ps : List PartSpec) : Nat → Nat → Prop
  | refl (i : Nat) : Reach ps i i
  | step {i j k : Nat} : Edge ps i j → Reach ps j k → Reach ps i k

/-- A path extended by one edge at its end is a path.

Reach is closed under appending an edge. -/
theorem Reach.tail {ps : List PartSpec} {i j k : Nat} (h : Reach ps i j) (e : Edge ps j k) : Reach ps i k := by
  induction h with
  | refl i => exact .step e (.refl k)
  | step e' _ ih => exact .step e' (ih e)

/-- The `Indep` of `Fw.Engine.Compose` for part list `ps`: position `i` does not reach position `j`.

No position is `Flow` of itself. -/
def Flow (ps : List PartSpec) (i j : Nat) : Prop := ¬ Reach ps i j

/-- **The semantic premise.** An observable per position (frame, arm) reads only the variants of positions that reach
it: `ReadsOnly` with `Flow` as `Indep`.

What the contract rows claim of the site; complete rows, I5 and the reads no wire carries are its open parts.
Positions are indices into `ps`; for `codeParts` they follow alphabetical id order, not stack order. -/
def FlowSound {V α : Type} (ps : List PartSpec) (obs : Nat → (Nat → V) → α) : Prop := ReadsOnly (Flow ps) obs

/-- `FlowSound` unfolded: equal variants on every position that reaches `j` give `j` the same observable.

The double negation of `ReadsOnly` over `Flow` cancels. -/
theorem flowSound_iff {V α : Type} (ps : List PartSpec) (obs : Nat → (Nat → V) → α) :
    FlowSound ps obs ↔ ∀ j (sel sel' : Nat → V), (∀ i, Reach ps i j → sel i = sel' i) → obs j sel = obs j sel' := by
  unfold FlowSound ReadsOnly Flow
  exact ⟨fun h j sel sel' ha => h j sel sel' fun i hi => ha i (Classical.not_not.mp hi),
    fun h j sel sel' ha => h j sel sel' fun i hi => ha i (Classical.not_not.mpr hi)⟩

/-! ## The bridge -/

/-- Position `p` is quiet towards every other position of `ps`.

Holds for every `p` out of range. -/
def Isolated (ps : List PartSpec) (p : Nat) : Prop :=
  ∀ q, q ≠ p → ∀ P Q, ps[p]? = some P → ps[q]? = some Q → quiet P Q = true

/-- Decision procedure for `Isolated`.

Checks the positions in range only. -/
def isolated (ps : List PartSpec) (p : Nat) : Bool :=
  (List.range ps.length).all fun q => q == p || match ps[p]?, ps[q]? with
    | some P, some Q => quiet P Q
    | _, _ => true

/-- `isolated` decides `Isolated`.

A position out of range has no part, so the check over `range |ps|` is complete. -/
theorem isolated_iff (ps : List PartSpec) (p : Nat) : isolated ps p = true ↔ Isolated ps p := by
  unfold isolated Isolated
  rw [List.all_eq_true]
  constructor
  · intro h q hq P Q hP hQ
    have hlt : q < ps.length := (List.getElem?_eq_some_iff.mp hQ).1
    have := h q (List.mem_range.mpr hlt)
    simp only [hP, hQ, Bool.or_eq_true, beq_iff_eq] at this
    exact this.resolve_left hq
  · intro h q _
    by_cases hq : q = p
    · simp [hq]
    · cases hP : ps[p]? with
      | none => simp
      | some P =>
        cases hQ : ps[q]? with
        | none => simp
        | some Q => simp [h q hq P Q hP hQ]

/-- **The bridge.** A position quiet towards every other position reaches none of them, so it is `Flow`-independent
of every other position.

The first edge of any path out of `p` would contradict a `quiet` pair. -/
theorem flow_of_isolated {ps : List PartSpec} {p : Nat} (h : Isolated ps p) : ∀ q, q ≠ p → Flow ps p q := by
  intro q hq hr
  cases hr with
  | refl => exact hq rfl
  | step e _ =>
    obtain ⟨hne, P, Q, hP, hQ, hfalse⟩ := e
    rw [h _ (Ne.symm hne) P Q hP hQ] at hfalse
    exact Bool.noConfusion hfalse

/-- **The bridge from `Independent`.** A position `Independent` of every other position of `ps` is `Flow`-independent of
every other position.

`Independent` is the stronger, two-way premise. -/
theorem flow_of_independent {ps : List PartSpec} {p : Nat}
    (h : ∀ q, q ≠ p → ∀ P Q, ps[p]? = some P → ps[q]? = some Q → Independent P Q) : ∀ q, q ≠ p → Flow ps p q :=
  flow_of_isolated fun q hq P Q hP hQ => quiet_of_independent (h q hq P Q hP hQ)

/-- **Lego swap on the contract rows.** If frames and arms are `FlowSound` over `ps` and position `p` is isolated, then
swapping `p`'s variant leaves every other position's frame, frame work under every engine, and arm unchanged.

`lego_swap_sound` with `Indep` discharged by `flow_of_isolated`. -/
theorem lego_swap_sound_flow {V P M : Type} (ps : List PartSpec) (frame : Nat → (Nat → V) → FrameIn P)
    (arm : Nat → (Nat → V) → PartArm) (E : Engine P M) (p : Nat) (x : V) (sel : Nat → V)
    (hf : FlowSound ps frame) (ha : FlowSound ps arm) (hp : Isolated ps p) :
    ∀ q, q ≠ p → frame q (swapSel sel p x) = frame q sel ∧
      frameWork E (frame q (swapSel sel p x)) = frameWork E (frame q sel) ∧
      arm q (swapSel sel p x) = arm q sel :=
  lego_swap_sound (Flow ps) frame arm E p x sel hf ha (flow_of_isolated hp)

/-- **Swap accounting on units, contract rows.** If frames are `FlowSound` over `ps`, `p` is isolated and `p < n`, the
page's units after the swap plus `p`'s units before equal the page's units before plus `p`'s units after, at every
stage.

`lego_swap_units` with `Indep` discharged by `flow_of_isolated`. -/
theorem lego_swap_units_flow {V P M : Type} (ps : List PartSpec) (frame : Nat → (Nat → V) → FrameIn P)
    (E : Engine P M) (n p : Nat) (x : V) (sel : Nat → V) (s : Stage)
    (hf : FlowSound ps frame) (hi : Isolated ps p) (hp : p < n) :
    (frameWork E (pageOf n fun j => frame j (swapSel sel p x))).units s + (frameWork E (frame p sel)).units s =
      (frameWork E (pageOf n fun j => frame j sel)).units s + (frameWork E (frame p (swapSel sel p x))).units s :=
  lego_swap_units (Flow ps) frame E n p x sel s hf (flow_of_isolated hi) hp

/-- **Swap keeps the visible page, contract rows.** If arms are `FlowSound` over `ps`, `p` is isolated, and `p`'s arm
keeps its band height and its visible scene at every offset, the visible scene of the arms of positions `0, ..., n-1`, stacked in index order, is unchanged from every start offset.

`lego_swap_visible` with `Indep` discharged by `flow_of_isolated`. Positions are indices into `ps`; for `codeParts`
they follow alphabetical id order, not stack order, so this scene is the page only under a map from index to band. -/
theorem lego_swap_visible_flow {V : Type} (ps : List PartSpec) (arm : Nat → (Nat → V) → PartArm) (vp : Rect)
    (n p : Nat) (x : V) (sel : Nat → V) (y : Rat) (ha : FlowSound ps arm) (hi : Isolated ps p)
    (hh : (arm p (swapSel sel p x)).height = (arm p sel).height)
    (hs : ∀ y', visible vp ((arm p (swapSel sel p x)).scene y') = visible vp ((arm p sel).scene y')) :
    visible vp (stackScene y ((List.range n).map fun j => arm j (swapSel sel p x))) =
      visible vp (stackScene y ((List.range n).map fun j => arm j sel)) :=
  lego_swap_visible (Flow ps) arm vp n p x sel y ha (flow_of_isolated hi) hh hs

/-! ## Page passes never increase under a strict part saving (S3) -/

/-- Frame `g` is pass-dominated by `f` on stage `s`: either `g` touches `s` only when `f` does and forces at most as
many `s` passes, or `g` forces at least one `s` pass fewer.

The invariant that survives appending the rest of the page. -/
def PassDom {P M : Type} (E : Engine P M) (s : Stage) (g f : FrameIn P) : Prop :=
  ((s ∈ touched E g → s ∈ touched E f) ∧ forcedPasses g s ≤ forcedPasses f s) ∨
    forcedPasses g s + 1 ≤ forcedPasses f s

/-- A frame pass-dominates itself.

The first case with equality. -/
theorem passDom_refl {P M : Type} (E : Engine P M) (s : Stage) (f : FrameIn P) : PassDom E s f f :=
  .inl ⟨id, Nat.le_refl _⟩

/-- A strict pass saving on `s` is a pass dominance.

A touched-only saving lands in the first case, a forced one in either. -/
theorem passDom_of_lt {P M : Type} (E : Engine P M) (s : Stage) (g f : FrameIn P)
    (h : (frameWork E g).passes s < (frameWork E f).passes s) : PassDom E s g f := by
  unfold PassDom
  simp only [frameWork] at h
  by_cases a : s ∈ touched E g <;> by_cases b : s ∈ touched E f <;> simp only [a, b, ↓reduceIte] at h
  · exact .inl ⟨fun _ => b, by omega⟩
  · exact .inr (by omega)
  · exact .inl ⟨fun h' => absurd h' a, by omega⟩
  · exact .inl ⟨fun h' => absurd h' a, by omega⟩

/-- Pass dominance survives a frame appended on the right.

Touched stages join and forced passes add. -/
theorem passDom_append_right {P M : Type} (E : Engine P M) (s : Stage) {g f : FrameIn P} (c : FrameIn P)
    (h : PassDom E s g f) : PassDom E s (g ++ c) (f ++ c) := by
  unfold PassDom at h ⊢
  rw [forcedPasses_append, forcedPasses_append, touched_append, touched_append]
  rcases h with ⟨ht, hf⟩ | h
  · exact .inl ⟨fun h' => h'.imp ht id, by omega⟩
  · exact .inr (by omega)

/-- Pass dominance survives a frame appended on the left.

Touched stages join and forced passes add. -/
theorem passDom_append_left {P M : Type} (E : Engine P M) (s : Stage) {g f : FrameIn P} (c : FrameIn P)
    (h : PassDom E s g f) : PassDom E s (c ++ g) (c ++ f) := by
  unfold PassDom at h ⊢
  rw [forcedPasses_append, forcedPasses_append, touched_append, touched_append]
  rcases h with ⟨ht, hf⟩ | h
  · exact .inl ⟨fun h' => h'.imp id ht, by omega⟩
  · exact .inr (by omega)

/-- Pass dominance bounds the passes.

At most one touched pass plus the forced ones. -/
theorem passes_le_of_passDom {P M : Type} (E : Engine P M) (s : Stage) {g f : FrameIn P} (h : PassDom E s g f) :
    (frameWork E g).passes s ≤ (frameWork E f).passes s := by
  simp only [frameWork]
  rcases h with ⟨ht, hf⟩ | h
  · by_cases a : s ∈ touched E g
    · simp only [a, ht a, ↓reduceIte]; omega
    · simp only [a, ↓reduceIte]; split <;> omega
  · split <;> split <;> omega

/-- **Never an increase (S3).** If part `g₁` runs strictly fewer passes of stage `s` than `f₁`, the page with `g₁` and
any other part `f₂` runs at most as many `s` passes as the page with `f₁`.

A pass saving can vanish on the page (`passes_not_compositional`) but never turns into an increase. -/
theorem passes_append_le {P M : Type} (E : Engine P M) (f₁ g₁ f₂ : FrameIn P) (s : Stage)
    (h : (frameWork E g₁).passes s < (frameWork E f₁).passes s) :
    (frameWork E (g₁ ++ f₂)).passes s ≤ (frameWork E (f₁ ++ f₂)).passes s :=
  passes_le_of_passDom E s (passDom_append_right E s f₂ (passDom_of_lt E s g₁ f₁ h))

/-- **Never an increase on a page of `n` parts.** If part functions `G` and `F` agree below `n` except at `p < n`, and
`G p` runs strictly fewer `s` passes than `F p`, the page of `G` runs at most as many `s` passes as the page of `F`.

The saving part may sit anywhere in the page. -/
theorem passes_pageOf_le {P M : Type} (E : Engine P M) (s : Stage) (n p : Nat) (F G : Nat → FrameIn P)
    (hp : p < n) (hfg : ∀ j, j < n → j ≠ p → G j = F j)
    (h : (frameWork E (G p)).passes s < (frameWork E (F p)).passes s) :
    (frameWork E (pageOf n G)).passes s ≤ (frameWork E (pageOf n F)).passes s := by
  suffices hd : PassDom E s (pageOf n G) (pageOf n F) from passes_le_of_passDom E s hd
  induction n with
  | zero => omega
  | succ n ih =>
    show PassDom E s (pageOf n G ++ G n) (pageOf n F ++ F n)
    rcases Nat.lt_succ_iff_lt_or_eq.mp hp with hlt | heq
    · rw [hfg n (by omega) (by omega)]
      exact passDom_append_right E s (F n) (ih hlt fun j hj hne => hfg j (by omega) hne)
    · subst heq
      rw [pageOf_congr p (F := G) (G := F) fun j hj => hfg j (by omega) (by omega)]
      exact passDom_append_left E s _ (passDom_of_lt E s _ _ h)

/-- A part whose passes do not grow can raise the page's passes by at most one.

The bound `passes_append_le_fails` attains. -/
theorem passes_append_le_succ {P M : Type} (E : Engine P M) (f₁ g₁ f₂ : FrameIn P) (s : Stage)
    (h : (frameWork E g₁).passes s ≤ (frameWork E f₁).passes s) :
    (frameWork E (g₁ ++ f₂)).passes s ≤ (frameWork E (f₁ ++ f₂)).passes s + 1 := by
  rw [passes_append, passes_append]
  simp only [frameWork] at h
  by_cases a : s ∈ touched E g₁ <;> by_cases b : s ∈ touched E f₁ <;> by_cases c : s ∈ touched E f₂ <;>
    simp only [a, b, c, or_true, or_false, ↓reduceIte] at h ⊢ <;> omega

/-- **Without a strict saving the page can grow.** Under every engine, for every change `c` that dirties `s` with
`s` the style or the layout stage, there are parts with `g₁ ≼ f₁` and equal `s` passes whose page with a third part
`f₂` runs one `s` pass more with `g₁` than with `f₁`.

`≼` is `Work.le`; `g₁` trades the touched pass for a forced one, and `f₂`'s touched pass absorbs only `f₁`'s. -/
theorem passes_append_le_fails {P M : Type} (E : Engine P M) (c : Change P) (s : Stage) (hc : s ∈ E.stagesOf c)
    (hs : s = .style ∨ s = .layout) :
    ∃ f₁ g₁ f₂ : FrameIn P, (frameWork E g₁).le (frameWork E f₁) ∧
      (frameWork E g₁).passes s = (frameWork E f₁).passes s ∧
      (frameWork E (g₁ ++ f₂)).passes s = (frameWork E (f₁ ++ f₂)).passes s + 1 := by
  let o : FrameIn P := ⟨0, 0, 0, 0, [c], 0⟩
  have ho : s ∈ touched E o := by
    simp only [touched, List.mem_append, List.mem_flatMap]; exact .inl (.inl (.inl ⟨c, by simp [o], hc⟩))
  rcases hs with rfl | rfl
  · let v : FrameIn P := ⟨0, 1, 0, 0, [], 0⟩
    have hv : ∀ t, t ∉ touched E v := by intro t; simp [touched, v, FrameIn.updates]
    refine ⟨o, v, o, ⟨fun t => ⟨?_, ?_⟩, Nat.le_refl _⟩, ?_, ?_⟩
    · simp only [frameWork, hv t, ↓reduceIte]
      cases t <;> simp [forcedPasses, v, o] <;> split <;> simp_all
    · simp [frameWork, stageUnits, v]
    · simp only [frameWork, hv, ho, ↓reduceIte]; simp [forcedPasses, v, o]
    · rw [passes_append, passes_append]; simp only [ho, or_true, ↓reduceIte]; simp [forcedPasses, v, o]
  · let v : FrameIn P := ⟨0, 0, 1, 0, [], 0⟩
    have hv : ∀ t, t ∉ touched E v := by intro t; simp [touched, v, FrameIn.updates]
    refine ⟨o, v, o, ⟨fun t => ⟨?_, ?_⟩, Nat.le_refl _⟩, ?_, ?_⟩
    · simp only [frameWork, hv t, ↓reduceIte]
      cases t <;> simp [forcedPasses, v, o] <;> split <;> simp_all
    · simp [frameWork, stageUnits, v]
    · simp only [frameWork, hv, ho, ↓reduceIte]; simp [forcedPasses, v, o]
    · rw [passes_append, passes_append]; simp only [ho, or_true, ↓reduceIte]; simp [forcedPasses, v, o]

/-- **Swap accounting on passes, contract rows.** If frames are `FlowSound` over `ps`, `p` is isolated, `p < n` and
the swap gives `p` strictly fewer `s` passes, the page runs at most as many `s` passes after the swap as before.

The part-local saving may vanish on the page, never reverse. -/
theorem lego_swap_passes_flow {V P M : Type} (ps : List PartSpec) (frame : Nat → (Nat → V) → FrameIn P)
    (E : Engine P M) (n p : Nat) (x : V) (sel : Nat → V) (s : Stage)
    (hf : FlowSound ps frame) (hi : Isolated ps p) (hp : p < n)
    (h : (frameWork E (frame p (swapSel sel p x))).passes s < (frameWork E (frame p sel)).passes s) :
    (frameWork E (pageOf n fun j => frame j (swapSel sel p x))).passes s ≤
      (frameWork E (pageOf n fun j => frame j sel)).passes s :=
  passes_pageOf_le E s n p _ _ hp (fun j _ hj =>
    (lego_swap_sound (Flow ps) frame (fun _ _ => ⟨0, fun _ => []⟩) E p x sel hf (fun _ _ _ _ => rfl)
      (flow_of_isolated hi) j hj).1) h

/-! ## Deciding reachability -/

/-- Decision procedure for `Edge`.

False on every index out of range. -/
def edgeB (ps : List PartSpec) (i j : Nat) : Bool :=
  i != j && match ps[i]?, ps[j]? with
    | some P, some Q => !quiet P Q
    | _, _ => false

/-- `edgeB` decides `Edge`.

Both read the parts at `i` and `j`. -/
theorem edgeB_iff (ps : List PartSpec) (i j : Nat) : edgeB ps i j = true ↔ Edge ps i j := by
  unfold edgeB Edge
  cases hi : ps[i]? <;> cases hj : ps[j]? <;> simp

/-- An edge joins two positions in range.

Both ends hold a part. -/
theorem Edge.lt {ps : List PartSpec} {i j : Nat} (e : Edge ps i j) : i < ps.length ∧ j < ps.length := by
  obtain ⟨_, P, Q, hP, hQ, _⟩ := e
  exact ⟨(List.getElem?_eq_some_iff.mp hP).1, (List.getElem?_eq_some_iff.mp hQ).1⟩

/-- Adjacency lists of `ps`: for each position in range, the positions it has an edge to, ascending.

Position `i`'s list is entry `i`. -/
def adj (ps : List PartSpec) : List (List Nat) :=
  (List.range ps.length).map fun i => (List.range ps.length).filter (edgeB ps i)

/-- Entry `i` of `adj ps` (empty past the end) lists exactly the edges out of `i`.

`xs[i]^([])` is entry `i` of `xs`, or `[]` when `i ≥ |xs|`. -/
theorem mem_adj (ps : List PartSpec) (i j : Nat) : j ∈ (adj ps).getD i [] ↔ Edge ps i j := by
  rw [← edgeB_iff]
  unfold adj
  rw [List.getD_eq_getElem?_getD, List.getElem?_map]
  by_cases hi : i < ps.length
  · rw [List.getElem?_range hi]
    simp only [Option.map_some, Option.getD_some, List.mem_filter, List.mem_range, and_iff_right_iff_imp]
    exact fun h => ((edgeB_iff ps i j).mp h).lt.2
  · rw [List.getElem?_eq_none (by simpa using hi)]
    simp only [Option.map_none, Option.getD_none, List.not_mem_nil, false_iff]
    exact fun h => hi ((edgeB_iff ps i j).mp h).lt.1

/-- One breadth step over adjacency lists `A`: `S`, then each position below `|A|` not in `S` that an edge from `S`
reaches, ascending.

`S` stays a prefix. -/
def grow (A : List (List Nat)) (S : List Nat) : List Nat :=
  S ++ (List.range A.length).filter fun j => !S.contains j && S.any fun i => (A.getD i []).contains j

/-- Positions found from `p` in `k` breadth steps.

`k = 0` gives `[p]`. -/
def reachList (A : List (List Nat)) (p k : Nat) : List Nat := Nat.repeat (grow A) k [p]

/-- `S` is closed under the edges of `A`.

A closed set holding `p` holds everything `p` reaches. -/
def closed (A : List (List Nat)) (S : List Nat) : Bool := S.all fun i => (A.getD i []).all S.contains

/-- The start is found.

`grow` keeps its argument as a prefix. -/
theorem start_mem_reachList (A : List (List Nat)) (p : Nat) : ∀ k, p ∈ reachList A p k
  | 0 => by simp [reachList, Nat.repeat]
  | k + 1 => by
    simp only [reachList, Nat.repeat, grow, List.mem_append]
    exact .inl (start_mem_reachList A p k)

/-- Every position found from `p` is reached from `p`, when `A` lists the edges of `ps`.

Soundness of the breadth search. -/
theorem reach_of_mem_reachList {ps : List PartSpec} {A : List (List Nat)}
    (hA : ∀ i j, j ∈ A.getD i [] ↔ Edge ps i j) (p : Nat) : ∀ k q, q ∈ reachList A p k → Reach ps p q
  | 0, q, h => by
    simp only [reachList, Nat.repeat, List.mem_singleton] at h
    subst h; exact .refl _
  | k + 1, q, h => by
    simp only [reachList, Nat.repeat, grow, List.mem_append, List.mem_filter, Bool.and_eq_true, List.any_eq_true,
      List.contains_iff_mem] at h
    rcases h with h | ⟨_, _, i, hi, hq⟩
    · exact reach_of_mem_reachList hA p k q h
    · exact (reach_of_mem_reachList hA p k i hi).tail ((hA i q).mp hq)

/-- A closed set holding `i` holds every position `i` reaches, when `A` lists the edges of `ps`.

Completeness of the breadth search once it stops growing. -/
theorem mem_of_reach {ps : List PartSpec} {A : List (List Nat)} {S : List Nat}
    (hA : ∀ i j, j ∈ A.getD i [] ↔ Edge ps i j) (hc : closed A S = true) {i k : Nat} (h : Reach ps i k)
    (hi : i ∈ S) : k ∈ S := by
  unfold closed at hc
  rw [List.all_eq_true] at hc
  induction h with
  | refl => exact hi
  | @step a b _ e _ ih =>
    exact ih (List.contains_iff_mem.mp (List.all_eq_true.mp (hc a hi) b ((hA a b).mpr e)))

/-! ## The code rows -/

/-- The adjacency lists of `codeParts`, position `i` the `i`-th contract row.

Literal of `adj codeParts` (`adj_code`). -/
def codeAdj : List (List Nat) :=
  [[1, 3, 13, 15, 16, 17, 22, 28],
   [],
   [0, 1, 4, 6, 7, 8, 9, 10, 11, 14, 15, 16, 18, 20, 21, 22, 24, 26, 27, 28, 29, 30, 31, 32, 33],
   [0, 9, 13, 15, 16, 17, 22, 24, 26, 27, 28],
   [5, 9, 10],
   [0, 1, 2, 4, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 18, 20, 21, 22, 24, 26, 27, 28],
   [12],
   [9],
   [],
   [3, 4, 7, 8, 10],
   [4, 7, 8, 9],
   [0, 1, 2, 4, 6, 7, 8, 9, 10, 14, 16, 18, 20, 21, 22, 24, 26, 27, 28],
   [6],
   [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 15, 16, 17, 20, 21, 22, 24, 25, 26, 27, 28, 29, 30, 33],
   [15],
   [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 20, 21, 22, 24, 25, 26, 27, 28, 29, 30, 33],
   [0, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 18, 21, 22, 24, 28],
   [0, 3, 13, 15, 16, 18, 24, 28],
   [],
   [],
   [],
   [22, 24],
   [0, 3, 21, 24],
   [],
   [3, 5, 15, 16, 17, 21, 22, 26],
   [],
   [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 15, 16, 17, 20, 21, 22, 24, 25, 27, 28, 29, 30, 33],
   [3, 24],
   [0, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 21, 22, 24, 29],
   [],
   [],
   [],
   [],
   []]

/-- `codeAdj` is the adjacency of the code rows.

Decided on the 34 × 34 pairs. -/
theorem adj_code : adj codeParts = codeAdj := by decide

/-- `codeAdj` lists exactly the edges of the code rows.

`mem_adj` rewritten by `adj_code`. -/
theorem mem_codeAdj (i j : Nat) : j ∈ codeAdj.getD i [] ↔ Edge codeParts i j := by
  rw [← adj_code]; exact mem_adj codeParts i j

/-- Six breadth steps close every search over the code rows.

The longest shortest path has five edges. -/
theorem closed_code : (List.range 34).all (fun p => closed codeAdj (reachList codeAdj p 6)) = true := by decide

/-- Reachability on the code rows is the six-step search.

Sound by `reach_of_mem_reachList`, complete by `closed_code`. -/
theorem reach_code_iff {p : Nat} (hp : p < 34) (q : Nat) :
    Reach codeParts p q ↔ q ∈ reachList codeAdj p 6 := by
  refine ⟨fun h => mem_of_reach mem_codeAdj ?_ h (start_mem_reachList codeAdj p 6),
    reach_of_mem_reachList mem_codeAdj p 6 q⟩
  exact List.all_eq_true.mp closed_code p (List.mem_range.mpr hp)

/-- **The isolated code rows.** Exactly 12 positions of `codeParts` are quiet towards every other position.

These are the parts `lego_swap_sound_flow` applies to. -/
theorem isolated_code :
    (List.range 34).filter (isolated codeParts) = [1, 8, 18, 19, 20, 23, 25, 29, 30, 31, 32, 33] ∧
      ([1, 8, 18, 19, 20, 23, 25, 29, 30, 31, 32, 33].filterMap fun i => codeParts[i]?.map (·.id)) =
        ["commission.typing", "hero.deck", "nav.langMenu", "overlays.drawer", "overlays.signup", "people", "people.carousel", "platform.entries", "platform.glint", "platform.marquee", "platform.stageBg", "platform.sweep"] := by decide

/-- `Independent` at two positions of `ps`.

False when either index is out of range. -/
def PairIndep (ps : List PartSpec) (i k : Nat) : Prop :=
  ∃ P Q, ps[i]? = some P ∧ ps[k]? = some Q ∧ Independent P Q

/-- Decision procedure for `PairIndep`.

Reads the parts at `i` and `k`. -/
def indepAt (ps : List PartSpec) (i k : Nat) : Bool :=
  match ps[i]?, ps[k]? with
  | some P, some Q => independent P Q
  | _, _ => false

/-- `indepAt` decides `PairIndep`.

Both read the parts at `i` and `k`. -/
theorem indepAt_iff (ps : List PartSpec) (i k : Nat) : indepAt ps i k = true ↔ PairIndep ps i k := by
  unfold indepAt PairIndep Independent
  cases hi : ps[i]? <;> cases hk : ps[k]? <;> simp

/-- Exactly two code rows are `Independent` of every other row.

Overlays.drawer and people; the two-way premise of `flow_of_independent` covers only them. -/
theorem independent_all_code :
    (List.range 34).filter (fun p => (List.range 34).all fun q => q == p || indepAt codeParts p q) = [19, 23] := by
  decide

/-! ## Where the literal bridge fails -/

/-- **Self-independence breaks the literal `Indep`.** If the part at `j` is `Independent` of itself, the observable
"own variant" is `FlowSound` but does not read only the non-`PairIndep` positions.

`PairIndep` as `Indep` would make part `j` blind to its own variant. -/
theorem selfIndep_not_readsOnly (ps : List PartSpec) (j : Nat) (P : PartSpec) (hP : ps[j]? = some P)
    (hPP : Independent P P) :
    FlowSound ps (fun k (sel : Nat → Bool) => sel k) ∧ ¬ ReadsOnly (PairIndep ps) (fun k (sel : Nat → Bool) => sel k) := by
  refine ⟨(flowSound_iff ps _).mpr fun k sel sel' h => h k (.refl k), fun h => ?_⟩
  have := h j (fun _ => false) (fun i => decide (i = j)) fun i hi => by
    by_cases hij : i = j
    · subst hij; exact absurd ⟨P, P, hP, hP, hPP⟩ hi
    · simp [hij]
  simp at this

/-- Six code rows are `Independent` of themselves.

So `Indep` must exclude `i = j`. -/
theorem selfIndep_code :
    (codeParts.filter fun P => independent P P).map (·.id) =
      ["engine.scroll", "hero.cue", "hero.deck", "people", "platform.marquee", "platform.stageBg"] := by
  decide

/-- **Chains break the literal `Indep`.** If `p` reaches `q ≠ p` and the parts at `p` and `q` are `Independent`, the
observable "`q` shows `p`'s variant" is `FlowSound` but does not read only the positions not `PairIndep` of it.

Pairwise `Independent` does not stop influence along a path. -/
theorem chain_not_readsOnly (ps : List PartSpec) (p q : Nat) (hpq : p ≠ q) (hr : Reach ps p q)
    (hi : PairIndep ps p q) :
    FlowSound ps (fun k (sel : Nat → Bool) => if k = q then sel p else false) ∧
      ¬ ReadsOnly (fun i k => i ≠ k ∧ PairIndep ps i k)
        (fun k (sel : Nat → Bool) => if k = q then sel p else false) := by
  refine ⟨(flowSound_iff ps _).mpr fun k sel sel' h => ?_, fun h => ?_⟩
  · by_cases hk : k = q
    · subst hk; simp [h p hr]
    · simp [hk]
  · have := h q (fun _ => false) (fun i => decide (i = p)) fun i hni => by
      by_cases hip : i = p
      · subst hip; exact absurd ⟨hpq, hi⟩ hni
      · simp [hip]
    simp at this

/-- Pairs where the literal bridge `PairIndep → Flow` fails: from each position `p` below `|ps|`, every position found
in `k` steps that is not `p` and is `Independent` of `p`, ascending.

Pairs in the order of the comprehension. -/
def chainPairs (ps : List PartSpec) (A : List (List Nat)) (k : Nat) : List (Nat × Nat) :=
  (List.range ps.length).flatMap fun p => ((reachList A p k).filter fun q => q != p && indepAt ps p q).map (p, ·)

/-- **The literal bridge fails on exactly the listed pairs.** On the code rows, two distinct positions that are
`Independent` yet not `Flow`-independent are exactly the pairs of `chainPairs`.

Every other `Independent` pair is `Flow`-independent. -/
theorem chainPairs_code_iff (p q : Nat) :
    (p, q) ∈ chainPairs codeParts codeAdj 6 ↔ p ≠ q ∧ PairIndep codeParts p q ∧ ¬ Flow codeParts p q := by
  have hlen : codeParts.length = 34 := by decide
  unfold chainPairs Flow
  simp only [List.mem_flatMap, List.mem_range, List.mem_map, List.mem_filter, Bool.and_eq_true, bne_iff_ne, ne_eq,
    Prod.mk.injEq, Classical.not_not, hlen]
  constructor
  · rintro ⟨p', hp', q', ⟨hq', hne, hind⟩, rfl, rfl⟩
    exact ⟨fun h => hne h.symm, (indepAt_iff _ _ _).mp hind, (reach_code_iff hp' q').mpr hq'⟩
  · rintro ⟨hne, hind, hr⟩
    obtain ⟨P, _, hP, _, _⟩ := id hind
    have hp : p < 34 := hlen ▸ (List.getElem?_eq_some_iff.mp hP).1
    exact ⟨p, hp, q, ⟨(reach_code_iff hp q).mp hr, fun h => hne h.symm, (indepAt_iff _ _ _).mpr hind⟩, rfl, rfl⟩

theorem chainPairs_code_length : (chainPairs codeParts codeAdj 6).length = 298 := by decide +kernel


theorem chainTargets_code :
    (List.range 34).map (fun p => ((chainPairs codeParts codeAdj 6).filter (·.1 == p)).map (·.2)) =
       [[4, 6, 7, 8, 9, 10, 12, 14, 18, 20, 21, 24, 25, 27, 29, 30, 33, 31, 32],
        [],
        [3, 12, 17, 25],
        [1, 2, 4, 5, 6, 7, 8, 10, 11, 12, 14, 18, 20, 21, 25, 29, 30, 33, 31, 32],
        [0, 1, 3, 6, 7, 8, 12, 14, 18, 20, 21, 22, 24, 27, 17, 25, 29, 30, 31, 32, 33],
        [3, 17, 25, 29, 30, 31, 32, 33],
        [],
        [3, 4, 8, 0, 17, 22, 24, 27, 1, 6, 12, 14, 18, 20, 21, 25, 29, 30, 33, 31, 32],
        [],
        [0, 17, 22, 24, 27, 1, 6, 12, 14, 18, 20, 21, 25, 29, 30, 33, 31, 32],
        [3, 0, 1, 6, 12, 14, 17, 18, 20, 21, 22, 24, 27, 25, 29, 30, 31, 32, 33],
        [3, 12, 17, 25, 29, 30, 31, 32, 33],
        [],
        [8, 14, 18, 31, 32],
        [0, 1, 3, 4, 6, 7, 8, 9, 10, 12, 13, 17, 18, 20, 21, 22, 24, 25, 26, 27, 29, 30, 33, 31, 32],
        [31, 32],
        [1, 6, 20, 25, 27, 29, 30, 31, 32, 33],
        [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 20, 21, 22, 25, 27, 29, 30, 33, 31, 32],
        [],
        [],
        [],
        [0, 3, 17, 1, 4, 6, 7, 8, 9, 10, 12, 14, 18, 20, 25, 27, 29, 30, 33, 31, 32],
        [1, 9, 17, 27, 4, 6, 7, 8, 10, 12, 14, 18, 20, 25, 29, 30, 33, 31, 32],
        [],
        [0, 1, 4, 6, 7, 8, 9, 10, 12, 14, 18, 20, 25, 29, 30, 33, 31, 32],
        [],
        [8, 14, 18, 31, 32],
        [0, 9, 16, 17, 21, 22, 28, 1, 4, 6, 7, 8, 10, 12, 14, 18, 20, 25, 29, 30, 33, 31, 32],
        [1, 6, 20, 25, 27, 30, 31, 32, 33],
        [],
        [],
        [],
        [],
        []] := by
  decide +kernel

#guard match codeParts[19]?, codeParts[0]? with | some P, some Q => quiet P Q | _, _ => false
#guard match codeParts[0]?, codeParts[3]? with | some P, some Q => !quiet P Q | _, _ => false
#guard isolated codeParts 19
#guard !isolated codeParts 0
#guard isolated codeParts 40
#guard edgeB codeParts 0 3
#guard !edgeB codeParts 0 0
#guard !edgeB codeParts 1 0
#guard !edgeB codeParts 0 40
#guard indepAt codeParts 0 9
#guard !indepAt codeParts 0 3
#guard !indepAt codeParts 0 40
#guard closed codeAdj (reachList codeAdj 6 6)
#guard !closed codeAdj [0]
#guard closed codeAdj []
#guard reachList codeAdj 6 0 = [6]
#guard reachList codeAdj 6 1 = [6, 12]
#guard grow codeAdj [1] = [1]
#guard (0, 9) ∈ chainPairs codeParts codeAdj 6
#guard !((0, 3) ∈ chainPairs codeParts codeAdj 6)

end Fw.Parts.Bridge
