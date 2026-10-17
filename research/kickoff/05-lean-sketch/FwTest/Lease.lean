import Fw
import Plausible
open Fw.Lease Plausible

/-! Compile-time examples: they run during `lake build`, a failure fails the build. -/
#guard (step {} (.acquire "a" 0 900)).2 matches .granted _
#guard ((step {} (.acquire "a" 0 900)).1 |> fun s => (step s (.acquire "b" 1 900)).2) matches .queued 0

/-- Random command traces for Plausible (owners drawn from a small pool so they collide). -/
inductive TCmd where
  | acquire (who : Fin 3) (dt : Fin 5)
  | renew   (who : Fin 3) (dt : Fin 5)
  | release (who : Fin 3) (dt : Fin 5)
  | tick    (dt : Fin 2000)
deriving Repr, Arbitrary, Shrinkable

def TCmd.toCmd (now : Nat) : TCmd → Nat × Cmd
  | .acquire w d => (now + d, .acquire s!"o{w}" (now + d) 900)
  | .renew w d   => (now + d, .renew s!"o{w}" (now + d) 900)
  | .release w d => (now + d, .release s!"o{w}" (now + d) 900)
  | .tick d      => (now + d, .tick (now + d) 900)

def run (cs : List TCmd) : State := (cs.foldl (fun (now, s) c =>
  let (now', cmd) := c.toCmd now; (now', (step s cmd).1)) (0, ({} : State))).2

/-- Bool mirror of `Inv` (what the TS oracle check would call). -/
def invB (s : State) : Bool :=
  (s.holder.isSome || s.queue.isEmpty) && s.queue.eraseDups.length == s.queue.length &&
  (match s.holder with | some l => !s.queue.contains l.owner | none => true)

/-- `step_inv` already proves this for all traces; the Plausible run checks that `invB`
agrees with `Inv` (the boundary copy is the thing that can be wrong). -/
def leaseProps : IO Bool := do
  let r ← Testable.checkIO (NamedBinder "cs" (∀ cs : List TCmd, invB (run cs) = true)) { numInst := 2000, quiet := true }
  match r with
  | .success _ => IO.println "lease: invB holds on 2000 random traces"; return true
  | _          => IO.println s!"lease: counterexample"; return false

-- The same property as an interactive check (prints "Unable to find a counter-example").
#eval Testable.check (∀ cs : List TCmd, invB (run cs) = true) { numInst := 300 }
