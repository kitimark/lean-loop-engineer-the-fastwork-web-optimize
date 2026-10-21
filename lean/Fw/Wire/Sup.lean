import Std.Data.TreeMap.Raw.Lemmas
import Fw.Sup.Core

/-! JSON wire of fw-sup: every event, command and state snapshot of `Fw.Sup.Core` as one versioned message
`{v, t, body}`, a total decoder, and `decode (encode m) = some m`. -/
namespace Fw.Wire.Sup
open Lean (Json JsonNumber)
open Fw.Sup (Ident Sig Why Phase Rsrc LKind Lease Req Ticket Sample State Target Reply Cmd Ask Event)
open Fw.Sched.Admit (Vec)
open Fw.Ops.Reap (Row Mcp Input)

/-- The wire version this module writes and the only one `decode` accepts; a new `Why` name raises it. -/
def version : Nat := 1

/-! ## Primitives -/

/-- A natural number as a JSON integer. -/
def num (x : Nat) : Json := .num (JsonNumber.fromNat x)

/-- A JSON integer that is a natural number. -/
def natOf : Json → Option Nat
  | .num ⟨.ofNat m, 0⟩ => some m
  | _ => none

/-- A JSON string. -/
def strOf : Json → Option String
  | .str s => some s
  | _ => none

/-- A JSON boolean. -/
def boolOf : Json → Option Bool
  | .bool b => some b
  | _ => none

/-- The value of a key of a JSON object. -/
def fld (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption

/-- A list as a JSON array. -/
def arrJson {α : Type} (f : α → Json) (l : List α) : Json := .arr (l.map f).toArray

/-- A JSON array decoded element by element; one bad element refuses the whole array. -/
def arrOf {α : Type} (g : Json → Option α) : Json → Option (List α)
  | .arr a => a.toList.mapM g
  | _ => none

/-- An option as `null` or its value. -/
def optJson {α : Type} (f : α → Json) : Option α → Json
  | none => .null
  | some x => f x

/-- `null` as `none`, any other value decoded as `some`. -/
def optOf {α : Type} (g : Json → Option α) : Json → Option (Option α)
  | .null => some none
  | j => (g j).map some

/-- A recorded console `(pid, record second)` as `{pid, at}`, the shape of `ops.lspReap`. -/
def keepJson (p : Nat × Nat) : Json := Json.mkObj [("pid", num p.1), ("at", num p.2)]

/-- Decode a recorded console `{pid, at}`. -/
def keepOf (j : Json) : Option (Nat × Nat) := do
  pure (← fld j "pid" >>= natOf, ← fld j "at" >>= natOf)

/-! ## Names -/

/-- The wire name of a signal. -/
def sigName : Sig → String
  | .term => "term"
  | .kill => "kill"

/-- The signal a wire name names. -/
def sigOf : Json → Option Sig
  | .str "term" => some .term
  | .str "kill" => some .kill
  | _ => none

/-- The wire name of a lease kind. -/
def lkindName : LKind → String
  | .job => "job"
  | .svc => "svc"

/-- The lease kind a wire name names. -/
def lkindOf : Json → Option LKind
  | .str "job" => some .job
  | .str "svc" => some .svc
  | _ => none

/-- The wire name of a refusal reason. -/
def whyName : Why → String
  | .deadline => "deadline"
  | .draining => "draining"
  | .unknown => "unknown"
  | .startFailed => "startFailed"
  | .restartCap => "restartCap"
  | .parent => "parent"
  | .renewCap => "renewCap"

/-- Every refusal reason of this version, in wire order. -/
def whys : List Why := [.deadline, .draining, .unknown, .startFailed, .restartCap, .parent, .renewCap]

/-- The refusal reason a wire name names, looked up in `whys`. -/
def whyOf : Json → Option Why
  | .str s => whys.find? (whyName · == s)
  | _ => none

/-! ## Records -/

/-- A resource vector. -/
def vecJson (v : Vec) : Json :=
  Json.mkObj [("cores", num v.cores), ("ram", num v.ram), ("cleanBuild", num v.cleanBuild), ("docker", num v.docker)]

/-- Decode a resource vector. -/
def vecOf (j : Json) : Option Vec := do
  pure { cores := ← fld j "cores" >>= natOf, ram := ← fld j "ram" >>= natOf,
         cleanBuild := ← fld j "cleanBuild" >>= natOf, docker := ← fld j "docker" >>= natOf }

/-- A process group identity. -/
def identJson (i : Ident) : Json := Json.mkObj [("pgid", num i.pgid), ("start", num i.start)]

/-- Decode a process group identity. -/
def identOf (j : Json) : Option Ident := do
  pure { pgid := ← fld j "pgid" >>= natOf, start := ← fld j "start" >>= natOf }

/-- A resource phase, tagged by `t`. -/
def phaseJson : Phase → Json
  | .absent => Json.mkObj [("t", .str "absent")]
  | .starting t => Json.mkObj [("t", .str "starting"), ("since", num t)]
  | .ready => Json.mkObj [("t", .str "ready")]
  | .stopping t g => Json.mkObj [("t", .str "stopping"), ("since", num t), ("sig", .str (sigName g))]
  | .failed u w => Json.mkObj [("t", .str "failed"), ("till", num u), ("why", .str (whyName w))]

/-- Decode a resource phase. -/
def phaseOf (j : Json) : Option Phase := do
  match ← fld j "t" with
  | .str "absent" => pure .absent
  | .str "starting" => pure (.starting (← fld j "since" >>= natOf))
  | .str "ready" => pure .ready
  | .str "stopping" => pure (.stopping (← fld j "since" >>= natOf) (← fld j "sig" >>= sigOf))
  | .str "failed" => pure (.failed (← fld j "till" >>= natOf) (← fld j "why" >>= whyOf))
  | _ => none

/-- A supervised resource. -/
def rsrcJson (x : Rsrc) : Json :=
  Json.mkObj [("id", num x.id), ("kind", num x.kind), ("cost", vecJson x.cost), ("phase", phaseJson x.phase),
    ("proc", optJson identJson x.proc), ("adopted", .bool x.adopted), ("foot", vecJson x.foot),
    ("lastUse", num x.lastUse), ("crashes", arrJson num x.crashes)]

/-- Decode a supervised resource. -/
def rsrcOf (j : Json) : Option Rsrc := do
  pure { id := ← fld j "id" >>= natOf, kind := ← fld j "kind" >>= natOf, cost := ← fld j "cost" >>= vecOf,
         phase := ← fld j "phase" >>= phaseOf, proc := ← fld j "proc" >>= optOf identOf,
         adopted := ← fld j "adopted" >>= boolOf, foot := ← fld j "foot" >>= vecOf,
         lastUse := ← fld j "lastUse" >>= natOf, crashes := ← fld j "crashes" >>= arrOf natOf }

/-- A lease. -/
def leaseJson (l : Lease) : Json :=
  Json.mkObj [("id", num l.id), ("owner", num l.owner), ("kind", .str (lkindName l.kind)), ("rid", num l.rid),
    ("cost", vecJson l.cost), ("granted", num l.granted), ("deadline", num l.deadline), ("renews", num l.renews)]

/-- Decode a lease. -/
def leaseOf (j : Json) : Option Lease := do
  pure { id := ← fld j "id" >>= natOf, owner := ← fld j "owner" >>= natOf, kind := ← fld j "kind" >>= lkindOf,
         rid := ← fld j "rid" >>= natOf, cost := ← fld j "cost" >>= vecOf, granted := ← fld j "granted" >>= natOf,
         deadline := ← fld j "deadline" >>= natOf, renews := ← fld j "renews" >>= natOf }

/-- A queued request. -/
def reqJson (q : Req) : Json :=
  Json.mkObj [("id", num q.id), ("owner", num q.owner), ("kind", .str (lkindName q.kind)), ("rid", num q.rid),
    ("cost", vecJson q.cost), ("hold", num q.hold), ("age", num q.age), ("born", num q.born),
    ("deadline", num q.deadline)]

/-- Decode a queued request. -/
def reqOf (j : Json) : Option Req := do
  pure { id := ← fld j "id" >>= natOf, owner := ← fld j "owner" >>= natOf, kind := ← fld j "kind" >>= lkindOf,
         rid := ← fld j "rid" >>= natOf, cost := ← fld j "cost" >>= vecOf, hold := ← fld j "hold" >>= natOf,
         age := ← fld j "age" >>= natOf, born := ← fld j "born" >>= natOf, deadline := ← fld j "deadline" >>= natOf }

/-- A kept queue age. -/
def ticketJson (t : Ticket) : Json := Json.mkObj [("owner", num t.owner), ("rid", num t.rid), ("age", num t.age)]

/-- Decode a kept queue age. -/
def ticketOf (j : Json) : Option Ticket := do
  pure { owner := ← fld j "owner" >>= natOf, rid := ← fld j "rid" >>= natOf, age := ← fld j "age" >>= natOf }

/-- A process-table row. -/
def rowJson (r : Row) : Json :=
  Json.mkObj [("pid", num r.pid), ("ppid", num r.ppid), ("pgid", num r.pgid), ("start", num r.start),
    ("cwd", optJson num r.cwd), ("kind", .str r.kind), ("wt", optJson .str r.wt), ("inRepo", .bool r.inRepo)]

/-- Decode a process-table row. -/
def rowOf (j : Json) : Option Row := do
  pure { pid := ← fld j "pid" >>= natOf, ppid := ← fld j "ppid" >>= natOf, pgid := ← fld j "pgid" >>= natOf,
         start := ← fld j "start" >>= natOf, cwd := ← fld j "cwd" >>= optOf natOf, kind := ← fld j "kind" >>= strOf,
         wt := ← fld j "wt" >>= optOf strOf, inRepo := ← fld j "inRepo" >>= boolOf }

/-- A lean-lsp-mcp process. -/
def mcpJson (m : Mcp) : Json := Json.mkObj [("pid", num m.pid), ("cwd", optJson num m.cwd)]

/-- Decode a lean-lsp-mcp process. -/
def mcpOf (j : Json) : Option Mcp := do
  pure { pid := ← fld j "pid" >>= natOf, cwd := ← fld j "cwd" >>= optOf natOf }

/-- The reap inputs of a restart. -/
def inputJson (i : Input) : Json :=
  Json.mkObj [("rows", arrJson rowJson i.rows), ("live", arrJson num i.live), ("mcps", arrJson mcpJson i.mcps),
    ("keep", arrJson keepJson i.keep), ("liveIds", arrJson .str i.liveIds), ("protect", arrJson num i.protect)]

/-- Decode the reap inputs of a restart. -/
def inputOf (j : Json) : Option Input := do
  pure { rows := ← fld j "rows" >>= arrOf rowOf, live := ← fld j "live" >>= arrOf natOf,
         mcps := ← fld j "mcps" >>= arrOf mcpOf, keep := ← fld j "keep" >>= arrOf keepOf,
         liveIds := ← fld j "liveIds" >>= arrOf strOf, protect := ← fld j "protect" >>= arrOf natOf }

/-- The footprint of one owned group. -/
def footJson (p : Ident × Vec) : Json := Json.mkObj [("id", identJson p.1), ("foot", vecJson p.2)]

/-- Decode the footprint of one owned group. -/
def footOf (j : Json) : Option (Ident × Vec) := do
  pure (← fld j "id" >>= identOf, ← fld j "foot" >>= vecOf)

/-- A tick sample. -/
def sampleJson (m : Sample) : Json :=
  Json.mkObj [("pressure", num m.pressure), ("ext", vecJson m.ext), ("foot", arrJson footJson m.foot),
    ("clients", arrJson num m.clients), ("rows", arrJson rowJson m.rows)]

/-- Decode a tick sample. -/
def sampleOf (j : Json) : Option Sample := do
  pure { pressure := ← fld j "pressure" >>= natOf, ext := ← fld j "ext" >>= vecOf,
         foot := ← fld j "foot" >>= arrOf footOf, clients := ← fld j "clients" >>= arrOf natOf,
         rows := ← fld j "rows" >>= arrOf rowOf }

/-- A state snapshot. -/
def stateJson (s : State) : Json :=
  Json.mkObj [("res", arrJson rsrcJson s.res), ("leases", arrJson leaseJson s.leases),
    ("pending", arrJson reqJson s.pending), ("tickets", arrJson ticketJson s.tickets), ("obs", sampleJson s.obs),
    ("shedding", .bool s.shedding), ("draining", .bool s.draining), ("now", num s.now), ("next", num s.next)]

/-- Decode a state snapshot. -/
def stateOf (j : Json) : Option State := do
  pure { res := ← fld j "res" >>= arrOf rsrcOf, leases := ← fld j "leases" >>= arrOf leaseOf,
         pending := ← fld j "pending" >>= arrOf reqOf, tickets := ← fld j "tickets" >>= arrOf ticketOf,
         obs := ← fld j "obs" >>= sampleOf, shedding := ← fld j "shedding" >>= boolOf,
         draining := ← fld j "draining" >>= boolOf, now := ← fld j "now" >>= natOf, next := ← fld j "next" >>= natOf }

/-- A lease request. -/
def askJson (a : Ask) : Json :=
  Json.mkObj [("kind", .str (lkindName a.kind)), ("rid", num a.rid), ("cost", vecJson a.cost), ("wait", num a.wait),
    ("hold", num a.hold), ("parent", optJson num a.parent)]

/-- Decode a lease request. -/
def askOf (j : Json) : Option Ask := do
  pure { kind := ← fld j "kind" >>= lkindOf, rid := ← fld j "rid" >>= natOf, cost := ← fld j "cost" >>= vecOf,
         wait := ← fld j "wait" >>= natOf, hold := ← fld j "hold" >>= natOf, parent := ← fld j "parent" >>= optOf natOf }

/-! ## Messages -/

/-- A reap stop target. -/
def reapJson (t : Fw.Ops.Reap.Target) : Json :=
  Json.mkObj [("pid", num t.pid), ("start", num t.start), ("group", .bool t.group)]

/-- Decode a reap stop target. -/
def reapOf (j : Json) : Option Fw.Ops.Reap.Target := do
  pure { pid := ← fld j "pid" >>= natOf, start := ← fld j "start" >>= natOf, group := ← fld j "group" >>= boolOf }

/-- A signal target, tagged by `t`. -/
def targetJson : Target → Json
  | .group i => Json.mkObj [("t", .str "group"), ("id", identJson i)]
  | .member p s => Json.mkObj [("t", .str "member"), ("pid", num p), ("start", num s)]
  | .reap r => Json.mkObj [("t", .str "reap"), ("target", reapJson r)]

/-- Decode a signal target. -/
def targetOf (j : Json) : Option Target := do
  match ← fld j "t" with
  | .str "group" => pure (.group (← fld j "id" >>= identOf))
  | .str "member" => pure (.member (← fld j "pid" >>= natOf) (← fld j "start" >>= natOf))
  | .str "reap" => pure (.reap (← fld j "target" >>= reapOf))
  | _ => none

/-- A reply, tagged by `t`. -/
def replyJson : Reply → Json
  | .granted l => Json.mkObj [("t", .str "granted"), ("lease", leaseJson l)]
  | .refused w => Json.mkObj [("t", .str "refused"), ("why", .str (whyName w))]
  | .released => Json.mkObj [("t", .str "released")]
  | .renewed d => Json.mkObj [("t", .str "renewed"), ("deadline", num d)]
  | .op => Json.mkObj [("t", .str "op")]
  | .draining => Json.mkObj [("t", .str "draining")]

/-- Decode a reply. -/
def replyOf (j : Json) : Option Reply := do
  match ← fld j "t" with
  | .str "granted" => pure (.granted (← fld j "lease" >>= leaseOf))
  | .str "refused" => pure (.refused (← fld j "why" >>= whyOf))
  | .str "released" => pure .released
  | .str "renewed" => pure (.renewed (← fld j "deadline" >>= natOf))
  | .str "op" => pure .op
  | .str "draining" => pure .draining
  | _ => none

/-- A shell command, tagged by `t`. -/
def cmdJson : Cmd → Json
  | .spawn r k => Json.mkObj [("t", .str "spawn"), ("rid", num r), ("kind", num k)]
  | .signal x g => Json.mkObj [("t", .str "signal"), ("target", targetJson x), ("sig", .str (sigName g))]
  | .probe r => Json.mkObj [("t", .str "probe"), ("rid", num r)]
  | .reply q r => Json.mkObj [("t", .str "reply"), ("req", num q), ("reply", replyJson r)]
  | .revoke o l => Json.mkObj [("t", .str "revoke"), ("owner", num o), ("lease", num l)]
  | .exit => Json.mkObj [("t", .str "exit")]

/-- Decode a shell command. -/
def cmdOf (j : Json) : Option Cmd := do
  match ← fld j "t" with
  | .str "spawn" => pure (.spawn (← fld j "rid" >>= natOf) (← fld j "kind" >>= natOf))
  | .str "signal" => pure (.signal (← fld j "target" >>= targetOf) (← fld j "sig" >>= sigOf))
  | .str "probe" => pure (.probe (← fld j "rid" >>= natOf))
  | .str "reply" => pure (.reply (← fld j "req" >>= natOf) (← fld j "reply" >>= replyOf))
  | .str "revoke" => pure (.revoke (← fld j "owner" >>= natOf) (← fld j "lease" >>= natOf))
  | .str "exit" => pure .exit
  | _ => none

/-- An event, tagged by `t`. -/
def eventJson : Event → Json
  | .request t o a => Json.mkObj [("t", .str "request"), ("tok", num t), ("owner", num o), ("ask", askJson a)]
  | .release t o l => Json.mkObj [("t", .str "release"), ("tok", num t), ("owner", num o), ("lease", num l)]
  | .renew t o l => Json.mkObj [("t", .str "renew"), ("tok", num t), ("owner", num o), ("lease", num l)]
  | .op t o => Json.mkObj [("t", .str "op"), ("tok", num t), ("owner", num o)]
  | .drain t o => Json.mkObj [("t", .str "drain"), ("tok", num t), ("owner", num o)]
  | .spawned r i => Json.mkObj [("t", .str "spawned"), ("rid", num r), ("id", optJson identJson i)]
  | .ready r => Json.mkObj [("t", .str "ready"), ("rid", num r)]
  | .childExit i => Json.mkObj [("t", .str "childExit"), ("id", identJson i)]
  | .tick n m => Json.mkObj [("t", .str "tick"), ("now", num n), ("sample", sampleJson m)]
  | .clientGone o => Json.mkObj [("t", .str "clientGone"), ("owner", num o)]
  | .restart n s i => Json.mkObj [("t", .str "restart"), ("now", num n), ("snap", stateJson s), ("input", inputJson i)]

/-- Decode an event. -/
def eventOf (j : Json) : Option Event := do
  match ← fld j "t" with
  | .str "request" => pure (.request (← fld j "tok" >>= natOf) (← fld j "owner" >>= natOf) (← fld j "ask" >>= askOf))
  | .str "release" =>
    pure (.release (← fld j "tok" >>= natOf) (← fld j "owner" >>= natOf) (← fld j "lease" >>= natOf))
  | .str "renew" => pure (.renew (← fld j "tok" >>= natOf) (← fld j "owner" >>= natOf) (← fld j "lease" >>= natOf))
  | .str "op" => pure (.op (← fld j "tok" >>= natOf) (← fld j "owner" >>= natOf))
  | .str "drain" => pure (.drain (← fld j "tok" >>= natOf) (← fld j "owner" >>= natOf))
  | .str "spawned" => pure (.spawned (← fld j "rid" >>= natOf) (← fld j "id" >>= optOf identOf))
  | .str "ready" => pure (.ready (← fld j "rid" >>= natOf))
  | .str "childExit" => pure (.childExit (← fld j "id" >>= identOf))
  | .str "tick" => pure (.tick (← fld j "now" >>= natOf) (← fld j "sample" >>= sampleOf))
  | .str "clientGone" => pure (.clientGone (← fld j "owner" >>= natOf))
  | .str "restart" =>
    pure (.restart (← fld j "now" >>= natOf) (← fld j "snap" >>= stateOf) (← fld j "input" >>= inputOf))
  | _ => none

/-- A wire message: an event for `step`, a command it emitted, or a persisted state snapshot. -/
inductive Msg where
  | event (e : Event)
  | cmd (c : Cmd)
  | snapshot (s : State)

/-- A message under a given version field. -/
def encodeAt (v : Nat) : Msg → Json
  | .event e => Json.mkObj [("v", num v), ("t", .str "event"), ("body", eventJson e)]
  | .cmd c => Json.mkObj [("v", num v), ("t", .str "cmd"), ("body", cmdJson c)]
  | .snapshot s => Json.mkObj [("v", num v), ("t", .str "snapshot"), ("body", stateJson s)]

/-- A message under the current `version`. -/
def encode (m : Msg) : Json := encodeAt version m

/-- Decode the tag and body of a message, whatever its version field. -/
def msgOf (j : Json) : Option Msg := do
  match ← fld j "t" with
  | .str "event" => pure (.event (← fld j "body" >>= eventOf))
  | .str "cmd" => pure (.cmd (← fld j "body" >>= cmdOf))
  | .str "snapshot" => pure (.snapshot (← fld j "body" >>= stateOf))
  | _ => none

/-- Decode a message; a version field other than `version` refuses it. -/
def decode (j : Json) : Option Msg :=
  (fld j "v" >>= natOf) >>= fun v => if v = version then msgOf j else none

#guard (decode (encode (.event (.request 42 1 { kind := .job, cost := { ram := 5000 }, wait := 30, hold := 60 })))).map
  encode == some (encode (.event (.request 42 1 { kind := .job, cost := { ram := 5000 }, wait := 30, hold := 60 })))
#guard (decode (encode (.cmd (.reply 3 (.refused .renewCap))))).map encode == some (encode (.cmd (.reply 3 (.refused .renewCap))))
#guard (decode (encode (.cmd (.signal (.group ⟨500, 7⟩) .kill)))).map encode == some (encode (.cmd (.signal (.group ⟨500, 7⟩) .kill)))
#guard (decode (encode (.snapshot { now := 9, next := 2, tickets := [⟨1, 1, 1⟩] }))).map encode
  == some (encode (.snapshot { now := 9, next := 2, tickets := [⟨1, 1, 1⟩] }))
#guard (decode (encodeAt 2 (.cmd .exit))).isNone
#guard (decode (encodeAt 0 (.cmd .exit))).isNone
#guard (decode (Json.mkObj [("t", .str "cmd"), ("body", cmdJson .exit)])).isNone
#guard (decode (Json.mkObj [("v", .str "1"), ("t", .str "cmd"), ("body", cmdJson .exit)])).isNone
#guard (decode (Json.mkObj [("v", num version), ("t", .str "cmd"),
  ("body", Json.mkObj [("t", .str "reply"), ("req", num 0),
    ("reply", Json.mkObj [("t", .str "refused"), ("why", .str "tooBig")])])])).isNone
#guard (decode (Json.mkObj [("v", num version), ("t", .str "note"), ("body", .null)])).isNone
#guard natOf (.num ⟨-1, 0⟩) == none && natOf (.num ⟨15, 1⟩) == none && natOf (num 7) == some 7
#guard (arrOf natOf (.arr #[num 1, .str "2"])).isNone && arrOf natOf (.arr #[]) == some []
#guard optOf natOf .null == some none && optOf natOf (num 3) == some (some 3) && (optOf natOf (.str "x")).isNone

/-! ## Round trips -/

theorem lookup_mem {l : List (String × Json)} {k : String} {v : Json} (h : l.lookup k = some v) : (k, v) ∈ l := by
  induction l with
  | nil => cases h
  | cons p ps ih =>
    obtain ⟨a, b⟩ := p
    cases e : (k == a)
    · simp only [List.lookup, e] at h
      exact List.Mem.tail _ (ih h)
    · simp only [List.lookup, e, Option.some.injEq] at h
      rw [beq_iff_eq.mp e, h]
      exact List.Mem.head _

theorem lookup_none {l : List (String × Json)} {k : String} (h : l.lookup k = none) :
    (l.map Prod.fst).contains k = false := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨a, b⟩ := p
    cases e : (k == a)
    · simp only [List.lookup, e] at h
      simp only [List.map_cons, List.contains_cons, ih h, Bool.or_false]
      exact e
    · simp only [List.lookup, e] at h
      cases h

/-- A key of an object written with distinct keys reads back as its value in the written list. -/
theorem fld_mkObj {l : List (String × Json)} (k : String) (hd : (l.map Prod.fst).Nodup) :
    fld (Json.mkObj l) k = l.lookup k := by
  have hd' : l.Pairwise (fun a b => ¬ compare a.1 b.1 = .eq) :=
    (List.pairwise_map.mp hd).imp fun h he => h (Std.LawfulEqCmp.eq_of_compare he)
  cases h : l.lookup k with
  | some v =>
    have e := Std.TreeMap.Raw.getElem?_ofList_of_mem (cmp := compare) (k := k) (k' := k)
      Std.ReflCmp.compare_self hd' (lookup_mem h)
    simp only [fld, Json.mkObj, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?, e]
    rfl
  | none =>
    have e := Std.TreeMap.Raw.getElem?_ofList_of_contains_eq_false (cmp := compare) (lookup_none h)
    simp only [fld, Json.mkObj, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?, e]
    rfl

theorem arrOf_arrJson {α : Type} (f : α → Json) (g : Json → Option α) (h : ∀ x, g (f x) = some x) (l : List α) :
    arrOf g (arrJson f l) = some l := by
  simp only [arrOf, arrJson]
  induction l with
  | nil => rfl
  | cons x xs ih => simp_all

theorem optOf_optJson {α : Type} (f : α → Json) (g : Json → Option α) (h : ∀ x, g (f x) = some x)
    (hn : ∀ x, f x ≠ .null) (o : Option α) : optOf g (optJson f o) = some o := by
  cases o with
  | none => rfl
  | some x =>
    simp only [optJson, optOf]
    split
    · exact absurd ‹_› (hn x)
    · simp [h]

theorem natOf_num (x : Nat) : natOf (num x) = some x := rfl

theorem num_ne (x : Nat) : num x ≠ .null := by simp [num]

theorem strOf_str (s : String) : strOf (.str s) = some s := rfl

theorem boolOf_bool (b : Bool) : boolOf (.bool b) = some b := rfl

theorem keepOf_keepJson (p : Nat × Nat) : keepOf (keepJson p) = some p := rfl

theorem sigOf_sigName (g : Sig) : sigOf (.str (sigName g)) = some g := by cases g <;> rfl

theorem lkindOf_lkindName (k : LKind) : lkindOf (.str (lkindName k)) = some k := by cases k <;> rfl

/-- Every refusal reason reads back from its wire name; a new `Why` constructor fails this proof until `whys` and
`whyName` name it. -/
theorem whyOf_whyName (w : Why) : whyOf (.str (whyName w)) = some w := by cases w <;> rfl

/-- No two refusal reasons share a wire name. -/
theorem whyName_nodup : (whys.map whyName).Nodup := by decide

theorem vecOf_vecJson (v : Vec) : vecOf (vecJson v) = some v := by
  obtain ⟨a, b, c, d⟩ := v; rfl

theorem identOf_identJson (i : Ident) : identOf (identJson i) = some i := by
  obtain ⟨a, b⟩ := i; rfl

theorem identJson_ne (i : Ident) : identJson i ≠ .null := by simp [identJson, Json.mkObj]

theorem phaseOf_phaseJson (p : Phase) : phaseOf (phaseJson p) = some p := by
  cases p with
  | stopping t g => cases g <;> rfl
  | failed u w => cases w <;> rfl
  | _ => rfl

theorem leaseOf_leaseJson (l : Lease) : leaseOf (leaseJson l) = some l := by
  obtain ⟨a, b, k, d, e, f, g, h⟩ := l
  cases k <;> rfl

theorem reqOf_reqJson (q : Req) : reqOf (reqJson q) = some q := by
  obtain ⟨a, b, k, d, e, f, g, h, i⟩ := q
  cases k <;> rfl

theorem ticketOf_ticketJson (t : Ticket) : ticketOf (ticketJson t) = some t := by
  obtain ⟨a, b, c⟩ := t; rfl

theorem rsrcOf_rsrcJson (x : Rsrc) : rsrcOf (rsrcJson x) = some x := by
  obtain ⟨a, b, c, p, o, d, f, u, cs⟩ := x
  simp [rsrcOf, rsrcJson, fld_mkObj, List.lookup, natOf_num, vecOf_vecJson, phaseOf_phaseJson, boolOf_bool,
    optOf_optJson identJson identOf identOf_identJson identJson_ne, arrOf_arrJson num natOf natOf_num]

theorem rowOf_rowJson (r : Row) : rowOf (rowJson r) = some r := by
  obtain ⟨a, b, c, d, w, k, t, i⟩ := r
  simp [rowOf, rowJson, fld_mkObj, List.lookup, natOf_num, strOf_str, boolOf_bool,
    optOf_optJson num natOf natOf_num num_ne, optOf_optJson Json.str strOf strOf_str (fun _ => Json.noConfusion)]

theorem mcpOf_mcpJson (m : Mcp) : mcpOf (mcpJson m) = some m := by
  obtain ⟨a, b⟩ := m
  simp [mcpOf, mcpJson, fld_mkObj, List.lookup, natOf_num, optOf_optJson num natOf natOf_num num_ne]

theorem inputOf_inputJson (i : Input) : inputOf (inputJson i) = some i := by
  obtain ⟨r, l, m, k, li, p⟩ := i
  simp [inputOf, inputJson, fld_mkObj, List.lookup, arrOf_arrJson rowJson rowOf rowOf_rowJson,
    arrOf_arrJson num natOf natOf_num, arrOf_arrJson mcpJson mcpOf mcpOf_mcpJson,
    arrOf_arrJson keepJson keepOf keepOf_keepJson, arrOf_arrJson Json.str strOf strOf_str]

theorem footOf_footJson (p : Ident × Vec) : footOf (footJson p) = some p := by
  obtain ⟨⟨a, b⟩, ⟨c, d, e, f⟩⟩ := p; rfl

theorem sampleOf_sampleJson (m : Sample) : sampleOf (sampleJson m) = some m := by
  obtain ⟨p, e, f, c, r⟩ := m
  simp [sampleOf, sampleJson, fld_mkObj, List.lookup, natOf_num, vecOf_vecJson,
    arrOf_arrJson footJson footOf footOf_footJson, arrOf_arrJson num natOf natOf_num,
    arrOf_arrJson rowJson rowOf rowOf_rowJson]

/-- A state snapshot reads back as itself. -/
theorem stateOf_stateJson (s : State) : stateOf (stateJson s) = some s := by
  obtain ⟨r, l, p, t, o, sh, dr, n, nx⟩ := s
  simp [stateOf, stateJson, fld_mkObj, List.lookup, natOf_num, boolOf_bool, sampleOf_sampleJson,
    arrOf_arrJson rsrcJson rsrcOf rsrcOf_rsrcJson, arrOf_arrJson leaseJson leaseOf leaseOf_leaseJson,
    arrOf_arrJson reqJson reqOf reqOf_reqJson, arrOf_arrJson ticketJson ticketOf ticketOf_ticketJson]

theorem askOf_askJson (a : Ask) : askOf (askJson a) = some a := by
  obtain ⟨k, r, c, w, h, p⟩ := a
  cases k <;> cases p <;> rfl

theorem reapOf_reapJson (t : Fw.Ops.Reap.Target) : reapOf (reapJson t) = some t := by
  obtain ⟨a, b, c⟩ := t; rfl

theorem targetOf_targetJson (t : Target) : targetOf (targetJson t) = some t := by
  cases t with
  | group i => obtain ⟨a, b⟩ := i; rfl
  | member p s => rfl
  | reap r => obtain ⟨a, b, c⟩ := r; rfl

/-- Every reply reads back as itself: grants, refusals with every reason, releases, renewals, ops and drains. -/
theorem replyOf_replyJson (r : Reply) : replyOf (replyJson r) = some r := by
  cases r with
  | granted l => obtain ⟨a, b, k, d, e, f, g, h⟩ := l; cases k <;> rfl
  | refused w => cases w <;> rfl
  | _ => rfl

/-- Every shell command reads back as itself: spawns, signals, probes, replies, revokes and the exit. -/
theorem cmdOf_cmdJson (c : Cmd) : cmdOf (cmdJson c) = some c := by
  cases c with
  | signal t g =>
    have := targetOf_targetJson t
    cases g <;> simp [cmdOf, cmdJson, fld_mkObj, List.lookup, this, sigOf_sigName]
  | reply q r =>
    have := replyOf_replyJson r
    simp [cmdOf, cmdJson, fld_mkObj, List.lookup, this, natOf_num]
  | _ => rfl

/-- Every event reads back as itself: requests, releases, renewals, ops, drains, spawn results, readiness, child
exits, ticks, client losses and restarts. -/
theorem eventOf_eventJson (e : Event) : eventOf (eventJson e) = some e := by
  cases e with
  | request t o a =>
    have := askOf_askJson a
    simp [eventOf, eventJson, fld_mkObj, List.lookup, this, natOf_num]
  | spawned r i =>
    have := optOf_optJson identJson identOf identOf_identJson identJson_ne i
    simp [eventOf, eventJson, fld_mkObj, List.lookup, this, natOf_num]
  | childExit i => obtain ⟨a, b⟩ := i; rfl
  | tick n m =>
    have := sampleOf_sampleJson m
    simp [eventOf, eventJson, fld_mkObj, List.lookup, this, natOf_num]
  | restart n s i =>
    have h1 := stateOf_stateJson s
    have h2 := inputOf_inputJson i
    simp [eventOf, eventJson, fld_mkObj, List.lookup, h1, h2, natOf_num]
  | _ => rfl

/-- Every message reads back as itself under the current version. -/
theorem decode_encode (m : Msg) : decode (encode m) = some m := by
  cases m with
  | event e =>
    have := eventOf_eventJson e
    simp [decode, msgOf, encode, encodeAt, fld_mkObj, List.lookup, this, natOf_num]
  | cmd c =>
    have := cmdOf_cmdJson c
    simp [decode, msgOf, encode, encodeAt, fld_mkObj, List.lookup, this, natOf_num]
  | snapshot s =>
    have := stateOf_stateJson s
    simp [decode, msgOf, encode, encodeAt, fld_mkObj, List.lookup, this, natOf_num]

/-- A message written under any other version is refused. -/
theorem decode_wrong_version (v : Nat) (m : Msg) (h : v ≠ version) : decode (encodeAt v m) = none := by
  cases m <;> simp [decode, encodeAt, fld_mkObj, List.lookup, natOf_num, h]

/-- Whatever `decode` accepts carries the current version in its `v` field. -/
theorem decode_version {j : Json} {m : Msg} (h : decode j = some m) : (fld j "v" >>= natOf) = some version := by
  simp only [decode] at h
  cases e : (fld j "v" >>= natOf) with
  | none => simp [e] at h
  | some v =>
    by_cases hv : v = version
    · rw [hv]
    · simp [e, hv] at h

end Fw.Wire.Sup
