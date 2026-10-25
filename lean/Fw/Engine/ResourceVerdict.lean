import Fw.Engine.Resource

namespace Fw.Engine.Resource

structure Effect where
  sign : Sign
  bound : Option (Nat × String)
  src : String
deriving Repr, Inhabited

structure Footprint where
  flag : String
  eng : Eng
  effects : List (Res × Effect)
  peak : Option Nat
deriving Repr, Inhabited

def Footprint.sign (fp : Footprint) (r : Res) : Sign := ((fp.effects.find? (·.1 == r)).map (·.2.sign)).getD .unknown

inductive Verdict where
  | win | trade | neutral | overBudget | open
deriving Repr, DecidableEq, Inhabited

def Verdict.name : Verdict → String
  | .win => "win" | .trade => "trade" | .neutral => "neutral" | .overBudget => "overBudget" | .open => "open"

def gated : List Res := Res.all.filter Res.gated

def memFit (B : Nat) (s : Sign) (peak : Option Nat) : Option Bool :=
  match s with
  | .down | .same => some true
  | .up => peak.map (memFits B)
  | .unknown => none

def verdict (B : Nat) (fp : Footprint) : Verdict :=
  if gated.any (fp.sign · == .up) then .trade
  else if gated.any (fp.sign · == .unknown) then .open
  else if !gated.any (fp.sign · == .down) then .neutral
  else match memFit B (fp.sign .gpuMem) fp.peak with
    | some true => .win
    | some false => .overBudget
    | none => .open

theorem trade_iff (B : Nat) (fp : Footprint) : verdict B fp = .trade ↔ ∃ r ∈ gated, fp.sign r = .up := by
  unfold verdict
  by_cases h : gated.any (fp.sign · == .up) = true
  · simp only [h, ite_true, true_iff]
    obtain ⟨r, hr, he⟩ := List.any_eq_true.mp h
    exact ⟨r, hr, by simpa using he⟩
  · have hn : ¬ ∃ r ∈ gated, fp.sign r = .up := fun ⟨r, hr, he⟩ =>
      h (List.any_eq_true.mpr ⟨r, hr, by simpa using he⟩)
    simp only [h, Bool.false_eq_true, ite_false, hn, iff_false]
    split
    · simp
    · split
      · simp
      · split <;> simp

theorem win_iff (B : Nat) (fp : Footprint) :
    verdict B fp = .win ↔ (∀ r ∈ gated, fp.sign r = .down ∨ fp.sign r = .same) ∧ (∃ r ∈ gated, fp.sign r = .down) ∧
      memFit B (fp.sign .gpuMem) fp.peak = some true := by
  have hs : ∀ r, (fp.sign r = .down ∨ fp.sign r = .same) ↔ (fp.sign r ≠ .up ∧ fp.sign r ≠ .unknown) := by
    intro r; cases fp.sign r <;> simp
  unfold verdict
  by_cases h1 : gated.any (fp.sign · == .up) = true
  · obtain ⟨r, hr, he⟩ := List.any_eq_true.mp h1
    simp only [h1, ite_true, reduceCtorEq, false_iff]
    intro ⟨ha, _⟩; have := (hs r).mp (ha r hr); simp_all
  · by_cases h2 : gated.any (fp.sign · == .unknown) = true
    · obtain ⟨r, hr, he⟩ := List.any_eq_true.mp h2
      simp only [h1, h2, Bool.false_eq_true, ite_false, ite_true, reduceCtorEq, false_iff]
      intro ⟨ha, _⟩; have := (hs r).mp (ha r hr); simp_all
    · have hall : ∀ r ∈ gated, fp.sign r = .down ∨ fp.sign r = .same := by
        intro r hr; rw [hs]
        exact ⟨fun he => h1 (List.any_eq_true.mpr ⟨r, hr, by simp [he]⟩),
          fun he => h2 (List.any_eq_true.mpr ⟨r, hr, by simp [he]⟩)⟩
      simp only [h1, h2, Bool.false_eq_true, ite_false]
      by_cases h3 : gated.any (fp.sign · == .down) = true
      · have hd : ∃ r ∈ gated, fp.sign r = .down := by
          obtain ⟨r, hr, he⟩ := List.any_eq_true.mp h3; exact ⟨r, hr, by simpa using he⟩
        simp only [h3, Bool.not_true, Bool.false_eq_true, ite_false]
        constructor
        · intro hw; refine ⟨hall, hd, ?_⟩; split at hw <;> simp_all
        · intro ⟨_, _, hm⟩; simp [hm]
      · have hd : ¬ ∃ r ∈ gated, fp.sign r = .down := fun ⟨r, hr, he⟩ =>
          h3 (List.any_eq_true.mpr ⟨r, hr, by simp [he]⟩)
        simp only [h3, Bool.not_false, ite_true, reduceCtorEq, false_iff]
        intro ⟨_, h, _⟩; exact hd h

theorem memory_only_not_trade (B : Nat) (fp : Footprint) (h : ∀ r ∈ gated, fp.sign r ≠ .up) : verdict B fp ≠ .trade :=
  fun ht => by obtain ⟨r, hr, he⟩ := (trade_iff B fp).mp ht; exact h r hr he

theorem memory_cost_win (B : Nat) (fp : Footprint) (hg : ∀ r ∈ gated, fp.sign r = .down ∨ fp.sign r = .same)
    (hd : ∃ r ∈ gated, fp.sign r = .down) (hm : fp.sign .gpuMem = .up) (peak : Nat) (hp : fp.peak = some peak)
    (hB : peak ≤ B) : verdict B fp = .win :=
  (win_iff B fp).mpr ⟨hg, hd, by simp [memFit, hm, hp, memFits, hB]⟩

theorem over_budget_not_win (B : Nat) (fp : Footprint) (hm : fp.sign .gpuMem = .up) (peak : Nat)
    (hp : fp.peak = some peak) (hB : B < peak) : verdict B fp ≠ .win := by
  intro hw
  have := ((win_iff B fp).mp hw).2.2
  simp [memFit, hm, hp, memFits] at this; omega

theorem win_mono_budget {B B' : Nat} (hB : B ≤ B') (fp : Footprint) (h : verdict B fp = .win) : verdict B' fp = .win := by
  obtain ⟨hg, hd, hm⟩ := (win_iff B fp).mp h
  refine (win_iff B' fp).mpr ⟨hg, hd, ?_⟩
  unfold memFit at hm ⊢
  split at hm
  · rfl
  · rfl
  · cases hp : fp.peak with
    | none => simp [hp] at hm
    | some p => simp [hp, memFits] at hm ⊢; omega
  · simp at hm

theorem open_of_unknown (B : Nat) (fp : Footprint) (h : ∀ r ∈ gated, fp.sign r ≠ .up) (r : Res) (hr : r ∈ gated)
    (hu : fp.sign r = .unknown) : verdict B fp = .open := by
  have h1 : gated.any (fp.sign · == .up) = false := by
    rw [List.any_eq_false]; intro x hx; simpa using h x hx
  have h2 : gated.any (fp.sign · == .unknown) = true := List.any_eq_true.mpr ⟨r, hr, by simp [hu]⟩
  simp [verdict, h1, h2]

def ofSigns (flag : String) (e : Eng) (ss : List (Res × Sign)) (peak : Option Nat) : Footprint :=
  ⟨flag, e, ss.map fun (r, s) => (r, ⟨s, none, ""⟩), peak⟩

def gatedAt (s : Sign) : List (Res × Sign) := gated.map (·, s)

#guard gated.length == 7
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: (.gpuMem, .same) :: gatedAt .same) none) == .win
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: (.gpuMem, .up) :: gatedAt .same) (some budgetB)) == .win
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: (.gpuMem, .up) :: gatedAt .same) (some (budgetB + 1)))
  == .overBudget
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: (.gpuMem, .up) :: gatedAt .same) none) == .open
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: (.gpuMem, .unknown) :: gatedAt .same) none) == .open
#guard verdict budgetB (ofSigns "x" .webkit ((.repaint, .up) :: (.style, .down) :: gatedAt .same) none) == .trade
#guard verdict budgetB (ofSigns "x" .webkit ((.layers, .up) :: (.gpuMem, .up) :: gatedAt .same) (some 1)) == .neutral
#guard verdict budgetB (ofSigns "x" .webkit [(.style, .down)] none) == .open
#guard memFit budgetB .up (some 1) == some true && memFit budgetB .unknown (some 1) == none
#guard verdict budgetB (ofSigns "x" .webkit ((.style, .down) :: gatedAt .same) none) == .open

end Fw.Engine.Resource
