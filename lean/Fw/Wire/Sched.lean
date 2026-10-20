import Lean.Data.Json
import Fw.Sched.Admit
import Fw.Sched.ParMetrics
import Fw.Measure.Wire
import Fw.Ops.Wire
import Fw.Wire.OpsGate
/-!
# JSON codecs and ops of `Fw.Sched` (`ops.admit`, `ops.gate`, `metrics.*`)

Glue between `fwcore`'s JSON lines and `Fw.Sched.Admit` / `Fw.Sched.ParMetrics` (namespace
`Fw.Wire.Sched`, so the math view treats it as wire code). Total decoders only (`Except String`);
no partial operations. Counts and times are non-negative integers; a non-integer number is refused.
Exact fractions are `{"num":"<int>","den":"<positive int>"}` (as `Fw.Wire.ratToJson`).

| op | request | reply |
|---|---|---|
| `ops.admit` | `budget` Vec, `state`? State, `event` Cmd, `probe`? [Item] | `state` (after `event`: the command, then admit until quiescent), `admitted` [id] (in admission order), `queued` [Decision] (every item still queued), `probes` [Decision] (each probe judged against the reply state as if enqueued now: `seq := next`, `enq := t`), `inv` (the input state satisfies `Inv`), `invAfter` |
| `ops.gate` | the `ops.spawn` fields (`alive`, `roles`, `caps`?, `recent`?, `now`, `req`), `budget` Vec, `state`? State (absent: the empty state), `item`? Item (absent: `{id: req.name}`, zero demand) | `decision` (`allow`/`needsApproval`/`deny`/`queue`), `accepted`, `reason` (the guard's reason on `deny`, the admission reason on `queue`, else null), `guard` (the `ops.spawn` reply), `admit` (Decision for the item judged as if enqueued now, always computed), `inv` |
| `ops.taskAdmit` | `running`? [Task], `candidates`? [Task] (Task: `{id, writes?, reads?}`, globs) | `pairs` [{a, b, kind, mine, theirs}] (each overlapping running pair a before b, its first clash; kind `ww`/`wr`/`rw`), `decisions` [{id, admitted, clash, message}] (each candidate against `running`; `message` = `not admitted: overlaps <task> on <glob> (…)`) |
| `metrics.merge` | `ivs` [[s, e]] | `ivs` |
| `metrics.busy` | `a`, `b`, `ivs` | `busy` |
| `metrics.speedup` | `a`, `b`, `agents` [[[s, e]]] | `speedup` (fraction) |
| `metrics.serialShare` | `a`, `b`, `agents` | `serial`, `serialShare` (fraction) |
| `metrics.stretch` | `d`, `dsolo` | `stretch` (fraction) |
| `metrics.cp` | `n`, `w` [nat], `edges` [[u, v]] | `cycle` (bool), `cp` (nat or `null` on a cycle) |
| `metrics.benchVerdict` | `labels` [bool] or `seed`, `ms` [int] | `labels`, `verdict` |

Shapes. Vec: `{cores?, ram?, cleanBuild?, docker?}` (missing = 0). Item: `{id, parent?, writes?,
deps?, demand?, devices?, seq?, enq?, base?, start?}` (devices `simulator`/`phone`). State: `{run?,
done?, queue?, t?, next?}`. Cmd: `{"type":"admit"}`, `{"type":"finish","id","landed"}`,
`{"type":"enqueue","item"}`, `{"type":"tick","now"}`. Decision: `{id, decision:"admit", reason:null}`
or `{id, decision:"queue", reason, …witness}` with reasons `neverFits {res}`, `depPending {dep}`,
`writeConflict {path, holder}`, `deviceBusy {device, holder}`, `overBudget {res, need, free}`,
`behindAged {behind}`. The encoders write every field, so a reply `state` can be sent back as is.

Proved: the round trips `stateOf_stateJson`, `itemOf_itemJson`, `vecOf_vecJson`, `cmdOf_cmdJson`,
`ivOf_ivJson`; `invB_iff` (the reply's `inv` flag is exactly `Inv`), `invB_event` (an event keeps
it), `event_queued_wait` (every `queued` decision is a `queue`) and `opAdmit_state` (the reply
state is `event`), `taskOf_taskJson` and `taskAdmitted_eq` (the `ops.taskAdmit` flag is `Reads.admits`), `gateName_accepted` (the `ops.gate` decision name is `allow`/`needsApproval` iff accepted; the gate itself is proved in `Fw.Wire.OpsGate`). Guards: `#guard`s at the end; golden vectors: `Fw.Wire.SchedGolden`.
-/
namespace Fw.Wire.Sched
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD arrD ostr)
open Fw.Sched.Admit
open Fw.Sched.ParMetrics

/-! ## Admit codecs -/

/-- Resource wire names. -/
def resName : Res → String
  | .cores => "cores" | .ram => "ram" | .cleanBuild => "cleanBuild" | .docker => "docker"

/-- Device wire names. -/
def devName : Dev → String
  | .simulator => "simulator" | .phone => "phone"

/-- A device from its wire name (an unknown name is refused). -/
def devOf (k : String) : String → Except String Dev
  | "simulator" => .ok .simulator | "phone" => .ok .phone
  | s => .error s!"field {k}: unknown device {s}"

/-- A demand or budget vector as JSON (every field written). -/
def vecJson (v : Vec) : Json :=
  Json.mkObj [("cores", toJson v.cores), ("ram", toJson v.ram), ("cleanBuild", toJson v.cleanBuild),
              ("docker", toJson v.docker)]

/-- Decode a vector; a missing field is 0. -/
def vecOf (j : Json) : Except String Vec := do
  pure { cores := ← natD j "cores" 0, ram := ← natD j "ram" 0, cleanBuild := ← natD j "cleanBuild" 0,
         docker := ← natD j "docker" 0 }

/-- An optional string field (absent or `null` is `none`). -/
def optS (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-- An optional array of strings (absent is empty). -/
def strsD (j : Json) (k : String) : Except String (List String) := do (← arrD j k).mapM (asStr k)

/-- A device as a JSON string. -/
def devJ (v : Json) : Except String Dev := do devOf "devices" (← asStr "devices" v)

/-- An item as JSON (every field written; `parent` is a string or `null`). -/
def itemJson (x : Item) : Json :=
  Json.mkObj [("id", .str x.id), ("parent", ostr x.parent), ("writes", .arr (x.writes.toArray.map .str)),
              ("deps", .arr (x.deps.toArray.map .str)), ("demand", vecJson x.demand),
              ("devices", .arr (x.devices.toArray.map fun v => .str (devName v))),
              ("seq", toJson x.seq), ("enq", toJson x.enq), ("base", toJson x.base), ("start", toJson x.start)]

/-- Decode an item; only `id` is required (lists default to empty, numbers to 0). -/
def itemOf (j : Json) : Except String Item := do
  let demand ← match opt j "demand" with
    | none => pure {}
    | some v => vecOf v
  pure { id := ← str j "id", parent := ← optS j "parent", writes := ← strsD j "writes",
         deps := ← strsD j "deps", demand, devices := ← (← arrD j "devices").mapM devJ,
         seq := ← natD j "seq" 0, enq := ← natD j "enq" 0, base := ← natD j "base" 0, start := ← natD j "start" 0 }

/-- A scheduler state as JSON (every field written). -/
def stateJson (σ : State) : Json :=
  Json.mkObj [("run", .arr (σ.run.toArray.map itemJson)), ("done", .arr (σ.done.toArray.map .str)),
              ("queue", .arr (σ.queue.toArray.map itemJson)), ("t", toJson σ.t), ("next", toJson σ.next)]

/-- Decode a scheduler state; every field is optional (absent is the empty state's value). -/
def stateOf (j : Json) : Except String State := do
  pure { run := ← (← arrD j "run").mapM itemOf, done := ← strsD j "done",
         queue := ← (← arrD j "queue").mapM itemOf, t := ← natD j "t" 0, next := ← natD j "next" 0 }

/-- Decode a command `{"type": …}`. -/
def cmdOf (j : Json) : Except String Cmd := do
  match ← str j "type" with
  | "admit" => pure .admit
  | "finish" => pure (.finish (← str j "id") (← asBool "landed" (← field j "landed")))
  | "enqueue" => pure (.enqueue (← itemOf (← field j "item")))
  | "tick" => pure (.tick (← nat j "now"))
  | s => throw s!"field type: unknown event {s}"

/-- A command as JSON (the form `cmdOf` reads). -/
def cmdJson : Cmd → Json
  | .admit => Json.mkObj [("type", .str "admit")]
  | .finish i l => Json.mkObj [("type", .str "finish"), ("id", .str i), ("landed", .bool l)]
  | .enqueue x => Json.mkObj [("type", .str "enqueue"), ("item", itemJson x)]
  | .tick n => Json.mkObj [("type", .str "tick"), ("now", toJson n)]

/-! ## Round trips: decoding an encoded value gives it back

So a reply `state` fed back as the next request's `state` is exactly the state the proofs talk
about. -/

/-- `Except.ok` then bind is application. -/
theorem ok_bind {ε α β : Type} (a : α) (f : α → Except ε β) : (Except.ok a >>= f) = f a := rfl

/-- Decoding a mapped list element-wise inverts the encoding when each element round-trips. -/
theorem mapM_rt {α : Type} (f : α → Json) (g : Json → Except String α) (h : ∀ a, g (f a) = .ok a) :
    ∀ l : List α, (l.map f).mapM g = .ok l
  | [] => rfl
  | a :: l => by simp [List.mapM_cons, h, mapM_rt f g h l]; rfl

/-- An array field reads back as its list. -/
theorem arrD_arr (j : Json) (k : String) (a : Array Json) (h : j.getObjVal? k = .ok (.arr a)) :
    arrD j k = .ok a.toList := by
  simp [arrD, opt, h]; rfl

/-- A string-array field reads back as its list of strings. -/
theorem strsD_rt (j : Json) (k : String) (l : List String)
    (h : j.getObjVal? k = .ok (.arr (l.toArray.map .str))) : strsD j k = .ok l := by
  simp only [strsD, arrD_arr j k _ h, Array.toList_map]
  exact mapM_rt .str (asStr k) (fun _ => rfl) l

/-- Devices round-trip. -/
theorem devJ_rt (v : Dev) : devJ (.str (devName v)) = .ok v := by cases v <;> rfl

/-- Vectors round-trip. -/
theorem vecOf_vecJson (v : Vec) : vecOf (vecJson v) = .ok v := by
  cases v; rfl

/-- Items round-trip. -/
theorem itemOf_itemJson (x : Item) : itemOf (itemJson x) = .ok x := by
  obtain ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩ := x
  have hw := strsD_rt (itemJson ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩)
    "writes" writes rfl
  have hd := strsD_rt (itemJson ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩)
    "deps" deps rfl
  have hv := arrD_arr (itemJson ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩)
    "devices" _ rfl
  have hdm : opt (itemJson ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩) "demand" =
      some (vecJson demand) := rfl
  have hp : optS (itemJson ⟨id, parent, writes, deps, demand, devices, seq, enq, base, start⟩) "parent" =
      .ok parent := by
    cases parent <;> rfl
  simp only [itemOf, hw, hd, hv, hdm, vecOf_vecJson, hp, Array.toList_map, ok_bind,
    mapM_rt (fun v => Json.str (devName v)) devJ devJ_rt devices]
  rfl

/-- States round-trip. -/
theorem stateOf_stateJson (σ : State) : stateOf (stateJson σ) = .ok σ := by
  obtain ⟨run, done, queue, t, next⟩ := σ
  have hr := arrD_arr (stateJson ⟨run, done, queue, t, next⟩) "run" _ rfl
  have hq := arrD_arr (stateJson ⟨run, done, queue, t, next⟩) "queue" _ rfl
  have hd := strsD_rt (stateJson ⟨run, done, queue, t, next⟩) "done" done rfl
  simp only [stateOf, hr, hq, hd, Array.toList_map, ok_bind, mapM_rt itemJson itemOf itemOf_itemJson]
  rfl

/-- Commands round-trip. -/
theorem cmdOf_cmdJson (c : Cmd) : cmdOf (cmdJson c) = .ok c := by
  cases c with
  | admit => rfl
  | finish i l => rfl
  | tick n => rfl
  | enqueue x =>
    have ht : str (cmdJson (.enqueue x)) "type" = .ok "enqueue" := rfl
    have h : field (cmdJson (.enqueue x)) "item" = .ok (itemJson x) := rfl
    simp only [cmdOf, ht, h, ok_bind, itemOf_itemJson]
    rfl

/-- The reason fields of a queue decision (the reason name and its witness). -/
def reasonFields : Reason → Reply
  | .neverFits r => [("reason", .str "neverFits"), ("res", .str (resName r))]
  | .depPending e => [("reason", .str "depPending"), ("dep", .str e)]
  | .writeConflict p y => [("reason", .str "writeConflict"), ("path", .str p), ("holder", .str y)]
  | .deviceBusy v y => [("reason", .str "deviceBusy"), ("device", .str (devName v)), ("holder", .str y)]
  | .overBudget r need free =>
    [("reason", .str "overBudget"), ("res", .str (resName r)), ("need", toJson need), ("free", toJson free)]
  | .behindAged z => [("reason", .str "behindAged"), ("behind", .str z)]

/-- A decision for one item as JSON. -/
def decisionJson (id : String) : Decision → Json
  | .admit => Json.mkObj [("id", .str id), ("decision", .str "admit"), ("reason", .null)]
  | .queue why => Json.mkObj ([("id", .str id), ("decision", .str "queue")] ++ reasonFields why)

/-! ## The invariant as a check -/

/-- The invariant `Inv` as a Boolean check (so `ops.admit` can say whether the proved guarantees
apply to the state it was given).

(see `invB_iff`)
-/
def invB (B : Vec) (σ : State) : Bool :=
  decide ((σ.run ++ σ.queue).map Item.id).Nodup && decide ((σ.run ++ σ.queue).map Item.seq).Nodup &&
  (σ.run ++ σ.queue).all (fun x => decide (x.seq < σ.next)) &&
  σ.run.all (fun x => decide (x.start ≤ σ.t)) &&
  σ.run.all (fun x => σ.run.all fun y => x.id == y.id || related x y || !wconf x y) &&
  σ.run.all (fun x => σ.run.all fun y => x.id == y.id || related x y || !devShare x y) &&
  σ.run.all (fun x => ready σ x) &&
  Res.all.all (fun r => decide (used σ.run r ≤ B.get r))

/-- The Boolean check is exactly the invariant. -/
theorem invB_iff (B : Vec) (σ : State) : invB B σ = true ↔ Inv B σ := by
  simp only [invB, Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, Bool.or_eq_true,
    beq_iff_eq, Bool.not_eq_true']
  constructor
  · rintro ⟨⟨⟨⟨⟨⟨⟨hi, hs⟩, hf⟩, hst⟩, hw⟩, hd⟩, hr⟩, hb⟩
    refine ⟨hi, hs, hf, hst, ?_, ?_, hr, fun r => hb r (Res.mem_all r)⟩
    · intro x hx y hy hne hrel
      rcases hw x hx y hy with (h | h) | h
      · exact absurd h hne
      · rw [h] at hrel; cases hrel
      · exact h
    · intro x hx y hy hne hrel
      rcases hd x hx y hy with (h | h) | h
      · exact absurd h hne
      · rw [h] at hrel; cases hrel
      · exact h
  · intro h
    refine ⟨⟨⟨⟨⟨⟨⟨h.ids, h.seqs⟩, h.fresh⟩, h.started⟩, ?_⟩, ?_⟩, h.deps⟩, fun r _ => h.budget r⟩
    · intro x hx y hy
      by_cases hne : x.id = y.id
      · exact Or.inl (Or.inl hne)
      · cases hrel : related x y
        · exact Or.inr (h.writes x hx y hy hne hrel)
        · exact Or.inl (Or.inr rfl)
    · intro x hx y hy
      by_cases hne : x.id = y.id
      · exact Or.inl (Or.inl hne)
      · cases hrel : related x y
        · exact Or.inr (h.devs x hx y hy hne hrel)
        · exact Or.inl (Or.inr rfl)

/-- Micro-step sequences keep the invariant. -/
theorem inv_steps {B : Vec} {σ τ : State} (h : Steps B σ τ) (hi : Inv B σ) : Inv B τ := by
  induction h with
  | refl => exact hi
  | head c _ ih => exact ih (inv_step B _ c hi)

/-- An `ops.admit` event keeps the invariant: if the input state passes the check, so does the
reply state.
-/
theorem invB_event (B : Vec) (σ : State) (c : Cmd) (h : invB B σ = true) :
    invB B (event B σ c) = true :=
  (invB_iff B _).mpr (inv_steps (steps_event B σ c) ((invB_iff B σ).mp h))

/-- After an event no queued item is admissible, so every `queued` decision of `ops.admit` is a
`queue` with a reason.
-/
theorem event_queued_wait (B : Vec) (σ : State) (c : Cmd) (x : Item)
    (hx : x ∈ (event B σ c).queue) : admit B (event B σ c) x ≠ .admit := by
  intro ha
  have hc := chosen_event B σ c
  simp only [chosen] at hc
  have hmem : x ∈ (event B σ c).queue.filter fun y => admit B (event B σ c) y == .admit := by
    simp [hx, ha]
  cases hq : (event B σ c).queue.filter fun y => admit B (event B σ c) y == .admit with
  | nil => rw [hq] at hmem; cases hmem
  | cons y ys => rw [hq] at hc; simp [pick] at hc

/-! ## ops.admit -/

/-- The items admitted by an event: the reply's running items that were not running after the
command, in admission order (`admitStep` prepends).
-/
def admittedIds (before after : State) : List String :=
  ((after.run.filter fun x => !before.run.any (·.id == x.id)).map (·.id)).reverse

/-- `ops.admit`: one event (the command, then admit until quiescent) with the decisions; probes are
judged as if enqueued now.
-/
def opAdmit (req : Json) : Except String Reply := do
  let B ← vecOf (← field req "budget")
  let σ ← match opt req "state" with
    | none => pure {}
    | some s => stateOf s
  let c ← cmdOf (← field req "event")
  let probe ← (← arrD req "probe").mapM itemOf
  let σ1 := step B σ c
  let σ' := admitAll B σ1
  let probe := probe.map fun x => { x with seq := σ'.next, enq := σ'.t }
  pure [("state", stateJson σ'), ("admitted", toJson (admittedIds σ1 σ')),
        ("queued", .arr (σ'.queue.toArray.map fun x => decisionJson x.id (admit B σ' x))),
        ("probes", .arr (probe.toArray.map fun x => decisionJson x.id (admit B σ' x))),
        ("inv", .bool (invB B σ)), ("invAfter", .bool (invB B σ'))]

/-- The reply state of `ops.admit` is the proved `event`. -/
theorem opAdmit_state (B : Vec) (σ : State) (c : Cmd) : admitAll B (step B σ c) = event B σ c := rfl

/-! ## ops.gate (task ops-gate) -/

/-- Decode the spawn guard's input from the `ops.spawn` request fields (`alive`, `roles`, `caps`?,
`recent`?, `now`, `req`), with the same defaults as `Fw.Wire.Ops.opSpawn`. -/
def inputOf (req : Json) : Except String Fw.Ops.SpawnGuard.Input := do
  let alive ← (← arr req "alive").toList.mapM fun a => do
    pure ({ name := ← str a "name", role := ← str a "role",
            kind := ← Fw.Wire.Ops.kindOf "alive.kind" (← str a "kind"),
            spawner := ← Fw.Wire.Ops.strD a "spawner" "" } : Fw.Ops.SpawnGuard.Agent)
  let roles ← (← arr req "roles").toList.mapM fun r => do
    pure ({ name := ← str r "name", runsAs := ← Fw.Wire.Ops.kindOf "roles.runsAs" (← str r "runsAs"),
            edits := ← Fw.Wire.Ops.boolD r "edits" false } : Fw.Ops.SpawnGuard.Role)
  let caps ← match opt req "caps" with
    | none => pure {}
    | some c => Fw.Wire.Ops.capsOf c
  let recent ← (← arrD req "recent").mapM fun r => do pure (← str r "spawner", ← nat r "at")
  let q ← field req "req"
  let rq : Fw.Ops.SpawnGuard.Req :=
    { name := ← Fw.Wire.Ops.strD q "name" "", role := ← str q "role", isolation := ← Fw.Wire.Ops.isolationOf q,
      model := ← Fw.Wire.Ops.strD q "model" "", spawner := ← Fw.Wire.Ops.strD q "spawner" "lead",
      depth := ← natD q "depth" 0 }
  pure ⟨alive, roles, caps, recent, ← nat req "now", rq⟩

/-- The spawn guard's reply for an input, field for field as `ops.spawn` writes it. -/
def guardReply (i : Fw.Ops.SpawnGuard.Input) : Reply :=
  let kind := [("kind", Json.str (Fw.Wire.Ops.kindName (Fw.Ops.SpawnGuard.effKind i.req))),
               ("wantKind", ostr ((Fw.Ops.SpawnGuard.wantKind i).map Fw.Wire.Ops.kindName))]
  match Fw.Ops.SpawnGuard.decide i with
  | .allow => [("decision", .str "allow"), ("reason", .null)] ++ kind
  | .needsApproval => [("decision", .str "needsApproval"), ("reason", .null)] ++ kind
  | .deny r => [("decision", .str "deny")] ++ Fw.Wire.Ops.reasonFields r ++ kind

open Fw.Wire.OpsGate (GateDecision gate) in
/-- The wire name of a gate decision. -/
def gateName : GateDecision → String
  | .guard .allow => "allow"
  | .guard .needsApproval => "needsApproval"
  | .guard (.deny _) => "deny"
  | .queue _ => "queue"

/-- The first value of a reply (the reason name of `reasonFields`), or `null` for an empty one. -/
def headVal : Reply → Json
  | (_, v) :: _ => v
  | [] => .null

open Fw.Wire.OpsGate (GateDecision) in
/-- The reason name of a gate decision: the guard's reason for a denial, the admission reason for
a queue, `null` otherwise. -/
def gateReason : GateDecision → Json
  | .guard (.deny r) => headVal (Fw.Wire.Ops.reasonFields r)
  | .guard _ => .null
  | .queue w => headVal (reasonFields w)

open Fw.Wire.OpsGate (GateDecision) in
/-- The wire name says `allow` or `needsApproval` exactly when the gate decision is accepted. -/
theorem gateName_accepted (g : GateDecision) :
    (gateName g = "allow" ∨ gateName g = "needsApproval") ↔ g.accepted = true := by
  rcases g with (_ | _ | _) | _ <;>
    simp [gateName, GateDecision.accepted, Fw.Ops.SpawnGuard.Decision.accepted]

/-- The item a spawn is judged as: the `item` field, or (absent) an item named after the request
with no demand, writes, dependencies or devices; in both cases enqueued now, with
`seq := next(σ)` and `enq := t(σ)` (as an `ops.admit` probe).
-/
def gateItem (σ : State) (x : Item) : Item := { x with seq := σ.next, enq := σ.t }

/-- `ops.gate`: the spawn guard, then admission of the spawn's item (`Fw.Wire.OpsGate.gate`).
The request is an `ops.spawn` request plus `budget`, `state`? and `item`?; the reply is the gate
decision with the guard's full reply and the admission decision (computed even after a denial,
for the shadow log).
-/
def opGate (req : Json) : Except String Reply := do
  let i ← inputOf req
  let B ← vecOf (← field req "budget")
  let σ ← match opt req "state" with
    | none => pure {}
    | some s => stateOf s
  let x ← match opt req "item" with
    | none => pure ({ id := i.req.name } : Item)
    | some j => itemOf j
  let x := gateItem σ x
  let g := Fw.Wire.OpsGate.gate i B σ x
  pure [("decision", .str (gateName g)), ("accepted", .bool g.accepted), ("reason", gateReason g),
        ("guard", Json.mkObj (guardReply i)), ("admit", decisionJson x.id (admit B σ x)),
        ("inv", .bool (invB B σ))]

/-! ## metrics.* codecs -/

/-- An exact fraction `{"num":"<int>","den":"<positive int>"}`, reduced (the form of `Fw.Wire.ratToJson`). -/
def ratJson (q : Rat) : Json :=
  Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- A pair `[a, b]` of natural numbers. -/
def pairOf (k : String) (j : Json) : Except String (Nat × Nat) := do
  match (← asArr k j).toList with
  | [a, b] => pure (← asNat k a, ← asNat k b)
  | _ => throw s!"field {k}: expected a pair [a, b]"

/-- An interval `[s, e]`. -/
def ivOf (k : String) (j : Json) : Except String Iv := do
  let (s, e) ← pairOf k j
  pure ⟨s, e⟩

/-- An interval as `[s, e]`. -/
def ivJson (i : Iv) : Json := .arr #[toJson i.s, toJson i.e]

/-- Intervals round-trip. -/
theorem ivOf_ivJson (k : String) (i : Iv) : ivOf k (ivJson i) = .ok i := by
  cases i; rfl

/-- A required list of intervals. -/
def ivsOf (j : Json) (k : String) : Except String (List Iv) := do (← arr j k).toList.mapM (ivOf k)

/-- A required list of agents, each a list of intervals. -/
def agentsOf (j : Json) (k : String) : Except String (List (List Iv)) := do
  (← arr j k).toList.mapM fun a => do (← asArr k a).toList.mapM (ivOf k)

/-- Verdict wire names (as `Fw.Wire.verdictName`). -/
def verdictName : Fw.Verdict.Verdict → String
  | .better => "better" | .worse => "worse" | .noise => "noise" | .tooFew => "tooFew"

/-! ## metrics.* ops -/

/-- `metrics.merge`: sort and fuse the intervals. -/
def opMerge (req : Json) : Except String Reply := do
  pure [("ivs", .arr ((merge (← ivsOf req "ivs")).toArray.map ivJson))]

/-- `metrics.busy`: merged busy time inside `[a, b)`. -/
def opBusy (req : Json) : Except String Reply := do
  pure [("busy", toJson (busy (← nat req "a") (← nat req "b") (← ivsOf req "ivs")))]

/-- `metrics.speedup`: summed busy time over the window length. -/
def opSpeedup (req : Json) : Except String Reply := do
  pure [("speedup", ratJson (speedup (← nat req "a") (← nat req "b") (← agentsOf req "agents")))]

/-- `metrics.serialShare`: time with at most one agent busy, and its share of the window. -/
def opSerialShare (req : Json) : Except String Reply := do
  let a ← nat req "a"
  let b ← nat req "b"
  let ag ← agentsOf req "agents"
  pure [("serial", toJson (serial a b ag)), ("serialShare", ratJson (serialShare a b ag))]

/-- `metrics.stretch`: `d / d_solo` (0 when `d_solo = 0`). -/
def opStretch (req : Json) : Except String Reply := do
  pure [("stretch", ratJson (stretch (← nat req "d") (← nat req "dsolo")))]

/-- `metrics.cp`: the critical path of a node-weighted graph, or `cycle`. -/
def opCp (req : Json) : Except String Reply := do
  let n ← nat req "n"
  let w ← (← arr req "w").toList.mapM (asNat "w")
  let es ← (← arr req "edges").toList.mapM (pairOf "edges")
  pure <| match cp n w es with
    | .ok c => [("cycle", .bool false), ("cp", toJson c)]
    | .cycle => [("cycle", .bool true), ("cp", .null)]

/-- `metrics.benchVerdict`: the bench verdict for a labeling (`labels`, or the one drawn by `seed`). -/
def opBenchVerdict (req : Json) : Except String Reply := do
  let labels ← match opt req "labels" with
    | some v => (← asArr "labels" v).toList.mapM (asBool "labels")
    | none => pure (labeling (← nat req "seed"))
  let ms ← (← arr req "ms").toList.mapM (Fw.Wire.Measure.asInt "ms")
  pure [("labels", toJson labels), ("verdict", .str (verdictName (benchVerdict labels ms)))]

/-! ## ops.taskAdmit (task admit-reads) -/

/-- A task as JSON (every field written). -/
def taskJson (t : Reads.Task) : Json :=
  Json.mkObj [("id", .str t.id), ("writes", .arr (t.writes.toArray.map .str)),
              ("reads", .arr (t.reads.toArray.map .str))]

/-- Decode a task; only `id` is required (`writes` and `reads` default to empty). -/
def taskOf (j : Json) : Except String Reads.Task := do
  pure { id := ← str j "id", writes := ← strsD j "writes", reads := ← strsD j "reads" }

/-- Tasks round-trip. -/
theorem taskOf_taskJson (t : Reads.Task) : taskOf (taskJson t) = .ok t := by
  obtain ⟨id, writes, reads⟩ := t
  have hw := strsD_rt (taskJson ⟨id, writes, reads⟩) "writes" writes rfl
  have hr := strsD_rt (taskJson ⟨id, writes, reads⟩) "reads" reads rfl
  simp only [taskOf, hw, hr, ok_bind]
  rfl

/-- Clash kind wire names. -/
def kindName : Reads.Kind → String
  | .ww => "ww"
  | .wr => "wr"
  | .rw => "rw"

/-- A clash as JSON. -/
def clashJson (c : Reads.Clash) : Json :=
  Json.mkObj [("task", .str c.task), ("kind", .str (kindName c.kind)), ("mine", .str c.mine),
              ("theirs", .str c.theirs)]

/-- The message of a refused start: `not admitted: overlaps <task> on <glob> (<task> writes|reads <glob>)`. -/
def clashMessage (c : Reads.Clash) : String :=
  let how := match c.kind with
    | .wr => "reads"
    | _ => "writes"
  s!"not admitted: overlaps {c.task} on {c.mine} ({c.task} {how} {c.theirs})"

/-- The reply's `admitted` flag: no first clash. -/
def taskAdmitted (run : List Reads.Task) (x : Reads.Task) : Bool := (Reads.blockAt run x).isNone

/-- The reply's `admitted` flag is the proved admission rule. -/
theorem taskAdmitted_eq (run : List Reads.Task) (x : Reads.Task) :
    taskAdmitted run x = Reads.admits run x := by
  apply Bool.eq_iff_iff.mpr
  rw [taskAdmitted, Option.isNone_iff_eq_none, Reads.blockAt_none]

/-- One candidate's decision: `{id, admitted, clash, message}` (`clash` and `message` null when admitted). -/
def taskDecisionJson (run : List Reads.Task) (x : Reads.Task) : Json :=
  match Reads.blockAt run x with
  | none => Json.mkObj [("id", .str x.id), ("admitted", .bool true), ("clash", .null), ("message", .null)]
  | some c => Json.mkObj [("id", .str x.id), ("admitted", .bool false), ("clash", clashJson c),
                          ("message", .str (clashMessage c))]

/-- `ops.taskAdmit`: the overlapping pairs of the running tasks (`Reads.overlapPairs`, first clash per
pair) and, for each candidate, the decision against the running tasks (`Reads.blockAt`).
-/
def opTaskAdmit (req : Json) : Except String Reply := do
  let run ← (← arrD req "running").mapM taskOf
  let cands ← (← arrD req "candidates").mapM taskOf
  pure [("pairs", .arr ((Reads.overlapPairs run).toArray.map fun (a, c) =>
          Json.mkObj [("a", .str a), ("b", .str c.task), ("kind", .str (kindName c.kind)), ("mine", .str c.mine),
                      ("theirs", .str c.theirs)])),
        ("decisions", .arr (cands.toArray.map (taskDecisionJson run)))]

/-! ## Dispatch -/

/-- The `Fw.Sched` ops. -/
def ops : List String :=
  ["ops.admit", "ops.gate", "ops.taskAdmit", "metrics.merge", "metrics.busy", "metrics.speedup", "metrics.serialShare", "metrics.stretch",
   "metrics.cp", "metrics.benchVerdict"]

/-- Dispatch a `Fw.Sched` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.admit" => some (opAdmit req)
  | "ops.gate" => some (opGate req)
  | "ops.taskAdmit" => some (opTaskAdmit req)
  | "metrics.merge" => some (opMerge req)
  | "metrics.busy" => some (opBusy req)
  | "metrics.speedup" => some (opSpeedup req)
  | "metrics.serialShare" => some (opSerialShare req)
  | "metrics.stretch" => some (opStretch req)
  | "metrics.cp" => some (opCp req)
  | "metrics.benchVerdict" => some (opBenchVerdict req)
  | _ => none

/-! ## Examples -/

/-- Run an op on a literal request (for the guards). -/
def run (op : String) (r : String) : String :=
  match Json.parse r with
  | .ok j => match handle op j with
    | some (.ok f) => (Json.mkObj f).compress
    | some (.error e) => s!"error: {e}"
    | none => "unknown op"
  | .error e => s!"parse: {e}"

#guard invB {} {} && !invB { cores := 1 } { run := [{ id := "a", demand := { cores := 2 } }], next := 1 }
#guard !invB {} { queue := [{ id := "a" }, { id := "a", seq := 1 }], next := 2 }
#guard (admittedIds {} (admitAll { cores := 4 } { queue := [{ id := "a", demand := { cores := 2 } },
  { id := "b", demand := { cores := 2 }, seq := 1 }], next := 2 })) == ["a", "b"]
#guard run "ops.admit" "{\"budget\":{\"cores\":4},\"event\":{\"type\":\"enqueue\",\"item\":{\"id\":\"a\",\"demand\":{\"cores\":2}}}}"
  |>.startsWith "{\"admitted\":[\"a\"]"
#guard gateName (.guard .needsApproval) == "needsApproval" && gateName (.guard (.deny .unnamed)) == "deny"
  && gateName (.queue (.depPending "a")) == "queue"
#guard gateReason (.guard (.deny (.capRole "r"))) == .str "capRole" && gateReason (.guard .allow) == .null
  && gateReason (.queue (.behindAged "z")) == .str "behindAged"
#guard (gateItem { t := 7, next := 3 } { id := "x", seq := 9, enq := 1 }) == { id := "x", seq := 3, enq := 7 }
#guard run "ops.gate" ("{\"alive\":[],\"roles\":[{\"name\":\"w\",\"runsAs\":\"worktree\"}],\"now\":0," ++
  "\"req\":{\"name\":\"w-1\",\"role\":\"w\",\"isolation\":\"worktree\"},\"budget\":{}}")
  |>.startsWith "{\"accepted\":true,\"admit\":{\"decision\":\"admit\",\"id\":\"w-1\""
#guard run "ops.gate" ("{\"alive\":[],\"roles\":[{\"name\":\"w\",\"runsAs\":\"worktree\"}],\"now\":0," ++
  "\"req\":{\"name\":\"w-1\",\"role\":\"w\",\"isolation\":\"worktree\"},\"budget\":{},\"item\":{\"id\":\"w-1\"," ++
  "\"demand\":{\"cores\":1}}}") |>.startsWith "{\"accepted\":false,"
#guard run "ops.taskAdmit" ("{\"running\":[{\"id\":\"w\",\"writes\":[\"packages/measure-wktr/src/**\"]}]," ++
  "\"candidates\":[{\"id\":\"e\",\"writes\":[\"packages/measure-*/**\"]},{\"id\":\"s\",\"writes\":[\"apps/site/**\"]}]}")
  == "{\"decisions\":[{\"admitted\":false,\"clash\":{\"kind\":\"ww\",\"mine\":\"packages/measure-*/**\"," ++
  "\"task\":\"w\",\"theirs\":\"packages/measure-wktr/src/**\"},\"id\":\"e\",\"message\":\"not admitted: overlaps w on " ++
  "packages/measure-*/** (w writes packages/measure-wktr/src/**)\"},{\"admitted\":true,\"clash\":null,\"id\":\"s\"," ++
  "\"message\":null}],\"pairs\":[]}"
#guard taskAdmitted [{ id := "r", reads := ["lean/Fw"] }] { id := "x", writes := ["lean/Fw/A.lean"] } == false
#guard run "metrics.cp" "{\"n\":2,\"w\":[1,1],\"edges\":[[0,1],[1,0]]}" == "{\"cp\":null,\"cycle\":true}"
#guard run "metrics.speedup" "{\"a\":0,\"b\":10,\"agents\":[[[0,6]],[[4,10]]]}" == "{\"speedup\":{\"den\":\"5\",\"num\":\"6\"}}"
#guard run "metrics.busy" "{\"a\":0,\"b\":10,\"ivs\":[[1,3.5]]}" == "error: field ivs: expected a non-negative integer"

end Fw.Wire.Sched
