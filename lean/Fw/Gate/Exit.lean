import Lean.Data.Json
import Fw.Wire.Gate
import Fw.Gate.Settle
import Fw.Gate.State
import Fw.Gate.Scope
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

/-- One reading of a cell: the verdict of one probe, or of one stop of a sweep, in one (row, column) cell. Its id is the probe id, or
`<sweep id>#<stop index>` for a sweep stop.

$$\mathrm{Reading} = \mathrm{Id} \times \mathcal V$$

A reading is judged on its own; no other reading of the cell can absorb it. -/
structure Reading where
  id : String
  v : Verdict
  deriving DecidableEq, Repr

/-- One cell of an engine's table: its row, its column (a probe block or `sweep:<id>`) and the readings the cell is made of; no
reading at all is a block that was not run (`not-run`).

$$\mathrm{Cell} = \mathrm{Row} \times \mathrm{Col} \times \mathrm{Reading}^{*}$$ -/
structure TableCell where
  row : String
  col : String
  readings : List Reading
  deriving DecidableEq, Repr

/-- Some reading of the cell passed.

$$\operatorname{isPass}(c) \iff \exists r \in c.\mathit{readings},\ r.v = \mathrm{pass}$$ -/
def TableCell.isPass (c : TableCell) : Bool := c.readings.any (·.v == .pass)

/-- Some reading of the cell failed.

$$\operatorname{isFail}(c) \iff \exists r \in c.\mathit{readings},\ r.v = \mathrm{fail}$$ -/
def TableCell.isFail (c : TableCell) : Bool := c.readings.any (·.v == .fail)

/-- One entry of the allowlist of excused readings: which engine, which row (`none`: any row) and column, which readings of the
cell (`none`: any reading of it, `some ids`: only those reading ids), which verdict it excuses, why, and the Lean fact that is the
premise (a name that must resolve: a renamed theorem breaks the build).

$$\mathrm{Ex} = \mathrm{Id} \times \mathrm{Engine} \times (\mathrm{Row} \cup \{*\}) \times \mathrm{Col} \times (\mathrm{Id}^{*} \cup \{*\}) \times \mathcal V \times \mathrm{Reason} \times \mathrm{Premise}$$ -/
structure Exemption where
  id : String
  engine : String
  row : Option String
  col : String
  ids : Option (List String)
  verdict : Verdict
  reason : String
  premise : Lean.Name

/-- An exemption names a reading: the same engine, column and verdict, the same row (or any row) and the same reading id (or any).

$$\operatorname{matches}(x, e, \rho, \kappa, r) \iff x.\mathit{engine} = e \wedge x.\mathit{col} = \kappa \wedge r.v = x.\mathit{verdict} \wedge (x.\mathit{row} = * \vee x.\mathit{row} = \rho) \wedge (x.\mathit{ids} = * \vee r.\mathit{id} \in x.\mathit{ids})$$ -/
def Exemption.matches (x : Exemption) (engine row col : String) (r : Reading) : Bool :=
  x.engine == engine && x.col == col && r.v == x.verdict && (x.row.map (· == row)).getD true &&
    (x.ids.map (·.contains r.id)).getD true

/-- The reading ids of the 1024 stops of the tablet sweep (stops 0, 2 and 4 of `touch-1024-1201`, `touch1024_lean_na`).

$$\mathrm{touch1024Ids} = [\texttt{touch-1024-1201\#}i]_{i \in \{0, 2, 4\}}$$ -/
def touch1024Ids : List String := [0, 2, 4].map fun i => s!"touch-1024-1201#{i}"

/-- **The allowlist of excused readings** (an exemption is an engine, a cell, an optional list of reading ids, a verdict, a reason
and a premise; nothing outside this list is ever excused, and the list excuses only `not-comparable` and `unreachable`
verdicts, `exemptions_verdict`).

$$\mathrm{exemptions} = [x_{\mathrm{cross}},\ x_{\mathrm{frac}},\ x_{\mathrm{mm}},\ x_{\mathrm{touch}}^{\mathrm{chromium}},\ x_{\mathrm{touch}}^{\mathrm{webkit}}]$$

* $x_{\mathrm{cross}}$: WebKit, any row, column `hover-pointer-cross`, `unreachable:primary-pair`, premise `matrix_cross_webkit`.
* $x_{\mathrm{frac}}$: WebKit, any row, column `fractional-gaps`, `unreachable:whole-width`, premise `matrix_fractional_webkit`.
* $x_{\mathrm{mm}}$: Chromium, row `matchMedia =Lean`, column `fractional-gaps`, `not-comparable`, premise `truthItems_lean_na`.
* $x_{\mathrm{touch}}$: each engine, row `matchMedia =Lean`, column `sweep:touch-1024-1201`, readings `touch-1024-1201#0`, `#2`, `#4` only,
  `not-comparable`, premise `touch1024_lean_na`. The other two stops (1201) and the phone-rotation sweep have no entry: a
  not-comparable reading there is a finding, not an excuse. -/
def exemptions : List Exemption :=
  [ { id := "webkit-cross-primary-pair", engine := "playwright-webkit", row := none, col := "hover-pointer-cross", ids := none,
      verdict := .unreachable .primaryPair,
      reason := "WebKit derives hover and pointer from one value, so a cross probe (hover without a fine pointer, or the reverse) cannot be delivered",
      premise := ``Fw.Gate.matrix_cross_webkit },
    { id := "webkit-fractional-whole-width", engine := "playwright-webkit", row := none, col := "fractional-gaps", ids := none,
      verdict := .unreachable .wholeWidth,
      reason := "WebKit's media width is a whole number, so a width strictly between two whole widths cannot be delivered",
      premise := ``Fw.Gate.matrix_fractional_webkit },
    { id := "chromium-matchmedia-lean-fractional", engine := "chromium", row := some "matchMedia =Lean", col := "fractional-gaps",
      ids := none, verdict := .nc,
      reason := "a fractional width is loaded at its ceiling, so the requested environment is not achieved and every check against Lean's value is not applicable",
      premise := ``Fw.Gate.truthItems_lean_na },
    { id := "chromium-touch-1024-no-vector", engine := "chromium", row := some "matchMedia =Lean", col := "sweep:touch-1024-1201",
      ids := some touch1024Ids, verdict := .nc,
      reason := "the 1024 stops of the tablet sweep have no Lean vector (no matrix probe has that environment), so every check against Lean's value there is not applicable",
      premise := ``Fw.Gate.touch1024_lean_na },
    { id := "webkit-touch-1024-no-vector", engine := "playwright-webkit", row := some "matchMedia =Lean", col := "sweep:touch-1024-1201",
      ids := some touch1024Ids, verdict := .nc,
      reason := "the 1024 stops of the tablet sweep have no Lean vector (no matrix probe has that environment), so every check against Lean's value there is not applicable",
      premise := ``Fw.Gate.touch1024_lean_na } ]

/-- The id under which a not-run cell of a narrowed run is excused.

$$\mathrm{narrowedId} = \texttt{narrowed-run}$$ -/
def narrowedId : String := "narrowed-run"

/-- Why a narrowed run excuses its not-run cells: the parts it did not cover carry no verdict, and the summary names them.

$$\mathrm{narrowedReason} \in \mathrm{String}$$ -/
def narrowedReason : String :=
  "a run narrowed to parts (header.parts) does not load the others; its cells for them carry no verdict and the summary names the skipped parts"

/-- **The excuse of a reading**, or none: the id of the first exemption that names it. Only a registered exemption excuses.

$$\operatorname{excuse}(e, \rho, \kappa, r) = \operatorname{id}(\text{first } x \in \mathrm{exemptions} \text{ with } \operatorname{matches}(x, e, \rho, \kappa, r))$$ -/
def excuseReading (engine row col : String) (r : Reading) : Option String :=
  (exemptions.find? (·.matches engine row col r)).map (·.id)

/-- A reading is `ok` when it passed or is excused.

$$\operatorname{ok}(e, \rho, \kappa, r) \iff r.v = \mathrm{pass} \vee \operatorname{excuse}(e, \rho, \kappa, r) \ne \bot$$ -/
def Reading.ok (r : Reading) (e row col : String) : Bool := r.v == .pass || (excuseReading e row col r).isSome

/-- **A cell is `ok` when every one of its readings is ok** (a cell with no reading is `ok` only in a run narrowed to parts).

$$\operatorname{ok}(e, N, c) \iff \begin{cases} N & c.\mathit{readings} = [\,] \\ \forall r \in c.\mathit{readings},\ \operatorname{ok}(e, c.\mathit{row}, c.\mathit{col}, r) & \text{otherwise} \end{cases}$$

There is no tolerance: one reading that is neither a pass nor excused makes the cell not ok, whatever its other readings say. -/
def TableCell.ok (e : String) (narrowed : Bool) (c : TableCell) : Bool :=
  if c.readings.isEmpty then narrowed else c.readings.all (·.ok e c.row c.col)

/-- The registry excuses neither a pass nor a fail.

$$\forall x \in \mathrm{exemptions},\ x.\mathit{verdict} \ne \mathrm{pass} \wedge x.\mathit{verdict} \ne \mathrm{fail}$$

A failing reading is never excusable; only not-comparable and unreachable readings can be. -/
theorem exemptions_verdict : ∀ x ∈ exemptions, x.verdict ≠ .pass ∧ x.verdict ≠ .fail := by
  decide

/-- A reading with an excuse neither passed nor failed.

$$\operatorname{excuse}(e, \rho, \kappa, r) \ne \bot \implies r.v \ne \mathrm{pass} \wedge r.v \ne \mathrm{fail}$$

Excusing a reading never turns a failure into a pass. -/
theorem excuseReading_not_pass_fail (e row col : String) (r : Reading) (h : (excuseReading e row col r).isSome = true) :
    r.v ≠ .pass ∧ r.v ≠ .fail := by
  unfold excuseReading at h
  cases hf : exemptions.find? (·.matches e row col r) with
  | none => simp [hf] at h
  | some x =>
    have hm := List.find?_some hf
    have hmem := List.mem_of_find?_eq_some hf
    simp only [Exemption.matches, Bool.and_eq_true, beq_iff_eq] at hm
    have hv := exemptions_verdict x hmem
    have hr : r.v = x.verdict := hm.1.1.2
    rw [hr]
    exact hv

/-- An ok reading did not fail.

$$\operatorname{ok}(e, \rho, \kappa, r) \implies r.v \ne \mathrm{fail}$$

A failing reading is never ok. -/
theorem Reading.ok_not_fail (e row col : String) (r : Reading) (h : r.ok e row col = true) : r.v ≠ .fail := by
  simp only [Reading.ok, Bool.or_eq_true, beq_iff_eq] at h
  rcases h with h | h
  · rw [h]; intro e; cases e
  · exact (excuseReading_not_pass_fail e row col r h).2

/-- **A cell is ok exactly when every one of its readings is ok.**

$$\operatorname{ok}(e, N, c) \iff (c.\mathit{readings} = [\,] \wedge N) \vee \bigl(c.\mathit{readings} \ne [\,] \wedge \forall r \in c.\mathit{readings},\ \operatorname{ok}(e, c.\mathit{row}, c.\mathit{col}, r)\bigr)$$

The rollup of a cell passes iff every reading passes or is excused by a registry entry. The old rollup of `Fw.Gate.Rule.rollup` (some
pass and no fail) is no longer what decides: a not-comparable reading next to a pass is not absorbed. -/
theorem rollup_pass_iff_all_readings (e : String) (N : Bool) (c : TableCell) :
    c.ok e N = true ↔
      (c.readings = [] ∧ N = true) ∨ (c.readings ≠ [] ∧ ∀ r ∈ c.readings, r.ok e c.row c.col = true) := by
  unfold TableCell.ok
  by_cases h : c.readings = []
  · simp [h]
  · have : c.readings.isEmpty = false := by simpa [List.isEmpty_iff] using h
    simp [this, h]

/-- An ok cell has no failing reading.

$$\operatorname{ok}(e, N, c) \implies \neg\operatorname{isFail}(c)$$

-/
theorem TableCell.ok_not_fail (e : String) (N : Bool) (c : TableCell) (h : c.ok e N = true) : c.isFail = false := by
  cases hf : c.isFail with
  | false => rfl
  | true =>
    obtain ⟨r, hr, hv⟩ := List.any_eq_true.1 hf
    have hv' : r.v = .fail := by simpa using hv
    rcases (rollup_pass_iff_all_readings e N c).1 h with ⟨hnil, _⟩ | ⟨_, hall⟩
    · rw [hnil] at hr; cases hr
    · exact absurd hv' (Reading.ok_not_fail e c.row c.col r (hall r hr))

/-- A reading that is not ok makes its cell not ok.

$$r \in c.\mathit{readings} \wedge \neg\operatorname{ok}(e, c.\mathit{row}, c.\mathit{col}, r) \implies \neg\operatorname{ok}(e, N, c)$$

-/
theorem TableCell.not_ok_of_reading (e : String) (N : Bool) (c : TableCell) (r : Reading) (hr : r ∈ c.readings)
    (h : r.ok e c.row c.col = false) : c.ok e N = false := by
  cases hk : c.ok e N with
  | false => rfl
  | true =>
    rcases (rollup_pass_iff_all_readings e N c).1 hk with ⟨hnil, _⟩ | ⟨_, hall⟩
    · rw [hnil] at hr; cases hr
    · rw [hall r hr] at h; cases h

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

$$\forall e, N, cs, u,\quad \operatorname{ev}_C(e, N, cs, u) = \mathrm{pass} \iff u = 0 \wedge \bigl(\forall c \in cs,\ \operatorname{ok}(e, N, c)\bigr) \wedge \exists c \in cs,\ \operatorname{isPass}(c)$$

There is no aggregate: a single cell that is neither a pass nor excused keeps the engine from passing, and a cell is ok only when
each of its readings is (`rollup_pass_iff_all_readings`). -/
theorem engine_pass_iff_all_cells (e : String) (N : Bool) (cs : List TableCell) (u : Nat) :
    engineVerdictC e N cs u = .pass ↔
      u = 0 ∧ (∀ c ∈ cs, c.ok e N = true) ∧ ∃ c ∈ cs, c.isPass = true := by
  have hfail : ∀ c ∈ cs, c.ok e N = true → c.isFail = false := fun c _ hok => TableCell.ok_not_fail e N c hok
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

/-- **An engine passes exactly when every reading of every cell is ok, no sample is unsettled, no cell is missing and some reading passed.**

$$\operatorname{ev}_C(e, N, cs, u) = \mathrm{pass} \iff u = 0 \wedge \bigl(\forall c \in cs,\ c.\mathit{readings} = [\,] \implies N\bigr) \wedge \bigl(\forall c \in cs,\ \forall r \in c.\mathit{readings},\ \operatorname{ok}(e, c.\mathit{row}, c.\mathit{col}, r)\bigr) \wedge \exists c \in cs,\ \exists r \in c.\mathit{readings},\ r.v = \mathrm{pass}$$

Each reading is judged on its own: a pass in a cell does not cover a not-comparable, not-run or unfit reading of the same cell. -/
theorem engine_pass_iff_all_readings (e : String) (N : Bool) (cs : List TableCell) (u : Nat) :
    engineVerdictC e N cs u = .pass ↔
      u = 0 ∧ (∀ c ∈ cs, c.readings = [] → N = true) ∧
        (∀ c ∈ cs, ∀ r ∈ c.readings, r.ok e c.row c.col = true) ∧ ∃ c ∈ cs, ∃ r ∈ c.readings, r.v = .pass := by
  rw [engine_pass_iff_all_cells]
  constructor
  · rintro ⟨hu, hall, c, hc, hp⟩
    refine ⟨hu, fun c hc hn => ?_, fun c hc r hr => ?_, ?_⟩
    · rcases (rollup_pass_iff_all_readings e N c).1 (hall c hc) with ⟨_, h⟩ | ⟨h, _⟩
      · exact h
      · exact absurd hn h
    · rcases (rollup_pass_iff_all_readings e N c).1 (hall c hc) with ⟨h, _⟩ | ⟨_, h⟩
      · rw [h] at hr; cases hr
      · exact h r hr
    · obtain ⟨r, hr, hv⟩ := List.any_eq_true.1 hp
      exact ⟨c, hc, r, hr, by simpa using hv⟩
  · rintro ⟨hu, hn, hr, c, hc, r, hrc, hv⟩
    refine ⟨hu, fun c hc => ?_, c, hc, List.any_eq_true.2 ⟨r, hrc, by simp [hv]⟩⟩
    rw [rollup_pass_iff_all_readings]
    by_cases h : c.readings = []
    · exact Or.inl ⟨h, hn c hc h⟩
    · exact Or.inr ⟨h, hr c hc⟩

/-- A cell that is neither a pass nor excused keeps its engine from passing.

$$c \in cs \wedge \neg\operatorname{ok}(e, N, c) \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

Whatever the other cells say. -/
theorem engineVerdictC_ne_pass_of_cell (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (h : c.ok e N = false) : engineVerdictC e N cs u ≠ .pass := by
  intro hp
  have := ((engine_pass_iff_all_cells e N cs u).1 hp).2.1 c hc
  rw [h] at this
  cases this

/-- A reading that is neither a pass nor excused keeps its engine from passing, whatever the other readings of its cell say.

$$c \in cs \wedge r \in c.\mathit{readings} \wedge \neg\operatorname{ok}(e, c.\mathit{row}, c.\mathit{col}, r) \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

A cell with a pass and one unexcused reading is not a pass. -/
theorem engineVerdictC_ne_pass_of_reading (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (r : Reading) (hr : r ∈ c.readings) (h : r.ok e c.row c.col = false) : engineVerdictC e N cs u ≠ .pass :=
  engineVerdictC_ne_pass_of_cell e N cs u c hc (TableCell.not_ok_of_reading e N c r hr h)

/-- A not-comparable reading that no exemption names keeps its engine from passing, even beside passing readings of the same cell.

$$c \in cs \wedge r \in c.\mathit{readings} \wedge r.v = \mathrm{nc} \wedge \operatorname{excuse}(e, c.\mathit{row}, c.\mathit{col}, r) = \bot \implies \operatorname{ev}_C(e, N, cs, u) \ne \mathrm{pass}$$

Not comparable is never a pass. -/
theorem engineVerdictC_nc_ne_pass (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (r : Reading) (hr : r ∈ c.readings) (hv : r.v = .nc) (hx : excuseReading e c.row c.col r = none) :
    engineVerdictC e N cs u ≠ .pass := by
  apply engineVerdictC_ne_pass_of_reading e N cs u c hc r hr
  simp [Reading.ok, hv, hx]

/-- In a run that was not narrowed, a not-run cell keeps its engine from passing.

$$c \in cs \wedge c.\mathit{readings} = [\,] \implies \operatorname{ev}_C(e, \bot, cs, u) \ne \mathrm{pass}$$

A full run has no missing cell. -/
theorem engineVerdictC_notRun_ne_pass (e : String) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (hv : c.readings = []) : engineVerdictC e false cs u ≠ .pass := by
  apply engineVerdictC_ne_pass_of_cell e false cs u c hc
  simp [TableCell.ok, hv]

/-- A failing reading fails its engine.

$$c \in cs \wedge r \in c.\mathit{readings} \wedge r.v = \mathrm{fail} \implies \operatorname{ev}_C(e, N, cs, u) = \mathrm{fail}$$

Unsettled samples do not hide a failure. -/
theorem engineVerdictC_fail (e : String) (N : Bool) (cs : List TableCell) (u : Nat) (c : TableCell)
    (hc : c ∈ cs) (r : Reading) (hr : r ∈ c.readings) (hv : r.v = .fail) : engineVerdictC e N cs u = .fail := by
  unfold engineVerdictC
  have : cs.any TableCell.isFail = true :=
    List.any_eq_true.2 ⟨c, hc, List.any_eq_true.2 ⟨r, hr, by simp [hv]⟩⟩
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

/-- One table cell from its wire form: the row, the column and the readings (reading id, verdict name), each name `pass`, `fail`,
`not-comparable` or `unreachable:<reason>`; no reading at all is a block that was not run.

$$\operatorname{cell}(\rho, \kappa, [(i_k, n_k)]_k) = \begin{cases} \operatorname{ok}\bigl((\rho, \kappa, [(i_k, v(n_k))]_k)\bigr) & \text{every } v(n_k) \text{ known} \\ \operatorname{error}(\texttt{unknown verdict } n_k) & n_k \text{ the first unknown name} \end{cases}$$

An unknown name is an error, never a pass; there is no `not-run` reading name, only the empty list. -/
def tableCellOfWire (row col : String) (readings : List (String × String)) : Except String TableCell := do
  let rs ← readings.mapM fun p => do
    let v ← Fw.Wire.Gate.verdictOf p.2
    return (⟨p.1, v⟩ : Reading)
  return ⟨row, col, rs⟩

/-- The verdict of one engine from the wire form of its cells (row, column, readings) and of its samples' wait outcomes (one pair per
probe or sweep stop).

$$\operatorname{ev}_{WW}(e, N, ns, ws) = \begin{cases} \operatorname{ok}\bigl(\operatorname{ev}_S(e, N, [\operatorname{cell}(\rho, \kappa, rs)]_{(\rho, \kappa, rs) \in ns},\ [(\operatorname{ow}(a), \operatorname{ow}(b))]_{(a, b) \in ws})\bigr) & \text{every name is known} \\ \operatorname{error}(m) & m \text{ the first error: the cells are read first, in order, then the waits} \end{cases}$$

-/
def engineVerdictCW (engine : String) (narrowed : Bool) (cells : List (String × String × List (String × String)))
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
/-- The JSON of one exemption: id, engine, row (`null`: any), column, reading ids (`null`: any), verdict wire name, reason and premise.

$$x \mapsto \{\mathrm{col}, \mathrm{engine}, \mathrm{id}, \mathrm{ids}, \mathrm{kind} = \texttt{exemption}, \mathrm{premise}, \mathrm{reason}, \mathrm{row}, \mathrm{verdict}\}$$ -/
def exemptionLine (x : Exemption) : String :=
  (Json.mkObj [("kind", "exemption"), ("id", x.id), ("engine", x.engine),
    ("row", match x.row with | some r => Json.str r | none => Json.null), ("col", x.col),
    ("ids", match x.ids with | some l => toJson l | none => Json.null),
    ("verdict", Fw.Wire.Gate.verdictName x.verdict), ("reason", x.reason), ("premise", x.premise.toString)]).compress

open Lean in
/-- The JSON of the narrowed-run excuse.

$$\{\mathrm{id} = \texttt{narrowed-run},\ \mathrm{kind} = \texttt{narrowed},\ \mathrm{reason}\}$$ -/
def narrowedLine : String :=
  (Json.mkObj [("kind", "narrowed"), ("id", narrowedId), ("reason", narrowedReason)]).compress

/-- The excuses of a cell, one per excused reading: (excuse id, cell id `row|col`, reading id). A not-run cell of a narrowed run has one,
under `narrowed-run` with an empty reading id.

$$X(e, N, c) = \begin{cases} [(\texttt{narrowed-run}, \rho \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} \kappa, \varepsilon)] & c.\mathit{readings} = [\,] \wedge N \\ [\,] & c.\mathit{readings} = [\,] \wedge \neg N \\ [(\operatorname{excuse}(e, \rho, \kappa, r), \rho \mathbin{+\!\!+} \texttt{"|"} \mathbin{+\!\!+} \kappa, r.\mathit{id}) \mid r \in c.\mathit{readings},\ \operatorname{excuse}(e, \rho, \kappa, r) \ne \bot] & \text{otherwise} \end{cases}$$

-/
def cellExcuses (e : String) (narrowed : Bool) (c : TableCell) : List (List String) :=
  if c.readings.isEmpty then (if narrowed then [[narrowedId, c.row ++ "|" ++ c.col, ""]] else [])
  else c.readings.filterMap fun r => (excuseReading e c.row c.col r).map fun id => [id, c.row ++ "|" ++ c.col, r.id]

open Lean in
/-- One engine case: the engine, whether the run was narrowed, the wire form of its cells (row, column, readings) and of its
samples' waits; the verdict, the unsettled count and the excused readings, or the first error.

$$\operatorname{engineCase}(e, N, ns, ws) = \begin{cases} \{\mathrm{cells} = ns,\ \mathrm{engine} = e,\ \mathrm{exempt} = X,\ \mathrm{kind} = \texttt{engine},\ \mathrm{narrowed} = N,\ \mathrm{unsettled} = \operatorname{u}(ws'),\ \mathrm{verdict} = \operatorname{wire}(v),\ \mathrm{waits} = ws\} & \operatorname{ev}_{WW}(e, N, ns, ws) = \operatorname{ok}(v) \\ \{\mathrm{cells} = ns,\ \mathrm{engine} = e,\ \mathrm{error} = m,\ \mathrm{kind} = \texttt{engine},\ \mathrm{narrowed} = N,\ \mathrm{waits} = ws\} & \operatorname{ev}_{WW}(e, N, ns, ws) = \operatorname{error}(m) \end{cases}$$

Here $X = \bigoplus_{c} X(e, N, c)$ over the cells $c$ read from $ns$, in order.
One compact JSON object with keys in sorted order. -/
def engineCase (engine : String) (narrowed : Bool) (cells : List (String × String × List (String × String)))
    (waits : List (String × String)) : String :=
  let head := [("kind", Json.str "engine"), ("engine", Json.str engine), ("narrowed", toJson narrowed),
    ("cells", Json.arr (cells.map fun c => Json.arr #[Json.str c.1, Json.str c.2.1, toJson (c.2.2.map fun p => [p.1, p.2])]).toArray),
    ("waits", toJson (waits.map fun w => [w.1, w.2]))]
  match engineVerdictCW engine narrowed cells waits with
  | .ok v =>
    let cs := cells.filterMap fun c => (tableCellOfWire c.1 c.2.1 c.2.2).toOption
    let ws := waits.filterMap fun w => match outcomeOfWire w.1, outcomeOfWire w.2 with
      | .ok a, .ok b => some (a, b)
      | _, _ => none
    let ex := cs.flatMap (cellExcuses engine narrowed)
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

/-- A single-reading wire cell from a (row, column, verdict name) triple; the name `not-run` is a cell with no reading. The reading is
called `probe`.

$$\operatorname{cell}_1(\rho, \kappa, n) = \begin{cases} (\rho, \kappa, [\,]) & n = \texttt{not-run} \\ (\rho, \kappa, [(\texttt{probe}, n)]) & \text{otherwise} \end{cases}$$ -/
def cell1 (c : String × String × String) : String × String × List (String × String) :=
  (c.1, c.2.1, if c.2.2 == "not-run" then [] else [("probe", c.2.2)])

/-- One engine case whose cells each have one reading, from (row, column, verdict name) triples; the name `not-run` is a cell with no
reading. The reading is called `probe`.

$$\operatorname{engineCase}_1(e, N, ns, ws) = \operatorname{engineCase}(e, N, [(\rho, \kappa, rs(n))]_{(\rho, \kappa, n) \in ns}, ws),\quad rs(n) = \begin{cases} [\,] & n = \texttt{not-run} \\ [(\texttt{probe}, n)] & \text{otherwise} \end{cases}$$

The single-reading cases of the golden file. -/
def engineCase1 (engine : String) (narrowed : Bool) (cells : List (String × String × String))
    (waits : List (String × String)) : String :=
  engineCase engine narrowed (cells.map cell1) waits

/-- The verdict of the single-reading wire cells, for the `#guard`s below.

$$\operatorname{ev}_1(e, N, ns, ws) = \operatorname{ev}_{WW}(e, N, [rs(n)]_{(\rho, \kappa, n) \in ns}, ws)$$ -/
def verdict1 (engine : String) (narrowed : Bool) (cells : List (String × String × String))
    (waits : List (String × String)) : Option EngineVerdict :=
  (engineVerdictCW engine narrowed (cells.map cell1) waits).toOption

/-- The cells of a sweep from the verdict names of its stops, the stop `i` being the reading `<sweep>#i`.

$$\operatorname{sweepCell}(\rho, s, [n_i]_i) = (\rho, \texttt{sweep:}s, [(s \mathbin{+\!\!+} \texttt{"\#"} \mathbin{+\!\!+} i, n_i)]_i)$$ -/
def sweepCell (row sweep : String) (names : List String) : String × String × List (String × String) :=
  (row, "sweep:" ++ sweep, ((List.range names.length).zip names).map fun p => (s!"{sweep}#{p.1}", p.2))

/-- The Lean row of the tablet sweep from the verdict names of its five stops.

$$\operatorname{touch}([n_i]_i) = \operatorname{sweepCell}(\texttt{matchMedia =Lean}, \texttt{touch-1024-1201}, [n_i]_i)$$ -/
def touchMm (names : List String) : String × String × List (String × String) :=
  sweepCell "matchMedia =Lean" "touch-1024-1201" names

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

The sizes are $|\mathrm{exemptions}| = 3$, $|E| = 33$ engine cases, $|X| = 10$ run cases and $|S| = 8$ hysteresis cases, so the file has
$3 + 1 + 33 + 10 + 8 = 55$ lines in that order. The engine cases cover: every registered exemption and each of its three
conditions broken (other engine, other row, other verdict, other column), a not-comparable or unreachable cell with no
exemption, a not-run cell in a full and in a narrowed run, the order fail over unsettled over incomplete over not-rendered, and the
wait outcomes (plain digits only, a missing wait, an unknown name, the first error). -/
def goldenLines : List String :=
  exemptions.map exemptionLine ++ [narrowedLine] ++
  [ engineCase1 "chromium" false [okCell, ncMm] [("settled@3", "settled@5")],
    engineCase1 "chromium" false [okCell, ("nav.hitTest", "fractional-gaps", "not-comparable")] [],
    engineCase1 "chromium" false [okCell, ("matchMedia =Lean", "desk", "not-comparable")] [],
    engineCase1 "chromium" false [okCell, ("matchMedia =Lean", "fractional-gaps", "unreachable:whole-width")] [],
    engineCase1 "playwright-webkit" false [okCell, ncMm] [],
    engineCase1 "playwright-webkit" false [okCell, crossCell, fracCell, ("matchMedia =Lean", "hover-pointer-cross", "unreachable:primary-pair")] [("settled@0", "settled@0")],
    engineCase1 "playwright-webkit" false [okCell, ("hero.exit", "hover-pointer-cross", "unreachable:whole-width")] [],
    engineCase1 "playwright-webkit" false [okCell, ("hero.exit", "desk", "unreachable:primary-pair")] [],
    engineCase1 "playwright-webkit" false [okCell, ("hero.exit", "hover-pointer-cross", "not-comparable")] [],
    engineCase1 "chromium" false [okCell, crossCell] [],
    engineCase1 "firefox" false [okCell, crossCell] [],
    engineCase1 "playwright-webkit" false [okCell, crossCell, ("platform.stageBg", "sweep:desktop-1512-320-1512", "fail")] [],
    engineCase1 "chromium" false [okCell, ("hero.exit", "desk", "unreachable:width-dpr")] [],
    engineCase1 "chromium" false [okCell, ("morph.panel", "desk", "not-run")] [],
    engineCase1 "chromium" true [okCell, ("morph.panel", "desk", "not-run")] [],
    engineCase1 "chromium" true [okCell, ("morph.panel", "desk", "not-run"), ncMm] [],
    engineCase1 "chromium" true [okCell, ("hero.exit", "desk", "not-comparable")] [],
    engineCase1 "chromium" true [("morph.panel", "desk", "not-run")] [],
    engineCase1 "chromium" false [ncMm] [],
    engineCase1 "chromium" false [] [],
    engineCase1 "chromium" false [okCell, ("hero.exit", "desk", "fail")] [("unsettled", "settled@1")],
    engineCase1 "chromium" false [okCell] [("settled@3", "settled@5"), ("settled@2", "settled@2")],
    engineCase1 "chromium" false [okCell] [("settled@3", "settled@5"), ("settled@2", "unsettled")],
    engineCase1 "chromium" false [okCell] [("unsettled", "settled@1")],
    engineCase1 "chromium" false [okCell, ("hero.exit", "desk", "not-comparable")] [("settled@3", "missing")],
    engineCase1 "chromium" false [okCell] [("settled@3", "late")],
    engineCase1 "chromium" false [okCell] [("settled@007", "settled@0")],
    engineCase1 "chromium" false [okCell] [("settled@1_0", "settled@0")],
    engineCase1 "chromium" false [okCell] [("settled@", "settled@0")],
    engineCase1 "chromium" false [okCell] [("settled@+1", "settled@0")],
    engineCase1 "chromium" false [okCell, ("hero.exit", "desk", "bogus")] [("late", "settled@0")],
    engineCase1 "chromium" false [okCell] [("late", "settled@0"), ("also-late", "settled@0")],
    engineCase1 "chromium" false [("hero.exit", "desk", "not-run")] [],
    engineCase "chromium" false [cell1 okCell, touchMm ["not-comparable", "pass", "not-comparable", "pass", "not-comparable"]] [],
    engineCase "playwright-webkit" false [cell1 okCell, touchMm ["not-comparable", "pass", "not-comparable", "pass", "not-comparable"]] [],
    engineCase "chromium" false [cell1 okCell, touchMm ["not-comparable", "not-comparable", "not-comparable", "pass", "not-comparable"]] [],
    engineCase "chromium" true [cell1 okCell, touchMm ["not-comparable", "pass", "pass", "pass", "not-comparable"]] [],
    engineCase "chromium" false [cell1 okCell, touchMm ["not-comparable", "pass", "fail", "pass", "not-comparable"]] [],
    engineCase "chromium" false [cell1 okCell, sweepCell "hero.exit" "touch-1024-1201" ["not-comparable", "pass", "not-comparable", "pass", "not-comparable"]] [],
    engineCase "chromium" false [cell1 okCell, ("matchMedia =Lean", "sweep:touch-1024-1201", [("other#0", "not-comparable"), ("touch-1024-1201#1", "pass")])] [],
    engineCase "playwright-webkit" false [cell1 okCell, sweepCell "matchMedia =Lean" "phone-rotation" ["pass", "not-comparable", "pass", "not-comparable", "pass"]] [],
    engineCase "chromium" false [cell1 okCell, sweepCell "nav.hitTest" "s" ["pass", "not-comparable"]] [],
    engineCase "chromium" false [cell1 okCell, ("hero.exit", "desk", [("a", "pass"), ("b", "unreachable:primary-pair")])] [],
    engineCase "playwright-webkit" false [cell1 okCell, ("hero.exit", "hover-pointer-cross", [("a", "unreachable:primary-pair"), ("b", "pass")])] [],
    engineCase "chromium" false [("hero.exit", "desk", [("a", "pass"), ("b", "pass")]), sweepCell "nav.hitTest" "s" ["pass", "pass", "pass"]] [("settled@1", "settled@2")],
    engineCase "chromium" false [("hero.exit", "desk", [("a", "fail"), ("b", "pass")])] [("unsettled", "settled@1")],
    engineCase "chromium" false [("hero.exit", "desk", [("a", "pass"), ("b", "bogus")])] [],
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

#guard goldenLines.length == 5 + 1 + 47 + 10 + 8
#guard touch1024Ids == ["touch-1024-1201#0", "touch-1024-1201#2", "touch-1024-1201#4"]
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
#guard verdict1 "chromium" false [okCell, ncMm] [] == some .pass
#guard verdict1 "chromium" false [okCell, ("nav.hitTest", "fractional-gaps", "not-comparable")] [] == some .incomplete
#guard verdict1 "playwright-webkit" false [okCell, crossCell, fracCell] [] == some .pass
#guard verdict1 "playwright-webkit" false [okCell, ("hero.exit", "desk", "unreachable:primary-pair")] [] == some .incomplete
#guard verdict1 "chromium" false [okCell, ("morph.panel", "desk", "not-run")] [] == some .incomplete
#guard verdict1 "chromium" true [okCell, ("morph.panel", "desk", "not-run")] [] == some .pass
#guard verdict1 "chromium" false [okCell, ("hero.exit", "desk", "fail")] [("unsettled", "settled@1")] == some .fail
#guard verdict1 "chromium" false [okCell] [("settled@1_0", "settled@0")] == none
/-- The exact bytes of `packages/contracts/golden/gate/exit.jsonl`: the lines, each newline-terminated.

$$\text{goldenText} = \mathbin{+\!\!+}_{\ell \in \text{goldenLines}} (\ell \mathbin{+\!\!+} \texttt{newline})$$ -/
def goldenText : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- Command-line driver (`lean/scripts/ExitGolden.lean`): print the golden text, or with `--check <file>` exit 0 when the file holds
exactly these bytes and 1 otherwise.

$$\operatorname{run}(\mathit{args}) = 0 \iff \text{no mismatch}$$ -/
def run (args : List String) : IO UInt32 := do
  match Fw.Gate.Settle.argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"exit golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"exit golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

-- a pass beside an unexcused not-comparable reading of the same cell is not a pass (the old rollup said pass)
#guard (engineVerdictCW "chromium" false [cell1 okCell, sweepCell "nav.hitTest" "s" ["pass", "not-comparable"]] []).toOption == some .incomplete
#guard (engineVerdictCW "chromium" false [cell1 okCell, touchMm ["not-comparable", "pass", "not-comparable", "pass", "not-comparable"]] []).toOption == some .pass
#guard (engineVerdictCW "chromium" false [cell1 okCell, touchMm ["not-comparable", "not-comparable", "not-comparable", "pass", "not-comparable"]] []).toOption == some .incomplete
#guard (engineVerdictCW "playwright-webkit" false [cell1 okCell, sweepCell "matchMedia =Lean" "phone-rotation" ["pass", "not-comparable", "pass", "not-comparable", "pass"]] []).toOption == some .incomplete

end Fw.Gate.Exit
