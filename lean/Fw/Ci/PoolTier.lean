import Fw.Ci.Pool.Fallback
import Fw.Ci.Codemagic
import Fw.Ci.Overflow
namespace Fw.Ci.PoolTier

open Fw.Ci.Pool
open Fw.Ci.Pool.Fallback (Req Target Engine)
open Fw.Ci.Pool.Key (Key Outcome)

inductive Via where
  | github
  | codemagic
  | circleci
  | bitrise
deriving DecidableEq, Repr

structure Cfg where
  base : Fallback.Cfg
  cmOn : Bool
  cmCls : String
  cmConc : Nat
  cmCapMin : Nat
  cmAllow : List String
deriving DecidableEq, Repr

def pool7 : Cfg where
  base := { Fallback.phase1 with circleMacAllow := ["webkit-sim"], circleCaps := [("webkit-sim", 40)], circleShortMaxMin := 40 }
  cmOn := true
  cmCls := "mac_mini_m2"
  cmConc := 1
  cmCapMin := Codemagic.maxCapMin
  cmAllow := ["webkit-sim"]

structure State where
  base : Fallback.State
  cmBusy : Nat
  cmUsed : Nat
  ccSpent : Nat
  ccStorage : Nat
deriving DecidableEq, Repr

def State.fb (c : Cfg) (s : State) : Fallback.State :=
  { s.base with circleCreditsLeft := Overflow.classLeft c.base.circleCls (s.ccSpent + Fw.Ci.Provider.storageCredits s.ccStorage) }

def cmOk (c : Cfg) (r : Req) (s : State) : Bool :=
  c.cmOn && c.cmAllow.contains r.lane && !c.base.ghOnly.contains r.lane && decide (r.capMin ≤ c.cmCapMin) &&
    decide (s.cmBusy < c.cmConc) && Codemagic.poolOk s.cmUsed c.cmCapMin

inductive Decision where
  | codemagic (cls : String) (engine : Engine) (capMin : Nat)
  | base (d : Fallback.Decision)
deriving DecidableEq, Repr

def route (c : Cfg) (r : Req) (s : State) : Decision :=
  if r.current && !Fallback.ghOk c.base (s.fb c) && cmOk c r s then .codemagic c.cmCls r.engine c.cmCapMin
  else .base (Fallback.route c.base r (s.fb c))

def Decision.via : Decision → Option Via
  | .codemagic .. => some .codemagic
  | .base (.run t) => some (match t.via with | .github => .github | .circleci => .circleci | .bitrise => .bitrise)
  | .base _ => none

def Decision.credits : Decision → Nat
  | .base (.run t) => t.credits
  | _ => 0

def State.after (c : Cfg) (s : State) : Decision → State
  | .codemagic _ _ m => { s with cmBusy := s.cmBusy + 1, cmUsed := s.cmUsed + m }
  | .base d => { s with base := (s.fb c).after c.base d, ccSpent := s.ccSpent + (Decision.base d).credits }

def step (c : Cfg) : List Req → State → List (Req × Decision) × State
  | [], s => ([], s)
  | r :: rs, s =>
    let d := route c r s
    let o := step c rs (s.after c d)
    ((r, d) :: o.1, o.2)

def inflight (s : State) : Nat := s.base.ghMacBusy + s.cmBusy + s.base.circleBusy + s.base.bitriseBusy

def macCap (c : Cfg) : Nat :=
  c.base.ghMacCap + c.cmConc + c.base.circleMacConc + (if c.base.bitriseOn then c.base.bitriseConc else 0)

def Inv (c : Cfg) (s : State) : Prop :=
  Fallback.Inv c.base s.base ∧ s.cmBusy ≤ c.cmConc ∧ (c.base.bitriseOn = false → s.base.bitriseBusy = 0)

theorem fb_macFree (c : Cfg) (s : State) : Fallback.macFree c.base (s.fb c) = Fallback.macFree c.base s.base := rfl

theorem route_cm_iff (c : Cfg) (r : Req) (s : State) (cls : String) (e : Engine) (m : Nat) :
    route c r s = .codemagic cls e m ↔
      r.current = true ∧ Fallback.ghOk c.base (s.fb c) = false ∧ cmOk c r s = true ∧ cls = c.cmCls ∧ e = r.engine ∧ m = c.cmCapMin := by
  unfold route
  by_cases h : (r.current && !Fallback.ghOk c.base (s.fb c) && cmOk c r s) = true
  · simp only [h, ↓reduceIte, Decision.codemagic.injEq]
    simp only [Bool.and_eq_true, Bool.not_eq_true'] at h
    exact ⟨fun ⟨a, b, d⟩ => ⟨h.1.1, h.1.2, h.2, a.symm, b.symm, d.symm⟩, fun ⟨_, _, _, a, b, d⟩ => ⟨a.symm, b.symm, d.symm⟩⟩
  · simp only [h, Bool.false_eq_true, ↓reduceIte, reduceCtorEq, false_iff]
    rintro ⟨h1, h2, h3, -⟩
    simp [h1, h2, h3] at h

theorem route_base (c : Cfg) (r : Req) (s : State) (d : Fallback.Decision) (h : route c r s = .base d) :
    d = Fallback.route c.base r (s.fb c) := by
  unfold route at h
  split at h
  · cases h
  · injection h with h; exact h.symm

theorem github_first (c : Cfg) (r : Req) (s : State) (hd : s.base.ghDegraded = false)
    (hf : Fallback.macFree c.base s.base = true) (hc : r.current = true) :
    route c r s = .base (.run ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩) := by
  have hg : Fallback.ghOk c.base (s.fb c) = true := by
    unfold Fallback.ghOk
    rw [fb_macFree, hf]
    simp [State.fb, hd]
  have := Fallback.gh_first c.base r (s.fb c) hd hf hc
  simp [route, hg, this]

theorem codemagic_before_circleci (c : Cfg) (r : Req) (s : State) (hm : cmOk c r s = true) (hc : r.current = true) (t : Target)
    (ht : t.via = .circleci) : route c r s ≠ .base (.run t) := by
  intro h
  by_cases hg : Fallback.ghOk c.base (s.fb c) = true
  · have hd := route_base c r s _ h
    rcases (Fallback.route_run_cases hd.symm).2 with ⟨_, rfl⟩ | ⟨hg', _⟩ | ⟨hg', _⟩ | ⟨hg', _⟩
    · cases ht
    all_goals (rw [hg] at hg'; cases hg')
  · have hg' : Fallback.ghOk c.base (s.fb c) = false := by simpa using hg
    simp [route, hc, hg', hm] at h

theorem overflow_only_past_github (c : Cfg) (r : Req) (s : State) (d : Decision) (v : Via) (h : route c r s = d)
    (hv : d.via = some v) (hn : v ≠ .github) : Fallback.ghOk c.base (s.fb c) = false := by
  cases d with
  | codemagic cls e m => exact ((route_cm_iff c r s cls e m).1 h).2.1
  | base d =>
    have hd := route_base c r s d h
    cases d with
    | run t =>
      rcases (Fallback.route_run_cases hd.symm).2 with ⟨_, rfl⟩ | ⟨hg, _⟩ | ⟨hg, _⟩ | ⟨hg, _, _, _, rfl⟩
      · simp [Decision.via] at hv; exact absurd hv.symm hn
      all_goals exact hg
    | wait => simp [Decision.via] at hv
    | done o => simp [Decision.via] at hv

theorem gh_line (c : Cfg) (r : Req) (s : State) (t : Target) (h : route c r s = .base (.run t)) (hv : t.via = .github)
    (ho : t.os = .macos) :
    s.base.ghDegraded = false ∧
      (Fallback.macFree c.base s.base = true ∨ ∃ w, Fallback.expWaitS c.base (s.fb c) = some w ∧ w < c.base.ghWaitMaxS) := by
  have hd := route_base c r s _ h
  have := Fallback.gh_overflow_bounded hd.symm hv ho
  exact this

theorem cm_line (c : Cfg) (r : Req) (s : State) (cls : String) (e : Engine) (m : Nat) (h : route c r s = .codemagic cls e m) :
    s.cmUsed + m ≤ Codemagic.stopAt ∧ m ≤ Codemagic.maxCapMin ∧ s.cmBusy < c.cmConc ∧ r.capMin ≤ m := by
  obtain ⟨_, _, hm, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 h
  simp only [cmOk, Bool.and_eq_true, decide_eq_true_eq] at hm
  have := (Codemagic.poolOk_iff _ _).1 hm.2
  exact ⟨this.1, this.2, hm.1.2, hm.1.1.2⟩

theorem cm_refuses_over (c : Cfg) (r : Req) (s : State) (h : Codemagic.stopAt < s.cmUsed + c.cmCapMin) (cls : String)
    (e : Engine) (m : Nat) : route c r s ≠ .codemagic cls e m := by
  intro hr
  obtain ⟨_, _, _, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 hr
  have := (cm_line c r s cls e _ hr).1
  omega

theorem cc_credits_line (c : Cfg) (r : Req) (s : State) (t : Target) (h : route c r s = .base (.run t))
    (hv : t.via = .circleci) (hp : 0 < t.credits) :
    ∃ rt, Fw.Ci.Provider.rateOf t.cls = some rt ∧
      t.credits + (s.ccSpent + Fw.Ci.Provider.storageCredits s.ccStorage) + Overflow.reserveOf rt.pool ≤
        Fw.Ci.Provider.poolCredits rt.pool := by
  have hd := route_base c r s _ h
  have hle := Fallback.circle_credits_le hd.symm hv
  obtain ⟨_, _, _, _, hcls, _⟩ := Fallback.circle_rule hd.symm hv
  rw [hcls]
  exact Overflow.classLeft_spec hle hp

theorem cc_storage_line (c : Cfg) (r : Req) (s : State) (t : Target) (h : route c r s = .base (.run t))
    (hv : t.via = .circleci) (hp : 0 < t.credits) :
    ∃ rt, Fw.Ci.Provider.rateOf t.cls = some rt ∧
      Fw.Ci.Provider.storageCredits s.ccStorage + s.ccSpent + Overflow.reserveOf rt.pool < Fw.Ci.Provider.poolCredits rt.pool := by
  obtain ⟨rt, hr, hle⟩ := cc_credits_line c r s t h hv hp
  exact ⟨rt, hr, by omega⟩

theorem fb_storage_within_allow (c : Cfg) (s : State) (h : s.ccStorage ≤ Fw.Ci.Provider.storageAllowMilli) :
    s.fb c = { s.base with circleCreditsLeft := Overflow.classLeft c.base.circleCls s.ccSpent } := by
  simp [State.fb, Fw.Ci.Provider.storageCredits_within_allow _ h]

theorem bitrise_line (c : Cfg) (r : Req) (s : State) (hb : c.base.bitriseOn = false) (t : Target) (hv : t.via = .bitrise) :
    route c r s ≠ .base (.run t) := by
  intro h
  have hd := route_base c r s _ h
  exact Fallback.bitrise_off_never hb hd.symm hv

theorem after_inv {c : Cfg} {s : State} (r : Req) (h : Inv c s) : Inv c (s.after c (route c r s)) := by
  obtain ⟨hb, hcm, hbr⟩ := h
  cases hd : route c r s with
  | codemagic cls e m =>
    have := (cm_line c r s cls e m hd).2.2.1
    exact ⟨hb, by simp only [State.after]; omega, hbr⟩
  | base d =>
    have hd' := route_base c r s d hd
    have hfb : Fallback.Inv c.base (s.fb c) := hb
    have := Fallback.after_inv (c := c.base) r hfb
    rw [← hd'] at this
    refine ⟨this, hcm, fun ho => ?_⟩
    simp only [State.after]
    cases d with
    | run t =>
      simp only [Fallback.State.after]
      have hbz : (s.fb c).bitriseBusy = 0 := hbr ho
      have hnb : t.via ≠ .bitrise := fun hv => bitrise_line c r s ho t hv hd
      split <;> (try split) <;> simp_all
    | wait => exact hbr ho
    | done o => exact hbr ho

theorem step_inv (c : Cfg) (rs : List Req) (s : State) (h : Inv c s) : Inv c (step c rs s).2 := by
  induction rs generalizing s with
  | nil => exact h
  | cons r rs ih => exact ih _ (after_inv r h)

theorem inflight_le (c : Cfg) (s : State) (h : Inv c s) : inflight s ≤ macCap c := by
  obtain ⟨⟨h1, _, h3, h4⟩, h5, h6⟩ := h
  unfold inflight macCap
  cases hb : c.base.bitriseOn
  · have := h6 hb; simp only [Bool.false_eq_true, ↓reduceIte]; omega
  · simp only [↓reduceIte]; omega

theorem macCap_pool7 : macCap pool7 = 7 := by decide

theorem cap_7 (rs : List Req) (s : State) (h : Inv pool7 s) : inflight (step pool7 rs s).2 ≤ 7 :=
  macCap_pool7 ▸ inflight_le pool7 _ (step_inv pool7 rs s h)

/-- True for a Codemagic decision. `fw run` sends exactly these cells to Codemagic; every other decision (GitHub, CircleCI, wait) leaves the cell on GitHub, whose queue holds it. -/
def Decision.isCm : Decision → Bool
  | .codemagic .. => true
  | .base _ => false

/-- The Codemagic minutes a decision reserves (its cap), 0 for any other decision. -/
def Decision.cmMin : Decision → Nat
  | .codemagic _ _ m => m
  | .base _ => 0

/-- How many cells of a routed list go to Codemagic. -/
def cmCount (l : List (Req × Decision)) : Nat := (l.filter fun x => x.2.isCm).length

theorem route_cmMin (c : Cfg) (r : Req) (s : State) :
    (route c r s).cmMin = if (route c r s).isCm then c.cmCapMin else 0 := by
  cases hd : route c r s with
  | codemagic cls e m =>
    obtain ⟨_, _, _, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 hd
    simp [Decision.cmMin, Decision.isCm]
  | base d => simp [Decision.cmMin, Decision.isCm]

theorem after_cmUsed (c : Cfg) (s : State) (d : Decision) : (s.after c d).cmUsed = s.cmUsed + d.cmMin := by
  cases d <;> simp [State.after, Decision.cmMin]

theorem after_cmBusy (c : Cfg) (s : State) (d : Decision) : (s.after c d).cmBusy = s.cmBusy + if d.isCm then 1 else 0 := by
  cases d <;> simp [State.after, Decision.isCm]

/-- Cells on Codemagic: each costs its cap in minutes and one concurrent slot. -/
theorem step_cm_used (c : Cfg) (rs : List Req) (s : State) :
    (step c rs s).2.cmUsed = s.cmUsed + c.cmCapMin * cmCount (step c rs s).1 := by
  induction rs generalizing s with
  | nil => simp [step, cmCount]
  | cons r rs ih =>
    simp only [step, cmCount, List.filter_cons] at ih ⊢
    rw [ih, after_cmUsed, route_cmMin]
    by_cases h : (route c r s).isCm = true <;> simp [h, Nat.mul_add] <;> omega

theorem step_cm_busy (c : Cfg) (rs : List Req) (s : State) :
    (step c rs s).2.cmBusy = s.cmBusy + cmCount (step c rs s).1 := by
  induction rs generalizing s with
  | nil => simp [step, cmCount]
  | cons r rs ih =>
    simp only [step, cmCount, List.filter_cons] at ih ⊢
    rw [ih, after_cmBusy]
    by_cases h : (route c r s).isCm = true <;> simp [h] <;> omega

/-- The budget line over a whole batch: from a month at or under the stop line, the cells sent to Codemagic never carry it past 400 minutes (of 500 free). -/
theorem cm_cells_budget (c : Cfg) (rs : List Req) (s : State) (h : s.cmUsed ≤ Codemagic.stopAt) :
    s.cmUsed + c.cmCapMin * cmCount (step c rs s).1 ≤ Codemagic.stopAt := by
  induction rs generalizing s with
  | nil => simpa [step, cmCount] using h
  | cons r rs ih =>
    have hc : (route c r s).isCm = true → s.cmUsed + c.cmCapMin ≤ Codemagic.stopAt := by
      intro hm
      cases hd : route c r s with
      | codemagic cls e m =>
        have := (cm_line c r s cls e m hd).1
        obtain ⟨_, _, _, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 hd
        exact this
      | base d => rw [hd] at hm; cases hm
    have h' : (s.after c (route c r s)).cmUsed ≤ Codemagic.stopAt := by
      rw [after_cmUsed, route_cmMin]
      by_cases hm : (route c r s).isCm = true
      · simp only [hm, ite_true]; exact hc hm
      · simpa [hm] using h
    have := ih _ h'
    rw [after_cmUsed, route_cmMin] at this
    simp only [step, cmCount, List.filter_cons] at this ⊢
    by_cases hm : (route c r s).isCm = true <;> simp [hm, Nat.mul_add] at this ⊢ <;> omega

/-- A batch from an invariant state fills at most the free Codemagic slots. -/
theorem cm_cells_slots (c : Cfg) (rs : List Req) (s : State) (h : Inv c s) :
    s.cmBusy + cmCount (step c rs s).1 ≤ c.cmConc := by
  rw [← step_cm_busy]
  exact (step_inv c rs s h).2.1

/-- The rewrite arm is never sent to Codemagic: its lane is not in the Codemagic allow-list of the pool (the site build is not on that machine). -/
theorem rewrite_never_codemagic (r : Req) (s : State) (h : r.lane = "webkit-sim-rewrite") (cls : String) (e : Engine) (m : Nat) :
    route pool7 r s ≠ .codemagic cls e m := by
  intro hr
  obtain ⟨_, _, hm, _⟩ := (route_cm_iff pool7 r s cls e m).1 hr
  simp [cmOk, pool7, h] at hm

structure Res where
  key : Key
  leg : Nat
  via : Via
  cls : String
  outcome : Outcome
deriving DecidableEq, Repr

def counted (rs : List Res) (k : Key) : Nat := (rs.filter fun x => x.key == k && x.outcome == .result).length

theorem counted_relabel (rs : List Res) (k : Key) (f : Res → Via) (g : Res → String) :
    counted (rs.map fun x => { x with via := f x, cls := g x }) k = counted rs k := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    simp only [counted] at ih ⊢
    rw [List.map_cons, List.filter_cons, List.filter_cons]
    by_cases hx : (x.key == k && x.outcome == .result) = true
    · simp only [hx, ite_true, List.length_cons, ih]
    · simp only [hx, ite_false, Bool.false_eq_true, ih]

theorem result_counts_any_provider (rs : List Res) (x : Res) (hx : x.outcome = .result) :
    counted (rs ++ [x]) x.key = counted rs x.key + 1 := by
  simp [counted, List.filter_append, hx]

private def sha1 : String := "0123456789abcdef0123456789abcdef01234567"
private def cfg1 : String := "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
private def rq (lane : String) (rep : Nat := 0) (cap : Nat := 40) : Req :=
  ⟨⟨sha1, lane, cfg1, rep⟩, 0, .iosSimSafari, "xcode-27", cap, 0, true⟩
private def idle : State := ⟨⟨0, 0, 0, false, none, 0, 0, 0⟩, 0, 46, 3575, 30⟩
private def seven : List Req := (List.range 7).map fun i => rq "webkit-sim" i

#guard (step pool7 seven idle).1.map (·.2.via) ==
  [some .github, some .github, some .github, some .github, some .github, some .codemagic, some .circleci]
#guard inflight (step pool7 seven idle).2 == 7
#guard (step pool7 (seven ++ [rq "webkit-sim" 7]) idle).1.getLast?.map (·.2) == some (.base .wait)
#guard (step pool7 seven idle).2.ccSpent == 3575 + 8600
#guard (step pool7 seven idle).2.cmUsed == 86
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 } == .codemagic "mac_mini_m2" .iosSimSafari 40
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmUsed := 361 } ==
  .base (.run ⟨.circleci, .macos, "m4pro.medium", .iosSimSafari, 43, 8600⟩)
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccStorage := 1297 } ==
  .base (.run ⟨.circleci, .macos, "m4pro.medium", .iosSimSafari, 43, 8600⟩)
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccSpent := 15400, ccStorage := 2000 } ==
  .base (.run ⟨.circleci, .macos, "m4pro.medium", .iosSimSafari, 43, 8600⟩)
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccSpent := 15400, ccStorage := 2001 } ==
  .base .wait
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccSpent := 15401 } ==
  .base .wait
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccSpent := 15400 } ==
  .base (.run ⟨.circleci, .macos, "m4pro.medium", .iosSimSafari, 43, 8600⟩)
#guard route pool7 (rq "webkit-sim" (cap := 41)) { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 } ==
  .base (.run ⟨.circleci, .macos, "m4pro.medium", .iosSimSafari, 43, 8600⟩)
#guard route pool7 (rq "gate-gaps") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 } == .base .wait
#guard route pool7 (rq "wktr") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 } == .base .wait
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, base.ghRemainingS := some [300] } ==
  .base (.run ⟨.github, .macos, "xcode-27", .iosSimSafari, 40, 0⟩)
#guard counted [⟨(rq "w").key, 0, .github, "xcode-27", .result⟩, ⟨(rq "w").key, 0, .codemagic, "mac_mini_m2", .result⟩,
  ⟨(rq "w").key, 0, .circleci, "m4pro.medium", .failed⟩] (rq "w").key == 2

end Fw.Ci.PoolTier
