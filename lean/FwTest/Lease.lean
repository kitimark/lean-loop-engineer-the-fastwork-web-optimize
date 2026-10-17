import Fw
/-!
# Lease: random command traces (deterministic generator, no test dependency)

`step_inv` proves the invariant for every trace; this checks that `invB`, the Bool copy a TS
oracle would call, agrees with it on 2000 pseudo-random traces (owners drawn from a pool of 3 so
they collide).
-/
namespace FwTest.Lease
open Fw.Lease

/-- One step of a 64-bit linear congruential generator. -/
def lcg (x : UInt64) : UInt64 := x * 6364136223846793005 + 1442695040888963407

/-- A pseudo-random command at time `now`, and the next generator state. -/
def genCmd (seed : UInt64) (now : Nat) : Cmd × Nat × UInt64 :=
  let s1 := lcg seed
  let s2 := lcg s1
  let s3 := lcg s2
  let who := s!"o{(s1 >>> 33).toNat % 3}"
  let dt := (s2 >>> 33).toNat % 5
  let now' := now + dt
  match (s3 >>> 33).toNat % 4 with
  | 0 => (.acquire who now' 900, now', s3)
  | 1 => (.renew who now' 900, now', s3)
  | 2 => (.release who now' 900, now', s3)
  | _ => (.tick (now + (s3 >>> 40).toNat % 2000) 900, now + (s3 >>> 40).toNat % 2000, s3)

/-- Run `n` pseudo-random commands from the empty state. -/
def runTrace (seed : UInt64) (n : Nat) : State := Id.run do
  let mut s : State := {}
  let mut now := 0
  let mut g := seed
  for _ in [0:n] do
    let (c, now', g') := genCmd g now
    s := (step s c).1
    now := now'
    g := g'
  return s

/-- Bool mirror of `Inv`. -/
def invB (s : State) : Bool :=
  (s.holder.isSome || s.queue.isEmpty) && s.queue.eraseDups.length == s.queue.length &&
  (match s.holder with | some l => !s.queue.contains l.owner | none => true)

/-- 2000 traces of 1 to 40 commands each; true when `invB` held at the end of every trace. -/
def leaseProps : IO Bool := do
  let mut ok := true
  for i in [0:2000] do
    let s := runTrace (UInt64.ofNat (i * 7919 + 1)) (i % 40 + 1)
    unless invB s do
      IO.println s!"lease: invB fails on trace {i}"
      ok := false
  if ok then IO.println "lease: invB holds on 2000 pseudo-random traces"
  return ok

end FwTest.Lease
