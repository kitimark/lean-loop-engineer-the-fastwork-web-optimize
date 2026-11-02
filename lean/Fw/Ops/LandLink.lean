/-!
# Land link check (task scratch-link-check, incident inc-scratch-symlink-wait)

`fw land --dry` refuses a branch that adds a symlink whose target leaves the worktree. A path
through such a link resolves outside the worktree, so a tool that follows it meets rules the
worktree does not cover (the incident: a link to the shared scratchpad and a copy that waited
for a permission answer).

**Rule.** A link is a pair (path of the link in the repo, target text). The target is resolved
against the link's directory, segment by segment: `..` pops one directory, `.` and empty
segments change nothing, any other segment pushes. A target is refused when it is empty
(`empty`), starts with `/` (`absolute`), or a `..` pops below the worktree root (`escapes`).
Every other link passes, including one that resolves to the worktree root.

Proved: one theorem per refusal branch (`check_empty`, `check_absolute`, `check_escapes`), the
passing case (`check_inside`), and soundness and completeness of `refused` (`mem_refused`).
-/
namespace Fw.Ops.LandLink

/-- Split at `/`, dropping empty and `.` segments. -/
def segs (s : String) : List String := (s.splitOn "/").filter fun x => x != "" && x != "."

/-- Resolve target segments on a reversed directory stack; `none` when a `..` pops below the
worktree root.
-/
def resolve : List String → List String → Option (List String)
  | st, [] => some st
  | [], ".." :: _ => none
  | _ :: t, ".." :: r => resolve t r
  | st, s :: r => resolve (s :: st) r

/-- A symlink the branch adds: its path in the repo and its target text. -/
structure Link where
  path : String
  target : String
deriving Repr, DecidableEq

/-- Why a link is refused. -/
inductive Reason where
  | empty
  | absolute
  | escapes
deriving Repr, DecidableEq

/-- The reversed directory of a link (all path segments but the last). -/
def dirStack (l : Link) : List String := (segs l.path).dropLast.reverse

/-- The refusal of one link, or `none` when it passes. -/
def check (l : Link) : Option Reason :=
  if l.target = "" then some .empty
  else if l.target.startsWith "/" then some .absolute
  else if (resolve (dirStack l) (segs l.target)).isNone then some .escapes
  else none

/-- The refused links with their reasons, in input order. -/
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

-- concrete cases pin the rule
#guard check ⟨"a/b/l", "../../x"⟩ == none
#guard check ⟨"a/b/l", "../../../x"⟩ == some .escapes
#guard check ⟨"l", "/etc"⟩ == some .absolute
#guard check ⟨"l", ""⟩ == some .empty
#guard check ⟨"a/l", "./b/../c"⟩ == none

end Fw.Ops.LandLink
