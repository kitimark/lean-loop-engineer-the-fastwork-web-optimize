import Fw.Parts.MorphGeomLook
import Fw.Parts.MorphGeomTimed
/-! Automatic flip readings (A3a, A4, A5) and the six mutation runs. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.MorphGeomTimed

structure QuietFrame where
  moving : Nat
  width : Rat

def quietFrameOk (base tol : Rat) (f : QuietFrame) : Bool :=
  f.moving == 0 && decide (f.width - base ≤ tol) && decide (base - f.width ≤ tol)

def quietOk (base tol : Rat) (fs : List QuietFrame) : Bool := !fs.isEmpty && fs.all (quietFrameOk base tol)

def leaveFrame (s : LeaveSt) (base dev : Rat) : QuietFrame :=
  if s.started then ⟨2, base + dev⟩ else ⟨0, base⟩

theorem quiet_new_passes (base tol dev : Rat) (h : 0 ≤ tol) :
    quietOk base tol [leaveFrame (leaveRun (leaveNew ++ [.flush])) base dev] = true := by
  have e : (leaveRun (leaveNew ++ [.flush])).started = false := leave_new_quiet
  simp [quietOk, quietFrameOk, leaveFrame, e]
  grind

theorem quiet_old_fails (base tol dev : Rat) :
    quietOk base tol [leaveFrame (leaveRun (leaveOld ++ [.flush])) base dev] = false := by
  have e : (leaveRun (leaveOld ++ [.flush])).started = true := by decide
  simp [quietOk, quietFrameOk, leaveFrame, e]

theorem quiet_fails_moving (base tol : Rat) (w : Rat) (n : Nat) (hn : n ≠ 0) :
    quietFrameOk base tol ⟨n, w⟩ = false := by
  simp [quietFrameOk, hn]

theorem quiet_fails_width (base tol w : Rat) (h : tol < w - base) :
    quietFrameOk base tol ⟨0, w⟩ = false := by
  have : ¬ (w - base ≤ tol) := Rat.not_le.mpr h
  simp [quietFrameOk, this]

theorem quiet_fails_narrow (base tol w : Rat) (h : tol < base - w) :
    quietFrameOk base tol ⟨0, w⟩ = false := by
  have : ¬ (base - w ≤ tol) := Rat.not_le.mpr h
  simp [quietFrameOk, this]

def keptWithin (frame dt before after : Rat) : Bool :=
  decide (after - before - dt ≤ frame) && decide (before + dt - after ≤ frame)

theorem kept_new (frame dt t : Rat) (h : 0 ≤ frame) :
    keptWithin frame dt t ((moveRun moveNew t).t + dt) = true := by
  have e : (moveRun moveNew t).t = t := move_new_keeps t
  simp [keptWithin, e]
  grind

theorem kept_old_fails (frame dt t : Rat) (h : frame < t) :
    keptWithin frame dt t ((moveRun moveOld t).t + dt) = false := by
  have e : (moveRun moveOld t).t = 0 := by simp [moveRun, moveOld, MoveSt.step]
  have : ¬ (t + dt - (0 + dt) ≤ frame) := by
    intro hc
    have : t ≤ frame := by grind
    exact absurd h (Rat.not_lt.mpr this)
  simp [keptWithin, e]
  grind

theorem kept_fails_ahead (frame dt before after : Rat) (h : frame < after - before - dt) :
    keptWithin frame dt before after = false := by
  have : ¬ (after - before - dt ≤ frame) := Rat.not_le.mpr h
  simp [keptWithin, this]

def keptAll (frame : Rat) (lost : Nat) (ps : List (Rat × Rat × Rat)) : Bool :=
  lost == 0 && !ps.isEmpty && ps.all fun (dt, b, a) => keptWithin frame dt b a

theorem kept_fails_lost (frame : Rat) (lost : Nat) (ps : List (Rat × Rat × Rat)) (h : lost ≠ 0) :
    keptAll frame lost ps = false := by
  simp [keptAll, h]

theorem kept_fails_vacuous (frame : Rat) : keptAll frame 0 [] = false := by simp [keptAll]

theorem kept_fails_one (frame : Rat) (ps : List (Rat × Rat × Rat)) (dt b a : Rat) (hm : (dt, b, a) ∈ ps)
    (h : keptWithin frame dt b a = false) : keptAll frame 0 ps = false := by
  simp only [keptAll, Bool.and_eq_false_iff, List.all_eq_false]
  right
  exact ⟨(dt, b, a), hm, by simp [h]⟩

theorem kept_passes (frame : Rat) (p : Rat × Rat × Rat) (h : keptWithin frame p.1 p.2.1 p.2.2 = true) :
    keptAll frame 0 [p] = true := by
  simp [keptAll, h]

theorem kept_fails_behind (frame dt before after : Rat) (h : frame < before + dt - after) :
    keptWithin frame dt before after = false := by
  have : ¬ (before + dt - after ≤ frame) := Rat.not_le.mpr h
  simp [keptWithin, this]

inductive TakeEv where
  | push
  | take
  deriving DecidableEq

def TakeEv.name : TakeEv → String
  | .push => "push" | .take => "take"

def takenAll : Bool → List TakeEv → Bool
  | pending, [] => !pending
  | pending, .push :: r => !pending && takenAll true r
  | pending, .take :: r => pending && takenAll false r

def pushesTaken (evs : List TakeEv) : Bool := evs.contains .push && takenAll false evs

def pushTrace (f t : Rat) (anims : Bool) (dark : Nat → Bool) (n : Nat) : List TakeEv :=
  .push :: (match takeFrame f t anims dark n with | some _ => [.take] | none => [])

theorem trace_dark_passes (f t : Rat) (dark : Nat → Bool) (n r : Nat) (hr : r < n) (hd : dark r = true)
    (hb : ∀ j, j < r → dark j = false) : pushesTaken (pushTrace f t false dark n) = true := by
  simp [pushTrace, take_at_first_dark f t dark n r hr hd hb, pushesTaken, takenAll]

theorem trace_entered_passes (f t : Rat) (dark : Nat → Bool) (n : Nat) :
    pushesTaken (pushTrace f t true dark (n + 1)) = true := by
  simp [pushTrace, take_entered, pushesTaken, takenAll]

theorem trace_never_fails (f t : Rat) (dark : Nat → Bool) (hn : ∀ j, dark j = false) (n : Nat) :
    pushesTaken (pushTrace f t false dark n) = false := by
  simp [pushTrace, take_never f t dark hn n, pushesTaken, takenAll]

theorem trace_empty_fails : pushesTaken [] = false := by decide

theorem trace_orphan_push_fails : pushesTaken [.push, .take, .push] = false := by decide

theorem trace_double_push_fails : pushesTaken [.push, .push, .take] = false := by decide

theorem trace_stray_take_fails : pushesTaken [.take, .push, .take] = false := by decide

theorem trace_cycle_passes : pushesTaken [.push, .take, .push, .take] = true := by decide

def takenFlags : Bool → List TakeEv → Option (List Bool)
  | false, [] => some []
  | true, [] => some [false]
  | false, .push :: r => takenFlags true r
  | true, .push :: r => (takenFlags true r).map (false :: ·)
  | true, .take :: r => (takenFlags false r).map (true :: ·)
  | false, .take :: _ => none

def pushJudged (chance taken : Bool) : Bool := !chance || taken

def pushChance (darkAtPush framed : Bool) : Bool := darkAtPush || framed

def pairsOk (chances ts : List Bool) : Bool :=
  ts.length == chances.length && (chances.zip ts).all (fun (c, t) => pushJudged c t) && ts.any id

def traceOk (evs : List TakeEv) (chances : List Bool) : Bool :=
  match takenFlags false evs with
  | none => false
  | some ts => pairsOk chances ts

theorem pairs_lost_chance_fails (chances ts : List Bool) (h : (true, false) ∈ chances.zip ts) :
    pairsOk chances ts = false := by
  simp only [pairsOk, Bool.and_eq_false_iff, List.all_eq_false]
  left; right
  exact ⟨(true, false), h, by simp [pushJudged]⟩

theorem pairs_dead_fails (chances ts : List Bool) (h : ts.any id = false) : pairsOk chances ts = false := by
  simp [pairsOk, h]

theorem pairs_excused_free (chances ts : List Bool) :
    pairsOk (chances ++ [false]) (ts ++ [false]) = pairsOk chances ts := by
  by_cases h : ts.length = chances.length
  · simp [pairsOk, h, List.zip_append h.symm, pushJudged]
  · have hb : (ts.length == chances.length) = false := by simpa using h
    simp [pairsOk, hb]

theorem trace_ok_cycle : traceOk [.push, .take, .push, .take] [true, true] = true := by decide

theorem judged_all_taken_passes : traceOk [.push, .take, .push, .take, .push, .take, .push, .take] [true, true, true, true] = true := by decide

theorem judged_open_untaken_fails : traceOk [.push, .take, .push, .take, .push, .take, .push] [true, true, true, true] = false := by decide

theorem judged_no_chance_excused :
    traceOk [.push, .take, .push, .take, .push, .take, .push] [true, true, true, false] = true := by decide

theorem judged_two_excused_passes :
    traceOk [.push, .take, .push, .take, .push, .push] [true, true, false, false] = true := by decide

theorem judged_open_starved_passes :
    traceOk [.push, .push, .take, .push, .push, .take] [false, false, false, true] = true := by decide

theorem judged_dead_without_chance_fails : traceOk [.push, .push] [false, false] = false := by decide

theorem judged_open_lost_with_closes_taken_fails :
    traceOk [.push, .push, .take, .push, .push, .take] [true, false, false, true] = false := by decide

theorem judged_stray_take_fails : traceOk [.take, .push, .take] [true] = false := by decide

theorem judged_double_take_fails : traceOk [.push, .take, .take] [true] = false := by decide

theorem judged_empty_fails : traceOk [] [] = false := by decide

theorem judged_chances_mismatch_fails : traceOk [.push, .take] [true, true] = false := by decide

theorem judged_taken_without_chance_passes :
    traceOk [.push, .take, .push, .take, .push, .take, .push, .take] [false, false, false, false] = true := by decide

theorem judged_untaken_without_chance_passes :
    traceOk [.push, .take, .push, .take, .push, .push] [false, false, false, false] = true := by decide

theorem push_chance_dark (framed : Bool) : pushChance true framed = true := by simp [pushChance]

theorem push_chance_framed (dark : Bool) : pushChance dark true = true := by simp [pushChance]

theorem push_chance_none : pushChance false false = false := by decide

theorem dark_push_untaken_fails : traceOk [.push, .push] [pushChance true false, pushChance true false] = false := by decide

structure PushObs where
  light : Bool
  chance : Bool
  taken : Bool

def retryJudged (ps : List PushObs) : Bool := !ps.any (·.light) || ps.any fun p => p.light && (p.chance || p.taken)

theorem retry_vacuous (ps : List PushObs) (h : ps.any (·.light) = false) : retryJudged ps = true := by
  simp [retryJudged, h]

theorem retry_unjudged_fails (ps : List PushObs) (hl : ps.any (·.light) = true)
    (h : ps.any (fun p => p.light && (p.chance || p.taken)) = false) : retryJudged ps = false := by
  simp [retryJudged, hl, h]

theorem retry_taken_passes (p : PushObs) (ps : List PushObs) (hm : p ∈ ps) (hl : p.light = true) (ht : p.taken = true) :
    retryJudged ps = true := by
  have : ps.any (fun p => p.light && (p.chance || p.taken)) = true := by
    simp only [List.any_eq_true]
    exact ⟨p, hm, by simp [hl, ht]⟩
  simp [retryJudged, this]

theorem retry_chance_passes (p : PushObs) (ps : List PushObs) (hm : p ∈ ps) (hl : p.light = true) (hc : p.chance = true) :
    retryJudged ps = true := by
  have : ps.any (fun p => p.light && (p.chance || p.taken)) = true := by
    simp only [List.any_eq_true]
    exact ⟨p, hm, by simp [hl, hc]⟩
  simp [retryJudged, this]

def leaveCovered (leaveTs lastTs windowMs : Rat) : Bool := decide (windowMs ≤ lastTs - leaveTs)

def leaveOk (covered quiet : Bool) : Bool := covered && quiet

theorem leave_uncovered_fails (quiet : Bool) : leaveOk false quiet = false := by simp [leaveOk]

theorem leave_noisy_fails (covered : Bool) : leaveOk covered false = false := by simp [leaveOk]

theorem leave_covered_quiet_passes : leaveOk true true = true := by decide

theorem leave_covered_later (leaveTs lastTs lastTs' windowMs : Rat) (h : leaveCovered leaveTs lastTs windowMs = true)
    (hl : lastTs ≤ lastTs') : leaveCovered leaveTs lastTs' windowMs = true := by
  simp only [leaveCovered, decide_eq_true_eq] at *
  grind

theorem leave_short_not_covered (leaveTs lastTs windowMs : Rat) (h : lastTs - leaveTs < windowMs) :
    leaveCovered leaveTs lastTs windowMs = false := by
  have : ¬ (windowMs ≤ lastTs - leaveTs) := Rat.not_le.mpr h
  simp [leaveCovered, this]

theorem push_judged_untaken (taken : Bool) (h : pushJudged true taken = false) : taken = false := by
  cases taken <;> simp_all [pushJudged]

def verifyWindowMs : Nat := 800

def verifyFrameMs : Rat := 50 / 3

def verifyTolPx : Rat := 1

inductive Mutation where
  | a1 | a3b | a3c | a4 | a3a | a5
  deriving DecidableEq

def Mutation.name : Mutation → String
  | .a1 => "A1" | .a3b => "A3b" | .a3c => "A3c" | .a4 => "A4" | .a3a => "A3a" | .a5 => "A5"

def Mutation.all : List Mutation := [.a1, .a3b, .a3c, .a4, .a3a, .a5]

def Mutation.reading : Mutation → String
  | .a1 => "column beside" | .a3b => "earn y" | .a3c => "lang y" | .a4 => "quiet leave" | .a3a => "time kept" | .a5 => "timed take"

theorem mutation_all_complete (m : Mutation) : m ∈ Mutation.all := by cases m <;> decide

theorem mutation_names_distinct : (Mutation.all.map Mutation.name).Nodup := by decide

end Fw.Parts.MorphGeom
