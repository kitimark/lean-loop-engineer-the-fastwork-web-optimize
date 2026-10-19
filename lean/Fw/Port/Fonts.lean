import Fw.Port.Text

/-! Check 5 of the port completeness gate: fonts. Per viewport and arm, a browser reports each text leaf with the
computed first font family, weight and style of its element, and the loaded faces of `document.fonts`. -/

namespace Fw.Port.Fonts

open Fw.Port.Sections

/-- One text leaf of an arm: the owning section, its text and the computed font of its element.
$$\ell = (s, t, \phi, w, \sigma)$$ -/
structure Leaf where
  sec : String
  text : String
  family : String
  weight : String
  style : String
deriving Repr, DecidableEq

/-- One `FontFace` of `document.fonts`.
$$f = (\phi, w, \sigma, \kappa)$$ -/
structure Face where
  family : String
  weight : String
  style : String
  status : String
deriving Repr, DecidableEq

/-- What one arm reports at one viewport. -/
structure Arm where
  leaves : List Leaf
  faces : List Face
deriving Repr

/-- The compared leaves: those with text left after `Fw.Port.Text.norm`, the text normalised, and blanked in a section
whose whole text is excluded (the text still differs there, the font must not).
$$U(E, L) = [\ell[t \mapsto \tau_E(\ell)] \mid \ell \in L,\ \operatorname{norm}(\ell.t) \ne \texttt{""}],\quad \tau_E(\ell) = \begin{cases} \texttt{""} & \operatorname{exclIn}(E, \mathrm{text}, \ell.s, \texttt{*}) \\ \operatorname{norm}(\ell.t) & \text{otherwise} \end{cases}$$ -/
def units (E : List Excl) (L : List Leaf) : List Leaf :=
  (L.filter fun l => Fw.Port.Text.norm l.text != "").map fun l =>
    { l with text := if exclIn E .text l.sec "*" then "" else Fw.Port.Text.norm l.text }

/-- The loaded faces as (family, weight, style) triples, without the excluded families.
$$F_E(A) = [(f.\phi, f.w, f.\sigma) \mid f \in A,\ f.\kappa = \texttt{loaded} \land \lnot\operatorname{exclKey}(E, \mathrm{fonts}, f.\phi)]$$ -/
def loaded (E : List Excl) (A : List Face) : List (String × String × String) :=
  (A.filter fun f => f.status == "loaded" && !exclKey E .fonts f.family).map fun f => (f.family, f.weight, f.style)

/-- The elements of `o` that `r` lacks.
$$\operatorname{lacks}(o, r) = [x \in o \mid x \notin r]$$ -/
def lacks {α : Type} [BEq α] (o r : List α) : List α := o.filter fun x => !r.contains x

/-- The verdict at one viewport.
$$V = (\text{leaves lost},\ \text{leaves added},\ \text{faces lost},\ \text{faces added})$$ -/
structure Verdict where
  missing : List Leaf
  extra : List Leaf
  missingFaces : List (String × String × String)
  extraFaces : List (String × String × String)
deriving Repr, DecidableEq

/-- The check of one viewport: leaf units as multisets, loaded faces as sets.
$$\operatorname{check}(E, O, R) = (\operatorname{unmatched}(U_O, U_R),\ \operatorname{unmatched}(U_R, U_O),\ \operatorname{lacks}(F_O, F_R),\ \operatorname{lacks}(F_R, F_O))$$ -/
def check (E : List Excl) (O R : Arm) : Verdict :=
  ⟨unmatched (units E O.leaves) (units E R.leaves), unmatched (units E R.leaves) (units E O.leaves),
    lacks (loaded E O.faces) (loaded E R.faces), lacks (loaded E R.faces) (loaded E O.faces)⟩

/-- The viewport passes when all four lists are empty.
$$\operatorname{pass}(E, O, R) \iff V = ([\,], [\,], [\,], [\,])$$ -/
def pass (E : List Excl) (O R : Arm) : Bool :=
  (check E O R).missing.isEmpty && (check E O R).extra.isEmpty && (check E O R).missingFaces.isEmpty &&
    (check E O R).extraFaces.isEmpty

/-- Membership in `lacks`.
$$x \in \operatorname{lacks}(o, r) \iff x \in o \land x \notin r$$ -/
theorem mem_lacks {α : Type} [BEq α] [LawfulBEq α] (o r : List α) (x : α) :
    x ∈ lacks o r ↔ x ∈ o ∧ x ∉ r := by
  simp [lacks]

/-- A leaf the original has more often than the rewrite fails the viewport.
$$\operatorname{count}(u, U_R) < \operatorname{count}(u, U_O) \Rightarrow \lnot\operatorname{pass}(E, O, R)$$ -/
theorem fail_of_missing_leaf (E : List Excl) (O R : Arm) (u : Leaf)
    (h : (units E R.leaves).count u < (units E O.leaves).count u) : pass E O R = false := by
  have h1 := unmatched_nil_iff (units E O.leaves) (units E R.leaves)
  cases hp : pass E O R with
  | false => rfl
  | true =>
    simp only [pass, check, Bool.and_eq_true, List.isEmpty_iff] at hp
    have := h1.mp hp.1.1.1 u
    omega

/-- A leaf the rewrite has more often than the original fails the viewport.
$$\operatorname{count}(u, U_O) < \operatorname{count}(u, U_R) \Rightarrow \lnot\operatorname{pass}(E, O, R)$$ -/
theorem fail_of_extra_leaf (E : List Excl) (O R : Arm) (u : Leaf)
    (h : (units E O.leaves).count u < (units E R.leaves).count u) : pass E O R = false := by
  have h1 := unmatched_nil_iff (units E R.leaves) (units E O.leaves)
  cases hp : pass E O R with
  | false => rfl
  | true =>
    simp only [pass, check, Bool.and_eq_true, List.isEmpty_iff] at hp
    have := h1.mp hp.1.1.2 u
    omega

/-- A face the original loads and the rewrite does not fails the viewport.
$$t \in F_O \land t \notin F_R \Rightarrow \lnot\operatorname{pass}(E, O, R)$$ -/
theorem fail_of_missing_face (E : List Excl) (O R : Arm) (t : String × String × String)
    (ho : t ∈ loaded E O.faces) (hr : t ∉ loaded E R.faces) : pass E O R = false := by
  cases hp : pass E O R with
  | false => rfl
  | true =>
    simp only [pass, check, Bool.and_eq_true, List.isEmpty_iff] at hp
    have : t ∈ lacks (loaded E O.faces) (loaded E R.faces) := (mem_lacks _ _ _).mpr ⟨ho, hr⟩
    rw [hp.1.2] at this
    simp at this

/-- A face the rewrite loads and the original does not fails the viewport.
$$t \in F_R \land t \notin F_O \Rightarrow \lnot\operatorname{pass}(E, O, R)$$ -/
theorem fail_of_extra_face (E : List Excl) (O R : Arm) (t : String × String × String)
    (hr : t ∈ loaded E R.faces) (ho : t ∉ loaded E O.faces) : pass E O R = false := by
  cases hp : pass E O R with
  | false => rfl
  | true =>
    simp only [pass, check, Bool.and_eq_true, List.isEmpty_iff] at hp
    have : t ∈ lacks (loaded E R.faces) (loaded E O.faces) := (mem_lacks _ _ _).mpr ⟨hr, ho⟩
    rw [hp.2] at this
    simp at this

/-- A viewport passes exactly when the leaf units are equal as multisets and the loaded faces equal as sets.
$$\operatorname{pass}(E, O, R) \iff (\forall u,\ \operatorname{count}(u, U_O) = \operatorname{count}(u, U_R)) \land (\forall t,\ t \in F_O \iff t \in F_R)$$ -/
theorem pass_iff (E : List Excl) (O R : Arm) :
    pass E O R = true ↔ (∀ u, (units E O.leaves).count u = (units E R.leaves).count u) ∧
      (∀ t, t ∈ loaded E O.faces ↔ t ∈ loaded E R.faces) := by
  have h1 := unmatched_nil_iff (units E O.leaves) (units E R.leaves)
  have h2 := unmatched_nil_iff (units E R.leaves) (units E O.leaves)
  simp only [pass, check, Bool.and_eq_true, List.isEmpty_iff]
  constructor
  · rintro ⟨⟨⟨a, b⟩, c⟩, d⟩
    refine ⟨fun u => Nat.le_antisymm (h1.mp a u) (h2.mp b u), fun t => ⟨fun ht => ?_, fun ht => ?_⟩⟩
    · refine Classical.byContradiction fun hn => ?_
      have : t ∈ lacks (loaded E O.faces) (loaded E R.faces) := (mem_lacks _ _ _).mpr ⟨ht, hn⟩
      rw [c] at this; simp at this
    · refine Classical.byContradiction fun hn => ?_
      have : t ∈ lacks (loaded E R.faces) (loaded E O.faces) := (mem_lacks _ _ _).mpr ⟨ht, hn⟩
      rw [d] at this; simp at this
  · rintro ⟨hc, hf⟩
    refine ⟨⟨⟨h1.mpr fun u => Nat.le_of_eq (hc u), h2.mpr fun u => Nat.le_of_eq (hc u).symm⟩, ?_⟩, ?_⟩
    · apply List.eq_nil_iff_forall_not_mem.mpr
      intro t ht
      have := (mem_lacks _ _ _).mp ht
      exact this.2 ((hf t).mp this.1)
    · apply List.eq_nil_iff_forall_not_mem.mpr
      intro t ht
      have := (mem_lacks _ _ _).mp ht
      exact this.2 ((hf t).mpr this.1)

/-- An arm passes against itself.
$$\forall E, A:\ \operatorname{pass}(E, A, A)$$ -/
theorem pass_self (E : List Excl) (A : Arm) : pass E A A = true :=
  (pass_iff E A A).mpr ⟨fun _ => rfl, fun _ => Iff.rfl⟩

/-- In a section whose whole text is excluded, every compared leaf has empty text, so only its font is compared.
$$\forall u \in U(E, L):\ \operatorname{exclIn}(E, \mathrm{text}, u.s, \texttt{*}) \Rightarrow u.t = \texttt{""}$$ -/
theorem units_blank (E : List Excl) (L : List Leaf) (u : Leaf) (hu : u ∈ units E L)
    (h : exclIn E .text u.sec "*" = true) : u.text = "" := by
  simp only [units, List.mem_map, List.mem_filter] at hu
  obtain ⟨l, _, rfl⟩ := hu
  simp_all

/-- Two lists with equal elements in no place: an element unmatched on one side is not unmatched on the other.
$$x \in \operatorname{unmatched}(a, b) \Rightarrow x \notin \operatorname{unmatched}(b, a)$$ -/
theorem unmatched_disjoint {α : Type} [BEq α] [LawfulBEq α] (a b : List α) (x : α)
    (h : x ∈ unmatched a b) : x ∉ unmatched b a := by
  intro h'
  have h1 := count_unmatched a b x
  have h2 := count_unmatched b a x
  have p1 : 0 < (unmatched a b).count x := List.count_pos_iff.mpr h
  have p2 : 0 < (unmatched b a).count x := List.count_pos_iff.mpr h'
  omega

/-- Pair each element of `ms` with the first not yet used element of `es` it relates to; the pairs, the unpaired of `ms` and the
unpaired of `es`.
$$\operatorname{pairOff}(p, m :: M, E) = \begin{cases} ((m, e) :: P, U_M, U_E) & e = \operatorname{find}(p\ m, E),\ (P, U_M, U_E) = \operatorname{pairOff}(p, M, E \setminus \{e\}) \\ (P, m :: U_M, U_E) & \text{no such } e \end{cases}$$ -/
def pairOff {α : Type} [BEq α] (p : α → α → Bool) : List α → List α → List (α × α) × List α × List α
  | [], es => ([], [], es)
  | m :: ms, es =>
    match es.find? (p m) with
    | some e =>
      let r := pairOff p ms (es.erase e)
      ((m, e) :: r.1, r.2.1, r.2.2)
    | none =>
      let r := pairOff p ms es
      (r.1, m :: r.2.1, r.2.2)

/-- Every pair is related.
$$(m, e) \in P \Rightarrow p(m, e)$$ -/
theorem pairOff_rel {α : Type} [BEq α] [LawfulBEq α] (p : α → α → Bool) (ms es : List α) (m e : α)
    (h : (m, e) ∈ (pairOff p ms es).1) : p m e = true := by
  induction ms generalizing es with
  | nil => simp [pairOff] at h
  | cons a ms ih =>
    simp only [pairOff] at h
    split at h
    · rename_i e' he'
      simp only [List.mem_cons, Prod.mk.injEq] at h
      rcases h with ⟨rfl, rfl⟩ | h
      · exact List.find?_some he'
      · exact ih _ h
    · exact ih _ h

/-- Everything that comes out of the pairing was in an input: pairs and unpaired of `ms` come from `ms`, pairs and unpaired of `es`
from `es`.
$$(m, e) \in P \Rightarrow m \in M \land e \in E,\qquad u \in U_M \Rightarrow u \in M,\qquad u \in U_E \Rightarrow u \in E$$ -/
theorem pairOff_mem {α : Type} [BEq α] [LawfulBEq α] (p : α → α → Bool) (ms es : List α) :
    (∀ m e, (m, e) ∈ (pairOff p ms es).1 → m ∈ ms ∧ e ∈ es) ∧ (∀ u, u ∈ (pairOff p ms es).2.1 → u ∈ ms) ∧
      (∀ u, u ∈ (pairOff p ms es).2.2 → u ∈ es) := by
  induction ms generalizing es with
  | nil => simp [pairOff]
  | cons a ms ih =>
    simp only [pairOff]
    split
    · rename_i e' he'
      have hm := List.mem_of_find?_eq_some he'
      obtain ⟨i1, i2, i3⟩ := ih (es.erase e')
      refine ⟨fun m e h => ?_, fun u hu => ?_, fun u hu => ?_⟩
      · simp only [List.mem_cons, Prod.mk.injEq] at h
        rcases h with ⟨rfl, rfl⟩ | h
        · exact ⟨by simp, hm⟩
        · have := i1 m e h
          exact ⟨List.mem_cons_of_mem _ this.1, List.mem_of_mem_erase this.2⟩
      · exact List.mem_cons_of_mem _ (i2 u hu)
      · exact List.mem_of_mem_erase (i3 u hu)
    · obtain ⟨i1, i2, i3⟩ := ih es
      refine ⟨fun m e h => ?_, fun u hu => ?_, fun u hu => ?_⟩
      · have := i1 m e h
        exact ⟨List.mem_cons_of_mem _ this.1, this.2⟩
      · simp only [List.mem_cons] at hu
        rcases hu with rfl | hu
        · simp
        · exact List.mem_cons_of_mem _ (i2 u hu)
      · exact i3 u hu

/-- Pairing neither loses nor invents an element: each side is its pairs plus its unpaired.
$$|P| + |U_M| = |M| \land |P| + |U_E| = |E|$$ -/
theorem pairOff_length {α : Type} [BEq α] [LawfulBEq α] (p : α → α → Bool) (ms es : List α) :
    (pairOff p ms es).1.length + (pairOff p ms es).2.1.length = ms.length ∧
      (pairOff p ms es).1.length + (pairOff p ms es).2.2.length = es.length := by
  induction ms generalizing es with
  | nil => simp [pairOff]
  | cons a ms ih =>
    simp only [pairOff]
    split
    · rename_i e' he'
      have hm := List.mem_of_find?_eq_some he'
      have hl := List.length_erase_of_mem hm
      have hpos : 0 < es.length := List.length_pos_of_mem hm
      have := ih (es.erase e')
      simp only [List.length_cons]
      omega
    · have := ih es
      simp only [List.length_cons]
      omega

/-- Same section and same text: the leaf is in both arms and only its font can differ. -/
def sameKey (m e : Leaf) : Bool := m.sec == e.sec && m.text == e.text

/-- Same text and same font: the leaf is in both arms and only its owning section can differ. -/
def sameFont (m e : Leaf) : Bool :=
  m.text == e.text && m.family == e.family && m.weight == e.weight && m.style == e.style

/-- The leaf difference of one viewport told apart: font changes, ownership moves, and the leaves of one arm only.
$$S = (\text{changes},\ \text{moves},\ \text{lost},\ \text{added})$$ -/
structure Split where
  changes : List (Leaf × Leaf)
  moves : List (Leaf × Leaf)
  lost : List Leaf
  added : List Leaf
deriving Repr, DecidableEq

/-- Pair the lost and the added leaves by (section, text) for the font changes, then the rest by (text, font) for the ownership moves.
$$S(E, O, R) = (P_1,\ P_2,\ U_2^{M},\ U_2^{E}),\quad (P_1, U_1^M, U_1^E) = \operatorname{pairOff}(\mathrm{key}, V.\mathrm{missing}, V.\mathrm{extra}),\ (P_2, U_2^M, U_2^E) = \operatorname{pairOff}(\mathrm{font}, U_1^M, U_1^E)$$ -/
def split (E : List Excl) (O R : Arm) : Split :=
  let v := check E O R
  let a := pairOff sameKey v.missing v.extra
  let b := pairOff sameFont a.2.1 a.2.2
  ⟨a.1, b.1, b.2.1, b.2.2⟩

/-- Facts of `split` about the lost and added leaves: they come from the check and are never equal to each other. -/
theorem split_sources (E : List Excl) (O R : Arm) :
    (∀ m e, (m, e) ∈ (split E O R).changes → m ∈ (check E O R).missing ∧ e ∈ (check E O R).extra) ∧
    (∀ m e, (m, e) ∈ (split E O R).moves → m ∈ (check E O R).missing ∧ e ∈ (check E O R).extra) := by
  obtain ⟨a1, a2, a3⟩ := pairOff_mem sameKey (check E O R).missing (check E O R).extra
  obtain ⟨b1, b2, b3⟩ := pairOff_mem sameFont (pairOff sameKey (check E O R).missing (check E O R).extra).2.1
    (pairOff sameKey (check E O R).missing (check E O R).extra).2.2
  exact ⟨fun m e h => a1 m e h, fun m e h => ⟨a2 m (b1 m e h).1, a3 e (b1 m e h).2⟩⟩

/-- A font change keeps the section and the text and changes the font.
$$(m, e) \in \text{changes} \Rightarrow m.s = e.s \land m.t = e.t \land (m.\phi, m.w, m.\sigma) \ne (e.\phi, e.w, e.\sigma)$$ -/
theorem change_font_differs (E : List Excl) (O R : Arm) (m e : Leaf) (h : (m, e) ∈ (split E O R).changes) :
    m.sec = e.sec ∧ m.text = e.text ∧ (m.family ≠ e.family ∨ m.weight ≠ e.weight ∨ m.style ≠ e.style) := by
  have hk : sameKey m e = true := pairOff_rel sameKey _ _ m e h
  have hs := (split_sources E O R).1 m e h
  have hne : m ≠ e := by
    rintro rfl
    exact unmatched_disjoint _ _ m hs.1 hs.2
  simp only [sameKey, Bool.and_eq_true, beq_iff_eq] at hk
  obtain ⟨hk1, hk2⟩ := hk
  refine ⟨hk1, hk2, Classical.byContradiction fun hc => ?_⟩
  simp only [not_or, ne_eq, Decidable.not_not] at hc
  apply hne
  cases m; cases e
  simp_all

/-- An ownership move keeps the text and the font and changes the section.
$$(m, e) \in \text{moves} \Rightarrow m.t = e.t \land (m.\phi, m.w, m.\sigma) = (e.\phi, e.w, e.\sigma) \land m.s \ne e.s$$ -/
theorem move_sec_differs (E : List Excl) (O R : Arm) (m e : Leaf) (h : (m, e) ∈ (split E O R).moves) :
    m.text = e.text ∧ m.family = e.family ∧ m.weight = e.weight ∧ m.style = e.style ∧ m.sec ≠ e.sec := by
  have hk : sameFont m e = true := pairOff_rel sameFont _ _ m e h
  have hs := (split_sources E O R).2 m e h
  have hne : m ≠ e := by
    rintro rfl
    exact unmatched_disjoint _ _ m hs.1 hs.2
  simp only [sameFont, Bool.and_eq_true, beq_iff_eq] at hk
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := hk
  refine ⟨h1, h2, h3, h4, ?_⟩
  intro hc
  apply hne
  cases m; cases e
  simp_all

/-- Nothing is dropped from the lost leaves: they are the changes, the moves and the unpaired lost leaves.
$$|V.\mathrm{missing}| = |\text{changes}| + |\text{moves}| + |\text{lost}|$$ -/
theorem split_missing_length (E : List Excl) (O R : Arm) :
    (check E O R).missing.length = (split E O R).changes.length + (split E O R).moves.length + (split E O R).lost.length := by
  have h1 := (pairOff_length sameKey (check E O R).missing (check E O R).extra).1
  have h2 := (pairOff_length sameFont (pairOff sameKey (check E O R).missing (check E O R).extra).2.1
    (pairOff sameKey (check E O R).missing (check E O R).extra).2.2).1
  simp only [split]
  omega

/-- Nothing is dropped from the added leaves: they are the changes, the moves and the unpaired added leaves.
$$|V.\mathrm{extra}| = |\text{changes}| + |\text{moves}| + |\text{added}|$$ -/
theorem split_extra_length (E : List Excl) (O R : Arm) :
    (check E O R).extra.length = (split E O R).changes.length + (split E O R).moves.length + (split E O R).added.length := by
  have h1 := (pairOff_length sameKey (check E O R).missing (check E O R).extra).2
  have h2 := (pairOff_length sameFont (pairOff sameKey (check E O R).missing (check E O R).extra).2.1
    (pairOff sameKey (check E O R).missing (check E O R).extra).2.2).2
  simp only [split]
  omega

/-- The leaf part of the check is clean exactly when the split is empty.
$$(V.\mathrm{missing} = [\,] \land V.\mathrm{extra} = [\,]) \iff \text{changes} = \text{moves} = \text{lost} = \text{added} = [\,]$$ -/
theorem split_empty_iff (E : List Excl) (O R : Arm) :
    ((check E O R).missing = [] ∧ (check E O R).extra = []) ↔
      ((split E O R).changes = [] ∧ (split E O R).moves = [] ∧ (split E O R).lost = [] ∧ (split E O R).added = []) := by
  have h1 := split_missing_length E O R
  have h2 := split_extra_length E O R
  constructor
  · rintro ⟨a, b⟩
    rw [a] at h1
    rw [b] at h2
    simp only [List.length_nil] at h1 h2
    refine ⟨List.length_eq_zero_iff.mp (by omega), List.length_eq_zero_iff.mp (by omega), List.length_eq_zero_iff.mp (by omega),
      List.length_eq_zero_iff.mp (by omega)⟩
  · rintro ⟨a, b, c, d⟩
    rw [a, b, c] at h1
    rw [a, b, d] at h2
    exact ⟨List.length_eq_zero_iff.mp h1, List.length_eq_zero_iff.mp h2⟩

/-- The fonts exclusions: the family the original declares but no rule applies.
$$E_{\mathrm{fonts}} = [(\mathrm{fonts}, \texttt{page}, \texttt{Fastwork}, \rho)]$$ -/
def exclusions : List Excl := [
  ⟨.fonts, "page", "Fastwork", "declared as /fonts/fastwork-Bold.ttf, never applied by a rule, so never loaded (the assets exclusion of the same file)"⟩]

/-- The fonts exclusions are well formed and all belong to the fonts check.
$$\operatorname{wf}(E_{\mathrm{fonts}}) \land \forall e \in E_{\mathrm{fonts}},\ e.c = \mathrm{fonts}$$ -/
theorem exclusions_wf : wf exclusions = true ∧ ∀ e ∈ exclusions, e.check = .fonts := by decide

/-- The text and font exclusions the check runs with. -/
def excl : List Excl := Fw.Port.Text.exclusions ++ exclusions

/-- The reference pair of an arm: the leaf `pain.notes` draws in Google Sans, and the faces it loads. -/
def refArm : Arm :=
  ⟨[⟨"pain.notes", "Hello  world", "Google Sans", "400", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩],
   [⟨"Google Sans", "400 700", "normal", "loaded"⟩, ⟨"Google Sans", "400 700", "italic", "unloaded"⟩,
    ⟨"Fastwork", "700", "normal", "unloaded"⟩]⟩

#guard pass excl refArm refArm
#guard pass excl refArm ⟨[⟨"pain.notes", "Hello world", "Google Sans", "400", "normal"⟩,
  ⟨"hero.countdown", "02", "Google Sans", "700", "normal"⟩], refArm.faces⟩
#guard !pass excl refArm ⟨[⟨"pain.notes", "Hello world", "Playpen Sans Start Selling", "400", "normal"⟩,
  ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩], refArm.faces⟩
#guard !pass excl refArm ⟨refArm.leaves, []⟩
#guard pass excl refArm ⟨refArm.leaves, refArm.faces ++ [⟨"Fastwork", "700", "normal", "loaded"⟩]⟩
#guard !pass excl refArm ⟨refArm.leaves, refArm.faces ++ [⟨"Google Sans", "400 700", "italic", "loaded"⟩]⟩

#guard (split excl refArm ⟨[⟨"pain.notes", "Hello world", "Arial", "400", "normal"⟩, ⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩], refArm.faces⟩).changes.length == 1
#guard (split excl refArm ⟨[⟨"hero.countdown", "01", "Google Sans", "700", "normal"⟩, ⟨"page", "Hello world", "Google Sans", "400", "normal"⟩], refArm.faces⟩).moves.length == 1

end Fw.Port.Fonts
