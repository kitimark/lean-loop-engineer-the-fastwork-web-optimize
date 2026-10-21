/-! Adaptive local work queue (task local-adaptive-queue): the AIMD concurrency controller, admission by per-kind memory
footprint, holders identified by owner and a renewed lease, the Simulator kind, the stop rule and the review result cache. -/
namespace Fw.Sup.Adapt

/-- A kind of heavy local work. -/
inductive Kind where
  | check | test | land | sim | other
deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .check => "check" | .test => "test" | .land => "land" | .sim => "sim" | .other => "other"

def Kind.all : List Kind := [.check, .test, .land, .sim, .other]

def Kind.ofName? (s : String) : Option Kind := Kind.all.find? (·.name == s)

#guard Kind.all.all fun k => Kind.ofName? k.name == some k
#guard Kind.ofName? "lake" == none

/-- Controller, footprint, lease and Simulator parameters (initial values, revised from the sampler tables). -/
structure Params where
  nMin : Nat := 1
  nMax : Nat := 4
  targetCenti : Nat := 800
  highCenti : Nat := 1600
  floorMB : Nat := 1024
  headroomMB : Nat := 2048
  cmprsPct : Nat := 40
  swapRiseMBPerMin : Nat := 512
  holdS : Nat := 30
  leanProcMB : Nat := 700
  testMB : Nat := 1600
  landMB : Nat := 1500
  simMB : Nat := 2800
  otherMB : Nat := 1000
  warmS : Nat := 60
  ageS : Nat := 300
  maxWaitS : Nat := 1800
  leaseS : Nat := 60
  leaseMaxS : Nat := 3600
  simIdleS : Nat := 600
  graceMs : Nat := 5000
deriving DecidableEq, Repr

/-- One probe sample: time (s), 1-min load times 100, free memory, RAM, compressor and swap used (MB), online cores. -/
structure Sample where
  time : Nat
  loadCenti : Nat
  freeMB : Nat
  ramMB : Nat
  compressorMB : Nat
  swapUsedMB : Nat
  cores : Nat
deriving DecidableEq, Repr

/-! ## Controller -/

/-- Controller state: admitted concurrency, time of its last change, and the previous (time, swap used) reading. -/
structure Ctl where
  n : Nat
  lastChange : Nat
  prev : Option (Nat × Nat) := none
deriving DecidableEq, Repr

inductive Signal where
  | overload | under | hold
deriving DecidableEq, Repr

def Signal.name : Signal → String
  | .overload => "overload" | .under => "under" | .hold => "hold"

def loadHigh (p : Params) (s : Sample) : Bool := decide (p.highCenti ≤ s.loadCenti)

def memLow (p : Params) (s : Sample) : Bool := decide (s.freeMB < p.floorMB)

def cmprsHigh (p : Params) (s : Sample) : Bool := decide (0 < s.ramMB ∧ p.cmprsPct * s.ramMB ≤ 100 * s.compressorMB)

/-- Swap grew by at least `swapRiseMBPerMin` per minute since the previous reading; the swap ratio is not read. -/
def swapRising (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Bool :=
  match prev with
  | none => false
  | some (t, mb) => decide (t < s.time ∧ p.swapRiseMBPerMin * (s.time - t) ≤ 60 * (s.swapUsedMB - mb))

def overloaded (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Bool :=
  loadHigh p s || memLow p s || cmprsHigh p s || swapRising p prev s

def roomy (p : Params) (s : Sample) : Bool :=
  decide (s.loadCenti < p.targetCenti ∧ p.floorMB + p.headroomMB ≤ s.freeMB)

def signal (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Signal :=
  if overloaded p prev s then .overload else if roomy p s then .under else .hold

def clamp (p : Params) (x : Nat) : Nat := max p.nMin (min p.nMax x)

def target (n : Nat) : Signal → Nat
  | .overload => n / 2
  | .under => n + 1
  | .hold => n

/-- Whether the hysteresis window since the last change has passed. -/
def windowOpen (p : Params) (c : Ctl) (now : Nat) : Bool := decide (c.lastChange + p.holdS ≤ now)

/-- The clamped AIMD target for a sample. -/
def nextN (p : Params) (c : Ctl) (s : Sample) : Nat := clamp p (target c.n (signal p c.prev s))

/-- One controller step on a sample: AIMD target, clamped, applied only once the hysteresis window has passed. -/
def step (p : Params) (c : Ctl) (s : Sample) : Ctl :=
  if windowOpen p c s.time && nextN p c s != c.n then
    { n := nextN p c s, lastChange := s.time, prev := some (s.time, s.swapUsedMB) }
  else { c with prev := some (s.time, s.swapUsedMB) }

def inRange (p : Params) (n : Nat) : Prop := p.nMin ≤ n ∧ n ≤ p.nMax

def init (p : Params) : Ctl := { n := clamp p 2, lastChange := 0 }

def okSample : Sample :=
  { time := 1000, loadCenti := 400, freeMB := 6000, ramMB := 16384, compressorMB := 2000, swapUsedMB := 5000, cores := 8 }

#guard (step {} { n := 2, lastChange := 0 } okSample).n == 3
#guard (step {} { n := 2, lastChange := 990 } okSample).n == 2
#guard (step {} { n := 4, lastChange := 0 } { okSample with loadCenti := 2000 }).n == 2
#guard (step {} { n := 1, lastChange := 0 } { okSample with freeMB := 500 }).n == 1
#guard (step {} { n := 3, lastChange := 0, prev := some (995, 4900) } okSample).n == 1
#guard (step {} { n := 3, lastChange := 0, prev := some (995, 5000) } okSample).n == 4
#guard signal {} none { okSample with loadCenti := 1000 } == .hold

theorem clamp_range (p : Params) (h : p.nMin ≤ p.nMax) (x : Nat) : inRange p (clamp p x) := by
  unfold inRange clamp; omega

/-- **N stays within [nMin, nMax].** -/
theorem step_range (p : Params) (h : p.nMin ≤ p.nMax) (c : Ctl) (s : Sample) (hc : inRange p c.n) :
    inRange p (step p c s).n := by
  unfold step
  split
  · exact clamp_range p h _
  · exact hc

theorem init_range (p : Params) (h : p.nMin ≤ p.nMax) : inRange p (init p).n := clamp_range p h 2

/-- A change happens only after the hysteresis window and stamps the sample time. -/
theorem step_change_spaced (p : Params) (c : Ctl) (s : Sample) (h : (step p c s).n ≠ c.n) :
    c.lastChange + p.holdS ≤ s.time ∧ (step p c s).lastChange = s.time := by
  unfold step at *
  split at h
  · rename_i hw
    simp only [Bool.and_eq_true, windowOpen, decide_eq_true_eq] at hw
    simp [hw.1, windowOpen, hw.2]
  · exact absurd rfl h

theorem step_same_lastChange (p : Params) (c : Ctl) (s : Sample) (h : (step p c s).n = c.n) :
    (step p c s).lastChange = c.lastChange := by
  unfold step at *
  split at h
  · rename_i hw
    simp only [Bool.and_eq_true, bne_iff_ne, ne_eq] at hw
    exact absurd h hw.2
  · rename_i hw
    simp [hw]

/-- Inside the hysteresis window N does not move. -/
theorem step_window_closed (p : Params) (c : Ctl) (s : Sample) (h : s.time < c.lastChange + p.holdS) :
    (step p c s).n = c.n := by
  unfold step
  have : windowOpen p c s.time = false := by simp [windowOpen]; omega
  simp [this]

/-- Once the window has passed, N is the clamped AIMD target. -/
theorem step_window_open (p : Params) (c : Ctl) (s : Sample) (h : c.lastChange + p.holdS ≤ s.time) :
    (step p c s).n = clamp p (target c.n (signal p c.prev s)) := by
  unfold step
  have hw : windowOpen p c s.time = true := by simp [windowOpen]; omega
  show _ = nextN p c s
  by_cases he : nextN p c s = c.n
  · simp [hw, he]
  · simp [hw, he]

theorem signal_overload (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : overloaded p prev s = true) :
    signal p prev s = .overload := by
  simp [signal, h]

theorem overload_of_load (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : loadHigh p s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem overload_of_mem (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : memLow p s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem overload_of_cmprs (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : cmprsHigh p s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem overload_of_swap (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : swapRising p prev s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

/-- An increase needs a sample that is not overloaded, below the load target and with headroom above the floor. -/
theorem signal_under_iff (p : Params) (prev : Option (Nat × Nat)) (s : Sample) :
    signal p prev s = .under ↔ overloaded p prev s = false ∧ roomy p s = true := by
  unfold signal
  cases ho : overloaded p prev s <;> cases hr : roomy p s <;> simp

/-- Multiplicative decrease: an overloaded sample after the window halves N (clamped). -/
theorem step_overload (p : Params) (c : Ctl) (s : Sample) (hw : c.lastChange + p.holdS ≤ s.time)
    (h : overloaded p c.prev s = true) : (step p c s).n = clamp p (c.n / 2) := by
  rw [step_window_open p c s hw, signal_overload p c.prev s h]; rfl

/-- Additive increase: a roomy sample with no overload after the window adds one (clamped). -/
theorem step_under (p : Params) (c : Ctl) (s : Sample) (hw : c.lastChange + p.holdS ≤ s.time)
    (h : overloaded p c.prev s = false) (hr : roomy p s = true) : (step p c s).n = clamp p (c.n + 1) := by
  rw [step_window_open p c s hw, (signal_under_iff p c.prev s).2 ⟨h, hr⟩]; rfl

/-- An overloaded sample never raises N. -/
theorem step_no_rise_on_overload (p : Params) (c : Ctl) (s : Sample) (hc : inRange p c.n)
    (h : overloaded p c.prev s = true) : (step p c s).n ≤ c.n := by
  by_cases hw : c.lastChange + p.holdS ≤ s.time
  · rw [step_overload p c s hw h]; unfold clamp; unfold inRange at hc; omega
  · rw [step_window_closed p c s (by omega)]; exact Nat.le_refl _

/-- A swap reading that did not grow never trips, whatever the swap ratio (the dynamic-swap recalibration). -/
theorem swap_static_never_trips (p : Params) (t mb : Nat) (s : Sample) (hp : 0 < p.swapRiseMBPerMin)
    (h : s.swapUsedMB ≤ mb) : swapRising p (some (t, mb)) s = false := by
  simp only [swapRising, decide_eq_false_iff_not, not_and, Nat.not_le]
  intro ht
  have : s.swapUsedMB - mb = 0 := by omega
  rw [this]; exact Nat.mul_pos hp (by omega)

/-- Times at which N changed along a run of samples. -/
def changeTimes (p : Params) : Ctl → List Sample → List Nat
  | _, [] => []
  | c, s :: ss =>
    let c' := step p c s
    if c'.n = c.n then changeTimes p c' ss else s.time :: changeTimes p c' ss

/-- Consecutive values at least `h` apart, starting from `a`. -/
def spaced (h : Nat) : Nat → List Nat → Prop
  | _, [] => True
  | a, b :: t => a + h ≤ b ∧ spaced h b t

/-- **No oscillation faster than the hysteresis window**: along any run, every change is at least `holdS` seconds after
the previous one (the first after the initial `lastChange`). -/
theorem changes_spaced (p : Params) (c : Ctl) (ss : List Sample) :
    spaced p.holdS c.lastChange (changeTimes p c ss) := by
  induction ss generalizing c with
  | nil => trivial
  | cons s ss ih =>
    simp only [changeTimes]
    split
    · rename_i he
      have := step_same_lastChange p c s he
      have hi := ih (step p c s)
      rwa [this] at hi
    · rename_i he
      have ⟨h1, h2⟩ := step_change_spaced p c s he
      refine ⟨h1, ?_⟩
      have hi := ih (step p c s)
      rwa [h2] at hi

/-! ## Holders and leases -/

/-- A queue ticket or a slot holder: the owning agent, a lease token, kind, time it entered (s), lease expiry (s) and the
memory charged (MB). No process id. -/
structure Entry where
  owner : String
  token : String
  kind : Kind
  since : Nat
  till : Nat
  foot : Nat := 0
deriving DecidableEq, Repr

def live (now : Nat) (e : Entry) : Bool := decide (now < e.till)

/-- Drop entries whose lease expired. -/
def prune (now : Nat) (es : List Entry) : List Entry := es.filter (live now)

def same (owner token : String) (e : Entry) : Bool := e.owner == owner && e.token == token

/-- The lease end granted for a requested lease at `now`. -/
def grantUntil (p : Params) (now lease : Nat) : Nat := now + min lease p.leaseMaxS

/-- Renew the live entry of (owner, token); `none` when it has none (expired or never held). -/
def renew (p : Params) (now : Nat) (owner token : String) (lease : Nat) (es : List Entry) : Option (List Entry) :=
  if es.any (fun e => same owner token e && live now e) then
    some (es.map fun e => if same owner token e then { e with till := grantUntil p now lease } else e)
  else none

def release (owner token : String) (es : List Entry) : List Entry := es.filter (fun e => !same owner token e)

def holdA : Entry := { owner := "a", token := "t1", kind := .sim, since := 0, till := 100 }

#guard prune 50 [holdA] == [holdA]
#guard prune 100 [holdA] == []
#guard (renew {} 50 "a" "t1" 600 [holdA]).map (·.map (·.till)) == some [650]
#guard renew {} 50 "a" "t2" 600 [holdA] == none
#guard renew {} 100 "a" "t1" 600 [holdA] == none
#guard release "a" "t1" [holdA] == []
#guard release "b" "t1" [holdA] == [holdA]

/-- **A live holder with an unexpired lease is never recovered as stale.** -/
theorem live_never_recovered (now : Nat) (es : List Entry) (e : Entry) (he : e ∈ es) (hl : now < e.till) :
    e ∈ prune now es := by
  simp [prune, live, he, hl]

/-- Only an expired lease is recovered. -/
theorem recovered_expired (now : Nat) (es : List Entry) (e : Entry) (he : e ∈ es) (hr : e ∉ prune now es) :
    e.till ≤ now := by
  simp [prune, live, he] at hr; exact hr

/-- Liveness reads only the lease end and the clock. -/
theorem live_iff (now : Nat) (e : Entry) : live now e = true ↔ now < e.till := by simp [live]

theorem renew_other (p : Params) (now : Nat) (o t : String) (lease : Nat) (es es' : List Entry)
    (h : renew p now o t lease es = some es') (e : Entry) (he : e ∈ es) (hs : same o t e = false) : e ∈ es' := by
  unfold renew at h
  split at h
  · cases h; exact List.mem_map.2 ⟨e, he, by simp [hs]⟩
  · cases h

theorem renew_live (p : Params) (now : Nat) (o t : String) (lease : Nat) (es es' : List Entry)
    (h : renew p now o t lease es = some es') (hl : 0 < lease) (hm : 0 < p.leaseMaxS) :
    ∀ e ∈ es', same o t e = true → live now e = true := by
  unfold renew at h
  split at h
  · cases h
    intro e he hs
    obtain ⟨x, _, rfl⟩ := List.mem_map.1 he
    by_cases hx : same o t x = true
    · simp [hx, live, grantUntil]; omega
    · simp [hx] at hs
  · cases h

/-- An expired or foreign lease cannot be renewed: the asker learns it lost the slot. -/
theorem renew_none (p : Params) (now : Nat) (o t : String) (lease : Nat) (es : List Entry)
    (h : ∀ e ∈ es, same o t e = true → live now e = false) : renew p now o t lease es = none := by
  unfold renew
  have : es.any (fun e => same o t e && live now e) = false := by
    simp only [List.any_eq_false, Bool.and_eq_true, not_and]
    intro e he hs; simp [h e he hs]
  simp [this]

theorem release_keeps_other (o t : String) (es : List Entry) (e : Entry) (he : e ∈ es) (hs : same o t e = false) :
    e ∈ release o t es := by
  simp [release, he, hs]

theorem release_removes (o t : String) (es : List Entry) (e : Entry) (hs : same o t e = true) :
    e ∉ release o t es := by
  simp [release, hs]

/-! ## Admission -/

/-- Lean worker processes for a `check` job: as many as fit `roomMB` at `leanProcMB` each, at least 1, at most the cores. -/
def leanThreads (p : Params) (cores roomMB : Nat) : Nat := max 1 (min cores (roomMB / p.leanProcMB))

/-- The memory a job of kind `k` is charged with `threads` Lean workers. -/
def foot (p : Params) (threads : Nat) : Kind → Nat
  | .check => threads * p.leanProcMB
  | .test => p.testMB
  | .land => p.landMB
  | .sim => p.simMB
  | .other => p.otherMB

/-- Memory of holders admitted within the last `warmS` seconds, not yet visible in the free-memory reading. -/
def charged (p : Params) (now : Nat) (hs : List Entry) : Nat :=
  ((prune now hs).filter (fun h => decide (now < h.since + p.warmS))).foldr (fun h a => h.foot + a) 0

def room (p : Params) (s : Sample) (hs : List Entry) : Nat := s.freeMB - p.floorMB - charged p s.time hs

def threadsFor (p : Params) (s : Sample) (hs : List Entry) : Nat := leanThreads p s.cores (room p s hs)

def need (p : Params) (s : Sample) (hs : List Entry) (k : Kind) : Nat := foot p (threadsFor p s hs) k

inductive Why where
  | queued (ahead : Nat)
  | older
  | full (running limit : Nat)
  | simBusy
  | memory (needMB roomMB : Nat)
deriving DecidableEq, Repr

inductive Verdict where
  | admit (threads footMB : Nat)
  | wait (why : Why)
  | timeout (why : Why)
deriving DecidableEq, Repr

def waitOr (p : Params) (waited : Nat) (w : Why) : Verdict :=
  if p.maxWaitS ≤ waited then .timeout w else .wait w

/-- Tickets ahead of `me` in the FIFO queue. -/
def before (q : List Entry) (me : Entry) : List Entry := q.takeWhile (fun e => e.token != me.token)

def aheadSame (q : List Entry) (me : Entry) : Nat := ((before q me).filter (fun e => e.kind == me.kind)).length

def simHeld (now : Nat) (hs : List Entry) : Bool := (prune now hs).any (fun h => h.kind == .sim)

/-- A ticket of another kind ahead of `me` has waited `ageS` seconds and can itself run (not a Simulator ticket while
the Simulator is held): kinds then share one FIFO order. -/
def starved (p : Params) (now : Nat) (hs q : List Entry) (me : Entry) : Bool :=
  (before q me).any (fun e => e.kind != me.kind && decide (e.since + p.ageS ≤ now) && !(e.kind == .sim && simHeld now hs))

/-- The decision for ticket `me` in queue `q` (FIFO order) under concurrency `n`, holders `hs` and sample `s`. -/
def verdict (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat) : Verdict :=
  let running := (prune s.time hs).length
  if 0 < aheadSame q me then waitOr p waited (.queued (aheadSame q me))
  else if starved p s.time hs q me then waitOr p waited .older
  else if n ≤ running then waitOr p waited (.full running n)
  else if me.kind == .sim && simHeld s.time hs then waitOr p waited .simBusy
  else if s.freeMB < need p s hs me.kind + p.floorMB + charged p s.time hs then
    waitOr p waited (.memory (need p s hs me.kind) (room p s hs))
  else .admit (threadsFor p s hs) (need p s hs me.kind)

def tk (o t : String) (k : Kind) (t0 : Nat) : Entry := { owner := o, token := t, kind := k, since := t0, till := t0 + 60 }

#guard verdict {} 2 okSample [] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 7 4900
#guard verdict {} 2 okSample [] [tk "a" "1" .test 990, tk "b" "2" .test 991] (tk "b" "2" .test 991) 0 == .wait (.queued 1)
#guard verdict {} 2 okSample [] [tk "a" "1" .test 600, tk "b" "2" .sim 991] (tk "b" "2" .sim 991) 0 == .wait .older
#guard verdict {} 1 okSample [{ tk "c" "9" .test 0 with till := 2000 }] [tk "a" "1" .test 990] (tk "a" "1" .test 990) 0 == .wait (.full 1 1)
#guard verdict {} 3 okSample [{ tk "c" "9" .sim 0 with till := 2000 }] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 0 == .wait .simBusy
#guard verdict {} 4 okSample [{ tk "c" "9" .sim 0 with till := 2000 }] [tk "s" "5" .sim 600, tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 7 4900
#guard verdict {} 4 okSample [] [tk "s" "5" .sim 600, tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .wait .older
#guard verdict {} 3 { okSample with freeMB := 3000 } [] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 0 == .wait (.memory 2800 1976)
#guard verdict {} 3 { okSample with freeMB := 3000 } [] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 1800 == .timeout (.memory 2800 1976)

theorem waitOr_ne_admit (p : Params) (w : Nat) (y : Why) (t f : Nat) : ¬ waitOr p w y = .admit t f := by
  unfold waitOr; split <;> simp

theorem verdict_admit (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) :
    aheadSame q me = 0 ∧ starved p s.time hs q me = false ∧ (prune s.time hs).length < n ∧
      (me.kind == .sim && simHeld s.time hs) = false ∧
      need p s hs me.kind + p.floorMB + charged p s.time hs ≤ s.freeMB ∧ t = threadsFor p s hs ∧ f = need p s hs me.kind := by
  unfold verdict at h
  simp only at h
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  rename_i h1 h2 h3 h4 h5
  cases h
  refine ⟨by omega, by simpa using h2, by omega, by simpa using h4, by omega, rfl, rfl⟩

/-- **Never admits a job whose footprint exceeds free memory minus the floor** (and the memory of warming holders). -/
theorem verdict_admit_fits (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : f + p.floorMB + charged p s.time hs ≤ s.freeMB := by
  have := verdict_admit p n s hs q me w t f h
  rw [this.2.2.2.2.2.2]; exact this.2.2.2.2.1

/-- An admit keeps the live holders below N. -/
theorem verdict_admit_under_n (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : (prune s.time hs).length < n :=
  (verdict_admit p n s hs q me w t f h).2.2.1

/-- FIFO per kind: only a ticket with no same-kind ticket ahead is admitted. -/
theorem verdict_admit_head (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : aheadSame q me = 0 :=
  (verdict_admit p n s hs q me w t f h).1

/-- At most one live Simulator holder. -/
theorem verdict_admit_sim_exclusive (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind = .sim) : simHeld s.time hs = false := by
  have := (verdict_admit p n s hs q me w t f h).2.2.2.1
  simpa [hk] using this

/-- Progress: the head of its kind, with no starved ticket ahead, below N, the Simulator free if it asks for it, and
memory for its footprint, is admitted. -/
theorem verdict_head_admitted (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (h1 : aheadSame q me = 0) (h2 : starved p s.time hs q me = false) (h3 : (prune s.time hs).length < n)
    (h4 : (me.kind == .sim && simHeld s.time hs) = false)
    (h5 : need p s hs me.kind + p.floorMB + charged p s.time hs ≤ s.freeMB) :
    verdict p n s hs q me w = .admit (threadsFor p s hs) (need p s hs me.kind) := by
  unfold verdict
  have h3' : ¬ n ≤ (prune s.time hs).length := by omega
  have h5' : ¬ s.freeMB < need p s hs me.kind + p.floorMB + charged p s.time hs := by omega
  simp [h1, h2, h3', h4, h5']

theorem starved_iff (p : Params) (now : Nat) (hs q : List Entry) (me : Entry) :
    starved p now hs q me = true ↔ ∃ e ∈ before q me, e.kind ≠ me.kind ∧ e.since + p.ageS ≤ now ∧
      (e.kind = .sim → simHeld now hs = false) := by
  simp [starved, Decidable.imp_iff_not_or, and_assoc]

/-- A Simulator ticket ahead of `me` while the Simulator is held never makes `me` starved. -/
theorem starved_skips_blocked_sim (p : Params) (now : Nat) (hs q : List Entry) (me e : Entry) (hk : e.kind = .sim)
    (hb : simHeld now hs = true) (h : starved p now hs q me = true) :
    ∃ e' ∈ before q me, e' ≠ e ∧ e'.kind ≠ me.kind ∧ e'.since + p.ageS ≤ now := by
  obtain ⟨e', he', hk', ha', hn'⟩ := (starved_iff p now hs q me).1 h
  refine ⟨e', he', ?_, hk', ha'⟩
  rintro rfl
  simp [hn' hk] at hb

theorem waitOr_ne_older (p : Params) (w : Nat) (y : Why) (hy : y ≠ .older) :
    waitOr p w y ≠ .wait .older ∧ waitOr p w y ≠ .timeout .older := by
  unfold waitOr; split <;> simp [hy]

/-- **No cross-kind stall**: while the Simulator is held, a ticket whose other-kind tickets ahead are all Simulator
tickets never waits or times out as `older`. -/
theorem verdict_not_older_of_sim_blocked (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (hb : simHeld s.time hs = true) (hq : ∀ e ∈ before q me, e.kind ≠ me.kind → e.kind = .sim) :
    verdict p n s hs q me w ≠ .wait .older ∧ verdict p n s hs q me w ≠ .timeout .older := by
  have hst : starved p s.time hs q me = false := by
    cases h : starved p s.time hs q me
    · rfl
    · obtain ⟨e, he, hk, _, hn⟩ := (starved_iff p s.time hs q me).1 h
      simp [hn (hq e he hk)] at hb
  unfold verdict
  simp only [hst]
  split
  · exact waitOr_ne_older _ _ _ (by simp)
  split
  · simp_all
  split
  · exact waitOr_ne_older _ _ _ (by simp)
  split
  · exact waitOr_ne_older _ _ _ (by simp)
  split
  · exact waitOr_ne_older _ _ _ (by simp)
  simp

theorem before_append_of_ne (pre post : List Entry) (a me : Entry) (hpre : ∀ e ∈ pre, e.token ≠ me.token)
    (ha : a.token ≠ me.token) : a ∈ before (pre ++ a :: post) me := by
  induction pre with
  | nil => simp [before, ha]
  | cons x xs ih =>
    have hx : x.token ≠ me.token := hpre x (by simp)
    have := ih (fun e he => hpre e (by simp [he]))
    have hb : (x.token != me.token) = true := by simpa using hx
    simp only [before, List.cons_append, List.takeWhile, hb]
    exact List.mem_cons_of_mem _ this

/-- **No overtaking within a kind**: a ticket behind a same-kind ticket is not admitted. -/
theorem verdict_no_overtake (p : Params) (n : Nat) (s : Sample) (hs : List Entry) (pre post : List Entry)
    (a me : Entry) (w t f : Nat) (hk : a.kind = me.kind) (hpre : ∀ e ∈ pre, e.token ≠ me.token)
    (ha : a.token ≠ me.token) : verdict p n s hs (pre ++ a :: post) me w ≠ .admit t f := by
  intro h
  have h0 := verdict_admit_head p n s hs _ me w t f h
  have hm := before_append_of_ne pre post a me hpre ha
  unfold aheadSame at h0
  have : a ∈ (before (pre ++ a :: post) me).filter (fun e => e.kind == me.kind) := by simp [hm, hk]
  rw [List.length_eq_zero_iff] at h0
  rw [h0] at this; cases this

theorem leanThreads_pos (p : Params) (c r : Nat) : 1 ≤ leanThreads p c r := by unfold leanThreads; omega

theorem leanThreads_le_cores (p : Params) (c r : Nat) (hc : 1 ≤ c) : leanThreads p c r ≤ c := by
  unfold leanThreads; omega

/-- **Lean workers sized from free memory**: when one worker fits the room, all of them fit it. -/
theorem leanThreads_fit (p : Params) (c r : Nat) (hr : p.leanProcMB ≤ r) :
    leanThreads p c r * p.leanProcMB ≤ r := by
  unfold leanThreads
  by_cases hp : p.leanProcMB = 0
  · simp [hp]
  have hq : 1 ≤ r / p.leanProcMB := (Nat.le_div_iff_mul_le (by omega)).2 (by omega)
  have hm : max 1 (min c (r / p.leanProcMB)) ≤ r / p.leanProcMB := by omega
  calc max 1 (min c (r / p.leanProcMB)) * p.leanProcMB ≤ r / p.leanProcMB * p.leanProcMB := Nat.mul_le_mul_right _ hm
    _ ≤ r := Nat.div_mul_le_self r p.leanProcMB

/-! ## Simulator kind -/

/-- Booting the Simulator is allowed only to the owner of a live Simulator slot. -/
def simBoot (now : Nat) (owner token : String) (hs : List Entry) : Bool :=
  hs.any (fun h => h.kind == .sim && same owner token h && live now h)

inductive SimAct where
  | none | keep | shutdown
deriving DecidableEq, Repr

def SimAct.name : SimAct → String
  | .none => "none" | .keep => "keep" | .shutdown => "shutdown"

/-- What to do with our booted Simulator: keep it while a live slot or the old sim lock holds it, shut it down once it
has been idle `simIdleS` seconds since `idleSince`. -/
def simAction (p : Params) (now : Nat) (hs : List Entry) (booted legacyHeld : Bool) (idleSince : Nat) : SimAct :=
  if !booted then .none
  else if legacyHeld || simHeld now hs then .keep
  else if idleSince + p.simIdleS ≤ now then .shutdown
  else .keep

#guard simBoot 50 "a" "t1" [holdA]
#guard !simBoot 50 "b" "t1" [holdA]
#guard !simBoot 100 "a" "t1" [holdA]
#guard simAction {} 50 [holdA] true false 0 == .keep
#guard simAction {} 700 [holdA] true false 0 == .shutdown
#guard simAction {} 700 [holdA] true true 0 == .keep
#guard simAction {} 500 [] true false 0 == .keep
#guard simAction {} 700 [] false false 0 == .none

theorem simBoot_iff (now : Nat) (o t : String) (hs : List Entry) :
    simBoot now o t hs = true ↔ ∃ h ∈ hs, h.kind = .sim ∧ same o t h = true ∧ now < h.till := by
  simp [simBoot, live, and_assoc]

/-- A live Simulator slot keeps the Simulator up. -/
theorem sim_keep_under_holder (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Nat) (h : simHeld now hs = true) :
    simAction p now hs true l i = .keep := by
  simp [simAction, h]

theorem sim_keep_under_legacy (p : Params) (now : Nat) (hs : List Entry) (i : Nat) :
    simAction p now hs true true i = .keep := by
  simp [simAction]

/-- **Shut down after the idle limit**: booted, no live slot, no old lock, idle `simIdleS` seconds. -/
theorem sim_shutdown_idle (p : Params) (now : Nat) (hs : List Entry) (i : Nat) (h : simHeld now hs = false)
    (hi : i + p.simIdleS ≤ now) : simAction p now hs true false i = .shutdown := by
  simp [simAction, h, hi]

theorem sim_keep_within_idle (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Nat) (hi : now < i + p.simIdleS) :
    simAction p now hs true l i = .keep := by
  have : ¬ i + p.simIdleS ≤ now := by omega
  cases l <;> cases simHeld now hs <;> simp [simAction, this]

theorem sim_shutdown_only_unheld (p : Params) (now : Nat) (hs : List Entry) (b l : Bool) (i : Nat)
    (h : simAction p now hs b l i = .shutdown) : b = true ∧ l = false ∧ simHeld now hs = false ∧ i + p.simIdleS ≤ now := by
  unfold simAction at h
  cases b <;> cases l <;> cases hh : simHeld now hs <;> simp [hh] at h
  exact ⟨rfl, rfl, rfl, h⟩

theorem sim_none_unbooted (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Nat) :
    simAction p now hs false l i = .none := by
  simp [simAction]

/-! ## Stopping the wrapped command -/

inductive StopAct where
  | term | wait | kill | done
deriving DecidableEq, Repr

def StopAct.name : StopAct → String
  | .term => "term" | .wait => "wait" | .kill => "kill" | .done => "done"

/-- The next stop action for our child group: TERM first, KILL only after `graceMs` and only while the leader's pid and
start time are unchanged. -/
def stopAct (p : Params) (alive sameStart : Bool) (termAt : Option Nat) (nowMs : Nat) : StopAct :=
  if !alive || !sameStart then .done
  else match termAt with
    | none => .term
    | some t => if t + p.graceMs ≤ nowMs then .kill else .wait

#guard stopAct {} true true none 0 == .term
#guard stopAct {} true true (some 0) 4999 == .wait
#guard stopAct {} true true (some 0) 5000 == .kill
#guard stopAct {} true false (some 0) 9000 == .done
#guard stopAct {} false true (some 0) 9000 == .done

theorem stop_kill_after_grace (p : Params) (a s : Bool) (tm : Option Nat) (now : Nat) (h : stopAct p a s tm now = .kill) :
    a = true ∧ s = true ∧ ∃ t, tm = some t ∧ t + p.graceMs ≤ now := by
  unfold stopAct at h
  cases a <;> cases s <;> simp at h
  cases tm with
  | none => simp at h
  | some t =>
    simp only at h
    split at h
    · exact ⟨rfl, rfl, t, rfl, by assumption⟩
    · cases h

theorem stop_never_other (p : Params) (a : Bool) (tm : Option Nat) (now : Nat) : stopAct p a false tm now = .done := by
  cases a <;> simp [stopAct]

theorem stop_term_first (p : Params) (now : Nat) : stopAct p true true none now = .term := by simp [stopAct]

/-! ## Review result cache -/

/-- What a cached result is keyed by: kind, the exact argv, the clean tree hash and, for `land`, the main commit. -/
structure CacheKey where
  kind : Kind
  argv : List String
  tree : String
  base : String
deriving DecidableEq, Repr

/-- The key of a run, `none` when the worktree is not clean (no cache read or write then). -/
def keyOf (k : Kind) (argv : List String) (tree mainSha : String) (clean : Bool) : Option CacheKey :=
  if clean then some { kind := k, argv, tree, base := if k == .land then mainSha else "" } else none

/-- A recorded result replays only for the same key and only when it passed. -/
def cacheHit (recorded : CacheKey) (exit : Nat) (k : Option CacheKey) : Bool :=
  match k with
  | none => false
  | some k => recorded == k && exit == 0

def cacheable (exit : Nat) : Bool := exit == 0

#guard keyOf .test ["pnpm", "test"] "t" "m" false == none
#guard (keyOf .land ["fw"] "t" "m" true).map (·.base) == some "m"
#guard (keyOf .test ["fw"] "t" "m" true).map (·.base) == some ""
#guard cacheHit ⟨.test, ["x"], "t", ""⟩ 0 (keyOf .test ["x"] "t" "m" true)
#guard !cacheHit ⟨.test, ["x"], "t", ""⟩ 1 (keyOf .test ["x"] "t" "m" true)
#guard !cacheHit ⟨.test, ["x"], "t", ""⟩ 0 (keyOf .test ["y"] "t" "m" true)
#guard !cacheHit ⟨.land, ["x"], "t", "m"⟩ 0 (keyOf .land ["x"] "t" "m2" true)

/-- **Same check set and verdict**: a hit is the same argv on the same clean tree (and main, for a land), recorded passing. -/
theorem cacheHit_same (r : CacheKey) (e : Nat) (k : Kind) (argv : List String) (tree m : String) (c : Bool)
    (h : cacheHit r e (keyOf k argv tree m c) = true) :
    c = true ∧ r.kind = k ∧ r.argv = argv ∧ r.tree = tree ∧ (k = .land → r.base = m) ∧ e = 0 := by
  unfold keyOf at h
  cases c
  · simp [cacheHit] at h
  · simp only [cacheHit, ite_true, Bool.and_eq_true, beq_iff_eq] at h
    obtain ⟨hr, he⟩ := h
    subst hr
    refine ⟨rfl, rfl, rfl, rfl, fun hk => by simp [hk], he⟩

theorem cacheHit_dirty (r : CacheKey) (e : Nat) (k : Kind) (argv : List String) (tree m : String) :
    cacheHit r e (keyOf k argv tree m false) = false := by
  simp [keyOf, cacheHit]

theorem cacheable_iff (e : Nat) : cacheable e = true ↔ e = 0 := by simp [cacheable]

end Fw.Sup.Adapt
