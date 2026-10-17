import Fw
import FwTest.Golden
/-!
# `fwcore serve` tests

* `golden/console-board.jsonl` and `packages/contracts/golden/console-board.jsonl` equal
  `Fw.Wire.Serve.boardGolden` byte for byte (Lean is the source; regenerate with
  `lake env lean --run scripts/BoardGolden.lean`), every case's `request.state` is the projection of
  its `events`, and both the stateless `console.board` and the stateful
  `console.reset` + `console.replay` + `console.query` give its `response.board`.
* Serve lines: applying a synthetic log one `console.apply` line at a time, and replaying it in one
  `console.replay` line, give the same `console.query` reply.
* Timing (informational): 100,000 synthetic events through `exec` and through one `console.replay`
  line (JSON parse included).
-/
namespace FwTest.Serve
open Lean Fw.Console Fw.Serve

/-- The life of one synthetic card `i` with `k` build rounds: open, approve, `k` × (build, run start,
run finish, screen), a step (post, start, done), review, land request, landed: `8 + 4k` events. -/
def cardLife (i k : Nat) : List Event :=
  let c := s!"c{i}"
  let t := 1000 + i
  [⟨s!"{c}o", t, .owner, .cardOpen c "o" false⟩, ⟨s!"{c}a", t, .lead, .cardApprove c⟩] ++
  ((List.range k).flatMap fun j =>
    [⟨s!"{c}b{j}", t, .git, .cardBuild c s!"s{j}" "o"⟩,
     ⟨s!"{c}rs{j}", t, .script, .runStart s!"{c}r{j}" c .screen⟩,
     ⟨s!"{c}rf{j}", t, .script, .runFinish s!"{c}r{j}" true⟩,
     ⟨s!"{c}sc{j}", t, .script, .cardScreen c s!"s{j}" true⟩]) ++
  [⟨s!"{c}p", t, .script, .stepPost s!"{c}S" (some c) "Plug in" .action none⟩,
   ⟨s!"{c}st", t, .user, .stepStart s!"{c}S"⟩, ⟨s!"{c}sd", t, .user, .stepDone s!"{c}S"⟩,
   ⟨s!"{c}rv", t, .reviewer, .cardReview c s!"s{k-1}" "r" true⟩,
   ⟨s!"{c}lr", t, .lead, .cardLandRequest c s!"s{k-1}"⟩, ⟨s!"{c}l", t, .git, .cardLanded c s!"s{k-1}"⟩]

/-- A synthetic log: `cards` card lives of `k` rounds each, one after another. -/
def synth (cards k : Nat) : List Event :=
  (List.range cards).flatMap (cardLife · k)

/-- Board golden files equal the Lean generator, and every case answers its board both ways. -/
def boardGolden : IO Nat := do
  let r ← FwTest.Golden.root
  let want := Fw.Wire.Serve.boardGolden
  let mut bad := 0
  for p in [r / "golden" / "console-board.jsonl", r / ".." / "packages" / "contracts" / "golden" / "console-board.jsonl"] do
    let got ← FwTest.Golden.lines p
    if got != want then
      IO.println s!"board golden: {p} differs from Fw.Wire.Serve.boardGolden (regenerate: lake env lean --run scripts/BoardGolden.lean)"
      bad := bad + 1
  let mut i := 0
  for l in want do
    i := i + 1
    match Json.parse l with
    | .error e => IO.println s!"board golden line {i}: {e}"; bad := bad + 1
    | .ok c =>
      let req := c.getObjValD "request"
      let wantB := (c.getObjValD "response").getObjValD "board"
      let now := req.getObjValD "now"
      let seq := req.getObjValD "seq"
      let stateless := Fw.Wire.handleLine (Json.mkObj [("id", toJson i), ("op", "console.board"),
        ("state", req.getObjValD "state"), ("now", now), ("seq", seq)]).compress
      let (v1, _) := Fw.Wire.Serve.serveLine init (Json.mkObj [("op", "console.reset")]).compress
      let (v2, rep) := Fw.Wire.Serve.serveLine v1
        (Json.mkObj [("op", "console.replay"), ("events", c.getObjValD "events")]).compress
      let (_, q) := Fw.Wire.Serve.serveLine v2
        (Json.mkObj [("op", "console.query"), ("now", now), ("seq", seq)]).compress
      let ok := (Json.parse stateless).toOption.map (·.getObjValD "board") == some wantB &&
        (Json.parse q).toOption.map (·.getObjValD "board") == some wantB &&
        (Json.parse rep).toOption.map (fun j => (j.getObjValD "replayed").getObjValD "refused") == some (toJson 0) &&
        Fw.Wire.stateJson v2.st == req.getObjValD "state"
      unless ok do
        IO.println s!"board golden {(c.getObjValAs? String "name").toOption.getD "?"}: mismatch\n  stateless {stateless}\n  query {q}"
        bad := bad + 1
  IO.println s!"console-board golden: {want.length - bad}/{want.length} cases equal (stateless and serve)"
  return bad

/-- A `console.apply` line for one event. -/
def applyLine (e : Event) : String :=
  (Json.mkObj [("op", "console.apply"), ("event", Fw.Wire.Serve.eventJson e)]).compress

/-- Apply-by-apply lines and one replay line give the same query reply (and a refused event is
reported with no changed rows). -/
def serveEquiv : IO Nat := do
  let es := synth 30 3 ++ (synth 3 2).map (fun e => { e with key := e.key ++ "x" }) -- re-opens: refused
  let mut v := init
  let mut refusedOk := true
  for e in es do
    let (v', out) := Fw.Wire.Serve.serveLine v (applyLine e)
    v := v'
    if let .ok j := Json.parse out then
      if (j.getObjValD "outcome").getObjValD "accepted" == .bool false then
        refusedOk := refusedOk && (j.getObjValD "changed") == Json.mkObj [("cards", .arr #[]), ("steps", .arr #[]), ("runs", .arr #[])]
  let (_, q1) := Fw.Wire.Serve.serveLine v "{\"op\":\"console.query\",\"now\":99999999,\"seq\":7}"
  let (w, _) := Fw.Wire.Serve.serveLine init
    (Json.mkObj [("op", "console.replay"), ("events", .arr (es.toArray.map Fw.Wire.Serve.eventJson))]).compress
  let (_, q2) := Fw.Wire.Serve.serveLine w "{\"op\":\"console.query\",\"now\":99999999,\"seq\":7}"
  let ok := q1 == q2 && refusedOk && v.st == project es && w.st == project es
  IO.println s!"serve equivalence ({es.length} events, apply-by-apply vs replay vs project): {if ok then "equal" else "DIFFER"}"
  return if ok then 0 else 1

/-- Replay timing for 100,000 synthetic events (informational). -/
def timing : IO Unit := do
  let es := synth 4167 4 -- 4,167 cards × 24 events = 100,008 events
  let n := es.length
  let t0 ← IO.monoNanosNow
  let (v, _) := exec init (.replay es)
  let landed := (v.st.cards.filter (·.landed)).length
  let t1 ← IO.monoNanosNow
  IO.println s!"serve replay: {n} events, {landed} landed cards, exec {(t1 - t0) / 1000000} ms"
  let line := (Json.mkObj [("op", "console.replay"), ("events", .arr (es.toArray.map Fw.Wire.Serve.eventJson))]).compress
  let t2 ← IO.monoNanosNow
  let (v2, out) := Fw.Wire.Serve.serveLine init line
  let t3 ← IO.monoNanosNow
  IO.println s!"serve replay: one {line.utf8ByteSize / 1000000} MB line {(t3 - t2) / 1000000} ms ({v2.st.cards.length} cards; {out.take 80})"
  let t4 ← IO.monoNanosNow
  let (_, q) := Fw.Wire.Serve.serveLine v2 "{\"op\":\"console.query\",\"now\":0,\"seq\":0}"
  let t5 ← IO.monoNanosNow
  IO.println s!"serve query on that state: {(t5 - t4) / 1000000} ms ({q.utf8ByteSize / 1000} kB reply)"

end FwTest.Serve
