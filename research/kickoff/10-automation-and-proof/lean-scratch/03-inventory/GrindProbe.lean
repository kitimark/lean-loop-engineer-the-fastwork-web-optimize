import Auto
open Auto.DeviceQueue Auto.Console Auto.ArtifactKey
-- Each line: can `grind` (with the definitions unfolded) close the goal on its own?
theorem g1 (t : Nat) (a b c : Job) (h1 : before t a b = true) (h2 : before t b c = true) :
    before t a c = true := by grind [before]
theorem g2 (t : Nat) (j k : Job) : before t j k = true ∨ before t k j = true := by grind [before]
theorem g3 (t : Nat) (j k : Job) (hage : j.enq + A * j.base ≤ t) (hseq : j.seq < k.seq) :
    before t j k = true := by grind [before, eff, A]
theorem g4 (s : State) (e : Event) : (apply (apply s e).1 e).1 = (apply s e).1 := by grind [apply]
theorem g5 (p : Phone) (t : Nat) (r : Job × Nat) (h : p.running = some r) : dispatch p t = p := by
  grind [dispatch]
theorem g6 (v : Input → Val) (i : Input) (w : Val) (hw : w ≠ v i) (a : Artifact) (hi : i ∈ a.deps) :
    key v a ≠ key (update v i w) a := by grind [key, update, List.map_inj_left]
theorem g7 (b : Body) : stepNext (some .answered) b = none := by grind [stepNext]
#print axioms g3
#print axioms g6
