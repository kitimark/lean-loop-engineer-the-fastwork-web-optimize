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
  task, at most `K` live previews, a disk floor, a target, and two free ports of the fixed localhost range
  (one for the rewrite, one for the original).
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

/-- Most live previews (a build is about 60 MB of disk and a few seconds of CPU).

$$K = 2$$ -/
def K : Nat := 2

/-- A preview's lifetime in milliseconds (60 minutes).

$$\mathit{ttl} = 60 \cdot 60 \cdot 1000$$ -/
def ttl : Nat := 3600000

/-- Disk floor in MB: a start is refused when less is free.

$$\mathit{floor} = 2048$$ -/
def diskFloor : Nat := 2048

/-- The first port of the localhost range.

$$P = \{47100, \dots, 47139\}, \quad \mathit{portLo} = 47100$$ -/
def portLo : Nat := 47100

/-- The number of ports in the range.

$$|P| = 40$$ -/
def portN : Nat := 40

/-! ## Target commit -/

/-- An integration ref the glue found: its name, its tip, and whether it contains a given commit
(`git merge-base --is-ancestor commit tip`).

$$c = (\mathit{ref}, \mathit{sha}, \mathit{contains}) \in \mathrm{String} \times \mathrm{String} \times \mathbb{B}$$ -/
structure Cand where
  ref : String
  sha : String
  contains : Bool
deriving Repr, DecidableEq

/-- One commit of main's first-parent line that contains the head (oldest first), and whether its second parent
contains the head (`git merge-base --is-ancestor head parent2`; false for a commit with one parent).

$$p = (\mathit{sha}, \mathit{p2Has}) \in \mathrm{String} \times \mathbb{B}$$ -/
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
glue sets it true for every other source), and whether another candidate holds code this one lacks (`behind`).

$$f = (\mathit{src}, s, \mathit{onMain}, \mathit{noCode}, \mathit{cs}, \mathit{fpLine}, \mathit{path}, \mathit{ownWork}, \mathit{behind})$$ -/
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

/-- What a preview shows.

$$\mathrm{Target} = \mathrm{main}(s) \mid \mathrm{integration}(\mathit{ref}, s) \mid \mathrm{own}(s) \mid \mathrm{none}$$ -/
inductive Target where
  | main (sha : String)
  | integration (ref sha : String)
  | own (sha : String)
  | none
deriving Repr, DecidableEq

/-- The first candidate that contains the commit (candidates come newest first).

$$\operatorname{firstContaining}(cs) = \text{the first } c \in cs \text{ with } c.\mathit{contains}$$ -/
def firstContaining (cs : List Cand) : Option Cand := cs.find? (·.contains)

/-- A commit is held when main or an integration ref contains it.

$$\operatorname{held}(f) \iff f.\mathit{onMain} \vee \exists c \in f.\mathit{cs},\ c.\mathit{contains}$$ -/
def Fact.held (f : Fact) : Bool := f.onMain || f.cands.any (·.contains)

/-- A candidate may be the head unless it is a merge's second parent that does not contain the task's own work
(a "merge main into the branch" commit has a second parent on main's first-parent line: that is main's work, not the
task's), or another candidate holds code it lacks (an older commit that the gate's commit has since replaced).

$$\operatorname{adm}(f) \iff (f.\mathit{src} \ne \mathrm{merge} \vee f.\mathit{ownWork}) \wedge \neg f.\mathit{behind}$$ -/
def Fact.admissible (f : Fact) : Bool := (f.src != "merge" || f.ownWork) && !f.behind

/-- The rank of a candidate source: the worktree branch the handoff names, a merge's second parent, a branch named
like the task, the newest commit touching the handoff, then `ci/<task>`, then `origin/ci/<task>`; an unknown source last.

$$\operatorname{rank}(\mathit{handoff}) = 0 < \operatorname{rank}(\mathit{merge}) = 1 < \operatorname{rank}(\mathit{named}) = 2 < \operatorname{rank}(\mathit{handoffCommit}) = 3 < \operatorname{rank}(\mathit{ci}) = 4 < \operatorname{rank}(\mathit{originCi}) = 5 < 6$$ -/
def srcRank (src : String) : Nat :=
  match src with
  | "handoff" => 0 | "merge" => 1 | "named" => 2 | "handoffCommit" => 3 | "ci" => 4 | "originCi" => 5 | _ => 6

/-- Insert a candidate before the first one of equal or higher rank (structural, so the kernel can evaluate it).

$$\operatorname{insert}(f, g :: t) = \begin{cases} f :: g :: t & \operatorname{rank}(f) \le \operatorname{rank}(g)\\ g :: \operatorname{insert}(f, t) & \text{otherwise}\end{cases}$$ -/
def insertByRank (f : Fact) : List Fact → List Fact
  | [] => [f]
  | g :: t => if srcRank f.src ≤ srcRank g.src then f :: g :: t else g :: insertByRank f t

/-- Inserting only adds the candidate.

$$\operatorname{insert}(f, l) \sim f :: l$$ -/
theorem insertByRank_perm (f : Fact) (l : List Fact) : (insertByRank f l).Perm (f :: l) := by
  induction l with
  | nil => simp [insertByRank]
  | cons g t ih =>
    unfold insertByRank
    split
    · exact List.Perm.refl _
    · exact ((ih.cons g).trans (List.Perm.swap f g t))

/-- The candidates in head priority order (a stable sort by `srcRank`; the order the glue lists them in does not matter).

$$\operatorname{ordered}(fs) = \operatorname{sort}_{\le}\bigl(fs,\ f \mapsto \operatorname{rank}(f.\mathit{src})\bigr)$$ -/
def ordered (fs : List Fact) : List Fact := fs.foldr insertByRank []

/-- **Sorting loses and invents no candidate.** The ordered list is a permutation of the glue's list, so the
glue's listing order carries no decision.

$$\operatorname{ordered}(fs) \sim fs$$ -/
theorem ordered_perm (fs : List Fact) : (ordered fs).Perm fs := by
  induction fs with
  | nil => simp [ordered]
  | cons f t ih =>
    have : (ordered (f :: t)) = insertByRank f (ordered t) := rfl
    rw [this]
    exact (insertByRank_perm f _).trans (ih.cons f)

/-- The candidates that may be the head, in head priority order.

$$\operatorname{eligible}(fs) = \operatorname{filter}(\operatorname{adm}, \operatorname{ordered}(fs))$$ -/
def eligible (fs : List Fact) : List Fact := (ordered fs).filter Fact.admissible

/-- The task head among the candidates: the first (in `eligible`) that main or an integration ref holds (a
documentation-only handoff commit never hides the commit the gate ran; the worktree or merge head comes before
`origin/ci`), else the first candidate; no candidate, no head. A head that main holds then previews its land commit
(`targetOf`).

$$\operatorname{pickHead}(fs) = \begin{cases}
\text{the first } f \in \operatorname{eligible}(fs) \text{ with } \operatorname{held}(f) & \text{if any}\\
\operatorname{head}(\operatorname{eligible}(fs)) & \text{otherwise (}\bot \text{ if } \operatorname{eligible}(fs) = [\,])
\end{cases}$$ -/
def pickHead (fs : List Fact) : Option Fact :=
  match (eligible fs).find? Fact.held with
  | some f => some f
  | none => (eligible fs).head?

/-- The integration ref whose tip is exactly the commit, among those that contain it.

$$\operatorname{exactTip}(f) = \text{the first } c \in f.\mathit{cs} \text{ with } c.\mathit{contains} \wedge c.\mathit{sha} = f.s$$ -/
def exactTip (f : Fact) : Option Cand := f.cands.find? fun c => c.contains && c.sha == f.sha

/-- The commit a landed head previews (its land commit on main). A head on main's first-parent line is its own land
commit; otherwise it is the first commit (oldest) of main's first-parent line containing the head whose second parent
contains the head; main's tip when the glue found none.

$$\operatorname{landOf}(m, f) = \begin{cases} f.s & f.\mathit{fpLine}\\ p.\mathit{sha} & \neg f.\mathit{fpLine},\ p = \text{the first } p \in f.\mathit{path} \text{ with } p.\mathit{p2Has}\\ m & \text{otherwise}\end{cases}$$ -/
def landOf (m : String) (f : Fact) : String :=
  if f.fpLine then f.sha else
  match f.path.find? (·.p2Has) with
  | some p => p.sha
  | none => m

/-- **A head on main's first-parent line is its own land commit.**

$$f.\mathit{fpLine} \Rightarrow \operatorname{landOf}(m, f) = f.s$$ -/
theorem landOf_fpLine (m : String) (f : Fact) (h : f.fpLine = true) : landOf m f = f.sha := by
  simp [landOf, h]

/-- **Otherwise the land commit is the first path commit whose second parent contains the head.**

$$\neg f.\mathit{fpLine} \wedge \operatorname{find}(\mathit{p2Has}, f.\mathit{path}) = p \Rightarrow \operatorname{landOf}(m, f) = p.\mathit{sha}$$ -/
theorem landOf_path (m : String) (f : Fact) (p : PathC) (h : f.fpLine = false)
    (hp : f.path.find? (·.p2Has) = some p) : landOf m f = p.sha := by
  simp [landOf, h, hp]

/-- **The land commit is the head itself, main's tip, or a path commit whose second parent holds the head.**

$$\operatorname{landOf}(m, f) = f.s \ \vee\ \operatorname{landOf}(m, f) = m \ \vee\ \exists p \in f.\mathit{path},\ p.\mathit{p2Has} \wedge p.\mathit{sha} = \operatorname{landOf}(m, f)$$ -/
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
holds, the newest integration ref (the newest state of the parts it examined); else the head itself.

$$\operatorname{targetOf}(m, f) = \begin{cases}
\mathrm{main}(\operatorname{landOf}(m, f)) & f.\mathit{onMain}\\
\mathrm{integration}(c) & c = \operatorname{exactTip}(f)\\
\mathrm{integration}(c) & c = \operatorname{firstContaining}(f.\mathit{cs})\\
\mathrm{integration}(\operatorname{head}(f.\mathit{cs})) & f.\mathit{noCode} \wedge f.\mathit{cs} \ne [\,]\\
\mathrm{own}(f.s) & \text{otherwise}
\end{cases}$$ -/
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

$$\operatorname{umbrella}(m, ks) = \begin{cases}
\mathrm{none} & ks = [\,]\\
\mathrm{main}(m) & \forall k \in ks,\ k.\mathit{onMain}\\
\mathrm{integration}(c) & c \text{ the first of } k_0.\mathit{cs} \text{ with } \forall k \in ks,\ k \text{ is contained in } c\\
\mathrm{none} & \text{otherwise}
\end{cases}$$
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
(`umbrella`).

$$\operatorname{headOf}(m, fs, kss) = \begin{cases}
(f, \operatorname{targetOf}(m, f)) & f = \operatorname{pickHead}(fs) \ne \bot\\
(\bot, \operatorname{umbrella}(m, [\operatorname{pickHead}(ks) \mid ks \in kss, \operatorname{pickHead}(ks) \ne \bot])) & fs = [\,]
\end{cases}$$ -/
def headOf (mainSha : String) (fs : List Fact) (kss : List (List Fact)) : Option Fact × Target :=
  match pickHead fs with
  | some f => (some f, targetOf mainSha f)
  | none => (none, umbrella mainSha (kss.filterMap pickHead))

/-- **No work, no preview.**

$$\forall m:\ \operatorname{headOf}(m, [\,], [\,]) = (\bot, \mathrm{none})$$ -/
theorem headOf_noWork (m : String) : headOf m [] [] = (none, .none) := by
  simp [headOf, pickHead, eligible, ordered, umbrella]

/-- **Landed means main.** A head main contains gives `main`.

$$f.\mathit{onMain} \Rightarrow \operatorname{targetOf}(m, f) = \mathrm{main}(\operatorname{landOf}(m, f))$$ -/
theorem targetOf_landed (m : String) (f : Fact) (h : f.onMain = true) : targetOf m f = .main (landOf m f) := by
  simp [targetOf, h]

/-- **A held head is never shown as its own.** If main or an integration ref holds the head, the target is
`main` or an integration ref, not `own`.

$$\operatorname{held}(f) \Rightarrow \forall s,\ \operatorname{targetOf}(m, f) \ne \mathrm{own}(s)$$ -/
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
integration ref does, and the head has code (or there is no integration ref at all).

$$\operatorname{targetOf}(m, f) = \mathrm{own}(s) \Rightarrow \neg f.\mathit{onMain} \wedge (\forall c \in f.\mathit{cs},\ \neg c.\mathit{contains}) \wedge (\neg f.\mathit{noCode} \vee f.\mathit{cs} = [\,])$$ -/
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
(it is the first held one).

$$\exists f \in fs,\ \operatorname{adm}(f) \wedge \operatorname{held}(f) \Rightarrow \exists g,\ \operatorname{pickHead}(fs) = g \wedge \operatorname{held}(g)$$ -/
theorem pickHead_held (fs : List Fact) (h : ∃ f ∈ fs, f.admissible = true ∧ f.held = true) :
    ∃ g, pickHead fs = some g ∧ g.held = true := by
  obtain ⟨f, hf, ha, hh⟩ := h
  have hmem : f ∈ eligible fs := List.mem_filter.mpr ⟨(ordered_perm fs).mem_iff.mpr hf, ha⟩
  unfold pickHead
  cases hx : (eligible fs).find? Fact.held with
  | none => exact absurd (List.find?_eq_none.mp hx f hmem) (by simpa using hh)
  | some g => exact ⟨g, rfl, List.find?_some hx⟩

/-- **The first eligible candidate wins when held.** If the first eligible candidate (rank order, whatever the
glue's listing order) is held, it is the head.

$$\operatorname{eligible}(fs) = g :: t \ \wedge\ \operatorname{held}(g) \Rightarrow \operatorname{pickHead}(fs) = \mathrm{some}(g)$$ -/
theorem pickHead_first_held (fs : List Fact) (g : Fact) (t : List Fact) (ho : eligible fs = g :: t)
    (hg : g.held = true) : pickHead fs = some g := by
  simp [pickHead, ho, List.find?_cons, hg]

/-- **Every picked head is admissible.** Whatever the facts, the head is never a candidate the rule excludes.

$$\operatorname{pickHead}(fs) = \mathrm{some}(g) \Rightarrow \operatorname{adm}(g)$$ -/
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
branch" commit (second parent on main's first-parent line) is never picked, in any rank order.

$$f.\mathit{src} = \mathrm{merge} \wedge \neg f.\mathit{ownWork} \Rightarrow \operatorname{pickHead}(fs) \ne \mathrm{some}(f)$$ -/
theorem pickHead_inadmissible_merge (fs : List Fact) (f : Fact) (hs : f.src = "merge") (hw : f.ownWork = false) :
    pickHead fs ≠ some f := by
  intro h
  have := pickHead_admissible fs f h
  simp [Fact.admissible, hs, hw] at this

/-- **A picked head is never behind another candidate.** The head never lacks code that another candidate holds.

$$\operatorname{pickHead}(fs) = \mathrm{some}(g) \Rightarrow \neg g.\mathit{behind}$$ -/
theorem pickHead_not_behind (fs : List Fact) (g : Fact) (h : pickHead fs = some g) : g.behind = false := by
  have := pickHead_admissible fs g h
  simp [Fact.admissible] at this
  exact this.2

/-- **Filter invariance** (what remains of the former `target_deterministic`). For a held head, dropping the
integration refs that do not contain it gives the same target; it is the only claim, the target is not
asserted to depend on anything else.

$$\operatorname{held}(f) \Rightarrow \operatorname{targetOf}(m, f) = \operatorname{targetOf}\bigl(m, f[\mathit{cs} := \operatorname{filter}(\mathit{contains}, f.\mathit{cs})]\bigr)$$ -/
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

$$p = (\mathit{id}, \mathit{task}, \mathit{rp}, \mathit{op}, t_0)$$ with the rewrite port `rp`, the original's port `op`, the start time `t₀` (ms). -/
structure Pv where
  id : String
  task : String
  rp : Nat
  op : Nat
  started : Nat
deriving Repr, DecidableEq

/-- The deadline of a preview.

$$\operatorname{deadline}(p) = p.t_0 + \mathit{ttl}$$ -/
def Pv.deadline (p : Pv) : Nat := p.started + ttl

/-- The ports the table holds.

$$\operatorname{ports}(T) = [\,p.\mathit{rp}, p.\mathit{op}\ \text{for}\ p \in T\,]$$ -/
def ports (s : List Pv) : List Nat := s.flatMap fun p => [p.rp, p.op]

/-- The free ports of the range, ascending.

$$F(T) = \{\mathit{portLo} + i \mid i < \mathit{portN}\} \setminus \operatorname{ports}(T)$$ -/
def freePorts (s : List Pv) : List Nat := (List.range' portLo portN).filter fun q => q ∉ ports s

/-- Why a start is refused.

$$\mathrm{Refusal} = \{\mathrm{notOwner}, \mathrm{taskBusy}, \mathrm{tooMany}, \mathrm{lowDisk}, \mathrm{noPorts}, \mathrm{noTarget}\}$$ -/
inductive Refusal where
  | notOwner | taskBusy | tooMany | lowDisk | noPorts | noTarget
deriving Repr, DecidableEq

/-- The wire name of a refusal.

$$\operatorname{name}(r) = \text{the constructor name of } r$$ -/
def Refusal.name : Refusal → String
  | .notOwner => "notOwner" | .taskBusy => "taskBusy" | .tooMany => "tooMany"
  | .lowDisk => "lowDisk" | .noPorts => "noPorts" | .noTarget => "noTarget"

/-- Who may start or stop a preview: the user only.

$$\operatorname{mayStart}(a) = \mathrm{true} \iff a = \mathrm{user}$$ -/
def mayStart (a : Actor) : Bool := a == .user

/-- Every agent actor is refused.

$$\operatorname{isAgentActor}(a) \Rightarrow \operatorname{mayStart}(a) = \mathrm{false}$$ -/
theorem mayStart_not_agent (a : Actor) (h : Fw.Ops.Identity.isAgentActor a = true) : mayStart a = false := by
  cases a <;> simp_all [mayStart, Fw.Ops.Identity.isAgentActor]

/-- What a request to a preview route shows: the three facts the route can check, and nothing else. `secret`: the
console secret header matched (the runner's own tools). `cookie`: the owner cookie matched the session that the
one-time owner link opened. `origin`: the Origin header is present and is an origin of this console.

$$p = (\mathit{secret}, \mathit{cookie}, \mathit{origin}) \in \mathbb{B}^3$$ -/
structure Proof where
  secret : Bool
  cookie : Bool
  origin : Bool
deriving Repr, DecidableEq

/-- The actor a request is stamped as.

$$\operatorname{actor}(p) = \begin{cases}
\mathrm{lead} & p.\mathit{secret}\\
\mathrm{user} & \neg p.\mathit{secret} \wedge p.\mathit{cookie} \wedge p.\mathit{origin}\\
\mathrm{script} & \text{otherwise}
\end{cases}$$ -/
def Proof.actor (p : Proof) : Actor :=
  if p.secret then .lead else if p.cookie && p.origin then .user else .script

/-- **Only the full owner proof is `user`.**

$$\operatorname{actor}(p) = \mathrm{user} \iff p.\mathit{secret} = \mathrm{false} \wedge p.\mathit{cookie} = \mathrm{true} \wedge p.\mathit{origin} = \mathrm{true}$$ -/
theorem proof_user_iff (p : Proof) :
    p.actor = .user ↔ (p.secret = false ∧ p.cookie = true ∧ p.origin = true) := by
  cases p with | mk a b c => cases a <;> cases b <;> cases c <;> simp [Proof.actor]

/-- A start request (the facts; `hasTarget` is `target ≠ none`).

$$r = (a, \mathit{id}, \mathit{task}, \mathit{now}, \mathit{disk}, \mathit{hasTarget})$$ -/
structure Req where
  actor : Actor
  id : String
  task : String
  now : Nat
  diskMb : Nat
  hasTarget : Bool

/-- The decision on a start: the new table or the refusal. The first failing rule wins.

$$\operatorname{admit}(T, r) = \begin{cases}
\mathrm{notOwner} & r.a \ne \mathrm{user}\\
\mathrm{taskBusy} & \exists p \in T,\ p.\mathit{task} = r.\mathit{task} \vee p.\mathit{id} = r.\mathit{id}\\
\mathrm{tooMany} & |T| \ge K\\
\mathrm{lowDisk} & r.\mathit{disk} < \mathit{floor}\\
\mathrm{noTarget} & \neg r.\mathit{hasTarget}\\
\mathrm{noPorts} & |F(T)| < 2\\
(q_1, q_2, r.\mathit{now})\!::\!T & q_1, q_2 \text{ the two smallest of } F(T)
\end{cases}$$ -/
def admit (s : List Pv) (r : Req) : Except Refusal (List Pv) :=
  if !mayStart r.actor then .error .notOwner
  else if s.any (fun p => p.task == r.task || p.id == r.id) then .error .taskBusy
  else if K ≤ s.length then .error .tooMany
  else if r.diskMb < diskFloor then .error .lowDisk
  else if !r.hasTarget then .error .noTarget
  else match freePorts s with
    | a :: b :: _ => .ok ({ id := r.id, task := r.task, rp := a, op := b, started := r.now } :: s)
    | _ => .error .noPorts

/-- An agent actor is refused.

$$\operatorname{isAgentActor}(a) \Rightarrow \operatorname{admit}(T, r) = \mathrm{error}(\mathrm{notOwner})$$ -/
theorem agent_actor_never_admitted (s : List Pv) (r : Req) (h : Fw.Ops.Identity.isAgentActor r.actor = true) :
    admit s r = .error .notOwner := by
  simp [admit, mayStart_not_agent r.actor h]

/-- **Without the owner proof nothing is admitted.** Over the request fields the route sees: a request that
shows the console secret, or lacks the owner cookie, or lacks a same-origin Origin, is refused `notOwner`
whatever the table is. (What the theorem cannot say: that no agent holds the cookie; see the design note.)

$$r.a = \operatorname{actor}(p) \wedge \neg(p.\mathit{secret} = \mathrm{false} \wedge p.\mathit{cookie} \wedge p.\mathit{origin}) \Rightarrow \operatorname{admit}(T, r) = \mathrm{error}(\mathrm{notOwner})$$ -/
theorem agent_never_admitted (s : List Pv) (r : Req) (p : Proof) (ha : r.actor = p.actor)
    (hp : ¬ (p.secret = false ∧ p.cookie = true ∧ p.origin = true)) : admit s r = .error .notOwner := by
  have hne : r.actor ≠ .user := fun h => hp ((proof_user_iff p).mp (ha ▸ h))
  simp [admit, mayStart, hne]

/-- **Only the user is admitted.**

$$\operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow r.a = \mathrm{user}$$ -/
theorem admit_user (s s' : List Pv) (r : Req) (h : admit s r = .ok s') : r.actor = .user := by
  unfold admit at h
  by_cases hm : (!mayStart r.actor) = true
  · simp [hm] at h
  · simpa [mayStart] using hm

/-- Time passing: every preview past its deadline leaves the table (and its process group is stopped).

$$\operatorname{tick}(T, t) = [\,p \in T \mid t < p.\mathit{deadline}\,]$$ -/
def tick (s : List Pv) (now : Nat) : List Pv := s.filter fun p => now < p.deadline

/-- The previews a tick stops.

$$\operatorname{expired}(T, t) = [\,p \in T \mid p.\mathit{deadline} \le t\,]$$ -/
def expired (s : List Pv) (now : Nat) : List Pv := s.filter fun p => !(now < p.deadline)

/-- A user stop: the previews with that id leave the table.

$$\operatorname{stop}(T, i) = [\,p \in T \mid p.\mathit{id} \ne i\,]$$ -/
def stop (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id != i

/-- The previews a stop of `i` kills: only entries of the table.

$$\operatorname{own}(T, i) = [\,p \in T \mid p.\mathit{id} = i\,]$$ -/
def own (s : List Pv) (i : String) : List Pv := s.filter fun p => p.id == i

/-- A failed build tears down: the preview with that id leaves the table (the same filter as a stop, without
an actor: the console tears down its own failure through Lean, not by a TypeScript-only path).

$$\operatorname{fail}(T, i) = \operatorname{stop}(T, i)$$ -/
def fail (s : List Pv) (i : String) : List Pv := stop s i

/-- The console ticks every 30 s.

$$\mathit{tickPeriod} = 30000\ \text{ms}$$ -/
def tickPeriod : Nat := 30000

/-- Console start or stop: everything recorded is killed and the table is empty.

$$\operatorname{reap}(T) = (\,[\,],\ T\,)$$ -/
def reap (s : List Pv) : List Pv × List Pv := ([], s)

/-! ## Reachable tables and their invariants -/

/-- The tables the transitions produce from the empty one (admit, tick, stop).

$$\mathrm{Reach}([\,]),\quad \mathrm{Reach}(T) \wedge \operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow \mathrm{Reach}(T'),\quad \mathrm{Reach}(T) \Rightarrow \mathrm{Reach}(\operatorname{tick}(T, t)) \wedge \mathrm{Reach}(\operatorname{stop}(T, i))$$ -/
inductive Reach : List Pv → Prop where
  | init : Reach []
  | admit {s s' : List Pv} (r : Req) : Reach s → admit s r = .ok s' → Reach s'
  | tick {s : List Pv} (t : Nat) : Reach s → Reach (tick s t)
  | stop {s : List Pv} (i : String) : Reach s → Reach (stop s i)
  | fail {s : List Pv} (i : String) : Reach s → Reach (fail s i)

/-- The invariants.

$$\operatorname{Inv}(T) \iff |T| \le K \wedge \operatorname{ports}(T)\ \text{has no duplicates} \wedge \operatorname{ports}(T) \subseteq P$$ -/
def Inv (s : List Pv) : Prop :=
  s.length ≤ K ∧ (ports s).Nodup ∧ ∀ q ∈ ports s, portLo ≤ q ∧ q < portLo + portN

/-- Filtering the table filters its ports (a sublist).

$$\operatorname{ports}(\operatorname{filter}(f, T)) \preceq \operatorname{ports}(T)$$ -/
theorem ports_filter_sublist (s : List Pv) (f : Pv → Bool) : (ports (s.filter f)).Sublist (ports s) := by
  induction s with
  | nil => simp [ports]
  | cons a t ih =>
    cases hfa : f a
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      exact ih.trans ((List.sublist_cons_self _ _).trans (List.sublist_cons_self _ _))
    · simp only [ports, List.filter_cons, hfa, List.flatMap_cons] at ih ⊢
      simpa using ih.append_left [a.rp, a.op]

/-- The invariants survive any filter (tick and stop are filters).

$$\operatorname{Inv}(T) \Rightarrow \operatorname{Inv}(\operatorname{filter}(f, T))$$ -/
theorem inv_filter {s : List Pv} (f : Pv → Bool) (h : Inv s) : Inv (s.filter f) := by
  obtain ⟨hl, hn, hr⟩ := h
  exact ⟨Nat.le_trans (List.length_filter_le _ _) hl, hn.sublist (ports_filter_sublist s f),
    fun q hq => hr q ((ports_filter_sublist s f).subset hq)⟩

/-- The invariants survive an admitted start.

$$\operatorname{Inv}(T) \wedge \operatorname{admit}(T, r) = \mathrm{ok}(T') \Rightarrow \operatorname{Inv}(T')$$ -/
theorem inv_admit {s s' : List Pv} (r : Req) (hi : Inv s) (h : admit s r = .ok s') : Inv s' := by
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
  · rename_i a b rest hf
    simp only [Except.ok.injEq] at h
    subst h
    have hmem : ∀ q ∈ freePorts s, portLo ≤ q ∧ q < portLo + portN ∧ q ∉ ports s := by
      intro q hq
      unfold freePorts at hq
      simp only [List.mem_filter, List.mem_range'_1, decide_eq_true_eq] at hq
      exact ⟨hq.1.1, hq.1.2, hq.2⟩
    have hnd : (freePorts s).Nodup := List.Nodup.sublist List.filter_sublist List.nodup_range'
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

/-- **Every reachable table satisfies the invariants.**

$$\mathrm{Reach}(T) \Rightarrow \operatorname{Inv}(T)$$ -/
theorem reach_inv {s : List Pv} (h : Reach s) : Inv s := by
  induction h with
  | init => exact ⟨by simp [K], by simp [ports], by simp [ports]⟩
  | admit r _ ha ih => exact inv_admit r ih ha
  | tick t _ ih => exact inv_filter _ ih
  | stop i _ ih => exact inv_filter _ ih
  | fail i _ ih => exact inv_filter _ ih

/-- **At most `K` live previews, always.**

$$\mathrm{Reach}(T) \Rightarrow |T| \le K = 2$$ -/
theorem live_le_K {s : List Pv} (h : Reach s) : s.length ≤ K := (reach_inv h).1

/-- **Ports are pairwise distinct** (the rewrite and original ports of all live previews).

$$\mathrm{Reach}(T) \Rightarrow \operatorname{ports}(T)\ \text{has no duplicates}$$ -/
theorem ports_distinct {s : List Pv} (h : Reach s) : (ports s).Nodup := (reach_inv h).2.1

/-- **Ports stay in the fixed localhost range.**

$$\mathrm{Reach}(T) \Rightarrow \forall q \in \operatorname{ports}(T):\ 47100 \le q < 47140$$ -/
theorem ports_in_range {s : List Pv} (h : Reach s) : ∀ q ∈ ports s, portLo ≤ q ∧ q < portLo + portN :=
  (reach_inv h).2.2

/-- **Expired previews are stopped at the next tick.** After a tick no preview of the table is past its deadline,
and every one that was is in the kill list.

$$\forall p \in \operatorname{tick}(T, t):\ t < p.t_0 + \mathit{ttl}, \qquad \forall p \in T:\ p.t_0 + \mathit{ttl} \le t \Rightarrow p \in \operatorname{expired}(T, t) \wedge p \notin \operatorname{tick}(T, t)$$ -/
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

/-- **Bounded lifetime.** A preview that survives a tick is younger than the TTL.

$$p \in \operatorname{tick}(T, t) \wedge t_0 \le t \Rightarrow t - p.t_0 < \mathit{ttl}$$ -/
theorem tick_lifetime (s : List Pv) (t : Nat) (p : Pv) (hp : p ∈ tick s t) (h0 : p.started ≤ t) :
    t - p.started < ttl := by
  have := (expired_stopped s t).1 p hp
  omega

/-- A tick is idempotent.

$$\operatorname{tick}(\operatorname{tick}(T, t), t) = \operatorname{tick}(T, t)$$ -/
theorem tick_idem (s : List Pv) (t : Nat) : tick (tick s t) t = tick s t := by
  simp [tick, List.filter_filter]

/-- **A stop kills only what the console recorded.** Every process group in the kill list is a table entry, and
an id that is not in the table kills nothing.

$$\operatorname{own}(T, i) \subseteq T, \qquad (\forall p \in T,\ p.\mathit{id} \ne i) \Rightarrow \operatorname{own}(T, i) = [\,]$$ -/
theorem stop_only_own (s : List Pv) (i : String) :
    (∀ p ∈ own s i, p ∈ s) ∧ ((∀ p ∈ s, p.id ≠ i) → own s i = []) := by
  refine ⟨fun p hp => (List.mem_filter.mp hp).1, fun h => ?_⟩
  unfold own
  rw [List.filter_eq_nil_iff]
  intro p hp
  have := h p hp
  simp [this]

/-- A stop splits the table into what stays and what is killed.

$$\operatorname{own}(T, i) \mathbin{+\!\!+} \operatorname{stop}(T, i) \sim T \ \text{(a permutation)}$$ -/
theorem stop_partition (s : List Pv) (i : String) : (own s i ++ stop s i).Perm s := by
  unfold stop own
  have := List.filter_append_perm (fun p : Pv => p.id == i) s
  simpa [Function.comp_def, bne] using this

/-- **Expiry kills only table entries too.**

$$\operatorname{expired}(T, t) \subseteq T$$ -/
theorem expired_sub (s : List Pv) (t : Nat) : ∀ p ∈ expired s t, p ∈ s :=
  fun _ hp => (List.mem_filter.mp hp).1

/-- **A failure removes only table entries.**

$$\operatorname{fail}(T, i) \subseteq T, \qquad (\forall p \in T,\ p.\mathit{id} \ne i) \Rightarrow \operatorname{fail}(T, i) = T$$ -/
theorem fail_only_own (s : List Pv) (i : String) :
    (∀ p ∈ fail s i, p ∈ s) ∧ ((∀ p ∈ s, p.id ≠ i) → fail s i = s) := by
  refine ⟨fun p hp => (List.mem_filter.mp hp).1, fun h => ?_⟩
  unfold fail stop
  rw [List.filter_eq_self]
  intro p hp
  simp [h p hp]

/-- **The lifetime bound.** With a tick every `tickPeriod` ms, some tick falls in the 30 s window that starts at
a preview's deadline; with `expired_stopped` the preview is gone at most 30 s after its 60 minutes.

$$\tau \le d \Rightarrow \exists k:\ d \le \tau + k \cdot 30000 < d + 30000$$ -/
theorem tick_within_period (d τ : Nat) (h : τ ≤ d) :
    ∃ k, d ≤ τ + k * tickPeriod ∧ τ + k * tickPeriod < d + tickPeriod := by
  unfold tickPeriod
  exact ⟨(d - τ + 29999) / 30000, by omega, by omega⟩

/-- **Reap kills exactly the table and empties it.**

$$\operatorname{reap}(T) = ([\,], T)$$ -/
theorem reap_all (s : List Pv) : (reap s).1 = [] ∧ (reap s).2 = s := ⟨rfl, rfl⟩

/-! ## The owner link: where it may be written -/

/-- Every place the console could write the one-time owner link.

$$\mathrm{Sink} = \mathrm{tty} \mid \mathrm{stdout} \mid \mathrm{stderr} \mid \mathrm{file} \mid \mathrm{log} \mid \mathrm{eventStore}$$ -/
inductive Sink where
  | tty | stdout | stderr | file | log | eventStore
deriving Repr, DecidableEq

/-- The link may go to a sink iff it is the controlling terminal (a process's stdout can be a file any agent reads).
Stated limit (INFERRED): `tty` means a terminal exists, not that it is the user's; a same-UID process can allocate a
pseudo-terminal and read the link there.

$$\operatorname{linkSink}(s) \iff s = \mathrm{tty}$$ -/
def linkSink (s : Sink) : Bool := s == .tty

/-- What the console does with the link: write it to the terminal when it has one, else print no link (the user asks
for one with the `owner-link` command, which itself needs a terminal).

$$\operatorname{linkPlan}(t) = \begin{cases}\mathrm{some}(\mathrm{tty}) & t\\ \bot & \neg t\end{cases}$$ -/
def linkPlan (hasTty : Bool) : Option Sink := if hasTty then some .tty else none

/-- **The link is allowed only on the terminal.**

$$\operatorname{linkSink}(s) = \mathrm{true} \iff s = \mathrm{tty}$$ -/
theorem linkSink_iff (s : Sink) : linkSink s = true ↔ s = .tty := by
  cases s <;> simp [linkSink]

/-- **No file sink.** The link is never written to a file (so not to a redirected stdout, a log, or the event store).

$$\operatorname{linkSink}(\mathrm{file}) = \mathrm{false}$$ -/
theorem no_file_sink : linkSink .file = false := rfl

/-- **No non-terminal sink.** Stdout, stderr, a file, a log and the event store are all refused.

$$s \ne \mathrm{tty} \Rightarrow \operatorname{linkSink}(s) = \mathrm{false}$$ -/
theorem no_nontty_sink (s : Sink) (h : s ≠ .tty) : linkSink s = false := by
  cases s <;> simp_all [linkSink]

/-- **The plan only chooses an allowed sink,** and only when there is a terminal.

$$\operatorname{linkPlan}(t) = \mathrm{some}(s) \Rightarrow \operatorname{linkSink}(s) \wedge t$$ -/
theorem linkPlan_ok (t : Bool) (s : Sink) (h : linkPlan t = some s) : linkSink s = true ∧ t = true := by
  cases t <;> simp_all [linkPlan, linkSink]

/-- With no terminal the console prints no link.

$$\operatorname{linkPlan}(\mathrm{false}) = \bot$$ -/
theorem linkPlan_no_tty : linkPlan false = none := rfl

/-! ## Re-issuing the link -/

/-- The least time between two owner links (ms): one per minute, so a process of the same user that signals the console
cannot keep invalidating the link the user has not opened yet.

$$\mathit{gap} = 60000$$ -/
def reissueGap : Nat := 60000

/-- May a new owner link be issued at `now`, the last having been issued at `last` (none yet: yes).

$$\operatorname{mayReissue}(\mathit{last}, \mathit{now}) = \begin{cases} \mathrm{true} & \mathit{last} = \bot\\ \mathit{last} + \mathit{gap} \le \mathit{now} & \text{otherwise}\end{cases}$$ -/
def mayReissue (last : Option Nat) (now : Nat) : Bool :=
  match last with
  | none => true
  | some l => decide (l + reissueGap ≤ now)

/-- **Two links are at least a minute apart.** A reissue is allowed only when the last link is at least `gap` old.

$$\operatorname{mayReissue}(\mathrm{some}(l), n) \Rightarrow l + \mathit{gap} \le n$$ -/
theorem mayReissue_gap (l n : Nat) (h : mayReissue (some l) n = true) : l + reissueGap ≤ n := by
  simpa [mayReissue] using h

/-- **A reissue inside the minute is refused.**

$$n < l + \mathit{gap} \Rightarrow \operatorname{mayReissue}(\mathrm{some}(l), n) = \mathrm{false}$$ -/
theorem mayReissue_refused (l n : Nat) (h : n < l + reissueGap) : mayReissue (some l) n = false := by
  simp [mayReissue]; omega

/-- **The first link is always allowed.**

$$\operatorname{mayReissue}(\bot, n) = \mathrm{true}$$ -/
theorem mayReissue_first (n : Nat) : mayReissue none n = true := rfl

end Fw.Console.Preview
