import Lean.Data.Json
import Fw.Ops.Wire

/-!
# Which leftover processes `fw reap --list` names (task `orphan-guard`)
A row is selected when it is of a named kind, its cwd inode matches no live checkout, and its parent fits the kind.
-/
namespace Fw.Ops.Reap

/-- The named kinds of leftover: a `lake serve` of lean-lsp-mcp and a console-api. -/
inductive Kind where
  | lspServe
  | console
deriving Repr, DecidableEq

/-- The kind named by the glue's argv classification. -/
def kindOf : String → Option Kind
  | "lspServe" => some .lspServe
  | "console" => some .console
  | _ => none

/-- The wire name of a kind. -/
def Kind.name : Kind → String
  | .lspServe => "lspServe"
  | .console => "console"

/-- One process-table row: pid, parent pid, process group, start time, cwd inode (`none`: unreadable), argv kind. -/
structure Row where
  pid : Nat
  ppid : Nat
  pgid : Nat
  start : Nat
  cwd : Option Nat
  kind : String
deriving Repr

/-- The inputs: the rows, the inodes of the live checkouts' directories, the pids of the lean-lsp-mcp servers. -/
structure Input where
  rows : List Row
  live : List Nat
  mcps : List Nat
deriving Repr

/-- A selected row: its identity (pid and start), its kind and whether the group may be signalled. -/
structure Sel where
  pid : Nat
  start : Nat
  kind : Kind
  group : Bool
deriving Repr, DecidableEq

/-- The parent a kind requires: the lean-lsp-mcp process for `lspServe`, init for `console`. -/
def parentOk (mcps : List Nat) : Kind → Row → Bool
  | .lspServe, r => mcps.contains r.ppid
  | .console, r => r.ppid == 1

/-- The kind a row is selected as, or `none`. -/
def pick (i : Input) (r : Row) : Option Kind :=
  match kindOf r.kind, r.cwd with
  | some k, some c => if !i.live.contains c && parentOk i.mcps k r && decide (1 < r.pid) then some k else none
  | _, _ => none

/-- The rows to stop, with a group flag that is set only for a group leader. -/
def reap (i : Input) : List Sel :=
  i.rows.filterMap fun r => (pick i r).map fun k => ⟨r.pid, r.start, k, r.pgid == r.pid⟩

theorem pick_some {i : Input} {r : Row} {k : Kind} (h : pick i r = some k) :
    kindOf r.kind = some k ∧ (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ parentOk i.mcps k r = true ∧ 1 < r.pid := by
  unfold pick at h
  split at h
  · rename_i k' c hk hc
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hb
      exact ⟨hk, ⟨c, hc, hb.1.1⟩, hb.1.2, hb.2⟩
    · cases h
  · cases h

theorem reap_mem {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, pick i r = some s.kind ∧ r.pid = s.pid ∧ r.start = s.start ∧ s.group = (r.pgid == r.pid) := by
  unfold reap at h
  rw [List.mem_filterMap] at h
  obtain ⟨r, hr, hs⟩ := h
  cases hp : pick i r with
  | none => simp [hp] at hs
  | some k =>
    simp [hp] at hs
    subst hs
    exact ⟨r, hr, hp, rfl, rfl, rfl⟩

/-- Selected: a named kind and a cwd inode that no live checkout has. -/
theorem selected_named_and_dead {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, kindOf r.kind = some s.kind ∧ r.pid = s.pid ∧ ∃ c, r.cwd = some c ∧ c ∉ i.live := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨hk, ⟨c, hc, hl⟩, -, -⟩ := pick_some hp
  exact ⟨r, hr, hk, hpid, c, hc, by simpa using hl⟩

/-- A process whose cwd inode is a live checkout's is never selected. -/
theorem live_never_selected {i : Input} {r : Row} (hr : r ∈ i.rows) {c : Nat} (hc : r.cwd = some c) (hl : c ∈ i.live)
    (hu : ∀ r' ∈ i.rows, r'.pid = r.pid → r' = r) : ∀ s ∈ reap i, s.pid ≠ r.pid := by
  intro s hs hpid
  obtain ⟨r', hr', hp, hpid', -, -⟩ := reap_mem hs
  obtain ⟨-, ⟨c', hc', hl'⟩, -, -⟩ := pick_some hp
  have := hu r' hr' (hpid'.trans hpid)
  subst this
  rw [hc] at hc'
  cases hc'
  simp [hl] at hl'

/-- A group signal is only for a group leader (`pgid = pid`). -/
theorem group_leader {i : Input} {s : Sel} (h : s ∈ reap i) (hg : s.group = true) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.pgid = r.pid := by
  obtain ⟨r, hr, -, hpid, -, hgr⟩ := reap_mem h
  refine ⟨r, hr, hpid, ?_⟩
  rw [hg] at hgr
  simpa using hgr.symm

/-- A `lake serve` row is selected only as a child of the lean-lsp-mcp process. -/
theorem lsp_parent {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .lspServe) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.ppid ∈ i.mcps := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
  exact ⟨r, hr, hpid, by simpa [parentOk] using hpa⟩

/-- A console row is selected only when its parent is init (an orphan). -/
theorem console_orphan {i : Input} {s : Sel} (h : s ∈ reap i) (hk : s.kind = .console) :
    ∃ r ∈ i.rows, r.pid = s.pid ∧ r.ppid = 1 := by
  obtain ⟨r, hr, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
  exact ⟨r, hr, hpid, by simpa [parentOk] using hpa⟩

/-- Neither init nor pid 0 is ever selected. -/
theorem not_init {i : Input} {s : Sel} (h : s ∈ reap i) : 1 < s.pid := by
  obtain ⟨r, -, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, -, -, h1⟩ := pick_some hp
  omega

/-- Without a lean-lsp-mcp pid no `lake serve` row is selected. -/
theorem no_mcp_no_lsp {i : Input} (hm : i.mcps = []) : ∀ s ∈ reap i, s.kind ≠ .lspServe := by
  intro s hs hk
  obtain ⟨r, -, hp, -, -, -⟩ := reap_mem hs
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
  simp [parentOk, hm] at hpa

/-- More live inodes never add a selection. -/
theorem antitone_live {i : Input} {extra : List Nat} {s : Sel} (h : s ∈ reap { i with live := i.live ++ extra }) :
    s ∈ reap i := by
  unfold reap at h ⊢
  rw [List.mem_filterMap] at h ⊢
  obtain ⟨r, hr, hs⟩ := h
  refine ⟨r, hr, ?_⟩
  have hp : pick { i with live := i.live ++ extra } r = some s.kind := by
    cases hq : pick { i with live := i.live ++ extra } r with
    | none => simp [hq] at hs
    | some k => simp [hq] at hs; subst hs; rfl
  obtain ⟨hk, ⟨c, hc, hl⟩, hpa, h1⟩ := pick_some hp
  have hl' : i.live.contains c = false := by
    simp only [List.contains_append, Bool.or_eq_false_iff] at hl
    exact hl.1
  have hpa' : parentOk i.mcps s.kind r = true := hpa
  have : pick i r = some s.kind := by
    unfold pick
    rw [hk, hc]
    simp [hpa', h1]
    simpa using hl'
  rw [hp] at hs
  rw [this]
  exact hs

/-- The reason printed for a kind. -/
def Kind.reason : Kind → String
  | .lspServe => "lake serve of lean-lsp-mcp, cwd in no live checkout"
  | .console => "orphan console-api, cwd in no live checkout"

end Fw.Ops.Reap

namespace Fw.Wire.Reap
open Lean Fw.Ops.Reap Fw.Wire.Ops

/-- One row from JSON: `pid`, `ppid`, `pgid`, `start`, `cwd`? (inode or null), `kind`. -/
def rowOf (j : Json) : Except String Row := do
  pure ⟨← nat j "pid", ← nat j "ppid", ← nat j "pgid", ← nat j "start", ← optN j "cwd", ← str j "kind"⟩

/-- `ops.lspReap`: `rows` [row], `live` [inode], `mcps`? [pid] → `selected` [{pid, start, kind, group, reason}],
`count`. -/
def opLspReap (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM rowOf
  let live ← (← arr req "live").toList.mapM (asNat "live")
  let i : Input := ⟨rows, live, ← (← arrD req "mcps").mapM (asNat "mcps")⟩
  let sel := reap i
  pure [("count", toJson sel.length), ("selected", .arr (sel.toArray.map fun s =>
    Json.mkObj [("pid", toJson s.pid), ("start", toJson s.start), ("kind", .str s.kind.name), ("group", .bool s.group),
      ("reason", .str s.kind.reason)]))]

/-- The ops of this module. -/
def ops : List String := ["ops.lspReap"]

/-- Dispatch (`none` when the op is not `ops.lspReap`). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.lspReap" => some (opLspReap req)
  | _ => none

#guard ops.all fun o => (handle o (Json.mkObj [("rows", .arr #[]), ("live", .arr #[])])).isSome

end Fw.Wire.Reap
