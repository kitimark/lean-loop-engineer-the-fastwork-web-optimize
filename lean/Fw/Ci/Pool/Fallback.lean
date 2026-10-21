import Lean.Data.Json
import Fw.Ci.Provider
import Fw.Ci.Pool.Caps
import Fw.Ci.Pool.Key
/-!
# macOS fallback route (task `pool-fallback`): GitHub first, then allowlisted fallbacks, else a bounded durable wait
-/
namespace Fw.Ci.Pool.Fallback

open Lean (Json)
open Fw.Ci.Pool.Key (Key Outcome)

/-- The provider a dispatched job runs on (local to the route; `Fw.Ci.Provider.Provider` keeps two constructors). -/
inductive Via where
  | github
  | circleci
  | bitrise
deriving DecidableEq, Repr

/-- The machine family of a target. -/
inductive Os where
  | macos
  | linux
deriving DecidableEq, Repr

/-- The browser engine a lane measures with. -/
inductive Engine where
  | iosSimSafari
  | wktrIosSim
  | pwWebkitMac
  | pwWebkitWpe
deriving DecidableEq, Repr

/-- Apple WebKit (Simulator or macOS); `false` only for WPE WebKit on Linux. -/
def Engine.apple : Engine → Bool
  | .pwWebkitWpe => false
  | _ => true

/-- Every constant the route reads; theorems take it as a parameter, so a constant edit re-proves nothing. -/
structure Cfg where
  ghMacCap : Nat
  ghTotalCap : Nat
  ghWaitMaxS : Nat
  waitMaxS : Nat
  circleCls : String
  circleMacConc : Nat
  circleShortMaxMin : Nat
  circleSetupMin : Nat
  circleMacAllow : List String
  circleCaps : List (String × Nat)
  bitriseOn : Bool
  bitriseCls : String
  bitriseConc : Nat
  bitriseMaxMin : Nat
  bitriseAllow : List String
  wpeCls : String
  wpeTolerant : List String
  ghOnly : List String
  crossPoolOk : List String
deriving DecidableEq, Repr

/-- Phase 1: every fallback allowlist empty and Bitrise off, so the route yields GitHub, a wait or a terminal row. -/
def phase1 : Cfg where
  ghMacCap := 5
  ghTotalCap := 20
  ghWaitMaxS := 1200
  waitMaxS := 7200
  circleCls := "m4pro.medium"
  circleMacConc := 1
  circleShortMaxMin := 10
  circleSetupMin := 3
  circleMacAllow := []
  circleCaps := []
  bitriseOn := false
  bitriseCls := "bitrise.mac"
  bitriseConc := 1
  bitriseMaxMin := 45
  bitriseAllow := []
  wpeCls := "ubuntu-24.04-arm"
  wpeTolerant := []
  ghOnly := ["sim-speed", "gate-gaps"]
  crossPoolOk := []

/-- The GitHub Enterprise seat: only the two GitHub caps change. -/
def enterprise : Cfg := { phase1 with ghMacCap := 50, ghTotalCap := 500 }

/-- Each constant of `phase1` with its status and source. -/
def sources : List (String × String × String) := [
  ("ghMacCap", "CONFIRMED", "docs.github.com/en/actions/reference/limits (Free/Pro/Team: 5 concurrent macOS jobs); the measured 6 of 2026-10-20 18:21:30Z counted job 118800606953, which ran no step (queued, then cancelled): by step times the peak is 5"),
  ("ghTotalCap", "CONFIRMED", "docs.github.com/en/actions/reference/limits (Free: 20 concurrent jobs)"),
  ("ghWaitMaxS", "INFERRED", "design choice, research/notes/2026/10-20-macos-pool-v2.md section 5; swept by task pool-replay"),
  ("waitMaxS", "INFERRED", "design choice above the longest measured cap wait, 72.3 min (research/notes/2026/10-20-macos-pool.md, 5-job cap section)"),
  ("circleCls", "CONFIRMED", "Fw.Ci.Provider.rates: m4pro.medium, 200 credits/min, base pool"),
  ("circleMacConc", "CONFIRMED", "research/notes/2026/10-20-circleci-free-tier.md: Free plan macOS concurrency 1"),
  ("circleShortMaxMin", "INFERRED", "design choice, research/notes/2026/10-20-macos-pool-v2.md section 5"),
  ("circleSetupMin", "INFERRED", "design choice, research/notes/2026/10-20-macos-pool-v2.md section 5"),
  ("circleMacAllow", "CONFIRMED", "empty: no CircleCI macOS spend in experiments (user 2026-10-21)"),
  ("circleCaps", "CONFIRMED", "empty: no lane has a measured m4pro cap; the failed m4pro pipeline of 2026-10-19 cost 2756 credits (research/notes/2026/10-21-macos-minutes.md section 5)"),
  ("bitriseOn", "CONFIRMED", "off until the user's public-app test (research/notes/2026/10-20-bitrise-macos.md)"),
  ("bitriseConc", "UNKNOWN", "2018 public-app terms, research/notes/2026/10-20-bitrise-macos.md"),
  ("bitriseMaxMin", "UNKNOWN", "2018 public-app terms, research/notes/2026/10-20-bitrise-macos.md"),
  ("bitriseAllow", "CONFIRMED", "empty while bitriseOn is false"),
  ("wpeTolerant", "CONFIRMED", "empty: no lane owner has declared WPE tolerance"),
  ("ghOnly", "CONFIRMED", "sim-speed measures GitHub runners; gate-gaps runs three engines in one job until it is split"),
  ("crossPoolOk", "CONFIRMED", "empty: a lane enters after a pair verdict (Fw.Ci.Provider.compare)")]

/-- A request key with the `run_attempt` of the plan job that routes it. -/
abbrev Id := Key × Nat

/-- One macOS request as the router holds it. -/
structure Req where
  key : Key
  attempt : Nat
  engine : Engine
  image : String
  capMin : Nat
  ageS : Nat
  current : Bool
deriving DecidableEq, Repr

/-- The dispatch identity of a request. -/
def Req.id (r : Req) : Id := (r.key, r.attempt)

/-- The lane of a request. -/
def Req.lane (r : Req) : String := r.key.lane

/-- Slots and credits as the route reads them; `ghRemainingS = none`: remaining times unknown. -/
structure State where
  ghMacBusy : Nat
  ghTotalBusy : Nat
  ghQueuedAhead : Nat
  ghDegraded : Bool
  ghRemainingS : Option (List Nat)
  circleBusy : Nat
  bitriseBusy : Nat
  circleCreditsLeft : Nat
deriving DecidableEq, Repr

/-- A GitHub macOS slot is free now. -/
def macFree (c : Cfg) (s : State) : Bool := s.ghMacBusy < c.ghMacCap && s.ghTotalBusy < c.ghTotalCap

/-- Seconds until a GitHub macOS slot frees for one more job; `none` when unknown. -/
def expWaitS (c : Cfg) (s : State) : Option Nat :=
  if macFree c s then some 0
  else if c.ghTotalCap ≤ s.ghTotalBusy then none
  else match s.ghRemainingS with
    | none => none
    | some l => (l.mergeSort (· ≤ ·))[s.ghQueuedAhead]?

/-- The expected wait is known and under the bound. -/
def waitOk (c : Cfg) (s : State) : Bool :=
  match expWaitS c s with
  | some w => decide (w < c.ghWaitMaxS)
  | none => false

/-- GitHub macOS takes the request. -/
def ghOk (c : Cfg) (s : State) : Bool := !s.ghDegraded && (macFree c s || waitOk c s)

/-- The measured m4pro cap of a lane, in minutes. -/
def circleCap (c : Cfg) (lane : String) : Option Nat := (c.circleCaps.find? (·.1 == lane)).map (·.2)

/-- Credits a CircleCI job is charged at an enforced timeout of `m` minutes. -/
def charge (c : Cfg) (m : Nat) : Nat := (Fw.Ci.Provider.credits c.circleCls (m * 60000)).getD 0

/-- The input `Fw.Ci.Provider.route` reads for a CircleCI macOS job of `m` minutes, with GitHub counted as degraded. -/
def circleInput (c : Cfg) (r : Req) (s : State) (m : Nat) : Fw.Ci.Provider.RouteInput :=
  ⟨r.lane, .macos, c.circleCls, c.circleMacAllow, true, m * 60000, s.circleCreditsLeft⟩

/-- The enforced CircleCI job timeout (m4pro cap plus setup) when the request may run there. -/
def circleOk (c : Cfg) (r : Req) (s : State) : Option Nat :=
  match circleCap c r.lane with
  | none => none
  | some m =>
    if !c.ghOnly.contains r.lane && c.circleMacAllow.contains r.lane && decide (m ≤ c.circleShortMaxMin) &&
        decide (s.circleBusy < c.circleMacConc) && Fw.Ci.Provider.affordable (circleInput c r s (m + c.circleSetupMin))
    then some (m + c.circleSetupMin) else none

/-- Bitrise takes the request. -/
def bitriseOk (c : Cfg) (r : Req) (s : State) : Bool :=
  c.bitriseOn && !c.ghOnly.contains r.lane && c.bitriseAllow.contains r.lane && decide (r.capMin ≤ c.bitriseMaxMin) &&
    decide (s.bitriseBusy < c.bitriseConc)

/-- Linux Playwright WebKit (WPE) takes the request. -/
def wpeOk (c : Cfg) (r : Req) (s : State) : Bool :=
  !c.ghOnly.contains r.lane && c.wpeTolerant.contains r.lane && decide (s.ghTotalBusy < c.ghTotalCap)

/-- Where and how a dispatched job runs; `credits` is what it reserves. -/
structure Target where
  via : Via
  os : Os
  cls : String
  engine : Engine
  timeoutMin : Nat
  credits : Nat
deriving DecidableEq, Repr

/-- The route's answer for one request. -/
inductive Decision where
  | run (t : Target)
  | wait
  | done (o : Outcome)
deriving DecidableEq, Repr

/-- The fallback route; the first rule that matches wins. -/
def route (c : Cfg) (r : Req) (s : State) : Decision :=
  if !r.current then .done .stale
  else if ghOk c s then .run ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩
  else match circleOk c r s with
  | some m => .run ⟨.circleci, .macos, c.circleCls, r.engine, m, charge c m⟩
  | none =>
    if bitriseOk c r s then .run ⟨.bitrise, .macos, c.bitriseCls, r.engine, r.capMin, 0⟩
    else if wpeOk c r s then .run ⟨.github, .linux, c.wpeCls, .pwWebkitWpe, r.capMin, 0⟩
    else if r.ageS < c.waitMaxS then .wait
    else .done .notRun

/-- The state after a decision: a GitHub macOS job takes a slot when one is free, else joins GitHub's queue. -/
def State.after (c : Cfg) (s : State) : Decision → State
  | .run t =>
    let s := { s with circleCreditsLeft := s.circleCreditsLeft - t.credits }
    match t.via, t.os with
    | .github, .macos =>
      if macFree c s then { s with ghMacBusy := s.ghMacBusy + 1, ghTotalBusy := s.ghTotalBusy + 1 }
      else { s with ghQueuedAhead := s.ghQueuedAhead + 1 }
    | .github, .linux => { s with ghTotalBusy := s.ghTotalBusy + 1 }
    | .circleci, _ => { s with circleBusy := s.circleBusy + 1 }
    | .bitrise, _ => { s with bitriseBusy := s.bitriseBusy + 1 }
  | _ => s

/-- One poller tick over the held requests. -/
structure Out where
  sent : List (Id × Target)
  waiting : List Req
  done : List (Id × Outcome)
  log : List (Id × Decision)
  state : State

/-- Route the requests in order, each against the state the earlier ones left. -/
def step (c : Cfg) : List Req → State → Out
  | [], s => ⟨[], [], [], [], s⟩
  | r :: rs, s =>
    let d := route c r s
    let o := step c rs (s.after c d)
    match d with
    | .run t => { o with sent := (r.id, t) :: o.sent, log := (r.id, d) :: o.log }
    | .wait => { o with waiting := r :: o.waiting, log := (r.id, d) :: o.log }
    | .done x => { o with done := (r.id, x) :: o.done, log := (r.id, d) :: o.log }

/-- The ids of a tick's three outputs. -/
def Out.ids (o : Out) : List Id := o.sent.map (·.1) ++ o.waiting.map Req.id ++ o.done.map (·.1)

/-- The durable record insert: an id already seen (held, sent or done) or repeated is dropped. -/
def admit : List Id → List Req → List Req
  | _, [] => []
  | seen, r :: rs => if r.id ∈ seen then admit seen rs else r :: admit (r.id :: seen) rs

/-- One poller tick: the facts read, the new requests, and the refresh of held ones (age, tip re-check). -/
structure Tick where
  state : State
  arrive : List Req
  refresh : Req → Req
  refresh_id : ∀ r, (refresh r).id = r.id

/-- Every dispatch over a sequence of ticks; `seen` holds every id ever admitted, `held` the waiting requests. -/
def drive (c : Cfg) : List Tick → List Id → List Req → List (Id × Target)
  | [], _, _ => []
  | t :: ts, seen, held =>
    let fresh := admit seen t.arrive
    let o := step c (held.map t.refresh ++ fresh) t.state
    o.sent ++ drive c ts (seen ++ fresh.map Req.id) o.waiting

/-- One result row of a dispatched unit. -/
structure Res where
  id : Id
  leg : Nat
  via : Via
  cls : String
  engine : Engine
  outcome : Outcome
deriving DecidableEq, Repr

/-- The result row a dispatched pair yields. -/
def resOf (p : Id × Target) (leg : Nat) (o : Outcome) : Res := ⟨p.1, leg, p.2.via, p.2.cls, p.2.engine, o⟩

/-- The group freeze, classes and verdicts pool by; Apple results of two providers share one only for `crossPoolOk`. -/
def poolKey (c : Cfg) (r : Res) : String × String × Option Via × Engine :=
  (r.id.1.lane, r.id.1.cfg, if c.crossPoolOk.contains r.id.1.lane && r.engine.apple then none else some r.via, r.engine)

/-! ## Route rules -/

theorem circleOk_spec {c : Cfg} {r : Req} {s : State} {m : Nat} (h : circleOk c r s = some m) :
    ∃ k, circleCap c r.lane = some k ∧ m = k + c.circleSetupMin ∧ r.lane ∉ c.ghOnly ∧ r.lane ∈ c.circleMacAllow ∧
      k ≤ c.circleShortMaxMin ∧ s.circleBusy < c.circleMacConc ∧ Fw.Ci.Provider.affordable (circleInput c r s m) = true := by
  unfold circleOk at h
  split at h
  · simp at h
  · rename_i k hk
    split at h
    · rename_i hif
      simp only [Option.some.injEq] at h
      subst h
      simp only [Bool.and_eq_true, Bool.not_eq_true', List.contains_eq_mem, decide_eq_true_eq,
        decide_eq_false_iff_not] at hif
      exact ⟨k, hk, rfl, hif.1.1.1.1, hif.1.1.1.2, hif.1.1.2, hif.1.2, hif.2⟩
    · simp at h

theorem route_run_cases {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t) :
    r.current = true ∧
      ((ghOk c s = true ∧ t = ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩) ∨
       (ghOk c s = false ∧ ∃ m, circleOk c r s = some m ∧ t = ⟨.circleci, .macos, c.circleCls, r.engine, m, charge c m⟩) ∨
       (ghOk c s = false ∧ circleOk c r s = none ∧ bitriseOk c r s = true ∧
          t = ⟨.bitrise, .macos, c.bitriseCls, r.engine, r.capMin, 0⟩) ∨
       (ghOk c s = false ∧ circleOk c r s = none ∧ bitriseOk c r s = false ∧ wpeOk c r s = true ∧
          t = ⟨.github, .linux, c.wpeCls, .pwWebkitWpe, r.capMin, 0⟩)) := by
  unfold route at h
  by_cases hc : r.current = true
  · refine ⟨hc, ?_⟩
    simp only [hc, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
    by_cases hg : ghOk c s = true
    · simp only [hg, ↓reduceIte, Decision.run.injEq] at h
      exact .inl ⟨hg, h.symm⟩
    · have hg' : ghOk c s = false := by simpa using hg
      simp only [hg', Bool.false_eq_true, ↓reduceIte] at h
      cases hco : circleOk c r s with
      | some m =>
        simp only [hco, Decision.run.injEq] at h
        exact .inr (.inl ⟨hg', m, rfl, h.symm⟩)
      | none =>
        simp only [hco] at h
        by_cases hb : bitriseOk c r s = true
        · simp only [hb, ↓reduceIte, Decision.run.injEq] at h
          exact .inr (.inr (.inl ⟨hg', rfl, hb, h.symm⟩))
        · have hb' : bitriseOk c r s = false := by simpa using hb
          simp only [hb', Bool.false_eq_true, ↓reduceIte] at h
          by_cases hw : wpeOk c r s = true
          · simp only [hw, ↓reduceIte, Decision.run.injEq] at h
            exact .inr (.inr (.inr ⟨hg', rfl, hb', hw, h.symm⟩))
          · simp only [hw, Bool.false_eq_true, ↓reduceIte] at h
            split at h <;> simp at h
  · simp [hc] at h

theorem route_stale (c : Cfg) (r : Req) (s : State) (h : r.current = false) : route c r s = .done .stale := by
  simp [route, h]

theorem macFree_wait (c : Cfg) (s : State) (h : macFree c s = true) : expWaitS c s = some 0 := by
  simp [expWaitS, h]

theorem gh_first (c : Cfg) (r : Req) (s : State) (hd : s.ghDegraded = false) (hf : macFree c s = true)
    (hc : r.current = true) : route c r s = .run ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩ := by
  simp [route, ghOk, hd, hf, hc]

theorem gh_of_wait (c : Cfg) (r : Req) (s : State) (w : Nat) (hd : s.ghDegraded = false) (hw : expWaitS c s = some w)
    (hlt : w < c.ghWaitMaxS) (hc : r.current = true) :
    route c r s = .run ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩ := by
  simp [route, ghOk, waitOk, hd, hw, hlt, hc]

theorem ghOk_spec {c : Cfg} {s : State} (h : ghOk c s = true) :
    s.ghDegraded = false ∧ (macFree c s = true ∨ ∃ w, expWaitS c s = some w ∧ w < c.ghWaitMaxS) := by
  simp only [ghOk, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_true] at h
  refine ⟨h.1, ?_⟩
  rcases h.2 with hf | hw
  · exact .inl hf
  · unfold waitOk at hw
    split at hw
    · rename_i w hw'
      exact .inr ⟨w, hw', by simpa using hw⟩
    · simp at hw

theorem gh_overflow_bounded {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t)
    (hv : t.via = .github) (ho : t.os = .macos) :
    s.ghDegraded = false ∧ (macFree c s = true ∨ ∃ w, expWaitS c s = some w ∧ w < c.ghWaitMaxS) := by
  rcases (route_run_cases h).2 with ⟨hg, _⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · exact ghOk_spec hg
  · cases hv
  · cases hv
  · cases ho

theorem unknown_wait_not_github {c : Cfg} {r : Req} {s : State} {t : Target} (hu : expWaitS c s = none)
    (h : route c r s = .run t) : ¬ (t.via = .github ∧ t.os = .macos) := by
  rintro ⟨hv, ho⟩
  rcases (gh_overflow_bounded h hv ho).2 with hf | ⟨w, hw, _⟩
  · rw [macFree_wait c s hf] at hu; cases hu
  · rw [hu] at hw; cases hw

theorem degraded_not_github {c : Cfg} {r : Req} {s : State} {t : Target} (hd : s.ghDegraded = true)
    (h : route c r s = .run t) : ¬ (t.via = .github ∧ t.os = .macos) := by
  rintro ⟨hv, ho⟩
  rw [(gh_overflow_bounded h hv ho).1] at hd; cases hd

theorem circle_rule {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t) (hv : t.via = .circleci) :
    ∃ k, circleCap c r.lane = some k ∧ t.timeoutMin = k + c.circleSetupMin ∧ t.credits = charge c t.timeoutMin ∧
      t.cls = c.circleCls ∧ t.engine = r.engine ∧ t.os = .macos ∧ r.lane ∉ c.ghOnly ∧ r.lane ∈ c.circleMacAllow ∧
      k ≤ c.circleShortMaxMin ∧ s.circleBusy < c.circleMacConc ∧ ghOk c s = false ∧
      Fw.Ci.Provider.affordable (circleInput c r s t.timeoutMin) = true := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨hg, m, hm, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · cases hv
  · obtain ⟨k, hk, rfl, h1, h2, h3, h4, h5⟩ := circleOk_spec hm
    exact ⟨k, hk, rfl, rfl, rfl, rfl, rfl, h1, h2, h3, h4, hg, h5⟩
  · cases hv
  · cases hv

theorem circle_extends_provider_route {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t)
    (hv : t.via = .circleci) : Fw.Ci.Provider.route (circleInput c r s t.timeoutMin) = .circleci := by
  obtain ⟨_, _, _, _, _, _, _, _, ha, _, _, _, hf⟩ := circle_rule h hv
  rw [Fw.Ci.Provider.route_iff]
  refine ⟨?_, hf, ?_⟩
  · simpa [circleInput] using ha
  · simp [circleInput]

theorem circle_credits_le {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t)
    (hv : t.via = .circleci) : t.credits ≤ s.circleCreditsLeft := by
  obtain ⟨_, _, _, hc, _, _, _, _, _, _, _, _, hf⟩ := circle_rule h hv
  rw [hc]
  unfold Fw.Ci.Provider.affordable at hf
  unfold charge Fw.Ci.Provider.credits
  simp only [circleInput] at hf
  cases hr : Fw.Ci.Provider.rateOf c.circleCls with
  | none => simp [hr] at hf
  | some rt =>
    simp only [hr, Bool.and_eq_true] at hf
    simpa [hr, Option.map] using of_decide_eq_true hf.2

theorem circle_charged_at_timeout {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t)
    (hv : t.via = .circleci) :
    ∃ rt, Fw.Ci.Provider.rateOf c.circleCls = some rt ∧ t.credits = t.timeoutMin * rt.creditsPerMin := by
  obtain ⟨_, _, _, hc, _, _, _, _, _, _, _, _, hf⟩ := circle_rule h hv
  unfold Fw.Ci.Provider.affordable at hf
  simp only [circleInput] at hf
  cases hr : Fw.Ci.Provider.rateOf c.circleCls with
  | none => simp [hr] at hf
  | some rt =>
    refine ⟨rt, rfl, ?_⟩
    rw [hc, charge, Fw.Ci.Provider.credits_exact_minute _ rt hr]
    rfl

theorem bitrise_rule {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t) (hv : t.via = .bitrise) :
    c.bitriseOn = true ∧ r.lane ∉ c.ghOnly ∧ r.lane ∈ c.bitriseAllow ∧ r.capMin ≤ c.bitriseMaxMin ∧
      s.bitriseBusy < c.bitriseConc ∧ t.os = .macos ∧ t.engine = r.engine ∧ t.credits = 0 := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, hb, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · cases hv
  · cases hv
  · simp only [bitriseOk, Bool.and_eq_true, Bool.not_eq_true', List.contains_eq_mem, decide_eq_true_eq,
      decide_eq_false_iff_not] at hb
    exact ⟨hb.1.1.1.1, hb.1.1.1.2, hb.1.1.2, hb.1.2, hb.2, rfl, rfl, rfl⟩
  · cases hv

theorem bitrise_off_never {c : Cfg} {r : Req} {s : State} {t : Target} (hb : c.bitriseOn = false)
    (h : route c r s = .run t) : t.via ≠ .bitrise := by
  intro hv
  rw [(bitrise_rule h hv).1] at hb; cases hb

theorem wpe_rule {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t) (ho : t.os = .linux) :
    r.lane ∈ c.wpeTolerant ∧ r.lane ∉ c.ghOnly ∧ s.ghTotalBusy < c.ghTotalCap ∧ t.via = .github ∧
      t.engine = .pwWebkitWpe ∧ t.cls = c.wpeCls ∧ t.credits = 0 := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, hw, rfl⟩
  · cases ho
  · cases ho
  · cases ho
  · simp only [wpeOk, Bool.and_eq_true, Bool.not_eq_true', List.contains_eq_mem, decide_eq_true_eq,
      decide_eq_false_iff_not] at hw
    exact ⟨hw.1.2, hw.1.1, hw.2, rfl, rfl, rfl, rfl⟩

theorem apple_only_never_linux {c : Cfg} {r : Req} {s : State} {t : Target} (hl : r.lane ∉ c.wpeTolerant)
    (h : route c r s = .run t) : t.os = .macos ∧ t.engine = r.engine := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · exact ⟨rfl, rfl⟩
  · exact ⟨rfl, rfl⟩
  · exact ⟨rfl, rfl⟩
  · exact absurd (wpe_rule h rfl).1 hl

theorem route_wait {c : Cfg} {r : Req} {s : State} (h : route c r s = .wait) :
    r.current = true ∧ r.ageS < c.waitMaxS ∧ ghOk c s = false ∧ circleOk c r s = none ∧ bitriseOk c r s = false ∧
      wpeOk c r s = false := by
  unfold route at h
  by_cases hc : r.current = true
  · simp only [hc, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
    by_cases hg : ghOk c s = true
    · simp [hg] at h
    · simp only [hg, Bool.false_eq_true, ↓reduceIte] at h
      cases hco : circleOk c r s with
      | some m => simp [hco] at h
      | none =>
        simp only [hco] at h
        by_cases hb : bitriseOk c r s = true
        · simp [hb] at h
        · simp only [hb, Bool.false_eq_true, ↓reduceIte] at h
          by_cases hw : wpeOk c r s = true
          · simp [hw] at h
          · simp only [hw, Bool.false_eq_true, ↓reduceIte] at h
            by_cases ha : r.ageS < c.waitMaxS
            · exact ⟨hc, ha, by simpa using hg, rfl, by simpa using hb, by simpa using hw⟩
            · simp [ha] at h
  · simp [hc] at h

theorem route_done {c : Cfg} {r : Req} {s : State} {o : Outcome} (h : route c r s = .done o) :
    (o = .stale ∧ r.current = false) ∨ (o = .notRun ∧ r.current = true ∧ c.waitMaxS ≤ r.ageS) := by
  unfold route at h
  by_cases hc : r.current = true
  · simp only [hc, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
    split at h
    · simp at h
    · split at h
      · simp at h
      · split at h
        · simp at h
        · split at h
          · simp at h
          · split at h
            · simp at h
            · rename_i ha
              simp only [Decision.done.injEq] at h
              exact .inr ⟨h.symm, hc, Nat.le_of_not_lt ha⟩
  · simp only [hc, Bool.not_false, ↓reduceIte, Decision.done.injEq] at h
    exact .inl ⟨h.symm, by simpa using hc⟩

theorem old_never_waits (c : Cfg) (r : Req) (s : State) (h : c.waitMaxS ≤ r.ageS) : route c r s ≠ .wait := by
  intro hw
  have := (route_wait hw).2.1
  omega

theorem phase1_github_or_wait {r : Req} {s : State} {t : Target} (h : route phase1 r s = .run t) :
    t.via = .github ∧ t.os = .macos := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨_, m, hm, _⟩ | ⟨_, _, hb, _⟩ | ⟨_, _, _, hw, _⟩
  · exact ⟨rfl, rfl⟩
  · obtain ⟨k, hk, _⟩ := circleOk_spec hm
    simp [circleCap, phase1] at hk
  · simp [bitriseOk, phase1] at hb
  · simp [wpeOk, phase1] at hw

theorem enterprise_caps : enterprise = { phase1 with ghMacCap := 50, ghTotalCap := 500 } := rfl

theorem gate_gaps_gh_only : "gate-gaps" ∈ phase1.ghOnly := by decide

theorem wpe_disjoint_gh_only : ∀ l ∈ phase1.wpeTolerant, l ∉ phase1.ghOnly := by decide

/-! ## One tick -/

theorem step_perm (c : Cfg) (rs : List Req) (s : State) : (step c rs s).ids.Perm (rs.map Req.id) := by
  induction rs generalizing s with
  | nil => simp [step, Out.ids]
  | cons r rs ih =>
    have h := ih (s.after c (route c r s))
    simp only [step, List.map_cons]
    split <;> simp only [Out.ids, List.map_cons, List.cons_append, List.append_assoc] at h ⊢
    · exact h.cons _
    · exact List.perm_middle.trans (h.cons _)
    · exact (List.perm_middle.append_left _).trans (List.perm_middle.trans (h.cons _))

theorem step_sent (c : Cfg) (rs : List Req) (s : State) :
    ∀ p ∈ (step c rs s).sent, ∃ r ∈ rs, r.id = p.1 ∧ ∃ s', route c r s' = .run p.2 := by
  induction rs generalizing s with
  | nil => simp [step]
  | cons r rs ih =>
    have h := ih (s.after c (route c r s))
    simp only [step]
    split
    · rename_i t hd
      intro p hp
      simp only [List.mem_cons] at hp
      rcases hp with rfl | hp
      · exact ⟨r, List.mem_cons_self .., rfl, s, hd⟩
      · obtain ⟨q, hq, h1, h2⟩ := h p hp
        exact ⟨q, List.mem_cons_of_mem _ hq, h1, h2⟩
    all_goals
      intro p hp
      obtain ⟨q, hq, h1, h2⟩ := h p hp
      exact ⟨q, List.mem_cons_of_mem _ hq, h1, h2⟩

theorem step_waiting (c : Cfg) (rs : List Req) (s : State) :
    ∀ r ∈ (step c rs s).waiting, r ∈ rs ∧ r.current = true ∧ r.ageS < c.waitMaxS := by
  induction rs generalizing s with
  | nil => simp [step]
  | cons r rs ih =>
    have h := ih (s.after c (route c r s))
    simp only [step]
    split
    · intro q hq
      obtain ⟨h1, h2⟩ := h q hq
      exact ⟨List.mem_cons_of_mem _ h1, h2⟩
    · rename_i hd
      intro q hq
      simp only [List.mem_cons] at hq
      rcases hq with rfl | hq
      · have := route_wait hd
        exact ⟨List.mem_cons_self .., this.1, this.2.1⟩
      · obtain ⟨h1, h2⟩ := h q hq
        exact ⟨List.mem_cons_of_mem _ h1, h2⟩
    · intro q hq
      obtain ⟨h1, h2⟩ := h q hq
      exact ⟨List.mem_cons_of_mem _ h1, h2⟩

theorem step_done (c : Cfg) (rs : List Req) (s : State) :
    ∀ p ∈ (step c rs s).done, p.2 = .stale ∨ p.2 = .notRun := by
  induction rs generalizing s with
  | nil => simp [step]
  | cons r rs ih =>
    have h := ih (s.after c (route c r s))
    simp only [step]
    split
    · exact h
    · exact h
    · rename_i o hd
      intro p hp
      simp only [List.mem_cons] at hp
      rcases hp with rfl | hp
      · rcases route_done hd with ⟨h1, _⟩ | ⟨h1, _⟩
        · exact .inl h1
        · exact .inr h1
      · exact h p hp

theorem wait_resolves (c : Cfg) (rs : List Req) (s : State) (h : ∀ r ∈ rs, c.waitMaxS ≤ r.ageS) :
    (step c rs s).waiting = [] := by
  cases hw : (step c rs s).waiting with
  | nil => rfl
  | cons r _ =>
    have := step_waiting c rs s r (by simp [hw])
    have := h r this.1
    omega

/-- The slot and concurrency caps hold. -/
def Inv (c : Cfg) (s : State) : Prop :=
  s.ghMacBusy ≤ c.ghMacCap ∧ s.ghTotalBusy ≤ c.ghTotalCap ∧ s.circleBusy ≤ c.circleMacConc ∧
    s.bitriseBusy ≤ c.bitriseConc

theorem run_credits_le {c : Cfg} {r : Req} {s : State} {t : Target} (h : route c r s = .run t) :
    t.credits ≤ s.circleCreditsLeft := by
  rcases (route_run_cases h).2 with ⟨_, rfl⟩ | ⟨_, _, _, ht⟩ | ⟨_, _, _, rfl⟩ | ⟨_, _, _, _, rfl⟩
  · exact Nat.zero_le _
  · exact circle_credits_le h (by rw [ht])
  · exact Nat.zero_le _
  · exact Nat.zero_le _

theorem after_credits (c : Cfg) (r : Req) (s : State) :
    (s.after c (route c r s)).circleCreditsLeft +
      (match route c r s with | .run t => t.credits | _ => 0) = s.circleCreditsLeft := by
  cases hd : route c r s with
  | run t =>
    have := run_credits_le hd
    simp only [State.after]
    split <;> (try split) <;> simp only <;> omega
  | wait => simp [State.after]
  | done o => simp [State.after]

theorem after_inv {c : Cfg} {s : State} (r : Req) (h : Inv c s) : Inv c (s.after c (route c r s)) := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  cases hd : route c r s with
  | run t =>
    rcases (route_run_cases hd).2 with ⟨_, rfl⟩ | ⟨_, m, hm, rfl⟩ | ⟨_, _, hb, rfl⟩ | ⟨_, _, _, hw, rfl⟩
    · simp only [State.after]
      split
      · rename_i hf
        simp only [macFree, Bool.and_eq_true, decide_eq_true_eq] at hf
        refine ⟨?_, ?_, h3, h4⟩ <;> dsimp only <;> omega
      · exact ⟨h1, h2, h3, h4⟩
    · obtain ⟨_, _, _, _, _, _, hc, _⟩ := circleOk_spec hm
      exact ⟨h1, h2, by simp only [State.after]; omega, h4⟩
    · simp only [bitriseOk, Bool.and_eq_true, decide_eq_true_eq] at hb
      exact ⟨h1, h2, h3, by simp only [State.after]; omega⟩
    · simp only [wpeOk, Bool.and_eq_true, decide_eq_true_eq] at hw
      exact ⟨h1, by simp only [State.after]; omega, h3, h4⟩
  | wait => exact ⟨h1, h2, h3, h4⟩
  | done o => exact ⟨h1, h2, h3, h4⟩

theorem never_exceeds_quota (c : Cfg) (rs : List Req) (s : State) (h : Inv c s) :
    Inv c (step c rs s).state ∧
      (step c rs s).state.circleCreditsLeft + ((step c rs s).sent.map (·.2.credits)).sum = s.circleCreditsLeft := by
  induction rs generalizing s with
  | nil => simp [step, h]
  | cons r rs ih =>
    have hc := after_credits c r s
    obtain ⟨hi, he⟩ := ih (s.after c (route c r s)) (after_inv r h)
    simp only [step]
    split <;> rename_i hd <;> (try simp only [hd] at hc he hi ⊢) <;> (try simp only [List.map_cons, List.sum_cons]) <;>
      exact ⟨hi, by omega⟩

/-! ## Durable insert and dispatch -/

theorem admit_mem {seen : List Id} {rs : List Req} {r : Req} (h : r ∈ admit seen rs) : r ∈ rs ∧ r.id ∉ seen := by
  induction rs generalizing seen with
  | nil => simp [admit] at h
  | cons q rs ih =>
    simp only [admit] at h
    split at h
    · exact ⟨List.mem_cons_of_mem _ (ih h).1, (ih h).2⟩
    · rename_i hq
      simp only [List.mem_cons] at h
      rcases h with rfl | h
      · exact ⟨List.mem_cons_self .., hq⟩
      · have := ih h
        exact ⟨List.mem_cons_of_mem _ this.1, fun hm => this.2 (List.mem_cons_of_mem _ hm)⟩

theorem admit_nodup (seen : List Id) (rs : List Req) : ((admit seen rs).map Req.id).Nodup := by
  induction rs generalizing seen with
  | nil => simp [admit]
  | cons q rs ih =>
    simp only [admit]
    split
    · exact ih seen
    · simp only [List.map_cons, List.nodup_cons, List.mem_map]
      refine ⟨?_, ih _⟩
      rintro ⟨x, hx, he⟩
      exact (admit_mem hx).2 (he ▸ List.mem_cons_self ..)

theorem refresh_ids (t : Tick) (held : List Req) : (held.map t.refresh).map Req.id = held.map Req.id := by
  simp [List.map_map, Function.comp_def, t.refresh_id]

theorem tick_nodup (t : Tick) (seen : List Id) (held : List Req) (hn : (held.map Req.id).Nodup)
    (hs : ∀ i ∈ held.map Req.id, i ∈ seen) : ((held.map t.refresh ++ admit seen t.arrive).map Req.id).Nodup := by
  rw [List.map_append, refresh_ids, List.nodup_append]
  refine ⟨hn, admit_nodup _ _, ?_⟩
  intro a ha b hb he
  obtain ⟨x, hx, rfl⟩ := List.mem_map.mp hb
  exact (admit_mem hx).2 (he ▸ hs a ha)

theorem tick_ids (c : Cfg) (t : Tick) (seen : List Id) (held : List Req) (i : Id)
    (hi : i ∈ (step c (held.map t.refresh ++ admit seen t.arrive) t.state).ids) :
    i ∈ held.map Req.id ∨ (i ∈ (admit seen t.arrive).map Req.id ∧ i ∉ seen) := by
  rw [(step_perm _ _ _).mem_iff, List.map_append, refresh_ids, List.mem_append] at hi
  rcases hi with hi | hi
  · exact .inl hi
  · obtain ⟨x, hx, rfl⟩ := List.mem_map.mp hi
    exact .inr ⟨hi, (admit_mem hx).2⟩

theorem tick_waiting (c : Cfg) (t : Tick) (seen : List Id) (held : List Req) (hs : ∀ i ∈ held.map Req.id, i ∈ seen) :
    ∀ i ∈ (step c (held.map t.refresh ++ admit seen t.arrive) t.state).waiting.map Req.id,
      i ∈ seen ++ (admit seen t.arrive).map Req.id := by
  intro i hi
  rcases tick_ids c t seen held i (by simp only [Out.ids, List.mem_append]; exact .inl (.inr hi)) with h | h
  · exact List.mem_append_left _ (hs i h)
  · exact List.mem_append_right _ h.1

theorem drive_ids (c : Cfg) (ts : List Tick) (seen : List Id) (held : List Req)
    (hs : ∀ i ∈ held.map Req.id, i ∈ seen) :
    ∀ p ∈ drive c ts seen held, p.1 ∈ held.map Req.id ∨ p.1 ∉ seen := by
  induction ts generalizing seen held with
  | nil => simp [drive]
  | cons t ts ih =>
    intro p hp
    simp only [drive, List.mem_append] at hp
    rcases hp with hp | hp
    · rcases tick_ids c t seen held p.1
        (by simp only [Out.ids, List.mem_append]; exact .inl (.inl (List.mem_map_of_mem hp))) with h | h
      · exact .inl h
      · exact .inr h.2
    · rcases ih _ _ (tick_waiting c t seen held hs) p hp with h | h
      · rcases tick_ids c t seen held p.1 (by simp only [Out.ids, List.mem_append]; exact .inl (.inr h)) with h' | h'
        · exact .inl h'
        · exact .inr h'.2
      · exact .inr fun hm => h (List.mem_append_left _ hm)

theorem dispatch_nodup (c : Cfg) (ts : List Tick) (seen : List Id) (held : List Req) (hn : (held.map Req.id).Nodup)
    (hs : ∀ i ∈ held.map Req.id, i ∈ seen) : ((drive c ts seen held).map (·.1)).Nodup := by
  induction ts generalizing seen held with
  | nil => simp [drive]
  | cons t ts ih =>
    simp only [drive]
    have hnd := (step_perm c (held.map t.refresh ++ admit seen t.arrive) t.state).nodup_iff.mpr
      (tick_nodup t seen held hn hs)
    simp only [Out.ids, List.nodup_append] at hnd
    obtain ⟨⟨hsent, hwait, hsw⟩, _, _⟩ := hnd
    have hw := tick_waiting c t seen held hs
    rw [List.map_append, List.nodup_append]
    refine ⟨hsent, ih _ _ hwait hw, ?_⟩
    intro a ha b hb he
    obtain ⟨q, hq, rfl⟩ := List.mem_map.mp hb
    rcases drive_ids c ts _ _ hw q hq with h | h
    · exact hsw a ha q.1 h he
    · apply h
      rw [← he]
      rcases tick_ids c t seen held a (by simp only [Out.ids, List.mem_append]; exact .inl (.inl ha)) with h' | h'
      · exact List.mem_append_left _ (hs a h')
      · exact List.mem_append_right _ h'.1

/-! ## Result identity -/

theorem result_identity (p : Id × Target) (leg : Nat) (o : Outcome) :
    (resOf p leg o).via = p.2.via ∧ (resOf p leg o).cls = p.2.cls ∧ (resOf p leg o).engine = p.2.engine :=
  ⟨rfl, rfl, rfl⟩

theorem poolKey_engine (c : Cfg) (a b : Res) (h : poolKey c a = poolKey c b) : a.engine = b.engine := by
  simp only [poolKey, Prod.mk.injEq] at h
  exact h.2.2.2

theorem no_pool_apple_wpe (c : Cfg) (a b : Res) (ha : a.engine.apple = true) (hb : b.engine = .pwWebkitWpe) :
    poolKey c a ≠ poolKey c b := by
  intro h
  have := poolKey_engine c a b h
  rw [hb] at this
  rw [this] at ha
  cases ha

theorem poolKey_via (c : Cfg) (a b : Res) (h : poolKey c a = poolKey c b) (hl : a.id.1.lane ∉ c.crossPoolOk) :
    a.via = b.via := by
  simp only [poolKey, Prod.mk.injEq] at h
  obtain ⟨h1, _, h3, _⟩ := h
  have hl' : b.id.1.lane ∉ c.crossPoolOk := h1 ▸ hl
  simp [hl, hl'] at h3
  exact h3

/-! ## Examples -/

private def sha1 : String := "0123456789abcdef0123456789abcdef01234567"
private def cfg1 : String := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
private def rq (lane : String) (age : Nat := 0) (cur : Bool := true) (rep : Nat := 0) : Req :=
  ⟨⟨sha1, lane, cfg1, rep⟩, 0, .wktrIosSim, "macos-26", 15, age, cur⟩
private def demo : Cfg :=
  { phase1 with circleMacAllow := ["wktr"], circleCaps := [("wktr", 5)], bitriseOn := true,
                bitriseAllow := ["wktr-fixtures"], wpeTolerant := ["trajectory-probe"] }
private def idle : State := ⟨0, 0, 0, false, some [], 0, 0, 30000⟩
private def full (rem : Option (List Nat)) (ahead : Nat := 0) : State := ⟨5, 5, ahead, false, rem, 0, 0, 30000⟩

#guard expWaitS phase1 idle == some 0
#guard expWaitS phase1 (full (some [1800, 600])) == some 600
#guard expWaitS phase1 (full (some [1800, 600]) 1) == some 1800
#guard expWaitS phase1 (full (some [1800, 600]) 2) == none
#guard expWaitS phase1 (full none) == none
#guard expWaitS phase1 { full (some [10]) with ghTotalBusy := 20 } == none
#guard ghOk phase1 (full (some [600])) && !ghOk phase1 (full (some [1200])) && !ghOk phase1 (full none)
#guard !ghOk phase1 { idle with ghDegraded := true }
#guard route phase1 (rq "wktr") idle == .run ⟨.github, .macos, "macos-26", .wktrIosSim, 15, 0⟩
#guard route phase1 (rq "wktr" (cur := false)) idle == .done .stale
#guard route phase1 (rq "wktr") (full none) == .wait
#guard route phase1 (rq "wktr" 7200) (full none) == .done .notRun
#guard route demo (rq "wktr") (full none) == .run ⟨.circleci, .macos, "m4pro.medium", .wktrIosSim, 8, 1600⟩
#guard circleOk demo (rq "wktr") (full none) == some 8
#guard circleOk demo (rq "wktr") { full none with circleCreditsLeft := 1599 } == none
#guard circleOk demo (rq "wktr") { full none with circleBusy := 1 } == none
#guard circleOk demo (rq "sim-speed") (full none) == none
#guard route demo (rq "wktr-fixtures") (full none) == .run ⟨.bitrise, .macos, "bitrise.mac", .wktrIosSim, 15, 0⟩
#guard !bitriseOk { demo with bitriseOn := false } (rq "wktr-fixtures") (full none)
#guard route demo (rq "trajectory-probe") (full none) == .run ⟨.github, .linux, "ubuntu-24.04-arm", .pwWebkitWpe, 15, 0⟩
#guard !wpeOk demo (rq "trajectory-probe") { full none with ghTotalBusy := 20 }
#guard !wpeOk { demo with wpeTolerant := ["gate-gaps"] } (rq "gate-gaps") (full none)
#guard (idle.after phase1 (route phase1 (rq "wktr") idle)).ghMacBusy == 1
#guard ((full (some [600])).after phase1 (route phase1 (rq "wktr") (full (some [600])))).ghQueuedAhead == 1
#guard ((full none).after demo (route demo (rq "wktr") (full none))).circleCreditsLeft == 28400
#guard (step phase1 ((List.range 6).map fun i => rq "wktr" (rep := i)) idle).sent.length == 5
#guard (step phase1 ((List.range 6).map fun i => rq "wktr" (rep := i)) idle).waiting.length == 1
#guard (step phase1 ((List.range 7).map fun i => rq "wktr" (rep := i)) { idle with ghRemainingS := some [300] }).sent.length == 6
#guard (step demo [rq "wktr", rq "wktr" (rep := 1)] (full none)).log.map (·.2) ==
  [.run ⟨.circleci, .macos, "m4pro.medium", .wktrIosSim, 8, 1600⟩, .wait]
#guard (admit [(rq "wktr").id] [rq "wktr", rq "wktr" (rep := 1), rq "wktr" (rep := 1)]).length == 1
#guard poolKey phase1 ⟨(rq "wktr").id, 0, .github, "macos-26", .wktrIosSim, .result⟩ !=
  poolKey phase1 ⟨(rq "wktr").id, 0, .circleci, "m4pro.medium", .wktrIosSim, .result⟩
#guard poolKey { phase1 with crossPoolOk := ["wktr"] } ⟨(rq "wktr").id, 0, .github, "macos-26", .wktrIosSim, .result⟩ ==
  poolKey { phase1 with crossPoolOk := ["wktr"] } ⟨(rq "wktr").id, 0, .circleci, "m4pro.medium", .wktrIosSim, .result⟩

end Fw.Ci.Pool.Fallback
