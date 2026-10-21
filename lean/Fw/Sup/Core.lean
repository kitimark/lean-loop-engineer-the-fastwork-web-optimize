import Fw.Sched.Admit
import Fw.Ops.Reap

/-! fw-sup supervisor model: state, events, commands and the pure `step : Cfg → State → Event → State × List Cmd`.
Stated limit: a nested join checks only that its parent job lease exists, and it outlives the parent's release. -/
namespace Fw.Sup

open Fw.Sched.Admit (Vec Res)

/-! ## Types -/

/-- A process group: its id and its leader's start second. -/
structure Ident where
  pgid : Nat
  start : Nat
deriving DecidableEq, Repr

/-- A stop signal. -/
inductive Sig where
  | term | kill
deriving DecidableEq, Repr

/-- Why a request is refused or a resource failed. -/
inductive Why where
  | deadline | draining | unknown | startFailed | restartCap | parent | renewCap
deriving DecidableEq, Repr

/-- The life phase of a resource. -/
inductive Phase where
  | absent
  | starting (since : Nat)
  | ready
  | stopping (since : Nat) (sig : Sig)
  | failed (till : Nat) (why : Why)
deriving DecidableEq, Repr

/-- Whether a phase holds a running process (starting, ready or stopping). -/
def Phase.live : Phase → Bool
  | .starting _ | .ready | .stopping _ _ => true
  | _ => false

/-- A supervised resource: id, kind, declared cost, phase, process group, adopted flag, observed footprint, last use and
the crash times kept for the restart window. -/
structure Rsrc where
  id : Nat
  kind : Nat
  cost : Vec
  phase : Phase := .absent
  proc : Option Ident := none
  adopted : Bool := false
  foot : Vec := {}
  lastUse : Nat := 0
  crashes : List Nat := []
deriving DecidableEq, Repr

/-- The two lease kinds: a budgeted job ticket or a share of a service resource. -/
inductive LKind where
  | job | svc
deriving DecidableEq, Repr

/-- A lease: id, owner, kind, resource id, cost, grant time, deadline and renew count. -/
structure Lease where
  id : Nat
  owner : Nat
  kind : LKind
  rid : Nat
  cost : Vec
  granted : Nat
  deadline : Nat
  renews : Nat := 0
deriving DecidableEq, Repr

/-- A queued request: id, owner, kind, resource id, cost, hold length, queue age, arrival time and deadline. -/
structure Req where
  id : Nat
  owner : Nat
  kind : LKind
  rid : Nat
  cost : Vec
  hold : Nat
  age : Nat
  born : Nat
  deadline : Nat
deriving DecidableEq, Repr

/-- The queue age an owner keeps for a resource after a refusal for cause. -/
structure Ticket where
  owner : Nat
  rid : Nat
  age : Nat
deriving DecidableEq, Repr

/-- One tick sample: pressure level, external footprint, footprint per owned group, live clients and process rows. -/
structure Sample where
  pressure : Nat := 0
  ext : Vec := {}
  foot : List (Ident × Vec) := []
  clients : List Nat := []
  rows : List Fw.Ops.Reap.Row := []

/-- The supervisor state. -/
structure State where
  res : List Rsrc := []
  leases : List Lease := []
  pending : List Req := []
  tickets : List Ticket := []
  obs : Sample := {}
  shedding : Bool := false
  draining : Bool := false
  now : Nat := 0
  next : Nat := 0

/-- The configuration: bearer token, budget, hysteresis margin, pressure warn level, wait and hold caps, renew cap,
start and kill timeouts, restart window and cap, and per-kind grace, cold-start cost and pinned flag. -/
structure Cfg where
  token : Nat
  budget : Vec
  margin : Vec := {}
  warn : Nat := 2
  maxWait : Nat
  holdMax : Nat
  renewCap : Nat
  startMax : Nat
  killAfter : Nat
  window : Nat
  maxRestarts : Nat
  grace : Nat → Nat
  coldStart : Nat → Nat
  pinned : Nat → Bool
  services : List Rsrc := []

/-- A signal target: a recorded group, a member row of the same sample, or a reap plan target. -/
inductive Target where
  | group (id : Ident)
  | member (pid start : Nat)
  | reap (t : Fw.Ops.Reap.Target)
deriving DecidableEq, Repr

/-- A reply to a client message. -/
inductive Reply where
  | granted (l : Lease)
  | refused (why : Why)
  | released
  | renewed (deadline : Nat)
  | op
  | draining
deriving DecidableEq, Repr

/-- The commands the shell executes. -/
inductive Cmd where
  | spawn (rid kind : Nat)
  | signal (t : Target) (sig : Sig)
  | probe (rid : Nat)
  | reply (req : Nat) (r : Reply)
  | revoke (owner lease : Nat)
  | exit
deriving DecidableEq, Repr

/-- A lease request: kind, resource id, cost, wait, hold and the parent lease of a nested request. -/
structure Ask where
  kind : LKind
  rid : Nat := 0
  cost : Vec := {}
  wait : Nat
  hold : Nat
  parent : Option Nat := none

/-- The events the shell feeds to `step`. -/
inductive Event where
  | request (tok owner : Nat) (a : Ask)
  | release (tok owner lease : Nat)
  | renew (tok owner lease : Nat)
  | op (tok owner : Nat)
  | drain (tok owner : Nat)
  | spawned (rid : Nat) (id : Option Ident)
  | ready (rid : Nat)
  | childExit (id : Ident)
  | tick (now : Nat) (smp : Sample)
  | clientGone (owner : Nat)
  | restart (now : Nat) (snap : State) (inp : Fw.Ops.Reap.Input)

/-! ## Budget -/

/-- The charge of a resource in one dimension: the larger of declared cost and observed footprint. -/
def charge (x : Rsrc) (d : Res) : Nat := max (x.cost.get d) (x.foot.get d)

/-- The summed charge of the live resources of a list. -/
def resLoad (rs : List Rsrc) (d : Res) : Nat := ((rs.filter (·.phase.live)).map (charge · d)).sum

/-- The summed cost of a list of leases. -/
def leaseLoad (ls : List Lease) (d : Res) : Nat := (ls.map (·.cost.get d)).sum

/-- The load of a state: live resource charge plus lease cost. -/
def used (s : State) (d : Res) : Nat := resLoad s.res d + leaseLoad s.leases d

/-- The summed charge of the stopping resources. -/
def stopLoad (s : State) (d : Res) : Nat :=
  ((s.res.filter fun x => match x.phase with | .stopping _ _ => true | _ => false).map (charge · d)).sum

/-- Whether `add` fits next to the load and the external footprint in every dimension. -/
def fitsB (c : Cfg) (s : State) (add : Res → Nat) : Bool :=
  Res.all.all fun d => decide (used s d + add d + s.obs.ext.get d ≤ c.budget.get d)

/-- Whether `add` fits once the stopping resources and the resources `xs` are gone. -/
def fitsFree (c : Cfg) (s : State) (add : Res → Nat) (xs : List Rsrc) : Bool :=
  Res.all.all fun d =>
    decide (used s d + add d + s.obs.ext.get d ≤ c.budget.get d + stopLoad s d + (xs.map (charge · d)).sum)

/-! ## Helpers -/

/-- The longest hold a lease gets per grant or renew (at least 1). -/
def hmax (c : Cfg) : Nat := max 1 c.holdMax

/-- The hold a request gets: its ask clamped to `[1, hmax]`. -/
def holdOf (c : Cfg) (h : Nat) : Nat := max 1 (min h (hmax c))

/-- The longest life of one lease: the first hold plus every allowed renew. -/
def span (c : Cfg) : Nat := hmax c * (1 + c.renewCap)

/-- The crash times inside the restart window ending at `now`. -/
def recent (c : Cfg) (now : Nat) (cs : List Nat) : List Nat := cs.filter fun t => decide (now < t + c.window)

/-- The service leases on a resource id. -/
def leasesOn (s : State) (rid : Nat) : List Lease := s.leases.filter fun l => l.kind == .svc && l.rid == rid

/-- The resource with an id. -/
def find (s : State) (rid : Nat) : Option Rsrc := s.res.find? (·.id == rid)

/-- Whether the resource with an id is ready. -/
def readyId (rs : List Rsrc) (rid : Nat) : Bool := rs.any fun x => x.id == rid && x.phase == .ready

/-- Queue order: older age first, then lower id. -/
def older (a b : Req) : Bool := a.age < b.age || (a.age == b.age && a.id < b.id)

/-- Insert a request before the first queued request it is older than. -/
def insertReq (q : Req) : List Req → List Req
  | [] => [q]
  | p :: ps => if older q p then q :: p :: ps else p :: insertReq q ps

/-- Whether a process row is the leader of a group. -/
def alive (rows : List Fw.Ops.Reap.Row) (id : Ident) : Bool := rows.any fun r => r.pid == id.pgid && r.start == id.start

/-- The footprint the sample reports for a group (zero when unseen). -/
def footOf (smp : Sample) : Option Ident → Vec
  | none => {}
  | some i => ((smp.foot.find? (·.1 == i)).map (·.2)).getD {}

/-- A KILL of the group of a resource, if it has one. -/
def killG : Option Ident → List Cmd
  | none => []
  | some i => [.signal (.group i) .kill]

/-- The smallest `k` in `[i, i + n]` with `p k`, or `i + n`. -/
def least (p : Nat → Bool) (i : Nat) : Nat → Nat
  | 0 => i
  | n + 1 => if p i then i else least p (i + 1) n

/-- Apply a per-resource transition to every resource, collecting its commands. -/
def mapRes (f : Rsrc → Rsrc × List Cmd) (s : State) : State × List Cmd :=
  ({ s with res := s.res.map fun x => (f x).1 }, s.res.flatMap fun x => (f x).2)

/-- Keep the leases with `p`, revoking the others. -/
def cut (p : Lease → Bool) (s : State) : State × List Cmd :=
  ({ s with leases := s.leases.filter p }, (s.leases.filter fun l => !p l).map fun l => .revoke l.owner l.id)

/-- Run two stages in sequence, concatenating their commands. -/
def andThen (f g : State → State × List Cmd) (s : State) : State × List Cmd :=
  let a := f s
  let b := g a.1
  (b.1, a.2 ++ b.2)

/-! ## Resource transitions -/

/-- A crash at `now`: the crash is recorded; at the restart cap the resource fails with `restartCap`, else with
`startFailed` when `fail`, else it becomes absent. -/
def crash (c : Cfg) (now : Nat) (fail : Bool) (x : Rsrc) : Rsrc :=
  let cs := now :: recent c now x.crashes
  { x with crashes := cs,
           phase := if c.maxRestarts ≤ cs.length then .failed (now + c.window) .restartCap
                    else if fail then .failed (now + c.window) .startFailed else .absent }

/-- A process exit: a stopping resource becomes absent; a starting or ready one crashed. -/
def exits (c : Cfg) (now : Nat) (x : Rsrc) : Rsrc :=
  match x.phase with
  | .stopping _ _ => { x with phase := .absent }
  | .starting _ | .ready => crash c now false x
  | _ => x

/-- Timeouts: an expired failure clears, a TERM older than `killAfter` escalates to KILL, a start older than
`startMax` fails with a KILL. -/
def ageRec (c : Cfg) (now : Nat) (x : Rsrc) : Rsrc × List Cmd :=
  match x.phase with
  | .failed u _ => (if u ≤ now then { x with phase := .absent } else x, [])
  | .stopping t .term =>
    if t + c.killAfter ≤ now then ({ x with phase := .stopping now .kill }, killG x.proc) else (x, [])
  | .starting t => if t + c.startMax ≤ now then (crash c now true x, killG x.proc) else (x, [])
  | _ => (x, [])

/-- An adopted live resource whose leader row is gone has exited (adopted children are seen by the ps poll only). -/
def goneRec (c : Cfg) (now : Nat) (rows : List Fw.Ops.Reap.Row) (x : Rsrc) : Rsrc :=
  match x.proc with
  | some i => if x.adopted && x.phase.live && !alive rows i then exits c now x else x
  | none => x

/-- Audit of a stopped resource that still names a group: KILL each row of the sample in the group that started no
earlier than the leader; forget the group when no such row is left or another process holds the leader's pid. -/
def auditRec (rows : List Fw.Ops.Reap.Row) (x : Rsrc) : Rsrc × List Cmd :=
  match x.proc with
  | some i =>
    if x.phase.live then (x, [])
    else
      let ms := rows.filter fun (r : Fw.Ops.Reap.Row) => r.pgid == i.pgid && decide (i.start ≤ r.start)
      if ms.isEmpty || rows.any (fun (r : Fw.Ops.Reap.Row) => r.pid == i.pgid && r.start != i.start) then
        ({ x with proc := none, adopted := false }, [])
      else (x, ms.map fun (r : Fw.Ops.Reap.Row) => .signal (.member r.pid r.start) .kill)
  | none => (x, [])

/-- The tick transition of one resource: footprint and last use refreshed, then timeouts, adopted exits, audit. -/
def tickRec (c : Cfg) (ls : List Lease) (now : Nat) (smp : Sample) (x : Rsrc) : Rsrc × List Cmd :=
  let x0 := { x with foot := footOf smp x.proc,
                     lastUse := if ls.any (fun l => l.kind == .svc && l.rid == x.id) then now else x.lastUse }
  let a := ageRec c now x0
  let x2 := goneRec c now smp.rows a.1
  let b := auditRec smp.rows x2
  (b.1, a.2 ++ b.2)

/-- Stop a ready resource whose id is listed: TERM to its group. -/
def stopRec (now : Nat) (ids : List Nat) (x : Rsrc) : Rsrc × List Cmd :=
  match x.proc with
  | some i =>
    if x.phase == .ready && ids.contains x.id then ({ x with phase := .stopping now .term }, [.signal (.group i) .term])
    else (x, [])
  | none => (x, [])

/-! ## Stop selection -/

/-- The resources that may be stopped: ready, with a group, not pinned, with no service lease. -/
def cands (c : Cfg) (s : State) : List Rsrc :=
  s.res.filter fun x => x.phase == .ready && x.proc.isSome && !c.pinned x.kind && (leasesOn s x.id).isEmpty

/-- The rank key: cold-start cost per MB of charge, cheapest to restart per MB freed first. -/
def rank (c : Cfg) (x : Rsrc) : Nat := c.coldStart x.kind * 1024 / (charge x .ram + 1)

/-- Insert a resource before the first one of higher rank. -/
def insRank (c : Cfg) (x : Rsrc) : List Rsrc → List Rsrc
  | [] => [x]
  | y :: ys => if rank c x ≤ rank c y then x :: y :: ys else y :: insRank c x ys

/-- The candidates in rank order. -/
def byRank (c : Cfg) (s : State) : List Rsrc := (cands c s).foldr (insRank c) []

/-- The idle candidates: unused for at least their kind's grace. -/
def idle (c : Cfg) (s : State) : List Rsrc := (cands c s).filter fun x => decide (x.lastUse + c.grace x.kind ≤ s.now)

/-- The shortest rank-order prefix of the candidates after which `add` fits, or all of them. -/
def prefixFor (c : Cfg) (s : State) (add : Res → Nat) : List Rsrc :=
  let cs := byRank c s
  cs.take (least (fun k => fitsFree c s add (cs.take k)) 0 cs.length)

/-- Shedding: every candidate under pressure at warn, else the prefix after which the margin fits. -/
def shedPick (c : Cfg) (s : State) : List Rsrc :=
  if c.warn ≤ s.obs.pressure then byRank c s else prefixFor c s c.margin.get

/-- Eviction for a blocked request of cost `add`: the prefix when all candidates together make it fit, else
nothing. -/
def evictPick (c : Cfg) (s : State) (add : Res → Nat) : List Rsrc :=
  if fitsFree c s add (byRank c s) then prefixFor c s add else []

/-- Stop every listed resource. -/
def stopAll (s : State) (xs : List Rsrc) : State × List Cmd := mapRes (stopRec s.now (xs.map (·.id))) s

/-- Whether the supervisor sheds: pressure at warn, over budget, or still within the margin of the budget. -/
def shedOn (c : Cfg) (s : State) : Bool :=
  decide (c.warn ≤ s.obs.pressure) || !fitsB c s (fun _ => 0) || (s.shedding && !fitsB c s c.margin.get)

/-! ## Client events -/

/-- Whether an event carries the configured token (internal events need none). -/
def authed (c : Cfg) : Event → Bool
  | .request t _ _ | .release t _ _ | .renew t _ _ | .op t _ | .drain t _ => t == c.token
  | _ => true

/-- A request: a nested one joins its parent job lease at once (cost zero) or is refused; any other is queued,
keeping the age of the owner's ticket for that resource. -/
def request (c : Cfg) (s : State) (o : Nat) (a : Ask) : State × List Cmd :=
  let n := s.next
  let s := { s with next := n + 1 }
  match a.parent with
  | some p =>
    match s.leases.find? (fun l => l.id == p && l.kind == .job) with
    | some pl =>
      if s.draining then (s, [.reply n (.refused .draining)])
      else
        let l : Lease := { id := n, owner := o, kind := .job, rid := pl.rid, cost := {}, granted := s.now,
                           deadline := min pl.deadline (s.now + holdOf c a.hold) }
        ({ s with leases := s.leases ++ [l] }, [.reply n (.granted l)])
    | none => (s, [.reply n (.refused .parent)])
  | none =>
    let mine := fun (t : Ticket) => t.owner == o && t.rid == a.rid
    let age := ((s.tickets.find? mine).map (·.age)).getD s.now
    let q : Req := { id := n, owner := o, kind := a.kind, rid := a.rid,
                     cost := if a.kind == .svc then {} else a.cost, hold := holdOf c a.hold, age := min age s.now,
                     born := s.now, deadline := s.now + min a.wait c.maxWait }
    ({ s with pending := insertReq q s.pending, tickets := s.tickets.filter fun t => !mine t }, [])

/-- A release: the owner's lease goes (its service is used now); unknown leases are released too. -/
def release (s : State) (o lid : Nat) : State × List Cmd :=
  let n := s.next
  let s := { s with next := n + 1 }
  match s.leases.find? (fun l => l.id == lid && l.owner == o) with
  | some l =>
    ({ s with leases := s.leases.filter (·.id != lid),
              res := s.res.map fun x => if l.kind == .svc && x.id == l.rid then { x with lastUse := s.now } else x },
     [.reply n .released])
  | none => (s, [.reply n .released])

/-- A renew: below the cap the deadline becomes at least `now + hmax`. -/
def renew (c : Cfg) (s : State) (o lid : Nat) : State × List Cmd :=
  let n := s.next
  let s := { s with next := n + 1 }
  match s.leases.find? (fun l => l.id == lid && l.owner == o) with
  | some l =>
    if l.renews < c.renewCap then
      let d := max l.deadline (s.now + hmax c)
      ({ s with leases := s.leases.map fun l' => if l'.id == lid then { l' with deadline := d, renews := l'.renews + 1 }
                                                 else l' },
       [.reply n (.renewed d)])
    else (s, [.reply n (.refused .renewCap)])
  | none => (s, [.reply n (.refused .unknown)])

/-! ## Internal events -/

/-- A spawn result: an error is a start failure; a group for the waiting record is recorded and probed; a group
nobody waits for is killed. -/
def spawned (c : Cfg) (s : State) (rid : Nat) : Option Ident → State × List Cmd
  | none =>
    ({ s with res := s.res.map fun x =>
        if x.id == rid && x.proc.isNone && (match x.phase with | .starting _ => true | _ => false)
        then crash c s.now true x else x }, [])
  | some i =>
    if s.res.any (·.proc == some i) then (s, [])
    else if s.res.any (fun x => x.id == rid && x.proc.isNone && match x.phase with | .starting _ => true | _ => false)
    then ({ s with res := s.res.map fun x => if x.id == rid then { x with proc := some i, adopted := false } else x },
          [.probe rid])
    else (s, [.signal (.group i) .kill])

/-- A passed health probe makes a starting resource with a group ready. -/
def readyEv (s : State) (rid : Nat) : State :=
  { s with res := s.res.map fun x =>
      if x.id == rid && x.proc.isSome && (match x.phase with | .starting _ => true | _ => false)
      then { x with phase := .ready, lastUse := s.now } else x }

/-- Keep a lease when it is a job or its resource is ready. -/
def svcOk (rs : List Rsrc) (l : Lease) : Bool := l.kind == .job || readyId rs l.rid

/-- A child exit: the resource with that group exits and the service leases on it are revoked. -/
def childExit (c : Cfg) (s : State) (i : Ident) : State × List Cmd :=
  let s1 := { s with res := s.res.map fun x => if x.proc == some i then exits c s.now x else x }
  cut (svcOk s1.res) s1

/-- A gone client: its leases, queued requests and tickets go, with no reply. -/
def gone (s : State) (o : Nat) : State :=
  { s with leases := s.leases.filter (·.owner != o), pending := s.pending.filter (·.owner != o),
           tickets := s.tickets.filter (·.owner != o) }

/-- The tick up to the shedding decision: clock, sample, gone clients, per-resource transitions, lease cut. -/
def observe (c : Cfg) (s : State) (now : Nat) (smp : Sample) : State × List Cmd :=
  let t := max s.now now
  let s1 := { s with now := t, obs := smp, pending := s.pending.filter (fun q => smp.clients.contains q.owner),
                     tickets := s.tickets.filter (fun k => smp.clients.contains k.owner) }
  let a := mapRes (tickRec c s.leases t smp) s1
  let keep := fun l : Lease => decide (t < l.deadline) && smp.clients.contains l.owner && svcOk a.1.res l
  let b := cut keep a.1
  ({ b.1 with shedding := shedOn c b.1 }, a.2 ++ b.2)

/-- The idle stops after `observe`. -/
def idleStage (c : Cfg) (s : State) : State × List Cmd := stopAll s (idle c s)

/-- The shedding stops after the idle stops. -/
def shedStage (c : Cfg) (s : State) : State × List Cmd :=
  if s.shedding then stopAll s (shedPick c s) else (s, [])

/-- A tick: observe, stop idle resources, shed, and exit once draining with no lease left. -/
def tick (c : Cfg) (s : State) (now : Nat) (smp : Sample) : State × List Cmd :=
  let a := observe c s now smp
  let b := idleStage c a.1
  let d := shedStage c b.1
  (d.1, a.2 ++ b.2 ++ d.2 ++ if d.1.draining && d.1.leases.isEmpty then [.exit] else [])

/-- A start phase restarted at `t`; any other phase is kept. -/
def Phase.restamp (t : Nat) : Phase → Phase
  | .starting _ => .starting t
  | p => p

/-- Whether a phase is starting. -/
def Phase.isStarting : Phase → Bool
  | .starting _ => true
  | _ => false

/-- Restart adoption at `t`: a live record whose group leader is in the rows and not claimed by an earlier record is
adopted, a starting one starting again at `t`; every other record forgets its group and a live one becomes absent. -/
def adopt (rows : List Fw.Ops.Reap.Row) (t : Nat) : List Ident → List Rsrc → List Rsrc
  | _, [] => []
  | seen, x :: xs =>
    match x.proc with
    | some i =>
      if x.phase.live && alive rows i && !seen.contains i then
        { x with adopted := true, phase := x.phase.restamp t } :: adopt rows t (i :: seen) xs
      else clear x :: adopt rows t seen xs
    | none => clear x :: adopt rows t seen xs
where
  /-- Forget the group; a live record becomes absent. -/
  clear (x : Rsrc) : Rsrc := { x with proc := none, adopted := false, phase := if x.phase.live then .absent else x.phase }

/-- The first record of each id. -/
def nubRes : List Rsrc → List Rsrc
  | [] => []
  | x :: xs => x :: (nubRes xs).filter (·.id != x.id)

/-- The first lease of each id. -/
def nubLease : List Lease → List Lease
  | [] => []
  | x :: xs => x :: (nubLease xs).filter (·.id != x.id)

/-- Whether a snapshot lease is well formed at `now` next to the recovered resources. -/
def validLease (c : Cfg) (rs : List Rsrc) (now : Nat) (l : Lease) : Bool :=
  decide (l.granted ≤ now) && decide (now < l.deadline) && decide (l.deadline ≤ l.granted + (l.renews + 1) * hmax c)
  && decide (l.renews ≤ c.renewCap) && (l.kind == .job || (readyId rs l.rid && l.cost == {}))

/-- Recovery from any snapshot and a fresh ps sample: adopt or forget each group, keep the well-formed leases and
revoke the rest, drop the queue, shed until the first tick, stop every reap plan target that no record owns, and
probe every adopted starting record. -/
def recover (c : Cfg) (now : Nat) (snap : State) (inp : Fw.Ops.Reap.Input) : State × List Cmd :=
  let t := max snap.now now
  let rs := adopt inp.rows t [] (nubRes snap.res)
  let ok := validLease c rs t
  let ls := nubLease (snap.leases.filter ok)
  let nx := ls.foldr (fun l n => max n (l.id + 1)) snap.next
  let owned := fun (p : Fw.Ops.Reap.Target) => rs.any fun x => x.proc.map (·.pgid) == some p.pid
  ({ res := rs, leases := ls, pending := [], tickets := [], obs := {}, shedding := true, draining := false,
     now := t, next := nx },
   (snap.leases.filter fun l => !ok l).map (fun l => .revoke l.owner l.id)
   ++ ((Fw.Ops.Reap.plan inp).filter fun p => !owned p).map (fun p => .signal (.reap p) .term)
   ++ (rs.filter (·.phase.isStarting)).map fun x => .probe x.id)

/-! ## The queue pump -/

/-- The pump accumulator: state, commands so far, and whether a request ahead is blocked on budget. -/
structure Acc where
  st : State
  out : List Cmd
  blk : Bool

/-- Keep a request queued; `b` marks it blocked on budget, and a request kept behind a blocked one leaves the mark set. -/
def keepQ (a : Acc) (q : Req) (b : Bool) : Acc :=
  { a with st := { a.st with pending := a.st.pending ++ [q] }, blk := a.blk || b }

/-- Answer a request and drop it. -/
def answer (a : Acc) (q : Req) (r : Reply) : Acc := { a with out := a.out ++ [.reply q.id r] }

/-- Refuse a request for cause. -/
def refuseT (a : Acc) (q : Req) (why : Why) : Acc :=
  { a with st := { a.st with tickets := a.st.tickets ++ [⟨q.owner, q.rid, q.age⟩] },
           out := a.out ++ [.reply q.id (.refused why)] }

/-- The lease a granted request gets. -/
def leaseOf (q : Req) (now : Nat) (cost : Vec) : Lease :=
  { id := q.id, owner := q.owner, kind := q.kind, rid := q.rid, cost := cost, granted := now,
    deadline := now + q.hold }

/-- Grant a request: the lease is added and the resource it names is used now. -/
def grant (a : Acc) (q : Req) : Acc :=
  let l := leaseOf q a.st.now (if q.kind == .svc then {} else q.cost)
  { a with st := { a.st with leases := a.st.leases ++ [l],
                             res := a.st.res.map fun x =>
                               if q.kind == .svc && x.id == q.rid then { x with lastUse := a.st.now } else x },
           out := a.out ++ [.reply q.id (.granted l)] }

/-- Keep a request blocked on budget; the first blocked request evicts idle resources when that makes it fit. -/
def block (c : Cfg) (a : Acc) (q : Req) (add : Res → Nat) : Acc :=
  if a.blk then keepQ a q true
  else
    let e := stopAll a.st (evictPick c a.st add)
    keepQ { a with st := e.1, out := a.out ++ e.2 } q true

/-- Start an absent resource for a request: it becomes starting and the shell spawns it. -/
def start (a : Acc) (q : Req) (r : Rsrc) : Acc :=
  keepQ { a with st := { a.st with res := a.st.res.map fun x =>
                           if x.id == r.id then { x with phase := .starting a.st.now, foot := {} } else x },
                 out := a.out ++ [.spawn r.id r.kind] } q false

/-- One queued request, in queue order. -/
def pumpOne (c : Cfg) (a : Acc) (q : Req) : Acc :=
  let st := a.st
  if q.deadline ≤ st.now then refuseT a q .deadline
  else if st.draining then answer a q (.refused .draining)
  else match q.kind with
    | .job =>
      if !st.shedding && !a.blk && fitsB c st q.cost.get then grant a q else block c a q q.cost.get
    | .svc =>
      match find st q.rid with
      | none => answer a q (.refused .unknown)
      | some r =>
        match r.phase with
        | .ready => if st.shedding || (a.blk && !c.pinned r.kind) then keepQ a q false else grant a q
        | .failed _ why => refuseT a q why
        | .absent =>
          if r.proc.isNone && !st.shedding && !a.blk && decide ((recent c st.now r.crashes).length < c.maxRestarts)
             && fitsB c st (charge r) then start a q r
          else block c a q (charge r)
        | _ => keepQ a q false

/-- The pump: every queued request once, in queue order. -/
def pump (c : Cfg) (s : State) : State × List Cmd :=
  let a := s.pending.foldl (pumpOne c) ⟨{ s with pending := [] }, [], false⟩
  (a.st, a.out)

/-! ## Step and run -/

/-- The event-specific stage before the pump. -/
def pre (c : Cfg) (s : State) : Event → State × List Cmd
  | .request _ o a => request c s o a
  | .release _ o l => release s o l
  | .renew _ o l => renew c s o l
  | .op _ _ => ({ s with next := s.next + 1 }, [.reply s.next .op])
  | .drain _ _ => ({ s with next := s.next + 1, draining := true }, [.reply s.next .draining])
  | .spawned rid i => spawned c s rid i
  | .ready rid => (readyEv s rid, [])
  | .childExit i => childExit c s i
  | .tick now smp => tick c s now smp
  | .clientGone o => (gone s o, [])
  | .restart now snap inp => recover c now snap inp

/-- The supervisor step: an event without the token changes nothing; any other runs its stage, then the pump. -/
def step (c : Cfg) (s : State) (e : Event) : State × List Cmd :=
  if authed c e then andThen (fun s => pre c s e) (pump c) s else (s, [])

/-- The state after a list of events and the concatenated commands. -/
def run (c : Cfg) (s : State) (es : List Event) : State × List Cmd :=
  es.foldl (fun a e => let r := step c a.1 e; (r.1, a.2 ++ r.2)) (s, [])

/-- The start state: the configured services, recovered from an empty sample at time 0. -/
def init (c : Cfg) : State := (recover c 0 { res := c.services } ⟨[], [], [], [], [], []⟩).1

/-! ## Examples -/

namespace Ex

/-- A config: 4 cores, 8 GB, wait 30 s, hold 60 s, 2 renews, grace 10 s, kind 7 pinned. -/
def cfg : Cfg :=
  { token := 42, budget := { cores := 40, ram := 8000 }, margin := { ram := 500 }, maxWait := 30, holdMax := 60,
    renewCap := 2, startMax := 20, killAfter := 5, window := 100, maxRestarts := 2, grace := fun _ => 10,
    coldStart := fun k => k * 10, pinned := fun k => k == 7,
    services := [{ id := 1, kind := 1, cost := { ram := 3000 } }, { id := 2, kind := 7, cost := { ram := 100 } }] }

/-- A job ask of 5000 MB. -/
def big : Ask := { kind := .job, cost := { ram := 5000 }, wait := 30, hold := 60 }

/-- A service ask on resource 1. -/
def sim : Ask := { kind := .svc, rid := 1, wait := 30, hold := 60 }

/-- A sample in which clients 1..3 live and nothing presses. -/
def calm : Sample := { clients := [1, 2, 3] }

/-- The state after a run from `init`. -/
def after (es : List Event) : State × List Cmd := run cfg (init cfg) es

end Ex

open Ex in
-- A job that fits is granted at once; a second one waits; a wrong token changes nothing.
#guard
  let r := after [.tick 1 calm, .request 42 1 big, .request 42 2 big, .request 9 3 big]
  r.2.contains (.reply 0 (.granted { id := 0, owner := 1, kind := .job, rid := 0, cost := { ram := 5000 }, granted := 1,
                                     deadline := 61 }))
  && r.1.pending.map (·.id) == [1] && r.1.next == 2

open Ex in
-- The waiting job is granted once the first is released; a nested request joins at once with cost zero.
#guard
  let r := after [.tick 1 calm, .request 42 1 big, .request 42 2 big, .request 42 3 { big with parent := some 0 },
                  .release 42 1 0]
  r.2.contains (.reply 2 (.granted { id := 2, owner := 3, kind := .job, rid := 0, cost := {}, granted := 1,
                                     deadline := 61 }))
  && r.2.any (fun c => match c with | .reply 1 (.granted _) => true | _ => false) && r.1.pending.isEmpty

open Ex in
-- A service request spawns the resource; the group is probed; ready grants the lease.
#guard
  let r := after [.tick 1 calm, .request 42 1 sim, .spawned 1 (some ⟨500, 7⟩), .ready 1]
  r.2.contains (.spawn 1 1) && r.2.contains (.probe 1)
  && r.2.any (fun c => match c with | .reply 0 (.granted l) => l.kind == .svc | _ => false)

open Ex in
-- Released and idle past its grace, the resource is stopped with TERM, then KILL after `killAfter`.
#guard
  let r := after [.tick 1 calm, .request 42 1 sim, .spawned 1 (some ⟨500, 7⟩), .ready 1, .release 42 1 0,
                  .tick 20 calm, .tick 30 calm]
  r.2.contains (.signal (.group ⟨500, 7⟩) .term) && r.2.contains (.signal (.group ⟨500, 7⟩) .kill)

open Ex in
-- A lease past its deadline is revoked at the tick; a waiter past its deadline is refused.
#guard
  let r := after [.tick 1 calm, .request 42 1 big, .request 42 2 big, .tick 62 calm]
  r.2.contains (.revoke 1 0) && r.2.contains (.reply 1 (.refused .deadline))

open Ex in
-- A start that never gets a group fails after `startMax`; its waiter is refused and keeps a ticket.
#guard
  let r := after [.tick 1 calm, .request 42 1 sim, .tick 25 calm]
  r.2.contains (.reply 0 (.refused .startFailed)) && r.1.tickets == [⟨1, 1, 1⟩]

open Ex in
-- Pressure at warn sheds: no grant, and the idle-free ready service is stopped while the pinned one is kept.
#guard
  let r := after [.tick 1 calm, .request 42 1 sim, .spawned 1 (some ⟨500, 7⟩), .ready 1, .release 42 1 0,
                  .tick 2 { calm with pressure := 2 }, .request 42 2 big]
  r.2.contains (.signal (.group ⟨500, 7⟩) .term) && r.1.shedding && r.1.pending.length == 1

open Ex in
-- Draining refuses waiters and exits once no lease is left; an unwanted group is killed.
#guard
  let r := after [.tick 1 calm, .request 42 1 big, .request 42 2 big, .drain 42 3, .spawned 2 (some ⟨9, 9⟩),
                  .release 42 1 0, .tick 3 calm]
  r.2.contains (.reply 1 (.refused .draining)) && r.2.contains .exit && r.2.contains (.signal (.group ⟨9, 9⟩) .kill)

open Ex in
-- Restart adopts a live group, forgets a dead one and reaps nothing it does not see.
#guard
  let snap : State := { res := [{ id := 1, kind := 1, cost := {}, phase := .ready, proc := some ⟨500, 7⟩ },
                                { id := 2, kind := 1, cost := {}, phase := .ready, proc := some ⟨600, 8⟩ }] }
  let inp : Fw.Ops.Reap.Input := ⟨[{ pid := 500, ppid := 1, pgid := 500, start := 7, cwd := none, kind := "x" }], [], [], [], [], []⟩
  let r := recover cfg 5 snap inp
  r.1.res.map (fun x => (x.phase, x.proc, x.adopted)) == [(.ready, some ⟨500, 7⟩, true), (.absent, none, false)]

open Ex in
-- An adopted starting record is probed and restamped; once it passes the probe it is not killed and records no crash.
#guard
  let snap : State := { res := [{ id := 1, kind := 1, cost := {}, phase := .starting 0, proc := some ⟨500, 7⟩ }] }
  let rows : List Fw.Ops.Reap.Row := [{ pid := 500, ppid := 1, pgid := 500, start := 7, cwd := none, kind := "x" }]
  let inp : Fw.Ops.Reap.Input := ⟨rows, [], [], [], [], []⟩
  let a := run cfg {} [.restart 1 snap inp, .tick 15 { calm with rows := rows }]
  let b := run cfg {} [.restart 1 snap inp, .ready 1, .tick 30 { calm with rows := rows }]
  a.2.contains (.probe 1) && a.1.res.map (·.phase) == [.starting 1]
  && !a.2.any (fun c => match c with | .signal _ .kill => true | _ => false)
  && !b.2.any (fun c => match c with | .signal _ .kill => true | _ => false) && b.1.res.map (·.crashes) == [[]]

-- The audit KILLs only rows of the group started no earlier than the leader, and forgets a group whose leader pid
-- another process holds.
#guard
  let x : Rsrc := { id := 1, kind := 1, cost := {}, phase := .absent, proc := some ⟨500, 7⟩ }
  let row := fun (pid st : Nat) => ({ pid := pid, ppid := 1, pgid := 500, start := st, cwd := none, kind := "x" } :
    Fw.Ops.Reap.Row)
  let r := step Ex.cfg { res := [x], now := 10 } (.tick 11 { Ex.calm with rows := [row 500 9999] })
  r.2 == [] && r.1.res.map (·.proc) == [none]
  && auditRec [row 501 3, row 502 8] x == (x, [.signal (.member 502 8) .kill])
  && (auditRec [row 501 3] x).2 == []

-- `least` finds the first index that passes, or the end.
#guard least (· ≥ 3) 0 10 == 3 && least (fun _ => false) 0 4 == 4 && least (fun _ => true) 2 4 == 2

-- Charge is the larger of declared cost and footprint; a job fits when load, request and external sum to the budget.
#guard charge { id := 1, kind := 1, cost := { ram := 300 }, foot := { ram := 900 } } .ram == 900
  && (let s : State := { leases := [⟨0, 1, .job, 0, { ram := 5000 }, 1, 61, 0⟩] }
      fitsB Ex.cfg s ({ ram := 3000 } : Vec).get && !fitsB Ex.cfg s ({ ram := 3001 } : Vec).get
      && !fitsB Ex.cfg { s with obs := { ext := { ram := 1 } } } ({ ram := 3000 } : Vec).get)

-- Holds are clamped to `[1, hmax]`; a lease lives at most `hmax · (1 + renewCap)`; crashes older than the window drop.
#guard holdOf Ex.cfg 0 == 1 && holdOf Ex.cfg 500 == 60 && holdOf Ex.cfg 30 == 30 && span Ex.cfg == 180
  && recent Ex.cfg 150 [10, 60, 140] == [60, 140]

-- The queue is ordered by age, then id; a ticket-aged request goes ahead of younger ones.
#guard
  let r := fun (i a : Nat) => (⟨i, 1, .job, 0, {}, 1, a, 0, 10⟩ : Req)
  (insertReq (r 9 3) [r 1 1, r 2 5]).map (·.id) == [1, 9, 2] && (insertReq (r 0 1) [r 1 1]).map (·.id) == [0, 1]
  && (insertReq (r 3 1) [r 1 1]).map (·.id) == [1, 3]

-- A group is alive when its leader row has the recorded start second.
#guard
  let rows : List Fw.Ops.Reap.Row := [{ pid := 500, ppid := 1, pgid := 500, start := 7, cwd := none, kind := "x" }]
  alive rows ⟨500, 7⟩ && !alive rows ⟨500, 8⟩ && !alive rows ⟨501, 7⟩

-- A crash below the cap leaves the record absent, a failed start fails it, the cap fails it for the window.
#guard
  let x : Rsrc := { id := 1, kind := 1, cost := {} }
  (crash Ex.cfg 5 false x).phase == .absent && (crash Ex.cfg 5 true x).phase == .failed 105 .startFailed
  && (crash Ex.cfg 5 false { x with crashes := [3] }).phase == .failed 105 .restartCap
  && (crash Ex.cfg 200 false { x with crashes := [3] }).phase == .absent

-- An exit makes a stopping record absent, crashes a ready one and leaves an absent one.
#guard
  let x : Rsrc := { id := 1, kind := 1, cost := {} }
  (exits Ex.cfg 5 { x with phase := .stopping 1 .term }).phase == .absent
  && (exits Ex.cfg 5 { x with phase := .ready }).crashes == [5] && exits Ex.cfg 5 x == x

-- Candidates exclude pinned and leased resources and are ranked by cold-start cost per MB; shedding at warn takes all,
-- eviction takes the shortest prefix that makes the request fit, or nothing.
#guard
  let a : Rsrc := { id := 1, kind := 1, cost := { ram := 3000 }, phase := .ready, proc := some ⟨10, 1⟩ }
  let b : Rsrc := { id := 3, kind := 2, cost := { ram := 100 }, phase := .ready, proc := some ⟨11, 1⟩ }
  let p : Rsrc := { id := 2, kind := 7, cost := { ram := 100 }, phase := .ready, proc := some ⟨12, 1⟩ }
  let s : State := { res := [b, p, a], now := 20 }
  (byRank Ex.cfg s).map (·.id) == [1, 3] && (idle Ex.cfg s).map (·.id) == [3, 1]
  && (idle Ex.cfg { s with now := 5 }).isEmpty
  && (cands Ex.cfg { s with leases := [⟨0, 1, .svc, 3, {}, 1, 61, 0⟩] }).map (·.id) == [1]
  && (shedPick Ex.cfg { s with obs := { pressure := 2 } }).map (·.id) == [1, 3] && (shedPick Ex.cfg s).isEmpty
  && (evictPick Ex.cfg s ({ ram := 6000 } : Vec).get).map (·.id) == [1]
  && (evictPick Ex.cfg s ({ ram := 12000 } : Vec).get).isEmpty

-- Shedding starts at warn pressure and holds while the load is within the margin of the budget.
#guard
  let s : State := { leases := [⟨0, 1, .job, 0, { ram := 7600 }, 1, 61, 0⟩] }
  shedOn Ex.cfg { obs := { pressure := 2 } } && !shedOn Ex.cfg {} && !shedOn Ex.cfg s
  && shedOn Ex.cfg { s with shedding := true }

-- Client events need the token; a service lease is kept only on a ready resource.
#guard
  let x : Rsrc := { id := 1, kind := 1, cost := {}, phase := .ready }
  !authed Ex.cfg (.request 9 1 Ex.big) && authed Ex.cfg (.request 42 1 Ex.big) && authed Ex.cfg (.tick 1 Ex.calm)
  && svcOk [x] ⟨0, 1, .svc, 1, {}, 1, 61, 0⟩ && !svcOk [x] ⟨0, 1, .svc, 2, {}, 1, 61, 0⟩
  && svcOk [] ⟨0, 1, .job, 2, {}, 1, 61, 0⟩

-- A snapshot lease survives recovery only while alive, within its hold and renew caps, and on a ready resource.
#guard
  let x : Rsrc := { id := 1, kind := 1, cost := {}, phase := .ready }
  validLease Ex.cfg [x] 5 ⟨0, 1, .job, 0, {}, 1, 61, 0⟩ && !validLease Ex.cfg [x] 61 ⟨0, 1, .job, 0, {}, 1, 61, 0⟩
  && !validLease Ex.cfg [x] 5 ⟨0, 1, .job, 0, {}, 1, 200, 0⟩ && validLease Ex.cfg [x] 5 ⟨0, 1, .svc, 1, {}, 1, 61, 0⟩
  && !validLease Ex.cfg [] 5 ⟨0, 1, .svc, 1, {}, 1, 61, 0⟩

-- Duplicates keep the first record of each id; a group gets a KILL only when recorded; unseen footprint is zero.
#guard
  let r := fun (i k : Nat) => ({ id := i, kind := k, cost := {} } : Rsrc)
  (nubRes [r 1 1, r 1 2, r 2 3]).map (·.kind) == [1, 3]
  && (nubLease [⟨0, 1, .job, 0, {}, 1, 61, 0⟩, ⟨0, 2, .job, 0, {}, 1, 61, 0⟩]).map (·.owner) == [1]
  && killG none == [] && killG (some ⟨5, 1⟩) == [.signal (.group ⟨5, 1⟩) .kill]
  && footOf { foot := [(⟨5, 1⟩, { ram := 70 })] } (some ⟨5, 1⟩) == { ram := 70 } && footOf {} (some ⟨5, 1⟩) == {}

end Fw.Sup
