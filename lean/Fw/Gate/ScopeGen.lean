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
`main`); `packages/gate-breakpoints/scripts/scopegen.mjs` runs `run` through a two-line driver.
-/
namespace Fw.Gate.ScopeGen
open Lean Fw.Gate Fw.Site.Breakpoints Fw.Site.BreakpointGen

/-- A requested environment in the run file's shape (`spec.mjs` `probeEnv`).

$$\forall e,\quad \operatorname{envJson}(e) = \{w, h, d_w, d_h, r, \eta, \kappa, \mu, \sigma\} \text{ as JSON (keywords as in CSS)}$$

One sweep stop as the package writes it. -/
def envJson (e : Env) : Json :=
  Json.mkObj [("width", pxJson e.width), ("height", pxJson e.height), ("deviceWidth", pxJson e.deviceWidth),
    ("deviceHeight", pxJson e.deviceHeight), ("dpr", pxJson e.dpr), ("hover", toJson (Feature.hoverKw e.hover)),
    ("pointer", toJson (Feature.pointerKw e.pointer)), ("reducedMotion", toJson (Feature.motionKw e.motion)),
    ("colorScheme", toJson (Feature.schemeKw e.scheme))]

#guard (envJson (deskStop 600)).compress ==
  "{\"colorScheme\":\"light\",\"deviceHeight\":900,\"deviceWidth\":600,\"dpr\":1,\"height\":900,\"hover\":\"hover\",\"pointer\":\"fine\",\"reducedMotion\":\"no-preference\",\"width\":600}"

/-- The ids of a list of probes, in order.

$$\forall S,\quad \operatorname{ids}(S) = [\mathrm{id}(p) \mid p \in S]$$

What the package filters the matrix by. -/
def probeIds (S : List Probe) : Json := toJson (S.map (·.id))

/-- One part's entry.

$$\forall u,\quad \operatorname{partJson}(u) = \{O(u), C_{\mathrm{orig}}(u), C_{\mathrm{rw}}(u), X(u), \mathit{Kn}(u), D(u), \operatorname{css}(Q(u)), \operatorname{ids}(S(u)), \operatorname{ids}(K(u))\}$$

What `--parts u` runs and why. -/
def partJson (u : PartUse) : Json :=
  Json.mkObj [
    ("owners", toJson u.owners),
    ("conditions", Json.mkObj [("orig", toJson u.orig), ("rewrite", toJson u.rewrite)]),
    ("extra", Json.arr (u.extra.map fun x =>
      Json.mkObj [("id", toJson x.id), ("css", toJson x.query.css), ("why", toJson x.why)]).toArray),
    ("knees", Json.arr (u.knees.map fun k =>
      Json.mkObj [("expression", toJson k.expr), ("px", toJson k.px), ("css", toJson (kneeQuery k).css)]).toArray),
    ("dismissed", Json.arr (u.dismissed.map fun (i, w) => Json.mkObj [("id", toJson i), ("why", toJson w)]).toArray),
    ("key", toJson (u.queries.map (·.css))),
    ("probes", probeIds (scopeProbes u)),
    ("sweeps", toJson ((scopeSweeps u).map (·.id)))]

/-- The union of all pilot scopes, in matrix and spec order.

$$S_\cup = [\,p \in M \mid \exists u \in \mathrm{pilot},\ p \in S(u)\,],\quad K_\cup = [\,w \in W \mid \exists u \in \mathrm{pilot},\ w \in K(u)\,]$$

What `--parts` with every pilot part runs. -/
def unionJson : Json :=
  Json.mkObj [
    ("probes", probeIds (matrix.filter fun p => pilotParts.any fun u => (scopeProbes u).any (·.id == p.id))),
    ("sweeps", toJson ((sweeps.filter fun w => pilotParts.any fun u => (scopeSweeps u).any (·.id == w.id)).map (·.id)))]

/-- Hypothesis H in words, as the JSON states it.

$$H = \text{the text of hypothesis H of } \texttt{Fw.Gate.Scope}$$

What the scoped verdict relies on. -/
def hypothesisText : String :=
  "H: on a fixed engine port, a part's verdict at a fresh load depends only on its key (the truth vector of the " ++
  "part's key queries), and at a sweep stop only on the key history so far with repeats collapsed; it is never " ++
  "unreachable except by the port's proved reason (Fw.Gate.envReason). H fails if the part reads a condition " ++
  "outside its key, if the rewrite's media text differs from Lean's, or if a continuous value differs between " ++
  "the arms at some widths of one key class only. The full matrix (no --parts) stays the gate of record."

/-- The whole generated document.

$$\operatorname{scopeJson} = \{\mathrm{schema}, \mathrm{generatedBy}, H, \mathrm{theorems}, \mathcal P, |M|, W, (\operatorname{partJson}(u))_{u \in \mathrm{pilot}}, (S_\cup, K_\cup)\}$$

What `scope.gen.json` holds. -/
def scopeJson : Json :=
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

/-- The exact bytes of the generated file: `scopeJson` pretty-printed at width 120, newline-terminated.

$$\operatorname{scopeText} = \operatorname{pretty}_{120}(\operatorname{scopeJson}) \mathbin{+\!\!+} \text{newline}$$

What the generator prints and `--check` compares. -/
def scopeText : String := scopeJson.pretty 120 ++ "\n"

/-- Command-line driver: without `--check` print the generated text; with `--check <file>` exit 0 when the file's
bytes equal it, else 1.

$$\operatorname{run}(\mathit{args}) = \begin{cases} 0 & \texttt{--check } f \text{ given} \wedge \operatorname{bytes}(f) = \operatorname{utf8}(\operatorname{scopeText}) \\ 1 & \texttt{--check } f \text{ given} \wedge \operatorname{bytes}(f) \ne \operatorname{utf8}(\operatorname{scopeText}) \\ 0,\ \text{stdout} := \operatorname{scopeText} & \text{no } \texttt{--check} \end{cases}$$

(An unreadable file raises an IO error; the flag is found by `argOf`.) -/
def run (args : List String) : IO UInt32 := do
  match argOf args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == scopeText.toUTF8.data then
      IO.eprintln s!"scopegen: {path} is up to date ({pilotParts.length} parts)"
      return 0
    IO.eprintln s!"scopegen: {path} differs from the generated bytes; regenerate with node packages/gate-breakpoints/scripts/scopegen.mjs"
    return 1
  | none =>
    IO.print scopeText
    return 0

end Fw.Gate.ScopeGen
