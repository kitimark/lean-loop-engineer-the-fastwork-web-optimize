import Lean.Data.Json
import Fw.Ci.Budget
import Fw.Ci.Golden
/-!
# Replay of header traces through the GitHub request budget

Every `packages/contracts/golden/ci-budget/fixtures/*.jsonl` is replayed second by second through the decisions of
`Fw.Ci.Budget` (`reserve`, `next`, `observe`) against a simulated GitHub: one bucket of 5000 requests per hour,
resetting on the hour from the start, that answers each call with one `HTTP/2.0 200` block per request (with
`X-Ratelimit-Remaining` and `X-Ratelimit-Reset`), or a 403 with remaining 0 when the bucket is empty.

Fixture format (JSON lines). Line 1: `{"scenario":{name, waiters N, start, seconds, oneoffEvery (0: none),
oneoffCost, burst?, burstAt?, sweep? [N…], expect? {ticksPerHourMax?, oldExceeds?, counts? [{from, until, kind
("tick"|"oneoff"|"any"), min, max}]}}}`. Then any number of `{"at", "lines":[…]}` (the first call at or after `at` gets
these header lines instead of the server's answer; a recorded trace is a list of these) and `{"at",
"serverRemaining"}` (another client drains the bucket to that many at `at`).

Each second: the clock event; at the start, `N` runs registered as `N` waiters; one-offs queued every `oneoffEvery`
s and `burst` of them at `burstAt`, tried in order through `reserve` (a wait holds the queue until its time); then the
poller's `next`. Checks, independent of the decisions:
- every hour and every minute window holds at most the share of each kind (1800/1200 and 20/40) and at most
  $B = 3000$ / $B_1 = 60$ in all;
- no call goes before a `retry-after` ends, before the reset after a refusal with remaining 0 or after remaining
  ≤ 500, nor within 60 s of a bare 403/429; the server never refuses for an empty bucket;
- liveness: when every `next` between two ticks waited only for the interval, the gap is at most the largest $P$
  seen in it, every wait is in the future and an interval wait is at most $P$ ahead, and each tick covers every
  watched run;
- the expectations of the fixture, and for `sweep` the same issued calls for every $N$.
-/
namespace FwTest.CiBudget
open Lean Fw.Ci.Budget

/-- An issue-count expectation. -/
structure Count where
  lo : Nat
  hi : Nat
  kind : String
  min : Nat
  max : Nat

/-- A fixture. -/
structure Fixture where
  name : String
  waiters : Nat
  start : Nat
  seconds : Nat
  oneoffEvery : Nat
  oneoffCost : Nat
  burst : Nat
  burstAt : Nat
  sweep : List Nat
  ticksPerHourMax : Option Nat
  oldExceeds : Option Nat
  counts : List Count
  overrides : List (Nat × List String)
  drains : List (Nat × Nat)

/-- A natural field with a default. -/
def natD (j : Json) (k : String) (d : Nat) : Nat := (j.getObjValAs? Nat k).toOption.getD d

/-- A fixture from its lines. -/
def fixtureOf (ls : List Json) : Except String Fixture := do
  let sc ← match ls.head? with
    | some j => j.getObjVal? "scenario"
    | none => .error "empty fixture"
  let ex := (sc.getObjVal? "expect").toOption.getD (Json.mkObj [])
  let cs := (ex.getObjValAs? (Array Json) "counts").toOption.getD #[]
  let counts ← cs.toList.mapM fun c => do
    pure { lo := ← c.getObjValAs? Nat "from", hi := ← c.getObjValAs? Nat "until", kind := ← c.getObjValAs? String "kind",
           min := natD c "min" 0, max := natD c "max" 1000000 : Count }
  let rest := ls.drop 1
  let overrides ← rest.filterMapM fun j => match j.getObjValAs? (List String) "lines" with
    | .ok l => do pure (some (← j.getObjValAs? Nat "at", l))
    | .error _ => pure none
  let drains ← rest.filterMapM fun j => match j.getObjValAs? Nat "serverRemaining" with
    | .ok r => do pure (some (← j.getObjValAs? Nat "at", r))
    | .error _ => pure none
  pure { name := ← sc.getObjValAs? String "name", waiters := natD sc "waiters" 1, start := ← sc.getObjValAs? Nat "start",
         seconds := ← sc.getObjValAs? Nat "seconds", oneoffEvery := natD sc "oneoffEvery" 0,
         oneoffCost := natD sc "oneoffCost" 1, burst := natD sc "burst" 0, burstAt := natD sc "burstAt" 0,
         sweep := (sc.getObjValAs? (List Nat) "sweep").toOption.getD [],
         ticksPerHourMax := (ex.getObjValAs? Nat "ticksPerHourMax").toOption,
         oldExceeds := (ex.getObjValAs? Nat "oldExceeds").toOption, counts, overrides, drains }

/-- The simulated server: requests used in the current hour. -/
structure Server where
  hour : Nat := 0
  used : Nat := 0

/-- The server rolled to the hour of `t`. -/
def Server.roll (f : Fixture) (v : Server) (t : Nat) : Server :=
  let h := (t - f.start) / 3600
  if h == v.hour then v else { hour := h, used := 0 }

/-- The server's answer to a call of `c` requests at `t`: header lines, the server after, and whether it refused for
an empty bucket. -/
def Server.answer (f : Fixture) (v : Server) (t c : Nat) : List String × Server × Bool :=
  let v := v.roll f t
  let reset := f.start + 3600 * (v.hour + 1)
  if 5000 < v.used + c then
    (["HTTP/2.0 403 Forbidden", "X-Ratelimit-Remaining: 0", s!"X-Ratelimit-Reset: {reset}"], v, true)
  else
    let ls := (List.range c).flatMap fun i =>
      ["HTTP/2.0 200 OK", s!"X-Ratelimit-Remaining: {5000 - (v.used + i + 1)}", s!"X-Ratelimit-Reset: {reset}"]
    (ls, { v with used := v.used + c }, false)

/-- The replay state. -/
structure Sim where
  s : State
  srv : Server := {}
  overrides : List (Nat × List String)
  queue : List (Nat × Nat) := []
  issues : Array (Nat × Kind × Nat) := #[]
  bad : Array String := #[]
  forbid : Nat := 0
  lastTick : Option Nat := none
  onlyInterval : Bool := true
  maxP : Nat := 0

/-- Send a call the budget issued: check it against what the responses so far forbid, get the answer, observe it. -/
def Sim.call (L : Limits) (f : Fixture) (m : Sim) (t : Nat) (k : Kind) (c : Nat) (s' : State) : Sim := Id.run do
  let mut m := m
  if t < m.forbid then m := { m with bad := m.bad.push s!"{repr k} issued at {t} before {m.forbid}" }
  m := { m with issues := m.issues.push (t, k, c) }
  let (ls, srv, refusedEmpty) := match m.overrides with
    | (a, ls) :: _ => if a ≤ t then (ls, m.srv, false) else m.srv.answer f t c
    | [] => m.srv.answer f t c
  let overrides := match m.overrides with
    | (a, _) :: r => if a ≤ t then r else m.overrides
    | [] => []
  if refusedEmpty then m := { m with bad := m.bad.push s!"server refused at {t}: bucket empty" }
  let (h, n) := parse ls
  let mut fb := m.forbid
  if let some a := h.retryAfter then fb := max fb (t + a)
  let rem0 := h.remaining == some 0 && h.reset.isSome
  if refused h.status && rem0 then fb := max fb (h.reset.getD 0)
  if refused h.status && h.retryAfter.isNone && !rem0 then fb := max fb (t + 60)
  if let (some r, some T) := (h.remaining, h.reset) then
    if r ≤ 500 && t < T then fb := max fb T
  return { m with s := step L s' (.response h n), srv, overrides, forbid := fb }

/-- Replay a fixture with `N` waiters. -/
def simulate (L : Limits) (f : Fixture) (N : Nat) : Sim := Id.run do
  let mut m : Sim := { s := init f.start, overrides := f.overrides }
  for i in [0:f.seconds] do
    let t := f.start + i
    for (a, r) in f.drains do
      if a == t then
        let v := m.srv.roll f t
        m := { m with srv := { v with used := 5000 - r } }
    m := { m with s := step L m.s (.clock t) }
    if i == 0 then
      for r in [0:N] do
        m := { m with s := step L m.s (.register (r + 1) f.start) }
    if f.oneoffEvery > 0 && i % f.oneoffEvery == 0 then m := { m with queue := m.queue ++ [(t, f.oneoffCost)] }
    if f.burst > 0 && t == f.burstAt then m := { m with queue := m.queue ++ List.replicate f.burst (t, 1) }
    -- one-offs in order; a wait holds the queue
    let mut go := true
    while go do
      match m.queue with
      | (ready, c) :: rest =>
        if t < ready then go := false
        else match reserve L m.s c with
          | .issue k c' s' => m := { (m.call L f t k c' s') with queue := rest }
          | .wait u r =>
            if u ≤ t then m := { m with bad := m.bad.push s!"reserve waits into the past at {t}: {u} {repr r}" }
            m := { m with queue := (max u (t + 1), c) :: rest }
            go := false
          | .stop r =>
            m := { m with queue := rest, bad := m.bad.push s!"reserve stopped at {t}: {repr r}" }
      | [] => go := false
    -- the poller
    let P := interval L m.s
    m := { m with maxP := max m.maxP P }
    match next L m.s with
    | .issue k c s' =>
      if let some t1 := m.lastTick then
        if m.onlyInterval && m.maxP < t - t1 then
          m := { m with bad := m.bad.push s!"tick gap {t - t1} > P {m.maxP} at {t}" }
      if !(s'.watched.all fun w => w.lastCovered == some t) then
        m := { m with bad := m.bad.push s!"tick at {t} left a run uncovered" }
      m := { m.call L f t k c s' with lastTick := some t, onlyInterval := true, maxP := 0 }
    | .wait u r =>
      if u ≤ t then m := { m with bad := m.bad.push s!"next waits into the past at {t}" }
      if r == .interval then
        if t + P < u then m := { m with bad := m.bad.push s!"interval wait {u - t} > P {P} at {t}" }
      else m := { m with onlyInterval := false }
    | .stop r =>
      if r != .idle || N > 0 then m := { m with bad := m.bad.push s!"next stopped at {t}: {repr r}" }
  return m

/-- The largest window sum over the issues of the selected kinds, for windows of length `W` ending at an issue. -/
def maxWindow (is : Array (Nat × Kind × Nat)) (W : Nat) (sel : Kind → Bool) : Nat :=
  is.foldl (fun acc (t, _, _) =>
    max acc (is.foldl (fun s (x, k, c) => if sel k && x ≤ t && t < x + W then s + c else s) 0)) 0

/-- Check one replay against the bounds and the fixture's expectations; returns the problems. -/
def check (L : Limits) (f : Fixture) (m : Sim) : Array String := Id.run do
  let mut bad := m.bad
  let isT := fun k => k == Kind.tick
  let isO := fun k => k == Kind.oneoff
  let hT := maxWindow m.issues L.W isT
  let hO := maxWindow m.issues L.W isO
  let mT := maxWindow m.issues L.W1 isT
  let mO := maxWindow m.issues L.W1 isO
  if 1800 < hT || 1200 < hO then bad := bad.push s!"hour share exceeded: tick {hT}, oneoff {hO}"
  if 20 < mT || 40 < mO then bad := bad.push s!"minute share exceeded: tick {mT}, oneoff {mO}"
  let hA := maxWindow m.issues L.W fun _ => true
  let mA := maxWindow m.issues L.W1 fun _ => true
  if 3000 < hA || 60 < mA then bad := bad.push s!"B exceeded: hour {hA}, minute {mA}"
  if let some x := f.ticksPerHourMax then
    if x < hT then bad := bad.push s!"ticks per hour {hT} > {x}"
  if let some x := f.oldExceeds then
    let old := oldRate L f.waiters 2 30 + oldRate L 1 4 3
    if old ≤ x then bad := bad.push s!"old per-agent rate {old} does not exceed {x}"
  for c in f.counts do
    let n := m.issues.foldl (fun s (t, k, _) =>
      if c.lo ≤ t && t < c.hi && (c.kind == "any" || c.kind == (match k with | .tick => "tick" | .oneoff => "oneoff"))
      then s + 1 else s) 0
    if n < c.min || c.max < n then bad := bad.push s!"{n} {c.kind} issues in [{c.lo}, {c.hi}), expected {c.min}..{c.max}"
  return bad

/-- Replay every fixture; returns the number of failing fixtures. -/
def replay (root : System.FilePath) : IO Nat := do
  let L := defaults
  let mut failed := 0
  if !(L.B == 3000 && L.B - L.R == 1800 && L.R == 1200 && L.F == 500 && L.Pmin == 30 && L.B1 == 60) then
    IO.println "ci-budget replay: limits differ from the task (B 3000 = 1800 + 1200, F 500, P_min 30, 60/min)"
    failed := failed + 1
  let d := Fw.Wire.Ci.Golden.dir root / "fixtures"
  let entries ← d.readDir
  let names := (entries.toList.map (·.fileName)).filter (·.endsWith ".jsonl") |>.mergeSort (· ≤ ·)
  if names.isEmpty then
    IO.println s!"ci-budget replay: no fixtures in {d}"
    failed := failed + 1
  for nm in names do
    let text ← IO.FS.readFile (d / nm)
    let ls := (text.splitOn "\n").filter (· ≠ "")
    match ls.mapM Json.parse >>= fixtureOf with
    | .error e =>
      IO.println s!"ci-budget replay: {nm}: {e}"
      failed := failed + 1
    | .ok f =>
      let t0 ← IO.monoMsNow
      let ns := if f.sweep.isEmpty then [f.waiters] else f.sweep
      let runs := ns.map fun n => simulate L f n
      let mut bad : Array String := #[]
      for m in runs do bad := bad ++ check L f m
      if let some m0 := runs.head? then
        for (n, m) in ns.zip runs do
          if m.issues != m0.issues then bad := bad.push s!"N = {n} issued other calls than N = {ns.headD 0}"
      let m := runs.headD { s := init 0, overrides := [] }
      let ticks := (m.issues.filter fun (_, k, _) => k == .tick).size
      let t1 ← IO.monoMsNow
      IO.println s!"ci-budget replay {f.name}: N {ns}, {m.issues.size} calls ({ticks} ticks), hour tick/oneoff {maxWindow m.issues L.W (· == .tick)}/{maxWindow m.issues L.W (· == .oneoff)}, minute {maxWindow m.issues L.W1 (fun _ => true)}, {bad.size} problems, {t1 - t0} ms"
      for b in bad.toList.take 5 do IO.println s!"  {b}"
      if !bad.isEmpty then failed := failed + 1
  return failed

end FwTest.CiBudget
