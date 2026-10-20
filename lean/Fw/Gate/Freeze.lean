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
  (`settled_frozen_anims`).

  Round 3 adds the instants (section Instants): every observation of a run is read at an absolute fake time `instant`,
  the same in both arms whatever prepare or mount steps one arm ran before (`both_arms_same_instant`,
  `mount_same_instant`); a stage that does not fit its slot is flagged unsettled, never silently read at another time
  (`overshoot_flagged`, `unfit_never_pass`). Golden vectors for the TypeScript twin close the file.
-/
import Lean.Data.Json
import Fw.Gate.Settle

namespace Fw.Gate.Freeze
open Lean Fw.Gate.Settle

/-- The step of the frozen clock: one 60 Hz frame, in milliseconds (the clock of a requestAnimationFrame in the page). -/
def stepMs : Nat := 16

/-- The observation after `i` steps of the frozen clock: the frame count is the step count and the time is the step count
times the step. Only `running` and `stable` (functions of the step index), and the hover flag, come from the page. -/
def frozenObs (run stable : Nat → Nat) (hov : Bool) (i : Nat) : Obs :=
  { running := run i, frames := i, stable := stable i, hoverInside := hov, t := stepMs * i }

/-- Under the frozen clock the time of an observation is a function of its step index: a slower machine does not change it. -/
theorem frozenObs_clock (run stable : Nat → Nat) (hov : Bool) (i : Nat) :
    (frozenObs run stable hov i).t = stepMs * i ∧ (frozenObs run stable hov i).frames = i := ⟨rfl, rfl⟩

/-- The decision `settled` does not read the time: the clock cannot change what settled means. -/
theorem settled_congr (p : Policy) (o : Obs) (t' : Nat) : settled p { o with t := t' } = settled p o := rfl

/-- The budget of an observation under the frozen clock: the time bound or the frame bound. -/
theorem spent_frozen (p : Policy) (run stable : Nat → Nat) (hov : Bool) (i : Nat) :
    spent p (frozenObs run stable hov i) = true ↔ p.timeoutMs < stepMs * i ∨ p.maxFrames < i := by
  show (decide (p.timeoutMs < stepMs * i) || decide (p.maxFrames < i)) = true ↔ _
  rw [Bool.or_eq_true, decide_eq_true_eq, decide_eq_true_eq]

/-- When the frame budget fits in the time budget (`Δ F ≤ T`), the frame budget alone ends a frozen wait: the time
bound never spends an observation first, so the outcome does not depend on the timeout at all. -/
theorem spent_frozen_frames (p : Policy) (run stable : Nat → Nat) (hov : Bool) (i : Nat)
    (h : stepMs * p.maxFrames ≤ p.timeoutMs) :
    spent p (frozenObs run stable hov i) = true ↔ p.maxFrames < i := by
  rw [spent_frozen]
  simp only [stepMs] at h ⊢
  omega

/-- The gate policy fits: 60 frames of 16 ms are 960 ms, far inside the 30 s timeout. -/
theorem gatePolicy_frozen : stepMs * gatePolicy.maxFrames ≤ gatePolicy.timeoutMs := by
  simp [stepMs, gatePolicy]

/-- Two frozen pages that look the same for the first `F + 2` steps (the same running count and quiet-frame count at each, the same
hover flag) have the same wait: the answer is a function of the page's steps alone, whichever machine ran them and
however long it took. -/
theorem wait_frozen_agree (p : Policy) (run stable run' stable' : Nat → Nat) (hov : Bool)
    (h : ∀ m, m ≤ p.maxFrames + 1 → run m = run' m ∧ stable m = stable' m) :
    wait p (frozenObs run stable hov) = wait p (frozenObs run' stable' hov) := by
  apply wait_stops_by_frames p _ _ (fun i => Nat.le_refl i)
  intro m hm
  obtain ⟨h1, h2⟩ := h m hm
  simp [frozenObs, h1, h2]

/-- The frozen wait settles exactly when some step inside the frame budget is settled (and the budget fits the time bound).
So the settled ratio under the frozen clock is a statement about the page's first `F` frames only. -/
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
The same trajectory under the frozen clock gives the same outcome on both. -/
theorem real_clock_machine_dependent :
    wait gatePolicy (fun i => { running := 0, frames := i, stable := i, hoverInside := false, t := 1 * i }) = .settled 3 ∧
    wait gatePolicy (fun i => { running := 0, frames := i, stable := i, hoverInside := false, t := 20000 * i }) = .unsettled := by
  constructor <;> decide

/-- The same trajectories under the frozen clock agree (the time is not a free input any more). -/
theorem frozen_machine_independent :
    wait gatePolicy (frozenObs (fun _ => 0) (fun i => i) false) = .settled 3 := by decide

-- ---------------------------------------------------------------------------------------------------------------
-- the freeze pass over CSS and Web animations
-- ---------------------------------------------------------------------------------------------------------------

/-- The iteration count of an animation: a finite number or infinite. -/
inductive Iter where
  | finite (n : Nat)
  | infinite
  deriving DecidableEq, Repr

/-- One animation as the freeze pass reads it from `getComputedTiming()`: duration and delay (ms), iteration count, and its
current time `elapsed` (ms since its timeline origin, the quantity the freeze sets). -/
structure AnimSpec where
  dur : Nat
  delay : Nat
  iter : Iter
  elapsed : Nat
  deriving DecidableEq, Repr

/-- The current time the freeze pass gives an animation: a finite one its end (`δ + n d`, what `finish()` does), an
infinite one (which has no end) the middle of its first iteration (`δ + ⌊ d/2 ⌋`, where it is paused). -/
def freezeTime (a : AnimSpec) : Nat :=
  match a.iter with
  | .finite n => a.delay + n * a.dur
  | .infinite => a.delay + a.dur / 2

/-- The freeze pass on one animation: set its current time to `freezeTime`. -/
def freezeAct (a : AnimSpec) : AnimSpec := { a with elapsed := freezeTime a }

/-- The frozen state of an animation does not depend on where it was when it was frozen (its current time, which depends on how
long the machine took): two animations with the same timing freeze to the same state. -/
theorem freeze_independent_of_elapsed (a : AnimSpec) (e e' : Nat) :
    freezeAct { a with elapsed := e } = freezeAct { a with elapsed := e' } := rfl

/-- The freeze pass is idempotent: freezing at every step is the same as freezing once. -/
theorem freeze_idem (a : AnimSpec) : freezeAct (freezeAct a) = freezeAct a := rfl

/-- An infinite animation is paused inside its first iteration, not on an iteration boundary: where the pause lands cannot
depend on the direction or the count of iterations. -/
theorem freeze_infinite_inside (a : AnimSpec) (h : a.iter = .infinite) (hd : 0 < a.dur) :
    a.delay ≤ freezeTime a ∧ freezeTime a < a.delay + a.dur := by
  simp only [freezeTime, h]
  omega

/-- Running as the settle wait counts it: a finite animation (or transition) whose current time is before its end. An
infinite one is never counted (the page filters on `Number.isFinite(iterations)`). -/
def isRunning (a : AnimSpec) : Bool :=
  match a.iter with
  | .finite n => decide (a.elapsed < a.delay + n * a.dur)
  | .infinite => false

/-- The running count of a list of animations. -/
def runCountA (as : List AnimSpec) : Nat := (as.filter isRunning).length

/-- After the freeze pass nothing finite runs: the running count of the frozen document is 0, whatever the animations were
doing and wherever the machine had got them. -/
theorem runCount_freeze (as : List AnimSpec) : runCountA (as.map freezeAct) = 0 := by
  unfold runCountA
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro a ha
  obtain ⟨b, _, rfl⟩ := List.mem_map.1 ha
  rcases b with ⟨d, dl, it, e⟩
  cases it <;> simp [isRunning, freezeAct, freezeTime]

/-- What "settled" means under the frozen clock: with the freeze pass done at the observation, the running count is 0 and
the decision reduces to the rest of its definition, enough frames since the resize, enough quiet frames in a row, the pointer
parked. -/
theorem settled_frozen_anims (p : Policy) (as : List AnimSpec) (fr st t : Nat) (hov : Bool) :
    settled p { running := runCountA (as.map freezeAct), frames := fr, stable := st, hoverInside := hov, t := t } = true ↔
      p.minFrames ≤ fr ∧ p.minStable ≤ st ∧ hov = false := by
  rw [runCount_freeze]
  simp [settled, and_assoc]

-- ---------------------------------------------------------------------------------------------------------------
-- the fake instant of an observation: a function of the stop alone, the same in both arms
-- ---------------------------------------------------------------------------------------------------------------

/-- The fake time a settle wait can read: it stops by observation `F + 1` (`wait_stops_by_frames`), so it advances the clock by
at most `(F + 1) Δ`. -/
def settleSpan (p : Policy) : Nat := stepMs * (p.maxFrames + 1)

/-- The gate policy's span is 976 ms. -/
theorem settleSpan_gate : settleSpan gatePolicy = 976 := by simp [settleSpan, stepMs, gatePolicy]

/-- The absolute fake time (ms since the freeze) both arms hold to at the end of the ready wait, before a stop's first settle wait. -/
def readyTo : Nat := 10000

/-- The fake time a live resize advances the clock by, in both arms (debounced resize handlers and timers have run). -/
def postResize : Nat := 1000

/-- Offset of the first observation of a stop from the stop's base: room for the post-resize advance and the longest settle wait. -/
def mainOff : Nat := 2000

/-- Length of one observation slot: the most fake time the work between two observations may take before the next instant. -/
def slotMs : Nat := 4000

/-- The post-resize advance and the longest settle wait fit before the first observation of a stop. -/
theorem mainOff_fits : postResize + settleSpan gatePolicy ≤ mainOff := by
  simp [postResize, mainOff, settleSpan, stepMs, gatePolicy]

/-- **The instant of an observation.** For a stop with base `b`, the observation of rank `k` is read at the absolute fake time
`b + m + σ k`: it depends on the stop base and the rank only, never on what the arm did before. -/
def instant (b k : Nat) : Nat := b + mainOff + slotMs * k

/-- The ranks of a stop: the first reading is rank 0, overlay part `j` is rank `1 + j`, the mount parts (read together) rank
`n_o + 1`, and the part with index `q` read after it was brought into view rank `n_o + 2 + q`. The ranks are positions in a list
fixed by the part list (the union of both arms' prepare steps), so they are the same in both arms. The parts brought into view are
the union over both arms of the parts either arm read skipped (src/view.mjs `viewUnion`), so a part is read at its view rank in both
arms or in neither. -/
def ovRank (j : Nat) : Nat := 1 + j

/-- The rank of the mount reading after `n_o` overlay readings. -/
def mountRank (nOv : Nat) : Nat := nOv + 1

/-- The rank of the reading of part `q` after it was brought into view. -/
def viewRank (nOv q : Nat) : Nat := nOv + 2 + q

/-- The ranks are in the order a stop runs its readings: main, then overlays, then mount, then views. -/
theorem rank_order (nOv j q : Nat) (h : j < nOv) :
    0 < ovRank j ∧ ovRank j < mountRank nOv ∧ mountRank nOv < viewRank nOv q := by
  simp only [ovRank, mountRank, viewRank]
  omega

/-- Instants of one stop are strictly increasing in the rank. -/
theorem instant_lt (b k k' : Nat) (h : k < k') : instant b k < instant b k' := by
  simp only [instant, slotMs]
  omega

/-- The length of a stop with `n = n_o + n_v` overlay and view readings: its ranks are `0 .. n + 1`, and the last one has a whole
slot after it. -/
def stopSpan (n : Nat) : Nat := mainOff + slotMs * (n + 2)

/-- **The base of stop `i` of a sweep** (stop 0 is the first load): an absolute fake time that depends on the stop index and the
reading count alone, so both arms start every stop at the same instant however long the previous one took. -/
def stopBase (i n : Nat) : Nat := readyTo + i * stopSpan n

/-- The next stop starts one slot after the last rank of this one. -/
theorem stopBase_succ (i n : Nat) : stopBase (i + 1) n = instant (stopBase i n) (n + 2) := by
  simp only [stopBase, stopSpan, instant]
  rw [Nat.add_mul, Nat.one_mul]
  omega

/-- Every reading of a stop is before the next stop, and the last rank leaves a whole slot. -/
theorem instant_before_next (i n k : Nat) (h : k ≤ n + 1) :
    instant (stopBase i n) k + slotMs ≤ stopBase (i + 1) n := by
  rw [stopBase_succ]
  simp only [instant, slotMs]
  have : 4000 * k + 4000 ≤ 4000 * (n + 2) := by omega
  omega

/-- The stop bases strictly increase with the stop index, and the first reading of a stop comes after its base. -/
theorem stopBase_lt (i n : Nat) : stopBase i n < stopBase (i + 1) n ∧ stopBase i n < instant (stopBase i n) 0 := by
  rw [stopBase_succ]
  simp only [instant, mainOff, slotMs]
  omega

/-- One step of the fake clock of an arm: the arm advances it by a relative amount (`rel`: a frame, a sleep, any work whose length
depends on the page), or the harness holds it to an absolute instant (`hold`: nothing happens when it is already past). -/
inductive Step where
  | rel (d : Nat)
  | hold (t : Nat)
  deriving DecidableEq, Repr

/-- The clock after one step. -/
def Step.apply (c : Nat) : Step → Nat
  | .rel d => c + d
  | .hold t => max c t

/-- The clock after a list of steps. -/
def clockAfter (c : Nat) (ss : List Step) : Nat := ss.foldl Step.apply c

/-- A stage of one arm: the work it does since its previous reading (any steps, and different in the two arms: the original runs
the mount stage, the rewrite none), then the reading at the absolute instant `T` (a hold). -/
abbrev Stage := List Step × Nat

/-- The readings of an arm over its stages: after each stage's work the harness holds the clock to the stage's instant, and the
page is read at the clock then. -/
def readings : Nat → List Stage → List Nat
  | _, [] => []
  | c, (ss, T) :: rest => max (clockAfter c ss) T :: readings (max (clockAfter c ss) T) rest

/-- The stages of an arm fit when each one's work ends at or before its instant. A stage that does not fit is read later than its
instant: the arm is out of step with every arm that did fit, and the harness flags the sample. -/
def fits : Nat → List Stage → Bool
  | _, [] => true
  | c, (ss, T) :: rest => decide (clockAfter c ss ≤ T) && fits T rest

/-- The instants an arm is asked for. -/
def targets (st : List Stage) : List Nat := st.map (·.2)

/-- **A fitting arm is read at exactly the instants asked for, whatever work it did before.** -/
theorem readings_of_fits : ∀ (st : List Stage) (c : Nat), fits c st = true → readings c st = targets st := by
  intro st
  induction st with
  | nil => intro c _; rfl
  | cons s rest ih =>
    intro c h
    obtain ⟨ss, T⟩ := s
    simp only [fits, Bool.and_eq_true, decide_eq_true_eq] at h
    simp only [readings, targets, List.map_cons]
    have hm : max (clockAfter c ss) T = T := Nat.max_eq_right h.1
    rw [hm]
    exact congrArg (T :: ·) (ih T h.2)

/-- A reading equal to its instant is exactly a fitting stage (the check the harness makes after each hold: the clock it reads is
the instant asked for). -/
theorem fits_of_readings : ∀ (st : List Stage) (c : Nat), readings c st = targets st → fits c st = true := by
  intro st
  induction st with
  | nil => intro c _; rfl
  | cons s rest ih =>
    intro c h
    obtain ⟨ss, T⟩ := s
    simp only [readings, targets, List.map_cons, List.cons.injEq] at h
    obtain ⟨h1, h2⟩ := h
    have hle : clockAfter c ss ≤ T := by
      have := Nat.le_max_left (clockAfter c ss) T
      omega
    simp only [fits, Bool.and_eq_true, decide_eq_true_eq]
    refine ⟨hle, ih T ?_⟩
    have hm : max (clockAfter c ss) T = T := Nat.max_eq_right hle
    rw [hm] at h2
    exact h2

/-- **Both arms are read at the same instants.** Two arms asked for the same instants, each fitting, are read at the same clock at
every observation, whatever steps they took between observations and wherever their clocks started. This includes the mount
stage that only the original runs. -/
theorem both_arms_same_instant (sa sb : List Stage) (ca cb : Nat) (h : targets sa = targets sb)
    (fa : fits ca sa = true) (fb : fits cb sb = true) : readings ca sa = readings cb sb := by
  rw [readings_of_fits sa ca fa, readings_of_fits sb cb fb, h]

/-- The mount stage of the original as the page runs it (`prepareInPage` stage `ready`): three frames, `w` sleeps of 50 ms while
the awaited node is missing, three frames, 300 ms, then the idle wait of `i` frames. The rewrite has no mount step. -/
def mountWork (w i : Nat) : List Step :=
  [.rel (3 * stepMs), .rel (50 * w), .rel (3 * stepMs), .rel 300, .rel (stepMs * i)]

/-- The mount stage takes this much fake time. -/
def mountSpan (w i : Nat) : Nat := 3 * stepMs + 50 * w + 3 * stepMs + 300 + stepMs * i

/-- The clock after the mount stage is its start plus the span. -/
theorem clockAfter_mountWork (c w i : Nat) : clockAfter c (mountWork w i) = c + mountSpan w i := by
  simp only [clockAfter, mountWork, mountSpan, List.foldl, Step.apply]
  omega

/-- A mount stage that takes at most one slot ends before the next rank's instant. -/
theorem mount_stage_fits (b k w i : Nat) (h : mountSpan w i ≤ slotMs) :
    clockAfter (instant b k) (mountWork w i) ≤ instant b (k + 1) := by
  rw [clockAfter_mountWork]
  simp only [instant, slotMs] at h ⊢
  omega

/-- **The original's mount stage does not move the reading.** The original runs the mount stage between its overlay readings and
its mount reading and the rewrite does not; both are read at the mount instant, for every start before the previous instant, when
the stage takes at most one slot (a stage of 50 ms sleeps for up to `w ≤ 60` and a 60-frame idle wait takes 396 + 3000 + 960 =
4356 ms in the worst case of the budgets, so the gate flags a mount stage that long as not fitting rather than reading it late). -/
theorem mount_same_instant (b k w i ca cb : Nat) (h : mountSpan w i ≤ slotMs)
    (ha : ca ≤ instant b k) (hb : cb ≤ instant b k) :
    readings ca [([], instant b k), (mountWork w i, instant b (k + 1))] =
      readings cb [([], instant b k), ([], instant b (k + 1))] := by
  refine both_arms_same_instant _ _ ca cb rfl ?_ ?_
  · have h2 := mount_stage_fits b k w i h
    simp [fits, clockAfter, List.foldl] at h2 ⊢
    exact ⟨decide_eq_true ha, decide_eq_true h2⟩
  · have : instant b k ≤ instant b (k + 1) := Nat.le_of_lt (instant_lt b k (k + 1) (Nat.lt_succ_self k))
    simp [fits, clockAfter, List.foldl]
    exact ⟨decide_eq_true hb, decide_eq_true this⟩

/-- A stage that overshoots its instant is read late, and is not fitting: the stage of the mount in a page whose wait loop ran
for `w = 80` sleeps is read after the instant, so the sample is flagged. -/
theorem overshoot_flagged :
    fits 0 [(mountWork 80 0, slotMs)] = false ∧ readings 0 [(mountWork 80 0, slotMs)] = [4396] := by
  decide

/-- The outcome a sample takes from its readings: settled when every reading was at its instant, unsettled when one was late. -/
def instantOutcome (ok : Bool) : Outcome := if ok then .settled 0 else .unsettled

/-- **A sample read at the wrong instant never passes.** The harness folds `instantOutcome (fits c st)` into the sample's waits
(that step is glue, not part of this theorem); with a late reading (`fits c st = false`) that outcome is unsettled, so the report is
never pass, and the engine is not a pass (`Fw.Gate.Exit.engineVerdictCS_ne_pass_of_unsettled`). The theorem states the fold. -/
theorem unfit_never_pass (a : Outcome) (ws : List Outcome) (b : Outcome) (e : Bool) :
    report (fold a (instantOutcome false :: ws)) b e ≠ .pass :=
  fold_unsettled_never_pass a _ b e (List.mem_cons_self ..)

/-- When every reading was at its instant the extra outcome changes nothing. -/
theorem fit_keeps_outcome (a : Outcome) (ws : List Outcome) (ha : a ≠ .unsettled) (h : Outcome.unsettled ∉ ws) :
    fold a (instantOutcome true :: ws) = a := by
  apply fold_settled a _ ha
  intro hm
  rcases List.mem_cons.1 hm with e | e
  · simp [instantOutcome] at e
  · exact h e


-- ---------------------------------------------------------------------------------------------------------------
-- which page of a sweep a part is read on
-- ---------------------------------------------------------------------------------------------------------------

/-- The page loads of one arm of a sweep. On the `plain` page the stage that scrolls away and back (the mount stage, `prepareInPage`
stage `ready`) never runs; on the `mounted` page it runs before every reading. -/
inductive SweepPage where
  | plain
  | mounted
  deriving DecidableEq, Repr

/-- The page a part is read on, from whether either arm has a mount step for it: `mounted` when one does, else `plain`.

The original renders a skipped section again (its remembered size, its pain notes' positions, its typing visual's state) when the
page scrolls away and back, and the rewrite does not, so a part that needs no mount must not be read after the excursion (CI run
39130842197: pain.notes, commission, commission.typing in four sweeps). -/
def pageOf (mountOrig mountRewrite : Bool) : SweepPage :=
  if mountOrig || mountRewrite then .mounted else .plain

/-- Whether a page runs the mount stage. -/
def runsMount : SweepPage → Bool
  | .mounted => true
  | .plain => false

/-- **A part with no mount step is never read after the scroll excursion.** -/
theorem plain_part_has_no_history (mo mr : Bool) (h1 : mo = false) (h2 : mr = false) :
    runsMount (pageOf mo mr) = false := by
  subst h1 h2; rfl

/-- A part that an arm mounts is read on a page where the mount stage runs. -/
theorem mounted_part_gets_mount (mo mr : Bool) (h : mo = true ∨ mr = true) : runsMount (pageOf mo mr) = true := by
  rcases h with rfl | rfl <;> simp [pageOf, runsMount]

/-- The number of parts (each with its two mount flags) read on a page. -/
def pageCount (ps : List (String × Bool × Bool)) (g : SweepPage) : Nat :=
  (ps.filter fun x => pageOf x.2.1 x.2.2 == g).length

/-- **The two pages read every part exactly once.** The parts of the pages add up to all parts. -/
theorem pages_partition (ps : List (String × Bool × Bool)) :
    pageCount ps .plain + pageCount ps .mounted = ps.length := by
  induction ps with
  | nil => rfl
  | cons x xs ih =>
    simp only [pageCount, List.filter_cons, List.length_cons] at ih ⊢
    generalize pageOf x.2.1 x.2.2 = g
    cases g <;> simp <;> omega

/-- Page cases: (mount step on the original, on the rewrite). -/
def pageCases : List (Bool × Bool) :=
  [ (false, false), (true, false), (false, true), (true, true) ]

-- ---------------------------------------------------------------------------------------------------------------
-- golden vectors for the TypeScript twin
-- ---------------------------------------------------------------------------------------------------------------

/-- Frozen-wait cases: (name, running per step, stable per step, hover). The trace is the first 64 steps, the wait the one over
that finite trace (`waitList`; a step past the end is spent). -/
def frozenCases : List (String × List Nat × List Nat × Bool) :=
  [ ("a page that is quiet from the first step", List.replicate 64 0, (List.range 64), false),
    ("a quiet page with the pointer inside", List.replicate 64 0, (List.range 64), true),
    ("a lerp that never gets quiet", List.replicate 64 0, List.replicate 64 0, false),
    ("a finite animation that ends at step 10", (List.range 64).map (fun i => if i < 10 then 1 else 0),
      (List.range 64).map (fun i => if i < 10 then 0 else i - 10), false),
    ("settles at the last step of the budget", List.replicate 64 0, (List.range 64).map (fun i => if i < 60 then 0 else 3), false),
    ("settles one step after the budget", List.replicate 64 0, (List.range 64).map (fun i => if i < 61 then 0 else 3), false) ]

/-- The frozen trace of a case: observation `i` has `frames = i` and `t = Δ i`. -/
def frozenTrace (run stable : List Nat) (hov : Bool) : List Obs :=
  (List.range (min run.length stable.length)).map (frozenObs (fun i => run.getD i 0) (fun i => stable.getD i 0) hov)

/-- Freeze cases: (name, animation). Finite and infinite, with and without a delay. -/
def freezeCases : List (String × AnimSpec) :=
  [ ("a finite animation goes to its end", { dur := 400, delay := 0, iter := .finite 1, elapsed := 120 }),
    ("a finite animation with a delay", { dur := 300, delay := 200, iter := .finite 1, elapsed := 0 }),
    ("a finite animation of two iterations", { dur := 250, delay := 0, iter := .finite 2, elapsed := 600 }),
    ("an infinite animation is paused in the middle of its first iteration", { dur := 3000, delay := 0, iter := .infinite, elapsed := 7123 }),
    ("an infinite animation with a delay", { dur := 1000, delay := 150, iter := .infinite, elapsed := 40 }),
    ("an odd duration rounds down", { dur := 1001, delay := 0, iter := .infinite, elapsed := 0 }) ]

/-- The JSON of an animation spec; an infinite count is `null`, the way `getComputedTiming().iterations` is `Infinity` in
the page (serialised as `null`). -/
def specJson (a : AnimSpec) : Json :=
  Json.mkObj [("dur", toJson a.dur), ("delay", toJson a.delay),
    ("iterations", match a.iter with | .finite n => toJson n | .infinite => Json.null), ("elapsed", toJson a.elapsed)]

/-- Instant cases: (stop index, reading count, rank). -/
def instantCases : List (Nat × Nat × Nat) :=
  [ (0, 0, 0), (0, 0, 1), (0, 0, 2), (1, 0, 0), (1, 0, 1), (7, 0, 0), (0, 2, 0), (0, 2, 3), (0, 2, 4), (3, 2, 4), (3, 5, 6) ]

/-- The JSON of a step: `["rel", d]` or `["hold", t]`. -/
def stepJson : Step → Json
  | .rel d => Json.arr #["rel", toJson d]
  | .hold t => Json.arr #["hold", toJson t]

/-- The JSON of a stage: its steps and its instant. -/
def stageJson (s : Stage) : Json :=
  Json.mkObj [("work", Json.arr (s.1.map stepJson).toArray), ("at", toJson s.2)]

/-- Reading cases: (name, start clock, stages). The original with its mount stage and the rewrite without one, an arm that
overshoots, an arm that starts late, a hold that is already past. -/
def readingCases : List (String × Nat × List Stage) :=
  [ ("rewrite without a mount stage", 10000, [([], instant 10000 0), ([], instant 10000 1)]),
    ("original with a mount stage", 10000, [([], instant 10000 0), (mountWork 3 2, instant 10000 1)]),
    ("original with a long wait loop", 10000, [([], instant 10000 0), (mountWork 80 0, instant 10000 1)]),
    ("relative work only", 0, [([.rel 100, .rel 200], 1000), ([.rel 5], 1500)]),
    ("a hold already past", 5000, [([.hold 100], 1000), ([], 2000)]),
    ("a hold between relative steps", 0, [([.rel 300, .hold 1000, .rel 20], 1000)]),
    ("the clock is past the first instant", 2000, [([], 1000), ([], 3000)]),
    ("no stages", 7, []) ]

/-- One golden line per case: frozen waits, then freeze passes, the clock constants, instants, readings, then pages. -/
def goldenLines (_ : Unit := ()) : List String :=
  frozenCases.map (fun (n, run, st, hov) =>
    (Json.mkObj [("kind", "frozenWait"), ("name", toJson n), ("policy", policyJson gatePolicy), ("stepMs", toJson stepMs),
      ("run", toJson run), ("stable", toJson st), ("hover", toJson hov),
      ("outcome", toJson (outcomeText (waitList gatePolicy (frozenTrace run st hov))))]).compress)
  ++ freezeCases.map (fun (n, a) =>
    (Json.mkObj [("kind", "freeze"), ("name", toJson n), ("anim", specJson a),
      ("freezeTime", toJson (freezeTime a)), ("running", toJson (isRunning (freezeAct a))),
      ("runningBefore", toJson (isRunning a))]).compress)
  ++ [(Json.mkObj [("kind", "clock"), ("stepMs", toJson stepMs), ("readyTo", toJson readyTo), ("postResize", toJson postResize),
      ("mainOff", toJson mainOff), ("slotMs", toJson slotMs)]).compress]
  ++ instantCases.map (fun (i, n, k) =>
    (Json.mkObj [("kind", "instant"), ("stop", toJson i), ("readings", toJson n), ("rank", toJson k),
      ("base", toJson (stopBase i n)), ("value", toJson (instant (stopBase i n) k))]).compress)
  ++ readingCases.map (fun (n, c, st) =>
    (Json.mkObj [("kind", "readings"), ("name", toJson n), ("start", toJson c),
      ("stages", Json.arr (st.map stageJson).toArray), ("fits", toJson (fits c st)),
      ("readings", toJson (readings c st))]).compress)
  ++ pageCases.map (fun (mo, mr) =>
    (Json.mkObj [("kind", "page"), ("mountOrig", toJson mo), ("mountRewrite", toJson mr),
      ("page", toJson (match pageOf mo mr with | .plain => "plain" | .mounted => "mounted")),
      ("runsMount", toJson (runsMount (pageOf mo mr)))]).compress)

/-- The exact bytes of `packages/contracts/golden/gate/freeze.jsonl`. -/
def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- Command-line driver: print the golden text (exit 0), or with `--check <file>` exit 0 exactly when the file holds these bytes
and 1 otherwise. -/
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
