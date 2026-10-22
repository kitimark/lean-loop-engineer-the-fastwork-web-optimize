import Fw.Ci.Pool.Fallback
import Fw.Ci.Codemagic
import Fw.Ci.Overflow
/-!
# The three-tier macOS pool: GitHub first, then Codemagic, then CircleCI

A macOS request goes to GitHub while a GitHub macOS slot is free or its wait is short (`Fw.Ci.Pool.Fallback.ghOk`). Past that it
goes to Codemagic (one build at a time, under the month's minutes line `Fw.Ci.Codemagic.poolOk`), and only then to the fallback
route of `Fw.Ci.Pool.Fallback`, whose CircleCI branch reads the credits and storage stop rules of `Fw.Ci.Overflow`. With
`pool7` at most 5 + 1 + 1 = 7 macOS jobs run at once. Task `macos-pool-7`; golden `packages/contracts/golden/ci/pool-tier.jsonl`;
ops `ci.poolTier`, `ci.poolTierConsts` (`Fw.Wire.CiPoolTier`).
-/
namespace Fw.Ci.PoolTier

open Fw.Ci.Pool
open Fw.Ci.Pool.Fallback (Req Target Engine)
open Fw.Ci.Pool.Key (Key Outcome)

/-- The provider a macOS job runs on. -/
inductive Via where
  | github
  | codemagic
  | circleci
  | bitrise
deriving DecidableEq, Repr

/-- The pool's constants: the fallback route's and the Codemagic tier's. -/
structure Cfg where
  base : Fallback.Cfg
  cmOn : Bool
  cmCls : String
  cmConc : Nat
  cmCapMin : Nat
  cmAllow : List String
deriving DecidableEq, Repr

/-- Seven macOS slots: GitHub 5, Codemagic 1, CircleCI 1 for the webkit-sim lane (m4pro cap 40 min INFERRED from the Codemagic
cap; the CircleCI stop rule `Fw.Ci.Provider.capMs` is 60 min). -/
def pool7 : Cfg where
  base := { Fallback.phase1 with circleMacAllow := ["webkit-sim"], circleCaps := [("webkit-sim", 40)], circleShortMaxMin := 40 }
  cmOn := true
  cmCls := "mac_mini_m2"
  cmConc := 1
  cmCapMin := Codemagic.maxCapMin
  cmAllow := ["webkit-sim"]

/-- The fallback state plus what the two extra tiers read: Codemagic builds running and minutes used this month (a pending
build counted at its cap), CircleCI credits spent this month and stored thousandths of the storage allowance. The fallback
state's `circleCreditsLeft` is not read: the pool derives it from `ccSpent`. -/
structure State where
  base : Fallback.State
  cmBusy : Nat
  cmUsed : Nat
  ccSpent : Nat
  ccStorage : Nat
deriving DecidableEq, Repr

/-- The fallback state the pool hands on: CircleCI credits left by `Fw.Ci.Overflow.classLeft`. -/
def State.fb (c : Cfg) (s : State) : Fallback.State :=
  { s.base with circleCreditsLeft := Overflow.classLeft c.base.circleCls s.ccSpent }

/-- The fallback constants the pool hands on: no CircleCI lane while the storage stop rule fires. -/
def baseCfg (c : Cfg) (s : State) : Fallback.Cfg :=
  if Overflow.storageClearAt s.ccStorage then c.base else { c.base with circleMacAllow := [] }

/-- Codemagic takes the request. -/
def cmOk (c : Cfg) (r : Req) (s : State) : Bool :=
  c.cmOn && c.cmAllow.contains r.lane && !c.base.ghOnly.contains r.lane && decide (r.capMin ≤ c.cmCapMin) &&
    decide (s.cmBusy < c.cmConc) && Codemagic.poolOk s.cmUsed c.cmCapMin

/-- The pool's answer: a Codemagic build (class, engine, `max_build_duration` in minutes) or the fallback route's answer. -/
inductive Decision where
  | codemagic (cls : String) (engine : Engine) (capMin : Nat)
  | base (d : Fallback.Decision)
deriving DecidableEq, Repr

/-- The pool route: a current request GitHub does not take goes to Codemagic when it may, else to the fallback route. -/
def route (c : Cfg) (r : Req) (s : State) : Decision :=
  if r.current && !Fallback.ghOk c.base (s.fb c) && cmOk c r s then .codemagic c.cmCls r.engine c.cmCapMin
  else .base (Fallback.route (baseCfg c s) r (s.fb c))

/-- The provider a decision runs on, if it runs. -/
def Decision.via : Decision → Option Via
  | .codemagic .. => some .codemagic
  | .base (.run t) => some (match t.via with | .github => .github | .circleci => .circleci | .bitrise => .bitrise)
  | .base _ => none

/-- Credits a decision reserves on CircleCI. -/
def Decision.credits : Decision → Nat
  | .base (.run t) => t.credits
  | _ => 0

/-- The state after a decision: a Codemagic build takes its slot and its cap in minutes, a fallback decision moves the
fallback state, and CircleCI credits are counted as spent. -/
def State.after (c : Cfg) (s : State) : Decision → State
  | .codemagic _ _ m => { s with cmBusy := s.cmBusy + 1, cmUsed := s.cmUsed + m }
  | .base d => { s with base := (s.fb c).after (baseCfg c s) d, ccSpent := s.ccSpent + (Decision.base d).credits }

/-- Route the requests in order, each against the state the earlier ones left. -/
def step (c : Cfg) : List Req → State → List (Req × Decision) × State
  | [], s => ([], s)
  | r :: rs, s =>
    let d := route c r s
    let o := step c rs (s.after c d)
    ((r, d) :: o.1, o.2)

/-- macOS jobs running now on every provider. -/
def inflight (s : State) : Nat := s.base.ghMacBusy + s.cmBusy + s.base.circleBusy + s.base.bitriseBusy

/-- The most macOS jobs the constants allow at once. -/
def macCap (c : Cfg) : Nat :=
  c.base.ghMacCap + c.cmConc + c.base.circleMacConc + (if c.base.bitriseOn then c.base.bitriseConc else 0)

/-- The slot caps hold, and Bitrise runs nothing while it is off. -/
def Inv (c : Cfg) (s : State) : Prop :=
  Fallback.Inv c.base s.base ∧ s.cmBusy ≤ c.cmConc ∧ (c.base.bitriseOn = false → s.base.bitriseBusy = 0)

/-! ## Order: GitHub first, Codemagic before CircleCI -/

theorem baseCfg_gh (c : Cfg) (s : State) : Fallback.ghOk (baseCfg c s) = Fallback.ghOk c.base := by
  unfold baseCfg; split <;> rfl

theorem baseCfg_macFree (c : Cfg) (s : State) : Fallback.macFree (baseCfg c s) = Fallback.macFree c.base := by
  unfold baseCfg; split <;> rfl

theorem baseCfg_inv (c : Cfg) (s : State) : Fallback.Inv (baseCfg c s) = Fallback.Inv c.base := by
  unfold baseCfg; split <;> rfl

theorem baseCfg_bitrise (c : Cfg) (s : State) : (baseCfg c s).bitriseOn = c.base.bitriseOn := by
  unfold baseCfg; split <;> rfl

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
    d = Fallback.route (baseCfg c s) r (s.fb c) := by
  unfold route at h
  split at h
  · cases h
  · injection h with h; exact h.symm

/-- GitHub first: while GitHub is not degraded and a GitHub macOS slot is free, a current request goes to GitHub. -/
theorem github_first (c : Cfg) (r : Req) (s : State) (hd : s.base.ghDegraded = false)
    (hf : Fallback.macFree c.base s.base = true) (hc : r.current = true) :
    route c r s = .base (.run ⟨.github, .macos, r.image, r.engine, r.capMin, 0⟩) := by
  have hg : Fallback.ghOk c.base (s.fb c) = true := by
    unfold Fallback.ghOk
    rw [fb_macFree, hf]
    simp [State.fb, hd]
  have := Fallback.gh_first (baseCfg c s) r (s.fb c) hd (by rw [baseCfg_macFree]; exact hf) hc
  simp [route, hg, this]

/-- Codemagic before CircleCI: a current request Codemagic may take never goes to CircleCI. -/
theorem codemagic_before_circleci (c : Cfg) (r : Req) (s : State) (hm : cmOk c r s = true) (hc : r.current = true) (t : Target)
    (ht : t.via = .circleci) : route c r s ≠ .base (.run t) := by
  intro h
  by_cases hg : Fallback.ghOk c.base (s.fb c) = true
  · have hd := route_base c r s _ h
    rcases (Fallback.route_run_cases hd.symm).2 with ⟨_, rfl⟩ | ⟨hg', _⟩ | ⟨hg', _⟩ | ⟨hg', _⟩
    · cases ht
    all_goals (rw [baseCfg_gh] at hg'; rw [hg] at hg'; cases hg')
  · have hg' : Fallback.ghOk c.base (s.fb c) = false := by simpa using hg
    simp [route, hc, hg', hm] at h

/-- Every run decision is GitHub, Codemagic, CircleCI or Bitrise, and a non-GitHub one only when GitHub does not take it. -/
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
      all_goals (rw [baseCfg_gh] at hg; exact hg)
    | wait => simp [Decision.via] at hv
    | done o => simp [Decision.via] at hv

/-! ## Stop rules: each provider refuses on its own line -/

/-- GitHub's line: a GitHub macOS job only while GitHub is not degraded and a slot is free or its wait is short. -/
theorem gh_line (c : Cfg) (r : Req) (s : State) (t : Target) (h : route c r s = .base (.run t)) (hv : t.via = .github)
    (ho : t.os = .macos) :
    s.base.ghDegraded = false ∧
      (Fallback.macFree c.base s.base = true ∨ ∃ w, Fallback.expWaitS c.base (s.fb c) = some w ∧ w < c.base.ghWaitMaxS) := by
  have hd := route_base c r s _ h
  have := Fallback.gh_overflow_bounded hd.symm hv ho
  unfold baseCfg at this
  split at this <;> exact this

/-- Codemagic's line: a Codemagic build only when one more build at the cap stays under the month's stop line, the cap is the
pilot's, and its one slot is free. -/
theorem cm_line (c : Cfg) (r : Req) (s : State) (cls : String) (e : Engine) (m : Nat) (h : route c r s = .codemagic cls e m) :
    s.cmUsed + m ≤ Codemagic.stopAt ∧ m ≤ Codemagic.maxCapMin ∧ s.cmBusy < c.cmConc ∧ r.capMin ≤ m := by
  obtain ⟨_, _, hm, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 h
  simp only [cmOk, Bool.and_eq_true, decide_eq_true_eq] at hm
  have := (Codemagic.poolOk_iff _ _).1 hm.2
  exact ⟨this.1, this.2, hm.1.2, hm.1.1.2⟩

/-- Codemagic refuses past the stop line. -/
theorem cm_refuses_over (c : Cfg) (r : Req) (s : State) (h : Codemagic.stopAt < s.cmUsed + c.cmCapMin) (cls : String)
    (e : Engine) (m : Nat) : route c r s ≠ .codemagic cls e m := by
  intro hr
  obtain ⟨_, _, _, _, _, rfl⟩ := (route_cm_iff c r s cls e m).1 hr
  have := (cm_line c r s cls e _ hr).1
  omega

/-- CircleCI's credits line: the charge, the credits spent and the class pool's reserve fit the class's free pool. -/
theorem cc_credits_line (c : Cfg) (r : Req) (s : State) (t : Target) (h : route c r s = .base (.run t))
    (hv : t.via = .circleci) (hp : 0 < t.credits) :
    ∃ rt, Fw.Ci.Provider.rateOf t.cls = some rt ∧
      t.credits + s.ccSpent + Overflow.reserveOf rt.pool ≤ Fw.Ci.Provider.poolCredits rt.pool := by
  have hd := route_base c r s _ h
  have hle := Fallback.circle_credits_le hd.symm hv
  obtain ⟨_, _, _, _, hcls, _⟩ := Fallback.circle_rule hd.symm hv
  have hcls' : t.cls = c.base.circleCls := by rw [hcls]; unfold baseCfg; split <;> rfl
  rw [hcls']
  exact Overflow.classLeft_spec hle hp

/-- CircleCI's storage line: while the storage stop rule fires, no request goes to CircleCI. -/
theorem cc_storage_line (c : Cfg) (r : Req) (s : State) (hs : Fw.Ci.Provider.storageMaxMilli < s.ccStorage) (t : Target)
    (hv : t.via = .circleci) : route c r s ≠ .base (.run t) := by
  intro h
  have hd := route_base c r s _ h
  obtain ⟨_, _, _, _, _, _, _, _, hl, _⟩ := Fallback.circle_rule hd.symm hv
  have hc : Overflow.storageClearAt s.ccStorage = false := by
    cases hx : Overflow.storageClearAt s.ccStorage
    · rfl
    · have := (Overflow.storageClearAt_iff _).1 hx; omega
  simp [baseCfg, hc] at hl

/-- Bitrise's line: off, it takes nothing. -/
theorem bitrise_line (c : Cfg) (r : Req) (s : State) (hb : c.base.bitriseOn = false) (t : Target) (hv : t.via = .bitrise) :
    route c r s ≠ .base (.run t) := by
  intro h
  have hd := route_base c r s _ h
  exact Fallback.bitrise_off_never (by rw [baseCfg_bitrise]; exact hb) hd.symm hv

/-! ## Seven at once -/

theorem after_inv {c : Cfg} {s : State} (r : Req) (h : Inv c s) : Inv c (s.after c (route c r s)) := by
  obtain ⟨hb, hcm, hbr⟩ := h
  cases hd : route c r s with
  | codemagic cls e m =>
    have := (cm_line c r s cls e m hd).2.2.1
    exact ⟨hb, by simp only [State.after]; omega, hbr⟩
  | base d =>
    have hd' := route_base c r s d hd
    have hfb : Fallback.Inv (baseCfg c s) (s.fb c) := by rw [baseCfg_inv]; exact hb
    have := Fallback.after_inv (c := baseCfg c s) r hfb
    rw [← hd', baseCfg_inv] at this
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

/-- Seven at once: from a state inside the caps, every tick of `pool7` keeps at most seven macOS jobs running. -/
theorem cap_7 (rs : List Req) (s : State) (h : Inv pool7 s) : inflight (step pool7 rs s).2 ≤ 7 :=
  macCap_pool7 ▸ inflight_le pool7 _ (step_inv pool7 rs s h)

/-! ## Results count whichever provider ran them -/

/-- One result row of a pool job. -/
structure Res where
  key : Key
  leg : Nat
  via : Via
  cls : String
  outcome : Outcome
deriving DecidableEq, Repr

/-- Results a key has: rows of that key whose outcome is `result`, whatever provider and class ran them. -/
def counted (rs : List Res) (k : Key) : Nat := (rs.filter fun x => x.key == k && x.outcome == .result).length

/-- A row's provider and class do not change the count: relabelling every row's provider and class keeps every key's count. -/
theorem counted_relabel (rs : List Res) (k : Key) (f : Res → Via) (g : Res → String) :
    counted (rs.map fun x => { x with via := f x, cls := g x }) k = counted rs k := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    simp only [counted] at ih ⊢
    rw [List.map_cons, List.filter_cons, List.filter_cons]
    by_cases hx : (x.key == k && x.outcome == .result) = true
    · rw [if_pos hx, if_pos hx, List.length_cons, List.length_cons, ih]
    · rw [if_neg hx, if_neg hx, ih]

/-- A result from any provider counts once for its key. -/
theorem result_counts_any_provider (rs : List Res) (x : Res) (hx : x.outcome = .result) :
    counted (rs ++ [x]) x.key = counted rs x.key + 1 := by
  simp [counted, List.filter_append, hx]

/-! ## Examples -/

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
#guard route pool7 (rq "webkit-sim") { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5, cmBusy := 1, ccStorage := 1001 } ==
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
