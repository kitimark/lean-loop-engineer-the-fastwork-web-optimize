/-!
# Node test workers per run (task node-worker-budget; fw-sup daemon stage 3, first piece)
Each of `pool` concurrent test runs gets `workers` workers, so the pool fits the room's cores and free memory.
-/
namespace Fw.Sched.NodeBudget

/-- The room test runs share: online cores, free memory, memory per worker (MiB) and runs at once. -/
structure Room where
  cores : Nat
  freeMiB : Nat
  workerMiB : Nat
  pool : Nat
deriving Repr, DecidableEq

/-- Today's constant room, until the daemon supplies it from its ledger: 8 cores; a 1024 MiB test budget (a chosen budget,
not measured); 115 MiB per worker, the upper end of the MEASURED 95-115 MiB p50 vitest workers (work-graph task
node-worker-budget); land pool 4. -/
def today : Room := { cores := 8, freeMiB := 1024, workerMiB := 115, pool := 4 }

/-- Workers the cores allow per run. -/
def byCores (r : Room) : Nat := r.cores / r.pool

/-- Workers the free memory allows per run. -/
def byMemory (r : Room) : Nat := r.freeMiB / (r.pool * r.workerMiB)

/-- Workers per test run: what both the cores and the memory allow, at least 1. -/
def workers (r : Room) : Nat := max 1 (min (byCores r) (byMemory r))

#guard workers today = 2
#guard workers { today with pool := 1 } = 8
#guard workers { today with pool := 2 } = 4
#guard workers { today with pool := 5 } = 1
#guard workers { today with pool := 9 } = 1
#guard workers { today with freeMiB := 0 } = 1
#guard workers { today with pool := 0 } = 1
#guard workers { cores := 16, freeMiB := 16384, workerMiB := 95, pool := 4 } = 4

/-! ## Proofs -/

theorem workers_pos (r : Room) : 1 ≤ workers r := by
  unfold workers; omega

theorem workers_floor (r : Room) (h : min (byCores r) (byMemory r) = 0) : workers r = 1 := by
  unfold workers; omega

theorem workers_fit (r : Room) (h : 0 < min (byCores r) (byMemory r)) :
    workers r = min (byCores r) (byMemory r) := by
  unfold workers; omega

theorem workers_pool_gt_cores (r : Room) (h : r.cores < r.pool) : workers r = 1 := by
  apply workers_floor
  have : byCores r = 0 := Nat.div_eq_of_lt h
  omega

theorem pool_within_room (r : Room) (hc : r.pool ≤ r.cores) (hm : r.pool * r.workerMiB ≤ r.freeMiB) :
    (List.replicate r.pool (workers r)).sum ≤ r.cores ∧
      (List.replicate r.pool (workers r * r.workerMiB)).sum ≤ r.freeMiB := by
  simp only [List.sum_replicate_nat]
  by_cases h0 : min (byCores r) (byMemory r) = 0
  · rw [workers_floor r h0]; constructor <;> simpa using by assumption
  · rw [workers_fit r (Nat.pos_of_ne_zero h0)]
    constructor
    · calc r.pool * min (byCores r) (byMemory r) ≤ r.pool * byCores r := Nat.mul_le_mul_left _ (Nat.min_le_left ..)
        _ ≤ r.cores := Nat.mul_div_le r.cores r.pool
    · calc r.pool * (min (byCores r) (byMemory r) * r.workerMiB)
          ≤ r.pool * (byMemory r * r.workerMiB) :=
            Nat.mul_le_mul_left _ (Nat.mul_le_mul_right _ (Nat.min_le_right ..))
        _ = r.pool * r.workerMiB * byMemory r := by rw [Nat.mul_comm (byMemory r), Nat.mul_assoc]
        _ ≤ r.freeMiB := Nat.mul_div_le r.freeMiB (r.pool * r.workerMiB)

theorem monotone (r r' : Room) (hp : r.pool = r'.pool) (hw : r.workerMiB = r'.workerMiB)
    (hc : r.cores ≤ r'.cores) (hm : r.freeMiB ≤ r'.freeMiB) : workers r ≤ workers r' := by
  have h1 : byCores r ≤ byCores r' := by unfold byCores; rw [hp]; exact Nat.div_le_div_right hc
  have h2 : byMemory r ≤ byMemory r' := by unfold byMemory; rw [hp, hw]; exact Nat.div_le_div_right hm
  unfold workers; omega

theorem antitone_demand (r r' : Room) (hc : r.cores = r'.cores) (hm : r.freeMiB = r'.freeMiB)
    (hp : r'.pool ≤ r.pool) (hw : r'.workerMiB ≤ r.workerMiB) (hp0 : 0 < r'.pool) (hw0 : 0 < r'.workerMiB) :
    workers r ≤ workers r' := by
  have h1 : byCores r ≤ byCores r' := by unfold byCores; rw [hc]; exact Nat.div_le_div_left hp hp0
  have h2 : byMemory r ≤ byMemory r' := by
    unfold byMemory; rw [hm]; exact Nat.div_le_div_left (Nat.mul_le_mul hp hw) (Nat.mul_pos hp0 hw0)
  unfold workers; omega

theorem today_workers : workers today = 2 := by decide

theorem today_pool_sum : (List.replicate today.pool (workers today)).sum = 8 := by decide

/-! ## Generated files -/

/-- Pools whose workers the generated table lists: 1 to `today.cores`; a larger pool gets 1 (`workers_pool_gt_cores`). -/
def pools : List Nat := (List.range today.cores).map (· + 1)

private def roomJson (r : Room) : String :=
  s!"\{\"cores\":{r.cores},\"freeMiB\":{r.freeMiB},\"workerMiB\":{r.workerMiB},\"pool\":{r.pool}}"

/-- `packages/contracts/golden/sched/node-budget.gen.json`: today's room, its workers, and the workers per land pool size. -/
def genText : String :=
  let byPool := ",".intercalate (pools.map fun p => s!"\"{p}\":{workers { today with pool := p }}")
  "{\"generated\":\"Fw.Sched.NodeBudget (lean/Fw/Sched/NodeBudget.lean); regenerate from lean/: lake env lean --run scripts/NodeBudgetGolden.lean\"," ++
    s!"\"room\":{roomJson today},\"workers\":{workers today},\"byPool\":\{{byPool}}}\n"

/-- Rooms of the golden vectors. -/
def cases : List Room := Id.run do
  let mut out := []
  for c in [0, 1, 4, 8, 16] do
    for f in [0, 460, 1024, 16384] do
      for w in [0, 95, 115] do
        for p in [0, 1, 2, 4, 8, 9] do
          out := out ++ [{ cores := c, freeMiB := f, workerMiB := w, pool := p }]
  return out

/-- `packages/contracts/golden/sched/node-budget.jsonl`: one `{room, workers}` row per case. -/
def goldenText : String :=
  String.join (cases.map fun r => s!"\{\"room\":{roomJson r},\"workers\":{workers r}}\n")

end Fw.Sched.NodeBudget
