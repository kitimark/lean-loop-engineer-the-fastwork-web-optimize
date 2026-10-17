import Fw.Ops.Golden
/-!
# Golden vectors of `ops.admit`, `ops.gate` and `metrics.*`

`packages/contracts/golden/ops/{admit,metrics,gate}.jsonl`: one
line per case, `{"name", "request", "response"}`, where `request` carries its `op` and `response`
is what `fwcore` replies (without the `id`). Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/SchedGolden.lean           # write the files
cd lean && lake env lean --run scripts/SchedGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check, and also checks that every `ops.gate` reply's `guard` is the
`ops.spawn` reply to the same request. The first `ops.admit` cases form one scenario: each request's
`state` is the previous reply's `state`, so a consumer can replay them in order. Consumers: the
spawn-guard hook, `fw plan` and `fw job` (parallel plan §3.3), the bench and profile scripts
(`metrics.*`).
-/
namespace Fw.Wire.Sched.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)

/-- The budget of the admit cases: 4 cores (tenths are the caller's unit), 8 units of RAM, one
clean-build token, one Docker token. -/
def budget : String := "{\"cores\":4,\"ram\":8,\"cleanBuild\":1,\"docker\":1}"

/-- An enqueue event for an item given as JSON fields (base priority 1, so it ages after 300 s). -/
def enq (fields : String) : String := "{\"type\":\"enqueue\",\"item\":{\"base\":1," ++ fields ++ "}}"

/-- The scenario: (case name, event) applied in order from the empty state. -/
def scenario : List (String × String) := [
  ("enqueue a into an empty state: admitted at once",
   enq "\"id\":\"a\",\"writes\":[\"lean/Fw/A.lean\"],\"demand\":{\"cores\":2}"),
  ("enqueue b: lean/Fw covers a's file, so writeConflict held by a",
   enq "\"id\":\"b\",\"writes\":[\"lean/Fw\"],\"demand\":{\"cores\":1}"),
  ("enqueue c: 3 cores wanted, 2 free, so overBudget",
   enq "\"id\":\"c\",\"writes\":[\"apps/site\"],\"demand\":{\"cores\":3}"),
  ("enqueue kid (job of a, same file): related items may overlap, admitted",
   enq "\"id\":\"kid\",\"parent\":\"a\",\"writes\":[\"lean/Fw/A.lean\"],\"demand\":{\"cores\":1}"),
  ("enqueue s1 (simulator): admitted", enq "\"id\":\"s1\",\"devices\":[\"simulator\"]"),
  ("enqueue s2 (simulator): deviceBusy held by s1", enq "\"id\":\"s2\",\"devices\":[\"simulator\"]"),
  ("enqueue dep (needs a landed): depPending", enq "\"id\":\"dep\",\"deps\":[\"a\"]"),
  ("enqueue big (9 RAM > 8): neverFits, named at enqueue", enq "\"id\":\"big\",\"demand\":{\"ram\":9}"),
  ("enqueue a again: an id already present is ignored", enq "\"id\":\"a\",\"demand\":{\"cores\":1}"),
  ("tick to 100: the clock moves, nothing changes", "{\"type\":\"tick\",\"now\":100}"),
  ("tick back to 50: time never runs backwards", "{\"type\":\"tick\",\"now\":50}"),
  ("a lands: dep (ready now) and c (3 cores free) are admitted; b still conflicts with kid",
   "{\"type\":\"finish\",\"id\":\"a\",\"landed\":true}"),
  ("s1 ends without landing: s2 gets the simulator", "{\"type\":\"finish\",\"id\":\"s1\",\"landed\":false}"),
  ("tick to 400: the queued items are aged (300 s per base level)", "{\"type\":\"tick\",\"now\":400}"),
  ("enqueue e (lean/Fw/B.lean): free of running items but behindAged b, which it competes with",
   enq "\"id\":\"e\",\"writes\":[\"lean/Fw/B.lean\"]"),
  ("kid lands: b is admitted; e now conflicts with b", "{\"type\":\"finish\",\"id\":\"kid\",\"landed\":true}"),
  ("finish an unknown id: nothing changes", "{\"type\":\"finish\",\"id\":\"nobody\",\"landed\":true}"),
  ("admit event on a quiescent state: nothing changes", "{\"type\":\"admit\"}")]

/-- The scenario as cases: each request carries the previous reply's state. -/
def scenarioCases : List (String × Json) :=
  (scenario.foldl (fun (acc : List (String × Json) × Json) (name, ev) =>
    let req := Json.mkObj [("budget", lit budget), ("state", acc.2), ("event", lit ev)]
    let st := ((respond "ops.admit" req).getObjVal? "state").toOption.getD (Json.mkObj [])
    (acc.1 ++ [(name, req)], st)) ([], Json.mkObj [])).1

/-- One admit request: the budget, a literal state and event, extra top-level fields. -/
def admitReq (state ev extra : String) : Json :=
  lit s!"\{\"budget\":{budget},\"state\":{state},\"event\":{ev}{extra}}"

/-- A state with `r` (3 cores) running, an aged `o` (2 cores) and a later `x` (1 core) queued. -/
def agedState : String :=
  "{\"run\":[{\"id\":\"r\",\"demand\":{\"cores\":3}}],\"queue\":[{\"id\":\"o\",\"writes\":[\"apps/site\"],\"demand\":{\"cores\":2},\"seq\":1},{\"id\":\"x\",\"writes\":[\"docs\"],\"demand\":{\"cores\":1},\"seq\":2},{\"id\":\"y\",\"writes\":[\"research\"],\"seq\":3,\"base\":2}],\"t\":0,\"next\":4}"

/-- The `ops.admit` cases: the scenario, then single cases. -/
def admitCases : List (String × Json) := scenarioCases ++ [
  ("no state field: the empty state", admitReq "{}" "{\"type\":\"admit\"}" ""),
  ("aged o over budget holds x and y back (behindAged), though both would fit",
   admitReq agedState "{\"type\":\"tick\",\"now\":10}" ""),
  ("r ends: o, x and y are admitted in before-order",
   admitReq agedState "{\"type\":\"finish\",\"id\":\"r\",\"landed\":true}" ""),
  ("probe: decisions for items not in the queue, against the state after the event",
   admitReq agedState "{\"type\":\"admit\"}"
     ",\"probe\":[{\"id\":\"p1\",\"writes\":[\"apps/site/x.ts\"]},{\"id\":\"p2\",\"demand\":{\"docker\":2}},{\"id\":\"p3\",\"deps\":[\"r\"]}]"),
  ("the clean-build token is exclusive by budget",
   admitReq "{\"run\":[{\"id\":\"lake1\",\"demand\":{\"cleanBuild\":1}}],\"next\":1}"
     "{\"type\":\"enqueue\",\"item\":{\"id\":\"lake2\",\"demand\":{\"cleanBuild\":1}}}" ""),
  ("a state breaking the invariant is answered, with inv false",
   admitReq "{\"queue\":[{\"id\":\"d\"},{\"id\":\"d\",\"seq\":1}],\"next\":2}" "{\"type\":\"admit\"}" ""),
  ("over-budget running state: inv false, invAfter false",
   admitReq "{\"run\":[{\"id\":\"h\",\"demand\":{\"cores\":5}}],\"next\":1}" "{\"type\":\"tick\",\"now\":1}" ""),
  ("unknown event type is refused", admitReq "{}" "{\"type\":\"pause\"}" ""),
  ("unknown device is refused",
   admitReq "{}" "{\"type\":\"enqueue\",\"item\":{\"id\":\"z\",\"devices\":[\"tablet\"]}}" ""),
  ("missing budget is refused", lit "{\"event\":{\"type\":\"admit\"}}"),
  ("a non-integer demand is refused",
   admitReq "{}" "{\"type\":\"enqueue\",\"item\":{\"id\":\"z\",\"demand\":{\"cores\":1.5}}}" "")]

/-- An `ops.gate` request: an `ops.spawn` request (roles of `Fw.Wire.Ops.Golden.roles`, `now` 1000)
with the admit budget, the given alive agents, extra top-level fields (state, item) and call. -/
def gateReq (alive extra call : String) : Json :=
  Fw.Wire.Ops.Golden.spawn alive (s!",\"budget\":{budget}" ++ extra) call

/-- A named lean-prover worktree call from the lead (the guard allows it on an empty roster). -/
def lp : String := "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"

/-- A state with `r` running (3 cores, writes `lean/Fw`, the simulator) and `a` landed. -/
def busyState : String :=
  ",\"state\":{\"run\":[{\"id\":\"r\",\"writes\":[\"lean/Fw\"],\"demand\":{\"cores\":3},\"devices\":[\"simulator\"]}],\"done\":[\"a\"],\"t\":50,\"next\":1}"

/-- The `ops.gate` cases. -/
def gateCases : List (String × Json) := [
  ("guard allows, no item (zero demand): allow", gateReq "[]" "" lp),
  ("guard allows, item fits beside r: allow", gateReq "[]" (busyState ++
     ",\"item\":{\"id\":\"lean-x\",\"writes\":[\"apps/site\"],\"demand\":{\"cores\":1},\"deps\":[\"a\"]}") lp),
  ("guard allows, item writes under r's path: queue writeConflict", gateReq "[]" (busyState ++
     ",\"item\":{\"id\":\"lean-x\",\"writes\":[\"lean/Fw/Wire.lean\"]}") lp),
  ("guard allows, simulator held by r: queue deviceBusy", gateReq "[]" (busyState ++
     ",\"item\":{\"id\":\"lean-x\",\"devices\":[\"simulator\"]}") lp),
  ("guard allows, 2 cores wanted, 1 free: queue overBudget", gateReq "[]" (busyState ++
     ",\"item\":{\"id\":\"lean-x\",\"demand\":{\"cores\":2}}") lp),
  ("guard allows, 9 RAM > 8: queue neverFits", gateReq "[]" ",\"item\":{\"id\":\"lean-x\",\"demand\":{\"ram\":9}}" lp),
  ("guard allows, dependency b not landed: queue depPending", gateReq "[]" (busyState ++
     ",\"item\":{\"id\":\"lean-x\",\"deps\":[\"a\",\"b\"]}") lp),
  ("guard allows, an aged queued item competes: queue behindAged",
   gateReq "[]" (",\"state\":" ++ agedState ++ ",\"item\":{\"id\":\"lean-x\",\"demand\":{\"cores\":1}}") lp),
  ("fable, item admitted: needsApproval",
   gateReq "[]" "" "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"fable\"}"),
  ("fable, item queued: queue (not accepted)", gateReq "[]" ",\"item\":{\"id\":\"lean-x\",\"demand\":{\"ram\":9}}"
     "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"fable\"}"),
  ("guard denies (unknown role), item admissible: deny, admit still reported",
   gateReq "[]" "" "{\"name\":\"x\",\"role\":\"general-purpose\",\"isolation\":\"worktree\"}"),
  ("guard denies (worktree trap) and the item would queue: deny wins", gateReq "[]"
     ",\"item\":{\"id\":\"lean-x\",\"demand\":{\"ram\":9}}" "{\"name\":\"lean-x\",\"role\":\"lean-prover\"}"),
  ("guard denies (4th lean-prover): deny capRole",
   gateReq (Fw.Wire.Ops.Golden.aliveN "l" "lean-prover" "worktree" 3) "" lp),
  ("state breaking the invariant: answered, inv false",
   gateReq "[]" ",\"state\":{\"queue\":[{\"id\":\"d\"},{\"id\":\"d\",\"seq\":1}],\"next\":2}" lp),
  ("missing budget is refused", Fw.Wire.Ops.Golden.spawn "[]" "" lp),
  ("missing req is refused", lit s!"\{\"alive\":[],\"roles\":[],\"now\":0,\"budget\":{budget}}"),
  ("unknown device in the item is refused",
   gateReq "[]" ",\"item\":{\"id\":\"lean-x\",\"devices\":[\"tablet\"]}" lp)]

/-- The `ops.gate` cases whose `guard` field is not the `ops.spawn` reply to the same request
(should be none: `ops.gate` decodes the guard input as `ops.spawn` does). -/
def gateGuardMismatches : List String :=
  gateCases.filterMap fun (name, req) =>
    match (respond "ops.gate" req).getObjVal? "guard" with
    | .ok g => if g == respond "ops.spawn" req then none else some name
    | .error _ => none

/-- The `metrics.*` cases: (name, op, request without op). -/
def metricsCases : List (String × String × Json) := [
  ("merge: sorted, fused, empty and reversed intervals dropped", "metrics.merge",
   lit "{\"ivs\":[[5,7],[1,3],[2,4],[4,4],[9,8]]}"),
  ("merge: touching intervals fuse", "metrics.merge", lit "{\"ivs\":[[1,3],[3,5]]}"),
  ("merge: empty", "metrics.merge", lit "{\"ivs\":[]}"),
  ("busy: clipped to the window", "metrics.busy", lit "{\"a\":0,\"b\":10,\"ivs\":[[1,3],[2,4],[8,12]]}"),
  ("busy: reversed window is 0", "metrics.busy", lit "{\"a\":10,\"b\":0,\"ivs\":[[1,3]]}"),
  ("speedup: two agents overlapping 2 of 10", "metrics.speedup",
   lit "{\"a\":0,\"b\":10,\"agents\":[[[0,6]],[[4,10]]]}"),
  ("speedup: empty window is 0", "metrics.speedup", lit "{\"a\":5,\"b\":5,\"agents\":[[[0,6]]]}"),
  ("serialShare: 8 of 10 with at most one busy", "metrics.serialShare",
   lit "{\"a\":0,\"b\":10,\"agents\":[[[0,6]],[[4,10]]]}"),
  ("serialShare: always two busy", "metrics.serialShare",
   lit "{\"a\":0,\"b\":10,\"agents\":[[[0,10]],[[0,10]],[[2,3]]]}"),
  ("serialShare: no agents", "metrics.serialShare", lit "{\"a\":0,\"b\":10,\"agents\":[]}"),
  ("stretch: 13/10", "metrics.stretch", lit "{\"d\":13,\"dsolo\":10}"),
  ("stretch: dsolo 0 gives 0", "metrics.stretch", lit "{\"d\":5,\"dsolo\":0}"),
  ("cp: the path 2+3+4 beats the shortcut 0→2", "metrics.cp", lit "{\"n\":3,\"w\":[2,3,4],\"edges\":[[0,1],[1,2],[0,2]]}"),
  ("cp: heaviest single node wins", "metrics.cp", lit "{\"n\":4,\"w\":[5,1,1,1],\"edges\":[[1,2],[2,3]]}"),
  ("cp: a cycle is reported", "metrics.cp", lit "{\"n\":2,\"w\":[1,1],\"edges\":[[0,1],[1,0]]}"),
  ("cp: a self-loop is a cycle", "metrics.cp", lit "{\"n\":1,\"w\":[5],\"edges\":[[0,0]]}"),
  ("cp: out-of-range edges are ignored", "metrics.cp", lit "{\"n\":2,\"w\":[1,2],\"edges\":[[0,5],[7,1]]}"),
  ("cp: empty graph", "metrics.cp", lit "{\"n\":0,\"w\":[],\"edges\":[]}"),
  ("cp: an edge must be a pair", "metrics.cp", lit "{\"n\":2,\"w\":[1,1],\"edges\":[[0,1,2]]}"),
  ("benchVerdict: seed 0, variant blocks clearly lower", "metrics.benchVerdict",
   lit "{\"seed\":0,\"ms\":[20,20,20,20,10,10,10,10]}"),
  ("benchVerdict: explicit labels, variant lower", "metrics.benchVerdict",
   lit "{\"labels\":[false,true,false,true,false,true,false,true],\"ms\":[20,10,21,11,22,12,23,13]}"),
  ("benchVerdict: interleaved values are noise", "metrics.benchVerdict",
   lit "{\"labels\":[false,true,false,true,false,true,false,true],\"ms\":[10,11,12,9,10,11,12,9]}"),
  ("benchVerdict: seed 69", "metrics.benchVerdict", lit "{\"seed\":69,\"ms\":[3,1,4,1,5,9,2,6]}"),
  ("busy: a non-integer bound is refused", "metrics.busy", lit "{\"a\":0.5,\"b\":10,\"ivs\":[]}")]

/-- The text of one golden file. -/
def fileText (cs : List (String × String × Json)) : String :=
  String.join (cs.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The files: (file stem, cases). -/
def files : List (String × List (String × String × Json)) :=
  [("admit", admitCases.map fun (n, r) => (n, "ops.admit", r)), ("metrics", metricsCases),
   ("gate", gateCases.map fun (n, r) => (n, "ops.gate", r))]

/-- The golden directory, relative to `lean/`. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"

/-- Compare (or write) both golden files; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  if write then IO.FS.createDirAll d
  let mut stale := 0
  for (stem, cs) in files do
    let p := d / s!"{stem}.jsonl"
    let text := fileText cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"sched golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/SchedGolden.lean)"
        stale := stale + 1
  for name in gateGuardMismatches do
    IO.println s!"sched golden: ops.gate case '{name}': guard differs from the ops.spawn reply"
    stale := stale + 1
  let n := files.foldl (fun a c => a + c.2.length) 0
  IO.println s!"sched golden: {files.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Sched.Golden
