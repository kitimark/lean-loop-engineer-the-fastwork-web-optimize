import Lean.Data.Json
import Fw.Gate.PathPix

namespace Fw.Measure.Census
open Lean
open Fw.Gate.PathPix (onGrid gridDelta)

structure Rect where
  x : Int
  y : Int
  w : Int
  h : Int
deriving DecidableEq, Repr

structure Box where
  name : String
  bounds : Rect
deriving DecidableEq, Repr

structure Layer where
  name : String
  fw : Option String
  layer : Option String
  bounds : Rect
  origin : Option (Int × Int)
  reasons : List String
  bytes : Option Nat
deriving DecidableEq, Repr

structure Sample where
  y : Int
  rendered : List String
  layers : List Layer
deriving DecidableEq, Repr

structure Arm where
  dpr : Nat
  samples : List Sample
deriving DecidableEq, Repr

structure Want where
  composite : List String
  snap : List String
deriving DecidableEq, Repr

def norm : Option String → Option String
  | some "" => none
  | s => s

inductive Ident where
  | box (id : String)
  | part (id : String)
  | free
deriving DecidableEq, Repr

def identOf (fw layer : Option String) : Ident :=
  match norm layer, norm fw with
  | some l, _ => .box l
  | none, some p => .part p
  | none, none => .free

def Layer.ident (l : Layer) : Ident := identOf l.fw l.layer

def nBox (id : String) (ls : List Layer) : Nat := ls.countP fun l => l.ident == .box id

def nPart (id : String) (ls : List Layer) : Nat := ls.countP fun l => l.ident == .part id

theorem identOf_both (f l : String) (h : l ≠ "") : identOf (some f) (some l) = .box l := by
  simp [identOf, norm, h]

theorem identOf_part (f : String) (h : f ≠ "") : identOf (some f) none = .part f := by
  simp [identOf, norm, h]

theorem identOf_free : identOf none none = .free := rfl

theorem identOf_empty : identOf (some "") (some "") = .free := rfl

theorem both_maps_once (l : Layer) (f i : String) (hf : l.fw = some f) (hl : l.layer = some i) (h : i ≠ "") :
    nBox i [l] = 1 ∧ nPart f [l] = 0 := by
  have : l.ident = .box i := by simp [Layer.ident, hf, hl, identOf_both _ _ h]
  simp [nBox, nPart, this]

def undeclared (ls : List Layer) : List Box :=
  ls.filterMap fun l => if l.ident = .free then some ⟨l.name, l.bounds⟩ else none

/-- Box-name prefixes the pass-to-pass check skips. Timer-run animations (INFERRED): accent word, typing line, scroll cue.
Listed after a refusal, mechanism not found: `section.commission.`, `div.fee-visual`, `div.body.svelte-ty4hd7`. Root layer
`#document`: its height is the page height of one load. -/
def runnerStems : List String :=
  ["#document", "span.accent-module_frame_", "svg.accent-module_svg_", "div.typing-module_visual_", "div.typing-module_beat_", "span.typing-module_avatar_",
   "span.frame.", "svg.accent-svg.", "button.scroll-cue.", "section.commission.", "div.fee-visual", "div.body.svelte-ty4hd7"]

def varying (name : String) : Bool := runnerStems.any fun s => name.startsWith s

theorem varying_of_stem (s t : String) (h : s ∈ runnerStems) : varying (s ++ t) = true := by
  simp only [varying, List.any_eq_true]
  exact ⟨s, h, by simp⟩

def Layer.gone (l : Layer) : Bool := l.reasons == ["(gone)"]

def Layer.keeps (l : Layer) : Bool := l.ident == .free && !l.gone && !varying l.name

def stable (ls : List Layer) : List Box := (ls.filter Layer.keeps).map fun l => ⟨l.name, l.bounds⟩

def firstDiff (a b : List Box) : Option Box := (a ++ b).find? fun x => a.count x != b.count x

theorem firstDiff_none_iff (a b : List Box) : firstDiff a b = none ↔ a.isPerm b = true := by
  rw [List.isPerm_iff, List.perm_iff_count, firstDiff, List.find?_eq_none]
  constructor
  · intro h x
    by_cases hx : x ∈ a ++ b
    · have := h x hx
      simpa using this
    · have ha : x ∉ a := fun hm => hx (List.mem_append_left _ hm)
      have hb : x ∉ b := fun hm => hx (List.mem_append_right _ hm)
      rw [List.count_eq_zero_of_not_mem ha, List.count_eq_zero_of_not_mem hb]
  · intro h x _
    simp [h x]

theorem firstDiff_some (a b : List Box) (x : Box) (h : firstDiff a b = some x) :
    a.count x ≠ b.count x ∧ (x ∈ a ∨ x ∈ b) := by
  refine ⟨?_, ?_⟩
  · have := List.find?_some h
    simpa using this
  · simpa using List.mem_of_find?_eq_some h

theorem firstDiff_self (a : List Box) : firstDiff a a = none := by
  rw [firstDiff_none_iff]
  exact List.isPerm_iff.2 (List.Perm.refl a)

theorem undeclared_perm (a b : List Layer) (h : a.Perm b) : (undeclared a).Perm (undeclared b) :=
  h.filterMap _

theorem stable_perm (a b : List Layer) (h : a.Perm b) : (stable a).Perm (stable b) :=
  (h.filter _).map _

theorem stable_cons_gone (l : Layer) (ls : List Layer) (h : l.gone = true) : stable (l :: ls) = stable ls := by
  simp [stable, Layer.keeps, h]

theorem stable_cons_varying (l : Layer) (ls : List Layer) (h : varying l.name = true) : stable (l :: ls) = stable ls := by
  simp [stable, Layer.keeps, h]

theorem stable_cons_declared (l : Layer) (ls : List Layer) (h : l.ident ≠ .free) : stable (l :: ls) = stable ls := by
  simp [stable, Layer.keeps, h]

theorem stable_cons_kept (l : Layer) (ls : List Layer) (h : l.keeps = true) :
    stable (l :: ls) = ⟨l.name, l.bounds⟩ :: stable ls := by
  simp [stable, h]

theorem stable_replicate_varying (l : Layer) (n : Nat) (ls : List Layer) (h : varying l.name = true) :
    stable (List.replicate n l ++ ls) = stable ls := by
  induction n with
  | zero => rfl
  | succ n ih => rw [List.replicate_succ, List.cons_append, stable_cons_varying _ _ h, ih]

theorem stable_replicate_gone (l : Layer) (n : Nat) (ls : List Layer) (h : l.gone = true) :
    stable (List.replicate n l ++ ls) = stable ls := by
  induction n with
  | zero => rfl
  | succ n ih => rw [List.replicate_succ, List.cons_append, stable_cons_gone _ _ h, ih]

theorem stable_mem_free (ls : List Layer) (b : Box) (h : b ∈ stable ls) :
    varying b.name = false ∧ ∃ l ∈ ls, l.ident = .free ∧ l.gone = false ∧ b = ⟨l.name, l.bounds⟩ := by
  simp only [stable, List.mem_map, List.mem_filter, Layer.keeps, Bool.and_eq_true, Bool.not_eq_true'] at h
  obtain ⟨l, ⟨hl, ⟨hi, hg⟩, hv⟩, rfl⟩ := h
  exact ⟨hv, l, hl, by simpa using hi, hg, rfl⟩

inductive Side where
  | a | b
deriving DecidableEq, Repr

inductive Refusal where
  | viewport (a b : Nat)
  | samples (a b : List Int)
  | undeclared (y : Int) (box : Box) (inA inB : Nat)
  | notComposited (side : Side) (y : Int) (id : String) (layers rendered : Nat)
  | noOrigin (side : Side) (y : Int) (id : String)
  | offGrid (side : Side) (y : Int) (id : String) (axis : String)
deriving DecidableEq, Repr

def Refusal.box : Refusal → String
  | .viewport .. | .samples .. => ""
  | .undeclared _ b .. => b.name
  | .notComposited _ _ id .. | .noOrigin _ _ id | .offGrid _ _ id _ => id

def gridOk (dpr : Nat) (o : Int) : Bool := onGrid ((o : Rat) * dpr / 1000000000)

theorem gridOk_exact (dpr : Nat) (o z : Int) (h : o * dpr = z * 1000000000) : gridOk dpr o = true := by
  have e : (o : Rat) * dpr / 1000000000 = z := by
    have : ((o * dpr : Int) : Rat) = ((z * 1000000000 : Int) : Rat) := by rw [h]
    push_cast at this
    rw [this]; grind
  unfold gridOk
  rw [e]
  simp only [onGrid, Fw.Engine.roundQ_int, gridDelta, Bool.and_eq_true, decide_eq_true_eq]
  constructor <;> grind

theorem gridOk_sound (dpr : Nat) (o : Int) (h : gridOk dpr o = true) :
    ∃ z : Int, (o : Rat) * dpr / 1000000000 - z ≤ gridDelta ∧ (z : Rat) - (o : Rat) * dpr / 1000000000 ≤ gridDelta := by
  have := Fw.Gate.PathPix.onGrid_round _ h
  exact ⟨_, this.2.1, this.2.2⟩

theorem gridOk_zero (dpr : Nat) : gridOk dpr 0 = true := gridOk_exact dpr 0 0 (by simp)

def compositeRefusals (side : Side) (w : Want) (s : Sample) : List Refusal :=
  (w.composite ++ w.snap).filterMap fun id =>
    let n := s.rendered.count id
    let k := nBox id s.layers
    if n = 0 ∨ k < n then some (.notComposited side s.y id k n) else none

def gridRefusals (side : Side) (w : Want) (dpr : Nat) (s : Sample) : List Refusal :=
  s.layers.flatMap fun l =>
    match l.ident with
    | .box id =>
      if w.snap.contains id then
        match l.origin with
        | none => [.noOrigin side s.y id]
        | some (ox, oy) =>
          (if gridOk dpr ox then [] else [.offGrid side s.y id "x"]) ++ (if gridOk dpr oy then [] else [.offGrid side s.y id "y"])
      else []
    | _ => []

def armRefusals (side : Side) (w : Want) (arm : Arm) : List Refusal :=
  arm.samples.flatMap fun s => compositeRefusals side w s ++ gridRefusals side w arm.dpr s

def undeclaredAt (sa sb : Sample) : Option Refusal :=
  (firstDiff (stable sa.layers) (stable sb.layers)).map fun x =>
    .undeclared sa.y x ((stable sa.layers).count x) ((stable sb.layers).count x)

def undeclaredRefusals (a b : Arm) : List Refusal :=
  (a.samples.zip b.samples).filterMap fun (sa, sb) => undeclaredAt sa sb

def refusals (wa wb : Want) (a b : Arm) : List Refusal :=
  if a.dpr ≠ b.dpr then [.viewport a.dpr b.dpr]
  else if a.samples.map (·.y) ≠ b.samples.map (·.y) then [.samples (a.samples.map (·.y)) (b.samples.map (·.y))]
  else undeclaredRefusals a b ++ armRefusals .a wa a ++ armRefusals .b wb b

def verdict (wa wb : Want) (a b : Arm) : Option Refusal := (refusals wa wb a b).head?

theorem refusals_viewport (wa wb : Want) (a b : Arm) (h : a.dpr ≠ b.dpr) :
    refusals wa wb a b = [.viewport a.dpr b.dpr] := by
  simp [refusals, h]

theorem refusals_samples (wa wb : Want) (a b : Arm) (h : a.dpr = b.dpr) (hs : a.samples.map (·.y) ≠ b.samples.map (·.y)) :
    refusals wa wb a b = [.samples (a.samples.map (·.y)) (b.samples.map (·.y))] := by
  simp [refusals, h, hs]

theorem undeclaredRefusals_eq_nil_iff (a b : Arm) :
    undeclaredRefusals a b = [] ↔ ∀ p ∈ a.samples.zip b.samples, (stable p.1.layers).isPerm (stable p.2.layers) = true := by
  simp only [undeclaredRefusals, undeclaredAt, List.filterMap_eq_nil_iff]
  constructor
  · intro h p hp
    have := h p hp
    rw [← firstDiff_none_iff]
    cases hd : firstDiff (stable p.1.layers) (stable p.2.layers) <;> simp_all
  · intro h p hp
    have := (firstDiff_none_iff _ _).2 (h p hp)
    simp [this]

theorem undeclaredRefusals_names_box (a b : Arm) (r : Refusal) (h : r ∈ undeclaredRefusals a b) :
    ∃ y x na nb, r = .undeclared y x na nb ∧ na ≠ nb ∧ (0 < na ∨ 0 < nb) ∧ varying x.name = false := by
  simp only [undeclaredRefusals, undeclaredAt, List.mem_filterMap] at h
  obtain ⟨⟨sa, sb⟩, _, hr⟩ := h
  cases hd : firstDiff (stable sa.layers) (stable sb.layers) with
  | none => simp [hd] at hr
  | some x =>
    simp only [hd, Option.map_some, Option.some.injEq] at hr
    obtain ⟨hne, hm⟩ := firstDiff_some _ _ _ hd
    refine ⟨sa.y, x, _, _, hr.symm, hne, ?_, ?_⟩
    · rcases hm with hm | hm
      · exact Or.inl (List.count_pos_iff.2 hm)
      · exact Or.inr (List.count_pos_iff.2 hm)
    · rcases hm with hm | hm
      · exact (stable_mem_free _ _ hm).1
      · exact (stable_mem_free _ _ hm).1

theorem undeclaredAt_cons_gone (l : Layer) (sa sb : Sample) (h : l.gone = true) :
    undeclaredAt { sa with layers := l :: sa.layers } sb = undeclaredAt sa sb := by
  simp [undeclaredAt, stable_cons_gone _ _ h]

theorem undeclaredAt_cons_varying (l : Layer) (sa sb : Sample) (h : varying l.name = true) :
    undeclaredAt { sa with layers := l :: sa.layers } sb = undeclaredAt sa sb := by
  simp [undeclaredAt, stable_cons_varying _ _ h]

theorem undeclaredAt_cons_kept (l : Layer) (sa sb : Sample) (h : l.keeps = true)
    (hp : (stable sa.layers).isPerm (stable sb.layers) = true) :
    undeclaredAt { sa with layers := l :: sa.layers } sb ≠ none := by
  intro hn
  have h0 : firstDiff (stable (l :: sa.layers)) (stable sb.layers) = none := by
    simpa [undeclaredAt] using hn
  rw [firstDiff_none_iff, stable_cons_kept _ _ h] at h0
  have h1 := (List.isPerm_iff.1 h0).length_eq
  have h2 := (List.isPerm_iff.1 hp).length_eq
  simp only [List.length_cons] at h1
  omega

theorem compositeRefusals_eq_nil_iff (side : Side) (w : Want) (s : Sample) :
    compositeRefusals side w s = [] ↔
      ∀ id ∈ w.composite ++ w.snap, 0 < s.rendered.count id ∧ s.rendered.count id ≤ nBox id s.layers := by
  simp only [compositeRefusals, List.filterMap_eq_nil_iff]
  constructor
  · intro h id hid
    have := h id hid
    by_cases c : s.rendered.count id = 0 ∨ nBox id s.layers < s.rendered.count id
    · simp [c] at this
    · omega
  · intro h id hid
    have := h id hid
    have c : ¬ (s.rendered.count id = 0 ∨ nBox id s.layers < s.rendered.count id) := by omega
    simp [c]

theorem gridRefusals_eq_nil_iff (side : Side) (w : Want) (dpr : Nat) (s : Sample) :
    gridRefusals side w dpr s = [] ↔
      ∀ l ∈ s.layers, ∀ id, l.ident = .box id → w.snap.contains id = true →
        ∃ ox oy, l.origin = some (ox, oy) ∧ gridOk dpr ox = true ∧ gridOk dpr oy = true := by
  simp only [gridRefusals, List.flatMap_eq_nil_iff]
  constructor
  · intro h l hl id hid hs
    have := h l hl
    simp only [hid, hs, ite_true] at this
    cases ho : l.origin with
    | none => simp [ho] at this
    | some o =>
      obtain ⟨ox, oy⟩ := o
      simp only [ho] at this
      refine ⟨ox, oy, rfl, ?_, ?_⟩
      · by_cases hx : gridOk dpr ox = true
        · exact hx
        · simp [hx] at this
      · by_cases hy : gridOk dpr oy = true
        · exact hy
        · simp [hy] at this
  · intro h l hl
    cases hid : l.ident with
    | free => simp
    | part _ => simp
    | box id =>
      by_cases hs : w.snap.contains id = true
      · obtain ⟨ox, oy, ho, hx, hy⟩ := h l hl id hid hs
        simp [ho, hx, hy]
      · have hn : id ∉ w.snap := by simpa using hs
        simp [hn]

theorem refusals_eq_nil_iff (wa wb : Want) (a b : Arm) :
    refusals wa wb a b = [] ↔
      a.dpr = b.dpr ∧ a.samples.map (·.y) = b.samples.map (·.y) ∧
      undeclaredRefusals a b = [] ∧ armRefusals .a wa a = [] ∧ armRefusals .b wb b = [] := by
  unfold refusals
  by_cases h1 : a.dpr = b.dpr
  · by_cases h2 : a.samples.map (·.y) = b.samples.map (·.y)
    · simp [h1, h2]
    · simp [h1, h2]
  · simp [h1]

theorem armRefusals_eq_nil_iff (side : Side) (w : Want) (arm : Arm) :
    armRefusals side w arm = [] ↔
      ∀ s ∈ arm.samples, compositeRefusals side w s = [] ∧ gridRefusals side w arm.dpr s = [] := by
  simp [armRefusals, List.flatMap_eq_nil_iff]

theorem zip_self_fst_eq {α : Type} (l : List α) (p : α × α) (hp : p ∈ l.zip l) : p.1 = p.2 := by
  induction l with
  | nil => simp at hp
  | cons x xs ih =>
    rcases List.mem_cons.1 hp with rfl | hp
    · rfl
    · exact ih hp

theorem refusals_self (wa wb : Want) (a : Arm) (h : armRefusals .a wa a = [] ∧ armRefusals .b wb a = []) :
    refusals wa wb a a = [] := by
  rw [refusals_eq_nil_iff]
  refine ⟨rfl, rfl, ?_, h.1, h.2⟩
  rw [undeclaredRefusals_eq_nil_iff]
  intro p hp
  have hz := zip_self_fst_eq _ p hp
  rw [hz]
  exact List.isPerm_iff.2 (List.Perm.refl _)

theorem refusals_ok_iff (wa wb : Want) (a b : Arm) :
    refusals wa wb a b = [] ↔
      a.dpr = b.dpr ∧ a.samples.map (·.y) = b.samples.map (·.y) ∧
      (∀ p ∈ a.samples.zip b.samples, (stable p.1.layers).isPerm (stable p.2.layers) = true) ∧
      (∀ s ∈ a.samples, compositeRefusals .a wa s = [] ∧ gridRefusals .a wa a.dpr s = []) ∧
      (∀ s ∈ b.samples, compositeRefusals .b wb s = [] ∧ gridRefusals .b wb b.dpr s = []) := by
  rw [refusals_eq_nil_iff, undeclaredRefusals_eq_nil_iff, armRefusals_eq_nil_iff, armRefusals_eq_nil_iff]

theorem compositeRefusals_names_id (side : Side) (w : Want) (s : Sample) (r : Refusal)
    (h : r ∈ compositeRefusals side w s) :
    ∃ id ∈ w.composite ++ w.snap, r = .notComposited side s.y id (nBox id s.layers) (s.rendered.count id) ∧
      (s.rendered.count id = 0 ∨ nBox id s.layers < s.rendered.count id) := by
  simp only [compositeRefusals, List.mem_filterMap] at h
  obtain ⟨id, hid, hr⟩ := h
  by_cases c : s.rendered.count id = 0 ∨ nBox id s.layers < s.rendered.count id
  · simp only [c, ite_true, Option.some.injEq] at hr
    exact ⟨id, hid, hr.symm, c⟩
  · simp [c] at hr

theorem gridRefusals_names_id (side : Side) (w : Want) (dpr : Nat) (s : Sample) (r : Refusal)
    (h : r ∈ gridRefusals side w dpr s) : ∃ id, w.snap.contains id = true ∧ r.box = id := by
  simp only [gridRefusals, List.mem_flatMap] at h
  obtain ⟨l, _, hr⟩ := h
  cases hid : l.ident with
  | free => simp [hid] at hr
  | part _ => simp [hid] at hr
  | box id =>
    by_cases hs : w.snap.contains id = true
    · refine ⟨id, hs, ?_⟩
      simp only [hid, hs, ite_true] at hr
      cases ho : l.origin with
      | none => simp [ho] at hr; simp [hr, Refusal.box]
      | some o =>
        obtain ⟨ox, oy⟩ := o
        simp only [ho] at hr
        by_cases hx : gridOk dpr ox = true <;> by_cases hy : gridOk dpr oy = true <;> simp [hx, hy] at hr <;>
          first | (subst hr; rfl) | (rcases hr with rfl | rfl <;> rfl)
    · exfalso
      simp only [hid] at hr
      simp only [hs] at hr
      simp at hr

structure Row where
  ident : Ident
  n : Nat
  bytes : Nat
deriving DecidableEq, Repr

def idents (ls : List Layer) : List Ident := (ls.map Layer.ident |>.filter (· ≠ .free)).eraseDups

def rows (ls : List Layer) : List Row :=
  (idents ls).map fun i =>
    ⟨i, ls.countP (·.ident == i), ((ls.filter (·.ident == i)).map fun l => l.bytes.getD 0).sum⟩

theorem rows_declared (ls : List Layer) (r : Row) (h : r ∈ rows ls) : r.ident ≠ .free := by
  simp only [rows, idents, List.mem_map] at h
  obtain ⟨i, hi, rfl⟩ := h
  have h2 := List.mem_eraseDups.1 hi
  simp at h2
  exact h2.2

theorem rows_n_pos (ls : List Layer) (r : Row) (h : r ∈ rows ls) : 0 < r.n := by
  simp only [rows, idents, List.mem_map] at h
  obtain ⟨i, hi, rfl⟩ := h
  have := (List.mem_eraseDups.1 hi)
  simp only [List.mem_filter, List.mem_map] at this
  obtain ⟨⟨l, hl, rfl⟩, _⟩ := this
  exact List.countP_pos_iff.2 ⟨l, hl, by simp⟩

private def rj (r : Rect) : Json := Json.arr #[toJson r.x, toJson r.y, toJson r.w, toJson r.h]
private def oj (o : Option (Int × Int)) : Json := match o with
  | none => Json.null
  | some (x, y) => Json.arr #[toJson x, toJson y]
private def lj (l : Layer) : Json :=
  Json.mkObj [("name", l.name), ("fw", toJson l.fw), ("layer", toJson l.layer), ("bounds", rj l.bounds),
    ("origin", oj l.origin), ("reasons", toJson l.reasons), ("bytes", toJson l.bytes)]
private def sj (s : Sample) : Json :=
  Json.mkObj [("y", toJson s.y), ("rendered", toJson s.rendered), ("layers", Json.arr (s.layers.map lj).toArray)]
private def aj (a : Arm) : Json := Json.mkObj [("dpr", toJson a.dpr), ("samples", Json.arr (a.samples.map sj).toArray)]
private def wj (w : Want) : Json := Json.mkObj [("composite", toJson w.composite), ("snap", toJson w.snap)]
private def sideJ : Side → Json | .a => "a" | .b => "b"

private def refJ : Refusal → Json
  | .viewport a b => Json.mkObj [("code", "viewport"), ("a", a), ("b", b)]
  | .samples a b => Json.mkObj [("code", "samples"), ("a", toJson a), ("b", toJson b)]
  | .undeclared y x na nb =>
    Json.mkObj [("code", "undeclared"), ("y", toJson y), ("box", x.name), ("bounds", rj x.bounds), ("inA", na), ("inB", nb)]
  | .notComposited s y id n k =>
    Json.mkObj [("code", "notComposited"), ("side", sideJ s), ("y", toJson y), ("box", id), ("layers", n), ("rendered", k)]
  | .noOrigin s y id => Json.mkObj [("code", "noOrigin"), ("side", sideJ s), ("y", toJson y), ("box", id)]
  | .offGrid s y id ax => Json.mkObj [("code", "offGrid"), ("side", sideJ s), ("y", toJson y), ("box", id), ("axis", ax)]

private def rowJ (r : Row) : Json :=
  match r.ident with
  | .box i => Json.mkObj [("kind", "box"), ("id", i), ("n", r.n), ("bytes", r.bytes)]
  | .part i => Json.mkObj [("kind", "part"), ("id", i), ("n", r.n), ("bytes", r.bytes)]
  | .free => Json.mkObj [("kind", "free"), ("id", ""), ("n", r.n), ("bytes", r.bytes)]

private def identJ : Ident → Json
  | .box i => Json.mkObj [("kind", "box"), ("id", i)]
  | .part i => Json.mkObj [("kind", "part"), ("id", i)]
  | .free => Json.mkObj [("kind", "free"), ("id", "")]

private def big : Rect := ⟨0, 0, 390000000, 844000000⟩

private def L (name : String) (fw layer : Option String := none) (b : Rect := big) (o : Option (Int × Int) := none)
    (bytes : Option Nat := some 4096) : Layer :=
  ⟨name, fw, layer, b, o, ["willChange"], bytes⟩

private def root : Layer := L "div#page"
private def hero : Layer := L "div.hero" (some "hero") (some "hero_copy") ⟨0, 80000000, 390000000, 300000000⟩ (some (0, 80000000))
private def nav : Layer := L "nav" (some "nav") (some "nav_bar") ⟨0, 0, 390000000, 64000000⟩ (some (0, 0))
private def side : Layer := L "aside.x" (some "nav_extra") none ⟨0, 0, 10000000, 10000000⟩
private def extra : Layer := L "span.glow" none none ⟨5000000, 5000000, 20000000, 20000000⟩

private def Lr (name : String) (reasons : List String) (b : Rect := big) : Layer := ⟨name, none, none, b, none, reasons, some 4096⟩

private def frameA : Layer := Lr "span.accent-module_frame_0z18R8" ["transformWithCompositedDescendants"] ⟨0, 0, 60000000, 49000000⟩
private def frameB : Layer := Lr "span.accent-module_frame_0z18R8" ["transformWithCompositedDescendants"] ⟨0, 0, 101000000, 47000000⟩
private def idleSvg : Layer := Lr "svg.accent-module_svg_HwEYD1.accent-module_idleFrame_f6M8wO" ["animation", "stacking"] ⟨0, 0, 42000000, 47000000⟩
private def typingVisual : Layer := Lr "div.typing-module_visual_YdYZxz" ["transformWithCompositedDescendants"] ⟨0, 0, 438000000, 225000000⟩
private def origCue : Layer := Lr "button.scroll-cue.svelte-1p2vpne" ["filterWithCompositedDescendants"] ⟨0, -9000000, 77000000, 54000000⟩
private def origFrame : Layer := Lr "span.frame.svelte-1fn2go6" ["(gone)"] ⟨0, 0, 60000000, 49000000⟩
private def goneNode : Layer := Lr "?" ["(gone)"] ⟨0, 0, 1000000, 32000000⟩
private def goneNamed : Layer := Lr "div.start-selling-morph-col" ["(gone)"] ⟨0, 0, 136000000, 52000000⟩
private def nearStem : Layer := Lr "span.accent-module_frame" ["transformWithCompositedDescendants"] ⟨0, 0, 60000000, 49000000⟩
private def nearStem2 : Layer := Lr "div.typing-module_visualX_1" ["transformWithCompositedDescendants"] ⟨0, 0, 60000000, 49000000⟩
private def goneDeclared : Layer := ⟨"nav", some "nav", some "nav_bar", ⟨0, 0, 390000000, 64000000⟩, some (0, 0), ["(gone)"], none⟩

private def smp (y : Int) (ls : List Layer) (rendered : List String := ["hero_copy", "nav_bar"]) : Sample := ⟨y, rendered, ls⟩
private def arm (ss : List Sample) (dpr : Nat := 3000) : Arm := ⟨dpr, ss⟩

private def wA : Want := ⟨["hero_copy"], []⟩
private def wB : Want := ⟨["hero_copy", "nav_bar"], ["nav_bar"]⟩

private def base : List Sample := [smp 0 [root, hero, nav], smp 1500 [root, hero, nav]]

private def navAt (x y : Int) : Layer := L "nav" (some "nav") (some "nav_bar") ⟨0, 0, 390000000, 64000000⟩ (some (x, y))

private def checks : List (String × Want × Want × Arm × Arm) :=
  [("identical", wA, wB, arm base, arm base),
   ("permuted", wA, wB, arm base, arm [smp 0 [nav, hero, root], smp 1500 [hero, root, nav]]),
   ("undeclaredExtraB", wA, wB, arm base, arm [smp 0 [root, hero, nav], smp 1500 [root, extra, hero, nav]]),
   ("undeclaredCount", wA, wB, arm [smp 0 [root, hero, nav], smp 1500 [root, extra, extra, hero, nav]],
     arm [smp 0 [root, hero, nav], smp 1500 [root, extra, hero, nav]]),
   ("partOnlyIgnored", wA, wB, arm base, arm [smp 0 [root, hero, nav, side], smp 1500 [root, hero, nav]]),
   ("emptyAttrsUndeclared", wA, wB, arm base,
     arm [smp 0 [root, hero, nav, L "i.e" (some "") (some "")], smp 1500 [root, hero, nav]]),
   ("viewport", wA, wB, arm base (dpr := 3000), arm base (dpr := 2000)),
   ("samples", wA, wB, arm base, arm [smp 0 [root, hero, nav], smp 1400 [root, hero, nav]]),
   ("compositeMissing", wA, wB, arm [smp 0 [root, nav], smp 1500 [root, nav]], arm base),
   ("notRendered", wA, wB, arm [smp 0 [root, hero, nav] (rendered := ["nav_bar"]), smp 1500 [root, hero, nav]], arm base),
   ("renderedTwiceOnce", wA, wB, arm [smp 0 [root, hero, nav] (rendered := ["hero_copy", "hero_copy", "nav_bar"]), smp 1500 [root, hero, nav]], arm base),
   ("snapOffGridX", wA, wB, arm base, arm [smp 0 [root, hero, navAt 500000 0], smp 1500 [root, hero, nav]]),
   ("snapOffGridXY", wA, wB, arm base, arm [smp 0 [root, hero, navAt 500000 250000], smp 1500 [root, hero, nav]]),
   ("snapNoOrigin", wA, wB, arm base,
     arm [smp 0 [root, hero, L "nav" (some "nav") (some "nav_bar") ⟨0, 0, 390000000, 64000000⟩ none], smp 1500 [root, hero, nav]]),
   ("snapFractionalOnGrid", wA, wB, arm base, arm [smp 0 [root, hero, navAt 333333 0], smp 1500 [root, hero, nav]]),
   ("snapFractionalOnGridDpr2", wA, wB, arm base (dpr := 2000), arm [smp 0 [root, hero, navAt 500000 0], smp 1500 [root, hero, nav]] (dpr := 2000)),
   ("snapOnlyDeclared", wA, wB, arm [smp 0 [root, hero, navAt 500000 0], smp 1500 [root, hero, nav]], arm base),
   ("loadVarianceBase", wA, wB, arm [smp 0 [root, hero, nav, frameA, idleSvg, idleSvg, typingVisual], smp 1500 [root, hero, nav, origCue, goneNode]],
     arm [smp 0 [root, hero, nav, goneNode, goneNamed], smp 1500 [root, hero, nav, frameB, { idleSvg with bounds := ⟨0, -1000000, 43000000, 47000000⟩ }, origFrame]]),
   ("rootHeightDiffers", wA, wB, arm [smp 0 [Lr "#document" ["root"] ⟨0, 0, 390000000, 6006000000⟩, hero, nav]], arm [smp 0 [Lr "#document" ["root"] ⟨0, 0, 390000000, 6042000000⟩, hero, nav]]),
   ("varyingCountNotTolerated", wA, wB, arm [smp 0 [root, hero, nav]], arm [smp 0 ([root, hero, nav] ++ List.replicate 9 frameA ++ List.replicate 9 goneNode)]),
   ("goneAndVaryingBeside", wA, wB, arm [smp 0 [root, hero, nav, extra, frameA]], arm [smp 0 [root, hero, nav, goneNode, extra, frameB]]),
   ("unlistedBesideVarying", wA, wB, arm [smp 0 [root, hero, nav, frameA]], arm [smp 0 [root, hero, nav, extra, goneNode]]),
   ("nearStemRefused", wA, wB, arm base, arm [smp 0 [root, hero, nav, nearStem], smp 1500 [root, hero, nav]]),
   ("nearStemRefused2", wA, wB, arm base, arm [smp 0 [root, hero, nav], smp 1500 [root, hero, nav, nearStem2]]),
   ("goneDeclaredNotUndeclared", wA, wB, arm base, arm [smp 0 [root, hero, goneDeclared], smp 1500 [root, hero, nav]]),
   ("order", wA, wB, arm [smp 0 [root, nav], smp 1500 [root, hero, nav]],
     arm [smp 0 [root, hero, navAt 500000 0, extra], smp 1500 [root, hero, nav]])]

private def sampleRows : List Layer :=
  [root, hero, L "div.hero2" (some "hero") (some "hero_copy") big none (some 1000), L "x" (some "nav") none big none none, extra]

private def identCases : List (Option String × Option String) :=
  [(some "hero", some "hero_copy"), (some "nav", none), (none, none), (some "", some ""), (some "", some "nav_bar"),
   (none, some "nav_bar"), (some "nav", some "")]

private def varyingCases : List String :=
  ["span.accent-module_frame_0z18R8", "svg.accent-module_svg_HwEYD1.accent-module_idleFrame_f6M8wO", "div.typing-module_visual_YdYZxz",
   "div.typing-module_beat_xRahAp.typing-module_scrollingOut_2jKdD5", "span.typing-module_avatar_lESUvo.typing-module_isLarge_uZcCpC", "span.frame.svelte-1fn2go6", "svg.accent-svg.is-idle-frame",
   "button.scroll-cue.svelte-1p2vpne", "section.commission.compact", "div.fee-visual-beat.scrolling-out", "div.body.svelte-ty4hd7", "#document", "span.accent-module_frame", "div.typing-module_visualX_1", "div.nav-module_bar_4ex1vU",
   "div.morph-module_track_CO8LmY", "?", "", "span.frame", "svg.accent-svg"]

private def gridCases : List (Nat × Int) :=
  [(3000, 0), (3000, 333333), (3000, 500000), (3000, 333000), (2000, 500000), (2000, 250000), (1000, 7), (1000, 1000000), (3000, -333333),
   (3000, 1000000)]

private def goldenLines (_ : Unit) : List String :=
  (identCases.map fun (f, l) =>
    (Json.mkObj [("kind", "ident"), ("fw", toJson f), ("layer", toJson l), ("ident", identJ (identOf f l))]).compress) ++
  (varyingCases.map fun (n : String) => (Json.mkObj [("kind", "varying"), ("name", n), ("varying", varying n)]).compress) ++
  (gridCases.map fun (d, o) =>
    (Json.mkObj [("kind", "grid"), ("dpr", d), ("o", toJson o), ("ok", gridOk d o)]).compress) ++
  [(Json.mkObj [("kind", "rows"), ("layers", Json.arr (sampleRows.map lj).toArray),
    ("rows", Json.arr ((rows sampleRows).map rowJ).toArray)]).compress] ++
  (checks.map fun (n, wa, wb, a, b) =>
    (Json.mkObj [("kind", "check"), ("name", n), ("wantA", wj wa), ("wantB", wj wb), ("a", aj a), ("b", aj b),
      ("refusals", Json.arr ((refusals wa wb a b).map refJ).toArray)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"census golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"census golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Measure.Census
