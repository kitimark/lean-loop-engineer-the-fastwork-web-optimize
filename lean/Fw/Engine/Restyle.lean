import Lean.Data.Json

/-! Elements one style pass resolves after a custom-property write on a root, in Chromium and WebKit, for unregistered
(inherited) properties and for registered non-inherited ones passed down by `inherit`. -/
namespace Fw.Engine.Restyle

/-- Per-element cascade facts: `vars` custom property declared or referenced, `slow` refused by Chromium
`Element::PropagateInheritedProperties` (third_party/blink/renderer/core/dom/element.cc:5554-5597@f842f52), `hidden`
no box, `inh` `inherit` for both written properties, `explicit` `inherit` for another non-inherited property, `reads`
reads a written property. -/
structure Flags where
  vars : Bool := false
  slow : Bool := false
  hidden : Bool := false
  inh : Bool := false
  explicit : Bool := false
  reads : Bool := false
deriving Repr, DecidableEq, Inhabited

/-- Golden letters of the set flags, in the order `v s h i x r`. -/
def Flags.letters (f : Flags) : String :=
  String.join <| [(f.vars, "v"), (f.slow, "s"), (f.hidden, "h"), (f.inh, "i"), (f.explicit, "x"), (f.reads, "r")]
    |>.filterMap fun (b, l) => if b then some l else none

#guard ({ vars := true, inh := true } : Flags).letters == "vi"
#guard ({} : Flags).letters == ""

inductive Node where
  | mk (name : String) (flags : Flags) (kids : List Node)
deriving Repr, Inhabited

namespace Node

def name : Node → String | mk n .. => n
def flags : Node → Flags | mk _ f _ => f

mutual
/-- Chromium `ResolveStyle` calls for a node whose inherited variables changed and whose style is resolved in full.
`display: none` stores no style, so no child is resolved
(third_party/blink/renderer/core/dom/element.cc:5713,5734-5735@f842f52). A node with variables turns the change into
`kInherited` (third_party/blink/renderer/core/style/computed_style.cc:470-475@f842f52), which resolves every child
(element.cc:5618-5619@f842f52); otherwise `kIndependentInherited` (computed_style.cc:476-478@f842f52) sends each child
down the clone path, which copies the inherited variables (element.cc:5621-5622,5698-5702@f842f52;
computed_style.cc:3146-3149@f842f52). A resolution is counted by `IncStyleForElementCount`
(third_party/blink/renderer/core/css/resolver/style_resolver.cc:1362-1364 via :1442@f842f52), the source of
`UpdateLayoutTree.elementCount` (third_party/blink/renderer/core/dom/document.cc:2822,2856-2857@f842f52); the clone path
(element.cc:5698-5702@f842f52) never reaches it. The units of this module are validated only as between-arm deltas;
no task cites an absolute unit as measured elementCount until a per-pass elementCount dump exists. -/
def crFull : Node → Nat
  | mk _ f ks => 1 + (if f.hidden then 0 else if f.vars then crFullL ks else crCloneL ks)
/-- Chromium `ResolveStyle` calls for a node reached by `kIndependentInherit`: the clone is not counted, and a node
with variables, animation or transition data, links, decorations, SVG callbacks or no stored style is resolved in
full (third_party/blink/renderer/core/dom/element.cc:5554-5597@f842f52). -/
def crClone : Node → Nat
  | mk _ f ks => (if f.vars || f.slow || f.hidden then 1 else 0) +
      (if f.hidden then 0 else if f.vars then crFullL ks else crCloneL ks)
def crFullL : List Node → Nat
  | [] => 0
  | k :: ks => crFull k + crFullL ks
def crCloneL : List Node → Nat
  | [] => 0
  | k :: ks => crClone k + crCloneL ks
end

mutual
/-- WebKit resolutions for a node whose inherited custom properties changed: `Change::Inherited` resolves every child
(Source/WebCore/style/StyleTreeResolver.cpp:307-308@862f17d), custom properties have no fast path
(Source/WebCore/style/computed/StyleComputedStyle.cpp:212@862f17d), and `display: none` stops the descent
(StyleTreeResolver.cpp:1387-1388@862f17d). -/
def wkFull : Node → Nat
  | mk _ f ks => 1 + (if f.hidden then 0 else wkFullL ks)
def wkFullL : List Node → Nat
  | [] => 0
  | k :: ks => wkFull k + wkFullL ks
end

/-- Chromium `ChildHasExplicitInheritance`: some child declares `inherit` for a non-inherited property
(third_party/blink/renderer/core/css/resolver/style_builder.cc:114-117@f842f52). -/
def explicitKid (ks : List Node) : Bool := ks.any fun k => k.flags.inh || k.flags.explicit

mutual
/-- Chromium resolutions for a node whose registered non-inherited values changed: with an explicitly inheriting
child the non-inherited diff becomes `kInherited` and every child is resolved, a child whose values follow by
`inherit` recursing; otherwise `kNonInherited` stops
(third_party/blink/renderer/core/style/computed_style.cc:466-468,504@f842f52). -/
def crScoped : Node → Nat
  | mk _ f ks => 1 + (if !f.hidden && explicitKid ks then crScopedL ks else 0)
def crScopedL : List Node → Nat
  | [] => 0
  | k :: ks => (if k.flags.inh then crScoped k else 1) + crScopedL ks
end

mutual
/-- WebKit resolutions for the same change: `Change::NonInherited` resolves only children with explicitly inherited
properties (Source/WebCore/style/StyleTreeResolver.cpp:310-311,1207-1209@862f17d;
Source/WebCore/style/StyleBuilder.cpp:576-577@862f17d). -/
def wkScoped : Node → Nat
  | mk _ f ks => 1 + (if f.hidden then 0 else wkScopedL ks)
def wkScopedL : List Node → Nat
  | [] => 0
  | k :: ks => (if k.flags.inh then wkScoped k else if k.flags.explicit then 1 else 0) + wkScopedL ks
end

mutual
/-- Each node's name, `reads` flag and the `inh` flags of the path below the root. -/
def paths (p : List Bool) : Node → List (String × Bool × List Bool)
  | mk n f ks => (n, f.reads, p) :: pathsL p ks
def pathsL (p : List Bool) : List Node → List (String × Bool × List Bool)
  | [] => []
  | k :: ks => paths (p ++ [k.flags.inh]) k ++ pathsL p ks
end

mutual
/-- Golden JSON of a tree: `[name, letters]` for a leaf, `[name, letters, kids]` otherwise. -/
def json : Node → Lean.Json
  | mk n f [] => Lean.Json.arr #[Lean.toJson n, Lean.toJson f.letters]
  | mk n f (k :: ks) => Lean.Json.arr #[Lean.toJson n, Lean.toJson f.letters, Lean.Json.arr (jsonL (k :: ks)).toArray]
def jsonL : List Node → List Lean.Json
  | [] => []
  | k :: ks => json k :: jsonL ks
end

end Node

open Node

private def leaf (n : String) (f : Flags := {}) : Node := mk n f []

private def ex : Node :=
  mk "s" { vars := true } [mk "a" { inh := true } [leaf "b" { vars := true }, leaf "c"], leaf "d" { slow := true },
    leaf "e" { hidden := true }]

#guard crFull ex == 5
#guard crClone (leaf "c") == 0
#guard crClone (leaf "c" { slow := true }) == 1
#guard crClone (mk "c" { hidden := true } [leaf "d" { vars := true }]) == 1
#guard wkFull ex == 6
#guard crScoped ex == 4
#guard wkScoped ex == 2
#guard crScoped (mk "s" {} [leaf "a", leaf "b" { explicit := true }]) == 3
#guard wkScoped (mk "s" {} [leaf "a", leaf "b" { explicit := true }]) == 2
#guard crScoped (mk "s" {} [leaf "a", leaf "b"]) == 1
#guard (paths [] ex).map (·.2.2) == [[], [true], [true, false], [true, false], [false], [false]]

theorem crClone_of_vars (n : String) (f : Flags) (ks : List Node) (h : f.vars = true) :
    crClone (mk n f ks) = crFull (mk n f ks) := by
  simp [crClone, crFull, h]

theorem crClone_of_slow (n : String) (f : Flags) (ks : List Node) (h : f.slow = true) :
    crClone (mk n f ks) = crFull (mk n f ks) := by
  simp [crClone, crFull, h]

theorem crClone_of_hidden (n : String) (f : Flags) (ks : List Node) (h : f.hidden = true) :
    crClone (mk n f ks) = crFull (mk n f ks) := by
  simp [crClone, crFull, h]

theorem crClone_fast (n : String) (f : Flags) (ks : List Node) (hv : f.vars = false) (hs : f.slow = false)
    (hh : f.hidden = false) : crClone (mk n f ks) = crCloneL ks := by
  simp [crClone, hv, hs, hh]

theorem explicitKid_of_inh (ks : List Node) (k : Node) (hk : k ∈ ks) (h : k.flags.inh = true) :
    explicitKid ks = true :=
  List.any_eq_true.2 ⟨k, hk, by simp [h]⟩

theorem explicitKid_of_explicit (ks : List Node) (k : Node) (hk : k ∈ ks) (h : k.flags.explicit = true) :
    explicitKid ks = true :=
  List.any_eq_true.2 ⟨k, hk, by simp [h]⟩

theorem one_le_wkFull : ∀ n : Node, 1 ≤ wkFull n
  | mk _ _ _ => by simp [wkFull]

mutual
theorem crFull_le_wkFull : ∀ n : Node, crFull n ≤ wkFull n
  | mk _ f ks => by
    have a := crFullL_le ks
    have b := crCloneL_le ks
    simp only [crFull, wkFull]
    split
    · omega
    · split <;> omega
theorem crClone_le_wkFull : ∀ n : Node, crClone n ≤ wkFull n
  | mk _ f ks => by
    have a := crFullL_le ks
    have b := crCloneL_le ks
    simp only [crClone, wkFull]
    split <;> split <;> (try split) <;> omega
theorem crFullL_le : ∀ l : List Node, crFullL l ≤ wkFullL l
  | [] => by simp [crFullL, wkFullL]
  | k :: ks => by
    have a := crFull_le_wkFull k
    have b := crFullL_le ks
    simp only [crFullL, wkFullL]; omega
theorem crCloneL_le : ∀ l : List Node, crCloneL l ≤ wkFullL l
  | [] => by simp [crCloneL, wkFullL]
  | k :: ks => by
    have a := crClone_le_wkFull k
    have b := crCloneL_le ks
    simp only [crCloneL, wkFullL]; omega
end

mutual
theorem crScoped_le_wkFull : ∀ n : Node, crScoped n ≤ wkFull n
  | mk _ f ks => by
    have a := crScopedL_le ks
    simp only [crScoped, wkFull]
    split <;> split <;> simp_all <;> omega
theorem crScopedL_le : ∀ l : List Node, crScopedL l ≤ wkFullL l
  | [] => by simp [crScopedL, wkFullL]
  | k :: ks => by
    have a := crScoped_le_wkFull k
    have b := crScopedL_le ks
    have c := one_le_wkFull k
    simp only [crScopedL, wkFullL]
    split <;> omega
end

mutual
theorem wkScoped_le_crScoped : ∀ n : Node, wkScoped n ≤ crScoped n
  | mk _ f ks => by
    have a := wkScopedL_le ks
    simp only [wkScoped, crScoped]
    by_cases hh : f.hidden
    · simp [hh]
    · by_cases he : explicitKid ks
      · simp [hh, he]; omega
      · have z := wkScopedL_zero ks (by simpa [explicitKid] using he)
        simp [hh, he, z]
theorem wkScopedL_le : ∀ l : List Node, wkScopedL l ≤ crScopedL l
  | [] => by simp [wkScopedL, crScopedL]
  | k :: ks => by
    have a := wkScoped_le_crScoped k
    have b := wkScopedL_le ks
    simp only [wkScopedL, crScopedL]
    split
    · omega
    · split <;> omega
theorem wkScopedL_zero : ∀ l : List Node, (∀ k ∈ l, k.flags.inh = false ∧ k.flags.explicit = false) →
    wkScopedL l = 0
  | [] => fun _ => by simp [wkScopedL]
  | k :: ks => fun h => by
    have hk := h k (by simp)
    have r := wkScopedL_zero ks fun k' hk' => h k' (by simp [hk'])
    simp [wkScopedL, hk.1, hk.2, r]
end

/-- Declaration of the written custom properties: unregistered (inherited) or registered with `inherits: false`. -/
inductive Reg where
  | inherited
  | registered
deriving Repr, DecidableEq

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
