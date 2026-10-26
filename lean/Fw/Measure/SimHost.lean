import Fw.Measure.SimBound
/-!
Retry budget and host gate of the WebKit Simulator lane.
Mirrored by `determinism.mjs` through `packages/contracts/golden/measure/sim-host.jsonl`.
-/
namespace Fw.Measure.SimHost

namespace Seen

def startS : Nat := 199

def warmS : Nat := 822

def passS : Nat := 1123

def pass2S : Nat := 896

def stepS : Nat := 1734

/-- Longest wait from a failed scroll attempt to the end of its retried step, seconds. -/
def scrollRetryS : Nat := 589

/-- Longest wait from a failed pass attempt to the end of the repeated pass, seconds. -/
def passRetryS : Nat := 436

def loadAnyCenti : Nat := 101592

def loadGreenCenti : Nat := 101119

def blockedS : Nat := 1399

end Seen

/-- Seconds after the gate bound kept for the kill and the watchdog's exit. -/
def endMarginS : Nat := 60

def gateBoundS (stepMin : Nat) : Nat := stepMin * 60 - endMarginS

/-- Whether a retry started `elapsedS` into the step, taking at most `needS`, ends within `boundS` (none: always). -/
def retryFits (elapsedS needS : Nat) (boundS : Option Nat) : Bool :=
  match boundS with
  | none => true
  | some b => decide (elapsedS + needS ≤ b)

/-- Whether to retry after an attempt threw. -/
def afterFailure (tries maxTries elapsedS needS : Nat) (boundS : Option Nat) : Bool :=
  decide (tries < maxTries) && retryFits elapsedS needS boundS

/-- The 1-minute load average, in hundredths, up to which a host is measured on. -/
def loadCeilCenti : Nat := 132000

def hostOk (loadCenti : Nat) : Bool := decide (loadCenti ≤ loadCeilCenti)

inductive PassVerdict where
  | count
  | redo
  | refuse
deriving DecidableEq, Repr

def PassVerdict.name : PassVerdict → String
  | .count => "count"
  | .redo => "redo"
  | .refuse => "refuse"

/-- Verdict on a finished pass: count, redo or refuse. -/
def afterPass (startCenti endCenti tries maxTries elapsedS needS : Nat) (boundS : Option Nat) : PassVerdict :=
  if hostOk startCenti && hostOk endCenti then .count
  else if afterFailure tries maxTries elapsedS needS boundS then .redo else .refuse

def counted (v : PassVerdict) : Bool := decide (v = .count)

structure Try where
  reconS : Nat
  runS : Nat
  ok : Bool

structure Out where
  stop : Nat
  ok : Bool
  retried : Bool

def run (n need b : Nat) : Nat → Nat → List Try → Out
  | _, e, [] => ⟨e, false, false⟩
  | k, e, t :: rest =>
    if t.ok then ⟨e + t.reconS + t.runS, true, false⟩
    else if k + 1 < n ∧ retryFits (e + t.reconS + t.runS) need (some b) = true then
      let o := run n need b (k + 1) (e + t.reconS + t.runS) rest
      ⟨o.stop, o.ok, true⟩
    else ⟨e + t.reconS + t.runS, false, false⟩

structure PassTry where
  reconS : Nat
  baseS : Nat
  scroll : List Try

def runPass (n m inner outer b : Nat) : Nat → Nat → List PassTry → Out
  | _, e, [] => ⟨e, false, false⟩
  | k, e, p :: rest =>
    let o := run n inner b 0 (e + p.reconS + p.baseS) p.scroll
    if o.ok then ⟨o.stop, true, o.retried⟩
    else if k + 1 < m ∧ retryFits o.stop outer (some b) = true then
      let o2 := runPass n m inner outer b (k + 1) o.stop rest
      ⟨o2.stop, o2.ok, true⟩
    else ⟨o.stop, false, o.retried⟩

theorem run_stop_le (n need b : Nat) (ts : List Try) (hts : ∀ t ∈ ts, t.reconS + t.runS ≤ need) :
    ∀ k e, (run n need b k e ts).stop ≤ max (e + need) b ∧ ((run n need b k e ts).retried = true → (run n need b k e ts).stop ≤ b) := by
  induction ts with
  | nil => intro k e; simp [run]; omega
  | cons t rest ih =>
    intro k e
    have ht := hts t (by simp)
    have hrest : ∀ t' ∈ rest, t'.reconS + t'.runS ≤ need := fun t' h => hts t' (by simp [h])
    have ih' := ih hrest (k + 1) (e + t.reconS + t.runS)
    by_cases h1 : t.ok = true
    · simp [run, h1]; omega
    · by_cases h2 : k + 1 < n ∧ retryFits (e + t.reconS + t.runS) need (some b) = true
      · have hfit : e + t.reconS + t.runS + need ≤ b := by simpa [retryFits] using h2.2
        simp [run, h1, h2]; omega
      · simp [run, h1, h2]; omega

theorem runPass_stop_le (n m inner outer b : Nat) (ps : List PassTry)
    (hin : ∀ p ∈ ps, ∀ t ∈ p.scroll, t.reconS + t.runS ≤ inner)
    (hout : ∀ p ∈ ps, p.reconS + p.baseS + inner ≤ outer) :
    ∀ k e, (runPass n m inner outer b k e ps).stop ≤ max (e + outer) b ∧
      ((runPass n m inner outer b k e ps).retried = true → (runPass n m inner outer b k e ps).stop ≤ b) := by
  induction ps with
  | nil => intro k e; simp [runPass]; omega
  | cons p rest ih =>
    intro k e
    have hp := hout p (by simp)
    have hin' := run_stop_le n inner b p.scroll (hin p (by simp)) 0 (e + p.reconS + p.baseS)
    have hin2 : ∀ p' ∈ rest, ∀ t ∈ p'.scroll, t.reconS + t.runS ≤ inner := fun p' h => hin p' (by simp [h])
    have hout2 : ∀ p' ∈ rest, p'.reconS + p'.baseS + inner ≤ outer := fun p' h => hout p' (by simp [h])
    have ih' := ih hin2 hout2 (k + 1) (run n inner b 0 (e + p.reconS + p.baseS) p.scroll).stop
    obtain ⟨hs, hr⟩ := hin'
    obtain ⟨hs2, hr2⟩ := ih'
    generalize hO : run n inner b 0 (e + p.reconS + p.baseS) p.scroll = o at hs hr hs2 hr2 ⊢
    generalize hO2 : runPass n m inner outer b (k + 1) o.stop rest = o2 at hs2 hr2 ⊢
    have hu : runPass n m inner outer b k e (p :: rest) =
        (if o.ok then ⟨o.stop, true, o.retried⟩
         else if k + 1 < m ∧ retryFits o.stop outer (some b) = true then ⟨o2.stop, o2.ok, true⟩
         else ⟨o.stop, false, o.retried⟩) := by
      subst hO2; subst hO; rfl
    rw [hu]
    by_cases h1 : o.ok = true
    · have e1 : (if o.ok then (⟨o.stop, true, o.retried⟩ : Out) else ⟨o.stop, false, o.retried⟩).stop = o.stop := by simp [h1]
      simp only [h1, ite_true]
      exact ⟨by omega, hr⟩
    · have h1' : o.ok = false := by simpa using h1
      by_cases h2 : k + 1 < m ∧ retryFits o.stop outer (some b) = true
      · have hfit : o.stop + outer ≤ b := by simpa [retryFits] using h2.2
        simp only [h1', h2, Bool.false_eq_true, ite_false, and_self, ite_true]
        exact ⟨by omega, fun _ => by omega⟩
      · simp only [h1', h2, Bool.false_eq_true, ite_false]
        exact ⟨by omega, hr⟩

theorem retryFits_none (e n : Nat) : retryFits e n none = true := rfl

theorem retryFits_le {e n b : Nat} (h : retryFits e n (some b) = true) : e + n ≤ b := by
  simpa [retryFits] using h

theorem le_retryFits {e n b : Nat} (h : e + n ≤ b) : retryFits e n (some b) = true := by
  simpa [retryFits] using h

theorem afterFailure_le {t mt e n b : Nat} (h : afterFailure t mt e n (some b) = true) : t < mt ∧ e + n ≤ b := by
  simp only [afterFailure, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1, retryFits_le h.2⟩

theorem gateBoundS_margin (m : Nat) (h : 1 ≤ m) : gateBoundS m + endMarginS = m * 60 := by
  unfold gateBoundS endMarginS; omega

theorem hostOk_iff (c : Nat) : hostOk c = true ↔ c ≤ loadCeilCenti := by simp [hostOk]

theorem refuse_not_counted (s e t mt el n : Nat) (b : Option Nat) (h : afterPass s e t mt el n b = .refuse) :
    counted (afterPass s e t mt el n b) = false := by simp [h, counted]

theorem counted_hostOk (s e t mt el n : Nat) (b : Option Nat) (h : counted (afterPass s e t mt el n b) = true) :
    hostOk s = true ∧ hostOk e = true := by
  unfold afterPass at h
  by_cases hc : (hostOk s && hostOk e) = true
  · simpa using hc
  · have hc' : (hostOk s && hostOk e) = false := by simpa using hc
    simp only [hc', Bool.false_eq_true, ite_false] at h
    by_cases hf : afterFailure t mt el n b = true <;> simp [hf, counted] at h

theorem fit_counted (s e t mt el n : Nat) (b : Option Nat) (hs : hostOk s = true) (he : hostOk e = true) :
    afterPass s e t mt el n b = .count := by simp [afterPass, hs, he]

theorem redo_fits {s e t mt el n b : Nat} (h : afterPass s e t mt el n (some b) = .redo) : t < mt ∧ el + n ≤ b := by
  unfold afterPass at h
  by_cases hc : (hostOk s && hostOk e) = true
  · simp [hc] at h
  · have hc' : (hostOk s && hostOk e) = false := by simpa using hc
    simp only [hc', Bool.false_eq_true, ite_false] at h
    by_cases hf : afterFailure t mt el n (some b) = true
    · exact afterFailure_le hf
    · have hf' : afterFailure t mt el n (some b) = false := by simpa using hf
      simp [hf'] at h

theorem seen_hostOk : hostOk Seen.loadAnyCenti = true ∧ hostOk Seen.loadGreenCenti = true := by decide

theorem ceil_above_seen : Seen.loadAnyCenti < loadCeilCenti := by decide

theorem stepS_lt_gate : Seen.stepS < gateBoundS SimBound.perSessionMin := by decide

theorem retry_after_warm_fits :
    retryFits (Seen.startS + Seen.warmS) Seen.scrollRetryS (some (gateBoundS SimBound.perSessionMin)) = true ∧
    retryFits (Seen.startS + Seen.warmS) Seen.passRetryS (some (gateBoundS SimBound.perSessionMin)) = true := by decide

theorem late_retry_refused :
    retryFits Seen.stepS Seen.scrollRetryS (some (gateBoundS SimBound.perSessionMin)) = false := by decide

theorem perSession_vs_step :
    Seen.stepS + endMarginS ≤ SimBound.perSessionMin * 60 ∧ SimBound.perSessionMin * 60 * 4 < Seen.stepS * 5 := by decide

end Fw.Measure.SimHost
