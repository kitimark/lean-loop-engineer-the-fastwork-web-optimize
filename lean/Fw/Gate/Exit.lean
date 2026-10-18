import Lean.Data.Json
import Fw.Wire.Gate
import Fw.Gate.Settle
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

The count of unsettled states is not a flag the page sets: it is taken from the settle wait itself
(`Fw.Gate.Settle.wait`, `Fw.Gate.Settle.fold`; gate-shard-balance round 2). Each sample (a probe, a sweep stop) carries
the two arms' wait outcomes; the sample is unsettled when either is (`stateUnsettled`, the `unsettled` case of
`Fw.Gate.Settle.report`), and a wait that is missing counts as unsettled (`outcomeOfWire`): nothing the gate did not
measure is a pass (`engineVerdictS_pass_iff`, `exit_ne_zero_of_wait_unsettled`). The hysteresis pair (the arm after a
sweep against a fresh load) is compared only when both of its waits settled (`staleComparable`).

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

/-! ## The unsettled count from the settle wait

A sample's two arms each end their settle wait with an `Outcome` (`settled i` or `unsettled`). -/

open Fw.Gate.Settle (Outcome report Report)

/-- A sample (probe or sweep stop) is unsettled when either arm's wait ended unsettled.

$$\operatorname{unst}(a, b) \iff \operatorname{report}(a, b, \mathrm{true}) = \mathrm{unsettled}$$

The values' equality is not needed for that case, so `true` is passed. -/
def stateUnsettled (s : Outcome × Outcome) : Bool := decide (report s.1 s.2 true = Report.unsettled)

/-- Unsettled exactly when one of the two waits is.

$$\operatorname{unst}(a, b) \iff a = \mathrm{unsettled} \vee b = \mathrm{unsettled}$$

-/
theorem stateUnsettled_iff (s : Outcome × Outcome) :
    stateUnsettled s = true ↔ s.1 = .unsettled ∨ s.2 = .unsettled := by
  obtain ⟨a, b⟩ := s
  cases a <;> cases b <;> simp [stateUnsettled, report]

/-- The number of unsettled samples among an engine's samples.

$$\operatorname{u}(ws) = \bigl|\{\, w \in ws \mid \operatorname{unst}(w) \,\}\bigr|$$

-/
def unsettledStates (ws : List (Outcome × Outcome)) : Nat := (ws.filter stateUnsettled).length

/-- The count is positive exactly when some sample has an unsettled wait.

$$\forall ws,\quad \operatorname{u}(ws) > 0 \iff \exists (a, b) \in ws,\ a = \mathrm{unsettled} \vee b = \mathrm{unsettled}$$

-/
theorem unsettledStates_pos_iff (ws : List (Outcome × Outcome)) :
    0 < unsettledStates ws ↔ ∃ s ∈ ws, s.1 = .unsettled ∨ s.2 = .unsettled := by
  unfold unsettledStates
  rw [List.length_pos_iff_exists_mem]
  constructor
  · rintro ⟨s, hs⟩
    obtain ⟨h1, h2⟩ := List.mem_filter.1 hs
    exact ⟨s, h1, (stateUnsettled_iff s).1 h2⟩
  · rintro ⟨s, hs, h⟩
    exact ⟨s, List.mem_filter.2 ⟨hs, (stateUnsettled_iff s).2 h⟩⟩

/-- The verdict of one engine from its table cells and the wait outcomes of its samples.

$$\operatorname{ev}_W(cs, ws) = \operatorname{ev}(cs, \operatorname{u}(ws))$$

-/
def engineVerdictS (cells : List Verdict) (ws : List (Outcome × Outcome)) : EngineVerdict :=
  engineVerdict cells (unsettledStates ws)

/-- **An engine passes exactly when no cell failed, every wait of every sample settled and some cell passed.**

$$\operatorname{ev}_W(cs, ws) = \mathrm{pass} \iff \mathrm{fail} \notin cs \wedge (\forall (a, b) \in ws,\ a \ne \mathrm{unsettled} \wedge b \ne \mathrm{unsettled}) \wedge \mathrm{pass} \in cs$$

-/
theorem engineVerdictS_pass_iff (cs : List Verdict) (ws : List (Outcome × Outcome)) :
    engineVerdictS cs ws = .pass ↔
      Verdict.fail ∉ cs ∧ (∀ s ∈ ws, s.1 ≠ .unsettled ∧ s.2 ≠ .unsettled) ∧ Verdict.pass ∈ cs := by
  unfold engineVerdictS
  rw [engineVerdict_pass_iff]
  have hp := unsettledStates_pos_iff ws
  have h : unsettledStates ws = 0 ↔ ∀ s ∈ ws, s.1 ≠ .unsettled ∧ s.2 ≠ .unsettled := by
    constructor
    · intro h0 s hs
      refine ⟨fun e => ?_, fun e => ?_⟩
      · have : 0 < unsettledStates ws := hp.2 ⟨s, hs, Or.inl e⟩
        omega
      · have : 0 < unsettledStates ws := hp.2 ⟨s, hs, Or.inr e⟩
        omega
    · intro hall
      cases Nat.eq_zero_or_pos (unsettledStates ws) with
      | inl h => exact h
      | inr h =>
        obtain ⟨s, hs, h⟩ := hp.1 h
        exfalso
        rcases h with h | h
        · exact (hall s hs).1 h
        · exact (hall s hs).2 h
  rw [h]

/-- A sample with an unsettled wait keeps its engine from passing.

$$\forall (a, b) \in ws,\ (a = \mathrm{unsettled} \vee b = \mathrm{unsettled}) \implies \operatorname{ev}_W(cs, ws) \ne \mathrm{pass}$$

Whatever the cells say, an engine with a sample that did not settle is not a pass. -/
theorem engineVerdictS_ne_pass_of_unsettled (cs : List Verdict) (ws : List (Outcome × Outcome)) (s : Outcome × Outcome)
    (hs : s ∈ ws) (h : s.1 = .unsettled ∨ s.2 = .unsettled) : engineVerdictS cs ws ≠ .pass := by
  intro e
  have := ((engineVerdictS_pass_iff cs ws).1 e).2.1 s hs
  rcases h with h | h
  · exact this.1 h
  · exact this.2 h

/-- A failing cell still fails the engine, whatever the waits.

$$\mathrm{fail} \in cs \implies \operatorname{ev}_W(cs, ws) = \mathrm{fail}$$

-/
theorem engineVerdictS_fail (cs : List Verdict) (ws : List (Outcome × Outcome)) (h : Verdict.fail ∈ cs) :
    engineVerdictS cs ws = .fail := engineVerdict_fail cs _ h

/-- **A sample with an unsettled wait anywhere gives a non-zero exit.**

$$\forall es,\ \forall (cs, ws) \in es,\ \forall (a, b) \in ws,\ (a = \mathrm{unsettled} \vee b = \mathrm{unsettled}) \implies \operatorname{exit}([\operatorname{ev}_W(cs', ws') \mid (cs', ws') \in es]) \ne 0$$

The exit code is taken from the waits, not from a flag the page sets. -/
theorem exit_ne_zero_of_wait_unsettled (es : List (List Verdict × List (Outcome × Outcome)))
    (e : List Verdict × List (Outcome × Outcome)) (he : e ∈ es) (s : Outcome × Outcome) (hs : s ∈ e.2)
    (h : s.1 = .unsettled ∨ s.2 = .unsettled) :
    exitCode (es.map fun x => engineVerdictS x.1 x.2) ≠ 0 := by
  intro z
  have hall := ((exit_zero_iff _).1 z).2 (engineVerdictS e.1 e.2) (List.mem_map.2 ⟨e, he, rfl⟩)
  exact engineVerdictS_ne_pass_of_unsettled e.1 e.2 s hs h hall

/-- The hysteresis pair (the arm after a sweep, the arm freshly loaded at the same final environment) is compared only when
both of its waits settled.

$$\operatorname{cmp}(a, f) \iff \operatorname{report}(a, f, \mathrm{true}) = \mathrm{pass}$$

-/
def staleComparable (after fresh : Outcome) : Bool := decide (report after fresh true = Report.pass)

/-- Comparable exactly when both waits settled; an unsettled pair is never compared.

$$\operatorname{cmp}(a, f) \iff a \ne \mathrm{unsettled} \wedge f \ne \mathrm{unsettled}$$

-/
theorem staleComparable_iff (a f : Outcome) :
    staleComparable a f = true ↔ a ≠ .unsettled ∧ f ≠ .unsettled := by
  cases a <;> cases f <;> simp [staleComparable, report]

/-- The wire form of a wait outcome: `settled@<i>`, `unsettled`, and `missing` (a sample the run made without the wait),
which is read as unsettled.

$$\operatorname{ow}(s) = \begin{cases} \mathrm{settled}(i) & s = \texttt{settled@}i \\ \mathrm{unsettled} & s \in \{\texttt{unsettled}, \texttt{missing}\} \\ \text{error} & \text{otherwise} \end{cases}$$

A wait that is absent is not a pass. -/
def outcomeOfWire (s : String) : Except String Outcome :=
  if s = "unsettled" ∨ s = "missing" then .ok .unsettled
  else if s.startsWith "settled@" then
    match (s.drop 8).toNat? with
    | some i => .ok (.settled i)
    | none => .error s!"unknown outcome {s}"
  else .error s!"unknown outcome {s}"

/-- A missing wait is read as unsettled.

$$\operatorname{ow}(\texttt{missing}) = \mathrm{unsettled}$$

-/
theorem outcomeOfWire_missing : outcomeOfWire "missing" = .ok .unsettled := by simp [outcomeOfWire]

/-- The engine verdict from the wire names of its cells and of its samples' wait outcomes (one pair per probe or stop).

$$\operatorname{evWW}(ns, ws) = \operatorname{ok}(\operatorname{ev}_W(cs, ws')) \text{ for known names; else the first error}$$

-/
def engineVerdictWW (names : List String) (waits : List (String × String)) : Except String EngineVerdict := do
  let cs ← (names.filter (· != "not-run")).mapM Fw.Wire.Gate.verdictOf
  let ws ← waits.mapM fun w => do return ((← outcomeOfWire w.1), (← outcomeOfWire w.2))
  return engineVerdictS cs ws

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
/-- One engine case with the waits: wire names of the cells, the samples' wait outcomes (orig, rewrite), the verdict.

$$\operatorname{engineCaseW}(ns, ws) = \{\mathrm{cells} = ns,\ \mathrm{kind} = \texttt{engineWait},\ \mathrm{unsettled} = \operatorname{u}(ws),\ \mathrm{verdict} = \operatorname{wire}(v),\ \mathrm{waits} = ws\}$$

One compact JSON object with keys in sorted order; an unknown cell or outcome name gives `error` instead of `verdict`. -/
def engineCaseW (cells : List String) (waits : List (String × String)) : String :=
  let wj := toJson (waits.map fun w => [w.1, w.2])
  match engineVerdictWW cells waits with
  | .ok v =>
    let ws := waits.filterMap fun w => match outcomeOfWire w.1, outcomeOfWire w.2 with
      | .ok a, .ok b => some (a, b)
      | _, _ => none
    (Json.mkObj [("kind", "engineWait"), ("cells", toJson cells), ("waits", wj),
      ("unsettled", toJson (unsettledStates ws)), ("verdict", verdictWire v)]).compress
  | .error e => (Json.mkObj [("kind", "engineWait"), ("cells", toJson cells), ("waits", wj), ("error", e)]).compress

open Lean in
/-- One hysteresis case: the wire outcomes of the two waits and whether the pair is compared.

$$\operatorname{staleCase}(a, f) = \{\mathrm{after} = a,\ \mathrm{comparable} = \operatorname{cmp}(a, f),\ \mathrm{fresh} = f,\ \mathrm{kind} = \texttt{stale}\}$$

-/
def staleCase (after fresh : String) : String :=
  match outcomeOfWire after, outcomeOfWire fresh with
  | .ok a, .ok f => (Json.mkObj [("kind", "stale"), ("after", after), ("fresh", fresh),
      ("comparable", toJson (staleComparable a f))]).compress
  | _, _ => (Json.mkObj [("kind", "stale"), ("after", after), ("fresh", fresh), ("error", "unknown outcome")]).compress

open Lean in
/-- One run case: the verdicts of the judged engines and the exit code.

$$\operatorname{exitCase}(vs) = \{\mathrm{engines} = [\,\operatorname{wire}(v) \mid v \in vs\,],\ \mathrm{exit} = \operatorname{exit}(vs),\ \mathrm{kind} = \texttt{exit}\}$$

One compact JSON object with keys in sorted order: the wire names of the verdicts, in order, and the exit code. -/
def exitCase (vs : List EngineVerdict) : String :=
  (Json.mkObj [("kind", "exit"), ("engines", toJson (vs.map verdictWire)), ("exit", toJson (exitCode vs))]).compress

/-- The golden lines (`packages/contracts/golden/gate/exit.jsonl`).

$$\begin{aligned} \mathrm{goldenLines} = {} &[\,\operatorname{engineCase}(ns, u) \mid (ns, u) \in E\,] \mathbin{+\!\!+} [\,\operatorname{exitCase}(vs) \mid vs \in X\,], \\ E = {} &[\,([\texttt{pass}, \texttt{pass}, \texttt{not-run}], 0),\ ([\texttt{pass}, \texttt{not-comparable}, \texttt{not-run}, \texttt{unreachable:whole-width}], 0),\ ([\texttt{pass}, \texttt{fail}, \texttt{pass}], 0), \\ &\ \ ([\texttt{pass}, \texttt{fail}], 3),\ ([\texttt{pass}, \texttt{pass}], 2),\ ([\texttt{not-comparable}, \texttt{not-run}], 0), \\ &\ \ ([\texttt{unreachable:primary-pair}, \texttt{unreachable:whole-width}], 0),\ ([\,], 0),\ ([\texttt{pass}, \texttt{bogus}], 0)\,], \\ X = {} &[\,[\mathrm{pass}],\ [\mathrm{pass}, \mathrm{pass}],\ [\mathrm{pass}, \mathrm{fail}],\ [\mathrm{fail}],\ [\mathrm{unsettled}],\ [\mathrm{pass}, \mathrm{unsettled}],\ [\mathrm{notRendered}],\ [\mathrm{pass}, \mathrm{notRendered}],\ [\,]\,] \end{aligned}$$

followed by the wait cases $[\operatorname{engineCaseW}(ns, ws) \mid (ns, ws) \in W]$ ($|W| = 9$: all samples settled; one arm unsettled on the rewrite; on the original; a missing wait; a failing cell with unsettled waits; no samples; unsettled with no passing cell; settled with no passing cell; an unknown outcome name) and the hysteresis cases $[\operatorname{staleCase}(a, f) \mid (a, f) \in S]$ ($|S| = 4$: both settled; either or both unsettled or missing).

The engine cases come first, then the run cases, the wait cases and the hysteresis cases, each in the order listed, so the
file has $|E| + |X| + |W| + |S| = 9 + 9 + 9 + 4 = 31$ lines. -/
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
    exitCase [],
    engineCaseW ["pass", "pass"] [("settled@3", "settled@5"), ("settled@2", "settled@2")],
    engineCaseW ["pass", "pass"] [("settled@3", "settled@5"), ("settled@2", "unsettled")],
    engineCaseW ["pass", "pass"] [("unsettled", "settled@1")],
    engineCaseW ["pass", "pass"] [("settled@3", "missing")],
    engineCaseW ["pass", "fail"] [("unsettled", "unsettled")],
    engineCaseW ["pass", "not-run"] [],
    engineCaseW ["not-comparable", "not-run"] [("unsettled", "settled@0")],
    engineCaseW ["not-comparable", "not-run"] [("settled@0", "settled@0")],
    engineCaseW ["pass"] [("settled@3", "late")],
    staleCase "settled@4" "settled@9",
    staleCase "unsettled" "settled@9",
    staleCase "settled@4" "unsettled",
    staleCase "missing" "missing" ]

#guard exitCode [] == 1
#guard exitCode [.pass, .pass] == 0
#guard exitCode [.pass, .fail] == 1
#guard engineVerdict [.pass, .fail] 0 == .fail
#guard engineVerdict [.pass, .nc] 0 == .pass
#guard engineVerdict [.pass] 1 == .unsettled
#guard engineVerdict [.nc, .unreachable .wholeWidth] 0 == .notRendered
#guard engineVerdictS [.pass] [(.settled 1, .settled 2)] == .pass
#guard engineVerdictS [.pass] [(.settled 1, .settled 2), (.unsettled, .settled 0)] == .unsettled
#guard staleComparable (.settled 1) .unsettled == false

end Fw.Gate.Exit
