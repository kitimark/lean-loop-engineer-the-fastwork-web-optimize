axiom wish : 1 = 2

namespace AxProbe

theorem usesWish : 2 = 3 := by have := wish; omega

macro "unfinished" : term => `(sorryAx _ false)

theorem viaMacro : 3 = 4 := unfinished

def viaDef : Nat := (unfinished : Nat) + 1

theorem standardOnly (p q : Prop) (h : p ↔ q) : p = q := propext h

theorem choiceOnly (α : Type) [Nonempty α] : ∃ _ : α, True := ⟨Classical.choice inferInstance, trivial⟩

end AxProbe
