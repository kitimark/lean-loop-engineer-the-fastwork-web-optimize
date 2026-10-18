import Lean.Data.Json
import Fw.Wire.Gate
/-!
# The exit code of the gate's `summary` step (`packages/gate-breakpoints/src/cli.mjs summary`)

The summary step used to exit 0 whatever the table said, so a gate job showed success on a failing run
(mistake retro, class `c-proxy-verdict`). Here the exit code is a function of the merged verdict per engine.

An engine's verdict is one of four (`EngineVerdict`): `pass`, `fail`, `unsettled` (some probe did not settle on an
arm, so its numbers are not a measurement) and `notRendered` (nothing was compared: no passing and no failing cell).
`engineVerdict` reduces an engine's table cells (`Fw.Gate.Verdict`, the Lean tallies the summary prints) and its
count of unsettled probes to one of them. `exitCode` is 0 exactly when at least one engine was judged and every
judged engine passed (`exit_zero_iff`); a failing, unsettled or not-rendered engine never gives 0
(`exit_ne_zero_of_fail`, `exit_ne_zero_of_unsettled`, `exit_ne_zero_of_notRendered`), and a failing table cell
anywhere gives a non-zero exit (`exit_ne_zero_of_fail_cell`).

TODO(gate-settle): `EngineVerdict` is local. When `Fw.Gate.Settle` lands on main, unify its pass / fail /
unsettled / notRendered with this enum and take `unsettled` from its settle states instead of the count.

Not comparable cells (`nc`) and not-run blocks do not make an engine unsettled: green runs have them (a matchMedia
row compared against Lean on the fractional-gaps block, and the blocks a narrowed run does not load). They carry no
verdict, so they are ignored; an engine whose cells are all of this kind is `notRendered`.
`goldenLines` are the golden vectors `cli.mjs` is checked against
(`packages/contracts/golden/gate/exit.jsonl`).
-/
namespace Fw.Gate.Exit
open Fw.Gate

/-- The merged verdict of one engine.

$$\mathcal E = \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}, \mathrm{notRendered}\}$$

What the gate says about one engine after the shards are merged. -/
inductive EngineVerdict where
  | pass
  | fail
  | unsettled
  | notRendered
  deriving DecidableEq, Repr, Inhabited

/-- The verdict of one engine from its table cells and its unsettled probe count.

$$\operatorname{ev}(cs, u) = \begin{cases} \mathrm{fail} & \mathrm{fail} \in cs \\ \mathrm{unsettled} & \mathrm{fail} \notin cs \wedge u > 0 \\ \mathrm{pass} & \mathrm{fail} \notin cs \wedge u = 0 \wedge \mathrm{pass} \in cs \\ \mathrm{notRendered} & \text{otherwise} \end{cases}$$

A failing cell fails the engine; else an unsettled probe makes it unsettled; else it passes only if some cell passed. -/
def engineVerdict (cells : List Verdict) (unsettled : Nat) : EngineVerdict :=
  if cells.any (· == .fail) then .fail
  else if 0 < unsettled then .unsettled
  else if cells.any (· == .pass) then .pass
  else .notRendered

/-- The exit code of `summary` from the verdicts of the engines it judged.

$$\operatorname{exit}(vs) = \begin{cases} 0 & vs \ne [\,] \wedge \forall v \in vs,\ v = \mathrm{pass} \\ 1 & \text{otherwise} \end{cases}$$

0 only when something was judged and everything judged passed; an empty list (no engine file) is not a pass. -/
def exitCode (vs : List EngineVerdict) : Nat :=
  if !vs.isEmpty && vs.all (· == .pass) then 0 else 1

/-- **Exit 0 exactly when every judged engine passed.**

$$\forall vs,\quad \operatorname{exit}(vs) = 0 \iff vs \ne [\,] \wedge \forall v \in vs,\ v = \mathrm{pass}$$

The exit code is the verdict: nothing else gives 0. -/
theorem exit_zero_iff (vs : List EngineVerdict) :
    exitCode vs = 0 ↔ vs ≠ [] ∧ ∀ v ∈ vs, v = .pass := by
  unfold exitCode
  constructor
  · intro h
    split at h
    · rename_i hc
      simp only [Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true, beq_iff_eq] at hc
      refine ⟨fun e => by simp [e] at hc, hc.2⟩
    · omega
  · rintro ⟨hne, hall⟩
    have h1 : (!vs.isEmpty && vs.all (· == .pass)) = true := by
      simp only [Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true, beq_iff_eq]
      exact ⟨by simpa [List.isEmpty_iff] using hne, hall⟩
    simp [h1]

/-- An engine that failed never gives exit 0.

$$\forall vs,\ \mathrm{fail} \in vs \implies \operatorname{exit}(vs) \ne 0$$

-/
theorem exit_ne_zero_of_fail (vs : List EngineVerdict) (h : EngineVerdict.fail ∈ vs) : exitCode vs ≠ 0 := by
  intro e
  have := ((exit_zero_iff vs).1 e).2 _ h
  cases this

/-- An unsettled engine never gives exit 0.

$$\forall vs,\ \mathrm{unsettled} \in vs \implies \operatorname{exit}(vs) \ne 0$$

A run whose probes did not settle is not a pass. -/
theorem exit_ne_zero_of_unsettled (vs : List EngineVerdict) (h : EngineVerdict.unsettled ∈ vs) :
    exitCode vs ≠ 0 := by
  intro e
  have := ((exit_zero_iff vs).1 e).2 _ h
  cases this

/-- A not-rendered engine never gives exit 0.

$$\forall vs,\ \mathrm{notRendered} \in vs \implies \operatorname{exit}(vs) \ne 0$$

A run that compared nothing is not a pass. -/
theorem exit_ne_zero_of_notRendered (vs : List EngineVerdict) (h : EngineVerdict.notRendered ∈ vs) :
    exitCode vs ≠ 0 := by
  intro e
  have := ((exit_zero_iff vs).1 e).2 _ h
  cases this

/-- An engine passes exactly when no cell failed, every probe settled and some cell passed.

$$\forall cs, u,\quad \operatorname{ev}(cs, u) = \mathrm{pass} \iff \mathrm{fail} \notin cs \wedge u = 0 \wedge \mathrm{pass} \in cs$$

-/
theorem engineVerdict_pass_iff (cs : List Verdict) (u : Nat) :
    engineVerdict cs u = .pass ↔ Verdict.fail ∉ cs ∧ u = 0 ∧ Verdict.pass ∈ cs := by
  unfold engineVerdict
  by_cases h1 : cs.any (· == .fail) = true
  · have : Verdict.fail ∈ cs := by simpa using h1
    simp [h1, this]
  · have h1' : Verdict.fail ∉ cs := by simpa using h1
    by_cases h2 : 0 < u
    · simp [h1, h2, h1']; omega
    · have hu : u = 0 := by omega
      by_cases h3 : cs.any (· == .pass) = true
      · have : Verdict.pass ∈ cs := by simpa using h3
        simp [h1, h3, h1', hu, this]
      · have h3' : Verdict.pass ∉ cs := by simpa using h3
        simp [h1, h3, h1', hu, h3']

/-- A failing cell fails its engine.

$$\forall cs, u,\ \mathrm{fail} \in cs \implies \operatorname{ev}(cs, u) = \mathrm{fail}$$

Unsettled probes do not hide a failure. -/
theorem engineVerdict_fail (cs : List Verdict) (u : Nat) (h : Verdict.fail ∈ cs) :
    engineVerdict cs u = .fail := by
  unfold engineVerdict
  have : cs.any (· == .fail) = true := by simpa using h
  simp [this]

/-- Unsettled probes keep an engine from passing.

$$\forall cs, u,\ u > 0 \implies \operatorname{ev}(cs, u) \ne \mathrm{pass}$$

-/
theorem engineVerdict_unsettled_ne_pass (cs : List Verdict) (u : Nat) (h : 0 < u) :
    engineVerdict cs u ≠ .pass := by
  intro e
  have := ((engineVerdict_pass_iff cs u).1 e).2.1
  omega

/-- **A failing table cell anywhere gives a non-zero exit.**

$$\forall es,\ \forall (cs, u) \in es,\quad \mathrm{fail} \in cs \implies \operatorname{exit}([\operatorname{ev}(cs', u') \mid (cs', u') \in es]) \ne 0$$

The exit code of a run is the exit code of its engines' verdicts; one failing cell in one engine is enough. -/
theorem exit_ne_zero_of_fail_cell (es : List (List Verdict × Nat)) (e : List Verdict × Nat) (he : e ∈ es)
    (h : Verdict.fail ∈ e.1) : exitCode (es.map fun x => engineVerdict x.1 x.2) ≠ 0 := by
  apply exit_ne_zero_of_fail
  exact List.mem_map.2 ⟨e, he, engineVerdict_fail e.1 e.2 h⟩

/-! ## The wire form (what `cli.mjs` reads) -/

/-- The wire names of an engine verdict, as `cli.mjs` prints them.

$$\operatorname{wire}(v) = \begin{cases} \texttt{pass} & v = \mathrm{pass} \\ \texttt{fail} & v = \mathrm{fail} \\ \texttt{unsettled} & v = \mathrm{unsettled} \\ \texttt{notRendered} & v = \mathrm{notRendered} \end{cases}$$

Each verdict is printed under the name of its constructor. -/
def verdictWire : EngineVerdict → String
  | .pass => "pass" | .fail => "fail" | .unsettled => "unsettled" | .notRendered => "notRendered"

/-- The engine verdict from the wire names of its table cells (`pass`, `fail`, `not-comparable`,
`unreachable:<reason>`, `not-run` for an empty block, which carries no verdict and is dropped).

$$\operatorname{evW}(ns, u) = \begin{cases} \operatorname{ok}(\operatorname{ev}([\,v(n) \mid n \in ns,\ n \ne \texttt{not-run}\,],\ u)) & \text{every such } n \text{ is known to } v = \operatorname{verdictOf} \\ \operatorname{error}(\texttt{unknown verdict } n) & n \text{ the first unknown such name} \end{cases}$$

An unknown name is an error, never a pass. -/
def engineVerdictW (names : List String) (unsettled : Nat) : Except String EngineVerdict := do
  let cs ← (names.filter (· != "not-run")).mapM Fw.Wire.Gate.verdictOf
  return engineVerdict cs unsettled

/-! ## Golden vectors -/

open Lean in
/-- One engine case: wire names of the cells, the unsettled count, the verdict.

$$\operatorname{engineCase}(ns, u) = \begin{cases} \{\mathrm{cells} = ns,\ \mathrm{kind} = \texttt{engine},\ \mathrm{unsettled} = u,\ \mathrm{verdict} = \operatorname{wire}(v)\} & \operatorname{evW}(ns, u) = \operatorname{ok}(v) \\ \{\mathrm{cells} = ns,\ \mathrm{error} = e,\ \mathrm{kind} = \texttt{engine},\ \mathrm{unsettled} = u\} & \operatorname{evW}(ns, u) = \operatorname{error}(e) \end{cases}$$

One compact JSON object with keys in sorted order: the verdict when every cell name is known, else the error
message of the first unknown name. -/
def engineCase (cells : List String) (unsettled : Nat) : String :=
  match engineVerdictW cells unsettled with
  | .ok v => (Json.mkObj [("kind", "engine"), ("cells", toJson cells), ("unsettled", toJson unsettled),
      ("verdict", verdictWire v)]).compress
  | .error e => (Json.mkObj [("kind", "engine"), ("cells", toJson cells), ("unsettled", toJson unsettled),
      ("error", e)]).compress

open Lean in
/-- One run case: the verdicts of the judged engines and the exit code.

$$\operatorname{exitCase}(vs) = \{\mathrm{engines} = [\,\operatorname{wire}(v) \mid v \in vs\,],\ \mathrm{exit} = \operatorname{exit}(vs),\ \mathrm{kind} = \texttt{exit}\}$$

One compact JSON object with keys in sorted order: the wire names of the verdicts, in order, and the exit code. -/
def exitCase (vs : List EngineVerdict) : String :=
  (Json.mkObj [("kind", "exit"), ("engines", toJson (vs.map verdictWire)), ("exit", toJson (exitCode vs))]).compress

/-- The golden lines (`packages/contracts/golden/gate/exit.jsonl`).

$$\begin{aligned} \mathrm{goldenLines} = {} &[\,\operatorname{engineCase}(ns, u) \mid (ns, u) \in E\,] \mathbin{+\!\!+} [\,\operatorname{exitCase}(vs) \mid vs \in X\,], \\ E = {} &[\,([\texttt{pass}, \texttt{pass}, \texttt{not-run}], 0),\ ([\texttt{pass}, \texttt{not-comparable}, \texttt{not-run}, \texttt{unreachable:whole-width}], 0),\ ([\texttt{pass}, \texttt{fail}, \texttt{pass}], 0), \\ &\ \ ([\texttt{pass}, \texttt{fail}], 3),\ ([\texttt{pass}, \texttt{pass}], 2),\ ([\texttt{not-comparable}, \texttt{not-run}], 0), \\ &\ \ ([\texttt{unreachable:primary-pair}, \texttt{unreachable:whole-width}], 0),\ ([\,], 0),\ ([\texttt{pass}, \texttt{bogus}], 0)\,], \\ X = {} &[\,[\mathrm{pass}],\ [\mathrm{pass}, \mathrm{pass}],\ [\mathrm{pass}, \mathrm{fail}],\ [\mathrm{fail}],\ [\mathrm{unsettled}],\ [\mathrm{pass}, \mathrm{unsettled}],\ [\mathrm{notRendered}],\ [\mathrm{pass}, \mathrm{notRendered}],\ [\,]\,] \end{aligned}$$

The engine cases come first, then the run cases, each in the order listed, so the file has
$|E| + |X| = 9 + 9 = 18$ lines. -/
def goldenLines : List String :=
  [ engineCase ["pass", "pass", "not-run"] 0,
    engineCase ["pass", "not-comparable", "not-run", "unreachable:whole-width"] 0,
    engineCase ["pass", "fail", "pass"] 0,
    engineCase ["pass", "fail"] 3,
    engineCase ["pass", "pass"] 2,
    engineCase ["not-comparable", "not-run"] 0,
    engineCase ["unreachable:primary-pair", "unreachable:whole-width"] 0,
    engineCase [] 0,
    engineCase ["pass", "bogus"] 0,
    exitCase [.pass],
    exitCase [.pass, .pass],
    exitCase [.pass, .fail],
    exitCase [.fail],
    exitCase [.unsettled],
    exitCase [.pass, .unsettled],
    exitCase [.notRendered],
    exitCase [.pass, .notRendered],
    exitCase [] ]

#guard exitCode [] == 1
#guard exitCode [.pass, .pass] == 0
#guard exitCode [.pass, .fail] == 1
#guard engineVerdict [.pass, .fail] 0 == .fail
#guard engineVerdict [.pass, .nc] 0 == .pass
#guard engineVerdict [.pass] 1 == .unsettled
#guard engineVerdict [.nc, .unreachable .wholeWidth] 0 == .notRendered

end Fw.Gate.Exit
