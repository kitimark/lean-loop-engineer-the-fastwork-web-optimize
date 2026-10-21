import Fw.Sched.Heavy

/-!
# Node test workers per run (task node-worker-budget; fw-sup daemon stage 3, first piece)
Each of `pool` concurrent test runs gets `workers` workers, so the pool fits the room's cores and free memory, and one run
never gets more workers than the cores minus the room's reserve (`workers_le_reserve`; with reserve 1, the old default of
vitest and `node --test`, `cores - 1`: `workers_le_old_default`).
-/
namespace Fw.Sched.NodeBudget

/-- The room test runs share: online cores, cores one run leaves to the rest of the host, free memory, memory per worker
(MiB) and runs at once. -/
structure Room where
  cores : Nat
  reserveCores : Nat := 1
  freeMiB : Nat
  workerMiB : Nat
  pool : Nat
deriving Repr, DecidableEq

/-- Today's constant room, until the daemon supplies it from its ledger (follow-up sup-tests):
- `cores` 8: this Mac's `hw.ncpu`.
- `reserveCores` 1: the default of vitest and `node --test`, `availableParallelism - 1` (CONFIRMED, Node docs of
  `--test-concurrency`), kept as the most one run gets.
- `freeMiB` 2048: `Fw.Sched.Heavy.Params.reserveMB`, the memory the heavy-job lock keeps free for everything beside a
  heavy job, test runs included. INFERRED: that reserve is itself chosen, not measured; the footprint of test runs beside a
  heavy job is measured by follow-up sup-baseline.
- `workerMiB` 136: MEASURED, work-graph task node-worker-budget: the console-api suite at 7 workers 1486 MiB, at 2 workers
  808 MiB, so (1486 - 808) / 5 = 135.6 MiB per worker, rounded up.
- `pool` 4: the land pool.

Memory does not bind at any pool of this room (`byMemory` ≥ `byCores` for pools 1 to 8); cores and the reserve set it. -/
def today : Room :=
  { cores := 8, reserveCores := 1, freeMiB := ({} : Fw.Sched.Heavy.Params).reserveMB, workerMiB := 136, pool := 4 }

/-- Workers the cores allow per run. -/
def byCores (r : Room) : Nat := r.cores / r.pool

/-- Workers the free memory allows per run. -/
def byMemory (r : Room) : Nat := r.freeMiB / (r.pool * r.workerMiB)

/-- Workers the cores, the reserve and the memory all allow per run. -/
def fit (r : Room) : Nat := min (r.cores - r.reserveCores) (min (byCores r) (byMemory r))

/-- Workers per test run: `fit`, at least 1. -/
def workers (r : Room) : Nat := max 1 (fit r)

#guard today.freeMiB = 2048
#guard workers today = 2
#guard workers { today with pool := 1 } = 7
#guard workers { today with pool := 2 } = 4
#guard workers { today with pool := 3 } = 2
#guard workers { today with pool := 5 } = 1
#guard workers { today with pool := 9 } = 1
#guard workers { today with freeMiB := 0 } = 1
#guard workers { today with pool := 0 } = 1
#guard workers { today with pool := 1, reserveCores := 0 } = 8
#guard workers { today with cores := 1 } = 1
#guard workers { today with pool := 1, freeMiB := 460 } = 3
#guard workers { cores := 16, freeMiB := 16384, workerMiB := 95, pool := 4 } = 4
#guard (List.range 9).all fun p => byCores { today with pool := p + 1 } ≤ byMemory { today with pool := p + 1 }

/-! ## Proofs -/

theorem workers_pos (r : Room) : 1 ≤ workers r := by
  unfold workers; omega

theorem workers_floor (r : Room) (h : fit r = 0) : workers r = 1 := by
  unfold workers; omega

theorem workers_fit (r : Room) (h : 0 < fit r) : workers r = fit r := by
  unfold workers; omega

theorem workers_pool_gt_cores (r : Room) (h : r.cores < r.pool) : workers r = 1 := by
  apply workers_floor
  have : byCores r = 0 := Nat.div_eq_of_lt h
  unfold fit; omega

theorem workers_le_reserve (r : Room) (h : r.reserveCores < r.cores) : workers r ≤ r.cores - r.reserveCores := by
  unfold workers fit; omega

theorem workers_le_old_default (r : Room) (h1 : r.reserveCores = 1) (h2 : 2 ≤ r.cores) : workers r ≤ r.cores - 1 := by
  have := workers_le_reserve r (by omega); omega

theorem today_le_old_default (p : Nat) : workers { today with pool := p } ≤ today.cores - 1 :=
  workers_le_old_default _ rfl (show 2 ≤ today.cores by decide)

theorem today_alone : workers { today with pool := 1 } = 7 := by decide

theorem pool_within_room (r : Room) (hc : r.pool ≤ r.cores) (hm : r.pool * r.workerMiB ≤ r.freeMiB) :
    (List.replicate r.pool (workers r)).sum ≤ r.cores ∧
      (List.replicate r.pool (workers r * r.workerMiB)).sum ≤ r.freeMiB := by
  simp only [List.sum_replicate_nat]
  by_cases h0 : fit r = 0
  · rw [workers_floor r h0]; constructor <;> simpa using by assumption
  · rw [workers_fit r (Nat.pos_of_ne_zero h0)]
    have hb : fit r ≤ byCores r := by unfold fit; omega
    have hy : fit r ≤ byMemory r := by unfold fit; omega
    constructor
    · calc r.pool * fit r ≤ r.pool * byCores r := Nat.mul_le_mul_left _ hb
        _ ≤ r.cores := Nat.mul_div_le r.cores r.pool
    · calc r.pool * (fit r * r.workerMiB)
          ≤ r.pool * (byMemory r * r.workerMiB) := Nat.mul_le_mul_left _ (Nat.mul_le_mul_right _ hy)
        _ = r.pool * r.workerMiB * byMemory r := by rw [Nat.mul_comm (byMemory r), Nat.mul_assoc]
        _ ≤ r.freeMiB := Nat.mul_div_le r.freeMiB (r.pool * r.workerMiB)

theorem monotone (r r' : Room) (hp : r.pool = r'.pool) (hw : r.workerMiB = r'.workerMiB)
    (hr : r.reserveCores = r'.reserveCores) (hc : r.cores ≤ r'.cores) (hm : r.freeMiB ≤ r'.freeMiB) :
    workers r ≤ workers r' := by
  have h1 : byCores r ≤ byCores r' := by unfold byCores; rw [hp]; exact Nat.div_le_div_right hc
  have h2 : byMemory r ≤ byMemory r' := by unfold byMemory; rw [hp, hw]; exact Nat.div_le_div_right hm
  unfold workers fit; omega

theorem antitone_demand (r r' : Room) (hc : r.cores = r'.cores) (hr : r.reserveCores = r'.reserveCores)
    (hm : r.freeMiB = r'.freeMiB) (hp : r'.pool ≤ r.pool) (hw : r'.workerMiB ≤ r.workerMiB) (hp0 : 0 < r'.pool)
    (hw0 : 0 < r'.workerMiB) : workers r ≤ workers r' := by
  have h1 : byCores r ≤ byCores r' := by unfold byCores; rw [hc]; exact Nat.div_le_div_left hp hp0
  have h2 : byMemory r ≤ byMemory r' := by
    unfold byMemory; rw [hm]; exact Nat.div_le_div_left (Nat.mul_le_mul hp hw) (Nat.mul_pos hp0 hw0)
  unfold workers fit; omega

theorem today_workers : workers today = 2 := by decide

theorem today_pool_sum : (List.replicate today.pool (workers today)).sum = 8 := by decide

/-! ## Generated files -/

/-- Pools whose workers the generated table lists: 1 to `today.cores`; a larger pool gets 1 (`workers_pool_gt_cores`). -/
def pools : List Nat := (List.range today.cores).map (· + 1)

private def roomJson (r : Room) : String :=
  s!"\{\"cores\":{r.cores},\"reserveCores\":{r.reserveCores},\"freeMiB\":{r.freeMiB},\"workerMiB\":{r.workerMiB},\"pool\":{r.pool}}"

/-- `packages/contracts/golden/sched/node-budget.gen.json`: today's room, its workers, and the workers per land pool size. -/
def genText : String :=
  let byPool := ",".intercalate (pools.map fun p => s!"\"{p}\":{workers { today with pool := p }}")
  "{\"generated\":\"Fw.Sched.NodeBudget (lean/Fw/Sched/NodeBudget.lean); regenerate from lean/: lake env lean --run scripts/NodeBudgetGolden.lean\"," ++
    s!"\"room\":{roomJson today},\"workers\":{workers today},\"byPool\":\{{byPool}}}\n"

/-- Rooms of the golden vectors. -/
def cases : List Room := Id.run do
  let mut out := []
  for c in [0, 1, 4, 8, 16] do
    for s in [0, 1] do
      for f in [0, 460, today.freeMiB, 16384] do
        for w in [0, 95, today.workerMiB] do
          for p in [0, 1, 2, 4, 8, 9] do
            out := out ++ [{ cores := c, reserveCores := s, freeMiB := f, workerMiB := w, pool := p }]
  return out

/-- `packages/contracts/golden/sched/node-budget.jsonl`: one `{room, workers}` row per case. -/
def goldenText : String :=
  String.join (cases.map fun r => s!"\{\"room\":{roomJson r},\"workers\":{workers r}}\n")

end Fw.Sched.NodeBudget
