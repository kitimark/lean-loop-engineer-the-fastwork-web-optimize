import Lean.Data.Json
import Fw.Engine
import Fw.Site.Breakpoints
import Fw.Site.BreakpointFacts
import Fw.Parts.EndFlags
/-!
# pain.notes: arm the notes' rotation interval only while the notes are visible (inventory #21, PLAN rev 10)

**The original** (snapshot `_app/immutable/nodes/2.DyWL8TcE.js`, pretty-printed lines; CONFIRMED by reading them):
* The notes are rendered into `.pain-canvas` (keyed each over `[...w, ...T]`, 4749-4791; `x` is `.pain-canvas`,
  4792-4796). `w` holds the base notes, `T` the extra notes the interval adds.
* `F ||= window.setInterval(le, 3e3)` arms the interval when the `IntersectionObserver` on `.pain-sticky` reports
  ratio ≥ 0.12 (`A`), and `clearInterval` plus `T := []` disarm it otherwise (4695-4704). So it ticks every 3 s
  (1/3 Hz) while `A` holds.
* The tick `le` (4590-4646) returns at once when `!A`, while a note is dragged (`O`), when `|T| ≥ 12`, when
  `matchMedia("(max-width: 860px)")` matches (`o`, 4415), or under `prefers-reduced-motion: reduce` (4591-4598).
  When `.commission-card`'s top is above `0.995·innerHeight` (the card covers the section) it sets `T := []` and
  returns (4599-4603). Otherwise it picks a free spot (`Math.random`, container width `< 1100` picks `ae`, else
  `ie`; 4604-4623) and appends one extra note (4624-4645).
* The per-frame scheduler callback `d` (`dE(d, {rootMargin: "150% 0px"})`, 4728-4736) applies the same cover test
  every scroll frame and clears `T` too.

**What "hidden" means here (a correction to the task wording).** At width ≤ 860 the CSS rule
`.pain-notes { display: none }` (`2.gBuqKVzi.css` pretty 2344) hides `.pain-notes`, an empty `aria-hidden` stage div.
The note boxes live in `.pain-canvas`, which stays displayed, and the base notes are drawn there in a narrow layout
(4559-4573). The interval is still harmless at ≤ 860 px: `le` returns before any write, so a tick changes nothing at
all (`narrow_tick_id`). Above 860 px the interval is skipped while the section is offscreen (`A` false; the original
already disarms) or covered by the commission card.

**The variant** `?fw=pain.notes:visible`: arm only while `armed c = A ∧ ¬narrow ∧ ¬covered`, re-evaluated in the
callbacks the original already runs (the IO callback, the `change` listener on `o` (4732), and `d`), and re-arm on
the original's tick grid (`resumeAt`). `prefers-reduced-motion` stays out of the gate on purpose: it does not hide the
notes, and re-arming on its flip would need a new listener, one extra callback in that frame.

**What is proved.**
* Vision, class E: `tickO_idle` (a tick the variant skips leaves the state unchanged), `pain_run_eq` and
  `pain_prefix_eq` (the variant's state equals the original's after every event of every trace), `pain_visSame`
  (every environment, every instant), `narrow_tick_id` / `narrow_run_eq` (≤ 860 px: no premise at all).
* Phase: `resumeAt_on_grid`, `resumeAt_ge`, `resumeAt_least`, `resume_grid`; a naive re-arm is not E
  (`naive_rearm_shifts`).
* Work, both engines: `hiddenTick_le` (every engine, every frame), `hiddenTick_lt` (strict),
  `cr_idle_tick` / `wk_idle_tick` (an idle hidden-tick frame costs the original a script callback, Chromium also a
  PrePaint pass and WebKit a commit; the variant's frame is all zero, `idle_zero`), `frames_le` (every frame of a run).
* Golden rows for `pnpm fw engine-check` (`goldenText`, `packages/contracts/golden/engine/pain-notes.jsonl`).

**Premises** (hypotheses, never axioms): `CovOk` (the original's `T` is empty at every tick that would clear it:
`d` cleared it when the card arrived), the gate is evaluated on the context `le` reads at that tick (built into
`tickV`), the variant ticks on the original's grid (`resumeAt`), and the variant's ticks get the original's random
draws (`add` takes the draw as an argument; the original's skipped ticks draw nothing, 4591-4603). Engine timer facts:
Chromium snaps a repeating timer to `next_fire_time_ + k·interval` (`third_party/blink/renderer/platform/timer.cc:150-161`@f842f52),
so the original's ticks lie on `tickAt`; WebKit re-bases each repeat on the actual fire time
(`Source/WebCore/platform/ThreadTimers.cpp:126-127`@862f17d), so its ticks drift by each tick's lateness, which the
variant cannot see while disarmed (open premise P-wk-drift).

Exact arithmetic: `Nat` milliseconds and counts.
-/
namespace Fw.Parts.PainNotesOpt

open Fw.Engine
open Fw.Site.Breakpoints (Env MQ wLe860 rmReduce wLe860_iff rmReduce_iff)

/-! ## 1. The original's tick `le` as a state machine -/

/-- The interval's state: the extra notes `T` (each of type `N`) and the counter `j`.

What the rotation interval reads and writes: the added notes and the running note number. -/
structure St (N : Type) where
  extras : List N
  next : Nat

/-- What `le` reads at a tick, besides the state: the section in view (`A`, IO ratio ≥ 0.12), a note being dragged
(`O`), `(max-width: 860px)`, `prefers-reduced-motion: reduce`, and the commission card covering the section.

The five flags `le` tests before it touches the notes. -/
structure Ctx where
  inView : Bool
  drag : Bool
  narrow : Bool
  reduce : Bool
  covered : Bool
deriving Repr, DecidableEq

/-- The cap on extra notes (`s(T).length >= 12`, JS 4594).

At twelve extra notes the interval stops adding. -/
def maxExtras : Nat := 12

/-- `le`'s early return (JS 4591-4598): out of view, dragging, full, narrow, or reduced motion.

The tick does nothing when any of these holds. -/
def blocked {N : Type} (c : Ctx) (s : St N) : Bool :=
  !c.inView || c.drag || decide (maxExtras ≤ s.extras.length) || c.narrow || c.reduce

/-- **The original's tick** `le` (JS 4590-4646): blocked, nothing changes; covered, the extra notes are cleared;
otherwise `add r s` places one note with the random draw `r` (it may also change nothing, when no spot is found or
the container is under 8 px). `add` is arbitrary, so both placement policies (container width `< 1100`, JS 4622)
are covered.

One firing of the original's 3 s interval. -/
def tickO {D N : Type} (add : D → St N → St N) (c : Ctx) (r : D) (s : St N) : St N :=
  if blocked c s then s else if c.covered then { s with extras := [] } else add r s

/-- **The variant's gate** (decision function): armed while the section is in view, wider than 860 px and not
covered.

The interval runs only while its notes can be seen. -/
def armed (c : Ctx) : Bool := c.inView && !c.narrow && !c.covered

/-- **The variant's tick**: the original's tick when armed, nothing otherwise (the interval is not armed, so the
tick does not fire).

The same tick, skipped while hidden. -/
def tickV {D N : Type} (add : D → St N → St N) (c : Ctx) (r : D) (s : St N) : St N :=
  if armed c then tickO add c r s else s

/-- The contexts in which the original's tick reaches the clearing branch (when also `|T| < 12`).

When a tick would clear the extra notes. -/
def clears (c : Ctx) : Bool := c.inView && !c.drag && !c.narrow && !c.reduce && c.covered

private def c0 : Ctx := ⟨true, false, false, false, false⟩
#guard armed c0 && !armed { c0 with narrow := true } && !armed { c0 with covered := true } &&
  !armed { c0 with inView := false }
#guard armed { c0 with reduce := true } && armed { c0 with drag := true }
#guard clears { c0 with covered := true } && !clears c0 && !clears { c0 with covered := true, narrow := true }
#guard (tickO (fun (r : Nat) (s : St Nat) => { s with extras := r :: s.extras }) c0 7 ⟨[], 0⟩).extras == [7]
#guard (tickO (fun (r : Nat) (s : St Nat) => { s with extras := r :: s.extras }) { c0 with covered := true } 7
  ⟨[1], 0⟩).extras == []
#guard (tickV (fun (r : Nat) (s : St Nat) => { s with extras := r :: s.extras }) { c0 with covered := true } 7
  ⟨[1], 0⟩).extras == [1]

/-- **A skipped tick changes nothing** (class E, one tick). Whenever the variant is not armed, the original's tick
leaves the state unchanged, provided the extra notes are already empty when that tick would clear them.

Out of view, narrow or covered, the original's tick has no effect on the notes. -/
theorem tickO_idle {D N : Type} (add : D → St N → St N) (c : Ctx) (r : D) (s : St N)
    (ha : armed c = false) (hc : clears c = true → s.extras = []) : tickO add c r s = s := by
  obtain ⟨a, d, n, m, cv⟩ := c
  obtain ⟨ex, j⟩ := s
  cases a <;> cases d <;> cases n <;> cases m <;> cases cv <;>
    simp_all [tickO, armed, blocked, clears]

/-- The variant's tick equals the original's under the same proviso.

Skipping the tick or running it gives the same notes. -/
theorem tickV_eq {D N : Type} (add : D → St N → St N) (c : Ctx) (r : D) (s : St N)
    (hc : clears c = true → armed c = false → s.extras = []) : tickV add c r s = tickO add c r s := by
  unfold tickV
  cases h : armed c
  · exact (tickO_idle add c r s h (fun h' => hc h' h)).symm
  · rfl

/-! ## 2. Traces: every event, every instant -/

/-- An event the notes see: an interval tick with its context and random draw, or any other handler (IO leave,
`d`'s cover clear, drag, keyboard move, resize layout), which both arms run identically.

The things that can change the notes, in order. -/
inductive Ev (D N : Type) where
  | tick (c : Ctx) (r : D)
  | other (g : St N → St N)

/-- One event in the original.

How the original reacts to one event. -/
def stepO {D N : Type} (add : D → St N → St N) (s : St N) : Ev D N → St N
  | .tick c r => tickO add c r s
  | .other g => g s

/-- One event in the variant.

How the variant reacts to one event. -/
def stepV {D N : Type} (add : D → St N → St N) (s : St N) : Ev D N → St N
  | .tick c r => tickV add c r s
  | .other g => g s

/-- The original's state after a list of events from `s_0`.

The original's notes after these events. -/
def runO {D N : Type} (add : D → St N → St N) (s0 : St N) (evs : List (Ev D N)) : St N := evs.foldl (stepO add) s0

/-- The variant's state after a list of events from `s_0`.

The variant's notes after these events. -/
def runV {D N : Type} (add : D → St N → St N) (s0 : St N) (evs : List (Ev D N)) : St N := evs.foldl (stepV add) s0

/-- **The cover premise.** At every tick that would clear the extra notes, the original's extra notes are already
empty (the per-frame callback `d`, JS 4728-4731, cleared them in the frame the card arrived, and nothing adds while
covered).

The covered ticks find nothing left to clear. -/
def CovOk {D N : Type} (add : D → St N → St N) (s0 : St N) (evs : List (Ev D N)) : Prop :=
  ∀ p c r q, evs = p ++ Ev.tick c r :: q → clears c = true → (runO add s0 p).extras = []

/-- **The variant's notes equal the original's after the whole trace** (class E).

Skipping every hidden tick ends in exactly the original's notes. -/
theorem pain_run_eq {D N : Type} (add : D → St N → St N) :
    ∀ (s0 : St N) (evs : List (Ev D N)), CovOk add s0 evs → runV add s0 evs = runO add s0 evs
  | _, [], _ => rfl
  | s0, e :: es, h => by
    have hstep : stepV add s0 e = stepO add s0 e := by
      cases e with
      | tick c r =>
        exact tickV_eq add c r s0 (fun hc _ => h [] c r es rfl hc)
      | other g => rfl
    have ih := pain_run_eq add (stepO add s0 e) es (fun p c r q hp hc => h (e :: p) c r q (by rw [hp]; rfl) hc)
    simp only [runV, runO, List.foldl_cons] at ih ⊢
    rw [hstep]; exact ih

/-- **Every instant** (class E): after the first `n` events, for every `n`, the states are equal.

At no point of the trace do the variant's notes differ from the original's. -/
theorem pain_prefix_eq {D N : Type} (add : D → St N → St N) (s0 : St N) (evs : List (Ev D N))
    (h : CovOk add s0 evs) (n : Nat) : runV add s0 (evs.take n) = runO add s0 (evs.take n) := by
  apply pain_run_eq
  intro p c r q hp hc
  refine h p c r (q ++ evs.drop n) ?_ hc
  calc evs = evs.take n ++ evs.drop n := (List.take_append_drop n evs).symm
    _ = p ++ Ev.tick c r :: (q ++ evs.drop n) := by rw [hp]; simp

/-- **pain.notes, class E, every environment and instant.** For every environment (every width band, touch, hover,
DPR, motion), every renderer of the notes' state, every placement function and every trace satisfying the cover
premise, the visible scenes after the first `n` events are equal, for every `n`.

Arming the interval only while the notes are visible draws exactly the original's notes, at every width and every
instant. -/
theorem pain_visSame {D N : Type} (vp : Env → Rect) (R : Env → St N → Scene) (add : Env → D → St N → St N)
    (s0 : Env → St N) (evs : Env → List (Ev D N)) (h : ∀ env, CovOk (add env) (s0 env) (evs env)) :
    VisSame E vp (fun env n => R env (runO (add env) (s0 env) ((evs env).take n)))
      (fun env n => R env (runV (add env) (s0 env) ((evs env).take n))) :=
  visSame_of_eq vp fun env n => by rw [pain_prefix_eq (add env) (s0 env) (evs env) (h env) n]

/-! ## 3. The width bands (generated breakpoints) -/

/-- The context of a tick in environment `env`: `narrow` is the generated condition `wLe860` (`(width<=860px)`,
the same edge as the JS string `(max-width: 860px)` at JS 4415), `reduce` is `rmReduce`.

The flags `le` reads, with the two media queries taken from the environment. -/
def ctxAt (env : Env) (inView drag covered : Bool) : Ctx :=
  ⟨inView, drag, wLe860.eval env, rmReduce.eval env, covered⟩

#guard wLe860.legacyCss == some "(max-width: 860px)"

/-- **At width ≤ 860 a tick does nothing, and the variant is not armed** (no premise).

In the narrow band the original's interval only burns time, and the variant does not run it. -/
theorem narrow_tick_id {D N : Type} (env : Env) (hw : env.width.LeNat 860) (a d k : Bool)
    (add : D → St N → St N) (r : D) (s : St N) :
    tickO add (ctxAt env a d k) r s = s ∧ armed (ctxAt env a d k) = false := by
  have hn : wLe860.eval env = true := (wLe860_iff env).mpr hw
  simp [tickO, blocked, armed, ctxAt, hn]

/-- **At width ≤ 860, the whole trace is equal without any premise** (every tick narrow).

When every tick sees the narrow layout, the variant matches the original unconditionally. -/
theorem narrow_run_eq {D N : Type} (add : D → St N → St N) (s0 : St N) (evs : List (Ev D N))
    (h : ∀ c r, Ev.tick c r ∈ evs → c.narrow = true) : runV add s0 evs = runO add s0 evs := by
  apply pain_run_eq
  intro p c r q hp hc
  have : c.narrow = true := h c r (by rw [hp]; simp)
  simp [clears, this] at hc

/-- **Above 860 px the gate is "in view and not covered".**

On wide screens the interval runs exactly while the section is in view and uncovered. -/
theorem wide_armed_iff (env : Env) (hw : ¬ env.width.LeNat 860) (a d k : Bool) :
    armed (ctxAt env a d k) = true ↔ a = true ∧ k = false := by
  have hn : wLe860.eval env = false := by
    cases h : wLe860.eval env
    · rfl
    · exact absurd ((wLe860_iff env).mp h) hw
  cases a <;> cases k <;> simp [armed, ctxAt, hn]

/-! ## 4. The phase: re-arm on the original's tick grid -/

/-- The interval period in ms (`setInterval(le, 3e3)`, JS 4696).

One tick every three seconds. -/
def period : Nat := 3000

/-- The original's `k`-th tick (`k ≥ 0`) after it was armed at `t_0` (Chromium's snapped repeat grid).

When the original's interval fires. -/
def tickAt (t0 k : Nat) : Nat := t0 + period * (k + 1)

/-- **The variant's resume time** (decision function): re-arming at `now`, the first tick goes at the original's
first tick at or after `now`.

The variant waits for the original's next tick instead of starting a fresh 3 s period. -/
def resumeAt (t0 now : Nat) : Nat := t0 + period * max 1 ((now - t0 + (period - 1)) / period)

#guard resumeAt 0 4000 == 6000 && resumeAt 0 6000 == 6000 && resumeAt 0 6001 == 9000 && resumeAt 0 0 == 3000
#guard resumeAt 500 100 == 3500 && resumeAt 0 3000 == 3000 && resumeAt 1000 4001 == 7000

/-- The resume time lies on the original's grid.

The variant's first tick is one of the original's ticks. -/
theorem resumeAt_on_grid (t0 now : Nat) : ∃ k, resumeAt t0 now = tickAt t0 k :=
  ⟨max 1 ((now - t0 + (period - 1)) / period) - 1, by
    simp only [resumeAt, tickAt]
    have : 1 ≤ max 1 ((now - t0 + (period - 1)) / period) := Nat.le_max_left _ _
    rw [Nat.sub_add_cancel this]⟩

/-- The resume time is not in the past.

The variant never schedules a tick before it re-arms. -/
theorem resumeAt_ge (t0 now : Nat) : now ≤ resumeAt t0 now := by
  simp only [resumeAt, period]
  have h1 := Nat.le_max_right 1 ((now - t0 + (3000 - 1)) / 3000)
  have h2 := Nat.div_add_mod (now - t0 + (3000 - 1)) 3000
  have h3 := Nat.mod_lt (now - t0 + (3000 - 1)) (show 3000 > 0 by decide)
  have h4 : 3000 * ((now - t0 + (3000 - 1)) / 3000) ≤ 3000 * max 1 ((now - t0 + (3000 - 1)) / 3000) :=
    Nat.mul_le_mul_left _ h1
  omega

/-- The resume time is the earliest grid tick at or after `now`.

No original tick at or after `now` comes before the variant's first one. -/
theorem resumeAt_least (t0 now k : Nat) (h : now ≤ tickAt t0 k) : resumeAt t0 now ≤ tickAt t0 k := by
  simp only [resumeAt, tickAt, period] at h ⊢
  have hq : (now - t0 + (3000 - 1)) / 3000 ≤ k + 1 := by
    exact Nat.lt_succ_iff.mp ((Nat.div_lt_iff_lt_mul (by decide)).mpr (by omega))
  have : max 1 ((now - t0 + (3000 - 1)) / 3000) ≤ k + 1 := Nat.max_le.mpr ⟨by omega, hq⟩
  have := Nat.mul_le_mul_left 3000 this
  omega

/-- **The variant's ticks after a re-arm are the original's ticks.** With `k_0` the grid index of the resume time,
the variant's `i`-th tick is the original's tick `k_0 + i`.

Once re-armed on the grid, the variant stays on it. -/
theorem resume_grid (t0 now k0 : Nat) (hk : resumeAt t0 now = tickAt t0 k0) (i : Nat) :
    resumeAt t0 now + period * i = tickAt t0 (k0 + i) := by
  rw [hk]; simp only [tickAt, period]; rw [Nat.add_right_comm k0 i 1, Nat.mul_add]; omega

/-- The number of ticks of an interval armed at `t_0` that fire in `(a, b]`.

How often an interval fires in a time window. -/
def ticksIn (t0 a b : Nat) : Nat := ((List.range b).filter fun k => decide (a < tickAt t0 k ∧ tickAt t0 k ≤ b)).length

/-- **A naive re-arm is not E.** Armed at 0, covered from 2000 ms to 4000 ms: the original fires at 6000 ms (and
adds a note); a fresh `setInterval` at 4000 ms fires first at 7000 ms. In the window `(4000, 6500]` the original
ticks once and the naive variant never, while `resumeAt` ticks at 6000 like the original.

Restarting the 3 s period on re-arm shifts when notes appear; the variant must resume on the original's grid. -/
theorem naive_rearm_shifts :
    ticksIn 0 4000 6500 = 1 ∧ ticksIn 4000 4000 6500 = 0 ∧ resumeAt 0 4000 = 6000 := by decide +kernel

/-! ## 5. Work: a skipped tick, in every engine -/

/-- The frame with a hidden tick added: `n` script callbacks (the timer callback and any microtask it queues),
`a` forced style and `b` forced layout passes (`getBoundingClientRect` in the cover test, only when dirty), and no
property change (the blocked branch returns before any write; the clearing branch writes `T := []` on an empty `T`,
which the keyed each leaves as it is).

The original's frame, which has the skipped tick in it. -/
def withTick {P : Type} (f : FrameIn P) (n a b : Nat) : FrameIn P :=
  { f with script := f.script + n, forcedStyle := f.forcedStyle + a, forcedLayout := f.forcedLayout + b }

private theorem coverB_self {P M : Type} (E : Engine P M) : ∀ (l : List (Change P)), coverB E l l = true
  | [] => rfl
  | c :: cs => by simp [coverB, coverB_self E cs]

/-- **A skipped tick never adds work**, in every engine and every frame.

The variant's frame, without the hidden tick, costs at most the original's. -/
theorem hiddenTick_le {P M : Type} (E : Engine P M) (f : FrameIn P) (n a b : Nat) :
    (frameWork E f).le (frameWork E (withTick f n a b)) :=
  frame_le_of_cover E f.changes [] (by simp [withTick]) (coverB_self E f.changes)
    (Nat.le_add_right _ _) (Nat.le_add_right _ _) (Nat.le_add_right _ _) (Nat.le_refl _) (Nat.le_refl _)

/-- **And strictly less**: the script units drop by `n > 0`, in every engine.

Each skipped tick removes its callback from the frame. -/
theorem hiddenTick_lt {P M : Type} (E : Engine P M) (f : FrameIn P) (n a b : Nat) (hn : 0 < n) :
    (frameWork E f).lt (frameWork E (withTick f n a b)) ∧
      (frameWork E (withTick f n a b)).units .script = (frameWork E f).units .script + n := by
  have hu : (frameWork E (withTick f n a b)).units .script = (frameWork E f).units .script + n := by
    simp only [frameWork, stageUnits, withTick, ↓reduceIte]; omega
  exact ⟨⟨hiddenTick_le E f n a b, Or.inl ⟨.script, Or.inr (by omega)⟩⟩, hu⟩

/-- **Every frame of a run** (both engines, all widths): if each variant frame is the original's frame or the
original's frame without a hidden tick, the variant's work is at most the original's in every frame.

Gating the interval never costs a frame anything. -/
theorem frames_le {P M : Type} (E : Engine P M) (v o : Nat → FrameIn P)
    (h : ∀ k, o k = v k ∨ ∃ n a b, o k = withTick (v k) n a b) (k : Nat) :
    (frameWork E (v k)).le (frameWork E (o k)) := by
  rcases h k with h | ⟨n, a, b, h⟩
  · rw [h]; exact Work.le_refl _
  · rw [h]; exact hiddenTick_le E (v k) n a b

/-- An idle frame: nothing runs.

A frame where the page does nothing. -/
def idle {P : Type} : FrameIn P := ⟨0, 0, 0, 0, [], 0⟩

/-- **The variant's idle frame costs nothing**, in every engine.

While the notes are hidden and nothing else happens, the variant's notes cost zero. -/
theorem idle_zero {P M : Type} (E : Engine P M) (s : Stage) :
    (frameWork E (idle : FrameIn P)).passes s = 0 ∧ (frameWork E (idle : FrameIn P)).units s = 0 ∧
      (frameWork E (idle : FrameIn P)).hits = 0 := by
  cases s <;> simp [frameWork, touched, stageUnits, forcedPasses, idle, FrameIn.updates]

open Fw.Engine.Chromium in
/-- **Chromium lane: an idle hidden tick costs one script pass and unit plus the update's PrePaint (`props`) pass
(the model's `base`); the variant's frame is zero.**

Changed since CI run 39088367495: the tick paid only `script`; the engine-premises lane MEASURED a PrePaint pass on
every script-only frame (`chromiumAt.base = [props]`).

On Chromium, each hidden 3 s tick is one timer callback and one PrePaint pass the variant no longer runs. -/
theorem cr_idle_tick :
    (∀ s : Stage, (frameWork chromium (withTick idle 1 0 0)).passes s =
        (if s = .script ∨ s = .props then 1 else 0) ∧
      (frameWork chromium (withTick idle 1 0 0)).units s = (if s = .script then 1 else 0)) ∧
    (frameWork chromium idle).lt (frameWork chromium (withTick idle 1 0 0)) := by
  refine ⟨fun s => ?_, (hiddenTick_lt chromium idle 1 0 0 (by decide)).1⟩
  cases s <;> simp [frameWork, touched, stageUnits, forcedPasses, idle, withTick, FrameIn.updates, chromium,
    chromiumAt, crCompStages, lane]

open Fw.Engine.WebKit in
/-- **WebKit: an idle hidden tick costs one script pass and unit plus the rendering update's commit (the model's
`base`); the variant's frame is zero.**

On WebKit, each hidden tick is one timer callback and, in the model, one commit the variant no longer pays. -/
theorem wk_idle_tick :
    (∀ s : Stage, (frameWork webkit (withTick idle 1 0 0)).passes s =
        (if s = .script ∨ s = .commit then 1 else 0) ∧
      (frameWork webkit (withTick idle 1 0 0)).units s = (if s = .script then 1 else 0)) ∧
    (frameWork webkit idle).lt (frameWork webkit (withTick idle 1 0 0)) := by
  refine ⟨fun s => ?_, (hiddenTick_lt webkit idle 1 0 0 (by decide)).1⟩
  cases s <;> simp [frameWork, touched, stageUnits, forcedPasses, idle, withTick, FrameIn.updates, webkit,
    webkitAt]

/-- Hidden ticks per minute: `60000 / 3000 = 20` (the rate is 1/3 Hz).

How many callbacks per minute the variant saves while the notes stay hidden. -/
def ticksPerMinute : Nat := 60000 / period

#guard ticksPerMinute == 20

/-! ## 6. Golden rows for `pnpm fw engine-check` -/

/-- A count type: its JSON name, the stage it reads, and whether it reads units (else passes).

Which counter reads which stage. -/
structure CountType where
  name : String
  stage : Stage
  units : Bool

/-- The JSON name of a stage.

As in the engine golden files. -/
def stageName : Stage → String
  | .script => "script" | .style => "style" | .layout => "layout" | .props => "props"
  | .paint => "paint" | .raster => "raster" | .commit => "commit" | .comp => "comp"

/-- **The relational prediction** of one count type over frame pairs `(v, o)` (decision function), first match:
equal in every pair gives `=o`; at most the original's in every pair gives `≤o` (not `<o`: whether a scenario reaches
a hidden tick is not modelled); else `any`. Here `x_t(w)` is `w.units(t.stage)` when
`t.units`, else `w.passes(t.stage)`.

Equal when no modelled hidden tick changes the count, at most when some lowers it. -/
def relPred (pairs : List (Work × Work)) (t : CountType) : String :=
  let x (w : Work) := if t.units then w.units t.stage else w.passes t.stage
  if pairs.all (fun p => x p.1 == x p.2) then "=o"
  else if pairs.all (fun p => decide (x p.1 ≤ x p.2)) then "≤o" else "any"

#guard relPred [] ⟨"x", .style, false⟩ == "=o"
#guard relPred [(Work.zero, paintW 1)] ⟨"x", .paint, false⟩ == "≤o"
#guard relPred [(paintW 1, Work.zero)] ⟨"x", .paint, false⟩ == "any"

/-- The frames the model pairs, per engine: the idle frame and a frame with one `transform` change on a target of
layer state `l`, each with a hidden tick of 1 callback and `(a, b) ∈ {(0,0), (1,1)}` forced passes; plus the
same frames unchanged (a visible tick, run by both).

The frames gating the interval changes, each with its original. -/
def pairsOf {P M : Type} (E : Engine P M) (p : P) : List (Work × Work) :=
  let fs : List (FrameIn P) := idle :: [LayerState.none, .layer, .own].map fun l => ⟨0, 0, 0, 0, [⟨0, p, l⟩], 0⟩
  (fs.flatMap fun f => [0, 1].map fun a => (frameWork E f, frameWork E (withTick f 1 a a))) ++
    fs.map fun f => (frameWork E f, frameWork E f)

/-- The Chromium count types of the swipe profiles (as in `morph-mount.jsonl`; `trace.Paint` quarantined). Each entry is (name, stage, units).

Which Chromium counter reads which stage. -/
def crTypes : List CountType :=
  [⟨"trace.FunctionCall", .script, true⟩, ⟨"trace.UpdateLayoutTree", .style, false⟩,
   ⟨"trace.Layout", .layout, false⟩, ⟨"trace.Layout.dirtyObjects", .layout, true⟩,
   ⟨"metric.LayoutCount", .layout, false⟩, ⟨"trace.PrePaint", .props, false⟩,
   ⟨"raster.invalidationAreaPx", .paint, true⟩, ⟨"trace.cc.Commit", .commit, false⟩]

/-- The WebKit count types (as in `morph-mount.jsonl`). Each entry is (name, stage, units).

Which WebKit counter reads which stage. -/
def wkTypes : List CountType :=
  [⟨"RecalculateStyles", .style, false⟩, ⟨"Layout", .layout, false⟩, ⟨"Paint", .paint, false⟩,
   ⟨"Composite", .commit, false⟩]

/-- One JSON row, keys sorted, in the `morph-mount.jsonl` schema.

The variant flag is `?fw=pain.notes:visible`; the base is the faithful rewrite. -/
def row (engine scenario : String) (t : CountType) (pred : String) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"" ++ t.name ++ "\",\"engine\":\"" ++ engine ++ "\",\"prediction\":\"" ++
    pred ++ "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"" ++ stageName t.stage ++
    "\",\"variant\":\"rewrite+?fw=pain.notes:visible\"}"

open Fw.Engine.Chromium Fw.Engine.WebKit in
/-- **The golden rows**: Chromium on `swipe-v1` and `swipe-touch-v1`, WebKit on `swipe-v1`, each prediction from
`relPred` over the engine's pairs.

The list comprehension runs `sc` outer and `t` inner, so there are `2 · 8 + 4 = 20` lines.
The file `packages/contracts/golden/engine/pain-notes.jsonl`, line by line. -/
def goldenLines : List String :=
  (["swipe-v1", "swipe-touch-v1"].flatMap fun sc =>
      crTypes.map fun t => row "chromium" sc t (relPred (pairsOf chromium (CrProp.css .transform)) t)) ++
    wkTypes.map fun t => row "webkit" "swipe-v1" t (relPred (pairsOf webkit WkProp.transform) t)

/-- The golden file text: one row per line, trailing newline.

What the driver writes. -/
def goldenText : String := String.join (goldenLines.map (· ++ "\n"))

#guard goldenLines.length == 20
-- props is `≤o` since CI run 39088367495: the hidden tick pays the base PrePaint pass the variant drops.
#guard (crTypes.map fun t => relPred (pairsOf Chromium.chromium (Chromium.CrProp.css .transform)) t) ==
  ["≤o", "≤o", "≤o", "=o", "≤o", "≤o", "=o", "=o"]
#guard (wkTypes.map fun t => relPred (pairsOf WebKit.webkit WebKit.WkProp.transform) t) == ["≤o", "≤o", "=o", "≤o"]

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

The hidden tick writes nothing; its cover test may read the rect (`a` forced style, `b` forced layout passes), which
cleans the flags the rest of the frame dirtied. So the original can end a stage clean that the variant (no tick, no
read) ends dirty and pays at frame end. That pass is the one the tick's forced read paid, so `⪯` holds whenever each
stage the variant ends dirty is end-dirty in the original too or carries one of the tick's forced passes, and the
win stays strict on the tick's script units (`hiddenTick_ltE`). Verdict unchanged: dominance in every engine; the
forced passes of the tick are no longer a saving of their own when the frame dirtied the stage before. -/

section EndPass

open Fw.Parts.EndFlags

/-- **A skipped tick under `frameWorkE`: `⪯`.** If every stage the variant touches and ends dirty is end-dirty in the
original, or is style with `a > 0`, or is layout with `b > 0`, the variant's frame costs at most the original's.

The tick's read pays for any pass the variant leaves to the frame end. -/
theorem hiddenTick_leE {P M : Type} (E : Engine P M) (f : FrameIn P) (n a b : Nat) (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E f → ev s = true →
      eo s = true ∨ (s = .style ∧ 0 < a) ∨ (s = .layout ∧ 0 < b)) :
    (frameWorkE E f ev).le (frameWorkE E (withTick f n a b) eo) := by
  have ht := touched_of_le_same_forced E (fun s => by cases s <;> rfl) (hiddenTick_le E f n 0 0)
  refine frameE_le_of_total E ev eo (fun s hs => ht s hs) (fun s => ((hiddenTick_le E f n a b).1 s).2)
    (hiddenTick_le E f n a b).2 (fun s => ?_) (fun s hs => ?_)
  · cases s <;> simp [forcedPasses, withTick]
  · have := hm s hs
    cases s <;> simp only [forcedPasses, withTick] <;> revert this <;> cases ev _ <;> cases eo _ <;>
      simp <;> omega

/-- **And strictly less under `frameWorkE`** when `n > 0`, under the same flag condition: the script units drop by
`n`.

The skipped callback is saved whatever the end flags. -/
theorem hiddenTick_ltE {P M : Type} (E : Engine P M) (f : FrameIn P) (n a b : Nat) (hn : 0 < n)
    (ev eo : Stage → Bool)
    (hm : ∀ s, s ∈ touched E f → ev s = true →
      eo s = true ∨ (s = .style ∧ 0 < a) ∨ (s = .layout ∧ 0 < b)) :
    (frameWorkE E f ev).lt (frameWorkE E (withTick f n a b) eo) :=
  ⟨hiddenTick_leE E f n a b ev eo hm, Or.inl ⟨.script, Or.inr (by
    have := (hiddenTick_lt E f n a b hn).2
    simp only [frameWork] at this
    show stageUnits E f .script < stageUnits E (withTick f n a b) .script
    omega)⟩⟩

end EndPass

/-! ## Magnitude of a skipped tick (ledger n=21)

A hidden tick without a read (`a = b = 0`) changes the units only on `script`, by its `n` callbacks, and the hit
tests not at all. Passes can change only on `script` and on the engine's base stages (the tick makes an idle frame
"update"; whether a write-free timer callback really schedules a rendering update in WebKit is the open cite that
decides the commit pass in `wk_idle_tick`). So the saving of the gate is the skipped callbacks, plus at most one
pass per base stage in frames that would otherwise be idle. -/

/-- **Units of a skipped tick.** Only `script` changes, by `n`; hit tests are equal.

The tick's only unit cost is its callbacks. -/
theorem tick_units {P M : Type} (E : Engine P M) (f : FrameIn P) (n a b : Nat) (s : Stage) :
    (frameWork E (withTick f n a b)).units s = (frameWork E f).units s + (if s = .script then n else 0) ∧
      (frameWork E (withTick f n a b)).hits = (frameWork E f).hits := by
  refine ⟨?_, rfl⟩
  simp only [frameWork, stageUnits, withTick]
  by_cases h : s = .script <;> simp only [h, ↓reduceIte] <;> omega

/-- **Passes of a read-free tick.** Off `script` and the base stages, a tick with no forced pass leaves every stage's
passes equal.

A write-free callback touches no stage of its own beyond script and the update it may schedule. -/
theorem tick_passes_eq {P M : Type} (E : Engine P M) (f : FrameIn P) (n : Nat) (s : Stage) (hs : s ≠ .script)
    (hb : s ∉ E.base) :
    (frameWork E (withTick f n 0 0)).passes s = (frameWork E f).passes s := by
  have hb' : ∀ c : Bool, s ∉ (if c = true then E.base else []) := by
    intro c; split <;> simp_all
  have hs' : ∀ x : Nat, s ∉ (if 0 < x then [Stage.script] else []) := by
    intro x; split <;> simp_all
  have hm : s ∈ touched E (withTick f n 0 0) ↔ s ∈ touched E f := by
    simp only [touched, List.mem_append, hb', hs', or_false]
    exact Iff.rfl
  have hF : forcedPasses (withTick f n 0 0) s = forcedPasses f s := by cases s <;> rfl
  simp only [frameWork, hF]
  by_cases h : s ∈ touched E f
  · simp [h, hm.mpr h]
  · simp [h, mt hm.mp h]

end Fw.Parts.PainNotesOpt
