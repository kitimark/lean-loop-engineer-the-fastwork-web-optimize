import Fw.Sup.Adapt
import Fw.Obs.Timing

/-! Measure windows of the slot queue. -/
namespace Fw.Sup.MeasureWindow

open Fw.Sup.Adapt

structure WParams where
  measureMaxS : Nat := 5400
  passMaxS : Nat := 1200
  settleS : Nat := 30
  histMin : Nat := 3
  histN : Nat := 20
deriving DecidableEq, Repr

structure Window where
  owner : String
  token : String
  deadline : Nat
  passTill : Option Nat := none
  next : Nat
deriving DecidableEq, Repr

def openAt (wp : WParams) (owner token : String) (now gapS : Nat) : Window :=
  { owner, token, deadline := now + wp.measureMaxS, next := now + gapS }

def active (now : Nat) (w : Window) : Bool := decide (now < w.deadline)

def held (now : Nat) (hs : List Entry) (w : Window) : Bool :=
  (prune now hs).any (fun h => h.kind == .measure && h.token == w.token && h.owner == w.owner)

def current (now : Nat) (hs : List Entry) : Option Window → Option Window
  | none => none
  | some w => if active now w && held now hs w then some w else none

def passLive (now : Nat) (w : Window) : Bool :=
  match w.passTill with
  | some t => decide (now < t)
  | none => false

def fits (wp : WParams) (now next d : Nat) : Bool := decide (now + d + wp.settleS ≤ next)

def gate (wp : WParams) (w : Window) (pred : Option Nat) (p : Params) (now waited : Nat) (me : Entry) (base : Verdict) :
    Verdict :=
  if passLive now w then waitOr p waited .pass
  else if me.kind == .measure then waitOr p waited .measureBusy
  else match base with
    | .admit t f =>
      match pred with
      | none => waitOr p waited .unknown
      | some d => if fits wp now w.next d then .admit t f else waitOr p waited (.gap (d + wp.settleS) (w.next - now))
    | v => v

def wverdict (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited : Nat) : Verdict :=
  match current s.time hs w with
  | none => verdict p n s hs q me waited
  | some w => gate wp w pred p s.time waited me (verdict p n s hs q me waited)

structure Row where
  step : String
  durMs : Nat
  exit : Option Nat
  host : String
deriving DecidableEq, Repr

def runStep (k : Kind) : String := "slot run " ++ k.name

def counts (k : Kind) (r : Row) : Bool :=
  r.host == "local" && r.exit == some 0 && !r.step.endsWith " cached" &&
    (r.step == runStep k || r.step.startsWith (runStep k ++ " "))

def durs (wp : WParams) (k : Kind) (rows : List Row) : List Nat :=
  (((rows.filter (counts k)).map (·.durMs)).reverse.take wp.histN)

def predict (wp : WParams) (k : Kind) (rows : List Row) : Option Nat :=
  if wp.histMin ≤ (durs wp k rows).length then some ((Fw.Obs.Timing.p90 (durs wp k rows) + 999) / 1000) else none

inductive PassVerdict where
  | start (till : Nat)
  | wait (others : Nat)
  | gone
deriving DecidableEq, Repr

def othersOf (now : Nat) (hs : List Entry) (token : String) : Nat :=
  ((prune now hs).filter (fun h => h.token != token)).length

def passStart (wp : WParams) (w : Option Window) (now : Nat) (hs : List Entry) (owner token : String) (forS : Nat) :
    PassVerdict :=
  match current now hs w with
  | none => .gone
  | some w =>
    if w.token != token || w.owner != owner then .gone
    else if 0 < othersOf now hs token then .wait (othersOf now hs token)
    else .start (min (now + min forS wp.passMaxS) w.deadline)

def begin (w : Window) (till : Nat) : Window := { w with passTill := some till }

def want (w : Window) (now : Nat) : Window := { w with next := min w.next now }

def stop (w : Window) (now gapS : Nat) : Window := { w with passTill := none, next := now + gapS }

def capLease (w : Window) (now lease : Nat) : Nat := min lease (w.deadline - now)

def mH (o t : String) (t0 till : Nat) : Entry := { owner := o, token := t, kind := .measure, since := t0, till := till }

def wA : Window := openAt {} "m" "M" 1000 0

def gapA : Window := stop (begin wA 1300) 1300 600

def chk (o t : String) (k : Kind) (t0 : Nat) : Entry := { owner := o, token := t, kind := k, since := t0, till := t0 + 60 }

def s1 (t : Nat) : Sample := { okSample with time := t }

#guard wA == { owner := "m", token := "M", deadline := 6400, next := 1000 }
#guard current 1100 [mH "m" "M" 1000 1200] (some wA) == some wA
#guard current 1100 [mH "m" "X" 1000 1200] (some wA) == none
#guard current 6400 [mH "m" "M" 1000 7000] (some wA) == none
#guard current 1300 [mH "m" "M" 1000 1200] (some wA) == none
#guard wverdict {} (some (begin wA 1300)) (some 10) {} 4 (s1 1100) [mH "m" "M" 1000 1600] [chk "a" "1" .check 1090]
  (chk "a" "1" .check 1090) 10 == .wait .pass
#guard wverdict {} (some gapA) (some 100) {} 4 (s1 1400) [mH "m" "M" 1000 2000] [chk "a" "1" .check 1390]
  (chk "a" "1" .check 1390) 10 == .admit 7 4900
#guard wverdict {} (some gapA) (some 500) {} 4 (s1 1400) [mH "m" "M" 1000 2000] [chk "a" "1" .check 1390]
  (chk "a" "1" .check 1390) 10 == .wait (.gap 530 500)
#guard wverdict {} (some gapA) none {} 4 (s1 1400) [mH "m" "M" 1000 2000] [chk "a" "1" .check 1390]
  (chk "a" "1" .check 1390) 10 == .wait .unknown
#guard wverdict {} (some gapA) (some 10) {} 4 (s1 1400) [mH "m" "M" 1000 2000] [chk "b" "2" .measure 1390]
  (chk "b" "2" .measure 1390) 10 == .wait .measureBusy
#guard wverdict {} (some gapA) (some 500) {} 4 (s1 6400) [mH "m" "M" 1000 7000] [chk "a" "1" .check 6390]
  (chk "a" "1" .check 6390) 10 == .admit 7 4900
#guard wverdict {} (some (begin wA 1300)) (some 10) {} 4 (s1 1100) [mH "m" "M" 1000 1600] [chk "a" "1" .check 1090]
  (chk "a" "1" .check 1090) 1800 == .timeout .pass
#guard passStart {} (some wA) 1100 [mH "m" "M" 1000 1600] "m" "M" 300 == .start 1400
#guard passStart {} (some wA) 1100 [mH "m" "M" 1000 1600] "m" "M" 9000 == .start 2300
#guard passStart {} (some wA) 6300 [mH "m" "M" 1000 7000] "m" "M" 300 == .start 6400
#guard passStart {} (some wA) 1100 [mH "m" "M" 1000 1600, chk "a" "1" .test 1090] "m" "M" 300 == .wait 1
#guard passStart {} (some wA) 1100 [mH "m" "M" 1000 1600] "x" "M" 300 == .gone
#guard passStart {} none 1100 [mH "m" "M" 1000 1600] "m" "M" 300 == .gone
#guard predict {} .check [⟨"slot run check", 61000, some 0, "local"⟩, ⟨"slot run check lake", 1500, some 0, "local"⟩] == none
#guard predict {} .check [⟨"slot run check", 61000, some 0, "local"⟩, ⟨"slot run check lake", 1500, some 0, "local"⟩,
  ⟨"slot run check lake cached", 10, some 0, "local"⟩, ⟨"slot run checker", 10, some 0, "local"⟩,
  ⟨"slot run check", 99000, some 1, "local"⟩, ⟨"slot run check", 7000, some 0, "ci"⟩,
  ⟨"slot run check lake", 2001, some 0, "local"⟩] == some 61
#guard predict { histN := 2 } .check [⟨"slot run check", 61000, some 0, "local"⟩, ⟨"slot run check", 1500, some 0, "local"⟩,
  ⟨"slot run check", 2001, some 0, "local"⟩] == none
#guard capLease wA 6000 600 == 400 && capLease wA 1000 600 == 600 && capLease wA 7000 600 == 0
#guard want gapA 1500 == { gapA with next := 1500 } && want gapA 2000 == gapA

theorem waitOr_eq_wait (p : Params) (w : Nat) (y y' : Why) (h : waitOr p w y = .wait y') : w < p.maxWaitS := by
  unfold waitOr at h; split at h <;> simp_all

theorem current_some (now : Nat) (hs : List Entry) (w : Option Window) (x : Window) (h : current now hs w = some x) :
    w = some x ∧ now < x.deadline ∧ held now hs x = true := by
  cases w with
  | none => simp [current] at h
  | some w =>
    simp only [current] at h
    split at h
    · rename_i hc; cases h; simp [active] at hc; exact ⟨rfl, hc.1, hc.2⟩
    · cases h

theorem held_nonempty (now : Nat) (hs : List Entry) (w : Window) (h : held now hs w = true) : prune now hs ≠ [] := by
  intro he; simp [held, he] at h

theorem pass_live_waits (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited : Nat) (x : Window) (hc : current s.time hs w = some x)
    (hl : passLive s.time x = true) : wverdict wp w pred p n s hs q me waited = waitOr p waited .pass := by
  simp [wverdict, hc, gate, hl]

theorem pass_live_no_admit (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited t f : Nat) (x : Window) (hc : current s.time hs w = some x)
    (hl : passLive s.time x = true) : wverdict wp w pred p n s hs q me waited ≠ .admit t f := by
  rw [pass_live_waits wp w pred p n s hs q me waited x hc hl]; exact waitOr_ne_admit p waited .pass t f

theorem pass_start_quiet (wp : WParams) (w : Option Window) (now : Nat) (hs : List Entry) (o tok : String) (forS t : Nat)
    (h : passStart wp w now hs o tok forS = .start t) : ∀ e ∈ prune now hs, e.token = tok := by
  intro e he
  unfold passStart at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h
      · rename_i ho
        have h0 : othersOf now hs tok = 0 := by omega
        simp only [othersOf, List.length_eq_zero_iff, List.filter_eq_nil_iff] at h0
        simpa using h0 e he

theorem pass_start_bounded (wp : WParams) (w : Option Window) (now : Nat) (hs : List Entry) (o tok : String) (forS t : Nat)
    (h : passStart wp w now hs o tok forS = .start t) :
    ∃ x, w = some x ∧ t ≤ now + wp.passMaxS ∧ t ≤ x.deadline ∧ t ≤ now + forS := by
  unfold passStart at h
  split at h
  · cases h
  · rename_i x hc
    obtain ⟨hw, -, -⟩ := current_some now hs w x hc
    split at h
    · cases h
    · split at h
      · cases h
      · cases h; exact ⟨x, hw, by omega, by omega, by omega⟩

theorem passLive_begin (now till : Nat) (w : Window) : passLive now (begin w till) = decide (now < till) := rfl

theorem gap_admit (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited t f : Nat) (x : Window) (hc : current s.time hs w = some x)
    (h : wverdict wp w pred p n s hs q me waited = .admit t f) :
    passLive s.time x = false ∧ (∃ d, pred = some d ∧ s.time + d + wp.settleS ≤ x.next) ∧
      f + p.floorMB + charged p s.time hs ≤ s.avail ∧ verdict p n s hs q me waited = .admit t f := by
  simp only [wverdict, hc, gate] at h
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  rename_i hl
  split at h
  · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  split at h
  · rename_i t' f' hb
    split at h
    · exact absurd h (waitOr_ne_admit _ _ _ _ _)
    · rename_i d
      split at h
      · rename_i hf
        cases h
        have hfit : s.time + d + wp.settleS ≤ x.next := by simpa [fits] using hf
        refine ⟨by simpa using hl, ⟨d, rfl, hfit⟩, ?_, hb⟩
        rcases admit_fits p n s hs q me waited t f hb with hm | hi
        · exact hm
        · exact absurd ((idleHead_iff p s hs).1 hi).1 (held_nonempty _ _ _ (current_some _ _ w x hc).2.2)
      · exact absurd h (waitOr_ne_admit _ _ _ _ _)
  · rename_i hv; exact absurd h (hv t f)

theorem gap_job_ends_before_pass (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat)
    (s : Sample) (hs q : List Entry) (me : Entry) (waited t f d run : Nat) (x : Window)
    (hc : current s.time hs w = some x) (h : wverdict wp w pred p n s hs q me waited = .admit t f)
    (hp : pred = some d) (hrun : run ≤ d) : s.time + run + wp.settleS ≤ x.next := by
  obtain ⟨-, ⟨d', hd', hfit⟩, -, -⟩ := gap_admit wp w pred p n s hs q me waited t f x hc h
  rw [hp] at hd'; cases hd'; omega

theorem want_closes_gap (wp : WParams) (w : Window) (now now' d : Nat) (hs : 0 < wp.settleS) (hn : now ≤ now') :
    fits wp now' (want w now).next d = false := by
  simp only [fits, want]
  exact decide_eq_false (by omega)

theorem gap_measure_waits (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited t f : Nat) (x : Window) (hc : current s.time hs w = some x)
    (hk : me.kind = .measure) : wverdict wp w pred p n s hs q me waited ≠ .admit t f := by
  simp only [wverdict, hc, gate, hk]
  split
  · exact waitOr_ne_admit _ _ _ _ _
  · simpa using waitOr_ne_admit p waited .measureBusy t f

theorem wverdict_no_window (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited : Nat) (hc : current s.time hs w = none) :
    wverdict wp w pred p n s hs q me waited = verdict p n s hs q me waited := by
  simp [wverdict, hc]

theorem after_deadline (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited : Nat) (x : Window) (hw : w = some x) (hd : x.deadline ≤ s.time) :
    wverdict wp w pred p n s hs q me waited = verdict p n s hs q me waited := by
  apply wverdict_no_window
  subst hw
  have : active s.time x = false := by simp [active]; omega
  simp [current, this]

theorem openAt_deadline (wp : WParams) (o t : String) (now g : Nat) : (openAt wp o t now g).deadline = now + wp.measureMaxS :=
  rfl

theorem deadline_fixed (w : Window) (now till g : Nat) :
    (begin w till).deadline = w.deadline ∧ (want w now).deadline = w.deadline ∧ (stop w now g).deadline = w.deadline :=
  ⟨rfl, rfl, rfl⟩

theorem capLease_within (w : Window) (now lease : Nat) (h : now ≤ w.deadline) : now + capLease w now lease ≤ w.deadline := by
  simp [capLease]; omega

theorem wverdict_admit_base (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited t f : Nat) (h : wverdict wp w pred p n s hs q me waited = .admit t f) :
    verdict p n s hs q me waited = .admit t f := by
  cases hc : current s.time hs w with
  | none => rwa [wverdict_no_window wp w pred p n s hs q me waited hc] at h
  | some x => exact (gap_admit wp w pred p n s hs q me waited t f x hc h).2.2.2

theorem window_wait_before_deadline (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat)
    (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat)
    (h : wverdict wp w pred p n s hs q me waited ≠ verdict p n s hs q me waited) :
    ∃ x, w = some x ∧ s.time < x.deadline := by
  cases hc : current s.time hs w with
  | none => exact absurd (wverdict_no_window wp w pred p n s hs q me waited hc) h
  | some x => obtain ⟨hw, hd, -⟩ := current_some _ _ w x hc; exact ⟨x, hw, hd⟩

theorem window_keeps_older (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat) (s : Sample)
    (hs q : List Entry) (me : Entry) (waited t f : Nat) (hk : me.kind ≠ .sim) (ho : starved p s.time hs q me = true) :
    wverdict wp w pred p n s hs q me waited ≠ .admit t f := by
  intro h
  have := (verdict_admit p n s hs q me waited t f (wverdict_admit_base wp w pred p n s hs q me waited t f h)).2.1
  simp [hk, ho] at this

theorem verdict_late_not_wait (p : Params) (n : Nat) (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat)
    (hw : p.maxWaitS ≤ waited) (y : Why) : verdict p n s hs q me waited ≠ .wait y := by
  intro h
  unfold verdict verdictWith at h
  simp only at h
  repeat' (split at h; · exact absurd (waitOr_eq_wait _ _ _ _ h) (by omega))
  cases h

theorem wverdict_late_not_wait (wp : WParams) (w : Option Window) (pred : Option Nat) (p : Params) (n : Nat)
    (s : Sample) (hs q : List Entry) (me : Entry) (waited : Nat) (hw : p.maxWaitS ≤ waited) (y : Why) :
    wverdict wp w pred p n s hs q me waited ≠ .wait y := by
  intro h
  have hb := verdict_late_not_wait p n s hs q me waited hw
  cases hc : current s.time hs w with
  | none => rw [wverdict_no_window wp w pred p n s hs q me waited hc] at h; exact hb y h
  | some x =>
    simp only [wverdict, hc, gate] at h
    split at h
    · exact absurd (waitOr_eq_wait _ _ _ _ h) (by omega)
    split at h
    · exact absurd (waitOr_eq_wait _ _ _ _ h) (by omega)
    split at h
    · split at h
      · exact absurd (waitOr_eq_wait _ _ _ _ h) (by omega)
      · split at h
        · cases h
        · exact absurd (waitOr_eq_wait _ _ _ _ h) (by omega)
    · exact hb y h

end Fw.Sup.MeasureWindow
