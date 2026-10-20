import Lean.Data.Json
import Fw.Gate.Scope
import Fw.Site.BreakpointGen
/-!
# `scope.gen.json`: the generated probe scope of each pilot part

`scopeJson` is the whole document read by `packages/gate-breakpoints` (`spec.mjs` `loadScope`): per pilot part its
owners, conditions, extra width facts, knees, dismissed inventory entries, key queries (CSS text), the scoped probe
ids (matrix order) and sweep ids (spec order); the union over all parts; the sweeps with their stops, so the package
test can compare them with `spec.mjs` `sweepDefs`. `run` prints it or, with `--check <file>`, compares bytes.
The module defines no `main` (the math view imports every `Fw` module, and `Fw.Parts.Golden` owns the root
`main`); `packages/gate-breakpoints/scripts/scopegen.mjs` runs `run` through the compiled `sweepsgen --scope`, or (binary missing) through a two-line `lean --run` driver (the interpreter: ~100 s).
-/
namespace Fw.Gate.ScopeGen
open Lean Fw.Gate Fw.Site.Breakpoints Fw.Site.BreakpointGen

/-- A requested environment in the run file's shape (`spec.mjs` `probeEnv`).

One sweep stop as the package writes it. -/
def envJson (e : Env) : Json :=
  Json.mkObj [("width", pxJson e.width), ("height", pxJson e.height), ("deviceWidth", pxJson e.deviceWidth),
    ("deviceHeight", pxJson e.deviceHeight), ("dpr", pxJson e.dpr), ("hover", toJson (Feature.hoverKw e.hover)),
    ("pointer", toJson (Feature.pointerKw e.pointer)), ("reducedMotion", toJson (Feature.motionKw e.motion)),
    ("colorScheme", toJson (Feature.schemeKw e.scheme))]

#guard (envJson (deskStop 600)).compress ==
  "{\"colorScheme\":\"light\",\"deviceHeight\":900,\"deviceWidth\":600,\"dpr\":1,\"height\":900,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"width\":600}"

/-- The ids of a list of probes, in order.

What the package filters the matrix by. -/
def probeIds (S : List Probe) : Json := toJson (S.map (·.id))

/-- One part's entry.

What `--parts u` runs and why. -/
def partJson (u : PartUse) : Json :=
  Json.mkObj [
    ("owners", toJson u.owners),
    ("conditions", Json.mkObj [("orig", toJson u.orig), ("rewrite", toJson u.rewrite)]),
    ("added", Json.arr (u.added.map fun (i, w) => Json.mkObj [("id", toJson i), ("why", toJson w)]).toArray),
    ("extra", Json.arr (u.extra.map fun x =>
      Json.mkObj [("id", toJson x.id), ("css", toJson x.query.css), ("why", toJson x.why)]).toArray),
    ("knees", Json.arr (u.knees.map fun k =>
      Json.mkObj [("expression", toJson k.expr), ("px", toJson k.px), ("css", toJson (kneeQuery k).css)]).toArray),
    ("dismissed", Json.arr (u.dismissed.map fun (i, w) => Json.mkObj [("id", toJson i), ("why", toJson w)]).toArray),
    ("key", toJson (u.queries.map (·.css))),
    ("probes", probeIds (scopeProbes u)),
    ("sweeps", toJson ((scopeSweeps u).map (·.id)))]

set_option compiler.extract_closed false in
/-- The union of all pilot scopes, in matrix and spec order.

What `--parts` with every pilot part runs: the matrix probes and spec sweeps whose id some pilot scope names, in
matrix and spec order. -/
def unionJson (_ : Unit := ()) : Json :=
  Json.mkObj [
    ("probes", probeIds (matrix.filter fun p => pilotParts.any fun u => (scopeProbes u).any (·.id == p.id))),
    ("sweeps", toJson ((sweeps.filter fun w => pilotParts.any fun u => (scopeSweeps u).any (·.id == w.id)).map (·.id)))]

/-- Hypothesis H in words, as the JSON states it: a separate fixed paraphrase, not a copy of the module text of
hypothesis H in `Fw.Gate.Scope` (it leaves out the clamp-in-vw detail and adds the gate-of-record sentence).

A fixed English string, written by hand, that the generated scope file carries as its hypothesis. -/
def hypothesisText : String :=
  "H: on a fixed engine port, a part's verdict at a fresh load depends only on its key (the truth vector of the " ++
  "part's key queries), and at a sweep stop only on the key history so far with repeats collapsed; it is never " ++
  "unreachable except by the port's proved reason (Fw.Gate.envReason). H fails if the part reads a condition " ++
  "outside its key, if the rewrite's media text differs from Lean's, or if a continuous value differs between " ++
  "the arms at some widths of one key class only. The full matrix (no --parts) stays the gate of record."

#guard hypothesisText.startsWith "H: on a fixed engine port, " &&
  hypothesisText.endsWith "The full matrix (no --parts) stays the gate of record."

set_option compiler.extract_closed false in
/-- The whole generated document.

What `scope.gen.json` holds. -/
def scopeJson (_ : Unit := ()) : Json :=
  Json.mkObj [
    ("schema", toJson "fw.gate-breakpoints.scope/1"),
    ("generatedBy", toJson "lean/Fw/Gate/ScopeGen.lean (Fw.Gate.ScopeGen.scopeText); regenerate with node packages/gate-breakpoints/scripts/scopegen.mjs"),
    ("hypothesis", toJson hypothesisText),
    ("theorems", toJson ["Fw.Gate.scoped_verdict_eq", "Fw.Gate.scope_sound", "Fw.Gate.scope_union_sound",
      "Fw.Gate.scope_covers", "Fw.Gate.scope_sweeps_covered", "Fw.Gate.scope_observes_edges",
      "Fw.Gate.sweeps_reachable"]),
    ("ports", toJson ["chromium", "webkitApple", "webkitGLib"]),
    ("matrixProbes", toJson matrix.length),
    ("sweeps", Json.arr (sweeps.map fun w =>
      Json.mkObj [("id", toJson w.id), ("stops", Json.arr (w.stops.map envJson).toArray)]).toArray),
    ("parts", Json.mkObj (pilotParts.map fun u => (u.id, partJson u))),
    ("union", unionJson)]

set_option compiler.extract_closed false in
/-- The exact bytes of the generated file: `scopeJson` pretty-printed at width 120, newline-terminated.

What the generator prints and `--check` compares. -/
def scopeText (_ : Unit := ()) : String := scopeJson.pretty 120 ++ "\n"


/-- The exit code of `--check` for a file holding the bytes `cur`.

The one decision of the checker, kept pure so that it is proved (`checkCode_eq_zero_iff`) and the I/O in `run` only reads
the file and prints. -/
def checkCode (cur : Array UInt8) : UInt32 := if cur == scopeText.toUTF8.data then 0 else 1

/-- `--check` accepts exactly the generated bytes.

So `src/scope.gen.json` is Lean's bytes when `scopegen --check` exits 0, whether the check ran as the compiled
`sweepsgen --scope` or as the interpreted `lean --run` driver: both are `run`. -/
theorem checkCode_eq_zero_iff (cur : Array UInt8) : checkCode cur = 0 ↔ cur = scopeText.toUTF8.data := by
  unfold checkCode
  split
  · rename_i h; exact ⟨fun _ => eq_of_beq h, fun _ => rfl⟩
  · rename_i h; exact ⟨fun h0 => absurd h0 (by decide), fun e => absurd (e ▸ beq_self_eq_true _) h⟩

/-- The generated bytes pass their own check. -/
theorem checkCode_self : checkCode scopeText.toUTF8.data = 0 := (checkCode_eq_zero_iff _).2 rfl

/-- Command-line driver: without `--check` print the generated text; with `--check <file>` exit `checkCode` of the file's
bytes (0 when equal to `scopeText`, else 1).

(An unreadable file raises an IO error; the flag is found by `argOf`.) -/
def run (args : List String) : IO UInt32 := do
  match argOf args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if checkCode cur.data == 0 then
      IO.eprintln s!"scopegen: {path} is up to date ({pilotParts.length} parts)"
      return 0
    IO.eprintln s!"scopegen: {path} differs from the generated bytes; regenerate with node packages/gate-breakpoints/scripts/scopegen.mjs"
    return 1
  | none =>
    IO.print scopeText
    return 0

end Fw.Gate.ScopeGen
