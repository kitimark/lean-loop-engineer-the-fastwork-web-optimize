import Lean.Data.Json
import Fw.Engine
import Fw.Parts.EndFlags
/-!
# hero.accent boil, variant `steps`: E per sample on the 60 Hz grid, and work per engine

**The part.** While the accent idles (`is-idle`, 2200 ms the first time, 1250 ms later; `2.DyWL8TcE.js` byte
~137916, the accent cycle), three inline `<svg class="accent-svg is-idle-frame is-idle-frame-j">` boxes ($j = 0, 1, 2$)
"boil": each runs `.6s step-end infinite` on its own keyframes (`2.gBuqKVzi.css:1`, bytes 20091-20357 and
21067-21239), restated:

* frame 0: `0%, 33.32% {opacity: 1}  33.33%, to {opacity: 0}`
* frame 1: `0%, 33.32% {opacity: 0}  33.33%, 66.65% {opacity: 1}  66.66%, to {opacity: 0}`
* frame 2: `0%, 66.65% {opacity: 0}  66.66%, to {opacity: 1}`

`step-end` is the per-keyframe easing (`B/core/animation/css/css_animations.cc:425,459-463`@f842f52); it is
`steps(1, end)`, $\lfloor t \rfloor$ on the interval's local progress (`ui/gfx/animation/keyframe/timing_function.cc:98-113`@f842f52),
and the interval is the one with $p \in [\mathit{from}, \mathit{to})$ (`B/core/animation/interpolation_effect.cc:27-41`).
So the value at iteration progress $p$ is the value of the last keyframe with offset $\le p$ (`stepEnd`). CONFIRMED.

**The variant `steps`.** Per frame box, a chain of zero-duration, `fill: forwards` animations with delays, one per
plateau boundary of every cycle (`chain`, `bounds`): a later animation in the list overrides an earlier one, so the
box shows the value of the last step whose delay has passed (`chainVal`). A zero-duration animation is never in its
active phase: Chromium services it at its delay and then never again (`B/core/animation/keyframe_effect.cc:848-857`),
WebKit ticks it at its delay (`AnimationEffect.cpp:385-402`@862f17d). No script. The chain starts with the same
`is-idle` class change as the original and covers the idle window ($N$ cycles, $600 N \ge$ idle ms).

**What is proved.**
* Vision, class E:
  * `origVal_plateau`: each original frame is a three-plateau function of the local time $u = (t - S) \bmod 600$ ms.
  * `exact_chain_vis`: the chain with the exact boundaries 199.98 ms and 399.96 ms equals the original at *every*
    elapsed time in the window, for every start time: no phase premise.
  * `clean_chain_grid` (the start-offset premise, R5): the chain with round boundaries 200 ms and 400 ms equals the
    original at every 60 Hz sample $t_k = 50k/3$ ms inside the chain window ($t_k - S = 600m + u$, $m < N$,
    $0 \le u < 600$), provided the start $S = 50s/3 + \varphi$ has phase $\varphi = 0$ or $1/25 < \varphi < 50/3$ ms
    (the "if" direction only). `clean_chain_phase_bad` shows a sample that differs at
    $\varphi = 1/50$. $S$ is the start time read from `document.timeline` (research note 10-18-engine-gaps, R5).
* Work, on the grid with the start on a sample ($\varphi = 0$, 36 frames per 600 ms cycle):
  * Chromium, original on the main thread (`validTarget = false`): every frame $W(v) \preceq W(o)$ and strictly on
    the 33 quiet frames of 36 (`cr_main_le`, `cr_main_quiet_lt`); 4 s run: `cr_main_run_dominates`.
  * Chromium, original on the compositor (INFERRED from source: an outer `<svg>` with a current opacity animation is
    stacked, has a paint layer and gets `kActiveOpacityAnimation`, `B/core/paint/compositing/compositing_reason_finder.cc:421-432,586-593`,
    `B/core/layout/layout_box.cc:554-562`, `B/core/animation/css/css_animations.cc:2226-2228`): a trade, not a win.
    Style passes per 4 s drop from 240 to 20, but every step frame adds a commit the compositor original never pays
    (`cr_comp_step_not_le`, `cr_comp_window`, `cr_comp_run_mixed`); in real Chrome the original's main thread is idle
    and the variant's is not (`cr_realChrome_step_worse`).
  * WebKit: the original ticks only at its steps (`KeyframeEffect.cpp:2670-2722`@862f17d), in the same frames as the
    variant, with the same value changes: $W(v) = W(o)$ in every frame (`wk_frame_eq`, `wk_run_equal`). Equality,
    not a win. Ticks that restyle to an equal value are not in the WebKit table, so the rows predict `≤o` there.
* Golden rows for `pnpm fw engine-check` (`goldenRows`, `packages/contracts/golden/engine/hero-accent.jsonl`).

**Premises** (hypotheses or named model choices): both arms start at the same $S$ (INFERRED: same class change);
the phase $\varphi$ for the round chain (R5); IEEE rounding of delays and progress (R8-like, not modelled); the chain
covers the idle window; Chromium's 40 ms pre-wake (`B/core/animation/document_timeline.cc:111-135`) services no
fraction change and so dirties no style (INFERRED, `keyframe_effect_model.cc:219-220`); the start frame $k = 0$ is
modelled as a cycle start. Exact arithmetic: `Rat` ms for times and opacity, `Nat` for frames and counts.
-/
namespace Fw.Parts.HeroAccentOpt

open Fw.Engine

/-! ## 1. The original: three step-end keyframe lists -/

/-- The keyframes of boil frame $j$ as (offset, opacity) pairs, offsets as exact fractions of the 600 ms cycle; no
frame for $j \ge 3$.

$$\operatorname{kf}(j) = \begin{cases} [(0,1), (0.3332,1), (0.3333,0), (1,0)] & j = 0 \\ [(0,0), (0.3332,0), (0.3333,1), (0.6665,1), (0.6666,0), (1,0)] & j = 1 \\ [(0,0), (0.6665,0), (0.6666,1), (1,1)] & j = 2 \\ [\,] & j \ge 3 \end{cases}$$

The snapshot's three `@keyframes svelte-1fn2go6-idle-j`, restated. -/
def kfs : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (3332 / 10000, 1), (3333 / 10000, 0), (1, 0)]
  | 1 => [(0, 0), (3332 / 10000, 0), (3333 / 10000, 1), (6665 / 10000, 1), (6666 / 10000, 0), (1, 0)]
  | 2 => [(0, 0), (6665 / 10000, 0), (6666 / 10000, 1), (1, 1)]
  | _ => []

/-- **Step-end evaluation** of a keyframe list at iteration progress $p$: the value of the last keyframe (in list
order) whose offset is at most $p$; 0 when there is none.

$$\operatorname{stepEnd}(K, p) = \operatorname{foldl}\big((a, (o, v)) \mapsto (v \text{ if } o \le p \text{ else } a),\ 0,\ K\big)$$

On a sorted list this is the from-value of the interval $[o_i, o_{i+1})$ that holds $p$, which is what
`steps(1, end)` shows. -/
def stepEnd (kf : List (Rat × Rat)) (p : Rat) : Rat :=
  kf.foldl (fun acc k => if k.1 ≤ p then k.2 else acc) 0

/-- The original's opacity of frame $j$ at local time $u$ ms into a cycle.

$$\operatorname{orig}(j, u) = \operatorname{stepEnd}\big(\operatorname{kf}(j),\ u / 600\big)$$

The value the original shows $u$ ms after a cycle start. -/
def origVal (j : Nat) (u : Rat) : Rat := stepEnd (kfs j) (u / 600)

/-- The three plateaus, in ms: frame 0 shows before 199.98, frame 1 on $[199.98, 399.96)$, frame 2 from 399.96 on.

$$\operatorname{plat}(j, u) = \begin{cases} [u < 199.98] & j = 0 \\ [199.98 \le u < 399.96] & j = 1 \\ [399.96 \le u] & j = 2 \\ 0 & j \ge 3 \end{cases}\quad ([\cdot] \in \{0, 1\})$$

Which frame is visible at each moment of a cycle. -/
def plateau (j : Nat) (u : Rat) : Rat :=
  match j with
  | 0 => if u < 19998 / 100 then 1 else 0
  | 1 => if 19998 / 100 ≤ u ∧ u < 39996 / 100 then 1 else 0
  | 2 => if 39996 / 100 ≤ u then 1 else 0
  | _ => 0

/-- **The original is a three-plateau function.** For every frame $j$ and every local time $u \ge 0$ the step-end
value equals the plateau value (for $u \ge 600$ the last keyframe holds, which agrees with the last plateau).

$$\forall j \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ 0 \le u \Rightarrow \operatorname{orig}(j, u) = \operatorname{plat}(j, u)$$

The 0.06 ms keyframe pairs at 33.32/33.33 % and 66.65/66.66 % only move each switch to 199.98 ms and 399.96 ms. -/
theorem origVal_plateau (j : Nat) (u : Rat) (h0 : 0 ≤ u) : origVal j u = plateau j u := by
  match j with
  | 0 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | 1 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | 2 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | _ + 3 => simp [origVal, kfs, stepEnd, plateau]

/-! ## 2. The variant: a chain of zero-duration, fill-forwards steps -/

/-- One step of the chain fold at elapsed time $e$: a step $(d, v)$ whose delay has passed ($d \le e$) replaces the
shown value.

$$\operatorname{stepF}_e(a, (d, v)) = \begin{cases} \operatorname{some}(v) & d \le e \\ a & \text{otherwise} \end{cases}$$

A later animation in the list wins over an earlier one. -/
def stepF (e : Rat) (acc : Option Rat) (s : Rat × Rat) : Option Rat := if s.1 ≤ e then some s.2 else acc

/-- **The chain's value** at elapsed time $e$ (ms since the shared start $S$): the value of the last step in list
order whose delay is at most $e$; none (the box's own style) before the first.

$$\operatorname{chainVal}(C, e) = \operatorname{foldl}(\operatorname{stepF}_e, \operatorname{none}, C)$$

What a box with the animation list $C$ shows $e$ ms after the start. -/
def chainVal (cs : List (Rat × Rat)) (e : Rat) : Option Rat := cs.foldl (stepF e) none

/-- The exact step offsets of frame $j$ within one cycle, as (delay ms, opacity).

$$\operatorname{bnd}(j) = \begin{cases} [(0,1), (199.98,0)] & j = 0 \\ [(0,0), (199.98,1), (399.96,0)] & j = 1 \\ [(0,0), (399.96,1)] & j = 2 \\ [\,] & j \ge 3 \end{cases}$$

Every value change of the original, at the original's own boundaries. -/
def bounds : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (19998 / 100, 0)]
  | 1 => [(0, 0), (19998 / 100, 1), (39996 / 100, 0)]
  | 2 => [(0, 0), (39996 / 100, 1)]
  | _ => []

/-- The round step offsets of frame $j$ (200 ms and 400 ms instead of 199.98 ms and 399.96 ms).

$$\operatorname{bnd}^{\circ}(j) = \begin{cases} [(0,1), (200,0)] & j = 0 \\ [(0,0), (200,1), (400,0)] & j = 1 \\ [(0,0), (400,1)] & j = 2 \\ [\,] & j \ge 3 \end{cases}$$

The chain a hand-written port would use; it needs the phase premise. -/
def cleanBounds : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (200, 0)]
  | 1 => [(0, 0), (200, 1), (400, 0)]
  | 2 => [(0, 0), (400, 1)]
  | _ => []

/-- Cycle $m$ of a chain: every offset shifted by $600m$ ms.

$$\operatorname{cyc}(B, m) = [\,(600m + b, v) \mid (b, v) \in B\,]$$

The steps of one 600 ms cycle. -/
def cycle (bs : List (Rat × Rat)) (m : Nat) : List (Rat × Rat) := bs.map fun s => (600 * (m : Rat) + s.1, s.2)

/-- The chain of $N$ cycles, cycle 0 first.

$$\operatorname{chain}(B, 0) = [\,],\qquad \operatorname{chain}(B, n+1) = \operatorname{chain}(B, n) \mathbin{+\!\!+} \operatorname{cyc}(B, n)$$

The animation list the variant puts on one frame box. -/
def chain (bs : List (Rat × Rat)) : Nat → List (Rat × Rat)
  | 0 => []
  | n + 1 => chain bs n ++ cycle bs n

/-- A fold over steps whose delays all lie after $e$ changes nothing.

$$\forall C, e, a:\ (\forall (d, v) \in C:\ e < d) \Rightarrow \operatorname{foldl}(\operatorname{stepF}_e, a, C) = a$$

Steps still in their before phase do not apply. -/
theorem foldl_inert (cs : List (Rat × Rat)) (e : Rat) (acc : Option Rat) (h : ∀ s ∈ cs, e < s.1) :
    cs.foldl (stepF e) acc = acc := by
  induction cs generalizing acc with
  | nil => rfl
  | cons s rest ih =>
    simp only [List.foldl]
    have hs : ¬ s.1 ≤ e := by have := h s (List.mem_cons_self ..); grind
    simp only [stepF, hs, ↓reduceIte]
    exact ih acc fun x hx => h x (List.mem_cons_of_mem _ hx)

/-- A later cycle is inert before its start.

$$\forall B, m, e, a:\ (\forall (b, v) \in B:\ 0 \le b) \land e < 600m \Rightarrow \operatorname{foldl}(\operatorname{stepF}_e, a, \operatorname{cyc}(B, m)) = a$$

Cycle $m$ waits until $600m$ ms. -/
theorem cycle_inert (bs : List (Rat × Rat)) (m : Nat) (e : Rat) (acc : Option Rat) (hb : ∀ s ∈ bs, 0 ≤ s.1)
    (he : e < 600 * (m : Rat)) : (cycle bs m).foldl (stepF e) acc = acc := by
  apply foldl_inert
  intro s hs
  simp only [cycle, List.mem_map] at hs
  obtain ⟨b, hb', rfl⟩ := hs
  have := hb b hb'
  simp only
  grind

/-- A cycle that starts with a step at offset 0 overrides whatever came before, once it has started.

$$\forall v, R, m, e, a:\ 600m \le e \Rightarrow \operatorname{foldl}(\operatorname{stepF}_e, a, \operatorname{cyc}((0, v) :: R, m)) = \operatorname{foldl}(\operatorname{stepF}_e, \operatorname{none}, \operatorname{cyc}((0, v) :: R, m))$$

The offset-0 step of cycle $m$ hides every earlier cycle. -/
theorem cycle_override (v : Rat) (rest : List (Rat × Rat)) (m : Nat) (e : Rat) (acc : Option Rat)
    (he : 600 * (m : Rat) ≤ e) :
    (cycle ((0, v) :: rest) m).foldl (stepF e) acc = (cycle ((0, v) :: rest) m).foldl (stepF e) none := by
  have h : 600 * (m : Rat) + 0 ≤ e := by grind
  simp only [cycle, List.map_cons, List.foldl_cons, stepF, h, ↓reduceIte]

/-- **The chain shows the current cycle.** If every offset is non-negative and the list starts with an offset-0
step, then for $m < n$ and $600m \le e < 600(m+1)$ the $n$-cycle chain shows what cycle $m$ alone shows.

$$\forall v, R, n, m, e:\ (\forall (b, w) \in (0, v) :: R:\ 0 \le b) \land m < n \land 600m \le e < 600(m+1) \Rightarrow \operatorname{chainVal}(\operatorname{chain}((0, v) :: R, n), e) = \operatorname{chainVal}(\operatorname{cyc}((0, v) :: R, m), e)$$

Earlier cycles are overridden, later ones have not started. -/
theorem chain_eq_cycle (v : Rat) (rest : List (Rat × Rat)) (hb : ∀ s ∈ (0, v) :: rest, 0 ≤ s.1) :
    ∀ (n m : Nat) (e : Rat), m < n → 600 * (m : Rat) ≤ e → e < 600 * ((m : Rat) + 1) →
      chainVal (chain ((0, v) :: rest) n) e = chainVal (cycle ((0, v) :: rest) m) e := by
  intro n
  induction n with
  | zero => intro m e hm; omega
  | succ n ih =>
    intro m e hm h1 h2
    simp only [chainVal, chain, List.foldl_append]
    rcases Nat.lt_succ_iff_lt_or_eq.mp hm with hlt | heq
    · have hih := ih m e hlt h1 h2
      simp only [chainVal] at hih
      rw [hih]
      apply cycle_inert _ _ _ _ hb
      have : ((m + 1 : Nat) : Rat) ≤ (n : Rat) := by exact_mod_cast hlt
      push_cast at this
      grind
    · subst heq
      exact cycle_override v rest m e _ h1

/-- One cycle of the exact chain shows the plateau value.

$$\forall j < 3,\ \forall m \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ 0 \le u \Rightarrow \operatorname{chainVal}(\operatorname{cyc}(\operatorname{bnd}(j), m), 600m + u) = \operatorname{some}(\operatorname{plat}(j, u))$$

The exact boundaries are the plateau boundaries. -/
theorem cycle_exact (j : Nat) (hj : j < 3) (m : Nat) (u : Rat) (h0 : 0 ≤ u) :
    chainVal (cycle (bounds j) m) (600 * (m : Rat) + u) = some (plateau j u) := by
  match j, hj with
  | 0, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind
  | 1, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind
  | 2, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind

/-- The round plateaus (boundaries 200 ms and 400 ms).

$$\operatorname{plat}^{\circ}(j, u) = \begin{cases} [u < 200] & j = 0 \\ [200 \le u < 400] & j = 1 \\ [400 \le u] & j = 2 \\ 0 & j \ge 3 \end{cases}$$

What the round chain shows. -/
def cleanPlateau (j : Nat) (u : Rat) : Rat :=
  match j with
  | 0 => if u < 200 then 1 else 0
  | 1 => if 200 ≤ u ∧ u < 400 then 1 else 0
  | 2 => if 400 ≤ u then 1 else 0
  | _ => 0

/-- One cycle of the round chain shows the round plateau value.

$$\forall j < 3,\ \forall m \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ 0 \le u \Rightarrow \operatorname{chainVal}(\operatorname{cyc}(\operatorname{bnd}^{\circ}(j), m), 600m + u) = \operatorname{some}(\operatorname{plat}^{\circ}(j, u))$$

The round chain switches at 200 and 400 ms. -/
theorem cycle_clean (j : Nat) (hj : j < 3) (m : Nat) (u : Rat) (h0 : 0 ≤ u) :
    chainVal (cycle (cleanBounds j) m) (600 * (m : Rat) + u) = some (cleanPlateau j u) := by
  match j, hj with
  | 0, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind
  | 1, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind
  | 2, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind

/-- **Vision, exact chain (class E, no phase premise).** For every frame $j < 3$, every chain length $N$, every
cycle $m < N$ and every local time $0 \le u < 600$ ms, the exact chain at elapsed time $600m + u$ shows the
original's value at local time $u$.

$$\forall j < 3,\ \forall N, m \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ m < N \land 0 \le u < 600 \Rightarrow \operatorname{chainVal}(\operatorname{chain}(\operatorname{bnd}(j), N), 600m + u) = \operatorname{some}(\operatorname{orig}(j, u))$$

With the exact boundaries the variant equals the original at every instant of the window, whatever the frame grid. -/
theorem exact_chain_vis (j : Nat) (hj : j < 3) (N m : Nat) (u : Rat) (hm : m < N) (h0 : 0 ≤ u) (h1 : u < 600) :
    chainVal (chain (bounds j) N) (600 * (m : Rat) + u) = some (origVal j u) := by
  rw [origVal_plateau j u h0, ← cycle_exact j hj m u h0]
  match j, hj with
  | 0, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 1, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 2, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)

/-- The round plateaus agree with the original's outside the two gaps $[199.98, 200)$ and $[399.96, 400)$.

$$\forall j \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ (u < 199.98 \lor 200 \le u) \land (u < 399.96 \lor 400 \le u) \Rightarrow \operatorname{plat}^{\circ}(j, u) = \operatorname{plat}(j, u)$$

Only a sample inside a 0.02 or 0.04 ms gap can tell the round chain apart. -/
theorem clean_eq_off_gaps (j : Nat) (u : Rat) (g1 : u < 19998 / 100 ∨ 200 ≤ u) (g2 : u < 39996 / 100 ∨ 400 ≤ u) :
    cleanPlateau j u = plateau j u := by
  match j with
  | 0 => simp only [cleanPlateau, plateau]; grind
  | 1 => simp only [cleanPlateau, plateau]; grind
  | 2 => simp only [cleanPlateau, plateau]; grind
  | _ + 3 => rfl

/-- No integer lies strictly between $a$ and $a + 1$.

$$\forall i, a \in \mathbb{Z}:\ \neg(a < i \land i < a + 1)\ \text{(read in } \mathbb{Q}\text{)}$$

The integer step used by the grid argument. -/
theorem no_int_between (i a : Int) (h1 : (a : Rat) < i) (h2 : (i : Rat) < a + 1) : False := by
  have h1' : a < i := by exact_mod_cast h1
  have h2' : i < a + 1 := by exact_mod_cast h2
  omega

/-- **Vision on the 60 Hz grid, round chain (class E per sample, start-offset premise R5).** Let the shared start be
$S = 50s/3 + \varphi$ ms with $s \in \mathbb{Z}$ and phase $\varphi = 0$ or $1/25 < \varphi < 50/3$. Then for every
frame $j < 3$, chain length $N$, sample $t_k = 50k/3$ ($k \in \mathbb{Z}$), cycle $m < N$ and local time
$0 \le u < 600$ with $t_k - S = 600m + u$, the round chain shows the original's value at the sample.

$$\forall j < 3,\ \forall N \in \mathbb{N},\ \forall s \in \mathbb{Z},\ \forall \varphi \in \mathbb{Q},\ \forall k \in \mathbb{Z},\ \forall m \in \mathbb{N},\ \forall u \in \mathbb{Q}:\ \big(\varphi = 0 \lor \tfrac{1}{25} < \varphi < \tfrac{50}{3}\big) \land m < N \land 0 \le u < 600 \land \tfrac{50k}{3} - \big(\tfrac{50s}{3} + \varphi\big) = 600m + u \Rightarrow \operatorname{chainVal}\Big(\operatorname{chain}(\operatorname{bnd}^{\circ}(j), N),\ \tfrac{50k}{3} - \big(\tfrac{50s}{3} + \varphi\big)\Big) = \operatorname{some}(\operatorname{orig}(j, u))$$

Every frame-time sample lands on a plateau of both arms unless the start sits 0 to 0.04 ms past a grid point. -/
theorem clean_chain_grid (j : Nat) (hj : j < 3) (N : Nat) (s : Int) (φ : Rat)
    (hφ : φ = 0 ∨ (1 / 25 < φ ∧ φ < 50 / 3)) (k : Int) (m : Nat) (u : Rat) (hm : m < N) (h0 : 0 ≤ u)
    (h1 : u < 600) (he : 50 * (k : Rat) / 3 - (50 * (s : Rat) / 3 + φ) = 600 * (m : Rat) + u) :
    chainVal (chain (cleanBounds j) N) (50 * (k : Rat) / 3 - (50 * (s : Rat) / 3 + φ)) = some (origVal j u) := by
  -- u sits on the grid shifted by φ: u = 50 i / 3 - φ with i = k - s - 36 m
  have hu : u = 50 * ((k - s - 36 * (m : Int) : Int) : Rat) / 3 - φ := by push_cast; grind
  have g1 : u < 19998 / 100 ∨ 200 ≤ u := by
    rcases Classical.em (u < 19998 / 100) with h | h
    · exact Or.inl h
    · right
      rcases Classical.em (200 ≤ u) with h' | h'
      · exact h'
      · exfalso
        rcases hφ with hφ | ⟨hφ1, hφ2⟩
        · exact no_int_between (k - s - 36 * (m : Int)) 11 (by push_cast at hu ⊢; grind) (by push_cast at hu ⊢; grind)
        · exact no_int_between (k - s - 36 * (m : Int)) 12 (by push_cast at hu ⊢; grind) (by push_cast at hu ⊢; grind)
  have g2 : u < 39996 / 100 ∨ 400 ≤ u := by
    rcases Classical.em (u < 39996 / 100) with h | h
    · exact Or.inl h
    · right
      rcases Classical.em (400 ≤ u) with h' | h'
      · exact h'
      · exfalso
        rcases hφ with hφ | ⟨hφ1, hφ2⟩
        · exact no_int_between (k - s - 36 * (m : Int)) 23 (by push_cast at hu ⊢; grind) (by push_cast at hu ⊢; grind)
        · exact no_int_between (k - s - 36 * (m : Int)) 24 (by push_cast at hu ⊢; grind) (by push_cast at hu ⊢; grind)
  rw [he, origVal_plateau j u h0, ← clean_eq_off_gaps j u g1 g2, ← cycle_clean j hj m u h0]
  match j, hj with
  | 0, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 1, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 2, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)

/-- **The phase premise is needed.** With $s = 0$, $\varphi = 1/50$ ms, sample $k = 12$ and one cycle, the elapsed
time is $600 \cdot 0 + 199.98$; there the round chain still shows frame 0 while the original has switched it off.

$$\tfrac{50 \cdot 12}{3} - \big(\tfrac{50 \cdot 0}{3} + \tfrac{1}{50}\big) = 600 \cdot 0 + 199.98 \ \land\ \operatorname{chainVal}\Big(\operatorname{chain}(\operatorname{bnd}^{\circ}(0), 1),\ \tfrac{50 \cdot 12}{3} - \big(\tfrac{50 \cdot 0}{3} + \tfrac{1}{50}\big)\Big) = \operatorname{some}(1) \ \land\ \operatorname{orig}(0, 199.98) = 0$$

A start 0.02 ms past a grid point puts sample 12 in the gap, so the round chain is not E there. -/
theorem clean_chain_phase_bad :
    50 * ((12 : Int) : Rat) / 3 - (50 * ((0 : Int) : Rat) / 3 + 1 / 50) = 600 * ((0 : Nat) : Rat) + 19998 / 100 ∧
      chainVal (chain (cleanBounds 0) 1) (50 * ((12 : Int) : Rat) / 3 - (50 * ((0 : Int) : Rat) / 3 + 1 / 50)) =
        some 1 ∧
      origVal 0 (19998 / 100) = 0 := by
  refine ⟨by push_cast; grind, ?_, ?_⟩
  · simp only [chainVal, chain, cycle, cleanBounds, List.map, List.nil_append, List.foldl, stepF]
    push_cast
    have a : (600 * (0 : Rat) + 0) ≤ 50 * 12 / 3 - (50 * 0 / 3 + 1 / 50) := by grind
    have b : ¬ (600 * (0 : Rat) + 200) ≤ 50 * 12 / 3 - (50 * 0 / 3 + 1 / 50) := by grind
    simp only [a, b, ↓reduceIte]
  · rw [origVal_plateau 0 _ (by grind)]
    simp only [plateau]
    have : ¬ (19998 / 100 : Rat) < 19998 / 100 := by grind
    simp only [this, ↓reduceIte]

/-! ## 3. The 60 Hz grid with the start on a sample -/

/-- Whether frame $j$ is shown at sample $i$ of a cycle ($t = 50i/3$ ms after the cycle start).

$$\operatorname{sv}(j, i) = \begin{cases} [i < 12] & j = 0 \\ [12 \le i < 24] & j = 1 \\ [24 \le i] & j = 2 \\ \mathrm{false} & j \ge 3 \end{cases}$$

Frame 0 on samples 0-11, frame 1 on 12-23, frame 2 on 24-35. -/
def sv : Nat → Nat → Bool
  | 0, i => decide (i < 12)
  | 1, i => decide (12 ≤ i) && decide (i < 24)
  | 2, i => decide (24 ≤ i)
  | _, _ => false

#guard ((List.range 36).map (sv 0)).count true == 12
#guard (List.range 36).all fun i => [0, 1, 2].countP (sv · i) == 1

/-- **The sampled original.** At sample $i$ the original's value is 1 exactly when `sv` says so.

$$\forall j < 3,\ \forall i \in \mathbb{N}:\ \operatorname{orig}(j, 50i/3) = \begin{cases} 1 & \operatorname{sv}(j, i) \\ 0 & \text{otherwise} \end{cases}$$

No sample falls between 199.98 and 200 ms or between 399.96 and 400 ms. -/
theorem sv_sample (j : Nat) (hj : j < 3) (i : Nat) :
    origVal j (50 * (i : Rat) / 3) = if sv j i then 1 else 0 := by
  rw [origVal_plateau j _ (by grind)]
  have c12 : (50 * (i : Rat) / 3 < 19998 / 100) ↔ i < 12 := by
    constructor
    · intro h
      have : (i : Rat) < 12 := by grind
      exact_mod_cast this
    · intro h
      have : (i : Rat) ≤ 11 := by exact_mod_cast (show i ≤ 11 by omega)
      grind
  have c24 : (50 * (i : Rat) / 3 < 39996 / 100) ↔ i < 24 := by
    constructor
    · intro h
      have : (i : Rat) < 24 := by grind
      exact_mod_cast this
    · intro h
      have : (i : Rat) ≤ 23 := by exact_mod_cast (show i ≤ 23 by omega)
      grind
  match j, hj with
  | 0, _ => simp only [plateau, sv, c12, decide_eq_true_eq]
  | 1, _ =>
    simp only [plateau, sv, Bool.and_eq_true, decide_eq_true_eq]
    have : (19998 / 100 ≤ 50 * (i : Rat) / 3) ↔ 12 ≤ i := by
      rw [← Nat.not_lt, ← c12]; grind
    simp only [this, c24]
  | 2, _ =>
    simp only [plateau, sv, decide_eq_true_eq]
    have : (39996 / 100 ≤ 50 * (i : Rat) / 3) ↔ 24 ≤ i := by
      rw [← Nat.not_lt, ← c24]; grind
    simp only [this]

/-- Whether a step at local offset $b$ ms is applied first at sample $i$: $b \in (50(i-1)/3, 50i/3]$.

$$\operatorname{crossAt}(b, i) \iff \tfrac{50i}{3} - \tfrac{50}{3} < b \le \tfrac{50i}{3}$$

The frame in which the engine sees the step (the offsets here lie in $[0, 399.96]$, so for $i = 0$ only an
offset-0 step of the same cycle qualifies). -/
def crossAt (b : Rat) (i : Nat) : Bool := decide (50 * (i : Rat) / 3 - 50 / 3 < b ∧ b ≤ 50 * (i : Rat) / 3)

/-- Whether any step of a list is applied first at sample $i$.

$$\operatorname{crosses}(B, i) \iff \exists (b, v) \in B:\ \operatorname{crossAt}(b, i)$$

The frames in which a box's chain fires. -/
def crosses (bs : List (Rat × Rat)) (i : Nat) : Bool := bs.any fun s => crossAt s.1 i

/-- The sample at which a step at offset $b$ ms fires, for the five offsets in play: exactly sample $c$.

$$\forall i \in \mathbb{N}:\ \operatorname{crossAt}(0, i) \iff i = 0;\quad \operatorname{crossAt}(b, i) \iff i = 12 \ (b \in \{199.92, 199.98\});\quad \operatorname{crossAt}(b, i) \iff i = 24 \ (b \in \{399.90, 399.96\})$$

Each boundary is seen in one frame: 0, 12 or 24. -/
theorem crossAt_vals (i : Nat) :
    crossAt 0 i = (i == 0) ∧ crossAt (19992 / 100) i = (i == 12) ∧ crossAt (19998 / 100) i = (i == 12) ∧
      crossAt (39990 / 100) i = (i == 24) ∧ crossAt (39996 / 100) i = (i == 24) := by
  have key : ∀ (b : Rat) (c : Nat), 50 * ((c : Rat) - 1) / 3 < b → b ≤ 50 * (c : Rat) / 3 →
      crossAt b i = (i == c) := by
    intro b c hb1 hb2
    simp only [crossAt]
    by_cases hic : i = c
    · subst hic; simp only [beq_self_eq_true, decide_eq_true_eq]; grind
    · have hne : (i == c) = false := by simpa using hic
      rw [hne, decide_eq_false_iff_not]
      intro ⟨h1, h2⟩
      rcases Nat.lt_or_gt_of_ne hic with h | h
      · have : (i : Rat) + 1 ≤ c := by exact_mod_cast h
        grind
      · have : (c : Rat) + 1 ≤ i := by exact_mod_cast h
        grind
  refine ⟨key 0 0 (by grind) (by grind), key _ 12 (by grind) (by grind), key _ 12 (by grind) (by grind),
    key _ 24 (by grind) (by grind), key _ 24 (by grind) (by grind)⟩

/-- The step frames of frame $j$'s chain within a cycle.

$$\operatorname{stepAt}(j, i) = \begin{cases} [i \in \{0, 12\}] & j = 0 \\ [i \in \{0, 12, 24\}] & j = 1 \\ [i \in \{0, 24\}] & j = 2 \\ \mathrm{false} & j \ge 3 \end{cases}$$

Three step frames per 36-frame cycle at most. -/
def stepAt : Nat → Nat → Bool
  | 0, i => i == 0 || i == 12
  | 1, i => i == 0 || i == 12 || i == 24
  | 2, i => i == 0 || i == 24
  | _, _ => false

/-- **The chain fires on the step frames.** For every frame $j$ and sample $i$, a step of the exact chain is first
seen at sample $i$ iff `stepAt` says so.

$$\forall j, i \in \mathbb{N}:\ \operatorname{crosses}(\operatorname{bnd}(j), i) = \operatorname{stepAt}(j, i)$$

The variant's work frames, from its delays. -/
theorem crosses_bounds (j i : Nat) : crosses (bounds j) i = stepAt j i := by
  obtain ⟨a0, -, a2, -, a4⟩ := crossAt_vals i
  match j with
  | 0 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a2, stepAt]
  | 1 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a2, a4, stepAt, Bool.or_assoc]
  | 2 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a4, stepAt]
  | _ + 3 => rfl

/-- The original's step points of frame $j$ in ms within a cycle: $600\,o$ for every keyframe offset $o < 1$ (the
offset-1 keyframe is the next cycle's 0).

$$\operatorname{pts}(j) = [\,(600\,o, v) \mid (o, v) \in \operatorname{kf}(j),\ o < 1\,]$$

Where WebKit schedules the original's ticks (`KeyframeEffect.cpp:2670-2722`@862f17d). -/
def origPoints (j : Nat) : List (Rat × Rat) := ((kfs j).filter fun k => decide (k.1 < 1)).map fun k => (600 * k.1, k.2)

/-- **The original ticks on the same frames.** For every frame $j$ and sample $i$, a step point of the original is
first seen at sample $i$ iff the variant's chain fires there (199.92 and 199.98 ms fall in one frame, as do 399.90
and 399.96 ms).

$$\forall j, i \in \mathbb{N}:\ \operatorname{crosses}(\operatorname{pts}(j), i) = \operatorname{stepAt}(j, i)$$

WebKit's step-aware scheduling already gives the original the variant's tick frames. -/
theorem crosses_origPoints (j i : Nat) : crosses (origPoints j) i = stepAt j i := by
  obtain ⟨a0, a1, a2, a3, a4⟩ := crossAt_vals i
  match j with
  | 0 =>
    have e1 : (600 : Rat) * (3332 / 10000) = 19992 / 100 := by grind
    have e2 : (600 : Rat) * (3333 / 10000) = 19998 / 100 := by grind
    have f : ((1 : Rat) < 1) = False := by grind
    simp [origPoints, kfs, crosses, e1, e2, a0, a1, a2, stepAt]
    grind
  | 1 =>
    have e1 : (600 : Rat) * (3332 / 10000) = 19992 / 100 := by grind
    have e2 : (600 : Rat) * (3333 / 10000) = 19998 / 100 := by grind
    have e3 : (600 : Rat) * (6665 / 10000) = 39990 / 100 := by grind
    have e4 : (600 : Rat) * (6666 / 10000) = 39996 / 100 := by grind
    simp [origPoints, kfs, crosses, e1, e2, e3, e4, a0, a1, a2, a3, a4, stepAt]
    grind
  | 2 =>
    have e3 : (600 : Rat) * (6665 / 10000) = 39990 / 100 := by grind
    have e4 : (600 : Rat) * (6666 / 10000) = 39996 / 100 := by grind
    simp [origPoints, kfs, crosses, e3, e4, a0, a3, a4, stepAt]
    grind
  | _ + 3 => rfl

/-- Whether frame $j$'s value changes at sample $i$ (against sample $i - 1$, cyclically: sample 0 against 35).

$$\operatorname{chg}(j, i) \iff \operatorname{sv}(j, i) \ne \operatorname{sv}(j, (i + 35) \bmod 36)$$

The start frame is modelled as a cycle start (one value change more for the variant than at the real start). -/
def chg (j i : Nat) : Bool := sv j i != sv j ((i + 35) % 36)

/-- **A value changes only on a step frame.**

$$\forall j < 3,\ \forall i < 36:\ \operatorname{chg}(j, i) \Rightarrow \operatorname{stepAt}(j, i)$$

The chain never misses a change. -/
theorem chg_step : ∀ j < 3, ∀ i < 36, chg j i = true → stepAt j i = true := by decide

/-! ## 4. Chromium -/

open Fw.Engine.Chromium in
/-- The original's three running animations: opacity on boxes 0, 1, 2 with layer state $\ell$; `valid` is whether the
target's compositing state is valid (a direct compositing reason).

$$\operatorname{crAnims}(\mathit{valid}, \ell) = [\,(j, [\mathrm{css}(\mathrm{opacity})], \ell, \mathit{valid}) \mid j \in [0, 1, 2]\,]\quad (\text{other fields default: document timeline})$$

The three `idle-j` animations. -/
def crAnims (valid : Bool) (ℓ : LayerState) : List Chromium.CrAnim :=
  [0, 1, 2].map fun j => { elem := j, props := [.css .opacity], layer := ℓ, validTarget := valid }

/-- The original's frame in mode $m$: the same every frame (an active non-composited animation is serviced every
frame, `B/core/animation/animation.cc:3390-3394`; a composited one ticks on the compositor).

$$\operatorname{crO}(m, \mathit{valid}, \ell) = \operatorname{animFrame}(m, \operatorname{crAnims}(\mathit{valid}, \ell))$$

What the original costs Chromium in any frame. -/
def crOrig (m : Chromium.CrMode) (valid : Bool) (ℓ : LayerState) : FrameIn Chromium.CrProp :=
  Chromium.animFrame m (crAnims valid ℓ)

open Fw.Engine.Chromium in
/-- The variant's change on box $j$ at a step frame $i$: an opacity change if the value changes, else a same-value
restyle (the table's style-only row, a custom property with no readers).

$$\operatorname{crC}(\ell, j, i) = \begin{cases} (j, \mathrm{css}(\mathrm{opacity}), \ell) & \operatorname{chg}(j, i) \\ (j, \mathrm{custom}(j, [\,]), \ell) & \text{otherwise} \end{cases}$$

A step that fires restyles its box; it repaints only if the value moved. -/
def crChange (ℓ : LayerState) (j i : Nat) : Change CrProp :=
  if chg j i then ⟨j, .css .opacity, ℓ⟩ else ⟨j, .custom j [], ℓ⟩

/-- The variant's Chromium frame at sample $i$: one change per box whose chain fires, nothing else.

$$\operatorname{crV}(\ell, i) = \big(0, 0, 0, 0,\ [\,\operatorname{crC}(\ell, j, i) \mid j \in [0, 1, 2],\ \operatorname{stepAt}(j, i)\,],\ 0\big)$$

Quiet frames are empty. -/
def crVar (ℓ : LayerState) (i : Nat) : FrameIn Chromium.CrProp :=
  ⟨0, 0, 0, 0, ([0, 1, 2].filter (stepAt · i)).map (crChange ℓ · i), 0⟩

/-- **Chromium, original on the main thread: every frame `≤`.** For every layer state and every sample of a cycle,
the variant's frame work is at most the original's when the original's targets are not compositable.

$$\forall \ell \in \mathrm{LayerState},\ \forall i < 36:\ W_{\mathrm{cr}}(\operatorname{crV}(\ell, i)) \preceq W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell))$$

Each firing step is one of the restyles the original does anyway. -/
theorem cr_main_le : ∀ ℓ : LayerState, ∀ i < 36,
    (frameWork Chromium.chromium (crVar ℓ i)).le (frameWork Chromium.chromium (crOrig Chromium.lane false ℓ)) := by
  intro ℓ i hi
  apply frame_le_union
  revert i
  cases ℓ <;> decide

/-- Whether no chain fires at sample $i$.

$$\operatorname{quiet}(i) \iff \forall j \in [0, 1, 2]:\ \lnot\operatorname{stepAt}(j, i)$$

33 of 36 samples per cycle. -/
def quiet (i : Nat) : Bool := [0, 1, 2].all fun j => !stepAt j i

#guard (List.range 36).countP quiet == 33

/-- **Chromium, original on the main thread: strictly less on quiet frames.**

$$\forall \ell \in \mathrm{LayerState},\ \forall i \in \mathbb{N}:\ \operatorname{quiet}(i) \Rightarrow W_{\mathrm{cr}}(\operatorname{crV}(\ell, i)) \prec W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell))$$

Between steps the variant does no work at all; the original restyles three boxes. -/
theorem cr_main_quiet_lt (ℓ : LayerState) (i : Nat) (hq : quiet i = true) :
    (frameWork Chromium.chromium (crVar ℓ i)).lt (frameWork Chromium.chromium (crOrig Chromium.lane false ℓ)) := by
  have he : crVar ℓ i = ⟨0, 0, 0, 0, [], 0⟩ := by
    simp only [quiet, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true, Bool.not_eq_true'] at hq
    simp [crVar, List.filter, hq.1, hq.2.1, hq.2.2]
  rw [he, ← Work.ltb_iff]
  cases ℓ <;> decide

/-- The variant's and the original's Chromium runs over $n$ samples from a cycle start, in mode $m$.

$$\operatorname{runV}(\ell, n) = [\,W_{\mathrm{cr}}(\operatorname{crV}(\ell, k \bmod 36)) \mid k < n\,],\qquad \operatorname{runO}(m, \mathit{valid}, \ell, n) = [\,W_{\operatorname{chromiumAt}(m)}(\operatorname{crO}(m, \mathit{valid}, \ell)) \mid k < n\,]$$

240 samples are 4 s. -/
def runV (ℓ : LayerState) (n : Nat) : List Work := (List.range n).map fun k => frameWork Chromium.chromium (crVar ℓ (k % 36))

/-- See `runV`.

$$\operatorname{runO}(m, \mathit{valid}, \ell, n) = [\,W_{\operatorname{chromiumAt}(m)}(\operatorname{crO}(m, \mathit{valid}, \ell)) \mid k < n\,]$$

The original's run: the same frame $n$ times. -/
def runO (m : Chromium.CrMode) (valid : Bool) (ℓ : LayerState) (n : Nat) : List Work :=
  (List.range n).map fun _ => frameWork (Chromium.chromiumAt m) (crOrig m valid ℓ)

/-- **Chromium, original on the main thread: the 4 s run dominates.** Over 240 samples (4 s) the screen, with the
original as baseline, answers `dominates`.

$$\forall \ell \in \mathrm{LayerState}:\ \operatorname{screen}\big(\operatorname{toRun}(\operatorname{runO}(\mathrm{lane}, \mathrm{false}, \ell, 240)),\ \operatorname{toRun}(\operatorname{runV}(\ell, 240))\big) = \mathrm{ok}(\mathrm{dominates})$$

Style and paint once per plateau instead of every frame. -/
theorem cr_main_run_dominates (ℓ : LayerState) :
    Screen.screen (toRun (runO Chromium.lane false ℓ 240)) (toRun (runV ℓ 240)) = .ok .dominates := by
  apply run_dominates
  · cases ℓ <;> decide +kernel
  · cases ℓ <;> decide +kernel

/-- **Chromium, original on the compositor: a step frame is not `≤`.** At the cycle start (sample 0) the variant
commits its own-layer opacity change, which the compositor-run original never does.

$$W_{\mathrm{cr}}(\operatorname{crV}(\mathrm{own}, 0)).\mathrm{passes}(\mathrm{commit}) = 1 \ \land\ W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{true}, \mathrm{own})).\mathrm{passes}(\mathrm{commit}) = 0 \ \land\ \neg\big(W_{\mathrm{cr}}(\operatorname{crV}(\mathrm{own}, 0)) \preceq W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}))\big)$$

Moving the boil to the main thread costs a commit per step. -/
theorem cr_comp_step_not_le :
    (frameWork Chromium.chromium (crVar .own 0)).passes .commit = 1 ∧
      (frameWork Chromium.chromium (crOrig Chromium.lane true .own)).passes .commit = 0 ∧
      ¬ (frameWork Chromium.chromium (crVar .own 0)).le (frameWork Chromium.chromium (crOrig Chromium.lane true .own)) := by
  refine ⟨by decide, by decide, ?_⟩
  rw [← Work.leb_iff]
  decide

/-- Sum of one stage's passes over a run.

$$\operatorname{sumP}(s, R) = \textstyle\sum_{w \in R} w.\mathrm{passes}(s)$$

A 4 s count per stage. -/
def sumP (s : Stage) (ws : List Work) : Nat := (ws.map fun w => w.passes s).sum

/-- **Chromium, original on the compositor: the 4 s counts.** Over 240 samples the variant has 20 style passes
against 240, 20 commits against 0, and no compositor ticks against 240.

$$\operatorname{sumP}(\mathrm{style}, \operatorname{runV}(\mathrm{own}, 240)) = 20 \land \operatorname{sumP}(\mathrm{style}, \operatorname{runO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}, 240)) = 240 \land \operatorname{sumP}(\mathrm{commit}, \operatorname{runV}(\mathrm{own}, 240)) = 20 \land \operatorname{sumP}(\mathrm{commit}, \operatorname{runO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}, 240)) = 0 \land \operatorname{sumP}(\mathrm{comp}, \operatorname{runV}(\mathrm{own}, 240)) = 0 \land \operatorname{sumP}(\mathrm{comp}, \operatorname{runO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}, 240)) = 240$$

A trade in the lane: 220 fewer style passes, 20 more commits. -/
theorem cr_comp_window :
    sumP .style (runV .own 240) = 20 ∧ sumP .style (runO Chromium.lane true .own 240) = 240 ∧
      sumP .commit (runV .own 240) = 20 ∧ sumP .commit (runO Chromium.lane true .own 240) = 0 ∧
      sumP .comp (runV .own 240) = 0 ∧ sumP .comp (runO Chromium.lane true .own 240) = 240 := by
  decide +kernel

/-- **Chromium, original on the compositor: the screen says `mixed`.**

$$\operatorname{screen}\big(\operatorname{toRun}(\operatorname{runO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}, 240)),\ \operatorname{toRun}(\operatorname{runV}(\mathrm{own}, 240))\big) = \mathrm{ok}(\mathrm{mixed})$$

Not a dominance claim in the lane. -/
theorem cr_comp_run_mixed :
    Screen.screen (toRun (runO Chromium.lane true .own 240)) (toRun (runV .own 240)) = .ok .mixed := by
  have h1 : Screen.shapeEq (toRun (runO Chromium.lane true .own 240)) (toRun (runV .own 240)) = true := by
    decide +kernel
  have h2 : (toRun (runV .own 240) == toRun (runO Chromium.lane true .own 240)) = false := by decide +kernel
  have h3 : Screen.leRun (toRun (runV .own 240)) (toRun (runO Chromium.lane true .own 240)) = false := by
    decide +kernel
  have h4 : Screen.leRun (toRun (runO Chromium.lane true .own 240)) (toRun (runV .own 240)) = false := by
    decide +kernel
  unfold Screen.screen
  simp only [h1, h2, h3, h4, Bool.not_true, Bool.false_eq_true, ↓reduceIte]

/-- **Real Chrome: the variant adds main-thread work.** With the original on the compositor, real Chrome's main
thread does no style pass in any frame, while the variant restyles on each step frame.

$$\forall i \in \{0, 12, 24\}:\ W_{\operatorname{chromiumAt}(\mathrm{realChrome})}(\operatorname{crO}(\mathrm{realChrome}, \mathrm{true}, \mathrm{own})).\mathrm{passes}(\mathrm{style}) = 0 \land W_{\operatorname{chromiumAt}(\mathrm{realChrome})}(\operatorname{crV}(\mathrm{own}, i)).\mathrm{passes}(\mathrm{style}) = 1$$

Outside the lane the variant is worse on the main thread. -/
theorem cr_realChrome_step_worse : ∀ i ∈ [0, 12, 24],
    (frameWork (Chromium.chromiumAt Chromium.realChrome) (crOrig Chromium.realChrome true .own)).passes .style = 0 ∧
      (frameWork (Chromium.chromiumAt Chromium.realChrome) (crVar .own i)).passes .style = 1 := by
  decide

/-! ## 5. WebKit -/

/-- A value change of box $j$ under WebKit: opacity between 0 and 1 crosses 1 (`StyleDifference.cpp:208-214`@862f17d),
on a box with no own layer.

$$\operatorname{wkC}(j) = (j, \mathrm{opacityCross1}, \mathrm{none})$$

The only modelled WebKit change of the boil. -/
def wkChange (j : Nat) : Change WebKit.WkProp := ⟨j, .opacityCross1, .none⟩

/-- A WebKit frame at sample $i$ from a tick rule: box $j$ contributes its value change when it ticks and its value
moves; a tick to an equal value has diff `equal` and no stages, so it is left out.

$$\operatorname{wkF}(\mathit{tick}, i) = \big(0, 0, 0, 0,\ [\,\operatorname{wkC}(j) \mid j \in [0, 1, 2],\ \mathit{tick}(j, i) \land \operatorname{chg}(j, i)\,],\ 0\big)$$

Steps are refused acceleration (`KeyframeEffect.cpp:2011`@862f17d), and so is a zero-duration chain: both run in the
web process. -/
def wkFrame (tick : Nat → Nat → Bool) (i : Nat) : FrameIn WebKit.WkProp :=
  ⟨0, 0, 0, 0, ([0, 1, 2].filter fun j => tick j i && chg j i).map wkChange, 0⟩

/-- The original's WebKit frame at sample $i$: it ticks where a keyframe step point is crossed.

$$\operatorname{wkO}(i) = \operatorname{wkF}\big((j, i) \mapsto \operatorname{crosses}(\operatorname{pts}(j), i),\ i\big)$$

WebKit@862f17d schedules the next tick at the next step. -/
def wkOrig (i : Nat) : FrameIn WebKit.WkProp := wkFrame (fun j i => crosses (origPoints j) i) i

/-- The variant's WebKit frame at sample $i$: it ticks where its chain fires.

$$\operatorname{wkV}(i) = \operatorname{wkF}\big((j, i) \mapsto \operatorname{crosses}(\operatorname{bnd}(j), i),\ i\big)$$

A zero-duration step ticks once, at its delay. -/
def wkVar (i : Nat) : FrameIn WebKit.WkProp := wkFrame (fun j i => crosses (bounds j) i) i

/-- **WebKit: equal work in every frame.** For every sample, the variant's WebKit frame is the original's, so the
work is equal.

$$\forall i \in \mathbb{N}:\ \operatorname{wkV}(i) = \operatorname{wkO}(i) \ \land\ W_{\mathrm{wk}}(\operatorname{wkV}(i)) \preceq W_{\mathrm{wk}}(\operatorname{wkO}(i)) \land W_{\mathrm{wk}}(\operatorname{wkO}(i)) \preceq W_{\mathrm{wk}}(\operatorname{wkV}(i))$$

Equality, not a win: the original already ticks only at its steps. -/
theorem wk_frame_eq (i : Nat) :
    wkVar i = wkOrig i ∧ (frameWork WebKit.webkit (wkVar i)).le (frameWork WebKit.webkit (wkOrig i)) ∧
      (frameWork WebKit.webkit (wkOrig i)).le (frameWork WebKit.webkit (wkVar i)) := by
  have h : wkVar i = wkOrig i := by
    simp only [wkVar, wkOrig, crosses_bounds, crosses_origPoints]
  refine ⟨h, ?_, ?_⟩ <;> rw [h] <;> exact Work.le_refl _

/-- The WebKit runs over $n$ samples from a cycle start.

$$\operatorname{wkRun}(F, n) = [\,W_{\mathrm{wk}}(F(k \bmod 36)) \mid k < n\,]$$

240 samples are 4 s. -/
def wkRun (f : Nat → FrameIn WebKit.WkProp) (n : Nat) : List Work :=
  (List.range n).map fun k => frameWork WebKit.webkit (f (k % 36))

/-- **WebKit: the 4 s screen says `equal`,** with 20 style passes in each arm.

$$\operatorname{screen}\big(\operatorname{toRun}(\operatorname{wkRun}(\operatorname{wkO}, 240)),\ \operatorname{toRun}(\operatorname{wkRun}(\operatorname{wkV}, 240))\big) = \mathrm{ok}(\mathrm{equal}) \ \land\ \operatorname{sumP}(\mathrm{style}, \operatorname{wkRun}(\operatorname{wkV}, 240)) = 20 = \operatorname{sumP}(\mathrm{style}, \operatorname{wkRun}(\operatorname{wkO}, 240))$$

No modelled WebKit gain. -/
theorem wk_run_equal :
    Screen.screen (toRun (wkRun wkOrig 240)) (toRun (wkRun wkVar 240)) = .ok .equal ∧
      sumP .style (wkRun wkVar 240) = 20 ∧ sumP .style (wkRun wkOrig 240) = 20 := by
  have h : wkVar = wkOrig := funext fun i => (wk_frame_eq i).1
  rw [h]
  have h1 : Screen.shapeEq (toRun (wkRun wkOrig 240)) (toRun (wkRun wkOrig 240)) = true := by decide +kernel
  refine ⟨?_, by decide +kernel, by decide +kernel⟩
  unfold Screen.screen
  simp only [h1, Bool.not_true, Bool.false_eq_true, ↓reduceIte, beq_self_eq_true]

/-! ## 6. Golden rows for `pnpm fw engine-check` -/

/-- The relational prediction of one stage over frame pairs $(v, o)$: `=o` if every pair has equal passes, else `≤o`
if every pair has $v \le o$, else `any`.

$$\forall Q \in (\mathrm{Work} \times \mathrm{Work})^{*},\ \forall s:\ \operatorname{relPred}(Q, s) = \begin{cases} \texttt{"=o"} & \forall (v, o) \in Q:\ v.\mathrm{passes}(s) = o.\mathrm{passes}(s) \\ \texttt{"≤o"} & \text{else if } \forall (v, o) \in Q:\ v.\mathrm{passes}(s) \le o.\mathrm{passes}(s) \\ \texttt{"any"} & \text{otherwise} \end{cases}\qquad (Q = [\,] \text{ gives } \texttt{"=o"})$$

`≤o`, not `<o`: whether a scenario's window holds idle frames is not modelled. -/
def relPred (pairs : List (Work × Work)) (s : Stage) : String :=
  if pairs.all (fun p => p.1.passes s == p.2.passes s) then "=o"
  else if pairs.all (fun p => decide (p.1.passes s ≤ p.2.passes s)) then "≤o" else "any"

/-- The Chromium pairs: every sample of a cycle, against the original in both thread cases (main thread with no
layer, compositor with its own layer).

$$\mathrm{crPairs} = [\,(W_{\mathrm{cr}}(\operatorname{crV}(\mathrm{none}, i)), W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \mathrm{none}))) \mid i < 36\,] \mathbin{+\!\!+} [\,(W_{\mathrm{cr}}(\operatorname{crV}(\mathrm{own}, i)), W_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}))) \mid i < 36\,]$$

The rows must hold whichever thread the original runs on. -/
def crPairs : List (Work × Work) :=
  ((List.range 36).map fun i =>
      (frameWork Chromium.chromium (crVar .none i), frameWork Chromium.chromium (crOrig Chromium.lane false .none))) ++
    ((List.range 36).map fun i =>
      (frameWork Chromium.chromium (crVar .own i), frameWork Chromium.chromium (crOrig Chromium.lane true .own)))

/-- The WebKit pairs: every sample of a cycle.

$$\mathrm{wkPairs} = [\,(W_{\mathrm{wk}}(\operatorname{wkV}(i)), W_{\mathrm{wk}}(\operatorname{wkO}(i))) \mid i < 36\,]$$

Equal in every pair. -/
def wkPairs : List (Work × Work) :=
  (List.range 36).map fun i => (frameWork WebKit.webkit (wkVar i), frameWork WebKit.webkit (wkOrig i))

/-- The WebKit prediction: `relPred` over `wkPairs`, weakened from `=o` to `≤o` for every stage but script. The
original's ticks that restyle to an equal value (199.92 ms, 399.90 ms, the `ceil(0)` re-tick) cost style passes and
rendering updates the table does not show, and a WebKit build without step-aware scheduling ticks the original every
frame (v1 measured 240 style passes and 481 paints per 4 s, INFERRED to be such a build); neither arm runs script.

$$\forall s \in \mathrm{Stage}:\ \operatorname{wkPred}(s) = \begin{cases} \texttt{"≤o"} & s \ne \mathrm{script} \land \operatorname{relPred}(\mathrm{wkPairs}, s) = \texttt{"=o"} \\ \operatorname{relPred}(\mathrm{wkPairs}, s) & \text{otherwise} \end{cases}$$

Never claims more than the model shows. -/
def wkPred (s : Stage) : String :=
  let p := relPred wkPairs s
  if s != .script && p == "=o" then "≤o" else p

/-- The variant key in the rewrite.

$$\mathrm{key} = \texttt{"rewrite+?fw=hero.accent:steps"}$$

`meta.target + "+" + search`. -/
def variantKey : String := "rewrite+?fw=hero.accent:steps"

/-- One row in the `engine-check` schema, keys sorted.

$$\operatorname{row}(e, s, c, p) = \{\texttt{base}: \texttt{"rewrite"}, \texttt{countType}: c, \texttt{engine}: e, \texttt{prediction}: p, \texttt{scenario}: \texttt{"swipe-v1"}, \texttt{stage}: s, \texttt{variant}: \mathrm{key}\}$$

A prediction row as `pnpm fw engine-check --rows` reads it. -/
def row (engine stage countType pred : String) : Lean.Json :=
  Lean.Json.mkObj [("base", .str "rewrite"), ("countType", .str countType), ("engine", .str engine),
    ("prediction", .str pred), ("scenario", .str "swipe-v1"), ("stage", .str stage), ("variant", .str variantKey)]

/-- **The golden rows.** Chromium: script, style, layout, paint, commit from `relPred crPairs`; WebKit: the same
stages from `wkPred`.

$$\mathrm{goldenRows} = [\operatorname{row}(\texttt{chromium}, n, c, \operatorname{relPred}(\mathrm{crPairs}, s)) \mid (s, n, c) \in C_{\mathrm{cr}}] \mathbin{+\!\!+} [\operatorname{row}(\texttt{webkit}, n, c, \operatorname{wkPred}(s)) \mid (s, n, c) \in C_{\mathrm{wk}}]$$
$$C_{\mathrm{cr}} = [(\mathrm{script}, \texttt{trace.FireAnimationFrame}), (\mathrm{style}, \texttt{trace.UpdateLayoutTree}), (\mathrm{layout}, \texttt{trace.Layout}), (\mathrm{paint}, \texttt{trace.Paint}), (\mathrm{commit}, \texttt{trace.cc.Commit})],\quad C_{\mathrm{wk}} = [(\mathrm{script}, \texttt{FireAnimationFrame}), (\mathrm{style}, \texttt{RecalculateStyles}), (\mathrm{layout}, \texttt{Layout}), (\mathrm{paint}, \texttt{Paint}), (\mathrm{commit}, \texttt{Composite})]$$
(each $n$ is the stage's name).

The ten predictions CI checks for `hero.accent:steps`. -/
def goldenRows : List Lean.Json :=
  ([(Stage.script, "script", "trace.FireAnimationFrame"), (.style, "style", "trace.UpdateLayoutTree"),
      (.layout, "layout", "trace.Layout"), (.paint, "paint", "trace.Paint"),
      (.commit, "commit", "trace.cc.Commit")].map fun (s, n, c) => row "chromium" n c (relPred crPairs s)) ++
    ([(Stage.script, "script", "FireAnimationFrame"), (.style, "style", "RecalculateStyles"),
      (.layout, "layout", "Layout"), (.paint, "paint", "Paint"), (.commit, "commit", "Composite")].map
      fun (s, n, c) => row "webkit" n c (wkPred s))

/-- The contents of `packages/contracts/golden/engine/hero-accent.jsonl`: one compact JSON row per line.

$$\mathrm{goldenJsonl} = \mathop{\Vert}_{r \in \mathrm{goldenRows}} \big(\operatorname{json}(r) \mathbin{+\!\!+} \texttt{\textbackslash n}\big)$$

The file text the exporter writes. -/
def goldenJsonl : String := String.join (goldenRows.map fun r => r.compress ++ "\n")

#guard relPred crPairs .script == "=o" && relPred crPairs .style == "≤o" && relPred crPairs .layout == "=o"
#guard relPred crPairs .paint == "=o" && relPred crPairs .commit == "any"
#guard wkPred .script == "=o" && wkPred .style == "≤o" && wkPred .layout == "≤o" && wkPred .paint == "≤o"
#guard wkPred .commit == "≤o"
#guard goldenRows.length == 10
#guard relPred [] .style == "=o"
#guard relPred [(Work.zero, paintW 1)] .paint == "≤o" && relPred [(paintW 1, Work.zero)] .paint == "any"
#guard stepEnd (kfs 0) (3332 / 10000) == 1 && stepEnd (kfs 0) (3333 / 10000) == 0 && stepEnd [] 0 == 0
#guard chainVal [] 5 == none && chainVal [(0, 1), (2, 0)] 1 == some 1 && chainVal [(0, 1), (2, 0)] 2 == some 0
#guard (List.range 36).all fun i => [0, 1, 2].all fun j => crosses (bounds j) i == stepAt j i
#guard (List.range 36).all fun i => [0, 1, 2].all fun j => crosses (origPoints j) i == stepAt j i
#guard (List.range 36).all fun i => [0, 1, 2].all fun j => crosses (cleanBounds j) i == stepAt j i
#guard !crossAt 0 1 && crossAt 0 0 && crossAt (19998 / 100) 12 && !crossAt (19998 / 100) 11
#guard (List.range 36).all fun i => [0, 1, 2].all fun j => !chg j i || stepAt j i
#guard (List.range 36).all fun i => [0, 1, 2].all fun j =>
  origVal j (50 * (i : Rat) / 3) == plateau j (50 * (i : Rat) / 3)

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

Neither the original nor the variant reads layout or style, so every stage either frame touches ends dirty
(`Fw.Parts.EndFlags.flagEnd_of_forced_zero`) and `frameWorkE` equals `frameWork`. The verdicts carry over unchanged:
the variant dominates in the main-thread lane, and the compositor and real-Chrome rows stay not `≤`. -/

section EndPass

open Fw.Parts.EndFlags

/-- **Chromium main-thread lane under `frameWorkE`: every frame still `≤`.** For end-flag assignments that are dirty
on every touched stage (the read-free case), the variant is at most the original in every sample of a cycle.

$$\forall \ell,\ \forall i < 36,\ \forall e_v, e_o:\ (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crV}(\ell, i)):\ e_v(s) = \top) \land (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell)):\ e_o(s) = \top) \Rightarrow W^{e_v}_{\mathrm{cr}}(\operatorname{crV}(\ell, i)) \preceq W^{e_o}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell))$$

The frame-end pass changes nothing when no read cleans a flag. -/
theorem cr_main_leE (ℓ : LayerState) (i : Nat) (hi : i < 36) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar ℓ i) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane false ℓ) → eo s = true) :
    (frameWorkE Chromium.chromium (crVar ℓ i) ev).le
      (frameWorkE Chromium.chromium (crOrig Chromium.lane false ℓ) eo) :=
  frameE_le_of_dirty _ ev eo hv ho (cr_main_le ℓ i hi)

/-- **Quiet frames under `frameWorkE`: still strict.**

$$\forall \ell, i,\ \forall e_v, e_o:\ \operatorname{quiet}(i) \land (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crV}(\ell, i)):\ e_v(s) = \top) \land (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell)):\ e_o(s) = \top) \Rightarrow W^{e_v}_{\mathrm{cr}}(\operatorname{crV}(\ell, i)) \prec W^{e_o}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{false}, \ell))$$

An empty frame stays cheaper than one that animates. -/
theorem cr_main_quiet_ltE (ℓ : LayerState) (i : Nat) (hq : quiet i = true) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar ℓ i) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane false ℓ) → eo s = true) :
    (frameWorkE Chromium.chromium (crVar ℓ i) ev).lt
      (frameWorkE Chromium.chromium (crOrig Chromium.lane false ℓ) eo) :=
  frameE_lt_of_dirty _ ev eo hv ho (cr_main_quiet_lt ℓ i hq)

/-- **Compositor lane under `frameWorkE`: still not `≤`.**

$$\forall e_v, e_o:\ (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crV}(\mathrm{own}, 0)):\ e_v(s) = \top) \land (\forall s \in \operatorname{touched}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{true}, \mathrm{own})):\ e_o(s) = \top) \Rightarrow W^{e_v}_{\mathrm{cr}}(\operatorname{crV}(\mathrm{own}, 0)) \not\preceq W^{e_o}_{\mathrm{cr}}(\operatorname{crO}(\mathrm{lane}, \mathrm{true}, \mathrm{own}))$$

The step frame's commit pass stays extra. -/
theorem cr_comp_step_not_leE (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar .own 0) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane true .own) → eo s = true) :
    ¬ (frameWorkE Chromium.chromium (crVar .own 0) ev).le
      (frameWorkE Chromium.chromium (crOrig Chromium.lane true .own) eo) :=
  frameE_not_le_of_dirty _ ev eo hv ho cr_comp_step_not_le.2.2

end EndPass

end Fw.Parts.HeroAccentOpt
