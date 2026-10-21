import Lean.Data.Json
import Fw.Engine
import Fw.Parts.EndFlags
import Fw.Parts.HiddenPause
/-!
# hero.accent boil, variant `steps`: E per sample on the 60 Hz grid, and work per engine

**The part.** While the accent idles (`is-idle`, 2200 ms the first time, 1250 ms later; `2.DyWL8TcE.js` byte
~137916, the accent cycle), three inline `<svg class="accent-svg is-idle-frame is-idle-frame-j">` boxes (`j = 0, 1, 2`)
"boil": each runs `.6s step-end infinite` on its own keyframes (`2.gBuqKVzi.css:1`, bytes 20091-20357 and
21067-21239), restated:

* frame 0: `0%, 33.32% {opacity: 1}  33.33%, to {opacity: 0}`
* frame 1: `0%, 33.32% {opacity: 0}  33.33%, 66.65% {opacity: 1}  66.66%, to {opacity: 0}`
* frame 2: `0%, 66.65% {opacity: 0}  66.66%, to {opacity: 1}`

`step-end` is the per-keyframe easing (`B/core/animation/css/css_animations.cc:425,459-463`@f842f52); it is
`steps(1, end)`, `⌊ t ⌋` on the interval's local progress (`ui/gfx/animation/keyframe/timing_function.cc:98-113`@f842f52),
and the interval is the one with `p ∈ [from, to)` (`B/core/animation/interpolation_effect.cc:27-41`).
So the value at iteration progress `p` is the value of the last keyframe with offset `≤ p` (`stepEnd`). CONFIRMED.

**The variant `steps`.** Per frame box, a chain of zero-duration, `fill: forwards` animations with delays, one per
plateau boundary of every cycle (`chain`, `bounds`): a later animation in the list overrides an earlier one, so the
box shows the value of the last step whose delay has passed (`chainVal`). A zero-duration animation is never in its
active phase: Chromium services it at its delay and then never again (`B/core/animation/keyframe_effect.cc:848-857`),
WebKit ticks it at its delay (`AnimationEffect.cpp:385-402`@862f17d). No script. The chain starts with the same
`is-idle` class change as the original and covers the idle window (`N` cycles, `600 N ≥` idle ms).

**What is proved.**
* Vision, class E:
  * `origVal_plateau`: each original frame is a three-plateau function of the local time `u = (t - S) mod 600` ms.
  * `exact_chain_vis`: the chain with the exact boundaries 199.98 ms and 399.96 ms equals the original at *every*
    elapsed time in the window, for every start time: no phase premise.
  * `clean_chain_grid` (the start-offset premise, R5): the chain with round boundaries 200 ms and 400 ms equals the
    original at every 60 Hz sample `t_k = 50k/3` ms inside the chain window (`t_k - S = 600m + u`, `m < N`,
    `0 ≤ u < 600`), provided the start `S = 50s/3 + φ` has phase `φ = 0` or `1/25 < φ < 50/3` ms
    (the "if" direction only). `clean_chain_phase_bad` shows a sample that differs at
    `φ = 1/50`. `S` is the start time read from `document.timeline` (research note 10-18-engine-gaps, R5).
* Work, on the grid with the start on a sample (`φ = 0`, 36 frames per 600 ms cycle):
  * Chromium, original on the main thread (`validTarget = false`): every frame `W(v) ≼ W(o)` and strictly on
    the 33 quiet frames of 36 (`cr_main_le`, `cr_main_quiet_lt`); 4 s run: `cr_main_run_dominates`.
  * Chromium, original on the compositor (INFERRED from source: an outer `<svg>` with a current opacity animation is
    stacked, has a paint layer and gets `kActiveOpacityAnimation`, `B/core/paint/compositing/compositing_reason_finder.cc:421-432,586-593`,
    `B/core/layout/layout_box.cc:554-562`, `B/core/animation/css/css_animations.cc:2226-2228`): a trade, not a win.
    Style passes per 4 s drop from 240 to 20, but every step frame adds a commit the compositor original never pays
    (`cr_comp_step_not_le`, `cr_comp_window`, `cr_comp_run_mixed`); in real Chrome the original's main thread is idle
    and the variant's is not (`cr_realChrome_step_worse`).
  * WebKit: the original ticks only at its steps (`KeyframeEffect.cpp:2670-2722`@862f17d), in the same frames as the
    variant, with the same value changes: `W(v) = W(o)` in every frame (`wk_frame_eq`, `wk_run_equal`). Equality,
    not a win. Ticks that restyle to an equal value are not in the WebKit table, so the rows predict `≤o` there.
* Golden rows for `pnpm fw engine-check` (`goldenRows`, `packages/contracts/golden/engine/hero-accent.jsonl`).

**Premises** (hypotheses or named model choices): both arms start at the same `S` (INFERRED: same class change);
the phase `φ` for the round chain (R5); IEEE rounding of delays and progress (R8-like, not modelled); the chain
covers the idle window; Chromium's 40 ms pre-wake (`B/core/animation/document_timeline.cc:111-135`) services no
fraction change and so dirties no style (INFERRED, `keyframe_effect_model.cc:219-220`); the start frame `k = 0` is
modelled as a cycle start. Exact arithmetic: `Rat` ms for times and opacity, `Nat` for frames and counts.
-/
namespace Fw.Parts.HeroAccentOpt

open Fw.Engine

/-! ## 1. The original: three step-end keyframe lists -/

/-- The keyframes of boil frame `j` as (offset, opacity) pairs, offsets as exact fractions of the 600 ms cycle; no
frame for `j ≥ 3`.

The snapshot's three `@keyframes svelte-1fn2go6-idle-j`, restated. -/
def kfs : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (3332 / 10000, 1), (3333 / 10000, 0), (1, 0)]
  | 1 => [(0, 0), (3332 / 10000, 0), (3333 / 10000, 1), (6665 / 10000, 1), (6666 / 10000, 0), (1, 0)]
  | 2 => [(0, 0), (6665 / 10000, 0), (6666 / 10000, 1), (1, 1)]
  | _ => []

/-- **Step-end evaluation** of a keyframe list at iteration progress `p`: the value of the last keyframe (in list
order) whose offset is at most `p`; 0 when there is none.

On a sorted list this is the from-value of the interval `[o_i, o_(i+1))` that holds `p`, which is what
`steps(1, end)` shows. -/
def stepEnd (kf : List (Rat × Rat)) (p : Rat) : Rat :=
  kf.foldl (fun acc k => if k.1 ≤ p then k.2 else acc) 0

/-- The original's opacity of frame `j` at local time `u` ms into a cycle.

The value the original shows `u` ms after a cycle start. -/
def origVal (j : Nat) (u : Rat) : Rat := stepEnd (kfs j) (u / 600)

/-- The three plateaus, in ms: frame 0 shows before 199.98, frame 1 on `[199.98, 399.96)`, frame 2 from 399.96 on.

Which frame is visible at each moment of a cycle. -/
def plateau (j : Nat) (u : Rat) : Rat :=
  match j with
  | 0 => if u < 19998 / 100 then 1 else 0
  | 1 => if 19998 / 100 ≤ u ∧ u < 39996 / 100 then 1 else 0
  | 2 => if 39996 / 100 ≤ u then 1 else 0
  | _ => 0

/-- **The original is a three-plateau function.** For every frame `j` and every local time `u ≥ 0` the step-end
value equals the plateau value (for `u ≥ 600` the last keyframe holds, which agrees with the last plateau).

The 0.06 ms keyframe pairs at 33.32/33.33 % and 66.65/66.66 % only move each switch to 199.98 ms and 399.96 ms. -/
theorem origVal_plateau (j : Nat) (u : Rat) (h0 : 0 ≤ u) : origVal j u = plateau j u := by
  match j with
  | 0 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | 1 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | 2 => simp only [origVal, kfs, stepEnd, List.foldl, plateau]; grind
  | _ + 3 => simp [origVal, kfs, stepEnd, plateau]

/-! ## 2. The variant: a chain of zero-duration, fill-forwards steps -/

/-- One step of the chain fold at elapsed time `e`: a step `(d, v)` whose delay has passed (`d ≤ e`) replaces the
shown value.

A later animation in the list wins over an earlier one. -/
def stepF (e : Rat) (acc : Option Rat) (s : Rat × Rat) : Option Rat := if s.1 ≤ e then some s.2 else acc

/-- **The chain's value** at elapsed time `e` (ms since the shared start `S`): the value of the last step in list
order whose delay is at most `e`; none (the box's own style) before the first.

What a box with the animation list `C` shows `e` ms after the start. -/
def chainVal (cs : List (Rat × Rat)) (e : Rat) : Option Rat := cs.foldl (stepF e) none

/-- The exact step offsets of frame `j` within one cycle, as (delay ms, opacity).

Every value change of the original, at the original's own boundaries. -/
def bounds : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (19998 / 100, 0)]
  | 1 => [(0, 0), (19998 / 100, 1), (39996 / 100, 0)]
  | 2 => [(0, 0), (39996 / 100, 1)]
  | _ => []

/-- The round step offsets of frame `j` (200 ms and 400 ms instead of 199.98 ms and 399.96 ms).

The chain a hand-written port would use; it needs the phase premise. -/
def cleanBounds : Nat → List (Rat × Rat)
  | 0 => [(0, 1), (200, 0)]
  | 1 => [(0, 0), (200, 1), (400, 0)]
  | 2 => [(0, 0), (400, 1)]
  | _ => []

/-- Cycle `m` of a chain: every offset shifted by `600m` ms.

The steps of one 600 ms cycle. -/
def cycle (bs : List (Rat × Rat)) (m : Nat) : List (Rat × Rat) := bs.map fun s => (600 * (m : Rat) + s.1, s.2)

/-- The chain of `N` cycles, cycle 0 first.

The animation list the variant puts on one frame box. -/
def chain (bs : List (Rat × Rat)) : Nat → List (Rat × Rat)
  | 0 => []
  | n + 1 => chain bs n ++ cycle bs n

/-- A fold over steps whose delays all lie after `e` changes nothing.

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

Cycle `m` waits until `600m` ms. -/
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

The offset-0 step of cycle `m` hides every earlier cycle. -/
theorem cycle_override (v : Rat) (rest : List (Rat × Rat)) (m : Nat) (e : Rat) (acc : Option Rat)
    (he : 600 * (m : Rat) ≤ e) :
    (cycle ((0, v) :: rest) m).foldl (stepF e) acc = (cycle ((0, v) :: rest) m).foldl (stepF e) none := by
  have h : 600 * (m : Rat) + 0 ≤ e := by grind
  simp only [cycle, List.map_cons, List.foldl_cons, stepF, h, ↓reduceIte]

/-- **The chain shows the current cycle.** If every offset is non-negative and the list starts with an offset-0
step, then for `m < n` and `600m ≤ e < 600(m+1)` the `n`-cycle chain shows what cycle `m` alone shows.

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

The exact boundaries are the plateau boundaries. -/
theorem cycle_exact (j : Nat) (hj : j < 3) (m : Nat) (u : Rat) (h0 : 0 ≤ u) :
    chainVal (cycle (bounds j) m) (600 * (m : Rat) + u) = some (plateau j u) := by
  match j, hj with
  | 0, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind
  | 1, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind
  | 2, _ => simp only [chainVal, cycle, bounds, List.map, List.foldl, stepF, plateau]; grind

/-- The round plateaus (boundaries 200 ms and 400 ms).

What the round chain shows. -/
def cleanPlateau (j : Nat) (u : Rat) : Rat :=
  match j with
  | 0 => if u < 200 then 1 else 0
  | 1 => if 200 ≤ u ∧ u < 400 then 1 else 0
  | 2 => if 400 ≤ u then 1 else 0
  | _ => 0

/-- One cycle of the round chain shows the round plateau value.

The round chain switches at 200 and 400 ms. -/
theorem cycle_clean (j : Nat) (hj : j < 3) (m : Nat) (u : Rat) (h0 : 0 ≤ u) :
    chainVal (cycle (cleanBounds j) m) (600 * (m : Rat) + u) = some (cleanPlateau j u) := by
  match j, hj with
  | 0, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind
  | 1, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind
  | 2, _ => simp only [chainVal, cycle, cleanBounds, List.map, List.foldl, stepF, cleanPlateau]; grind

/-- **Vision, exact chain (class E, no phase premise).** For every frame `j < 3`, every chain length `N`, every
cycle `m < N` and every local time `0 ≤ u < 600` ms, the exact chain at elapsed time `600m + u` shows the
original's value at local time `u`.

With the exact boundaries the variant equals the original at every instant of the window, whatever the frame grid. -/
theorem exact_chain_vis (j : Nat) (hj : j < 3) (N m : Nat) (u : Rat) (hm : m < N) (h0 : 0 ≤ u) (h1 : u < 600) :
    chainVal (chain (bounds j) N) (600 * (m : Rat) + u) = some (origVal j u) := by
  rw [origVal_plateau j u h0, ← cycle_exact j hj m u h0]
  match j, hj with
  | 0, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 1, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)
  | 2, _ => exact chain_eq_cycle _ _ (by simp; grind) N m _ hm (by grind) (by grind)

/-- The round plateaus agree with the original's outside the two gaps `[199.98, 200)` and `[399.96, 400)`.

Only a sample inside a 0.02 or 0.04 ms gap can tell the round chain apart. -/
theorem clean_eq_off_gaps (j : Nat) (u : Rat) (g1 : u < 19998 / 100 ∨ 200 ≤ u) (g2 : u < 39996 / 100 ∨ 400 ≤ u) :
    cleanPlateau j u = plateau j u := by
  match j with
  | 0 => simp only [cleanPlateau, plateau]; grind
  | 1 => simp only [cleanPlateau, plateau]; grind
  | 2 => simp only [cleanPlateau, plateau]; grind
  | _ + 3 => rfl

/-- No integer lies strictly between `a` and `a + 1`.

The integer step used by the grid argument. -/
theorem no_int_between (i a : Int) (h1 : (a : Rat) < i) (h2 : (i : Rat) < a + 1) : False := by
  have h1' : a < i := by exact_mod_cast h1
  have h2' : i < a + 1 := by exact_mod_cast h2
  omega

/-- **Vision on the 60 Hz grid, round chain (class E per sample, start-offset premise R5).** Let the shared start be
`S = 50s/3 + φ` ms with `s ∈ ℤ` and phase `φ = 0` or `1/25 < φ < 50/3`. Then for every
frame `j < 3`, chain length `N`, sample `t_k = 50k/3` (`k ∈ ℤ`), cycle `m < N` and local time
`0 ≤ u < 600` with `t_k - S = 600m + u`, the round chain shows the original's value at the sample.

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

/-- **The phase premise is needed.** With `s = 0`, `φ = 1/50` ms, sample `k = 12` and one cycle, the elapsed
time is `600 · 0 + 199.98`; there the round chain still shows frame 0 while the original has switched it off.

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

/-- Whether frame `j` is shown at sample `i` of a cycle (`t = 50i/3` ms after the cycle start).

Frame 0 on samples 0-11, frame 1 on 12-23, frame 2 on 24-35. -/
def sv : Nat → Nat → Bool
  | 0, i => decide (i < 12)
  | 1, i => decide (12 ≤ i) && decide (i < 24)
  | 2, i => decide (24 ≤ i)
  | _, _ => false

#guard ((List.range 36).map (sv 0)).count true == 12
#guard (List.range 36).all fun i => [0, 1, 2].countP (sv · i) == 1

/-- **The sampled original.** At sample `i` the original's value is 1 exactly when `sv` says so.

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

/-- Whether a step at local offset `b` ms is applied first at sample `i`: `b ∈ (50(i-1)/3, 50i/3]`.

The frame in which the engine sees the step (the offsets here lie in `[0, 399.96]`, so for `i = 0` only an
offset-0 step of the same cycle qualifies). -/
def crossAt (b : Rat) (i : Nat) : Bool := decide (50 * (i : Rat) / 3 - 50 / 3 < b ∧ b ≤ 50 * (i : Rat) / 3)

/-- Whether any step of a list is applied first at sample `i`.

The frames in which a box's chain fires. -/
def crosses (bs : List (Rat × Rat)) (i : Nat) : Bool := bs.any fun s => crossAt s.1 i

/-- The sample at which a step at offset `b` ms fires, for the five offsets in play: exactly sample `c`.

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

/-- The step frames of frame `j`'s chain within a cycle.

Three step frames per 36-frame cycle at most. -/
def stepAt : Nat → Nat → Bool
  | 0, i => i == 0 || i == 12
  | 1, i => i == 0 || i == 12 || i == 24
  | 2, i => i == 0 || i == 24
  | _, _ => false

/-- **The chain fires on the step frames.** For every frame `j` and sample `i`, a step of the exact chain is first
seen at sample `i` iff `stepAt` says so.

The variant's work frames, from its delays. -/
theorem crosses_bounds (j i : Nat) : crosses (bounds j) i = stepAt j i := by
  obtain ⟨a0, -, a2, -, a4⟩ := crossAt_vals i
  match j with
  | 0 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a2, stepAt]
  | 1 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a2, a4, stepAt, Bool.or_assoc]
  | 2 => simp only [crosses, bounds, List.any_cons, List.any_nil, Bool.or_false, a0, a4, stepAt]
  | _ + 3 => rfl

/-- The original's step points of frame `j` in ms within a cycle: `600 o` for every keyframe offset `o < 1` (the
offset-1 keyframe is the next cycle's 0).

Where WebKit schedules the original's ticks (`KeyframeEffect.cpp:2670-2722`@862f17d). -/
def origPoints (j : Nat) : List (Rat × Rat) := ((kfs j).filter fun k => decide (k.1 < 1)).map fun k => (600 * k.1, k.2)

/-- **The original ticks on the same frames.** For every frame `j` and sample `i`, a step point of the original is
first seen at sample `i` iff the variant's chain fires there (199.92 and 199.98 ms fall in one frame, as do 399.90
and 399.96 ms).

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

/-- Whether frame `j`'s value changes at sample `i` (against sample `i - 1`, cyclically: sample 0 against 35).

The start frame is modelled as a cycle start (one value change more for the variant than at the real start). -/
def chg (j i : Nat) : Bool := sv j i != sv j ((i + 35) % 36)

/-- **A value changes only on a step frame.**

The chain never misses a change. -/
theorem chg_step : ∀ j < 3, ∀ i < 36, chg j i = true → stepAt j i = true := by decide

/-! ## 4. Chromium -/

open Fw.Engine.Chromium in
/-- The original's three running animations: opacity on boxes 0, 1, 2 with layer state `ℓ`; `valid` is whether the
target's compositing state is valid (a direct compositing reason).

The three `idle-j` animations. -/
def crAnims (valid : Bool) (ℓ : LayerState) : List Chromium.CrAnim :=
  [0, 1, 2].map fun j => { elem := j, props := [.css .opacity], layer := ℓ, validTarget := valid }

/-- The original's frame in mode `m`: the same every frame (an active non-composited animation is serviced every
frame, `B/core/animation/animation.cc:3390-3394`; a composited one ticks on the compositor).

What the original costs Chromium in any frame. -/
def crOrig (m : Chromium.CrMode) (valid : Bool) (ℓ : LayerState) : FrameIn Chromium.CrProp :=
  Chromium.animFrame m (crAnims valid ℓ)

open Fw.Engine.Chromium in
/-- The variant's change on box `j` at a step frame `i`: an opacity change if the value changes, else a same-value
restyle (the table's style-only row, a custom property with no readers).

A step that fires restyles its box; it repaints only if the value moved. -/
def crChange (ℓ : LayerState) (j i : Nat) : Change CrProp :=
  if chg j i then ⟨j, .css .opacity, ℓ⟩ else ⟨j, .custom j [], ℓ⟩

/-- The variant's Chromium frame at sample `i`: one change per box whose chain fires, nothing else.

Quiet frames are empty. -/
def crVar (ℓ : LayerState) (i : Nat) : FrameIn Chromium.CrProp :=
  ⟨0, 0, 0, 0, ([0, 1, 2].filter (stepAt · i)).map (crChange ℓ · i), 0⟩

/-- **Chromium, original on the main thread: every frame `≤`.** For every layer state and every sample of a cycle,
the variant's frame work is at most the original's when the original's targets are not compositable.

Each firing step is one of the restyles the original does anyway. -/
theorem cr_main_le : ∀ ℓ : LayerState, ∀ i < 36,
    (frameWork Chromium.chromium (crVar ℓ i)).le (frameWork Chromium.chromium (crOrig Chromium.lane false ℓ)) := by
  intro ℓ i hi
  apply frame_le_union
  revert i
  cases ℓ <;> decide

/-- Whether no chain fires at sample `i`.

33 of 36 samples per cycle. -/
def quiet (i : Nat) : Bool := [0, 1, 2].all fun j => !stepAt j i

#guard (List.range 36).countP quiet == 33

/-- **Chromium, original on the main thread: strictly less on quiet frames.**

Between steps the variant does no work at all; the original restyles three boxes. -/
theorem cr_main_quiet_lt (ℓ : LayerState) (i : Nat) (hq : quiet i = true) :
    (frameWork Chromium.chromium (crVar ℓ i)).lt (frameWork Chromium.chromium (crOrig Chromium.lane false ℓ)) := by
  have he : crVar ℓ i = ⟨0, 0, 0, 0, [], 0⟩ := by
    simp only [quiet, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true, Bool.not_eq_true'] at hq
    simp [crVar, List.filter, hq.1, hq.2.1, hq.2.2]
  rw [he, ← Work.ltb_iff]
  cases ℓ <;> decide

/-- The variant's and the original's Chromium runs over `n` samples from a cycle start, in mode `m`.

240 samples are 4 s. -/
def runV (ℓ : LayerState) (n : Nat) : List Work := (List.range n).map fun k => frameWork Chromium.chromium (crVar ℓ (k % 36))

/-- See `runV`.

The original's run: the same frame `n` times. -/
def runO (m : Chromium.CrMode) (valid : Bool) (ℓ : LayerState) (n : Nat) : List Work :=
  (List.range n).map fun _ => frameWork (Chromium.chromiumAt m) (crOrig m valid ℓ)

/-- **Chromium, original on the main thread: the 4 s run dominates.** Over 240 samples (4 s) the screen, with the
original as baseline, answers `dominates`.

Style and paint once per plateau instead of every frame. -/
theorem cr_main_run_dominates (ℓ : LayerState) :
    Screen.screen (toRun (runO Chromium.lane false ℓ 240)) (toRun (runV ℓ 240)) = .ok .dominates := by
  apply run_dominates
  · cases ℓ <;> decide +kernel
  · cases ℓ <;> decide +kernel

/-- **Chromium, original on the compositor: a step frame is not `≤`.** At the cycle start (sample 0) the variant
commits its own-layer opacity change, which the compositor-run original never does.

Moving the boil to the main thread costs a commit per step. -/
theorem cr_comp_step_not_le :
    (frameWork Chromium.chromium (crVar .own 0)).passes .commit = 1 ∧
      (frameWork Chromium.chromium (crOrig Chromium.lane true .own)).passes .commit = 0 ∧
      ¬ (frameWork Chromium.chromium (crVar .own 0)).le (frameWork Chromium.chromium (crOrig Chromium.lane true .own)) := by
  refine ⟨by decide, by decide, ?_⟩
  rw [← Work.leb_iff]
  decide

/-- Sum of one stage's passes over a run.

A 4 s count per stage. -/
def sumP (s : Stage) (ws : List Work) : Nat := (ws.map fun w => w.passes s).sum

/-- **Chromium, original on the compositor: the 4 s counts.** Over 240 samples the variant has 20 style passes
against 240, 20 commits against 0, and no compositor ticks against 240.

A trade in the lane: 220 fewer style passes, 20 more commits. -/
theorem cr_comp_window :
    sumP .style (runV .own 240) = 20 ∧ sumP .style (runO Chromium.lane true .own 240) = 240 ∧
      sumP .commit (runV .own 240) = 20 ∧ sumP .commit (runO Chromium.lane true .own 240) = 0 ∧
      sumP .comp (runV .own 240) = 0 ∧ sumP .comp (runO Chromium.lane true .own 240) = 240 := by
  decide +kernel

/-- **Chromium, original on the compositor: the screen says `mixed`.**

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

Outside the lane the variant is worse on the main thread. -/
theorem cr_realChrome_step_worse : ∀ i ∈ [0, 12, 24],
    (frameWork (Chromium.chromiumAt Chromium.realChrome) (crOrig Chromium.realChrome true .own)).passes .style = 0 ∧
      (frameWork (Chromium.chromiumAt Chromium.realChrome) (crVar .own i)).passes .style = 1 := by
  decide

/-! ## 5. WebKit -/

/-- A value change of box `j` under WebKit: opacity between 0 and 1 crosses 1 (`StyleDifference.cpp:208-214`@862f17d),
on a box with no own layer.

The only modelled WebKit change of the boil. -/
def wkChange (j : Nat) : Change WebKit.WkProp := ⟨j, .opacityCross1, .none⟩

/-- A WebKit frame at sample `i` from a tick rule: box `j` contributes its value change when it ticks and its value
moves; a tick to an equal value has diff `equal` and no stages, so it is left out.

Steps are refused acceleration (`KeyframeEffect.cpp:2011`@862f17d), and so is a zero-duration chain: both run in the
web process. -/
def wkFrame (tick : Nat → Nat → Bool) (i : Nat) : FrameIn WebKit.WkProp :=
  ⟨0, 0, 0, 0, ([0, 1, 2].filter fun j => tick j i && chg j i).map wkChange, 0⟩

/-- The original's WebKit frame at sample `i`: it ticks where a keyframe step point is crossed.

WebKit@862f17d schedules the next tick at the next step. -/
def wkOrig (i : Nat) : FrameIn WebKit.WkProp := wkFrame (fun j i => crosses (origPoints j) i) i

/-- The variant's WebKit frame at sample `i`: it ticks where its chain fires.

A zero-duration step ticks once, at its delay. -/
def wkVar (i : Nat) : FrameIn WebKit.WkProp := wkFrame (fun j i => crosses (bounds j) i) i

/-- **WebKit: equal work in every frame.** For every sample, the variant's WebKit frame is the original's, so the
work is equal.

Equality, not a win: the original already ticks only at its steps. -/
theorem wk_frame_eq (i : Nat) :
    wkVar i = wkOrig i ∧ (frameWork WebKit.webkit (wkVar i)).le (frameWork WebKit.webkit (wkOrig i)) ∧
      (frameWork WebKit.webkit (wkOrig i)).le (frameWork WebKit.webkit (wkVar i)) := by
  have h : wkVar i = wkOrig i := by
    simp only [wkVar, wkOrig, crosses_bounds, crosses_origPoints]
  refine ⟨h, ?_, ?_⟩ <;> rw [h] <;> exact Work.le_refl _

/-- The WebKit runs over `n` samples from a cycle start.

240 samples are 4 s. -/
def wkRun (f : Nat → FrameIn WebKit.WkProp) (n : Nat) : List Work :=
  (List.range n).map fun k => frameWork WebKit.webkit (f (k % 36))

/-- **WebKit: the 4 s screen says `equal`,** with 20 style passes in each arm.

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

/-- The relational prediction of one stage over frame pairs `(v, o)`: `=o` if every pair has equal passes, else `≤o`
if every pair has `v ≤ o`, else `any`.

`≤o`, not `<o`: whether a scenario's window holds idle frames is not modelled. -/
def relPred (pairs : List (Work × Work)) (s : Stage) : String :=
  if pairs.all (fun p => p.1.passes s == p.2.passes s) then "=o"
  else if pairs.all (fun p => decide (p.1.passes s ≤ p.2.passes s)) then "≤o" else "any"

/-- The Chromium pairs: every sample of a cycle, against the original in both thread cases (main thread with no
layer, compositor with its own layer).

The rows must hold whichever thread the original runs on. -/
def crPairs : List (Work × Work) :=
  ((List.range 36).map fun i =>
      (frameWork Chromium.chromium (crVar .none i), frameWork Chromium.chromium (crOrig Chromium.lane false .none))) ++
    ((List.range 36).map fun i =>
      (frameWork Chromium.chromium (crVar .own i), frameWork Chromium.chromium (crOrig Chromium.lane true .own)))

/-- The WebKit pairs: every sample of a cycle.

Equal in every pair. -/
def wkPairs : List (Work × Work) :=
  (List.range 36).map fun i => (frameWork WebKit.webkit (wkVar i), frameWork WebKit.webkit (wkOrig i))

/-- The WebKit prediction: `relPred` over `wkPairs`, weakened from `=o` to `≤o` for every stage but script. The
original's ticks that restyle to an equal value (199.92 ms, 399.90 ms, the `ceil(0)` re-tick) cost style passes and
rendering updates the table does not show, and a WebKit build without step-aware scheduling ticks the original every
frame (v1 measured 240 style passes and 481 paints per 4 s, INFERRED to be such a build); neither arm runs script.

Never claims more than the model shows. -/
def wkPred (s : Stage) : String :=
  let p := relPred wkPairs s
  if s != .script && p == "=o" then "≤o" else p

/-- The variant key in the rewrite.

`meta.target + "+" + search`. -/
def variantKey : String := "rewrite+?fw=hero.accent:steps"

/-- One row in the `engine-check` schema, keys sorted.

A prediction row as `pnpm fw engine-check --rows` reads it. -/
def row (engine stage countType pred : String) : Lean.Json :=
  Lean.Json.mkObj [("base", .str "rewrite"), ("countType", .str countType), ("engine", .str engine),
    ("prediction", .str pred), ("scenario", .str "swipe-v1"), ("stage", .str stage), ("variant", .str variantKey)]

/-- **The golden rows.** Chromium: script, style, layout, paint, commit from `relPred crPairs`; WebKit: the same
stages from `wkPred`.

(each `n` is the stage's name).

The ten predictions CI checks for `hero.accent:steps`. -/
def goldenRows : List Lean.Json :=
  ([(Stage.script, "script", "trace.FireAnimationFrame"), (.style, "style", "trace.UpdateLayoutTree"),
      (.layout, "layout", "trace.Layout"), (.paint, "paint", "trace.Paint"),
      (.commit, "commit", "trace.cc.Commit")].map fun (s, n, c) => row "chromium" n c (relPred crPairs s)) ++
    ([(Stage.script, "script", "FireAnimationFrame"), (.style, "style", "RecalculateStyles"),
      (.layout, "layout", "Layout"), (.paint, "paint", "Paint"), (.commit, "commit", "Composite")].map
      fun (s, n, c) => row "webkit" n c (wkPred s))

/-- The contents of `packages/contracts/golden/engine/hero-accent.jsonl`: one compact JSON row per line.

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

The frame-end pass changes nothing when no read cleans a flag. -/
theorem cr_main_leE (ℓ : LayerState) (i : Nat) (hi : i < 36) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar ℓ i) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane false ℓ) → eo s = true) :
    (frameWorkE Chromium.chromium (crVar ℓ i) ev).le
      (frameWorkE Chromium.chromium (crOrig Chromium.lane false ℓ) eo) :=
  frameE_le_of_dirty _ ev eo hv ho (cr_main_le ℓ i hi)

/-- **Quiet frames under `frameWorkE`: still strict.**

An empty frame stays cheaper than one that animates. -/
theorem cr_main_quiet_ltE (ℓ : LayerState) (i : Nat) (hq : quiet i = true) (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar ℓ i) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane false ℓ) → eo s = true) :
    (frameWorkE Chromium.chromium (crVar ℓ i) ev).lt
      (frameWorkE Chromium.chromium (crOrig Chromium.lane false ℓ) eo) :=
  frameE_lt_of_dirty _ ev eo hv ho (cr_main_quiet_lt ℓ i hq)

/-- **Compositor lane under `frameWorkE`: still not `≤`.**

The step frame's commit pass stays extra. -/
theorem cr_comp_step_not_leE (ev eo : Stage → Bool)
    (hv : ∀ s, s ∈ touched Chromium.chromium (crVar .own 0) → ev s = true)
    (ho : ∀ s, s ∈ touched Chromium.chromium (crOrig Chromium.lane true .own) → eo s = true) :
    ¬ (frameWorkE Chromium.chromium (crVar .own 0) ev).le
      (frameWorkE Chromium.chromium (crOrig Chromium.lane true .own) eo) :=
  frameE_not_le_of_dirty _ ev eo hv ho cr_comp_step_not_le.2.2

end EndPass

/-! ## 7. The draw window: only the visible copy runs the stroke draw (`draw-one`, ledger n=15 sub-change)

While the word is drawn out or in (`.drawingOut` / `.drawingIn`, 0.9 s each), the rule
`:is(.drawingIn, .drawingOut) .idleFrame {opacity: 0}` followed by `.frame0 {opacity: 1}`
(`apps/site/src/parts/hero.accent/accent.module.css:76-83`) leaves copy 0 opaque and copies 1 and 2 at opacity 0 for the
whole window. Yet `.drawingIn .path` / `.drawingOut .path` (`:52-61`) start the `strokeIn` / `strokeOut` dash-offset
animation on all three copies. Variant `draw-one` starts it on copy 0 only. A copy at opacity 0 is dropped by
`Fw.Engine.visible`, so `Fw.Parts.HiddenPause.hidden_pause_eq` gives the same visible scene for any value of the
hidden copies' dash offset (class E). The saving is work, not look: in WebKit a dash-offset change forces a layout of
each animated SVG (`StyleDifference.cpp:157-163`@862f17d, CONFIRMED), so 3 animated paths per draw frame become 1. The
count is a decision (`animates`); how much layout time it saves is measured on CI, not modelled here. -/

open Fw.Parts.HiddenPause (Tmpl inst HiddenOrStill hidden_pause_eq hiddenPause_visSame)

/-- The two variants of the draw window: every copy animates (the original), or only the opaque one.

The faithful page or `hero.accent:draw-one`. -/
inductive DrawVariant where
  | faithful
  | drawOne
  deriving DecidableEq, Repr

/-- The accent's phase: idle (the boil) or drawing (`.drawingOut` / `.drawingIn`).

The word is either at rest or being drawn. -/
inductive Phase where
  | idle
  | drawing
  deriving DecidableEq, Repr

/-- **Opacity of copy `j` during the draw window** (`accent.module.css:76-83`): copy 0 is 1, every other copy 0.

Only the first scribble shows while a word is drawn. -/
def drawAlpha (j : Nat) : Rat := if j = 0 then 1 else 0

/-- **The decision**: does copy `j` run the stroke-dashoffset animation in the draw window? The original: always.
`draw-one`: exactly when the copy is not transparent.

A copy gets the draw animation only if it can be seen, or if the page is the faithful one. -/
def animates : DrawVariant → Nat → Bool
  | .faithful, _ => true
  | .drawOne, j => decide (drawAlpha j ≠ 0)

/-- **The animation exists only in the draw window.** Copy `j` runs the stroke animation in `phase` under `v`.

Outside the draw window (`.idle .path` has no dash pattern) no variant runs it. -/
def strokeAnimated (v : DrawVariant) (phase : Phase) (j : Nat) : Bool :=
  match phase with
  | .idle => false
  | .drawing => animates v j

/-- **Which copies animate.** Under `draw-one` exactly copy 0 does.

The decision reduces to "the first copy only". -/
theorem drawOne_animates_iff (j : Nat) : animates .drawOne j = true ↔ j = 0 := by
  unfold animates drawAlpha
  by_cases h : j = 0 <;> simp [h]

/-- **The faithful page animates every copy.**

Nothing changes for the original. -/
theorem faithful_animates (j : Nat) : animates .faithful j = true := rfl

/-- **Skipped copies are exactly the transparent ones.** For any copy, `draw-one` leaves it still iff its opacity in
the window is 0.

The variant never stops the animation of a copy that paints. -/
theorem drawOne_still_iff (j : Nat) : animates .drawOne j = false ↔ drawAlpha j = 0 := by
  unfold animates
  by_cases h : drawAlpha j = 0 <;> simp [h]

/-- **Outside the draw window both variants run nothing.**

Idle frames are the same in the original and `draw-one`. -/
theorem idle_same (j : Nat) : strokeAnimated .drawOne .idle j = strokeAnimated .faithful .idle j := rfl

/-- The number of the three copies that run the stroke animation in a phase.

How many SVG paths the engine restyles per draw frame. -/
def animatedCount (v : DrawVariant) (phase : Phase) : Nat :=
  ([0, 1, 2].filter fun j => strokeAnimated v phase j).length

/-- **The work, as a count.** Three animated paths per draw frame become one; idle frames run none in either.

The saving is two of three paths per draw frame. -/
theorem animatedCount_values :
    animatedCount .faithful .drawing = 3 ∧ animatedCount .drawOne .drawing = 1 ∧
    animatedCount .faithful .idle = 0 ∧ animatedCount .drawOne .idle = 0 := by
  decide

/-- **The saving never exceeds the original.** Per phase `draw-one` animates at most as many copies.

The variant never adds work. -/
theorem animatedCount_le (phase : Phase) : animatedCount .drawOne phase ≤ animatedCount .faithful phase := by
  cases phase <;> decide

/-! ### The picture is the same -/

/-- The look of copy `j` in the draw window, as a box: the same geometry for all copies, opacity `drawAlpha j`, and
the dash offset `off` as its one paint value.

What the scene holds for one scribble when its dash offset reads `off`. -/
def copyLook (r : Rect) (j : Nat) (off : Rat) : BoxVis :=
  { box := r, ink := r, paint := [("stroke-dashoffset", toString off)], xf := ⟨1, 0, 0, 1, 0, 0⟩,
    alpha := drawAlpha j, clip := none, filter := [], order := j }

/-- The draw window's scene as a template over the hidden copies' dash offset `a`. Copy 0 carries its own offset `d0`
(both pages animate it the same way); copies 1 and 2 read `a`.

The three scribbles, with the value the variant may change in the last two. -/
def drawTmpl (r : Rect) (d0 : Rat) : Tmpl Rat :=
  [("copy0", fun _ => copyLook r 0 d0), ("copy1", fun a => copyLook r 1 a), ("copy2", fun a => copyLook r 2 a)]

/-- Every box of the draw template is constant in `a` or dropped by `visible`.

Copy 0 ignores the hidden copies' offset, copies 1 and 2 have opacity 0. -/
theorem drawTmpl_hidden (vp r : Rect) (d0 : Rat) : HiddenOrStill vp (drawTmpl r d0) := by
  intro e he
  simp only [drawTmpl, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl | rfl
  · exact Or.inl fun _ _ => rfl
  · exact Or.inr fun a => by simp [copyLook, drawAlpha, BoxVis.drop]
  · exact Or.inr fun a => by simp [copyLook, drawAlpha, BoxVis.drop]

/-- **One instant (class E).** Any two dash offsets of the hidden copies give the same visible scene.

An animated and a still hidden scribble look the same, in every viewport. -/
theorem draw_one_eq (vp r : Rect) (d0 a a' : Rat) :
    visible vp (inst (drawTmpl r d0) a) = visible vp (inst (drawTmpl r d0) a') :=
  hidden_pause_eq vp (drawTmpl r d0) (drawTmpl_hidden vp r d0) a a'

/-- **Every instant, every viewport (class E).** The original shows the hidden copies' dash offset `aO env t`. The
variant shows a still value in the draw window and the original's value elsewhere. The visible scenes are equal for
every environment and every instant, including the frames where the class switches between drawing and idle.

`draw-one` gives the original's picture at every width and every instant. -/
theorem drawOne_visSame {Env T : Type} (vp : Env → Rect) (r : Env → T → Rect) (d0 : Env → T → Rat)
    (phase : T → Phase) (aO : Env → T → Rat) (still : Rat) :
    VisSame E vp (fun env t => inst (drawTmpl (r env t) (d0 env t)) (aO env t))
      (fun env t => inst (drawTmpl (r env t) (d0 env t)) (if phase t = .drawing then still else aO env t)) :=
  hiddenPause_visSame vp (fun env t => drawTmpl (r env t) (d0 env t)) aO
    (fun env t => if phase t = .drawing then still else aO env t) (fun _ t => phase t = .drawing)
    (fun env t _ => drawTmpl_hidden (vp env) (r env t) (d0 env t))
    (fun _ t h => by simp [h])

#guard animates .drawOne 0 && !animates .drawOne 1 && !animates .drawOne 2 && animates .faithful 2
#guard strokeAnimated .drawOne .drawing 0 && !strokeAnimated .drawOne .idle 0
#guard animatedCount .faithful .drawing == 3 && animatedCount .drawOne .drawing == 1

/-! ### Golden rows for `hero.accent.drawone.jsonl` -/

/-- A phase name on the wire. -/
def phaseName : Phase → String
  | .idle => "idle"
  | .drawing => "drawing"

/-- A variant name on the wire. -/
def variantName : DrawVariant → String
  | .faithful => "faithful"
  | .drawOne => "draw-one"

/-- One row: whether copy `j` animates, and its opacity in the draw window, for a variant and phase.

`alpha` is null in the idle phase, where the boil sets the opacity. -/
def drawRow (v : DrawVariant) (phase : Phase) (j : Nat) : Lean.Json :=
  Lean.Json.mkObj
    [("alpha", match phase with | .idle => Lean.Json.null | .drawing => Lean.Json.num (drawAlpha j).num.toNat),
     ("animated", strokeAnimated v phase j), ("copy", Lean.Json.num j), ("phase", phaseName phase),
     ("variant", variantName v)]

/-- One count row: animated copies per phase and variant.

The number of animated paths per draw frame the CI count is compared with. -/
def countRow (v : DrawVariant) (phase : Phase) : Lean.Json :=
  Lean.Json.mkObj [("count", Lean.Json.num (animatedCount v phase)), ("phase", phaseName phase),
    ("variant", variantName v)]

/-- The contents of `packages/contracts/golden/parts/hero.accent.drawone.jsonl`: 12 decision rows, then 4 count rows.

The file text the exporter writes. -/
def drawGoldenText : String :=
  String.join
    ((([DrawVariant.faithful, .drawOne].flatMap fun v =>
        [Phase.idle, .drawing].flatMap fun ph => [0, 1, 2].map fun j => drawRow v ph j) ++
      ([DrawVariant.faithful, .drawOne].flatMap fun v => [Phase.idle, .drawing].map fun ph => countRow v ph)).map
      fun r => r.compress ++ "\n")

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference).

Any other argument list prints the text and returns 0. -/
def drawRun (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == drawGoldenText then
      IO.eprintln s!"accent draw-one golden: {path} is up to date"
      return 0
    IO.eprintln s!"accent draw-one golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print drawGoldenText
    return 0

end Fw.Parts.HeroAccentOpt
