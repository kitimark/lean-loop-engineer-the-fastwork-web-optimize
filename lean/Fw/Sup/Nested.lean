import Fw.Sup.Adapt

/-! A `fw slot run` started inside another slot's command: when it may skip the queue (docs/team/tools/slot.md). -/
namespace Fw.Sup.Adapt

def nestedSkips (now : Nat) (kind : Kind) (named : Option (String × String)) (held : List Entry) : Bool :=
  match named with
  | none => false
  | some (owner, token) => held.any fun e => live now e && e.kind == kind && e.owner == owner && e.token == token

theorem nestedSkips_iff (now : Nat) (kind : Kind) (owner token : String) (held : List Entry) :
    nestedSkips now kind (some (owner, token)) held = true ↔
      ∃ e ∈ held, now < e.till ∧ e.kind = kind ∧ e.owner = owner ∧ e.token = token := by
  simp only [nestedSkips, List.any_eq_true, live, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  constructor
  · rintro ⟨e, he, ⟨⟨h1, h2⟩, h3⟩, h4⟩; exact ⟨e, he, h1, h2, h3, h4⟩
  · rintro ⟨e, he, h1, h2, h3, h4⟩; exact ⟨e, he, ⟨⟨h1, h2⟩, h3⟩, h4⟩

theorem nestedSkips_none (now : Nat) (kind : Kind) (held : List Entry) : nestedSkips now kind none held = false := rfl

theorem nestedSkips_kind {now : Nat} {kind : Kind} {owner token : String} {held : List Entry}
    (h : nestedSkips now kind (some (owner, token)) held = true) :
    ∃ e ∈ held, e.kind = kind ∧ e.token = token := by
  obtain ⟨e, he, _, hk, _, ht⟩ := (nestedSkips_iff now kind owner token held).1 h
  exact ⟨e, he, hk, ht⟩

theorem nestedSkips_live {now : Nat} {kind : Kind} {owner token : String} {held : List Entry}
    (h : nestedSkips now kind (some (owner, token)) held = true) :
    ∃ e ∈ held, now < e.till ∧ e.token = token := by
  obtain ⟨e, he, hl, _, _, ht⟩ := (nestedSkips_iff now kind owner token held).1 h
  exact ⟨e, he, hl, ht⟩

theorem nestedSkips_of_live {now : Nat} {kind : Kind} {held : List Entry} {e : Entry} (he : e ∈ held)
    (hl : now < e.till) (hk : e.kind = kind) :
    nestedSkips now kind (some (e.owner, e.token)) held = true :=
  (nestedSkips_iff now kind e.owner e.token held).2 ⟨e, he, hl, hk, rfl, rfl⟩

theorem nestedSkips_empty (now : Nat) (kind : Kind) (named : Option (String × String)) :
    nestedSkips now kind named [] = false := by
  cases named <;> simp [nestedSkips]

end Fw.Sup.Adapt
