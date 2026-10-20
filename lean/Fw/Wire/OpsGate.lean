import Fw.Sched.Admit
import Fw.Ops.SpawnGuard
/-!
# The spawn gate: the spawn guard composed with admission (`ops.gate`, parallel plan §3.3)

`gate i B σ x` asks the spawn guard (`Fw.Ops.SpawnGuard.decide`) first. A guard denial is
returned unchanged. Otherwise the admission decision (`Fw.Sched.Admit.admit`) for the spawn's
item decides: `admit` passes the guard's own decision through (`allow` or `needsApproval`),
`queue why` becomes `queue why`. Admit does not count agents again; SpawnGuard does not look at
resources, writes or devices.

The plan (parallel plan §3.3) names this module `Fw.Ops.Gate`; it lives under `Fw/Wire/` because
the `ops-gate` task writes only there.

Proved: `gate_spec` (the gate accepts exactly when the guard accepts and admission admits),
`gate_deny` (a guard denial is returned unchanged), `gate_admit`, `gate_queue`, `gate_guard`
(a `guard d` result always carries the guard's own decision), and the carry-over of the
guarantees of both sides (`gate_accepted_within`, `gate_accepted_rate`, `gate_accepted_admit`).
-/
namespace Fw.Wire.OpsGate

open Fw.Sched.Admit (Vec State Item Reason admit ready free fits held)
open Fw.Ops.SpawnGuard (Input Within newAgent recentCount)

/-- The gate's answer: a guard decision (allow, needs approval, or a guard denial), or a queue
with the admission reason.
-/
inductive GateDecision where
  | guard (d : Fw.Ops.SpawnGuard.Decision)
  | queue (why : Reason)
deriving DecidableEq, Repr

/-- A gate decision lets the spawn go ahead (directly or after approval): a guard decision that
the guard accepts; a queue never does.
-/
def GateDecision.accepted : GateDecision → Bool
  | .guard d => d.accepted
  | .queue _ => false

/-- The gate: the spawn guard first (a denial is final), then admission of the item. -/
def gate (i : Input) (B : Vec) (σ : State) (x : Item) : GateDecision :=
  match Fw.Ops.SpawnGuard.decide i with
  | .deny r => .guard (.deny r)
  | d => match admit B σ x with
    | .admit => .guard d
    | .queue why => .queue why

/-- **Gate spec.** The gate accepts exactly when the guard accepts and admission admits. -/
theorem gate_spec (i : Input) (B : Vec) (σ : State) (x : Item) :
    (gate i B σ x).accepted = true ↔
      (Fw.Ops.SpawnGuard.decide i).accepted = true ∧ admit B σ x = .admit := by
  unfold gate
  cases hd : Fw.Ops.SpawnGuard.decide i <;> cases ha : admit B σ x <;>
    simp [GateDecision.accepted, Fw.Ops.SpawnGuard.Decision.accepted]

/-- A guard denial is returned unchanged, whatever admission would say. -/
theorem gate_deny (i : Input) (B : Vec) (σ : State) (x : Item) (r : Fw.Ops.SpawnGuard.Reason)
    (h : Fw.Ops.SpawnGuard.decide i = .deny r) : gate i B σ x = .guard (.deny r) := by
  simp [gate, h]

/-- An admitted item gives the guard's own decision, whatever it is (a denial included). -/
theorem gate_admit (i : Input) (B : Vec) (σ : State) (x : Item) (ha : admit B σ x = .admit) :
    gate i B σ x = .guard (Fw.Ops.SpawnGuard.decide i) := by
  unfold gate
  cases Fw.Ops.SpawnGuard.decide i <;> simp [ha]

/-- An accepted guard decision and a queued item give the admission reason. -/
theorem gate_queue (i : Input) (B : Vec) (σ : State) (x : Item) (w : Reason)
    (hg : (Fw.Ops.SpawnGuard.decide i).accepted = true) (ha : admit B σ x = .queue w) :
    gate i B σ x = .queue w := by
  unfold gate
  cases hd : Fw.Ops.SpawnGuard.decide i <;> rw [hd] at hg <;>
    simp_all [Fw.Ops.SpawnGuard.Decision.accepted]

/-- A guard result is always the guard's own decision: the gate never alters or invents a guard
decision.
-/
theorem gate_guard (i : Input) (B : Vec) (σ : State) (x : Item) (d : Fw.Ops.SpawnGuard.Decision)
    (h : gate i B σ x = .guard d) : d = Fw.Ops.SpawnGuard.decide i := by
  unfold gate at h
  cases hd : Fw.Ops.SpawnGuard.decide i <;> cases ha : admit B σ x <;> simp_all

/-- A gate-accepted spawn keeps every cap (carried over from `SpawnGuard.accepted_within`). -/
theorem gate_accepted_within (i : Input) (B : Vec) (σ : State) (x : Item)
    (h : (gate i B σ x).accepted = true) : Within i.caps (newAgent i.req :: i.alive) :=
  Fw.Ops.SpawnGuard.accepted_within i ((gate_spec i B σ x).mp h).1

/-- A gate-accepted spawn respects the rate cap (carried over from `SpawnGuard.accepted_rate`). -/
theorem gate_accepted_rate (i : Input) (B : Vec) (σ : State) (x : Item)
    (h : (gate i B σ x).accepted = true) : recentCount i + 1 ≤ i.caps.spawnsPerWindow :=
  Fw.Ops.SpawnGuard.accepted_rate i ((gate_spec i B σ x).mp h).1

/-- A gate-accepted item is ready, free, fits the budget and is not held (carried over from
`Admit.admit_iff`).
-/
theorem gate_accepted_admit (i : Input) (B : Vec) (σ : State) (x : Item)
    (h : (gate i B σ x).accepted = true) :
    ready σ x = true ∧ free σ x = true ∧ fits B σ x = true ∧ held B σ x = false :=
  (Fw.Sched.Admit.admit_iff B σ x).mp ((gate_spec i B σ x).mp h).2

/-! ## Examples -/

/-- A guard input with no agents alive, one worktree role `w` and the default caps, asking for a
named worktree spawn of `w` from the lead. -/
def exInput : Input :=
  { alive := [], roles := [{ name := "w", runsAs := .worktree, edits := true }], caps := {}, recent := [],
    now := 0, req := { name := "w-1", role := "w", isolation := true, model := "", spawner := "lead", depth := 0 } }

#guard gate exInput {} {} { id := "w-1" } == .guard .allow
#guard gate exInput {} {} { id := "w-1", demand := { cores := 1 } } == .queue (.neverFits .cores)
#guard gate { exInput with req := { exInput.req with role := "nope" } } {} {} { id := "w-1", demand := { cores := 1 } }
  == .guard (.deny .unknownRole)
#guard (gate exInput { cores := 2 } {} { id := "w-1", demand := { cores := 1 } }).accepted
#guard !(gate exInput {} {} { id := "w-1", deps := ["a"] }).accepted

end Fw.Wire.OpsGate
