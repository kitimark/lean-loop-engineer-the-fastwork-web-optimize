/-!
# Stale services: a running service must not lag the files it was built from

A service reads input files once, when it is started (console-api) or built (the `fwcore` binary). If one of them
changed on `main` after that, the running process still holds the old code: the incident of task `console-stale`
(console-api started 04:12 kept running while `workflow-claim` landed at 04:48, so workflow runs stayed unbound in
the ready lane for hours).

Time is not used: `fw land` builds the merge commit before its checks and moves `main` to it 23-89 s later
(MEASURED, 12 lands), so a commit time predates the moment `main` moved. Instead each running piece of code records
the commit of `main` it was started or built from (its base), and an input is *changed* iff the first-parent range
`base..main` touches it (`git log --first-parent <base>..main -- <path>` is non-empty). The collector (`fw watch`)
only measures that Bool per input; this module is the rule.

What runs is judged, not what is on disk. console-api holds one long-lived `fwcore` child, spawned from the binary
that was on disk at that moment. So console-api is judged on its own inputs against its start commit AND on the
`fwcore` inputs against the build commit of its child; the binary on disk is a third thing, judged as service
`fwcore`. A rebuild on disk changes only the disk; the child is replaced only when console-api restarts (or the child
respawns). Design rule: when the code a process runs cannot be identified, that is an alert (`svc.unknown`), never
silence: `chooseBase` below picks the build commit of a binary or says it cannot.
-/

namespace Fw.Obs

/-- One input group of a service: a path (file or directory prefix) and whether the first-parent range
`base..main` touches it.
-/
structure SvcInput where
  path    : String
  changed : Bool
deriving DecidableEq, Repr

/-- A service: its name, its input groups (each judged against the base commit of the code that runs it), when that
code cannot be identified, the reason, and the fwcore throws its drain caught since it started.
-/
structure Svc where
  name    : String
  inputs  : List SvcInput := []
  /-- Why the code this service runs cannot be identified (`none`: it can). Never silence: the alert `svc.unknown`. -/
  unknown : Option String := none
  /-- The fwcore throws the service's drain caught since it started (`0`: none). Never silence: the alert
  `svc.sweepError`. -/
  sweepErrors : Nat := 0
deriving DecidableEq, Repr

/-- The changed input paths of a service. -/
def Svc.changed (s : Svc) : List String :=
  (s.inputs.filter (fun i => i.changed)).map SvcInput.path

/-- A service is stale when some input changed on `main` since its base commit. -/
def Svc.staleB (s : Svc) : Bool := !s.changed.isEmpty

/-- A path is reported exactly when one of the service's inputs has that path and is changed. -/
theorem Svc.mem_changed (s : Svc) (x : String) :
    x ∈ s.changed ↔ ∃ i ∈ s.inputs, i.path = x ∧ i.changed = true := by
  simp only [Svc.changed, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨i, ⟨hi, hs⟩, rfl⟩; exact ⟨i, hi, rfl, hs⟩
  · rintro ⟨i, hi, rfl, hs⟩; exact ⟨i, ⟨hi, hs⟩, rfl⟩

/-- Stale iff some input is changed. -/
theorem Svc.stale_iff (s : Svc) :
    s.staleB = true ↔ ∃ i ∈ s.inputs, i.changed = true := by
  unfold Svc.staleB
  constructor
  · intro h
    cases hc : s.changed with
    | nil => simp [hc] at h
    | cons x _ =>
      obtain ⟨i, hi, _, hs⟩ := (Svc.mem_changed s x).1 (by rw [hc]; exact List.mem_cons_self)
      exact ⟨i, hi, hs⟩
  · rintro ⟨i, hi, hs⟩
    have hm := (Svc.mem_changed s i.path).2 ⟨i, hi, rfl, hs⟩
    cases hc : s.changed with
    | nil => rw [hc] at hm; simp at hm
    | cons _ _ => rfl

/-- The code of a service cannot be identified. -/
def Svc.unknownB (s : Svc) : Bool := s.unknown.isSome

/-! ### The history model

`main` is a first-parent history, oldest first; each commit is the list of files it touches. A base commit is a
position `b` in it (the number of commits it contains). An input `x` is a git pathspec: a file, or a directory that
covers every file below it (`git log -- lean/Fw` matches `lean/Fw/Obs/Stale.lean`, not `lean/Fw.lean`). The model
is that same predicate (`covers`), so the statements below are about what the collector measures. Every statement
below is about this model: whether the range after the base touches an input. -/

/-- The input `x` covers the file `f`: they are equal, or `f` lies below the directory `x`. -/
def covers (x f : String) : Bool := f == x || (x ++ "/").isPrefixOf f

/-- An input covers itself. -/
theorem covers_self (x : String) : covers x x = true := by simp [covers]

/-- A directory input covers the files below it. -/
theorem covers_child (x r : String) : covers x (x ++ "/" ++ r) = true := by
  simp [covers, String.isPrefixOf]

/-- The input is touched by the range after position `b`: some commit of the range changes a file it covers. -/
def touched (hist : List (List String)) (b : Nat) (x : String) : Bool :=
  (hist.drop b).any (fun c => c.any (covers x))

/-- The input groups `X` judged against base position `b` of the history `H`. -/
def judgeInputs (hist : List (List String)) (b : Nat) (paths : List String) : List SvcInput :=
  paths.map (fun x => ⟨x, touched hist b x⟩)

/-- The service whose inputs are judged against base position `b` of the history `H`. -/
def Svc.judge (hist : List (List String)) (b : Nat) (name : String) (paths : List String) : Svc :=
  { name, inputs := judgeInputs hist b paths }

/-- At the head of `main` the range is empty: nothing is touched. -/
theorem touched_length (hist : List (List String)) (x : String) : touched hist hist.length x = false := by
  simp [touched]

/-- A commit on `main` at or after the base that changes a file an input covers marks it: a landing after the start is
stale.
-/
theorem touched_of_mem (hist : List (List String)) (b j : Nat) (hj : b ≤ j) (c : List String)
    (hc : hist[j]? = some c) (x f : String) (hf : f ∈ c) (hx : covers x f = true) : touched hist b x = true := by
  simp only [touched, List.any_eq_true]
  refine ⟨c, ?_, f, hf, hx⟩
  rw [List.mem_iff_getElem?]
  exact ⟨j - b, by rw [List.getElem?_drop]; simpa [Nat.add_sub_cancel' hj] using hc⟩

/-- Landing more commits never clears a touched path: the range only grows. -/
theorem touched_append (hist ext : List (List String)) (b : Nat) (x : String)
    (h : touched hist b x = true) : touched (hist ++ ext) b x = true := by
  simp only [touched, List.any_eq_true, List.drop_append] at h ⊢
  obtain ⟨c, hc, hx⟩ := h
  exact ⟨c, List.mem_append.2 (.inl hc), hx⟩

/-- A judged service is judged at the head of `main`: restarting (console-api) or rebuilding (`fwcore`) records the
current head as the new base, the range is empty, no input is changed.
-/
theorem Svc.judge_head_not_stale (hist : List (List String)) (name : String) (paths : List String) :
    (Svc.judge hist hist.length name paths).staleB = false := by
  cases hb : (Svc.judge hist hist.length name paths).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Svc.judge, judgeInputs, List.mem_map] at hi
    obtain ⟨x, _, rfl⟩ := hi
    simp [touched] at hc

/-- A judged service is stale once a later commit touches one of its inputs, whatever else lands afterwards. -/
theorem Svc.judge_stale_append (hist ext : List (List String)) (b : Nat) (name : String) (paths : List String)
    (h : (Svc.judge hist b name paths).staleB = true) : (Svc.judge (hist ++ ext) b name paths).staleB = true := by
  obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 h
  simp only [Svc.judge, judgeInputs, List.mem_map] at hi
  obtain ⟨x, hx, rfl⟩ := hi
  exact (Svc.stale_iff _).2 ⟨⟨x, touched (hist ++ ext) b x⟩, by
    simp only [Svc.judge, judgeInputs, List.mem_map]; exact ⟨x, hx, rfl⟩,
    touched_append hist ext b x hc⟩

/-! ### The stack: what console-api runs, what is on disk

Three base positions in the history `H`:

* `apiBase`: the commit console-api was started from (it read `apps/console-api`, `packages/contracts` then);
* `coreBase`: the build commit of the `fwcore` child console-api holds (spawned from the disk binary at that moment);
* `diskBase`: the build commit of the `fwcore` binary on disk now.

console-api is judged on its own inputs against `apiBase` and on the `fwcore` inputs against `coreBase`; the disk
binary is the service `fwcore`, judged against `diskBase`. -/

/-- The three base positions. -/
structure Stack where
  apiBase  : Nat
  coreBase : Nat
  diskBase : Nat

/-- console-api: its own inputs `A` against its start commit, the `fwcore` inputs `K` against the commit its child was
built from.
-/
def Stack.api (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) : Svc :=
  { name := "console-api", inputs := judgeInputs hist t.apiBase apiOwn ++ judgeInputs hist t.coreBase coreIn }

/-- The `fwcore` binary on disk: the `fwcore` inputs `K` against its build commit. -/
def Stack.disk (hist : List (List String)) (coreIn : List String) (t : Stack) : Svc :=
  Svc.judge hist t.diskBase "fwcore" coreIn

/-- Restarting console-api: it is started from the head of `main` and spawns its `fwcore` child from the binary on
disk, so the child is as old as the disk.
-/
def Stack.restartApi (hist : List (List String)) (t : Stack) : Stack :=
  { t with apiBase := hist.length, coreBase := t.diskBase }

/-- A child respawn (crash) takes the binary on disk and leaves console-api's own base. -/
def Stack.respawn (t : Stack) : Stack := { t with coreBase := t.diskBase }

/-- `lake build` at the head of `main` replaces the file on disk only; the child holds the old code. -/
def Stack.rebuild (hist : List (List String)) (t : Stack) : Stack := { t with diskBase := hist.length }

/-- A rebuild without a console-api restart leaves console-api's core inputs stale: if a commit at or after the
child's build commit touched a `fwcore` input, console-api is still stale after the rebuild. (The old model said a
rebuild cleared everything: the false negative of round 3.)
-/
theorem rebuild_without_restart_api_stale (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack)
    (j : Nat) (hj : t.coreBase ≤ j) (c : List String) (hc : hist[j]? = some c) (x f : String)
    (hf : f ∈ c) (hx : covers x f = true) (hk : x ∈ coreIn) :
    ((t.rebuild hist).api hist apiOwn coreIn).staleB = true := by
  refine (Svc.stale_iff _).2 ⟨⟨x, touched hist t.coreBase x⟩, ?_, touched_of_mem hist t.coreBase j hj c hc x f hf hx⟩
  simp only [Stack.api, Stack.rebuild, List.mem_append, judgeInputs, List.mem_map]
  exact .inr ⟨x, hk, rfl⟩

/-- The rebuild itself is fine: the binary on disk is not stale afterwards, and console-api's verdict is unchanged. -/
theorem rebuild_clears_disk (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) :
    ((t.rebuild hist).disk hist coreIn).staleB = false ∧
      (t.rebuild hist).api hist apiOwn coreIn = t.api hist apiOwn coreIn :=
  ⟨Svc.judge_head_not_stale hist "fwcore" coreIn, rfl⟩

/-- Restarting console-api after a rebuild clears everything: both input groups are judged at the head. -/
theorem restartApi_after_rebuild_clears (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack) :
    (((t.rebuild hist).restartApi hist).api hist apiOwn coreIn).staleB = false ∧
      (((t.rebuild hist).restartApi hist).disk hist coreIn).staleB = false := by
  refine ⟨?_, Svc.judge_head_not_stale hist "fwcore" coreIn⟩
  cases hb : (((t.rebuild hist).restartApi hist).api hist apiOwn coreIn).staleB with
  | false => rfl
  | true =>
    obtain ⟨i, hi, hc⟩ := (Svc.stale_iff _).1 hb
    simp only [Stack.api, Stack.rebuild, Stack.restartApi, List.mem_append, judgeInputs, List.mem_map] at hi
    rcases hi with ⟨x, _, rfl⟩ | ⟨x, _, rfl⟩ <;> simp [touched] at hc

/-- Restarting console-api without a rebuild leaves the core inputs stale: the new child comes from the stale binary on
disk, while console-api's own inputs are fresh.
-/
theorem restartApi_without_rebuild_stale (hist : List (List String)) (apiOwn coreIn : List String) (t : Stack)
    (j : Nat) (hj : t.diskBase ≤ j) (c : List String) (hc : hist[j]? = some c) (x f : String)
    (hf : f ∈ c) (hx : covers x f = true) (hk : x ∈ coreIn) :
    ((t.restartApi hist).api hist apiOwn coreIn).staleB = true ∧
      ((t.restartApi hist).disk hist coreIn).staleB = true ∧
      (Svc.judge hist (t.restartApi hist).apiBase "console-api" apiOwn).staleB = false := by
  have ht := touched_of_mem hist t.diskBase j hj c hc x f hf hx
  refine ⟨(Svc.stale_iff _).2 ⟨⟨x, touched hist t.diskBase x⟩, ?_, ht⟩,
    (Svc.stale_iff _).2 ⟨⟨x, touched hist t.diskBase x⟩, ?_, ht⟩, Svc.judge_head_not_stale hist "console-api" apiOwn⟩
  · simp only [Stack.api, Stack.restartApi, List.mem_append, judgeInputs, List.mem_map]
    exact .inr ⟨x, hk, rfl⟩
  · simp only [Stack.disk, Stack.restartApi, Svc.judge, judgeInputs, List.mem_map]
    exact ⟨x, hk, rfl⟩

/-- A child respawn picks up the disk: it clears console-api's core inputs exactly when the disk is current.

Here `k(Θ')` is the core base of the stack `Θ'`.
-/
theorem respawn_coreBase (t : Stack) : t.respawn.coreBase = t.diskBase := rfl

/-! ### Which commit was a binary built from

No time is compared and nothing is inferred from file times or the reflog: a binary's commit is known only from the
build record that `scripts/fwcore-build.sh` writes after a successful build on a clean tree that is not mid-merge:
the pair `(s, h)` of the commit `s` read BEFORE the build and the sha256 `h` of the binary it produced. The record is
tied to the binary by content, so a later build that replaces the binary (even one that restores a cached file with an
old mtime) makes the record not match, and the binary is unknown. A record is accepted only when the sha256 `h_b` of
the binary now on disk equals the recorded one. Otherwise (no record, mismatch, a dirty or mid-merge build writes none)
the commit is unknown, which is an alert, never a guess. -/

/-- The build commit of a binary: a commit, or unknown with the reason. -/
inductive Base where
  | at (sha : String)
  | unknown (why : String)
deriving DecidableEq, Repr

/-- The base commit of a binary whose sha256 is `h_b`, given its build record `(s, h)` (if any). -/
def chooseBase (binHash : String) (rec : Option (String × String)) : Base :=
  match rec with
  | some (s, h) =>
    if h = binHash then .at s else .unknown "the build record does not match the binary (rebuilt without scripts/fwcore-build.sh)"
  | none => .unknown "no build record: build with scripts/fwcore-build.sh"

/-- An accepted record is the base: the recorded commit, unchanged. -/
theorem chooseBase_accepted (binHash s : String) : chooseBase binHash (some (s, binHash)) = .at s := by
  simp [chooseBase]

/-- The base is a commit exactly when the record names it and carries the binary's own hash (identity: nothing is
inferred, nothing is invented).
-/
theorem chooseBase_at_iff (binHash : String) (rec : Option (String × String)) (s : String) :
    chooseBase binHash rec = .at s ↔ rec = some (s, binHash) := by
  constructor
  · intro h
    cases rec with
    | none => simp [chooseBase] at h
    | some r =>
      obtain ⟨s', h'⟩ := r
      by_cases hh : h' = binHash
      · subst hh; simp [chooseBase] at h; subst h; rfl
      · simp [chooseBase, hh] at h
  · rintro rfl; exact chooseBase_accepted binHash s

/-- A record whose hash is not the binary's is never accepted: the base is unknown. -/
theorem chooseBase_mismatch (binHash s h : String) (hne : h ≠ binHash) :
    ∃ why, chooseBase binHash (some (s, h)) = .unknown why :=
  ⟨"the build record does not match the binary (rebuilt without scripts/fwcore-build.sh)", by simp [chooseBase, hne]⟩

/-- No record: unknown. -/
theorem chooseBase_none (binHash : String) : ∃ why, chooseBase binHash none = .unknown why :=
  ⟨_, rfl⟩

/-- The reason of an unidentified base (`none` when it is a commit). -/
def Base.unknownOf : Base → Option String
  | .at _ => none
  | .unknown w => some w

/-- The service whose code is the binary of base `b`: it carries no inputs of its own here; an unidentified base is
its `unknown` reason (`svc.unknown`, `unknown_service_alerts` in `Fw.Obs.Health` fires for it).
-/
def Base.svc (name : String) (b : Base) : Svc := { name, unknown := b.unknownOf }

/-- Unknown always alerts: whenever the record does not name the binary (no record, mismatch), the service built from
it is `unknown`, which `unknown_service_alerts` turns into a `svc.unknown` alert.
-/
theorem chooseBase_unknown_alerts (binHash : String) (rec : Option (String × String)) (name : String)
    (h : ∀ s, rec ≠ some (s, binHash)) : (Base.svc name (chooseBase binHash rec)).unknownB = true := by
  cases hb : chooseBase binHash rec with
  | «at» s => exact absurd ((chooseBase_at_iff binHash rec s).1 hb) (h s)
  | unknown w => rfl

/-! ## The built tree (task local-mem-budget)

`scripts/fwcore-build.sh` used to name the commit `HEAD` it built from and wrote nothing on a tree that was mid-merge
(`fw land` builds the merged tree before the commit that lands it exists), so the watcher raised `svc.unknown` for
each such build. The record now names the built TREE (the id `git write-tree` gives for the index, read before the
build). A tree is identity: the commit that lands the merge has the same tree, so the base commit is found by
looking the tree up among the commits of `main` (`chooseBaseTree`). The merge, rebase or cherry-pick state is no input:
only the tree and whether the working files equal it.
-/

/-- What the build script observes: the tree id of the index before and after the build, and whether the working
files (tracked, and untracked under `lean/`) equal that index before and after. -/
structure BuildFacts where
  before      : Option String
  after       : Option String
  cleanBefore : Bool
  cleanAfter  : Bool
deriving DecidableEq, Repr

/-- The tree to record: the one built, when the files equalled it before and after and it did not change. -/
def recordTree (f : BuildFacts) : Option String :=
  match f.before, f.after with
  | some a, some b => if f.cleanBefore && f.cleanAfter && a = b then some a else none
  | _, _ => none

/-- A tree is recorded exactly when both reads gave that tree and the files equalled it at both ends. -/
theorem recordTree_some_iff (f : BuildFacts) (t : String) :
    recordTree f = some t ↔ f.before = some t ∧ f.after = some t ∧ f.cleanBefore = true ∧ f.cleanAfter = true := by
  unfold recordTree
  rcases hb : f.before with _ | a <;> rcases ha : f.after with _ | b <;> simp
  by_cases h : f.cleanBefore = true ∧ f.cleanAfter = true ∧ a = b
  · simp [h.1, h.2.1, h.2.2]
  · have : ¬(f.cleanBefore = true ∧ f.cleanAfter = true ∧ a = b ∧ a = t) := fun hh => h ⟨hh.1, hh.2.1, hh.2.2.1⟩
    by_cases h1 : f.cleanBefore = true <;> by_cases h2 : f.cleanAfter = true <;> by_cases h3 : a = b <;>
      (simp_all <;> (intro h4 h5; exact h3 (h4.trans h5.symm)))

/-- A dirty tree is never recorded (no commit can have the tree that was built). -/
theorem recordTree_dirty (f : BuildFacts) (h : f.cleanBefore = false ∨ f.cleanAfter = false) : recordTree f = none := by
  unfold recordTree
  rcases f.before with _ | a <;> rcases f.after with _ | b <;> simp
  rcases h with h | h <;> simp [h]

/-- A tree that changed during the build (HEAD or the index moved) is never recorded. -/
theorem recordTree_moved (f : BuildFacts) (a b : String) (hb : f.before = some a) (ha : f.after = some b) (hne : a ≠ b) :
    recordTree f = none := by
  unfold recordTree; simp [hb, ha, hne]

/-- A merge, rebase or cherry-pick in progress is no input: a clean merged tree is recorded like a committed one. -/
theorem recordTree_merged (t : String) :
    recordTree ⟨some t, some t, true, true⟩ = some t := by
  simp [recordTree]

/-- Commits of `main`, newest first, each with its tree id. -/
abbrev CommitLog := List (String × String)

/-- The base of a binary built from tree `t` (recorded with hash `h`), given the commits of `main`: the newest commit
with that tree, when the record is the binary's own. -/
def chooseBaseTree (binHash t h : String) (log : CommitLog) : Base :=
  if h = binHash then
    match log.find? (fun c => c.2 = t) with
    | some (c, _) => .at c
    | none => .unknown "the built tree is on no commit of main (a land in progress, or the build was never landed)"
  else .unknown "the build record does not match the binary (rebuilt without scripts/fwcore-build.sh)"

/-- A base commit comes only from the binary's own record and carries the recorded tree. -/
theorem chooseBaseTree_at (binHash t h : String) (log : CommitLog) (c : String)
    (hb : chooseBaseTree binHash t h log = .at c) : h = binHash ∧ (c, t) ∈ log := by
  unfold chooseBaseTree at hb
  by_cases hh : h = binHash
  · simp only [hh, ite_true] at hb
    rcases hf : log.find? (fun c => c.2 = t) with _ | ⟨c', t'⟩
    · simp [hf] at hb
    · simp [hf] at hb
      subst hb
      have := List.mem_of_find?_eq_some hf
      have h2 := List.find?_some hf
      simp at h2; subst h2
      exact ⟨hh, this⟩
  · simp [hh] at hb

/-- A commit of `main` has the tree when the lookup finds one. -/
theorem find_tree_some (log : CommitLog) (t c : String) (hc : (c, t) ∈ log) :
    ∃ c', log.find? (fun x => decide (x.2 = t)) = some (c', t) := by
  rcases hf : log.find? (fun x => decide (x.2 = t)) with _ | ⟨c', t'⟩
  · have := List.find?_eq_none.1 hf (c, t) hc
    simp at this
  · have h2 := List.find?_some hf
    simp at h2; subst h2
    exact ⟨c', hf⟩

/-- The land: the commit that lands the merge has the built tree, so the binary's base is a commit, never
`svc.unknown`. -/
theorem chooseBaseTree_landed (binHash t : String) (log : CommitLog) (c : String) (hc : (c, t) ∈ log) :
    ∃ c', chooseBaseTree binHash t binHash log = .at c' := by
  obtain ⟨c', hf⟩ := find_tree_some log t c hc
  exact ⟨c', by simp [chooseBaseTree, hf]⟩

/-- A tree no commit of `main` has is unknown (never a guess): it alerts. -/
theorem chooseBaseTree_unlanded (binHash t : String) (log : CommitLog) (h : ∀ c, (c, t) ∉ log) :
    (Base.svc "fwcore" (chooseBaseTree binHash t binHash log)).unknownB = true := by
  rcases hf : log.find? (fun x => decide (x.2 = t)) with _ | ⟨c', t'⟩
  · simp [chooseBaseTree, hf, Base.svc, Base.unknownOf, Svc.unknownB]
  · have hm := List.mem_of_find?_eq_some hf
    have h2 := List.find?_some hf
    simp at h2; subst h2
    exact absurd hm (h c')

#guard recordTree ⟨some "T", some "T", true, true⟩ == some "T"
#guard recordTree ⟨some "T", some "T", false, true⟩ == none
#guard recordTree ⟨some "T", some "T", true, false⟩ == none
#guard recordTree ⟨some "T", some "U", true, true⟩ == none
#guard recordTree ⟨none, some "T", true, true⟩ == none
#guard recordTree ⟨some "T", none, true, true⟩ == none
#guard chooseBaseTree "H" "T" "H" [("c2", "T2"), ("c1", "T")] == .at "c1"
#guard chooseBaseTree "H" "T" "H" [("c3", "T"), ("c1", "T")] == .at "c3"
#guard (chooseBaseTree "H" "T" "H" [("c2", "T2")]).unknownOf.isSome
#guard (chooseBaseTree "H2" "T" "H" [("c1", "T")]).unknownOf.isSome

-- the table of `apps/console-api/test/build-base.test.ts`
#guard chooseBase "H1" (some ("c1", "H1")) == .at "c1"
#guard (chooseBase "H2" (some ("c1", "H1"))).unknownOf.isSome
#guard (chooseBase "H1" none).unknownOf.isSome
#guard covers "lean/Fw" "lean/Fw/Obs/Stale.lean"
#guard covers "lean/Fw" "lean/Fw"
#guard !covers "lean/Fw" "lean/Fw.lean"
#guard !covers "lean/Fw" "lean/Fwx/a"

end Fw.Obs
