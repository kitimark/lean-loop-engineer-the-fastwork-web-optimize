/-!
# Where the time of a `fw ci wait` goes (task `ci-wait-lag`)

A wait that decided on a finish of its own passes through marks, all epoch milliseconds: GitHub marks the run done
(`upd`), the poller's list shows it (`tick`), the waiter reads the file (`read`), its jobs view ends (`viewEnd`),
fwcore decides (`done`), the cleanup ends (`ret`), the ingest of the CI spans runs from `i0` to `i1`, and the process
ends (`end`). `parts` cuts that path into seven pieces, each gap belongs to exactly one piece, and the pieces add up to
the whole (`parts_sum`). `fw timings --lag` (`apps/runner/src/timing-ci.ts`) only records the marks and replays the golden
`packages/contracts/golden/ci-budget/lag.jsonl` that this module generates.
-/
namespace Fw.Ci.Lag

/-- The marks of one wait, epoch milliseconds. -/
structure Marks where
  upd : Int
  tick : Int
  read : Int
  viewEnd : Int
  done : Int
  ret : Int
  i0 : Int
  i1 : Int
  stop : Int
  deriving Repr

/-- The pieces of the lag of one wait. `ingest` is the span ingest inside the exit, taken out of `exit`.
$$\operatorname{list} = t_{tick}-t_{upd},\ \operatorname{pickup} = t_{read}-t_{tick},\ \operatorname{view} = t_{viewEnd}-t_{read},\ \operatorname{verdict} = t_{done}-t_{viewEnd},\ \operatorname{cleanup} = t_{ret}-t_{done},\ \operatorname{ingest} = i_1-i_0,\ \operatorname{exit} = t_{end}-t_{ret}-(i_1-i_0)$$ -/
structure Parts where
  list : Int
  pickup : Int
  view : Int
  verdict : Int
  cleanup : Int
  ingest : Int
  exit : Int
  total : Int
  deriving Repr, DecidableEq

/-- The partition of the path from `upd` to the end into seven pieces and the total.
$$\operatorname{total} = t_{end}-t_{upd}$$ -/
def parts (m : Marks) : Parts where
  list := m.tick - m.upd
  pickup := m.read - m.tick
  view := m.viewEnd - m.read
  verdict := m.done - m.viewEnd
  cleanup := m.ret - m.done
  ingest := m.i1 - m.i0
  exit := m.stop - m.ret - (m.i1 - m.i0)
  total := m.stop - m.upd

/-- **The seven pieces add up to the total**, for any marks, in order or not.
$$\forall m:\ \operatorname{list}+\operatorname{pickup}+\operatorname{view}+\operatorname{verdict}+\operatorname{cleanup}+\operatorname{ingest}+\operatorname{exit} = \operatorname{total}$$ -/
theorem parts_sum (m : Marks) :
    let p := parts m
    p.list + p.pickup + p.view + p.verdict + p.cleanup + p.ingest + p.exit = p.total := by
  simp only [parts]; omega

/-- The gap between the previous tick and the deciding tick.
$$\operatorname{gap} = t_{tick}-t_{prev}$$ -/
def gap (tick prev : Int) : Int := tick - prev

/-- How long the list still showed the run unfinished after GitHub marked it done (never negative).
$$\operatorname{stale} = \max(0,\ t_{prev}-t_{upd})$$ -/
def stale (prev upd : Int) : Int := max 0 (prev - upd)

/-- **Staleness is never negative.** -/
theorem stale_nonneg (prev upd : Int) : 0 ≤ stale prev upd := by
  unfold stale; omega

/-- **No staleness when the previous tick came before the finish.** -/
theorem stale_zero_of_before (prev upd : Int) (h : prev ≤ upd) : stale prev upd = 0 := by
  simp [stale]; omega

#guard parts ⟨1000, 3000, 3100, 5000, 5010, 5020, 5030, 5230, 5300⟩ ==
  ⟨2000, 100, 1900, 10, 10, 200, 80, 4300⟩
#guard stale 900 1000 == 0
#guard stale 1500 1000 == 500

end Fw.Ci.Lag
