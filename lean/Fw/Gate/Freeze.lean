/-
  Fw.Gate.Freeze: the gate's settle wait under a frozen clock (gate-shard-balance, round 2).

  Why. In round 1 (run 39101532038) a sample settled or not depending on how fast the runner painted: `Obs.t` is real
  milliseconds, so a slow WebKit job could spend the 30 s timeout on a page a fast job settled in 3 frames, and CSS
  animations that restart from timers ended a sample at a random point of their cycle. Round 2 fixes both arms of both
  engines to one deterministic clock:

  * the page clock (Date, timers, requestAnimationFrame, performance.now) is installed frozen at one instant before the
    page loads and is advanced only by the harness, `stepMs` (one 60 Hz frame) at a time, one step per observation;
  * before an observation the harness freezes the document's CSS and Web animations: a finite one jumps to its end,
    an infinite one is paused at a fixed point of its first iteration.

  Nothing that is compared changes; only when it is read. This module states what that does to the wait of
  `Fw.Gate.Settle` and proves it: the observations depend on the step index alone (`wait_frozen_agree`), the frame budget
  alone ends an unsettled wait (`spent_frozen_frames`), a wait settles iff some step inside the budget is settled
  (`wait_frozen_settled_iff`), and after the freeze nothing finite runs, so "settled" means three quiet frames, no hover
  (`settled_frozen_anims`). Golden vectors for the TypeScript twin close the file.
-/
import Lean.Data.Json
import Fw.Gate.Settle

namespace Fw.Gate.Freeze
open Lean Fw.Gate.Settle

/-- The step of the frozen clock: one 60 Hz frame, in milliseconds (the clock of a requestAnimationFrame in the page).

$$\Delta = 16 \text{ ms}$$ -/
def stepMs : Nat := 16

/-- The observation after `i` steps of the frozen clock: the frame count is the step count and the time is the step count
times the step. Only `running` and `stable` (functions of the step index), and the hover flag, come from the page.

$$o_i = (\mathit{run}_i, i, \mathit{st}_i, \mathit{hov}, \Delta\, i)$$ -/
def frozenObs (run stable : Nat → Nat) (hov : Bool) (i : Nat) : Obs :=
  { running := run i, frames := i, stable := stable i, hoverInside := hov, t := stepMs * i }

/-- Under the frozen clock the time of an observation is a function of its step index: a slower machine does not change it.

$$t(o_i) = \Delta\, i \quad\wedge\quad \mathit{fr}(o_i) = i$$ -/
theorem frozenObs_clock (run stable : Nat → Nat) (hov : Bool) (i : Nat) :
    (frozenObs run stable hov i).t = stepMs * i ∧ (frozenObs run stable hov i).frames = i := ⟨rfl, rfl⟩

/-- The decision `settled` does not read the time: the clock cannot change what settled means.

$$\forall t',\quad \operatorname{settled}_\pi(o[t := t']) = \operatorname{settled}_\pi(o)$$ -/
theorem settled_congr (p : Policy) (o : Obs) (t' : Nat) : settled p { o with t := t' } = settled p o := rfl

/-- The budget of an observation under the frozen clock: the time bound or the frame bound.

$$\operatorname{spent}_\pi(o_i) \iff T < \Delta\, i \;\vee\; F < i$$ -/
theorem spent_frozen (p : Policy) (run stable : Nat → Nat) (hov : Bool) (i : Nat) :
    spent p (frozenObs run stable hov i) = true ↔ p.timeoutMs < stepMs * i ∨ p.maxFrames < i := by
  show (decide (p.timeoutMs < stepMs * i) || decide (p.maxFrames < i)) = true ↔ _
  rw [Bool.or_eq_true, decide_eq_true_eq, decide_eq_true_eq]

/-- When the frame budget fits in the time budget ($\Delta F \le T$), the frame budget alone ends a frozen wait: the time
bound never spends an observation first, so the outcome does not depend on the timeout at all.

$$\Delta F \le T \;\Longrightarrow\; \left(\operatorname{spent}_\pi(o_i) \iff F < i\right)$$ -/
theorem spent_frozen_frames (p : Policy) (run stable : Nat → Nat) (hov : Bool) (i : Nat)
    (h : stepMs * p.maxFrames ≤ p.timeoutMs) :
    spent p (frozenObs run stable hov i) = true ↔ p.maxFrames < i := by
  rw [spent_frozen]
  simp only [stepMs] at h ⊢
  omega

/-- The gate policy fits: 60 frames of 16 ms are 960 ms, far inside the 30 s timeout.

$$\Delta \cdot 60 = 960 \le 30000$$ -/
theorem gatePolicy_frozen : stepMs * gatePolicy.maxFrames ≤ gatePolicy.timeoutMs := by
  simp [stepMs, gatePolicy]

/-- Two frozen pages that look the same for the first $F + 2$ steps (the same running count and quiet-frame count at each, the same
hover flag) have the same wait: the answer is a function of the page's steps alone, whichever machine ran them and
however long it took.

$$\left(\forall m \le F + 1,\ \mathit{run}_m = \mathit{run}'_m \wedge \mathit{st}_m = \mathit{st}'_m\right) \wedge \mathit{hov} = \mathit{hov}' \;\Longrightarrow\; \operatorname{wait}_\pi(o) = \operatorname{wait}_\pi(o')$$ -/
theorem wait_frozen_agree (p : Policy) (run stable run' stable' : Nat → Nat) (hov : Bool)
    (h : ∀ m, m ≤ p.maxFrames + 1 → run m = run' m ∧ stable m = stable' m) :
    wait p (frozenObs run stable hov) = wait p (frozenObs run' stable' hov) := by
  apply wait_stops_by_frames p _ _ (fun i => Nat.le_refl i)
  intro m hm
  obtain ⟨h1, h2⟩ := h m hm
  simp [frozenObs, h1, h2]

/-- The frozen wait settles exactly when some step inside the frame budget is settled (and the budget fits the time bound).
So the settled ratio under the frozen clock is a statement about the page's first $F$ frames only.

$$\Delta F \le T \;\Longrightarrow\; \left(\exists k,\ \operatorname{wait}_\pi(o) = \mathrm{settled}(k)\right) \iff \exists j \le F,\ \operatorname{settled}_\pi(o_j)$$ -/
theorem wait_frozen_settled_iff (p : Policy) (run stable : Nat → Nat) (hov : Bool)
    (h : stepMs * p.maxFrames ≤ p.timeoutMs) :
    (∃ k, wait p (frozenObs run stable hov) = .settled k) ↔
      ∃ j, j ≤ p.maxFrames ∧ settled p (frozenObs run stable hov j) = true := by
  constructor
  · rintro ⟨k, hk⟩
    obtain ⟨hs, _, hf⟩ := wait_sound p _ k hk
    exact ⟨k, hf, hs⟩
  · rintro ⟨j, hj, hs⟩
    have hF : p.maxFrames ≤ stepMs * p.maxFrames := by simp only [stepMs]; omega
    have tmono : ∀ n, (frozenObs run stable hov n).t ≤ (frozenObs run stable hov (n + 1)).t := by
      intro n; simp only [frozenObs, stepMs]; omega
    have fmono : ∀ n, (frozenObs run stable hov n).frames ≤ (frozenObs run stable hov (n + 1)).frames := by
      intro n; simp only [frozenObs]; omega
    have hjt : j ≤ p.timeoutMs := by omega
    have htj : (frozenObs run stable hov j).t ≤ p.timeoutMs := by
      simp only [frozenObs, stepMs] at h ⊢; omega
    obtain ⟨k, hk, _⟩ := wait_complete p _ tmono fmono j hjt hs htj hj
    exact ⟨k, hk⟩

/-- Why the real clock was replaced: with real time the same page steps give different outcomes on a fast and a slow machine
(one observation per frame; the slow machine takes 20 s per frame, so the time bound is spent at the second frame).
The same trajectory under the frozen clock gives the same outcome on both.

$$\exists\, s \ne s':\ \operatorname{wait}_{\pi_{\mathrm{gate}}}(o^{s}) = \mathrm{settled}(3) \;\wedge\; \operatorname{wait}_{\pi_{\mathrm{gate}}}(o^{s'}) = \mathrm{unsettled},\qquad o^{s}_i = (0, i, i, \bot, s\, i)$$ -/
theorem real_clock_machine_dependent :
    wait gatePolicy (fun i => { running := 0, frames := i, stable := i, hoverInside := false, t := 1 * i }) = .settled 3 ∧
    wait gatePolicy (fun i => { running := 0, frames := i, stable := i, hoverInside := false, t := 20000 * i }) = .unsettled := by
  constructor <;> decide

/-- The same trajectories under the frozen clock agree (the time is not a free input any more).

$$\operatorname{wait}_{\pi_{\mathrm{gate}}}(o_i = (0, i, i, \bot, \Delta i)) = \mathrm{settled}(3)$$ -/
theorem frozen_machine_independent :
    wait gatePolicy (frozenObs (fun _ => 0) (fun i => i) false) = .settled 3 := by decide

-- ---------------------------------------------------------------------------------------------------------------
-- the freeze pass over CSS and Web animations
-- ---------------------------------------------------------------------------------------------------------------

/-- The iteration count of an animation: a finite number or infinite.

$$\mathrm{Iter} = \mathrm{finite}(n) \mid \mathrm{infinite}$$ -/
inductive Iter where
  | finite (n : Nat)
  | infinite
  deriving DecidableEq, Repr

/-- One animation as the freeze pass reads it from `getComputedTiming()`: duration and delay (ms), iteration count, and its
current time `elapsed` (ms since its timeline origin, the quantity the freeze sets).

$$a = (d, \delta, \iota, c) \in \mathbb{N}\times\mathbb{N}\times(\mathbb{N}\cup\{\infty\})\times\mathbb{N}$$ -/
structure AnimSpec where
  dur : Nat
  delay : Nat
  iter : Iter
  elapsed : Nat
  deriving DecidableEq, Repr

/-- The current time the freeze pass gives an animation: a finite one its end ($\delta + n\,d$, what `finish()` does), an
infinite one (which has no end) the middle of its first iteration ($\delta + \lfloor d/2 \rfloor$, where it is paused).

$$\operatorname{freezeTime}(d, \delta, \iota) = \begin{cases}\delta + n\,d & \iota = n\\ \delta + \lfloor d/2\rfloor & \iota = \infty\end{cases}$$ -/
def freezeTime (a : AnimSpec) : Nat :=
  match a.iter with
  | .finite n => a.delay + n * a.dur
  | .infinite => a.delay + a.dur / 2

/-- The freeze pass on one animation: set its current time to `freezeTime`.

$$\operatorname{freeze}(a) = a[c := \operatorname{freezeTime}(a)]$$ -/
def freezeAct (a : AnimSpec) : AnimSpec := { a with elapsed := freezeTime a }

/-- The frozen state of an animation does not depend on where it was when it was frozen (its current time, which depends on how
long the machine took): two animations with the same timing freeze to the same state.

$$\operatorname{freeze}(a[c := e]) = \operatorname{freeze}(a[c := e'])$$ -/
theorem freeze_independent_of_elapsed (a : AnimSpec) (e e' : Nat) :
    freezeAct { a with elapsed := e } = freezeAct { a with elapsed := e' } := rfl

/-- The freeze pass is idempotent: freezing at every step is the same as freezing once.

$$\operatorname{freeze}(\operatorname{freeze}(a)) = \operatorname{freeze}(a)$$ -/
theorem freeze_idem (a : AnimSpec) : freezeAct (freezeAct a) = freezeAct a := rfl

/-- An infinite animation is paused inside its first iteration, not on an iteration boundary: where the pause lands cannot
depend on the direction or the count of iterations.

$$0 < d \;\Longrightarrow\; \delta \le \operatorname{freezeTime}(d, \delta, \infty) < \delta + d$$ -/
theorem freeze_infinite_inside (a : AnimSpec) (h : a.iter = .infinite) (hd : 0 < a.dur) :
    a.delay ≤ freezeTime a ∧ freezeTime a < a.delay + a.dur := by
  simp only [freezeTime, h]
  omega

/-- Running as the settle wait counts it: a finite animation (or transition) whose current time is before its end. An
infinite one is never counted (the page filters on `Number.isFinite(iterations)`).

$$\operatorname{running}(a) \iff \iota = n \wedge c < \delta + n\,d$$ -/
def isRunning (a : AnimSpec) : Bool :=
  match a.iter with
  | .finite n => decide (a.elapsed < a.delay + n * a.dur)
  | .infinite => false

/-- The running count of a list of animations.

$$\operatorname{runCount}(A) = \left|\{a \in A \mid \operatorname{running}(a)\}\right|$$ -/
def runCountA (as : List AnimSpec) : Nat := (as.filter isRunning).length

/-- After the freeze pass nothing finite runs: the running count of the frozen document is 0, whatever the animations were
doing and wherever the machine had got them.

$$\operatorname{runCount}(\operatorname{freeze}(A)) = 0$$ -/
theorem runCount_freeze (as : List AnimSpec) : runCountA (as.map freezeAct) = 0 := by
  unfold runCountA
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro a ha
  obtain ⟨b, _, rfl⟩ := List.mem_map.1 ha
  rcases b with ⟨d, dl, it, e⟩
  cases it <;> simp [isRunning, freezeAct, freezeTime]

/-- What "settled" means under the frozen clock: with the freeze pass done at the observation, the running count is 0 and
the decision reduces to the rest of its definition, enough frames since the resize, enough quiet frames in a row, the pointer
parked.

$$\operatorname{settled}_\pi(\operatorname{runCount}(\operatorname{freeze}(A)), \mathit{fr}, \mathit{st}, \mathit{hov}, t) \iff m_f \le \mathit{fr} \;\wedge\; m_s \le \mathit{st} \;\wedge\; \neg\,\mathit{hov}$$ -/
theorem settled_frozen_anims (p : Policy) (as : List AnimSpec) (fr st t : Nat) (hov : Bool) :
    settled p { running := runCountA (as.map freezeAct), frames := fr, stable := st, hoverInside := hov, t := t } = true ↔
      p.minFrames ≤ fr ∧ p.minStable ≤ st ∧ hov = false := by
  rw [runCount_freeze]
  simp [settled, and_assoc]

-- ---------------------------------------------------------------------------------------------------------------
-- the fake time of a stop: both arms leave it at the same instant
-- ---------------------------------------------------------------------------------------------------------------

/-- The fake time a settle wait can read: it stops by observation $F + 1$ (`wait_stops_by_frames`), so it advances the clock by
at most $(F + 1)\,\Delta$.

$$\operatorname{span}(\pi) = \Delta\,(F_\pi + 1)$$ -/
def settleSpan (p : Policy) : Nat := stepMs * (p.maxFrames + 1)

/-- The gate policy's span is 976 ms.

$$\operatorname{span}(\pi_{\mathrm{gate}}) = 16 \cdot 61 = 976$$ -/
theorem settleSpan_gate : settleSpan gatePolicy = 976 := by simp [settleSpan, stepMs, gatePolicy]

/-- The instant a stop is aligned to: the next multiple of the grid $g$ strictly after the clock $e$.

$$\operatorname{align}_g(e) = \left(\lfloor e / g \rfloor + 1\right) g$$ -/
def alignTarget (e g : Nat) : Nat := (e / g + 1) * g

/-- Two clocks inside the same grid cell are aligned to the same instant: the arms may differ in how many steps a stop took, but
as long as each stays inside the cell they leave it at the same time.

$$kg \le e < (k+1)g \;\wedge\; kg \le e' < (k+1)g \;\Longrightarrow\; \operatorname{align}_g(e) = \operatorname{align}_g(e')$$ -/
theorem alignTarget_eq (k g e e' : Nat) (h1 : k * g ≤ e) (h2 : e < (k + 1) * g)
    (h3 : k * g ≤ e') (h4 : e' < (k + 1) * g) : alignTarget e g = alignTarget e' g := by
  have a1 : e / g = k := Nat.div_eq_of_lt_le h1 h2
  have a2 : e' / g = k := Nat.div_eq_of_lt_le h3 h4
  simp [alignTarget, a1, a2]

/-- A stop that starts on a grid instant $kg$, advances the clock by a fixed $r$ (the post-resize advance) and then waits at most
$\operatorname{span}(\pi)$ ends inside the same grid cell when $r + \operatorname{span}(\pi) < g$: so every arm is aligned to
the next grid instant, whatever its wait took. (With $g = 2000$, $r = 1000$: $1000 + 976 < 2000$.)

$$r + \operatorname{span}(\pi) < g \;\Longrightarrow\; \forall w \le \operatorname{span}(\pi),\ kg \le kg + r + w < (k+1)g$$ -/
theorem stop_stays_in_cell (p : Policy) (k g r w : Nat) (h : r + settleSpan p < g) (hw : w ≤ settleSpan p) :
    k * g ≤ k * g + r + w ∧ k * g + r + w < (k + 1) * g := by
  constructor
  · omega
  · rw [Nat.add_mul, Nat.one_mul]; omega

/-- The harness numbers fit: the post-resize advance 1000 ms and the gate span 976 ms are inside the 2000 ms grid.

$$1000 + 976 < 2000$$ -/
theorem harness_grid_fits : 1000 + settleSpan gatePolicy < 2000 := by simp [settleSpan, stepMs, gatePolicy]

-- ---------------------------------------------------------------------------------------------------------------
-- golden vectors for the TypeScript twin
-- ---------------------------------------------------------------------------------------------------------------

/-- Frozen-wait cases: (name, running per step, stable per step, hover). The trace is the first 64 steps, the wait the one over
that finite trace (`waitList`; a step past the end is spent).

$$\text{frozenCases} = [(n_k, \mathit{run}^k, \mathit{st}^k, \mathit{hov}^k)]_k$$ -/
def frozenCases : List (String × List Nat × List Nat × Bool) :=
  [ ("a page that is quiet from the first step", List.replicate 64 0, (List.range 64), false),
    ("a quiet page with the pointer inside", List.replicate 64 0, (List.range 64), true),
    ("a lerp that never gets quiet", List.replicate 64 0, List.replicate 64 0, false),
    ("a finite animation that ends at step 10", (List.range 64).map (fun i => if i < 10 then 1 else 0),
      (List.range 64).map (fun i => if i < 10 then 0 else i - 10), false),
    ("settles at the last step of the budget", List.replicate 64 0, (List.range 64).map (fun i => if i < 60 then 0 else 3), false),
    ("settles one step after the budget", List.replicate 64 0, (List.range 64).map (fun i => if i < 61 then 0 else 3), false) ]

/-- The frozen trace of a case: observation `i` has `frames = i` and `t = Δ i`.

$$\operatorname{trace}(\mathit{run}, \mathit{st}, \mathit{hov}) = [o_i]_{i < \min(|\mathit{run}|, |\mathit{st}|)}$$ -/
def frozenTrace (run stable : List Nat) (hov : Bool) : List Obs :=
  (List.range (min run.length stable.length)).map (frozenObs (fun i => run.getD i 0) (fun i => stable.getD i 0) hov)

/-- Freeze cases: (name, animation). Finite and infinite, with and without a delay.

$$\text{freezeCases} = [(n_k, a_k)]_k$$ -/
def freezeCases : List (String × AnimSpec) :=
  [ ("a finite animation goes to its end", { dur := 400, delay := 0, iter := .finite 1, elapsed := 120 }),
    ("a finite animation with a delay", { dur := 300, delay := 200, iter := .finite 1, elapsed := 0 }),
    ("a finite animation of two iterations", { dur := 250, delay := 0, iter := .finite 2, elapsed := 600 }),
    ("an infinite animation is paused in the middle of its first iteration", { dur := 3000, delay := 0, iter := .infinite, elapsed := 7123 }),
    ("an infinite animation with a delay", { dur := 1000, delay := 150, iter := .infinite, elapsed := 40 }),
    ("an odd duration rounds down", { dur := 1001, delay := 0, iter := .infinite, elapsed := 0 }) ]

/-- The JSON of an animation spec; an infinite count is `null`, the way `getComputedTiming().iterations` is `Infinity` in
the page (serialised as `null`).

$$a \mapsto \{\mathit{dur}, \mathit{delay}, \mathit{iterations}, \mathit{elapsed}\}$$ -/
def specJson (a : AnimSpec) : Json :=
  Json.mkObj [("dur", toJson a.dur), ("delay", toJson a.delay),
    ("iterations", match a.iter with | .finite n => toJson n | .infinite => Json.null), ("elapsed", toJson a.elapsed)]

/-- One golden line per case: frozen waits, then freeze passes.

$$\text{lines} = [\ell_{\mathrm{frozen}}(c)]_c \mathbin{+\!\!+} [\ell_{\mathrm{freeze}}(c)]_c$$ -/
def goldenLines : List String :=
  frozenCases.map (fun (n, run, st, hov) =>
    (Json.mkObj [("kind", "frozenWait"), ("name", toJson n), ("policy", policyJson gatePolicy), ("stepMs", toJson stepMs),
      ("run", toJson run), ("stable", toJson st), ("hover", toJson hov),
      ("outcome", toJson (outcomeText (waitList gatePolicy (frozenTrace run st hov))))]).compress)
  ++ freezeCases.map (fun (n, a) =>
    (Json.mkObj [("kind", "freeze"), ("name", toJson n), ("anim", specJson a),
      ("freezeTime", toJson (freezeTime a)), ("running", toJson (isRunning (freezeAct a))),
      ("runningBefore", toJson (isRunning a))]).compress)

/-- The exact bytes of `packages/contracts/golden/gate/freeze.jsonl`.

$$\text{goldenText} = \mathbin{+\!\!+}_{\ell \in \text{goldenLines}} (\ell \mathbin{+\!\!+} \texttt{newline})$$ -/
def goldenText : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- Command-line driver: print the golden text, or with `--check <file>` exit 0 when the file holds exactly these bytes.

$$\operatorname{run}(\mathit{args}) = 0 \iff \text{no mismatch}$$ -/
def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"freeze golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"freeze golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

-- pins of the vectors (the proofs above are the statement)
#guard waitList gatePolicy (frozenTrace (List.replicate 64 0) (List.range 64) false) == .settled 3
#guard waitList gatePolicy (frozenTrace (List.replicate 64 0) (List.range 64) true) == .unsettled
#guard freezeTime { dur := 3000, delay := 0, iter := .infinite, elapsed := 0 } == 1500
#guard freezeTime { dur := 400, delay := 0, iter := .finite 1, elapsed := 0 } == 400

end Fw.Gate.Freeze
