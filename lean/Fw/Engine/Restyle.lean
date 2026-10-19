import Lean.Data.Json

/-! Elements the next style pass resolves after one element's custom-property write, in Chromium and WebKit, for an
inherited property and for a registered non-inherited one passed down by `inherit`. -/
namespace Fw.Engine.Restyle

/-- DOM summary: `chain` children declare `inherit` for the written properties, `extra` counts the other children,
`explicit` those that `inherit` another non-inherited property, `rest` the elements of the other children's subtrees. -/
inductive Node where
  | mk (name : String) (extra explicit rest : Nat) (chain : List Node)
deriving Repr, Inhabited

namespace Node

def name : Node → String | mk n .. => n
def extra : Node → Nat | mk _ e .. => e
def explicit : Node → Nat | mk _ _ x .. => x
def rest : Node → Nat | mk _ _ _ r _ => r
def chain : Node → List Node | mk _ _ _ _ c => c

/-- Chromium `ChildHasExplicitInheritance` on the node: some child declares `inherit` for a non-inherited property
(style_builder.cc:114-117@f842f52). -/
def flagged (n : Node) : Bool := !n.chain.isEmpty || n.explicit > 0

#guard (mk "a" 0 0 0 [mk "b" 0 0 0 []]).flagged
#guard !(mk "a" 3 0 9 []).flagged
#guard (mk "a" 3 1 9 []).flagged

mutual
def size : Node → Nat
  | mk _ _ _ r c => 1 + r + sizes c
def sizes : List Node → Nat
  | [] => 0
  | n :: ns => size n + sizes ns
end

mutual
/-- Chromium elements resolved below a changed chain node: `ChildHasExplicitInheritance` turns a non-inherited diff
into `kInherited` (computed_style.cc:466-468@f842f52), which recalcs every child (element.cc:5618-5619@f842f52);
otherwise `kNonInherited` stops (computed_style.cc:504@f842f52). -/
def crBelow : Node → Nat
  | n@(mk _ e _ _ c) => if n.flagged then c.length + e + crBelows c else 0
def crBelows : List Node → Nat
  | [] => 0
  | n :: ns => crBelow n + crBelows ns
end

mutual
/-- WebKit elements resolved below a changed chain node: `Change::NonInherited` resolves only the children with
explicitly inherited properties (StyleTreeResolver.cpp:310-311,1207-1210@862f17d). -/
def wkBelow : Node → Nat
  | mk _ _ x _ c => c.length + x + wkBelows c
def wkBelows : List Node → Nat
  | [] => 0
  | n :: ns => wkBelow n + wkBelows ns
end

mutual
/-- Names of the node and every chain node below it. -/
def chainNames : Node → List String
  | mk n _ _ _ c => n :: chainNamesL c
def chainNamesL : List Node → List String
  | [] => []
  | n :: ns => chainNames n ++ chainNamesL ns
end

mutual
def flaggedKids : Node → Nat
  | n@(mk _ e _ _ c) => (if n.flagged then c.length + e else 0) + flaggedKidsL c
def flaggedKidsL : List Node → Nat
  | [] => 0
  | n :: ns => flaggedKids n + flaggedKidsL ns
end

mutual
def wf : Node → Bool
  | mk _ e x r c => x ≤ e && e ≤ r && wfL c
def wfL : List Node → Bool
  | [] => true
  | n :: ns => wf n && wfL ns
end

mutual
/-- Every node with the `inherit` flags, read from `rule` by name, of the path below the root. -/
def paths (rule : String → Bool) (p : List Bool) : Node → List (String × List Bool)
  | mk n _ _ _ c => (n, p) :: pathsL rule p c
def pathsL (rule : String → Bool) (p : List Bool) : List Node → List (String × List Bool)
  | [] => []
  | k :: ks => paths rule (p ++ [rule k.name]) k ++ pathsL rule p ks
end

#guard paths (· == "a") [] (mk "s" 0 0 0 [mk "a" 0 0 0 [mk "b" 0 0 0 []]]) == [("s", []), ("a", [true]), ("b", [true, false])]

mutual
/-- Golden JSON of a summary: `name`, `extra`, `explicit`, `rest`, `chain`. -/
def json : Node → Lean.Json
  | mk n e x r c => Lean.Json.mkObj [("name", Lean.toJson n), ("extra", Lean.toJson e), ("explicit", Lean.toJson x),
      ("rest", Lean.toJson r), ("chain", Lean.Json.arr (jsonL c).toArray)]
def jsonL : List Node → List Lean.Json
  | [] => []
  | k :: ks => json k :: jsonL ks
end

end Node

open Node

/-- Declaration of the written custom properties: unregistered (inherited) or registered with `inherits: false`. -/
inductive Reg where
  | inherited
  | registered
deriving Repr, DecidableEq

/-- Chromium bound on the elements resolved in a frame that writes the root; an inherited variable diff is
`kInherited` or `kIndependentInherited` and reaches the whole subtree (computed_style.cc:470-478@f842f52). -/
def crUnits : Reg → Node → Nat
  | .inherited, t => t.size
  | .registered, t => 1 + t.crBelow

/-- WebKit elements resolved in the same frame; a custom property is inherited unless registered with
`inherits: false` (StyleBuilder.cpp:103-106@862f17d) and an inherited change resolves every child
(StyleTreeResolver.cpp:307-308@862f17d). -/
def wkUnits : Reg → Node → Nat
  | .inherited, t => t.size
  | .registered, t => 1 + t.wkBelow

#guard crUnits .registered (mk "s" 0 0 0 [mk "a" 2 0 5 [mk "d" 0 0 0 []]]) == 5
#guard wkUnits .registered (mk "s" 0 0 0 [mk "a" 2 0 5 [mk "d" 0 0 0 []]]) == 3
#guard crUnits .inherited (mk "s" 0 0 0 [mk "a" 2 0 5 [mk "d" 0 0 0 []]]) == 8
#guard crUnits .registered (mk "s" 0 0 0 [mk "a" 2 1 5 []]) == 4
#guard wkUnits .registered (mk "s" 0 0 0 [mk "a" 2 1 5 []]) == 3

theorem crBelow_eq_flaggedKids : ∀ n : Node, n.crBelow = n.flaggedKids
  | mk name e x r c => by
    have h := crBelows_eq c
    unfold crBelow flaggedKids
    by_cases hf : (mk name e x r c).flagged
    · simp only [hf, ite_true]; omega
    · simp only [hf]
      have hc : c = [] := by
        cases c with
        | nil => rfl
        | cons _ _ => simp [flagged, chain] at hf
      subst hc; simp [flaggedKidsL]
where
  crBelows_eq : ∀ l : List Node, crBelows l = flaggedKidsL l
    | [] => by simp [crBelows, flaggedKidsL]
    | n :: ns => by simp only [crBelows, flaggedKidsL, crBelow_eq_flaggedKids n, crBelows_eq ns]

theorem scoped_le (t : Node) : crUnits .registered t ≤ 1 + t.flaggedKids := by
  simp [crUnits, crBelow_eq_flaggedKids]

theorem wk_le_cr : ∀ n : Node, n.wf → n.wkBelow ≤ n.crBelow
  | mk name e x r c, hw => by
    simp only [wf, Bool.and_eq_true, decide_eq_true_eq] at hw
    obtain ⟨⟨hxe, _⟩, hc⟩ := hw
    have ih := go c hc
    unfold wkBelow crBelow
    by_cases hf : (mk name e x r c).flagged
    · simp only [hf, ite_true]; omega
    · simp only [hf]
      have hx : x = 0 := by
        cases x with
        | zero => rfl
        | succ k => simp [flagged, explicit] at hf
      have hcn : c = [] := by
        cases c with
        | nil => rfl
        | cons _ _ => simp [flagged, chain] at hf
      subst hx hcn
      simp [wkBelows]
where
  go : ∀ l : List Node, wfL l → wkBelows l ≤ crBelows l
    | [], _ => by simp [wkBelows, crBelows]
    | n :: ns, h => by
      simp only [wfL, Bool.and_eq_true] at h
      obtain ⟨h1, h2⟩ := h
      have a := wk_le_cr n h1
      have b := go ns h2
      simp only [wkBelows, crBelows]; omega

theorem wk_le_cr_units (t : Node) (h : t.wf) : wkUnits .registered t ≤ crUnits .registered t := by
  have := wk_le_cr t h
  simp only [wkUnits, crUnits]; omega

theorem crBelow_lt_size : ∀ n : Node, n.wf → n.crBelow < n.size
  | mk name e x r c, hw => by
    simp only [wf, Bool.and_eq_true, decide_eq_true_eq] at hw
    obtain ⟨⟨_, her⟩, hc⟩ := hw
    have ih := go c hc
    unfold crBelow size
    split <;> omega
where
  go : ∀ l : List Node, wfL l → l.length + crBelows l ≤ sizes l
    | [], _ => by simp [crBelows, sizes]
    | n :: ns, h => by
      simp only [wfL, Bool.and_eq_true] at h
      obtain ⟨h1, h2⟩ := h
      have a := crBelow_lt_size n h1
      have b := go ns h2
      simp only [List.length_cons, crBelows, sizes]; omega

theorem registered_le_inherited (t : Node) (h : t.wf) : crUnits .registered t ≤ crUnits .inherited t := by
  have := crBelow_lt_size t h
  simp only [crUnits]; omega

/-- Value at a node from the root's value `v` and the path's `inherit` declarations; `none` is guaranteed-invalid. -/
def valueAt : Reg → Option String → List Bool → Option String
  | .inherited, v, _ => v
  | .registered, v, path => if path.all id then v else none

#guard valueAt .registered (some "0.5") [true, true] == some "0.5"
#guard valueAt .registered (some "0.5") [true, false] == none
#guard valueAt .inherited (some "0.5") [false] == some "0.5"

theorem consumer_eq (v : Option String) (path : List Bool) (h : path.all id = true) :
    valueAt .registered v path = valueAt .inherited v path := by
  simp [valueAt, h]

end Fw.Engine.Restyle
