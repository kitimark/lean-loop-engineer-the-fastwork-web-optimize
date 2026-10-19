import Lean.Data.Json
import Std.Data.HashSet
import Fw.Ops.Wire

/-!
# Which Lake cache artifacts `fw lake-gc` may list (tasks `lean-bin-slim`, `lake-gc-refs`)
An entry is listed when no checkout names it and no live Lake writer may own it; the age floor is a named fallback.
-/
namespace Fw.Ops.LakeGc

/-- One directory entry of the artifacts directory, as the glue reads it with `lstat`: its name, whether it is a
regular file, its hard-link count, its modification and inode-change times (whole seconds since the epoch) and its
size in bytes. -/
structure Fact where
  name : String
  file : Bool
  links : Nat
  mtime : Nat
  ctime : Nat
  size : Nat
deriving Repr, DecidableEq, BEq

/-- A checkout and every string its Lake `.trace` outputs and `.hash` files name. -/
structure Checkout where
  path : String
  refs : List String
deriving Repr

/-- A live process: pid, start time (whole seconds since the epoch), executable path, argument line and cwd. -/
structure Proc where
  pid : Nat
  start : Nat
  exe : String
  args : String
  cwd : Option String
deriving Repr

/-- Why the list falls back to the age floor: a fact family the identity rule needs was not gathered. -/
inductive Fallback where
  | noCheckoutList
  | noProcessTable
  | noOutputsMap
deriving Repr, DecidableEq

/-- The run's inputs besides the cache entries: the artifacts directory, now, the age floor, the alert budget, the
checkouts, the process table and the names in Lake's outputs map (`none`: not gathered). -/
structure Config where
  root : String
  now : Nat
  ageFloor : Nat
  budget : Nat
  checkouts : Option (List Checkout)
  procs : Option (List Proc)
  outputs : Option (List String)
deriving Repr

/-- The default age floor of the fallback: 2 hours. -/
def defaultAgeFloor : Nat := 7200

/-- The default alert budget: 20 GB (decimal), research/notes/2026/10-18-lean-bin-slim.md. -/
def budgetBytes : Nat := 20000000000

/-- A character allowed in an entry name: an ASCII letter or digit, `.`, `_` or `-` (no `/`, no space, no quote). -/
def nameChar (x : Char) : Bool := x.isAlphanum || x == '.' || x == '_' || x == '-'

/-- An entry name that may be listed: non-empty, only `nameChar`s, not starting with `.` (so not `.`, `..` or a hidden
file). Having no `/`, it is one path segment. -/
def nameOk (n : String) : Bool := !n.isEmpty && n.all nameChar && !n.startsWith "."

/-- A character allowed in the root: a `nameChar` or `/`. -/
def rootChar (x : Char) : Bool := nameChar x || x == '/'

/-- A root the module lists under: absolute, only `rootChar`s, ending in `/artifacts`, and every segment after the
leading `/` non-empty and neither `.` nor `..` (so the path is normalized and names the artifacts directory itself).
Here `split_(/)(r)` cuts `r` at every `/`, and `drop_1` removes its first (empty) part. -/
def rootOk (r : String) : Bool :=
  r.startsWith "/" && r.all rootChar && r.endsWith "/artifacts" &&
    ((r.splitOn "/").drop 1).all fun s => s != "" && s != "." && s != ".."

/-- The path of an entry: the root, `/`, the name. -/
def pathOf (root name : String) : String := root ++ "/" ++ name

/-- The last `/`-segment of a path. -/
def baseName (p : String) : String := ((p.splitOn "/").getLast?).getD p

/-- The Lake subcommands that write nothing to the artifact cache themselves. -/
def readOnlyCommands : List String := ["serve", "env"]

/-- The non-empty space-separated words of a process's argument line. -/
def argv (p : Proc) : List String := (p.args.splitOn " ").filter (· != "")

/-- A live process that may write or link cache entries: a `lake` executable not run exactly as `lake serve` or
`lake env`. -/
def writer (p : Proc) : Bool :=
  baseName p.exe == "lake" && !readOnlyCommands.contains (((argv p).drop 1).headD "")

/-- The basis of the list: `none` is the identity rule; `some r` is the age floor with reason `r`. -/
def fallback (c : Config) : Option Fallback :=
  match c.checkouts, c.procs with
  | none, _ => some .noCheckoutList
  | some _, none => some .noProcessTable
  | some _, some ps => if ps.any writer && c.outputs.isNone then some .noOutputsMap else none

/-- The part of a name before its first `.`: the content hash of a cache entry `hash.ext`. -/
def stem (n : String) : String := (n.splitOn ".").headD n

/-- Checkout `w` names entry `n`: a trace output equal to `n`, or a hash file equal to its hash. -/
def refersTo (w : Checkout) (n : String) : Bool := w.refs.contains n || w.refs.contains (stem n)

/-- Some gathered checkout names entry `n`. -/
def referenced (c : Config) (n : String) : Bool := (c.checkouts.getD []).any (refersTo · n)

/-- The inode of `f` changed (created, written, linked or unlinked) at or after `p` started. -/
def touchedSince (p : Proc) (f : Fact) : Bool := decide (p.start ≤ f.ctime)

/-- Lake's outputs map names `f`, so a build may resolve and link it. -/
def linkable (c : Config) (f : Fact) : Bool := (c.outputs.getD []).contains f.name

/-- A live writer may still own `f`: it may have created it, or may link it from the outputs map. -/
def liveOwned (c : Config) (f : Fact) : Bool :=
  (c.procs.getD []).any fun p => writer p && (touchedSince p f || linkable c f)

/-- `f` was modified at least the age floor before now. -/
def ageOk (c : Config) (f : Fact) : Bool := decide (f.mtime + c.ageFloor ≤ c.now)

/-- A regular file with an allowed name that no other directory entry hard-links. -/
def unheld (f : Fact) : Bool := f.file && nameOk f.name && decide (f.links < 2)

/-- One fact taken alone may be listed: unheld, named by no checkout, and either not owned by a live writer
(identity) or older than the floor (fallback). -/
def ok (c : Config) (f : Fact) : Bool :=
  unheld f && !referenced c f.name &&
    match fallback c with
    | none => !liveOwned c f
    | some _ => ageOk c f

/-- The rule before task `lake-gc-refs`: unheld and older than the floor. -/
def ageRuleOk (c : Config) (f : Fact) : Bool := unheld f && ageOk c f

/-- The facts every one of whose namesakes passes `p`, in input order. -/
def listBy (p : Fact → Bool) (fs : List Fact) : List Fact :=
  fs.filter fun f => fs.all fun g => g.name != f.name || p g

/-- The listed facts. -/
def gcList (c : Config) (fs : List Fact) : List Fact := listBy (ok c) fs

/-- The facts the rule before task `lake-gc-refs` lists. -/
def ageList (c : Config) (fs : List Fact) : List Fact := listBy (ageRuleOk c) fs

/-- The paths of `l`: none when the root is not allowed. -/
def pathsOf (c : Config) (l : List Fact) : List String :=
  if rootOk c.root then l.map fun f => pathOf c.root f.name else []

/-- The bytes of `l` (0 when the root is not allowed). -/
def bytesOf (c : Config) (l : List Fact) : Nat :=
  if rootOk c.root then (l.map (·.size)).sum else 0

/-- The listed paths. -/
def gcPaths (c : Config) (fs : List Fact) : List String := pathsOf c (gcList c fs)

/-- The bytes the listed files hold. -/
def listBytes (c : Config) (fs : List Fact) : Nat := bytesOf c (gcList c fs)

/-- The bytes of the whole cache directory: the sum of every fact's size (0 for no facts). -/
def cacheBytes (fs : List Fact) : Nat := (fs.map (·.size)).sum

/-- The cache alert (named `sys.lakeCache` for a later `fw watch` rule): the cache holds more bytes than the budget. -/
def alert (c : Config) (fs : List Fact) : Bool := decide (cacheBytes fs > c.budget)

/-- `listBy` with the failing names in a hash set: linear instead of quadratic. -/
def listFast (p : Fact → Bool) (fs : List Fact) : List Fact :=
  let bad : Std.HashSet String := .ofList ((fs.filter fun g => !p g).map (·.name))
  fs.filter fun f => !bad.contains f.name

/-- The reference and map sets, the live writers and the basis, computed once per run. -/
structure Index where
  refs : Std.HashSet String
  outs : Std.HashSet String
  writers : List Proc
  basis : Option Fallback

/-- The index of a config. -/
def Index.of (c : Config) : Index :=
  ⟨.ofList ((c.checkouts.getD []).flatMap (·.refs)), .ofList (c.outputs.getD []), (c.procs.getD []).filter writer,
    fallback c⟩

/-- `ok` over an index. -/
def okFast (c : Config) (ix : Index) (f : Fact) : Bool :=
  unheld f && !(ix.refs.contains f.name || ix.refs.contains (stem f.name)) &&
    match ix.basis with
    | none => !ix.writers.any fun p => touchedSince p f || ix.outs.contains f.name
    | some _ => ageOk c f

/-- The checkout under which `cwd` lies, the longest such path. -/
def checkoutOf (ws : List Checkout) (cwd : String) : Option String :=
  (ws.filter fun w => cwd == w.path || cwd.startsWith (w.path ++ "/")).foldl
    (fun best w => match best with
      | some b => if b.length < w.path.length then some w.path else best
      | none => some w.path) none

/-- Per checkout: its path, the number of facts it names and their bytes. -/
def refStats (c : Config) (fs : List Fact) : List (String × Nat × Nat) :=
  (c.checkouts.getD []).map fun w =>
    let s : Std.HashSet String := .ofList w.refs
    let hit := fs.filter fun f => s.contains f.name || s.contains (stem f.name)
    (w.path, hit.length, (hit.map (·.size)).sum)

/-- A config for the examples. -/
private def c0 : Config :=
  ⟨"/h/.elan/toolchains/t/lake/cache/artifacts", 10000, 7200, 100, some [], some [], some []⟩

/-- A live `lake build` started at 9000. -/
private def build0 : Proc := ⟨7, 9000, "/h/.elan/toolchains/t/bin/lake", "/h/.elan/toolchains/t/bin/lake build", none⟩

#guard nameOk "95998c8e69fc0bd7.o" && nameOk "d4b7e953ed4ebdab" && !nameOk "" && !nameOk ".." && !nameOk "."
#guard !nameOk "a/b" && !nameOk "a b" && !nameOk ".hidden" && !nameOk "a'b"
#guard rootOk "/h/.elan/toolchains/t/lake/cache/artifacts" && !rootOk "h/lake/cache/artifacts"
#guard !rootOk "/h/../etc/artifacts" && !rootOk "/h//artifacts" && !rootOk "/h/./artifacts" && !rootOk "/artifacts/x"
#guard !rootOk "/my cache/artifacts" && !rootOk "/" && !rootOk "" && rootOk "/artifacts"
#guard writer build0 && writer { build0 with args := "lake setup-file X.lean" } && writer { build0 with args := "lake" }
#guard !writer { build0 with args := "/t/bin/lake serve -- -Dx" } && !writer { build0 with args := "lake env lean --run a" }
#guard writer { build0 with args := "lake -d serve build" } && !writer { build0 with exe := "/t/bin/lean" }
#guard writer { build0 with exe := "/my dir/bin/lake", args := "/my dir/bin/lake serve" }
#guard stem "a1.olean" == "a1" && stem "a1" == "a1" && stem "a.b.c" == "a"
#guard fallback { c0 with checkouts := none } == some .noCheckoutList
#guard fallback { c0 with procs := none } == some .noProcessTable
#guard fallback { c0 with procs := some [build0], outputs := none } == some .noOutputsMap
#guard fallback { c0 with outputs := none } == none && fallback { c0 with procs := some [build0] } == none
#guard gcPaths c0 [⟨"a.o", true, 1, 9999, 9999, 5⟩] == ["/h/.elan/toolchains/t/lake/cache/artifacts/a.o"]
#guard gcPaths c0 [⟨"a.o", true, 2, 0, 0, 5⟩] == [] && gcPaths c0 [⟨"a.o", false, 1, 0, 0, 5⟩] == []
#guard gcPaths c0 [⟨"../x", true, 1, 0, 0, 5⟩] == []
#guard gcPaths c0 [⟨"a.o", true, 1, 0, 0, 5⟩, ⟨"a.o", true, 3, 0, 0, 5⟩] == []
#guard gcPaths { c0 with checkouts := some [⟨"/w", ["a.o"]⟩] } [⟨"a.o", true, 1, 0, 0, 5⟩] == []
#guard gcPaths { c0 with checkouts := some [⟨"/w", ["a"]⟩] } [⟨"a.o", true, 1, 0, 0, 5⟩] == []
#guard gcPaths { c0 with procs := some [build0] } [⟨"a.o", true, 1, 0, 9000, 5⟩] == []
#guard gcPaths { c0 with procs := some [build0] } [⟨"a.o", true, 1, 0, 8999, 5⟩] != []
#guard gcPaths { c0 with procs := some [build0], outputs := some ["a.o"] } [⟨"a.o", true, 1, 0, 0, 5⟩] == []
#guard gcPaths { c0 with procs := none } [⟨"a.o", true, 1, 2801, 2801, 5⟩] == []
#guard gcPaths { c0 with procs := none } [⟨"a.o", true, 1, 2800, 2800, 5⟩] != []
#guard gcPaths { c0 with root := "/tmp" } [⟨"a.o", true, 1, 0, 0, 5⟩] == []
#guard gcPaths c0 [] == [] && listBytes c0 [] == 0 && cacheBytes [] == 0 && !alert c0 []
#guard listBytes c0 [⟨"a", true, 1, 0, 0, 40⟩, ⟨"b", true, 2, 0, 0, 70⟩] == 40
#guard alert c0 [⟨"a", true, 1, 0, 0, 40⟩, ⟨"b", true, 2, 0, 0, 61⟩] &&
  !alert c0 [⟨"a", true, 1, 0, 0, 40⟩, ⟨"b", true, 2, 0, 0, 60⟩]
#guard checkoutOf [⟨"/r", []⟩, ⟨"/r/.claude/w1", []⟩] "/r/.claude/w1/lean" == some "/r/.claude/w1"
#guard checkoutOf [⟨"/r", []⟩] "/r2" == none && checkoutOf [⟨"/r", []⟩] "/r" == some "/r"
#guard refStats { c0 with checkouts := some [⟨"/w", ["a", "b.c"]⟩] }
  [⟨"a.o", true, 1, 0, 0, 5⟩, ⟨"b.c", true, 1, 0, 0, 7⟩, ⟨"d", true, 1, 0, 0, 9⟩] == [("/w", 2, 12)]

/-- **What a listed fact satisfies.** Every fact named like a fact `p` lists passes `p`. -/
theorem listBy_ok (p : Fact → Bool) (fs : List Fact) (f g : Fact) (hf : f ∈ listBy p fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : p g = true := by
  simp only [listBy, List.mem_filter, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq] at hf
  rcases hf.2 g hg with h | h
  · exact absurd hn h
  · exact h

/-- **What a listed fact satisfies.** Every fact named like a listed fact is `ok`. -/
theorem listed_ok (c : Config) (fs : List Fact) (f g : Fact) (hf : f ∈ gcList c fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : ok c g = true :=
  listBy_ok (ok c) fs f g hf hg hn

/-- A listed fact is `ok`. -/
theorem listed_self (c : Config) (fs : List Fact) (f : Fact) (hf : f ∈ gcList c fs) : ok c f = true :=
  listed_ok c fs f f hf (List.mem_filter.1 hf).1 rfl

/-- **Never lists a linked file.** Every fact named like a listed fact has a link count below 2. -/
theorem never_lists_linked (c : Config) (fs : List Fact) (f g : Fact) (hf : f ∈ gcList c fs) (hg : g ∈ fs)
    (hn : g.name = f.name) : g.links < 2 := by
  have h := listed_ok c fs f g hf hg hn
  simp only [ok, unheld, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1.2

/-- A listed fact is named by no gathered checkout. -/
theorem listed_unreferenced (c : Config) (fs : List Fact) (f : Fact) (hf : f ∈ gcList c fs) :
    referenced c f.name = false := by
  have h := listed_self c fs f hf
  simp only [ok, Bool.and_eq_true, Bool.not_eq_true'] at h
  exact h.1.2

/-- **Never lists an entry a checkout's trace names.** -/
theorem never_lists_named_by_trace (c : Config) (fs : List Fact) (ws : List Checkout) (w : Checkout) (f : Fact)
    (hc : c.checkouts = some ws) (hw : w ∈ ws) (hf : f ∈ gcList c fs) : w.refs.contains f.name = false := by
  have h := listed_unreferenced c fs f hf
  simp only [referenced, hc, Option.getD_some, List.any_eq_false, refersTo, Bool.or_eq_true, not_or] at h
  simpa using (h w hw).1

/-- **Never lists an entry whose stem a checkout names.** -/
theorem never_lists_named_by_stem (c : Config) (fs : List Fact) (ws : List Checkout) (w : Checkout) (f : Fact)
    (hc : c.checkouts = some ws) (hw : w ∈ ws) (hf : f ∈ gcList c fs) : w.refs.contains (stem f.name) = false := by
  have h := listed_unreferenced c fs f hf
  simp only [referenced, hc, Option.getD_some, List.any_eq_false, refersTo, Bool.or_eq_true, not_or] at h
  simpa using (h w hw).2

/-- Under the identity basis a listed fact is owned by no live writer. -/
theorem listed_not_owned (c : Config) (fs : List Fact) (f : Fact) (hb : fallback c = none) (hf : f ∈ gcList c fs) :
    liveOwned c f = false := by
  have h := listed_self c fs f hf
  simp only [ok, hb, Bool.and_eq_true, Bool.not_eq_true'] at h
  exact h.2

/-- **Never lists an entry a live writer may have created or linked** (identity basis): its inode changed before every
live writer started. -/
theorem never_lists_touched_by_writer (c : Config) (fs : List Fact) (ps : List Proc) (p : Proc) (f : Fact)
    (hb : fallback c = none) (hc : c.procs = some ps) (hp : p ∈ ps) (hw : writer p = true)
    (hf : f ∈ gcList c fs) : f.ctime < p.start := by
  have h := listed_not_owned c fs f hb hf
  simp only [liveOwned, hc, Option.getD_some, List.any_eq_false, Bool.and_eq_true, Bool.or_eq_true, not_and,
    not_or] at h
  have := (h p hp hw).1
  simp only [touchedSince, decide_eq_true_eq] at this
  omega

/-- **Never lists an entry a live writer may link from the outputs map** (identity basis): the map was read and does
not name it. -/
theorem never_lists_linkable_by_writer (c : Config) (fs : List Fact) (ps : List Proc) (p : Proc) (f : Fact)
    (hb : fallback c = none) (hc : c.procs = some ps) (hp : p ∈ ps) (hw : writer p = true)
    (hf : f ∈ gcList c fs) : ∃ os, c.outputs = some os ∧ os.contains f.name = false := by
  have h := listed_not_owned c fs f hb hf
  simp only [liveOwned, hc, Option.getD_some, List.any_eq_false, Bool.and_eq_true, Bool.or_eq_true, not_and,
    not_or] at h
  have hl := (h p hp hw).2
  have hany : ps.any writer = true := List.any_eq_true.2 ⟨p, hp, hw⟩
  cases ho : c.outputs with
  | none =>
    unfold fallback at hb
    split at hb <;> simp_all
  | some os =>
    refine ⟨os, rfl, ?_⟩
    simpa [linkable, ho] using hl

/-- **The fallback never lists a young file.** -/
theorem fallback_never_lists_young (c : Config) (fs : List Fact) (r : Fallback) (f : Fact)
    (hb : fallback c = some r) (hf : f ∈ gcList c fs) : f.mtime + c.ageFloor ≤ c.now := by
  have h := listed_self c fs f hf
  simp only [ok, hb, ageOk, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

/-- **Fallback `noCheckoutList`** exactly when the checkouts were not gathered. -/
theorem fallback_noCheckoutList (c : Config) : fallback c = some .noCheckoutList ↔ c.checkouts = none := by
  unfold fallback
  rcases c.checkouts with _ | ws <;> rcases c.procs with _ | ps <;> simp

/-- **Fallback `noProcessTable`** exactly when the checkouts were gathered and the process table was not. -/
theorem fallback_noProcessTable (c : Config) :
    fallback c = some .noProcessTable ↔ c.checkouts.isSome ∧ c.procs = none := by
  unfold fallback
  rcases c.checkouts with _ | ws <;> rcases c.procs with _ | ps <;> simp

/-- **Fallback `noOutputsMap`** exactly when checkouts and processes were gathered, a writer is live, and the outputs
map was not read. -/
theorem fallback_noOutputsMap (c : Config) :
    fallback c = some .noOutputsMap ↔
      c.checkouts.isSome ∧ (∃ ps, c.procs = some ps ∧ ps.any writer = true) ∧ c.outputs = none := by
  unfold fallback
  rcases c.checkouts with _ | ws <;> rcases c.procs with _ | ps <;> simp
  cases ha : ps.any writer <;> cases c.outputs <;> simp_all

/-- **Identity basis** exactly when checkouts and processes were gathered and no writer is live or the outputs map was
read. -/
theorem identity_basis (c : Config) :
    fallback c = none ↔
      c.checkouts.isSome ∧ ∃ ps, c.procs = some ps ∧ (ps.any writer = false ∨ c.outputs.isSome) := by
  unfold fallback
  rcases c.checkouts with _ | ws <;> rcases c.procs with _ | ps <;> simp
  cases ha : ps.any writer <;> cases c.outputs <;> simp_all

/-- **Superset of the age rule when no build runs.** With checkouts and processes gathered and no live writer, every
fact the age rule lists whose name no checkout names is listed. -/
theorem superset_when_idle (c : Config) (fs : List Fact) (ps : List Proc) (f : Fact) (hc : c.checkouts.isSome)
    (hp : c.procs = some ps) (hidle : ∀ p ∈ ps, writer p = false) (hf : f ∈ ageList c fs)
    (hr : referenced c f.name = false) : f ∈ gcList c fs := by
  have hany : ps.any writer = false := List.any_eq_false.2 fun p hp' => by simp [hidle p hp']
  have hb : fallback c = none := (identity_basis c).2 ⟨hc, ps, hp, Or.inl hany⟩
  have hown : ∀ g : Fact, liveOwned c g = false := fun g => by
    simp only [liveOwned, hp, Option.getD_some, List.any_eq_false, Bool.and_eq_true, not_and]
    intro p hp' hw
    simp [hidle p hp'] at hw
  simp only [gcList, ageList, listBy, List.mem_filter, List.all_eq_true, Bool.or_eq_true, bne_iff_ne,
    ne_eq] at hf ⊢
  refine ⟨hf.1, fun g hg => ?_⟩
  by_cases hn : g.name = f.name
  · rcases hf.2 g hg with h | h
    · exact absurd hn h
    · simp only [ageRuleOk, Bool.and_eq_true] at h
      right
      simp [ok, h.1, hn, hr, hb, hown g]
  · exact Or.inl hn

/-- **Only inside the artifacts directory.** Every listed path is the allowed root, `/`, and one allowed name. -/
theorem inside_root_only (c : Config) (fs : List Fact) (p : String) (hp : p ∈ gcPaths c fs) :
    rootOk c.root = true ∧ ∃ n, p = c.root ++ "/" ++ n ∧ nameOk n = true := by
  unfold gcPaths pathsOf at hp
  split at hp
  · rename_i hr
    refine ⟨hr, ?_⟩
    obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hp
    have h := listed_self c fs f hf
    simp only [ok, unheld, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨f.name, rfl, h.1.1.1.2⟩
  · simp at hp

/-- `ok` only gains facts when `now` grows or the floor shrinks. -/
theorem ok_mono (c : Config) (now' floor' : Nat) (g : Fact) (hn : c.now ≤ now') (ha : floor' ≤ c.ageFloor)
    (h : ok c g = true) : ok { c with now := now', ageFloor := floor' } g = true := by
  have hb : fallback { c with now := now', ageFloor := floor' } = fallback c := rfl
  have hr : referenced { c with now := now', ageFloor := floor' } g.name = referenced c g.name := rfl
  have hl : liveOwned { c with now := now', ageFloor := floor' } g = liveOwned c g := rfl
  simp only [ok, hb, hr, hl] at h ⊢
  cases hfb : fallback c with
  | none => simpa [hfb] using h
  | some _ =>
    simp only [hfb, ageOk, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, by omega⟩

/-- **Monotone in age.** A later `now` or a smaller floor lists every path listed before. -/
theorem list_monotone_in_age (c : Config) (now' floor' : Nat) (fs : List Fact) (p : String) (hn : c.now ≤ now')
    (ha : floor' ≤ c.ageFloor) (hp : p ∈ gcPaths c fs) : p ∈ gcPaths { c with now := now', ageFloor := floor' } fs := by
  unfold gcPaths pathsOf at hp ⊢
  split at hp
  · rename_i hro
    simp only [hro, ↓reduceIte]
    obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hp
    refine List.mem_map.2 ⟨f, ?_, rfl⟩
    simp only [gcList, listBy, List.mem_filter, List.all_eq_true, Bool.or_eq_true] at hf ⊢
    exact ⟨hf.1, fun g hg => (hf.2 g hg).imp id (ok_mono c now' floor' g hn ha)⟩
  · simp at hp

/-- **Complete.** Under an allowed root, a fact all of whose namesakes are `ok` is listed. -/
theorem list_complete (c : Config) (fs : List Fact) (f : Fact) (hr : rootOk c.root = true) (hf : f ∈ fs)
    (h : ∀ g ∈ fs, g.name = f.name → ok c g = true) : pathOf c.root f.name ∈ gcPaths c fs := by
  unfold gcPaths pathsOf
  simp only [hr, ↓reduceIte]
  refine List.mem_map.2 ⟨f, ?_, rfl⟩
  simp only [gcList, listBy, List.mem_filter, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq]
  refine ⟨hf, fun g hg => ?_⟩
  by_cases hn : g.name = f.name
  · exact Or.inr (h g hg hn)
  · exact Or.inl hn

/-- **The alert.** The verdict `alert` (`fw lake-gc --check` exits 1 on it) holds exactly when the cache holds more bytes
than the budget; equal to the budget is no alert. -/
theorem alert_iff (c : Config) (fs : List Fact) : alert c fs = true ↔ cacheBytes fs > c.budget := by
  simp [alert]

/-- **Writers run `lake`.** -/
theorem writer_runs_lake (p : Proc) (h : writer p = true) : baseName p.exe = "lake" := by
  simp only [writer, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

/-- **`lake serve` and `lake env` are not writers.** -/
theorem read_only_not_writer (p : Proc) (h : readOnlyCommands.contains (((argv p).drop 1).headD "") = true) :
    writer p = false := by
  simp only [writer, h, Bool.not_true, Bool.and_false]

/-- `listFast` lists what `listBy` lists. -/
theorem listFast_eq (p : Fact → Bool) (fs : List Fact) : listFast p fs = listBy p fs := by
  unfold listFast listBy
  refine List.filter_congr fun f _ => ?_
  rw [Bool.eq_iff_iff]
  simp only [Std.HashSet.contains_ofList, Bool.not_eq_true', List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq]
  rw [← Bool.not_eq_true, List.contains_iff_mem]
  simp only [List.mem_map, List.mem_filter, Bool.not_eq_true']
  constructor
  · intro h x hx
    by_cases hn : x.name = f.name
    · right
      cases hp : p x
      · exact absurd ⟨x, ⟨hx, hp⟩, hn⟩ h
      · rfl
    · exact Or.inl hn
  · rintro h ⟨x, ⟨hx, hp⟩, hn⟩
    rcases h x hx with h' | h'
    · exact h' hn
    · simp [h'] at hp

/-- `okFast` on the config's index is `ok`. -/
theorem okFast_eq (c : Config) (f : Fact) : okFast c (Index.of c) f = ok c f := by
  have hr : ((Std.HashSet.ofList ((c.checkouts.getD []).flatMap (·.refs))).contains f.name ||
      (Std.HashSet.ofList ((c.checkouts.getD []).flatMap (·.refs))).contains (stem f.name)) =
      referenced c f.name := by
    rw [Bool.eq_iff_iff]
    simp only [Std.HashSet.contains_ofList, referenced, refersTo, Bool.or_eq_true, List.any_eq_true,
      List.contains_iff_mem, List.mem_flatMap]
    constructor
    · rintro (⟨w, hw, h⟩ | ⟨w, hw, h⟩)
      · exact ⟨w, hw, Or.inl h⟩
      · exact ⟨w, hw, Or.inr h⟩
    · rintro ⟨w, hw, h | h⟩
      · exact Or.inl ⟨w, hw, h⟩
      · exact Or.inr ⟨w, hw, h⟩
  have hl : ((c.procs.getD []).filter writer).any (fun p => touchedSince p f ||
      (Std.HashSet.ofList (c.outputs.getD [])).contains f.name) = liveOwned c f := by
    rw [Bool.eq_iff_iff]
    simp only [Std.HashSet.contains_ofList, liveOwned, linkable, List.any_eq_true, List.mem_filter,
      Bool.and_eq_true]
    constructor
    · rintro ⟨p, ⟨hp, hw⟩, h⟩
      exact ⟨p, hp, hw, h⟩
    · rintro ⟨p, hp, hw, h⟩
      exact ⟨p, ⟨hp, hw⟩, h⟩
  simp only [okFast, Index.of, ok]
  rw [hr]
  cases fallback c with
  | none => simp only; rw [hl]
  | some _ => rfl

/-- **The run's list is the spec's list.** -/
theorem fast_eq (c : Config) (fs : List Fact) : listFast (okFast c (Index.of c)) fs = gcList c fs := by
  rw [listFast_eq]
  unfold gcList
  congr 1
  funext f
  exact okFast_eq c f

end Fw.Ops.LakeGc

/-! ## Wire: `ops.lakeGc` -/

namespace Fw.Wire.LakeGc
open Lean Fw.Ops.LakeGc Fw.Wire.Ops

/-- One fact from JSON: `name`, `file`, `links`, `mtime`, `ctime` (seconds), `size` (bytes), all required. -/
def factOf (j : Json) : Except String Fact := do
  pure ⟨← str j "name", ← asBool "file" (← field j "file"), ← nat j "links", ← nat j "mtime", ← nat j "ctime",
    ← nat j "size"⟩

/-- A list of strings from JSON. -/
def strsOf (k : String) (j : Json) : Except String (List String) := do
  (← asArr k j).toList.mapM (asStr k)

/-- One checkout from JSON: `path`, `refs` [string]. -/
def checkoutOfJson (j : Json) : Except String Checkout := do
  pure ⟨← str j "path", ← strsOf "refs" (← field j "refs")⟩

/-- One process from JSON: `pid`, `start` (seconds), `exe`, `args`, `cwd`? (string or null). -/
def procOf (j : Json) : Except String Proc := do
  let cwd ← match opt j "cwd" with
    | none => pure none
    | some v => some <$> asStr "cwd" v
  pure ⟨← nat j "pid", ← nat j "start", ← str j "exe", ← str j "args", cwd⟩

/-- An optional array field decoded element-wise (absent or null: `none`). -/
def optList {α : Type} (j : Json) (k : String) (dec : Json → Except String α) : Except String (Option (List α)) :=
  match opt j k with
  | none => pure none
  | some v => do pure (some (← (← asArr k v).toList.mapM dec))

/-- The name of a fallback reason. -/
def fallbackName : Fallback → String
  | .noCheckoutList => "noCheckoutList"
  | .noProcessTable => "noProcessTable"
  | .noOutputsMap => "noOutputsMap"

/-- `ops.lakeGc`: `root`, `now`, `ageFloor`? (default 7200), `budget`? (default 20 GB), `files` [fact], `checkouts`?
[{path, refs}], `procs`? [{pid, start, exe, args, cwd?}], `outputs`? [name] → `rootOk`, `paths` (`gcPaths`),
`listed`, `listBytes`, `cacheBytes`, `files` (count), `ageFloor`, `budget`, `alert`, `basis` (`identity`/`ageFloor`),
`fallback` (reason or null), `ageListed`, `ageListBytes` (the age rule), `writers` [{pid, start, checkout}],
`checkouts` [{path, entries, bytes}]. -/
def opLakeGc (req : Json) : Except String Reply := do
  let c : Config := ⟨← str req "root", ← nat req "now", ← natD req "ageFloor" defaultAgeFloor,
    ← natD req "budget" budgetBytes, ← optList req "checkouts" checkoutOfJson, ← optList req "procs" procOf,
    ← optList req "outputs" (asStr "outputs")⟩
  let fs ← (← arr req "files").toList.mapM factOf
  let ix := Index.of c
  let l := listFast (okFast c ix) fs
  let ps := pathsOf c l
  let al := listFast (ageRuleOk c) fs
  let ws := c.checkouts.getD []
  pure [("rootOk", .bool (rootOk c.root)), ("paths", .arr (ps.toArray.map .str)), ("listed", toJson ps.length),
    ("listBytes", toJson (bytesOf c l)), ("cacheBytes", toJson (cacheBytes fs)), ("files", toJson fs.length),
    ("ageFloor", toJson c.ageFloor), ("budget", toJson c.budget), ("alert", .bool (alert c fs)),
    ("basis", .str (if ix.basis.isNone then "identity" else "ageFloor")),
    ("fallback", match ix.basis with | some r => .str (fallbackName r) | none => .null),
    ("ageListed", toJson (pathsOf c al).length), ("ageListBytes", toJson (bytesOf c al)),
    ("writers", .arr (ix.writers.toArray.map fun p => Json.mkObj [("pid", toJson p.pid), ("start", toJson p.start),
      ("checkout", match p.cwd.bind (checkoutOf ws) with | some s => .str s | none => .null)])),
    ("checkouts", .arr ((refStats c fs).toArray.map fun (p, n, b) =>
      Json.mkObj [("path", .str p), ("entries", toJson n), ("bytes", toJson b)]))]

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
