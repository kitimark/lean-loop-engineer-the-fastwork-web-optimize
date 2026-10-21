import Fw.Wire.Sup

/-! Write (or with `--check`, verify and replay) `packages/contracts/golden/sup/wire.jsonl`: `{name, ok, wire}` per case
(Fw.Wire.Sup). Run from `lean/`: `lake env lean --run scripts/SupWireGolden.lean [--check]`. -/

open Lean Fw.Sup Fw.Wire.Sup

def path : System.FilePath := "../packages/contracts/golden/sup/wire.jsonl"

def line (name : String) (ok : Bool) (wire : Json) : String :=
  (Json.mkObj [("name", .str name), ("ok", .bool ok), ("wire", wire)]).compress ++ "\n"

def good (name : String) (m : Msg) : String := line name true (encode m)

def bad (name : String) (wire : Json) : String := line name false wire

def ask : Ask := { kind := .svc, rid := 1, cost := { cores := 10, ram := 300 }, wait := 30, hold := 60 }

def row : Fw.Ops.Reap.Row :=
  { pid := 501, ppid := 500, pgid := 500, start := 7, cwd := some 90, kind := "lspServe", wt := some "wf_1", inRepo := true }

def smp : Sample :=
  { pressure := 2, ext := { ram := 1200 }, foot := [(⟨500, 7⟩, { cores := 3, ram := 410 })], clients := [1, 2],
    rows := [row, { row with pid := 502, cwd := none, kind := "tool", wt := none, inRepo := false }] }

def lease : Lease := { id := 4, owner := 1, kind := .job, rid := 0, cost := { ram := 5000 }, granted := 1, deadline := 61 }

def phases : List Phase :=
  [.absent, .starting 3, .ready, .stopping 20 .term, .stopping 25 .kill, .failed 40 .startFailed]

def snap : State :=
  { res := phases.zipIdx.map fun (p, i) =>
      { id := i, kind := i % 3, cost := { ram := 100 * i }, phase := p,
        proc := if i % 2 == 0 then some ⟨600 + i, 9⟩ else none, adopted := i == 2, foot := { ram := 90 * i },
        lastUse := i, crashes := List.range i },
    leases := [lease, { lease with id := 5, kind := .svc, rid := 2, renews := 2 }],
    pending := [{ id := 6, owner := 3, kind := .job, rid := 0, cost := { cores := 20 }, hold := 60, age := 2, born := 3,
                  deadline := 33 }],
    tickets := [⟨3, 0, 2⟩], obs := smp, shedding := true, draining := false, now := 9, next := 7 }

def input : Fw.Ops.Reap.Input :=
  { rows := [row], live := [90], mcps := [⟨499, some 90⟩, ⟨498, none⟩], keep := [(700, 12)], liveIds := ["wf_1"],
    protect := [1] }

def events : List (String × Event) :=
  [("request job", .request 42 1 Ex.big), ("request svc", .request 42 2 ask),
   ("request nested", .request 42 3 { Ex.big with parent := some 0 }), ("release", .release 42 1 0),
   ("renew", .renew 42 1 0), ("op", .op 42 1), ("drain", .drain 42 1), ("spawned", .spawned 1 (some ⟨500, 7⟩)),
   ("spawn failed", .spawned 1 none), ("ready", .ready 1), ("child exit", .childExit ⟨500, 7⟩),
   ("tick calm", .tick 1 Ex.calm), ("tick sample", .tick 2 smp), ("client gone", .clientGone 3),
   ("restart", .restart 100 snap input)]

def replies : List (String × Reply) :=
  [("granted", .granted lease), ("released", .released), ("renewed", .renewed 121), ("op", .op),
   ("draining", .draining)] ++ whys.map fun w => (s!"refused {whyName w}", .refused w)

def targets : List (String × Target) :=
  [("group", .group ⟨500, 7⟩), ("member", .member 501 7), ("reap", .reap ⟨502, 8, true⟩)]

def cmds : List (String × Cmd) :=
  [("spawn", .spawn 1 1), ("probe", .probe 1), ("revoke", .revoke 1 4), ("exit", .exit)]
  ++ (targets.flatMap fun (n, t) => [Sig.term, .kill].map fun g => (s!"signal {n} {sigName g}", .signal t g))
  ++ replies.map fun (n, r) => (s!"reply {n}", .reply 0 r)

def trace : List Event :=
  [.tick 1 Ex.calm, .request 42 1 Ex.sim, .spawned 1 (some ⟨500, 7⟩), .ready 1, .release 42 1 0, .tick 20 Ex.calm,
   .tick 30 Ex.calm, .request 42 2 Ex.big, .request 42 3 Ex.big, .tick 92 Ex.calm]

def withV (v : Json) : Json := Json.mkObj [("v", v), ("t", .str "cmd"), ("body", cmdJson .exit)]

def refusedAs (why : String) : Json :=
  Json.mkObj [("v", num version), ("t", .str "cmd"), ("body", Json.mkObj [("t", .str "reply"), ("req", num 0),
    ("reply", Json.mkObj [("t", .str "refused"), ("why", .str why)])])]

def rejected : List String :=
  [bad "version 0" (encodeAt 0 (.cmd .exit)), bad "version 2" (encodeAt (version + 1) (.cmd .exit)),
   bad "version missing" (Json.mkObj [("t", .str "cmd"), ("body", cmdJson .exit)]),
   bad "version as string" (withV (.str "1")), bad "version negative" (withV (.num ⟨-1, 0⟩)),
   bad "version fraction" (withV (.num ⟨15, 1⟩)), bad "unknown message tag" (Json.mkObj [("v", num version),
     ("t", .str "note"), ("body", .null)]),
   bad "unknown why" (refusedAs "tooBig"),
   bad "event field missing" (Json.mkObj [("v", num version), ("t", .str "event"),
     ("body", Json.mkObj [("t", .str "release"), ("tok", num 42), ("owner", num 1)])])]

def text : String :=
  let r := Ex.after trace
  String.join <|
    events.map (fun (n, e) => good s!"event {n}" (.event e))
    ++ cmds.map (fun (n, c) => good s!"cmd {n}" (.cmd c))
    ++ [good "snapshot init" (.snapshot (init Ex.cfg)), good "snapshot phases" (.snapshot snap)]
    ++ trace.zipIdx.map (fun (e, i) => good s!"trace event {i}" (.event e))
    ++ r.2.zipIdx.map (fun (c, i) => good s!"trace cmd {i}" (.cmd c))
    ++ [good "trace snapshot" (.snapshot r.1)]
    ++ rejected

/-- The replay of one golden line read from disk: `ok` lines decode and re-encode to the same `wire`, the rest are refused. -/
def replay (l : String) : Except String Unit := do
  let j ← Json.parse l
  let name ← j.getObjValAs? String "name"
  let ok ← j.getObjValAs? Bool "ok"
  let wire ← j.getObjVal? "wire"
  match decode wire, ok with
  | some m, true => if encode m == wire then pure () else throw s!"{name}: re-encoding differs"
  | none, false => pure ()
  | some _, false => throw s!"{name}: decoded, expected a refusal"
  | none, true => throw s!"{name}: refused, expected a message"

def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let disk ← IO.FS.readFile path
    if disk != text then
      IO.eprintln "sup wire golden: differs from the Lean output (regenerate without --check)"; return 1
    let lines := (disk.splitOn "\n").filter (· ≠ "")
    for l in lines do
      if let .error e := replay l then
        IO.eprintln s!"sup wire golden: replay failed: {e}"; return 1
    IO.println s!"sup wire golden: up to date, {lines.length} lines replayed through the parser"; return 0
  else
    IO.FS.createDirAll "../packages/contracts/golden/sup"
    IO.FS.writeFile path text
    IO.println "sup wire golden: written"; return 0
