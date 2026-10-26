import Fw.Measure.SimBound
/-!
# Retry budget and host gate of the WebKit Simulator lane (task `wk-sim-hang`)
`determinism.mjs` follows `retryFits`, `afterFailure` and `afterPass` through `packages/contracts/golden/measure/sim-host.jsonl`.
-/
namespace Fw.Measure.SimHost

/-! ## Measured maxima: seconds, CI run and job ids (green jobs unless stated) -/
namespace Seen

/-- Longest start of the measuring process, "serving" line to "proxy up" (run 40236531932, job 121300136535). -/
def startS : Nat := 199

/-- Longest warm-up, "proxy up" to the discarded pass (run 40171953359, job 121153585933). -/
def warmS : Nat := 822

/-- Longest first pass, "pass 1/2" to "written" (run 40271367353, job 121416196352). -/
def passS : Nat := 1123

/-- Longest second pass (run 40271370582, job 121405613291). -/
def pass2S : Nat := 896

/-- Longest whole measuring step, "serving" to "pass 2/2 written" (run 40271367353, job 121416196352). -/
def stepS : Nat := 1734

/-- Longest wait from a failed scroll attempt to the end of its retried scroll step, 13 retries (run 40171941566, job 121153604305). -/
def scrollRetryS : Nat := 589

/-- Longest wait from a failed pass attempt to the end of the repeated pass, 3 retries (run 40271367353, job 121416196352). -/
def passRetryS : Nat := 436

/-- Highest 1-minute load average ever sampled on a sim VM, hundredths: a failed job (run 40282962088, job sim-r3, telemetry probes). -/
def loadAnyCenti : Nat := 101592

/-- Highest load average sampled in a green job, hundredths (run 40282951274, job sim-r1, telemetry probes). -/
def loadGreenCenti : Nat := 101119

/-- Longest event-loop stand-still caused by the `top` sample of the old load stamp (run 40282962088, job sim-r1). -/
def blockedS : Nat := 1399

end Seen

/-! ## Retry gate -/

/-- Seconds after the gate bound that the step keeps for the kill (20 s TERM to KILL) and the watchdog's exit (`SimBound.exitMs`). -/
def endMarginS : Nat := 60

/-- The latest second, from the start of the measuring step, at which a retried piece of work may end: the step bound minus the margin. -/
def gateBoundS (stepMin : Nat) : Nat := stepMin * 60 - endMarginS

/-- A retry started `elapsedS` into the step, whose work takes at most `needS`, fits when it ends within `boundS` (no bound: it always fits). -/
def retryFits (elapsedS needS : Nat) (boundS : Option Nat) : Bool :=
  match boundS with
  | none => true
  | some b => decide (elapsedS + needS ≤ b)

/-- What the harness does after an attempt threw: `tries` attempts are done of `maxTries`. -/
def afterFailure (tries maxTries elapsedS needS : Nat) (boundS : Option Nat) : Bool :=
  decide (tries < maxTries) && retryFits elapsedS needS boundS

/-- The 1-minute load average, in hundredths, up to which a host is measured on: 1.3 times `Seen.loadAnyCenti`. -/
def loadCeilCenti : Nat := 132000

/-- A host is fit for a counted pass when its load average is at most `loadCeilCenti`. -/
def hostOk (loadCenti : Nat) : Bool := decide (loadCenti ≤ loadCeilCenti)

/-- What the harness does with a finished pass. -/
inductive PassVerdict where
  | count
  | redo
  | refuse
deriving DecidableEq, Repr

/-- The verdict's wire name. -/
def PassVerdict.name : PassVerdict → String
  | .count => "count"
  | .redo => "redo"
  | .refuse => "refuse"

/-- A pass counts only when the host was fit at its start and at its end; else it is repeated if a retry fits, else refused. -/
def afterPass (startCenti endCenti tries maxTries elapsedS needS : Nat) (boundS : Option Nat) : PassVerdict :=
  if hostOk startCenti && hostOk endCenti then .count
  else if afterFailure tries maxTries elapsedS needS boundS then .redo else .refuse

/-- Whether the pass enters the classification. -/
def counted (v : PassVerdict) : Bool := decide (v = .count)

/-! ## Two nested retry levels under one deadline -/

/-- One try of a level: the reconnect before it (0 for the first), the time it ran (to the end of the pass for a good try), whether it succeeded. -/
structure Try where
  reconS : Nat
  runS : Nat
  ok : Bool

/-- A level's result: the second it stopped, whether a try succeeded, whether a retry was decided. -/
structure Out where
  stop : Nat
  ok : Bool
  retried : Bool

/-- The scroll attempts of one pass: `k` tries are done, up to `n`, a retry needs `need` seconds to the bound `b`. -/
def run (n need b : Nat) : Nat → Nat → List Try → Out
  | _, e, [] => ⟨e, false, false⟩
  | k, e, t :: rest =>
    if t.ok then ⟨e + t.reconS + t.runS, true, false⟩
    else if k + 1 < n ∧ retryFits (e + t.reconS + t.runS) need (some b) = true then
      let o := run n need b (k + 1) (e + t.reconS + t.runS) rest
      ⟨o.stop, o.ok, true⟩
    else ⟨e + t.reconS + t.runS, false, false⟩

/-- One pass attempt: the reconnect before it, the load and census before the scroll step, the scroll attempts. -/
structure PassTry where
  reconS : Nat
  baseS : Nat
  scroll : List Try

/-- The pass attempts: scroll attempts (`n`, `inner`) inside pass attempts (`m`, `outer`), one bound `b` for both. -/
def runPass (n m inner outer b : Nat) : Nat → Nat → List PassTry → Out
  | _, e, [] => ⟨e, false, false⟩
  | k, e, p :: rest =>
    let o := run n inner b 0 (e + p.reconS + p.baseS) p.scroll
    if o.ok then ⟨o.stop, true, o.retried⟩
    else if k + 1 < m ∧ retryFits o.stop outer (some b) = true then
      let o2 := runPass n m inner outer b (k + 1) o.stop rest
      ⟨o2.stop, o2.ok, true⟩
    else ⟨o.stop, false, o.retried⟩

/-- **A scroll retry decided to fit ends within the bound; with no retry the level ends within `need` of its start.** Whatever the failures, when each try and its reconnect take at most `need`. -/
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

/-- **Both levels under one bound: a retry decided at either level ends within the bound; with no retry the pass ends within `outer` of its start.** `outer` covers a pass attempt's reconnect, its load and one clean scroll attempt. -/
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

/-! ## Theorems -/

theorem retryFits_none (e n : Nat) : retryFits e n none = true := rfl

theorem retryFits_le {e n b : Nat} (h : retryFits e n (some b) = true) : e + n ≤ b := by
  simpa [retryFits] using h

theorem le_retryFits {e n b : Nat} (h : e + n ≤ b) : retryFits e n (some b) = true := by
  simpa [retryFits] using h

/-- **A retry decided on is within the attempts and ends within the bound.** -/
theorem afterFailure_le {t mt e n b : Nat} (h : afterFailure t mt e n (some b) = true) : t < mt ∧ e + n ≤ b := by
  simp only [afterFailure, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1, retryFits_le h.2⟩

theorem gateBoundS_margin (m : Nat) (h : 1 ≤ m) : gateBoundS m + endMarginS = m * 60 := by
  unfold gateBoundS endMarginS; omega

theorem hostOk_iff (c : Nat) : hostOk c = true ↔ c ≤ loadCeilCenti := by simp [hostOk]

/-- **A refused pass is never counted.** -/
theorem refuse_not_counted (s e t mt el n : Nat) (b : Option Nat) (h : afterPass s e t mt el n b = .refuse) :
    counted (afterPass s e t mt el n b) = false := by simp [h, counted]

/-- **A counted pass had a fit host at its start and at its end.** -/
theorem counted_hostOk (s e t mt el n : Nat) (b : Option Nat) (h : counted (afterPass s e t mt el n b) = true) :
    hostOk s = true ∧ hostOk e = true := by
  unfold afterPass at h
  by_cases hc : (hostOk s && hostOk e) = true
  · simpa using hc
  · have hc' : (hostOk s && hostOk e) = false := by simpa using hc
    simp only [hc', Bool.false_eq_true, ite_false] at h
    by_cases hf : afterFailure t mt el n b = true <;> simp [hf, counted] at h

/-- **A fit host is counted.** -/
theorem fit_counted (s e t mt el n : Nat) (b : Option Nat) (hs : hostOk s = true) (he : hostOk e = true) :
    afterPass s e t mt el n b = .count := by simp [afterPass, hs, he]

/-- **A repeat decided on after an unfit host fits the bound.** -/
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

/-- The ceiling lies above every load sampled so far, the failed jobs' too: the gate guards beyond the envelope seen, it does not separate the failed jobs. -/
theorem seen_hostOk : hostOk Seen.loadAnyCenti = true ∧ hostOk Seen.loadGreenCenti = true := by decide

theorem ceil_above_seen : Seen.loadAnyCenti < loadCeilCenti := by decide

/-! ## The per-session bound against the maxima seen -/

/-- **The longest measuring step seen ends before the gate bound of one session.** A first attempt is never refused by the bound. -/
theorem stepS_lt_gate : Seen.stepS < gateBoundS SimBound.perSessionMin := by decide

/-- A scroll or pass retry decided right after the longest start and warm-up seen fits the bound. -/
theorem retry_after_warm_fits :
    retryFits (Seen.startS + Seen.warmS) Seen.scrollRetryS (some (gateBoundS SimBound.perSessionMin)) = true ∧
    retryFits (Seen.startS + Seen.warmS) Seen.passRetryS (some (gateBoundS SimBound.perSessionMin)) = true := by decide

/-- A retry decided after the longest step seen has ended would overrun the bound, so the gate refuses it. -/
theorem late_retry_refused :
    retryFits Seen.stepS Seen.scrollRetryS (some (gateBoundS SimBound.perSessionMin)) = false := by decide

/-- **`perSessionMin` holds the longest step seen with the gate margin, and is within a quarter of it.** The maxima do not call for raising it. -/
theorem perSession_vs_step :
    Seen.stepS + endMarginS ≤ SimBound.perSessionMin * 60 ∧ SimBound.perSessionMin * 60 * 4 < Seen.stepS * 5 := by decide

end Fw.Measure.SimHost
