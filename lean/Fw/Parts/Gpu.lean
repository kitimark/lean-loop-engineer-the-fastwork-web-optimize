namespace Fw.Parts.Gpu

structure Entry where
  part : String
  variant : String
  mechanism : String
  n : Nat
deriving Repr, DecidableEq

def entries : List Entry := [
  ⟨"hero.exit", "threaded", "scroll-driven CSS animations of opacity and transform replace a per-frame main-thread write of --exit-opacity", 6⟩,
  ⟨"platform", "fade-threaded", "the section fade is one opacity and blur Web Animation per push (compositor) instead of a per-frame custom property write", 44⟩,
  ⟨"morph.panel", "const-bounds", "the blur-backed panel layer keeps a constant box, so the compositor never resizes it on a morph frame", 45⟩,
  ⟨"hero.countdown", "strip", "one 12-entry strip per digit replaces 10 will-change faces: 80 composited layers become 8", 7⟩,
  ⟨"morph.countdown", "strip", "one 12-entry strip per digit replaces 10 will-change faces: 80 composited layers become 8", 13⟩,
  ⟨"hero", "scene-pause", "will-change auto and paused animations off-screen release about 85 composited hero layers", 40⟩]

/-- The GPU mechanism text of a variant, `none` when it is not a GPU optimization. -/
def mechanism (part variant : String) : Option String :=
  (entries.find? fun e => e.part == part && e.variant == variant).map (·.mechanism)

#guard (entries.map fun e => (e.part, e.variant)).eraseDups.length == entries.length

theorem mechanism_entry : ∀ e ∈ entries, mechanism e.part e.variant ≠ none := by decide

theorem mechanism_none_of_not_mem (p v : String) (h : (p, v) ∉ entries.map fun e => (e.part, e.variant)) : mechanism p v = none := by
  unfold mechanism
  cases hf : entries.find? (fun e => e.part == p && e.variant == v) with
  | none => rfl
  | some e =>
    exfalso; apply h
    have hm := List.mem_of_find?_eq_some hf
    have hp := List.find?_some hf
    simp only [Bool.and_eq_true, beq_iff_eq] at hp
    exact List.mem_map.2 ⟨e, hm, by rw [hp.1, hp.2]⟩

end Fw.Parts.Gpu
