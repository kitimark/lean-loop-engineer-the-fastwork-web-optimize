import Lean.Data.Json
import Fw.Ops.Wire
import Fw.Sup.Adapt

/-!
# Which leftover processes `fw reap` names and how they are stopped (tasks `orphan-guard`, `reap-auto-stop`)
Every branch selects a row only if its cwd lies inside THIS repo, which the glue decides by device and inode (never by a path
string): `inRepo` (an ancestor of the cwd path is the repo root) and `wt` (the directory below this repo's `.claude/worktrees`).
A: it is of a named kind (`lspServe`, `console`), its cwd is in a non-live worktree of this repo (`goneWt`) and its inode
matches no live checkout, and its parent fits the kind (a lean-lsp-mcp of this repo for `lake serve`, init for a console).
B: it is a tool (lean, lake, fwcore, node, vitest, a playwright browser, or a `lake serve` also when orphaned) in a non-live
worktree of this repo. C: it is a tool inside this repo whose cwd is in no live checkout, with an ancestor selected by A or
B. Every branch refuses a row shielded off: the recorded console (`.fw-console/api.json`), everything below it, the stopper's
own process and its ancestors, pid <= 1. B and C also refuse a lean-lsp-mcp process, every branch a row with an unreadable
cwd, and A, B and C a cwd inode of a live checkout. D: a CPU-quiet lean-lsp-mcp server stack in a worktree with no live
session. No branch takes a row with a serena process in its chain.
The stop plan: read, check the identity again, TERM, wait the grace, read again, KILL the survivors whose (pid, start) is
unchanged, verify. A group is signalled only when every row of that group is selected, and every signal passes `guardOk`
against an explicit scope of pids.
-/
namespace Fw.Ops.Reap

/-- The kinds a selection carries: a `lake serve` of lean-lsp-mcp, a console-api, a tool of a removed worktree (branch B),
a tool below a selected ancestor (branch C) and a process of an idle lean-lsp-mcp server stack (branch D). -/
inductive Kind where
  | lspServe
  | console
  | removed
  | descendant
  | mcpIdle
  | orphanLoop
  | simBooted
deriving Repr, DecidableEq

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
  | .mcpIdle => "mcpIdle"
  | .orphanLoop => "orphanLoop"
  | .simBooted => "simBooted"

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

/-- The CPU time one process (pid, start) used so far, in centiseconds. -/
structure Use where
  pid : Nat
  start : Nat
  cpu : Nat
deriving Repr

/-- The CPU baseline of one process: its identity (pid, start), the second the baseline was set and the CPU time then
(centiseconds). -/
structure Base where
  pid : Nat
  start : Nat
  since : Nat
  cpu : Nat
deriving Repr, DecidableEq

/-- A worktree lock: the worktree id and the pid its reason names (`claude agent <id> (pid P start ...)`), `none` when the
reason names no pid. -/
structure Lock where
  id : String
  holder : Option Nat
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

structure LoopFact where
  pid : Nat
  start : Nat
  awaits : String
  callLive : Bool
  inode : String
deriving Repr

structure Waiter where
  pid : Nat
  start : Nat
  wt : String
  writes : String
  inode : String
deriving Repr

structure InputD extends Input where
  now : Nat := 0
  uses : List Use := []
  bases : List Base := []
  locks : List Lock := []
  mcpWt : List (Nat × String) := []
  loops : List LoopFact := []
  waiters : List Waiter := []
  simIdleSince : Option Nat := none
  simAcquired : Option Nat := none
  ownSims : List (Nat × Nat) := []
  simHolders : Nat := 0
  legacyHeld : Bool := true
  auto : Bool := false
deriving Repr

instance : Coe InputD Input := ⟨InputD.toInput⟩

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

/-- Row safety 1: a row whose cwd inode is a live checkout's (nested projects included) is not picked by A, B or C (D picks
only an idle MCP stack, `never_live_mcp_parent`). -/
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

/-- A process whose cwd inode is a live checkout's is never selected by A, B or C (corollary of `live_row`, with unique
pids). -/
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
  | .console => "orphan console-api, cwd in a removed worktree of this repo"
  | .removed => "tool whose cwd is in a removed worktree"
  | .descendant => "tool below a selected process"
  | .mcpIdle => "lean-lsp-mcp server stack idle (CPU quiet) in a worktree with no live agent"
  | .orphanLoop => "until-loop shell that outlived its tool call, no live writer of the awaited file"
  | .simBooted => "Simulator booted by a sim slot run that has released, no sim slot held"

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


/-! ## Branch D: an idle lean-lsp-mcp server stack in a worktree with no live session -/

/-- The quiet window: a baseline must be at least this many seconds old before its stack counts as idle. -/
def idleSec : Nat := 1200

/-- The CPU a quiet row may use since its baseline, in centiseconds. -/
def cpuTolCs : Nat := 300

/-- A `lake serve` whose parent is a lean-lsp-mcp process: the root of an MCP server stack. -/
def mcpRoot (i : InputD) (R : Row) : Bool := R.kind == "lspServe" && i.mcps.any fun m => m.pid == R.ppid

/-- The root of the MCP stack a row is in: the nearest row of its chain (the row itself included) that is an MCP root. -/
def rootOf (i : InputD) (r : Row) : Option Row := (r :: chain i i.rows.length r).find? (mcpRoot i)

/-- The row `x` is `R` or lies below it. -/
def below (i : InputD) (R x : Row) : Bool := (x :: chain i i.rows.length x).any fun a => a.pid == R.pid

/-- The baseline of the row's identity (pid and start). -/
def baseOf (i : InputD) (r : Row) : Option Base := i.bases.find? fun b => b.pid == r.pid && b.start == r.start

/-- The CPU time read for the row's identity (pid and start), `none` when unread. -/
def cpuOf (i : InputD) (r : Row) : Option Nat :=
  (i.uses.find? fun u => u.pid == r.pid && u.start == r.start).map (·.cpu)

/-- The row used at most `cpuTolCs` of CPU since a baseline set at least `idleSec` ago; an unread CPU time or no baseline is
not quiet. -/
def quiet (i : InputD) (r : Row) : Bool :=
  match cpuOf i r, baseOf i r with
  | some c, some b => decide (c ≤ b.cpu + cpuTolCs) && decide (b.since + idleSec ≤ i.now)
  | _, _ => false

/-- Every row of the stack rooted at `R` is quiet. -/
def stackIdle (i : InputD) (R : Row) : Bool := (i.rows.filter (below i R)).all (quiet i)

/-- A lock is live when its holder pid is in the process table, or when its reason names no pid. -/
def lockLive (i : InputD) (l : Lock) : Bool :=
  match l.holder with
  | none => true
  | some p => i.rows.any fun r => r.pid == p

/-- A live session works in the worktree `id`: a live lock holds it, or a lean-lsp-mcp process was started there. -/
def sessionLive (i : InputD) (id : String) : Bool :=
  i.locks.any (fun l => l.id == id && lockLive i l) || i.mcpWt.any (fun m => m.2 == id)

/-- Branch D: a tool (or the `lake serve` root) of an idle MCP stack whose root shares its worktree, which has no live
session. -/
def pickD (i : InputD) (r : Row) : Option Kind :=
  match r.cwd, r.wt, rootOf i r with
  | some _, some id, some R =>
    if isTool r.kind && r.inRepo && R.wt == some id && !sessionLive i id && stackIdle i R && !isMcp i r &&
        decide (1 < r.pid) && shielded i r
    then some .mcpIdle else none
  | _, _, _ => none

/-- No row of the chain (the row itself included) is a serena process. -/
def serenaFree (i : InputD) (r : Row) : Bool := (r :: chain i i.rows.length r).all fun a => a.kind != "serena"

/-- The kind a row is selected as by A, B or C, else by D; never for a row with a serena process in its chain. -/
def pickAll (i : InputD) (r : Row) : Option Kind :=
  if serenaFree i r then
    match pickAny i r with
    | some k => some k
    | none => pickD i r
  else none

/-- The rows to stop by every branch, with a group flag that is set only for a group leader. -/
def reapAll (i : InputD) : List Sel :=
  i.rows.filterMap fun r => (pickAll i r).map fun k => ⟨r.pid, r.start, k, r.pgid == r.pid⟩

/-- The TERM targets of every branch: one per selected row. -/
def planAll (i : InputD) : List Target :=
  (reapAll i).map fun s => ⟨s.pid, s.start, groupSafe i (reapAll i) s⟩

/-- The baselines for the next run, one per row of an MCP stack with a read CPU time: the old baseline while the row stays
within `cpuTolCs` of it, else a new one at `now`. -/
def rebase (i : InputD) : List Base :=
  i.rows.filterMap fun r =>
    if (rootOf i r).isSome then
      (cpuOf i r).map fun c =>
        match baseOf i r with
        | some b => if c ≤ b.cpu + cpuTolCs then b else ⟨r.pid, r.start, i.now, c⟩
        | none => ⟨r.pid, r.start, i.now, c⟩
    else none

theorem rootOf_some {i : InputD} {r R : Row} (h : rootOf i r = some R) :
    R ∈ r :: chain i i.rows.length r ∧ mcpRoot i R = true :=
  ⟨List.mem_of_find?_eq_some h, List.find?_some h⟩

theorem pickD_some {i : InputD} {r : Row} {k : Kind} (h : pickD i r = some k) :
    k = .mcpIdle ∧ (∃ c, r.cwd = some c) ∧ ∃ id R, r.wt = some id ∧ rootOf i r = some R ∧ R.wt = some id ∧
      isTool r.kind = true ∧ r.inRepo = true ∧ sessionLive i id = false ∧ stackIdle i R = true ∧ isMcp i r = false ∧
      1 < r.pid ∧ shielded i r = true := by
  unfold pickD at h
  split at h
  · rename_i c id R hc hw hR
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq, beq_iff_eq] at hb
      exact ⟨rfl, ⟨c, hc⟩, id, R, hw, hR, hb.1.1.1.1.1.2, hb.1.1.1.1.1.1.1, hb.1.1.1.1.1.1.2, hb.1.1.1.1.2,
        hb.1.1.1.2, hb.1.1.2, hb.1.2, hb.2⟩
    · cases h
  · cases h

/-- Quiet, spelled out: a read CPU time, a baseline of the same identity, at most `cpuTolCs` used since it, and the baseline
at least `idleSec` old. -/
theorem quiet_iff {i : InputD} {r : Row} :
    quiet i r = true ↔ ∃ c b, cpuOf i r = some c ∧ baseOf i r = some b ∧ c ≤ b.cpu + cpuTolCs ∧ b.since + idleSec ≤ i.now := by
  unfold quiet
  cases hc : cpuOf i r with
  | none => simp
  | some c =>
    cases hb : baseOf i r with
    | none => simp
    | some b => simp

/-- A row picked by D is quiet: every row of its stack is, and the row lies in its own stack. -/
theorem idle_row {i : InputD} {r : Row} {k : Kind} (hr : r ∈ i.rows) (h : pickD i r = some k) : quiet i r = true := by
  obtain ⟨-, -, id, R, -, hR, -, -, -, -, hs, -⟩ := pickD_some h
  have hm := (rootOf_some hR).1
  have hb : below i R r = true := by
    unfold below
    rw [List.any_eq_true]
    exact ⟨R, hm, by simp⟩
  unfold stackIdle at hs
  rw [List.all_eq_true] at hs
  exact hs r (List.mem_filter.2 ⟨hr, hb⟩)

/-- A worker whose worktree has a live session (a live lock, or a lean-lsp-mcp started there) is not picked by D. -/
theorem live_session_row {i : InputD} {r : Row} {id : String} (hw : r.wt = some id) (hs : sessionLive i id = true) :
    pickD i r = none := by
  cases hq : pickD i r with
  | none => rfl
  | some k =>
    obtain ⟨-, -, id', -, hw', -, -, -, -, hs', -⟩ := pickD_some hq
    rw [hw] at hw'
    cases hw'
    rw [hs] at hs'
    cases hs'

/-- A row outside every worktree (the main checkout, a land worktree, another directory) is not picked by D. -/
theorem main_row {i : InputD} {r : Row} (hw : r.wt = none) : pickD i r = none := by
  unfold pickD
  rw [hw]
  split <;> simp_all

/-- A row of a stack with a row that is not quiet (CPU used, a young or missing baseline, an unread CPU time) is not picked
by D. -/
theorem busy_stack_row {i : InputD} {r R : Row} (hR : rootOf i r = some R) (hs : stackIdle i R = false) :
    pickD i r = none := by
  cases hq : pickD i r with
  | none => rfl
  | some k =>
    obtain ⟨-, -, -, R', -, hR', -, -, -, -, hs', -⟩ := pickD_some hq
    rw [hR] at hR'
    cases hR'
    rw [hs] at hs'
    cases hs'

/-- A row with no MCP root in its chain (a serena-lean server, a `lake serve` of an editor) is not picked by D. -/
theorem no_root_row {i : InputD} {r : Row} (h : rootOf i r = none) : pickD i r = none := by
  unfold pickD
  rw [h]
  split <;> simp_all

/-- Branch A, B and C never name the kind of D. -/
theorem pickAny_ne_idle {i : Input} {r : Row} : pickAny i r ≠ some .mcpIdle := by
  intro h
  unfold pickAny pickAB at h
  cases hp : pick i r with
  | some k =>
    rw [hp] at h
    obtain ⟨hk, -⟩ := pick_some hp
    simp only [Option.some.injEq] at h
    subst h
    simp [kindOf] at hk
    split at hk <;> simp_all
  | none =>
    rw [hp] at h
    cases hb : pickB i r with
    | some k =>
      rw [hb] at h
      obtain ⟨hk, -⟩ := pickB_some hb
      simp only [Option.some.injEq] at h
      rw [h] at hk
      cases hk
    | none =>
      rw [hb] at h
      obtain ⟨hk, -⟩ := pickC_some h
      cases hk

/-- A row with a serena process in its chain (itself included) is never picked, by any branch. -/
theorem serena_row {i : InputD} {r a : Row} (ha : a ∈ r :: chain i i.rows.length r) (hk : a.kind = "serena") :
    pickAll i r = none := by
  have : serenaFree i r = false := by
    unfold serenaFree
    cases h : (r :: chain i i.rows.length r).all (fun a => a.kind != "serena") with
    | false => rfl
    | true =>
      have := (List.all_eq_true.1 h) a ha
      simp [hk] at this
  unfold pickAll
  rw [this]
  rfl

/-- A selection of A, B or C keeps its kind and all the guarantees of `pickAny`; any other selection is D's. -/
theorem all_some {i : InputD} {r : Row} {k : Kind} (h : pickAll i r = some k) :
    (k ≠ .mcpIdle ∧ pickAny i r = some k) ∨ (k = .mcpIdle ∧ pickAny i r = none ∧ pickD i r = some .mcpIdle) := by
  unfold pickAll at h
  split at h
  · cases hp : pickAny i r with
    | some k' =>
      rw [hp] at h
      cases h
      exact Or.inl ⟨fun he => pickAny_ne_idle (he ▸ hp), rfl⟩
    | none =>
      rw [hp] at h
      obtain ⟨hk, -⟩ := pickD_some h
      subst hk
      exact Or.inr ⟨rfl, rfl, h⟩
  · cases h

/-- What every selection of every branch has in common: a readable cwd, pid > 1 and a shielded chain (not the recorded
console nor below it, not a protected pid). -/
theorem all_safe {i : InputD} {r : Row} {k : Kind} (h : pickAll i r = some k) :
    (∃ c, r.cwd = some c) ∧ 1 < r.pid ∧ shielded i r = true ∧ r.inRepo = true := by
  rcases all_some h with ⟨-, hp⟩ | ⟨-, -, hd⟩
  · obtain ⟨⟨c, hc, -⟩, h1, -, -, -, hin, -, hs⟩ := any_some hp
    exact ⟨⟨c, hc⟩, h1, hs, hin⟩
  · obtain ⟨-, hc, -, -, -, -, -, -, hin, -, -, -, h1, hs⟩ := pickD_some hd
    exact ⟨hc, h1, hs, hin⟩

theorem reapAll_mem {i : InputD} {s : Sel} (h : s ∈ reapAll i) :
    ∃ r ∈ i.rows, pickAll i r = some s.kind ∧ r.pid = s.pid ∧ r.start = s.start ∧ s.group = (r.pgid == r.pid) := by
  unfold reapAll at h
  rw [List.mem_filterMap] at h
  obtain ⟨r, hr, hs⟩ := h
  cases hp : pickAll i r with
  | none => simp [hp] at hs
  | some k =>
    simp [hp] at hs
    subst hs
    exact ⟨r, hr, hp, rfl, rfl, rfl⟩

/-- Neither init nor pid 0 is ever selected, by any branch. -/
theorem all_not_init {i : InputD} {s : Sel} (h : s ∈ reapAll i) : 1 < s.pid := by
  obtain ⟨r, -, hp, hpid, -⟩ := reapAll_mem h
  obtain ⟨-, h1, -⟩ := all_safe hp
  omega

/-- The recorded console and its descendants, and the stopper's own chain, are never selected, by any branch. -/
theorem all_shielded {i : InputD} {s : Sel} (h : s ∈ reapAll i) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ shielded i r = true := by
  obtain ⟨r, hr, hp, hpid, -⟩ := reapAll_mem h
  exact ⟨r, hr, hpid, (all_safe hp).2.2.1⟩

/-- A selection of D is a quiet tool of an MCP stack whose root shares its worktree `id`; no lean-lsp-mcp process (its MCP
parent included) was started in that worktree and no live lock holds it: a worker whose MCP parent belongs to a live session
there is never selected. -/
theorem never_live_mcp_parent {i : InputD} {s : Sel} (h : s ∈ reapAll i) (hk : s.kind = .mcpIdle) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ quiet i r = true ∧ ∃ id, r.wt = some id ∧
      (∃ R ∈ r :: chain i i.rows.length r, mcpRoot i R = true ∧ R.wt = some id) ∧
      (∀ m ∈ i.mcpWt, m.2 ≠ id) ∧ ∀ l ∈ i.locks, l.id = id → lockLive i l = false := by
  obtain ⟨r, hr, hp, hpid, -⟩ := reapAll_mem h
  rw [hk] at hp
  rcases all_some hp with ⟨hne, -⟩ | ⟨-, -, hd⟩
  · exact absurd rfl hne
  · obtain ⟨-, -, id, R, hw, hR, hRw, -, -, hs, -⟩ := pickD_some hd
    refine ⟨r, hr, hpid, idle_row hr hd, id, hw, ⟨R, (rootOf_some hR).1, (rootOf_some hR).2, hRw⟩, ?_, ?_⟩
    · intro m hm hmw
      have : sessionLive i id = true := by
        unfold sessionLive
        simp only [Bool.or_eq_true, List.any_eq_true]
        exact Or.inr ⟨m, hm, by simp [hmw]⟩
      rw [this] at hs
      cases hs
    · intro l hl hid
      cases hll : lockLive i l with
      | false => rfl
      | true =>
        have : sessionLive i id = true := by
          unfold sessionLive
          simp only [Bool.or_eq_true, List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
          exact Or.inl ⟨l, hl, hid, hll⟩
        rw [this] at hs
        cases hs

/-- Without a lean-lsp-mcp process nothing is selected as an idle MCP stack. -/
theorem no_mcp_no_idle {i : InputD} (hm : i.mcps = []) : ∀ s ∈ reapAll i, s.kind ≠ .mcpIdle := by
  intro s hs hk
  obtain ⟨r, -, -, -, -, -, ⟨R, -, hR, -⟩, -⟩ := never_live_mcp_parent hs hk
  simp [mcpRoot, hm] at hR

/-- Every TERM target of every branch is a selected identity. -/
theorem planAll_sel {i : InputD} {t : Target} (h : t ∈ planAll i) :
    ∃ s ∈ reapAll i, s.pid = t.pid ∧ s.start = t.start := by
  unfold planAll at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  exact ⟨s, hs, rfl, rfl⟩

/-- A TERM group signal of every branch reaches only selected rows. -/
theorem planAll_group_inside {i : InputD} {t : Target} (h : t ∈ planAll i) (hg : t.group = true) :
    ∀ r ∈ i.rows, r.pgid = t.pid → ∃ s ∈ reapAll i, s.pid = r.pid ∧ s.start = r.start := by
  unfold planAll at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  intro r hr hpg
  simp only [groupSafe, Bool.and_eq_true, List.all_eq_true] at hg
  have := hg.2 r hr
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, inSel, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  rcases this with h1 | ⟨s', hs', h2, h3⟩
  · exact absurd hpg h1
  · exact ⟨s', hs', h2, h3⟩

/-- A quiet row keeps its baseline, so its quiet window keeps growing. -/
theorem rebase_quiet {i : InputD} {r : Row} {c : Nat} {b : Base} (hr : r ∈ i.rows) (hR : (rootOf i r).isSome = true)
    (hc : cpuOf i r = some c) (hb : baseOf i r = some b) (hq : c ≤ b.cpu + cpuTolCs) : b ∈ rebase i := by
  unfold rebase
  rw [List.mem_filterMap]
  exact ⟨r, hr, by simp [hR, hc, hb, hq]⟩

/-- A row that used more than `cpuTolCs` since its baseline gets a new baseline at `now`: its quiet window starts again. -/
theorem rebase_busy {i : InputD} {r : Row} {c : Nat} {b : Base} (hr : r ∈ i.rows) (hR : (rootOf i r).isSome = true)
    (hc : cpuOf i r = some c) (hb : baseOf i r = some b) (hq : b.cpu + cpuTolCs < c) :
    (⟨r.pid, r.start, i.now, c⟩ : Base) ∈ rebase i := by
  unfold rebase
  rw [List.mem_filterMap]
  exact ⟨r, hr, by simp [hR, hc, hb, Nat.not_le.2 hq]⟩

/-- A row that used more than `cpuTolCs` since its baseline is not quiet. -/
theorem busy_not_quiet {i : InputD} {r : Row} {c : Nat} {b : Base} (hc : cpuOf i r = some c) (hb : baseOf i r = some b)
    (hq : b.cpu + cpuTolCs < c) : quiet i r = false := by
  unfold quiet
  rw [hc, hb]
  simp [Nat.not_le.2 hq]

private def gR (pid ppid pgid : Nat) (kind : String) (wt : String := "w") : Row :=
  { pid, ppid, pgid, start := 9, cwd := some 30, kind, wt := some wt, inRepo := true }

private def gIn : InputD :=
  { rows := [gR 500 400 500 "lspServe", gR 501 500 500 "tool", gR 502 501 502 "tool"],
    live := [1, 30], mcps := [⟨400, some 1⟩], keep := [], liveIds := ["w"], now := 5000,
    uses := [⟨500, 9, 10⟩, ⟨501, 9, 600⟩, ⟨502, 9, 900⟩],
    bases := [⟨500, 9, 1000, 10⟩, ⟨501, 9, 1000, 590⟩, ⟨502, 9, 1000, 700⟩] }

#guard (reapAll gIn).map (·.pid) == [500, 501, 502]
#guard (planAll gIn).map (·.group) == [true, false, true]
#guard (reapAll { gIn with locks := [⟨"w", some 400⟩], rows := gIn.rows ++ [gR 400 1 400 "other" "x"] }).isEmpty
#guard (reapAll { gIn with locks := [⟨"w", some 77⟩] }).length == 3
#guard (reapAll { gIn with locks := [⟨"w", none⟩] }).isEmpty
#guard (reapAll { gIn with mcpWt := [(400, "w")] }).isEmpty
#guard (reapAll { gIn with mcpWt := [(400, "v")] }).length == 3
#guard (reapAll { gIn with now := 2000 }).isEmpty
#guard (reapAll { gIn with bases := [⟨500, 9, 1000, 10⟩, ⟨501, 9, 1000, 590⟩, ⟨502, 9, 1000, 500⟩] }).isEmpty
#guard (reapAll { gIn with uses := [⟨500, 9, 10⟩, ⟨501, 9, 600⟩] }).isEmpty
#guard (reapAll { gIn with rows := gIn.rows.map fun r => { r with wt := none } }).isEmpty
#guard (reapAll { gIn with rows := gIn.rows.map fun r => if r.pid == 500 then { r with kind := "serena" } else r }).isEmpty
#guard quiet { gIn with uses := [⟨501, 9, 890⟩] } (gR 501 500 500 "tool") &&
  !quiet { gIn with uses := [⟨501, 9, 891⟩] } (gR 501 500 500 "tool")
#guard rebase { gIn with uses := [⟨500, 9, 10⟩, ⟨501, 9, 600⟩, ⟨502, 9, 1001⟩] } ==
  [⟨500, 9, 1000, 10⟩, ⟨501, 9, 1000, 590⟩, ⟨502, 9, 5000, 1001⟩]
#guard rebase { gIn with bases := [] } == [⟨500, 9, 5000, 10⟩, ⟨501, 9, 5000, 600⟩, ⟨502, 9, 5000, 900⟩]
#guard sessionLive { gIn with locks := [⟨"w", some 500⟩] } "w" && !sessionLive gIn "w"


def orphanMinSec : Nat := 60

def ownSim (i : InputD) (r : Row) : Bool := i.ownSims.any fun p => p.1 == r.pid && p.2 == r.start

def simVerdict (i : InputD) (s : Nat) : Fw.Sup.Adapt.SimAct :=
  Fw.Sup.Adapt.simAction {} i.now
    (List.replicate i.simHolders ⟨"", "", Fw.Sup.Adapt.Kind.sim, 0, i.now + 1, 0, 0⟩) true i.legacyHeld (some s)

def waiterLive (i : InputD) (w : Waiter) : Bool := i.rows.any fun r => r.pid == w.pid && r.start == w.start

def loopOf (i : InputD) (r : Row) : Option LoopFact := i.loops.find? fun l => l.pid == r.pid && l.start == r.start

def hasInode (s : String) : Bool := s != ""

def sameFile (l : LoopFact) (w : Waiter) : Bool :=
  if hasInode l.inode && hasInode w.inode then l.inode == w.inode else w.writes == l.awaits

def writerLive (i : InputD) (r : Row) (l : LoopFact) : Bool :=
  match r.wt with
  | some a => i.waiters.any fun w => w.wt == a && sameFile l w && waiterLive i w
  | none => false

def awaitChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '_' || c == '/' || c == '-'

def awaitOk (p : String) : Bool := p.startsWith "/" && p.toList.all awaitChar

def pickE (i : InputD) (r : Row) : Option Kind :=
  match r.cwd, r.wt, loopOf i r with
  | some _, some _, some l =>
    if r.kind == "untilLoop" && r.inRepo && !l.callLive && awaitOk l.awaits && !writerLive i r l &&
        decide (r.start + orphanMinSec ≤ i.now) &&
        decide (1 < r.pid) && shielded i r
    then some .orphanLoop else none
  | _, _, _ => none

def pickF (i : InputD) (r : Row) : Option Kind :=
  match i.simAcquired, i.simIdleSince with
  | some a, some s =>
    if r.kind == "simDevice" && ownSim i r && decide (a ≤ r.start) && decide (r.start ≤ s) && simVerdict i s == .shutdown &&
        decide (1 < r.pid) && shielded i r
    then some .simBooted else none
  | _, _ => none

def pickW (i : InputD) (r : Row) : Option Kind :=
  if serenaFree i r then
    match pickE i r with
    | some k => some k
    | none => pickF i r
  else none

def pickOne (i : InputD) (r : Row) : Option Kind :=
  match pickAll i r with
  | some k => some k
  | none => pickW i r

def reapOne(i : InputD) : List Sel :=
  i.rows.filterMap fun r => (pickOne i r).map fun k => ⟨r.pid, r.start, k, r.pgid == r.pid⟩

def autoKinds : List Kind := [.lspServe, .console, .removed, .descendant, .mcpIdle]

def planSel (i : InputD) : List Sel := (reapOne i).filter fun s => !i.auto || decide (s.kind ∈ autoKinds)

def planOne (i : InputD) : List Target :=
  (planSel i).map fun s => ⟨s.pid, s.start, groupSafe i (planSel i) s⟩

def held (i : InputD) : List Sel := (reapOne i).filter fun s => s.kind == .orphanLoop

private def gE : InputD :=
  { rows := [⟨2846, 1, 2846, 1000, some 5, "untilLoop", some "w", true⟩, ⟨3100, 1, 3100, 1000, some 5, "simDevice", none, false⟩],
    live := [1], mcps := [], keep := [], liveIds := ["w"], now := 1800,
    loops := [⟨2846, 1000, "/tmp/mwm-wait.log", false, ""⟩], simIdleSince := some 1200, simAcquired := some 900,
    ownSims := [(3100, 1000)], legacyHeld := false }

#guard (reapOne gE).map (·.kind) == [.orphanLoop, .simBooted]
#guard (planOne gE).map (·.pid) == [2846, 3100]
#guard (planOne { gE with auto := true }).isEmpty
#guard (held { gE with auto := true }).map (·.pid) == [2846]
#guard (reapOne { gE with legacyHeld := true }).map (·.pid) == [2846]
#guard (reapOne { gE with loops := [⟨2846, 1000, "out.log", false, ""⟩] }).map (·.pid) == [3100]
#guard (reapOne { gE with loops := [⟨2846, 1000, "$HOME/x", false, ""⟩] }).map (·.pid) == [3100]

theorem pickE_some {i : InputD} {r : Row} {k : Kind} (h : pickE i r = some k) :
    k = .orphanLoop ∧ (∃ c, r.cwd = some c) ∧ (∃ a, r.wt = some a) ∧
      (∃ l, loopOf i r = some l ∧ r.kind = "untilLoop" ∧ r.inRepo = true ∧ l.callLive = false ∧ awaitOk l.awaits = true ∧
        writerLive i r l = false) ∧
      r.start + orphanMinSec ≤ i.now ∧ 1 < r.pid ∧ shielded i r = true := by
  unfold pickE at h
  split at h
  · rename_i c a l hc ha hp
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', beq_iff_eq, decide_eq_true_eq] at hb
      obtain ⟨⟨⟨⟨⟨⟨⟨hk, hin⟩, hcl⟩, hok⟩, hw⟩, hn⟩, h1⟩, hs⟩ := hb
      exact ⟨rfl, ⟨c, hc⟩, ⟨a, ha⟩, ⟨l, hp, hk, hin, hcl, hok, hw⟩, hn, h1, hs⟩
    · cases h
  · cases h

theorem pickF_some {i : InputD} {r : Row} {k : Kind} (h : pickF i r = some k) :
    k = .simBooted ∧ r.kind = "simDevice" ∧ ownSim i r = true ∧
      (∃ a s, i.simAcquired = some a ∧ i.simIdleSince = some s ∧ a ≤ r.start ∧ r.start ≤ s ∧ simVerdict i s = .shutdown) ∧
      1 < r.pid ∧ shielded i r = true := by
  unfold pickF at h
  split at h
  · rename_i a s ha hs
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hb
      obtain ⟨⟨⟨⟨⟨⟨hk, ho⟩, ha'⟩, hst⟩, hv⟩, h1⟩, hsh⟩ := hb
      exact ⟨rfl, hk, ho, ⟨a, s, ha, hs, ha', hst, hv⟩, h1, hsh⟩
    · cases h
  · cases h

theorem live_writer_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l) (h : writerLive i r l = true) :
    pickE i r = none := by
  unfold pickE
  rw [hl]
  split
  · rename_i heq
    cases heq
    simp [h]
  · rfl

theorem writer_identity {i : InputD} {r : Row} {l : LoopFact} (h : writerLive i r l = true) :
    ∃ w ∈ i.waiters, r.wt = some w.wt ∧ sameFile l w = true ∧ ∃ x ∈ i.rows, x.pid = w.pid ∧ x.start = w.start := by
  unfold writerLive at h
  split at h
  · rename_i a hw
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq, waiterLive] at h
    obtain ⟨w, hw', ⟨hwa, hwp⟩, x, hx, hxp⟩ := h
    exact ⟨w, hw', by rw [hw, hwa], hwp, x, hx, hxp.1, hxp.2⟩
  · cases h

/-- A waiter that holds the awaited file open under another name (a symlinked directory, a hard link) is a writer: the
inodes decide when both are known. -/
theorem writer_inode_match {i : InputD} {r : Row} {l : LoopFact} {w : Waiter} (hw : w ∈ i.waiters) (a : String)
    (hwt : r.wt = some a) (hwa : w.wt = a) (hlive : waiterLive i w = true)
    (hi : hasInode w.inode = true) (heq : l.inode = w.inode) : writerLive i r l = true := by
  unfold writerLive
  rw [hwt]
  simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
  exact ⟨w, hw, ⟨hwa, by simp [sameFile, hi, heq]⟩, hlive⟩

/-- Two known inodes that differ are two files: equal path strings do not make a writer (the file was replaced). -/
theorem sameFile_inode_differs {l : LoopFact} {w : Waiter} (hl : hasInode l.inode = true) (hi : hasInode w.inode = true)
    (hne : l.inode ≠ w.inode) : sameFile l w = false := by
  simp [sameFile, hl, hi, hne]

/-- With an inode unknown (the awaited file does not exist yet) the path string decides. -/
theorem sameFile_path_fallback {l : LoopFact} {w : Waiter} (h : hasInode l.inode = false) :
    sameFile l w = (w.writes == l.awaits) := by
  simp [sameFile, h]

theorem call_live_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l) (h : l.callLive = true) :
    pickE i r = none := by
  unfold pickE
  rw [hl]
  split
  · rename_i heq
    cases heq
    simp [h]
  · rfl

theorem young_loop_kept {i : InputD} {r : Row} (h : i.now < r.start + orphanMinSec) : pickE i r = none := by
  unfold pickE
  split
  · simp; omega
  · rfl

theorem not_loop_kept {i : InputD} {r : Row} (h : r.kind ≠ "untilLoop") : pickE i r = none := by
  unfold pickE
  split <;> simp [h]

theorem orphan_selected {i : InputD} {r : Row} {c : Nat} {a : String} {l : LoopFact} (hc : r.cwd = some c) (ha : r.wt = some a)
    (hl : loopOf i r = some l) (hk : r.kind = "untilLoop") (hin : r.inRepo = true) (hcl : l.callLive = false)
    (hok : awaitOk l.awaits = true) (hw : writerLive i r l = false) (hn : r.start + orphanMinSec ≤ i.now) (h1 : 1 < r.pid)
    (hs : shielded i r = true) : pickE i r = some .orphanLoop := by
  unfold pickE
  rw [hc, ha, hl]
  simp [hk, hin, hcl, hok, hw, hn, h1, hs]

theorem await_unsafe_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l) (h : awaitOk l.awaits = false) :
    pickE i r = none := by
  unfold pickE
  rw [hl]
  split
  · rename_i heq
    cases heq
    simp [h]
  · rfl

theorem relative_await_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l)
    (h : l.awaits.startsWith "/" = false) : pickE i r = none :=
  await_unsafe_kept hl (by simp [awaitOk, h])

/-- Any character outside the allowlist (letters, digits, dot, underscore, slash, hyphen) keeps the loop. -/
theorem await_char_kept {i : InputD} {r : Row} {l : LoopFact} {c : Char} (hl : loopOf i r = some l)
    (hc : awaitChar c = false) (hm : c ∈ l.awaits.toList) : pickE i r = none :=
  await_unsafe_kept hl (by
    simp only [awaitOk, Bool.and_eq_false_iff, List.all_eq_false]
    exact Or.inr ⟨c, hm, by simp [hc]⟩)

theorem dollar_await_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l)
    (h : '$' ∈ l.awaits.toList) : pickE i r = none :=
  await_char_kept hl (by decide) h

theorem backtick_await_kept {i : InputD} {r : Row} {l : LoopFact} (hl : loopOf i r = some l)
    (h : '`' ∈ l.awaits.toList) : pickE i r = none :=
  await_char_kept hl (by decide) h

#guard !awaitOk "out.log" && !awaitOk "$HOME/x" && !awaitOk "/tmp/$X/y" && awaitOk "/tmp/mwm-wait.log"
#guard !awaitOk "/tmp/`x`.log" && !awaitOk "/tmp/*.log" && !awaitOk "/tmp/?.log" && !awaitOk "/tmp/[a].log" &&
  !awaitOk "~/x" && !awaitOk "/tmp/a b" && awaitOk "/tmp/a-b_c.1/x"

theorem sim_selected {i : InputD} {r : Row} {a s : Nat} (ha : i.simAcquired = some a) (hs : i.simIdleSince = some s)
    (hk : r.kind = "simDevice") (ho : ownSim i r = true) (hl : a ≤ r.start) (hb : r.start ≤ s) (hv : simVerdict i s = .shutdown)
    (h1 : 1 < r.pid) (hsh : shielded i r = true) : pickF i r = some .simBooted := by
  unfold pickF
  rw [ha, hs]
  simp [hk, ho, hl, hb, hv, h1, hsh]

theorem simVerdict_held {i : InputD} (s : Nat) (h : i.simHolders ≠ 0) : simVerdict i s = .keep := by
  apply Fw.Sup.Adapt.sim_keep_under_holder
  obtain ⟨n, hn⟩ := Nat.exists_eq_succ_of_ne_zero h
  rw [hn]
  simp [Fw.Sup.Adapt.simHeld, Fw.Sup.Adapt.prune, Fw.Sup.Adapt.live, List.replicate_succ]

theorem sim_held_kept {i : InputD} {r : Row} (h : i.simHolders ≠ 0) : pickF i r = none := by
  unfold pickF
  split
  · simp [simVerdict_held _ h]
  · rfl

theorem sim_legacy_kept {i : InputD} {r : Row} (h : i.legacyHeld = true) : pickF i r = none := by
  unfold pickF
  split
  · have (s : Nat) : simVerdict i s = .keep := by
      unfold simVerdict
      rw [h]
      exact Fw.Sup.Adapt.sim_keep_under_legacy _ _ _ _
    simp [this]
  · rfl

theorem sim_after_release_kept {i : InputD} {r : Row} {s : Nat} (hs : i.simIdleSince = some s) (h : s < r.start) :
    pickF i r = none := by
  unfold pickF
  rw [hs]
  rcases hA : i.simAcquired with _ | a
  · rfl
  · simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq]
    split
    · rename_i hb; omega
    · rfl

theorem sim_before_acquire_kept {i : InputD} {r : Row} {a : Nat} (ha : i.simAcquired = some a) (h : r.start < a) :
    pickF i r = none := by
  unfold pickF
  rw [ha]
  rcases hS : i.simIdleSince with _ | s
  · rfl
  · simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq]
    split
    · rename_i hb; omega
    · rfl

theorem sim_not_own_kept {i : InputD} {r : Row} (h : ownSim i r = false) : pickF i r = none := by
  unfold pickF
  split <;> simp [h]

theorem sim_no_release_kept {i : InputD} {r : Row} (h : i.simIdleSince = none) : pickF i r = none := by
  unfold pickF
  rw [h]
  rcases i.simAcquired with _ | a <;> rfl

theorem sim_no_acquire_kept {i : InputD} {r : Row} (h : i.simAcquired = none) : pickF i r = none := by
  unfold pickF
  rw [h]

theorem sim_idle_kept {i : InputD} {r : Row} {s : Nat} (hs : i.simIdleSince = some s) (h : i.now < s + 600) :
    pickF i r = none := by
  unfold pickF
  rw [hs]
  have : simVerdict i s = .keep := by
    unfold simVerdict
    exact Fw.Sup.Adapt.sim_keep_within_idle _ _ _ _ _ h
  rcases i.simAcquired with _ | a <;> simp [this]

theorem pickAny_ne_w {i : Input} {r : Row} {k : Kind} (h : pickAny i r = some k) : k ≠ .orphanLoop ∧ k ≠ .simBooted := by
  unfold pickAny pickAB at h
  cases hp : pick i r with
  | some k' =>
    rw [hp] at h
    obtain ⟨hk, -⟩ := pick_some hp
    simp only [Option.some.injEq] at h
    subst h
    simp [kindOf] at hk
    split at hk <;> (cases hk; try exact ⟨by decide, by decide⟩)
  | none =>
    rw [hp] at h
    cases hb : pickB i r with
    | some k' =>
      rw [hb] at h
      obtain ⟨hk, -⟩ := pickB_some hb
      simp only [Option.some.injEq] at h
      subst h
      rw [hk]
      exact ⟨by decide, by decide⟩
    | none =>
      rw [hb] at h
      obtain ⟨hk, -⟩ := pickC_some h
      subst hk
      exact ⟨by decide, by decide⟩

theorem all_ne_w {i : InputD} {r : Row} {k : Kind} (h : pickAll i r = some k) : k ≠ .orphanLoop ∧ k ≠ .simBooted := by
  rcases all_some h with ⟨-, hp⟩ | ⟨hk, -⟩
  · exact pickAny_ne_w hp
  · subst hk
    exact ⟨by decide, by decide⟩

theorem one_some {i : InputD} {r : Row} {k : Kind} (h : pickOne i r = some k) :
    pickAll i r = some k ∨ (pickAll i r = none ∧ pickW i r = some k) := by
  unfold pickOne at h
  cases hp : pickAll i r with
  | some k' => rw [hp] at h; cases h; exact Or.inl rfl
  | none => rw [hp] at h; exact Or.inr ⟨rfl, h⟩

theorem pickW_some {i : InputD} {r : Row} {k : Kind} (h : pickW i r = some k) :
    serenaFree i r = true ∧ (pickE i r = some k ∨ (pickE i r = none ∧ pickF i r = some k)) := by
  unfold pickW at h
  split at h
  · rename_i hs
    refine ⟨hs, ?_⟩
    cases hp : pickE i r with
    | some k' => rw [hp] at h; cases h; exact Or.inl rfl
    | none => rw [hp] at h; exact Or.inr ⟨rfl, h⟩
  · cases h

theorem w_safe {i : InputD} {r : Row} {k : Kind} (h : pickW i r = some k) :
    1 < r.pid ∧ shielded i r = true ∧ serenaFree i r = true := by
  obtain ⟨hs, hp | ⟨-, hp⟩⟩ := pickW_some h
  · obtain ⟨-, -, -, -, -, h1, hsh⟩ := pickE_some hp
    exact ⟨h1, hsh, hs⟩
  · obtain ⟨-, -, -, -, h1, hsh⟩ := pickF_some hp
    exact ⟨h1, hsh, hs⟩

theorem one_safe {i : InputD} {r : Row} {k : Kind} (h : pickOne i r = some k) : 1 < r.pid ∧ shielded i r = true := by
  rcases one_some h with hp | ⟨-, hp⟩
  · obtain ⟨-, h1, hs, -⟩ := all_safe hp
    exact ⟨h1, hs⟩
  · obtain ⟨h1, hs, -⟩ := w_safe hp
    exact ⟨h1, hs⟩

theorem reapOne_mem {i : InputD} {s : Sel} (h : s ∈ reapOne i) :
    ∃ r ∈ i.rows, pickOne i r = some s.kind ∧ r.pid = s.pid ∧ r.start = s.start ∧ s.group = (r.pgid == r.pid) := by
  unfold reapOne at h
  rw [List.mem_filterMap] at h
  obtain ⟨r, hr, hs⟩ := h
  cases hp : pickOne i r with
  | none => simp [hp] at hs
  | some k =>
    simp [hp] at hs
    subst hs
    exact ⟨r, hr, hp, rfl, rfl, rfl⟩

theorem one_not_init {i : InputD} {s : Sel} (h : s ∈ reapOne i) : 1 < s.pid := by
  obtain ⟨r, -, hp, hpid, -⟩ := reapOne_mem h
  have := (one_safe hp).1
  omega

theorem one_shielded {i : InputD} {s : Sel} (h : s ∈ reapOne i) : ∃ r ∈ i.rows, r.pid = s.pid ∧ shielded i r = true := by
  obtain ⟨r, hr, hp, hpid, -⟩ := reapOne_mem h
  exact ⟨r, hr, hpid, (one_safe hp).2⟩

theorem orphan_branch {i : InputD} {s : Sel} (h : s ∈ reapOne i) (hk : s.kind = .orphanLoop) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.start = s.start ∧ r.kind = "untilLoop" ∧ r.inRepo = true ∧
      ∃ l, loopOf i r = some l ∧ l.callLive = false ∧ awaitOk l.awaits = true ∧ writerLive i r l = false := by
  obtain ⟨r, hr, hp, hpid, hst, -⟩ := reapOne_mem h
  rw [hk] at hp
  rcases one_some hp with hp | ⟨-, hp⟩
  · exact absurd rfl (all_ne_w hp).1
  · obtain ⟨-, hp | ⟨-, hp⟩⟩ := pickW_some hp
    · obtain ⟨-, -, -, ⟨l, hl, hk', hin, hcl, hok, hw⟩, -⟩ := pickE_some hp
      exact ⟨r, hr, hpid, hst, hk', hin, l, hl, hcl, hok, hw⟩
    · obtain ⟨hk', -⟩ := pickF_some hp
      cases hk'

theorem sim_branch {i : InputD} {s : Sel} (h : s ∈ reapOne i) (hk : s.kind = .simBooted) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.start = s.start ∧ r.kind = "simDevice" ∧ ownSim i r = true ∧
      ∃ a t, i.simAcquired = some a ∧ i.simIdleSince = some t ∧ a ≤ r.start ∧ r.start ≤ t ∧ simVerdict i t = .shutdown := by
  obtain ⟨r, hr, hp, hpid, hst, -⟩ := reapOne_mem h
  rw [hk] at hp
  rcases one_some hp with hp | ⟨-, hp⟩
  · exact absurd rfl (all_ne_w hp).2
  · obtain ⟨-, hp | ⟨-, hp⟩⟩ := pickW_some hp
    · obtain ⟨hk', -⟩ := pickE_some hp
      cases hk'
    · obtain ⟨-, hkind, ho, ht, -⟩ := pickF_some hp
      exact ⟨r, hr, hpid, hst, hkind, ho, ht⟩

theorem planSel_sub {i : InputD} {s : Sel} (h : s ∈ planSel i) : s ∈ reapOne i := (List.mem_filter.1 h).1

theorem planSel_explicit {i : InputD} (h : i.auto = false) : planSel i = reapOne i := by
  unfold planSel
  simp [h]

theorem planSel_auto {i : InputD} {s : Sel} (h : i.auto = true) (hs : s ∈ planSel i) : s.kind ∈ autoKinds := by
  unfold planSel at hs
  rw [List.mem_filter] at hs
  simpa [h] using hs.2

theorem planOne_sel {i : InputD} {t : Target} (h : t ∈ planOne i) :
    ∃ s ∈ planSel i, s.pid = t.pid ∧ s.start = t.start := by
  unfold planOne at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  exact ⟨s, hs, rfl, rfl⟩

theorem auto_plan_no_loop_sim {i : InputD} {t : Target} (ha : i.auto = true) (h : t ∈ planOne i) :
    ∃ s ∈ reapOne i, s.pid = t.pid ∧ s.start = t.start ∧ s.kind ≠ .orphanLoop ∧ s.kind ≠ .simBooted := by
  obtain ⟨s, hs, hp, hst⟩ := planOne_sel h
  have hk := planSel_auto ha hs
  refine ⟨s, planSel_sub hs, hp, hst, ?_, ?_⟩ <;> intro he <;> rw [he] at hk <;> simp [autoKinds] at hk

theorem planOne_group_inside {i : InputD} {t : Target} (h : t ∈ planOne i) (hg : t.group = true) :
    ∀ r ∈ i.rows, r.pgid = t.pid → ∃ s ∈ planSel i, s.pid = r.pid ∧ s.start = r.start := by
  unfold planOne at h
  rw [List.mem_map] at h
  obtain ⟨s, hs, rfl⟩ := h
  intro r hr hpg
  simp only [groupSafe, Bool.and_eq_true, List.all_eq_true] at hg
  have := hg.2 r hr
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, inSel, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at this
  rcases this with h1 | ⟨s', hs', h2, h3⟩
  · exact absurd hpg h1
  · exact ⟨s', hs', h2, h3⟩

theorem held_in_plan {i : InputD} {s : Sel} (ha : i.auto = false) (h : s ∈ held i) :
    ∃ t ∈ planOne i, t.pid = s.pid ∧ t.start = s.start := by
  unfold held at h
  rw [List.mem_filter] at h
  unfold planOne
  rw [planSel_explicit ha]
  exact ⟨_, List.mem_map.2 ⟨s, h.1, rfl⟩, rfl, rfl⟩

theorem held_kind {i : InputD} {s : Sel} (h : s ∈ held i) : s.kind = .orphanLoop := by
  unfold held at h
  rw [List.mem_filter] at h
  simpa using h.2

/-! ### Exit rule: when E or F may join `autoKinds`
The watch logs every E/F selection per tick to `reap.jsonl`. A reader folds that log into one `Seen` per identity (pid and
start) and the process table's later answer. `exitRule` says whether a kind has earned automatic stopping. -/

/-- What became of a logged selection: still running at the last tick, stopped by an explicit `fw reap --stop` (a true
orphan), or gone without our stop (the loop or Simulator ended by itself, so the selection was wrong or early). -/
inductive Outcome where
  | alive
  | stopped
  | ended
deriving Repr, DecidableEq

/-- One logged identity of kind `kind`, first selected at second `firstAt`. -/
structure Seen where
  kind : Kind
  pid : Nat
  start : Nat
  firstAt : Nat
  outcome : Outcome
deriving Repr

/-- Seven days in seconds. -/
def exitSec : Nat := 7 * 86400

/-- The kinds that can earn automatic stopping through the log. -/
def exitKinds : List Kind := [.orphanLoop, .simBooted]

/-- A kind joins `autoKinds` when it is an E/F kind, its log goes back at least `exitSec`, it has at least one true orphan
(`stopped`) and none of its identities `ended` by itself. Each identity decides on its own; other kinds do not count. -/
def exitRule (now : Nat) (seen : List Seen) (k : Kind) : Bool :=
  let ks := seen.filter fun s => s.kind == k
  decide (k ∈ exitKinds) && ks.any (fun s => decide (s.firstAt + exitSec ≤ now)) &&
    ks.any (fun s => s.outcome == .stopped) && ks.all (fun s => s.outcome != .ended)

/-- The kinds that have earned automatic stopping. -/
def promoted (now : Nat) (seen : List Seen) : List Kind := exitKinds.filter (exitRule now seen)

theorem exit_selected {now : Nat} {seen : List Seen} {k : Kind} (hk : k ∈ exitKinds)
    (hold : ∃ s ∈ seen, s.kind = k ∧ s.firstAt + exitSec ≤ now) (horph : ∃ s ∈ seen, s.kind = k ∧ s.outcome = .stopped)
    (hnone : ∀ s ∈ seen, s.kind = k → s.outcome ≠ .ended) : exitRule now seen k = true := by
  obtain ⟨a, ha, hak, han⟩ := hold
  obtain ⟨b, hb, hbk, hbs⟩ := horph
  unfold exitRule
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.any_eq_true, List.all_eq_true, List.mem_filter, beq_iff_eq,
    bne_iff_ne, ne_eq]
  exact ⟨⟨⟨hk, a, ⟨ha, hak⟩, by simpa using han⟩, b, ⟨hb, hbk⟩, by simpa using hbs⟩, fun s hs => hnone s hs.1 hs.2⟩

theorem exit_other_kind_kept {now : Nat} {seen : List Seen} {k : Kind} (hk : k ∉ exitKinds) : exitRule now seen k = false := by
  unfold exitRule
  simp [hk]

theorem exit_short_kept {now : Nat} {seen : List Seen} {k : Kind}
    (h : ∀ s ∈ seen, s.kind = k → now < s.firstAt + exitSec) : exitRule now seen k = false := by
  unfold exitRule
  simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not, List.any_eq_false, List.mem_filter, beq_iff_eq]
  refine Or.inl (Or.inl (Or.inr fun s hs => ?_))
  have := h s hs.1 hs.2
  simpa using this

theorem exit_no_orphan_kept {now : Nat} {seen : List Seen} {k : Kind}
    (h : ∀ s ∈ seen, s.kind = k → s.outcome ≠ .stopped) : exitRule now seen k = false := by
  unfold exitRule
  simp only [Bool.and_eq_false_iff, List.any_eq_false, List.mem_filter, beq_iff_eq]
  refine Or.inl (Or.inr fun s hs => ?_)
  have := h s hs.1 hs.2
  simpa using this

theorem exit_ended_kept {now : Nat} {seen : List Seen} {k : Kind} {s : Seen} (hs : s ∈ seen) (hk : s.kind = k)
    (h : s.outcome = .ended) : exitRule now seen k = false := by
  unfold exitRule
  simp only [Bool.and_eq_false_iff]
  refine Or.inr ?_
  simp only [List.all_eq_false, List.mem_filter, beq_iff_eq]
  exact ⟨s, ⟨hs, hk⟩, by simp [h]⟩

theorem promoted_sub {now : Nat} {seen : List Seen} {k : Kind} (h : k ∈ promoted now seen) : k ∈ exitKinds :=
  (List.mem_filter.1 h).1

/-- The rows of the exit rule: a quiet log, no orphan, an ended loop, an old log with an orphan. -/
private def sOld (o : Outcome) : Seen := ⟨.orphanLoop, 10, 100, 1000, o⟩

#guard promoted (1000 + exitSec) [sOld .stopped] == [.orphanLoop]
#guard promoted (1000 + exitSec - 1) [sOld .stopped] == []
#guard promoted (1000 + exitSec) [sOld .alive] == []
#guard promoted (1000 + exitSec) [sOld .stopped, ⟨.orphanLoop, 11, 100, 2000, .ended⟩] == []
#guard promoted (1000 + exitSec) [sOld .stopped, ⟨.simBooted, 12, 100, 2000, .ended⟩] == [.orphanLoop]
#guard promoted (1000 + exitSec) [⟨.removed, 10, 100, 1000, .stopped⟩] == []

end Fw.Ops.Reap

namespace Fw.Wire.Reap
open Lean Fw.Ops.Reap Fw.Wire.Ops

def rowOf (j : Json) : Except String Row := do
  let pid ← nat j "pid"
  let ppid ← nat j "ppid"
  let pgid ← nat j "pgid"
  let start ← nat j "start"
  let cwd ← optN j "cwd"
  let kind ← str j "kind"
  let wt ← optS j "wt"
  let inRepo ← boolD j "inRepo" false
  pure { pid, ppid, pgid, start, cwd, kind, wt, inRepo }

def useOf (j : Json) : Except String (Option Use) := do
  match ← optN j "cpu" with
  | some c => pure (some ⟨← nat j "pid", ← nat j "start", c⟩)
  | none => pure none

/-- A baseline from JSON: `pid`, `start`, `since`, `cpu`. -/
def baseOfJson (j : Json) : Except String Base := do
  pure ⟨← nat j "pid", ← nat j "start", ← nat j "since", ← nat j "cpu"⟩

/-- A baseline as JSON. -/
def baseJson (b : Base) : Json :=
  Json.mkObj [("pid", toJson b.pid), ("start", toJson b.start), ("since", toJson b.since), ("cpu", toJson b.cpu)]

/-- The input of the selection ops from JSON. -/
def inputOf (req : Json) : Except String InputD := do
  let rowsJ := (← arr req "rows").toList
  let rows ← rowsJ.mapM rowOf
  let uses := (← rowsJ.mapM useOf).filterMap id
  let live ← (← arr req "live").toList.mapM (asNat "live")
  let mcpsJ ← arrD req "mcps"
  let mcps ← mcpsJ.mapM fun j => do pure (Mcp.mk (← nat j "pid") (← optN j "cwd"))
  let mcpWt ← mcpsJ.filterMapM fun j => do pure ((← optS j "wt").map ((← nat j "pid"), ·))
  let keep ← (← arrD req "keep").mapM fun j => do pure ((← nat j "pid"), (← nat j "at"))
  let liveIds ← (← arrD req "liveIds").mapM (asStr "liveIds")
  let protect ← (← arrD req "protect").mapM (asNat "protect")
  let bases ← (← arrD req "bases").mapM baseOfJson
  let locks ← (← arrD req "locks").mapM fun j => do pure (Lock.mk (← str j "id") (← optN j "holder"))
  let waiters ← (← arrD req "waiters").mapM fun j => do pure (Waiter.mk (← nat j "pid") (← nat j "start") (← str j "wt") (← str j "writes") (← strD j "inode" ""))
  let loops ← (← arrD req "loops").mapM fun j => do
    pure (LoopFact.mk (← nat j "pid") (← nat j "start") (← str j "awaits") (← boolD j "callLive" false) (← strD j "inode" ""))
  let now ← natD req "now" 0
  let simIdleSince ← optN req "simIdleSince"
  let simAcquired ← optN req "simAcquired"
  let ownSims ← (← arrD req "ownSims").mapM fun j => do pure ((← nat j "pid"), (← nat j "start"))
  let simHolders ← natD req "simHolders" 0
  let legacyHeld ← boolD req "legacyHeld" true
  let auto ← boolD req "auto" false
  let i : InputD :=
    { rows, live, mcps, keep, liveIds, protect, now, uses, bases, locks, mcpWt, loops, waiters, simIdleSince, simAcquired, ownSims, simHolders }
  pure { i with legacyHeld, auto }

def selJson (s : Sel) : Json :=
  Json.mkObj [("pid", toJson s.pid), ("start", toJson s.start), ("kind", .str s.kind.name), ("group", .bool s.group),
    ("reason", .str s.kind.reason)]

/-- A stop target as JSON. -/
def targetJson (t : Target) : Json :=
  Json.mkObj [("pid", toJson t.pid), ("start", toJson t.start), ("group", .bool t.group)]

/-- A stop target from JSON. -/
def targetOf (j : Json) : Except String Target := do
  pure ⟨← nat j "pid", ← nat j "start", ← boolD j "group" false⟩

/-- `ops.lspReap`: `rows` [row with `cpu`? (centiseconds)], `live` [inode], `mcps`? [{pid, cwd?, wt?}], `keep`? [{pid, at}], `liveIds`? [id], `protect`?
[pid], `now`? (second), `bases`? [{pid, start, since, cpu}], `locks`? [{id, holder?}] → `selected` [{pid, start, kind, group,
reason}] of every branch, `count`. -/
def opLspReap (req : Json) : Except String Reply := do
  let sel := reapOne (← inputOf req)
  pure [("count", toJson sel.length), ("selected", .arr (sel.toArray.map selJson))]

/-- `ops.reapPlan`: the request of `ops.lspReap` → `count`, `selected`, `targets` [{pid, start, group}] (the TERM
targets), `graceMs`, `killWaitMs`, `script` [stage name]. -/
def opReapPlan (req : Json) : Except String Reply := do
  let i ← inputOf req
  let sel := reapOne i
  pure [("count", toJson sel.length), ("selected", .arr (sel.toArray.map selJson)),
    ("targets", .arr ((planOne i).toArray.map targetJson)), ("graceMs", toJson graceMs), ("killWaitMs", toJson killWaitMs),
    ("script", .arr (script.toArray.map fun s => .str s.name))]

/-- `ops.reapIdle`: the request of `ops.lspReap` → `bases` [{pid, start, since, cpu}] (the baselines to store for the next
run), `idleSec`, `cpuTolCs`. -/
def opReapIdle (req : Json) : Except String Reply := do
  let i ← inputOf req
  pure [("bases", .arr ((rebase i).toArray.map baseJson)), ("idleSec", toJson idleSec), ("cpuTolCs", toJson cpuTolCs)]

/-- `ops.reapHeld`: the request of `ops.lspReap` → `held` [{pid, start, kind, group, reason}], `count`. -/
def opReapHeld (req : Json) : Except String Reply := do
  let sel := held (← inputOf req)
  pure [("count", toJson sel.length), ("held", .arr (sel.toArray.map selJson))]

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

/-- A logged identity from JSON: `kind`, `pid`, `start`, `firstAt`, `outcome` (alive, stopped, ended). -/
def seenOf (j : Json) : Except String Seen := do
  let kind ← match ← str j "kind" with
    | "orphanLoop" => pure Kind.orphanLoop
    | "simBooted" => pure Kind.simBooted
    | k => throw s!"kind: unknown {k}"
  let outcome ← match ← str j "outcome" with
    | "alive" => pure Outcome.alive
    | "stopped" => pure Outcome.stopped
    | "ended" => pure Outcome.ended
    | o => throw s!"outcome: unknown {o}"
  pure ⟨kind, ← nat j "pid", ← nat j "start", ← nat j "firstAt", outcome⟩

/-- `ops.reapExit`: `now`, `seen` [{kind, pid, start, firstAt, outcome}] → `promote` [kind name] (the E/F kinds that earned
automatic stopping), `exitSec`. -/
def opReapExit (req : Json) : Except String Reply := do
  let now ← nat req "now"
  let seen ← (← arrD req "seen").mapM seenOf
  pure [("promote", .arr ((promoted now seen).toArray.map fun k => .str k.name)), ("exitSec", toJson exitSec)]

def ops : List String :=
  ["ops.reapExit", "ops.lspReap", "ops.reapPlan", "ops.reapKill", "ops.reapVerify", "ops.reapTerm", "ops.reapGuard", "ops.reapIdle", "ops.reapHeld"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.lspReap" => some (opLspReap req)
  | "ops.reapPlan" => some (opReapPlan req)
  | "ops.reapKill" => some (opReapKill req)
  | "ops.reapVerify" => some (opReapVerify req)
  | "ops.reapTerm" => some (opReapTerm req)
  | "ops.reapGuard" => some (opReapGuard req)
  | "ops.reapIdle" => some (opReapIdle req)
  | "ops.reapHeld" => some (opReapHeld req)
  | "ops.reapExit" => some (opReapExit req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("rows", .arr #[]), ("live", .arr #[]), ("planned", .arr #[]), ("scope", .arr #[]), ("target", Json.mkObj [("pid", toJson 2), ("start", toJson 0)])])).isSome

end Fw.Wire.Reap
