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

end Fw.Port.Fonts
