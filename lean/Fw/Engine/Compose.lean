import Fw.Engine.Visual
import Fw.Engine.Chromium
import Fw.Engine.WebKit
/-!
# Composing parts (Lego): what per-part results say about the whole page (parts plan §C item 2)

Over any `Engine`: units and hit tests add over parts, so per-part dominance and strictness carry to the page; passes
do not (`passes_not_compositional`, `frame_le_append_passes_fails`), and page dominance needs the stage-set form
(`unionLe_append`, `frame_le_append_cover`). `lego_swap_sound` keeps every independent part unchanged under a swap.
Consumers: the combined-run and part-shard rules of the parts plan, and the model-bug-fixes check of UpdateLayoutTree.
-/
namespace Fw.Engine

/-! ## Frames of several parts -/

/-- The frame of no part: no callbacks, no forced passes, no hit tests, no changes, no compositor animations. -/
def FrameIn.empty {P : Type} : FrameIn P := ⟨0, 0, 0, 0, [], 0⟩

/-- Two parts in one frame: counts add, change lists concatenate. -/
def FrameIn.append {P : Type} (f g : FrameIn P) : FrameIn P where
  script       := f.script + g.script
  forcedStyle  := f.forcedStyle + g.forcedStyle
  forcedLayout := f.forcedLayout + g.forcedLayout
  hits         := f.hits + g.hits
  changes      := f.changes ++ g.changes
  compAnims    := f.compAnims + g.compAnims

instance {P : Type} : Append (FrameIn P) := ⟨FrameIn.append⟩

/-- The changes of two parts are the concatenation of their changes. -/
@[simp] theorem FrameIn.append_changes {P : Type} (f g : FrameIn P) :
    (f ++ g).changes = f.changes ++ g.changes := rfl

/-- The callbacks of two parts add. -/
@[simp] theorem FrameIn.append_script {P : Type} (f g : FrameIn P) : (f ++ g).script = f.script + g.script := rfl

/-- The forced style passes of two parts add. -/
@[simp] theorem FrameIn.append_forcedStyle {P : Type} (f g : FrameIn P) :
    (f ++ g).forcedStyle = f.forcedStyle + g.forcedStyle := rfl

/-- The forced layout passes of two parts add. -/
@[simp] theorem FrameIn.append_forcedLayout {P : Type} (f g : FrameIn P) :
    (f ++ g).forcedLayout = f.forcedLayout + g.forcedLayout := rfl

/-- The hit tests of two parts add. -/
@[simp] theorem FrameIn.append_hits {P : Type} (f g : FrameIn P) : (f ++ g).hits = f.hits + g.hits := rfl

/-- The compositor animations of two parts add. -/
@[simp] theorem FrameIn.append_compAnims {P : Type} (f g : FrameIn P) :
    (f ++ g).compAnims = f.compAnims + g.compAnims := rfl

/-- Two parts update the frame when one of them does. -/
theorem FrameIn.updates_append {P : Type} (f g : FrameIn P) : (f ++ g).updates = (f.updates || g.updates) := by
  unfold FrameIn.updates
  show (!(f.changes ++ g.changes).isEmpty || decide (0 < f.script + g.script)) = _
  by_cases ha : 0 < f.script <;> by_cases hb : 0 < g.script <;>
    cases f.changes <;> cases g.changes <;> simp [ha, hb] <;> omega

/-- The forced passes of two parts add, stage by stage. -/
theorem forcedPasses_append {P : Type} (f g : FrameIn P) (s : Stage) :
    forcedPasses (f ++ g) s = forcedPasses f s + forcedPasses g s := by
  cases s <;> rfl

/-- **Touched stages of two parts** are the union of each part's touched stages. -/
theorem touched_append {P M : Type} (E : Engine P M) (f₁ f₂ : FrameIn P) (s : Stage) :
    s ∈ touched E (f₁ ++ f₂) ↔ s ∈ touched E f₁ ∨ s ∈ touched E f₂ := by
  simp only [touched, List.mem_append, FrameIn.append_changes, List.flatMap_append, FrameIn.append_compAnims,
    FrameIn.append_script, FrameIn.updates_append]
  grind

/-- The passes of stage `s` for two parts: one if either part touches `s`, plus both parts' forced passes. -/
theorem passes_append {P M : Type} (E : Engine P M) (f₁ f₂ : FrameIn P) (s : Stage) :
    (frameWork E (f₁ ++ f₂)).passes s =
      (if s ∈ touched E f₁ ∨ s ∈ touched E f₂ then 1 else 0) + forcedPasses f₁ s + forcedPasses f₂ s := by
  simp only [frameWork, forcedPasses_append, Nat.add_assoc]
  by_cases h : s ∈ touched E f₁ ∨ s ∈ touched E f₂
  · simp only [(touched_append E f₁ f₂ s).mpr h, h, ↓reduceIte]
  · simp only [show s ∉ touched E (f₁ ++ f₂) from fun h' => h ((touched_append E f₁ f₂ s).mp h'), h, ↓reduceIte]

/-! ## Passes do not compose -/

/-- **A dropped pass is absorbed.** When another part touches stage `s` in the frame, replacing part `f₁` by `g₁`
with the same forced passes on `s` leaves the page's passes of `s` unchanged, whether or not `g₁` touches `s`.
-/
theorem passes_absorb_part {P M : Type} (E : Engine P M) (f₁ g₁ f₂ : FrameIn P) (s : Stage)
    (h₂ : s ∈ touched E f₂) (hf : forcedPasses g₁ s = forcedPasses f₁ s) :
    (frameWork E (g₁ ++ f₂)).passes s = (frameWork E (f₁ ++ f₂)).passes s := by
  rw [passes_append, passes_append, hf]
  simp [h₂]

/-- **Passes are not compositional.** Under every engine, for every change `c` that dirties stage `s`, there are
parts `f₁`, `g₁`, `f₂` such that `f₁` touches `s` and `g₁` does not, `g₁` alone runs strictly fewer `s` passes and
strictly less work than `f₁`, `f₂` touches `s`, and the page with `g₁` runs exactly as many `s` passes as the page
with `f₁`.

A part that drops a stage pass saves nothing on the page while another part touches that stage in the frame. -/
theorem passes_not_compositional {P M : Type} (E : Engine P M) (c : Change P) (s : Stage)
    (hc : s ∈ E.stagesOf c) :
    ∃ f₁ g₁ f₂ : FrameIn P, s ∉ touched E g₁ ∧ s ∈ touched E f₁ ∧ s ∈ touched E f₂ ∧
      (frameWork E g₁).passes s < (frameWork E f₁).passes s ∧ (frameWork E g₁).lt (frameWork E f₁) ∧
      (frameWork E (g₁ ++ f₂)).passes s = (frameWork E (f₁ ++ f₂)).passes s := by
  let f : FrameIn P := ⟨0, 0, 0, 0, [c], 0⟩
  have hf : s ∈ touched E f := by
    simp only [touched, List.mem_append, List.mem_flatMap]; exact .inl (.inl (.inl ⟨c, by simp [f], hc⟩))
  have hg : s ∉ touched E (FrameIn.empty : FrameIn P) := by
    simp [touched, FrameIn.empty, FrameIn.updates]
  have hp : (frameWork E (FrameIn.empty : FrameIn P)).passes s < (frameWork E f).passes s := by
    simp only [frameWork, hg, hf, ↓reduceIte]
    cases s <;> simp [forcedPasses, FrameIn.empty, f]
  refine ⟨f, FrameIn.empty, f, hg, hf, hf, hp, ⟨⟨fun t => ⟨?_, ?_⟩, Nat.zero_le _⟩, .inl ⟨s, .inl hp⟩⟩,
    passes_absorb_part E f FrameIn.empty f s hf (by cases s <;> rfl)⟩
  · have : t ∉ touched E (FrameIn.empty : FrameIn P) := by simp [touched, FrameIn.empty, FrameIn.updates]
    simp only [frameWork, this, ↓reduceIte]
    cases t <;> simp [forcedPasses, FrameIn.empty]
  · simp [frameWork, stageUnits, FrameIn.empty]

open Chromium in
/-- **Chromium instance.** A `height` change on a box without a layer dirties `layout` in the lane mode, so a dropped
layout pass can be absorbed by another part's layout pass.
-/
theorem passes_not_compositional_chromium :
    ∃ f₁ g₁ f₂ : FrameIn CrProp, Stage.layout ∉ touched chromium g₁ ∧
      Stage.layout ∈ touched chromium f₁ ∧
      Stage.layout ∈ touched chromium f₂ ∧
      (frameWork chromium g₁).passes .layout < (frameWork chromium f₁).passes .layout ∧
      (frameWork chromium g₁).lt (frameWork chromium f₁) ∧
      (frameWork chromium (g₁ ++ f₂)).passes .layout = (frameWork chromium (f₁ ++ f₂)).passes .layout :=
  passes_not_compositional chromium ⟨0, .css .height, .none⟩ .layout (by decide)

open WebKit in
/-- **WebKit instance.** A `size` change on a box without a layer dirties `layout`, so a dropped layout pass can be
absorbed by another part's layout pass.
-/
theorem passes_not_compositional_webkit :
    ∃ f₁ g₁ f₂ : FrameIn WkProp, Stage.layout ∉ touched webkit g₁ ∧
      Stage.layout ∈ touched webkit f₁ ∧
      Stage.layout ∈ touched webkit f₂ ∧
      (frameWork webkit g₁).passes .layout < (frameWork webkit f₁).passes .layout ∧
      (frameWork webkit g₁).lt (frameWork webkit f₁) ∧
      (frameWork webkit (g₁ ++ f₂)).passes .layout = (frameWork webkit (f₁ ++ f₂)).passes .layout :=
  passes_not_compositional webkit ⟨0, .size, .none⟩ .layout (by decide)

/-- **Per-part dominance does not give page dominance on passes.** Under every engine with a change `c` that dirties
`style`, there are parts with `v_1 ≼ o_1` and `v_2 ≼ o_2` whose page frames are not ordered: `v_1` trades
a touched `style` pass for a forced one, and the forced pass is not absorbed by `v_2`'s `style` pass.

The plan's `frame_le_append` stated over `≼` alone is false for passes. -/
theorem frame_le_append_passes_fails {P M : Type} (E : Engine P M) (c : Change P) (hc : .style ∈ E.stagesOf c) :
    ∃ v₁ o₁ v₂ o₂ : FrameIn P, (frameWork E v₁).le (frameWork E o₁) ∧ (frameWork E v₂).le (frameWork E o₂) ∧
      ¬ (frameWork E (v₁ ++ v₂)).le (frameWork E (o₁ ++ o₂)) := by
  let v : FrameIn P := ⟨0, 1, 0, 0, [], 0⟩
  let o : FrameIn P := ⟨0, 0, 0, 0, [c], 0⟩
  have ho : Stage.style ∈ touched E o := by
    simp only [touched, List.mem_append, List.mem_flatMap]; exact .inl (.inl (.inl ⟨c, by simp [o], hc⟩))
  have hv : ∀ t, t ∉ touched E v := by intro t; simp [touched, v, FrameIn.updates]
  refine ⟨v, o, o, o, ⟨fun t => ⟨?_, ?_⟩, Nat.le_refl _⟩, Work.le_refl _, fun h => ?_⟩
  · simp only [frameWork, hv t, ↓reduceIte]
    cases t <;> simp [forcedPasses, v, o] <;> split <;> simp_all
  · simp [frameWork, stageUnits, v]
  · have h1 := (h.1 .style).1
    rw [passes_append, passes_append] at h1
    simp only [ho, or_self, ↓reduceIte] at h1
    simp [forcedPasses, v, o] at h1

/-! ## Units and hit tests compose -/

/-- **Units add over parts.** -/
theorem frameWork_append_units {P M : Type} (E : Engine P M) (f₁ f₂ : FrameIn P) (s : Stage) :
    (frameWork E (f₁ ++ f₂)).units s = (frameWork E f₁).units s + (frameWork E f₂).units s := by
  simp only [frameWork, stageUnits, FrameIn.append_changes, List.countP_append, FrameIn.append_compAnims,
    FrameIn.append_script]
  split <;> split <;> omega

/-- **Hit tests add over parts.** -/
theorem frameWork_append_hits {P M : Type} (E : Engine P M) (f₁ f₂ : FrameIn P) :
    (frameWork E (f₁ ++ f₂)).hits = (frameWork E f₁).hits + (frameWork E f₂).hits := rfl

/-- **Per-part dominance gives page dominance on units and hit tests.** -/
theorem frame_le_append_units {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (h₁ : (frameWork E v₁).le (frameWork E o₁)) (h₂ : (frameWork E v₂).le (frameWork E o₂)) :
    (∀ s, (frameWork E (v₁ ++ v₂)).units s ≤ (frameWork E (o₁ ++ o₂)).units s) ∧
      (frameWork E (v₁ ++ v₂)).hits ≤ (frameWork E (o₁ ++ o₂)).hits := by
  refine ⟨fun s => ?_, ?_⟩
  · rw [frameWork_append_units, frameWork_append_units]
    have := (h₁.1 s).2; have := (h₂.1 s).2; omega
  · rw [frameWork_append_hits, frameWork_append_hits]
    have := h₁.2; have := h₂.2; omega

/-- **Strictness survives through units.** A part strictly smaller on the units of some stage, next to a part no
larger on units, gives a page strictly smaller on the units of that stage.
-/
theorem someLt_append_units {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (h₂ : ∀ s, (frameWork E v₂).units s ≤ (frameWork E o₂).units s)
    (h : ∃ s, (frameWork E v₁).units s < (frameWork E o₁).units s) :
    ∃ s, (frameWork E (v₁ ++ v₂)).units s < (frameWork E (o₁ ++ o₂)).units s := by
  obtain ⟨s, hs⟩ := h
  refine ⟨s, ?_⟩
  rw [frameWork_append_units, frameWork_append_units]
  have := h₂ s; omega

/-! ## Page dominance from the stage-set form -/

/-- **The union check composes.** If each part passes `unionLe` against its original, the page does. -/
theorem unionLe_append {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (h₁ : unionLe E v₁ o₁ = true) (h₂ : unionLe E v₂ o₂ = true) :
    unionLe E (v₁ ++ v₂) (o₁ ++ o₂) = true := by
  simp only [unionLe, Bool.and_eq_true, List.all_eq_true, Bool.or_eq_true, Bool.not_eq_true',
    decide_eq_false_iff_not, decide_eq_true_eq] at h₁ h₂ ⊢
  refine ⟨fun s hs => ?_, by simp only [FrameIn.append_hits]; omega⟩
  obtain ⟨⟨t₁, u₁⟩, p₁⟩ := h₁.1 s hs
  obtain ⟨⟨t₂, u₂⟩, p₂⟩ := h₂.1 s hs
  have hu₁ := frameWork_append_units E v₁ v₂ s
  have hu₂ := frameWork_append_units E o₁ o₂ s
  simp only [frameWork] at hu₁ hu₂
  refine ⟨⟨?_, by omega⟩, by rw [forcedPasses_append, forcedPasses_append]; omega⟩
  rw [touched_append, touched_append]
  by_cases a : s ∈ touched E v₁ <;> by_cases b : s ∈ touched E v₂ <;> simp_all

/-- **Page dominance from per-part union checks.** -/
theorem frame_le_append {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (h₁ : unionLe E v₁ o₁ = true) (h₂ : unionLe E v₂ o₂ = true) :
    (frameWork E (v₁ ++ v₂)).le (frameWork E (o₁ ++ o₂)) :=
  frame_le_union E (unionLe_append E h₁ h₂)

/-- **Strict page dominance from per-part union checks.** With both union checks and part 1 strictly smaller on the
units of some stage or on hit tests, the page is strictly smaller.
-/
theorem frame_lt_append {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (h₁ : unionLe E v₁ o₁ = true) (h₂ : unionLe E v₂ o₂ = true)
    (h : (∃ s, (frameWork E v₁).units s < (frameWork E o₁).units s) ∨ v₁.hits < o₁.hits) :
    (frameWork E (v₁ ++ v₂)).lt (frameWork E (o₁ ++ o₂)) := by
  have hle₂ := frame_le_union E h₂
  refine ⟨frame_le_append E h₁ h₂, ?_⟩
  rcases h with h | h
  · obtain ⟨s, hs⟩ := someLt_append_units E (fun s => (hle₂.1 s).2) h
    exact .inl ⟨s, .inr hs⟩
  · refine .inr ?_
    simp only [frameWork_append_hits]
    have := hle₂.2; simp only [frameWork] at this ⊢; omega

/-- Pairwise covers concatenate. -/
theorem coverB_append {P M : Type} (E : Engine P M) :
    ∀ {l₁ m₁ l₂ m₂ : List (Change P)}, coverB E l₁ m₁ = true → coverB E l₂ m₂ = true →
      coverB E (l₁ ++ l₂) (m₁ ++ m₂) = true
  | [], [], _, _, _, h₂ => h₂
  | [], _ :: _, _, _, h, _ => by simp [coverB] at h
  | _ :: _, [], _, _, h, _ => by simp [coverB] at h
  | _ :: _, _ :: _, _, _, h, h₂ => by
    simp only [coverB, List.cons_append, Bool.and_eq_true] at h ⊢
    exact ⟨h.1, coverB_append E h.2 h₂⟩

/-- **Page dominance from per-part covers.** Each variant part covered by a sub-multiset of its original part's
changes, with no more callbacks, forced passes, hit tests or compositor animations, gives page dominance; the page
cover is the concatenation, partitioned by part.
-/
theorem frame_le_append_cover {P M : Type} (E : Engine P M) {v₁ o₁ v₂ o₂ : FrameIn P}
    (m₁ r₁ m₂ r₂ : List (Change P))
    (hp₁ : (m₁ ++ r₁).Perm o₁.changes) (hc₁ : coverB E v₁.changes m₁ = true)
    (hs₁ : v₁.script ≤ o₁.script) (hfs₁ : v₁.forcedStyle ≤ o₁.forcedStyle)
    (hfl₁ : v₁.forcedLayout ≤ o₁.forcedLayout) (hh₁ : v₁.hits ≤ o₁.hits) (ha₁ : v₁.compAnims ≤ o₁.compAnims)
    (hp₂ : (m₂ ++ r₂).Perm o₂.changes) (hc₂ : coverB E v₂.changes m₂ = true)
    (hs₂ : v₂.script ≤ o₂.script) (hfs₂ : v₂.forcedStyle ≤ o₂.forcedStyle)
    (hfl₂ : v₂.forcedLayout ≤ o₂.forcedLayout) (hh₂ : v₂.hits ≤ o₂.hits) (ha₂ : v₂.compAnims ≤ o₂.compAnims) :
    (frameWork E (v₁ ++ v₂)).le (frameWork E (o₁ ++ o₂)) := by
  have hperm : ((m₁ ++ m₂) ++ (r₁ ++ r₂)).Perm (o₁ ++ o₂).changes := by
    rw [FrameIn.append_changes]
    have hmid : (m₂ ++ (r₁ ++ r₂)).Perm (r₁ ++ (m₂ ++ r₂)) := by
      rw [← List.append_assoc, ← List.append_assoc]
      exact List.perm_append_comm.append_right r₂
    have h : ((m₁ ++ m₂) ++ (r₁ ++ r₂)).Perm ((m₁ ++ r₁) ++ (m₂ ++ r₂)) := by
      rw [List.append_assoc, List.append_assoc]
      exact hmid.append_left m₁
    exact h.trans (hp₁.append hp₂)
  exact frame_le_of_cover E (m₁ ++ m₂) (r₁ ++ r₂) hperm (by simpa using coverB_append E hc₁ hc₂)
    (by simp only [FrameIn.append_script]; omega) (by simp only [FrameIn.append_forcedStyle]; omega)
    (by simp only [FrameIn.append_forcedLayout]; omega) (by simp only [FrameIn.append_hits]; omega)
    (by simp only [FrameIn.append_compAnims]; omega)

/-! ## Lego: swapping one part's variant -/

/-- Part `p`'s variant set to `x`, every other part's variant kept. -/
def swapSel {V : Type} (sel : Nat → V) (p : Nat) (x : V) : Nat → V := fun i => if i = p then x else sel i

/-- An observable per part (frame, arm) reads only the variants of the parts it is not independent of: two variant
choices that agree on every part `i` with `¬ Indep i j` give part `j` the same observable.
-/
def ReadsOnly {V α : Type} (Indep : Nat → Nat → Prop) (obs : Nat → (Nat → V) → α) : Prop :=
  ∀ j (sel sel' : Nat → V), (∀ i, ¬ Indep i j → sel i = sel' i) → obs j sel = obs j sel'

/-- **Lego swap is sound.** If every part's frame and arm read only the variants of parts they are not independent
of, and part `p` is independent of every other part, then swapping `p`'s variant leaves every other part's frame,
frame work under every engine, and arm unchanged.
-/
theorem lego_swap_sound {V P M : Type} (Indep : Nat → Nat → Prop) (frame : Nat → (Nat → V) → FrameIn P)
    (arm : Nat → (Nat → V) → PartArm) (E : Engine P M) (p : Nat) (x : V) (sel : Nat → V)
    (hf : ReadsOnly Indep frame) (ha : ReadsOnly Indep arm) (hind : ∀ q, q ≠ p → Indep p q) :
    ∀ q, q ≠ p → frame q (swapSel sel p x) = frame q sel ∧
      frameWork E (frame q (swapSel sel p x)) = frameWork E (frame q sel) ∧
      arm q (swapSel sel p x) = arm q sel := by
  intro q hq
  have hagree : ∀ i, ¬ Indep i q → swapSel sel p x i = sel i := by
    intro i hi
    unfold swapSel
    split
    · next h => subst h; exact absurd (hind q hq) hi
    · rfl
  have h1 := hf q _ _ hagree
  exact ⟨h1, by rw [h1], ha q _ _ hagree⟩

/-- The page frame of parts `0, …, n-1`: the parts' frames appended in order. -/
def pageOf {P : Type} : Nat → (Nat → FrameIn P) → FrameIn P
  | 0, _ => FrameIn.empty
  | n + 1, F => pageOf n F ++ F n

/-- Page frames of part functions that agree below `n` are equal. -/
theorem pageOf_congr {P : Type} : ∀ (n : Nat) {F G : Nat → FrameIn P}, (∀ j, j < n → F j = G j) →
    pageOf n F = pageOf n G
  | 0, _, _, _ => rfl
  | n + 1, _, _, h => by
    simp only [pageOf, pageOf_congr n (fun j hj => h j (by omega)), h n (by omega)]

/-- **Swap accounting on units.** Under the hypotheses of `lego_swap_sound`, for a part `p < n` the page's units
after the swap plus `p`'s units before equal the page's units before plus `p`'s units after, at every stage.

A swap of an independent part moves the page's units by exactly that part's change. -/
theorem lego_swap_units {V P M : Type} (Indep : Nat → Nat → Prop) (frame : Nat → (Nat → V) → FrameIn P)
    (E : Engine P M) (n p : Nat) (x : V) (sel : Nat → V) (s : Stage)
    (hf : ReadsOnly Indep frame) (hind : ∀ q, q ≠ p → Indep p q) (hp : p < n) :
    (frameWork E (pageOf n fun j => frame j (swapSel sel p x))).units s + (frameWork E (frame p sel)).units s =
      (frameWork E (pageOf n fun j => frame j sel)).units s + (frameWork E (frame p (swapSel sel p x))).units s := by
  have hq : ∀ q, q ≠ p → frame q (swapSel sel p x) = frame q sel := fun q hq =>
    (lego_swap_sound Indep frame (fun _ _ => ⟨0, fun _ => []⟩) E p x sel hf (fun _ _ _ _ => rfl) hind q hq).1
  induction n with
  | zero => omega
  | succ n ih =>
    simp only [pageOf, frameWork_append_units]
    rcases Nat.lt_succ_iff_lt_or_eq.mp hp with h | h
    · rw [hq n (by omega)]; have := ih h; omega
    · subst h
      rw [pageOf_congr p (F := fun j => frame j (swapSel sel p x)) (G := fun j => frame j sel)
        (fun j hj => hq j (by omega))]
      omega

/-- A pair in the zip of two maps of one list is the pair of images of one element. -/
theorem mem_zip_map_self {α β : Type} (f g : α → β) :
    ∀ (l : List α) (q : β × β), q ∈ (l.map f).zip (l.map g) → ∃ a ∈ l, q = (f a, g a)
  | [], _, h => by simp at h
  | a :: l, q, h => by
    simp only [List.map_cons, List.zip_cons_cons, List.mem_cons] at h
    rcases h with h | h
    · exact ⟨a, by simp, h⟩
    · obtain ⟨b, hb, rfl⟩ := mem_zip_map_self f g l q h
      exact ⟨b, by simp [hb], rfl⟩

/-- **Swap keeps the visible page** when the swapped part passes its own gate. Under the hypotheses of
`lego_swap_sound`, if part `p`'s arm keeps its band height and its visible scene at every offset, the visible page
scene of parts `0, …, n-1` is unchanged, from every start offset.
-/
theorem lego_swap_visible {V : Type} (Indep : Nat → Nat → Prop) (arm : Nat → (Nat → V) → PartArm) (vp : Rect)
    (n p : Nat) (x : V) (sel : Nat → V) (y : Rat)
    (ha : ReadsOnly Indep arm) (hind : ∀ q, q ≠ p → Indep p q)
    (hh : (arm p (swapSel sel p x)).height = (arm p sel).height)
    (hs : ∀ y', visible vp ((arm p (swapSel sel p x)).scene y') = visible vp ((arm p sel).scene y')) :
    visible vp (stackScene y ((List.range n).map fun j => arm j (swapSel sel p x))) =
      visible vp (stackScene y ((List.range n).map fun j => arm j sel)) := by
  have hq : ∀ q, q ≠ p → arm q (swapSel sel p x) = arm q sel := fun q hq =>
    (lego_swap_sound Indep (fun _ _ => (FrameIn.empty : FrameIn Unit)) arm (⟨(), fun _ => [], [], []⟩ :
      Engine Unit Unit) p x sel (fun _ _ _ _ => rfl) ha hind q hq).2.2
  have hpart : ∀ j, (arm j (swapSel sel p x)).height = (arm j sel).height ∧
      ∀ y', visible vp ((arm j (swapSel sel p x)).scene y') = visible vp ((arm j sel).scene y') := by
    intro j
    by_cases hj : j = p
    · subst hj; exact ⟨hh, hs⟩
    · rw [hq j hj]; exact ⟨rfl, fun _ => rfl⟩
  refine visible_append_of_boxes_eq vp y (by simp) ?_
  intro q hq
  obtain ⟨j, -, rfl⟩ := mem_zip_map_self _ _ _ q hq
  exact hpart j

end Fw.Engine
