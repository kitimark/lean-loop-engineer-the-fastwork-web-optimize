import Fw.Sup.Adapt

/-! A `fw slot run` started inside another slot's command: when it may skip the queue (docs/team/tools/slot.md). -/
namespace Fw.Sup.Adapt

/-- A nested run skips the queue iff its parent names a live held entry of the same owner and token, whatever the kinds of the parent and the request (it runs under the parent's lease). Refusing a request of another kind would break `fw land`, which runs check.sh and package tests inside its own land slot. Live means the lease has not expired (`live`, now < till; the parent's run renews it every leaseS/3); the owner's pid and start time are not checked, so a dead parent's token covers a child until its lease lapses (follow-up: Entry has no pid). -/
def nestedSkips (now : Nat) (named : Option (String × String)) (held : List Entry) : Bool :=
  match named with
  | none => false
  | some (owner, token) => held.any fun e => live now e && e.owner == owner && e.token == token

theorem nestedSkips_iff (now : Nat) (owner token : String) (held : List Entry) :
    nestedSkips now (some (owner, token)) held = true ↔
      ∃ e ∈ held, now < e.till ∧ e.owner = owner ∧ e.token = token := by
  simp only [nestedSkips, List.any_eq_true, live, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  constructor
  · rintro ⟨e, he, ⟨h1, h2⟩, h3⟩; exact ⟨e, he, h1, h2, h3⟩
  · rintro ⟨e, he, h1, h2, h3⟩; exact ⟨e, he, ⟨h1, h2⟩, h3⟩

theorem nestedSkips_none (now : Nat) (held : List Entry) : nestedSkips now none held = false := rfl

theorem nestedSkips_live {now : Nat} {owner token : String} {held : List Entry}
    (h : nestedSkips now (some (owner, token)) held = true) :
    ∃ e ∈ held, now < e.till ∧ e.token = token := by
  obtain ⟨e, he, hl, _, ht⟩ := (nestedSkips_iff now owner token held).1 h
  exact ⟨e, he, hl, ht⟩

/-- A request inside a live ancestor never queues, whatever its kind: this is the OR-branch "run under the parent's lease". -/
theorem nestedSkips_of_live {now : Nat} {held : List Entry} {e : Entry} (he : e ∈ held)
    (hl : now < e.till) :
    nestedSkips now (some (e.owner, e.token)) held = true :=
  (nestedSkips_iff now e.owner e.token held).2 ⟨e, he, hl, rfl, rfl⟩

/-- Of any two kinds, a request of the other kind under a live parent skips too (no wait on the own ancestor at limit 1). -/
theorem nestedSkips_other_kind {now : Nat} {held : List Entry} {e : Entry} {k : Kind} (he : e ∈ held)
    (hl : now < e.till) (_hk : e.kind ≠ k) :
    nestedSkips now (some (e.owner, e.token)) held = true :=
  nestedSkips_of_live he hl

/-- The refuse branch is never taken: a skip needs a live entry, so an expired or unnamed token falls back to the queue. -/
theorem nestedSkips_empty (now : Nat) (named : Option (String × String)) :
    nestedSkips now named [] = false := by
  cases named <;> simp [nestedSkips]

end Fw.Sup.Adapt
