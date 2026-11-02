namespace Fw.Ops.LandLink

def segs (s : String) : List String := (s.splitOn "/").filter fun x => x != "" && x != "."

def resolve : List String → List String → Option (List String)
  | st, [] => some st
  | [], ".." :: _ => none
  | _ :: t, ".." :: r => resolve t r
  | st, s :: r => resolve (s :: st) r

structure Link where
  path : String
  target : String
deriving Repr, DecidableEq

inductive Reason where
  | empty
  | absolute
  | escapes
deriving Repr, DecidableEq

def dirStack (l : Link) : List String := (segs l.path).dropLast.reverse

def check (l : Link) : Option Reason :=
  if l.target = "" then some .empty
  else if l.target.startsWith "/" then some .absolute
  else if (resolve (dirStack l) (segs l.target)).isNone then some .escapes
  else none

def refused (ls : List Link) : List (Link × Reason) :=
  ls.filterMap fun l => (check l).map (l, ·)

theorem check_empty (l : Link) (h : l.target = "") : check l = some .empty := by
  simp [check, h]

theorem check_absolute (l : Link) (h0 : l.target ≠ "") (h : l.target.startsWith "/" = true) :
    check l = some .absolute := by
  simp [check, h0, h]

theorem check_escapes (l : Link) (h0 : l.target ≠ "") (h : l.target.startsWith "/" = false)
    (he : resolve (dirStack l) (segs l.target) = none) : check l = some .escapes := by
  simp [check, h0, h, he]

theorem check_inside (l : Link) (h0 : l.target ≠ "") (h : l.target.startsWith "/" = false)
    (p : List String) (hi : resolve (dirStack l) (segs l.target) = some p) : check l = none := by
  simp [check, h0, h, hi]

theorem mem_refused (ls : List Link) (l : Link) (r : Reason) :
    (l, r) ∈ refused ls ↔ l ∈ ls ∧ check l = some r := by
  simp [refused, List.mem_filterMap, Option.map_eq_some_iff]

#guard check ⟨"a/b/l", "../../x"⟩ == none
#guard check ⟨"a/b/l", "../../../x"⟩ == some .escapes
#guard check ⟨"l", "/etc"⟩ == some .absolute
#guard check ⟨"l", ""⟩ == some .empty
#guard check ⟨"a/l", "./b/../c"⟩ == none

end Fw.Ops.LandLink
