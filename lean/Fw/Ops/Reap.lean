import Lean.Data.Json
import Fw.Ops.Wire

/-!
# Which leftover processes `fw reap` names and how they are stopped (tasks `orphan-guard`, `reap-auto-stop`)
Every branch selects a row only if its cwd lies inside THIS repo, which the glue decides by device and inode (never by a path
string): `inRepo` (an ancestor of the cwd path is the repo root) and `wt` (the directory below this repo's `.claude/worktrees`).
A: it is of a named kind (`lspServe`, `console`), its cwd is in a non-live worktree of this repo (`goneWt`) and its inode
matches no live checkout, and its parent fits the kind (a lean-lsp-mcp of this repo for `lake serve`, init for a console).
B: it is a tool (lean, lake, fwcore, node, vitest, a playwright browser, or a `lake serve` also when orphaned) in a non-live
worktree of this repo. C: it is a tool inside this repo whose cwd is in no live checkout, with an ancestor selected by A or
B. Every branch refuses a row shielded off: the recorded console (`.fw-console/api.json`), everything below it, the stopper's
own process and its ancestors, pid <= 1. B and C also refuse a lean-lsp-mcp process, and every branch a row with an
unreadable cwd or a cwd inode of a live checkout.
The stop plan: read, check the identity again, TERM, wait the grace, read again, KILL the survivors whose (pid, start) is
unchanged, verify. A group is signalled only when every row of that group is selected, and every signal passes `guardOk`
against an explicit scope of pids.
-/
namespace Fw.Ops.Reap

/-- The kinds a selection carries: a `lake serve` of lean-lsp-mcp, a console-api, a tool of a removed worktree (branch B)
and a tool below a selected ancestor (branch C). -/
inductive Kind where
  | lspServe
  | console
  | removed
  | descendant
deriving Repr, DecidableEq

/-- The kind named by the glue's argv classification for branch A. -/
def kindOf : String → Option Kind
  | "lspServe" => some .lspServe
  | "console" => some .console
  | _ => none

/-- The wire name of a kind. -/
def Kind.name : Kind → String
  | .lspServe => "lspServe"
  | .console => "console"
  | .removed => "removed"
  | .descendant => "descendant"

/-- The argv kinds that branches B and C may select: a tool process (lean, lake, fwcore, node, vitest, a playwright browser)
or a `lake serve` (also when its parent is gone). A tool is never selected by its name, only through its cwd (B) or an
ancestor (C). -/
def isTool (k : String) : Bool := k == "tool" || k == "lspServe"

/-- One process-table row: pid, parent pid, process group, start time, cwd inode (`none`: unreadable), argv kind, and `wt`,
the id of the `.claude/worktrees/<id>` of this repo that the cwd path lies in (`none`: elsewhere), and `inRepo`, whether
the cwd path lies anywhere inside this repo (an ancestor with the device and inode of the repo root). -/
structure Row where
  pid : Nat
  ppid : Nat
  pgid : Nat
  start : Nat
  cwd : Option Nat
  kind : String
  wt : Option String := none
  inRepo : Bool := false
deriving Repr

/-- A lean-lsp-mcp process: pid and cwd inode (`none`: unreadable). -/
structure Mcp where
  pid : Nat
  cwd : Option Nat
deriving Repr

/-- The inputs: the rows (the whole process table), the inodes of the live checkouts' directories (this repo's worktree
list, nested Lean projects included), the lean-lsp-mcp processes, the recorded console `keep` as (pid, start second of its
record), the ids of the live worktrees and the pids the stopper itself must keep (its own process and ancestors). -/
structure Input where
  rows : List Row
  live : List Nat
  mcps : List Mcp
  keep : List (Nat × Nat)
  liveIds : List String := []
  protect : List Nat := []
deriving Repr

/-- A selected row: its identity (pid and start), its kind and whether the group may be signalled. -/
structure Sel where
  pid : Nat
  start : Nat
  kind : Kind
  group : Bool
deriving Repr, DecidableEq

/-- The recorded console: same pid and a record second within 60 s after the process start (a reused pid starts later). -/
def kept (i : Input) (r : Row) : Bool :=
  i.keep.any fun k => k.1 == r.pid && decide (r.start ≤ k.2) && decide (k.2 ≤ r.start + 60)

/-- The parent a kind requires: for `lspServe` a lean-lsp-mcp whose own cwd is in a live checkout (so only this repo's
servers count), for `console` init. -/
def parentOk (i : Input) : Kind → Row → Bool
  | .lspServe, r => i.mcps.any fun m => m.pid == r.ppid && m.cwd.any i.live.contains
  | .console, r => r.ppid == 1
  | _, _ => false

/-- A lean-lsp-mcp process (never stopped by B or C). -/
def isMcp (i : Input) (r : Row) : Bool := i.mcps.any fun m => m.pid == r.pid

/-- The ancestors of a row, nearest first, at most `n` steps (fuel makes a cycle in the table harmless). -/
def chain (i : Input) : Nat → Row → List Row
  | 0, _ => []
  | n + 1, r =>
    match i.rows.find? (fun p => p.pid == r.ppid) with
    | none => []
    | some p => if p.pid == r.pid then [] else p :: chain i n p

/-- No row of the chain (the row itself included) is the recorded console, and the row is not a protected pid (the stopper's own
process or ancestor). Every branch asks for it: the live console and everything below it is never selectable. -/
def shielded (i : Input) (r : Row) : Bool :=
  (r :: chain i i.rows.length r).all (fun a => !kept i a) && !i.protect.contains r.pid

/-- The cwd of the row lies inside a non-live `.claude/worktrees/<id>` of THIS repo. The glue sets `wt` only for a cwd path
that has an ancestor with the device and inode of this repo's `.claude/worktrees` directory, whose parent has the inode of
the repo root (never by comparing a path string). Every branch asks for it, so a process of another repo is never selected. -/
def goneWt (i : Input) (r : Row) : Bool :=
  r.inRepo &&
    match r.wt with
    | some id => !i.liveIds.contains id
    | none => false

/-- Branch A: the kind a row is selected as, or `none`. -/
def pick (i : Input) (r : Row) : Option Kind :=
  match kindOf r.kind, r.cwd with
  | some k, some c =>
    if !i.live.contains c && goneWt i r && parentOk i k r && decide (1 < r.pid) && shielded i r then some k else none
  | _, _ => none

/-- Branch B: a tool (or a `lake serve`, also an orphan) whose cwd is in a removed worktree of this repo. -/
def pickB (i : Input) (r : Row) : Option Kind :=
  match r.cwd with
  | some c =>
    if isTool r.kind && !i.live.contains c && goneWt i r && !isMcp i r && decide (1 < r.pid) && shielded i r
    then some .removed else none
  | none => none

/-- Selected by A or B. -/
def pickAB (i : Input) (r : Row) : Option Kind :=
  match pick i r with
  | some k => some k
  | none => pickB i r

/-- Branch C: a tool whose cwd lies inside this repo (a removed worktree, or a deleted directory below the repo root) and
with an ancestor selected by A or B (a dead owner). -/
def pickC (i : Input) (r : Row) : Option Kind :=
  match r.cwd with
  | some c =>
    if isTool r.kind && !i.live.contains c && r.inRepo && !isMcp i r && decide (1 < r.pid) && shielded i r &&
        (chain i i.rows.length r).any (fun a => (pickAB i a).isSome)
    then some .descendant else none
  | none => none

/-- The kind a row is selected as by any branch, or `none`. -/
def pickAny (i : Input) (r : Row) : Option Kind :=
  match pickAB i r with
  | some k => some k
  | none => pickC i r

/-- The rows to stop, with a group flag that is set only for a group leader. -/
def reap (i : Input) : List Sel :=
  i.rows.filterMap fun r => (pickAny i r).map fun k => ⟨r.pid, r.start, k, r.pgid == r.pid⟩

theorem goneWt_inRepo {i : Input} {r : Row} (h : goneWt i r = true) : r.inRepo = true := by
  unfold goneWt at h
  simp only [Bool.and_eq_true] at h
  exact h.1

theorem pick_some {i : Input} {r : Row} {k : Kind} (h : pick i r = some k) :
    kindOf r.kind = some k ∧ (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ goneWt i r = true ∧
      parentOk i k r = true ∧ 1 < r.pid ∧ shielded i r = true := by
  unfold pick at h
  split at h
  · rename_i k' c hk hc
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hb
      exact ⟨hk, ⟨c, hc, hb.1.1.1.1⟩, hb.1.1.1.2, hb.1.1.2, hb.1.2, hb.2⟩
    · cases h
  · cases h

theorem shielded_kept {i : Input} {r : Row} (h : shielded i r = true) : kept i r = false := by
  unfold shielded at h
  simp only [Bool.and_eq_true, List.all_eq_true, List.mem_cons] at h
  simpa using h.1 r (Or.inl rfl)

theorem shielded_protect {i : Input} {r : Row} (h : shielded i r = true) : i.protect.contains r.pid = false := by
  unfold shielded at h
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at h
  exact h.2

theorem pickB_some {i : Input} {r : Row} {k : Kind} (h : pickB i r = some k) :
    k = .removed ∧ isTool r.kind = true ∧ (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ goneWt i r = true ∧
      isMcp i r = false ∧ 1 < r.pid ∧ shielded i r = true := by
  unfold pickB at h
  split at h
  · rename_i c hc
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hb
      exact ⟨rfl, hb.1.1.1.1.1, ⟨c, hc, hb.1.1.1.1.2⟩, hb.1.1.1.2, hb.1.1.2, hb.1.2, hb.2⟩
    · cases h
  · cases h

theorem pickC_some {i : Input} {r : Row} {k : Kind} (h : pickC i r = some k) :
    k = .descendant ∧ isTool r.kind = true ∧ (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ r.inRepo = true ∧
      isMcp i r = false ∧ 1 < r.pid ∧ shielded i r = true ∧ ∃ a ∈ chain i i.rows.length r, (pickAB i a).isSome = true := by
  unfold pickC at h
  split at h
  · rename_i c hc
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq, List.any_eq_true] at hb
      exact ⟨rfl, hb.1.1.1.1.1.1, ⟨c, hc, hb.1.1.1.1.1.2⟩, hb.1.1.1.1.2, hb.1.1.1.2, hb.1.1.2, hb.1.2, hb.2⟩
    · cases h
  · cases h

/-- What every selection has in common, whichever branch: a readable cwd inode that no live checkout has, pid > 1, not the
recorded console, a kind that is named (A) or a tool (B, C), a cwd in a removed worktree of this repo and a shielded chain
(the last three after the branch-A fact: inside this repo, removed worktree unless a descendant, shielded). -/
theorem any_some {i : Input} {r : Row} {k : Kind} (h : pickAny i r = some k) :
    (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ 1 < r.pid ∧ kept i r = false ∧
      (kindOf r.kind = some k ∨ isTool r.kind = true) ∧ (k = .lspServe ∨ k = .console → pick i r = some k) ∧
      r.inRepo = true ∧ (k ≠ .descendant → goneWt i r = true) ∧ shielded i r = true := by
  unfold pickAny pickAB at h
  cases hp : pick i r with
  | some k' =>
    rw [hp] at h
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨hk, hc, hg, -, h1, hs⟩ := pick_some hp
    exact ⟨hc, h1, shielded_kept hs, Or.inl hk, fun _ => rfl, goneWt_inRepo hg, fun _ => hg, hs⟩
  | none =>
    rw [hp] at h
    cases hb : pickB i r with
    | some k' =>
      rw [hb] at h
      simp only [Option.some.injEq] at h
      subst h
      obtain ⟨hk, ht, hc, hg, -, h1, hs⟩ := pickB_some hb
      subst hk
      exact ⟨hc, h1, shielded_kept hs, Or.inr ht, (fun h' => by rcases h' with h' | h' <;> cases h'), goneWt_inRepo hg,
        fun _ => hg, hs⟩
    | none =>
      rw [hb] at h
      obtain ⟨hk, ht, hc, hg, -, h1, hs, -⟩ := pickC_some h
      subst hk
      exact ⟨hc, h1, shielded_kept hs, Or.inr ht, (fun h' => by rcases h' with h' | h' <;> cases h'), hg,
        fun hne => absurd rfl hne, hs⟩

theorem reap_mem {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, pickAny i r = some s.kind ∧ r.pid = s.pid ∧ r.start = s.start ∧ s.group = (r.pgid == r.pid) := by
  unfold reap at h
  rw [List.mem_filterMap] at h
  obtain ⟨r, hr, hs⟩ := h
  cases hp : pickAny i r with
  | none => simp [hp] at hs
  | some k =>
    simp [hp] at hs
    subst hs
    exact ⟨r, hr, hp, rfl, rfl, rfl⟩

/-- Selected: a cwd inode that no live checkout has, and a named kind (branch A) or a tool (B, C). -/
theorem selected_named_and_dead {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, (kindOf r.kind = some s.kind ∨ isTool r.kind = true) ∧ r.pid = s.pid ∧
      ∃ c, r.cwd = some c ∧ c ∉ i.live := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨⟨c, hc, hl⟩, -, -, hk, -⟩ := any_some hp
  exact ⟨r, hr, hk, hpid, c, hc, by simpa using hl⟩

/-- Row safety 1: a row whose cwd inode is a live checkout's (nested projects included) is not picked by any branch. -/
theorem live_row {i : Input} {r : Row} {c : Nat} (hc : r.cwd = some c) (hl : c ∈ i.live) : pickAny i r = none := by
  cases hp : pickAny i r with
  | none => rfl
  | some k =>
    obtain ⟨⟨c', hc', hl'⟩, -⟩ := any_some hp
    rw [hc] at hc'
    cases hc'
    simp [hl] at hl'

/-- Row safety 2: the recorded console (same pid, record second within 60 s of the start) is not picked. -/
theorem kept_row {i : Input} {r : Row} {k : Nat × Nat} (hk : k ∈ i.keep) (hp : k.1 = r.pid) (h1 : r.start ≤ k.2)
    (h2 : k.2 ≤ r.start + 60) : pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, -, hk', -⟩ := any_some hq
    have : kept i r = true := by
      unfold kept
      rw [List.any_eq_true]
      exact ⟨k, hk, by simp [hp, h1, h2]⟩
    rw [this] at hk'
    cases hk'

/-- Row safety 3: a row of pid 0 or 1 is not picked. -/
theorem init_row {i : Input} {r : Row} (h : r.pid ≤ 1) : pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, h1, -⟩ := any_some hq
    omega

/-- Row safety 4: a row that is neither of a named kind nor a tool is not picked. -/
theorem unnamed_row {i : Input} {r : Row} (h : kindOf r.kind = none) (ht : isTool r.kind = false) :
    pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, -, -, hk, -⟩ := any_some hq
    rcases hk with hk | hk
    · rw [h] at hk
      cases hk
    · rw [ht] at hk
      cases hk

/-- Row safety 5: a row with an unreadable cwd is not picked. -/
theorem unreadable_row {i : Input} {r : Row} (h : r.cwd = none) : pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    obtain ⟨⟨c, hc, -⟩, -⟩ := any_some hq
    rw [h] at hc
    cases hc

/-- Row safety 6: a lean-lsp-mcp process is not picked by B or C (its children of a removed worktree are, by their own
rows). Branch A needs a named kind, which an MCP launcher does not have. -/
theorem mcp_row {i : Input} {r : Row} (hm : isMcp i r = true) (hk : kindOf r.kind = none) : pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    unfold pickAny pickAB at hq
    cases hp : pick i r with
    | some k' =>
      obtain ⟨hk', -⟩ := pick_some hp
      rw [hk] at hk'
      cases hk'
    | none =>
      rw [hp] at hq
      cases hb : pickB i r with
      | some k' =>
        obtain ⟨-, -, -, -, hm', -⟩ := pickB_some hb
        rw [hm] at hm'
        cases hm'
      | none =>
        rw [hb] at hq
        obtain ⟨-, -, -, -, hm', -⟩ := pickC_some hq
        rw [hm] at hm'
        cases hm'

/-- A row that is not shielded (the recorded console in its chain, or a protected pid) is not picked by any branch. -/
theorem unshielded_row {i : Input} {r : Row} (hs : shielded i r = false) : pickAny i r = none := by
  cases hq : pickAny i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, -, -, -, -, -, -, hs'⟩ := any_some hq
    rw [hs] at hs'
    cases hs'

/-- Row safety 7: the recorded console or any of its descendants (its own fwcore) is not picked as a tool: when a row of
its chain is the recorded console, B and C refuse it. -/
theorem kept_ancestor_row {i : Input} {r a : Row}
    (ha : a ∈ r :: chain i i.rows.length r) (hk : kept i a = true) : pickAny i r = none := by
  apply unshielded_row
  unfold shielded
  cases hsh : (r :: chain i i.rows.length r).all (fun a => !kept i a) with
  | false => rfl
  | true =>
    have := (List.all_eq_true.1 hsh) a ha
    simp [hk] at this

/-- Row safety 8: a protected pid (the stopper's own process or an ancestor of it) is not picked as a tool. -/
theorem protect_row {i : Input} {r : Row} (hp : r.pid ∈ i.protect) :
    pickAny i r = none := by
  apply unshielded_row
  unfold shielded
  simp [hp]

/-- Branch B: a row picked as `removed` has a tool kind and a cwd path in a worktree id that is not live. -/
theorem removed_branch {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .removed) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ isTool r.kind = true ∧ ∃ id, r.wt = some id ∧ id ∉ i.liveIds := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  unfold pickAny pickAB at hp
  cases hq : pick i r with
  | some k' =>
    rw [hq] at hp
    have := pick_some hq
    have e : k' = .removed := by simpa using hp
    obtain ⟨-, -, -, hpa, -⟩ := this
    subst e
    simp [parentOk] at hpa
  | none =>
    rw [hq] at hp
    cases hb : pickB i r with
    | some k' =>
      obtain ⟨-, ht, -, hg, -⟩ := pickB_some hb
      unfold goneWt at hg
      cases hw : r.wt with
      | none => simp [hw] at hg
      | some id =>
        simp [hw] at hg
        exact ⟨r, hr, hpid, ht, id, hw, hg.2⟩
    | none =>
      rw [hb] at hp
      obtain ⟨hk', -⟩ := pickC_some hp
      cases hk'

/-- Branch C: a row picked as `descendant` has a tool kind and an ancestor selected by A or B (a dead owner). -/
theorem descendant_branch {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .descendant) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ isTool r.kind = true ∧ (∃ a ∈ chain i i.rows.length r, (pickAB i a).isSome = true) ∧
      r.inRepo = true := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  unfold pickAny at hp
  cases hq : pickAB i r with
  | some k' =>
    rw [hq] at hp
    have e : k' = .descendant := by simpa using hp
    subst e
    unfold pickAB at hq
    cases hp' : pick i r with
    | some k'' =>
      rw [hp'] at hq
      obtain ⟨-, -, -, hpa, -⟩ := pick_some hp'
      simp only [Option.some.injEq] at hq
      subst hq
      simp [parentOk] at hpa
    | none =>
      rw [hp'] at hq
      obtain ⟨hk', -⟩ := pickB_some hq
      cases hk'
  | none =>
    rw [hq] at hp
    obtain ⟨-, ht, -, hg, -, -, -, ha⟩ := pickC_some hp
    exact ⟨r, hr, hpid, ht, ha, hg⟩

/-- Per row, without a uniqueness hypothesis: a selection is exactly a picked row, and its group flag is set exactly
when that row is its own group leader (`pgid = pid`). -/
theorem group_iff {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, pickAny i r = some s.kind ∧ r.pid = s.pid ∧ (s.group = true ↔ r.pgid = r.pid) := by
  obtain ⟨r, hr, hp, hpid, -, hg⟩ := reap_mem h
  refine ⟨r, hr, hp, hpid, ?_⟩
  rw [hg]
  simp

/-- A process whose cwd inode is a live checkout's is never selected (corollary of `live_row`, with unique pids). -/
theorem live_never_selected {i : Input} {r : Row} (hr : r ∈ i.rows) {c : Nat} (hc : r.cwd = some c) (hl : c ∈ i.live)
    (hu : ∀ r' ∈ i.rows, r'.pid = r.pid → r' = r) : ∀ s ∈ reap i, s.pid ≠ r.pid := by
  intro s hs hpid
  obtain ⟨r', hr', hp, hpid', -, -⟩ := reap_mem hs
  have := hu r' hr' (hpid'.trans hpid)
  subst this
  rw [live_row hc hl] at hp
  cases hp

/-- A group signal is only for a group leader (`pgid = pid`). -/
theorem group_leader {i : Input} {s : Sel} (h : s ∈ reap i) (hg : s.group = true) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.pgid = r.pid := by
  obtain ⟨r, hr, -, hpid, hiff⟩ := group_iff h
  exact ⟨r, hr, hpid, hiff.1 hg⟩

/-- A `lake serve` row is selected only as a child of a lean-lsp-mcp process whose own cwd is in a live checkout. -/
theorem lsp_parent {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .lspServe) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ ∃ m ∈ i.mcps, m.pid = r.ppid ∧ ∃ c, m.cwd = some c ∧ c ∈ i.live := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  obtain ⟨-, -, -, -, hA, -⟩ := any_some hp
  obtain ⟨-, -, -, hpa, -⟩ := pick_some (hA (Or.inl rfl))
  simp only [parentOk, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at hpa
  obtain ⟨m, hm, hmp, hc⟩ := hpa
  rcases hmc : m.cwd with _ | c
  · simp [hmc] at hc
  · simp [hmc] at hc
    exact ⟨r, hr, hpid, m, hm, hmp, c, hmc, by simpa using hc⟩

/-- A console row is selected only when its parent is init (an orphan). -/
theorem console_orphan {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .console) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.ppid = 1 := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  obtain ⟨-, -, -, -, hA, -⟩ := any_some hp
  obtain ⟨-, -, -, hpa, -⟩ := pick_some (hA (Or.inr rfl))
  exact ⟨r, hr, hpid, by simpa [parentOk] using hpa⟩

/-- Neither init nor pid 0 is ever selected. -/
theorem not_init {i : Input} {s : Sel} (h : s ∈ reap i) : 1 < s.pid := by
  obtain ⟨r, -, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, h1, -⟩ := any_some hp
  omega

/-- Without a lean-lsp-mcp process no `lake serve` row is selected. -/
theorem no_mcp_no_lsp {i : Input} (hm : i.mcps = []) : ∀ s ∈ reap i, s.kind ≠ .lspServe := by
  intro s hs hk
  obtain ⟨r, -, hp, -, -, -⟩ := reap_mem hs
  rw [hk] at hp
  obtain ⟨-, -, -, -, hA, -⟩ := any_some hp
  obtain ⟨-, -, -, hpa, -⟩ := pick_some (hA (Or.inl rfl))
  simp [parentOk, hm] at hpa

/-- A `lake serve` row whose parent is no lean-lsp-mcp with a cwd in a live checkout (another repo's server) is not
picked by branch A. -/
theorem foreign_mcp {i : Input} {r : Row} (hk : kindOf r.kind = some .lspServe)
    (hf : ∀ m ∈ i.mcps, m.pid = r.ppid → ∀ c, m.cwd = some c → c ∉ i.live) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨hk', -, -, hpa, -⟩ := pick_some hq
    rw [hk] at hk'
    cases hk'
    simp only [parentOk, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at hpa
    obtain ⟨m, hm, hmp, hc⟩ := hpa
    rcases hmc : m.cwd with _ | c
    · simp [hmc] at hc
    · simp [hmc] at hc
      exact absurd (by simpa using hc) (hf m hm hmp c hmc)

/-- More recorded consoles never add a branch-A selection. -/
theorem antitone_keep {i : Input} {extra : List (Nat × Nat)} {r : Row} {k : Kind}
    (h : pick { i with keep := i.keep ++ extra } r = some k) : pick i r = some k := by
  obtain ⟨hk, ⟨c, hc, hl⟩, hg, hpa, h1, hs⟩ := pick_some h
  have hch : ∀ n r', chain { i with keep := i.keep ++ extra } n r' = chain i n r' := by
    intro n
    induction n with
    | zero => intro r'; rfl
    | succ n ih => intro r'; simp [chain, ih]
  have hs' : shielded i r = true := by
    unfold shielded at hs ⊢
    simp only [hch, Bool.and_eq_true, List.all_eq_true] at hs ⊢
    refine ⟨fun a ha => ?_, hs.2⟩
    have := hs.1 a ha
    simp only [kept, List.any_append, Bool.not_eq_true', Bool.or_eq_false_iff] at this ⊢
    simpa using this.1
  unfold pick
  rw [hk, hc]
  simp only [parentOk] at hpa ⊢
  simp [hpa, h1, hs']
  exact ⟨by simpa using hl, hg⟩

/-- The reason printed for a kind. -/
def Kind.reason : Kind → String
  | .lspServe => "lake serve of lean-lsp-mcp, cwd in no live checkout"
  | .console => "orphan console-api, cwd in no live checkout"
  | .removed => "tool whose cwd is in a removed worktree"
  | .descendant => "tool below a selected process"

/-! ## The stop plan -/

/-- One process to signal: identity (pid, start second) and whether the whole group is signalled. -/
structure Target where
  pid : Nat
  start : Nat
  group : Bool
deriving Repr, DecidableEq

/-- The row has the identity of a selection. -/
def inSel (sel : List Sel) (r : Row) : Bool := sel.any fun s => s.pid == r.pid && s.start == r.start

/-- A group is signalled only when it was a leader and every row of that group is selected. -/
def groupSafe (i : Input) (sel : List Sel) (s : Sel) : Bool :=
  s.group && i.rows.all fun r => r.pgid != s.pid || inSel sel r

/-- The TERM targets: one per selected row. -/
def plan (i : Input) : List Target :=
  (reap i).map fun s => ⟨s.pid, s.start, groupSafe i (reap i) s⟩

/-- The target's identity is still present in a fresh read. -/
def present (fresh : List Row) (t : Target) : Bool := fresh.any fun r => r.pid == t.pid && r.start == t.start

/-- The row has the identity of a planned target. -/
def inPlan (planned : List Target) (r : Row) : Bool := planned.any fun p => p.pid == r.pid && p.start == r.start

/-- The KILL targets after the grace: the planned targets whose (pid, start) is unchanged in the fresh read; a group stays a
group signal only while every row now in that group is a planned identity. -/
def killPlan (planned : List Target) (fresh : List Row) : List Target :=
  (planned.filter (present fresh)).map fun t =>
    { t with group := t.group && fresh.all fun r => r.pgid != t.pid || inPlan planned r }

/-- The planned targets still present after KILL (the verify step): non-empty means a survivor to report. -/
def left (planned : List Target) (fresh : List Row) : List Target := planned.filter (present fresh)

/-- The steps of a stop, in order. -/
inductive Stage where
  | read
  | term
  | wait
  | reread
  | kill
  | verify
deriving Repr, DecidableEq

/-- The wire name of a stage. -/
def Stage.name : Stage → String
  | .read => "read"
  | .term => "term"
  | .wait => "wait"
  | .reread => "reread"
  | .kill => "kill"
  | .verify => "verify"

/-- The script of a stop. -/
def script : List Stage := [.read, .term, .wait, .reread, .kill, .verify]

/-- The grace between TERM and the second read, in milliseconds. -/
def graceMs : Nat := 3000

/-- The wait after KILL before the verify read, in milliseconds. -/
def killWaitMs : Nat := 1000

theorem plan_length (i : Input) : (plan i).length = (reap i).length := by simp [plan]

theorem reap_length_le (i : Input) : (reap i).length ≤ i.rows.length := by
  unfold reap
  exact List.length_filterMap_le _ _

/-- The plan is finite and no longer than the process table. -/
theorem plan_finite (i : Input) : (plan i).length ≤ i.rows.length := by
  rw [plan_length]
  exact reap_length_le i

/-- Every TERM target is a selected identity. -/
theorem plan_sel {i : Input} {t : Target} (h : t ∈ plan i) : ∃ s ∈ reap i, s.pid = t.pid ∧ s.start = t.start := by
  unfold plan at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  exact ⟨s, hs, rfl, rfl⟩

/-- A TERM group signal reaches only selected rows: every row of that process group is a selected identity. -/
theorem plan_group_inside {i : Input} {t : Target} (h : t ∈ plan i) (hg : t.group = true) :
    ∀ r ∈ i.rows, r.pgid = t.pid → ∃ s ∈ reap i, s.pid = r.pid ∧ s.start = r.start := by
  unfold plan at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  intro r hr hpg
  simp only [groupSafe, Bool.and_eq_true, List.all_eq_true] at hg
  have := hg.2 r hr
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, inSel, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  rcases this with h1 | ⟨s', hs', h2, h3⟩
  · exact absurd hpg h1
  · exact ⟨s', hs', h2, h3⟩

/-- Every KILL target was planned (so TERMed) and has the identity (pid, start) it was planned with, present in the fresh
read: a pid whose start time changed (reuse) is never in it. -/
theorem kill_present {planned : List Target} {fresh : List Row} {t : Target} (h : t ∈ killPlan planned fresh) :
    (∃ p ∈ planned, p.pid = t.pid ∧ p.start = t.start) ∧ ∃ r ∈ fresh, r.pid = t.pid ∧ r.start = t.start := by
  unfold killPlan at h
  rw [List.mem_map] at h
  obtain ⟨p, hp, rfl⟩ := h
  rw [List.mem_filter] at hp
  refine ⟨⟨p, hp.1, rfl, rfl⟩, ?_⟩
  have := hp.2
  simp only [present, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  obtain ⟨r, hr, h1, h2⟩ := this
  exact ⟨r, hr, h1, h2⟩

/-- Pid reuse guard: when every fresh row of the planned pid has another start time, the pid is not in the KILL plan. -/
theorem reuse_guard {planned : List Target} {fresh : List Row} {p : Target}
    (hr : ∀ r ∈ fresh, r.pid = p.pid → r.start ≠ p.start) :
    ∀ t ∈ killPlan planned fresh, t.pid = p.pid → t.start ≠ p.start := by
  intro t ht hpid hst
  obtain ⟨-, r, hrf, h1, h2⟩ := kill_present ht
  exact hr r hrf (h1.trans hpid) (h2.trans hst)

/-- A KILL group signal reaches only planned identities. -/
theorem kill_group_inside {planned : List Target} {fresh : List Row} {t : Target} (h : t ∈ killPlan planned fresh)
    (hg : t.group = true) : ∀ r ∈ fresh, r.pgid = t.pid → ∃ p ∈ planned, p.pid = r.pid ∧ p.start = r.start := by
  unfold killPlan at h
  rw [List.mem_map] at h
  obtain ⟨p, hp, rfl⟩ := h
  intro r hr hpg
  simp only [Bool.and_eq_true, List.all_eq_true] at hg
  have := hg.2 r hr
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, inPlan, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  rcases this with h1 | ⟨p', hp', h2, h3⟩
  · exact absurd hpg h1
  · exact ⟨p', hp', h2, h3⟩

/-- The KILL plan of the planned targets of a selection holds only selected identities (a row outside the selection is
never signalled, by TERM or by KILL). -/
theorem kill_in_selection {i : Input} {fresh : List Row} {t : Target} (h : t ∈ killPlan (plan i) fresh) :
    ∃ s ∈ reap i, s.pid = t.pid ∧ s.start = t.start := by
  obtain ⟨⟨p, hp, h1, h2⟩, -⟩ := kill_present h
  obtain ⟨s, hs, h3, h4⟩ := plan_sel hp
  exact ⟨s, hs, h3.trans h1, h4.trans h2⟩

/-- The KILL plan is never longer than the TERM plan. -/
theorem kill_finite (planned : List Target) (fresh : List Row) : (killPlan planned fresh).length ≤ planned.length := by
  unfold killPlan
  rw [List.length_map]
  exact List.length_filter_le _ _

/-- The script has six steps, so a stop is finite. -/
theorem script_finite : script.length = 6 := rfl

/-- TERM is step 1, the wait is step 2, the second read step 3, and KILL step 4 and the only one: KILL comes after TERM
and the grace. -/
theorem kill_after_term_and_grace :
    script[1]? = some .term ∧ script[2]? = some .wait ∧ script[3]? = some .reread ∧ script[4]? = some .kill ∧
      script.count .kill = 1 ∧ script.count .term = 1 := by
  decide

/-- The grace is positive. -/
theorem grace_positive : 0 < graceMs := by decide

/-- The cwd of a `goneWt` row names a worktree id of this repo that is not live. -/
theorem goneWt_some {i : Input} {r : Row} (h : goneWt i r = true) : ∃ id, r.wt = some id ∧ id ∉ i.liveIds := by
  unfold goneWt at h
  cases hw : r.wt with
  | none => simp [hw] at h
  | some id =>
    simp [hw] at h
    exact ⟨id, rfl, h.2⟩

/-- Repo identity, every branch: a selected row has a cwd path inside this repo (an ancestor with the device and inode of
the repo root); A and B rows lie in a non-live worktree of it (`console_in_removed_wt`, `lsp_in_removed_wt`,
`removed_branch`), C rows below an owner that does. -/
theorem in_repo {i : Input} {s : Sel} (h : s ∈ reap i) : ∃ r ∈ i.rows, r.pid = s.pid ∧ r.inRepo = true := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, -, -, -, -, hi, -⟩ := any_some hp
  exact ⟨r, hr, hpid, hi⟩

/-- Repo identity, branch A (console): a console is selected only when its cwd is inside a non-live worktree of this repo
(never because it is merely an orphan whose cwd is outside the live checkouts, as the console of another repo is). -/
theorem console_in_removed_wt {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .console) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.ppid = 1 ∧ ∃ id, r.wt = some id ∧ id ∉ i.liveIds := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  obtain ⟨-, -, -, -, hA, -, hg, -⟩ := any_some hp
  obtain ⟨-, -, -, hpa, -⟩ := pick_some (hA (Or.inr rfl))
  obtain ⟨id, hw, hn⟩ := goneWt_some (hg (by simp))
  exact ⟨r, hr, hpid, by simpa [parentOk] using hpa, id, hw, hn⟩

/-- Repo identity, branch A (lake serve): a `lake serve` picked by A lies in a non-live worktree of this repo. -/
theorem lsp_in_removed_wt {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .lspServe) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ ∃ id, r.wt = some id ∧ id ∉ i.liveIds := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  rw [hk] at hp
  obtain ⟨-, -, -, -, -, -, hg, -⟩ := any_some hp
  obtain ⟨id, hw, hn⟩ := goneWt_some (hg (by simp))
  exact ⟨r, hr, hpid, id, hw, hn⟩

/-- The live console never selected: a row that is the recorded console, or has it among its ancestors, is never in the
selection, for any `keep` list and any branch (unique pids). -/
theorem live_console_never_selected {i : Input} {r a : Row} (hr : r ∈ i.rows)
    (ha : a ∈ r :: chain i i.rows.length r) (hk : kept i a = true) (hu : ∀ r' ∈ i.rows, r'.pid = r.pid → r' = r) :
    ∀ s ∈ reap i, s.pid ≠ r.pid := by
  intro s hs hpid
  obtain ⟨r', hr', hp, hpid', -, -⟩ := reap_mem hs
  have := hu r' hr' (hpid'.trans hpid)
  subst this
  rw [kept_ancestor_row ha hk] at hp
  cases hp

/-- A chain of a recorded console: the descendants of the recorded console are shielded off, so a console of the repo and its
fwcore are never selected whatever `top` was. -/
theorem recorded_console_shields {i : Input} {r : Row} {k : Nat × Nat} (hk : k ∈ i.keep) (hp : k.1 = r.pid)
    (h1 : r.start ≤ k.2) (h2 : k.2 ≤ r.start + 60) : shielded i r = false := by
  unfold shielded
  have : kept i r = true := by
    unfold kept
    rw [List.any_eq_true]
    exact ⟨k, hk, by simp [hp, h1, h2]⟩
  simp [this]

/-! ## The signal scope -/

/-- A signal to `t` is allowed: the pid is above init and in `scope`, and a group signal only when every row of that process
group (in the table just read) is in `scope`. The executor asks this before every `kill(2)`. -/
def guardOk (scope : List Nat) (rows : List Row) (t : Target) : Bool :=
  decide (1 < t.pid) && scope.contains t.pid && (!t.group || rows.all fun r => r.pgid != t.pid || scope.contains r.pid)

/-- No signal outside the scope: an allowed signal is for a pid in the scope above init, and an allowed group signal reaches
only rows in the scope. -/
theorem guard_scope {scope : List Nat} {rows : List Row} {t : Target} (h : guardOk scope rows t = true) :
    1 < t.pid ∧ t.pid ∈ scope ∧ (t.group = true → ∀ r ∈ rows, r.pgid = t.pid → r.pid ∈ scope) := by
  unfold guardOk at h
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.contains_iff_mem, Bool.or_eq_true, Bool.not_eq_true',
    List.all_eq_true, bne_iff_ne, ne_eq] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨h1, h2, fun hg r hr hpg => ?_⟩
  rcases h3 with h3 | h3
  · rw [hg] at h3
    cases h3
  · rcases h3 r hr with h4 | h4
    · exact absurd hpg h4
    · exact h4

/-- The TERM targets after the fresh read right before TERM: the planned identities still present with an unchanged start,
a group staying a group only while every row now in it is planned (the same filter as the KILL step). -/
def termPlan (planned : List Target) (fresh : List Row) : List Target := killPlan planned fresh

/-- Every TERM target is a planned identity and is present with the same (pid, start) in the read right before TERM: a pid
whose start changed since the gather (reuse) is never TERMed. -/
theorem term_present {planned : List Target} {fresh : List Row} {t : Target} (h : t ∈ termPlan planned fresh) :
    (∃ p ∈ planned, p.pid = t.pid ∧ p.start = t.start) ∧ ∃ r ∈ fresh, r.pid = t.pid ∧ r.start = t.start :=
  kill_present h

/-- The TERM group signal reaches only planned identities of the pre-TERM read. -/
theorem term_group_inside {planned : List Target} {fresh : List Row} {t : Target} (h : t ∈ termPlan planned fresh)
    (hg : t.group = true) : ∀ r ∈ fresh, r.pgid = t.pid → ∃ p ∈ planned, p.pid = r.pid ∧ p.start = r.start :=
  kill_group_inside h hg


end Fw.Ops.Reap

namespace Fw.Wire.Reap
open Lean Fw.Ops.Reap Fw.Wire.Ops

/-- One row from JSON: `pid`, `ppid`, `pgid`, `start`, `cwd`? (inode or null), `kind`, `wt`? (worktree id or null), `inRepo`? (bool). -/
def rowOf (j : Json) : Except String Row := do
  pure ⟨← nat j "pid", ← nat j "ppid", ← nat j "pgid", ← nat j "start", ← optN j "cwd", ← str j "kind", ← optS j "wt", ← boolD j "inRepo" false⟩

/-- The input of the selection ops from JSON. -/
def inputOf (req : Json) : Except String Input := do
  let rows ← (← arr req "rows").toList.mapM rowOf
  let live ← (← arr req "live").toList.mapM (asNat "live")
  let mcps ← (← arrD req "mcps").mapM fun j => do pure (Mcp.mk (← nat j "pid") (← optN j "cwd"))
  let keep ← (← arrD req "keep").mapM fun j => do pure ((← nat j "pid"), (← nat j "at"))
  let liveIds ← (← arrD req "liveIds").mapM (asStr "liveIds")
  let protect ← (← arrD req "protect").mapM (asNat "protect")
  pure ⟨rows, live, mcps, keep, liveIds, protect⟩

/-- A selected row as JSON. -/
def selJson (s : Sel) : Json :=
  Json.mkObj [("pid", toJson s.pid), ("start", toJson s.start), ("kind", .str s.kind.name), ("group", .bool s.group),
    ("reason", .str s.kind.reason)]

/-- A stop target as JSON. -/
def targetJson (t : Target) : Json :=
  Json.mkObj [("pid", toJson t.pid), ("start", toJson t.start), ("group", .bool t.group)]

/-- A stop target from JSON. -/
def targetOf (j : Json) : Except String Target := do
  pure ⟨← nat j "pid", ← nat j "start", ← boolD j "group" false⟩

/-- `ops.lspReap`: `rows` [row], `live` [inode], `mcps`? [{pid, cwd?}], `keep`? [{pid, at}], `liveIds`? [id], `protect`? [pid] → `selected`
[{pid, start, kind, group, reason}], `count`. -/
def opLspReap (req : Json) : Except String Reply := do
  let sel := reap (← inputOf req)
  pure [("count", toJson sel.length), ("selected", .arr (sel.toArray.map selJson))]

/-- `ops.reapPlan`: the request of `ops.lspReap` → `count`, `selected`, `targets` [{pid, start, group}] (the TERM
targets), `graceMs`, `killWaitMs`, `script` [stage name]. -/
def opReapPlan (req : Json) : Except String Reply := do
  let i ← inputOf req
  let sel := reap i
  pure [("count", toJson sel.length), ("selected", .arr (sel.toArray.map selJson)),
    ("targets", .arr ((plan i).toArray.map targetJson)), ("graceMs", toJson graceMs), ("killWaitMs", toJson killWaitMs),
    ("script", .arr (script.toArray.map fun s => .str s.name))]

/-- `ops.reapKill`: `planned` [{pid, start, group}], `rows` [row] (the fresh read) → `kill` [{pid, start, group}]. -/
def opReapKill (req : Json) : Except String Reply := do
  let planned ← (← arr req "planned").toList.mapM targetOf
  let fresh ← (← arr req "rows").toList.mapM rowOf
  pure [("kill", .arr ((killPlan planned fresh).toArray.map targetJson))]

/-- `ops.reapVerify`: `planned`, `rows` (the read after KILL) → `left` [{pid, start, group}], `gone` (count). -/
def opReapVerify (req : Json) : Except String Reply := do
  let planned ← (← arr req "planned").toList.mapM targetOf
  let fresh ← (← arr req "rows").toList.mapM rowOf
  let l := left planned fresh
  pure [("left", .arr (l.toArray.map targetJson)), ("gone", toJson (planned.length - l.length))]

/-- `ops.reapTerm`: `planned`, `rows` (the read right before TERM) → `term` [{pid, start, group}]. -/
def opReapTerm (req : Json) : Except String Reply := do
  let planned ← (← arr req "planned").toList.mapM targetOf
  let fresh ← (← arr req "rows").toList.mapM rowOf
  pure [("term", .arr ((termPlan planned fresh).toArray.map targetJson))]

/-- `ops.reapGuard`: `scope` [pid], `rows` (the table just read), `target` {pid, start, group} → `allowed`. -/
def opReapGuard (req : Json) : Except String Reply := do
  let scope ← (← arr req "scope").toList.mapM (asNat "scope")
  let rows ← (← arr req "rows").toList.mapM rowOf
  let t ← targetOf (← field req "target")
  pure [("allowed", .bool (guardOk scope rows t))]

/-- The ops of this module. -/
def ops : List String := ["ops.lspReap", "ops.reapPlan", "ops.reapKill", "ops.reapVerify", "ops.reapTerm", "ops.reapGuard"]

/-- Dispatch (`none` when the op is not one of this module's). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.lspReap" => some (opLspReap req)
  | "ops.reapPlan" => some (opReapPlan req)
  | "ops.reapKill" => some (opReapKill req)
  | "ops.reapVerify" => some (opReapVerify req)
  | "ops.reapTerm" => some (opReapTerm req)
  | "ops.reapGuard" => some (opReapGuard req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("rows", .arr #[]), ("live", .arr #[]), ("planned", .arr #[]), ("scope", .arr #[]), ("target", Json.mkObj [("pid", toJson 2), ("start", toJson 0)])])).isSome

end Fw.Wire.Reap
