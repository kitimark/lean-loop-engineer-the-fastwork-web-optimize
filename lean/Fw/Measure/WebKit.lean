import Fw.Measure.Tolerance
/-!
# The WebKit lane's reductions (`packages/measure-webkit/src/reduce.mjs`)

The Lean specification of the pure reductions of the WebKit counts lane: Timeline record tallies
(`tally`, with the shoelace paint area `quadArea`), the join of records to scroll steps
(`stepOf`, `reduceSteps`), dense per-zone sums (`zones`), the cell-spread determinism classes
(`classifyCells`), the multiset symmetric difference (`symDiff`) and the worst-class summary
(`summarize`). `flattenRecords`, `markTimes`/`markTime` and `layerKey` are extraction and
formatting and are not specified here (like the Chromium lane's `trace.mjs`).

Numbers: Timeline times and clip coordinates are JSON decimals, read exactly as rationals (the JS
side uses doubles, whose shortest decimal form is what JSON carries, so comparisons agree);
counts are integers. Paint areas are summed exactly and rounded half up (JS: double sum, then
`Math.round`). Tolerances are exact rationals; the JS product `relTol * big` is a double, which
agrees with the exact product for `relTol` ∈ {0.02, 0.05, 0.1} because each of those doubles lies
above its decimal (INFERRED, see `docs/team/handoffs/lean-measure.md`).

Laws proved: every row in the step window lands in exactly one step, so step tallies add up to the
window tally (`steps_partition`, `stepOf_lt`); zone sums add up to the step sums (`zones_partition`,
`zones_steps_total`), the same partition law as the Chromium `zoneSums`; the cell classes are sound
(`classifyCells_det_iff`, `classifyCells_stable`), monotone in the runs when `relTol ≤ 1`
(`cellStatus_snoc`, `classifyCells_snoc`) and deterministic cells are deterministic in the frame
sense of `Fw.Measure.Classes` (`classifyCells_det_holds`); `symDiff` is symmetric and zero on equal
lists.
-/
namespace Fw.Measure.WebKit
open Fw.Measure

/-! ## Record tallies -/

/-- The record types tallied in every vector, in column order (`COUNT_TYPES`).

$$T = [\texttt{RecalculateStyles}, \texttt{Layout}, \texttt{Paint}, \texttt{Composite}, \texttt{RenderingFrame}, \texttt{FireAnimationFrame}, \texttt{TimerFire}, \texttt{ObserverCallback}, \texttt{EventDispatch}, \texttt{FunctionCall}, \texttt{ScheduleStyleRecalculation}, \texttt{InvalidateLayout}]$$
-/
def countTypes : List String :=
  ["RecalculateStyles", "Layout", "Paint", "Composite", "RenderingFrame",
   "FireAnimationFrame", "TimerFire", "ObserverCallback", "EventDispatch", "FunctionCall",
   "ScheduleStyleRecalculation", "InvalidateLayout"]

/-- Record types neither tallied nor reported as "other" (`IGNORED`).

$$I = \{\texttt{TimeStamp}, \texttt{RequestAnimationFrame}, \texttt{CancelAnimationFrame}, \texttt{TimerInstall}, \texttt{TimerRemove}\}$$
-/
def ignored : List String :=
  ["TimeStamp", "RequestAnimationFrame", "CancelAnimationFrame", "TimerInstall", "TimerRemove"]

/-- The absolute value of a rational.

$$|q| = \begin{cases} -q & q < 0 \\ q & q \ge 0 \end{cases}$$
-/
def ratAbs (q : Rat) : Rat := if q < 0 then -q else q

/-- The area of a clip quad (shoelace formula, CSS px²); 0 unless it has at least 8 coordinates.

$$\operatorname{area}(x_1, y_1, \dots, x_4, y_4, \dots) = \tfrac12 \Big|\sum_{i=1}^{4} (x_i\, y_{i+1} - x_{i+1}\, y_i)\Big|,\ \ (x_5, y_5) = (x_1, y_1);\qquad \operatorname{area}(q) = 0 \text{ if } |q| < 8$$
-/
def quadArea : List Rat → Rat
  | x1 :: y1 :: x2 :: y2 :: x3 :: y3 :: x4 :: y4 :: _ =>
    ratAbs (x1 * y2 - x2 * y1 + (x2 * y3 - x3 * y2) + (x3 * y4 - x4 * y3) + (x4 * y1 - x1 * y4)) / 2
  | _ => 0

#guard quadArea [0, 0, 10, 0, 10, 5, 0, 5] == 50
#guard quadArea [1, 2, 3] == 0
#guard quadArea [0, 0, 0, 5, 10, 5, 10, 0] == 50

/-- Round half up to an integer (JS `Math.round`).

$$\operatorname{round}(q) = \lfloor q + \tfrac12 \rfloor$$
-/
def roundHalfUp (q : Rat) : Int := (2 * q.num + q.den) / (2 * (q.den : Int))

#guard roundHalfUp (5 / 2) == 3 && roundHalfUp (-5 / 2) == -2 && roundHalfUp (7 / 3) == 2 && roundHalfUp 4 == 4

/-- One flattened Timeline record: type, start time in seconds (`none` when not a number), and the
clip quad of a Paint record (empty otherwise).

$$\mathrm{Row} = \Sigma^{*} \times (\mathbb{Q} \cup \{\bot\}) \times \mathbb{Q}^{*}$$
-/
structure Row where
  type : String
  start : Option Rat
  clip : List Rat
deriving Repr, DecidableEq

/-- The tally of a list of rows: one count per tallied type, the rounded paint area, and the
counts of the other (not ignored) types.

$$\mathrm{Tally} = \mathbb{N}^{*} \times \mathbb{Z} \times (\Sigma^{*} \times \mathbb{N})^{*}$$

(`tally` fills `counts` with `|T|` entries.)
-/
structure Tally where
  counts : List Nat
  paintArea : Int
  other : List (String × Nat)
deriving Repr, DecidableEq

/-- The number of rows of one type.

$$n_\tau(R) = \big|\{\, i < |R| \mid R_i.\mathrm{type} = \tau \,\}\big|$$
-/
def countType (rows : List Row) (τ : String) : Nat := (rows.filter (·.type == τ)).length

/-- **Tally** (`tally`): counts per tallied type, the paint area rounded half up, and the other
types (sorted by name).

$$\operatorname{tally}(R) = \Big([n_\tau(R)]_{\tau \in T},\ \operatorname{round}\big(\textstyle\sum_{r \in R,\ r.\mathrm{type} = \texttt{Paint}} \operatorname{area}(r.\mathrm{clip})\big),\ [(\tau, n_\tau(R))]_{\tau \in \operatorname{sort}\{r.\mathrm{type}\} \setminus (T \cup I)}\Big)$$
-/
def tally (rows : List Row) : Tally :=
  let area := (rows.filter (·.type == "Paint")).foldr (fun r a => quadArea r.clip + a) 0
  let others := (keysOf (rows.map fun r => [(r.type, (0 : Int))])).filter
    (fun τ => !countTypes.contains τ && !ignored.contains τ)
  { counts := countTypes.map (countType rows), paintArea := roundHalfUp area,
    other := others.map fun τ => (τ, countType rows τ) }

#guard (tally [⟨"Layout", some 0, []⟩, ⟨"Layout", some 0, []⟩, ⟨"Paint", some 0, [0, 0, 4, 0, 4, 4, 0, 4]⟩,
    ⟨"EvaluateScript", some 0, []⟩, ⟨"TimeStamp", some 0, []⟩]) ==
  { counts := [0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], paintArea := 16, other := [("EvaluateScript", 1)] }

/-! ## Steps -/

/-- The step of a start time `s ≥ m₀`: the number of marks at or before `s`, minus one (for
non-decreasing marks this is the last `k` with `m_k ≤ s`, which the JS binary search finds).

$$\operatorname{step}(M, s) = \big|\{\, k < |M| \mid m_k \le s \,\}\big| \mathbin{\dot-} 1 \quad (= 0 \text{ when no } m_k \le s)$$
-/
def stepOf (marks : List Rat) (s : Rat) : Nat := (marks.filter (· ≤ s)).length - 1

/-- Where a row goes: before the first mark (also when its start is not a number), into a step,
or after the end (dropped).

$$\mathrm{Place} = \{\mathrm{before}, \mathrm{after}\} \cup \{\, \mathrm{step}(k) \mid k \in \mathbb{N} \,\}$$
-/
inductive Place where
  | before
  | after
  | step (k : Nat)
deriving Repr, DecidableEq

/-- The place of one row (with `m₀ = 0` for an empty mark list; the wire refuses one).

$$\operatorname{place}(M, e, r) = \begin{cases} \mathrm{before} & r.\mathrm{start} = \bot \ \lor\ r.\mathrm{start} < m_0 \\ \mathrm{after} & m_0 \le r.\mathrm{start} \ \land\ e \le r.\mathrm{start} \\ \mathrm{step}(\operatorname{step}(M, r.\mathrm{start})) & m_0 \le r.\mathrm{start} < e \end{cases},\quad m_0 = \begin{cases} M_0 & M \ne [\,] \\ 0 & M = [\,] \end{cases}$$
-/
def place (marks : List Rat) (endTime : Rat) (r : Row) : Place :=
  match r.start with
  | none => .before
  | some s => if s < marks.headD 0 then .before else if endTime ≤ s then .after else .step (stepOf marks s)

/-- The rows in the step window (start a number, `m₀ ≤ start < e`).

$$W(R) = [\, r \in R \mid r.\mathrm{start} \ne \bot,\ m_0 \le r.\mathrm{start} < e \,]$$
-/
def window (marks : List Rat) (endTime : Rat) (rows : List Row) : List Row :=
  rows.filter fun r => match place marks endTime r with | .step _ => true | _ => false

/-- The rows of step `k`.

$$R_k = [\, r \in R \mid \operatorname{place}(M, e, r) = \mathrm{step}(k) \,]$$
-/
def stepRows (marks : List Rat) (endTime : Rat) (rows : List Row) (k : Nat) : List Row :=
  rows.filter fun r => place marks endTime r == .step k

/-- The result of `reduceSteps`: per-step count rows (columns `countTypes`), per-step paint areas,
the window tally and the number of rows before the first step.

$$\mathrm{Reduced} = (\mathbb{N}^{*})^{*} \times \mathbb{Z}^{*} \times \mathrm{Tally} \times \mathbb{N}$$

(`reduceSteps` fills `n = |M|` rows of `|T|` counts.)
-/
structure Reduced where
  perStep : List (List Nat)
  perStepPaintArea : List Int
  total : Tally
  rowsBeforeFirstStep : Nat
deriving Repr, DecidableEq

/-- **Per-step reduction** (`reduceSteps`) with `n = |M|` steps.

$$\big|[\, r \in R \mid \operatorname{place}(M, e, r) = \mathrm{before} \,]\big|$$
-/
def reduceSteps (rows : List Row) (marks : List Rat) (endTime : Rat) : Reduced :=
  let per := (List.range marks.length).map fun k => tally (stepRows marks endTime rows k)
  { perStep := per.map (·.counts), perStepPaintArea := per.map (·.paintArea),
    total := tally (window marks endTime rows),
    rowsBeforeFirstStep := (rows.filter (place marks endTime · == .before)).length }

-- the seed vectors of test/reduce.test.mjs
private def seedRows : List Row :=
  [⟨"Layout", some (1 / 2), []⟩, ⟨"Layout", some 1, []⟩, ⟨"Layout", some (19 / 10), []⟩, ⟨"Paint", some 2, []⟩,
   ⟨"Layout", some (7 / 2), []⟩, ⟨"Layout", some 4, []⟩]
#guard (List.range 3).map (fun k => (stepRows [1, 2, 3] 4 seedRows k).length) == [2, 1, 1]
#guard (reduceSteps seedRows [1, 2, 3] 4).rowsBeforeFirstStep == 1
#guard ((reduceSteps [⟨"RecalculateStyles", some 1, []⟩, ⟨"Layout", some (5 / 2), []⟩, ⟨"Layout", some (7 / 2), []⟩,
    ⟨"Paint", some (18 / 5), [0, 0, 1, 0, 1, 1, 0, 1]⟩] [1, 2, 3] 4).perStepPaintArea) == [0, 0, 1]

/-- Every start time has a step below the number of marks (when there is a mark).

$$\forall M, s:\ |M| \ge 1 \;\Rightarrow\; \operatorname{step}(M, s) < |M|$$
-/
theorem stepOf_lt (marks : List Rat) (s : Rat) (h : marks ≠ []) : stepOf marks s < marks.length := by
  have := List.length_filter_le (· ≤ s) marks
  have : 0 < marks.length := List.length_pos_iff.mpr h
  simp only [stepOf]; omega

/-- A row in the window lands in some step below `|M|`.

$$\forall M, e, r, k:\ M \ne [\,] \land \operatorname{place}(M, e, r) = \mathrm{step}(k) \;\Rightarrow\; k < |M|$$
-/
theorem place_step_lt {marks : List Rat} {endTime : Rat} {r : Row} {k : Nat} (h : marks ≠ [])
    (hp : place marks endTime r = .step k) : k < marks.length := by
  simp only [place] at hp
  split at hp
  · cases hp
  · split at hp
    · cases hp
    · split at hp
      · cases hp
      · cases hp; exact stepOf_lt marks _ h

/-- Generic partition: summing over the distinct keys `0 … n-1` of the rows with each key is
summing over all rows, when every row's key is below `n`.

$$\forall \kappa : \alpha \to \mathbb{N},\ g : \alpha \to \mathbb{Z},\ n \in \mathbb{N},\ R \in \alpha^{*}:\ (\forall r \in R:\ \kappa(r) < n) \;\Rightarrow\; \sum_{z < n} \sum_{r \in R,\ \kappa(r) = z} g(r) = \sum_{r \in R} g(r)$$
-/
theorem sum_partition_range {α : Type} (key : α → Nat) (g : α → Int) : ∀ (n : Nat) (rs : List α),
    (∀ r ∈ rs, key r < n) →
    sumBy (fun z => sumBy g (rs.filter (key · == z))) (List.range n) = sumBy g rs
  | 0, [], _ => rfl
  | 0, r :: _, h => absurd (h r (by simp)) (Nat.not_lt_zero _)
  | n + 1, rs, h => by
    rw [List.range_succ, sumBy_append]
    have hsplit : ∀ rs' : List α, (∀ r ∈ rs', key r < n + 1) →
        sumBy g rs' = sumBy g (rs'.filter (key · < n)) + sumBy g (rs'.filter (key · == n)) := by
      intro rs' hrs
      induction rs' with
      | nil => rfl
      | cons r rs ih =>
        have ih' := ih (fun x hx => hrs x (by simp [hx]))
        have hr := hrs r (by simp)
        simp only [List.filter_cons]
        by_cases h1 : key r < n
        · have : (key r == n) = false := by simp; omega
          simp [h1, this, sumBy, ih']; omega
        · have h2 : key r = n := by omega
          simp [h2, sumBy, ih']; omega
    have ih := sum_partition_range key g n (rs.filter (key · < n)) (by
      intro r hr; simpa using (List.mem_filter.mp hr).2)
    have hcongr : ∀ z ∈ List.range n, sumBy g (rs.filter (key · == z)) =
        sumBy g ((rs.filter (key · < n)).filter (key · == z)) := by
      intro z hz
      have hz' : z < n := List.mem_range.mp hz
      congr 1; rw [List.filter_filter]; apply List.filter_congr
      intro r _; by_cases e : key r = z
      · subst e; simp [hz']
      · simp [e]
    rw [sumBy_congr hcongr, ih, hsplit rs h]
    simp [sumBy]

/-- **Step partition.** For each tallied type, the per-step counts add up to the window tally's
count: every row in the window lands in exactly one step.

$$\forall R, M, e, \tau:\ M \ne [\,] \;\Rightarrow\; \sum_{k < |M|} n_\tau(R_k) = n_\tau(W(R))$$
-/
theorem steps_partition (rows : List Row) (marks : List Rat) (endTime : Rat) (τ : String)
    (h : marks ≠ []) :
    sumBy (fun k => (countType (stepRows marks endTime rows k) τ : Int)) (List.range marks.length) =
      countType (window marks endTime rows) τ := by
  let W := (window marks endTime rows).filter (·.type == τ)
  let key : Row → Nat := fun r => match place marks endTime r with | .step k => k | _ => 0
  have hW : ∀ r ∈ W, key r < marks.length := by
    intro r hr
    simp only [W, window, List.mem_filter] at hr
    obtain ⟨⟨_, hp⟩, _⟩ := hr
    simp only [key]
    split
    · rename_i k hk; exact place_step_lt h hk
    · rename_i hne; split at hp <;> simp_all
  have := sum_partition_range key (fun _ => 1) marks.length W hW
  rw [sumBy_one] at this
  have e : (countType (window marks endTime rows) τ : Int) = W.length := rfl
  rw [e, ← this]
  apply sumBy_congr
  intro k _
  rw [sumBy_one]
  simp only [countType, stepRows, W, window, List.filter_filter]
  congr 2
  apply List.filter_congr
  intro r _
  simp only [key]
  generalize place marks endTime r = p
  cases p
  case step k' =>
    by_cases e : k' = k
    · simp [e, Bool.and_comm]
    · have e1 : (Place.step k' == Place.step k) = false := beq_false_of_ne (by intro h; cases h; exact e rfl)
      have e2 : (k' == k) = false := beq_false_of_ne e
      simp [e1, e2]
  all_goals simp

/-- **Rows are conserved.** Every row is before the first step, in exactly one step, or after the
end.

$$\forall R, M, e:\ M \ne [\,] \Rightarrow |R| = \big|[r \in R \mid \operatorname{place}(M,e,r) = \mathrm{before}]\big| + \sum_{k < |M|} |R_k| + \big|[r \in R \mid \operatorname{place}(M,e,r) = \mathrm{after}]\big|$$
-/
theorem rows_conserved (rows : List Row) (marks : List Rat) (endTime : Rat) (h : marks ≠ []) :
    (rows.length : Int) = (rows.filter (place marks endTime · == .before)).length +
      sumBy (fun k => ((stepRows marks endTime rows k).length : Int)) (List.range marks.length) +
      (rows.filter (place marks endTime · == .after)).length := by
  let key : Row → Nat := fun r => match place marks endTime r with | .step k => k | _ => 0
  have hW : ∀ r ∈ window marks endTime rows, key r < marks.length := by
    intro r hr
    simp only [window, List.mem_filter] at hr
    simp only [key]
    split
    · rename_i k hk; exact place_step_lt h hk
    · rename_i hne; obtain ⟨_, hp⟩ := hr; split at hp <;> simp_all
  have hp := sum_partition_range key (fun _ => 1) marks.length _ hW
  rw [sumBy_one] at hp
  have hc : ∀ k ∈ List.range marks.length, ((stepRows marks endTime rows k).length : Int) =
      sumBy (fun _ => (1 : Int)) ((window marks endTime rows).filter (key · == k)) := by
    intro k _
    rw [sumBy_one]; simp only [stepRows, window, List.filter_filter]
    congr 2; apply List.filter_congr; intro r _
    simp only [key]
    generalize place marks endTime r = p
    cases p
    case step k' =>
      by_cases e : k' = k
      · simp [e]
      · have e1 : (Place.step k' == Place.step k) = false := beq_false_of_ne (by intro h; cases h; exact e rfl)
        have e2 : (k' == k) = false := beq_false_of_ne e
        simp [e1, e2]
    all_goals simp
  rw [sumBy_congr hc, hp]
  simp only [window]
  clear hc hp hW
  induction rows with
  | nil => rfl
  | cons r rs ih =>
    simp only [List.filter_cons, List.length_cons]
    cases place marks endTime r <;> simp <;> omega

/-! ## Zones -/

/-- One dense zone: index, start offset, number of steps, column sums and paint area.

$$\mathrm{WZone} = \mathbb{N} \times \mathbb{N} \times \mathbb{N} \times \mathbb{Z}^{*} \times \mathbb{Z}$$

(`zones_{h,w}` fills `counts` with `w` entries.)
-/
structure WZone where
  zone : Nat
  y0 : Nat
  steps : Nat
  counts : List Int
  paintArea : Int
deriving Repr, DecidableEq

/-- One scroll step: its scroll offset, its count row and its paint area.

$$\mathrm{Step} = \mathbb{Q} \times \mathbb{Z}^{*} \times \mathbb{Z}$$
-/
structure Step where
  y : Rat
  row : List Int
  area : Int
deriving Repr, DecidableEq

/-- The zone index of a scroll offset, `⌊y / h⌋` (a natural number for `y ≥ 0`; the wire refuses
negative offsets, on which JS throws).

$$\operatorname{zix}_h(y) = \max\big(0, \lfloor y / h \rfloor\big)\quad (y / 0 = 0)$$
-/
def zoneIx (h : Nat) (y : Rat) : Nat := (Rat.floor (y / (h : Rat))).toNat

/-- The steps of zone `z`.

$$S_z = [\, s \in S \mid \operatorname{zix}_h(s.y) = z \,]$$
-/
def zoneSteps (h : Nat) (steps : List Step) (z : Nat) : List Step := steps.filter (zoneIx h ·.y == z)

/-- The number of zones: one more than the largest zone index (0 for no steps).

$$N_h(S) = \begin{cases} 0 & S = [\,] \\ 1 + \max_{s \in S} \operatorname{zix}_h(s.y) & \text{else} \end{cases}$$
-/
def zoneCount (h : Nat) (steps : List Step) : Nat :=
  if steps.isEmpty then 0 else maxOf (steps.map (zoneIx h ·.y)) + 1

/-- The record of zone `z`.

$$\operatorname{zrec}_{h,w}(S, z) = \big(z,\ z h,\ |S_z|,\ [\textstyle\sum_{s \in S_z} s.\mathrm{row}[j]]_{j < w},\ \sum_{s \in S_z} s.\mathrm{area}\big)$$
-/
def zoneRec (h w : Nat) (steps : List Step) (z : Nat) : WZone :=
  let sz := zoneSteps h steps z
  { zone := z, y0 := z * h, steps := sz.length,
    counts := (List.range w).map fun j => sumBy (fun s => valAt s.row j) sz,
    paintArea := sumBy (·.area) sz }

/-- **Dense zones** (`zones`) of width-`w` count rows: zones `0 … max index`, each with the steps
whose offset falls in it (empty zones included).

$$\operatorname{zones}_{h,w}(S) = [\operatorname{zrec}_{h,w}(S, z)]_{z < N_h(S)}$$
-/
def zones (h w : Nat) (steps : List Step) : List WZone :=
  (List.range (zoneCount h steps)).map (zoneRec h w steps)

#guard (zones 500 2 [⟨0, [1, 0], 0⟩, ⟨400, [0, 0], 0⟩, ⟨800, [0, 1], 1⟩]).map (fun z => (z.steps, z.counts, z.paintArea)) ==
  [(2, [1, 0], 0), (1, [0, 1], 1)]
#guard (zones 500 1 [⟨1200, [3], 2⟩]).map (·.steps) == [0, 0, 1]
#guard zones 500 12 [] == []

/-- Every step's zone is below the number of zones.

$$\forall h \in \mathbb{N},\ S,\ s \in S:\ \operatorname{zix}_h(s.y) < N_h(S)$$
-/
theorem zoneIx_lt (h : Nat) (steps : List Step) : ∀ s ∈ steps, zoneIx h s.y < zoneCount h steps := by
  intro s hs
  have hne : steps.isEmpty = false := by cases steps <;> simp_all
  have := le_maxOf (List.mem_map_of_mem (f := fun s : Step => zoneIx h s.y) hs)
  simp only [zoneCount, hne]; simp; omega

/-- **Zone partition.** For every column `j < w`, the zone sums add up to the sum over all steps;
the same law as the Chromium `zones_sum_total`.

$$\forall h, w, S, j < w:\ \sum_{z \in \operatorname{zones}_{h,w}(S)} z.\mathrm{counts}[j] = \sum_{s \in S} s.\mathrm{row}[j]$$
-/
theorem zones_partition (h w : Nat) (steps : List Step) (j : Nat) (hj : j < w) :
    sumBy (fun z => valAt z.counts j) (zones h w steps) = sumBy (fun s => valAt s.row j) steps := by
  simp only [zones, sumBy_map]
  have hc : ∀ z ∈ List.range (zoneCount h steps),
      ((fun z : WZone => valAt z.counts j) ∘ zoneRec h w steps) z =
        sumBy (fun s => valAt s.row j) (steps.filter (zoneIx h ·.y == z)) := by
    intro z _
    simp only [Function.comp, valAt, zoneRec]
    rw [List.getD_eq_getElem?_getD, List.getElem?_map, List.getElem?_range hj]
    rfl
  rw [sumBy_congr hc]
  exact sum_partition_range (fun s => zoneIx h s.y) _ _ steps (zoneIx_lt h steps)

/-- **Step count partition.** The zones' step counts add up to the number of steps.

$$\forall h, w, S:\ \sum_{z \in \operatorname{zones}_{h,w}(S)} z.\mathrm{steps} = |S|$$
-/
theorem zones_steps_total (h w : Nat) (steps : List Step) :
    sumBy (fun z => (z.steps : Int)) (zones h w steps) = steps.length := by
  simp only [zones, sumBy_map]
  have hc : ∀ z ∈ List.range (zoneCount h steps),
      ((fun z : WZone => (z.steps : Int)) ∘ zoneRec h w steps) z =
        sumBy (fun _ => (1 : Int)) (steps.filter (zoneIx h ·.y == z)) := by
    intro z _; simp [zoneRec, zoneSteps, sumBy_one]
  rw [sumBy_congr hc, sum_partition_range (fun s => zoneIx h s.y) _ _ steps (zoneIx_lt h steps), sumBy_one]

/-- **Zone additivity.** Zone `z`'s column sum over a concatenation of step lists is the sum of the
two parts' (zones beyond a part's last zone count as 0).

$$\forall h, z, j, A, B:\ \sum_{s \in (A \mathbin{+\!\!+} B)_z} s.\mathrm{row}[j] = \sum_{s \in A_z} s.\mathrm{row}[j] + \sum_{s \in B_z} s.\mathrm{row}[j]$$
-/
theorem zoneSteps_append (h z j : Nat) (a b : List Step) :
    sumBy (fun s => valAt s.row j) (zoneSteps h (a ++ b) z) =
      sumBy (fun s => valAt s.row j) (zoneSteps h a z) + sumBy (fun s => valAt s.row j) (zoneSteps h b z) := by
  simp [zoneSteps, List.filter_append, sumBy_append]

/-! ## Cell-spread classes -/

/-- Tolerances of one aggregation level: a cell may spread by `max(absTol, relTol · max|v|)`.

$$\mathrm{Tol} = (a, r) \in \mathbb{Q}^2$$
-/
structure Tol where
  absTol : Rat
  relTol : Rat
deriving Repr, DecidableEq

/-- Integer absolute value.

$$|x| \in \mathbb{Z}$$
-/
def absI (x : Int) : Int := if x < 0 then -x else x

/-- The running (lo, hi, big) of a cell's values: minimum, maximum, largest absolute value.

$$\operatorname{st}(\ell, h, b; v) = (\min(\ell, v),\ \max(h, v),\ \max(b, |v|))$$
-/
def stStep (st : Int × Int × Int) (v : Int) : Int × Int × Int := (min st.1 v, max st.2.1 v, max st.2.2 (absI v))

/-- The (lo, hi, big) of a non-empty list of values ((0, 0, 0) for none).

$$\operatorname{stats}(v_1, \dots, v_m) = \begin{cases} (0, 0, 0) & m = 0 \\ (\min_i v_i,\ \max_i v_i,\ \max_i |v_i|) & m \ge 1 \end{cases}$$
-/
def stats : List Int → Int × Int × Int
  | [] => (0, 0, 0)
  | v :: vs => vs.foldl stStep (v, v, absI v)

/-- A cell's status: 0 identical in every run, 1 spread within tolerance, 2 beyond (with
`a = p_a/q_a`, `r = p_r/q_r` in lowest terms, the comparisons are exact).

$$\operatorname{status}(v) = \begin{cases} 0 & s = 0 \\ 2 & s > a \ \land\ s > r\,b \\ 1 & \text{otherwise} \end{cases},\quad (\ell, h, b) = \operatorname{stats}(v),\ s = h - \ell$$
-/
def cellStatus (tol : Tol) (vs : List Int) : Nat :=
  let st := stats vs
  let s := st.2.1 - st.1
  if s = 0 then 0
  else if s * tol.absTol.den > tol.absTol.num ∧ s * tol.relTol.den > tol.relTol.num * st.2.2 then 2 else 1

/-- The values of cell `i` over the runs.

$$\operatorname{cell}_i(R) = [r[i]]_{r \in R}$$
-/
def cellVals (runs : List Series) (i : Nat) : List Int := runs.map (valAt · i)

/-- The cell-spread class (`classify(runs, tol)`): quarantined when the runs' lengths differ,
else the worst cell status (0 deterministic, 1 stable, 2 quarantined). The wire refuses fewer
than two runs, as JS does.

$$\operatorname{classifyCells}(R, \mathrm{tol}) = \begin{cases} 2 & \exists r \in R:\ |r| \ne |R_1| \\ \max{}^{*}_{i < |R_1|} \operatorname{status}(\operatorname{cell}_i(R)) & \text{otherwise} \end{cases},\quad R_1 = [\,] \text{ if } R = [\,]$$
-/
def classifyCells (tol : Tol) (runs : List Series) : Nat :=
  let len := (runs.headD []).length
  if runs.any (·.length != len) then 2
  else maxOf ((List.range len).map fun i => cellStatus tol (cellVals runs i))

#guard classifyCells ⟨1, 0⟩ [[1, 2, 3], [1, 2, 3]] == 0
#guard classifyCells ⟨1, 0⟩ [[1, 2, 3], [1, 3, 3]] == 1
#guard classifyCells ⟨1, 0⟩ [[1, 2, 3], [1, 5, 3]] == 2
#guard classifyCells ⟨2, 1 / 20⟩ [[100], [104]] == 1
#guard classifyCells ⟨2, 1 / 20⟩ [[100], [110]] == 2
#guard classifyCells ⟨1, 0⟩ [[1, 2], [1]] == 2
#guard classifyCells ⟨0, 0⟩ [[0], [1]] == 2
#guard classifyCells ⟨1, 0⟩ [[1], [1], [2]] == 1

/-- The (lo, hi, big) invariant: lo ≤ hi, hi ≤ big and −lo ≤ big.

$$\operatorname{Inv}(\ell, h, b) \iff \ell \le h \ \land\ h \le b \ \land\ -\ell \le b$$
-/
def Inv (st : Int × Int × Int) : Prop := st.1 ≤ st.2.1 ∧ st.2.1 ≤ st.2.2 ∧ -st.1 ≤ st.2.2

/-- One step keeps the invariant.

$$\forall \sigma \in \mathbb{Z}^3,\ v \in \mathbb{Z}:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\operatorname{st}(\sigma; v))$$
-/
theorem inv_step {st : Int × Int × Int} (v : Int) (h : Inv st) : Inv (stStep st v) := by
  obtain ⟨l, hi, b⟩ := st
  simp only [Inv, stStep, absI] at h ⊢
  split <;> omega

/-- Folding `st` over any list from a start that satisfies the invariant keeps the invariant.

$$\forall V \in \mathbb{Z}^{*},\ \sigma \in \mathbb{Z}^3:\ \operatorname{Inv}(\sigma) \Rightarrow \operatorname{Inv}(\operatorname{foldl}(\operatorname{st}, \sigma, V))$$
-/
theorem inv_foldl : ∀ (vs : List Int) (st : Int × Int × Int), Inv st → Inv (vs.foldl stStep st)
  | [], _, h => h
  | v :: vs, _, h => inv_foldl vs _ (inv_step v h)

/-- The stats of any list satisfy the invariant (`stats [] = (0, 0, 0)`).

$$\forall V \in \mathbb{Z}^{*}:\ \operatorname{Inv}(\operatorname{stats}(V))$$
-/
theorem inv_stats : ∀ vs : List Int, Inv (stats vs)
  | [] => by simp [stats, Inv]
  | v :: vs => inv_foldl vs _ (by simp only [Inv, absI]; split <;> omega)

/-- Appending a value is one more step.

$$\forall V \in \mathbb{Z}^{*},\ x \in \mathbb{Z}:\ V \ne [\,] \Rightarrow \operatorname{stats}(V \mathbin{+\!\!+} [x]) = \operatorname{st}(\operatorname{stats}(V); x)$$
-/
theorem stats_snoc : ∀ (vs : List Int) (x : Int), vs ≠ [] → stats (vs ++ [x]) = stStep (stats vs) x
  | [], _, h => absurd rfl h
  | v :: vs, x, _ => by simp [stats, List.foldl_append]

/-- **Spread grows at least as fast as the largest magnitude.** Adding a value raises the spread
by at least as much as it raises `big`, and never lowers either.

$$\forall (\ell, h, b) \in \mathbb{Z}^3,\ x \in \mathbb{Z}:\ \operatorname{Inv}(\ell, h, b) \land (\ell', h', b') = \operatorname{st}(\ell, h, b; x) \Rightarrow 0 \le b' - b \le (h' - \ell') - (h - \ell)$$
-/
theorem spread_step (st : Int × Int × Int) (x : Int) (h : Inv st) :
    0 ≤ (stStep st x).2.2 - st.2.2 ∧
      (stStep st x).2.2 - st.2.2 ≤ ((stStep st x).2.1 - (stStep st x).1) - (st.2.1 - st.1) := by
  obtain ⟨l, hi, b⟩ := st
  simp only [Inv, stStep, absI] at h ⊢
  split <;> omega

/-- **A cell's status never decreases when a run is added**, provided `relTol ≤ 1` (true for every
lane tolerance: 0, 0.02, 0.05, 0.1).

$$\forall \mathrm{tol} = (a, r),\ V \in \mathbb{Z}^{*},\ x \in \mathbb{Z}:\ r \le 1 \land V \ne [\,] \Rightarrow \operatorname{status}_{\mathrm{tol}}(V) \le \operatorname{status}_{\mathrm{tol}}(V \mathbin{+\!\!+} [x])$$
-/
theorem cellStatus_snoc (tol : Tol) (hr1 : tol.relTol.num ≤ tol.relTol.den)
    (vs : List Int) (x : Int) (hne : vs ≠ []) : cellStatus tol vs ≤ cellStatus tol (vs ++ [x]) := by
  have hinv := inv_stats vs
  obtain ⟨d1, d2⟩ := spread_step (stats vs) x hinv
  simp only [cellStatus, stats_snoc vs x hne]
  generalize stats vs = st at hinv d1 d2
  obtain ⟨l, hi, b⟩ := st
  generalize hs' : stStep (l, hi, b) x = st' at d1 d2
  obtain ⟨l', hi', b'⟩ := st'
  simp only [Inv] at hinv d1 d2 ⊢
  have hq : (0 : Int) < tol.relTol.den := by have := tol.relTol.den_pos; omega
  have hqa : (0 : Int) < tol.absTol.den := by have := tol.absTol.den_pos; omega
  have m1 : (b' - b) * tol.relTol.num ≤ (b' - b) * tol.relTol.den :=
    Int.mul_le_mul_of_nonneg_left hr1 d1
  have m2 : (b' - b) * (tol.relTol.den : Int) ≤ ((hi' - l') - (hi - l)) * tol.relTol.den :=
    Int.mul_le_mul_of_nonneg_right d2 (by omega)
  have m3 : (0 : Int) ≤ ((hi' - l') - (hi - l)) * tol.absTol.den :=
    Int.mul_nonneg (by omega) (by omega)
  have e1 : (hi' - l') * (tol.relTol.den : Int) = (hi - l) * tol.relTol.den + ((hi' - l') - (hi - l)) * tol.relTol.den := by
    rw [← Int.add_mul]; congr 1; omega
  have e2 : tol.relTol.num * b' = tol.relTol.num * b + (b' - b) * tol.relTol.num := by
    rw [Int.mul_comm (b' - b), ← Int.mul_add]; congr 1; omega
  have e3 : (hi' - l') * (tol.absTol.den : Int) = (hi - l) * tol.absTol.den + ((hi' - l') - (hi - l)) * tol.absTol.den := by
    rw [← Int.add_mul]; congr 1; omega
  by_cases s0 : hi - l = 0
  · simp only [s0, ite_true]; exact Nat.zero_le _
  · have s0' : ¬ hi' - l' = 0 := by omega
    simp only [s0, s0', ite_false]
    by_cases hb : (hi - l) * tol.absTol.den > tol.absTol.num ∧ (hi - l) * tol.relTol.den > tol.relTol.num * b
    · have hb' : (hi' - l') * tol.absTol.den > tol.absTol.num ∧ (hi' - l') * tol.relTol.den > tol.relTol.num * b' := by
        constructor <;> omega
      simp [hb, hb']
    · simp only [hb, ite_false]; split <;> omega

/-- The maximum of pointwise larger values is larger.

$$\forall f, g : \alpha \to \mathbb{N},\ L \in \alpha^{*}:\ (\forall x \in L:\ f(x) \le g(x)) \Rightarrow \max{}^{*} f(L) \le \max{}^{*} g(L)$$
-/
theorem maxOf_map_le {α : Type} {f g : α → Nat} : ∀ {l : List α}, (∀ x ∈ l, f x ≤ g x) →
    maxOf (l.map f) ≤ maxOf (l.map g)
  | [], _ => Nat.le_refl _
  | x :: xs, h => by
    simp only [List.map_cons, maxOf, List.foldr_cons]
    have := maxOf_map_le (l := xs) (fun y hy => h y (by simp [hy]))
    simp only [maxOf] at this
    have := h x (by simp)
    omega

/-- **The cell class is monotone in the runs.** Adding a run never makes the class stricter, when
`relTol ≤ 1` and there is at least one run.

$$\forall \mathrm{tol} = (a, r),\ R \in (\mathbb{Z}^{*})^{*},\ x \in \mathbb{Z}^{*}:\ r \le 1 \land R \ne [\,] \Rightarrow \operatorname{classifyCells}(R, \mathrm{tol}) \le \operatorname{classifyCells}(R \mathbin{+\!\!+} [x], \mathrm{tol})$$
-/
theorem classifyCells_snoc (tol : Tol) (hr1 : tol.relTol.num ≤ tol.relTol.den)
    (runs : List Series) (x : Series) (hne : runs ≠ []) :
    classifyCells tol runs ≤ classifyCells tol (runs ++ [x]) := by
  have hhead : (runs ++ [x]).headD [] = runs.headD [] := by cases runs <;> simp_all
  have hbound : ∀ runs' : List Series, classifyCells tol runs' ≤ 2 := by
    intro runs'
    simp only [classifyCells]
    split
    · exact Nat.le_refl _
    · apply maxOf_le; intro v hv
      simp only [List.mem_map] at hv
      obtain ⟨i, _, rfl⟩ := hv
      simp only [cellStatus]; split
      · omega
      · split <;> omega
  simp only [classifyCells, hhead]
  by_cases h1 : runs.any (·.length != (runs.headD []).length)
  · have h2 : (runs ++ [x]).any (·.length != (runs.headD []).length) := by simp_all
    simp only [h1, h2, ite_true]; exact Nat.le_refl _
  · have h1' : (runs.any (·.length != (runs.headD []).length)) = false := by simpa using h1
    simp only [h1', Bool.false_eq_true, ite_false]
    split
    · have := hbound runs
      simp only [classifyCells, h1', Bool.false_eq_true, ite_false] at this; exact this
    · apply maxOf_map_le
      intro i _
      simp only [cellVals, List.map_append, List.map_cons, List.map_nil]
      exact cellStatus_snoc tol hr1 _ _ (by simp [hne])

/-- A list whose stats have zero spread is constant.

$$\forall V \in \mathbb{Z}^{*}:\ (\ell, h, b) = \operatorname{stats}(V) \land h - \ell = 0 \Rightarrow \forall u, v \in V:\ u = v$$
-/
theorem const_of_spread_zero (vs : List Int) (h : (stats vs).2.1 - (stats vs).1 = 0) :
    ∀ u ∈ vs, ∀ v ∈ vs, u = v := by
  -- every value lies between lo and hi
  have bounds : ∀ (ws : List Int) (st : Int × Int × Int), (∀ w ∈ ws, st.1 ≤ w ∧ w ≤ st.2.1) →
      ∀ (us : List Int), ∀ w ∈ ws ++ us, (us.foldl stStep st).1 ≤ w ∧ w ≤ (us.foldl stStep st).2.1 := by
    intro ws st hst us
    induction us generalizing ws st with
    | nil => simpa using hst
    | cons u us ih =>
      intro w hw
      have := ih (ws ++ [u]) (stStep st u) (by
        intro w' hw'
        simp only [List.mem_append, List.mem_singleton] at hw'
        simp only [stStep]
        rcases hw' with hw' | hw'
        · have := hst w' hw'; omega
        · subst hw'; omega) w (by simp_all)
      simpa using this
  cases vs with
  | nil => simp
  | cons v0 vs =>
    have hb := bounds [v0] (v0, v0, absI v0) (by simp) vs
    intro u hu w hw
    have h1 := hb u (by simpa using hu)
    have h2 := hb w (by simpa using hw)
    simp only [stats] at h
    omega

/-- **Deterministic cells are deterministic runs.** If the cell class is deterministic then every
pair of runs is identical frame by frame, so the runs are `deterministic` in the sense of
`Fw.Measure.Classes` (and enter the screen frame by frame).

$$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathrm{tol}) = 0 \Rightarrow \operatorname{Holds}(\mathrm{det}, R)$$
-/
theorem classifyCells_det_holds (tol : Tol) (runs : List Series) (h : classifyCells tol runs = 0) :
    Holds .deterministic runs := by
  simp only [classifyCells] at h
  split at h
  · cases h
  · rename_i hlen
    simp only [Bool.not_eq_true, List.any_eq_false, bne_iff_ne, ne_eq, Classical.not_not] at hlen
    intro a ha b hb
    simp only [Within]
    rw [diffFrames_zero_iff]
    intro i
    by_cases hi : i < (runs.headD []).length
    · have hs : cellStatus tol (cellVals runs i) = 0 := by
        have := le_maxOf (List.mem_map_of_mem (f := fun i => cellStatus tol (cellVals runs i)) (List.mem_range.mpr hi))
        omega
      simp only [cellStatus] at hs
      split at hs
      · rename_i hz
        exact const_of_spread_zero _ hz _ (List.mem_map_of_mem ha) _ (List.mem_map_of_mem hb)
      · split at hs <;> cases hs
    · have la := hlen a ha; have lb := hlen b hb
      simp only [valAt, List.getD_eq_getElem?_getD]
      rw [List.getElem?_eq_none (by omega), List.getElem?_eq_none (by omega)]

/-- **Stable cells: the frame-sense bounds.** Whatever the cell class, every pair of runs is
within stable(k, t) for the observed maxima `k(R)`, `t(R)` of `Fw.Measure.Classes`, so the margin
theorems of `Fw.Measure.Tolerance` apply to WebKit types too.

$$\forall R:\ \operatorname{Holds}(\mathrm{stable}(k(R), t(R)), R)$$
-/
theorem classifyCells_stable (runs : List Series) : Holds (.stable (kObs runs) (tObs runs)) runs :=
  fun _ ha _ hb => le_obs ha hb

/-- `classifyCells` is 0 exactly when the runs have equal lengths and every cell is identical.

$$\forall \mathrm{tol},\ R:\ \operatorname{classifyCells}(R, \mathrm{tol}) = 0 \iff (\forall r \in R:\ |r| = |R_1|) \land \forall i < |R_1|:\ \operatorname{status}(\operatorname{cell}_i(R)) = 0,\quad R_1 = [\,] \text{ if } R = [\,]$$
-/
theorem classifyCells_det_iff (tol : Tol) (runs : List Series) :
    classifyCells tol runs = 0 ↔ (∀ r ∈ runs, r.length = (runs.headD []).length) ∧
      ∀ i < (runs.headD []).length, cellStatus tol (cellVals runs i) = 0 := by
  simp only [classifyCells]
  split
  · rename_i h
    simp only [List.any_eq_true, bne_iff_ne, ne_eq] at h
    obtain ⟨r, hr, hne⟩ := h
    simp only [Nat.succ_ne_zero, false_iff, not_and]
    intro hall; exact absurd (hall r hr) hne
  · rename_i h
    simp only [Bool.not_eq_true, List.any_eq_false, bne_iff_ne, ne_eq, Classical.not_not] at h
    constructor
    · intro hm
      refine ⟨h, fun i hi => ?_⟩
      have := le_maxOf (List.mem_map_of_mem (f := fun i => cellStatus tol (cellVals runs i)) (List.mem_range.mpr hi))
      omega
    · intro ⟨_, hz⟩
      have := maxOf_le (l := (List.range (runs.headD []).length).map fun i => cellStatus tol (cellVals runs i)) (m := 0)
        (by intro v hv; simp only [List.mem_map, List.mem_range] at hv; obtain ⟨i, hi, rfl⟩ := hv; exact Nat.le_of_eq (hz i hi))
      omega

/-! ## Multiset symmetric difference -/

/-- The number of occurrences of a string.

$$\#_x(A) = |\{\, i \mid A_i = x \,\}|$$
-/
def occ (a : List String) (x : String) : Nat := (a.filter (· == x)).length

/-- **Multiset symmetric difference** (`symDiff`).

$$\operatorname{symDiff}(A, B) = \sum_{x \in \operatorname{set}(A \mathbin{+\!\!+} B)} \big|\#_x(A) - \#_x(B)\big|$$
-/
def symDiff (a b : List String) : Nat :=
  ((keysOf ((a ++ b).map fun x => [(x, (0 : Int))])).map fun x => ((occ a x : Int) - occ b x).natAbs).foldr (· + ·) 0

#guard symDiff ["a", "b"] ["b", "a"] == 0
#guard symDiff ["a", "a", "b"] ["a", "c"] == 3

/-- The keys of singleton count lists are the keys inserted one by one.

$$\forall m,\ x_1, \dots, x_m \in \Sigma^{*}:\ \operatorname{keys}([[(x_1, 0)], \dots, [(x_m, 0)]]) = \operatorname{ins}(x_1, \operatorname{ins}(x_2, \dots \operatorname{ins}(x_m, [\,])))$$
-/
theorem keysOf_singletons (l : List String) :
    keysOf (l.map fun x => [(x, (0 : Int))]) = l.foldr (fun x acc => insKey x acc) [] := by
  induction l with
  | nil => rfl
  | cons x xs ih => simp [keysOf, ih]

/-- A list has no symmetric difference with itself.

$$\forall A:\ \operatorname{symDiff}(A, A) = 0$$
-/
theorem symDiff_self (a : List String) : symDiff a a = 0 := by
  simp only [symDiff, Int.sub_self, Int.natAbs_zero]
  generalize keysOf _ = ks
  induction ks with
  | nil => rfl
  | cons _ _ ih => simpa using ih

/-- **Symmetry** of the multiset symmetric difference, as a sum over any key list.

$$\forall A, B, K \in (\Sigma^{*})^{*}:\ \sum_{x \in K} |\#_x(A) - \#_x(B)| = \sum_{x \in K} |\#_x(B) - \#_x(A)|$$

(`symDiff A B = symDiff B A` itself is not proved here, since `keys (A ++ B) = keys (B ++ A)` is not shown.)
-/
theorem symDiff_terms_comm (a b : List String) (ks : List String) :
    (ks.map fun x => ((occ a x : Int) - occ b x).natAbs).foldr (· + ·) 0 =
      (ks.map fun x => ((occ b x : Int) - occ a x).natAbs).foldr (· + ·) 0 := by
  induction ks with
  | nil => rfl
  | cons x xs ih => simp only [List.map_cons, List.foldr_cons, ih]; omega

/-! ## Summary: the worst class per (family, metric) -/

/-- One classification row: family, metric, aggregation level and class (0 deterministic,
1 stable, 2 quarantined).

$$\mathrm{CRow} = \Sigma^{*} \times \Sigma^{*} \times \Sigma^{*} \times \mathbb{N}$$

(The classes used are 0, 1, 2.)
-/
structure CRow where
  family : String
  metric : String
  level : String
  cls : Nat
deriving Repr, DecidableEq

/-- One summary entry: family, metric, the class per level (the last row of each level wins),
and the worst of those.

$$\mathrm{Sum} = \Sigma^{*} \times \Sigma^{*} \times (\Sigma^{*} \times \mathbb{N})^{*} \times \mathbb{N}$$
-/
structure Summary where
  family : String
  metric : String
  levels : List (String × Nat)
  worst : Nat
deriving Repr, DecidableEq

/-- The class of the last row with a given level.

$$\operatorname{last}_\lambda(R) = \text{the class of the last } r \in R \text{ with } r.\mathrm{level} = \lambda \ (0 \text{ if none})$$
-/
def lastCls (rows : List CRow) (lv : String) : Nat :=
  ((rows.filter (·.level == lv)).getLast?.map (·.cls)).getD 0

/-- **Summary** (`summarize`): group rows by the key `family|metric` in order of first appearance;
per group the levels with their last class (sorted by level) and the worst of them.

$$\operatorname{summarize}(R) = \Big[\big(R_g[0].f,\ R_g[0].m,\ [(\lambda, \operatorname{last}_\lambda(R_g))]_{\lambda \in \operatorname{sort}\{r.\mathrm{level} \mid r \in R_g\}},\ \max{}^{*}_\lambda \operatorname{last}_\lambda(R_g)\big)\Big]_{g \in \operatorname{firstSeen}([\kappa(r)]_{r \in R})},\ \kappa(r) = r.f \cdot \texttt{"|"} \cdot r.m,\ R_g = [r \in R \mid \kappa(r) = g]$$
-/
def summarize (rows : List CRow) : List Summary :=
  let key := fun (r : CRow) => r.family ++ "|" ++ r.metric
  (firstSeen (rows.map key)).map fun g =>
    let rg := rows.filter (key · == g)
    let first := rg.headD ⟨"", "", "", 0⟩
    let lvs := keysOf (rg.map fun r => [(r.level, (0 : Int))])
    let levels := lvs.map fun lv => (lv, lastCls rg lv)
    { family := first.family, metric := first.metric, levels, worst := maxOf (levels.map (·.2)) }

#guard summarize [⟨"s", "Layout", "total", 1⟩, ⟨"s", "Layout", "zone", 2⟩, ⟨"c", "n", "x", 0⟩, ⟨"s", "Layout", "zone", 0⟩] ==
  [⟨"s", "Layout", [("total", 1), ("zone", 0)], 1⟩, ⟨"c", "n", [("x", 0)], 0⟩]

/-- **The worst class bounds every level.** In each summary entry, every level's class is at most
the entry's worst class.

$$\forall R,\ e \in \operatorname{summarize}(R),\ (\lambda, c) \in e.\mathrm{levels}:\ c \le e.\mathrm{worst}$$
-/
theorem summarize_worst (rows : List CRow) :
    ∀ e ∈ summarize rows, ∀ p ∈ e.levels, p.2 ≤ e.worst := by
  intro e he p hp
  simp only [summarize, List.mem_map] at he
  obtain ⟨g, _, rfl⟩ := he
  exact le_maxOf (List.mem_map_of_mem hp)

end Fw.Measure.WebKit
