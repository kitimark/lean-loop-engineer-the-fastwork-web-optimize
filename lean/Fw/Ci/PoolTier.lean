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
  cmAllow := ["webkit-sim", "webkit-sim-rewrite"]

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

def Decision.isCm : Decision → Bool
  | .codemagic .. => true
  | .base _ => false

def Decision.cmMin : Decision → Nat
  | .codemagic _ _ m => m
  | .base _ => 0

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

theorem cm_cells_slots (c : Cfg) (rs : List Req) (s : State) (h : Inv c s) :
    s.cmBusy + cmCount (step c rs s).1 ≤ c.cmConc := by
  rw [← step_cm_busy]
  exact (step_inv c rs s h).2.1

def rewriteLane : String := "webkit-sim-rewrite"

def laneOfTarget : String → Option String
  | "original" => some "webkit-sim"
  | "rewrite" => some rewriteLane
  | _ => none

def routableLane (c : Cfg) (lane : String) : Bool :=
  c.cmOn && c.cmAllow.contains lane && !c.base.ghOnly.contains lane

def routableTarget (c : Cfg) (t : String) : Bool :=
  match laneOfTarget t with
  | some l => routableLane c l
  | none => false

def siteMatch (gh cm : Option String) : Bool :=
  match gh, cm with
  | some a, some b => !a.isEmpty && a == b
  | _, _ => false

def cellFiled (lane : String) (gh cm : Option String) : Bool :=
  lane != rewriteLane || siteMatch gh cm

theorem original_routable : routableTarget pool7 "original" = true := by decide

theorem rewrite_routable : routableTarget pool7 "rewrite" = true := by decide

theorem both_not_routable (c : Cfg) : routableTarget c "both" = false := rfl

theorem rewrite_filed_needs_digest (gh cm : Option String) (h : cellFiled rewriteLane gh cm = true) :
    ∃ d, d ≠ "" ∧ gh = some d ∧ cm = some d := by
  unfold cellFiled at h
  have hl : (rewriteLane != rewriteLane) = false := by simp
  rw [hl, Bool.false_or] at h
  unfold siteMatch at h
  cases gh <;> cases cm <;> simp at h
  rename_i a b
  exact ⟨a, by simpa using h.1, by simp [h.2], by simp [h.2]⟩

theorem rewrite_mismatch_refused (a b : String) (h : a ≠ b) : cellFiled rewriteLane (some a) (some b) = false := by
  simp [cellFiled, siteMatch, h]

theorem rewrite_no_cm_digest_refused (gh : Option String) : cellFiled rewriteLane gh none = false := by
  cases gh <;> simp [cellFiled, siteMatch]

theorem rewrite_no_gh_digest_refused (cm : Option String) : cellFiled rewriteLane none cm = false := by
  cases cm <;> simp [cellFiled, siteMatch]

theorem original_filed (gh cm : Option String) : cellFiled "webkit-sim" gh cm = true := by
  simp [cellFiled, rewriteLane]

structure Hw where
  cpus : Nat
  memsize : Nat
deriving DecidableEq, Repr

structure PlatformKey where
  macosBuild : String
  xcodeBuild : String
  runtimeBuild : String
  hw : Hw
deriving DecidableEq, Repr

def PlatformKey.complete (k : PlatformKey) : Bool :=
  !k.macosBuild.isEmpty && !k.xcodeBuild.isEmpty && !k.runtimeBuild.isEmpty && decide (0 < k.hw.cpus) &&
    decide (0 < k.hw.memsize)

def cellMerged (ref cell : PlatformKey) : Bool :=
  cell.complete && ref == cell

theorem cellMerged_iff (ref cell : PlatformKey) : cellMerged ref cell = true ↔ ref = cell ∧ cell.complete = true := by
  unfold cellMerged
  simp [Bool.and_eq_true, and_comm]

theorem cellMerged_of_eq (k : PlatformKey) (h : k.complete = true) : cellMerged k k = true := by
  simp [cellMerged, h]

theorem cellMerged_macos_refused (ref cell : PlatformKey) (h : ref.macosBuild ≠ cell.macosBuild) : cellMerged ref cell = false := by
  cases ref; cases cell; simp_all [cellMerged]

theorem cellMerged_xcode_refused (ref cell : PlatformKey) (h : ref.xcodeBuild ≠ cell.xcodeBuild) : cellMerged ref cell = false := by
  cases ref; cases cell; simp_all [cellMerged]

theorem cellMerged_runtime_refused (ref cell : PlatformKey) (h : ref.runtimeBuild ≠ cell.runtimeBuild) : cellMerged ref cell = false := by
  cases ref; cases cell; simp_all [cellMerged]

theorem cellMerged_hw_refused (ref cell : PlatformKey) (h : ref.hw ≠ cell.hw) : cellMerged ref cell = false := by
  cases ref; cases cell; simp_all [cellMerged]

theorem cellMerged_cpus_refused (ref cell : PlatformKey) (h : ref.hw.cpus ≠ cell.hw.cpus) : cellMerged ref cell = false :=
  cellMerged_hw_refused ref cell fun e => h (e ▸ rfl)

theorem cellMerged_memsize_refused (ref cell : PlatformKey) (h : ref.hw.memsize ≠ cell.hw.memsize) : cellMerged ref cell = false :=
  cellMerged_hw_refused ref cell fun e => h (e ▸ rfl)

theorem cellMerged_empty_macos (ref cell : PlatformKey) (h : cell.macosBuild = "") : cellMerged ref cell = false := by
  cases cell; simp_all [cellMerged, PlatformKey.complete]

theorem cellMerged_empty_xcode (ref cell : PlatformKey) (h : cell.xcodeBuild = "") : cellMerged ref cell = false := by
  cases cell; simp_all [cellMerged, PlatformKey.complete]

theorem cellMerged_empty_runtime (ref cell : PlatformKey) (h : cell.runtimeBuild = "") : cellMerged ref cell = false := by
  cases cell; simp_all [cellMerged, PlatformKey.complete]

theorem cellMerged_no_cpus (ref cell : PlatformKey) (h : cell.hw.cpus = 0) : cellMerged ref cell = false := by
  cases cell; simp_all [cellMerged, PlatformKey.complete]

theorem cellMerged_no_memsize (ref cell : PlatformKey) (h : cell.hw.memsize = 0) : cellMerged ref cell = false := by
  cases cell; simp_all [cellMerged, PlatformKey.complete]

def ghHw : Hw := ⟨3, 7516192768⟩

def cmHw : Hw := ⟨8, 12884901888⟩

theorem round2_pair_refused :
    cellMerged ⟨"26A434", "27A9275", "24A434", ghHw⟩ ⟨"26A428", "27A266a", "24A434", ghHw⟩ = false := by decide

theorem pinned_pair_merged :
    cellMerged ⟨"26A434", "27A9275", "24A434", ghHw⟩ ⟨"26A434", "27A9275", "24A434", ghHw⟩ = true := by decide

theorem missing_runtime_refused :
    cellMerged ⟨"26A434", "27A9275", "24A434", ghHw⟩ ⟨"26A434", "27A9275", "", ghHw⟩ = false := by decide

theorem measured_pair_not_merged :
    cellMerged ⟨"26A434", "27A9275", "24A434", ghHw⟩ ⟨"26A434", "27A9275", "24A434", cmHw⟩ = false := by decide

/-! ## Cross-pool pooling: a row on other hardware pairs only when `kReq` pinned pairs agree on its class -/

inductive RowClass where
  | deterministic
  | stable
  | quarantined
deriving DecidableEq, Repr

def RowClass.rank : RowClass → Nat
  | .deterministic => 0
  | .stable => 1
  | .quarantined => 2

def RowClass.ofString : String → Option RowClass
  | "deterministic" => some .deterministic
  | "stable" => some .stable
  | "quarantined" => some .quarantined
  | _ => none

def RowClass.worse (a b : RowClass) : RowClass := if a.rank ≤ b.rank then b else a

theorem worse_ge_left (a b : RowClass) : a.rank ≤ (a.worse b).rank := by
  unfold RowClass.worse; split <;> omega

theorem worse_ge_right (a b : RowClass) : b.rank ≤ (a.worse b).rank := by
  unfold RowClass.worse; split <;> omega

structure Obs where
  gh : RowClass
  cm : RowClass
  ghKey : PlatformKey
  cmKey : PlatformKey
  ghRun : String
  cmBuild : String
  ghSha : String
  cmSha : String
deriving DecidableEq, Repr

def kReq : Nat := 3

def Obs.holds (ref cell : PlatformKey) (o : Obs) : Bool :=
  o.gh == o.cm && o.ghKey == ref && o.cmKey == cell && o.ghSha == o.cmSha && !o.ghSha.isEmpty

def rowPooled (ref cell : PlatformKey) (obs : List Obs) : Bool :=
  decide (kReq ≤ obs.length) && obs.all (·.holds ref cell) && decide (obs.map (·.ghRun)).Nodup &&
    decide (obs.map (·.cmBuild)).Nodup

theorem rowPooled_iff (ref cell : PlatformKey) (obs : List Obs) :
    rowPooled ref cell obs = true ↔
      kReq ≤ obs.length ∧ (∀ o ∈ obs, o.holds ref cell = true) ∧ (obs.map (·.ghRun)).Nodup ∧ (obs.map (·.cmBuild)).Nodup := by
  simp [rowPooled, and_assoc]

theorem pooled_too_few (ref cell : PlatformKey) (obs : List Obs) (h : obs.length < kReq) : rowPooled ref cell obs = false := by
  have : ¬ kReq ≤ obs.length := by omega
  simp [rowPooled, this]

theorem pooled_disagree (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (ho : o ∈ obs) (h : o.gh ≠ o.cm) :
    rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · have := ((rowPooled_iff ref cell obs).1 hp).2.1 o ho
    simp [Obs.holds, h] at this

theorem pooled_ghKey_mismatch (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (ho : o ∈ obs) (h : o.ghKey ≠ ref) :
    rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · have := ((rowPooled_iff ref cell obs).1 hp).2.1 o ho
    simp [Obs.holds, h] at this

theorem pooled_cmKey_mismatch (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (ho : o ∈ obs) (h : o.cmKey ≠ cell) :
    rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · have := ((rowPooled_iff ref cell obs).1 hp).2.1 o ho
    simp [Obs.holds, h] at this

theorem pooled_append_disagree (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (h : o.gh ≠ o.cm) :
    rowPooled ref cell (obs ++ [o]) = false :=
  pooled_disagree ref cell _ o (by simp) h

theorem pooled_dup_gh_refused (ref cell : PlatformKey) (obs : List Obs) (h : ¬ (obs.map (·.ghRun)).Nodup) :
    rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · exact absurd ((rowPooled_iff ref cell obs).1 hp).2.2.1 h

theorem pooled_dup_cm_refused (ref cell : PlatformKey) (obs : List Obs) (h : ¬ (obs.map (·.cmBuild)).Nodup) :
    rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · exact absurd ((rowPooled_iff ref cell obs).1 hp).2.2.2 h

theorem pooled_sha_mismatch_refused (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (ho : o ∈ obs)
    (h : o.ghSha ≠ o.cmSha) : rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · have := ((rowPooled_iff ref cell obs).1 hp).2.1 o ho
    simp [Obs.holds, h] at this

theorem pooled_empty_sha_refused (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (ho : o ∈ obs)
    (h : o.ghSha = "") : rowPooled ref cell obs = false := by
  cases hp : rowPooled ref cell obs
  · rfl
  · have := ((rowPooled_iff ref cell obs).1 hp).2.1 o ho
    simp [Obs.holds, h] at this

def sameToolchain (ref cell : PlatformKey) : Bool :=
  ref.macosBuild == cell.macosBuild && ref.xcodeBuild == cell.xcodeBuild && ref.runtimeBuild == cell.runtimeBuild

inductive Use where
  | direct
  | paired
  | refused
deriving DecidableEq, Repr

def rowUse (ref cell : PlatformKey) (obs : List Obs) : Use :=
  if cellMerged ref cell then .direct
  else if ref.complete && cell.complete && sameToolchain ref cell && rowPooled ref cell obs then .paired
  else .refused

theorem rowUse_direct_iff (ref cell : PlatformKey) (obs : List Obs) :
    rowUse ref cell obs = .direct ↔ cellMerged ref cell = true := by
  unfold rowUse
  by_cases h : cellMerged ref cell = true
  · simp [h]
  · simp only [h, ↓reduceIte, Bool.false_eq_true, iff_false]
    by_cases p : (ref.complete && cell.complete && sameToolchain ref cell && rowPooled ref cell obs) = true <;> simp [p]

theorem rowUse_paired_iff (ref cell : PlatformKey) (obs : List Obs) :
    rowUse ref cell obs = .paired ↔
      cellMerged ref cell = false ∧ ref.complete = true ∧ cell.complete = true ∧ sameToolchain ref cell = true ∧
        rowPooled ref cell obs = true := by
  unfold rowUse
  by_cases h : cellMerged ref cell = true
  · simp [h]
  · have h' : cellMerged ref cell = false := by simpa using h
    by_cases p : (ref.complete && cell.complete && sameToolchain ref cell && rowPooled ref cell obs) = true
    · simp only [h', p]; simp at p; simp [p]
    · simp only [h', p]; simp at p ⊢; intro a b c; exact p a b c

theorem hw_differs_not_direct (ref cell : PlatformKey) (obs : List Obs) (h : ref.hw ≠ cell.hw) :
    rowUse ref cell obs ≠ .direct := by
  intro e
  have := (rowUse_direct_iff ref cell obs).1 e
  rw [cellMerged_hw_refused ref cell h] at this
  cases this

theorem rowUse_unpaired_refused (ref cell : PlatformKey) (obs : List Obs) (h : cellMerged ref cell = false)
    (hp : rowPooled ref cell obs = false) : rowUse ref cell obs = .refused := by
  simp [rowUse, h, hp]

theorem rowUse_toolchain_refused (ref cell : PlatformKey) (obs : List Obs) (h : cellMerged ref cell = false)
    (ht : sameToolchain ref cell = false) : rowUse ref cell obs = .refused := by
  simp [rowUse, h, ht]

theorem rowUse_xcode_not_paired (ref cell : PlatformKey) (obs : List Obs) (h : ref.xcodeBuild ≠ cell.xcodeBuild) :
    rowUse ref cell obs ≠ .paired := by
  intro e
  have := ((rowUse_paired_iff ref cell obs).1 e).2.2.2.1
  simp [sameToolchain] at this
  exact h this.1.2

theorem rowUse_macos_not_paired (ref cell : PlatformKey) (obs : List Obs) (h : ref.macosBuild ≠ cell.macosBuild) :
    rowUse ref cell obs ≠ .paired := by
  intro e
  have := ((rowUse_paired_iff ref cell obs).1 e).2.2.2.1
  simp [sameToolchain] at this
  exact h this.1.1

theorem rowUse_runtime_not_paired (ref cell : PlatformKey) (obs : List Obs) (h : ref.runtimeBuild ≠ cell.runtimeBuild) :
    rowUse ref cell obs ≠ .paired := by
  intro e
  have := ((rowUse_paired_iff ref cell obs).1 e).2.2.2.1
  simp [sameToolchain] at this
  exact h this.2

theorem rowUse_incomplete_ref_refused (ref cell : PlatformKey) (obs : List Obs) (h : cellMerged ref cell = false)
    (hc : ref.complete = false) : rowUse ref cell obs = .refused := by
  simp [rowUse, h, hc]

theorem rowUse_few_pairs_refused (ref cell : PlatformKey) (obs : List Obs) (h : cellMerged ref cell = false)
    (hn : obs.length < kReq) : rowUse ref cell obs = .refused :=
  rowUse_unpaired_refused ref cell obs h (pooled_too_few ref cell obs hn)

theorem rowUse_disagree_refused (ref cell : PlatformKey) (obs : List Obs) (o : Obs) (h : cellMerged ref cell = false)
    (ho : o ∈ obs) (hd : o.gh ≠ o.cm) : rowUse ref cell obs = .refused :=
  rowUse_unpaired_refused ref cell obs h (pooled_disagree ref cell obs o ho hd)

def pairedClass : List Obs → RowClass
  | [] => .deterministic
  | o :: os => (pairedClass os).worse (o.gh.worse o.cm)

theorem pairedClass_ge (obs : List Obs) (o : Obs) (ho : o ∈ obs) :
    o.gh.rank ≤ (pairedClass obs).rank ∧ o.cm.rank ≤ (pairedClass obs).rank := by
  induction obs with
  | nil => cases ho
  | cons x xs ih =>
    have hx := worse_ge_right (pairedClass xs) (x.gh.worse x.cm)
    have h1 := worse_ge_left x.gh x.cm
    have h2 := worse_ge_right x.gh x.cm
    simp only [pairedClass]
    rcases List.mem_cons.1 ho with rfl | h
    · omega
    · have := ih h
      have h3 := worse_ge_left (pairedClass xs) (x.gh.worse x.cm)
      omega

def rowsUse (ref cell : PlatformKey) (rows : List (String × List Obs)) : List (String × Use) :=
  rows.map fun r => (r.1, rowUse ref cell r.2)

theorem rowsUse_mem (ref cell : PlatformKey) (rows : List (String × List Obs)) (n : String) (u : Use) :
    (n, u) ∈ rowsUse ref cell rows ↔ ∃ obs, (n, obs) ∈ rows ∧ u = rowUse ref cell obs := by
  simp only [rowsUse, List.mem_map, Prod.mk.injEq]
  constructor
  · rintro ⟨⟨a, b⟩, h, rfl, rfl⟩; exact ⟨b, h, rfl⟩
  · rintro ⟨obs, h, rfl⟩; exact ⟨(n, obs), h, rfl, rfl⟩

theorem rowsUse_length (ref cell : PlatformKey) (rows : List (String × List Obs)) :
    (rowsUse ref cell rows).length = rows.length := by simp [rowsUse]

def pairsAffordable (used k : Nat) : Bool := decide (used + k * Codemagic.maxCapMin ≤ Codemagic.stopAt)

def pairsReachable (used : Nat) : Nat := min kReq ((Codemagic.stopAt - used) / Codemagic.maxCapMin)

theorem k3_fits_166 : pairsAffordable 166 kReq = true := by decide

theorem k5_fits_166 : pairsAffordable 166 5 = true := by decide

theorem k6_over_166 : pairsAffordable 166 6 = false := by decide

theorem pairsAffordable_mono (u v k : Nat) (h : u ≤ v) (hv : pairsAffordable v k = true) : pairsAffordable u k = true := by
  simp only [pairsAffordable, decide_eq_true_eq] at hv ⊢; omega

theorem pairsAffordable_pred (u k : Nat) (h : pairsAffordable u (k + 1) = true) : pairsAffordable u k = true := by
  simp only [pairsAffordable, decide_eq_true_eq, Nat.add_mul] at h ⊢; omega

theorem pairsReachable_le (used : Nat) : pairsReachable used ≤ kReq := Nat.min_le_left _ _

theorem pairsReachable_affordable (used : Nat) (hu : used ≤ Codemagic.stopAt) : pairsAffordable used (pairsReachable used) = true := by
  simp only [pairsAffordable, pairsReachable, Codemagic.maxCapMin, Codemagic.stopAt, kReq] at hu ⊢
  apply decide_eq_true
  have h3 : (400 - used) / 40 * 40 ≤ 400 - used := Nat.div_mul_le_self (400 - used) 40
  generalize (400 - used) / 40 = q at h3 ⊢
  rcases Nat.le_total 3 q with h | h
  · rw [Nat.min_eq_left h]; omega
  · rw [Nat.min_eq_right h]; omega

theorem pairsReachable_full (used : Nat) (h : pairsAffordable used kReq = true) : pairsReachable used = kReq := by
  simp [pairsAffordable, pairsReachable, Codemagic.maxCapMin, Codemagic.stopAt, kReq] at h ⊢
  have : 3 ≤ (400 - used) / 40 := (Nat.le_div_iff_mul_le (show 0 < 40 by omega)).2 (by omega)
  exact Nat.min_eq_left this

def rerouteAfterS : Nat := 300

structure Queued where
  req : Req
  queuedS : Nat
  runCells : Nat
deriving DecidableEq, Repr

def Queued.movable (q : Queued) : Bool := decide (rerouteAfterS ≤ q.queuedS) && q.runCells == 1

def rerouteReqs (qs : List Queued) : List Req := (qs.filter Queued.movable).map (·.req)

def reroutePlan (c : Cfg) (qs : List Queued) (s : State) : List (Req × Decision) × State := step c (rerouteReqs qs) s

def rerouteMoved (c : Cfg) (qs : List Queued) (s : State) : List (Req × Decision) :=
  (reroutePlan c qs s).1.filter fun x => x.2.isCm

theorem reroute_only_movable (qs : List Queued) (r : Req) (h : r ∈ rerouteReqs qs) : ∃ q ∈ qs, q.movable = true ∧ q.req = r := by
  simp only [rerouteReqs, List.mem_map, List.mem_filter] at h
  obtain ⟨q, ⟨hq, ha⟩, he⟩ := h
  exact ⟨q, hq, ha, he⟩

theorem reroute_none_young (qs : List Queued) (h : ∀ q ∈ qs, q.queuedS < rerouteAfterS) : rerouteReqs qs = [] := by
  simp only [rerouteReqs]
  have : qs.filter Queued.movable = [] := by
    apply List.filter_eq_nil_iff.2
    intro q hq
    have h1 : ¬ rerouteAfterS ≤ q.queuedS := Nat.not_le.2 (h q hq)
    simp [Queued.movable, h1]
  simp [this]

theorem reroute_none_shared (qs : List Queued) (h : ∀ q ∈ qs, q.runCells ≠ 1) : rerouteReqs qs = [] := by
  simp only [rerouteReqs]
  have : qs.filter Queued.movable = [] := by
    apply List.filter_eq_nil_iff.2
    intro q hq
    have h1 := h q hq
    simp [Queued.movable, h1]
  simp [this]

theorem movable_iff (q : Queued) : q.movable = true ↔ rerouteAfterS ≤ q.queuedS ∧ q.runCells = 1 := by
  simp [Queued.movable]

theorem reroute_budget (c : Cfg) (qs : List Queued) (s : State) (h : s.cmUsed ≤ Codemagic.stopAt) :
    s.cmUsed + c.cmCapMin * cmCount (reroutePlan c qs s).1 ≤ Codemagic.stopAt :=
  cm_cells_budget c (rerouteReqs qs) s h

theorem reroute_slots (c : Cfg) (qs : List Queued) (s : State) (h : Inv c s) :
    s.cmBusy + cmCount (reroutePlan c qs s).1 ≤ c.cmConc :=
  cm_cells_slots c (rerouteReqs qs) s h

theorem reroute_inv (c : Cfg) (qs : List Queued) (s : State) (h : Inv c s) : Inv c (reroutePlan c qs s).2 :=
  step_inv c (rerouteReqs qs) s h

theorem reroute_cap_7 (qs : List Queued) (s : State) (h : Inv pool7 s) : inflight (reroutePlan pool7 qs s).2 ≤ 7 :=
  cap_7 (rerouteReqs qs) s h

theorem reroute_gh_free_stays (c : Cfg) (r : Req) (s : State) (hg : Fallback.ghOk c.base (s.fb c) = true) (cls : String)
    (e : Engine) (m : Nat) : route c r s ≠ .codemagic cls e m := by
  intro h
  have := ((route_cm_iff c r s cls e m).1 h).2.1
  rw [hg] at this
  cases this

theorem reroute_stale_stays (c : Cfg) (r : Req) (s : State) (hc : r.current = false) (cls : String) (e : Engine) (m : Nat) :
    route c r s ≠ .codemagic cls e m := by
  intro h
  have := ((route_cm_iff c r s cls e m).1 h).1
  rw [hc] at this
  cases this

theorem reroute_ghOnly_stays (c : Cfg) (r : Req) (s : State) (hg : c.base.ghOnly.contains r.lane = true) (cls : String)
    (e : Engine) (m : Nat) : route c r s ≠ .codemagic cls e m := by
  intro h
  have := ((route_cm_iff c r s cls e m).1 h).2.2.1
  simp [cmOk] at this
  exact this.1.1.1.2 (by simpa using hg)

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

private def refK : PlatformKey := ⟨"26A434", "27A9275", "24A434", ghHw⟩
private def cmK : PlatformKey := ⟨"26A434", "27A9275", "24A434", cmHw⟩
private def ob (g c : RowClass) (n : Nat := 0) : Obs := ⟨g, c, refK, cmK, s!"gh{n}", s!"cm{n}", "abc", "abc"⟩

#guard rowUse refK cmK [] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, ob .deterministic .deterministic 2] == .paired
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, ob .stable .deterministic 2] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, { ob .stable .stable 2 with cmKey.hw := ghHw }] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 0, ob .stable .stable 0] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, { ob .stable .stable 2 with ghRun := "gh0" }] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, { ob .stable .stable 2 with cmBuild := "cm0" }] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, { ob .stable .stable 2 with cmSha := "def" }] == .refused
#guard rowUse refK cmK [ob .stable .stable 0, ob .stable .stable 1, { ob .stable .stable 2 with ghSha := "", cmSha := "" }] == .refused
#guard rowUse refK { cmK with xcodeBuild := "27A1" } [ob .stable .stable 0, ob .stable .stable 1, ob .stable .stable 2] == .refused
#guard rowUse refK refK [] == .direct
#guard pairedClass [ob .stable .stable 0, ob .deterministic .deterministic 1, ob .stable .stable 2] == .stable
#guard pairedClass [ob .quarantined .quarantined 0, ob .deterministic .deterministic 1] == .quarantined
#guard pairsReachable 166 == 3
#guard pairsReachable 280 == 3
#guard pairsReachable 281 == 2
#guard pairsReachable 361 == 0
#guard (reroutePlan pool7 [⟨rq "webkit-sim", 300, 1⟩, ⟨rq "webkit-sim" 1, 299, 1⟩] { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 }).1.map (·.2.isCm) == [true]
#guard (reroutePlan pool7 [⟨rq "webkit-sim", 300, 1⟩, ⟨rq "webkit-sim" 1, 400, 1⟩] { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 }).1.map (·.2.isCm) == [true, false]
#guard (reroutePlan pool7 [⟨rq "webkit-sim", 900, 2⟩] { idle with base.ghMacBusy := 5, base.ghTotalBusy := 5 }).1.map (·.2.isCm) == []
#guard (reroutePlan pool7 [⟨rq "webkit-sim", 900, 1⟩] idle).1.map (·.2.isCm) == [false]

end Fw.Ci.PoolTier
