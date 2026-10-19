import Fw.Ops.LeanFirstProps

/-!
# Decision code: the gate's prefix test is the allowlist rule

Task `lfg-spec`, rule 1a. `Fw.Ops.LeanFirstProps` states decision code as `DecisionWrite`: a write glob may cover
(`GlobCovers`) a path outside the allowlist (`Allowed`). The gate computes `isDecisionWrite`, a prefix test on the
glob. `isDecisionWrite_iff` proves the two agree on every glob, which makes `DecisionWrite`, and so every rule spec
`RuleOk`, decidable for the search checks of `Fw.Ops.LeanFirstSearch` and the proofs of `Fw.Ops.LeanFirstProofs`.
-/
namespace Fw.Ops.LeanFirst

/-- A glob with every `*` replaced by `z`: a path the glob covers literally. -/
def fillZ (w : List Char) : List Char := w.map fun c => if c = '*' then 'z' else c

/-- A glob covers its `z`-filled form followed by `/` and anything. -/
theorem covers_fillZ (w t : List Char) : GlobCovers w (fillZ w ++ '/' :: t) := by
  induction w with
  | nil => exact .under t
  | cons c w ih =>
    by_cases hc : c = '*'
    · subst hc
      have : fillZ ('*' :: w) ++ '/' :: t = 'z' :: (fillZ w ++ '/' :: t) := by simp [fillZ]
      rw [this]
      exact .starEat 'z' (.starStop ih)
    · have : fillZ (c :: w) ++ '/' :: t = c :: (fillZ w ++ '/' :: t) := by simp [fillZ, hc]
      rw [this]
      exact .lit c hc ih

/-- If the `z`-filled glob, then `/`, starts with the segment `d` (no `/`, `z` or `*`) and `/`, the glob is `d` or
starts with `d` and `/`. -/
theorem fillZ_seg (d : List Char) (hd : ∀ e ∈ d, e ≠ '/' ∧ e ≠ 'z' ∧ e ≠ '*') :
    ∀ w t r, fillZ w ++ '/' :: t = d ++ '/' :: r → w = d ∨ ∃ r', w = d ++ '/' :: r' := by
  induction d with
  | nil =>
    intro w t r h
    cases w with
    | nil => exact .inl rfl
    | cons c w =>
      right
      by_cases hc : c = '*'
      · simp [fillZ, hc] at h
      · simp [fillZ, hc] at h
        exact ⟨w, by simp [h.1]⟩
  | cons e d ih =>
    intro w t r h
    have he := hd e (by simp)
    have hd' : ∀ x ∈ d, x ≠ '/' ∧ x ≠ 'z' ∧ x ≠ '*' := fun x hx => hd x (by simp [hx])
    cases w with
    | nil => simp [fillZ] at h; exact absurd h.1.symm he.1
    | cons c w =>
      by_cases hc : c = '*'
      · simp [fillZ, hc] at h; exact absurd h.1.symm he.2.1
      · simp [fillZ, hc] at h
        obtain ⟨rfl, h2⟩ := h
        rcases ih hd' w t r h2 with rfl | ⟨r', rfl⟩
        · exact .inl rfl
        · exact .inr ⟨r', rfl⟩

/-- A glob that is a segment `d` (no `*` or `/`) followed by nothing or by `/` covers only paths that are `d` followed
by nothing or by `/`. -/
theorem covers_seg {g p : List Char} (h : GlobCovers g p) :
    ∀ d r, g = d ++ r → (∀ e ∈ d, e ≠ '*' ∧ e ≠ '/') → (r = [] ∨ ∃ r', r = '/' :: r') →
      ∃ p', p = d ++ p' ∧ (p' = [] ∨ ∃ q, p' = '/' :: q) := by
  induction h with
  | done =>
    intro d r hg _ _
    have : d = [] := (List.append_eq_nil_iff.1 hg.symm).1
    subst this
    exact ⟨[], rfl, .inl rfl⟩
  | under p =>
    intro d r hg _ _
    have : d = [] := (List.append_eq_nil_iff.1 hg.symm).1
    subst this
    exact ⟨'/' :: p, rfl, .inr ⟨p, rfl⟩⟩
  | slashEnd =>
    intro d r hg hd _
    cases d with
    | nil => exact ⟨[], rfl, .inl rfl⟩
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).2
  | slashBelow p =>
    intro d r hg hd _
    cases d with
    | nil => exact ⟨'/' :: p, rfl, .inr ⟨p, rfl⟩⟩
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).2
  | starStop _ _ =>
    intro d r hg hd hr
    cases d with
    | nil => simp at hg; subst hg; simp at hr
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).1
  | starEat _ _ _ =>
    intro d r hg hd hr
    cases d with
    | nil => simp at hg; subst hg; simp at hr
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).1
  | @lit g0 p0 c _ _ ih =>
    intro d r hg hd hr
    cases d with
    | nil =>
      simp at hg; subst hg
      rcases hr with h | ⟨r', h⟩
      · simp at h
      · simp at h; obtain ⟨rfl, -⟩ := h; exact ⟨'/' :: p0, rfl, .inr ⟨p0, rfl⟩⟩
    | cons e d =>
      simp at hg; obtain ⟨rfl, hg⟩ := hg
      obtain ⟨p', rfl, hp'⟩ := ih d r hg (fun x hx => hd x (by simp [hx])) hr
      exact ⟨p', rfl, hp'⟩
  | @dstarSkip g0 p0 hg0 _ ih =>
    intro d r hg hd _
    cases d with
    | nil => exact ih [] g0 rfl (by simp) hg0
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).2
  | dstarLead _ _ =>
    intro d r hg hd hr
    cases d with
    | nil => simp at hg; subst hg; simp at hr
    | cons e d => simp at hg; exact absurd hg.1.symm (hd e (by simp)).1

/-- The gate's test is an allowed root or a root and `/` as a prefix, and nothing else. -/
theorem isDecisionWrite_false (w : String) :
    isDecisionWrite w = false ↔ ∃ d ∈ ["docs".toList, "research".toList], FirstSeg w.toList d := by
  have hp : ∀ d : List Char, ((d ++ ['/']).isPrefixOf w.toList = true) ↔ ∃ r, w.toList = d ++ '/' :: r := by
    intro d
    rw [List.isPrefixOf_iff_prefix]
    constructor
    · rintro ⟨t, ht⟩; exact ⟨t, by simp [← ht]⟩
    · rintro ⟨r, hr⟩; exact ⟨r, by simp [hr]⟩
  simp only [isDecisionWrite, allowRoots, Bool.not_eq_false', List.any_cons, List.any_nil, Bool.or_false,
    Bool.or_eq_true, beq_iff_eq, hp, List.mem_cons, List.mem_nil_iff, or_false, exists_eq_or_imp, exists_eq_left,
    FirstSeg]

/-- **The gate's decision test is the allowlist rule**: `isDecisionWrite` holds exactly when the glob may cover a path
that is not allowlisted.
The gate's prefix test and the spec's allowlist over covered paths agree on every glob. -/
theorem isDecisionWrite_iff (w : String) : isDecisionWrite w = true ↔ DecisionWrite w := by
  have hroots : ∀ d ∈ ["docs".toList, "research".toList], ∀ e ∈ d, e ≠ '/' ∧ e ≠ 'z' ∧ e ≠ '*' := by decide
  constructor
  · intro h
    refine ⟨fillZ w.toList ++ ['/', 'x'], covers_fillZ w.toList ['x'], ?_⟩
    have hseg : ∀ d ∈ ["docs".toList, "research".toList], ¬ FirstSeg (fillZ w.toList ++ ['/', 'x']) d := by
      intro d hd hf
      have hfalse : isDecisionWrite w = false := by
        rw [isDecisionWrite_false]
        refine ⟨d, hd, ?_⟩
        rcases hf with hf | ⟨r, hr⟩
        · have := congrArg List.reverse hf
          rcases List.mem_cons.1 hd with rfl | hd
          · simp at this
          · rcases List.mem_singleton.1 hd with rfl; simp at this
        · exact fillZ_seg d (hroots d hd) w.toList ['x'] r hr
      simp [h] at hfalse
    intro ha
    rcases ha with ha | ha | ⟨⟨r, hr⟩, -⟩
    · exact hseg _ (by simp) ha
    · exact hseg _ (by simp) ha
    · have := congrArg List.reverse hr
      simp at this
  · rintro ⟨p, hc, hna⟩
    cases h : isDecisionWrite w
    · obtain ⟨d, hd, hf⟩ := (isDecisionWrite_false w).1 h
      have hd' : ∀ e ∈ d, e ≠ '*' ∧ e ≠ '/' := fun e he => ⟨(hroots d hd e he).2.2, (hroots d hd e he).1⟩
      have hcov : ∃ p', p = d ++ p' ∧ (p' = [] ∨ ∃ q, p' = '/' :: q) := by
        rcases hf with hf | ⟨r, hr⟩
        · exact covers_seg hc d [] (by simp [hf]) hd' (.inl rfl)
        · exact covers_seg hc d ('/' :: r) hr hd' (.inr ⟨r, rfl⟩)
      obtain ⟨p', rfl, hp'⟩ := hcov
      have hfs : FirstSeg (d ++ p') d := by
        rcases hp' with rfl | ⟨q, rfl⟩
        · exact .inl (by simp)
        · exact .inr ⟨q, rfl⟩
      apply absurd _ hna
      rcases List.mem_cons.1 hd with rfl | hd
      · exact .inl hfs
      · rcases List.mem_singleton.1 hd with rfl; exact .inr (.inl hfs)
    · rfl

instance instDecidableDecisionWrite (w : String) : Decidable (DecisionWrite w) :=
  decidable_of_iff _ (isDecisionWrite_iff w)

instance instDecidableReachKnown (F : Facts) : Decidable (ReachKnown F) :=
  inferInstanceAs (Decidable (∀ t ∈ F.thms, t.implArg ≠ none → (∃ Q ∈ F.props, t.proves = some Q.name) →
    t.reachFromWire ≠ none))

instance instDecidableAllPresent (F : Facts) : Decidable (AllPresent F) :=
  inferInstanceAs (Decidable (F.present.mathview = true ∧ F.present.kills = true ∧ F.present.tsLint = true ∧
    ReachKnown F ∧ F.exemptAt = some F.mainAt))

/-- Every rule spec is decidable: each is a list-bounded formula, and decision code is decided by `isDecisionWrite`. -/
instance instDecidableRuleOk (r : Rule) (F : Facts) : Decidable (RuleOk r F) :=
  match r with
  | .props => inferInstanceAs (Decidable (PropsOk F))
  | .kills => inferInstanceAs (Decidable (KillsOk F))
  | .twins => inferInstanceAs (Decidable (TwinsOk F))
  | .premises => inferInstanceAs (Decidable (PremOk F))
  | .search => inferInstanceAs (Decidable (SearchOk F))
  | .ratchet => inferInstanceAs (Decidable (RatchetOk F))

#guard decide (DecisionWrite "apps/runner/**") && !decide (DecisionWrite "docs/team/handoffs/x.md")
#guard decide (DecisionWrite "*") && !decide (DecisionWrite "research")

end Fw.Ops.LeanFirst
