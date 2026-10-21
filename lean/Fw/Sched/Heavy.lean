import Lean

/-!
# Heavy-job lock (task local-mem-budget)

Several agents start `lean/scripts/check.sh` (29 processes in the warm tree; summed RSS peaked at 7.0 GB, an upper bound because the `lean` workers share mapped oleans) on one
8-CPU, 16 GB Mac at the same time; the load average climbs to 20-40 and every timed step runs 1.5-2x slower
(see `Fw.Obs.Timing.contendedLoad`). The lock admits a heavy job only when the number of live holders is below a
cap derived from the CPU count, when memory is free, and when swap is not already heavily used. An idle machine
always admits, so the lock cannot deadlock. `scripts/heavy-lock.mjs` is the I/O shell and a temporary TS
stand-in of `verdict`; it is tested against `packages/contracts/golden/sched/heavy.jsonl`, written from here.

Proved: `verdict_idle` (no live holder: admit), `verdict_admit_le_cap` (an admit never raises the live holders
above the cap, except the first), `verdict_admit_mem` (an admit beside a holder has the job's memory plus the
reserve free and swap below the limit), `verdict_swap_blocks`, `verdict_rank` (only the head of the FIFO queue
is admitted), `cap_pos` / `cap_le` (the cap is between 1 and `max 1 capMax`), `mem_prune` (a holder counts only
when its pid and start time both match a live process, so a reused pid is stale), `prune_sublist`.
-/
namespace Fw.Sched.Heavy

/-- The lock parameters. `capMax`: most concurrent heavy jobs, 2 (one job runs parallel groups 4 wide, so two fill the 8 CPUs at `Fw.Obs.Timing.contendedLoad` 8); `cpusPerJob`: CPUs one job is given;
`jobMB`: memory one job needs; 5000 MB (MEASURED, one local debug run of check.sh at load 10-15: summed RSS peak 7.0 GB, 29 processes, wall 25-36 s; not a result); `reserveMB`: memory kept free for everything else; `swapPct`: swap use (in
percent of the total) at and above which no further job is admitted.
-/
structure Params where
  capMax     : Nat := 2
  cpusPerJob : Nat := 4
  jobMB      : Nat := 5000
  reserveMB  : Nat := 2048
  swapPct    : Nat := 60
deriving Repr, DecidableEq

/-- What the shell observes: CPU count, free memory (MB), swap used and total (MB). -/
structure Obs where
  cpus        : Nat
  freeMB      : Nat
  swapUsedMB  : Nat
  swapTotalMB : Nat
deriving Repr, DecidableEq

/-- The concurrent-job cap: `cpus / cpusPerJob`, at least 1, at most `capMax`. -/
def cap (p : Params) (cpus : Nat) : Nat := max 1 (min p.capMax (cpus / p.cpusPerJob))

/-- Swap is heavily used: a swap area exists and its use is at least `swapPct` percent. -/
def swapHigh (p : Params) (o : Obs) : Bool :=
  decide (0 < o.swapTotalMB) && decide (p.swapPct * o.swapTotalMB ≤ 100 * o.swapUsedMB)

/-- Why a job waits. -/
inductive Why where
  | queued (ahead : Nat)
  | cap (running limit : Nat)
  | swap
  | memory (needMB freeMB : Nat)
deriving Repr, DecidableEq

/-- The answer. -/
inductive Verdict where
  | admit
  | wait (why : Why)
deriving Repr, DecidableEq

/-- The decision for one asker: `rank` askers are ahead of it in the FIFO queue and `n` live holders run. -/
def verdict (p : Params) (o : Obs) (n rank : Nat) : Verdict :=
  if 0 < rank then .wait (.queued rank)
  else if n = 0 then .admit
  else if cap p o.cpus ≤ n then .wait (.cap n (cap p o.cpus))
  else if swapHigh p o then .wait .swap
  else if o.freeMB < p.jobMB + p.reserveMB then .wait (.memory (p.jobMB + p.reserveMB) o.freeMB)
  else .admit

/-- An idle machine admits the head of the queue (liveness: the lock never blocks forever). -/
theorem verdict_idle (p : Params) (o : Obs) : verdict p o 0 0 = .admit := by
  simp [verdict]

/-- Only the head of the queue is admitted. -/
theorem verdict_rank (p : Params) (o : Obs) (n rank : Nat) (h : verdict p o n rank = .admit) : rank = 0 := by
  refine Decidable.byContradiction fun hr => ?_
  have : 0 < rank := Nat.pos_of_ne_zero hr
  simp [verdict, this] at h

/-- The cap is at least 1. -/
theorem cap_pos (p : Params) (c : Nat) : 1 ≤ cap p c := by
  unfold cap; omega

/-- The cap is at most `max 1 capMax`. -/
theorem cap_le (p : Params) (c : Nat) : cap p c ≤ max 1 p.capMax := by
  unfold cap
  omega

/-- An admit raises the live holders above the cap only from an idle machine (and then to 1). -/
theorem verdict_admit_le_cap (p : Params) (o : Obs) (n rank : Nat) (h : verdict p o n rank = .admit) :
    n = 0 ∨ n + 1 ≤ cap p o.cpus := by
  by_cases hn : n = 0
  · exact Or.inl hn
  · refine Or.inr ?_
    refine Decidable.byContradiction fun hc => ?_
    have hc' : cap p o.cpus ≤ n := by omega
    by_cases hr : 0 < rank
    · simp [verdict, hr] at h
    · simp [verdict, hr, hn, hc'] at h

/-- An admit beside a live holder has memory for the job plus the reserve, and swap below the limit. -/
theorem verdict_admit_mem (p : Params) (o : Obs) (n rank : Nat) (hn : n ≠ 0)
    (h : verdict p o n rank = .admit) :
    p.jobMB + p.reserveMB ≤ o.freeMB ∧ swapHigh p o = false := by
  by_cases hr : 0 < rank
  · simp [verdict, hr] at h
  · by_cases hc : cap p o.cpus ≤ n
    · simp [verdict, hr, hn, hc] at h
    · by_cases hs : swapHigh p o = true
      · simp [verdict, hr, hn, hc, hs] at h
      · by_cases hm : o.freeMB < p.jobMB + p.reserveMB
        · simp [verdict, hr, hn, hc, hs, hm] at h
        · refine ⟨by omega, by simpa using hs⟩

/-- With swap heavily used and a holder running, nothing is admitted. -/
theorem verdict_swap_blocks (p : Params) (o : Obs) (n rank : Nat) (hn : n ≠ 0)
    (hs : swapHigh p o = true) : verdict p o n rank ≠ .admit := by
  intro h
  have := (verdict_admit_mem p o n rank hn h).2
  simp [hs] at this

/-! ## Stale holders -/

/-- A holder: process id and process start time (the pair identifies a process; a reused pid has another start). -/
abbrev Holder := Nat × Nat

/-- The live holders: those whose pid and start time match a live process in `tbl`. -/
def prune (tbl hs : List Holder) : List Holder := hs.filter fun h => tbl.contains h

/-- A holder survives pruning exactly when it was recorded and its pid and start match a live process. -/
theorem mem_prune (tbl hs : List Holder) (h : Holder) : h ∈ prune tbl hs ↔ h ∈ hs ∧ h ∈ tbl := by
  simp [prune]

/-- A holder whose pid is alive with another start time (pid reuse) is stale. -/
theorem reused_pid_stale (pid s s' : Nat) (hne : s ≠ s') (hs : List Holder) :
    (pid, s) ∉ prune [(pid, s')] hs := by
  intro h
  rw [mem_prune] at h
  simp at h
  exact hne h.2

/-- Pruning only removes holders. -/
theorem prune_sublist (tbl hs : List Holder) : (prune tbl hs).Sublist hs := List.filter_sublist

/-! ## Golden vectors for `scripts/heavy-lock.mjs` -/

open Lean in
/-- The wire form of a verdict. -/
def verdictJson : Verdict → Json
  | .admit => Json.mkObj [("verdict", "admit")]
  | .wait (.queued a) => Json.mkObj [("verdict", "wait"), ("why", "queued"), ("ahead", toJson a)]
  | .wait (.cap r l) => Json.mkObj [("verdict", "wait"), ("why", "cap"), ("running", toJson r), ("limit", toJson l)]
  | .wait .swap => Json.mkObj [("verdict", "wait"), ("why", "swap")]
  | .wait (.memory need free) =>
      Json.mkObj [("verdict", "wait"), ("why", "memory"), ("needMB", toJson need), ("freeMB", toJson free)]

open Lean in
def paramsJson (p : Params) : Json :=
  Json.mkObj [("capMax", toJson p.capMax), ("cpusPerJob", toJson p.cpusPerJob), ("jobMB", toJson p.jobMB),
    ("reserveMB", toJson p.reserveMB), ("swapPct", toJson p.swapPct)]

open Lean in
def obsJson (o : Obs) : Json :=
  Json.mkObj [("cpus", toJson o.cpus), ("freeMB", toJson o.freeMB), ("swapUsedMB", toJson o.swapUsedMB),
    ("swapTotalMB", toJson o.swapTotalMB)]

/-- A healthy 8-CPU, 16 GB machine. -/
def okObs : Obs := { cpus := 8, freeMB := 9000, swapUsedMB := 500, swapTotalMB := 4096 }

/-- The decision cases: (name, params, observation, live holders, askers ahead). -/
def verdictCases : List (String × Params × Obs × Nat × Nat) :=
  [ ("idle machine admits", {}, okObs, 0, 0),
    ("idle machine admits even with no free memory", {}, { okObs with freeMB := 0, swapUsedMB := 4096 }, 0, 0),
    ("one holder, cap 2, memory free: admit", {}, okObs, 1, 0),
    ("holders at the cap wait", {}, okObs, 2, 0),
    ("holders above the cap wait", {}, okObs, 5, 0),
    ("asker behind another waits", {}, okObs, 0, 1),
    ("asker behind two waits, with the count", {}, okObs, 1, 2),
    ("swap at 60 percent blocks a second job", {}, { okObs with swapUsedMB := 2458 }, 1, 0),
    ("swap just below 60 percent admits", {}, { okObs with swapUsedMB := 2457 }, 1, 0),
    ("no swap area: swap is not high", {}, { okObs with swapUsedMB := 0, swapTotalMB := 0 }, 1, 0),
    ("free memory one MB short waits", {}, { okObs with freeMB := 7047 }, 1, 0),
    ("free memory exactly enough admits", {}, { okObs with freeMB := 7048 }, 1, 0),
    ("2 CPUs: cap is 1, a second job waits", {}, { okObs with cpus := 2 }, 1, 0),
    ("16 CPUs but capMax 2: cap stays 2", {}, { okObs with cpus := 16 }, 2, 0),
    ("capMax 4 on 16 CPUs: third job admitted", { capMax := 4 }, { okObs with cpus := 16 }, 2, 0),
    ("capMax 0 still allows one job", { capMax := 0 }, okObs, 0, 0) ]

open Lean in
/-- The prune cases: (name, live process table, recorded holders). -/
def pruneCases : List (String × List Holder × List Holder) :=
  [ ("all alive", [(10, 1), (20, 2)], [(10, 1), (20, 2)]),
    ("dead holder dropped", [(10, 1)], [(10, 1), (20, 2)]),
    ("reused pid with another start time dropped", [(10, 9)], [(10, 1)]),
    ("empty table drops all", [], [(10, 1), (20, 2)]) ]

open Lean in
def goldenText : String :=
  let vs := verdictCases.map fun (n, p, o, k, r) =>
    Json.mkObj [("name", .str n),
      ("request", Json.mkObj [("op", "sched.heavy"), ("params", paramsJson p), ("obs", obsJson o),
        ("running", toJson k), ("rank", toJson r)]),
      ("response", verdictJson (verdict p o k r))]
  let ps := pruneCases.map fun (n, tbl, hs) =>
    let h2j := fun (h : Holder) => Json.mkObj [("pid", toJson h.1), ("start", toJson h.2)]
    Json.mkObj [("name", .str n),
      ("request", Json.mkObj [("op", "sched.heavy.prune"), ("live", .arr (tbl.map h2j).toArray),
        ("holders", .arr (hs.map h2j).toArray)]),
      ("response", Json.mkObj [("holders", .arr ((prune tbl hs).map h2j).toArray)])]
  String.intercalate "\n" ((vs ++ ps).map Json.compress) ++ "\n"

/-- Path of the golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/sched/heavy.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Sched.Heavy
