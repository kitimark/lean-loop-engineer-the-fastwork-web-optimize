import Lean.Data.Json
import Fw.Ops.Wire

/-!
# Which leftover processes `fw reap --list` names (task `orphan-guard`)
A row is selected when it is of a named kind, its cwd inode matches no live checkout of this repo, its parent fits the kind
(a lean-lsp-mcp of this repo for `lake serve`, init for a console) and it is not the console recorded in main's `.fw-console`.
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

/-- A lean-lsp-mcp process: pid and cwd inode (`none`: unreadable). -/
structure Mcp where
  pid : Nat
  cwd : Option Nat
deriving Repr

/-- The inputs: the rows, the inodes of the live checkouts' directories (this repo's `git worktree list`, nested Lean
projects included), the lean-lsp-mcp processes, and the recorded console `keep` as (pid, start second of its record). -/
structure Input where
  rows : List Row
  live : List Nat
  mcps : List Mcp
  keep : List (Nat × Nat)
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

/-- The kind a row is selected as, or `none`. -/
def pick (i : Input) (r : Row) : Option Kind :=
  match kindOf r.kind, r.cwd with
  | some k, some c =>
    if !i.live.contains c && parentOk i k r && decide (1 < r.pid) && !kept i r then some k else none
  | _, _ => none

/-- The rows to stop, with a group flag that is set only for a group leader. -/
def reap (i : Input) : List Sel :=
  i.rows.filterMap fun r => (pick i r).map fun k => ⟨r.pid, r.start, k, r.pgid == r.pid⟩

theorem pick_some {i : Input} {r : Row} {k : Kind} (h : pick i r = some k) :
    kindOf r.kind = some k ∧ (∃ c, r.cwd = some c ∧ i.live.contains c = false) ∧ parentOk i k r = true ∧ 1 < r.pid ∧
      kept i r = false := by
  unfold pick at h
  split at h
  · rename_i k' c hk hc
    split at h
    · rename_i hb
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hb
      exact ⟨hk, ⟨c, hc, hb.1.1.1⟩, hb.1.1.2, hb.1.2, hb.2⟩
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
  obtain ⟨hk, ⟨c, hc, hl⟩, -, -, -⟩ := pick_some hp
  exact ⟨r, hr, hk, hpid, c, hc, by simpa using hl⟩

/-- Row safety 1: a row whose cwd inode is a live checkout's (nested projects included) is not picked. -/
theorem live_row {i : Input} {r : Row} {c : Nat} (hc : r.cwd = some c) (hl : c ∈ i.live) : pick i r = none := by
  cases hp : pick i r with
  | none => rfl
  | some k =>
    obtain ⟨-, ⟨c', hc', hl'⟩, -, -, -⟩ := pick_some hp
    rw [hc] at hc'
    cases hc'
    simp [hl] at hl'

/-- Row safety 2: the recorded console (same pid, record second within 60 s of the start) is not picked. -/
theorem kept_row {i : Input} {r : Row} {k : Nat × Nat} (hk : k ∈ i.keep) (hp : k.1 = r.pid) (h1 : r.start ≤ k.2)
    (h2 : k.2 ≤ r.start + 60) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, -, -, -, hk'⟩ := pick_some hq
    have : kept i r = true := by
      unfold kept
      rw [List.any_eq_true]
      exact ⟨k, hk, by simp [hp, h1, h2]⟩
    rw [this] at hk'
    cases hk'

/-- Row safety 3: a row of pid 0 or 1 is not picked. -/
theorem init_row {i : Input} {r : Row} (h : r.pid ≤ 1) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, -, -, h1, -⟩ := pick_some hq
    omega

/-- Row safety 4: a row of an unnamed kind is not picked. -/
theorem unnamed_row {i : Input} {r : Row} (h : kindOf r.kind = none) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨hk, -⟩ := pick_some hq
    rw [h] at hk
    cases hk

/-- Row safety 5: a row with an unreadable cwd is not picked. -/
theorem unreadable_row {i : Input} {r : Row} (h : r.cwd = none) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨-, ⟨c, hc, -⟩, -⟩ := pick_some hq
    rw [h] at hc
    cases hc

/-- Per row, without a uniqueness hypothesis: a selection is exactly a picked row, and its group flag is set exactly
when that row is its own group leader (`pgid = pid`). -/
theorem group_iff {i : Input} {s : Sel} (h : s ∈ reap i) :
    ∃ r ∈ i.rows, pick i r = some s.kind ∧ r.pid = s.pid ∧ (s.group = true ↔ r.pgid = r.pid) := by
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
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
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
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
  exact ⟨r, hr, hpid, by simpa [parentOk] using hpa⟩

/-- Neither init nor pid 0 is ever selected. -/
theorem not_init {i : Input} {s : Sel} (h : s ∈ reap i) : 1 < s.pid := by
  obtain ⟨r, -, hp, hpid, -, -⟩ := reap_mem h
  obtain ⟨-, -, -, h1, -⟩ := pick_some hp
  omega

/-- Without a lean-lsp-mcp process no `lake serve` row is selected. -/
theorem no_mcp_no_lsp {i : Input} (hm : i.mcps = []) : ∀ s ∈ reap i, s.kind ≠ .lspServe := by
  intro s hs hk
  obtain ⟨r, -, hp, -, -, -⟩ := reap_mem hs
  obtain ⟨-, -, hpa, -⟩ := pick_some hp
  rw [hk] at hpa
  simp [parentOk, hm] at hpa

/-- A `lake serve` row whose parent is no lean-lsp-mcp with a cwd in a live checkout (another repo's server) is not
picked. -/
theorem foreign_mcp {i : Input} {r : Row} (hk : kindOf r.kind = some .lspServe)
    (hf : ∀ m ∈ i.mcps, m.pid = r.ppid → ∀ c, m.cwd = some c → c ∉ i.live) : pick i r = none := by
  cases hq : pick i r with
  | none => rfl
  | some kd =>
    obtain ⟨hk', -, hpa, -⟩ := pick_some hq
    rw [hk] at hk'
    cases hk'
    simp only [parentOk, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at hpa
    obtain ⟨m, hm, hmp, hc⟩ := hpa
    rcases hmc : m.cwd with _ | c
    · simp [hmc] at hc
    · simp [hmc] at hc
      exact absurd (by simpa using hc) (hf m hm hmp c hmc)

/-- More recorded consoles never add a selection. -/
theorem antitone_keep {i : Input} {extra : List (Nat × Nat)} {s : Sel} (h : s ∈ reap { i with keep := i.keep ++ extra }) :
    s ∈ reap i := by
  unfold reap at h ⊢
  rw [List.mem_filterMap] at h ⊢
  obtain ⟨r, hr, hs⟩ := h
  refine ⟨r, hr, ?_⟩
  have hp : pick { i with keep := i.keep ++ extra } r = some s.kind := by
    cases hq : pick { i with keep := i.keep ++ extra } r with
    | none => simp [hq] at hs
    | some k => simp [hq] at hs; subst hs; rfl
  obtain ⟨hk, ⟨c, hc, hl⟩, hpa, h1, hke⟩ := pick_some hp
  have hke' : kept i r = false := by
    unfold kept at hke ⊢
    simp only [List.any_append, Bool.or_eq_false_iff] at hke
    exact hke.1
  have : pick i r = some s.kind := by
    unfold pick
    rw [hk, hc]
    simp only [parentOk] at hpa ⊢
    simp [hpa, h1, hke']
    simpa using hl
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

/-- `ops.lspReap`: `rows` [row], `live` [inode], `mcps`? [{pid, cwd?}], `keep`? [{pid, at}] → `selected` [{pid, start, kind, group, reason}],
`count`. -/
def opLspReap (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM rowOf
  let live ← (← arr req "live").toList.mapM (asNat "live")
  let mcps ← (← arrD req "mcps").mapM fun j => do pure (Mcp.mk (← nat j "pid") (← optN j "cwd"))
  let keep ← (← arrD req "keep").mapM fun j => do pure ((← nat j "pid"), (← nat j "at"))
  let i : Input := ⟨rows, live, mcps, keep⟩
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
