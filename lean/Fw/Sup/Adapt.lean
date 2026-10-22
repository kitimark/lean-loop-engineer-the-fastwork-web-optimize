/-! Adaptive local work queue: AIMD concurrency, admission by memory footprint, leased holders, Simulator priority,
builder admission, the stop rule and the result cache. -/
namespace Fw.Sup.Adapt

inductive Kind where
  | check | test | land | sim | other | measure
deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .check => "check" | .test => "test" | .land => "land" | .sim => "sim" | .other => "other" | .measure => "measure"

def Kind.all : List Kind := [.check, .test, .land, .sim, .other, .measure]

def Kind.ofName? (s : String) : Option Kind := Kind.all.find? (·.name == s)

#guard Kind.all.all fun k => Kind.ofName? k.name == some k
#guard Kind.ofName? "lake" == none

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
  simPollS : Nat := 30
  buildMB : Nat := 2100
  agentsMax : Nat := 8
  agentsAgeS : Nat := 900
  swapOutMBPerMinMax : Nat := 64
  comprMBPerMinMax : Nat := 1500
  rateMinS : Nat := 5
  rateMaxS : Nat := 600
  measureMB : Nat := 2800
deriving DecidableEq, Repr

structure Mem where
  freeMB : Nat
  specMB : Nat := 0
  purgMB : Nat := 0
  fileMB : Nat := 0
  fileMinMB : Nat := 0
  swapUsedMB : Nat := 0
  swapTotalMB : Nat := 0
  press : Nat := 1
  comprMBPerMin : Nat := 0
  swapOutMBPerMin : Nat := 0
deriving DecidableEq, Repr

def availMB (m : Mem) : Nat := m.freeMB + m.specMB + m.purgMB + (m.fileMB - m.fileMinMB)

def swapActive (p : Params) (m : Mem) : Bool := decide (p.swapOutMBPerMinMax ≤ m.swapOutMBPerMin)

def thrash (p : Params) (m : Mem) : Bool := decide (p.comprMBPerMinMax ≤ m.comprMBPerMin)

def memLow (p : Params) (m : Mem) : Bool :=
  decide (availMB m < p.floorMB) || decide (m.press ≠ 1) || swapActive p m || thrash p m

#guard availMB { freeMB := 217, specMB := 120, purgMB := 87, fileMB := 4986, fileMinMB := 3656 } == 1754
#guard availMB { freeMB := 100, fileMB := 2000, fileMinMB := 3000 } == 100
#guard memLow {} { freeMB := 1023 }
#guard !memLow {} { freeMB := 1024 }
#guard memLow {} { freeMB := 9000, press := 2 }
#guard memLow {} { freeMB := 9000, press := 0 }
#guard !memLow {} { freeMB := 9000, swapUsedMB := 3276, swapTotalMB := 4096 }
#guard memLow {} { freeMB := 9000, swapOutMBPerMin := 64 }
#guard !memLow {} { freeMB := 9000, swapOutMBPerMin := 63 }
#guard memLow {} { freeMB := 9000, comprMBPerMin := 1500 }
#guard !memLow {} { freeMB := 9000, comprMBPerMin := 1499 }

structure VmMark where
  time : Nat
  count : Nat
  rate : Nat
  swapCount : Nat := 0
  swapRate : Nat := 0
deriving DecidableEq, Repr

def mbPerMin (dt c0 c1 pageB : Nat) : Nat := if c0 ≤ c1 then (c1 - c0) * pageB * 60 / (dt * 1048576) else 0

def vmNext (p : Params) (prev : Option VmMark) (now count swapCount pageB : Nat) : VmMark :=
  match prev with
  | some m =>
    if now < m.time + p.rateMinS then m
    else if now ≤ m.time + p.rateMaxS then
      { time := now, count := count, rate := mbPerMin (now - m.time) m.count count pageB, swapCount := swapCount,
        swapRate := mbPerMin (now - m.time) m.swapCount swapCount pageB }
    else { time := now, count := count, rate := 0, swapCount := swapCount }
  | none => { time := now, count := count, rate := 0, swapCount := swapCount }

#guard vmNext {} none 100 5 7 16384 == { time := 100, count := 5, rate := 0, swapCount := 7 }
#guard vmNext {} (some ⟨100, 1701467470, 0, 13043114, 0⟩) 111 1701529764 13043114 16384 == ⟨111, 1701529764, 5309, 13043114, 0⟩
#guard vmNext {} (some ⟨100, 10, 7, 0, 0⟩) 130 10 2048 16384 == ⟨130, 10, 0, 2048, 64⟩
#guard vmNext {} (some ⟨100, 10, 7, 3, 9⟩) 104 99999 99 16384 == ⟨100, 10, 7, 3, 9⟩
#guard vmNext {} (some ⟨100, 10, 7, 3, 9⟩) 701 99999 99 16384 == ⟨701, 99999, 0, 99, 0⟩
#guard vmNext {} (some ⟨100, 500, 7, 500, 9⟩) 160 10 10 16384 == ⟨160, 10, 0, 10, 0⟩

structure Sample where
  time : Nat
  loadCenti : Nat
  mem : Mem
  ramMB : Nat
  compressorMB : Nat
  cores : Nat
deriving DecidableEq, Repr

def Sample.avail (s : Sample) : Nat := availMB s.mem

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

def cmprsHigh (p : Params) (s : Sample) : Bool := decide (0 < s.ramMB ∧ p.cmprsPct * s.ramMB ≤ 100 * s.compressorMB)

def swapRising (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Bool :=
  match prev with
  | none => false
  | some (t, mb) => decide (t < s.time ∧ p.swapRiseMBPerMin * (s.time - t) ≤ 60 * (s.mem.swapUsedMB - mb))

def overloaded (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Bool :=
  loadHigh p s || memLow p s.mem || cmprsHigh p s || swapRising p prev s

def roomy (p : Params) (s : Sample) : Bool :=
  decide (s.loadCenti < p.targetCenti ∧ p.floorMB + p.headroomMB ≤ s.avail)

def signal (p : Params) (prev : Option (Nat × Nat)) (s : Sample) : Signal :=
  if overloaded p prev s then .overload else if roomy p s then .under else .hold

def clamp (p : Params) (x : Nat) : Nat := max p.nMin (min p.nMax x)

def target (n : Nat) : Signal → Nat
  | .overload => n / 2
  | .under => n + 1
  | .hold => n

def windowOpen (p : Params) (c : Ctl) (now : Nat) : Bool := decide (c.lastChange + p.holdS ≤ now)

def nextN (p : Params) (c : Ctl) (s : Sample) : Nat := clamp p (target c.n (signal p c.prev s))

def step (p : Params) (c : Ctl) (s : Sample) : Ctl :=
  if windowOpen p c s.time && nextN p c s != c.n then
    { n := nextN p c s, lastChange := s.time, prev := some (s.time, s.mem.swapUsedMB) }
  else { c with prev := some (s.time, s.mem.swapUsedMB) }

def inRange (p : Params) (n : Nat) : Prop := p.nMin ≤ n ∧ n ≤ p.nMax

def init (p : Params) : Ctl := { n := clamp p 2, lastChange := 0 }

def okSample : Sample :=
  { time := 1000, loadCenti := 400, mem := { freeMB := 6000, swapUsedMB := 5000, swapTotalMB := 8192 }, ramMB := 16384,
    compressorMB := 2000, cores := 8 }

def Sample.withMem (s : Sample) (m : Mem) : Sample := { s with mem := m }

def Sample.withFree (s : Sample) (mb : Nat) : Sample := s.withMem { s.mem with freeMB := mb }

#guard (step {} { n := 2, lastChange := 0 } okSample).n == 3
#guard (step {} { n := 2, lastChange := 990 } okSample).n == 2
#guard (step {} { n := 4, lastChange := 0 } { okSample with loadCenti := 2000 }).n == 2
#guard (step {} { n := 1, lastChange := 0 } (okSample.withFree 500)).n == 1
#guard (step {} { n := 3, lastChange := 0, prev := some (995, 4900) } okSample).n == 1
#guard (step {} { n := 3, lastChange := 0, prev := some (995, 5000) } okSample).n == 4
#guard signal {} none { okSample with loadCenti := 1000 } == .hold

theorem clamp_range (p : Params) (h : p.nMin ≤ p.nMax) (x : Nat) : inRange p (clamp p x) := by
  unfold inRange clamp; omega

theorem step_range (p : Params) (h : p.nMin ≤ p.nMax) (c : Ctl) (s : Sample) (hc : inRange p c.n) :
    inRange p (step p c s).n := by
  unfold step
  split
  · exact clamp_range p h _
  · exact hc

theorem init_range (p : Params) (h : p.nMin ≤ p.nMax) : inRange p (init p).n := clamp_range p h 2

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

theorem step_window_closed (p : Params) (c : Ctl) (s : Sample) (h : s.time < c.lastChange + p.holdS) :
    (step p c s).n = c.n := by
  unfold step
  have : windowOpen p c s.time = false := by simp [windowOpen]; omega
  simp [this]

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

theorem overload_of_mem (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : memLow p s.mem = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem overload_of_cmprs (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : cmprsHigh p s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem overload_of_swap (p : Params) (prev : Option (Nat × Nat)) (s : Sample) (h : swapRising p prev s = true) :
    signal p prev s = .overload := signal_overload p prev s (by simp [overloaded, h])

theorem signal_under_iff (p : Params) (prev : Option (Nat × Nat)) (s : Sample) :
    signal p prev s = .under ↔ overloaded p prev s = false ∧ roomy p s = true := by
  unfold signal
  cases ho : overloaded p prev s <;> cases hr : roomy p s <;> simp

theorem step_overload (p : Params) (c : Ctl) (s : Sample) (hw : c.lastChange + p.holdS ≤ s.time)
    (h : overloaded p c.prev s = true) : (step p c s).n = clamp p (c.n / 2) := by
  rw [step_window_open p c s hw, signal_overload p c.prev s h]; rfl

theorem step_under (p : Params) (c : Ctl) (s : Sample) (hw : c.lastChange + p.holdS ≤ s.time)
    (h : overloaded p c.prev s = false) (hr : roomy p s = true) : (step p c s).n = clamp p (c.n + 1) := by
  rw [step_window_open p c s hw, (signal_under_iff p c.prev s).2 ⟨h, hr⟩]; rfl

theorem step_no_rise_on_overload (p : Params) (c : Ctl) (s : Sample) (hc : inRange p c.n)
    (h : overloaded p c.prev s = true) : (step p c s).n ≤ c.n := by
  by_cases hw : c.lastChange + p.holdS ≤ s.time
  · rw [step_overload p c s hw h]; unfold clamp; unfold inRange at hc; omega
  · rw [step_window_closed p c s (by omega)]; exact Nat.le_refl _

theorem swap_static_never_trips (p : Params) (t mb : Nat) (s : Sample) (hp : 0 < p.swapRiseMBPerMin)
    (h : s.mem.swapUsedMB ≤ mb) : swapRising p (some (t, mb)) s = false := by
  simp only [swapRising, decide_eq_false_iff_not, not_and, Nat.not_le]
  intro ht
  have : s.mem.swapUsedMB - mb = 0 := by omega
  rw [this]; exact Nat.mul_pos hp (by omega)

def changeTimes (p : Params) : Ctl → List Sample → List Nat
  | _, [] => []
  | c, s :: ss =>
    let c' := step p c s
    if c'.n = c.n then changeTimes p c' ss else s.time :: changeTimes p c' ss

def spaced (h : Nat) : Nat → List Nat → Prop
  | _, [] => True
  | a, b :: t => a + h ≤ b ∧ spaced h b t

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

structure Entry where
  owner : String
  token : String
  kind : Kind
  since : Nat
  till : Nat
  foot : Nat := 0
  leaseS : Nat := 0
deriving DecidableEq, Repr

def live (now : Nat) (e : Entry) : Bool := decide (now < e.till)

def prune (now : Nat) (es : List Entry) : List Entry := es.filter (live now)

def expired (now : Nat) (es : List Entry) : List Entry := es.filter (fun e => !live now e)

def same (owner token : String) (e : Entry) : Bool := e.owner == owner && e.token == token

def grantUntil (p : Params) (now lease : Nat) : Nat := now + min lease p.leaseMaxS

def grant (p : Params) (me : Entry) (now lease foot : Nat) : Entry :=
  { me with since := now, till := grantUntil p now lease, foot := foot, leaseS := min lease p.leaseMaxS }

def lenOf (p : Params) (lease : Option Nat) (e : Entry) : Nat :=
  match lease with
  | some l => min l p.leaseMaxS
  | none => e.leaseS

def renew (p : Params) (now : Nat) (owner token : String) (lease : Option Nat) (es : List Entry) : Option (List Entry) :=
  if es.any (fun e => same owner token e && live now e) then
    some (es.map fun e => if same owner token e then { e with till := now + lenOf p lease e, leaseS := lenOf p lease e } else e)
  else none

def leaseOr (stored : Option Nat) (since till : Nat) : Nat := stored.getD (till - since)

def release (owner token : String) (es : List Entry) : List Entry := es.filter (fun e => !same owner token e)

def holdA : Entry := { owner := "a", token := "t1", kind := .sim, since := 0, till := 100, leaseS := 100 }

#guard prune 50 [holdA] == [holdA]
#guard prune 100 [holdA] == []
#guard expired 50 [holdA] == []
#guard expired 100 [holdA] == [holdA]
#guard (renew {} 50 "a" "t1" (some 600) [holdA]).map (·.map fun e => (e.till, e.leaseS)) == some [(650, 600)]
#guard (renew {} 50 "a" "t1" none [holdA]).map (·.map fun e => (e.till, e.leaseS)) == some [(150, 100)]
#guard renew {} 50 "a" "t2" none [holdA] == none
#guard renew {} 100 "a" "t1" (some 600) [holdA] == none
#guard (grant {} holdA 10 99999 5).till == 3610
#guard (grant {} holdA 10 1800 5).leaseS == 1800
#guard leaseOr (some 30) 0 100 == 30
#guard leaseOr none 40 100 == 60
#guard release "a" "t1" [holdA] == []
#guard release "b" "t1" [holdA] == [holdA]

theorem live_never_recovered (now : Nat) (es : List Entry) (e : Entry) (he : e ∈ es) (hl : now < e.till) :
    e ∈ prune now es := by
  simp [prune, live, he, hl]

theorem recovered_expired (now : Nat) (es : List Entry) (e : Entry) (he : e ∈ es) (hr : e ∉ prune now es) :
    e.till ≤ now := by
  simp [prune, live, he] at hr; exact hr

theorem live_iff (now : Nat) (e : Entry) : live now e = true ↔ now < e.till := by simp [live]

theorem expire_emits (now : Nat) (es : List Entry) (e : Entry) (h : live now e = false) :
    (expired now es).count e = es.count e := by
  unfold expired
  rw [List.count_filter]
  simp [h]

theorem expire_live_silent (now : Nat) (es : List Entry) (e : Entry) (h : live now e = true) :
    (expired now es).count e = 0 := by
  unfold expired
  rw [List.count_eq_zero]
  simp [h]

theorem prune_expired_split (now : Nat) (es : List Entry) :
    (prune now es).length + (expired now es).length = es.length := by
  unfold prune expired
  induction es with
  | nil => rfl
  | cons x xs ih => by_cases hx : live now x = true <;> simp_all <;> omega

theorem grant_len (p : Params) (me : Entry) (now lease foot : Nat) :
    (grant p me now lease foot).till = (grant p me now lease foot).since + (grant p me now lease foot).leaseS := rfl

theorem renew_other (p : Params) (now : Nat) (o t : String) (lease : Option Nat) (es es' : List Entry)
    (h : renew p now o t lease es = some es') (e : Entry) (he : e ∈ es) (hs : same o t e = false) : e ∈ es' := by
  unfold renew at h
  split at h
  · cases h; exact List.mem_map.2 ⟨e, he, by simp [hs]⟩
  · cases h

theorem renew_keeps_len (p : Params) (now : Nat) (o t : String) (es es' : List Entry)
    (h : renew p now o t none es = some es') :
    es'.map (·.leaseS) = es.map (·.leaseS) ∧
      ∀ e ∈ es, same o t e = true → { e with till := now + e.leaseS } ∈ es' := by
  unfold renew at h
  split at h
  · cases h
    refine ⟨?_, fun e he hs => List.mem_map.2 ⟨e, he, by simp [hs, lenOf]⟩⟩
    rw [List.map_map]
    apply List.map_congr_left
    intro e _
    by_cases hs : same o t e = true <;> simp [hs, lenOf]
  · cases h

theorem renew_sets_len (p : Params) (now : Nat) (o t : String) (l : Nat) (es es' : List Entry)
    (h : renew p now o t (some l) es = some es') :
    ∀ e ∈ es, same o t e = true → { e with till := grantUntil p now l, leaseS := min l p.leaseMaxS } ∈ es' := by
  unfold renew at h
  split at h
  · cases h
    exact fun e he hs => List.mem_map.2 ⟨e, he, by simp [hs, lenOf, grantUntil]⟩
  · cases h

theorem grant_renew_keeps (p : Params) (me : Entry) (t0 now lease foot : Nat) (es es' : List Entry)
    (h : renew p now me.owner me.token none (es ++ [grant p me t0 lease foot]) = some es') :
    { grant p me t0 lease foot with till := now + min lease p.leaseMaxS } ∈ es' :=
  (renew_keeps_len p now me.owner me.token _ es' h).2 _ (by simp) (by simp [same, grant])

theorem renew_live (p : Params) (now : Nat) (o t : String) (lease : Option Nat) (es es' : List Entry)
    (h : renew p now o t lease es = some es') (hl : ∀ e ∈ es, same o t e = true → 0 < lenOf p lease e) :
    ∀ e ∈ es', same o t e = true → live now e = true := by
  unfold renew at h
  split at h
  · cases h
    intro e he hs
    obtain ⟨x, hx0, rfl⟩ := List.mem_map.1 he
    by_cases hx : same o t x = true
    · have := hl x hx0 hx
      simp [hx, live]; omega
    · simp [hx] at hs
  · cases h

theorem leaseOr_stored (l since till : Nat) : leaseOr (some l) since till = l := rfl

theorem leaseOr_legacy (since till : Nat) (h : since ≤ till) : since + leaseOr none since till = till := by
  simp [leaseOr]; omega

theorem renew_none (p : Params) (now : Nat) (o t : String) (lease : Option Nat) (es : List Entry)
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

def leanThreads (p : Params) (cores roomMB : Nat) : Nat := max 1 (min cores (roomMB / p.leanProcMB))

def foot (p : Params) (threads : Nat) : Kind → Nat
  | .check => threads * p.leanProcMB
  | .test => p.testMB
  | .land => p.landMB
  | .sim => p.simMB
  | .other => p.otherMB
  | .measure => p.measureMB

def charged (p : Params) (now : Nat) (hs : List Entry) : Nat :=
  ((prune now hs).filter (fun h => decide (now < h.since + p.warmS))).foldr (fun h a => h.foot + a) 0

def room (p : Params) (s : Sample) (hs : List Entry) : Nat := s.avail - p.floorMB - charged p s.time hs

def threadsFor (p : Params) (s : Sample) (hs : List Entry) : Nat := leanThreads p s.cores (room p s hs)

def need (p : Params) (s : Sample) (hs : List Entry) (k : Kind) : Nat := foot p (threadsFor p s hs) k

inductive Why where
  | queued (ahead : Nat)
  | older
  | full (running limit : Nat)
  | simBusy
  | drain (others : Nat)
  | memory (needMB roomMB : Nat)
  | memLow (availMB : Nat)
  | simFirst
  | pass
  | gap (needS leftS : Nat)
  | unknown
  | measureBusy
deriving DecidableEq, Repr

/-- The reason of a wait without its numbers: one constructor per `Why` constructor. It is the one canonical list of
reason names; the timing verdict and the TS span parse read it. -/
inductive WhyTag where
  | queued | older | full | simBusy | drain | memory | memLow | simFirst | pass | gap | unknown | measureBusy
deriving DecidableEq, Repr

/-- The tag of a reason. -/
def Why.tag : Why → WhyTag
  | .queued _ => .queued
  | .older => .older
  | .full _ _ => .full
  | .simBusy => .simBusy
  | .drain _ => .drain
  | .memory _ _ => .memory
  | .memLow _ => .memLow
  | .simFirst => .simFirst
  | .pass => .pass
  | .gap _ _ => .gap
  | .unknown => .unknown
  | .measureBusy => .measureBusy

/-- The wire name of a tag: the `why` field of a verdict. -/
def WhyTag.name : WhyTag → String
  | .queued => "queued"
  | .older => "older"
  | .full => "full"
  | .simBusy => "simBusy"
  | .drain => "drain"
  | .memory => "memory"
  | .memLow => "memLow"
  | .simFirst => "simFirst"
  | .pass => "pass"
  | .gap => "gap"
  | .unknown => "unknown"
  | .measureBusy => "measureBusy"

/-- Every tag, once. -/
def WhyTag.all : List WhyTag :=
  [.queued, .older, .full, .simBusy, .drain, .memory, .memLow, .simFirst, .pass, .gap, .unknown, .measureBusy]

/-- The tag of a wire name, or none for an unknown name. -/
def WhyTag.ofName? (n : String) : Option WhyTag := WhyTag.all.find? (fun t => t.name == n)

theorem WhyTag.all_complete (t : WhyTag) : t ∈ WhyTag.all := by cases t <;> simp [WhyTag.all]

theorem WhyTag.ofName_name (t : WhyTag) : WhyTag.ofName? t.name = some t := by cases t <;> decide

inductive Verdict where
  | admit (threads footMB : Nat)
  | wait (why : Why)
  | timeout (why : Why)
deriving DecidableEq, Repr

def waitOr (p : Params) (waited : Nat) (w : Why) : Verdict :=
  if p.maxWaitS ≤ waited then .timeout w else .wait w

def before (q : List Entry) (me : Entry) : List Entry := q.takeWhile (fun e => e.token != me.token)

def aheadSame (q : List Entry) (me : Entry) : Nat := ((before q me).filter (fun e => e.kind == me.kind)).length

def simHeld (now : Nat) (hs : List Entry) : Bool := (prune now hs).any (fun h => h.kind == .sim)

def heldOf (now : Nat) (hs : List Entry) (k : Kind) : Bool := (prune now hs).any (fun h => h.kind == k)

theorem heldOf_sim (now : Nat) (hs : List Entry) : heldOf now hs .sim = simHeld now hs := rfl

def others (now : Nat) (hs : List Entry) : Nat := ((prune now hs).filter (fun h => h.kind != .sim)).length

def simPending (now : Nat) (hs q : List Entry) : Bool := q.any (fun e => e.kind == .sim) && !simHeld now hs

def starved (p : Params) (now : Nat) (hs q : List Entry) (me : Entry) : Bool :=
  (before q me).any (fun e => e.kind != me.kind && decide (e.since + p.ageS ≤ now) && !(e.kind == .sim && simHeld now hs))

def yieldsToSim (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) : Bool :=
  me.kind != .sim &&
    ((simHeld s.time hs && decide (0 < others s.time hs)) ||
      (simPending s.time hs q &&
        (decide (0 < others s.time hs) || decide (n < (prune s.time hs).length + 2) ||
          decide (s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs + p.simMB))))

def idleHead (p : Params) (s : Sample) (hs : List Entry) : Bool :=
  (prune s.time hs).isEmpty && decide (s.mem.press = 1) && !thrash p s.mem && !swapActive p s.mem

def verdictWith (idle : Bool) (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat) :
    Verdict :=
  let running := (prune s.time hs).length
  if 0 < aheadSame q me then waitOr p waited (.queued (aheadSame q me))
  else if me.kind != .sim && starved p s.time hs q me then waitOr p waited .older
  else if n ≤ running then waitOr p waited (.full running n)
  else if me.kind == .sim && simHeld s.time hs then waitOr p waited .simBusy
  else if me.kind == .sim && decide (1 < others s.time hs) then waitOr p waited (.drain (others s.time hs))
  else if memLow p s.mem && !idle then waitOr p waited (.memLow s.avail)
  else if decide (s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs) && !idle then
    waitOr p waited (.memory (need p s hs me.kind) (room p s hs))
  else if yieldsToSim p n s hs q me then waitOr p waited .simFirst
  else .admit (threadsFor p s hs) (need p s hs me.kind)

def verdict (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat) : Verdict :=
  verdictWith (idleHead p s hs) p n s hs q me waited

def tk (o t : String) (k : Kind) (t0 : Nat) : Entry := { owner := o, token := t, kind := k, since := t0, till := t0 + 60 }

def simH : Entry := { tk "c" "9" .sim 0 with till := 2000 }

def oldH : Entry := { tk "d" "8" .test 0 with till := 2000 }

def stallMem : Mem :=
  { freeMB := 179, specMB := 17, purgMB := 85, fileMB := 4443, fileMinMB := 4608, swapUsedMB := 3276, swapTotalMB := 4096,
    press := 1, comprMBPerMin := 0, swapOutMBPerMin := 0 }

def stallSample : Sample := okSample.withMem stallMem

#guard verdict {} 2 okSample [] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 7 4900
#guard verdict {} 2 okSample [] [tk "a" "1" .test 990, tk "b" "2" .test 991] (tk "b" "2" .test 991) 0 == .wait (.queued 1)
#guard verdict {} 2 okSample [] [tk "a" "1" .test 600, tk "b" "2" .sim 991] (tk "b" "2" .sim 991) 0 == .admit 7 2800
#guard verdict {} 1 okSample [{ tk "c" "9" .test 0 with till := 2000 }] [tk "a" "1" .test 990] (tk "a" "1" .test 990) 0 == .wait (.full 1 1)
#guard verdict {} 3 okSample [simH] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 0 == .wait .simBusy
#guard verdict {} 4 okSample [simH] [tk "s" "5" .sim 600, tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 7 4900
#guard verdict {} 4 okSample [simH, { tk "d" "8" .test 0 with till := 2000 }] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .wait .simFirst
#guard verdict {} 4 okSample [] [tk "s" "5" .sim 600, tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .wait .older
#guard verdict {} 4 okSample [] [tk "a" "1" .check 990, tk "s" "5" .sim 995] (tk "a" "1" .check 990) 0 == .wait .simFirst
#guard verdict {} 4 (okSample.withFree 12000) [] [tk "a" "1" .check 990, tk "s" "5" .sim 995] (tk "a" "1" .check 990) 0 == .admit 8 5600
#guard verdict {} 1 (okSample.withFree 12000) [] [tk "a" "1" .check 990, tk "s" "5" .sim 995] (tk "a" "1" .check 990) 0 == .wait .simFirst
#guard verdict {} 4 okSample [{ tk "d" "8" .test 0 with till := 2000 }, { tk "e" "7" .land 0 with till := 2000 }]
  [tk "s" "5" .sim 990] (tk "s" "5" .sim 990) 0 == .wait (.drain 2)
#guard verdict {} 3 (okSample.withFree 3000) [oldH] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 0 == .wait (.memory 2800 1976)
#guard verdict {} 3 (okSample.withFree 3000) [oldH] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 1800
  == .timeout (.memory 2800 1976)
#guard verdict {} 3 (okSample.withFree 3000) [] [tk "a" "1" .sim 990] (tk "a" "1" .sim 990) 0 == .admit 2 2800
#guard verdict {} 2 { okSample with mem := { okSample.mem with press := 2 } } [] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0
  == .wait (.memLow 6000)
#guard verdict {} 2 { okSample with mem := { okSample.mem with comprMBPerMin := 5309 } } [] [tk "a" "1" .sim 990]
  (tk "a" "1" .sim 990) 0 == .wait (.memLow 6000)
#guard verdict {} 2 (okSample.withFree 1755) [] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 1 700
#guard stallSample.avail == 281
#guard verdict {} 2 stallSample [] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .admit 1 700
#guard verdict {} 2 stallSample [oldH] [tk "a" "1" .check 990] (tk "a" "1" .check 990) 0 == .wait (.memLow 281)
#guard verdict {} 2 stallSample [] [tk "a" "1" .check 990, tk "b" "2" .check 991] (tk "b" "2" .check 991) 0
  == .wait (.queued 1)
#guard verdict {} 2 (stallSample.withMem { stallSample.mem with swapOutMBPerMin := 64 }) [] [tk "a" "1" .check 990]
  (tk "a" "1" .check 990) 0 == .wait (.memLow 281)
#guard verdict {} 2 (stallSample.withMem { stallSample.mem with press := 2 }) [] [tk "a" "1" .check 990]
  (tk "a" "1" .check 990) 0 == .wait (.memLow 281)
#guard verdict {} 2 (stallSample.withMem { stallSample.mem with comprMBPerMin := 1500 }) [] [tk "a" "1" .check 990]
  (tk "a" "1" .check 990) 0 == .wait (.memLow 281)

theorem waitOr_ne_admit (p : Params) (w : Nat) (y : Why) (t f : Nat) : ¬ waitOr p w y = .admit t f := by
  unfold waitOr; split <;> simp

theorem verdict_admit (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) :
    aheadSame q me = 0 ∧ (me.kind != .sim && starved p s.time hs q me) = false ∧ (prune s.time hs).length < n ∧
      (me.kind == .sim && simHeld s.time hs) = false ∧ (me.kind == .sim && decide (1 < others s.time hs)) = false ∧
      (need p s hs me.kind + p.floorMB + charged p s.time hs ≤ s.avail ∨ idleHead p s hs = true) ∧
      yieldsToSim p n s hs q me = false ∧ t = threadsFor p s hs ∧ f = need p s hs me.kind := by
  unfold verdict verdictWith at h
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
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  rename_i h1 h2 h3 h4 h5 _ h6 h7
  cases h
  refine ⟨by omega, by simpa using h2, by omega, by simpa using h4, by simpa using h5, ?_, by simpa using h7, rfl, rfl⟩
  cases hi : idleHead p s hs
  · simp only [hi, Bool.not_false, Bool.and_true, decide_eq_true_eq] at h6; omega
  · exact .inr rfl

theorem admit_fits (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) :
    f + p.floorMB + charged p s.time hs ≤ s.avail ∨ idleHead p s hs = true := by
  have := verdict_admit p n s hs q me w t f h
  rw [this.2.2.2.2.2.2.2.2]; exact this.2.2.2.2.2.1

theorem verdict_admit_memLow (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : memLow p s.mem = false ∨ idleHead p s hs = true := by
  unfold verdict verdictWith at h
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
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  rename_i _ _ _ _ _ hm _ _
  cases hi : idleHead p s hs
  · simpa [hi] using hm
  · exact .inr rfl

theorem memLow_false (p : Params) (m : Mem) (hp : m.press = 1) (hs : swapActive p m = false) (ht : thrash p m = false)
    (ha : p.floorMB ≤ availMB m) : memLow p m = false := by
  simp [memLow, hp, hs, ht]; omega

theorem idleHead_iff (p : Params) (s : Sample) (hs : List Entry) :
    idleHead p s hs = true ↔
      prune s.time hs = [] ∧ s.mem.press = 1 ∧ thrash p s.mem = false ∧ swapActive p s.mem = false := by
  simp [idleHead, and_assoc]

theorem admit_calm (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) :
    s.mem.press = 1 ∧ swapActive p s.mem = false ∧ thrash p s.mem = false ∧
      (p.floorMB ≤ s.avail ∨ prune s.time hs = []) := by
  rcases verdict_admit_memLow p n s hs q me w t f h with hm | hi
  · simp only [memLow, Bool.or_eq_false_iff, decide_eq_false_iff_not, Nat.not_lt, Decidable.not_not] at hm
    exact ⟨hm.1.1.2, hm.1.2, hm.2, .inl hm.1.1.1⟩
  · obtain ⟨h0, hp, ht, hw⟩ := (idleHead_iff p s hs).1 hi
    exact ⟨hp, hw, ht, .inr h0⟩

theorem idle_head_only_when_empty (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f)
    (hlow : memLow p s.mem = true ∨ s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs) :
    prune s.time hs = [] ∧ aheadSame q me = 0 ∧ (me.kind != .sim && starved p s.time hs q me) = false ∧
      s.mem.press = 1 ∧ thrash p s.mem = false ∧ swapActive p s.mem = false := by
  have ha := verdict_admit p n s hs q me w t f h
  have hi : idleHead p s hs = true := by
    rcases hlow with hl | hl
    · rcases verdict_admit_memLow p n s hs q me w t f h with hm | hm
      · simp [hm] at hl
      · exact hm
    · rcases ha.2.2.2.2.2.1 with hf | hf
      · omega
      · exact hf
  obtain ⟨h0, hp, ht, hw⟩ := (idleHead_iff p s hs).1 hi
  exact ⟨h0, ha.1, ha.2.1, hp, ht, hw⟩

theorem verdict_unchanged_with_holder (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (h : prune s.time hs ≠ []) : verdict p n s hs q me w = verdictWith false p n s hs q me w := by
  have : idleHead p s hs = false := by
    cases hi : idleHead p s hs
    · rfl
    · exact absurd ((idleHead_iff p s hs).1 hi).1 h
  simp only [verdict, this]

theorem verdict_admit_under_n (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : (prune s.time hs).length < n :=
  (verdict_admit p n s hs q me w t f h).2.2.1

theorem verdict_admit_head (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) : aheadSame q me = 0 :=
  (verdict_admit p n s hs q me w t f h).1

theorem verdict_admit_sim_exclusive (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind = .sim) : simHeld s.time hs = false := by
  have := (verdict_admit p n s hs q me w t f h).2.2.2.1
  simpa [hk] using this

theorem verdict_admit_sim_drained (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind = .sim) : others s.time hs ≤ 1 := by
  have := (verdict_admit p n s hs q me w t f h).2.2.2.2.1
  simp [hk] at this; omega

theorem yieldsToSim_false (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (hk : me.kind ≠ .sim)
    (h : yieldsToSim p n s hs q me = false) :
    (simHeld s.time hs = true → others s.time hs = 0) ∧
      (simPending s.time hs q = true → others s.time hs = 0 ∧ (prune s.time hs).length + 2 ≤ n ∧
        need p s hs me.kind + p.floorMB + charged p s.time hs + p.simMB ≤ s.avail) := by
  have hk' : (me.kind != .sim) = true := by simpa using hk
  simp only [yieldsToSim, hk', Bool.true_and, Bool.or_eq_false_iff, Bool.and_eq_false_iff, decide_eq_false_iff_not] at h
  obtain ⟨h1, h2⟩ := h
  refine ⟨fun hh => ?_, fun hp => ?_⟩
  · rcases h1 with h1 | h1
    · simp [hh] at h1
    · omega
  · rcases h2 with h2 | h2
    · simp [hp] at h2
    · omega

theorem verdict_admit_beside_sim (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind ≠ .sim) (hh : simHeld s.time hs = true) :
    others s.time hs = 0 :=
  (yieldsToSim_false p n s hs q me hk (verdict_admit p n s hs q me w t f h).2.2.2.2.2.2.1).1 hh

theorem verdict_admit_reserves_sim (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind ≠ .sim) (hp : simPending s.time hs q = true) :
    others s.time hs = 0 ∧ (prune s.time hs).length + 2 ≤ n ∧ f + p.simMB + p.floorMB + charged p s.time hs ≤ s.avail := by
  have ha := verdict_admit p n s hs q me w t f h
  have := (yieldsToSim_false p n s hs q me hk ha.2.2.2.2.2.2.1).2 hp
  rw [ha.2.2.2.2.2.2.2.2]
  exact ⟨this.1, this.2.1, by omega⟩

theorem verdict_head_admitted (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (h1 : aheadSame q me = 0) (h2 : (me.kind != .sim && starved p s.time hs q me) = false)
    (h3 : (prune s.time hs).length < n) (h4 : (me.kind == .sim && simHeld s.time hs) = false)
    (h5 : (me.kind == .sim && decide (1 < others s.time hs)) = false) (hm : memLow p s.mem = false ∨ idleHead p s hs = true)
    (h6 : need p s hs me.kind + p.floorMB + charged p s.time hs ≤ s.avail ∨ idleHead p s hs = true)
    (h7 : yieldsToSim p n s hs q me = false) :
    verdict p n s hs q me w = .admit (threadsFor p s hs) (need p s hs me.kind) := by
  unfold verdict verdictWith
  have h3' : ¬ n ≤ (prune s.time hs).length := by omega
  have hm' : (memLow p s.mem && !idleHead p s hs) = false := by rcases hm with hm | hm <;> simp [hm]
  have h6' : (decide (s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs) && !idleHead p s hs) = false := by
    rcases h6 with h6 | h6
    · have : ¬ s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs := by omega
      simp [this]
    · simp [h6]
  simp only [h1, Nat.lt_irrefl, ite_false, h2, h3', h4, h5, hm', h6', h7, Bool.false_eq_true]

theorem idle_head_admitted (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (h1 : aheadSame q me = 0) (h2 : (me.kind != .sim && starved p s.time hs q me) = false) (h0 : prune s.time hs = [])
    (hn : 0 < n) (hp : s.mem.press = 1) (ht : thrash p s.mem = false) (hw : swapActive p s.mem = false)
    (h7 : yieldsToSim p n s hs q me = false) :
    verdict p n s hs q me w = .admit (threadsFor p s hs) (need p s hs me.kind) := by
  have hi : idleHead p s hs = true := (idleHead_iff p s hs).2 ⟨h0, hp, ht, hw⟩
  apply verdict_head_admitted p n s hs q me w h1 h2 (by simp [h0]; omega) (by simp [simHeld, h0])
    (by simp [others, h0]) (.inr hi) (.inr hi) h7

theorem starved_iff (p : Params) (now : Nat) (hs q : List Entry) (me : Entry) :
    starved p now hs q me = true ↔ ∃ e ∈ before q me, e.kind ≠ me.kind ∧ e.since + p.ageS ≤ now ∧
      (e.kind = .sim → simHeld now hs = false) := by
  simp [starved, Decidable.imp_iff_not_or, and_assoc]

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

theorem verdict_older (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (h : verdict p n s hs q me w = .wait .older ∨ verdict p n s hs q me w = .timeout .older) :
    me.kind ≠ .sim ∧ starved p s.time hs q me = true := by
  unfold verdict verdictWith at h
  simp only at h
  split at h
  · have := waitOr_ne_older p w (.queued (aheadSame q me)) (by simp); rcases h with h | h <;> simp_all
  split at h
  · rename_i h2; simp only [Bool.and_eq_true, bne_iff_ne, ne_eq] at h2; exact h2
  split at h
  · have := waitOr_ne_older p w (.full (prune s.time hs).length n) (by simp); rcases h with h | h <;> simp_all
  split at h
  · have := waitOr_ne_older p w .simBusy (by simp); rcases h with h | h <;> simp_all
  split at h
  · have := waitOr_ne_older p w (.drain (others s.time hs)) (by simp); rcases h with h | h <;> simp_all
  split at h
  · have := waitOr_ne_older p w (.memLow s.avail) (by simp); rcases h with h | h <;> simp_all
  split at h
  · have := waitOr_ne_older p w (.memory (need p s hs me.kind) (room p s hs)) (by simp); rcases h with h | h <;> simp_all
  split at h
  · have := waitOr_ne_older p w .simFirst (by simp); rcases h with h | h <;> simp_all
  · rcases h with h | h <;> cases h

theorem verdict_sim_never_older (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (hk : me.kind = .sim) : verdict p n s hs q me w ≠ .wait .older ∧ verdict p n s hs q me w ≠ .timeout .older :=
  ⟨fun h => (verdict_older p n s hs q me w (.inl h)).1 hk, fun h => (verdict_older p n s hs q me w (.inr h)).1 hk⟩

theorem verdict_not_older_of_sim_blocked (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w : Nat)
    (hb : simHeld s.time hs = true) (hq : ∀ e ∈ before q me, e.kind ≠ me.kind → e.kind = .sim) :
    verdict p n s hs q me w ≠ .wait .older ∧ verdict p n s hs q me w ≠ .timeout .older := by
  have hst : starved p s.time hs q me = false := by
    cases h : starved p s.time hs q me
    · rfl
    · obtain ⟨e, he, hk, _, hn⟩ := (starved_iff p s.time hs q me).1 h
      simp [hn (hq e he hk)] at hb
  refine ⟨fun h => ?_, fun h => ?_⟩
  · simp [(verdict_older p n s hs q me w (.inl h)).2] at hst
  · simp [(verdict_older p n s hs q me w (.inr h)).2] at hst

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

theorem leanThreads_fit (p : Params) (c r : Nat) (hr : p.leanProcMB ≤ r) :
    leanThreads p c r * p.leanProcMB ≤ r := by
  unfold leanThreads
  by_cases hp : p.leanProcMB = 0
  · simp [hp]
  have hq : 1 ≤ r / p.leanProcMB := (Nat.le_div_iff_mul_le (by omega)).2 (by omega)
  have hm : max 1 (min c (r / p.leanProcMB)) ≤ r / p.leanProcMB := by omega
  calc max 1 (min c (r / p.leanProcMB)) * p.leanProcMB ≤ r / p.leanProcMB * p.leanProcMB := Nat.mul_le_mul_right _ hm
    _ ≤ r := Nat.div_mul_le_self r p.leanProcMB

theorem threads_fit (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (h : verdict p n s hs q me w = .admit t f) :
    t * p.leanProcMB ≤ s.avail - p.floorMB - charged p s.time hs ∨ t = 1 := by
  rw [(verdict_admit p n s hs q me w t f h).2.2.2.2.2.2.2.1]
  by_cases hr : p.leanProcMB ≤ room p s hs
  · exact .inl (leanThreads_fit p s.cores _ hr)
  · right
    have : room p s hs / p.leanProcMB = 0 := Nat.div_eq_of_lt (by omega)
    simp only [threadsFor, leanThreads, this]; omega

def Worse (m m' : Mem) : Prop :=
  availMB m' ≤ availMB m ∧ 1 ≤ m.press ∧ m.press ≤ m'.press ∧ m.swapOutMBPerMin ≤ m'.swapOutMBPerMin ∧
    m.comprMBPerMin ≤ m'.comprMBPerMin

theorem memLow_antitone (p : Params) (m m' : Mem) (hw : Worse m m') (h : memLow p m' = false) : memLow p m = false := by
  obtain ⟨ha, hp1, hp, hsw, hc⟩ := hw
  simp only [memLow, swapActive, thrash, Bool.or_eq_false_iff, decide_eq_false_iff_not, Nat.not_le, Nat.not_lt,
    Decidable.not_not] at h ⊢
  omega

theorem idleHead_antitone (p : Params) (s : Sample) (m' : Mem) (hs : List Entry) (hw : Worse s.mem m')
    (h : idleHead p { s with mem := m' } hs = true) : idleHead p s hs = true := by
  obtain ⟨_, hp1, hp, hsw, hc⟩ := hw
  obtain ⟨h0, h1, h2, h3⟩ := (idleHead_iff p _ hs).1 h
  simp only [thrash, swapActive, decide_eq_false_iff_not, Nat.not_le] at h2 h3
  refine (idleHead_iff p s hs).2 ⟨h0, by simp at h1; omega, ?_, ?_⟩ <;> simp [thrash, swapActive] <;> omega

theorem threads_fit_mono (L c r r' e : Nat) (he : e = 0 ∨ L ≤ e) (hr : r' ≤ r)
    (h : max 1 (min c (r' / L)) * L + e ≤ r') : max 1 (min c (r / L)) * L + e ≤ r := by
  rcases Nat.eq_zero_or_pos L with hL | hL
  · subst hL; simp at h ⊢; omega
  have ha1 := Nat.div_mul_le_self r' L
  have ha2 := Nat.lt_div_mul_add (a := r') hL
  have hb1 := Nat.div_mul_le_self r L
  have hab : r' / L ≤ r / L := Nat.div_le_div_right hr
  generalize r' / L = a at *
  generalize r / L = b at *
  have hpos : ∀ x, L ≤ max 1 x * L := fun x => Nat.le_mul_of_pos_left L (by omega)
  have hl1 := hpos (min c a)
  by_cases hca : c ≤ a
  · have hb : max 1 (min c b) = max 1 (min c a) := by omega
    rw [hb]; omega
  rcases he with he | he
  · subst he
    by_cases hb0 : b = 0
    · subst hb0
      have : max 1 (min c 0) * L ≤ max 1 (min c a) * L := Nat.mul_le_mul_right L (by omega)
      omega
    · have : max 1 (min c b) * L ≤ b * L := Nat.mul_le_mul_right L (by omega)
      omega
  · by_cases ha0 : a = 0
    · subst ha0; omega
    · have : max 1 (min c a) = a := by omega
      rw [this] at h; omega

theorem need_fit_mono (p : Params) (s s' : Sample) (hs : List Entry) (k : Kind) (e : Nat) (he : e = 0 ∨ p.leanProcMB ≤ e)
    (ht : s'.time = s.time) (hc : s'.cores = s.cores) (ha : s'.avail ≤ s.avail)
    (h : need p s' hs k + p.floorMB + charged p s'.time hs + e ≤ s'.avail) :
    need p s hs k + p.floorMB + charged p s.time hs + e ≤ s.avail := by
  rw [ht] at h
  cases k
  case check =>
    simp only [need, foot, threadsFor, room, leanThreads, hc, ht] at h ⊢
    have := threads_fit_mono p.leanProcMB s.cores (s.avail - p.floorMB - charged p s.time hs)
      (s'.avail - p.floorMB - charged p s.time hs) e he (by omega) (by omega)
    omega
  all_goals simp only [need, foot] at h ⊢; omega

theorem yieldsToSim_antitone (p : Params) (n : Nat) (s s' : Sample) (hs q : List Entry) (me : Entry)
    (hp : p.leanProcMB ≤ p.simMB) (ht : s'.time = s.time) (hc : s'.cores = s.cores) (ha : s'.avail ≤ s.avail)
    (h : yieldsToSim p n s' hs q me = false) : yieldsToSim p n s hs q me = false := by
  by_cases hk : me.kind = .sim
  · simp [yieldsToSim, hk]
  have hk' : (me.kind != .sim) = true := by simpa using hk
  have hn : ¬ s'.avail < need p s' hs me.kind + p.floorMB + charged p s'.time hs + p.simMB →
      ¬ s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs + p.simMB := fun h2 => by
    have := need_fit_mono p s s' hs me.kind p.simMB (.inr hp) ht hc ha (by omega)
    omega
  rw [ht] at hn
  simp only [yieldsToSim, hk', ht, Bool.true_and, Bool.or_eq_false_iff, Bool.and_eq_false_iff, decide_eq_false_iff_not] at h ⊢
  obtain ⟨h1, h2⟩ := h
  refine ⟨h1, ?_⟩
  rcases h2 with h2 | h2
  · exact .inl h2
  · exact .inr ⟨h2.1, hn h2.2⟩

theorem verdict_antitone (p : Params) (hp : p.leanProcMB ≤ p.simMB) (n : Nat) (s : Sample) (m' : Mem)
    (hs q : List Entry) (me : Entry) (w t f : Nat) (hw : Worse s.mem m')
    (h : verdict p n { s with mem := m' } hs q me w = .admit t f) :
    verdict p n s hs q me w = .admit (threadsFor p s hs) (need p s hs me.kind) := by
  have ha := verdict_admit p n _ hs q me w t f h
  have hav : ({ s with mem := m' } : Sample).avail ≤ s.avail := hw.1
  apply verdict_head_admitted
  · exact ha.1
  · exact ha.2.1
  · exact ha.2.2.1
  · exact ha.2.2.2.1
  · exact ha.2.2.2.2.1
  · rcases verdict_admit_memLow p n _ hs q me w t f h with hm | hi
    · exact .inl (memLow_antitone p s.mem m' hw hm)
    · exact .inr (idleHead_antitone p s m' hs hw hi)
  · rcases ha.2.2.2.2.2.1 with hf | hi
    · left
      have := need_fit_mono p s { s with mem := m' } hs me.kind 0 (.inl rfl) rfl rfl hav (by omega)
      omega
    · exact .inr (idleHead_antitone p s m' hs hw hi)
  · exact yieldsToSim_antitone p n s { s with mem := m' } hs q me hp rfl rfl hav ha.2.2.2.2.2.2.1

def holderOf (me : Entry) (now till f : Nat) : Entry := { me with since := now, till := till, foot := f }

theorem prune_append_live (now : Nat) (hs : List Entry) (x : Entry) (hx : now < x.till) :
    prune now (hs ++ [x]) = prune now hs ++ [x] := by
  simp [prune, List.filter_append, live, hx]

theorem simHeld_append (now : Nat) (hs : List Entry) (x : Entry) (hx : now < x.till) :
    simHeld now (hs ++ [x]) = (simHeld now hs || x.kind == .sim) := by
  simp [simHeld, prune_append_live now hs x hx, List.any_append]

theorem others_append (now : Nat) (hs : List Entry) (x : Entry) (hx : now < x.till) :
    others now (hs ++ [x]) = others now hs + (if x.kind = .sim then 0 else 1) := by
  unfold others
  rw [prune_append_live now hs x hx, List.filter_append, List.length_append]
  by_cases hk : x.kind = .sim <;> simp [hk]

theorem charged_append_le (p : Params) (now : Nat) (hs : List Entry) (x : Entry) :
    charged p now (hs ++ [x]) ≤ charged p now hs + x.foot := by
  unfold charged prune
  rw [List.filter_append, List.filter_append, List.foldr_append]
  generalize ((hs.filter (live now)).filter (fun h => decide (now < h.since + p.warmS))) = l
  have key : ∀ (l : List Entry) (b : Nat), l.foldr (fun h a => h.foot + a) b = l.foldr (fun h a => h.foot + a) 0 + b := by
    intro l b
    induction l with
    | nil => simp
    | cons y ys ih => simp only [List.foldr_cons, ih]; omega
  rw [key l]
  have : (List.filter (fun h => decide (now < h.since + p.warmS)) (List.filter (live now) [x])).foldr
      (fun h a => h.foot + a) 0 ≤ x.foot := by
    by_cases h1 : live now x = true <;> by_cases h2 : now < x.since + p.warmS <;> simp [h1, h2]
  omega

theorem charged_append_warm (p : Params) (now : Nat) (hs : List Entry) (x : Entry) (hx : now < x.till)
    (hw : now < x.since + p.warmS) : charged p now (hs ++ [x]) = charged p now hs + x.foot := by
  unfold charged
  rw [prune_append_live now hs x hx, List.filter_append, List.foldr_append]
  generalize (prune now hs).filter (fun h => decide (now < h.since + p.warmS)) = l
  simp only [List.filter_cons, hw, decide_true, ite_true, List.filter_nil, List.foldr_cons, List.foldr_nil, Nat.add_zero]
  induction l with
  | nil => simp
  | cons y ys ih => simp only [List.foldr_cons, ih]; omega

theorem idle_head_at_most_one (p : Params) (hw : 0 < p.warmS) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry)
    (w t f till : Nat) (h : verdict p n s hs q me w = .admit t f)
    (hlow : memLow p s.mem = true ∨ s.avail < need p s hs me.kind + p.floorMB + charged p s.time hs)
    (ht : s.time < till) (q' : List Entry) (e : Entry) (w' t' f' : Nat) :
    verdict p n s (hs ++ [holderOf me s.time till f]) q' e w' ≠ .admit t' f' := by
  intro h'
  have hx : s.time < (holderOf me s.time till f).till := ht
  have hne : prune s.time (hs ++ [holderOf me s.time till f]) ≠ [] := by simp [prune_append_live _ _ _ hx]
  have hni : idleHead p s (hs ++ [holderOf me s.time till f]) = false := by
    cases hi : idleHead p s (hs ++ [holderOf me s.time till f])
    · rfl
    · exact absurd ((idleHead_iff p s _).1 hi).1 hne
  rcases hlow with hl | hl
  · rcases verdict_admit_memLow p n s _ q' e w' t' f' h' with hm | hm
    · simp [hl] at hm
    · simp [hni] at hm
  · have hf : f = need p s hs me.kind := (verdict_admit p n s hs q me w t f h).2.2.2.2.2.2.2.2
    have hc := charged_append_warm p s.time hs (holderOf me s.time till f) hx (by simp [holderOf]; omega)
    rcases (verdict_admit p n s _ q' e w' t' f' h').2.2.2.2.2.1 with hfit | hi
    · rw [hc] at hfit
      have : (holderOf me s.time till f).foot = f := rfl
      omega
    · simp [hni] at hi

def simInv (now : Nat) (hs : List Entry) : Prop := simHeld now hs = true → others now hs ≤ 1

theorem admit_keeps_simInv (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f till : Nat)
    (h : verdict p n s hs q me w = .admit t f) (ht : s.time < till) :
    simInv s.time (hs ++ [holderOf me s.time till f]) := by
  intro hh
  have hx : s.time < (holderOf me s.time till f).till := ht
  have hk' : (holderOf me s.time till f).kind = me.kind := rfl
  rw [others_append _ _ _ hx, hk']
  rw [simHeld_append _ _ _ hx, hk'] at hh
  by_cases hk : me.kind = .sim
  · simp only [hk, ite_true]
    have := verdict_admit_sim_drained p n s hs q me w t f h hk
    omega
  · simp only [hk, ite_false]
    have hs' : simHeld s.time hs = true := by simpa [hk] using hh
    have := verdict_admit_beside_sim p n s hs q me w t f h hk hs'
    omega

theorem sim_not_starved (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f till : Nat)
    (h : verdict p n s hs q me w = .admit t f) (hk : me.kind ≠ .sim) (hp : simPending s.time hs q = true)
    (ht : s.time < till) (q' : List Entry) (e : Entry) (he : e.kind = .sim) (h1 : aheadSame q' e = 0) (w' : Nat) :
    verdict p n s (hs ++ [holderOf me s.time till f]) q' e w' =
      .admit (threadsFor p s (hs ++ [holderOf me s.time till f])) p.simMB := by
  have hx : s.time < (holderOf me s.time till f).till := ht
  have hk' : (holderOf me s.time till f).kind = me.kind := rfl
  obtain ⟨ho, hn, hm⟩ := verdict_admit_reserves_sim p n s hs q me w t f h hk hp
  have hns : simHeld s.time hs = false := by simp [simPending] at hp; exact hp.2
  have hc := charged_append_le p s.time hs (holderOf me s.time till f)
  have hfoot : (holderOf me s.time till f).foot = f := rfl
  have hneed : ∀ l, need p s l .sim = p.simMB := fun _ => rfl
  rw [← hneed (hs ++ [holderOf me s.time till f]), ← he]
  apply verdict_head_admitted
  · exact h1
  · simp [he]
  · rw [prune_append_live _ _ _ hx, List.length_append]; simp; omega
  · simp [he, simHeld_append _ _ _ hx, hk', hns, hk]
  · simp [he, others_append _ _ _ hx, hk', hk, ho]
  · have hc := admit_calm p n s hs q me w t f h
    exact .inl (memLow_false p s.mem hc.1 hc.2.1 hc.2.2.1 (show p.floorMB ≤ s.avail by omega))
  · rw [he, hneed]; omega
  · simp [yieldsToSim, he]

def legacyEntry (now : Nat) : Entry :=
  { owner := "sim-lock", token := "sim-lock", kind := .sim, since := 0, till := now + 1 }

def withLegacy (now : Nat) (legacy : Bool) (hs : List Entry) : List Entry :=
  if legacy then hs ++ [legacyEntry now] else hs

theorem simHeld_withLegacy (now : Nat) (hs : List Entry) : simHeld now (withLegacy now true hs) = true := by
  simp only [withLegacy, ite_true]
  rw [simHeld_append now hs (legacyEntry now) (by simp [legacyEntry])]
  simp [legacyEntry]

theorem others_withLegacy (now : Nat) (l : Bool) (hs : List Entry) : others now (withLegacy now l hs) = others now hs := by
  cases l
  · rfl
  · simp only [withLegacy, ite_true]
    rw [others_append now hs (legacyEntry now) (by simp [legacyEntry])]
    simp [legacyEntry]

theorem verdict_legacy_blocks_sim (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (hk : me.kind = .sim) : verdict p n s (withLegacy s.time true hs) q me w ≠ .admit t f := by
  intro h
  have := verdict_admit_sim_exclusive p n s _ q me w t f h hk
  rw [simHeld_withLegacy] at this; cases this

theorem verdict_legacy_one_other (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (w t f : Nat)
    (hk : me.kind ≠ .sim) (h : verdict p n s (withLegacy s.time true hs) q me w = .admit t f) : others s.time hs = 0 := by
  rw [← others_withLegacy s.time true hs]
  exact verdict_admit_beside_sim p n s _ q me w t f h hk (simHeld_withLegacy s.time hs)

def simBoot (now : Nat) (owner token : String) (hs : List Entry) : Bool :=
  hs.any (fun h => h.kind == .sim && same owner token h && live now h)

inductive SimAct where
  | none | keep | shutdown
deriving DecidableEq, Repr

def SimAct.name : SimAct → String
  | .none => "none" | .keep => "keep" | .shutdown => "shutdown"

def simIdleNext (now : Nat) (held booted : Bool) (prev : Option Nat) : Option Nat :=
  if booted && !held then some (prev.getD now) else none

def simAction (p : Params) (now : Nat) (hs : List Entry) (booted legacyHeld : Bool) (idleSince : Option Nat) : SimAct :=
  if !booted then .none
  else if legacyHeld || simHeld now hs then .keep
  else match idleSince with
    | none => .keep
    | some i => if i + p.simIdleS ≤ now then .shutdown else .keep

def simDue (p : Params) (now last : Nat) : Bool := decide (last + p.simPollS ≤ now)

#guard simBoot 50 "a" "t1" [holdA]
#guard !simBoot 50 "b" "t1" [holdA]
#guard !simBoot 100 "a" "t1" [holdA]
#guard simAction {} 50 [holdA] true false (some 0) == .keep
#guard simAction {} 700 [holdA] true false (some 0) == .shutdown
#guard simAction {} 700 [holdA] true true (some 0) == .keep
#guard simAction {} 500 [] true false (some 0) == .keep
#guard simAction {} 700 [] false false (some 0) == .none
#guard simAction {} 9000 [] true false none == .keep
#guard simIdleNext 700 false true none == some 700
#guard simIdleNext 900 false true (some 700) == some 700
#guard simIdleNext 900 true true (some 700) == none
#guard simIdleNext 900 false false (some 700) == none
#guard simDue {} 130 100 && !simDue {} 129 100

theorem simBoot_iff (now : Nat) (o t : String) (hs : List Entry) :
    simBoot now o t hs = true ↔ ∃ h ∈ hs, h.kind = .sim ∧ same o t h = true ∧ now < h.till := by
  simp [simBoot, live, and_assoc]

theorem sim_keep_under_holder (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Option Nat)
    (h : simHeld now hs = true) : simAction p now hs true l i = .keep := by
  simp [simAction, h]

theorem sim_keep_under_legacy (p : Params) (now : Nat) (hs : List Entry) (i : Option Nat) :
    simAction p now hs true true i = .keep := by
  simp [simAction]

theorem sim_shutdown_idle (p : Params) (now : Nat) (hs : List Entry) (i : Nat) (h : simHeld now hs = false)
    (hi : i + p.simIdleS ≤ now) : simAction p now hs true false (some i) = .shutdown := by
  simp [simAction, h, hi]

theorem sim_keep_within_idle (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Nat) (hi : now < i + p.simIdleS) :
    simAction p now hs true l (some i) = .keep := by
  have : ¬ i + p.simIdleS ≤ now := by omega
  cases l <;> cases simHeld now hs <;> simp [simAction, this]

theorem sim_keep_no_clock (p : Params) (now : Nat) (hs : List Entry) (l : Bool) :
    simAction p now hs true l none = .keep := by
  cases l <;> cases simHeld now hs <;> simp [simAction]

theorem sim_shutdown_only_unheld (p : Params) (now : Nat) (hs : List Entry) (b l : Bool) (i : Option Nat)
    (h : simAction p now hs b l i = .shutdown) :
    b = true ∧ l = false ∧ simHeld now hs = false ∧ ∃ t, i = some t ∧ t + p.simIdleS ≤ now := by
  unfold simAction at h
  cases b <;> cases l <;> cases hh : simHeld now hs <;> simp [hh] at h
  cases i with
  | none => simp at h
  | some t =>
    simp only at h
    split at h
    · exact ⟨rfl, rfl, rfl, t, rfl, by assumption⟩
    · cases h

theorem sim_none_unbooted (p : Params) (now : Nat) (hs : List Entry) (l : Bool) (i : Option Nat) :
    simAction p now hs false l i = .none := by
  simp [simAction]

theorem simIdleNext_cleared (now : Nat) (b : Bool) (prev : Option Nat) : simIdleNext now true b prev = none := by
  simp [simIdleNext]

theorem simIdleNext_kept (now i : Nat) : simIdleNext now false true (some i) = some i := by
  simp [simIdleNext]

theorem sim_first_sighting_keeps (p : Params) (now : Nat) (hs : List Entry) (h : 0 < p.simIdleS) :
    simAction p now hs true false (simIdleNext now false true none) = .keep := by
  simp only [simIdleNext, Bool.not_false, Bool.and_self, ite_true, Option.getD_none]
  exact sim_keep_within_idle p now hs false now (by omega)

inductive BuildWhy where
  | simWaits
  | agentsUnknown
  | agents (live max : Nat)
  | memory (availMB needMB : Nat)
deriving DecidableEq, Repr

inductive BuildVerdict where
  | admit
  | wait (why : BuildWhy)
deriving DecidableEq, Repr

def simQueued (now : Nat) (q : List Entry) : Bool := (prune now q).any (fun e => e.kind == .sim)

def agentsSeen (p : Params) (now : Nat) : Option (Nat × Nat) → Option Nat
  | none => none
  | some (t0, n) => if now ≤ t0 + p.agentsAgeS then some n else none

def admitBuild (p : Params) (simWaits : Bool) (availMB : Nat) (agents : Option Nat) : BuildVerdict :=
  if simWaits then .wait .simWaits
  else match agents with
    | none => .wait .agentsUnknown
    | some a =>
      if p.agentsMax ≤ a then .wait (.agents a p.agentsMax)
      else if availMB < p.floorMB + p.buildMB then .wait (.memory availMB (p.floorMB + p.buildMB))
      else .admit

#guard admitBuild {} false 9000 (some 5) == .admit
#guard admitBuild {} true 9000 (some 5) == .wait .simWaits
#guard admitBuild {} false 9000 none == .wait .agentsUnknown
#guard admitBuild {} false 9000 (some 8) == .wait (.agents 8 8)
#guard admitBuild {} false 3123 (some 7) == .wait (.memory 3123 3124)
#guard admitBuild {} false 3124 (some 7) == .admit
#guard agentsSeen {} 1900 (some (1000, 6)) == some 6
#guard agentsSeen {} 1901 (some (1000, 6)) == none
#guard agentsSeen {} 1901 none == none
#guard !simQueued 100 [{ tk "s" "5" .sim 0 with till := 100 }] && simQueued 99 [{ tk "s" "5" .sim 0 with till := 100 }]

theorem admitBuild_sim (p : Params) (m : Nat) (a : Option Nat) : admitBuild p true m a = .wait .simWaits := by
  simp [admitBuild]

theorem admitBuild_unknown (p : Params) (m : Nat) : admitBuild p false m none = .wait .agentsUnknown := by
  simp [admitBuild]

theorem admitBuild_agents (p : Params) (m a : Nat) (h : p.agentsMax ≤ a) :
    admitBuild p false m (some a) = .wait (.agents a p.agentsMax) := by
  simp [admitBuild, h]

theorem admitBuild_memory (p : Params) (m a : Nat) (ha : a < p.agentsMax) (h : m < p.floorMB + p.buildMB) :
    admitBuild p false m (some a) = .wait (.memory m (p.floorMB + p.buildMB)) := by
  have : ¬ p.agentsMax ≤ a := by omega
  simp [admitBuild, this, h]

theorem admitBuild_iff (p : Params) (sw : Bool) (m : Nat) (a : Option Nat) :
    admitBuild p sw m a = .admit ↔ sw = false ∧ ∃ k, a = some k ∧ k < p.agentsMax ∧ p.floorMB + p.buildMB ≤ m := by
  cases sw
  · cases a with
    | none => simp [admitBuild]
    | some k =>
      by_cases h1 : p.agentsMax ≤ k
      · simp [admitBuild, h1]; omega
      · by_cases h2 : m < p.floorMB + p.buildMB
        · simp [admitBuild, h1, h2]
        · simp [admitBuild, h1, h2]; omega
  · simp [admitBuild]

theorem agentsSeen_stale (p : Params) (now t0 n : Nat) (h : t0 + p.agentsAgeS < now) :
    agentsSeen p now (some (t0, n)) = none := by
  have : ¬ now ≤ t0 + p.agentsAgeS := by omega
  simp [agentsSeen, this]

inductive StopAct where
  | term | wait | kill | done
deriving DecidableEq, Repr

def StopAct.name : StopAct → String
  | .term => "term" | .wait => "wait" | .kill => "kill" | .done => "done"

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

structure CacheKey where
  kind : Kind
  argv : List String
  tree : String
  base : String
deriving DecidableEq, Repr

def keyOf (k : Kind) (argv : List String) (tree mainSha : String) (clean : Bool) : Option CacheKey :=
  if clean then some { kind := k, argv, tree, base := if k == .land then mainSha else "" } else none

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
