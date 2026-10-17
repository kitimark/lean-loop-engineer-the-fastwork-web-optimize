import Lean.Data.Json
/-!
# Screening without coefficients (class W, PLAN §4.3)

A run is a list of frames aligned by content anchor; each frame is a vector of work counts. If the
variant's vector is at most the baseline's in every component of every frame, then under **any**
non-negative coefficients (and any constant term) no frame's predicted cost goes up. The model is
the linear one, $T_{\kappa,c}(x) = \kappa + \sum_j c_j x_j$; whether an engine obeys it, whether the
counts are right and whether the frames are aligned are L3 premises checked elsewhere.
-/
namespace Fw.Screen

/-- One frame's work counts (layout passes, restyled elements, painted kpx, ...).

$$\mathrm{Counts} = \mathbb{N}^{*}$$
-/
abbrev Counts := List Nat

/-- A run: one count vector per frame, frames aligned by content anchor.

$$\mathrm{Run} = \mathrm{Counts}^{*} = (\mathbb{N}^{*})^{*}$$
-/
abbrev Run := List Counts

/-- The weighted sum of the counts with coefficients `c` (pairs up positions; extra entries on
either side are ignored).

$$\operatorname{dot}(c, x) = \sum_{j=1}^{\min(|c|, |x|)} c_j\, x_j \in \mathbb{Q}$$
-/
def dot : List Rat → Counts → Rat
  | c :: cs, x :: xs => c * (x : Rat) + dot cs xs
  | _, _ => 0

/-- The predicted cost of one frame under the linear model with constant `κ` and coefficients `c`.

$$T_{\kappa, c}(x) = \kappa + \operatorname{dot}(c, x)$$
-/
def cost (κ : Rat) (c : List Rat) (x : Counts) : Rat := κ + dot c x

/-- One count vector is componentwise at most another of the same length.

$$\operatorname{leVec}(x, y) = \mathrm{true} \iff |x| = |y| \ \land\ \forall j:\ x_j \le y_j$$
-/
def leVec : Counts → Counts → Bool
  | [], [] => true
  | x :: xs, y :: ys => decide (x ≤ y) && leVec xs ys
  | _, _ => false

/-- One run is framewise at most another: the same number of frames and `leVec` in every frame.

$$\operatorname{leRun}(A, B) = \mathrm{true} \iff |A| = |B| \ \land\ \forall f:\ \operatorname{leVec}(A_f, B_f) = \mathrm{true}$$
-/
def leRun : Run → Run → Bool
  | [], [] => true
  | a :: as, b :: bs => leVec a b && leRun as bs
  | _, _ => false

/-- The four screening outcomes.

$$\mathrm{Result} = \{\mathrm{dominates}, \mathrm{equal}, \mathrm{worse}, \mathrm{mixed}\}$$
-/
inductive Result where
  | dominates | equal | worse | mixed
deriving Repr, DecidableEq, Lean.ToJson, Lean.FromJson

/-- The two runs have the same shape: the same number of frames and the same vector length in
each frame.

$$\operatorname{shapeEq}(B, V) = \mathrm{true} \iff |B| = |V| \ \land\ \forall f:\ |B_f| = |V_f|$$
-/
def shapeEq (base var : Run) : Bool := base.map List.length == var.map List.length

/-- The screen: first match wins.

$$\operatorname{screen}(B, V) = \begin{cases} \mathrm{error}(\texttt{"frames or count vectors not aligned"}) & \text{if } \neg\operatorname{shapeEq}(B, V) \\ \mathrm{ok}(\mathrm{equal}) & \text{else if } V = B \\ \mathrm{ok}(\mathrm{dominates}) & \text{else if } \operatorname{leRun}(V, B) \\ \mathrm{ok}(\mathrm{worse}) & \text{else if } \operatorname{leRun}(B, V) \\ \mathrm{ok}(\mathrm{mixed}) & \text{otherwise} \end{cases}$$
-/
def screen (base var : Run) : Except String Result :=
  if !shapeEq base var then .error "frames or count vectors not aligned"
  else if var == base then .ok .equal
  else if leRun var base then .ok .dominates
  else if leRun base var then .ok .worse
  else .ok .mixed

-- v1 golden case A: fewer layout passes in some frames, never more -> dominates (class W).
#guard screen [[3, 10], [2, 10], [1, 10]] [[1, 10], [2, 10], [1, 10]] matches .ok .dominates
-- v1 golden case B: paint moved one frame earlier, total equal -> mixed (not class W).
#guard screen [[0, 0], [0, 50], [0, 0]] [[0, 50], [0, 0], [0, 0]] matches .ok .mixed
#guard screen [[1]] [[1]] matches .ok .equal
#guard screen [[1]] [[2]] matches .ok .worse
#guard (match screen [[1]] [[1, 2]] with | .error e => e == "frames or count vectors not aligned" | .ok _ => false)
#guard screen [] [] matches .ok .equal

/-- More counts never give a smaller weighted sum when the coefficients are non-negative.

$$\forall c \in \mathbb{Q}^{*},\ \forall x, y \in \mathbb{N}^{*}:\quad (\forall j:\ 0 \le c_j) \ \land\ \operatorname{leVec}(x, y) \;\Rightarrow\; \operatorname{dot}(c, x) \le \operatorname{dot}(c, y)$$
-/
theorem dot_mono (cs : List Rat) (hc : ∀ c ∈ cs, 0 ≤ c) :
    ∀ {x y : Counts}, leVec x y = true → dot cs x ≤ dot cs y := by
  induction cs with
  | nil => intro x y _; cases x <;> cases y <;> exact Rat.le_refl
  | cons c cs ih =>
    intro x y h
    cases x with
    | nil => cases y with
      | nil => exact Rat.le_refl
      | cons _ _ => simp [leVec] at h
    | cons a xs => cases y with
      | nil => simp [leVec] at h
      | cons b ys =>
        simp only [leVec, Bool.and_eq_true, decide_eq_true_eq] at h
        simp only [dot]
        have h1 : c * (a : Rat) ≤ c * (b : Rat) :=
          Rat.mul_le_mul_of_nonneg_left (Rat.natCast_le_natCast.mpr h.1) (hc c (by simp))
        have h2 : dot cs xs ≤ dot cs ys := ih (fun c' hc' => hc c' (by simp [hc'])) h.2
        exact Rat.le_trans (Rat.add_le_add_right.mpr h1) (Rat.add_le_add_left.mpr h2)

/-- `leRun` means `leVec` frame by frame, with equal frame counts.

$$\operatorname{leRun}(A, B) = \mathrm{true} \;\Rightarrow\; |A| = |B| \ \land\ \forall (a, b) \in \operatorname{zip}(A, B):\ \operatorname{leVec}(a, b) = \mathrm{true}$$
-/
theorem leRun_spec : ∀ {A B : Run}, leRun A B = true →
    A.length = B.length ∧ ∀ p ∈ A.zip B, leVec p.1 p.2 = true
  | [], [], _ => by simp
  | [], _ :: _, h => by simp [leRun] at h
  | _ :: _, [], h => by simp [leRun] at h
  | a :: as, b :: bs, h => by
    simp only [leRun, Bool.and_eq_true] at h
    obtain ⟨hl, hz⟩ := leRun_spec h.2
    refine ⟨by simp [hl], ?_⟩
    intro p hp
    simp only [List.zip_cons_cons, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact h.1
    · exact hz p hp

/-- **Screening soundness (class W).** If the screen says "dominates", the variant has as many
frames as the baseline, differs from it, and under every constant term and every non-negative
coefficient vector no aligned frame of the variant is predicted to cost more than the baseline's.

$$\operatorname{screen}(B, V) = \mathrm{ok}(\mathrm{dominates}) \;\Rightarrow\; |V| = |B| \ \land\ V \ne B \ \land\ \forall \kappa \in \mathbb{Q},\ \forall c \in \mathbb{Q}^{*}:\ (\forall j:\ 0 \le c_j) \Rightarrow \forall (v, b) \in \operatorname{zip}(V, B):\ T_{\kappa, c}(v) \le T_{\kappa, c}(b)$$
-/
theorem screen_sound {base var : Run} (h : screen base var = .ok .dominates) :
    var.length = base.length ∧ var ≠ base ∧
      ∀ (κ : Rat) (cs : List Rat), (∀ c ∈ cs, 0 ≤ c) →
        ∀ p ∈ var.zip base, cost κ cs p.1 ≤ cost κ cs p.2 := by
  unfold screen at h
  split at h; · cases h
  split at h; · cases h
  rename_i hne
  split at h
  · rename_i hle
    obtain ⟨hl, hz⟩ := leRun_spec hle
    refine ⟨hl, fun e => hne (by simp [e]), ?_⟩
    intro κ cs hc p hp
    exact Rat.add_le_add_left.mpr (dot_mono cs hc (hz p hp))
  · split at h <;> cases h

/-- The mirror image: if the screen says "worse", no aligned frame of the baseline is predicted to
cost more than the variant's, under every constant term and non-negative coefficients.

$$\operatorname{screen}(B, V) = \mathrm{ok}(\mathrm{worse}) \;\Rightarrow\; |B| = |V| \ \land\ V \ne B \ \land\ \forall \kappa \in \mathbb{Q},\ \forall c \in \mathbb{Q}^{*}:\ (\forall j:\ 0 \le c_j) \Rightarrow \forall (b, v) \in \operatorname{zip}(B, V):\ T_{\kappa, c}(b) \le T_{\kappa, c}(v)$$
-/
theorem screen_worse {base var : Run} (h : screen base var = .ok .worse) :
    base.length = var.length ∧ var ≠ base ∧
      ∀ (κ : Rat) (cs : List Rat), (∀ c ∈ cs, 0 ≤ c) →
        ∀ p ∈ base.zip var, cost κ cs p.1 ≤ cost κ cs p.2 := by
  unfold screen at h
  split at h; · cases h
  split at h; · cases h
  rename_i hne
  split at h; · cases h
  split at h
  · rename_i hle
    obtain ⟨hl, hz⟩ := leRun_spec hle
    refine ⟨hl, fun e => hne (by simp [e]), ?_⟩
    intro κ cs hc p hp
    exact Rat.add_le_add_left.mpr (dot_mono cs hc (hz p hp))
  · cases h

end Fw.Screen
