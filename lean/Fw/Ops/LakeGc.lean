import Lean.Data.Json
import Fw.Ops.Wire

/-!
# Which Lake cache artifacts `fw lake-gc` may list (task `lean-bin-slim`)

Lake's artifact cache (`$LAKE_CACHE_DIR/artifacts`, one flat directory of content-addressed files) only grows: every
relink stores a new ~100 MB executable, and a checkout's `.lake/build` hard-links the files it uses. A file with a link
count of 1 is held by the cache alone; Lake re-downloads or rebuilds it on a miss (Lake/Build/Common.lean:521-535
@v4.35.0), so deleting it is safe for every checkout. The glue (`scripts/lake-gc.mjs`, `fw lake-gc`) reads one `Fact` per
directory entry and prints the list and the `rm` command; it never deletes. This module decides the list and the alert:

* `never_lists_linked`, `never_lists_young`: a listed name has, in every fact with that name, link count < 2 and an
  age of at least the floor;
* `inside_root_only`: every listed path is `<root>/<name>`, with an allowlisted root and a one-segment allowlisted name;
* `list_monotone_in_age`: a later `now` or a smaller floor lists every path listed before;
* `alert_iff`: the alert (`fw lake-gc --check`; `sys.lakeCache` once `fw watch` reads it) holds exactly when the
  cache bytes exceed the budget.
-/
namespace Fw.Ops.LakeGc

/-- One directory entry of the artifacts directory, as the glue reads it with `lstat`: its name, whether it is a
regular file, its hard-link count, its modification time (whole seconds since the epoch) and its size in bytes.
$$\mathrm{Fact} = \mathrm{String} \times \mathbb B \times \mathbb N \times \mathbb N \times \mathbb N \quad (\mathit{name}, \mathit{file}, \mathit{links}, \mathit{mtime}, \mathit{size})$$ -/
structure Fact where
  name : String
  file : Bool
  links : Nat
  mtime : Nat
  size : Nat
deriving Repr, DecidableEq, BEq

/-- The run's inputs besides the facts: the artifacts directory, the time now (seconds since the epoch), the age floor
(seconds) and the alert budget (bytes).
$$\mathrm{Config} = \mathrm{String} \times \mathbb N \times \mathbb N \times \mathbb N \quad (\mathit{root}, \mathit{now}, \mathit{floor}, \mathit{budget})$$ -/
structure Config where
  root : String
  now : Nat
  ageFloor : Nat
  budget : Nat
deriving Repr

/-- The default age floor: 2 hours. A build that started before the listing and still runs is far shorter than this on
this repository (a full rebuild of every executable measured 82 s), so a file it just wrote is never listed.
$$\mathit{floor}_0 = 7200$$ -/
def defaultAgeFloor : Nat := 7200

/-- The default alert budget: 20 GB (decimal). Measured on 2026-10-18 with 27 worktrees
(research/notes/2026/10-18-lean-bin-slim.md): the cache held 30.0 GB, 9.08 GB hard-linked by checkouts, 12.82 GB
unlinked but younger than the floor, 8.10 GB listable. One full rebuild stored 707 MB before this task and 400 MB
after it, so the 2-hour young share scales to about 7.3 GB, and the cache after a `lake-gc` stays near 16.4 GB; above
20 GB, a run of `lake-gc` frees space.
$$\mathit{budget}_0 = 20 \cdot 10^9$$ -/
def budgetBytes : Nat := 20000000000

/-- A character allowed in an entry name: an ASCII letter or digit, `.`, `_` or `-` (no `/`, no space, no quote).
$$\operatorname{nameChar}(x) \iff x \in [\texttt{A}..\texttt{Z}] \cup [\texttt{a}..\texttt{z}] \cup [\texttt{0}..\texttt{9}] \cup \{\texttt{.}, \texttt{\_}, \texttt{-}\}$$ -/
def nameChar (x : Char) : Bool := x.isAlphanum || x == '.' || x == '_' || x == '-'

/-- An entry name that may be listed: non-empty, only `nameChar`s, not starting with `.` (so not `.`, `..` or a hidden
file). Having no `/`, it is one path segment.
$$\operatorname{nameOk}(n) \iff n \ne \varepsilon \land (\forall x \in n:\ \operatorname{nameChar}(x)) \land n_0 \ne \texttt{.}$$ -/
def nameOk (n : String) : Bool := !n.isEmpty && n.all nameChar && !n.startsWith "."

/-- A character allowed in the root: a `nameChar` or `/`.
$$\operatorname{rootChar}(x) \iff \operatorname{nameChar}(x) \lor x = \texttt{/}$$ -/
def rootChar (x : Char) : Bool := nameChar x || x == '/'

/-- A root the module lists under: absolute, only `rootChar`s, ending in `/artifacts`, and every segment after the
leading `/` non-empty and neither `.` nor `..` (so the path is normalized and names the artifacts directory itself).
$$\operatorname{rootOk}(r) \iff r_0 = \texttt{/} \land (\forall x \in r:\ \operatorname{rootChar}(x)) \land r \text{ ends with } \texttt{/artifacts} \land (\forall s \in \operatorname{drop}_1(\operatorname{split}_{\texttt{/}}(r)):\ s \notin \{\varepsilon, \texttt{.}, \texttt{..}\})$$
Here $\operatorname{split}_{\texttt{/}}(r)$ cuts $r$ at every `/`, and $\operatorname{drop}_1$ removes its first (empty) part. -/
def rootOk (r : String) : Bool :=
  r.startsWith "/" && r.all rootChar && r.endsWith "/artifacts" &&
    ((r.splitOn "/").drop 1).all fun s => s != "" && s != "." && s != ".."

/-- The path of an entry: the root, `/`, the name.
$$\operatorname{path}(r, n) = r \mathbin{+\!\!+} \texttt{/} \mathbin{+\!\!+} n$$ -/
def pathOf (root name : String) : String := root ++ "/" ++ name

/-- One fact taken alone may be listed: a regular file with an allowed name, a link count below 2 (no checkout holds
it), and modified at least `floor` seconds before `now`.
$$\operatorname{ok}_c(f) \iff f.\mathit{file} \land \operatorname{nameOk}(f.\mathit{name}) \land f.\mathit{links} < 2 \land f.\mathit{mtime} + c.\mathit{floor} \le c.\mathit{now}$$ -/
def ok (c : Config) (f : Fact) : Bool :=
  f.file && nameOk f.name && decide (f.links < 2) && decide (f.mtime + c.ageFloor ≤ c.now)

/-- A fact is listed when every fact with its name is `ok` (a name reported twice, once linked, is kept).
$$\operatorname{eligible}_{c,F}(f) \iff \forall g \in F:\ g.\mathit{name} = f.\mathit{name} \Rightarrow \operatorname{ok}_c(g)$$ -/
def eligible (c : Config) (fs : List Fact) (f : Fact) : Bool :=
  fs.all fun g => g.name != f.name || ok c g

/-- The listed facts, in input order (a name given twice and eligible is listed twice).
$$\operatorname{gcList}(c, F) = [\,f \in F \mid \operatorname{eligible}_{c,F}(f)\,]$$ -/
def gcList (c : Config) (fs : List Fact) : List Fact := fs.filter (eligible c fs)

/-- The listed paths: none when the root is not allowed, else the path of every listed fact.
$$\operatorname{gcPaths}(c, F) = \begin{cases} [\,\operatorname{path}(c.\mathit{root}, f.\mathit{name}) \mid f \in \operatorname{gcList}(c, F)\,] & \operatorname{rootOk}(c.\mathit{root}) \\ [\,] & \text{otherwise} \end{cases}$$ -/
def gcPaths (c : Config) (fs : List Fact) : List String :=
  if rootOk c.root then (gcList c fs).map fun f => pathOf c.root f.name else []

/-- The bytes the listed files hold (0 when the root is not allowed).
$$\operatorname{listBytes}(c, F) = \begin{cases} \sum_{f \in \operatorname{gcList}(c, F)} f.\mathit{size} & \operatorname{rootOk}(c.\mathit{root}) \\ 0 & \text{otherwise} \end{cases}$$ -/
def listBytes (c : Config) (fs : List Fact) : Nat :=
  if rootOk c.root then ((gcList c fs).map (·.size)).sum else 0

/-- The bytes of the whole cache directory: the sum of every fact's size (0 for no facts).
$$\operatorname{cacheBytes}(F) = \sum_{f \in F} f.\mathit{size}$$ -/
def cacheBytes (fs : List Fact) : Nat := (fs.map (·.size)).sum

/-- The cache alert (named `sys.lakeCache` for a later `fw watch` rule): the cache holds more bytes than the budget.
$$\operatorname{alert}(c, F) \iff \operatorname{cacheBytes}(F) > c.\mathit{budget}$$ -/
def alert (c : Config) (fs : List Fact) : Bool := decide (cacheBytes fs > c.budget)

/-- A config for the examples. -/
private def c0 : Config := ⟨"/h/.elan/toolchains/t/lake/cache/artifacts", 10000, 7200, 100⟩

#guard nameOk "95998c8e69fc0bd7.o" && nameOk "d4b7e953ed4ebdab" && !nameOk "" && !nameOk ".." && !nameOk "."
#guard !nameOk "a/b" && !nameOk "a b" && !nameOk ".hidden" && !nameOk "a'b"
#guard rootOk "/h/.elan/toolchains/t/lake/cache/artifacts" && !rootOk "h/lake/cache/artifacts"
#guard !rootOk "/h/../etc/artifacts" && !rootOk "/h//artifacts" && !rootOk "/h/./artifacts" && !rootOk "/artifacts/x"
#guard !rootOk "/my cache/artifacts" && !rootOk "/" && !rootOk "" && rootOk "/artifacts"
#guard gcPaths c0 [⟨"a.o", true, 1, 2800, 5⟩] == ["/h/.elan/toolchains/t/lake/cache/artifacts/a.o"]
#guard gcPaths c0 [⟨"a.o", true, 1, 2801, 5⟩] == []
#guard gcPaths c0 [⟨"a.o", true, 2, 0, 5⟩] == []
#guard gcPaths c0 [⟨"a.o", false, 1, 0, 5⟩] == []
#guard gcPaths c0 [⟨"../x", true, 1, 0, 5⟩] == []
#guard gcPaths c0 [⟨"a.o", true, 1, 0, 5⟩, ⟨"a.o", true, 3, 0, 5⟩] == []
#guard gcPaths { c0 with root := "/tmp" } [⟨"a.o", true, 1, 0, 5⟩] == []
#guard gcPaths c0 [] == [] && listBytes c0 [] == 0 && cacheBytes [] == 0 && !alert c0 []
#guard listBytes c0 [⟨"a", true, 1, 0, 40⟩, ⟨"b", true, 2, 0, 70⟩] == 40
#guard alert c0 [⟨"a", true, 1, 0, 40⟩, ⟨"b", true, 2, 0, 61⟩] && !alert c0 [⟨"a", true, 1, 0, 40⟩, ⟨"b", true, 2, 0, 60⟩]

/-- **What a listed fact satisfies.** Every fact named like a listed fact is `ok`.
$$\forall c, F, f, g:\ f \in \operatorname{gcList}(c, F) \land g \in F \land g.\mathit{name} = f.\mathit{name} \Rightarrow \operatorname{ok}_c(g)$$
The four guarantees below read their conjuncts off this one. -/
theorem listed_ok (c : Config) (fs : List Fact) (f g : Fact) (hf : f ∈ gcList c fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : ok c g = true := by
  simp only [gcList, List.mem_filter, eligible, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq] at hf
  rcases hf.2 g hg with h | h
  · exact absurd hn h
  · exact h

/-- **Never lists a linked file.** Every fact named like a listed fact has a link count below 2, so no checkout's
`.lake` shares its inode.
$$\forall c, F, f, g:\ f \in \operatorname{gcList}(c, F) \land g \in F \land g.\mathit{name} = f.\mathit{name} \Rightarrow g.\mathit{links} < 2$$ -/
theorem never_lists_linked (c : Config) (fs : List Fact) (f g : Fact) (hf : f ∈ gcList c fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : g.links < 2 := by
  have h := listed_ok c fs f g hf hg hn
  simp only [ok, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.2

/-- **Never lists a young file.** Every fact named like a listed fact was modified at least the age floor before now.
$$\forall c, F, f, g:\ f \in \operatorname{gcList}(c, F) \land g \in F \land g.\mathit{name} = f.\mathit{name} \Rightarrow g.\mathit{mtime} + c.\mathit{floor} \le c.\mathit{now}$$ -/
theorem never_lists_young (c : Config) (fs : List Fact) (f g : Fact) (hf : f ∈ gcList c fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : g.mtime + c.ageFloor ≤ c.now := by
  have h := listed_ok c fs f g hf hg hn
  simp only [ok, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

/-- **Only inside the artifacts directory.** Every listed path is the allowed root, `/`, and one allowed name.
$$\forall c, F, p:\ p \in \operatorname{gcPaths}(c, F) \Rightarrow \operatorname{rootOk}(c.\mathit{root}) \land \exists n:\ p = c.\mathit{root} \mathbin{+\!\!+} \texttt{/} \mathbin{+\!\!+} n \land \operatorname{nameOk}(n)$$ -/
theorem inside_root_only (c : Config) (fs : List Fact) (p : String) (hp : p ∈ gcPaths c fs) :
    rootOk c.root = true ∧ ∃ n, p = c.root ++ "/" ++ n ∧ nameOk n = true := by
  unfold gcPaths at hp
  split at hp
  · rename_i hr
    refine ⟨hr, ?_⟩
    obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hp
    have h := listed_ok c fs f f hf (List.mem_filter.1 hf).1 rfl
    simp only [ok, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨f.name, rfl, h.1.1.2⟩
  · simp at hp

/-- `ok` only gains facts when `now` grows or the floor shrinks.
$$\forall c, c', g:\ c.\mathit{now} \le c'.\mathit{now} \land c'.\mathit{floor} \le c.\mathit{floor} \land \operatorname{ok}_c(g) \Rightarrow \operatorname{ok}_{c'}(g)$$ -/
theorem ok_mono (c c' : Config) (g : Fact) (hn : c.now ≤ c'.now) (ha : c'.ageFloor ≤ c.ageFloor)
    (h : ok c g = true) : ok c' g = true := by
  simp only [ok, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
  exact ⟨h.1, by omega⟩

/-- **Monotone in age.** With the same root, a later `now` or a smaller floor lists every path listed before.
$$\forall c, c', F, p:\ c.\mathit{root} = c'.\mathit{root} \land c.\mathit{now} \le c'.\mathit{now} \land c'.\mathit{floor} \le c.\mathit{floor} \land p \in \operatorname{gcPaths}(c, F) \Rightarrow p \in \operatorname{gcPaths}(c', F)$$ -/
theorem list_monotone_in_age (c c' : Config) (fs : List Fact) (p : String) (hr : c.root = c'.root)
    (hn : c.now ≤ c'.now) (ha : c'.ageFloor ≤ c.ageFloor) (hp : p ∈ gcPaths c fs) : p ∈ gcPaths c' fs := by
  unfold gcPaths at hp ⊢
  rw [← hr]
  split at hp
  · rename_i hro
    simp only [hro, ↓reduceIte]
    obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hp
    refine List.mem_map.2 ⟨f, ?_, rfl⟩
    simp only [gcList, List.mem_filter, eligible, List.all_eq_true, Bool.or_eq_true] at hf ⊢
    exact ⟨hf.1, fun g hg => (hf.2 g hg).imp id (ok_mono c c' g hn ha)⟩
  · simp at hp

/-- **Complete.** Under an allowed root, a fact all of whose namesakes are `ok` is listed.
$$\forall c, F, f:\ \operatorname{rootOk}(c.\mathit{root}) \land f \in F \land (\forall g \in F:\ g.\mathit{name} = f.\mathit{name} \Rightarrow \operatorname{ok}_c(g)) \Rightarrow \operatorname{path}(c.\mathit{root}, f.\mathit{name}) \in \operatorname{gcPaths}(c, F)$$ -/
theorem list_complete (c : Config) (fs : List Fact) (f : Fact) (hr : rootOk c.root = true) (hf : f ∈ fs)
    (h : ∀ g ∈ fs, g.name = f.name → ok c g = true) : pathOf c.root f.name ∈ gcPaths c fs := by
  unfold gcPaths
  simp only [hr, ↓reduceIte]
  refine List.mem_map.2 ⟨f, ?_, rfl⟩
  simp only [gcList, List.mem_filter, eligible, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq]
  refine ⟨hf, fun g hg => ?_⟩
  by_cases hn : g.name = f.name
  · exact Or.inr (h g hg hn)
  · exact Or.inl hn

/-- **The alert.** The verdict `alert` (`fw lake-gc --check` exits 1 on it) holds exactly when the cache holds more bytes
than the budget; equal to the budget is no alert.
$$\forall c, F:\ \operatorname{alert}(c, F) \iff \operatorname{cacheBytes}(F) > c.\mathit{budget}$$ -/
theorem alert_iff (c : Config) (fs : List Fact) : alert c fs = true ↔ cacheBytes fs > c.budget := by
  simp [alert]

end Fw.Ops.LakeGc

/-! ## Wire: `ops.lakeGc` -/

namespace Fw.Wire.LakeGc
open Lean Fw.Ops.LakeGc Fw.Wire.Ops

/-- One fact from JSON: `name`, `file`, `links`, `mtime` (seconds), `size` (bytes), all required. -/
def factOf (j : Json) : Except String Fact := do
  pure ⟨← str j "name", ← asBool "file" (← field j "file"), ← nat j "links", ← nat j "mtime", ← nat j "size"⟩

/-- `ops.lakeGc`: `root`, `now`, `ageFloor`? (default 7200), `budget`? (default 20 GB), `files` [fact] → `rootOk`,
`paths` (`gcPaths`), `listed`, `listBytes`, `cacheBytes`, `files` (count), `ageFloor`, `budget`, `alert`. -/
def opLakeGc (req : Json) : Except String Reply := do
  let c : Config := ⟨← str req "root", ← nat req "now", ← natD req "ageFloor" defaultAgeFloor,
    ← natD req "budget" budgetBytes⟩
  let fs ← (← arr req "files").toList.mapM factOf
  let ps := gcPaths c fs
  pure [("rootOk", .bool (rootOk c.root)), ("paths", .arr (ps.toArray.map .str)), ("listed", toJson ps.length),
    ("listBytes", toJson (listBytes c fs)), ("cacheBytes", toJson (cacheBytes fs)), ("files", toJson fs.length),
    ("ageFloor", toJson c.ageFloor), ("budget", toJson c.budget), ("alert", .bool (alert c fs))]

/-- The ops of this module. -/
def ops : List String := ["ops.lakeGc"]

/-- Dispatch (`none` when the op is not `ops.lakeGc`). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.lakeGc" => some (opLakeGc req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("root", .str "/a/artifacts"), ("now", toJson 0),
  ("files", .arr #[])])).isSome

end Fw.Wire.LakeGc
