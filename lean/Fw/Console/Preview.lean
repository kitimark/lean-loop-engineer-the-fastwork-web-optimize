import Fw.Console
import Fw.Ops.Identity
/-!
# Task preview: which commit, who may start it, how many, which ports, when it ends

The console can start a local web server per `port-*` / `fix-*` task: the task's version of the site next
to the original snapshot, for manual testing (task `task-preview`, `research/notes/2026/10-18-task-preview.md`).
Everything that is a *decision* is here; the TypeScript glue only does git, process and http I/O.

* **Head and target commit** (`headOf`). The glue gathers repository facts for each head candidate of the task
  (handoff branch line, `ci/<task>`, `origin/ci/<task>`, a branch named like the task, a merge's second
  parent) and for each sub-task of an umbrella; Lean picks the head (`pickHead`) and its target (`targetOf`,
  `umbrella`): `main` when the head is landed; else the integration ref whose tip is the head, else the newest
  integration ref containing it; a head with no code of its own that nothing holds shows the newest integration
  ref; else the head itself; no head and no sub-task head, no preview. The checked table of the 25 `port-` /
  `fix-` tasks is `Fw.Console.PreviewTable`.
* **Admission** (`admit`). Only the actor `user` may start a preview (`mayStart`), and a request is `user` only
  when it shows the owner proof (`Proof.actor`: owner cookie and same-origin Origin, no console secret). Then, in this order: one live preview per
  task, at most `K` live previews, a disk floor, a target, and two free ports of the localhost range
  [lo, lo + portN) (production: `portLo` = 47100; one for the rewrite, one for the original).
* **Expiry** (`tick`). A preview lives `ttl` milliseconds from its start; the console ticks, and every
  preview past its deadline is removed from the table and its process group is stopped.
* **Stop** (`stop`, `reap`). The kill list is always a part of the console's own table (the previews it
  started and recorded), never a name or a pattern.

`Reach` is every table the three transitions can produce from the empty one; `reach_inv` proves the
invariants for all of them: at most `K` live previews (`live_le_K`) and pairwise distinct ports
(`ports_distinct`).
-/
namespace Fw.Console.Preview
open Fw.Console

/-! ## Limits -/

/-- Most live previews (a build is about 60 MB of disk and a few seconds of CPU). -/
def K : Nat := 2

/-- A preview's lifetime in milliseconds (60 minutes). -/
def ttl : Nat := 3600000

/-- Disk floor in MB: a start is refused when less is free. -/
def diskFloor : Nat := 2048

/-- The production first port of the localhost range, and the default base of every decision below (a test
passes another base; nothing else re-types this number). -/
def portLo : Nat := 47100

/-- The number of ports in the range. -/
def portN : Nat := 40

/-- How far an arm's private backend port lies above its public port (`Arm.backendOf` in `PreviewArm`). At least the
width of the range, so a backend port is never a public port. -/
def backendOff : Nat := 1000

/-- The highest port number plus one: ports are below it. -/
def portSpace : Nat := 65536

/-! ## Target commit -/

/-- An integration ref the glue found: its name, its tip, and whether it contains a given commit
(`git merge-base --is-ancestor commit tip`). -/
structure Cand where
  ref : String
  sha : String
  contains : Bool
deriving Repr, DecidableEq

/-- One commit of main's first-parent line that contains the head (oldest first), and whether its second parent
contains the head (`git merge-base --is-ancestor head parent2`; false for a commit with one parent). -/
structure PathC where
  sha : String
  p2Has : Bool
deriving Repr, DecidableEq

/-- What the glue knows (through git) about one head candidate of a task: where the candidate came from
(`handoff` branch line, `ci/<task>`, `origin/ci/<task>`, a branch named like the task, a merge's second
parent), its commit, whether main contains it, whether its own commits touch only documentation, and which
integration refs contain it (newest first); whether the head is itself on main's first-parent line (`fpLine`), the
commits of that line that contain it (`path`, oldest first), for a merge's second parent whether it contains the task's own
work (`ownWork`: it descends from `origin/ci/<task>` or the handoff branch head and is not on main's first-parent line; the
glue sets it true for every other source), and whether another candidate holds code this one lacks (`behind`). -/
structure Fact where
  src : String
  sha : String
  onMain : Bool
  noCode : Bool
  cands : List Cand
  /-- The head is a commit of main's first-parent line. -/
  fpLine : Bool := false
  /-- The commits of main's first-parent line that contain the head, oldest first (it may stop at its first `p2Has`). -/
  path : List PathC := []
  /-- The candidate contains the task's own work (checked for `merge` candidates). -/
  ownWork : Bool := true
  /-- Another candidate of the task is a descendant of this one with code beyond documentation. -/
  behind : Bool := false
deriving Repr, DecidableEq

/-- What a preview shows. -/
inductive Target where
  | main (sha : String)
  | integration (ref sha : String)
  | own (sha : String)
  | none
deriving Repr, DecidableEq

/-- The first candidate that contains the commit (candidates come newest first). -/
def firstContaining (cs : List Cand) : Option Cand := cs.find? (·.contains)

/-- A commit is held when main or an integration ref contains it. -/
def Fact.held (f : Fact) : Bool := f.onMain || f.cands.any (·.contains)

/-- A candidate may be the head unless it is a merge's second parent that does not contain the task's own work
(a "merge main into the branch" commit has a second parent on main's first-parent line: that is main's work, not the
task's), or another candidate holds code it lacks (an older commit that the gate's commit has since replaced). -/
def Fact.admissible (f : Fact) : Bool := (f.src != "merge" || f.ownWork) && !f.behind

/-- The rank of a candidate source: the worktree branch the handoff names, a merge's second parent, a branch named
like the task, the newest commit touching the handoff, then `ci/<task>`, then `origin/ci/<task>`; an unknown source last. -/
def srcRank (src : String) : Nat :=
  match src with
  | "handoff" => 0 | "merge" => 1 | "named" => 2 | "handoffCommit" => 3 | "ci" => 4 | "originCi" => 5 | _ => 6

/-- Insert a candidate before the first one of equal or higher rank (structural, so the kernel can evaluate it). -/
def insertByRank (f : Fact) : List Fact → List Fact
  | [] => [f]
  | g :: t => if srcRank f.src ≤ srcRank g.src then f :: g :: t else g :: insertByRank f t

/-- Inserting only adds the candidate. -/
theorem insertByRank_perm (f : Fact) (l : List Fact) : (insertByRank f l).Perm (f :: l) := by
  induction l with
  | nil => simp [insertByRank]
  | cons g t ih =>
    unfold insertByRank
    split
    · exact List.Perm.refl _
    · exact ((ih.cons g).trans (List.Perm.swap f g t))

/-- The candidates in head priority order (a stable sort by `srcRank`; the order the glue lists them in does not matter). -/
def ordered (fs : List Fact) : List Fact := fs.foldr insertByRank []

/-- **Sorting loses and invents no candidate.** The ordered list is a permutation of the glue's list, so the
glue's listing order carries no decision. -/
theorem ordered_perm (fs : List Fact) : (ordered fs).Perm fs := by
  induction fs with
  | nil => simp [ordered]
  | cons f t ih =>
    have : (ordered (f :: t)) = insertByRank f (ordered t) := rfl
    rw [this]
    exact (insertByRank_perm f _).trans (ih.cons f)

/-- The candidates that may be the head, in head priority order. -/
def eligible (fs : List Fact) : List Fact := (ordered fs).filter Fact.admissible

/-- The task head among the candidates: the first (in `eligible`) that main or an integration ref holds (a
documentation-only handoff commit never hides the commit the gate ran; the worktree or merge head comes before
`origin/ci`), else the first candidate; no candidate, no head. A head that main holds then previews its land commit
(`targetOf`). -/
def pickHead (fs : List Fact) : Option Fact :=
  match (eligible fs).find? Fact.held with
  | some f => some f
  | none => (eligible fs).head?

/-- The integration ref whose tip is exactly the commit, among those that contain it. -/
def exactTip (f : Fact) : Option Cand := f.cands.find? fun c => c.contains && c.sha == f.sha

/-- The commit a landed head previews (its land commit on main). A head on main's first-parent line is its own land
commit; otherwise it is the first commit (oldest) of main's first-parent line containing the head whose second parent
contains the head; main's tip when the glue found none. -/
def landOf (m : String) (f : Fact) : String :=
  if f.fpLine then f.sha else
  match f.path.find? (·.p2Has) with
  | some p => p.sha
  | none => m

/-- **A head on main's first-parent line is its own land commit.** -/
theorem landOf_fpLine (m : String) (f : Fact) (h : f.fpLine = true) : landOf m f = f.sha := by
  simp [landOf, h]

/-- **Otherwise the land commit is the first path commit whose second parent contains the head.** -/
theorem landOf_path (m : String) (f : Fact) (p : PathC) (h : f.fpLine = false)
    (hp : f.path.find? (·.p2Has) = some p) : landOf m f = p.sha := by
  simp [landOf, h, hp]

/-- **The land commit is the head itself, main's tip, or a path commit whose second parent holds the head.** -/
theorem landOf_cases (m : String) (f : Fact) :
    landOf m f = f.sha ∨ landOf m f = m ∨ ∃ p ∈ f.path, p.p2Has = true ∧ p.sha = landOf m f := by
  unfold landOf
  by_cases h : f.fpLine = true
  · simp [h]
  · simp only [h, if_false]
    cases hx : f.path.find? (·.p2Has) with
    | none => simp
    | some p => exact Or.inr (Or.inr ⟨p, List.mem_of_find?_eq_some hx, by simpa using List.find?_some hx, rfl⟩)

/-- The target of one head. Order: main (landed); the integration ref whose tip is the head (the exact state
the gate judged); the newest integration ref containing it; for a head with no code of its own that nothing
holds, the newest integration ref (the newest state of the parts it examined); else the head itself. -/
def targetOf (mainSha : String) (f : Fact) : Target :=
  if f.onMain then .main (landOf mainSha f)
  else match exactTip f with
    | some c => .integration c.ref c.sha
    | none => match firstContaining f.cands with
      | some c => .integration c.ref c.sha
      | none => match f.noCode, f.cands with
        | true, c :: _ => .integration c.ref c.sha
        | _, _ => .own f.sha

/-- The target of an umbrella task (no commit of its own; sub-tasks `<task>-*` with heads, given as facts):
`main` when every sub-task head is on main; else the first integration ref (newest first, taken from the
first sub-task's list) that contains every sub-task head; else none. No sub-task with a head, no target.

A sub-task's containment in `c` is the `contains` flag of its entry with the same ref name. -/
def umbrella (mainSha : String) (ks : List Fact) : Target :=
  match ks with
  | [] => .none
  | k0 :: _ =>
    if ks.all (·.onMain) then .main mainSha
    else match k0.cands.find? fun c => ks.all fun k => k.cands.any fun d => d.ref == c.ref && d.contains with
      | some c => .integration c.ref c.sha
      | none => .none

/-- The decision of the task head: which candidate is the head, and what its preview shows. With no
candidate the sub-tasks decide: each sub-task's candidate list `kss` gives its head by `pickHead`
(`umbrella`). -/
def headOf (mainSha : String) (fs : List Fact) (kss : List (List Fact)) : Option Fact × Target :=
  match pickHead fs with
  | some f => (some f, targetOf mainSha f)
  | none => (none, umbrella mainSha (kss.filterMap pickHead))

/-- **No work, no preview.** -/
theorem headOf_noWork (m : String) : headOf m [] [] = (none, .none) := by
  simp [headOf, pickHead, eligible, ordered, umbrella]

/-- **Landed means main.** A head main contains gives `main`. -/
theorem targetOf_landed (m : String) (f : Fact) (h : f.onMain = true) : targetOf m f = .main (landOf m f) := by
  simp [targetOf, h]

/-- **A held head is never shown as its own.** If main or an integration ref holds the head, the target is
`main` or an integration ref, not `own`. -/
theorem targetOf_held_not_own (m : String) (f : Fact) (h : f.held = true) (s : String) :
    targetOf m f ≠ .own s := by
  unfold Fact.held at h
  unfold targetOf exactTip firstContaining
  by_cases hm : f.onMain = true
  · simp [hm]
  · have hc : f.cands.any (·.contains) = true := by simpa [hm] using h
    have hs : (f.cands.find? (·.contains)).isSome = true := by
      rw [List.find?_isSome]; simpa using hc
    simp only [hm, Bool.false_eq_true, ite_false]
    cases he : f.cands.find? (fun c => c.contains && c.sha == f.sha) with
    | some c => simp
    | none =>
      cases hf : f.cands.find? (·.contains) with
      | some c => simp
      | none => simp [hf] at hs

/-- **Own head only when nothing holds it.** A target of `own` means main does not contain the head, no
integration ref does, and the head has code (or there is no integration ref at all). -/
theorem targetOf_own (m s : String) (f : Fact) (h : targetOf m f = .own s) :
    f.onMain = false ∧ (∀ c ∈ f.cands, c.contains = false) ∧ (f.noCode = false ∨ f.cands = []) := by
  unfold targetOf exactTip firstContaining at h
  by_cases hm : f.onMain = true
  · simp [hm] at h
  have hm' : f.onMain = false := by simpa using hm
  simp only [hm', Bool.false_eq_true, ite_false] at h
  cases he : f.cands.find? (fun c => c.contains && c.sha == f.sha) with
  | some c => simp [he] at h
  | none =>
    cases hf : f.cands.find? (·.contains) with
    | some c => simp [he, hf] at h
    | none =>
      refine ⟨hm', fun c hc => ?_, ?_⟩
      · have := List.find?_eq_none.mp hf c hc
        simpa using this
      · simp only [he, hf] at h
        cases hn : f.noCode with
        | false => exact Or.inl rfl
        | true =>
          right
          cases hcs : f.cands with
          | nil => rfl
          | cons c t => simp [hn, hcs] at h

/-- **The pick is held when anything admissible is.** If some admissible candidate is held, the picked head is held
(it is the first held one). -/
theorem pickHead_held (fs : List Fact) (h : ∃ f ∈ fs, f.admissible = true ∧ f.held = true) :
    ∃ g, pickHead fs = some g ∧ g.held = true := by
  obtain ⟨f, hf, ha, hh⟩ := h
  have hmem : f ∈ eligible fs := List.mem_filter.mpr ⟨(ordered_perm fs).mem_iff.mpr hf, ha⟩
  unfold pickHead
  cases hx : (eligible fs).find? Fact.held with
  | none => exact absurd (List.find?_eq_none.mp hx f hmem) (by simpa using hh)
  | some g => exact ⟨g, rfl, List.find?_some hx⟩

/-- **The first eligible candidate wins when held.** If the first eligible candidate (rank order, whatever the
glue's listing order) is held, it is the head. -/
theorem pickHead_first_held (fs : List Fact) (g : Fact) (t : List Fact) (ho : eligible fs = g :: t)
    (hg : g.held = true) : pickHead fs = some g := by
  simp [pickHead, ho, List.find?_cons, hg]

/-- **Every picked head is admissible.** Whatever the facts, the head is never a candidate the rule excludes. -/
theorem pickHead_admissible (fs : List Fact) (g : Fact) (h : pickHead fs = some g) : g.admissible = true := by
  unfold pickHead at h
  cases hx : (eligible fs).find? Fact.held with
  | some f =>
    simp only [hx, Option.some.injEq] at h
    subst h
    exact (List.mem_filter.mp (List.mem_of_find?_eq_some hx)).2
  | none =>
    simp only [hx] at h
    exact (List.mem_filter.mp (List.mem_of_mem_head? h)).2

/-- **A merge that does not contain the task's own work is never the head.** In particular a "merge main into the
branch" commit (second parent on main's first-parent line) is never picked, in any rank order. -/
theorem pickHead_inadmissible_merge (fs : List Fact) (f : Fact) (hs : f.src = "merge") (hw : f.ownWork = false) :
    pickHead fs ≠ some f := by
  intro h
  have := pickHead_admissible fs f h
  simp [Fact.admissible, hs, hw] at this

/-- **A picked head is never behind another candidate.** The head never lacks code that another candidate holds. -/
theorem pickHead_not_behind (fs : List Fact) (g : Fact) (h : pickHead fs = some g) : g.behind = false := by
  have := pickHead_admissible fs g h
  simp [Fact.admissible] at this
  exact this.2

/-- **Filter invariance** (what remains of the former `target_deterministic`). For a held head, dropping the
integration refs that do not contain it gives the same target; it is the only claim, the target is not
asserted to depend on anything else. -/
theorem targetOf_filter_invariant (m : String) (f : Fact) (h : f.held = true) :
    targetOf m f = targetOf m { f with cands := f.cands.filter (·.contains) } := by
  have key : ∀ (cs : List Cand) (p : Cand → Bool), (∀ c, p c = true → c.contains = true) →
      (cs.filter (·.contains)).find? p = cs.find? p := by
    intro cs p hp
    induction cs with
    | nil => rfl
    | cons c t ih =>
      by_cases hc : c.contains = true
      · simp [hc, List.find?_cons, ih]
      · have : p c = false := by
          cases hpc : p c
          · rfl
          · exact absurd (hp c hpc) hc
        simp [hc, this, ih]
  have hex : (f.cands.filter (·.contains)).find? (fun c => c.contains && c.sha == f.sha)
      = f.cands.find? (fun c => c.contains && c.sha == f.sha) :=
    key f.cands _ (fun c hc => by simpa using (Bool.and_eq_true_iff.mp hc).1)
  have hfc : (f.cands.filter (·.contains)).find? (·.contains) = f.cands.find? (·.contains) :=
    key f.cands _ (fun c hc => hc)
  by_cases hm : f.onMain = true
  · simp [targetOf, hm, landOf]
  · have hc : f.cands.any (·.contains) = true := by unfold Fact.held at h; simpa [hm] using h
    have hs : (f.cands.find? (·.contains)).isSome = true := by
      rw [List.find?_isSome]; simpa using hc
    unfold targetOf exactTip firstContaining
    simp only [hm, Bool.false_eq_true, ite_false, hex, hfc]
    cases f.cands.find? (fun c => c.contains && c.sha == f.sha) with
    | some c => rfl
    | none =>
      cases hf : f.cands.find? (·.contains) with
      | none => simp [hf] at hs
      | some c => simp

/-! ## The table, admission, ports -/

/-- A live preview (the console's own record of a process group it started).

With the rewrite port `rp`, the original's port `op`, the start time `t₀` (ms). -/
structure Pv where
  id : String
  task : String
  rp : Nat
  op : Nat
  started : Nat
deriving Repr, DecidableEq

/-- The deadline of a preview. -/
def Pv.deadline (p : Pv) : Nat := p.started + ttl

/-- The ports the table holds. -/
def ports (s : List Pv) : List Nat := s.flatMap fun p => [p.rp, p.op]

/-- The free ports of the range, ascending.

With the base `b`. -/
def freePorts (lo : Nat) (s : List Pv) : List Nat := (List.range' lo portN).filter fun q => q ∉ ports s

/-- Why a start is refused. -/
inductive Refusal where
  | notOwner | taskBusy | tooMany | lowDisk | noPorts | noTarget
deriving Repr, DecidableEq

/-- The wire name of a refusal. -/
def Refusal.name : Refusal → String
  | .notOwner => "notOwner" | .taskBusy => "taskBusy" | .tooMany => "tooMany"
  | .lowDisk => "lowDisk" | .noPorts => "noPorts" | .noTarget => "noTarget"

/-- Who may start or stop a preview: the user only. -/
def mayStart (a : Actor) : Bool := a == .user

/-- Every agent actor is refused. -/
theorem mayStart_not_agent (a : Actor) (h : Fw.Ops.Identity.isAgentActor a = true) : mayStart a = false := by
  cases a <;> simp_all [mayStart, Fw.Ops.Identity.isAgentActor]

/-- What a request to a preview route shows: the three facts the route can check, and nothing else. `secret`: the
console secret header matched (the runner's own tools). `cookie`: the owner cookie matched the session that the
one-time owner link opened. `origin`: the Origin header is present and is an origin of this console. -/
structure Proof where
  secret : Bool
  cookie : Bool
  origin : Bool
deriving Repr, DecidableEq

/-- The actor a request is stamped as. -/
def Proof.actor (p : Proof) : Actor :=
  if p.secret then .lead else if p.cookie && p.origin then .user else .script

/-- **Only the full owner proof is `user`.** -/
theorem proof_user_iff (p : Proof) :
    p.actor = .user ↔ (p.secret = false ∧ p.cookie = true ∧ p.origin = true) := by
  cases p with | mk a b c => cases a <;> cases b <;> cases c <;> simp [Proof.actor]

/-- A start request (the facts; `hasTarget` is `target ≠ none`). -/
structure Req where
  actor : Actor
  id : String
  task : String
  now : Nat
  diskMb : Nat
  hasTarget : Bool

/-- The decision on a start: the new table or the refusal. The first failing rule wins. -/
def admit (lo : Nat) (s : List Pv) (r : Req) : Except Refusal (List Pv) :=
  if !mayStart r.actor then .error .notOwner
  else if s.any (fun p => p.task == r.task || p.id == r.id) then .error .taskBusy
  else if K ≤ s.length then .error .tooMany
  else if r.diskMb < diskFloor then .error .lowDisk
  else if !r.hasTarget then .error .noTarget
  else if portSpace < lo + portN + backendOff then .error .noPorts
  else match freePorts lo s with
    | a :: b :: _ => .ok ({ id := r.id, task := r.task, rp := a, op := b, started := r.now } :: s)
    | _ => .error .noPorts

/-- An agent actor is refused. -/
theorem agent_actor_never_admitted (lo : Nat) (s : List Pv) (r : Req) (h : Fw.Ops.Identity.isAgentActor r.actor = true) :
    admit lo s r = .error .notOwner := by
  simp [admit, mayStart_not_agent r.actor h]

/-- **Without the owner proof nothing is admitted.** Over the request fields the route sees: a request that
shows the console secret, or lacks the owner cookie, or lacks a same-origin Origin, is refused `notOwner`
whatever the table is. (What the theorem cannot say: that no agent holds the cookie; see the design note.) -/
theorem agent_never_admitted (lo : Nat) (s : List Pv) (r : Req) (p : Proof) (ha : r.actor = p.actor)
    (hp : ¬ (p.secret = false ∧ p.cookie = true ∧ p.origin = true)) : admit lo s r = .error .notOwner := by
  have hne : r.actor ≠ .user := fun h => hp ((proof_user_iff p).mp (ha ▸ h))
  simp [admit, mayStart, hne]

/-- **A range whose backend ports would leave the port space admits nothing.** If every other rule passes, a base with
`lo + portN + backendOff > 65536` is refused `noPorts`, whatever the table. -/
theorem admit_refuses_high_base (lo : Nat) (s : List Pv) (r : Req) (hm : mayStart r.actor = true)
    (hb : s.any (fun p => p.task == r.task || p.id == r.id) = false) (hk : ¬ K ≤ s.length) (hd : ¬ r.diskMb < diskFloor)
    (ht : r.hasTarget = true) (h : portSpace < lo + portN + backendOff) : admit lo s r = .error .noPorts := by
  simp [admit, hm, hb, hk, hd, ht, h]

/-- **An admitted preview's backend ports are ports.** Stated against `admit`'s output: the new head has its public
and its backend port below 65536, for every base and table. -/
theorem admit_backend_in_space (lo : Nat) (s s' : List Pv) (r : Req) (h : admit lo s r = .ok s') :
    ∃ p t, s' = p :: t ∧ p.rp + backendOff < portSpace ∧ p.op + backendOff < portSpace := by
  unfold admit at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  rename_i hsp
  split at h
  · rename_i a b rest hf
    simp only [Except.ok.injEq] at h
    subst h
    have hmem : ∀ q ∈ freePorts lo s, lo ≤ q ∧ q < lo + portN := by
      intro q hq
      unfold freePorts at hq
      simp only [List.mem_filter, List.mem_range'_1, decide_eq_true_eq] at hq
      exact hq.1
    rw [hf] at hmem
    have ha := hmem a (by simp)
    have hb := hmem b (by simp)
    simp only [Nat.not_lt] at hsp
    exact ⟨_, _, rfl, by simp only []; omega, by simp only []; omega⟩
  · simp at h

/-- **Only the user is admitted.** -/
theorem admit_user (lo : Nat) (s s' : List Pv) (r : Req) (h : admit lo s r = .ok s') : r.actor = .user := by
  unfold admit at h
  by_cases hm : (!mayStart r.actor) = true
  · simp [hm] at h
  · simpa [mayStart] using hm

/-- Time passing: every preview past its deadline leaves the table (and its process group is stopped). -/
def tick (s : List Pv) (now : Nat) : List Pv := s.filter fun p => now < p.deadline

/-- The previews a tick stops. -/
def expired (s : List Pv) (now : Nat) : List Pv := s.filter fun p => !(now < p.deadline)

/-- A user stop: the previews with that id leave the table. -/
def stop (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id != i

/-- The previews a stop of `i` kills: only entries of the table. -/
def own (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id == i

/-- A failed build tears down: the preview with that id leaves the table (the same filter as a stop, without
an actor: the console tears down its own failure through Lean, not by a TypeScript-only path). -/
def fail (s : List Pv) (i : String) : List Pv := stop s i

/-- The console ticks every 30 s. -/
def tickPeriod : Nat := 30000

/-- Console start or stop: everything recorded is killed and the table is empty. -/
def reap (s : List Pv) : List Pv × List Pv := ([], s)

/-! ## Reachable tables and their invariants -/

/-- The tables the transitions produce from the empty one (admit, tick, stop). -/
inductive Reach (lo : Nat) : List Pv → Prop where
  | init : Reach lo []
  | admit {s s' : List Pv} (r : Req) : Reach lo s → admit lo s r = .ok s' → Reach lo s'
  | tick {s : List Pv} (t : Nat) : Reach lo s → Reach lo (tick s t)
  | stop {s : List Pv} (i : String) : Reach lo s → Reach lo (stop s i)
  | fail {s : List Pv} (i : String) : Reach lo s → Reach lo (fail s i)

/-- The invariants. -/
def Inv (lo : Nat) (s : List Pv) : Prop :=
  s.length ≤ K ∧ (ports s).Nodup ∧ ∀ q ∈ ports s, lo ≤ q ∧ q < lo + portN

/-- Filtering the table filters its ports (a sublist). -/
theorem ports_filter_sublist (s : List Pv) (f : Pv → Bool) : (ports (s.filter f)).Sublist (ports s) := by
  induction s with
  | nil => simp [ports]
  | cons a t ih =>
    cases hfa : f a
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      exact ih.trans ((List.sublist_cons_self _ _).trans (List.sublist_cons_self _ _))
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      simpa using ih.append_left [a.rp, a.op]

/-- The invariants survive any filter (tick and stop are filters). -/
theorem inv_filter {lo : Nat} {s : List Pv} (f : Pv → Bool) (h : Inv lo s) : Inv lo (s.filter f) := by
  obtain ⟨hl, hn, hr⟩ := h
  exact ⟨Nat.le_trans (List.length_filter_le _ _) hl, hn.sublist (ports_filter_sublist s f),
    fun q hq => hr q ((ports_filter_sublist s f).subset hq)⟩

/-- The invariants survive an admitted start. -/
theorem inv_admit {lo : Nat} {s s' : List Pv} (r : Req) (hi : Inv lo s) (h : admit lo s r = .ok s') : Inv lo s' := by
  obtain ⟨hl, hn, hr⟩ := hi
  unfold admit at h
  split at h
  · simp at h
  split at h
  · simp at h
  rename_i h1 h2
  split at h
  · simp at h
  rename_i h3
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · simp at h
  split at h
  · rename_i a b rest hf
    simp only [Except.ok.injEq] at h
    subst h
    have hmem : ∀ q ∈ freePorts lo s, lo ≤ q ∧ q < lo + portN ∧ q ∉ ports s := by
      intro q hq
      unfold freePorts at hq
      simp only [List.mem_filter, List.mem_range'_1, decide_eq_true_eq] at hq
      exact ⟨hq.1.1, hq.1.2, hq.2⟩
    have hnd : (freePorts lo s).Nodup := List.Nodup.sublist List.filter_sublist List.nodup_range'
    rw [hf] at hmem hnd
    have ha := hmem a (by simp)
    have hb := hmem b (by simp)
    have hab : a ≠ b := by
      intro e; subst e; simp at hnd
    refine ⟨?_, ?_, ?_⟩
    · simp only [List.length_cons]
      simp only [Nat.not_le] at h3
      omega
    · simp only [ports, List.flatMap_cons, List.cons_append, List.nil_append] at hn ⊢
      simp only [List.nodup_cons, List.mem_cons, not_or]
      exact ⟨⟨hab, fun hh => ha.2.2 (by simpa [ports] using hh)⟩, fun hh => hb.2.2 (by simpa [ports] using hh), hn⟩
    · intro q hq
      simp only [ports, List.flatMap_cons, List.cons_append, List.nil_append, List.mem_cons] at hq
      rcases hq with rfl | rfl | hq
      · exact ⟨ha.1, ha.2.1⟩
      · exact ⟨hb.1, hb.2.1⟩
      · exact hr q (by simpa [ports] using hq)
  · simp at h

/-- **Every reachable table satisfies the invariants.** -/
theorem reach_inv {lo : Nat} {s : List Pv} (h : Reach lo s) : Inv lo s := by
  induction h with
  | init => exact ⟨by simp [K], by simp [ports], by simp [ports]⟩
  | admit r _ ha ih => exact inv_admit r ih ha
  | tick t _ ih => exact inv_filter _ ih
  | stop i _ ih => exact inv_filter _ ih
  | fail i _ ih => exact inv_filter _ ih

/-- **At most `K` live previews, always.** -/
theorem live_le_K {lo : Nat} {s : List Pv} (h : Reach lo s) : s.length ≤ K := (reach_inv h).1

/-- **Ports are pairwise distinct** (the rewrite and original ports of all live previews). -/
theorem ports_distinct {lo : Nat} {s : List Pv} (h : Reach lo s) : (ports s).Nodup := (reach_inv h).2.1

/-- **Ports stay in the range of the base** (production: `portLo`, 47100 to 47139). -/
theorem ports_in_range {lo : Nat} {s : List Pv} (h : Reach lo s) : ∀ q ∈ ports s, lo ≤ q ∧ q < lo + portN :=
  (reach_inv h).2.2

/-- **Expired previews are stopped at the next tick.** After a tick no preview of the table is past its deadline,
and every one that was is in the kill list. -/
theorem expired_stopped (s : List Pv) (t : Nat) :
    (∀ p ∈ tick s t, t < p.started + ttl) ∧
    (∀ p ∈ s, p.started + ttl ≤ t → p ∈ expired s t ∧ p ∉ tick s t) := by
  refine ⟨fun p hp => ?_, fun p hp he => ?_⟩
  · exact of_decide_eq_true (List.mem_filter.mp hp).2
  · refine ⟨List.mem_filter.mpr ⟨hp, ?_⟩, fun hm => ?_⟩
    · have : ¬ t < p.deadline := by simp only [Pv.deadline]; omega
      simp [this]
    · have h2 : t < p.deadline := of_decide_eq_true (List.mem_filter.mp hm).2
      simp only [Pv.deadline] at h2
      omega

/-- **Bounded lifetime.** A preview that survives a tick is younger than the TTL. -/
theorem tick_lifetime (s : List Pv) (t : Nat) (p : Pv) (hp : p ∈ tick s t) (h0 : p.started ≤ t) :
    t - p.started < ttl := by
  have := (expired_stopped s t).1 p hp
  omega

/-- A tick is idempotent. -/
theorem tick_idem (s : List Pv) (t : Nat) : tick (tick s t) t = tick s t := by
  simp [tick, List.filter_filter]

/-- **A stop kills only what the console recorded.** Every process group in the kill list is a table entry, and
an id that is not in the table kills nothing. -/
theorem stop_only_own (s : List Pv) (i : String) :
    (∀ p ∈ own s i, p ∈ s) ∧ ((∀ p ∈ s, p.id ≠ i) → own s i = []) := by
  refine ⟨fun p hp => (List.mem_filter.mp hp).1, fun h => ?_⟩
  unfold own
  rw [List.filter_eq_nil_iff]
  intro p hp
  have := h p hp
  simp [this]

/-- A stop splits the table into what stays and what is killed. -/
theorem stop_partition (s : List Pv) (i : String) : (own s i ++ stop s i).Perm s := by
  unfold stop own
  have := List.filter_append_perm (fun p : Pv => p.id == i) s
  simpa [Function.comp_def, bne] using this

/-- **Expiry kills only table entries too.** -/
theorem expired_sub (s : List Pv) (t : Nat) : ∀ p ∈ expired s t, p ∈ s :=
  fun _ hp => (List.mem_filter.mp hp).1

/-- **A failure removes only table entries.** -/
theorem fail_only_own (s : List Pv) (i : String) :
    (∀ p ∈ fail s i, p ∈ s) ∧ ((∀ p ∈ s, p.id ≠ i) → fail s i = s) := by
  refine ⟨fun p hp => (List.mem_filter.mp hp).1, fun h => ?_⟩
  unfold fail stop
  rw [List.filter_eq_self]
  intro p hp
  simp [h p hp]

/-- **The lifetime bound.** With a tick every `tickPeriod` ms, some tick falls in the 30 s window that starts at
a preview's deadline; with `expired_stopped` the preview is gone at most 30 s after its 60 minutes. -/
theorem tick_within_period (d τ : Nat) (h : τ ≤ d) :
    ∃ k, d ≤ τ + k * tickPeriod ∧ τ + k * tickPeriod < d + tickPeriod := by
  unfold tickPeriod
  exact ⟨(d - τ + 29999) / 30000, by omega, by omega⟩

/-- **Reap kills exactly the table and empties it.** -/
theorem reap_all (s : List Pv) : (reap s).1 = [] ∧ (reap s).2 = s := ⟨rfl, rfl⟩

/-! ## The owner link: where it may be written -/

/-- Every place the console could write the one-time owner link. -/
inductive Sink where
  | tty | stdout | stderr | file | log | eventStore
deriving Repr, DecidableEq

/-- The link may go to a sink iff it is the controlling terminal (a process's stdout can be a file any agent reads).
Stated limit (INFERRED): `tty` means a terminal exists, not that it is the user's; a same-UID process can allocate a
pseudo-terminal and read the link there. -/
def linkSink (s : Sink) : Bool := s == .tty

/-- What the console does with the link: write it to the terminal when it has one, else print no link (the user asks
for one with the `owner-link` command, which itself needs a terminal). -/
def linkPlan (hasTty : Bool) : Option Sink := if hasTty then some .tty else none

/-- **The link is allowed only on the terminal.** -/
theorem linkSink_iff (s : Sink) : linkSink s = true ↔ s = .tty := by
  cases s <;> simp [linkSink]

/-- **No file sink.** The link is never written to a file (so not to a redirected stdout, a log, or the event store). -/
theorem no_file_sink : linkSink .file = false := rfl

/-- **No non-terminal sink.** Stdout, stderr, a file, a log and the event store are all refused. -/
theorem no_nontty_sink (s : Sink) (h : s ≠ .tty) : linkSink s = false := by
  cases s <;> simp_all [linkSink]

/-- **The plan only chooses an allowed sink,** and only when there is a terminal. -/
theorem linkPlan_ok (t : Bool) (s : Sink) (h : linkPlan t = some s) : linkSink s = true ∧ t = true := by
  cases t <;> simp_all [linkPlan, linkSink]

/-- With no terminal the console prints no link. -/
theorem linkPlan_no_tty : linkPlan false = none := rfl

/-! ## Re-issuing the link -/

/-- The least time between two owner links (ms): one per minute, so a process of the same user that signals the console
cannot keep invalidating the link the user has not opened yet. -/
def reissueGap : Nat := 60000

/-- May a new owner link be issued at `now`, the last having been issued at `last` (none yet: yes). -/
def mayReissue (last : Option Nat) (now : Nat) : Bool :=
  match last with
  | none => true
  | some l => decide (l + reissueGap ≤ now)

/-- **Two links are at least a minute apart.** A reissue is allowed only when the last link is at least `gap` old. -/
theorem mayReissue_gap (l n : Nat) (h : mayReissue (some l) n = true) : l + reissueGap ≤ n := by
  simpa [mayReissue] using h

/-- **A reissue inside the minute is refused.** -/
theorem mayReissue_refused (l n : Nat) (h : n < l + reissueGap) : mayReissue (some l) n = false := by
  simp [mayReissue]; omega

/-- **The first link is always allowed.** -/
theorem mayReissue_first (n : Nat) : mayReissue none n = true := rfl

end Fw.Console.Preview
