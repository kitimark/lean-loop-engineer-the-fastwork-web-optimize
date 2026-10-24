import Fw.Sup.Adapt

/-! A `fw slot run` started inside another slot's command: when it may skip the queue (docs/team/tools/slot.md). -/
namespace Fw.Sup.Adapt

/-- A nested `slot run` of kind `kind` skips the queue only when its parent names (owner, token) and the state holds
that entry, live at `now` and of the same kind. Every other request takes a slot. -/
def nestedSkips (now : Nat) (kind : Kind) (named : Option (String × String)) (held : List Entry) : Bool :=
  match named with
  | none => false
  | some (owner, token) => held.any fun e => live now e && e.kind == kind && e.owner == owner && e.token == token

/-- The skip holds exactly when a live entry of the asked kind carries the named owner and token. -/
theorem nestedSkips_iff (now : Nat) (kind : Kind) (owner token : String) (held : List Entry) :
    nestedSkips now kind (some (owner, token)) held = true ↔
      ∃ e ∈ held, now < e.till ∧ e.kind = kind ∧ e.owner = owner ∧ e.token = token := by
  simp only [nestedSkips, List.any_eq_true, live, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  constructor
  · rintro ⟨e, he, ⟨⟨h1, h2⟩, h3⟩, h4⟩; exact ⟨e, he, h1, h2, h3, h4⟩
  · rintro ⟨e, he, h1, h2, h3, h4⟩; exact ⟨e, he, ⟨⟨h1, h2⟩, h3⟩, h4⟩

/-- No named token (`FW_SLOT_HELD` alone, a bare call): the request takes a slot. -/
theorem nestedSkips_none (now : Nat) (kind : Kind) (held : List Entry) : nestedSkips now kind none held = false := rfl

/-- A skip needs the named entry to be of the asked kind: a held test slot never covers a land request. -/
theorem nestedSkips_kind {now : Nat} {kind : Kind} {owner token : String} {held : List Entry}
    (h : nestedSkips now kind (some (owner, token)) held = true) :
    ∃ e ∈ held, e.kind = kind ∧ e.token = token := by
  obtain ⟨e, he, _, hk, _, ht⟩ := (nestedSkips_iff now kind owner token held).1 h
  exact ⟨e, he, hk, ht⟩

/-- A skip needs the named entry to be live: an expired or released token takes a slot. -/
theorem nestedSkips_live {now : Nat} {kind : Kind} {owner token : String} {held : List Entry}
    (h : nestedSkips now kind (some (owner, token)) held = true) :
    ∃ e ∈ held, now < e.till ∧ e.token = token := by
  obtain ⟨e, he, hl, _, _, ht⟩ := (nestedSkips_iff now kind owner token held).1 h
  exact ⟨e, he, hl, ht⟩

/-- Other direction: a live entry of the asked kind that carries the named owner and token lets the request skip. -/
theorem nestedSkips_of_live {now : Nat} {kind : Kind} {held : List Entry} {e : Entry} (he : e ∈ held)
    (hl : now < e.till) (hk : e.kind = kind) :
    nestedSkips now kind (some (e.owner, e.token)) held = true :=
  (nestedSkips_iff now kind e.owner e.token held).2 ⟨e, he, hl, hk, rfl, rfl⟩

/-- No entry of the state is held: the request takes a slot, whatever it names. -/
theorem nestedSkips_empty (now : Nat) (kind : Kind) (named : Option (String × String)) :
    nestedSkips now kind named [] = false := by
  cases named <;> simp [nestedSkips]

end Fw.Sup.Adapt
