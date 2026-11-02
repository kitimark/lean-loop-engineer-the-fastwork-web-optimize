import Lean.Data.Json
import Fw.Measure.WalkBudget
/-!
# Fw.Measure.TouchReady: when the Simulator touch driver counts as ready, when its launch is abandoned and relaunched
-/
namespace Fw.Measure.TouchReady

structure Cfg where
  launches : Nat
  launchMs : Nat
  killMs : Nat
  stopWaitMs : Nat
deriving Repr, BEq

def cfg : Cfg := ⟨3, 150000, 10000, 20000⟩

def restartCfg : Cfg := ⟨1, 470000, 10000, 20000⟩

inductive LaunchFault where
  | launchStuck
  | bodyStuck
  | ended
deriving DecidableEq, Repr

def LaunchFault.name : LaunchFault → String
  | .launchStuck => "driver-launch-stuck"
  | .bodyStuck => "driver-body-stuck"
  | .ended => "driver-ended"

def LaunchFault.all : List LaunchFault := [.launchStuck, .bodyStuck, .ended]

theorem names_nodup : (LaunchFault.all.map LaunchFault.name).Nodup := by decide

theorem names_not_walk_faults :
    ∀ f ∈ LaunchFault.all, ∀ g ∈ Fw.Measure.FaultNames.Fault.all, f.name ≠ g.name := by decide

structure Obs where
  ready : Bool
  alive : Bool
  ended : Bool
  elapsed : Nat
deriving Repr, BEq

inductive Act where
  | wait
  | ready
  | relaunch (f : LaunchFault)
  | give (f : LaunchFault)
deriving DecidableEq, Repr

def faultOf (o : Obs) : LaunchFault :=
  if o.ended then .ended else if o.alive then .bodyStuck else .launchStuck

def verdict (c : Cfg) (n : Nat) (o : Obs) : Act :=
  if o.ready then .ready
  else if o.ended || c.launchMs ≤ o.elapsed then
    (if n < c.launches then .relaunch (faultOf o) else .give (faultOf o))
  else .wait

theorem faultOf_ended (o : Obs) (h : o.ended = true) : faultOf o = .ended := by
  simp [faultOf, h]

theorem faultOf_body (o : Obs) (h : o.ended = false) (ha : o.alive = true) : faultOf o = .bodyStuck := by
  simp [faultOf, h, ha]

theorem faultOf_launch (o : Obs) (h : o.ended = false) (ha : o.alive = false) : faultOf o = .launchStuck := by
  simp [faultOf, h, ha]

theorem verdict_cases (c : Cfg) (n : Nat) (o : Obs) :
    (o.ready = true ∧ verdict c n o = .ready) ∨
    (o.ready = false ∧ (o.ended = true ∨ c.launchMs ≤ o.elapsed) ∧ n < c.launches ∧ verdict c n o = .relaunch (faultOf o)) ∨
    (o.ready = false ∧ (o.ended = true ∨ c.launchMs ≤ o.elapsed) ∧ c.launches ≤ n ∧ verdict c n o = .give (faultOf o)) ∨
    (o.ready = false ∧ o.ended = false ∧ o.elapsed < c.launchMs ∧ verdict c n o = .wait) := by
  cases hr : o.ready
  · cases he : o.ended
    · by_cases hc : c.launchMs ≤ o.elapsed
      · by_cases hn : n < c.launches
        · exact Or.inr (Or.inl ⟨rfl, Or.inr hc, hn, by simp [verdict, hr, he, hc, hn]⟩)
        · exact Or.inr (Or.inr (Or.inl ⟨rfl, Or.inr hc, by omega, by simp [verdict, hr, he, hc, hn]⟩))
      · exact Or.inr (Or.inr (Or.inr ⟨rfl, rfl, by omega, by simp [verdict, hr, he, hc]⟩))
    · by_cases hn : n < c.launches
      · exact Or.inr (Or.inl ⟨rfl, Or.inl rfl, hn, by simp [verdict, hr, he, hn]⟩)
      · exact Or.inr (Or.inr (Or.inl ⟨rfl, Or.inl rfl, by omega, by simp [verdict, hr, he, hn]⟩))
  · exact Or.inl ⟨rfl, by simp [verdict, hr]⟩

theorem ready_wins (c : Cfg) (n : Nat) (o : Obs) (h : o.ready = true) : verdict c n o = .ready := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all

theorem ready_only_if_ready (c : Cfg) (n : Nat) (o : Obs) (h : verdict c n o = .ready) : o.ready = true := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all

theorem wait_iff (c : Cfg) (n : Nat) (o : Obs) :
    verdict c n o = .wait ↔ o.ready = false ∧ o.ended = false ∧ o.elapsed < c.launchMs := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1
  · simp_all
  · obtain ⟨h2, h3, h4, h5⟩ := h1
    rw [h5]
    simp only [reduceCtorEq, false_iff]
    intro ⟨_, h6, h7⟩
    rcases h3 with h3 | h3 <;> simp_all <;> omega
  · obtain ⟨h2, h3, h4, h5⟩ := h1
    rw [h5]
    simp only [reduceCtorEq, false_iff]
    intro ⟨_, h6, h7⟩
    rcases h3 with h3 | h3 <;> simp_all <;> omega
  · obtain ⟨h2, h3, h4, h5⟩ := h1
    simp [h2, h3, h4, h5]

theorem relaunch_cap (c : Cfg) (n : Nat) (o : Obs) (hr : o.ready = false) (hn : n < c.launches)
    (h : c.launchMs ≤ o.elapsed) : verdict c n o = .relaunch (faultOf o) := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all <;> omega

theorem relaunch_ended (c : Cfg) (n : Nat) (o : Obs) (hr : o.ready = false) (hn : n < c.launches)
    (h : o.ended = true) : verdict c n o = .relaunch .ended := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all [faultOf] <;> omega

theorem give_cap (c : Cfg) (n : Nat) (o : Obs) (hr : o.ready = false) (hn : c.launches ≤ n)
    (h : c.launchMs ≤ o.elapsed) : verdict c n o = .give (faultOf o) := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all <;> omega

theorem give_ended (c : Cfg) (n : Nat) (o : Obs) (hr : o.ready = false) (hn : c.launches ≤ n)
    (h : o.ended = true) : verdict c n o = .give .ended := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all [faultOf] <;> omega

theorem relaunch_has_launch_left (c : Cfg) (n : Nat) (o : Obs) (f : LaunchFault)
    (h : verdict c n o = .relaunch f) : n < c.launches ∧ o.ready = false := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all

theorem give_has_none_left (c : Cfg) (n : Nat) (o : Obs) (f : LaunchFault)
    (h : verdict c n o = .give f) : c.launches ≤ n ∧ o.ready = false := by
  rcases verdict_cases c n o with h1 | h1 | h1 | h1 <;> simp_all

structure Traj where
  aliveAt : Option Nat
  readyAt : Option Nat
  endedAt : Option Nat
deriving Repr, BEq

def Traj.never : Traj := ⟨none, none, none⟩

def stopAt (c : Cfg) (t : Traj) : Nat :=
  let m := match t.readyAt with | some r => min c.launchMs r | none => c.launchMs
  match t.endedAt with | some e => min m e | none => m

theorem stopAt_le (c : Cfg) (t : Traj) : stopAt c t ≤ c.launchMs := by
  unfold stopAt
  cases t.readyAt <;> cases t.endedAt <;> simp <;> omega

def reached (x : Option Nat) (at_ : Nat) : Bool :=
  match x with | some v => decide (v ≤ at_) | none => false

def obsAt (t : Traj) (x : Nat) : Obs :=
  ⟨reached t.readyAt x, reached t.aliveAt x, reached t.endedAt x, x⟩

structure Result where
  ready : Bool
  faults : List LaunchFault
  ms : Nat
deriving Repr, BEq

def drive (c : Cfg) : Nat → Nat → List Traj → Result
  | 0, _, _ => ⟨false, [], 0⟩
  | fuel + 1, n, ls =>
    let t := ls.headD Traj.never
    let x := stopAt c t
    match verdict c n (obsAt t x) with
    | .ready => ⟨true, [], x⟩
    | .relaunch f =>
      let r := drive c fuel (n + 1) ls.tail
      ⟨r.ready, f :: r.faults, x + c.killMs + r.ms⟩
    | .give f => ⟨false, [f], x + c.killMs⟩
    | .wait => ⟨false, [], x⟩

def run (c : Cfg) (ls : List Traj) : Result := drive c c.launches 1 ls

theorem fate_not_wait (c : Cfg) (n : Nat) (t : Traj) : verdict c n (obsAt t (stopAt c t)) ≠ .wait := by
  rw [Ne, wait_iff]
  intro ⟨h1, h2, h3⟩
  unfold obsAt stopAt reached at h1 h2 h3
  simp only at h1 h2 h3
  cases hr : t.readyAt <;> cases he : t.endedAt <;> simp_all <;> omega

theorem drive_ms_le (c : Cfg) : ∀ (fuel n : Nat) (ls : List Traj), (drive c fuel n ls).ms ≤ fuel * (c.launchMs + c.killMs) := by
  intro fuel
  induction fuel with
  | zero => intro n ls; simp [drive]
  | succ k ih =>
    intro n ls
    have hs := stopAt_le c (ls.headD Traj.never)
    have := ih (n + 1) ls.tail
    have hm : (k + 1) * (c.launchMs + c.killMs) = k * (c.launchMs + c.killMs) + (c.launchMs + c.killMs) := Nat.succ_mul _ _
    simp only [drive]
    split <;> simp only <;> omega

theorem run_ms_le (c : Cfg) (ls : List Traj) : (run c ls).ms ≤ c.launches * (c.launchMs + c.killMs) :=
  drive_ms_le c c.launches 1 ls

theorem worst_fits : cfg.launches * (cfg.launchMs + cfg.killMs) ≤ Fw.Measure.WalkBudget.readyAllowMs := by decide

theorem restart_fits : restartCfg.launches * (restartCfg.launchMs + restartCfg.killMs) ≤ Fw.Measure.WalkBudget.readyAllowMs := by decide

theorem restart_never_relaunches (n : Nat) (hn : 1 ≤ n) (o : Obs) (f : LaunchFault) : verdict restartCfg n o ≠ .relaunch f := by
  intro h
  have := (relaunch_has_launch_left restartCfg n o f h).1
  have h1 : restartCfg.launches = 1 := rfl
  omega

theorem restart_run_fits (ls : List Traj) : (run restartCfg ls).ms ≤ Fw.Measure.WalkBudget.readyAllowMs :=
  Nat.le_trans (run_ms_le restartCfg ls) restart_fits

theorem run_fits (ls : List Traj) : (run cfg ls).ms ≤ Fw.Measure.WalkBudget.readyAllowMs :=
  Nat.le_trans (run_ms_le cfg ls) worst_fits

theorem run_first_ready (c : Cfg) (t : Traj) (ls : List Traj) (hl : 1 ≤ c.launches)
    (h : verdict c 1 (obsAt t (stopAt c t)) = .ready) : run c (t :: ls) = ⟨true, [], stopAt c t⟩ := by
  obtain ⟨k, hk⟩ : ∃ k, c.launches = k + 1 := ⟨c.launches - 1, by omega⟩
  simp [run, hk, drive, h]

theorem run_relaunch_named (c : Cfg) (t : Traj) (ls : List Traj) (f : LaunchFault) (hl : 1 < c.launches)
    (h : verdict c 1 (obsAt t (stopAt c t)) = .relaunch f) :
    (run c (t :: ls)).faults = f :: (drive c (c.launches - 1) 2 ls).faults := by
  obtain ⟨k, hk⟩ : ∃ k, c.launches = k + 1 := ⟨c.launches - 1, by omega⟩
  simp [run, hk, drive, h]

theorem run_single_launch (t : Traj) (ls : List Traj) (c : Cfg) (hc : c.launches = 1)
    (hr : (obsAt t (stopAt c t)).ready = false) :
    (run c (t :: ls)).ready = false ∧ (run c (t :: ls)).faults = [faultOf (obsAt t (stopAt c t))] := by
  have hd := fate_not_wait c 1 t
  have hg : verdict c 1 (obsAt t (stopAt c t)) = .give (faultOf (obsAt t (stopAt c t))) := by
    rcases verdict_cases c 1 (obsAt t (stopAt c t)) with h1 | h1 | h1 | h1 <;> simp_all
  simp [run, hc, drive, hg]

inductive StopAct where
  | wait
  | clean
  | lateBody
  | lateTeardown
deriving DecidableEq, Repr

def StopAct.name : StopAct → String
  | .wait => "wait"
  | .clean => "clean"
  | .lateBody => "driver-stop-late-body"
  | .lateTeardown => "driver-stop-late-teardown"

def stopStep (c : Cfg) (exited bodyEnded : Bool) (waitedMs : Nat) : StopAct :=
  if exited then .clean
  else if c.stopWaitMs ≤ waitedMs then (if bodyEnded then .lateTeardown else .lateBody)
  else .wait

theorem stop_clean (c : Cfg) (t : Bool) (w : Nat) : stopStep c true t w = .clean := by simp [stopStep]

theorem stop_late_body (c : Cfg) (w : Nat) (h : c.stopWaitMs ≤ w) : stopStep c false false w = .lateBody := by
  simp [stopStep, h]

theorem stop_late_teardown (c : Cfg) (w : Nat) (h : c.stopWaitMs ≤ w) : stopStep c false true w = .lateTeardown := by
  simp [stopStep, h]

theorem stop_wait (c : Cfg) (t : Bool) (w : Nat) (h : w < c.stopWaitMs) : stopStep c false t w = .wait := by
  have : ¬ c.stopWaitMs ≤ w := by omega
  simp [stopStep, this]

theorem stop_decides_by (c : Cfg) (exited t : Bool) (w : Nat) (h : c.stopWaitMs ≤ w) : stopStep c exited t w ≠ .wait := by
  cases exited <;> cases t <;> simp [stopStep, h]

theorem stop_late_split (c : Cfg) (w : Nat) (h : c.stopWaitMs ≤ w) :
    stopStep c false false w ≠ stopStep c false true w := by
  rw [stop_late_body c w h, stop_late_teardown c w h]; decide

theorem stop_late_names : StopAct.lateBody.name ≠ StopAct.lateTeardown.name ∧ StopAct.lateBody.name ≠ StopAct.clean.name
    ∧ StopAct.lateTeardown.name ≠ StopAct.clean.name := by decide

structure Gate where
  exitWaitMs : Nat
  checks : Nat
  gapMs : Nat
  probeMs : Nat
deriving Repr, BEq

def gate : Gate := ⟨120000, 2, 30000, 25000⟩

def Gate.waitMs (g : Gate) : Nat := g.exitWaitMs + g.checks * g.probeMs + (g.checks - 1) * g.gapMs

def resetCallMs : Nat := 15000

def restartMs (g : Gate) (c : Cfg) : Nat := g.waitMs + resetCallMs + c.launches * (c.launchMs + c.killMs)

def oldRestartMs (c : Cfg) : Nat := c.stopWaitMs + 35000 + c.launches * (c.launchMs + c.killMs)

def restartAllowMs : Nat := 700000

inductive GateAct where
  | waitExit
  | recheck
  | launch (overlap unsure : Bool)
deriving DecidableEq, Repr

def overlapName : String := "driver-restart-overlap"

def unsureName : String := "driver-restart-device-unsure"

def GateAct.names : GateAct → List String
  | .launch o u => (if o then [overlapName] else []) ++ (if u then [unsureName] else [])
  | _ => []

def GateAct.name : GateAct → String
  | .waitExit => "wait-exit"
  | .recheck => "recheck"
  | .launch o u => match GateAct.names (.launch o u) with
    | [] => "launch"
    | ns => "launch:" ++ String.intercalate "," ns

def gateStep (g : Gate) (exited : Bool) (waitedMs : Nat) (deviceOk : Bool) (checked : Nat) : GateAct :=
  if !exited && waitedMs < g.exitWaitMs then .waitExit
  else if !deviceOk && checked < g.checks then .recheck
  else .launch (!exited) (!deviceOk)

theorem gate_wait_exit (g : Gate) (ok : Bool) (k w : Nat) (h : w < g.exitWaitMs) : gateStep g false w ok k = .waitExit := by
  simp [gateStep, h]

theorem gate_recheck (g : Gate) (e : Bool) (k w : Nat) (hk : k < g.checks) (hw : e = true ∨ g.exitWaitMs ≤ w) :
    gateStep g e w false k = .recheck := by
  rcases hw with rfl | hw
  · simp [gateStep, hk]
  · have : ¬ w < g.exitWaitMs := by omega
    simp [gateStep, this, hk]

theorem gate_launch_clean (g : Gate) (k w : Nat) : gateStep g true w true k = .launch false false := by
  simp [gateStep]

theorem gate_launch_overlap (g : Gate) (k w : Nat) (hw : g.exitWaitMs ≤ w) : gateStep g false w true k = .launch true false := by
  have : ¬ w < g.exitWaitMs := by omega
  simp [gateStep, this]

theorem gate_launch_unsure (g : Gate) (k w : Nat) (hk : g.checks ≤ k) : gateStep g true w false k = .launch false true := by
  have : ¬ k < g.checks := by omega
  simp [gateStep, this]

theorem gate_launch_both (g : Gate) (k w : Nat) (hw : g.exitWaitMs ≤ w) (hk : g.checks ≤ k) :
    gateStep g false w false k = .launch true true := by
  have h1 : ¬ w < g.exitWaitMs := by omega
  have h2 : ¬ k < g.checks := by omega
  simp [gateStep, h1, h2]

theorem gate_decides (g : Gate) (e ok : Bool) (k w : Nat) (hw : g.exitWaitMs ≤ w) (hk : g.checks ≤ k) :
    gateStep g e w ok k = .launch (!e) (!ok) := by
  have h1 : ¬ w < g.exitWaitMs := by omega
  have h2 : ¬ k < g.checks := by omega
  simp [gateStep, h1, h2]

theorem gate_names_distinct : overlapName ≠ unsureName ∧ overlapName ≠ StopAct.lateBody.name ∧ overlapName ≠ StopAct.lateTeardown.name
    ∧ unsureName ≠ StopAct.lateBody.name ∧ unsureName ≠ StopAct.lateTeardown.name := by decide

theorem gate_names_not_launch_faults : ∀ f ∈ LaunchFault.all, f.name ≠ overlapName ∧ f.name ≠ unsureName := by decide

theorem gate_names_not_walk_faults : ∀ f ∈ Fw.Measure.FaultNames.Fault.all, f.name ≠ overlapName ∧ f.name ≠ unsureName := by decide

theorem gate_wait_value : gate.waitMs = 200000 := by decide

theorem restart_total_value : restartMs gate restartCfg = 695000 := by decide

theorem restart_fits_allow : restartMs gate restartCfg ≤ restartAllowMs := by decide

theorem restart_added_le : restartMs gate restartCfg ≤ oldRestartMs restartCfg + 160000 := by decide

theorem restart_pair_fits : Fw.Measure.WalkBudget.setupWorstMs + 2 * restartAllowMs ≤ Fw.Measure.WalkBudget.deadlineAt Fw.Measure.WalkBudget.job := by decide

theorem restart_pair_exact : Fw.Measure.WalkBudget.setupWorstMs + 2 * restartMs gate restartCfg + 100000 ≤ Fw.Measure.WalkBudget.deadlineAt Fw.Measure.WalkBudget.job := by decide

inductive ResetAct where
  | skip
  | run
deriving DecidableEq, Repr

def resetAct : GateAct → ResetAct
  | .launch false _ => .run
  | _ => .skip

def ResetAct.name : ResetAct → String
  | .skip => "skip"
  | .run => "run"

theorem reset_runs_after_exit (u : Bool) : resetAct (.launch false u) = .run := rfl

theorem reset_skips_overlap (u : Bool) : resetAct (.launch true u) = .skip := rfl

theorem reset_skips_undecided : resetAct .waitExit = .skip ∧ resetAct .recheck = .skip := ⟨rfl, rfl⟩

theorem reset_only_after_launch (a : GateAct) (h : resetAct a = .run) : ∃ u, a = .launch false u := by
  cases a with
  | waitExit => simp [resetAct] at h
  | recheck => simp [resetAct] at h
  | launch o u => cases o <;> simp [resetAct] at h ⊢

inductive CallEnd where
  | ended
  | absent
  | late
  | failed
deriving DecidableEq, Repr

def callEnd (timedOut : Bool) (code : Nat) (nothingToTerminate : Bool) : CallEnd :=
  if timedOut then .late else if code = 0 then .ended else if nothingToTerminate then .absent else .failed

theorem call_late (c : Nat) (n : Bool) : callEnd true c n = .late := by simp [callEnd]

theorem call_ended (n : Bool) : callEnd false 0 n = .ended := by simp [callEnd]

theorem call_absent (c : Nat) (h : c ≠ 0) : callEnd false c true = .absent := by simp [callEnd, h]

theorem call_failed (c : Nat) (h : c ≠ 0) : callEnd false c false = .failed := by simp [callEnd, h]

def CallEnd.name : CallEnd → String
  | .ended => "ended"
  | .absent => "absent"
  | .late => "late"
  | .failed => "failed"

def resetLateName : String := "driver-restart-reset-late"

def resetFailedName : String := "driver-restart-reset-failed"

def resetNames (ends : List CallEnd) : List String :=
  (if ends.contains .late then [resetLateName] else []) ++ (if ends.contains .failed then [resetFailedName] else [])

def GateAct.nameWith (a : GateAct) (ends : List CallEnd) : String :=
  match a with
  | .launch o _ =>
    match GateAct.names a ++ (if o then [] else resetNames ends) with
    | [] => "launch"
    | ns => "launch:" ++ String.intercalate "," ns
  | _ => a.name

theorem nameWith_nil (a : GateAct) : a.nameWith [] = a.name := by
  cases a with
  | waitExit => rfl
  | recheck => rfl
  | launch o u => cases o <;> cases u <;> rfl

theorem nameWith_overlap (u : Bool) (ends : List CallEnd) : (GateAct.launch true u).nameWith ends = (GateAct.launch true u).name := by
  cases u <;> rfl

theorem nameWith_undecided (ends : List CallEnd) : GateAct.waitExit.nameWith ends = "wait-exit" ∧ GateAct.recheck.nameWith ends = "recheck" := ⟨rfl, rfl⟩

theorem nameWith_clean (u : Bool) : (GateAct.launch false u).nameWith [.ended, .absent] = (GateAct.launch false u).name := by
  cases u <;> rfl

theorem nameWith_late_only : (GateAct.launch false false).nameWith [.late, .ended] = "launch:driver-restart-reset-late" := by decide

theorem nameWith_failed_only : (GateAct.launch false false).nameWith [.absent, .failed] = "launch:driver-restart-reset-failed" := by decide

theorem nameWith_both : (GateAct.launch false true).nameWith [.late, .failed] =
    "launch:driver-restart-device-unsure,driver-restart-reset-late,driver-restart-reset-failed" := by decide

theorem reset_names_distinct : resetLateName ≠ resetFailedName ∧ resetLateName ≠ overlapName ∧ resetLateName ≠ unsureName
    ∧ resetFailedName ≠ overlapName ∧ resetFailedName ≠ unsureName := by decide

theorem reset_names_not_other_faults : (∀ f ∈ LaunchFault.all, f.name ≠ resetLateName ∧ f.name ≠ resetFailedName)
    ∧ (∀ f ∈ Fw.Measure.FaultNames.Fault.all, f.name ≠ resetLateName ∧ f.name ≠ resetFailedName)
    ∧ (resetLateName ≠ StopAct.lateBody.name ∧ resetLateName ≠ StopAct.lateTeardown.name
      ∧ resetFailedName ≠ StopAct.lateBody.name ∧ resetFailedName ≠ StopAct.lateTeardown.name) := by decide

theorem reset_value : resetCallMs = 15000 := by decide

theorem restart_adds_reset : restartMs gate restartCfg = gate.waitMs + resetCallMs + (restartCfg.launches * (restartCfg.launchMs + restartCfg.killMs)) := rfl

structure Job where
  launchFaults : List LaunchFault
  ready : Bool
deriving Repr, BEq

structure Tally where
  jobs : Nat
  ready : Nat
  firstTry : Nat
  relaunched : Nat
  launchStuck : Nat
  bodyStuck : Nat
  ended : Nat
deriving Repr, BEq

def count (f : LaunchFault) (js : List Job) : Nat :=
  js.foldl (fun a j => a + (j.launchFaults.filter (· == f)).length) 0

def tally (js : List Job) : Tally :=
  ⟨js.length, (js.filter (·.ready)).length, (js.filter fun j => j.ready && j.launchFaults.isEmpty).length,
    (js.filter fun j => !j.launchFaults.isEmpty).length, count .launchStuck js, count .bodyStuck js, count .ended js⟩

theorem filter_length_mono (p q : Job → Bool) (h : ∀ a, p a = true → q a = true) :
    ∀ js : List Job, (js.filter p).length ≤ (js.filter q).length
  | [] => by simp
  | a :: t => by
    have ih := filter_length_mono p q h t
    by_cases hp : p a = true
    · have hq := h a hp
      simp [hp, hq]
      omega
    · by_cases hq : q a = true <;> simp [hp, hq] <;> omega

theorem tally_first_try_le (js : List Job) : (tally js).firstTry ≤ (tally js).ready := by
  simp only [tally]
  exact filter_length_mono _ _ (by intro j hj; simp_all) js

theorem tally_ready_le (js : List Job) : (tally js).ready ≤ (tally js).jobs := by
  simp only [tally]
  exact List.length_filter_le _ _

def obsCases : List (String × Nat × Obs) := [
  ("ready at once", 1, ⟨true, true, false, 40000⟩),
  ("ready wins over ended", 1, ⟨true, true, true, 40000⟩),
  ("ready wins at the cap", 3, ⟨true, true, false, 150000⟩),
  ("waiting before the cap", 1, ⟨false, false, false, 149999⟩),
  ("launch stuck at the cap, a launch left", 1, ⟨false, false, false, 150000⟩),
  ("body stuck at the cap, a launch left", 2, ⟨false, true, false, 150000⟩),
  ("ended early, a launch left", 1, ⟨false, true, true, 3000⟩),
  ("ended before alive, a launch left", 2, ⟨false, false, true, 3000⟩),
  ("launch stuck, last launch", 3, ⟨false, false, false, 150000⟩),
  ("body stuck, last launch", 3, ⟨false, true, false, 151000⟩),
  ("ended, last launch", 3, ⟨false, false, true, 100⟩)]

def actName : Act → String
  | .wait => "wait"
  | .ready => "ready"
  | .relaunch f => "relaunch:" ++ f.name
  | .give f => "give:" ++ f.name

def trajCases : List (String × List Traj) := [
  ("ready on the first launch", [⟨some 30000, some 62000, none⟩]),
  ("ready at the cap", [⟨some 30000, some 150000, none⟩]),
  ("launch stuck once, then ready", [⟨none, none, none⟩, ⟨some 20000, some 50000, none⟩]),
  ("body stuck once, then ready", [⟨some 114000, none, none⟩, ⟨some 20000, some 50000, none⟩]),
  ("ended once, then ready", [⟨some 5000, none, some 9000⟩, ⟨some 20000, some 50000, none⟩]),
  ("ready after the cap counts as stuck", [⟨some 30000, some 150001, none⟩, ⟨some 30000, some 60000, none⟩]),
  ("ended after ready is ready", [⟨some 30000, some 62000, some 70000⟩]),
  ("ended before ready", [⟨some 30000, some 62000, some 40000⟩, ⟨some 30000, some 62000, none⟩]),
  ("stuck three times", [⟨none, none, none⟩, ⟨none, none, none⟩, ⟨none, none, none⟩]),
  ("two stuck, third ready", [⟨none, none, none⟩, ⟨some 100000, none, none⟩, ⟨some 30000, some 90000, none⟩]),
  ("no launch ever", [])]

def restartTrajCases : List (String × List Traj) := [
  ("ready at 220 s", [⟨some 215000, some 220000, none⟩]),
  ("ready at the cap", [⟨some 460000, some 470000, none⟩]),
  ("slow past the cap is abandoned", [⟨some 469000, some 470001, none⟩]),
  ("never alive", [⟨none, none, none⟩]),
  ("ended before ready", [⟨some 5000, none, some 9000⟩])]

def stopCases : List (Bool × Bool × Nat) := [(true, false, 0), (true, true, 25000), (false, false, 0), (false, true, 19999), (false, false, 19999),
  (false, false, 20000), (false, true, 20000), (false, false, 60000), (false, true, 60000)]

def gateCases : List (Bool × Nat × Bool × Nat) := [(true, 0, true, 0), (true, 5000, false, 0), (true, 5000, false, 1), (true, 5000, false, 2), (false, 0, true, 0),
  (false, 119999, true, 0), (false, 119999, false, 2), (false, 120000, true, 0), (false, 120000, false, 0), (false, 120000, false, 1), (false, 120000, false, 2),
  (false, 300000, true, 2)]

def callCases : List (Bool × Nat × Bool) := [(false, 0, false), (false, 0, true), (false, 3, true), (false, 149, false), (false, 1, false), (true, 0, false), (true, 3, true), (true, 149, false)]

def resetCases : List (Bool × Bool × List CallEnd) := [
  (false, false, [.ended, .ended]), (false, false, [.ended, .absent]), (false, false, [.absent, .absent]), (false, false, [.late, .ended]), (false, false, [.ended, .failed]),
  (false, false, [.late, .failed]), (false, true, [.absent, .absent]), (false, true, [.failed, .failed]), (false, true, [.late, .late]),
  (true, false, [.late, .failed]), (true, true, [.late, .failed]), (true, true, [])]

def jobCases : List (String × List Job) := [
  ("empty", []),
  ("all first try", [⟨[], true⟩, ⟨[], true⟩]),
  ("one relaunched ready, one lost", [⟨[.launchStuck], true⟩, ⟨[.launchStuck, .bodyStuck, .ended], false⟩]),
  ("mixed", [⟨[], true⟩, ⟨[.bodyStuck], true⟩, ⟨[.ended, .ended], true⟩, ⟨[.launchStuck, .launchStuck, .launchStuck], false⟩])]

open Lean in
def trajJson (t : Traj) : Json :=
  let o (x : Option Nat) : Json := match x with | some v => toJson v | none => Json.null
  Json.mkObj [("aliveAt", o t.aliveAt), ("readyAt", o t.readyAt), ("endedAt", o t.endedAt)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("launches", toJson cfg.launches), ("launchMs", toJson cfg.launchMs),
    ("killMs", toJson cfg.killMs), ("stopWaitMs", toJson cfg.stopWaitMs),
    ("restartLaunches", toJson restartCfg.launches), ("restartLaunchMs", toJson restartCfg.launchMs), ("readyAllowMs", toJson Fw.Measure.WalkBudget.readyAllowMs),
    ("names", Json.arr (LaunchFault.all.map (fun f => Json.str f.name)).toArray),
    ("stopLateNames", Json.arr #[Json.str StopAct.lateBody.name, Json.str StopAct.lateTeardown.name]),
    ("gateExitWaitMs", toJson gate.exitWaitMs), ("gateChecks", toJson gate.checks), ("gateGapMs", toJson gate.gapMs), ("gateProbeMs", toJson gate.probeMs),
    ("restartAllowMs", toJson restartAllowMs), ("restartMs", toJson (restartMs gate restartCfg)),
    ("gateNames", Json.arr #[Json.str overlapName, Json.str unsureName]), ("resetCallMs", toJson resetCallMs),
    ("resetNames", Json.arr #[Json.str resetLateName, Json.str resetFailedName])]).compress
  let ds := obsCases.map fun (name, n, o) =>
    (Json.mkObj [("op", "decide"), ("case", Json.str name), ("n", toJson n),
      ("obs", Json.mkObj [("ready", toJson o.ready), ("alive", toJson o.alive), ("ended", toJson o.ended), ("elapsed", toJson o.elapsed)]),
      ("act", Json.str (actName (verdict cfg n o)))]).compress
  let rs := trajCases.map fun (name, ls) =>
    let r := run cfg ls
    (Json.mkObj [("op", "run"), ("case", Json.str name), ("trajs", Json.arr (ls.map trajJson).toArray), ("ready", toJson r.ready),
      ("faults", Json.arr (r.faults.map (fun f => Json.str f.name)).toArray), ("ms", toJson r.ms)]).compress
  let rr := restartTrajCases.map fun (name, ls) =>
    let r := run restartCfg ls
    (Json.mkObj [("op", "runRestart"), ("case", Json.str name), ("trajs", Json.arr (ls.map trajJson).toArray), ("ready", toJson r.ready),
      ("faults", Json.arr (r.faults.map (fun f => Json.str f.name)).toArray), ("ms", toJson r.ms)]).compress
  let ss := stopCases.map fun (exited, ended, w) =>
    (Json.mkObj [("op", "stop"), ("exited", toJson exited), ("bodyEnded", toJson ended), ("waitedMs", toJson w),
      ("act", Json.str (stopStep cfg exited ended w).name)]).compress
  let gs := gateCases.map fun (exited, w, ok, k) =>
    (Json.mkObj [("op", "gate"), ("exited", toJson exited), ("waitedMs", toJson w), ("deviceOk", toJson ok), ("checked", toJson k),
      ("act", Json.str (gateStep gate exited w ok k).name)]).compress
  let cs := callCases.map fun (timedOut, code, nothing) =>
    (Json.mkObj [("op", "call"), ("timedOut", toJson timedOut), ("code", toJson code), ("nothingToTerminate", toJson nothing),
      ("end", Json.str (callEnd timedOut code nothing).name)]).compress
  let ps := resetCases.map fun (overlap, unsure, ends) =>
    let a := GateAct.launch overlap unsure
    (Json.mkObj [("op", "reset"), ("overlap", toJson overlap), ("unsure", toJson unsure), ("ends", Json.arr (ends.map fun e => Json.str e.name).toArray),
      ("reset", Json.str (resetAct a).name), ("act", Json.str (a.nameWith ends))]).compress
  let ts := jobCases.map fun (name, js) =>
    let t := tally js
    (Json.mkObj [("op", "tally"), ("case", Json.str name),
      ("jobs", Json.arr (js.map fun j => Json.mkObj [("faults", Json.arr (j.launchFaults.map (fun f => Json.str f.name)).toArray), ("ready", toJson j.ready)]).toArray),
      ("out", Json.mkObj [("jobs", toJson t.jobs), ("ready", toJson t.ready), ("firstTry", toJson t.firstTry), ("relaunched", toJson t.relaunched),
        ("driver-launch-stuck", toJson t.launchStuck), ("driver-body-stuck", toJson t.bodyStuck), ("driver-ended", toJson t.ended)])]).compress
  [consts] ++ ds ++ rs ++ rr ++ ss ++ gs ++ cs ++ ps ++ ts

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def goldenMain (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"touch-ready golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"touch-ready golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard verdict cfg 1 ⟨true, false, false, 0⟩ == .ready
#guard (run cfg [⟨none, none, none⟩, ⟨some 20000, some 50000, none⟩]).faults == [.launchStuck]
#guard (run cfg []).ready == false
#guard gateStep gate false 0 true 0 == .waitExit
#guard gateStep gate true 0 false 0 == .recheck
#guard gateStep gate false 120000 false 2 == .launch true true
#guard (GateAct.launch false false).nameWith [.late, .failed] == "launch:driver-restart-reset-late,driver-restart-reset-failed"
#guard resetAct (.launch true false) == .skip

end Fw.Measure.TouchReady
