import Fw.Sup.Adapt

/-! A `fw slot run` started inside another slot's command: when it may skip the queue (docs/team/tools/slot.md). -/
namespace Fw.Sup.Adapt

/-- A nested request skips the queue iff a live held entry has its owner and token and the same kind, or the request is neither `sim` nor `measure`. -/
def nestedSkips (now : Nat) (kind : Kind) (named : Option (String × String)) (held : List Entry) : Bool :=
  match named with
  | none => false
  | some (owner, token) =>
    held.any fun e => live now e && e.owner == owner && e.token == token &&
      (e.kind == kind || (kind != .sim && kind != .measure))

theorem nestedSkips_iff (now : Nat) (kind : Kind) (owner token : String) (held : List Entry) :
    nestedSkips now kind (some (owner, token)) held = true ↔
      ∃ e ∈ held, now < e.till ∧ e.owner = owner ∧ e.token = token ∧ (e.kind = kind ∨ (kind ≠ .sim ∧ kind ≠ .measure)) := by
  simp only [nestedSkips, List.any_eq_true, live, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq,
    bne_iff_ne, ne_eq]
  constructor
  · rintro ⟨e, he, ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩⟩; exact ⟨e, he, h1, h2, h3, h4⟩
  · rintro ⟨e, he, h1, h2, h3, h4⟩; exact ⟨e, he, ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩⟩

theorem nestedSkips_none (now : Nat) (kind : Kind) (held : List Entry) : nestedSkips now kind none held = false := rfl

theorem nestedSkips_empty (now : Nat) (kind : Kind) (named : Option (String × String)) :
    nestedSkips now kind named [] = false := by
  cases named <;> simp [nestedSkips]

theorem nestedSkips_same_kind {now : Nat} {held : List Entry} {e : Entry} (he : e ∈ held) (hl : now < e.till) :
    nestedSkips now e.kind (some (e.owner, e.token)) held = true :=
  (nestedSkips_iff now e.kind e.owner e.token held).2 ⟨e, he, hl, rfl, rfl, Or.inl rfl⟩

theorem nestedSkips_other_kind {now : Nat} {held : List Entry} {e : Entry} {k : Kind} (he : e ∈ held)
    (hl : now < e.till) (hs : k ≠ .sim) (hm : k ≠ .measure) :
    nestedSkips now k (some (e.owner, e.token)) held = true :=
  (nestedSkips_iff now k e.owner e.token held).2 ⟨e, he, hl, rfl, rfl, Or.inr ⟨hs, hm⟩⟩

theorem nestedSkips_sim_admission {now : Nat} {held : List Entry} {owner token : String}
    (h : ∀ e ∈ held, e.kind ≠ .sim) : nestedSkips now .sim (some (owner, token)) held = false := by
  cases hc : nestedSkips now .sim (some (owner, token)) held
  · rfl
  · obtain ⟨e, he, _, _, _, h4⟩ := (nestedSkips_iff now .sim owner token held).1 hc
    rcases h4 with h4 | h4
    · exact absurd h4 (h e he)
    · exact absurd rfl h4.1

theorem nestedSkips_measure_admission {now : Nat} {held : List Entry} {owner token : String}
    (h : ∀ e ∈ held, e.kind ≠ .measure) : nestedSkips now .measure (some (owner, token)) held = false := by
  cases hc : nestedSkips now .measure (some (owner, token)) held
  · rfl
  · obtain ⟨e, he, _, _, _, h4⟩ := (nestedSkips_iff now .measure owner token held).1 hc
    rcases h4 with h4 | h4
    · exact absurd h4 (h e he)
    · exact absurd rfl h4.2

theorem sim_under_parent_not_blocked (p : Params) (n : Nat) (s : Sample) (e : Entry) (q : List Entry) (me : Entry) (w : Nat)
    (hk : me.kind = .sim) (he : e.kind ≠ .sim) {why : Why} {r : Verdict}
    (hv : verdict p n s [e] q me w = r) (hr : r = .wait why ∨ r = .timeout why) :
    why ≠ .simBusy ∧ ∀ k, why ≠ .drain k := by
  have hsim : simHeld s.time [e] = false := by
    simp [simHeld, prune, List.filter_cons, live, he]
  have hoth : others s.time [e] ≤ 1 := by
    simp only [others, prune]
    exact Nat.le_trans (List.length_filter_le _ _) (Nat.le_trans (List.length_filter_le _ _) (by simp))
  subst hv
  unfold verdict verdictWith at hr
  have h1 : decide (1 < others s.time [e]) = false := by simp; omega
  simp only [hk, hsim, h1, Bool.and_false, Bool.false_eq_true, ite_false] at hr
  have key : ∀ w' : Why, w' ≠ .simBusy → (∀ k, w' ≠ .drain k) →
      (waitOr p w w' = .wait why ∨ waitOr p w w' = .timeout why) → why ≠ .simBusy ∧ ∀ k, why ≠ .drain k := by
    intro w' h1 h2 h
    unfold waitOr at h
    split at h <;> rcases h with h | h <;> cases h <;> exact ⟨h1, h2⟩
  rcases hr with hr | hr
  all_goals (repeat' split at hr)
  all_goals first | (refine key _ ?_ ?_ (Or.inl hr) <;> simp) | (refine key _ ?_ ?_ (Or.inr hr) <;> simp) | cases hr

end Fw.Sup.Adapt
