import Fw.Measure.Classes
/-!
# The WKTR fixture lane: layout of the passes, the premise that gates parallelism, the assertions (task `wktr-fixture-speed`)

The lane `.github/workflows/wktr-fixtures.yml` runs 13 **cells** (a fixture page, a number of frames per scroll step and a
harness variant), each `passes` times in a fresh WebKitTestRunner process of the iOS Simulator. Done one process after
another that is 39 launches per job. This module decides three things and proves what it can.

* **Layout.** A cell may run beside other cells only when the *premise* held for its variant: the count classes measured
  with `k` processes at once equal the classes measured one at a time. The layout has one **phase** per variant (the
  phases run one after the other, so no two variants ever share the VM), and a phase deals the cells of its variant over
  `width` lanes (one Simulator device and one driver process each). The width is the largest `k` up to the request
  (never above 3: the CI VM has 3 cores) whose premise is in the table `held`; `k = 1` is always allowed.
* **The theorem** (`layout_classes_eq`): if the table is sound for the oracle (every `held v k` is a measured fact: all
  count types of all cells of `v` have the same class at width `k` as at width 1), then each cell of the layout has the
  class it would have had in the serial run. The layout is a partition of the cells (`phaseOf_perm`: every cell exactly
  once). The production layout of a variant is the same list of lanes as the layout the premise test measured
  (`layout_phase_eq`), so the premise is a statement about the layout that runs.
* **Job parallelism** (`maxParallel`): the account has 5 macOS slots shared by every macOS lane; this lane takes what the
  other lanes (`webkit-sim` at most 2, `gate-gaps` 1) leave, and never more than its jobs (`maxParallel_not_blocking`).
* **Assertions** (`Expect.ok`): the measured classes of the fixtures (`wktr-p1p4`), decided here and replayed in
  `packages/measure-wktr/fixtures/premise.mjs` against `packages/contracts/golden/measure/wktr.fixtures.jsonl`.

Lean specifies and proves; the cells' counts are CI measurements (`held` is filled from them, never guessed).
-/
namespace Fw.Measure.WktrLayout
open Fw.Measure

/-! ## Cells -/

/-- The harness variants the fixture lane runs: real-time `live`, and `live-trace` (the same plus event counters).

$$\mathrm{Variant} = \{\mathrm{live}, \mathrm{liveTrace}\}$$
-/
inductive Variant where
  | live | liveTrace
deriving Repr, DecidableEq, Inhabited

/-- The variant's name in file names (`counts-<name>-<pass>.json`).

$$\operatorname{name}(\mathrm{live}) = \texttt{live}, \quad \operatorname{name}(\mathrm{liveTrace}) = \texttt{live-trace}$$
-/
def Variant.name : Variant → String
  | .live => "live"
  | .liveTrace => "live-trace"

/-- One unit of work: a fixture page, the frames sampled per scroll step, the variant.

$$\mathrm{Cell} = \mathrm{Fixture} \times \mathbb{N} \times \mathrm{Variant}$$
-/
structure Cell where
  fixture : String
  frames : Nat
  variant : Variant
deriving Repr, DecidableEq, Inhabited

/-- The 13 cells of the lane (the order of `run.sh` before this task): every fixture at one frame in both variants, and the
three animation fixtures at three frames in `live`.

$$|\mathrm{cells}| = 5 \cdot 2 + 3 = 13$$
-/
def cells : List Cell :=
  ["control", "scroll-timeline", "scroll-js-transform", "scroll-js-bg", "time-accel"].flatMap
      (fun f => [⟨f, 1, .live⟩, ⟨f, 1, .liveTrace⟩]) ++
    ["control", "scroll-timeline", "time-accel"].map (fun f => ⟨f, 3, .live⟩)

/-- The cells of one variant, in lane order.

$$\operatorname{cellsOf}(v) = [\, c \in \mathrm{cells} \mid c.\mathrm{variant} = v \,]$$
-/
def cellsOf (v : Variant) : List Cell := cells.filter (fun c => c.variant == v)

#guard cells.length == 13 && (cellsOf .live).length == 8 && (cellsOf .liveTrace).length == 5

/-! ## Dealing the cells of a phase over lanes -/

/-- The cells of lane `i` of `k`: the cells at positions $\equiv i \pmod k$.

$$\operatorname{lane}_k^i(cs) = [\, c_j \mid j \bmod k = i \,]$$
-/
def lane (k i : Nat) (cs : List Cell) : List Cell :=
  (cs.zipIdx.filter (fun p => p.2 % k == i)).map Prod.fst

/-- All lanes of a phase of width `k`.

$$\operatorname{deal}_k(cs) = [\operatorname{lane}_k^0(cs), \dots, \operatorname{lane}_k^{k-1}(cs)]$$
-/
def deal (k : Nat) (cs : List Cell) : List (List Cell) := (List.range k).map (lane k · cs)

/-- The largest width a phase may have: the CI VM has 3 cores.

$$k_{\max} = 3$$
-/
def maxK : Nat := 3

/-- **Dealing is a partition.** For every width the layout may use and either variant, the lanes together hold each cell of
the variant exactly once (a permutation of `cellsOf v`).

$$\forall v,\ \forall k \in \{1,2,3\}:\ \biguplus_{i<k} \operatorname{lane}_k^i(\operatorname{cellsOf}(v)) = \operatorname{cellsOf}(v) \ \text{(as multisets)}$$

Proved by exhaustion over the two variants and the three widths. -/
theorem deal_perm : ∀ v ∈ [Variant.live, Variant.liveTrace], ∀ k ∈ [1, 2, 3],
    ((deal k (cellsOf v)).flatten).Perm (cellsOf v) := by
  decide

/-! ## The premise table and the width -/

/-- The premise table: `held v k` is true when the lane measured, on CI, that the count classes of every cell of variant `v`
with `k` processes at once equal the classes one at a time. `k = 1` needs no measurement. Filled from CI runs only
(`docs/team/handoffs/wktr-fixture-speed.md`).

$$\mathrm{Held} = \mathrm{Variant} \to \mathbb{N} \to \mathrm{Bool}$$
-/
abbrev Held := Variant → Nat → Bool

/-- The table with the entries of CI runs. `none` yet means serial for all: the conservative default. -/
def heldTable : Held := fun _ k => k == 1

/-- The table of a premise test: every width is requested, whether or not the premise has been shown.

$$\mathrm{probe}(v, k) = \mathrm{true}$$
-/
def probeTable : Held := fun _ _ => true

/-- The largest `j \le n` (and `\ge 1`) with `held v j`; 1 when none.

$$\operatorname{pick}(v, 0) = 1, \quad \operatorname{pick}(v, n+1) = \begin{cases} n+1 & \mathrm{held}(v, n+1) \\ \operatorname{pick}(v, n) & \text{otherwise} \end{cases}$$
-/
def pick (held : Held) (v : Variant) : Nat → Nat
  | 0 => 1
  | n + 1 => if held v (n + 1) then n + 1 else pick held v n

/-- The width of the phase of variant `v` for a request of `req` processes.

$$\operatorname{width}(v, \mathit{req}) = \operatorname{pick}(v, \min(\mathit{req}, k_{\max}))$$
-/
def width (held : Held) (req : Nat) (v : Variant) : Nat := pick held v (min req maxK)

/-- `k = 1` is always allowed; any other width needs the table.

$$\operatorname{ok}(v, k) \iff k = 1 \lor \mathrm{held}(v, k)$$
-/
def okAt (held : Held) (v : Variant) (k : Nat) : Bool := k == 1 || held v k

/-- The width is at least 1 and at most the request (when the request is at least 1) and at most 3.

$$1 \le \operatorname{width}(v, r) \le \max(1, \min(r, 3))$$
-/
theorem width_bounds (held : Held) (req : Nat) (v : Variant) :
    1 ≤ width held req v ∧ width held req v ≤ max 1 (min req maxK) := by
  unfold width
  generalize min req maxK = n
  induction n with
  | zero => simp [pick]
  | succ n ih =>
    simp only [pick]
    split
    · omega
    · omega

/-- **The width respects the table**: it is 1 or a width whose premise is in the table.

$$\mathrm{held}(v, \operatorname{width}(v, r)) \lor \operatorname{width}(v, r) = 1$$
-/
theorem width_ok (held : Held) (req : Nat) (v : Variant) : okAt held v (width held req v) = true := by
  unfold width
  generalize min req maxK = n
  induction n with
  | zero => simp [pick, okAt]
  | succ n ih =>
    simp only [pick]
    split
    · next h => simp [okAt, h]
    · exact ih

/-! ## The layout -/

/-- One phase: the lanes of one variant.

$$\mathrm{Phase} = \mathrm{Variant} \times \mathrm{List}(\mathrm{List}(\mathrm{Cell}))$$
-/
structure Phase where
  variant : Variant
  lanes : List (List Cell)
deriving Repr, DecidableEq

/-- The phase of variant `v` at width `k`.

$$\operatorname{phaseOf}(v, k) = (v, \operatorname{deal}_k(\operatorname{cellsOf}(v)))$$
-/
def phaseOf (v : Variant) (k : Nat) : Phase := ⟨v, deal k (cellsOf v)⟩

/-- **The layout**: one phase per variant, each at its width.

$$\mathrm{layout}(\mathit{held}, r) = [\operatorname{phaseOf}(\mathrm{live}, w_{\mathrm{live}}), \operatorname{phaseOf}(\mathrm{liveTrace}, w_{\mathrm{liveTrace}})], \quad w_v = \operatorname{width}(v, r)$$
-/
def layout (held : Held) (req : Nat) : List Phase :=
  [Variant.live, Variant.liveTrace].map fun v => phaseOf v (width held req v)

/-- **The layout that runs is the layout that was measured.** The phase of `v` in the production layout is the phase the
premise test ran at that width: it depends on `v` and the width only.

$$\mathrm{layout}(\mathit{held}, r)[v] = \operatorname{phaseOf}(v, \operatorname{width}(v, r))$$
-/
theorem layout_phase_eq (held : Held) (req : Nat) (v : Variant) :
    (layout held req).find? (fun p => p.variant == v) = some (phaseOf v (width held req v)) := by
  cases v <;> simp [layout, phaseOf, List.find?]

/-- **The layout runs every cell once.** Whatever the table and the request, the cells of all lanes of all phases are the
13 cells, each once.

$$\biguplus_{\text{phase}}\ \biguplus_{\text{lane}} \text{lane} = \mathrm{cells} \ \text{(as multisets)}$$
-/
theorem layout_perm (held : Held) (req : Nat) :
    (((layout held req).flatMap (fun p => p.lanes.flatten))).Perm cells := by
  have hw : ∀ v, width held req v ∈ [1, 2, 3] := by
    intro v
    obtain ⟨h1, h2⟩ := width_bounds held req v
    have : width held req v ≤ 3 := by simp [maxK] at h2; omega
    simp only [List.mem_cons, List.not_mem_nil, or_false]
    omega
  have hl := deal_perm Variant.live (by simp) _ (hw .live)
  have ht := deal_perm Variant.liveTrace (by simp) _ (hw .liveTrace)
  simp only [layout, phaseOf, List.map, List.flatMap_cons, List.flatMap_nil, List.append_nil]
  have hc : cells.Perm (cellsOf .live ++ cellsOf .liveTrace) := by decide
  exact (hl.append ht).trans hc.symm

/-! ## The oracle and the theorem -/

/-- A count type, such as `styleRecalcs`.

$$\mathrm{CountType} = \mathrm{String}$$
-/
abbrev CountType := String

/-- The measurement oracle: the series (one per pass) of count type `t` for cell `c` when its phase ran at width `k`. CI fills
it; here it is abstract.

$$\mathrm{Oracle} = \mathrm{Cell} \to \mathbb{N} \to \mathrm{CountType} \to \mathrm{List}(\mathrm{Series})$$
-/
abbrev Oracle := Cell → Nat → CountType → List Series

/-- The kind of a class: deterministic, stable (within the policy, whatever its observed `k` and `t`) or quarantined. The observed
`k` and `t` of a stable class are maxima over the passes at hand; the kind is the policy's verdict.

$$\mathrm{Kind} = \{\mathrm{det}, \mathrm{stable}, \mathrm{quar}\}$$
-/
inductive Kind where
  | det | stable | quar
deriving Repr, DecidableEq

/-- The kind of a class.

$$\operatorname{kind}(\mathrm{det}) = \mathrm{det}, \quad \operatorname{kind}(\mathrm{stable}(k, t)) = \mathrm{stable}, \quad \operatorname{kind}(\mathrm{quar}) = \mathrm{quar}$$
-/
def _root_.Fw.Measure.Class.kind : Class → Kind
  | .deterministic => .det
  | .stable _ _ => .stable
  | .quarantined => .quar

/-- **The premise** for variant `v` at width `k`: every count type of every cell of `v` has the kind of class at width `k` that it
has at width 1.

$$\operatorname{Preserved}(v, k) \iff \forall c,\ c.\mathrm{variant} = v \Rightarrow \forall t:\ \operatorname{kind}(\operatorname{classify}_p(o(c, k, t))) = \operatorname{kind}(\operatorname{classify}_p(o(c, 1, t)))$$
-/
def Preserved (p : Policy) (o : Oracle) (v : Variant) (k : Nat) : Prop :=
  ∀ c : Cell, c.variant = v → ∀ t : CountType, (classify p (o c k t)).kind = (classify p (o c 1 t)).kind

/-- The table is **sound** for the oracle: every entry it claims is a measured fact.

$$\operatorname{Sound}(\mathit{held}) \iff \forall v, k:\ \mathrm{held}(v, k) \Rightarrow \operatorname{Preserved}(v, k)$$
-/
def Sound (p : Policy) (o : Oracle) (held : Held) : Prop :=
  ∀ v k, held v k = true → Preserved p o v k

/-- **Parallel classes equal serial classes.** If the table is sound, every cell of every phase of the layout has, for every
count type, the kind of class it has when run alone. (The width of a phase is `lanes.length` = `width`.)

$$\operatorname{Sound}(\mathit{held}) \Rightarrow \forall c \in \mathrm{layout}(\mathit{held}, r),\ \forall t:\ \operatorname{kind}(\operatorname{classify}_p(o(c, w, t))) = \operatorname{kind}(\operatorname{classify}_p(o(c, 1, t)))$$
$$\text{where } w = \operatorname{width}(c.\mathrm{variant}, r)$$
-/
theorem layout_classes_eq (p : Policy) (o : Oracle) (held : Held) (req : Nat) (hs : Sound p o held) :
    ∀ c : Cell, c ∈ (layout held req).flatMap (fun ph => ph.lanes.flatten) →
      ∀ t : CountType, (classify p (o c (width held req c.variant) t)).kind = (classify p (o c 1 t)).kind := by
  intro c hc t
  have hok := width_ok held req c.variant
  simp only [okAt, Bool.or_eq_true, beq_iff_eq] at hok
  rcases hok with h1 | hh
  · rw [h1]
  · exact hs _ _ hh c rfl t

/-- **Measured premise.** The classes of the cells' count types at width `k` equal those at width 1: same count types, same kind of
class. This is what the premise test computes from the classes of two sets of passes.

$$\operatorname{eq}(A, B) \iff \forall (t, c) \in A:\ \operatorname{kind}(B[t]) = \operatorname{kind}(c) \ \land\ \forall (t, c) \in B:\ \operatorname{kind}(A[t]) = \operatorname{kind}(c)$$
-/
def classesEqual (a b : List (CountType × Class)) : Bool :=
  a.all (fun (t, c) => (b.lookup t).map Class.kind == some c.kind) &&
    b.all (fun (t, c) => (a.lookup t).map Class.kind == some c.kind)

/-- Equal classes is symmetric: the serial run and the parallel run play the same role.

$$\operatorname{eq}(A, B) = \operatorname{eq}(B, A)$$
-/
theorem classesEqual_comm (a b : List (CountType × Class)) : classesEqual a b = classesEqual b a := by
  unfold classesEqual
  exact Bool.and_comm _ _

#guard classesEqual [("a", .deterministic), ("b", .stable 1 2)] [("b", .stable 3 9), ("a", .deterministic)]
#guard !classesEqual [("a", .deterministic)] [("a", .stable 1 0)]
#guard !classesEqual [("a", .deterministic)] [("a", .deterministic), ("b", .deterministic)]

/-! ## Job parallelism on the macOS slots -/

/-- The macOS jobs the account may run at once (GitHub's limit for the free plan).

$$S = 5$$
-/
def macSlots : Nat := 5

/-- The slots other lanes may hold at once while this lane runs: `webkit-sim` (`max-parallel: 2`) and `gate-gaps`
(`collect-macos`, one VM). The WKTR lane `wktr.yml` is not counted: it is manual and shares this lane's slot (one WKTR lane at
a time).

$$\mathrm{others} = [2, 1]$$
-/
def otherLanes : List Nat := [2, 1]

/-- The `max-parallel` of the fixture job: the free slots, at least 1, at most the number of jobs.

$$\operatorname{maxParallel}(S, O, n) = \max(1, \min(n, S - \textstyle\sum O))$$
-/
def maxParallel (total : Nat) (others : List Nat) (jobs : Nat) : Nat := max 1 (min jobs (total - others.sum))

/-- **Not blocking**: when the other lanes leave at least one slot, the fixture jobs and the other lanes together never ask
for more than the account has, so `webkit-sim`'s two jobs always find their slots.

$$\textstyle\sum O < S \ \Rightarrow\ \operatorname{maxParallel}(S, O, n) + \sum O \le S$$
-/
theorem maxParallel_not_blocking (total : Nat) (others : List Nat) (jobs : Nat) (h : others.sum < total) :
    maxParallel total others jobs + others.sum ≤ total := by
  unfold maxParallel
  omega

/-- With the lanes of this account the fixture job runs two at a time.

$$\operatorname{maxParallel}(5, [2,1], 3) = 2$$
-/
theorem maxParallel_here : maxParallel macSlots otherLanes 3 = 2 := by decide

/-! ## What the lane asserts -/

/-- One assertion: the class kind of count type `type` in arm `fixture-f<frames>` and the band of its rate per rendering update,
in thousandths: $\mathit{lo} \le 1000 \cdot \Sigma\text{type} / \Sigma\text{renderingUpdates} \le \mathit{hi}$.

$$\mathrm{Expect} = \mathrm{Fixture} \times \mathbb{N} \times \mathrm{Variant} \times \mathrm{CountType} \times \mathrm{Kind} \times \mathbb{N} \times \mathbb{N}$$
-/
structure Expect where
  fixture : String
  frames : Nat
  variant : Variant
  type : CountType
  kind : Kind
  lo : Nat
  hi : Nat
deriving Repr

/-- The assertion holds for one pass-pooled observation: the class kind matches and every pass is in the band. `sums` lists
`(Σ type, Σ renderingUpdates)` per pass.

$$\operatorname{ok}(e, \kappa, S) \iff \kappa = e.\mathrm{kind} \ \land\ \forall (a, u) \in S:\ e.\mathrm{lo}\cdot u \le 1000\,a \ \land\ 1000\,a \le e.\mathrm{hi}\cdot u$$
-/
def Expect.ok (e : Expect) (kind : Kind) (sums : List (Nat × Nat)) : Bool :=
  kind == e.kind && sums.all fun (a, u) => e.lo * u ≤ 1000 * a && 1000 * a ≤ e.hi * u

/-- A deterministic exact rate of `r` thousandths.

$$\operatorname{exact}(r) = (r, r)$$
-/
def exactRate (fixture : String) (frames : Nat) (v : Variant) (t : CountType) (r : Nat) : Expect :=
  ⟨fixture, frames, v, t, .det, r, r⟩

/-- The measured classes of the fixtures (run 39075991405, three jobs by three passes, kMax 4, tMax 24): scrolling alone costs no
style recalc; the scroll-timeline animation costs one per update; the document-timeline one none (its animation does run:
`ev_animActive` is one per update). The two JS-driven arms restyle in a changing share of the updates (0.74 to 0.93), a class
`quarantined`, band one half to one.

$$\mu_{\mathrm{control}} = 0, \quad \mu_{\mathrm{timeline}} = 1, \quad \mu_{\mathrm{timeAccel}} = 0, \quad \mu_{\mathrm{js}} \in [\tfrac12, 1] \text{ (quarantined)}$$
-/
def expects : List Expect :=
  [1, 3].flatMap (fun fr =>
    [ exactRate "control" fr .live "styleRecalcs" 0, exactRate "scroll-timeline" fr .live "styleRecalcs" 1000,
      exactRate "time-accel" fr .live "styleRecalcs" 0 ]) ++
  [ exactRate "control" 1 .liveTrace "styleRecalcs" 0, exactRate "scroll-timeline" 1 .liveTrace "styleRecalcs" 1000,
    exactRate "time-accel" 1 .liveTrace "styleRecalcs" 0,
    exactRate "control" 1 .liveTrace "ev_animActive" 0, exactRate "time-accel" 1 .liveTrace "ev_animActive" 1000,
    { fixture := "scroll-js-transform", frames := 1, variant := .live, type := "styleRecalcs", kind := .quar, lo := 500, hi := 1000 },
    { fixture := "scroll-js-transform", frames := 1, variant := .liveTrace, type := "styleRecalcs", kind := .quar, lo := 500, hi := 1000 },
    { fixture := "scroll-js-bg", frames := 1, variant := .live, type := "styleRecalcs", kind := .quar, lo := 500, hi := 1000 },
    { fixture := "scroll-js-bg", frames := 1, variant := .liveTrace, type := "styleRecalcs", kind := .quar, lo := 500, hi := 1000 } ]

#guard expects.length == 15
#guard (exactRate "x" 1 .live "styleRecalcs" 1000).ok .det [(53, 53), (159, 159)]
#guard !(exactRate "x" 1 .live "styleRecalcs" 1000).ok .det [(53, 53), (158, 159)]
#guard !(exactRate "x" 1 .live "styleRecalcs" 0).ok .det [(1, 53)]
#guard !(exactRate "x" 1 .live "styleRecalcs" 0).ok .quar [(0, 53)]

end Fw.Measure.WktrLayout
