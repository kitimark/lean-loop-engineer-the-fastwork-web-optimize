import Fw.Ops.PathCheck
/-!
# `plan.overlap`: do two tasks' graph `writes` cover a common path?
Glob intersection reuses `Fw.Ops.PathCheck` semantics; proved sound and complete (`globsOverlap_sound`, `globsOverlap_complete`).
-/
namespace Fw.Plan.Overlap
open Fw.Ops.PathCheck

/-- Do two glob segments (character lists, `*` = any run) match a common string? -/
def segInter : List Char → List Char → Bool
  | [], [] => true
  | '*' :: p, [] => segInter p []
  | [], '*' :: q => segInter [] q
  | _ :: _, [] => false
  | [], _ :: _ => false
  | '*' :: p, '*' :: q => segInter p ('*' :: q) || segInter ('*' :: p) q
  | '*' :: p, d :: q => segInter p (d :: q) || segInter ('*' :: p) q
  | c :: p, '*' :: q => segInter (c :: p) q || segInter p ('*' :: q)
  | c :: p, d :: q => c == d && segInter p q
termination_by p q => p.length + q.length

theorem sm_nil (s : List Char) : segMatch [] s = s.isEmpty := by simp [segMatch]
theorem sm_star_nil (p : List Char) : segMatch ('*' :: p) [] = segMatch p [] := by simp [segMatch]
theorem sm_star_cons (p : List Char) (c : Char) (s : List Char) :
    segMatch ('*' :: p) (c :: s) = (segMatch p (c :: s) || segMatch ('*' :: p) s) := by simp [segMatch]
theorem sm_cons_nil (c : Char) (p : List Char) (h : c ≠ '*') : segMatch (c :: p) [] = false := by
  cases c <;> simp_all [segMatch]
theorem sm_cons_cons (c : Char) (p : List Char) (d : Char) (s : List Char) (h : c ≠ '*') :
    segMatch (c :: p) (d :: s) = (c == d && segMatch p s) := by
  cases c <;> simp_all [segMatch]

theorem si_star_cons (p : List Char) (d : Char) (q : List Char) (hd : d ≠ '*') :
    segInter ('*' :: p) (d :: q) = (segInter p (d :: q) || segInter ('*' :: p) q) := by
  rw [segInter]; intro h; exact hd h
theorem si_cons_star (c : Char) (p q : List Char) (hc : c ≠ '*') :
    segInter (c :: p) ('*' :: q) = (segInter (c :: p) q || segInter p ('*' :: q)) := by
  rw [segInter]; intro h; exact hc h
theorem si_cons_cons (c : Char) (p : List Char) (d : Char) (q : List Char) (hc : c ≠ '*') (hd : d ≠ '*') :
    segInter (c :: p) (d :: q) = (c == d && segInter p q) := by
  rw [segInter] <;> intros <;> simp_all

theorem segInter_complete (p q s : List Char) (hp : segMatch p s = true) (hq : segMatch q s = true) :
    segInter p q = true := by
  match p, q, s with
  | [], [], _ => simp [segInter]
  | '*' :: p, [], s =>
    rw [segInter]
    cases s with
    | nil => rw [sm_star_nil] at hp; exact segInter_complete p [] [] hp hq
    | cons c s => simp [segMatch] at hq
  | [], '*' :: q, s =>
    rw [segInter]
    cases s with
    | nil => rw [sm_star_nil] at hq; exact segInter_complete [] q [] hp hq
    | cons c s => simp [segMatch] at hp
  | c :: p, [], s =>
    by_cases hc : c = '*'
    · subst hc
      rw [segInter]
      cases s with
      | nil => rw [sm_star_nil] at hp; exact segInter_complete p [] [] hp hq
      | cons c s => simp [segMatch] at hq
    · cases s with
      | nil => rw [sm_cons_nil c p hc] at hp; cases hp
      | cons d s => simp [segMatch] at hq
  | [], d :: q, s =>
    by_cases hd : d = '*'
    · subst hd
      rw [segInter]
      cases s with
      | nil => rw [sm_star_nil] at hq; exact segInter_complete [] q [] hp hq
      | cons c s => simp [segMatch] at hp
    · cases s with
      | nil => rw [sm_cons_nil d q hd] at hq; cases hq
      | cons e s => simp [segMatch] at hp
  | c :: p, d :: q, s =>
    by_cases hc : c = '*' <;> by_cases hd : d = '*'
    · subst hc; subst hd
      rw [segInter]
      cases s with
      | nil =>
        rw [sm_star_nil] at hp hq
        have := segInter_complete p ('*' :: q) [] hp (by rw [sm_star_nil]; exact hq)
        simp [this]
      | cons e s =>
        rw [sm_star_cons] at hp hq
        simp only [Bool.or_eq_true] at hp hq
        rcases hp with hp | hp
        · have := segInter_complete p ('*' :: q) (e :: s) hp (by rw [sm_star_cons]; simp [hq])
          simp [this]
        · rcases hq with hq | hq
          · have := segInter_complete ('*' :: p) q (e :: s) (by rw [sm_star_cons]; simp [hp]) hq
            simp [this]
          · have := segInter_complete ('*' :: p) ('*' :: q) s hp hq
            rw [segInter] at this; exact this
    · subst hc
      rw [si_star_cons p d q hd]
      cases s with
      | nil => rw [sm_cons_nil d q hd] at hq; cases hq
      | cons e s =>
        rw [sm_cons_cons d q e s hd] at hq
        simp only [Bool.and_eq_true] at hq
        rw [sm_star_cons] at hp
        simp only [Bool.or_eq_true] at hp
        rcases hp with hp | hp
        · have := segInter_complete p (d :: q) (e :: s) hp (by rw [sm_cons_cons d q e s hd]; simpa using hq)
          simp [this]
        · have := segInter_complete ('*' :: p) q s hp hq.2
          simp [this]
    · subst hd
      rw [si_cons_star c p q hc]
      cases s with
      | nil => rw [sm_cons_nil c p hc] at hp; cases hp
      | cons e s =>
        rw [sm_cons_cons c p e s hc] at hp
        simp only [Bool.and_eq_true] at hp
        rw [sm_star_cons] at hq
        simp only [Bool.or_eq_true] at hq
        rcases hq with hq | hq
        · have := segInter_complete (c :: p) q (e :: s) (by rw [sm_cons_cons c p e s hc]; simpa using hp) hq
          simp [this]
        · have := segInter_complete p ('*' :: q) s hp.2 hq
          simp [this]
    · cases s with
      | nil => rw [sm_cons_nil c p hc] at hp; cases hp
      | cons e s =>
        rw [sm_cons_cons c p e s hc] at hp
        rw [sm_cons_cons d q e s hd] at hq
        simp only [Bool.and_eq_true, beq_iff_eq] at hp hq
        have := segInter_complete p q s hp.2 hq.2
        rw [si_cons_cons c p d q hc hd]
        simp [this, hp.1, hq.1]
termination_by p.length + q.length + s.length

theorem sm_star_of (p s : List Char) (h : segMatch p s = true) : segMatch ('*' :: p) s = true := by
  cases s with
  | nil => rw [sm_star_nil]; exact h
  | cons c s => rw [sm_star_cons]; simp [h]

theorem segInter_sound (p q : List Char) (h : segInter p q = true) :
    ∃ s, segMatch p s = true ∧ segMatch q s = true := by
  match p, q with
  | [], [] => exact ⟨[], by simp [segMatch], by simp [segMatch]⟩
  | '*' :: p, [] =>
    rw [segInter] at h
    obtain ⟨s, h1, h2⟩ := segInter_sound p [] h
    have : s = [] := by cases s <;> simp_all [segMatch]
    subst this
    exact ⟨[], by rw [sm_star_nil]; exact h1, h2⟩
  | [], '*' :: q =>
    rw [segInter] at h
    obtain ⟨s, h1, h2⟩ := segInter_sound [] q h
    have : s = [] := by cases s <;> simp_all [segMatch]
    subst this
    exact ⟨[], h1, by rw [sm_star_nil]; exact h2⟩
  | c :: p, [] =>
    by_cases hc : c = '*'
    · subst hc
      rw [segInter] at h
      obtain ⟨s, h1, h2⟩ := segInter_sound p [] h
      have : s = [] := by cases s <;> simp_all [segMatch]
      subst this
      exact ⟨[], by rw [sm_star_nil]; exact h1, h2⟩
    · rw [segInter] at h
      · cases h
      · exact hc
  | [], d :: q =>
    by_cases hd : d = '*'
    · subst hd
      rw [segInter] at h
      obtain ⟨s, h1, h2⟩ := segInter_sound [] q h
      have : s = [] := by cases s <;> simp_all [segMatch]
      subst this
      exact ⟨[], h1, by rw [sm_star_nil]; exact h2⟩
    · rw [segInter] at h
      · cases h
      · exact hd
  | c :: p, d :: q =>
    by_cases hc : c = '*' <;> by_cases hd : d = '*'
    · subst hc; subst hd
      rw [segInter] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := segInter_sound p ('*' :: q) h
        exact ⟨s, sm_star_of p s h1, h2⟩
      · obtain ⟨s, h1, h2⟩ := segInter_sound ('*' :: p) q h
        exact ⟨s, h1, sm_star_of q s h2⟩
    · subst hc
      rw [si_star_cons p d q hd] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := segInter_sound p (d :: q) h
        exact ⟨s, sm_star_of p s h1, h2⟩
      · obtain ⟨s, h1, h2⟩ := segInter_sound ('*' :: p) q h
        refine ⟨d :: s, ?_, ?_⟩
        · rw [sm_star_cons]; simp [h1]
        · rw [sm_cons_cons d q d s hd]; simp [h2]
    · subst hd
      rw [si_cons_star c p q hc] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := segInter_sound (c :: p) q h
        exact ⟨s, h1, sm_star_of q s h2⟩
      · obtain ⟨s, h1, h2⟩ := segInter_sound p ('*' :: q) h
        refine ⟨c :: s, ?_, ?_⟩
        · rw [sm_cons_cons c p c s hc]; simp [h1]
        · rw [sm_star_cons]; simp [h2]
    · rw [si_cons_cons c p d q hc hd] at h
      simp only [Bool.and_eq_true, beq_iff_eq] at h
      obtain ⟨hcd, hpq⟩ := h
      obtain ⟨s, h1, h2⟩ := segInter_sound p q hpq
      subst hcd
      exact ⟨c :: s, by rw [sm_cons_cons c p c s hc]; simp [h1], by rw [sm_cons_cons c q c s hd]; simp [h2]⟩
termination_by p.length + q.length

/-! ## Whole globs: segment lists with `**` -/

/-- Do two globs (segment lists, `**` = any number of segments) match a common path? -/
def globInter : List String → List String → Bool
  | [], [] => true
  | "**" :: p, [] => globInter p []
  | [], "**" :: q => globInter [] q
  | _ :: _, [] => false
  | [], _ :: _ => false
  | "**" :: p, "**" :: q => globInter p ("**" :: q) || globInter ("**" :: p) q
  | "**" :: p, y :: q => globInter p (y :: q) || globInter ("**" :: p) q
  | x :: p, "**" :: q => globInter (x :: p) q || globInter p ("**" :: q)
  | x :: p, y :: q => segInter x.toList y.toList && globInter p q
termination_by p q => p.length + q.length

/-- A glob segment matches itself as a string. -/
theorem segMatch_refl' : ∀ p : List Char, segMatch p p = true
  | [] => by simp [segMatch]
  | c :: p => by
    by_cases hc : c = '*'
    · subst hc
      rw [sm_star_cons]
      have := sm_star_of p p (segMatch_refl' p)
      simp [this]
    · rw [sm_cons_cons c p c p hc]; simp [segMatch_refl' p]

theorem segMatch_refl (s : String) : segMatch s.toList s.toList = true := segMatch_refl' _

theorem gm_star_nil (p : List String) : globMatch ("**" :: p) [] = globMatch p [] := by simp [globMatch]
theorem gm_star_cons (p : List String) (c : String) (s : List String) :
    globMatch ("**" :: p) (c :: s) = (globMatch p (c :: s) || globMatch ("**" :: p) s) := by simp [globMatch]
theorem gm_cons_nil (c : String) (p : List String) (h : c ≠ "**") : globMatch (c :: p) [] = false := by
  simp [globMatch]
theorem gm_cons_cons (c : String) (p : List String) (d : String) (s : List String) (h : c ≠ "**") :
    globMatch (c :: p) (d :: s) = (segMatch c.toList d.toList && globMatch p s) := by
  simp [globMatch]

theorem gi_star_cons (p : List String) (d : String) (q : List String) (hd : d ≠ "**") :
    globInter ("**" :: p) (d :: q) = (globInter p (d :: q) || globInter ("**" :: p) q) := by
  rw [globInter] <;> intros <;> simp_all
theorem gi_cons_star (c : String) (p q : List String) (hc : c ≠ "**") :
    globInter (c :: p) ("**" :: q) = (globInter (c :: p) q || globInter p ("**" :: q)) := by
  rw [globInter] <;> intros <;> simp_all
theorem gi_cons_cons (c : String) (p : List String) (d : String) (q : List String) (hc : c ≠ "**") (hd : d ≠ "**") :
    globInter (c :: p) (d :: q) = (segInter c.toList d.toList && globInter p q) := by
  rw [globInter] <;> intros <;> simp_all

theorem globInter_complete (p q s : List String) (hp : globMatch p s = true) (hq : globMatch q s = true) :
    globInter p q = true := by
  match p, q, s with
  | [], [], _ => simp [globInter]
  | "**" :: p, [], s =>
    rw [globInter]
    cases s with
    | nil => rw [gm_star_nil] at hp; exact globInter_complete p [] [] hp hq
    | cons c s => simp [globMatch] at hq
  | [], "**" :: q, s =>
    rw [globInter]
    cases s with
    | nil => rw [gm_star_nil] at hq; exact globInter_complete [] q [] hp hq
    | cons c s => simp [globMatch] at hp
  | c :: p, [], s =>
    by_cases hc : c = "**"
    · subst hc
      rw [globInter]
      cases s with
      | nil => rw [gm_star_nil] at hp; exact globInter_complete p [] [] hp hq
      | cons c s => simp [globMatch] at hq
    · cases s with
      | nil => rw [gm_cons_nil c p hc] at hp; cases hp
      | cons d s => simp [globMatch] at hq
  | [], d :: q, s =>
    by_cases hd : d = "**"
    · subst hd
      rw [globInter]
      cases s with
      | nil => rw [gm_star_nil] at hq; exact globInter_complete [] q [] hp hq
      | cons c s => simp [globMatch] at hp
    · cases s with
      | nil => rw [gm_cons_nil d q hd] at hq; cases hq
      | cons e s => simp [globMatch] at hp
  | c :: p, d :: q, s =>
    by_cases hc : c = "**" <;> by_cases hd : d = "**"
    · subst hc; subst hd
      rw [globInter]
      cases s with
      | nil =>
        rw [gm_star_nil] at hp hq
        have := globInter_complete p ("**" :: q) [] hp (by rw [gm_star_nil]; exact hq)
        simp [this]
      | cons e s =>
        rw [gm_star_cons] at hp hq
        simp only [Bool.or_eq_true] at hp hq
        rcases hp with hp | hp
        · have := globInter_complete p ("**" :: q) (e :: s) hp (by rw [gm_star_cons]; simp [hq])
          simp [this]
        · rcases hq with hq | hq
          · have := globInter_complete ("**" :: p) q (e :: s) (by rw [gm_star_cons]; simp [hp]) hq
            simp [this]
          · have := globInter_complete ("**" :: p) ("**" :: q) s hp hq
            rw [globInter] at this; exact this
    · subst hc
      rw [gi_star_cons p d q hd]
      cases s with
      | nil => rw [gm_cons_nil d q hd] at hq; cases hq
      | cons e s =>
        rw [gm_cons_cons d q e s hd] at hq
        simp only [Bool.and_eq_true] at hq
        rw [gm_star_cons] at hp
        simp only [Bool.or_eq_true] at hp
        rcases hp with hp | hp
        · have := globInter_complete p (d :: q) (e :: s) hp (by rw [gm_cons_cons d q e s hd]; simpa using hq)
          simp [this]
        · have := globInter_complete ("**" :: p) q s hp hq.2
          simp [this]
    · subst hd
      rw [gi_cons_star c p q hc]
      cases s with
      | nil => rw [gm_cons_nil c p hc] at hp; cases hp
      | cons e s =>
        rw [gm_cons_cons c p e s hc] at hp
        simp only [Bool.and_eq_true] at hp
        rw [gm_star_cons] at hq
        simp only [Bool.or_eq_true] at hq
        rcases hq with hq | hq
        · have := globInter_complete (c :: p) q (e :: s) (by rw [gm_cons_cons c p e s hc]; simpa using hp) hq
          simp [this]
        · have := globInter_complete p ("**" :: q) s hp.2 hq
          simp [this]
    · cases s with
      | nil => rw [gm_cons_nil c p hc] at hp; cases hp
      | cons e s =>
        rw [gm_cons_cons c p e s hc] at hp
        rw [gm_cons_cons d q e s hd] at hq
        simp only [Bool.and_eq_true] at hp hq
        have h1 := segInter_complete _ _ _ hp.1 hq.1
        have h2 := globInter_complete p q s hp.2 hq.2
        rw [gi_cons_cons c p d q hc hd]
        simp [h1, h2]
termination_by p.length + q.length + s.length

theorem gm_star_of (p s : List String) (h : globMatch p s = true) : globMatch ("**" :: p) s = true := by
  cases s with
  | nil => rw [gm_star_nil]; exact h
  | cons c s => rw [gm_star_cons]; simp [h]

theorem globInter_sound (p q : List String) (h : globInter p q = true) :
    ∃ s, globMatch p s = true ∧ globMatch q s = true := by
  match p, q with
  | [], [] => exact ⟨[], by simp [globMatch], by simp [globMatch]⟩
  | "**" :: p, [] =>
    rw [globInter] at h
    obtain ⟨s, h1, h2⟩ := globInter_sound p [] h
    have : s = [] := by cases s <;> simp_all [globMatch]
    subst this
    exact ⟨[], by rw [gm_star_nil]; exact h1, h2⟩
  | [], "**" :: q =>
    rw [globInter] at h
    obtain ⟨s, h1, h2⟩ := globInter_sound [] q h
    have : s = [] := by cases s <;> simp_all [globMatch]
    subst this
    exact ⟨[], h1, by rw [gm_star_nil]; exact h2⟩
  | c :: p, [] =>
    by_cases hc : c = "**"
    · subst hc
      rw [globInter] at h
      obtain ⟨s, h1, h2⟩ := globInter_sound p [] h
      have : s = [] := by cases s <;> simp_all [globMatch]
      subst this
      exact ⟨[], by rw [gm_star_nil]; exact h1, h2⟩
    · rw [globInter] at h
      · cases h
      · exact hc
  | [], d :: q =>
    by_cases hd : d = "**"
    · subst hd
      rw [globInter] at h
      obtain ⟨s, h1, h2⟩ := globInter_sound [] q h
      have : s = [] := by cases s <;> simp_all [globMatch]
      subst this
      exact ⟨[], h1, by rw [gm_star_nil]; exact h2⟩
    · rw [globInter] at h
      · cases h
      · exact hd
  | c :: p, d :: q =>
    by_cases hc : c = "**" <;> by_cases hd : d = "**"
    · subst hc; subst hd
      rw [globInter] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := globInter_sound p ("**" :: q) h
        exact ⟨s, gm_star_of p s h1, h2⟩
      · obtain ⟨s, h1, h2⟩ := globInter_sound ("**" :: p) q h
        exact ⟨s, h1, gm_star_of q s h2⟩
    · subst hc
      rw [gi_star_cons p d q hd] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := globInter_sound p (d :: q) h
        exact ⟨s, gm_star_of p s h1, h2⟩
      · obtain ⟨s, h1, h2⟩ := globInter_sound ("**" :: p) q h
        refine ⟨d :: s, ?_, ?_⟩
        · rw [gm_star_cons]; simp [h1]
        · rw [gm_cons_cons d q d s hd]; simp [h2, segMatch_refl]
    · subst hd
      rw [gi_cons_star c p q hc] at h
      simp only [Bool.or_eq_true] at h
      rcases h with h | h
      · obtain ⟨s, h1, h2⟩ := globInter_sound (c :: p) q h
        exact ⟨s, h1, gm_star_of q s h2⟩
      · obtain ⟨s, h1, h2⟩ := globInter_sound p ("**" :: q) h
        refine ⟨c :: s, ?_, ?_⟩
        · rw [gm_cons_cons c p c s hc]; simp [h1, segMatch_refl]
        · rw [gm_star_cons]; simp [h2]
    · rw [gi_cons_cons c p d q hc hd] at h
      simp only [Bool.and_eq_true] at h
      obtain ⟨hcd, hpq⟩ := h
      obtain ⟨t, ht1, ht2⟩ := segInter_sound _ _ hcd
      obtain ⟨s, h1, h2⟩ := globInter_sound p q hpq
      refine ⟨String.ofList t :: s, ?_, ?_⟩
      · rw [gm_cons_cons c p _ s hc]; simp [h1, ht1]
      · rw [gm_cons_cons d q _ s hd]; simp [h2, ht2]
termination_by p.length + q.length

/-- `globInter` holds exactly when some path matches both globs. -/
theorem globInter_iff (p q : List String) :
    globInter p q = true ↔ ∃ s, globMatch p s = true ∧ globMatch q s = true :=
  ⟨globInter_sound p q, fun ⟨s, h1, h2⟩ => globInter_complete p q s h1 h2⟩

/-- A glob that matches `u` followed by `**` matches `u` and everything after it. -/
theorem gm_snoc_dstar : ∀ (g u v : List String), globMatch g u = true →
    globMatch (g ++ ["**"]) (u ++ v) = true
  | g, u, v, h => by
    match g, u with
    | [], [] => exact globMatch_dstar v
    | [], _ :: _ => simp [globMatch] at h
    | y :: g, u =>
      by_cases hy : y = "**"
      · subst hy
        cases u with
        | nil =>
          rw [gm_star_nil] at h
          have := gm_snoc_dstar g [] v h
          cases v with
          | nil => rw [List.cons_append, List.nil_append, gm_star_nil]; simpa using this
          | cons x v => rw [List.cons_append, List.nil_append, gm_star_cons]; simp_all
        | cons x u =>
          rw [gm_star_cons] at h
          simp only [Bool.or_eq_true] at h
          rw [List.cons_append, List.cons_append, gm_star_cons]
          rcases h with h | h
          · have := gm_snoc_dstar g (x :: u) v h
            simp_all
          · have := gm_snoc_dstar ("**" :: g) u v h
            rw [List.cons_append] at this
            simp [this]
      · cases u with
        | nil => rw [gm_cons_nil y g hy] at h; cases h
        | cons x u =>
          rw [gm_cons_cons y g x u hy] at h
          simp only [Bool.and_eq_true] at h
          rw [List.cons_append, List.cons_append, gm_cons_cons y _ x _ hy]
          simp [h.1, gm_snoc_dstar g u v h.2]
termination_by g u => g.length + u.length

/-- A match of `g ++ ["**"]` splits the path into a part matched by `g` and the rest. -/
theorem gm_snoc_split : ∀ (g p : List String), globMatch (g ++ ["**"]) p = true →
    ∃ u v, p = u ++ v ∧ globMatch g u = true
  | g, p, h => by
    match g, p with
    | [], p => exact ⟨[], p, rfl, by simp [globMatch]⟩
    | y :: g, p =>
      by_cases hy : y = "**"
      · subst hy
        cases p with
        | nil =>
          rw [List.cons_append, gm_star_nil] at h
          obtain ⟨u, v, he, hg⟩ := gm_snoc_split g [] h
          have : u = [] := by
            cases u with
            | nil => rfl
            | cons a u => simp at he
          subst this
          exact ⟨[], [], rfl, by rw [gm_star_nil]; exact hg⟩
        | cons x p =>
          rw [List.cons_append, gm_star_cons] at h
          simp only [Bool.or_eq_true] at h
          rcases h with h | h
          · obtain ⟨u, v, he, hg⟩ := gm_snoc_split g (x :: p) h
            exact ⟨u, v, he, gm_star_of g u hg⟩
          · obtain ⟨u, v, he, hg⟩ := gm_snoc_split ("**" :: g) p h
            refine ⟨x :: u, v, by simp [he], ?_⟩
            rw [gm_star_cons]; simp [hg]
      · cases p with
        | nil => rw [List.cons_append, gm_cons_nil y _ hy] at h; cases h
        | cons x p =>
          rw [List.cons_append, gm_cons_cons y _ x p hy] at h
          simp only [Bool.and_eq_true] at h
          obtain ⟨u, v, he, hg⟩ := gm_snoc_split g p h.2
          refine ⟨x :: u, v, by simp [he], ?_⟩
          rw [gm_cons_cons y g x u hy]; simp [h.1, hg]
termination_by g p => g.length + p.length

/-- A non-empty glob that matches the empty path (so it is all `**`) matches every path. -/
theorem gm_nil_all : ∀ (g s : List String), g ≠ [] → globMatch g [] = true → globMatch g s = true
  | [], _, h, _ => absurd rfl h
  | y :: g, s, _, h => by
    by_cases hy : y = "**"
    · subst hy
      rw [gm_star_nil] at h
      cases g with
      | nil => exact globMatch_dstar s
      | cons z g =>
        have ih := gm_nil_all (z :: g) s (by simp) h
        cases s with
        | nil => rw [gm_star_nil]; exact h
        | cons x s => rw [gm_star_cons]; simp [ih]
    · rw [gm_cons_nil y g hy] at h; cases h

/-- A non-empty glob covers a path (`matchesPath`) exactly when the path is non-empty and `g ++ ["**"]` matches it. -/
theorem matchesPath_iff (g p : List String) (hg : g ≠ []) :
    matchesPath g p = true ↔ p ≠ [] ∧ globMatch (g ++ ["**"]) p = true := by
  constructor
  · intro h
    simp only [matchesPath, List.any_eq_true, List.mem_range] at h
    obtain ⟨k, hk, hm⟩ := h
    refine ⟨by intro e; subst e; simp at hk, ?_⟩
    have := gm_snoc_dstar g _ (p.drop (k + 1)) hm
    rwa [List.take_append_drop] at this
  · rintro ⟨hp, h⟩
    obtain ⟨u, v, he, hm⟩ := gm_snoc_split g p h
    simp only [matchesPath, List.any_eq_true, List.mem_range]
    cases u with
    | nil =>
      cases p with
      | nil => exact absurd rfl hp
      | cons x p =>
        refine ⟨0, by simp, ?_⟩
        exact gm_nil_all g _ hg (by simpa using hm)
    | cons x u =>
      refine ⟨u.length, ?_, ?_⟩
      · rw [he]; simp; omega
      · rw [he]
        have : (x :: u ++ v).take (u.length + 1) = x :: u := by
          rw [List.cons_append, List.take_succ_cons, List.take_append_of_le_length (by omega)]
          simp
        rw [this]; exact hm

/-! ## Two write globs -/

/-- Do two write globs cover a common path? -/
def globsOverlap (a b : String) : Bool :=
  let ga := segs a
  let gb := segs b
  !ga.isEmpty && !gb.isEmpty && globInter (ga ++ ["**"]) (gb ++ ["**"])

/-- A path covered by both globs makes them overlap. -/
theorem globsOverlap_complete (a b : String) (p : List String)
    (ha : matchesPath (segs a) p = true) (hb : matchesPath (segs b) p = true) :
    globsOverlap a b = true := by
  have hna : segs a ≠ [] := by intro e; rw [e, matchesPath_nil] at ha; cases ha
  have hnb : segs b ≠ [] := by intro e; rw [e, matchesPath_nil] at hb; cases hb
  have h1 := ((matchesPath_iff _ _ hna).mp ha).2
  have h2 := ((matchesPath_iff _ _ hnb).mp hb).2
  simp [globsOverlap, globInter_complete _ _ p h1 h2, hna, hnb]

/-- Two globs that overlap cover a common non-empty path. -/
theorem globsOverlap_sound (a b : String) (h : globsOverlap a b = true) :
    ∃ p, matchesPath (segs a) p = true ∧ matchesPath (segs b) p = true := by
  simp only [globsOverlap, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
  obtain ⟨⟨hna, hnb⟩, hi⟩ := h
  obtain ⟨s, h1, h2⟩ := globInter_sound _ _ hi
  by_cases hs : s = []
  · subst hs
    refine ⟨["x"], ?_, ?_⟩
    · exact (matchesPath_iff _ _ hna).mpr ⟨by simp, gm_nil_all _ _ (by simp) h1⟩
    · exact (matchesPath_iff _ _ hnb).mpr ⟨by simp, gm_nil_all _ _ (by simp) h2⟩
  · exact ⟨s, (matchesPath_iff _ _ hna).mpr ⟨hs, h1⟩, (matchesPath_iff _ _ hnb).mpr ⟨hs, h2⟩⟩

/-- Overlap is symmetric. -/
theorem globsOverlap_comm (a b : String) : globsOverlap a b = globsOverlap b a := by
  have key : ∀ a b, globsOverlap a b = true → globsOverlap b a = true := fun a b h => by
    obtain ⟨p, h1, h2⟩ := globsOverlap_sound a b h
    exact globsOverlap_complete b a p h2 h1
  cases h : globsOverlap a b
  · cases h' : globsOverlap b a
    · rfl
    · rw [key b a h'] at h; cases h
  · exact (key a b h).symm

/-! ## Task rows and the start verdict -/

/-- A work graph task as this check reads it: its id and its `writes` globs. -/
structure Row where
  id : String
  writes : List String

/-- One overlapping pair of write globs: task `a` writes `ga`, task `b` writes `gb`. -/
structure Conflict where
  a : String
  b : String
  ga : String
  gb : String
deriving DecidableEq

/-- The include globs of a `writes` list (`!` excludes are not read, so the check never misses a pair). -/
def incl (ws : List String) : List String := ws.filter fun w => !w.startsWith "!"

/-- Every pair (glob of `r`, glob of `s`) that overlaps. -/
def conflictsOf (r s : Row) : List Conflict :=
  (incl r.writes).flatMap fun x => (incl s.writes).filterMap fun y =>
    if globsOverlap x y then some ⟨r.id, s.id, x, y⟩ else none

/-- A conflict of `conflictsOf` is exactly an overlapping pair of include globs. -/
theorem mem_conflictsOf (r s : Row) (c : Conflict) :
    c ∈ conflictsOf r s ↔
      ∃ x ∈ incl r.writes, ∃ y ∈ incl s.writes, globsOverlap x y = true ∧ c = ⟨r.id, s.id, x, y⟩ := by
  simp only [conflictsOf, List.mem_flatMap, List.mem_filterMap]
  constructor
  · rintro ⟨x, hx, y, hy, h⟩
    by_cases ho : globsOverlap x y = true
    · simp [ho] at h
      exact ⟨x, hx, y, hy, ho, h.symm⟩
    · simp [ho] at h
  · rintro ⟨x, hx, y, hy, ho, rfl⟩
    exact ⟨x, hx, y, hy, by simp [ho]⟩

/-- The row of a task id. -/
def find (rows : List Row) (id : String) : Option Row := rows.find? fun r => r.id == id

/-- Unordered pairs of distinct positions. -/
def pairs : List String → List (String × String)
  | [] => []
  | a :: t => t.map (a, ·) ++ pairs t

/-- The pairs to check: the candidate against each other running task, else every pair of running tasks. -/
def subjects (running : List String) : Option String → List (String × String)
  | some c => (running.filter (· != c)).map (c, ·)
  | none => pairs running

/-- All conflicts of the subject pairs whose two rows are in the graph. -/
def conflicts (rows : List Row) (running : List String) (cand : Option String) : List Conflict :=
  (subjects running cand).flatMap fun (a, b) =>
    match find rows a, find rows b with
    | some r, some s => conflictsOf r s
    | _, _ => []

/-- Ids named in the request (candidate and running) that are not in the graph, once each. -/
def unknownIds (rows : List Row) (running : List String) (cand : Option String) : List String :=
  ((cand.toList ++ running).filter fun i => (find rows i).isNone).eraseDups

/-- An override counts only with a reason that has a non-blank character. -/
def validReason : Option String → Bool
  | some r => !(r.all Char.isWhitespace)
  | none => false

/-- The start verdict. -/
inductive Verdict | clear | refused | overridden | unknown
deriving DecidableEq

/-- Verdict name in the reply. -/
def Verdict.name : Verdict → String
  | .clear => "clear" | .refused => "refused" | .overridden => "overridden" | .unknown => "unknown"

/-- Unknown id, else clear without conflict, else overridden with a non-blank reason, else refused. -/
def verdict (rows : List Row) (running : List String) (cand : Option String) (ov : Option String) : Verdict :=
  if unknownIds rows running cand ≠ [] then .unknown
  else if conflicts rows running cand = [] then .clear
  else if validReason ov then .overridden else .refused

/-- `unknown` branch. -/
theorem verdict_unknown_iff (rows running cand ov) :
    verdict rows running cand ov = .unknown ↔ unknownIds rows running cand ≠ [] := by
  unfold verdict
  by_cases h1 : unknownIds rows running cand = [] <;> by_cases h2 : conflicts rows running cand = [] <;>
    cases hv : validReason ov <;> simp_all

/-- `clear` branch: every id is known and no pair overlaps. -/
theorem verdict_clear_iff (rows running cand ov) :
    verdict rows running cand ov = .clear ↔
      unknownIds rows running cand = [] ∧ conflicts rows running cand = [] := by
  unfold verdict
  by_cases h1 : unknownIds rows running cand = [] <;> by_cases h2 : conflicts rows running cand = [] <;>
    cases hv : validReason ov <;> simp_all

/-- `overridden` branch: all ids known, a conflict, and a valid reason. -/
theorem verdict_overridden_iff (rows running cand ov) :
    verdict rows running cand ov = .overridden ↔
      unknownIds rows running cand = [] ∧ conflicts rows running cand ≠ [] ∧ validReason ov = true := by
  unfold verdict
  by_cases h1 : unknownIds rows running cand = [] <;> by_cases h2 : conflicts rows running cand = [] <;>
    cases hv : validReason ov <;> simp_all

/-- `refused` branch: all ids known, a conflict, and no valid reason. -/
theorem verdict_refused_iff (rows running cand ov) :
    verdict rows running cand ov = .refused ↔
      unknownIds rows running cand = [] ∧ conflicts rows running cand ≠ [] ∧ validReason ov = false := by
  unfold verdict
  by_cases h1 : unknownIds rows running cand = [] <;> by_cases h2 : conflicts rows running cand = [] <;>
    cases hv : validReason ov <;> simp_all

/-- Without a reason, a conflict is never let through. -/
theorem no_reason_no_start (rows running cand) (h : conflicts rows running cand ≠ []) :
    verdict rows running cand none = .refused ∨ verdict rows running cand none = .unknown := by
  unfold verdict
  split <;> simp_all [validReason]

/-- Write globs of the candidate and a running task that cover a common path never give `clear`. -/
theorem overlap_not_clear (rows : List Row) (running : List String) (c sid : String) (ov : Option String)
    (r s : Row) (hr : find rows c = some r) (hs : find rows sid = some s)
    (hrun : sid ∈ running) (hne : sid ≠ c)
    (x y : String) (hx : x ∈ incl r.writes) (hy : y ∈ incl s.writes) (p : List String)
    (hpx : matchesPath (segs x) p = true) (hpy : matchesPath (segs y) p = true) :
    verdict rows running (some c) ov ≠ .clear := by
  intro hc
  rw [verdict_clear_iff] at hc
  have hov := globsOverlap_complete x y p hpx hpy
  have hmem : (⟨r.id, s.id, x, y⟩ : Conflict) ∈ conflicts rows running (some c) := by
    simp only [conflicts, subjects, List.mem_flatMap, List.mem_map, List.mem_filter]
    refine ⟨(c, sid), ⟨sid, ⟨hrun, by simpa using hne⟩, rfl⟩, ?_⟩
    rw [hr, hs]
    exact (mem_conflictsOf r s _).mpr ⟨x, hx, y, hy, hov, rfl⟩
  rw [hc.2] at hmem
  cases hmem

/-- Every conflict reported is a real overlap. -/
theorem conflict_sound (r s : Row) (c : Conflict) (h : c ∈ conflictsOf r s) :
    ∃ p, matchesPath (segs c.ga) p = true ∧ matchesPath (segs c.gb) p = true := by
  obtain ⟨x, _, y, _, ho, rfl⟩ := (mem_conflictsOf r s c).mp h
  exact globsOverlap_sound x y ho

/-! ## Examples -/

#guard globsOverlap "lean/Fw/Parts/MorphTweenOpt.lean" "lean/Fw/Parts/MorphTweenOpt.lean"
#guard globsOverlap "apps/site/src/parts/morph.tween/**" "apps/site/src/parts/morph.tween/**"
-- glob against file
#guard globsOverlap "apps/site/src/parts/morph.tween/**" "apps/site/src/parts/morph.tween/a/b.ts"
#guard globsOverlap "apps/site/src/parts/morph.tween/a.ts" "apps/site/src/parts/morph.tween/**"
-- glob against glob
#guard globsOverlap "apps/site/src/**/morph.tween/*.ts" "apps/site/src/parts/**"
#guard globsOverlap "packages/measure-*" "packages/measure-webkit/src/**"
#guard globsOverlap "lean/**" "lean/Fw/Plan/Overlap.lean"
#guard globsOverlap "lean/Fw/Plan" "lean/Fw/Plan/Overlap.lean"
-- disjoint
#guard !globsOverlap "lean/Fw/Plan/Overlap.lean" "lean/Fw/Plan/Lint.lean"
#guard !globsOverlap "docs/**" "lean/**"
#guard !globsOverlap "a/*.ts" "a/b/c.ts"
#guard !globsOverlap "apps/runner/src/plan-overlap*.ts" "apps/runner/src/plan.ts"
#guard !globsOverlap "" "lean/**"

private def exRows : List Row := [
  ⟨"waapi-nav-width-tail", ["lean/Fw/Parts/MorphTweenOpt.lean", "apps/site/src/parts/morph.tween/**"]⟩,
  ⟨"morph-scroll-lock", ["lean/Fw/Parts/MorphTweenOpt.lean", "apps/site/src/parts/morph.tween/**", "!docs/x"]⟩,
  ⟨"spawn-write-overlap", ["lean/Fw/Plan/Overlap.lean", "apps/runner/src/plan-overlap*.ts"]⟩]

#guard (conflicts exRows ["morph-scroll-lock"] (some "waapi-nav-width-tail")).length == 2
#guard verdict exRows ["morph-scroll-lock"] (some "waapi-nav-width-tail") none == .refused
#guard verdict exRows ["morph-scroll-lock"] (some "waapi-nav-width-tail") (some "  ") == .refused
#guard verdict exRows ["morph-scroll-lock"] (some "waapi-nav-width-tail") (some "disjoint halves") == .overridden
#guard verdict exRows ["morph-scroll-lock"] (some "spawn-write-overlap") none == .clear
#guard verdict exRows ["nope"] (some "spawn-write-overlap") none == .unknown
#guard verdict exRows ["morph-scroll-lock", "waapi-nav-width-tail", "spawn-write-overlap"] none none == .refused

end Fw.Plan.Overlap
