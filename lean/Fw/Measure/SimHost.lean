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

def passRetryS : Nat := 436

def headS : Nat := 687

def tryS : Nat := 876

def loadAnyCenti : Nat := 101592

def loadGreenCenti : Nat := 101119

def blockedS : Nat := 1399

end Seen

/-- Seconds after the gate bound kept for the kill and the watchdog's exit. -/
def endMarginS : Nat := 60

def gateBoundS (stepMin : Nat) : Nat := stepMin * 60 - endMarginS

def scrollNeedS : Nat := Seen.scrollRetryS

def passNeedS : Nat := Seen.passRetryS

def navWaitMs : Nat := 60000

def ciScale : Nat := 8

def tabNeedS (waitMs : Nat) : Nat := (waitMs + 999) / 1000

def retryFits (elapsedS needS : Nat) (boundS : Option Nat) : Bool :=
  match boundS with
  | none => true
  | some b => decide (elapsedS + needS ≤ b)

def tabFits (elapsedS waitMs : Nat) (boundS : Option Nat) : Bool := retryFits elapsedS (tabNeedS waitMs) boundS

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
  nav : Bool
  tabS : Nat
  baseS : Nat
  scroll : List Try

def runPass (n m inner outer tab b : Nat) : Nat → Nat → List PassTry → Out
  | _, e, [] => ⟨e, false, false⟩
  | k, e, p :: rest =>
    if p.nav = true ∧ retryFits (e + p.reconS) tab (some b) = false then ⟨e + p.reconS, false, false⟩
    else
      let o := run n inner b 0 (e + p.reconS + p.tabS + p.baseS) p.scroll
      if o.ok then ⟨o.stop, true, o.retried⟩
      else if k + 1 < m ∧ retryFits o.stop outer (some b) = true then
        let o2 := runPass n m inner outer tab b (k + 1) o.stop rest
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

theorem runPass_stop_le (n m inner outer tab b : Nat) (ps : List PassTry)
    (hin : ∀ p ∈ ps, ∀ t ∈ p.scroll, t.reconS + t.runS ≤ inner)
    (hout : ∀ p ∈ ps, p.reconS + p.tabS + p.baseS + inner ≤ outer) :
    ∀ k e, (runPass n m inner outer tab b k e ps).stop ≤ max (e + outer) b ∧
      ((runPass n m inner outer tab b k e ps).retried = true → (runPass n m inner outer tab b k e ps).stop ≤ b) := by
  induction ps with
  | nil => intro k e; simp [runPass]; omega
  | cons p rest ih =>
    intro k e
    have hp := hout p (by simp)
    by_cases hg : p.nav = true ∧ retryFits (e + p.reconS) tab (some b) = false
    · have hu : runPass n m inner outer tab b k e (p :: rest) = ⟨e + p.reconS, false, false⟩ := by
        rw [runPass, ite_eq_left_of_eq_true _ _ (eq_true hg)]
      rw [hu]
      exact ⟨by simp; omega, by simp⟩
    have hin' := run_stop_le n inner b p.scroll (hin p (by simp)) 0 (e + p.reconS + p.tabS + p.baseS)
    have hin2 : ∀ p' ∈ rest, ∀ t ∈ p'.scroll, t.reconS + t.runS ≤ inner := fun p' h => hin p' (by simp [h])
    have hout2 : ∀ p' ∈ rest, p'.reconS + p'.tabS + p'.baseS + inner ≤ outer := fun p' h => hout p' (by simp [h])
    have ih' := ih hin2 hout2 (k + 1) (run n inner b 0 (e + p.reconS + p.tabS + p.baseS) p.scroll).stop
    obtain ⟨hs, hr⟩ := hin'
    obtain ⟨hs2, hr2⟩ := ih'
    generalize hO : run n inner b 0 (e + p.reconS + p.tabS + p.baseS) p.scroll = o at hs hr hs2 hr2 ⊢
    generalize hO2 : runPass n m inner outer tab b (k + 1) o.stop rest = o2 at hs2 hr2 ⊢
    have hu : runPass n m inner outer tab b k e (p :: rest) =
        (if o.ok then ⟨o.stop, true, o.retried⟩
         else if k + 1 < m ∧ retryFits o.stop outer (some b) = true then ⟨o2.stop, o2.ok, true⟩
         else ⟨o.stop, false, o.retried⟩) := by
      subst hO2; subst hO; rw [runPass, ite_eq_right_of_eq_false _ _ (eq_false hg)]
    rw [hu]
    by_cases h1 : o.ok = true
    · simp only [h1, ite_true]
      exact ⟨by omega, hr⟩
    · have h1' : o.ok = false := by simpa using h1
      by_cases h2 : k + 1 < m ∧ retryFits o.stop outer (some b) = true
      · have hfit : o.stop + outer ≤ b := by simpa [retryFits] using h2.2
        simp only [h1', h2, Bool.false_eq_true, ite_false, and_self, ite_true]
        exact ⟨by omega, fun _ => by omega⟩
      · simp only [h1', h2, Bool.false_eq_true, ite_false]
        exact ⟨by omega, hr⟩

theorem runPass_tab_refused (n m inner outer tab b k e : Nat) (p : PassTry) (rest : List PassTry)
    (hn : p.nav = true) (hf : retryFits (e + p.reconS) tab (some b) = false) :
    runPass n m inner outer tab b k e (p :: rest) = ⟨e + p.reconS, false, false⟩ := by
  simp [runPass, hn, hf]

theorem tab_started_le {e r t tab b : Nat} (h : retryFits (e + r) tab (some b) = true) (ht : t ≤ tab) : e + r + t ≤ b := by
  simp [retryFits] at h; omega

theorem tab_refused_no_pass_retry {x w b : Nat} (t mt : Nat) (hw : tabNeedS w ≤ passNeedS) (h : tabFits x w (some b) = false) :
    afterFailure t mt x passNeedS (some b) = false := by
  simp only [tabFits, retryFits, decide_eq_false_iff_not, Nat.not_le] at h
  simp only [afterFailure, retryFits, Bool.and_eq_false_iff, decide_eq_false_iff_not, Nat.not_le]
  right; omega

theorem deployed_needs_missed (p : PassTry) : ¬ (p.reconS + p.tabS + p.baseS + scrollNeedS ≤ passNeedS) := by
  unfold scrollNeedS passNeedS Seen.scrollRetryS Seen.passRetryS; omega

theorem deployed_scroll_below_try : scrollNeedS < Seen.tryS := by decide

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

theorem seen_retries_within_needs : Seen.scrollRetryS ≤ scrollNeedS ∧ Seen.passRetryS ≤ passNeedS := by decide

theorem retry_after_warm :
    retryFits (Seen.startS + Seen.warmS) scrollNeedS (some (gateBoundS SimBound.perSessionMin)) = true ∧
    retryFits (Seen.startS + Seen.warmS) passNeedS (some (gateBoundS SimBound.perSessionMin)) = true := by decide

theorem last_admitted :
    gateBoundS SimBound.perSessionMin - scrollNeedS = 1451 ∧ gateBoundS SimBound.perSessionMin - passNeedS = 1604 := by decide

theorem late_retry_refused :
    retryFits Seen.stepS scrollNeedS (some (gateBoundS SimBound.perSessionMin)) = false := by decide

theorem ciScale_stall : SimBound.stallMs = ciScale * 90000 := by decide

theorem ci_tab_need : tabNeedS (navWaitMs * ciScale) = 480 ∧ passNeedS < tabNeedS (navWaitMs * ciScale) := by decide

theorem perSession_vs_step :
    Seen.stepS + endMarginS ≤ SimBound.perSessionMin * 60 ∧ SimBound.perSessionMin * 60 * 4 < Seen.stepS * 5 := by decide

inductive Kind where
  | scroll
  | pass
  | tab
deriving DecidableEq, Repr

structure Decision where
  kind : Kind
  atS : Nat
  tries : Nat
deriving Repr

structure Job where
  job : Nat
  run : Nat
  sessions : Nat
  maxTries : Nat
  decisions : List Decision
deriving Repr

structure Needs where
  scroll : Nat
  pass : Nat
  tab : Nat
deriving DecidableEq, Repr

def Needs.le (c d : Needs) : Prop := c.scroll ≤ d.scroll ∧ c.pass ≤ d.pass ∧ c.tab ≤ d.tab

def Needs.of (c : Needs) : Kind → Nat
  | .scroll => c.scroll
  | .pass => c.pass
  | .tab => c.tab

def tabWaitS : Nat := tabNeedS (navWaitMs * ciScale)

/-- runPass_stop_le's premise at the seen maxima (inner, outer), plus tab cover for tab_started_le. -/
def Premise (c : Needs) : Prop := Seen.tryS ≤ c.scroll ∧ Seen.headS + c.scroll ≤ c.pass ∧ tabWaitS ≤ c.tab

instance (c : Needs) : Decidable (Premise c) := by unfold Premise; infer_instance

def admits (c : Needs) (b maxTries : Nat) (d : Decision) : Bool :=
  match d.kind with
  | .tab => retryFits d.atS c.tab (some b)
  | k => afterFailure d.tries maxTries d.atS (c.of k) (some b)

def boundOf (j : Job) : Nat := gateBoundS (j.sessions * SimBound.perSessionMin)

def refused (c : Needs) (j : Job) : Bool := j.decisions.any fun d => !admits c (boundOf j) j.maxTries d

def refusedCount (c : Needs) (js : List Job) : Nat := js.countP (refused c)

def best : Needs := ⟨Seen.tryS, Seen.headS + Seen.tryS, tabWaitS⟩

def shipped : Needs := ⟨Seen.scrollRetryS, Seen.passRetryS, 0⟩

def pick (best fallback : Needs) (js : List Job) : Needs :=
  if refusedCount best js ≤ refusedCount fallback js then best else fallback

def deployed : Needs := ⟨scrollNeedS, passNeedS, 0⟩

theorem retryFits_mono {e n n' b : Nat} (h : n ≤ n') (hf : retryFits e n' (some b) = true) : retryFits e n (some b) = true :=
  le_retryFits (by have := retryFits_le hf; omega)

theorem admits_mono {c d : Needs} (h : c.le d) (b mt : Nat) (x : Decision) (ha : admits d b mt x = true) :
    admits c b mt x = true := by
  obtain ⟨hs, hp, ht⟩ := h
  unfold admits at ha ⊢
  cases hk : x.kind <;> simp only [hk, Needs.of] at ha ⊢
  · simp only [afterFailure, Bool.and_eq_true] at ha ⊢; exact ⟨ha.1, retryFits_mono hs ha.2⟩
  · simp only [afterFailure, Bool.and_eq_true] at ha ⊢; exact ⟨ha.1, retryFits_mono hp ha.2⟩
  · exact retryFits_mono ht ha

theorem refused_mono {c d : Needs} (h : c.le d) (j : Job) (hr : refused c j = true) : refused d j = true := by
  simp only [refused, List.any_eq_true, Bool.not_eq_true'] at hr ⊢
  obtain ⟨x, hx, hn⟩ := hr
  refine ⟨x, hx, ?_⟩
  cases hd : admits d (boundOf j) j.maxTries x
  · rfl
  · have := admits_mono h _ _ x hd; simp_all

theorem refusedCount_mono {c d : Needs} (h : c.le d) (js : List Job) : refusedCount c js ≤ refusedCount d js :=
  List.countP_mono_left fun j _ hr => refused_mono h j hr

theorem best_premise : Premise best := by decide

theorem premise_best_le {c : Needs} (h : Premise c) : best.le c := by
  obtain ⟨hs, hp, ht⟩ := h
  exact ⟨hs, by show Seen.headS + Seen.tryS ≤ c.pass; omega, ht⟩

theorem best_fewest {c : Needs} (h : Premise c) (js : List Job) : refusedCount best js ≤ refusedCount c js :=
  refusedCount_mono (premise_best_le h) js

theorem untabbed_fewest {c : Needs} (h : Seen.tryS ≤ c.scroll ∧ Seen.headS + c.scroll ≤ c.pass) (js : List Job) :
    refusedCount { best with tab := 0 } js ≤ refusedCount c js :=
  refusedCount_mono ⟨h.1, by show Seen.headS + Seen.tryS ≤ c.pass; omega, Nat.zero_le _⟩ js

theorem pick_best {b f : Needs} {js : List Job} (h : refusedCount b js ≤ refusedCount f js) : pick b f js = b := by
  simp [pick, h]

theorem pick_fallback {b f : Needs} {js : List Job} (h : refusedCount f js < refusedCount b js) : pick b f js = f := by
  simp [pick, Nat.not_le.mpr h]

theorem deployed_premise_unmet : ¬ Premise deployed := by decide

theorem best_stop_le (n m b : Nat) (ps : List PassTry)
    (hin : ∀ p ∈ ps, ∀ t ∈ p.scroll, t.reconS + t.runS ≤ Seen.tryS)
    (hhead : ∀ p ∈ ps, p.reconS + p.tabS + p.baseS ≤ Seen.headS) :
    ∀ k e, (runPass n m best.scroll best.pass best.tab b k e ps).stop ≤ max (e + best.pass) b ∧
      ((runPass n m best.scroll best.pass best.tab b k e ps).retried = true →
        (runPass n m best.scroll best.pass best.tab b k e ps).stop ≤ b) :=
  runPass_stop_le n m best.scroll best.pass best.tab b ps hin
    (fun p hp => by have := hhead p hp; show _ + Seen.tryS ≤ Seen.headS + Seen.tryS; omega)

end Fw.Measure.SimHost
