import Fw.Engine.Compose
import Fw.Parts.Contract

/-!
# Bridge from the contract rows to the Lego swap (`Independent` → `Indep`), and page passes never increase

Instantiates the abstract `Indep` of `Fw.Engine.Compose` with `Flow` (no `quiet`-violating path in a part list),
decides which rows of `codeParts` may be swapped alone, refutes the literal bridge on the listed pairs, and proves that a
part's strict pass saving never raises the page's passes. Consumers: PLAN §4.8 and §10.7 (sentences S1, S2, S3, S5).
-/

namespace Fw.Parts.Bridge

open Fw.Engine Fw.Parts.Contract

/-! ## One-way independence -/

/-- `P`'s variant cannot change `Q` directly: I1, I2 and I4 of the pair hold, and no effective output of `P` affects an
input of `Q`.

$$\operatorname{quiet}(P,Q) \iff \mathrm{I1}(P,Q) \land \mathrm{I2}(P,Q) \land \bigl(\forall o \in \operatorname{effOut}(P),\
\forall i \in \mathrm{in}_Q:\ \lnot\operatorname{affects}(o,i)\bigr) \land \mathrm{I4}(P,Q)$$

It is `Independent` without the signal flow from `Q` back to `P`. -/
def quiet (P Q : PartSpec) : Bool :=
  i1 P Q && i2 P Q && !((effOut P).any fun o => Q.inputs.any (affects o)) && i4 P Q

/-- `Independent` is `quiet` plus no signal flow from `Q` to `P`.

$$\forall P, Q:\ \operatorname{independent}(P,Q) = \Bigl(\operatorname{quiet}(P,Q) \land \bigl(\forall o \in
\operatorname{effOut}(Q),\ \forall i \in \mathrm{in}_P:\ \lnot\operatorname{affects}(o,i)\bigr)\Bigr)$$

The one-way relation drops exactly the reverse half of I3. -/
theorem independent_eq_quiet (P Q : PartSpec) :
    independent P Q = (quiet P Q && !((effOut Q).any fun o => P.inputs.any (affects o))) := by
  unfold independent quiet i3
  cases i1 P Q <;> cases i2 P Q <;> cases i4 P Q <;> cases ((effOut P).any fun o => Q.inputs.any (affects o)) <;>
    cases ((effOut Q).any fun o => P.inputs.any (affects o)) <;> rfl

/-- Independent parts are quiet towards each other.

$$\forall P, Q:\ \operatorname{Independent}(P,Q) \Rightarrow \operatorname{quiet}(P,Q)$$

The first half of `independent_eq_quiet`. -/
theorem quiet_of_independent {P Q : PartSpec} (h : Independent P Q) : quiet P Q = true := by
  rw [Independent, independent_eq_quiet, Bool.and_eq_true] at h
  exact h.1

/-! ## Flow over a part list -/

/-- A direct influence edge in part list `ps`: two distinct positions in range whose parts are not quiet.

$$\operatorname{Edge}_{ps}(i,j) \iff i \ne j \land \exists P, Q:\ ps[i] = P \land ps[j] = Q \land
\lnot\operatorname{quiet}(P,Q)$$

$ps[i] = P$ means position $i < |ps|$ holds part $P$; an index out of range has no edges. -/
def Edge (ps : List PartSpec) (i j : Nat) : Prop :=
  i ≠ j ∧ ∃ P Q, ps[i]? = some P ∧ ps[j]? = some Q ∧ quiet P Q = false

/-- Reachability in `ps`: the reflexive-transitive closure of `Edge`.

$$\operatorname{Reach}_{ps}(i,k) \iff \exists m \in \mathbb{N},\ \exists v_0, \dots, v_m \in \mathbb{N}:\ v_0 = i \land
v_m = k \land \forall t < m:\ \operatorname{Edge}_{ps}(v_t, v_{t+1})$$

Every position reaches itself. -/
inductive Reach (ps : List PartSpec) : Nat → Nat → Prop
  | refl (i : Nat) : Reach ps i i
  | step {i j k : Nat} : Edge ps i j → Reach ps j k → Reach ps i k

/-- A path extended by one edge at its end is a path.

$$\forall ps,\ \forall i, j, k \in \mathbb{N}:\ \operatorname{Reach}_{ps}(i,j) \land \operatorname{Edge}_{ps}(j,k)
\Rightarrow \operatorname{Reach}_{ps}(i,k)$$

Reach is closed under appending an edge. -/
theorem Reach.tail {ps : List PartSpec} {i j k : Nat} (h : Reach ps i j) (e : Edge ps j k) : Reach ps i k := by
  induction h with
  | refl i => exact .step e (.refl k)
  | step e' _ ih => exact .step e' (ih e)

/-- The `Indep` of `Fw.Engine.Compose` for part list `ps`: position `i` reaches not position `j`.

$$\operatorname{Flow}_{ps}(i,j) \iff \lnot\operatorname{Reach}_{ps}(i,j)$$

No position is `Flow` of itself. -/
def Flow (ps : List PartSpec) (i j : Nat) : Prop := ¬ Reach ps i j

/-- **The semantic premise.** An observable per position (frame, arm) reads only the variants of positions that reach
it: `ReadsOnly` with `Flow` as `Indep`.

$$\operatorname{FlowSound}_{ps}(\mathit{obs}) \iff \operatorname{ReadsOnly}(\operatorname{Flow}_{ps}, \mathit{obs})$$

What the contract rows claim of the site; complete rows, I5 and the reads no wire carries are its open parts. -/
def FlowSound {V α : Type} (ps : List PartSpec) (obs : Nat → (Nat → V) → α) : Prop := ReadsOnly (Flow ps) obs

/-- `FlowSound` unfolded: equal variants on every position that reaches `j` give `j` the same observable.

$$\forall ps,\ \forall \mathit{obs}:\ \operatorname{FlowSound}_{ps}(\mathit{obs}) \iff \forall j \in \mathbb{N},\ \forall
\sigma, \sigma' : \mathbb{N} \to V:\ \bigl(\forall i \in \mathbb{N}:\ \operatorname{Reach}_{ps}(i,j) \Rightarrow
\sigma(i) = \sigma'(i)\bigr) \Rightarrow \mathit{obs}(j,\sigma) = \mathit{obs}(j,\sigma')$$

The double negation of `ReadsOnly` over `Flow` cancels. -/
theorem flowSound_iff {V α : Type} (ps : List PartSpec) (obs : Nat → (Nat → V) → α) :
    FlowSound ps obs ↔ ∀ j (sel sel' : Nat → V), (∀ i, Reach ps i j → sel i = sel' i) → obs j sel = obs j sel' := by
  unfold FlowSound ReadsOnly Flow
  exact ⟨fun h j sel sel' ha => h j sel sel' fun i hi => ha i (Classical.not_not.mp hi),
    fun h j sel sel' ha => h j sel sel' fun i hi => ha i (Classical.not_not.mpr hi)⟩

/-! ## The bridge -/

/-- Position `p` is quiet towards every other position of `ps`.

$$\operatorname{Isolated}_{ps}(p) \iff \forall q \in \mathbb{N}:\ q \ne p \Rightarrow \forall P, Q:\ ps[p] = P \land
ps[q] = Q \Rightarrow \operatorname{quiet}(P,Q)$$

Holds for every `p` out of range. -/
def Isolated (ps : List PartSpec) (p : Nat) : Prop :=
  ∀ q, q ≠ p → ∀ P Q, ps[p]? = some P → ps[q]? = some Q → quiet P Q = true

/-- Decision procedure for `Isolated`.

$$\operatorname{isolated}(ps, p) \iff \forall q < |ps|:\ q = p \lor \begin{cases} \operatorname{quiet}(ps[p], ps[q]) &
p < |ps| \\ \top & p \ge |ps| \end{cases}$$

Checks the positions in range only. -/
def isolated (ps : List PartSpec) (p : Nat) : Bool :=
  (List.range ps.length).all fun q => q == p || match ps[p]?, ps[q]? with
    | some P, some Q => quiet P Q
    | _, _ => true

/-- `isolated` decides `Isolated`.

$$\forall ps,\ \forall p \in \mathbb{N}:\ \operatorname{isolated}(ps,p) \iff \operatorname{Isolated}_{ps}(p)$$

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

$$\forall ps,\ \forall p \in \mathbb{N}:\ \operatorname{Isolated}_{ps}(p) \Rightarrow \forall q \in \mathbb{N}:\ q \ne p
\Rightarrow \operatorname{Flow}_{ps}(p,q)$$

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

$$\forall ps,\ \forall p \in \mathbb{N}:\ \bigl(\forall q \in \mathbb{N}:\ q \ne p \Rightarrow \forall P, Q:\ ps[p] = P
\land ps[q] = Q \Rightarrow \operatorname{Independent}(P,Q)\bigr) \Rightarrow \forall q \in \mathbb{N}:\ q \ne p
\Rightarrow \operatorname{Flow}_{ps}(p,q)$$

`Independent` is the stronger, two-way premise. -/
theorem flow_of_independent {ps : List PartSpec} {p : Nat}
    (h : ∀ q, q ≠ p → ∀ P Q, ps[p]? = some P → ps[q]? = some Q → Independent P Q) : ∀ q, q ≠ p → Flow ps p q :=
  flow_of_isolated fun q hq P Q hP hQ => quiet_of_independent (h q hq P Q hP hQ)

/-- **Lego swap on the contract rows.** If frames and arms are `FlowSound` over `ps` and position `p` is isolated, then
swapping `p`'s variant leaves every other position's frame, frame work under every engine, and arm unchanged.

$$\forall ps,\ \forall \mathit{frame},\ \forall \mathit{arm},\ \forall E,\ \forall p \in \mathbb{N},\ \forall x \in V,\
\forall \sigma:\ \operatorname{FlowSound}_{ps}(\mathit{frame}) \land \operatorname{FlowSound}_{ps}(\mathit{arm}) \land
\operatorname{Isolated}_{ps}(p) \Rightarrow \forall q \in \mathbb{N}:\ q \ne p \Rightarrow \mathit{frame}(q,\sigma') =
\mathit{frame}(q,\sigma) \land \operatorname{frameWork}_E(\mathit{frame}(q,\sigma')) =
\operatorname{frameWork}_E(\mathit{frame}(q,\sigma)) \land \mathit{arm}(q,\sigma') = \mathit{arm}(q,\sigma),\quad
\sigma' = \operatorname{swap}(\sigma,p,x)$$

`lego_swap_sound` with `Indep` discharged by `flow_of_isolated`. -/
theorem lego_swap_sound_flow {V P M : Type} (ps : List PartSpec) (frame : Nat → (Nat → V) → FrameIn P)
    (arm : Nat → (Nat → V) → PartArm) (E : Engine P M) (p : Nat) (x : V) (sel : Nat → V)
    (hf : FlowSound ps frame) (ha : FlowSound ps arm) (hp : Isolated ps p) :
    ∀ q, q ≠ p → frame q (swapSel sel p x) = frame q sel ∧
      frameWork E (frame q (swapSel sel p x)) = frameWork E (frame q sel) ∧
      arm q (swapSel sel p x) = arm q sel :=
  lego_swap_sound (Flow ps) frame arm E p x sel hf ha (flow_of_isolated hp)

/-- **Swap accounting on units, contract rows.** If frames are `FlowSound` over `ps`, `p` is isolated and $p < n$, the
page's units after the swap plus `p`'s units before equal the page's units before plus `p`'s units after, at every
stage.

$$\forall ps,\ \forall \mathit{frame},\ \forall E,\ \forall n, p \in \mathbb{N},\ \forall x \in V,\ \forall \sigma,\
\forall s \in \mathrm{Stage}:\ \operatorname{FlowSound}_{ps}(\mathit{frame}) \land \operatorname{Isolated}_{ps}(p) \land
p < n \Rightarrow \operatorname{frameWork}_E(\operatorname{page}(n, j \mapsto \mathit{frame}(j,
\sigma'))).\mathrm{units}(s) + \operatorname{frameWork}_E(\mathit{frame}(p,\sigma)).\mathrm{units}(s) =
\operatorname{frameWork}_E(\operatorname{page}(n, j \mapsto \mathit{frame}(j, \sigma))).\mathrm{units}(s) +
\operatorname{frameWork}_E(\mathit{frame}(p,\sigma')).\mathrm{units}(s),\quad \sigma' = \operatorname{swap}(\sigma,p,x)$$

`lego_swap_units` with `Indep` discharged by `flow_of_isolated`. -/
theorem lego_swap_units_flow {V P M : Type} (ps : List PartSpec) (frame : Nat → (Nat → V) → FrameIn P)
    (E : Engine P M) (n p : Nat) (x : V) (sel : Nat → V) (s : Stage)
    (hf : FlowSound ps frame) (hi : Isolated ps p) (hp : p < n) :
    (frameWork E (pageOf n fun j => frame j (swapSel sel p x))).units s + (frameWork E (frame p sel)).units s =
      (frameWork E (pageOf n fun j => frame j sel)).units s + (frameWork E (frame p (swapSel sel p x))).units s :=
  lego_swap_units (Flow ps) frame E n p x sel s hf (flow_of_isolated hi) hp

/-- **Swap keeps the visible page, contract rows.** If arms are `FlowSound` over `ps`, `p` is isolated, and `p`'s arm
keeps its band height and its visible scene at every offset, the visible page scene of parts $0, \dots, n-1$ is
unchanged from every start offset.

$$\forall ps,\ \forall \mathit{arm},\ \forall \mathit{vp},\ \forall n, p \in \mathbb{N},\ \forall x \in V,\ \forall
\sigma,\ \forall y \in \mathbb{Q}:\ \operatorname{FlowSound}_{ps}(\mathit{arm}) \land \operatorname{Isolated}_{ps}(p)
\land \mathit{arm}(p,\sigma').\mathrm{height} = \mathit{arm}(p,\sigma).\mathrm{height} \land \bigl(\forall y' \in
\mathbb{Q}:\ \operatorname{visible}_{\mathit{vp}}(\mathit{arm}(p,\sigma').\mathrm{scene}(y')) =
\operatorname{visible}_{\mathit{vp}}(\mathit{arm}(p,\sigma).\mathrm{scene}(y'))\bigr) \Rightarrow
\operatorname{visible}_{\mathit{vp}}\bigl(\operatorname{stackScene}(y, [\mathit{arm}(j,\sigma')]_{j<n})\bigr) =
\operatorname{visible}_{\mathit{vp}}\bigl(\operatorname{stackScene}(y, [\mathit{arm}(j,\sigma)]_{j<n})\bigr),\quad
\sigma' = \operatorname{swap}(\sigma,p,x)$$

`lego_swap_visible` with `Indep` discharged by `flow_of_isolated`. -/
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

$$\operatorname{PassDom}_{E,s}(g,f) \iff \bigl((s \in \operatorname{touched}_E(g) \Rightarrow s \in
\operatorname{touched}_E(f)) \land \operatorname{forced}(g,s) \le \operatorname{forced}(f,s)\bigr) \lor
\operatorname{forced}(g,s) + 1 \le \operatorname{forced}(f,s)$$

The invariant that survives appending the rest of the page. -/
def PassDom {P M : Type} (E : Engine P M) (s : Stage) (g f : FrameIn P) : Prop :=
  ((s ∈ touched E g → s ∈ touched E f) ∧ forcedPasses g s ≤ forcedPasses f s) ∨
    forcedPasses g s + 1 ≤ forcedPasses f s

/-- A frame pass-dominates itself.

$$\forall E,\ \forall s,\ \forall f \in \mathrm{FrameIn}(P):\ \operatorname{PassDom}_{E,s}(f,f)$$

The first case with equality. -/
theorem passDom_refl {P M : Type} (E : Engine P M) (s : Stage) (f : FrameIn P) : PassDom E s f f :=
  .inl ⟨id, Nat.le_refl _⟩

/-- A strict pass saving on `s` is a pass dominance.

$$\forall E,\ \forall s,\ \forall g, f \in \mathrm{FrameIn}(P):\ \operatorname{frameWork}_E(g).\mathrm{passes}(s) <
\operatorname{frameWork}_E(f).\mathrm{passes}(s) \Rightarrow \operatorname{PassDom}_{E,s}(g,f)$$

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

$$\forall E,\ \forall s,\ \forall g, f, c \in \mathrm{FrameIn}(P):\ \operatorname{PassDom}_{E,s}(g,f) \Rightarrow
\operatorname{PassDom}_{E,s}(g \mathbin{+\!\!+} c,\ f \mathbin{+\!\!+} c)$$

Touched stages join and forced passes add. -/
theorem passDom_append_right {P M : Type} (E : Engine P M) (s : Stage) {g f : FrameIn P} (c : FrameIn P)
    (h : PassDom E s g f) : PassDom E s (g ++ c) (f ++ c) := by
  unfold PassDom at h ⊢
  rw [forcedPasses_append, forcedPasses_append, touched_append, touched_append]
  rcases h with ⟨ht, hf⟩ | h
  · exact .inl ⟨fun h' => h'.imp ht id, by omega⟩
  · exact .inr (by omega)

/-- Pass dominance survives a frame appended on the left.

$$\forall E,\ \forall s,\ \forall g, f, c \in \mathrm{FrameIn}(P):\ \operatorname{PassDom}_{E,s}(g,f) \Rightarrow
\operatorname{PassDom}_{E,s}(c \mathbin{+\!\!+} g,\ c \mathbin{+\!\!+} f)$$

Touched stages join and forced passes add. -/
theorem passDom_append_left {P M : Type} (E : Engine P M) (s : Stage) {g f : FrameIn P} (c : FrameIn P)
    (h : PassDom E s g f) : PassDom E s (c ++ g) (c ++ f) := by
  unfold PassDom at h ⊢
  rw [forcedPasses_append, forcedPasses_append, touched_append, touched_append]
  rcases h with ⟨ht, hf⟩ | h
  · exact .inl ⟨fun h' => h'.imp id ht, by omega⟩
  · exact .inr (by omega)

/-- Pass dominance bounds the passes.

$$\forall E,\ \forall s,\ \forall g, f \in \mathrm{FrameIn}(P):\ \operatorname{PassDom}_{E,s}(g,f) \Rightarrow
\operatorname{frameWork}_E(g).\mathrm{passes}(s) \le \operatorname{frameWork}_E(f).\mathrm{passes}(s)$$

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

$$\forall E,\ \forall f_1, g_1, f_2 \in \mathrm{FrameIn}(P),\ \forall s \in \mathrm{Stage}:\
\operatorname{frameWork}_E(g_1).\mathrm{passes}(s) < \operatorname{frameWork}_E(f_1).\mathrm{passes}(s) \Rightarrow
\operatorname{frameWork}_E(g_1 \mathbin{+\!\!+} f_2).\mathrm{passes}(s) \le \operatorname{frameWork}_E(f_1
\mathbin{+\!\!+} f_2).\mathrm{passes}(s)$$

A pass saving can vanish on the page (`passes_not_compositional`) but never turns into an increase. -/
theorem passes_append_le {P M : Type} (E : Engine P M) (f₁ g₁ f₂ : FrameIn P) (s : Stage)
    (h : (frameWork E g₁).passes s < (frameWork E f₁).passes s) :
    (frameWork E (g₁ ++ f₂)).passes s ≤ (frameWork E (f₁ ++ f₂)).passes s :=
  passes_le_of_passDom E s (passDom_append_right E s f₂ (passDom_of_lt E s g₁ f₁ h))

/-- **Never an increase on a page of `n` parts.** If part functions `G` and `F` agree below `n` except at `p < n`, and
`G p` runs strictly fewer `s` passes than `F p`, the page of `G` runs at most as many `s` passes as the page of `F`.

$$\forall E,\ \forall s,\ \forall n, p \in \mathbb{N},\ \forall F, G : \mathbb{N} \to \mathrm{FrameIn}(P):\ p < n \land
\bigl(\forall j < n:\ j \ne p \Rightarrow G(j) = F(j)\bigr) \land \operatorname{frameWork}_E(G(p)).\mathrm{passes}(s)
< \operatorname{frameWork}_E(F(p)).\mathrm{passes}(s) \Rightarrow \operatorname{frameWork}_E(\operatorname{page}(n,
G)).\mathrm{passes}(s) \le \operatorname{frameWork}_E(\operatorname{page}(n, F)).\mathrm{passes}(s)$$

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

$$\forall E,\ \forall f_1, g_1, f_2 \in \mathrm{FrameIn}(P),\ \forall s \in \mathrm{Stage}:\
\operatorname{frameWork}_E(g_1).\mathrm{passes}(s) \le \operatorname{frameWork}_E(f_1).\mathrm{passes}(s) \Rightarrow
\operatorname{frameWork}_E(g_1 \mathbin{+\!\!+} f_2).\mathrm{passes}(s) \le \operatorname{frameWork}_E(f_1
\mathbin{+\!\!+} f_2).\mathrm{passes}(s) + 1$$

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

$$\forall E,\ \forall c \in \mathrm{Change}(P),\ \forall s \in \mathrm{Stage}:\ s \in E.\mathrm{stagesOf}(c) \land s
\in \{\mathrm{style}, \mathrm{layout}\} \Rightarrow \exists f_1, g_1, f_2 \in \mathrm{FrameIn}(P):\
\operatorname{frameWork}_E(g_1) \preceq \operatorname{frameWork}_E(f_1) \land
\operatorname{frameWork}_E(g_1).\mathrm{passes}(s) = \operatorname{frameWork}_E(f_1).\mathrm{passes}(s) \land
\operatorname{frameWork}_E(g_1 \mathbin{+\!\!+} f_2).\mathrm{passes}(s) = \operatorname{frameWork}_E(f_1
\mathbin{+\!\!+} f_2).\mathrm{passes}(s) + 1$$

`g₁` trades the touched pass for a forced one, and `f₂`'s touched pass absorbs only `f₁`'s. -/
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

/-- **Swap accounting on passes, contract rows.** If frames are `FlowSound` over `ps`, `p` is isolated, $p < n$ and
the swap gives `p` strictly fewer `s` passes, the page runs at most as many `s` passes after the swap as before.

$$\forall ps,\ \forall \mathit{frame},\ \forall E,\ \forall n, p \in \mathbb{N},\ \forall x \in V,\ \forall \sigma,\
\forall s \in \mathrm{Stage}:\ \operatorname{FlowSound}_{ps}(\mathit{frame}) \land \operatorname{Isolated}_{ps}(p)
\land p < n \land \operatorname{frameWork}_E(\mathit{frame}(p,\sigma')).\mathrm{passes}(s) <
\operatorname{frameWork}_E(\mathit{frame}(p,\sigma)).\mathrm{passes}(s) \Rightarrow
\operatorname{frameWork}_E(\operatorname{page}(n, j \mapsto \mathit{frame}(j,\sigma'))).\mathrm{passes}(s) \le
\operatorname{frameWork}_E(\operatorname{page}(n, j \mapsto \mathit{frame}(j,\sigma))).\mathrm{passes}(s),\quad
\sigma' = \operatorname{swap}(\sigma,p,x)$$

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

end Fw.Parts.Bridge
