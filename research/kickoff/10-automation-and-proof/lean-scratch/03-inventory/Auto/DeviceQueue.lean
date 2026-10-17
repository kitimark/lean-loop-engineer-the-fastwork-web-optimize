/-!
# Sketch 2: the phone job queue (priority with aging, mutual exclusion, session window)

v1: ~230 hand moves of the queue, 40 scheduler incidents, I-011 (short lane starves),
I-049 (readers starve). v2: priority is a pure function of (job class, the user's list, wait);
the phone runs at most one job; jobs start only if they fit inside the session the user booked.

math (for the reader):
  base(j)   = R · class(j) + rank(j)                 -- class: user step 0, calibration 1, X/P 2, spot-check 3
  eff_t(j)  = base(j) − min(base(j), ⌊(t − enq(j)) / A⌋)    -- aging: one level per A seconds of waiting
  j ≺_t k   ⇔ eff_t(j) < eff_t(k) ∨ (eff_t(j) = eff_t(k) ∧ seq(j) ≤ seq(k))
  pick_t(Q) = the ≺_t-least job of Q                   -- pick_mem, pick_min
  t ≥ enq(j) + A·base(j) ∧ seq(j) < seq(k) ⇒ j ≺_t k ∧ ¬ k ≺_t j  -- aged_beats_newer: no starvation
  running ∈ {none} ∪ {some j}                          -- mutual exclusion by construction
  start(j) at t ⇒ s ≤ t ∧ t + dur(j) ≤ e               -- every job fits its booked window [s, e]
  started j ⇒ ∀ k ∈ Q fitting: j ≼_t k                  -- dispatch_sound: most urgent among those that fit
  free ∧ window open ∧ nothing started ⇒ no k ∈ Q fits   -- dispatch_conserving (work conservation)
  e ≤ now ⇒ nothing runs after tick(now)               -- tick_kills_at_end: the window end is a hard stop
-/
namespace Auto.DeviceQueue

structure Job where
  seq  : Nat   -- arrival order, unique (assigned by the single writer)
  enq  : Nat   -- enqueue time, s
  base : Nat   -- R·class + rank (smaller = more urgent)
  dur  : Nat   -- max duration, s
deriving Repr, DecidableEq

/-- Aging step A (s per priority level). -/
def A : Nat := 300

def eff (t : Nat) (j : Job) : Nat := j.base - min j.base ((t - j.enq) / A)

/-- `j` goes no later than `k` at time `t`. -/
def before (t : Nat) (j k : Job) : Bool :=
  decide (eff t j < eff t k ∨ (eff t j = eff t k ∧ j.seq ≤ k.seq))

theorem before_total (t : Nat) (j k : Job) : before t j k = true ∨ before t k j = true := by
  simp only [before, decide_eq_true_eq]; omega

theorem before_trans (t : Nat) {a b c : Job} (h1 : before t a b = true) (h2 : before t b c = true) :
    before t a c = true := by
  simp only [before, decide_eq_true_eq] at *; omega

theorem before_refl (t : Nat) (j : Job) : before t j j = true := by
  simp [before]

/-- Pick the most urgent job: a left fold keeping the best so far. -/
def pickFrom (t : Nat) (best : Job) : List Job → Job
  | [] => best
  | k :: ks => pickFrom t (if before t k best then k else best) ks

def pick (t : Nat) : List Job → Option Job
  | [] => none
  | j :: js => some (pickFrom t j js)

theorem pickFrom_mem (t : Nat) (best : Job) (ks : List Job) :
    pickFrom t best ks = best ∨ pickFrom t best ks ∈ ks := by
  induction ks generalizing best with
  | nil => simp [pickFrom]
  | cons k ks ih =>
    simp only [pickFrom]
    split
    · rcases ih k with h | h <;> simp [h]
    · rcases ih best with h | h <;> simp [h]

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

/-- `pick` returns a queued job … -/
theorem pick_mem {t : Nat} {q : List Job} {j : Job} (h : pick t q = some j) : j ∈ q := by
  cases q with
  | nil => cases h
  | cons a as =>
    simp only [pick, Option.some.injEq] at h; subst h
    rcases pickFrom_mem t a as with h | h
    · rw [h]; simp
    · simp [h]

/-- … and no queued job goes before it. -/
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

/-- **No starvation.** Once `j` has waited `A·base(j)` seconds it goes before every job that
arrived after it, whatever their class. So `j` waits at most `A·base(j)` plus the jobs that were
already queued when it arrived. -/
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

structure Phone where
  running : Option (Job × Nat) := none   -- the job and its start time: at most one, by construction
  queue   : List Job := []
  window  : Option (Nat × Nat) := none   -- the session the user booked: [start, end)

/-- The first version (kept for the record): it blocks the head of the line. If the most urgent job
does not fit the rest of the window, nothing starts, even when a shorter job would fit. -/
def dispatchHoL (p : Phone) (t : Nat) : Phone :=
  match p.running, p.window, pick t p.queue with
  | none, some (s, e), some j =>
    if s ≤ t ∧ t + j.dur ≤ e then { p with running := some (j, t), queue := p.queue.erase j } else p
  | _, _, _ => p

/-- A job fits at `t` in window `[s, e)` when the window is open and the job ends by `e`. -/
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

/-- Whatever `dispatch` starts is a queued job that fits the booked window, and no queued job that
also fits goes before it. -/
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

/-- **Work conservation.** If the phone is free, the window is open, and `dispatch` still starts
nothing, then no queued job fits the rest of the window. -/
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

/-- The window end is a hard stop: at or after `e`, a running job is killed. -/
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

/-! ## Examples -/
def jStep : Job := ⟨1, 0, 0, 120⟩       -- a user step (class 0)
def jSpot : Job := ⟨0, 0, 3 * 100, 900⟩ -- a spot-check queued first (class 3)
#guard pick 10 [jSpot, jStep] == some jStep           -- class wins while fresh
#guard pick (A * 300) [jSpot, ⟨5, A * 300, 0, 60⟩] == some jSpot  -- fully aged spot-check beats a new user step
#guard (dispatch { queue := [jSpot, jStep], window := some (0, 3600) } 10).running == some (jStep, 10)
#guard (dispatch { queue := [jSpot], window := some (0, 600) } 10).running == none  -- 900 s does not fit
-- no head-of-line blocking: an aged 900 s spot-check that does not fit a 600 s window no longer
-- keeps a 120 s user step waiting (the first version started nothing here)
def jSpotAged : Job := ⟨0, 0, 3 * 100, 900⟩
#guard pick (A * 300) [jSpotAged, ⟨1, A * 300, 0, 120⟩] == some jSpotAged
#guard (dispatchHoL { queue := [jSpotAged, ⟨1, A * 300, 0, 120⟩], window := some (A * 300, A * 300 + 600) } (A * 300)).running == none
#guard (dispatch { queue := [jSpotAged, ⟨1, A * 300, 0, 120⟩], window := some (A * 300, A * 300 + 600) } (A * 300)).running
        == some (⟨1, A * 300, 0, 120⟩, A * 300)
-- the window end is a hard stop
#guard (tick { running := some (jSpot, 0), window := some (0, 600) } 600).running == none

end Auto.DeviceQueue
