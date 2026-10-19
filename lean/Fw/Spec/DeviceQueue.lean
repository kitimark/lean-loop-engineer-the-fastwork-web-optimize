/-!
# The phone job queue (priority with aging, mutual exclusion, session window)

Ported from the kickoff scratch `03-inventory/Auto/DeviceQueue.lean` (proofs unchanged).
v1: ~230 hand moves of the queue, 40 scheduler incidents, I-011 (short lane starves),
I-049 (readers starve). v2: priority is a pure function of (job class, the user's list, wait);
the phone runs at most one job; jobs start only if they fit inside the session the user booked.
-/
namespace Fw.DeviceQueue

/-- A queued phone job: arrival order (unique, assigned by the single writer), enqueue time in
seconds, base priority `R · class + rank` (smaller = more urgent; class: user
step 0, calibration 1, X/P 2, spot-check 3) and maximum duration in seconds.
-/
structure Job where
  seq  : Nat   -- arrival order, unique (assigned by the single writer)
  enq  : Nat   -- enqueue time, s
  base : Nat   -- R·class + rank (smaller = more urgent)
  dur  : Nat   -- max duration, s
deriving Repr, DecidableEq

/-- The aging step: seconds of waiting per priority level gained. -/
def A : Nat := 300

/-- Effective priority at time `t`: the base priority, lowered by one level per `A` seconds of
waiting, never below 0.

Edge: `∸` is truncated subtraction on `ℕ`; a time before the enqueue time counts as no
waiting.
-/
def eff (t : Nat) (j : Job) : Nat := j.base - min j.base ((t - j.enq) / A)

/-- `j` goes no later than `k` at time `t`: lower effective priority first, ties by arrival order. -/
def before (t : Nat) (j k : Job) : Bool :=
  decide (eff t j < eff t k ∨ (eff t j = eff t k ∧ j.seq ≤ k.seq))

/-- The order is total: of any two jobs, one goes no later than the other. -/
theorem before_total (t : Nat) (j k : Job) : before t j k = true ∨ before t k j = true := by
  simp only [before, decide_eq_true_eq]; omega

/-- The order is transitive. -/
theorem before_trans (t : Nat) {a b c : Job} (h1 : before t a b = true) (h2 : before t b c = true) :
    before t a c = true := by
  simp only [before, decide_eq_true_eq] at *; omega

/-- The order is reflexive. -/
theorem before_refl (t : Nat) (j : Job) : before t j j = true := by
  simp [before]

/-- Pick the most urgent job: a left fold keeping the best so far (a later job replaces the best
only if it goes no later than it).
-/
def pickFrom (t : Nat) (best : Job) : List Job → Job
  | [] => best
  | k :: ks => pickFrom t (if before t k best then k else best) ks

/-- Pick from a queue: nothing from an empty queue, otherwise `pickFrom` seeded with the head. -/
def pick (t : Nat) : List Job → Option Job
  | [] => none
  | j :: js => some (pickFrom t j js)

/-- The fold returns its seed or one of the jobs it scanned. -/
theorem pickFrom_mem (t : Nat) (best : Job) (ks : List Job) :
    pickFrom t best ks = best ∨ pickFrom t best ks ∈ ks := by
  induction ks generalizing best with
  | nil => simp [pickFrom]
  | cons k ks ih =>
    simp only [pickFrom]
    split
    · rcases ih k with h | h <;> simp [h]
    · rcases ih best with h | h <;> simp [h]

/-- The fold's result goes no later than its seed and every job it scanned. -/
theorem pickFrom_min (t : Nat) (best : Job) (ks : List Job) :
    before t (pickFrom t best ks) best = true ∧ ∀ k ∈ ks, before t (pickFrom t best ks) k = true := by
  induction ks generalizing best with
  | nil => simp [pickFrom, before_refl]
  | cons k ks ih =>
    simp only [pickFrom]
    split
    · rename_i hkb
      obtain ⟨h1, h2⟩ := ih k
      refine ⟨before_trans t h1 hkb, ?_⟩
      intro x hx; simp at hx; rcases hx with rfl | hx
      · exact h1
      · exact h2 x hx
    · rename_i hkb
      obtain ⟨h1, h2⟩ := ih best
      have hbk : before t best k = true := by
        rcases before_total t k best with h | h
        · exact absurd h hkb
        · exact h
      refine ⟨h1, ?_⟩
      intro x hx; simp at hx; rcases hx with rfl | hx
      · exact before_trans t h1 hbk
      · exact h2 x hx

/-- `pick` returns a queued job. -/
theorem pick_mem {t : Nat} {q : List Job} {j : Job} (h : pick t q = some j) : j ∈ q := by
  cases q with
  | nil => cases h
  | cons a as =>
    simp only [pick, Option.some.injEq] at h; subst h
    rcases pickFrom_mem t a as with h | h
    · rw [h]; simp
    · simp [h]

/-- No queued job goes before the picked one. -/
theorem pick_min {t : Nat} {q : List Job} {j : Job} (h : pick t q = some j) :
    ∀ k ∈ q, before t j k = true := by
  cases q with
  | nil => cases h
  | cons a as =>
    simp only [pick, Option.some.injEq] at h; subst h
    intro k hk; simp at hk
    obtain ⟨h1, h2⟩ := pickFrom_min t a as
    rcases hk with rfl | hk
    · exact h1
    · exact h2 k hk

/-- **Aging.** Once `j` has waited `A·base(j)` seconds it goes before every job that arrived after
it, whatever their class, and none of them goes before it (a key lemma, not starvation-freedom of
`dispatch`: it says nothing about older jobs, and a job that fits no window is never started, see
`unfit_never_starts`).
-/
theorem aged_beats_newer (t : Nat) (j k : Job) (hage : j.enq + A * j.base ≤ t)
    (hseq : j.seq < k.seq) : before t j k = true ∧ before t k j = false := by
  have h0 : eff t j = 0 := by
    unfold eff
    have : j.base ≤ (t - j.enq) / A := by
      apply (Nat.le_div_iff_mul_le (by decide)).mpr
      have := Nat.mul_comm A j.base; omega
    omega
  simp only [before, h0]
  constructor
  · simp; omega
  · simp; omega

/-! ## The phone: mutual exclusion and the booked window -/

/-- The phone: at most one running job with its start time (by construction), the queue, and the
session the user booked (start, end) in seconds, if any.
-/
structure Phone where
  running : Option (Job × Nat) := none   -- the job and its start time: at most one, by construction
  queue   : List Job := []
  window  : Option (Nat × Nat) := none   -- the session the user booked: [start, end)

/-- The first version (kept for the record): it blocks the head of the line. If the most urgent job
does not fit the rest of the window, nothing starts, even when a shorter job would fit.

Here `Q ⊖ j` removes the first occurrence of `j`.
-/
def dispatchHoL (p : Phone) (t : Nat) : Phone :=
  match p.running, p.window, pick t p.queue with
  | none, some (s, e), some j =>
    if s ≤ t ∧ t + j.dur ≤ e then { p with running := some (j, t), queue := p.queue.erase j } else p
  | _, _, _ => p

/-- A job fits at `t` in the window from `s` to `e` when the window has started and the job ends
by `e`.
-/
def fits (s e t : Nat) (j : Job) : Bool := decide (s ≤ t ∧ t + j.dur ≤ e)

/-- Start the most urgent job **among those that fit** the booked window (no head-of-line blocking). -/
def dispatch (p : Phone) (t : Nat) : Phone :=
  match p.running, p.window with
  | none, some (s, e) =>
    match pick t (p.queue.filter (fits s e t)) with
    | some j => { p with running := some (j, t), queue := p.queue.erase j }
    | none => p
  | _, _ => p

/-- A busy phone never starts a second job. -/
theorem dispatch_busy (p : Phone) (t : Nat) (r : Job × Nat) (h : p.running = some r) :
    dispatch p t = p := by
  simp [dispatch, h]

/-- Whatever `dispatch` starts is a queued job that fits the booked window, started now, and no
queued job that also fits goes before it.
-/
theorem dispatch_sound (p : Phone) (t : Nat) (j : Job) (t0 : Nat)
    (hfree : p.running = none) (h : (dispatch p t).running = some (j, t0)) :
    t0 = t ∧ j ∈ p.queue ∧
    ∃ s e, p.window = some (s, e) ∧ s ≤ t ∧ t + j.dur ≤ e ∧
      ∀ k ∈ p.queue, fits s e t k = true → before t j k = true := by
  cases hw : p.window with
  | none => simp [dispatch, hfree, hw] at h
  | some se =>
    obtain ⟨s, e⟩ := se
    cases hp : pick t (p.queue.filter (fits s e t)) with
    | none => simp [dispatch, hfree, hw, hp] at h
    | some j' =>
      simp [dispatch, hfree, hw, hp] at h
      rcases h with ⟨rfl, rfl⟩
      have hm := pick_mem hp
      have hmin := pick_min hp
      simp only [List.mem_filter] at hm
      have hf := hm.2
      simp only [fits, decide_eq_true_eq] at hf
      refine ⟨rfl, hm.1, s, e, rfl, hf.1, hf.2, ?_⟩
      intro k hk hkf
      exact hmin k (List.mem_filter.mpr ⟨hk, hkf⟩)

/-- **Work conservation.** If the phone is free, the window is booked, and `dispatch` still starts
nothing, then no queued job fits the rest of the window.
-/
theorem dispatch_conserving (p : Phone) (t s e : Nat)
    (hfree : p.running = none) (hw : p.window = some (s, e))
    (hidle : (dispatch p t).running = none) :
    ∀ k ∈ p.queue, fits s e t k = false := by
  intro k hk
  cases hf : fits s e t k with
  | false => rfl
  | true =>
    exfalso
    have hmem : k ∈ p.queue.filter (fits s e t) := List.mem_filter.mpr ⟨hk, hf⟩
    cases hq : p.queue.filter (fits s e t) with
    | nil => rw [hq] at hmem; cases hmem
    | cons a as =>
      simp [dispatch, hfree, hw, hq, pick] at hidle

/-- **Bounded overtaking.** Once a queued job `j` is fully aged and fits the window, `dispatch` can
start only a job that arrived no later than it (with unique arrival numbers: `j` itself or an
older job), so the jobs that can still go ahead of `j` are the finitely many older ones.
-/
theorem aged_not_overtaken (p : Phone) (t t0 s e : Nat) (j k : Job)
    (hfree : p.running = none) (hw : p.window = some (s, e)) (hj : j ∈ p.queue)
    (hfit : fits s e t j = true) (hage : j.enq + A * j.base ≤ t)
    (h : (dispatch p t).running = some (k, t0)) : k.seq ≤ j.seq := by
  obtain ⟨_, _, s', e', hw', _, _, hmin⟩ := dispatch_sound p t k t0 hfree h
  rw [hw] at hw'
  simp only [Option.some.injEq, Prod.mk.injEq] at hw'
  obtain ⟨rfl, rfl⟩ := hw'
  have hkj := hmin j hj hfit
  apply Nat.le_of_not_lt
  intro hlt
  have := (aged_beats_newer t j k hage hlt).2
  rw [hkj] at this
  cases this

/-- **A job longer than the window starves.** If the booked window is shorter than a job's
duration, `dispatch` never starts that job, at any time, however long it has waited.
-/
theorem unfit_never_starts (p : Phone) (t t0 s e : Nat) (j : Job)
    (hfree : p.running = none) (hw : p.window = some (s, e)) (hshort : e < s + j.dur) :
    (dispatch p t).running ≠ some (j, t0) := by
  intro h
  obtain ⟨_, _, s', e', hw', hs, he, _⟩ := dispatch_sound p t j t0 hfree h
  rw [hw] at hw'
  simp only [Option.some.injEq, Prod.mk.injEq] at hw'
  omega

/-- The clock tick: a running job is stopped when its duration is used up or the window has ended
(the window end is a hard stop); a running job without a window is left alone.
-/
def tick (p : Phone) (now : Nat) : Phone :=
  match p.running, p.window with
  | some (j, t0), some (_, e) => if t0 + j.dur ≤ now ∨ e ≤ now then { p with running := none } else p
  | _, _ => p

/-- Nothing runs past the booked window once the tick at its end has been applied. -/
theorem tick_kills_at_end (p : Phone) (now s e : Nat) (hw : p.window = some (s, e)) (hle : e ≤ now) :
    (tick p now).running = none := by
  cases hr : p.running with
  | none => simp [tick, hr]
  | some r =>
    obtain ⟨j, t0⟩ := r
    simp [tick, hr, hw, hle]

/-! ## Examples (job = ⟨seq, enq, base, dur⟩) -/
-- class wins while fresh: a user step beats a spot-check queued first
#guard pick 10 [⟨0, 0, 300, 900⟩, ⟨1, 0, 0, 120⟩] == some ⟨1, 0, 0, 120⟩
-- a fully aged spot-check beats a new user step
#guard pick (A * 300) [⟨0, 0, 300, 900⟩, ⟨5, A * 300, 0, 60⟩] == some ⟨0, 0, 300, 900⟩
#guard (dispatch { queue := [⟨0, 0, 300, 900⟩, ⟨1, 0, 0, 120⟩], window := some (0, 3600) } 10).running
        == some (⟨1, 0, 0, 120⟩, 10)
-- 900 s does not fit a 600 s window
#guard (dispatch { queue := [⟨0, 0, 300, 900⟩], window := some (0, 600) } 10).running == none
-- no head-of-line blocking: the aged 900 s spot-check that does not fit no longer keeps a 120 s
-- user step waiting (the first version, `dispatchHoL`, started nothing here)
#guard
  let p : Phone := { queue := [⟨0, 0, 300, 900⟩, ⟨1, A * 300, 0, 120⟩], window := some (A * 300, A * 300 + 600) }
  (dispatchHoL p (A * 300)).running == none &&
    (dispatch p (A * 300)).running == some (⟨1, A * 300, 0, 120⟩, A * 300)
-- the window end is a hard stop
#guard (tick { running := some (⟨0, 0, 300, 900⟩, 0), window := some (0, 600) } 600).running == none

end Fw.DeviceQueue
