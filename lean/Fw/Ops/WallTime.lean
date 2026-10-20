/-!
# Wall time of a land: a shared prep job cannot beat parallel legs (task land-fwcore-once, closed negative)

Jobs that run in parallel finish at the maximum of their times (`wall`). A land with a lean change
used to build fwcore in each of its legs, side by side, so the build cost one build of latency.
The prep design builds once in a serial job before the legs: the legs then start after
prep setup + build + upload, and each pays a download instead of the build.

A leg is `(s, r)`: its setup and its remaining work. Building in the leg gives time `s + b + r`.
With a prep job the leg takes `s + d + r`, after the prep job `P + b + U`. Proved:
`wallPrep_eq` (the prep wall is the parallel wall plus `P + U + d`) and `wallPrep_ge`
(so it is never shorter). MEASURED, runs 39369049545 and 39370530353: 477 s against 553 s.
-/
namespace Fw.Ops.WallTime

/-- Wall time of jobs that run in parallel: the longest one (first job, then the rest). -/
def wall (x : Nat) (xs : List Nat) : Nat := xs.foldl max x

theorem foldl_max_add (b : Nat) : ∀ (xs : List Nat) (a : Nat),
    (xs.map (· + b)).foldl max (a + b) = xs.foldl max a + b
  | [], a => rfl
  | x :: xs, a => by
    simp only [List.map_cons, List.foldl_cons]
    rw [Nat.add_max_add_right a x b]
    exact foldl_max_add b xs (max a x)

/-- Wall of the parallel design: every leg builds (`s + b + r`). -/
def wallPar (b : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) : Nat :=
  wall (l.1 + b + l.2) (ls.map fun p => p.1 + b + p.2)

/-- Wall of the prep design: prep setup `P`, build `b`, upload `U`, then legs `s + d + r`. -/
def wallPrep (P b U d : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) : Nat :=
  (P + b + U) + wall (l.1 + d + l.2) (ls.map fun p => p.1 + d + p.2)

/-- Both walls are the longest `s + r` plus their own overhead: `b` for building legs. -/
theorem wallPar_eq (b : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) :
    wallPar b l ls = wall (l.1 + l.2) (ls.map fun p => p.1 + p.2) + b := by
  unfold wallPar wall
  have e : (ls.map fun p => p.1 + b + p.2) = (ls.map fun p => p.1 + p.2).map (· + b) := by
    simp only [List.map_map, Function.comp_def]
    exact List.map_congr_left fun p _ => by omega
  rw [e, show l.1 + b + l.2 = (l.1 + l.2) + b by omega]
  exact foldl_max_add b _ _

/-- The prep wall: the longest `s + r`, plus the download `d` and the serial prefix `P + b + U`. -/
theorem wallPrep_eq (P b U d : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) :
    wallPrep P b U d l ls = wall (l.1 + l.2) (ls.map fun p => p.1 + p.2) + d + (P + b + U) := by
  unfold wallPrep wall
  have e : (ls.map fun p => p.1 + d + p.2) = (ls.map fun p => p.1 + p.2).map (· + d) := by
    simp only [List.map_map, Function.comp_def]
    exact List.map_congr_left fun p _ => by omega
  rw [e, show l.1 + d + l.2 = (l.1 + l.2) + d by omega, foldl_max_add d _ _]
  omega

/-- Prep never wins: it equals the parallel wall plus `P + U + d`, so it is at least the parallel
wall. -/
theorem wallPrep_ge (P b U d : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) :
    wallPar b l ls ≤ wallPrep P b U d l ls := by
  rw [wallPar_eq, wallPrep_eq]; omega

/-- It ties only with no setup, upload or download cost. -/
theorem wallPrep_eq_par_iff (P b U d : Nat) (l : Nat × Nat) (ls : List (Nat × Nat)) :
    wallPrep P b U d l ls = wallPar b l ls ↔ P + U + d = 0 := by
  rw [wallPar_eq, wallPrep_eq]; omega

-- Measured: legs 4 x ~260 s build, prep job 321 s (setup 46, build 259, upload 9) + legs up to 211 s.
#guard (477 : Nat) < 553
#guard 553 - 477 = 76

end Fw.Ops.WallTime
