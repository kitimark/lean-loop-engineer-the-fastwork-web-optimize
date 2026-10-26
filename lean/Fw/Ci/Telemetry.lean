import Lean.Data.Json
import Fw.Obs.Timing
import Fw.Ops.Wire
import Fw.Wire.Sched
import Fw.Wire.Obs
import Fw.Measure.SimBound
/-!
# CI telemetry record (task `ci-telemetry`): one job on one provider, its step spans and resource probes
Slow verdicts over the spans are `Fw.Obs.Timing`'s, keyed by (lane, job/step, provider, runner class).
-/
namespace Fw.Ci.Telemetry

/-- The CI providers whose jobs write a record. -/
inductive Provider where
  | github
  | circleci
deriving DecidableEq, Repr

/-- The wire name of a provider. -/
def Provider.tag : Provider → String
  | .github => "github"
  | .circleci => "circleci"

/-- The machine a job ran on: os, arch, cpu model, cores, memory in MB. -/
structure Machine where
  os : String
  arch : String
  cpu : String
  cores : Nat
  memMb : Nat
deriving DecidableEq, Repr

/-- One command of a job: name, start and end in epoch ms, exit code, bytes downloaded when the tool reported them. -/
structure Step where
  name : String
  startMs : Nat
  endMs : Nat
  exit : Option Nat := none
  netBytes : Option Nat := none
deriving DecidableEq, Repr

structure Probe where
  atMs : Nat
  cpuPct : Nat
  memUsedMb : Nat
  loadCenti : Nat
  diskFreeMb : Nat
  swapUsedMb : Option Nat := none
  compressorMb : Option Nat := none
  storedMb : Option Nat := none
  swapOuts : Option Nat := none
  compressions : Option Nat := none
  pressureLevel : Option Nat := none
  freePct : Option Nat := none
deriving DecidableEq, Repr

structure CacheUse where
  key : String
  hit : Bool
  restoredBytes : Nat
  savedBytes : Nat
deriving DecidableEq, Repr

/-- The telemetry of one job; `createdMs` is the provider's queue start, known to the collector only. -/
structure Record where
  provider : Provider
  lane : String
  job : String
  runId : String
  commit : String
  cls : String
  machine : Machine
  createdMs : Option Nat := none
  startedMs : Nat
  endedMs : Nat
  steps : List Step := []
  probes : List Probe := []
  caches : List CacheUse := []
  simBootMs : Option Nat := none
deriving DecidableEq, Repr

open Fw.Obs.Timing (Sample SampleVerdict Params Code)

/-- The history key part naming provider and runner class. -/
def kindOf (pv : Provider) (cls : String) : String := pv.tag ++ "/" ++ cls

/-- Duration of a step in ms. -/
def Step.durMs (s : Step) : Nat := s.endMs - s.startMs

/-- A timing sample with the run and job it came from. -/
structure Span where
  runId : String
  job : String
  name : String
  sample : Sample
deriving DecidableEq, Repr

/-- The named durations of a record in order: queue time when known, each step, simulator boot when known, the whole job. -/
def Record.parts (r : Record) : List (String × Nat) :=
  (r.createdMs.toList.map fun c => ("(queue)", r.startedMs - c)) ++ r.steps.map (fun s => (s.name, s.durMs)) ++
    (r.simBootMs.toList.map fun b => ("(sim boot)", b)) ++ [("(job)", r.endedMs - r.startedMs)]

/-- The text that spells the k-th try of a name: the name itself for k = 0, then name#1, name#2 and so on. -/
def tryName (name : String) (k : Nat) : String := if k = 0 then name else name ++ "#" ++ toString k

/-- The first try of the name that no earlier key uses. Out of tries (never, the tries outnumber the used keys) it
returns the used keys joined and one more character, which is longer than each of them. -/
def freshGo (used : List String) (name : String) : Nat → Nat → String
  | 0, _ => String.join used ++ "#"
  | f + 1, k => if tryName name k ∈ used then freshGo used name f (k + 1) else tryName name k

/-- The key of a name given the keys already taken in its record. -/
def freshKey (used : List String) (name : String) : String := freshGo used name (used.length + 1) 0

/-- The keys of a list of names: a repeated name gets name#1, name#2 and so on, so no two keys are equal. -/
def keysFrom (used : List String) : List String → List String
  | [] => []
  | n :: rest => let k := freshKey used n; k :: keysFrom (k :: used) rest

/-- The timing samples of a record. A step name repeated inside one job is told apart by its occurrence index, so
each step has its own history key. -/
def Record.spans (r : Record) : List Span :=
  let ps := r.parts
  (List.zip (keysFrom [] (ps.map (·.1))) (ps.map (·.2))).map fun (name, d) =>
    { runId := r.runId, job := r.job, name,
      sample := { tool := r.lane, step := r.job ++ "/" ++ name, durMs := d, host := .ci, kind := kindOf r.provider r.cls } }

/-- Records in start-time order. -/
def byStart (rs : List Record) : List Record := rs.mergeSort (fun a b => decide (a.startedMs ≤ b.startedMs))

/-- The spans of all records in start-time order. -/
def spansOf (rs : List Record) : List Span := (byStart rs).flatMap Record.spans

/-- Each span with the Timing verdict against the spans before it. -/
def judged (p : Params) (ts : List Span) : List (Span × SampleVerdict) :=
  ts.mapIdx fun i t => (t, Fw.Obs.Timing.judgeQ p ((ts.map (·.sample)).take i) i t.sample)

/-- Spans whose verdict is slow: the investigate items. -/
def slowItems (p : Params) (ts : List Span) : List (Span × SampleVerdict) :=
  (judged p ts).filter fun x => decide (x.2.code = .slow)

/-- The investigate subject of a slow span: tool/step#kind. -/
def Span.subject (t : Span) : String := t.sample.tool ++ "/" ++ t.sample.step ++ "#" ++ t.sample.kind

/-- Defaults for telemetry: three earlier runs make a baseline, a step must also exceed 5 s. -/
def telemetryParams : Params := { nMin := 3, budgetMs := 5000 }

theorem kindOf_inj {p q : Provider} {c d : String} (h : kindOf p c = kindOf q d) : p = q ∧ c = d := by
  have h' := congrArg String.toList h
  simp only [kindOf, String.toList_append] at h'
  cases p <;> cases q <;> simp [Provider.tag] at h' <;> exact ⟨rfl, String.toList_inj.1 h'⟩

theorem judged_verdicts (p : Params) (ts : List Span) :
    (judged p ts).map (·.2) = Fw.Obs.Timing.sampleVerdicts p (ts.map (·.sample)) := by
  apply List.ext_getElem?
  intro i
  cases h : ts[i]? <;> simp [judged, Fw.Obs.Timing.sampleVerdicts, h]

theorem mem_slowItems (p : Params) (ts : List Span) (x : Span × SampleVerdict) :
    x ∈ slowItems p ts ↔ x ∈ judged p ts ∧ x.2.code = .slow := by
  simp [slowItems]

theorem slow_of_ceiling (p : Params) (hist : List Sample) (i : Nat) (t : Span)
    (h : Fw.Obs.Timing.ceilingBreach p t.sample = true) : (Fw.Obs.Timing.judge p hist i t.sample).code = .slow :=
  (Fw.Obs.Timing.slow_iff p hist i t.sample).2 (Or.inl h)

theorem slow_of_window (p : Params) (hist : List Sample) (i : Nat) (t : Span)
    (hn : p.nMin ≤ (Fw.Obs.Timing.windowOf p hist t.sample.key).length) (hq : Fw.Obs.Timing.contended p t.sample = false)
    (hB : Fw.Obs.Timing.budgetOf p t.sample.tool < t.sample.durMs)
    (hk : p.kNum * Fw.Obs.Timing.p50 (Fw.Obs.Timing.windowOf p hist t.sample.key) < p.kDen * t.sample.durMs) :
    (Fw.Obs.Timing.judge p hist i t.sample).code = .slow :=
  (Fw.Obs.Timing.slow_iff p hist i t.sample).2 (Or.inr ⟨hn, hq, hB, hk⟩)

theorem not_slow_of_neither (p : Params) (hist : List Sample) (i : Nat) (t : Span)
    (hc : Fw.Obs.Timing.ceilingBreach p t.sample = false)
    (hw : ¬ (p.nMin ≤ (Fw.Obs.Timing.windowOf p hist t.sample.key).length ∧ Fw.Obs.Timing.contended p t.sample = false ∧
      Fw.Obs.Timing.budgetOf p t.sample.tool < t.sample.durMs ∧
      p.kNum * Fw.Obs.Timing.p50 (Fw.Obs.Timing.windowOf p hist t.sample.key) < p.kDen * t.sample.durMs)) :
    (Fw.Obs.Timing.judge p hist i t.sample).code ≠ .slow := fun h =>
  ((Fw.Obs.Timing.slow_iff p hist i t.sample).1 h).elim (by simp [hc]) hw

theorem key_ne_of_class {p q : Provider} {c d : String} {s s' : Sample} (hs : s.kind = kindOf p c)
    (hs' : s'.kind = kindOf q d) (h : p ≠ q ∨ c ≠ d) : s.key ≠ s'.key := by
  intro hk
  have hk' : s.kind = s'.kind := congrArg Fw.Obs.Timing.Key.kind hk
  rw [hs, hs'] at hk'
  obtain ⟨h1, h2⟩ := kindOf_inj hk'
  exact h.elim (fun a => a h1) (fun a => a h2)

theorem window_unmoved (p : Params) (hist : List Sample) (s : Sample) (k : Fw.Obs.Timing.Key) (h : s.key ≠ k) :
    Fw.Obs.Timing.windowOf p (hist ++ [s]) k = Fw.Obs.Timing.windowOf p hist k := by
  simp [Fw.Obs.Timing.windowOf, List.filter_append, h]

theorem spans_kind (r : Record) (t : Span) (h : t ∈ r.spans) :
    t.sample.kind = kindOf r.provider r.cls ∧ t.sample.tool = r.lane ∧ t.sample.host = .ci := by
  simp only [Record.spans, List.mem_map] at h
  obtain ⟨_, _, rfl⟩ := h
  simp

theorem string_len_le_join (used : List String) (u : String) (h : u ∈ used) : u.length ≤ (String.join used).length := by
  rw [String.length_join]
  induction used with
  | nil => simp at h
  | cons a t ih =>
    simp only [List.map_cons, List.sum_cons]
    rcases List.mem_cons.1 h with rfl | h
    · omega
    · have := ih h; omega

theorem freshGo_not_mem (used : List String) (name : String) : ∀ f k, freshGo used name f k ∉ used := by
  intro f
  induction f with
  | zero =>
    intro k h
    have h1 := string_len_le_join used _ h
    have h2 : "#".length = 1 := by decide
    simp only [freshGo, String.length_append, h2] at h1
    omega
  | succ f ih =>
    intro k
    unfold freshGo
    split
    · exact ih _
    · assumption

/-- A key is never one of the keys taken before it. -/
theorem freshKey_not_mem (used : List String) (name : String) : freshKey used name ∉ used :=
  freshGo_not_mem used name _ _

theorem keysFrom_not_mem : ∀ (names used : List String), ∀ k ∈ keysFrom used names, k ∉ used := by
  intro names
  induction names with
  | nil => intro used k h; simp [keysFrom] at h
  | cons n rest ih =>
    intro used k h
    simp only [keysFrom, List.mem_cons] at h
    rcases h with rfl | h
    · exact freshKey_not_mem used n
    · intro hu
      exact ih _ k h (List.mem_cons_of_mem _ hu)

/-- The keys of any list of names are pairwise distinct. -/
theorem keysFrom_nodup : ∀ (names used : List String), (keysFrom used names).Nodup := by
  intro names
  induction names with
  | nil => intro used; simp [keysFrom]
  | cons n rest ih =>
    intro used
    simp only [keysFrom, List.nodup_cons]
    exact ⟨fun h => keysFrom_not_mem rest _ _ h (List.mem_cons_self ..), ih _⟩

theorem keysFrom_length : ∀ (names used : List String), (keysFrom used names).length = names.length := by
  intro names
  induction names with
  | nil => intro used; simp [keysFrom]
  | cons n rest ih => intro used; simp [keysFrom, ih]

/-- The samples of one record have pairwise distinct history steps, so no span of a run is judged against another span
of the same run through a shared key. -/
theorem spans_steps_nodup (r : Record) : (r.spans.map (·.sample.step)).Nodup := by
  have hk := keysFrom_nodup (r.parts.map (·.1)) []
  have hl : (keysFrom [] (r.parts.map (·.1))).length ≤ (r.parts.map (·.2)).length := by
    simp [keysFrom_length]
  have hfst := List.map_fst_zip hl
  have hinj : Function.Injective (fun k : String => r.job ++ "/" ++ k) := by
    intro a b h
    apply String.toList_inj.1
    have := congrArg String.toList h
    simp only [String.toList_append] at this
    exact List.append_cancel_left this
  have : r.spans.map (·.sample.step) =
      (List.map Prod.fst (List.zip (keysFrom [] (r.parts.map (·.1))) (r.parts.map (·.2)))).map (fun k => r.job ++ "/" ++ k) := by
    simp [Record.spans, List.map_map, Function.comp_def]
  rw [this, hfst]
  exact List.Pairwise.map _ (fun a b hab h => hab (hinj h)) hk

theorem byStart_perm (rs : List Record) : (byStart rs).Perm rs := List.mergeSort_perm _ _

theorem spansOf_nil : spansOf [] = [] := by simp [spansOf, byStart]

def callCapMs : Nat := 200000

def callGraceMs : Nat := 5000

def callBoundMs (limit : Nat) : Nat := min limit callCapMs

def callSettleMs (limit : Nat) : Nat := callBoundMs limit + callGraceMs

theorem callBound_le_limit (l : Nat) : callBoundMs l ≤ l := Nat.min_le_left _ _

theorem callBound_le_cap (l : Nat) : callBoundMs l ≤ callCapMs := Nat.min_le_right _ _

theorem callBound_of_le {l : Nat} (h : l ≤ callCapMs) : callBoundMs l = l := Nat.min_eq_left h

theorem callBound_of_gt {l : Nat} (h : callCapMs < l) : callBoundMs l = callCapMs := Nat.min_eq_right (Nat.le_of_lt h)

theorem callBound_mono {a b : Nat} (h : a ≤ b) : callBoundMs a ≤ callBoundMs b := by
  unfold callBoundMs; omega

theorem callSettle_le (l : Nat) : callSettleMs l ≤ callCapMs + callGraceMs := by
  unfold callSettleMs callBoundMs; omega

theorem retried_call_before_stall (gapMs : Nat) (h : gapMs ≤ 30000) :
    2 * callSettleMs 200000 + gapMs < Fw.Measure.SimBound.stallMs := by
  unfold callSettleMs callBoundMs callCapMs callGraceMs Fw.Measure.SimBound.stallMs; omega

def hostStalled (now last limit : Nat) : Bool := decide (limit < now - last)

theorem hostStalled_iff (now last limit : Nat) : hostStalled now last limit = true ↔ last + limit < now := by
  unfold hostStalled; simp only [decide_eq_true_eq]; omega

theorem hostStalled_fresh {now last limit : Nat} (h : now ≤ last + limit) : hostStalled now last limit = false := by
  unfold hostStalled; simp only [decide_eq_false_iff_not]; omega

theorem hostStalled_after_output (now limit : Nat) : hostStalled now now limit = false := by
  unfold hostStalled; simp only [decide_eq_false_iff_not]; omega

theorem hostStalled_mono {n m last limit : Nat} (h : n ≤ m) (hs : hostStalled n last limit = true) :
    hostStalled m last limit = true := by
  rw [hostStalled_iff] at *; omega

def lagMs (tick since : Nat) : Nat := since - tick

def tickBlocked (tick since : Nat) : Bool := decide (0 < tick ∧ tick ≤ lagMs tick since)

theorem tickBlocked_iff (tick since : Nat) : tickBlocked tick since = true ↔ 0 < tick ∧ 2 * tick ≤ since := by
  unfold tickBlocked lagMs; simp only [decide_eq_true_eq]; omega

theorem tickBlocked_on_time {tick since : Nat} (h : since < 2 * tick) : tickBlocked tick since = false := by
  unfold tickBlocked lagMs; simp only [decide_eq_false_iff_not]; omega

theorem tickBlocked_late {tick since : Nat} (hp : 0 < tick) (h : 2 * tick ≤ since) : tickBlocked tick since = true := by
  unfold tickBlocked lagMs; simp only [decide_eq_true_eq]; omega

theorem tickBlocked_no_tick (since : Nat) : tickBlocked 0 since = false := by
  unfold tickBlocked; simp

/-! ## Upload cadence of a Simulator job (task `macos-vm-upload`) -/

/-- Upload tick steps in `webkit-sim.yml`. -/
def tickSteps : Nat := 8

/-- Periodic ticks that fit inside one measuring step. -/
def periodicTicks : Nat := 4

/-- Passes one determinism session writes (`--runs 2`). -/
def passesPerSession : Nat := 2

/-- Minutes one tick upload may take. -/
def tickUploadMin : Nat := 2

/-- Minutes between two periodic probe uploads for a measuring step of `step` minutes. -/
def tickPeriodMin (step : Nat) : Nat := step / (periodicTicks + 1)

/-- Seconds between two periodic probe uploads. -/
def tickPeriodS (step : Nat) : Nat := 60 * tickPeriodMin step

/-- Why a tick step stops waiting. -/
inductive Why where
  | done
  | deadline
  | pass
  | period
deriving DecidableEq, Repr

/-- The wire name of a wake reason. -/
def Why.name : Why → String
  | .done => "done"
  | .deadline => "deadline"
  | .pass => "pass"
  | .period => "period"

/-- A tick step wakes when the measurement ended, its step bound is reached, a pass file is new, or the period since the last upload passed; the first
reason in this order wins. -/
def wakeWhy (elapsedS sinceS periodS stepS fresh : Nat) (done : Bool) : Option Why :=
  if done then some .done
  else if stepS ≤ elapsedS then some .deadline
  else if 0 < fresh then some .pass
  else if periodS ≤ sinceS then some .period
  else none

theorem wakeWhy_done (e s p t f : Nat) : wakeWhy e s p t f true = some .done := by
  simp [wakeWhy]

theorem wakeWhy_deadline {e s p t f : Nat} (h : t ≤ e) : wakeWhy e s p t f false = some .deadline := by
  simp [wakeWhy, h]

theorem wakeWhy_pass {e s p t f : Nat} (h : e < t) (hf : 0 < f) : wakeWhy e s p t f false = some .pass := by
  simp [wakeWhy, Nat.not_le.2 h, hf]

theorem wakeWhy_period {e s p t : Nat} (h : e < t) (hs : p ≤ s) : wakeWhy e s p t 0 false = some .period := by
  simp [wakeWhy, Nat.not_le.2 h, hs]

theorem wakeWhy_none {e s p t : Nat} (h : e < t) (hs : s < p) : wakeWhy e s p t 0 false = none := by
  simp [wakeWhy, Nat.not_le.2 h, Nat.not_le.2 hs]

theorem tickPeriod_le (step : Nat) : tickPeriodMin step ≤ step := by
  unfold tickPeriodMin periodicTicks; omega

theorem periodic_ticks_inside {step : Nat} (h : 1 ≤ step) : periodicTicks * tickPeriodMin step < step := by
  unfold tickPeriodMin periodicTicks; omega

theorem last_tick_lands_in_step {step : Nat} (h : 10 ≤ step) :
    periodicTicks * tickPeriodMin step + tickUploadMin ≤ step := by
  unfold tickPeriodMin periodicTicks tickUploadMin; omega

theorem two_periodic_ticks {step : Nat} (h : 5 ≤ step) :
    0 < tickPeriodMin step ∧ tickPeriodMin step < 2 * tickPeriodMin step ∧ 2 * tickPeriodMin step < step ∧ 2 ≤ periodicTicks := by
  unfold tickPeriodMin periodicTicks; omega

/-- **A telemetry upload lands before the job cap.** The first periodic upload of any measuring step ends before the job's timeout, with the tail still ahead. -/
theorem first_upload_before_cap (e : String) (k : Nat) :
    Fw.Measure.SimBound.setupMin + tickPeriodMin (Fw.Measure.SimBound.stepMin e k) + tickUploadMin <
      Fw.Measure.SimBound.jobMin e k := by
  have := tickPeriod_le (Fw.Measure.SimBound.stepMin e k)
  unfold Fw.Measure.SimBound.jobMin Fw.Measure.SimBound.tailMin tickUploadMin
  omega

/-- **The last periodic upload also ends inside the measuring step** for every allowed session count and for the quiet experiment. -/
theorem last_upload_before_step_end (k : Nat) (h : 1 ≤ k) :
    periodicTicks * tickPeriodMin (Fw.Measure.SimBound.stepMin "determinism" k) + tickUploadMin ≤ Fw.Measure.SimBound.stepMin "determinism" k := by
  apply last_tick_lands_in_step
  rw [Fw.Measure.SimBound.stepMin_determinism]
  unfold Fw.Measure.SimBound.perSessionMin; omega

theorem last_upload_before_quiet_end :
    periodicTicks * tickPeriodMin (Fw.Measure.SimBound.stepMin "quiet" 1) + tickUploadMin ≤ Fw.Measure.SimBound.stepMin "quiet" 1 := by
  decide

/-- **One session fits its ticks.** The periodic ticks, one wake per pass and the wake at the end need no more steps than the workflow has. -/
theorem ticks_cover_one_session : periodicTicks + passesPerSession + 1 ≤ tickSteps := by decide

#guard tickPeriodMin 35 == 7 && tickPeriodS 35 == 420 && tickPeriodMin 70 == 14 && tickPeriodMin 50 == 10
#guard (wakeWhy 0 0 420 2100 0 false).isNone && wakeWhy 420 420 420 2100 0 false == some .period

end Fw.Ci.Telemetry

namespace Fw.Wire.Ci.Telemetry
open Lean
open Fw.Ci.Telemetry
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr)
open Fw.Obs.Timing (Sample SampleVerdict Params)
open Fw.Wire.Sched (ok_bind mapM_rt arrD_arr)

/-- The schema version written to and required from every record. -/
def schemaVersion : Nat := 1

/-- An optional natural as a number or `null`. -/
def onat : Option Nat → Json
  | some n => toJson n
  | none => .null

/-- An optional natural field (absent or `null` is `none`). -/
def optN (j : Json) (k : String) : Except String (Option Nat) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asNat k v

/-- A list field decoded element by element (absent is empty). -/
def listD {α : Type} (j : Json) (k : String) (g : Json → Except String α) : Except String (List α) :=
  match opt j k with
  | none => .ok []
  | some v => do (← asArr k v).toList.mapM g

/-- Decode a provider name. -/
def providerOf (k : String) (j : Json) : Except String Provider := do
  match ← asStr k j with
  | "github" => pure .github
  | "circleci" => pure .circleci
  | p => throw s!"field {k}: unknown provider {p}"

/-- Encode a machine. -/
def machineJson (m : Machine) : Json :=
  Json.mkObj [("os", .str m.os), ("arch", .str m.arch), ("cpu", .str m.cpu), ("cores", toJson m.cores),
    ("memMb", toJson m.memMb)]

/-- Decode a machine. -/
def machineOf (j : Json) : Except String Machine := do
  pure { os := ← str j "os", arch := ← str j "arch", cpu := ← str j "cpu", cores := ← nat j "cores",
         memMb := ← nat j "memMb" }

/-- Encode a step. -/
def stepJson (s : Step) : Json :=
  Json.mkObj [("name", .str s.name), ("startMs", toJson s.startMs), ("endMs", toJson s.endMs),
    ("exit", onat s.exit), ("netBytes", onat s.netBytes)]

/-- Decode a step. -/
def stepOf (j : Json) : Except String Step := do
  pure { name := ← str j "name", startMs := ← nat j "startMs", endMs := ← nat j "endMs",
         exit := ← optN j "exit", netBytes := ← optN j "netBytes" }

def probeJson (p : Probe) : Json :=
  Json.mkObj [("atMs", toJson p.atMs), ("cpuPct", toJson p.cpuPct), ("memUsedMb", toJson p.memUsedMb),
    ("loadCenti", toJson p.loadCenti), ("diskFreeMb", toJson p.diskFreeMb), ("swapUsedMb", onat p.swapUsedMb),
    ("compressorMb", onat p.compressorMb), ("storedMb", onat p.storedMb), ("swapOuts", onat p.swapOuts),
    ("compressions", onat p.compressions), ("pressureLevel", onat p.pressureLevel), ("freePct", onat p.freePct)]

def probeOf (j : Json) : Except String Probe := do
  pure { atMs := ← nat j "atMs", cpuPct := ← nat j "cpuPct", memUsedMb := ← nat j "memUsedMb",
         loadCenti := ← nat j "loadCenti", diskFreeMb := ← nat j "diskFreeMb",
         swapUsedMb := ← optN j "swapUsedMb", compressorMb := ← optN j "compressorMb", storedMb := ← optN j "storedMb",
         swapOuts := ← optN j "swapOuts", compressions := ← optN j "compressions",
         pressureLevel := ← optN j "pressureLevel", freePct := ← optN j "freePct" }

def cacheJson (c : CacheUse) : Json :=
  Json.mkObj [("key", .str c.key), ("hit", .bool c.hit), ("restoredBytes", toJson c.restoredBytes),
    ("savedBytes", toJson c.savedBytes)]

/-- Decode a cache lookup. -/
def cacheOf (j : Json) : Except String CacheUse := do
  pure { key := ← str j "key", hit := ← asBool "hit" (← field j "hit"), restoredBytes := ← nat j "restoredBytes",
         savedBytes := ← nat j "savedBytes" }

/-- Encode the identity block of a record. -/
def identJson (r : Record) : Json :=
  Json.mkObj [("provider", .str r.provider.tag), ("lane", .str r.lane), ("job", .str r.job),
    ("runId", .str r.runId), ("commit", .str r.commit), ("class", .str r.cls)]

/-- Encode the times block of a record. -/
def timesJson (r : Record) : Json :=
  Json.mkObj [("createdMs", onat r.createdMs), ("startedMs", toJson r.startedMs), ("endedMs", toJson r.endedMs),
    ("simBootMs", onat r.simBootMs)]

/-- Encode a record. -/
def recordJson (r : Record) : Json :=
  Json.mkObj [("schema", toJson schemaVersion), ("ident", identJson r), ("machine", machineJson r.machine),
    ("times", timesJson r), ("steps", .arr (r.steps.toArray.map stepJson)),
    ("probes", .arr (r.probes.toArray.map probeJson)), ("cache", .arr (r.caches.toArray.map cacheJson))]

/-- Decode a record; a schema other than `schemaVersion` is refused. -/
def recordOf (j : Json) : Except String Record := do
  if (← nat j "schema") ≠ schemaVersion then throw s!"field schema: expected {schemaVersion}"
  let i ← field j "ident"
  let t ← field j "times"
  pure { provider := ← providerOf "provider" (← field i "provider"), lane := ← str i "lane", job := ← str i "job",
         runId := ← str i "runId", commit := ← str i "commit", cls := ← str i "class",
         machine := ← machineOf (← field j "machine"), createdMs := ← optN t "createdMs",
         startedMs := ← nat t "startedMs", endedMs := ← nat t "endedMs", steps := ← listD j "steps" stepOf,
         probes := ← listD j "probes" probeOf, caches := ← listD j "cache" cacheOf, simBootMs := ← optN t "simBootMs" }

theorem providerOf_tag (p : Provider) : providerOf "provider" (.str p.tag) = .ok p := by
  cases p <;> rfl

theorem machineOf_machineJson (m : Machine) : machineOf (machineJson m) = .ok m := by
  obtain ⟨os, arch, cpu, cores, memMb⟩ := m
  rfl

theorem stepOf_stepJson (s : Step) : stepOf (stepJson s) = .ok s := by
  obtain ⟨name, startMs, endMs, exit, netBytes⟩ := s
  cases exit <;> cases netBytes <;> rfl

private theorem optN_swapUsedMb (p : Probe) : optN (probeJson p) "swapUsedMb" = .ok p.swapUsedMb := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases f <;> rfl

private theorem optN_compressorMb (p : Probe) : optN (probeJson p) "compressorMb" = .ok p.compressorMb := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases g <;> rfl

private theorem optN_storedMb (p : Probe) : optN (probeJson p) "storedMb" = .ok p.storedMb := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases h <;> rfl

private theorem optN_swapOuts (p : Probe) : optN (probeJson p) "swapOuts" = .ok p.swapOuts := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases i <;> rfl

private theorem optN_compressions (p : Probe) : optN (probeJson p) "compressions" = .ok p.compressions := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases j <;> rfl

private theorem optN_pressureLevel (p : Probe) : optN (probeJson p) "pressureLevel" = .ok p.pressureLevel := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases k <;> rfl

private theorem optN_freePct (p : Probe) : optN (probeJson p) "freePct" = .ok p.freePct := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; cases l <;> rfl

private theorem nat_atMs (p : Probe) : nat (probeJson p) "atMs" = .ok p.atMs := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; rfl

private theorem nat_cpuPct (p : Probe) : nat (probeJson p) "cpuPct" = .ok p.cpuPct := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; rfl

private theorem nat_memUsedMb (p : Probe) : nat (probeJson p) "memUsedMb" = .ok p.memUsedMb := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; rfl

private theorem nat_loadCenti (p : Probe) : nat (probeJson p) "loadCenti" = .ok p.loadCenti := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; rfl

private theorem nat_diskFreeMb (p : Probe) : nat (probeJson p) "diskFreeMb" = .ok p.diskFreeMb := by
  obtain ⟨a, b, c, d, e, f, g, h, i, j, k, l⟩ := p; rfl

theorem probeOf_probeJson (p : Probe): probeOf (probeJson p) = .ok p := by
  simp only [probeOf, optN_swapUsedMb, optN_compressorMb, optN_storedMb, optN_swapOuts, optN_compressions,
    optN_pressureLevel, optN_freePct, nat_atMs, nat_cpuPct, nat_memUsedMb, nat_loadCenti, nat_diskFreeMb, ok_bind]
  rfl

theorem cacheOf_cacheJson (c : CacheUse) : cacheOf (cacheJson c) = .ok c := by
  obtain ⟨k, h, a, b⟩ := c
  rfl

theorem listD_rt {α : Type} (f : α → Json) (g : Json → Except String α) (h : ∀ a, g (f a) = .ok a)
    (j : Json) (k : String) (l : List α) (hj : j.getObjVal? k = .ok (.arr (l.toArray.map f))) :
    listD j k g = .ok l := by
  simp only [listD, opt, hj]
  simp only [Array.toList_map, ok_bind, asArr]
  exact mapM_rt f g h l

theorem recordOf_recordJson (r : Record) : recordOf (recordJson r) = .ok r := by
  have hs := listD_rt stepJson stepOf stepOf_stepJson (recordJson r) "steps" r.steps rfl
  have hp := listD_rt probeJson probeOf probeOf_probeJson (recordJson r) "probes" r.probes rfl
  have hc := listD_rt cacheJson cacheOf cacheOf_cacheJson (recordJson r) "cache" r.caches rfl
  have hm := machineOf_machineJson r.machine
  have hv := providerOf_tag r.provider
  have hi : field (recordJson r) "ident" = .ok (identJson r) := rfl
  have ht : field (recordJson r) "times" = .ok (timesJson r) := rfl
  have hmm : field (recordJson r) "machine" = .ok (machineJson r.machine) := rfl
  have hc1 : optN (timesJson r) "createdMs" = .ok r.createdMs := by cases h : r.createdMs <;> simp [timesJson, h] <;> rfl
  have hc2 : optN (timesJson r) "simBootMs" = .ok r.simBootMs := by cases h : r.simBootMs <;> simp [timesJson, h] <;> rfl
  have h0 : nat (recordJson r) "schema" = .ok schemaVersion := rfl
  have h1 : field (identJson r) "provider" = .ok (.str r.provider.tag) := rfl
  have h2 : str (identJson r) "lane" = .ok r.lane := rfl
  have h3 : str (identJson r) "job" = .ok r.job := rfl
  have h4 : str (identJson r) "runId" = .ok r.runId := rfl
  have h5 : str (identJson r) "commit" = .ok r.commit := rfl
  have h6 : str (identJson r) "class" = .ok r.cls := rfl
  have h7 : nat (timesJson r) "startedMs" = .ok r.startedMs := rfl
  have h8 : nat (timesJson r) "endedMs" = .ok r.endedMs := rfl
  simp only [recordOf, hs, hp, hc, hm, hv, hi, ht, hmm, hc1, hc2, h0, h1, h2, h3, h4, h5, h6, h7, h8, ok_bind,
    ne_eq, not_true_eq_false, ite_false]
  rfl


/-- The reply row of a judged span. -/
def spanJson (x : Span × SampleVerdict) : Json :=
  Json.mkObj [("runId", .str x.1.runId), ("job", .str x.1.job), ("name", .str x.1.name),
    ("tool", .str x.1.sample.tool), ("step", .str x.1.sample.step), ("kind", .str x.1.sample.kind),
    ("durMs", toJson x.1.sample.durMs), ("code", .str (Fw.Wire.Obs.Timing.codeStr x.2.code)),
    ("n", toJson x.2.n), ("baseline", toJson x.2.baseline), ("budgetMs", toJson x.2.budgetMs)]

/-- The reply row of a slow span: the investigate subject and the numbers behind it. -/
def slowJson (x : Span × SampleVerdict) : Json :=
  Json.mkObj [("subject", .str x.1.subject), ("runId", .str x.1.runId), ("job", .str x.1.job),
    ("name", .str x.1.name), ("durMs", toJson x.1.sample.durMs), ("baseline", toJson x.2.baseline),
    ("n", toJson x.2.n)]

/-- `ci.telemetry`: records (any order) and optional Timing params; one row per span in start order, and the slow ones. -/
def opTelemetry (req : Json) : Except String Reply := do
  let p ← match opt req "params" with
    | none => pure telemetryParams
    | some v => Fw.Wire.Obs.Timing.paramsOf v
  let rs ← (← arr req "records").toList.mapM recordOf
  let ts := spansOf rs
  pure [("spans", Json.arr ((judged p ts).toArray.map spanJson)), ("slow", Json.arr ((slowItems p ts).toArray.map slowJson))]

def opHostCall (req : Json) : Except String Reply := do
  match ← str req "what" with
  | "bound" =>
    let l ← nat req "limitMs"
    pure [("boundMs", toJson (callBoundMs l)), ("settleMs", toJson (callSettleMs l))]
  | "stall" =>
    pure [("stalled", Json.bool (hostStalled (← nat req "nowMs") (← nat req "lastMs") (← nat req "limitMs")))]
  | "lag" =>
    let t ← nat req "tickMs"
    let s ← nat req "sinceMs"
    pure [("lagMs", toJson (lagMs t s)), ("blocked", Json.bool (tickBlocked t s))]
  | w => throw s!"unknown what {w}"

def opUpload (req : Json) : Except String Reply := do
  match ← str req "upload" with
  | "period" =>
    let step ← nat req "stepMin"
    let p := tickPeriodMin step
    pure [("periodMin", toJson p), ("periodS", toJson (tickPeriodS step)), ("tickSteps", toJson tickSteps),
      ("atMin", toJson ((List.range periodicTicks).map fun i => (i + 1) * p))]
  | "wake" =>
    let w := wakeWhy (← nat req "elapsedS") (← nat req "sinceS") (← nat req "periodS") (← nat req "stepS") (← nat req "fresh") (← asBool "done" (← field req "done"))
    pure [("wake", Json.bool w.isSome), ("why", Json.str (match w with | some y => y.name | none => "none"))]
  | w => throw s!"unknown upload {w}"

def ops : List String := ["ci.telemetry"]

def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.telemetry" => some (match opt req "what", opt req "upload" with
      | some _, _ => opHostCall req
      | none, some _ => opUpload req
      | none, none => opTelemetry req)
  | _ => none


/-! ## Golden cases -/

/-- A request: the operation, optional params, the records. -/
def reqJson (rs : List Json) (params : Option Json := none) : Json :=
  Json.mkObj ([("op", Json.str "ci.telemetry"), ("records", Json.arr rs.toArray)] ++
    (params.map fun v => [("params", v)]).getD [])

/-- A job on `cls` starting at `t0` after `queue` ms in the queue; its steps run one after the other. -/
def mkRec (pv : Provider) (lane job cls runId : String) (t0 : Nat) (steps : List (String × Nat))
    (queue : Option Nat := some 4000) (sim : Option Nat := none) : Record :=
  let rec go : List (String × Nat) → Nat → List Step
    | [], _ => []
    | (n, d) :: rest, t => { name := n, startMs := t, endMs := t + d, exit := some 0 } :: go rest (t + d)
  { provider := pv, lane, job, runId, commit := "92403f8", cls,
    machine := { os := "linux", arch := "x64", cpu := "x86_64 test cpu", cores := 4, memMb := 16000 },
    createdMs := queue.map (t0 - ·), startedMs := t0, endedMs := t0 + (steps.map (·.2)).foldl (· + ·) 0,
    steps := go steps t0,
    probes := [{ atMs := t0 + 5000, cpuPct := 40, memUsedMb := 2000, loadCenti := 150, diskFreeMb := 60000 }],
    caches := [{ key := "pnpm-store", hit := true, restoredBytes := 100000000, savedBytes := 0 }],
    simBootMs := sim }

/-- The base time of the cases: 2025-10-09 08:53:20 UTC in ms. -/
def t0 : Nat := 1760000000000

/-- Steps of a gate job with the given install duration in s. -/
def gateSteps (install : Nat) : List (String × Nat) :=
  [("checkout", 3000), ("setup pnpm", 12000), ("install", install * 1000), ("measure", 55000)]

/-- Three earlier runs of the gate job on `cls`, installing for 40, 42 and 41 s. -/
def hist3 (pv : Provider) (cls : String) : List Record :=
  [mkRec pv "breakpoint-gate" "gate (chromium, s0)" cls "r1" t0 (gateSteps 40),
   mkRec pv "breakpoint-gate" "gate (chromium, s0)" cls "r2" (t0 + 600000) (gateSteps 42),
   mkRec pv "breakpoint-gate" "gate (chromium, s0)" cls "r3" (t0 + 1200000) (gateSteps 41)]

/-- The fourth run, installing for `last` s. -/
def fourth (pv : Provider) (cls : String) (last : Nat) : Record :=
  mkRec pv "breakpoint-gate" "gate (chromium, s0)" cls "r4" (t0 + 1800000) (gateSteps last)

def pressureRec (t : Nat) : Record :=
  let r := mkRec .github "webkit-sim" "sim" "macos-14" "r1" t [("run", 1000)]
  let p : Probe :=
    { atMs := t + 5000, cpuPct := 40, memUsedMb := 6100, loadCenti := 150, diskFreeMb := 60000,
      swapUsedMb := some 2300, compressorMb := some 1800, storedMb := some 4900, swapOuts := some 120000,
      compressions := some 5000000, pressureLevel := some 2, freePct := some 4 }
  { r with probes := [p] }

def cases (_ : Unit := ()) : List (String × Json) :=
  let rj := recordJson
  let h4 := hist3 .github "ubuntu-24.04" ++ [fourth .github "ubuntu-24.04" 70]
  [("one run, no history: every span is noBaseline, nothing slow",
      reqJson [rj (mkRec .github "breakpoint-gate" "gate (chromium, s0)" "ubuntu-24.04" "r1" t0 (gateSteps 40))]),
   ("install 70 s after 40, 42, 41 s on the same lane, job and class: install is slow, the job (140 s against 111 s) is not",
      reqJson (h4.map rj)),
   ("the same 70 s install on a macOS class with only Linux history: no baseline, nothing slow",
      reqJson ((hist3 .github "ubuntu-24.04").map rj ++ [rj (fourth .github "macos-14" 70)])),
   ("the same history on CircleCI, class ubuntu-24.04 too: the provider is part of the key, nothing slow",
      reqJson ((hist3 .github "ubuntu-24.04").map rj ++ [rj (fourth .circleci "ubuntu-24.04" 70)])),
   ("records given newest first are judged in start order: the same slow steps as the second case",
      reqJson (h4.reverse.map rj)),
   ("exactly 1.5 x the baseline (60 s after 40 s x3) is ok",
      reqJson ((List.range 3).map (fun i => rj (mkRec .github "lean" "check" "ubuntu-24.04" s!"r{i}" (t0 + i * 600000)
        [("check", 40000)])) ++ [rj (mkRec .github "lean" "check" "ubuntu-24.04" "r3" (t0 + 1800000) [("check", 60000)])])),
   ("queue 30 s after 4 s x3 and simulator boot 60 s after 20 s x3: both slow",
      reqJson ((List.range 3).map (fun i => rj (mkRec .github "webkit-sim" "sim" "macos-14" s!"r{i}" (t0 + i * 600000)
        [("run", 1000)] (some 4000) (some 20000))) ++
        [rj (mkRec .github "webkit-sim" "sim" "macos-14" "r3" (t0 + 1800000) [("run", 1000)] (some 30000) (some 60000))])),
   ("a step name twice in one job: the second download is download#1 with its own history: it and the job are slow, the first download is not",
      reqJson ((List.range 3).map (fun i => rj (mkRec .github "chromium-counts" "counts" "ubuntu-24.04" s!"r{i}" (t0 + i * 600000)
        [("download", 3000), ("build", 40000), ("download", 4000)])) ++
        [rj (mkRec .github "chromium-counts" "counts" "ubuntu-24.04" "r3" (t0 + 1800000)
          [("download", 3000), ("build", 40000), ("download", 70000)])])),
   ("params with a ceiling of 1 s on the job: slow at once with no history",
      reqJson [rj (mkRec .github "lean" "check" "ubuntu-24.04" "r1" t0 [("check", 2000)] none)]
        (some (Json.mkObj [("ceilings", Json.arr #[Json.mkObj [("tool", Json.str "lean"), ("step", Json.str "check/(job)"),
          ("ms", toJson 1000)]])]))),
   ("a record whose probes carry the swap, compressor and memory pressure readings is read and judged like any other",
      reqJson [rj (pressureRec t0)]),
   ("a record with schema 2 is refused",
      reqJson [Json.mkObj [("schema", toJson 2)]])]

def hostReq (what : String) (fs : List (String × Nat)) : Json :=
  Json.mkObj ([("op", Json.str "ci.telemetry"), ("what", Json.str what)] ++ fs.map fun (k, v) => (k, toJson v))

def hostCases (_ : Unit := ()) : List (String × Json) :=
  [("bound: a limit below the cap is the bound, the settle adds the grace", hostReq "bound" [("limitMs", 120000)]),
   ("bound: the limit at the cap is the bound", hostReq "bound" [("limitMs", 200000)]),
   ("bound: a limit above the cap is cut to the cap", hostReq "bound" [("limitMs", 900000)]),
   ("bound: a zero limit is zero", hostReq "bound" [("limitMs", 0)]),
   ("stall: exactly the limit is not a stall", hostReq "stall" [("nowMs", 820000), ("lastMs", 100000), ("limitMs", 720000)]),
   ("stall: one ms over the limit is a stall", hostReq "stall" [("nowMs", 820001), ("lastMs", 100000), ("limitMs", 720000)]),
   ("stall: a clock before the last output is no stall", hostReq "stall" [("nowMs", 50), ("lastMs", 100), ("limitMs", 0)]),
   ("lag: a tick on time lost nothing", hostReq "lag" [("tickMs", 30000), ("sinceMs", 30000)]),
   ("lag: a tick that came early lost nothing", hostReq "lag" [("tickMs", 30000), ("sinceMs", 10000)]),
   ("lag: 59.999 s since the last tick is late but not blocked", hostReq "lag" [("tickMs", 30000), ("sinceMs", 59999)]),
   ("lag: 60 s since the last tick is one whole period lost: blocked", hostReq "lag" [("tickMs", 30000), ("sinceMs", 60000)]),
   ("lag: a 174 s gap on a 30 s tick (a blocked bootstatus) is blocked with 144 s lost", hostReq "lag" [("tickMs", 30000), ("sinceMs", 174000)]),
   ("lag: no tick period is never blocked", hostReq "lag" [("tickMs", 0), ("sinceMs", 100)]),
   ("an unknown what is refused", Json.mkObj [("op", Json.str "ci.telemetry"), ("what", Json.str "nope")])]

def uploadReq (kind : String) (fs : List (String × Json)) : Json :=
  Json.mkObj ([("op", Json.str "ci.telemetry"), ("upload", Json.str kind)] ++ fs)

def wakeReq (elapsed since period step fresh : Nat) (done : Bool) : Json :=
  uploadReq "wake" [("elapsedS", toJson elapsed), ("sinceS", toJson since), ("periodS", toJson period), ("stepS", toJson step),
    ("fresh", toJson fresh), ("done", Json.bool done)]

def uploadCases (_ : Unit := ()) : List (String × Json) :=
  [("upload period: one session (35 min) ticks every 7 min", uploadReq "period" [("stepMin", toJson 35)]),
   ("upload period: two sessions (70 min) ticks every 14 min", uploadReq "period" [("stepMin", toJson 70)]),
   ("upload period: the quiet experiment (50 min) ticks every 10 min", uploadReq "period" [("stepMin", toJson 50)]),
   ("upload period: a 4-minute step has no whole minute period", uploadReq "period" [("stepMin", toJson 4)]),
   ("upload wake: nothing new and the period not over keeps waiting", wakeReq 100 100 420 2100 0 false),
   ("upload wake: the period over wakes", wakeReq 420 420 420 2100 0 false),
   ("upload wake: one second short of the period keeps waiting", wakeReq 419 419 420 2100 0 false),
   ("upload wake: a new pass file wakes before the period", wakeReq 100 100 420 2100 1 false),
   ("upload wake: the measurement ended wakes", wakeReq 100 100 420 2100 0 true),
   ("upload wake: the end wins over a new pass", wakeReq 100 100 420 2100 2 true),
   ("upload wake: the step bound wakes a waiting tick", wakeReq 2100 0 420 2100 0 false),
   ("upload wake: the step bound wins over a new pass", wakeReq 2100 0 420 2100 1 false),
   ("upload: an unknown kind is refused", uploadReq "nope" [])]

def replyOf (req : Json) : Except String Reply :=
  match opt req "what", opt req "upload" with
  | some _, _ => opHostCall req
  | none, some _ => opUpload req
  | none, none => opTelemetry req

def replyJson (req : Json) : Json :=
  match replyOf req with
  | .ok f => Json.mkObj f
  | .error e => Json.mkObj [("error", .str e)]

def goldenText (_ : Unit := ()) : String :=
  String.join ((cases ++ hostCases ++ uploadCases).map fun (n, rq) => (Json.mkObj [("name", .str n), ("request", rq), ("response", replyJson rq)]).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/ci/telemetry.jsonl"

/-- Write the golden. -/
def writeGolden : IO Unit := do
  IO.FS.createDirAll "../packages/contracts/golden/ci"
  IO.FS.writeFile goldenPath goldenText

/-- Whether the golden file is the Lean output. -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

private def slowNames (rs : List Record) : List String := (slowItems telemetryParams (spansOf rs)).map (·.1.name)

#guard slowNames (hist3 .github "ubuntu-24.04" ++ [fourth .github "ubuntu-24.04" 70]) == ["install"]
#guard slowNames (fourth .github "ubuntu-24.04" 70 :: (hist3 .github "ubuntu-24.04").reverse) == ["install"]
#guard slowNames (hist3 .github "ubuntu-24.04" ++ [fourth .github "macos-14" 70]) == []
#guard slowNames (hist3 .github "ubuntu-24.04" ++ [fourth .circleci "ubuntu-24.04" 70]) == []
#guard slowNames (hist3 .github "ubuntu-24.04" ++ [fourth .github "ubuntu-24.04" 61]) == []
#guard slowNames (hist3 .github "ubuntu-24.04" ++ [fourth .github "ubuntu-24.04" 62]) == ["install"]
private def dupRecs (last : Nat) : List Record :=
  (List.range 3).map (fun i => mkRec .github "chromium-counts" "counts" "ubuntu-24.04" s!"r{i}" (t0 + i * 600000)
    [("download", 3000), ("build", 40000), ("download", 4000)]) ++
  [mkRec .github "chromium-counts" "counts" "ubuntu-24.04" "r3" (t0 + 1800000) [("download", 3000), ("build", 40000), ("download", last)]]

#guard keysFrom [] ["a", "a", "b", "a"] == ["a", "a#1", "b", "a#2"]
#guard keysFrom [] ["x", "x#1", "x"] == ["x", "x#1", "x#2"]
#guard keysFrom [] ["(job)", "(job)"] == ["(job)", "(job)#1"]
#guard ((dupRecs 70000).getLast?.map fun r => r.spans.map (·.name)) == some ["(queue)", "download", "build", "download#1", "(job)"]
#guard slowNames (dupRecs 70000) == ["download#1", "(job)"]
#guard slowNames (dupRecs 5000) == []
#guard (match recordOf (recordJson (fourth .circleci "x" 5)) with | .ok r => r == fourth .circleci "x" 5 | .error _ => false)
#guard (match recordOf (Json.mkObj [("schema", toJson 2)]) with | .error e => e == "field schema: expected 1" | .ok _ => false)

end Fw.Wire.Ci.Telemetry
