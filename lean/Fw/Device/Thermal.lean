import Lean.Data.Json
import Fw.Device.PhoneArms
/-!
# The phone thermal check
Gate, pause and resume rules of `packages/measure-webkit/src/device-thermal.mjs`.
-/
namespace Fw.Device.Thermal
open Lean
open Fw.Device.PhoneArms (coolOk coolMin)

inductive Thermal where
  | nominal | fair | serious | critical
  deriving DecidableEq

def Thermal.name : Thermal → String
  | .nominal => "Nominal" | .fair => "Fair" | .serious => "Serious" | .critical => "Critical"

def Thermal.ofName : String → Option Thermal
  | "Nominal" => some .nominal | "Fair" => some .fair | "Serious" => some .serious | "Critical" => some .critical
  | _ => none

theorem ofName_name (t : Thermal) : Thermal.ofName t.name = some t := by
  cases t <;> rfl

def tempMarginC : Nat := 2

inductive Lock where
  | unlocked | locked | unknown
  deriving DecidableEq

def Lock.name : Lock → String
  | .unlocked => "unlocked" | .locked => "locked" | .unknown => "unknown"

def lockOf : Option Bool → Lock
  | some true => .locked
  | some false => .unlocked
  | none => .unknown

inductive Verdict where
  | go
  | locked
  | thermal
  | battery
  | unreadable
  deriving DecidableEq

def Verdict.name : Verdict → String
  | .go => "go" | .locked => "locked" | .thermal => "thermal" | .battery => "battery" | .unreadable => "unreadable"

def gate (th : Option Thermal) (temp first : Option Nat) : Verdict :=
  match th with
  | none => .unreadable
  | some t =>
    if t ≠ .nominal then .thermal
    else match temp, first with
      | some c, some f => if f + tempMarginC ≤ c then .battery else .go
      | _, _ => .go

def preflight (lock : Lock) (th : Option Thermal) (temp first : Option Nat) : Verdict :=
  if lock = .locked then .locked else gate th temp first

theorem gate_unreadable (temp first : Option Nat) : gate none temp first = .unreadable := rfl

theorem gate_fair (temp first : Option Nat) : gate (some .fair) temp first = .thermal := by
  simp [gate]

theorem gate_serious (temp first : Option Nat) : gate (some .serious) temp first = .thermal := by
  simp [gate]

theorem gate_critical (temp first : Option Nat) : gate (some .critical) temp first = .thermal := by
  simp [gate]

theorem gate_battery {c f : Nat} (h : f + tempMarginC ≤ c) : gate (some .nominal) (some c) (some f) = .battery := by
  simp [gate, h]

theorem gate_go {c f : Nat} (h : c < f + tempMarginC) : gate (some .nominal) (some c) (some f) = .go := by
  have : ¬ f + tempMarginC ≤ c := by omega
  simp [gate, this]

theorem gate_go_blind (temp first : Option Nat) (h : temp = none ∨ first = none) : gate (some .nominal) temp first = .go := by
  rcases h with rfl | rfl
  · cases first <;> simp [gate]
  · cases temp <;> simp [gate]

theorem gate_go_iff (th : Option Thermal) (temp first : Option Nat) :
    gate th temp first = .go ↔ th = some .nominal ∧ ∀ c f, temp = some c → first = some f → c < f + tempMarginC := by
  cases th with
  | none => simp [gate]
  | some t =>
    cases t <;> simp [gate]
    cases temp <;> cases first <;> simp

theorem preflight_locked (th : Option Thermal) (temp first : Option Nat) : preflight .locked th temp first = .locked := by
  simp [preflight]

theorem preflight_open {lock : Lock} (h : lock ≠ .locked) (th : Option Thermal) (temp first : Option Nat) :
    preflight lock th temp first = gate th temp first := by
  simp [preflight, h]

def passesRun : List Verdict → Nat
  | [] => 0
  | .go :: rs => passesRun rs + 1
  | _ :: _ => 0

theorem passesRun_nil : passesRun [] = 0 := rfl

theorem passesRun_all_go : ∀ rs : List Verdict, (∀ v ∈ rs, v = .go) → passesRun rs = rs.length
  | [], _ => rfl
  | r :: rs, h => by
    have hr : r = .go := h r (by simp)
    subst hr
    have := passesRun_all_go rs (fun v hv => h v (by simp [hv]))
    simp [passesRun, this]

theorem passesRun_le_stop : ∀ (rs : List Verdict) (k : Nat) (v : Verdict), rs[k]? = some v → v ≠ .go → passesRun rs ≤ k
  | [], k, v, h, _ => by simp at h
  | r :: rs, 0, v, h, hv => by
    simp at h
    subst h
    cases r <;> simp_all [passesRun]
  | r :: rs, k + 1, v, h, hv => by
    have ih := passesRun_le_stop rs k v (by simpa using h) hv
    cases r <;> simp [passesRun] <;> omega

def blockPasses (rd : List (Option Thermal × Option Nat)) (first : Option Nat) : Nat :=
  passesRun (rd.map fun r => gate r.1 r.2 first)

theorem blockPasses_le_serious {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {c : Option Nat}
    (h : rd[k]? = some (some .serious, c)) : blockPasses rd first ≤ k := by
  refine passesRun_le_stop _ k .thermal (by simp [h, gate]) (by decide)

theorem blockPasses_le_critical {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {c : Option Nat}
    (h : rd[k]? = some (some .critical, c)) : blockPasses rd first ≤ k := by
  refine passesRun_le_stop _ k .thermal (by simp [h, gate]) (by decide)

theorem blockPasses_one_after_trigger {rd : List (Option Thermal × Option Nat)} {first : Option Nat} {k : Nat} {r : Option Thermal × Option Nat}
    (h : rd[k]? = some r) (hv : gate r.1 r.2 first ≠ .go) : blockPasses rd first ≤ k :=
  passesRun_le_stop _ k _ (by simp [h]) hv

def calmFrom (p : Nat) (rs : List (Nat × Verdict)) : Nat :=
  rs.foldl (fun c r => if r.2 = .go then c else r.1) p

theorem calmFrom_snoc_bad (p t : Nat) (rs : List (Nat × Verdict)) {v : Verdict} (h : v ≠ .go) :
    calmFrom p (rs ++ [(t, v)]) = t := by
  simp [calmFrom, List.foldl_append, h]

theorem calmFrom_snoc_go (p t : Nat) (rs : List (Nat × Verdict)) :
    calmFrom p (rs ++ [(t, .go)]) = calmFrom p rs := by
  simp [calmFrom, List.foldl_append]

def resume (now p : Nat) (rs : List (Nat × Verdict)) : Bool :=
  match rs.getLast? with
  | some (_, .go) => coolOk (now - calmFrom p rs)
  | _ => false

theorem resume_needs_go {now p : Nat} {rs : List (Nat × Verdict)} (h : resume now p rs = true) :
    ∃ t, rs.getLast? = some (t, .go) := by
  unfold resume at h
  split at h
  · rename_i t _; exact ⟨t, by assumption⟩
  · simp at h

theorem resume_needs_gap {now p : Nat} {rs : List (Nat × Verdict)} (h : resume now p rs = true) :
    coolMin * 60 ≤ now - calmFrom p rs := by
  unfold resume at h
  split at h
  · exact of_decide_eq_true h
  · simp at h

theorem resume_after_bad {now p t : Nat} {rs : List (Nat × Verdict)} {v : Verdict} (hv : v ≠ .go) :
    resume now p (rs ++ [(t, v)]) = false := by
  unfold resume
  simp
  cases v <;> simp_all

theorem resume_too_soon {now p : Nat} {rs : List (Nat × Verdict)} (h : now - calmFrom p rs < coolMin * 60) :
    resume now p rs = false := by
  cases hr : resume now p rs
  · rfl
  · have := resume_needs_gap hr
    omega

def pollS : Nat := 60

def pauseMaxS : Nat := 3600

def pauseOver (pausedS nowS : Nat) : Bool := decide (pausedS + pauseMaxS ≤ nowS)

theorem pauseOver_iff (p n : Nat) : pauseOver p n = true ↔ p + 3600 ≤ n := by
  unfold pauseOver pauseMaxS
  exact decide_eq_true_iff

theorem pauseOver_not_before {p n : Nat} (h : n < p + 3600) : pauseOver p n = false := by
  have : ¬ p + pauseMaxS ≤ n := by simp [pauseMaxS]; omega
  simp [pauseOver, this]

def Thermal.rank : Thermal → Nat
  | .nominal => 0 | .fair => 1 | .serious => 2 | .critical => 3

def pinTarget (t : Thermal) : Bool := decide (t = .fair ∨ t = .serious)

def Thermal.profile : Thermal → Option String
  | .fair => some "ThermalFair" | .serious => some "ThermalSerious" | _ => none

def pinWaitMaxS : Nat := 180

def pinPollS : Nat := 5

def stopGraceS : Nat := 15

def killGraceS : Nat := 5

def clearWaitMaxS : Nat := 300

theorem profile_isSome_iff (t : Thermal) : (Thermal.profile t).isSome = pinTarget t := by
  cases t <;> simp [Thermal.profile, pinTarget]

inductive Why where
  | badTarget | locked | notHeld | unreadable | critical | above | below | rising | timeout | onTarget
  deriving DecidableEq

def Why.name : Why → String
  | .badTarget => "badTarget" | .locked => "locked" | .notHeld => "notHeld" | .unreadable => "unreadable"
  | .critical => "critical" | .above => "above" | .below => "below" | .rising => "rising" | .timeout => "timeout"
  | .onTarget => "onTarget"

inductive Pin where
  | go | wait | stop
  deriving DecidableEq

def Pin.name : Pin → String
  | .go => "go" | .wait => "wait" | .stop => "stop"

def Why.pin : Why → Pin
  | .onTarget => .go
  | .unreadable | .rising => .wait
  | _ => .stop

def pinWhy (target : Thermal) (held : Bool) (lock : Lock) (obs : Option Thermal) (entered : Bool) (waitedS : Nat) : Why :=
  if ¬ pinTarget target then .badTarget
  else if lock = .locked then .locked
  else if ¬ held then .notHeld
  else match obs with
    | none => if waitedS < pinWaitMaxS then .unreadable else .timeout
    | some o =>
      if o = .critical then .critical
      else if target.rank < o.rank then .above
      else if o = target then .onTarget
      else if entered then .below
      else if waitedS < pinWaitMaxS then .rising else .timeout

def pinGate (target : Thermal) (held : Bool) (lock : Lock) (obs : Option Thermal) (entered : Bool) (waitedS : Nat) : Pin :=
  (pinWhy target held lock obs entered waitedS).pin

theorem why_badTarget {t : Thermal} (h : pinTarget t = false) (held : Bool) (lock : Lock) (o : Option Thermal) (e : Bool) (w : Nat) :
    pinWhy t held lock o e w = .badTarget := by
  simp [pinWhy, h]

theorem why_locked {t : Thermal} (h : pinTarget t = true) (held : Bool) (o : Option Thermal) (e : Bool) (w : Nat) :
    pinWhy t held .locked o e w = .locked := by
  simp [pinWhy, h]

theorem why_notHeld {t : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (o : Option Thermal) (e : Bool) (w : Nat) :
    pinWhy t false lock o e w = .notHeld := by
  simp [pinWhy, h, hl]

theorem why_unreadable {t : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (e : Bool) {w : Nat} (hw : w < pinWaitMaxS) :
    pinWhy t true lock none e w = .unreadable := by
  simp [pinWhy, h, hl, hw]

theorem why_unreadable_timeout {t : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (e : Bool) {w : Nat} (hw : pinWaitMaxS ≤ w) :
    pinWhy t true lock none e w = .timeout := by
  have : ¬ w < pinWaitMaxS := by omega
  simp [pinWhy, h, hl, this]

theorem why_critical {t : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (e : Bool) (w : Nat) :
    pinWhy t true lock (some .critical) e w = .critical := by
  simp [pinWhy, h, hl]

theorem why_above {t o : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (ho : o ≠ .critical)
    (hr : t.rank < o.rank) (e : Bool) (w : Nat) : pinWhy t true lock (some o) e w = .above := by
  simp [pinWhy, h, hl, ho, hr]

theorem why_onTarget {t : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (e : Bool) (w : Nat) :
    pinWhy t true lock (some t) e w = .onTarget := by
  have hc : t ≠ .critical := by intro hc; subst hc; simp [pinTarget] at h
  have hr : ¬ t.rank < t.rank := Nat.lt_irrefl _
  simp [pinWhy, h, hl, hc, hr]

theorem rank_lt_ne {t o : Thermal} (hr : o.rank < t.rank) (h : pinTarget t = true) : o ≠ .critical ∧ ¬ t.rank < o.rank ∧ o ≠ t := by
  cases t <;> cases o <;> simp_all [Thermal.rank, pinTarget]

theorem why_below_entered {t o : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (hr : o.rank < t.rank) (w : Nat) :
    pinWhy t true lock (some o) true w = .below := by
  obtain ⟨hc, hn, ho⟩ := rank_lt_ne hr h
  simp [pinWhy, h, hl, hc, hn, ho]

theorem why_rising {t o : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (hr : o.rank < t.rank) {w : Nat} (hw : w < pinWaitMaxS) :
    pinWhy t true lock (some o) false w = .rising := by
  obtain ⟨hc, hn, ho⟩ := rank_lt_ne hr h
  simp [pinWhy, h, hl, hc, hn, ho, hw]

theorem why_rising_timeout {t o : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (hr : o.rank < t.rank) {w : Nat} (hw : pinWaitMaxS ≤ w) :
    pinWhy t true lock (some o) false w = .timeout := by
  obtain ⟨hc, hn, ho⟩ := rank_lt_ne hr h
  have hw' : ¬ w < pinWaitMaxS := by omega
  simp [pinWhy, h, hl, hc, hn, ho, hw']

theorem pinGate_go_iff (t : Thermal) (held : Bool) (lock : Lock) (o : Option Thermal) (e : Bool) (w : Nat) :
    pinGate t held lock o e w = .go ↔ pinTarget t = true ∧ lock ≠ .locked ∧ held = true ∧ o = some t := by
  by_cases hw : w < pinWaitMaxS <;>
  rcases o with _ | x <;> (try cases x) <;> cases t <;> cases held <;> cases e <;> cases lock <;>
  simp [pinGate, pinWhy, pinTarget, Thermal.rank, Why.pin, hw]

theorem pinGate_critical (t : Thermal) (held : Bool) (lock : Lock) (e : Bool) (w : Nat) :
    pinGate t held lock (some .critical) e w = .stop := by
  cases t <;> cases held <;> cases lock <;> simp [pinGate, pinWhy, pinTarget, Why.pin]

theorem pinGate_notHeld (t : Thermal) (lock : Lock) (o : Option Thermal) (e : Bool) (w : Nat) : pinGate t false lock o e w ≠ .go := by
  intro h
  have := (pinGate_go_iff t false lock o e w).1 h
  simp at this

theorem pinGate_below_entered {t o : Thermal} (h : pinTarget t = true) {lock : Lock} (hl : lock ≠ .locked) (hr : o.rank < t.rank) (w : Nat) :
    pinGate t true lock (some o) true w = .stop := by
  simp [pinGate, why_below_entered h hl hr w, Why.pin]

theorem pinGate_wait_lt {t : Thermal} {held : Bool} {lock : Lock} {o : Option Thermal} {e : Bool} {w : Nat}
    (h : pinGate t held lock o e w = .wait) : w < pinWaitMaxS := by
  by_cases hw : w < pinWaitMaxS
  · exact hw
  · exfalso
    revert h
    rcases o with _ | x <;> (try cases x) <;> cases t <;> cases held <;> cases e <;> cases lock <;>
    simp [pinGate, pinWhy, pinTarget, Thermal.rank, Why.pin, hw]

def lanesRun : List Pin → Nat
  | [] => 0
  | .go :: ps => lanesRun ps + 1
  | _ :: _ => 0

theorem lanesRun_le_stop : ∀ (ps : List Pin) (k : Nat) (v : Pin), ps[k]? = some v → v ≠ .go → lanesRun ps ≤ k
  | [], k, v, h, _ => by simp at h
  | p :: ps, 0, v, h, hv => by
    simp at h
    subst h
    cases p <;> simp_all [lanesRun]
  | p :: ps, k + 1, v, h, hv => by
    have ih := lanesRun_le_stop ps k v (by simpa using h) hv
    cases p <;> simp [lanesRun] <;> omega

theorem lanesRun_go : ∀ (ps : List Pin) (k : Nat), k < lanesRun ps → ps[k]? = some .go
  | [], k, h => by simp [lanesRun] at h
  | p :: ps, k, h => by
    cases p <;> simp [lanesRun] at h
    cases k with
    | zero => simp
    | succ k => simpa using lanesRun_go ps k (by omega)

abbrev Rd := Bool × Lock × Option Thermal

def laneGates (target : Thermal) (rs : List Rd) : List Pin :=
  rs.map fun r => pinGate target r.1 r.2.1 r.2.2 true 0

theorem lane_on_target (target : Thermal) (rs : List Rd) (k : Nat) (h : k < lanesRun (laneGates target rs)) :
    ∃ r, rs[k]? = some r ∧ r.1 = true ∧ r.2.2 = some target := by
  have hk := lanesRun_go _ k h
  simp only [laneGates, List.getElem?_map] at hk
  cases hr : rs[k]? with
  | none => simp [hr] at hk
  | some r =>
    refine ⟨r, rfl, ?_⟩
    simp only [hr, Option.map_some, Option.some.injEq] at hk
    have := (pinGate_go_iff target r.1 r.2.1 r.2.2 true 0).1 hk
    exact ⟨this.2.2.1, this.2.2.2⟩

def visitOk (ps : List Pin) : Bool := decide (ps.length = 3) && ps.all (· == .go)

theorem visitOk_iff (ps : List Pin) : visitOk ps = true ↔ ps.length = 3 ∧ ∀ p ∈ ps, p = .go := by
  simp [visitOk]

theorem visitOk_refuses {ps : List Pin} {p : Pin} (hp : p ∈ ps) (h : p ≠ .go) : visitOk ps = false := by
  cases hv : visitOk ps
  · rfl
  · exact absurd ((visitOk_iff ps).1 hv).2 (fun a => h (a p hp))

def blockValid (target : Thermal) (rs : List (Option Thermal)) : Bool :=
  pinTarget target && rs.all (· == some target)

theorem blockValid_iff (t : Thermal) (rs : List (Option Thermal)) :
    blockValid t rs = true ↔ pinTarget t = true ∧ ∀ o ∈ rs, o = some t := by
  simp [blockValid]

theorem blockValid_critical {t : Thermal} {rs : List (Option Thermal)} (h : some Thermal.critical ∈ rs) : blockValid t rs = false := by
  cases hv : blockValid t rs
  · rfl
  · have := (blockValid_iff t rs).1 hv
    have hc := this.2 _ h
    have : t = .critical := by simpa using hc.symm
    subst this
    simp [pinTarget] at *

theorem blockValid_off_target {t : Thermal} {rs : List (Option Thermal)} {o : Option Thermal} (h : o ∈ rs) (ho : o ≠ some t) :
    blockValid t rs = false := by
  cases hv : blockValid t rs
  · rfl
  · exact absurd (((blockValid_iff t rs).1 hv).2 o h) ho

inductive Sent where
  | none | term | kill
  deriving DecidableEq

def Sent.name : Sent → String
  | .none => "none" | .term => "term" | .kill => "kill"

inductive StopAct where
  | done | term | wait | kill | stuck
  deriving DecidableEq

def StopAct.name : StopAct → String
  | .done => "done" | .term => "term" | .wait => "wait" | .kill => "kill" | .stuck => "stuck"

def stopAct (alive : Bool) (sent : Sent) (sinceS : Nat) : StopAct :=
  if ¬ alive then .done
  else match sent with
    | .none => .term
    | .term => if sinceS < stopGraceS then .wait else .kill
    | .kill => if sinceS < killGraceS then .wait else .stuck

theorem stopAct_done_iff (alive : Bool) (sent : Sent) (s : Nat) : stopAct alive sent s = .done ↔ alive = false := by
  cases alive <;> cases sent <;> simp [stopAct] <;> split <;> simp

theorem stopAct_term_first (s : Nat) : stopAct true .none s = .term := rfl

theorem stopAct_no_kill_before_term (alive : Bool) (s : Nat) : stopAct alive .none s ≠ .kill := by
  cases alive <;> simp [stopAct]

theorem stopAct_wait_term {s : Nat} (h : s < stopGraceS) : stopAct true .term s = .wait := by
  simp [stopAct, h]

theorem stopAct_kill {s : Nat} (h : stopGraceS ≤ s) : stopAct true .term s = .kill := by
  have : ¬ s < stopGraceS := by omega
  simp [stopAct, this]

theorem stopAct_wait_kill {s : Nat} (h : s < killGraceS) : stopAct true .kill s = .wait := by
  simp [stopAct, h]

theorem stopAct_stuck {s : Nat} (h : killGraceS ≤ s) : stopAct true .kill s = .stuck := by
  have : ¬ s < killGraceS := by omega
  simp [stopAct, this]

inductive Phase where
  | idle | starting | held | stopping | stopped
  deriving DecidableEq

def Phase.name : Phase → String
  | .idle => "idle" | .starting => "starting" | .held => "held" | .stopping => "stopping" | .stopped => "stopped"

def Phase.mayBeAlive : Phase → Bool
  | .idle | .stopped => false
  | .starting | .held | .stopping => true

inductive Close where
  | nothing | stopOwner
  deriving DecidableEq

def Close.name : Close → String
  | .nothing => "nothing" | .stopOwner => "stopOwner"

def closeAct (p : Phase) : Close := if p.mayBeAlive then .stopOwner else .nothing

theorem closeAct_alive {p : Phase} (h : p.mayBeAlive = true) : closeAct p = .stopOwner := by
  simp [closeAct, h]

theorem closeAct_iff (p : Phase) : closeAct p = .stopOwner ↔ p.mayBeAlive = true := by
  cases p <;> simp [closeAct, Phase.mayBeAlive]

inductive End where
  | cleared | heatRemains | unread | unconfirmed | stuck
  deriving DecidableEq

def End.name : End → String
  | .cleared => "cleared" | .heatRemains => "heatRemains" | .unread => "unread" | .unconfirmed => "unconfirmed" | .stuck => "stuck"

def endVerdict (target : Thermal) (ownerGone acked : Bool) (back : Option Thermal) : End :=
  if ¬ ownerGone then .stuck
  else if ¬ acked then .unconfirmed
  else match back with
    | none => .unread
    | some b => if b.rank < target.rank then .cleared else .heatRemains

def conditionSet (ownerGone acked : Bool) : Bool := !(ownerGone && acked)

theorem endVerdict_stuck_iff (t : Thermal) (g a : Bool) (b : Option Thermal) : endVerdict t g a b = .stuck ↔ g = false := by
  cases g <;> cases a <;> cases b <;> simp [endVerdict] <;> split <;> simp

theorem endVerdict_unconfirmed_iff (t : Thermal) (g a : Bool) (b : Option Thermal) : endVerdict t g a b = .unconfirmed ↔ g = true ∧ a = false := by
  cases g <;> cases a <;> cases b <;> simp [endVerdict] <;> split <;> simp

theorem endVerdict_unset {t : Thermal} {g a : Bool} {b : Option Thermal} (h1 : endVerdict t g a b ≠ .stuck) (h2 : endVerdict t g a b ≠ .unconfirmed) : conditionSet g a = false := by
  have e1 : ¬ g = false := fun h => h1 ((endVerdict_stuck_iff t g a b).2 h)
  have e2 : ¬ (g = true ∧ a = false) := fun h => h2 ((endVerdict_unconfirmed_iff t g a b).2 h)
  cases g <;> cases a <;> simp_all [conditionSet]

theorem endVerdict_set {t : Thermal} {g a : Bool} {b : Option Thermal} (h : conditionSet g a = true) : endVerdict t g a b = .stuck ∨ endVerdict t g a b = .unconfirmed := by
  cases g <;> cases a <;> simp_all [conditionSet, endVerdict]

theorem endVerdict_cleared {t b : Thermal} (h : b.rank < t.rank) : endVerdict t true true (some b) = .cleared := by
  simp [endVerdict, h]

theorem endVerdict_heat {t b : Thermal} (h : ¬ b.rank < t.rank) : endVerdict t true true (some b) = .heatRemains := by
  simp [endVerdict, h]

theorem endVerdict_unread (t : Thermal) : endVerdict t true true none = .unread := rfl

inductive Recover where
  | nothing | stopOwner | clearCycle
  deriving DecidableEq

def Recover.name : Recover → String
  | .nothing => "nothing" | .stopOwner => "stopOwner" | .clearCycle => "clearCycle"

def recoverAct (hasRecord alive acked : Bool) : Recover :=
  if ¬ hasRecord then .nothing else if alive then .stopOwner else if acked then .nothing else .clearCycle

theorem recoverAct_alive {r a : Bool} (h : r = true) : recoverAct r true a = .stopOwner := by
  simp [recoverAct, h]

theorem recoverAct_unacked : recoverAct true false false = .clearCycle := rfl

theorem recoverAct_nothing_iff (r l a : Bool) : recoverAct r l a = .nothing ↔ (r = false ∨ (l = false ∧ a = true)) := by
  cases r <;> cases l <;> cases a <;> simp [recoverAct]

def clearWait (target : Thermal) (back : Option Thermal) (waitedS : Nat) : Bool :=
  decide (waitedS < clearWaitMaxS) && (match back with | some b => decide (¬ b.rank < target.rank) | none => true)

theorem clearWait_cleared {t b : Thermal} (h : b.rank < t.rank) (w : Nat) : clearWait t (some b) w = false := by
  simp [clearWait, h]

theorem clearWait_budget {t : Thermal} (b : Option Thermal) {w : Nat} (h : clearWaitMaxS ≤ w) : clearWait t b w = false := by
  have : ¬ w < clearWaitMaxS := by omega
  simp [clearWait, this]

def mayKill (recPid curPid : Nat) (recStart curStart : String) : Bool :=
  decide (recPid = curPid) && decide (recStart ≠ "") && decide (recStart = curStart)

theorem mayKill_iff (p q : Nat) (a b : String) : mayKill p q a b = true ↔ p = q ∧ a ≠ "" ∧ a = b := by
  simp [mayKill, and_assoc]

theorem mayKill_pid {p q : Nat} (h : p ≠ q) (a b : String) : mayKill p q a b = false := by
  simp [mayKill, h]

theorem mayKill_start {p : Nat} {a b : String} (h : a ≠ b) (q : Nat) : mayKill p q a b = false := by
  simp [mayKill, h]

theorem mayKill_blank (p q : Nat) (b : String) : mayKill p q "" b = false := by
  simp [mayKill]

section Golden

private def thJ : Option Thermal → Json
  | none => Json.null
  | some t => Json.str t.name

private def natJ : Option Nat → Json
  | none => Json.null
  | some n => toJson n

private def thCases : List (Option Thermal) := [none, some .nominal, some .fair, some .serious, some .critical]

private def tempCases : List (Option Nat × Option Nat) :=
  [(none, none), (some 33, none), (none, some 33), (some 33, some 33), (some 34, some 33), (some 35, some 33), (some 36, some 33),
   (some 30, some 33), (some 0, some 0), (some 1, some 0), (some 2, some 0)]

private def readingsCases : List (List (Option Thermal × Option Nat)) :=
  [[], [(some .nominal, some 33)], [(some .nominal, some 33), (some .nominal, some 34), (some .nominal, some 34)],
   [(some .nominal, some 33), (some .fair, some 34), (some .nominal, some 33)],
   [(some .nominal, some 33), (some .nominal, some 35), (some .nominal, some 33)],
   [(some .nominal, some 33), (some .nominal, some 33), (some .serious, some 34), (some .nominal, some 33)],
   [(some .critical, some 33), (some .nominal, some 33)], [(none, some 33), (some .nominal, some 33)],
   [(some .nominal, none), (some .nominal, none)]]

private def resumeCases : List (Nat × Nat × List (Nat × Verdict)) :=
  [(100, 0, []), (400, 0, [(100, .thermal)]), (399, 0, [(100, .thermal)]), (400, 0, [(100, .thermal), (200, .go)]),
   (500, 100, [(200, .thermal), (300, .go)]), (500, 100, [(200, .thermal), (300, .battery)]), (800, 0, [(200, .thermal), (300, .go), (400, .go)]),
   (800, 0, [(200, .thermal), (300, .go), (450, .thermal), (500, .go)]), (700, 0, [(200, .thermal), (300, .go), (450, .thermal), (500, .go)]),
   (800, 0, [(200, .thermal), (300, .unreadable)]), (500, 0, [(0, .go)]), (300, 0, [(0, .go)])]

private def verdictsJ (vs : List Verdict) : Json := Json.arr (vs.map fun v => Json.str v.name).toArray

private def baseLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("tempMarginC", tempMarginC), ("coolS", (coolMin * 60 : Nat)), ("pollS", pollS), ("pauseMaxS", pauseMaxS)]).compress] ++
  ([("Nominal"), "Fair", "Serious", "Critical", "nominal", "", "Unknown", "Nominal "].map fun (s : String) =>
    (Json.mkObj [("kind", "parse"), ("text", s), ("state", thJ (Thermal.ofName s))]).compress) ++
  ([some true, some false, none].map fun (b : Option Bool) =>
    (Json.mkObj [("kind", "lock"), ("passcodeRequired", match b with | none => Json.null | some x => Json.bool x), ("lock", (lockOf b).name)]).compress) ++
  (thCases.flatMap fun (th : Option Thermal) => tempCases.map fun (tf : Option Nat × Option Nat) =>
    (Json.mkObj [("kind", "gate"), ("state", thJ th), ("tempC", natJ tf.1), ("firstC", natJ tf.2), ("verdict", (gate th tf.1 tf.2).name)]).compress) ++
  ([Lock.unlocked, .locked, .unknown].flatMap fun (l : Lock) => [none, some Thermal.nominal, some .serious].map fun (th : Option Thermal) =>
    (Json.mkObj [("kind", "preflight"), ("lock", l.name), ("state", thJ th), ("tempC", natJ (some 33)), ("firstC", natJ (some 33)),
      ("verdict", (preflight l th (some 33) (some 33)).name)]).compress) ++
  (readingsCases.map fun (rd : List (Option Thermal × Option Nat)) =>
    (Json.mkObj [("kind", "block"), ("firstC", natJ (some 33)),
      ("readings", Json.arr (rd.map fun r => Json.mkObj [("state", thJ r.1), ("tempC", natJ r.2)]).toArray),
      ("verdicts", verdictsJ (rd.map fun r => gate r.1 r.2 (some 33))), ("passes", blockPasses rd (some 33))]).compress) ++
  ([(0, 0), (0, 3599), (0, 3600), (100, 3699), (100, 3700), (500, 100)].map fun (c : Nat × Nat) =>
    (Json.mkObj [("kind", "pause"), ("pausedS", c.1), ("nowS", c.2), ("over", pauseOver c.1 c.2)]).compress) ++
  (resumeCases.map fun (c : Nat × Nat × List (Nat × Verdict)) =>
    (Json.mkObj [("kind", "resume"), ("nowS", c.1), ("pausedS", c.2.1),
      ("readings", Json.arr (c.2.2.map fun r => Json.mkObj [("atS", r.1), ("verdict", r.2.name)]).toArray),
      ("resume", resume c.1 c.2.1 c.2.2)]).compress)

private def allThermal : List Thermal := [.nominal, .fair, .serious, .critical]

private def lockCases : List Lock := [.unlocked, .locked, .unknown]

private def boolJ (b : Bool) : Json := Json.bool b

private def pinCases : List (Thermal × Bool × Lock × Option Thermal × Bool × Nat) :=
  (allThermal.flatMap fun t => [true, false].flatMap fun held => [Lock.unlocked, .locked].flatMap fun l =>
    thCases.flatMap fun o => [true, false].flatMap fun e => [0, 179, 180].map fun w => (t, held, l, o, e, w)).filter
    fun c => c.1 = .serious ∨ (c.2.1 = true ∧ c.2.2.1 = .unlocked ∧ c.2.2.2.2.2 ≠ 179)

private def laneCases : List (List Rd) :=
  [[], [(true, .unlocked, some .serious)], [(true, .unlocked, some .serious), (true, .unlocked, some .serious)],
   [(true, .unlocked, some .serious), (true, .unlocked, some .fair)], [(true, .unlocked, some .fair), (true, .unlocked, some .serious)],
   [(true, .unlocked, some .serious), (true, .unlocked, some .critical), (true, .unlocked, some .serious)],
   [(true, .unlocked, some .serious), (false, .unlocked, some .serious)], [(true, .unlocked, none), (true, .unlocked, some .serious)],
   [(true, .locked, some .serious), (true, .unlocked, some .serious)]]

private def visitCases : List (List Pin) :=
  [[.go, .go, .go], [.go, .go, .stop], [.go, .stop, .go], [.stop, .go, .go], [.go, .go], [.go, .go, .go, .go], [], [.go, .wait, .go]]

private def blockCases : List (Thermal × List (Option Thermal)) :=
  [(.serious, []), (.serious, [some .serious, some .serious]), (.serious, [some .serious, some .fair]), (.serious, [some .serious, some .critical]),
   (.serious, [none]), (.fair, [some .fair, some .fair]), (.fair, [some .fair, some .serious]), (.nominal, [some .nominal]), (.critical, [some .critical])]

private def stopCases : List (Bool × Sent × Nat) :=
  [Sent.none, .term, .kill].flatMap fun sn => [true, false].flatMap fun a => [0, 14, 15, 4, 5].map fun s => (a, sn, s)

private def endCases : List (Thermal × Bool × Bool × Option Thermal) :=
  [Thermal.serious, .fair].flatMap fun t => [true, false].flatMap fun g => [true, false].flatMap fun a => thCases.map fun b => (t, g, a, b)

private def killCases : List (Nat × Nat × String × String) :=
  [(100, 100, "Sat Oct 25 12:00:00 2026", "Sat Oct 25 12:00:00 2026"), (100, 101, "Sat Oct 25 12:00:00 2026", "Sat Oct 25 12:00:00 2026"),
   (100, 100, "Sat Oct 25 12:00:00 2026", "Sat Oct 25 12:00:01 2026"), (100, 100, "", ""), (100, 100, "", "x")]

private def pinLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "pinconsts"), ("pinWaitMaxS", pinWaitMaxS), ("pinPollS", pinPollS), ("stopGraceS", stopGraceS),
    ("killGraceS", killGraceS), ("clearWaitMaxS", clearWaitMaxS)]).compress] ++
  (allThermal.map fun t =>
    (Json.mkObj [("kind", "profile"), ("state", t.name), ("rank", t.rank), ("pinTarget", boolJ (pinTarget t)),
      ("profile", match t.profile with | none => Json.null | some p => Json.str p)]).compress) ++
  (pinCases.map fun c =>
    (Json.mkObj [("kind", "pin"), ("target", c.1.name), ("held", boolJ c.2.1), ("lock", c.2.2.1.name), ("state", thJ c.2.2.2.1),
      ("entered", boolJ c.2.2.2.2.1), ("waitedS", c.2.2.2.2.2), ("why", (pinWhy c.1 c.2.1 c.2.2.1 c.2.2.2.1 c.2.2.2.2.1 c.2.2.2.2.2).name),
      ("verdict", (pinGate c.1 c.2.1 c.2.2.1 c.2.2.2.1 c.2.2.2.2.1 c.2.2.2.2.2).name)]).compress) ++
  (laneCases.map fun rs =>
    (Json.mkObj [("kind", "lanes"), ("target", "Serious"),
      ("readings", Json.arr (rs.map fun r => Json.mkObj [("held", boolJ r.1), ("lock", r.2.1.name), ("state", thJ r.2.2)]).toArray),
      ("verdicts", Json.arr ((laneGates .serious rs).map fun p => Json.str p.name).toArray), ("lanes", lanesRun (laneGates .serious rs))]).compress) ++
  (visitCases.map fun ps =>
    (Json.mkObj [("kind", "visit"), ("verdicts", Json.arr (ps.map fun p => Json.str p.name).toArray), ("ok", boolJ (visitOk ps))]).compress) ++
  (blockCases.map fun c =>
    (Json.mkObj [("kind", "blockvalid"), ("target", c.1.name), ("states", Json.arr (c.2.map thJ).toArray), ("valid", boolJ (blockValid c.1 c.2))]).compress) ++
  (stopCases.map fun c =>
    (Json.mkObj [("kind", "stop"), ("alive", boolJ c.1), ("sent", c.2.1.name), ("sinceS", c.2.2), ("act", (stopAct c.1 c.2.1 c.2.2).name)]).compress) ++
  ([Phase.idle, .starting, .held, .stopping, .stopped].map fun p =>
    (Json.mkObj [("kind", "close"), ("phase", p.name), ("mayBeAlive", boolJ p.mayBeAlive), ("close", (closeAct p).name)]).compress) ++
  (endCases.map fun c =>
    (Json.mkObj [("kind", "end"), ("target", c.1.name), ("ownerGone", boolJ c.2.1), ("acked", boolJ c.2.2.1), ("back", thJ c.2.2.2),
      ("end", (endVerdict c.1 c.2.1 c.2.2.1 c.2.2.2).name), ("conditionSet", boolJ (conditionSet c.2.1 c.2.2.1))]).compress) ++
  ([true, false].flatMap fun r => [true, false].flatMap fun l => [true, false].map fun a =>
    (Json.mkObj [("kind", "recover"), ("hasRecord", boolJ r), ("alive", boolJ l), ("acked", boolJ a), ("act", (recoverAct r l a).name)]).compress) ++
  ([Thermal.serious, .fair].flatMap fun t => thCases.flatMap fun b => ([0, 299, 300] : List Nat).map fun w =>
    (Json.mkObj [("kind", "clearwait"), ("target", t.name), ("back", thJ b), ("waitedS", toJson w), ("wait", boolJ (clearWait t b w))]).compress) ++
  (killCases.map fun c =>
    (Json.mkObj [("kind", "kill"), ("recPid", c.1), ("curPid", c.2.1), ("recStart", c.2.2.1), ("curStart", c.2.2.2), ("ok", boolJ (mayKill c.1 c.2.1 c.2.2.1 c.2.2.2))]).compress)

def goldenLines (_ : Unit) : List String := baseLines () ++ pinLines ()

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-thermal golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-thermal golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Golden

end Fw.Device.Thermal
