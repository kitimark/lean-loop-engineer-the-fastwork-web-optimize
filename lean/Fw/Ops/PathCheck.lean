/-!
# Path check (PLAN §8.2 write scopes, §8.3 notes: the land-time path check)

`fw land` refuses a branch whose changed paths leave the role's write scope. The scope is a list
of globs from the §8.2 table; a glob starting with `!` excludes (for example `lean/**` and
`!lean/math.lock.json` for lean-prover).

**Glob semantics (minimal, gitignore-like).** Paths and globs are split at `/`; empty and `.`
segments are dropped. A glob segment `**` matches zero or more path segments; any other glob
segment matches one path segment, where `*` matches any run of characters (no `/`) and every
other character matches itself. A glob matches a path when it matches the path **or one of its
directory prefixes** (so `packages/measure-*` covers `packages/measure-chromium/src/a.ts`, and
`research/notes/` covers everything under it). A path with a `..` segment, or with no segment,
is never in scope.

Proved: soundness and completeness of `violations` (`mem_violations`), the scope rule
(`inScope_iff`), and the glob laws (`segMatch_star`, `segMatch_lit`, `globMatch_dstar`,
`globMatch_dstar_append`, `globMatch_lit`, `matchesPath_append`, `matchesPath_lit`).
-/
namespace Fw.Ops.PathCheck

/-- Split a path or glob at `/`, dropping empty and `.` segments. -/
def segs (s : String) : List String := (s.splitOn "/").filter fun x => x != "" && x != "."

/-- One glob segment against one path segment, as character lists; `*` matches any run of
characters.
-/
def segMatch : List Char → List Char → Bool
  | [], s => s.isEmpty
  | '*' :: p, [] => segMatch p []
  | '*' :: p, c :: s => segMatch p (c :: s) || segMatch ('*' :: p) s
  | _ :: _, [] => false
  | c :: p, d :: s => c == d && segMatch p s

/-- A glob (segment list) against a whole path (segment list); `**` matches zero or more
segments.
-/
def globMatch : List String → List String → Bool
  | [], s => s.isEmpty
  | "**" :: p, [] => globMatch p []
  | "**" :: p, x :: s => globMatch p (x :: s) || globMatch ("**" :: p) s
  | _ :: _, [] => false
  | g :: p, x :: s => segMatch g.toList x.toList && globMatch p s

/-- A glob matches a path when it matches the path or one of its non-empty directory prefixes. -/
def matchesPath (g path : List String) : Bool :=
  (List.range path.length).any fun k => globMatch g (path.take (k + 1))

/-- A parsed scope: include globs and exclude globs (written with a leading `!`). -/
structure Scope where
  incl : List (List String)
  excl : List (List String)
deriving Repr, DecidableEq

/-- Parse a list of globs: a glob starting with `!` is an exclusion. -/
def parseScope (globs : List String) : Scope :=
  ⟨(globs.filter (!·.startsWith "!")).map segs, (globs.filter (·.startsWith "!")).map fun g => segs (g.drop 1).toString⟩

/-- A path is in scope: it has segments, no `..`, matches an include and no exclude. -/
def inScope (sc : Scope) (path : String) : Bool :=
  let p := segs path
  !p.isEmpty && !p.contains ".." && sc.incl.any (matchesPath · p) && !sc.excl.any (matchesPath · p)

/-- The violations of a branch: the changed paths outside the scope, in their order. -/
def violations (globs paths : List String) : List String :=
  paths.filter fun p => !inScope (parseScope globs) p

/-! ## Soundness -/

/-- Soundness and completeness: a path is reported exactly when it is a changed path outside the
scope (every path outside is reported, nothing inside is).
-/
theorem mem_violations (globs paths : List String) (x : String) :
    x ∈ violations globs paths ↔ x ∈ paths ∧ inScope (parseScope globs) x = false := by
  simp [violations]

/-- A branch passes exactly when all its changed paths are in scope. -/
theorem violations_nil_iff (globs paths : List String) :
    violations globs paths = [] ↔ ∀ x ∈ paths, inScope (parseScope globs) x = true := by
  simp [violations, List.filter_eq_nil_iff]

/-- The scope rule, unfolded. -/
theorem inScope_iff (sc : Scope) (x : String) : inScope sc x = true ↔
    segs x ≠ [] ∧ ".." ∉ segs x ∧ (∃ g ∈ sc.incl, matchesPath g (segs x) = true) ∧
      ∀ g ∈ sc.excl, matchesPath g (segs x) = false := by
  simp [inScope, and_assoc]

/-- An exclusion wins over every inclusion. -/
theorem excl_wins (sc : Scope) (x : String) (g : List String) (hg : g ∈ sc.excl)
    (hm : matchesPath g (segs x) = true) : inScope sc x = false := by
  cases h : inScope sc x
  · rfl
  · have := ((inScope_iff sc x).mp h).2.2.2 g hg
    rw [hm] at this; cases this

/-! ## Glob laws -/

/-- `*` matches every segment. -/
theorem segMatch_star (s : List Char) : segMatch ['*'] s = true := by
  induction s with
  | nil => simp [segMatch]
  | cons c s ih => simp [segMatch, ih]

/-- A glob segment without `*` matches exactly itself. -/
theorem segMatch_lit (p s : List Char) (h : '*' ∉ p) : segMatch p s = true ↔ p = s := by
  induction p generalizing s with
  | nil => cases s <;> simp [segMatch]
  | cons c p ih =>
    have hc : c ≠ '*' := fun e => h (e ▸ List.mem_cons_self)
    have hp : '*' ∉ p := fun m => h (List.mem_cons_of_mem _ m)
    cases s with
    | nil => cases c <;> simp_all [segMatch]
    | cons d s =>
      have : segMatch (c :: p) (d :: s) = (c == d && segMatch p s) := by
        simp [segMatch]
      rw [this]; simp [ih s hp]

/-- `**` alone matches every path. -/
theorem globMatch_dstar (s : List String) : globMatch ["**"] s = true := by
  induction s with
  | nil => simp [globMatch]
  | cons x s ih => simp [globMatch, ih]

/-- `**` absorbs any prefix: if the rest of the glob matches `s`, then `**` followed by it
matches any path ending in `s`.
-/
theorem globMatch_dstar_append (p u s : List String) (h : globMatch p s = true) :
    globMatch ("**" :: p) (u ++ s) = true := by
  induction u with
  | nil => cases s <;> simp_all [globMatch]
  | cons x u ih => simp [globMatch, ih]

/-- A glob without `**` and without `*` matches exactly the equal path. -/
theorem globMatch_lit (p s : List String) (h : ∀ g ∈ p, g ≠ "**" ∧ '*' ∉ g.toList) :
    globMatch p s = true ↔ p = s := by
  induction p generalizing s with
  | nil => cases s <;> simp [globMatch]
  | cons g p ih =>
    have hg := h g List.mem_cons_self
    have hp : ∀ g ∈ p, g ≠ "**" ∧ '*' ∉ g.toList := fun g' m => h g' (List.mem_cons_of_mem _ m)
    cases s with
    | nil =>
      have : globMatch (g :: p) [] = false := by simp [globMatch, hg.1]
      simp [this]
    | cons x s =>
      have : globMatch (g :: p) (x :: s) = (segMatch g.toList x.toList && globMatch p s) := by
        simp [globMatch, hg.1]
      rw [this, Bool.and_eq_true, segMatch_lit _ _ hg.2, ih s hp, String.toList_inj]
      simp

/-- Directory law: a glob that matches a path matches every path below it. -/
theorem matchesPath_append (g x y : List String) (h : matchesPath g x = true) :
    matchesPath g (x ++ y) = true := by
  simp only [matchesPath, List.any_eq_true, List.mem_range] at h ⊢
  obtain ⟨k, hk, hm⟩ := h
  refine ⟨k, by simp; omega, ?_⟩
  rw [List.take_append_of_le_length (by omega)]
  exact hm

/-- A non-empty literal glob matches its own path (and, by the directory law, everything below). -/
theorem matchesPath_lit (x : List String) (hx : x ≠ []) (h : ∀ g ∈ x, g ≠ "**" ∧ '*' ∉ g.toList) :
    matchesPath x x = true := by
  simp only [matchesPath, List.any_eq_true, List.mem_range]
  refine ⟨x.length - 1, ?_, ?_⟩
  · cases x with
    | nil => exact absurd rfl hx
    | cons _ _ => simp
  · have : x.length - 1 + 1 = x.length := by
      cases x with
      | nil => exact absurd rfl hx
      | cons _ _ => simp
    rw [this, List.take_length]
    exact (globMatch_lit x x h).mpr rfl

/-- `**` alone matches every non-empty path. -/
theorem matchesPath_dstar (x : List String) (hx : x ≠ []) : matchesPath ["**"] x = true := by
  simp only [matchesPath, List.any_eq_true, List.mem_range]
  cases x with
  | nil => exact absurd rfl hx
  | cons _ _ => exact ⟨0, by simp, globMatch_dstar _⟩

/-- The empty glob matches no path. -/
theorem matchesPath_nil (x : List String) : matchesPath [] x = false := by
  simp only [matchesPath, List.any_eq_false, List.mem_range]
  intro k hk
  cases x with
  | nil => simp at hk
  | cons a x => simp [globMatch]

/-! ## Examples (lean-prover's scope, PLAN §8.2) -/

/-- The lean-prover write scope of PLAN §8.2. -/
def leanScope : List String := ["lean/**", "!lean/math.lock.json"]

#guard violations leanScope ["lean/Fw/Ops/Usage.lean", "lean/math.lock.json", "docs/plan/PLAN.md"] ==
  ["lean/math.lock.json", "docs/plan/PLAN.md"]
#guard violations leanScope ["lean/../docs/x.md", "lean", "./lean//Fw.lean", ""] == ["lean/../docs/x.md", ""]
#guard violations ["packages/measure-*"] ["packages/measure-webkit/src/a.ts", "packages/model/x.ts"] ==
  ["packages/model/x.ts"]
#guard violations ["apps/console-*/**"] ["apps/console-web/src/App.tsx", "apps/site/x"] == ["apps/site/x"]
#guard violations ["research/notes/", "refs/**"] ["research/notes/2026/a.md", "research/decisions/b.md", "refs/x"] ==
  ["research/decisions/b.md"]
#guard violations ["apps/site/src/parts/hero/**"] ["apps/site/src/parts/hero/a.tsx", "apps/site/src/parts/heroX/a.tsx"] ==
  ["apps/site/src/parts/heroX/a.tsx"]
#guard violations ["docs/**/*.md"] ["docs/a.md", "docs/x/y/b.md", "docs/x/c.html"] == ["docs/x/c.html"]
#guard violations [] ["a"] == ["a"]
#guard segMatch "a*b*c".toList "aXXbYc".toList && !segMatch "a*b".toList "abc".toList && segMatch "*".toList [] 

end Fw.Ops.PathCheck
