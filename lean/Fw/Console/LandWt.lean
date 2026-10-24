import Lean
/-!
# Which land worktree a dry land starts from

A land checks its commit out in one of the pool worktrees `.claude/land-wt/<n>`; each keeps its own `.lake`. The lake
step of the land rebuilds the Lean modules whose sources differ from the state in that `.lake`, so the step costs
what the checkout changes: dry-land spans (`.fw-console/timings.jsonl`, `lake.built`, task land-wt-lake-rebuilds)
show a median of 3.0 s at 0 modules built (n 100), 10.7 s at 1-7 (n 48) and 18.9 s at 8 or more (n 56), and commit
2e54fbe built 24, 0 and 24 modules in three dry lands because each took the first free worktree.

The rule: among the free worktrees take the one whose last checkout differs least from the commit. `dist` is the number
of Lean build inputs (`*.lean`, `lakefile*`, `lean-toolchain`, `lake-manifest*` under `lean/`) that differ between
the worktree's HEAD and the commit; `none` is a worktree with no checkout yet. The distance is a proxy for rebuilt
modules (INFERRED: zero differing inputs rebuild nothing, more inputs rebuild at least as many modules).
-/
namespace Fw.Console.LandWt
open Lean

/-- A free pool worktree: its number and the distance of its last checkout from the commit. -/
structure Slot where
  idx : Nat
  dist : Option Nat
deriving Repr, DecidableEq

/-- `a` is preferred to `b`: a known distance beats `none`, then the smaller distance, then the lower number. -/
def before (a b : Slot) : Bool :=
  match a.dist, b.dist with
  | some x, some y => decide (x < y) || (x == y && decide (a.idx < b.idx))
  | some _, none => true
  | none, some _ => false
  | none, none => decide (a.idx < b.idx)

def pickAux (acc : Slot) : List Slot → Slot
  | [] => acc
  | y :: ys => pickAux (if before y acc then y else acc) ys

/-- The worktree number a dry land claims first; `none` when no worktree is free. -/
def pick : List Slot → Option Nat
  | [] => none
  | x :: xs => some (pickAux x xs).idx

/-- Today's rule: the lowest free number. -/
def firstFree : List Slot → Option Slot
  | [] => none
  | x :: xs => some (xs.foldl (fun a y => if y.idx < a.idx then y else a) x)

theorem before_trans (a b c : Slot) (h1 : before a b = true) (h2 : before b c = true) : before a c = true := by
  obtain ⟨i, x⟩ := a; obtain ⟨j, y⟩ := b; obtain ⟨k, z⟩ := c
  cases x <;> cases y <;> cases z <;> simp_all [before] <;> omega

theorem before_irrefl (a : Slot) : before a a = false := by
  obtain ⟨i, x⟩ := a
  cases x <;> simp [before]

theorem bool_false_of {b : Bool} (h : b = true → False) : b = false := by
  cases b <;> simp_all

theorem pickAux_mem (acc : Slot) (l : List Slot) : pickAux acc l ∈ acc :: l := by
  induction l generalizing acc with
  | nil => simp [pickAux]
  | cons y ys ih =>
    show pickAux (if before y acc then y else acc) ys ∈ acc :: y :: ys
    cases hb : before y acc
    · have h := ih acc
      simp only [Bool.false_eq_true, ite_false, List.mem_cons] at h ⊢
      rcases h with h | h
      · exact Or.inl h
      · exact Or.inr (Or.inr h)
    · have h := ih y
      simp only [ite_true, List.mem_cons] at h ⊢
      rcases h with h | h
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)

/-- The pick is the start value or preferred to it. -/
theorem pickAux_le (acc : Slot) (l : List Slot) : pickAux acc l = acc ∨ before (pickAux acc l) acc = true := by
  induction l generalizing acc with
  | nil => simp [pickAux]
  | cons y ys ih =>
    show pickAux (if before y acc then y else acc) ys = acc ∨ before (pickAux (if before y acc then y else acc) ys) acc = true
    cases hb : before y acc
    · simp only [Bool.false_eq_true, ite_false]; exact ih acc
    · simp only [ite_true]
      rcases ih y with h | h
      · right; rw [h]; exact hb
      · right; exact before_trans _ _ _ h hb

/-- **Nobody beats the pick.** No free worktree is preferred to the one chosen. -/
theorem pickAux_best (acc : Slot) (l : List Slot) : ∀ s ∈ acc :: l, before s (pickAux acc l) = false := by
  induction l generalizing acc with
  | nil => intro s hs; simp at hs; subst hs; simp [pickAux, before_irrefl]
  | cons y ys ih =>
    intro s hs
    show before s (pickAux (if before y acc then y else acc) ys) = false
    cases hb : before y acc
    · simp only [Bool.false_eq_true, ite_false]
      rcases List.mem_cons.mp hs with h | hs'
      · subst h; exact ih _ _ (by simp)
      · rcases List.mem_cons.mp hs' with h | hs''
        · subst h
          apply bool_false_of
          intro hc
          rcases pickAux_le acc ys with h | h
          · rw [h] at hc; simp [hb] at hc
          · have := before_trans _ _ _ hc h
            simp [hb] at this
        · exact ih _ _ (by simp [hs''])
    · simp only [ite_true]
      rcases List.mem_cons.mp hs with h | hs'
      · subst h
        apply bool_false_of
        intro hc
        have h1 := before_trans _ _ _ hb hc
        have h2 := ih y y (by simp)
        simp [h1] at h2
      · exact ih y s hs'

theorem pick_mem (l : List Slot) (n : Nat) (h : pick l = some n) : ∃ s ∈ l, s.idx = n := by
  cases l with
  | nil => simp [pick] at h
  | cons x xs =>
    simp only [pick, Option.some.injEq] at h
    exact ⟨_, pickAux_mem x xs, h⟩

theorem pick_none_iff (l : List Slot) : pick l = none ↔ l = [] := by
  cases l <;> simp [pick]

/-- **OR-branch: a worktree already at the commit is taken.** If one free worktree has distance 0, the pick has
distance 0: no module is rebuilt. -/
theorem pick_zero (x : Slot) (xs : List Slot) (z : Slot) (hz : z ∈ x :: xs) (h0 : z.dist = some 0) :
    (pickAux x xs).dist = some 0 := by
  have hb := pickAux_best x xs z hz
  have hm := pickAux_mem x xs
  generalize pickAux x xs = r at hb hm ⊢
  obtain ⟨i, d⟩ := z; obtain ⟨j, e⟩ := r
  simp only at h0; subst h0
  cases e <;> simp_all [before] <;> omega

/-- **OR-branch: a known distance beats a fresh worktree.** The pick has no checkout (`none`) only when every free
worktree has none. -/
theorem pick_none_only (x : Slot) (xs : List Slot) (h : (pickAux x xs).dist = none) :
    ∀ s ∈ x :: xs, s.dist = none := by
  intro s hs
  have hb := pickAux_best x xs s hs
  generalize pickAux x xs = r at hb h
  obtain ⟨i, d⟩ := s; obtain ⟨j, e⟩ := r
  simp only at h; subst h
  cases d <;> simp_all [before]

/-- **OR-branch: the pick is never farther than any known worktree.** -/
theorem pick_dist_le (x : Slot) (xs : List Slot) (s : Slot) (hs : s ∈ x :: xs) (d : Nat) (hd : s.dist = some d) :
    ∃ c, (pickAux x xs).dist = some c ∧ c ≤ d := by
  have hb := pickAux_best x xs s hs
  generalize pickAux x xs = r at hb
  obtain ⟨i, e⟩ := s; obtain ⟨j, f⟩ := r
  simp only at hd; subst hd
  cases f <;> simp_all [before]

/-- **OR-branch: ties go to the lower number.** A worktree at the same distance as the pick has a number at least as
large. -/
theorem pick_tie (x : Slot) (xs : List Slot) (s : Slot) (hs : s ∈ x :: xs)
    (h : s.dist = (pickAux x xs).dist) : (pickAux x xs).idx ≤ s.idx := by
  have hb := pickAux_best x xs s hs
  generalize pickAux x xs = r at hb h
  obtain ⟨i, e⟩ := s; obtain ⟨j, f⟩ := r
  simp only at h; subst h
  cases e <;> simp_all [before] <;> omega

theorem foldl_mem (l : List Slot) (a : Slot) :
    l.foldl (fun a y => if y.idx < a.idx then y else a) a ∈ a :: l := by
  induction l generalizing a with
  | nil => simp
  | cons y ys ih =>
    simp only [List.foldl]
    have h := ih (if y.idx < a.idx then y else a)
    by_cases hc : y.idx < a.idx
    · simp only [hc, ite_true, List.mem_cons] at h ⊢
      rcases h with h | h
      · exact Or.inr (Or.inl h)
      · exact Or.inr (Or.inr h)
    · simp only [hc, ite_false, List.mem_cons] at h ⊢
      rcases h with h | h
      · exact Or.inl h
      · exact Or.inr (Or.inr h)

/-- **Never worse than today.** The pick is at least as near as the lowest free number, whenever that one has a known
distance. -/
theorem pick_le_firstFree (x : Slot) (xs : List Slot) (f : Slot) (hf : firstFree (x :: xs) = some f) (d : Nat)
    (hd : f.dist = some d) : ∃ c, (pickAux x xs).dist = some c ∧ c ≤ d := by
  simp only [firstFree, Option.some.injEq] at hf
  subst hf
  exact pick_dist_le x xs _ (foldl_mem xs x) d hd

/-! ## Golden: the measured dry lands

`packages/contracts/golden/console/land-wt.jsonl`: `request.slots` are the free worktrees with the distance of their last
checkout from the commit (`null` when never checked out), `response.pick` the worktree number or `null`. The rows
2e54fbe, 72f52a1 are replayed from `.fw-console/timings.jsonl` spans (cutoff: last dry-total start 1792806731169): the
first free worktree (0) was taken and built 24 and 25 modules, the pick would take worktree 1. -/

def slotJson (s : Slot) : Json := Json.mkObj [("idx", toJson s.idx), ("dist", toJson s.dist)]

def cases : List (String × List Slot) :=
  [("2e54fbe third dry land (start 1792805509801, built 24 in worktree 0): worktree 1 holds the previous 2e54fbe checkout",
      [⟨0, some 4⟩, ⟨1, some 0⟩]),
   ("72f52a1 dry land (start 1792806731169, built 25 in worktree 0): worktree 1 is one input away",
      [⟨0, some 4⟩, ⟨1, some 1⟩]),
   ("2e54fbe second dry land (start 1792805275634): only worktree 1 free", [⟨1, some 4⟩]),
   ("tie: the lower number", [⟨2, some 3⟩, ⟨0, some 3⟩, ⟨1, some 3⟩]),
   ("a known distance beats a worktree with no checkout", [⟨0, none⟩, ⟨1, some 40⟩]),
   ("all fresh: the lowest number", [⟨2, none⟩, ⟨1, none⟩]),
   ("distance 0 beats a lower number", [⟨0, some 1⟩, ⟨3, some 0⟩, ⟨2, some 5⟩]),
   ("no free worktree", [])]

def goldenText : String :=
  String.join (cases.map fun (n, ss) => (Json.mkObj [("name", Json.str n),
    ("request", Json.mkObj [("slots", Json.arr (ss.map slotJson).toArray)]),
    ("response", Json.mkObj [("pick", toJson (pick ss))])]).compress ++ "\n")

#guard pick [⟨0, some 4⟩, ⟨1, some 0⟩] == some 1
#guard pick [⟨2, some 3⟩, ⟨0, some 3⟩, ⟨1, some 3⟩] == some 0
#guard pick [⟨0, none⟩, ⟨1, some 40⟩] == some 1
#guard pick [⟨2, none⟩, ⟨1, none⟩] == some 1
#guard pick [] == none

/-- Regenerate the golden, or check it with `--check`. -/
def gen (args : List String) : IO Unit := do
  let path := "../packages/contracts/golden/console/land-wt.jsonl"
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != goldenText then
      throw (IO.userError s!"land-wt: {path} is stale; regenerate with Fw.Console.LandWt.gen []")
    IO.println s!"land-wt: {path} equals the Lean output, {cases.length} lines"
  else
    IO.FS.writeFile path goldenText

end Fw.Console.LandWt
