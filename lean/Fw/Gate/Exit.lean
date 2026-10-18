import Lean.Data.Json
import Fw.Wire.Gate
import Fw.Gate.Settle
import Fw.Gate.State
/-!
# The exit code of the gate's `summary` step (`packages/gate-breakpoints/src/cli.mjs summary`)

The summary step used to exit 0 whatever the table said, so a gate job showed success on a failing run
(mistake retro, class `c-proxy-verdict`). Here the exit code is a function of the merged verdict per engine, and the
engine verdict is a function of EVERY cell of its table, one by one (gate-shard-balance round 3).

**The rule.** An engine passes only if every cell was compared and passed, with both arms observed in the same state.
A cell is `ok` when it passed, or when a Lean-registered exemption excuses it (`exemptions`: an allowlist of cell id,
engine, verdict, reason and premise, printed in the verdict). Nothing else is `ok`: a `fail`, an unsettled sample, a
not-comparable or unreachable cell that no exemption names, and a not-run cell of a run that was not narrowed to parts are
each a reason the engine does not pass (`engine_pass_iff_all_cells`, `engineVerdictCS_pass_iff`). There is no aggregate
that can hide one: a faster or greener gate never comes from comparing less.

An engine's verdict is one of five (`EngineVerdict`): `pass`, `fail`, `unsettled` (some sample did not settle on an arm, so
its numbers are not a measurement), `incomplete` (a cell is neither a pass nor excused) and `notRendered` (nothing passed).
`exitCode` is 0 exactly when at least one engine was judged and every judged engine passed (`exit_zero_iff`).

The count of unsettled states is not a flag the page sets: it is taken from the settle wait itself
(`Fw.Gate.Settle.wait`, `Fw.Gate.Settle.fold`). Each sample (a probe, a sweep stop) carries the two arms' wait outcomes; the
sample is unsettled when either is (`stateUnsettled`), and a wait that is missing counts as unsettled (`outcomeOfWire`).
The hysteresis pair (the arm after a sweep against a fresh load) is compared only when both of its waits settled
(`staleComparable`).

`goldenLines` are the golden vectors `cli.mjs` is checked against (`packages/contracts/golden/gate/exit.jsonl`); they also
carry the exemption registry, so the TypeScript twin reads the allowlist from Lean's bytes and has no list of its own.
-/
namespace Fw.Gate.Exit
open Fw.Gate

/-- The merged verdict of one engine.

$$\mathcal E = \{\mathrm{pass}, \mathrm{fail}, \mathrm{unsettled}, \mathrm{incomplete}, \mathrm{notRendered}\}$$

What the gate says about one engine after the shards are merged. -/
inductive EngineVerdict where
  | pass
  | fail
  | unsettled
  | incomplete
  | notRendered
  deriving DecidableEq, Repr, Inhabited

/-- One cell of an engine's table: its row, its column (a probe block or `sweep:<id>`) and its verdict; `none` is a block
with no verdicts at all (`not-run`).

$$\mathrm{Cell} = \mathrm{Row} \times \mathrm{Col} \times (\mathcal V \cup \{\mathrm{notRun}\})$$ -/
structure TableCell where
  row : String
  col : String
  v : Option Verdict
  deriving DecidableEq, Repr

/-- The cell passed.

$$\operatorname{isPass}(r, c, v) \iff v = \mathrm{pass}$$ -/
def TableCell.isPass (c : TableCell) : Bool := c.v == some .pass

/-- The cell failed.

$$\operatorname{isFail}(r, c, v) \iff v = \mathrm{fail}$$ -/
def TableCell.isFail (c : TableCell) : Bool := c.v == some .fail

/-- One entry of the allowlist of excused cells: which engine, which row (`none`: any row) and column, which verdict it
excuses, why, and the Lean fact or incident that is the premise (a name that must resolve: a renamed theorem breaks the build).

$$\mathrm{Ex} = \mathrm{Id} \times \mathrm{Engine} \times (\mathrm{Row} \cup \{*\}) \times \mathrm{Col} \times \mathcal V \times \mathrm{Reason} \times \mathrm{Premise}$$ -/
structure Exemption where
  id : String
  engine : String
  row : Option String
  col : String
  verdict : Verdict
  reason : String
  premise : Lean.Name

/-- An exemption names a cell of an engine: the same engine, the same column, the same verdict and the same row (or any row).

$$\operatorname{matches}(x, e, c) \iff x.\mathit{engine} = e \wedge x.\mathit{col} = c.\mathit{col} \wedge c.v = x.\mathit{verdict} \wedge (x.\mathit{row} = * \vee x.\mathit{row} = c.\mathit{row})$$ -/
def Exemption.matches (x : Exemption) (engine : String) (c : TableCell) : Bool :=
  x.engine == engine && x.col == c.col && c.v == some x.verdict && (x.row.map (· == c.row)).getD true

/-- **The allowlist of excused cells** (an exemption is a cell id, an engine, a verdict, a reason and a premise; nothing outside
this list is ever excused, and the list excuses only `not-comparable` and `unreachable` verdicts, `exemptions_verdict`).

$$\mathrm{exemptions} = [x_{\mathrm{cross}},\ x_{\mathrm{frac}},\ x_{\mathrm{mm}}]$$

* $x_{\mathrm{cross}}$: WebKit, any row, column `hover-pointer-cross`, `unreachable:primary-pair`, premise `matrix_cross_webkit`.
* $x_{\mathrm{frac}}$: WebKit, any row, column `fractional-gaps`, `unreachable:whole-width`, premise `matrix_fractional_webkit`.
* $x_{\mathrm{mm}}$: Chromium, row `matchMedia =Lean`, column `fractional-gaps`, `not-comparable`, premise `truthItems_lean_na`. -/
def exemptions : List Exemption :=
  [ { id := "webkit-cross-primary-pair", engine := "playwright-webkit", row := none, col := "hover-pointer-cross",
      verdict := .unreachable .primaryPair,
      reason := "WebKit derives hover and pointer from one value, so a cross probe (hover without a fine pointer, or the reverse) cannot be delivered",
      premise := ``Fw.Gate.matrix_cross_webkit },
    { id := "webkit-fractional-whole-width", engine := "playwright-webkit", row := none, col := "fractional-gaps",
      verdict := .unreachable .wholeWidth,
      reason := "WebKit's media width is a whole number, so a width strictly between two whole widths cannot be delivered",
      premise := ``Fw.Gate.matrix_fractional_webkit },
    { id := "chromium-matchmedia-lean-fractional", engine := "chromium", row := some "matchMedia =Lean", col := "fractional-gaps",
      verdict := .nc,
      reason := "a fractional width is loaded at its ceiling, so the requested environment is not achieved and every check against Lean's value is not applicable",
      premise := ``Fw.Gate.truthItems_lean_na } ]

/-- The id under which a not-run cell of a narrowed run is excused.

$$\mathrm{narrowedId} = \texttt{narrowed-run}$$ -/
def narrowedId : String := "narrowed-run"

/-- Why a narrowed run excuses its not-run cells: the parts it did not cover carry no verdict, and the summary names them.

$$\mathrm{narrowedReason} \in \mathrm{String}$$ -/
def narrowedReason : String :=
  "a run narrowed to parts (header.parts) does not load the others; its cells for them carry no verdict and the summary names the skipped parts"

/-- **The excuse of a cell**, or none. A not-run cell is excused only when the run is narrowed; any other cell only by a
registered exemption.

$$\operatorname{excuse}(e, N, c) = \begin{cases} (N ? \texttt{narrowed-run} : \bot) & c.v = \mathrm{notRun} \\ \operatorname{id}(\text{first } x \in \mathrm{exemptions} \text{ with } \operatorname{matches}(x, e, c)) & \text{otherwise} \end{cases}$$ -/
def excuse (engine : String) (narrowed : Bool) (c : TableCell) : Option String :=
  if c.v.isNone then (if narrowed then some narrowedId else none)
  else (exemptions.find? (·.matches engine c)).map (·.id)

/-- A cell is `ok` when it passed or is excused.

$$\operatorname{ok}(e, N, c) \iff c.v = \mathrm{pass} \vee \operatorname{excuse}(e, N, c) \ne \bot$$ -/
def TableCell.ok (e : String) (narrowed : Bool) (c : TableCell) : Bool := c.isPass || (excuse e narrowed c).isSome

/-- The registry excuses neither a pass nor a fail.

$$\forall x \in \mathrm{exemptions},\ x.\mathit{verdict} \ne \mathrm{pass} \wedge x.\mathit{verdict} \ne \mathrm{fail}$$

A failing cell is never excusable; only not-comparable and unreachable cells can be. -/
theorem exemptions_verdict : ∀ x ∈ exemptions, x.verdict ≠ .pass ∧ x.verdict ≠ .fail := by
  decide

/-- A cell with an excuse neither passed nor failed.

$$\operatorname{excuse}(e, N, c) \ne \bot \implies c.v \ne \mathrm{pass} \wedge c.v \ne \mathrm{fail}$$

Excusing a cell never turns a failure into a pass. -/
theorem excuse_not_pass_fail (e : String) (N : Bool) (c : TableCell) (h : (excuse e N c).isSome = true) :
    c.v ≠ some .pass ∧ c.v ≠ some .fail := by
  unfold excuse at h
  by_cases hn : c.v.isNone = true
  · have : c.v = none := Option.isNone_iff_eq_none.1 hn
    simp [this]
  · simp only [hn, Bool.false_eq_true, ↓reduceIte] at h
    cases hf : exemptions.find? (·.matches e c) with
    | none => simp [hf] at h
    | some x =>
      have hm := List.find?_some hf
      have hmem := List.mem_of_find?_eq_some hf
      simp only [Exemption.matches, Bool.and_eq_true, beq_iff_eq] at hm
      have hv := exemptions_verdict x hmem
      rw [hm.1.2]
      exact ⟨fun e => hv.1 (Option.some.inj e), fun e => hv.2 (Option.some.inj e)⟩

/-- The verdict of one engine from the cells of its table, whether the run was narrowed to parts, and the number of unsettled
samples.

$$\operatorname{ev}_C(e, N, cs, u) = \begin{cases} \mathrm{fail} & \exists c \in cs,\ c.v = \mathrm{fail} \\ \mathrm{unsettled} & \text{no fail} \wedge u > 0 \\ \mathrm{incomplete} & \text{no fail} \wedge u = 0 \wedge \exists c \in cs,\ \neg\operatorname{ok}(e, N, c) \\ \mathrm{pass} & \text{the above fail} \wedge \exists c \in cs,\ c.v = \mathrm{pass} \\ \mathrm{notRendered} & \text{otherwise} \end{cases}$$

A failing cell fails the engine; else an unsettled sample makes it unsettled; else a cell that is neither a pass nor excused makes it
incomplete; else it passes only if some cell passed. -/
def engineVerdictC (e : String) (narrowed : Bool) (cs : List TableCell) (unsettled : Nat) : EngineVerdict :=
  if cs.any TableCell.isFail then .fail
  else if 0 < unsettled then .unsettled
  else if cs.any (fun c => !c.ok e narrowed) then .incomplete
  else if cs.any TableCell.isPass then .pass
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

A failing engine is not a pass. -/
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

/-- An incomplete engine never gives exit 0.

$$\forall vs,\ \mathrm{incomplete} \in vs \implies \operatorname{exit}(vs) \ne 0$$

A run with a cell that was neither passed nor excused is not a pass. -/
theorem exit_ne_zero_of_incomplete (vs : List EngineVerdict) (h : EngineVerdict.incomplete ∈ vs) :
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

/-- **An engine passes exactly when every one of its cells is ok, no sample is unsettled and some cell passed.**

$$\forall e, N, cs, u,\quad \operatorname{ev}_C(e, N, cs, u) = \mathrm{pass} \iff u = 0 \wedge \bigl(\forall c \in cs,\ \operatorname{ok}(e, N, c)\bigr) \wedge \exists c \in cs,\ c.v = \mathrm{pass}$$

There is no aggregate: a single cell that is neither a pass nor excused keeps the engine from passing. -/
theorem engine_pass_iff_all_cells (e : String) (N : Bool) (cs : List TableCell) (u : Nat) :
    engineVerdictC e N cs u = .pass ↔
      u = 0 ∧ (∀ c ∈ cs, c.ok e N = true) ∧ ∃ c ∈ cs, c.isPass = true := by
  have hfail : ∀ c ∈ cs, c.ok e N = true → c.isFail = false := by
    intro c _ hok
    cases hf : c.isFail with
    | false => rfl
    | true =>
      have hv : c.v = some .fail := by simpa [TableCell.isFail] using hf
      simp only [TableCell.ok, TableCell.isPass, hv, Bool.or_eq_true, beq_iff_eq] at hok
      rcases hok with h | h
      · cases h
      · exact absurd hv (excuse_not_pass_fail e N c h).2
  unfold engineVerdictC
  constructor
  · intro h
    by_cases h1 : cs.any TableCell.isFail = true
    · simp [h1] at h
    · by_cases h2 : 0 < u
      · simp [h1, h2] at h
      · by_cases h3 : cs.any (fun c => !c.ok e N) = true
        · simp [h1, h2, h3] at h
        · by_cases h4 : cs.any TableCell.isPass = true
          · refine ⟨by omega, ?_, by simpa using h4⟩
            intro c hc
            cases hk : c.ok e N with
            | true => rfl
            | false => exact absurd (List.any_eq_true.2 ⟨c, hc, by simp [hk]⟩) h3
          · simp [h1, h2, h3, h4] at h
  · rintro ⟨hu, hall, hex⟩
    have h1 : ¬ (cs.any TableCell.isFail = true) := by
      intro h
      obtain ⟨c, hc, hf⟩ := List.any_eq_true.1 h
      have := hfail c hc (hall c hc)
      simp [this] at hf
    have h2 : ¬ (0 < u) := by omega
    have h3 : ¬ (cs.any (fun c => !c.ok e N) = true) := by
      intro h
      obtain ⟨c, hc, hn⟩ := List.any_eq_true.1 h
      simp [hall c hc] at hn
    have h4 : cs.any TableCell.isPass = true := by
      obtain ⟨c, hc, hp⟩ := hex
      exact List.any_eq_true.2 ⟨c, hc, hp⟩
    simp [h1, h2, h3, h4]

/-- A cell that is neither a pass nor excused keeps its engine from passing.

$$c \in cs \wedge \neg\operatorname{ok}(e, N, c) \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

Whatever the other cells say. -/
theorem engineVerdictC_ne_pass_of_cell (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (h : c.ok e N = false) : engineVerdictC e N cs u ≠ .pass := by
  intro hp
  have := ((engine_pass_iff_all_cells e N cs u).1 hp).2.1 c hc
  rw [h] at this
  cases this

/-- A not-comparable cell that no exemption names keeps its engine from passing.

$$c \in cs \wedge c.v = \mathrm{nc} \wedge \operatorname{excuse}(e, N, c) = \bot \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

Not comparable is never a pass. -/
theorem engineVerdictC_nc_ne_pass (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (hv : c.v = some .nc) (hx : excuse e N c = none) : engineVerdictC e N cs u ≠ .pass := by
  apply engineVerdictC_ne_pass_of_cell e N cs u c hc
  simp [TableCell.ok, TableCell.isPass, hv, hx]

/-- In a run that was not narrowed, a not-run cell keeps its engine from passing.

$$c \in cs \wedge c.v = \mathrm{notRun} \implies \operatorname{ev}_C(e, \bot, cs, u) \ne \mathrm{pass}$$

A full run has no missing cell. -/
theorem engineVerdictC_notRun_ne_pass (e : String) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (hv : c.v = none) : engineVerdictC e false cs u ≠ .pass := by
  apply engineVerdictC_ne_pass_of_cell e false cs u c hc
  simp [TableCell.ok, TableCell.isPass, excuse, hv]

/-- A failing cell fails its engine.

$$\exists c \in cs,\ c.v = \mathrm{fail} \implies \operatorname{ev}_C(e, N, cs, u) = \mathrm{fail}$$

Unsettled samples do not hide a failure. -/
theorem engineVerdictC_fail (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (hv : c.v = some .fail) : engineVerdictC e N cs u = .fail := by
  unfold engineVerdictC
  have : cs.any TableCell.isFail = true := List.any_eq_true.2 ⟨c, hc, by simp [TableCell.isFail, hv]⟩
  simp [this]

/-- Unsettled samples keep an engine from passing.

$$u > 0 \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

A run with a sample that did not settle is not a pass. -/
theorem engineVerdictC_unsettled_ne_pass (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (h : 0 < u) :
    engineVerdictC e N cs u ≠ .pass := by
  intro hp
  have := ((engine_pass_iff_all_cells e N cs u).1 hp).1
  omega

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

/-- The count is zero exactly when every wait of every sample settled.

$$\operatorname{u}(ws) = 0 \iff \forall (a, b) \in ws,\ a \ne \mathrm{unsettled} \wedge b \ne \mathrm{unsettled}$$

-/
theorem unsettledStates_zero_iff (ws : List (Outcome × Outcome)) :
    unsettledStates ws = 0 ↔ ∀ s ∈ ws, s.1 ≠ .unsettled ∧ s.2 ≠ .unsettled := by
  have hp := unsettledStates_pos_iff ws
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

/-- The verdict of one engine from its cells and the wait outcomes of its samples.

$$\operatorname{ev}_S(e, N, cs, ws) = \operatorname{ev}_C(e, N, cs, \operatorname{u}(ws))$$

-/
def engineVerdictCS (e : String) (narrowed : Bool) (cs : List TableCell) (ws : List (Outcome × Outcome)) : EngineVerdict :=
  engineVerdictC e narrowed cs (unsettledStates ws)

/-- **An engine passes exactly when every cell is ok, every wait of every sample settled and some cell passed.**

$$\operatorname{ev}_S(e, N, cs, ws) = \mathrm{pass} \iff \bigl(\forall (a, b) \in ws,\ a \ne \mathrm{unsettled} \wedge b \ne \mathrm{unsettled}\bigr) \wedge \bigl(\forall c \in cs,\ \operatorname{ok}(e, N, c)\bigr) \wedge \exists c \in cs,\ c.v = \mathrm{pass}$$

Each cell and each wait is judged on its own. -/
theorem engineVerdictCS_pass_iff (e : String) (N : Bool) (cs : List TableCell) (ws : List (Outcome × Outcome)) :
    engineVerdictCS e N cs ws = .pass ↔
      (∀ s ∈ ws, s.1 ≠ .unsettled ∧ s.2 ≠ .unsettled) ∧ (∀ c ∈ cs, c.ok e N = true) ∧ ∃ c ∈ cs, c.isPass = true := by
  unfold engineVerdictCS
  rw [engine_pass_iff_all_cells, unsettledStates_zero_iff]

/-- A sample with an unsettled wait keeps its engine from passing.

$$\forall (a, b) \in ws,\ (a = \mathrm{unsettled} \vee b = \mathrm{unsettled}) \implies \operatorname{ev}_S(e, N, cs, ws) \ne \mathrm{pass}$$

Whatever the cells say, an engine with a sample that did not settle is not a pass. -/
theorem engineVerdictCS_ne_pass_of_unsettled (e : String) (N : Bool) (cs : List TableCell) (ws : List (Outcome × Outcome))
    (s : Outcome × Outcome) (hs : s ∈ ws) (h : s.1 = .unsettled ∨ s.2 = .unsettled) : engineVerdictCS e N cs ws ≠ .pass := by
  intro hp
  have := ((engineVerdictCS_pass_iff e N cs ws).1 hp).1 s hs
  rcases h with h | h
  · exact this.1 h
  · exact this.2 h

/-- One engine of a run: its name, whether the run was narrowed to parts, its cells and its samples' wait outcomes.

$$\mathrm{In} = \mathrm{Engine} \times \{\bot, \top\} \times \mathrm{Cell}^{*} \times (\mathrm{Outcome} \times \mathrm{Outcome})^{*}$$ -/
structure EngineInput where
  engine : String
  narrowed : Bool
  cells : List TableCell
  waits : List (Outcome × Outcome)

/-- The verdict of one engine of a run.

$$\operatorname{eng}(i) = \operatorname{ev}_S(i.\mathit{engine}, i.\mathit{narrowed}, i.\mathit{cells}, i.\mathit{waits})$$ -/
def EngineInput.verdict (i : EngineInput) : EngineVerdict := engineVerdictCS i.engine i.narrowed i.cells i.waits

/-- **A run exits 0 exactly when every cell of every engine is ok, every wait settled and each engine has a passing cell.**

$$\operatorname{exit}([\operatorname{eng}(i)]_{i \in is}) = 0 \iff is \ne [\,] \wedge \forall i \in is,\ \Bigl(\forall s \in i.\mathit{waits},\ s_1, s_2 \ne \mathrm{unsettled}\Bigr) \wedge \bigl(\forall c \in i.\mathit{cells},\ \operatorname{ok}(i.\mathit{engine}, i.\mathit{narrowed}, c)\bigr) \wedge \exists c \in i.\mathit{cells},\ c.v = \mathrm{pass}$$

The exit code is the conjunction over every cell and every wait; nothing is aggregated first. -/
theorem exit_zero_iff_all_cells (is : List EngineInput) :
    exitCode (is.map EngineInput.verdict) = 0 ↔
      is ≠ [] ∧ ∀ i ∈ is, (∀ s ∈ i.waits, s.1 ≠ .unsettled ∧ s.2 ≠ .unsettled) ∧
        (∀ c ∈ i.cells, c.ok i.engine i.narrowed = true) ∧ ∃ c ∈ i.cells, c.isPass = true := by
  rw [exit_zero_iff]
  constructor
  · rintro ⟨hne, hall⟩
    refine ⟨fun e => hne (by simp [e]), fun i hi => ?_⟩
    exact (engineVerdictCS_pass_iff _ _ _ _).1 (hall _ (List.mem_map.2 ⟨i, hi, rfl⟩))
  · rintro ⟨hne, hall⟩
    refine ⟨fun e => hne (by simpa using e), fun v hv => ?_⟩
    obtain ⟨i, hi, rfl⟩ := List.mem_map.1 hv
    exact (engineVerdictCS_pass_iff _ _ _ _).2 (hall i hi)

/-- **A cell that is neither a pass nor excused, in any engine, gives a non-zero exit.**

$$\forall i \in is,\ \forall c \in i.\mathit{cells},\ \neg\operatorname{ok}(i.\mathit{engine}, i.\mathit{narrowed}, c) \implies \operatorname{exit}([\operatorname{eng}(i')]_{i' \in is}) \ne 0$$

One failing, not-comparable, unreachable-unregistered or missing cell in one engine is enough. -/
theorem exit_ne_zero_of_cell (is : List EngineInput) (i : EngineInput) (hi : i ∈ is) (c : TableCell) (hc : c ∈ i.cells)
    (h : c.ok i.engine i.narrowed = false) : exitCode (is.map EngineInput.verdict) ≠ 0 := by
  intro z
  have := ((exit_zero_iff_all_cells is).1 z).2 i hi
  rw [this.2.1 c hc] at h
  cases h

/-- **A sample with an unsettled wait anywhere gives a non-zero exit.**

$$\forall i \in is,\ \forall s \in i.\mathit{waits},\ (s_1 = \mathrm{unsettled} \vee s_2 = \mathrm{unsettled}) \implies \operatorname{exit}([\operatorname{eng}(i')]_{i' \in is}) \ne 0$$

The exit code is taken from the waits, not from a flag the page sets. -/
theorem exit_ne_zero_of_wait_unsettled (is : List EngineInput) (i : EngineInput) (hi : i ∈ is) (s : Outcome × Outcome)
    (hs : s ∈ i.waits) (h : s.1 = .unsettled ∨ s.2 = .unsettled) : exitCode (is.map EngineInput.verdict) ≠ 0 := by
  intro z
  have := ((exit_zero_iff_all_cells is).1 z).2 i hi
  rcases h with h | h
  · exact (this.1 s hs).1 h
  · exact (this.1 s hs).2 h

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

/-- A natural number from plain ASCII digits only: nonempty, every character `0`..`9`. (`String.toNat?` also accepts `_`
separators, which no summary writes and no wire should carry.)

$$\operatorname{digits}(s) = \begin{cases} \sum_i d_i 10^{|s| - 1 - i} & s \ne \varepsilon \wedge \forall i,\ s_i \in \{\texttt{0}, \ldots, \texttt{9}\} \\ \bot & \text{otherwise} \end{cases}$$ -/
def plainNat? (s : String) : Option Nat :=
  if !s.isEmpty && s.all Char.isDigit then some (s.foldl (fun n c => 10 * n + (c.toNat - 48)) 0) else none

/-- A plain number is read exactly from a nonempty string of ASCII digits.

$$\operatorname{digits}(s) \ne \bot \iff s \ne \varepsilon \wedge \forall i,\ s_i \in \{\texttt{0}, \ldots, \texttt{9}\}$$

Underscores, signs and empty strings are not numbers. -/
theorem plainNat_isSome_iff (s : String) : (plainNat? s).isSome = true ↔ s.isEmpty = false ∧ s.all Char.isDigit = true := by
  unfold plainNat?
  by_cases h : (!s.isEmpty && s.all Char.isDigit) = true
  · simp only [h, ↓reduceIte, Option.isSome_some, true_iff]
    simpa using h
  · simp only [h, Bool.false_eq_true, ↓reduceIte, Option.isSome_none, false_iff]
    intro hh
    exact h (by simp [hh.1, hh.2])

/-- The wire form of a wait outcome: `settled@<i>` with plain digits, `unsettled`, and `missing` (a sample the run made
without the wait), which is read as unsettled.

$$\operatorname{ow}(s) = \begin{cases} \mathrm{settled}(i) & s = \texttt{settled@}d,\ \operatorname{digits}(d) = i \\ \mathrm{unsettled} & s \in \{\texttt{unsettled}, \texttt{missing}\} \\ \text{error} & \text{otherwise} \end{cases}$$

A wait that is absent is not a pass; `settled@`, `settled@+1`, `settled@1_0` and `settled@x` are errors. -/
def outcomeOfWire (s : String) : Except String Outcome :=
  if s = "unsettled" ∨ s = "missing" then .ok .unsettled
  else if s.startsWith "settled@" then
    match plainNat? (String.ofList (s.toList.drop 8)) with
    | some i => .ok (.settled i)
    | none => .error s!"unknown outcome {s}"
  else .error s!"unknown outcome {s}"

/-- A missing wait is read as unsettled.

$$\operatorname{ow}(\texttt{missing}) = \mathrm{unsettled}$$

-/
theorem outcomeOfWire_missing : outcomeOfWire "missing" = .ok .unsettled := by simp [outcomeOfWire]

/-- One table cell from its wire names: the row, the column and the verdict name (`pass`, `fail`, `not-comparable`,
`unreachable:<reason>`, or `not-run` for a block with no verdicts).

$$\operatorname{cell}(r, c, n) = \begin{cases} \operatorname{ok}((r, c, \mathrm{notRun})) & n = \texttt{not-run} \\ \operatorname{ok}((r, c, v(n))) & v(n) \text{ known} \\ \operatorname{error}(\texttt{unknown verdict } n) & \text{otherwise} \end{cases}$$

An unknown name is an error, never a pass. -/
def tableCellOfWire (row col name : String) : Except String TableCell :=
  if name = "not-run" then .ok ⟨row, col, none⟩
  else do return ⟨row, col, some (← Fw.Wire.Gate.verdictOf name)⟩

/-- The verdict of one engine from the wire names of its cells (row, column, verdict) and of its samples' wait outcomes (one
pair per probe or sweep stop).

$$\operatorname{ev}_{WW}(e, N, ns, ws) = \begin{cases} \operatorname{ok}\bigl(\operatorname{ev}_S(e, N, [\operatorname{cell}(r, c, n)]_{(r, c, n) \in ns},\ [(\operatorname{ow}(a), \operatorname{ow}(b))]_{(a, b) \in ws})\bigr) & \text{every name is known} \\ \operatorname{error}(m) & m \text{ the first error: the cells are read first, in order, then the waits} \end{cases}$$

-/
def engineVerdictCW (engine : String) (narrowed : Bool) (cells : List (String × String × String))
    (waits : List (String × String)) : Except String EngineVerdict := do
  let cs ← cells.mapM fun c => tableCellOfWire c.1 c.2.1 c.2.2
  let ws ← waits.mapM fun w => do return ((← outcomeOfWire w.1), (← outcomeOfWire w.2))
  return engineVerdictCS engine narrowed cs ws

/-! ## The wire form (what `cli.mjs` reads) -/

/-- The wire names of an engine verdict, as `cli.mjs` prints them.

$$\operatorname{wire}(v) = \text{the name of the constructor } v \in \{\texttt{pass}, \texttt{fail}, \texttt{unsettled}, \texttt{incomplete}, \texttt{notRendered}\}$$

Each verdict is printed under the name of its constructor. -/
def verdictWire : EngineVerdict → String
  | .pass => "pass" | .fail => "fail" | .unsettled => "unsettled" | .incomplete => "incomplete" | .notRendered => "notRendered"

/-! ## Golden vectors -/

open Lean in
/-- The JSON of one exemption: id, engine, row (`null`: any), column, verdict wire name, reason and premise.

$$x \mapsto \{\mathrm{col}, \mathrm{engine}, \mathrm{id}, \mathrm{kind} = \texttt{exemption}, \mathrm{premise}, \mathrm{reason}, \mathrm{row}, \mathrm{verdict}\}$$ -/
def exemptionLine (x : Exemption) : String :=
  (Json.mkObj [("kind", "exemption"), ("id", x.id), ("engine", x.engine),
    ("row", match x.row with | some r => Json.str r | none => Json.null), ("col", x.col),
    ("verdict", Fw.Wire.Gate.verdictName x.verdict), ("reason", x.reason), ("premise", x.premise.toString)]).compress

open Lean in
/-- The JSON of the narrowed-run excuse.

$$\{\mathrm{id} = \texttt{narrowed-run},\ \mathrm{kind} = \texttt{narrowed},\ \mathrm{reason}\}$$ -/
def narrowedLine : String :=
  (Json.mkObj [("kind", "narrowed"), ("id", narrowedId), ("reason", narrowedReason)]).compress

open Lean in
/-- One engine case: the engine, whether the run was narrowed, the wire names of its cells (row, column, verdict) and of its
samples' waits; the verdict, the unsettled count and the excused cells (excuse id, cell id `row|col`), or the first error.

$$\operatorname{engineCase}(e, N, ns, ws) = \begin{cases} \{\mathrm{cells} = ns,\ \mathrm{engine} = e,\ \mathrm{exempt} = X,\ \mathrm{kind} = \texttt{engine},\ \mathrm{narrowed} = N,\ \mathrm{unsettled} = \operatorname{u}(ws'),\ \mathrm{verdict} = \operatorname{wire}(v),\ \mathrm{waits} = ws\} & \operatorname{ev}_{WW}(e, N, ns, ws) = \operatorname{ok}(v) \\ \{\mathrm{cells} = ns,\ \mathrm{engine} = e,\ \mathrm{error} = m,\ \mathrm{kind} = \texttt{engine},\ \mathrm{narrowed} = N,\ \mathrm{waits} = ws\} & \operatorname{ev}_{WW}(e, N, ns, ws) = \operatorname{error}(m) \end{cases}$$

where $X = [[\operatorname{excuse}(e, N, c), r \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} c] \mid (r, c, \cdot) \in ns,\ \operatorname{excuse}(e, N, \cdot) \ne \bot]$.
One compact JSON object with keys in sorted order. -/
def engineCase (engine : String) (narrowed : Bool) (cells : List (String × String × String))
    (waits : List (String × String)) : String :=
  let head := [("kind", Json.str "engine"), ("engine", Json.str engine), ("narrowed", toJson narrowed),
    ("cells", toJson (cells.map fun c => [c.1, c.2.1, c.2.2])), ("waits", toJson (waits.map fun w => [w.1, w.2]))]
  match engineVerdictCW engine narrowed cells waits with
  | .ok v =>
    let cs := cells.filterMap fun c => (tableCellOfWire c.1 c.2.1 c.2.2).toOption
    let ws := waits.filterMap fun w => match outcomeOfWire w.1, outcomeOfWire w.2 with
      | .ok a, .ok b => some (a, b)
      | _, _ => none
    let ex := cs.filterMap fun c => (excuse engine narrowed c).map fun id => [id, c.row ++ "|" ++ c.col]
    (Json.mkObj (head ++ [("unsettled", toJson (unsettledStates ws)), ("verdict", Json.str (verdictWire v)), ("exempt", toJson ex)])).compress
  | .error e => (Json.mkObj (head ++ [("error", Json.str e)])).compress

open Lean in
/-- One hysteresis case: the wire outcomes of the two waits and whether the pair is compared.

$$\operatorname{staleCase}(a, f) = \begin{cases} \{\mathrm{after} = a,\ \mathrm{comparable} = \operatorname{cmp}(\operatorname{ow}(a), \operatorname{ow}(f)),\ \mathrm{fresh} = f,\ \mathrm{kind} = \texttt{stale}\} & \operatorname{ow}(a), \operatorname{ow}(f) \text{ both ok} \\ \{\mathrm{after} = a,\ \mathrm{error} = \texttt{unknown outcome},\ \mathrm{fresh} = f,\ \mathrm{kind} = \texttt{stale}\} & \text{otherwise} \end{cases}$$

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

/-- A passing cell in the original's `desk` column, for the cases below.

$$\mathrm{ok}_0 = (\texttt{engine.scroll}, \texttt{desk}, \texttt{pass})$$ -/
def okCell : String × String × String := ("engine.scroll", "desk", "pass")

/-- The three registered cells, as wire triples.

$$\mathrm{nc}_{mm} = (\texttt{matchMedia =Lean}, \texttt{fractional-gaps}, \texttt{not-comparable}),\ \mathrm{cross} = (\texttt{hero.exit}, \texttt{hover-pointer-cross}, \texttt{unreachable:primary-pair}),\ \mathrm{frac} = (\texttt{hero.exit}, \texttt{fractional-gaps}, \texttt{unreachable:whole-width})$$ -/
def ncMm : String × String × String := ("matchMedia =Lean", "fractional-gaps", "not-comparable")

/-- A cross cell of a WebKit table.

$$\mathrm{cross} = (\texttt{hero.exit}, \texttt{hover-pointer-cross}, \texttt{unreachable:primary-pair})$$ -/
def crossCell : String × String × String := ("hero.exit", "hover-pointer-cross", "unreachable:primary-pair")

/-- A fractional cell of a WebKit table.

$$\mathrm{frac} = (\texttt{hero.exit}, \texttt{fractional-gaps}, \texttt{unreachable:whole-width})$$ -/
def fracCell : String × String × String := ("hero.exit", "fractional-gaps", "unreachable:whole-width")

/-- The golden lines (`packages/contracts/golden/gate/exit.jsonl`).

$$\mathrm{goldenLines} = [\operatorname{exemptionLine}(x)]_{x \in \mathrm{exemptions}} \mathbin{+\!\!+} [\mathrm{narrowedLine}] \mathbin{+\!\!+} [\operatorname{engineCase}(e, N, ns, ws)]_{(e, N, ns, ws) \in E} \mathbin{+\!\!+} [\operatorname{exitCase}(vs)]_{vs \in X} \mathbin{+\!\!+} [\operatorname{staleCase}(a, f)]_{(a, f) \in S}$$

with $|\mathrm{exemptions}| = 3$, $|E| = 33$ engine cases, $|X| = 10$ run cases and $|S| = 8$ hysteresis cases, so the file has
$3 + 1 + 33 + 10 + 8 = 55$ lines in that order. The engine cases cover: every registered exemption and each of its three
conditions broken (other engine, other row, other verdict, other column), a not-comparable or unreachable cell with no
exemption, a not-run cell in a full and in a narrowed run, the order fail over unsettled over incomplete over not-rendered, and the
wait outcomes (plain digits only, a missing wait, an unknown name, the first error). -/
def goldenLines : List String :=
  exemptions.map exemptionLine ++ [narrowedLine] ++
  [ engineCase "chromium" false [okCell, ncMm] [("settled@3", "settled@5")],
    engineCase "chromium" false [okCell, ("nav.hitTest", "fractional-gaps", "not-comparable")] [],
    engineCase "chromium" false [okCell, ("matchMedia =Lean", "desk", "not-comparable")] [],
    engineCase "chromium" false [okCell, ("matchMedia =Lean", "fractional-gaps", "unreachable:whole-width")] [],
    engineCase "playwright-webkit" false [okCell, ncMm] [],
    engineCase "playwright-webkit" false [okCell, crossCell, fracCell, ("matchMedia =Lean", "hover-pointer-cross", "unreachable:primary-pair")] [("settled@0", "settled@0")],
    engineCase "playwright-webkit" false [okCell, ("hero.exit", "hover-pointer-cross", "unreachable:whole-width")] [],
    engineCase "playwright-webkit" false [okCell, ("hero.exit", "desk", "unreachable:primary-pair")] [],
    engineCase "playwright-webkit" false [okCell, ("hero.exit", "hover-pointer-cross", "not-comparable")] [],
    engineCase "chromium" false [okCell, crossCell] [],
    engineCase "firefox" false [okCell, crossCell] [],
    engineCase "playwright-webkit" false [okCell, crossCell, ("platform.stageBg", "sweep:desktop-1512-320-1512", "fail")] [],
    engineCase "chromium" false [okCell, ("hero.exit", "desk", "unreachable:width-dpr")] [],
    engineCase "chromium" false [okCell, ("morph.panel", "desk", "not-run")] [],
    engineCase "chromium" true [okCell, ("morph.panel", "desk", "not-run")] [],
    engineCase "chromium" true [okCell, ("morph.panel", "desk", "not-run"), ncMm] [],
    engineCase "chromium" true [okCell, ("hero.exit", "desk", "not-comparable")] [],
    engineCase "chromium" true [("morph.panel", "desk", "not-run")] [],
    engineCase "chromium" false [ncMm] [],
    engineCase "chromium" false [] [],
    engineCase "chromium" false [okCell, ("hero.exit", "desk", "fail")] [("unsettled", "settled@1")],
    engineCase "chromium" false [okCell] [("settled@3", "settled@5"), ("settled@2", "settled@2")],
    engineCase "chromium" false [okCell] [("settled@3", "settled@5"), ("settled@2", "unsettled")],
    engineCase "chromium" false [okCell] [("unsettled", "settled@1")],
    engineCase "chromium" false [okCell, ("hero.exit", "desk", "not-comparable")] [("settled@3", "missing")],
    engineCase "chromium" false [okCell] [("settled@3", "late")],
    engineCase "chromium" false [okCell] [("settled@007", "settled@0")],
    engineCase "chromium" false [okCell] [("settled@1_0", "settled@0")],
    engineCase "chromium" false [okCell] [("settled@", "settled@0")],
    engineCase "chromium" false [okCell] [("settled@+1", "settled@0")],
    engineCase "chromium" false [okCell, ("hero.exit", "desk", "bogus")] [("late", "settled@0")],
    engineCase "chromium" false [okCell] [("late", "settled@0"), ("also-late", "settled@0")],
    engineCase "chromium" false [("hero.exit", "desk", "not-run")] [],
    exitCase [.pass],
    exitCase [.pass, .pass],
    exitCase [.pass, .fail],
    exitCase [.fail],
    exitCase [.unsettled],
    exitCase [.pass, .unsettled],
    exitCase [.incomplete],
    exitCase [.pass, .incomplete],
    exitCase [.pass, .notRendered],
    exitCase [],
    staleCase "settled@4" "settled@9",
    staleCase "unsettled" "settled@9",
    staleCase "settled@4" "unsettled",
    staleCase "missing" "missing",
    staleCase "settled@007" "settled@1",
    staleCase "settled@1_0" "settled@1",
    staleCase "settled@4" "late",
    staleCase "settled@" "settled@1" ]

#guard goldenLines.length == 55
#guard exitCode [] == 1
#guard exitCode [.pass, .pass] == 0
#guard exitCode [.pass, .fail] == 1
#guard exitCode [.pass, .incomplete] == 1
#guard plainNat? "007" == some 7
#guard plainNat? "1_0" == none
#guard plainNat? "" == none
#guard plainNat? "+1" == none
#guard plainNat? "٣" == none
#guard staleComparable (.settled 1) .unsettled == false
-- the wire cells below are decided by Lean; the cases above pin the golden bytes
#guard (engineVerdictCW "chromium" false [okCell, ncMm] []).toOption == some .pass
#guard (engineVerdictCW "chromium" false [okCell, ("nav.hitTest", "fractional-gaps", "not-comparable")] []).toOption == some .incomplete
#guard (engineVerdictCW "playwright-webkit" false [okCell, crossCell, fracCell] []).toOption == some .pass
#guard (engineVerdictCW "playwright-webkit" false [okCell, ("hero.exit", "desk", "unreachable:primary-pair")] []).toOption == some .incomplete
#guard (engineVerdictCW "chromium" false [okCell, ("morph.panel", "desk", "not-run")] []).toOption == some .incomplete
#guard (engineVerdictCW "chromium" true [okCell, ("morph.panel", "desk", "not-run")] []).toOption == some .pass
#guard (engineVerdictCW "chromium" false [okCell, ("hero.exit", "desk", "fail")] [("unsettled", "settled@1")]).toOption == some .fail
#guard (engineVerdictCW "chromium" false [okCell] [("settled@1_0", "settled@0")]).toOption == none

end Fw.Gate.Exit
