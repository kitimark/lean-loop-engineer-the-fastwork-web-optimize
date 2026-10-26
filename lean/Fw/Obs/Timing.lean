import Std.Data.String.ToNat
import Lean.Data.Json
import Fw.Sup.Adapt
import Fw.Ops.CheckMap
import Fw.Ci.Budget
/-!
# Timing: when an automation step took too long

Every automation step (an `fw` command, a `fw land` phase, a `check.sh` stage, a CI job) records a timing sample
(task `timing-spans`). This module is the pure decision over those samples: is the latest run of a step **slow**
against its own history, and is one step of a parallel stage **structural**, i.e. the one that sets the stage's wall
time by a wide margin (the sweeps-vs-shards case of the breakpoint gate). A step flagged either way is handed to an
agent to investigate and improve (task `timing-alert` wires the op and the alert).

Definitions (all durations in whole ms, `Nat`):
* A sample is `(tool, step, d, h, λ, kind, work)` with host `h ∈ {local, ci}`,
  `λ` the floor of the 1-min load average when it ran and `work` its work dimensions. Its key is `(tool, step, h, kind, work)`.
* A local sample with `λ > L` is **contended** (`L = contendedLoad = 8`, the CPUs of the local Mac): the machine ran more
  runnable tasks than CPUs, so its duration says how busy the machine was, not how the step changed. It gets the verdict
  `contended` (never `slow`) and never enters a window. A CI sample is never contended.
* The **window** of a sample is the last `N` uncontended samples with the same key that come before it in the input.
* The **baseline** is the nearest-rank median (p50) of the window: the `⌈ n/2 ⌉`-th smallest of its `n`
  values, defined by counting (`ord`), so no sort is needed and the proofs are about counts. It was the p90 until
  task `timing-small-n`: with `n ≤ 9` the p90 is the window maximum, so a regression seen twice became its own
  baseline (history `[2,1,2,27,26]` s, then 40 s was `ok`). A median moves only once a shift fills more than half the window
  (`no_self_mask`), so the counterexample is now `slow` (`site_regression_slow`).
* Verdict of one sample, first match: `noBaseline` when the window has fewer than `n_min` samples; `contended`; `slow`
  when `d > max(B, k · b)` with `B` the step's budget and `b` the baseline; otherwise `ok`.
* A **ceiling** is an absolute limit `C(tool, step)` for one step. A not contended sample above its
  ceiling is `slow` at once, with no window needed: a step that is slow from its first run (the 2-minute `fw land`)
  has no history to be slow against, so the relative rule alone never alerts for it. `landCeilings` sets 30 s for the
  whole `fw land` and 5 s for the time its lock is held.
* **Structural call**: a stage is a list of groups (a group is the list of keys of one job, e.g. the matrix legs of
  `sweeps`); a group's baseline is the largest final baseline of its keys (defined when every key has one). Every
  group of every stage gets a call: `structural` when its baseline exceeds twice every sibling group's baseline,
  `noise` when every sibling has a baseline but one is at least half of it, `undecided` otherwise.
* **Where stages come from**: `params.stages` when the caller gives any; otherwise (`fw watch` sends no params) they
  are derived from the CI job samples (`autoStages`): one stage per CI workflow with at least two job families, one
  group per job family (the job name up to its first `" ("`, so matrix legs share a group). A workflow is a coarser
  stage than its parallel jobs (sequential jobs count as siblings too), so an auto `structural` call reads "this job
  family dominates its workflow's job time".

Proved (main results; helper lemmas below): `slow_iff`, `ceilingBreach_iff`, `land_budget_alert`,
`no_alert_within_budget`, `no_alert_within_budget_list`, `slow_mono_dur`, `slow_mono_window`, `no_self_mask`,
`site_regression_slow`, `site_repeat_slow`, `stable_never_slow`, `contended_not_slow`, `slow_at_normal_load`.
-/
namespace Fw.Obs.Timing

/-! ## Samples and parameters -/

/-- Where a sample was taken: on the local machine or on a CI runner. -/
inductive Host where
  | «local»
  | ci
deriving DecidableEq, Repr

structure Sample where
  tool    : String
  step    : String
  durMs   : Nat
  host    : Host
  load    : Nat := 0
  kind    : String := ""
  exit    : Option Int := none
  skipped : Bool := false
  waitMs  : Nat := 0
  waits   : List (Fw.Sup.Adapt.WhyTag × Nat) := []
  work    : List (String × String) := []
  ownMs   : Option Nat := none
  startMs : Nat := 0
  commit  : String := ""
deriving DecidableEq, Repr

def fullRun (exit : Option Int) (skipped : Bool) : Bool := !skipped && (exit == none || exit == some 0)

def Sample.full (s : Sample) : Bool := fullRun s.exit s.skipped

#guard fullRun none false && fullRun (some 0) false && !fullRun (some 1) false && !fullRun (some 16) false
#guard !fullRun (some (-1)) false && !fullRun (some 0) true && !fullRun none true

theorem fullRun_none : fullRun none false = true := rfl

theorem fullRun_zero : fullRun (some 0) false = true := rfl

theorem fullRun_skipped (e : Option Int) : fullRun e true = false := rfl

theorem fullRun_nonzero (n : Int) (b : Bool) (h : n ≠ 0) : fullRun (some n) b = false := by
  simp [fullRun, h]

def Sample.remoteQueue (s : Sample) : Bool := s.tool == "fw land" && s.step == "remote queue"

def Sample.ciWait (s : Sample) : Bool := s.tool == "fw" && s.step == "ci wait"

def Sample.remote (s : Sample) : Bool := s.remoteQueue || s.ciWait

inductive NetSrc where
  | observed
  | state
deriving DecidableEq, Repr

def netSrc (tickMs prevTickMs : Option Nat) : NetSrc :=
  match tickMs, prevTickMs with
  | some t, some p => if p < t then .observed else .state
  | _, _ => .state

def backoffMs (prevTickMs retryUntilS : Option Nat) : Nat :=
  match prevTickMs, retryUntilS with
  | some p, some r => r * 1000 - p
  | _, _ => 0

def gapCapMs (prevTickMs pollS retryUntilS prevPollS : Option Nat) : Option Nat :=
  match pollS, retryUntilS with
  | some q, some _ => some (max q (prevPollS.getD 0) * 1000 + backoffMs prevTickMs retryUntilS)
  | _, _ => none

def capNets : Fw.Ci.Budget.Reason → Bool
  | .interval | .retryAfter => true
  | .failures | .idle | .tooBig | .floor | .hour | .minute => false

def netMsOf (tickMs prevTickMs pollS retryUntilS prevPollS : Option Nat) : Option Nat :=
  match netSrc tickMs prevTickMs, tickMs, prevTickMs with
  | .observed, some t, some p =>
    match gapCapMs (some p) pollS retryUntilS prevPollS with
    | some c => some (min (t - p) c)
    | none => some (t - p)
  | _, _, _ => pollS.map (· * 1000)

theorem netSrc_observed_iff (t p : Option Nat) :
    netSrc t p = .observed ↔ ∃ t' p', t = some t' ∧ p = some p' ∧ p' < t' := by
  unfold netSrc
  cases t <;> cases p <;> simp

theorem netSrc_no_prev (t : Option Nat) : netSrc t none = .state := by cases t <;> rfl

theorem netSrc_no_tick (p : Option Nat) : netSrc none p = .state := rfl

theorem netSrc_not_before (t p : Nat) (h : t ≤ p) : netSrc (some t) (some p) = .state := by
  simp [netSrc, Nat.not_lt.2 h]

theorem backoffMs_before (p r : Nat) (h : r * 1000 ≤ p) : backoffMs (some p) (some r) = 0 := by
  simp [backoffMs]; omega

theorem capNets_iff (w : Fw.Ci.Budget.Reason) : capNets w = true ↔ w = .interval ∨ w = .retryAfter := by
  cases w <;> simp [capNets]

theorem capNets_floor : capNets .floor = false := rfl

theorem capNets_hour : capNets .hour = false := rfl

theorem capNets_minute : capNets .minute = false := rfl

theorem gapCapMs_no_retry (p q w : Option Nat) : gapCapMs p q none w = none := by cases q <;> rfl

theorem gapCapMs_no_poll (p r w : Option Nat) : gapCapMs p none r w = none := rfl

theorem gapCapMs_some (p q r w : Nat) :
    gapCapMs (some p) (some q) (some r) (some w) = some (max q w * 1000 + (r * 1000 - p)) := rfl

theorem gapCapMs_no_prev_poll (p q r : Nat) :
    gapCapMs (some p) (some q) (some r) none = some (q * 1000 + (r * 1000 - p)) := by
  simp [gapCapMs, backoffMs]

theorem gapCapMs_shrunk (p q r w : Nat) (h : q ≤ w) :
    gapCapMs (some p) (some q) (some r) (some w) = some (w * 1000 + (r * 1000 - p)) := by
  rw [gapCapMs_some, Nat.max_eq_right h]

theorem gapCapMs_grew (p q r w : Nat) (h : w ≤ q) :
    gapCapMs (some p) (some q) (some r) (some w) = some (q * 1000 + (r * 1000 - p)) := by
  rw [gapCapMs_some, Nat.max_eq_left h]

theorem gapCapMs_prev_le (p q r w c c' : Nat) (h : gapCapMs (some p) (some q) (some r) none = some c)
    (h' : gapCapMs (some p) (some q) (some r) w = some c') : c ≤ c' := by
  simp [gapCapMs, backoffMs] at h h'
  omega

theorem netMsOf_observed (t p : Nat) (q w : Option Nat) (h : p < t) :
    netMsOf (some t) (some p) q none w = some (t - p) := by
  cases q <;> simp [netMsOf, netSrc, h, gapCapMs]

theorem netMsOf_capped (t p q r c : Nat) (w : Option Nat) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) :
    netMsOf (some t) (some p) (some q) (some r) w = some (min (t - p) c) := by
  simp only [netMsOf, netSrc, h, ite_true, hc]

theorem netMsOf_gap_within (t p q r c : Nat) (w : Option Nat) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : t - p ≤ c) :
    netMsOf (some t) (some p) (some q) (some r) w = some (t - p) := by
  rw [netMsOf_capped t p q r c w h hc, Nat.min_eq_left hg]

theorem netMsOf_gap_stall (t p q r c : Nat) (w : Option Nat) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : c < t - p) :
    netMsOf (some t) (some p) (some q) (some r) w = some c := by
  rw [netMsOf_capped t p q r c w h hc, Nat.min_eq_right (Nat.le_of_lt hg)]

theorem netMsOf_shrunk_within (t p q r w : Nat) (h : p < t) (hq : q ≤ w)
    (hg : t - p ≤ w * 1000 + (r * 1000 - p)) :
    netMsOf (some t) (some p) (some q) (some r) (some w) = some (t - p) :=
  netMsOf_gap_within t p q r _ (some w) h (gapCapMs_shrunk p q r w hq) hg

theorem netMsOf_shrunk_no_prev_poll (t p q r : Nat) (h : p < t) (hg : q * 1000 + (r * 1000 - p) < t - p) :
    netMsOf (some t) (some p) (some q) (some r) none = some (q * 1000 + (r * 1000 - p)) :=
  netMsOf_gap_stall t p q r _ none h (gapCapMs_no_prev_poll p q r) hg

theorem netMsOf_state (t p q r w : Option Nat) (h : netSrc t p = .state) :
    netMsOf t p q r w = q.map (· * 1000) := by
  unfold netMsOf
  rw [h]

theorem netMsOf_observed_ignores_poll (t p : Nat) (q q' w w' : Option Nat) (h : p < t) :
    netMsOf (some t) (some p) q none w = netMsOf (some t) (some p) q' none w' := by
  rw [netMsOf_observed t p q w h, netMsOf_observed t p q' w' h]

theorem netMsOf_le_cap (t p q r w : Option Nat) (n c : Nat) (hn : netMsOf t p q r w = some n)
    (hc : gapCapMs p q r w = some c) : n ≤ c := by
  cases q with
  | none => simp [gapCapMs] at hc
  | some q =>
    cases r with
    | none => simp [gapCapMs] at hc
    | some r =>
      cases hs : netSrc t p with
      | state =>
        rw [netMsOf_state t p (some q) (some r) w hs] at hn
        simp [gapCapMs] at hc hn
        omega
      | observed =>
        obtain ⟨t', p', rfl, rfl, hp⟩ := (netSrc_observed_iff t p).1 hs
        rw [netMsOf_capped t' p' q r c w hp hc] at hn
        simp at hn
        omega

def waitsMs (net : Bool) (ws : List (Fw.Ci.Budget.Reason × Nat)) : Nat :=
  ((ws.filter fun x => capNets x.1 == net).map (·.2)).sum

theorem netMsOf_capNets (t p q r c : Nat) (w : Option Nat) (ws : List (Fw.Ci.Budget.Reason × Nat)) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : t - p = waitsMs true ws + waitsMs false ws)
    (hn : waitsMs true ws ≤ c) :
    ∃ n, netMsOf (some t) (some p) (some q) (some r) w = some n ∧
      t - p - n = waitsMs false ws - (c - waitsMs true ws) := by
  refine ⟨min (t - p) c, netMsOf_capped t p q r c w h hc, ?_⟩
  omega

theorem netMsOf_capNets_full (t p q r c : Nat) (w : Option Nat) (ws : List (Fw.Ci.Budget.Reason × Nat)) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : t - p = waitsMs true ws + waitsMs false ws)
    (hn : waitsMs true ws = c) :
    ∃ n, netMsOf (some t) (some p) (some q) (some r) w = some n ∧ t - p - n = waitsMs false ws := by
  obtain ⟨n, hn', he⟩ := netMsOf_capNets t p q r c w ws h hc hg (Nat.le_of_eq hn)
  exact ⟨n, hn', by omega⟩

theorem netMsOf_own_wait (t p q r f : Nat) (why : Fw.Ci.Budget.Reason) (hw : capNets why = false) (h : p < t)
    (hr : r * 1000 ≤ p) (hg : t - p = q * 1000 + f) :
    ∃ n, netMsOf (some t) (some p) (some q) (some r) none = some n ∧
      t - p - n = waitsMs false [(.interval, q * 1000), (why, f)] := by
  have hc : gapCapMs (some p) (some q) (some r) none = some (q * 1000) := by
    rw [gapCapMs_no_prev_poll, Nat.sub_eq_zero_of_le hr, Nat.add_zero]
  have h1 : waitsMs true [(.interval, q * 1000), (why, f)] = q * 1000 := by
    cases why <;> simp_all [waitsMs, capNets]
  have h2 : waitsMs false [(.interval, q * 1000), (why, f)] = f := by
    cases why <;> simp_all [waitsMs, capNets]
  exact netMsOf_capNets_full t p q r _ none _ h hc (by rw [h1, h2]; exact hg) h1

theorem floor_row_own :
    ∃ n, netMsOf (some 100000) (some 40000) (some 10) (some 30) none = some n ∧
      100000 - 40000 - n = waitsMs false [(.interval, 10000), (.floor, 50000)] :=
  netMsOf_own_wait 100000 40000 10 30 50000 .floor rfl (by omega) (by omega) (by omega)

theorem interval_step_unregister (L : Fw.Ci.Budget.Limits) (s : Fw.Ci.Budget.State) (r : Nat) :
    Fw.Ci.Budget.interval L (Fw.Ci.Budget.step L s (.unregister r)) = Fw.Ci.Budget.interval L s := rfl

theorem interval_step_listed (L : Fw.Ci.Budget.Limits) (s : Fw.Ci.Budget.State) (rows : List (Nat × Nat))
    (count pagesRead since : Nat) :
    Fw.Ci.Budget.interval L (Fw.Ci.Budget.step L s (.listed rows count pagesRead since)) =
      Fw.Ci.Budget.interval L s := rfl

theorem interval_step_register (L : Fw.Ci.Budget.Limits) (s : Fw.Ci.Budget.State) (r c : Nat) :
    Fw.Ci.Budget.interval L (Fw.Ci.Budget.step L s (.register r c)) = Fw.Ci.Budget.interval L s := by
  simp only [Fw.Ci.Budget.step]
  split <;> rfl

theorem next_waits_interval (L : Fw.Ci.Budget.Limits) (s : Fw.Ci.Budget.State) (t0 : Nat) (hf : s.fails < L.maxFails)
    (hw : s.watched ≠ []) (hl : s.lastTick = some t0) (hn : s.now < t0 + Fw.Ci.Budget.interval L s) :
    Fw.Ci.Budget.next L s = .wait (t0 + Fw.Ci.Budget.interval L s) .interval := by
  simp [Fw.Ci.Budget.next, Nat.not_le.2 hf, hw, hl, hn]

def prePagesTick : Fw.Ci.Budget.State :=
  { Fw.Ci.Budget.init 0 with remaining := some 505, reset := some 100, lastTick := some 0 }

theorem pre_pages_max_misses :
    let L := Fw.Ci.Budget.defaults
    let s1 := { prePagesTick with pages := 2 }
    max (Fw.Ci.Budget.interval L prePagesTick)
        (Fw.Ci.Budget.interval L (Fw.Ci.Budget.step L s1 (.clock (Fw.Ci.Budget.interval L s1)))) <
      Fw.Ci.Budget.interval L s1 := by decide

#guard netMsOf (some 1792784016000) (some 1792784004000) (some 10) none none == some 12000
#guard netMsOf (some 1792784016000) (some 1792784004000) none none none == some 12000
#guard netMsOf (some 1792784016000) none (some 10) none none == some 10000
#guard netMsOf (some 1792784016000) (some 1792784016000) (some 10) none none == some 10000
#guard netMsOf (some 1792784016000) (some 1792784020000) (some 10) none none == some 10000
#guard netMsOf none (some 5) (some 10) none none == some 10000
#guard netMsOf (some 9) none none none none == none
#guard netMsOf (some 1792784016000) (some 1792784004000) (some 10) (some 1792783000) none == some 10000
#guard netMsOf (some 1792784016000) (some 1792784004000) (some 10) (some 1792784006) none == some 12000
#guard netMsOf (some 257000) (some 40000) (some 10) (some 30) none == some 10000
#guard netMsOf (some 257000) (some 40000) none (some 30) none == some 217000
#guard netMsOf (some 257000) none (some 10) (some 300) none == some 10000
#guard netMsOf (some 95000) (some 40000) (some 10) (some 30) (some 60) == some 55000
#guard netMsOf (some 95000) (some 40000) (some 10) (some 30) none == some 10000
#guard netMsOf (some 257000) (some 40000) (some 30) (some 30) (some 10) == some 30000
#guard netMsOf (some 257000) (some 40000) (some 10) (some 30) (some 60) == some 60000
#guard netMsOf (some 257000) none (some 10) (some 30) (some 60) == some 10000
#guard backoffMs (some 40000) (some 110) == 70000 && backoffMs (some 40000) (some 30) == 0
#guard backoffMs none (some 30) == 0
#guard gapCapMs (some 40000) (some 10) (some 110) none == some 80000 && gapCapMs (some 40000) (some 10) none none == none
#guard gapCapMs (some 40000) (some 10) (some 110) (some 60) == some 130000
#guard gapCapMs (some 40000) (some 10) none (some 60) == none && gapCapMs (some 40000) none (some 30) (some 60) == none
#guard [Fw.Ci.Budget.Reason.interval, .retryAfter].all capNets
#guard waitsMs true [(.interval, 10000), (.floor, 50000), (.retryAfter, 3000), (.hour, 7)] == 13000
#guard waitsMs false [(.interval, 10000), (.floor, 50000), (.retryAfter, 3000), (.hour, 7)] == 50007
#guard waitsMs true [] == 0 && waitsMs false [(.minute, 4)] == 4
#guard Fw.Ci.Budget.interval Fw.Ci.Budget.defaults prePagesTick == 50
#guard Fw.Ci.Budget.interval Fw.Ci.Budget.defaults { prePagesTick with pages := 2 } == 100
#guard ![Fw.Ci.Budget.Reason.failures, .idle, .tooBig, .floor, .hour, .minute].any capNets

def ownOfNet (startMs durMs : Nat) (how : String) (updMs tickMs netMs : Option Nat) : Option Nat :=
  match updMs, tickMs, netMs with
  | some u, some t, some n =>
    if how == "done" && u ≤ startMs + durMs then
      some (startMs + durMs - max u startMs - min (t - max u startMs) n)
    else none
  | _, _, _ => none

def ownOfPhases (startMs durMs : Nat) (how : String) (updMs tickMs prevTickMs pollS retryUntilS prevPollS : Option Nat) :
    Option Nat :=
  ownOfNet startMs durMs how updMs tickMs (netMsOf tickMs prevTickMs pollS retryUntilS prevPollS)

theorem ownOfNet_some (s d : Nat) (how : String) (u t n o : Nat) :
    ownOfNet s d how (some u) (some t) (some n) = some o ↔
      how = "done" ∧ u ≤ s + d ∧ o = s + d - max u s - min (t - max u s) n := by
  simp only [ownOfNet]
  by_cases h : (how == "done" && decide (u ≤ s + d)) = true
  · simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
    simp [h, eq_comm]
  · simp only [h]
    simp only [Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, not_and] at h
    constructor
    · intro e; cases e
    · intro ⟨h1, h2, _⟩; exact absurd h2 (h h1)

theorem ownOfNet_none_net (s d : Nat) (how : String) (u t : Option Nat) : ownOfNet s d how u t none = none := by
  cases u <;> cases t <;> rfl

theorem ownOfPhases_observed (s d : Nat) (how : String) (u : Option Nat) (t p : Nat) (q w : Option Nat) (h : p < t) :
    ownOfPhases s d how u (some t) (some p) q none w = ownOfNet s d how u (some t) (some (t - p)) := by
  simp only [ownOfPhases, netMsOf_observed t p q w h]

theorem ownOfPhases_capped (s d : Nat) (how : String) (u : Option Nat) (t p q r c : Nat) (w : Option Nat) (h : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c) :
    ownOfPhases s d how u (some t) (some p) (some q) (some r) w = ownOfNet s d how u (some t) (some (min (t - p) c)) := by
  simp only [ownOfPhases, netMsOf_capped t p q r c w h hc]

theorem ownOfPhases_state (s d : Nat) (how : String) (u t p q r w : Option Nat) (h : netSrc t p = .state) :
    ownOfPhases s d how u t p q r w = ownOfNet s d how u t (q.map (· * 1000)) := by
  simp only [ownOfPhases, netMsOf_state t p q r w h]

theorem ownOfPhases_not_done (s d : Nat) (how : String) (u t p q r w : Option Nat) (h : how ≠ "done") :
    ownOfPhases s d how u t p q r w = none := by
  unfold ownOfPhases ownOfNet
  generalize netMsOf t p q r w = n
  cases u <;> cases t <;> cases n <;> simp [h]

theorem ownOfPhases_no_upd (s d : Nat) (how : String) (t p q r w : Option Nat) :
    ownOfPhases s d how none t p q r w = none := rfl

theorem ownOfPhases_no_tick (s d : Nat) (how : String) (u p q r w : Option Nat) :
    ownOfPhases s d how u none p q r w = none := by
  unfold ownOfPhases ownOfNet
  cases u <;> rfl

theorem ownOfPhases_no_interval (s d : Nat) (how : String) (u t r w : Option Nat) :
    ownOfPhases s d how u t none none r w = none := by
  rw [ownOfPhases_state s d how u t none none r w (netSrc_no_prev t)]
  exact ownOfNet_none_net s d how u t

theorem ownOfPhases_after_end (s d : Nat) (how : String) (u : Nat) (t p q r w : Option Nat) (h : s + d < u) :
    ownOfPhases s d how (some u) t p q r w = none := by
  unfold ownOfPhases ownOfNet
  generalize netMsOf t p q r w = n
  cases t <;> cases n <;> simp [Nat.not_le.2 h]

theorem ownOfNet_le_dur (s d : Nat) (how : String) (u t n o : Nat)
    (h : ownOfNet s d how (some u) (some t) (some n) = some o) : o ≤ d := by
  obtain ⟨_, _, rfl⟩ := (ownOfNet_some s d how u t n o).1 h
  omega

theorem ownOfPhases_le_dur (s d : Nat) (how : String) (u t p q r w : Option Nat) (o : Nat)
    (h : ownOfPhases s d how u t p q r w = some o) : o ≤ d := by
  unfold ownOfPhases at h
  cases u with
  | none => cases h
  | some u =>
    cases t with
    | none => cases h
    | some t =>
      cases hn : netMsOf (some t) p q r w with
      | none => rw [hn] at h; cases h
      | some n => rw [hn] at h; exact ownOfNet_le_dur s d how u t n o h

theorem ownOfPhases_before_start (s d : Nat) (how : String) (u : Nat) (t p q r w : Option Nat) (hu : u ≤ s) :
    ownOfPhases s d how (some u) t p q r w = ownOfPhases s d how (some s) t p q r w := by
  unfold ownOfPhases ownOfNet
  generalize netMsOf t p q r w = n
  cases t <;> cases n <;> simp [Nat.max_eq_right hu, Nat.le_trans hu (Nat.le_add_right s d)]

theorem ownOfNet_net_le (s d : Nat) (how : String) (u t n o : Nat)
    (h : ownOfNet s d how (some u) (some t) (some n) = some o) : s + d - max u s ≤ o + n := by
  obtain ⟨_, _, rfl⟩ := (ownOfNet_some s d how u t n o).1 h
  omega

theorem ownOfPhases_observed_net_le (s d : Nat) (how : String) (u t p o : Nat) (q w : Option Nat) (hp : p < t)
    (h : ownOfPhases s d how (some u) (some t) (some p) q none w = some o) : s + d - max u s ≤ o + (t - p) := by
  rw [ownOfPhases_observed s d how _ t p q w hp] at h
  exact ownOfNet_net_le s d how u t _ o h

theorem ownOfPhases_capped_net_le (s d : Nat) (how : String) (u t p q r c o : Nat) (w : Option Nat) (hp : p < t)
    (hc : gapCapMs (some p) (some q) (some r) w = some c)
    (h : ownOfPhases s d how (some u) (some t) (some p) (some q) (some r) w = some o) : s + d - max u s ≤ o + c := by
  rw [ownOfPhases_capped s d how _ t p q r c w hp hc] at h
  have := ownOfNet_net_le s d how u t _ o h
  omega

theorem ownOfPhases_state_net_le (s d : Nat) (how : String) (u t q o : Nat) (r w : Option Nat)
    (h : ownOfPhases s d how (some u) (some t) none (some q) r w = some o) : s + d - max u s ≤ o + q * 1000 := by
  rw [ownOfPhases_state s d how _ _ none _ r w (netSrc_no_prev _)] at h
  exact ownOfNet_net_le s d how u t _ o h

theorem ownOfNet_within (s d u t n : Nat) (hu : u ≤ s + d) (ht : max u s ≤ t) (hn : t - max u s ≤ n) :
    ownOfNet s d "done" (some u) (some t) (some n) = some (s + d - t) := by
  refine (ownOfNet_some s d "done" u t n _).2 ⟨rfl, hu, ?_⟩
  omega

theorem ownOfNet_stall (s d u t n : Nat) (hu : u ≤ s + d) (hn : n < t - max u s) :
    ownOfNet s d "done" (some u) (some t) (some n) = some (s + d - max u s - n) := by
  refine (ownOfNet_some s d "done" u t n _).2 ⟨rfl, hu, ?_⟩
  omega

theorem ownOfPhases_observed_unfinished (s d u t p : Nat) (q w : Option Nat) (hu : u ≤ s + d) (hp : p ≤ max u s)
    (ht : max u s ≤ t) (hpt : p < t) :
    ownOfPhases s d "done" (some u) (some t) (some p) q none w = some (s + d - t) := by
  rw [ownOfPhases_observed s d _ _ t p q w hpt]
  exact ownOfNet_within s d u t _ hu ht (by omega)

theorem ownOfPhases_capped_within (s d u t p q r c : Nat) (w : Option Nat) (hu : u ≤ s + d) (hp : p ≤ max u s)
    (ht : max u s ≤ t) (hpt : p < t) (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : t - p ≤ c) :
    ownOfPhases s d "done" (some u) (some t) (some p) (some q) (some r) w = some (s + d - t) := by
  rw [ownOfPhases_capped s d _ _ t p q r c w hpt hc, Nat.min_eq_left hg]
  exact ownOfNet_within s d u t _ hu ht (by omega)

theorem ownOfPhases_shrunk_within (s d u t p q r w : Nat) (hu : u ≤ s + d) (hp : p ≤ max u s) (ht : max u s ≤ t)
    (hpt : p < t) (hq : q ≤ w) (hg : t - p ≤ w * 1000 + (r * 1000 - p)) :
    ownOfPhases s d "done" (some u) (some t) (some p) (some q) (some r) (some w) = some (s + d - t) :=
  ownOfPhases_capped_within s d u t p q r _ (some w) hu hp ht hpt (gapCapMs_shrunk p q r w hq) hg

theorem ownOfPhases_gap_stall (s d u t p q r c : Nat) (w : Option Nat) (hu : u ≤ s + d) (hp : p ≤ max u s)
    (hpt : p < t) (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : c < t - max u s) :
    ownOfPhases s d "done" (some u) (some t) (some p) (some q) (some r) w = some (s + d - max u s - c) := by
  rw [ownOfPhases_capped s d _ _ t p q r c w hpt hc, Nat.min_eq_right (by omega)]
  exact ownOfNet_stall s d u t _ hu hg

theorem ownOfPhases_gap_stall_counts (s d u t p q r c : Nat) (w : Option Nat) (hu : u ≤ s + d) (hp : p ≤ max u s)
    (hpt : p < t) (ht : t ≤ s + d) (hc : gapCapMs (some p) (some q) (some r) w = some c) (hg : c < t - max u s) :
    ownOfPhases s d "done" (some u) (some t) (some p) (some q) (some r) w =
      (ownOfPhases s d "done" (some u) (some t) (some p) (some q) none w).map (· + (t - max u s - c)) := by
  rw [ownOfPhases_gap_stall s d u t p q r c w hu hp hpt hc hg,
    ownOfPhases_observed_unfinished s d u t p (some q) w hu hp (by omega) hpt]
  simp only [Option.map_some]
  congr 1
  omega

theorem ownOfPhases_state_within (s d u t q : Nat) (r w : Option Nat) (hu : u ≤ s + d) (ht : max u s ≤ t)
    (hq : t - max u s ≤ q * 1000) : ownOfPhases s d "done" (some u) (some t) none (some q) r w = some (s + d - t) := by
  rw [ownOfPhases_state s d _ _ _ none _ r w (netSrc_no_prev _)]
  exact ownOfNet_within s d u t _ hu ht hq

theorem ownOfPhases_state_stall (s d u t q : Nat) (r w : Option Nat) (hu : u ≤ s + d) (hq : q * 1000 < t - max u s) :
    ownOfPhases s d "done" (some u) (some t) none (some q) r w = some (s + d - max u s - q * 1000) := by
  rw [ownOfPhases_state s d _ _ _ none _ r w (netSrc_no_prev _)]
  exact ownOfNet_stall s d u t _ hu hq

#guard ownOfPhases 1000 1377258 "done" (some (1000 + 1377258 - 27294)) (some (1000 + 1377258 - 27294)) none (some 10)
  none none == some 27294
#guard 1792784208219 + 6921 - 1792784005000 == 210140
#guard ownOfPhases 1792784208219 6921 "done" (some 1792784005000) (some 1792784212000) none (some 10) none none ==
  some 3140
#guard ownOfPhases 1792784208219 6921 "done" (some 1792784005000) (some 1792784212000) none (some 120) none none ==
  some 3140
#guard ownOfPhases 1792784208219 6921 "done" (some 1792784005000) (some 1792784212000) none none none none == none
#guard ownOfPhases 1792783668155 405554 "done" (some 1792784005000) (some 1792784016000) (some 1792784004000) (some 10)
  none none == some 57709
#guard ownOfPhases 1792783668155 405554 "done" (some 1792784005000) (some 1792784016000) none (some 10) none none ==
  some 58709
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) none (some 10) none none == some 240000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) (some 245000) (some 10) none none == some 238000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 100000) (some 40000) (some 10) none none == some 200000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 57000) none (some 10) none none == some 243000
#guard ownOfPhases 0 900000 "done" none (some 5) none (some 10) none none == none
#guard ownOfPhases 0 900000 "timeout" (some 5) (some 5) none (some 10) none none == none
#guard ownOfPhases 0 10 "done" (some 99) (some 99) none (some 10) none none == none
#guard ownOfPhases 0 10 "done" (some 10) (some 10) none (some 10) none none == some 0
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) (some 40000) (some 10) (some 30) none == some 240000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) (some 40000) (some 10) none none == some 43000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 111000) (some 40000) (some 10) (some 110) none == some 189000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 95000) (some 40000) (some 10) (some 30) (some 60) == some 205000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 95000) (some 40000) (some 10) (some 30) none == some 240000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) (some 40000) (some 30) (some 30) (some 10) == some 220000
#guard ownOfPhases 0 300000 "done" (some 50000) (some 257000) (some 40000) (some 10) (some 30) (some 60) == some 190000

def Sample.own (s : Sample) : Option Nat :=
  if s.remoteQueue then some 0 else if s.ciWait then s.ownMs else some s.durMs

def Sample.norm (s : Sample) : Sample :=
  { s with durMs := s.own.getD s.durMs, skipped := s.skipped || s.own.isNone }

#guard ({ tool := "fw", step := "ci wait", durMs := 293198, host := .«local», ownMs := some 12245 } : Sample).norm.durMs == 12245
#guard !({ tool := "fw", step := "ci wait", durMs := 293198, host := .«local» } : Sample).norm.full
#guard ({ tool := "fw land", step := "remote queue", durMs := 36034, host := .«local» } : Sample).norm.durMs == 0
#guard ({ tool := "fw", step := "land dry", durMs := 36034, host := .«local» } : Sample).norm.durMs == 36034

structure Key where
  tool : String
  step : String
  host : Host
  kind : String := ""
  work : List (String × String) := []
deriving DecidableEq, Repr

/-- The key of a sample. -/
def Sample.key (s : Sample) : Key := { tool := s.tool, step := s.step, host := s.host, kind := s.kind, work := s.work }

def widthDim : String := "width"

/-- The work dimensions of a span from its granted slot width and job count: the width only, none without a width. -/
def slotWork (width : Option Nat) (_jobs : Option Nat) : List (String × String) :=
  match width with
  | some w => [(widthDim, toString w)]
  | none => []

#guard slotWork (some 2) (some 30) == [("width", "2")] && slotWork (some 1) none == [("width", "1")]
#guard slotWork none (some 30) == [] && slotWork (some 2) (some 30) == slotWork (some 2) (some 31)

theorem slotWork_some (w : Nat) (j : Option Nat) : slotWork (some w) j = [(widthDim, toString w)] := rfl

theorem slotWork_none (j : Option Nat) : slotWork none j = [] := rfl

theorem slotWork_jobs (w : Option Nat) (j j' : Option Nat) : slotWork w j = slotWork w j' := by
  cases w <;> rfl

theorem slotWork_width_ne (w w' : Nat) (j j' : Option Nat) (h : w ≠ w') : slotWork (some w) j ≠ slotWork (some w') j' := by
  intro e
  simp only [slotWork, List.cons.injEq, Prod.mk.injEq, and_true, true_and] at e
  exact h (Nat.repr_injective e)

def checksDim : String := "checks"

def heavyChecks : List String :=
  (Fw.Ops.CheckMap.order.filter Fw.Ops.CheckMap.heavy).map Fw.Wire.CheckMap.checkName

theorem heavyChecks_eq : heavyChecks = ["lakeBuild", "leanElab", "presetCheck"] := rfl

def lightClass : String := "light"

/-- The work class of a polish commit from the kinds of its checkmap commands: the heavy kinds it ran, joined by `+` in
`heavyChecks` order, or `light` when it ran none. The command count is recorded on the span but is not a dimension.
-/
def checksWork (kinds : List String) : List (String × String) :=
  let heavy := heavyChecks.filter kinds.contains
  [(checksDim, if heavy.isEmpty then lightClass else "+".intercalate heavy)]

def modsDim : String := "mods"

def modsLow (n : Nat) : Nat := if n = 0 then 0 else 4 ^ (n.log2 / 2)

def modsWork (n : Nat) : List (String × String) := [(modsDim, toString (modsLow n))]

def builtLine (l : String) : Bool :=
  match l.splitOn "] Built " with
  | [pre, post] =>
    let num (t : String) := !t.isEmpty && t.all Char.isDigit
    let progress := match ((pre.splitOn "[").getLast?.getD "").splitOn "/" with
      | [i, n] => num i && num n
      | _ => false
    let name := (post.splitOn " ").headD ""
    progress && !name.isEmpty && !name.contains ':'
  | _ => false

def builtModules (out : String) : Nat := (out.splitOn "\n").countP builtLine

def lakeDone (out : String) : Bool := 1 < (out.splitOn "Build completed successfully").length

def lakeBuilt? (out : String) : Option Nat :=
  if 0 < builtModules out || lakeDone out then some (builtModules out) else none

theorem lakeBuilt?_some (out : String) (n : Nat) (h : lakeBuilt? out = some n) : n = builtModules out := by
  unfold lakeBuilt? at h
  split at h
  · exact (Option.some.inj h).symm
  · cases h

theorem lakeBuilt?_noop (out : String) (h : lakeDone out = true) (hz : builtModules out = 0) :
    lakeBuilt? out = some 0 := by
  simp [lakeBuilt?, h, hz]

def spanWork (width jobs : Option Nat) (checks : Option (List String)) (built : Option Nat := none) :
    List (String × String) :=
  (checks.map checksWork).getD [] ++ (built.map modsWork).getD [] ++ slotWork width jobs

#guard checksWork ["nodeCheck", "shParse"] == [("checks", "light")] && checksWork [] == [("checks", "light")]
#guard checksWork ["shParse", "lakeBuild", "nodeCheck"] == [("checks", "lakeBuild")]
#guard checksWork ["presetCheck", "lakeBuild", "lakeBuild"] == [("checks", "lakeBuild+presetCheck")]
#guard spanWork (some 2) (some 30) none == [("width", "2")] && spanWork none none none == []
#guard spanWork none none (some ["lakeBuild"]) == [("checks", "lakeBuild")]

theorem checksWork_mem (a b : List String) (h : ∀ x, x ∈ a ↔ x ∈ b) : checksWork a = checksWork b := by
  have hf : heavyChecks.filter a.contains = heavyChecks.filter b.contains :=
    List.filter_congr fun x _ => by simp [h x]
  simp only [checksWork, hf]

theorem checksWork_light (kinds : List String) (h : ∀ k ∈ heavyChecks, k ∉ kinds) :
    checksWork kinds = [(checksDim, lightClass)] := by
  have hf : heavyChecks.filter kinds.contains = [] :=
    List.filter_eq_nil_iff.2 fun k hk => by simp [h k hk]
  simp [checksWork, hf]

theorem checksWork_heavy (kinds : List String) (k : String) (hk : k ∈ heavyChecks) (hm : k ∈ kinds) :
    checksWork kinds ≠ [(checksDim, lightClass)] := by
  have hc : kinds.contains k = true := by simpa using hm
  simp only [heavyChecks_eq, List.mem_cons, List.not_mem_nil, or_false] at hk
  simp only [checksWork, heavyChecks_eq, lightClass, checksDim, List.filter_cons, List.filter_nil]
  rcases hk with rfl | rfl | rfl <;> rw [hc] <;>
    cases kinds.contains "lakeBuild" <;> cases kinds.contains "leanElab" <;> cases kinds.contains "presetCheck" <;>
    simp

theorem spanWork_unchecked (w j : Option Nat) : spanWork w j none = slotWork w j := rfl

#guard [0, 1, 3, 4, 15, 16, 24, 40, 63, 64].map modsLow == [0, 1, 1, 4, 4, 16, 16, 16, 16, 64]
#guard modsWork 24 == [("mods", "16")] && modsWork 0 == [("mods", "0")]
#guard spanWork none none (some ["lakeBuild"]) (some 40) == [("checks", "lakeBuild"), ("mods", "16")]
#guard spanWork (some 2) (some 30) none (some 6) == [("mods", "4"), ("width", "2")]
#guard builtLine "✔ [795/843] Built Fw.Wire (1.3s)" && builtLine "⚠ [3/9] Built Fw.Obs.Timing (12s)"
#guard !builtLine "✔ [840/843] Built fwcore:exe (2.1s)" && !builtLine "✔ [12/843] Built Fw:c.o (90ms)"
#guard !builtLine "✖ [4/9] Building Fw.Obs.Timing" && !builtLine "Built Fw.Wire" && !builtLine "✔ [a/9] Built Fw.Wire"
#guard builtModules "✔ [1/3] Built Fw.A (1s)\n✔ [2/3] Built Fw:c.o (1s)\nBuild completed successfully.\n✔ [3/3] Built Fw.B" == 2

theorem modsLow_le (n : Nat) : modsLow n ≤ n := by
  unfold modsLow
  split
  · omega
  · rename_i h
    have h1 : 4 ^ (n.log2 / 2) = 2 ^ (2 * (n.log2 / 2)) := by rw [Nat.pow_mul]
    have h2 : 2 ^ (2 * (n.log2 / 2)) ≤ 2 ^ n.log2 := Nat.pow_le_pow_right (by omega) (by omega)
    exact h1 ▸ Nat.le_trans h2 (Nat.log2_self_le h)

theorem lt_modsLow (n : Nat) (h : n ≠ 0) : n < 4 * modsLow n := by
  unfold modsLow
  simp only [h, ↓reduceIte]
  have h1 : 4 * 4 ^ (n.log2 / 2) = 2 ^ (2 * (n.log2 / 2) + 2) := by
    rw [Nat.pow_add, Nat.pow_mul, Nat.mul_comm]
  have h2 : 2 ^ (n.log2 + 1) ≤ 2 ^ (2 * (n.log2 / 2) + 2) := Nat.pow_le_pow_right (by omega) (by omega)
  rw [h1]
  exact Nat.lt_of_lt_of_le Nat.lt_log2_self h2

theorem modsLow_eq_zero (n : Nat) : modsLow n = 0 ↔ n = 0 := by
  constructor
  · intro h
    rcases Nat.eq_zero_or_pos n with hn | hn
    · exact hn
    · have := lt_modsLow n (by omega)
      omega
  · intro h
    simp [modsLow, h]

theorem modsWork_eq_iff (a b : Nat) : modsWork a = modsWork b ↔ modsLow a = modsLow b := by
  constructor
  · intro e
    simp only [modsWork, List.cons.injEq, Prod.mk.injEq, true_and, and_true] at e
    exact Nat.repr_injective e
  · intro e
    simp [modsWork, e]

theorem mods_same_lt (a b : Nat) (h : modsLow a = modsLow b) (ha : a ≠ 0) : a < 4 * b :=
  Nat.lt_of_lt_of_le (lt_modsLow a ha) (by rw [h]; exact Nat.mul_le_mul_left 4 (modsLow_le b))

theorem mods_same_zero (a b : Nat) (h : modsLow a = modsLow b) (ha : a = 0) : b = 0 :=
  (modsLow_eq_zero b).1 (by rw [← h, ha]; rfl)

theorem spanWork_mods_ne (w j : Option Nat) (c : Option (List String)) (a b : Nat) (h : modsLow a ≠ modsLow b) :
    spanWork w j c (some a) ≠ spanWork w j c (some b) := by
  intro e
  simp only [spanWork, Option.map_some, Option.getD_some, List.append_cancel_left_eq,
    List.append_cancel_right_eq] at e
  exact h ((modsWork_eq_iff a b).1 e)

theorem spanWork_built_ne_unbuilt (w j : Option Nat) (c : Option (List String)) (a : Nat) :
    spanWork w j c (some a) ≠ spanWork w j c none := by
  intro e
  have := congrArg List.length e
  simp [spanWork, modsWork] at this

structure Group where
  name : String
  keys : List Key
deriving DecidableEq, Repr

/-- A parallel stage: an id and the groups that run side by side in it (the input grouping that defines siblings). -/
structure Stage where
  id     : String
  groups : List Group
deriving DecidableEq, Repr

/-- **The load above which a local sample is contended**, in CPUs of the local Mac (`hw.ncpu` = 8). MEASURED
2026-10-21 over the `lean/check` spans of `.fw-console/timings.jsonl` (36 831 local samples of the `lean/check` spans), the
median duration of one step by the floor of the 1-min load average `λ`, in seconds:

| step | `λ < 4` | `4 ≤ λ < 8` | `8 ≤ λ < 12` | `12 ≤ λ < 16` | `16 ≤ λ < 24` | `24 ≤ λ < 40` |
|---|---|---|---|---|---|---|
| props lint | 16.8 | 19.2 | 22.8 | 22.7 | 24.3 | 22.7 |
| init cost lint | 9.0 | 12.1 | 13.9 | 14.9 | 16.4 | 20.1 |
| shard golden check | 9.1 | 9.4 | 11.6 | 12.1 | 12.5 | 13.2 |

The median of every step rises with `λ` (init cost lint 9.0 s at `λ < 4`, 20.1 s at `24 ≤ λ < 40`), and the burst of
`timing.slow` of 2026-10-21 (props lint 32 to 51 s against a 22.6 s median) came at `λ` 11 to 23, mostly between this
limit and the old 16. The limit is a constant of the machine, not tuned to make a verdict pass: `p.loadMax` still overrides it in tests.

ACCEPTED LIMIT (measured 2026-10-21 over the same spans): 60 to 96 percent of the local `lean/check` samples of a day are
contended at `L = 8` (2026-10-17 96, 10-18 83, 10-19 86, 10-20 60, 10-21 82), so the local `timing.slow` is silent for most
samples and a regression that shows only on a loaded machine is seen by the CI timings, not here. The heavy-job lock
(`Fw.Sched.Heavy`) exists to lower that fraction; this module does not hide it. -/
def contendedLoad : Nat := 8

/-- The load at or below which an open `sys.contended` closes (hysteresis, `Fw.Obs.Health.contendedNow`): half the CPUs of
the local Mac. The table above measures the steps at `λ < 4` as the fastest column (props lint 16.8 s against 19.2 s at
`4 ≤ λ < 8`), so a floor at or below 4 is a calm machine. Replayed over the 5-minute bins of the local timing samples of
`.fw-console/timings.jsonl` (lowest load floor of each bin; 2026-10-17 to 21), opening above 8 gives 5, 32, 25, 25, 12 OPEN
lines a day, and holding it open down to 5 gives 1, 11, 6, 14, 2 (replay, INFERRED: local timings, not a live run). -/
def calmLoad : Nat := 4

/-- The closing load is below the opening load, so the alert has a band to hold in. -/
theorem calmLoad_lt : calmLoad < contendedLoad := by decide

/-- The parameters: `n_min` (`nMin`), the window length `N` (`window`), the multiplier `k = k_n / k_d`
(`kNum`, `kDen`), the default budget `B_0` in ms (`budgetMs`), per-tool budget overrides (`budgets`, first match
wins), per-step ceilings (`ceilings`, first match wins), the load limit `L` (`loadMax`, compared with the floor of the 1-min load average; the default is `contendedLoad`, the 8 CPUs
of the local Mac), and the parallel stages (`stages`).
-/
structure Params where
  nMin     : Nat := 5
  window   : Nat := 20
  kNum     : Nat := 3
  kDen     : Nat := 2
  budgetMs : Nat := 30000
  budgets  : List (String × Nat) := []
  waitBudgetMs : Nat := 1800000
  ceilings : List (String × String × Nat) := []
  loadMax  : Nat := contendedLoad
  stages   : List Stage := []
deriving Repr

/-! ## Nearest-rank quantile -/

/-- The number of values of `xs` at or below `v`. -/
def cntLe (xs : List Nat) (v : Nat) : Nat := xs.countP (fun x => decide (x ≤ v))

/-- The values of `xs` with at least `j + 1` values of `xs` at or below them (in list order). -/
def cands (xs : List Nat) (j : Nat) : List Nat := xs.filter (fun v => decide (j + 1 ≤ cntLe xs v))

/-- The order statistic of index `j` (0-based): the least value of `xs` with at least `j + 1` values of `xs` at or
below it, that is the `(j+1)`-th smallest value; 0 when there is none (exactly when `j ≥ |X|`).
-/
def ord (xs : List Nat) (j : Nat) : Nat := ((cands xs j).min?).getD 0

/-- The nearest rank of the 90th percentile among `n` values: `⌈ 9n/10 ⌉` (1-based; 0 for `n = 0`). -/
def rank90 (n : Nat) : Nat := (9 * n + 9) / 10

/-- The nearest-rank p90 of a list: its `⌈ 9n/10 ⌉`-th smallest value; 0 for the empty list. -/
def p90 (xs : List Nat) : Nat := ord xs (rank90 xs.length - 1)

#guard rank90 0 == 0 && rank90 1 == 1 && rank90 9 == 9 && rank90 10 == 9 && rank90 11 == 10 && rank90 20 == 18
#guard ord [5, 1, 4, 1, 3] 0 == 1 && ord [5, 1, 4, 1, 3] 1 == 1 && ord [5, 1, 4, 1, 3] 2 == 3
#guard ord [5, 1, 4, 1, 3] 4 == 5 && ord [5, 1, 4, 1, 3] 5 == 0 && ord [] 0 == 0
#guard p90 [] == 0 && p90 [7] == 7 && p90 [3, 9, 1] == 9
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100] == 90
#guard p90 [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110] == 100

/-- The nearest rank of the median among `n` values: `⌈ n/2 ⌉` (1-based; 0 for `n = 0`). -/
def rank50 (n : Nat) : Nat := (n + 1) / 2

/-- The nearest-rank median (p50) of a list: its `⌈ n/2 ⌉`-th smallest value (the lower median for an even
length); 0 for the empty list. This is the baseline of the slow test.
-/
def p50 (xs : List Nat) : Nat := ord xs (rank50 xs.length - 1)

#guard rank50 0 == 0 && rank50 1 == 1 && rank50 2 == 1 && rank50 5 == 3 && rank50 6 == 3 && rank50 20 == 10
#guard p50 [] == 0 && p50 [7] == 7 && p50 [3, 9, 1] == 3 && p50 [4, 1, 3, 2] == 2
#guard p50 [2000, 1000, 2000, 27000, 26000] == 2000 && p90 [2000, 1000, 2000, 27000, 26000] == 27000

/-! ## The verdict of one sample -/

/-- A sample is contended when it ran locally at a load above the limit (CI samples never are). -/
def contended (p : Params) (s : Sample) : Bool := decide (s.host = .«local») && decide (p.loadMax < s.load)

/-- The last `n` elements of a list (all of it when it is shorter). -/
def lastN (n : Nat) (xs : List Nat) : List Nat := xs.drop (xs.length - n)

/-- A sample waited when its acquire waited under any reason (`waitMs > 0`, memory included). Such a sample stays out of
    the windows (`counts`). -/
def Sample.waited (s : Sample) : Bool := decide (0 < s.waitMs)

def holderWait : Fw.Sup.Adapt.WhyTag → Bool
  | .queued | .older | .full | .simBusy | .drain | .simFirst | .pass | .measureBusy | .gap | .unknown => true
  | .memory | .memLow => false

def Sample.holdMs (s : Sample) : Nat := ((s.waits.filter (fun w => holderWait w.1)).map (·.2)).sum

def queuedWithin (s : Sample) : Bool := decide (0 < s.holdMs)

def Sample.rest (s : Sample) : Sample := { s with durMs := s.durMs - s.holdMs, waitMs := 0, waits := [] }

def counts (p : Params) (s : Sample) : Bool := s.full && !contended p s && !s.waited

def windowOf (p : Params) (hist : List Sample) (k : Key) : List Nat :=
  lastN p.window ((hist.filter (fun s => decide (s.key = k) && counts p s)).map (·.durMs))

def waitTool : String := "fw wait"

def budgetOf (p : Params) (tool : String) : Nat :=
  (p.budgets.lookup tool).getD (if tool == waitTool then p.waitBudgetMs else p.budgetMs)

/-- The ceiling of a step: the limit of the first entry of `ceilings` with that tool and step, if any. -/
def ceilingOf (p : Params) (tool step : String) : Option Nat :=
  (p.ceilings.find? (fun c => decide (c.1 = tool) && decide (c.2.1 = step))).map (·.2.2)

/-- A sample breaches its ceiling when its step has one, the sample is not contended, and it took longer than the ceiling.
No window is involved.
-/
def ceilingBreach (p : Params) (s : Sample) : Bool :=
  match ceilingOf p s.tool s.step with
  | some c => decide (c < s.durMs) && !contended p s
  | none => false

/-- The budget a sample is held to: its tool's budget, lowered to the step's ceiling when the step has one. -/
def budgetFor (p : Params) (s : Sample) : Nat :=
  match ceilingOf p s.tool s.step with
  | some c => min (budgetOf p s.tool) c
  | none => budgetOf p s.tool

/-- The slow test, exact over the rationals: `d > max(B, k · b)` with `k = k_n / k_d`, cross-multiplied so no
division happens (for `k_d ≥ 1` it is the same as `d > B ∧ d > k · b`; for `k_d = 0` the second half is
false and nothing is slow).
-/
def overLimit (p : Params) (budget base d : Nat) : Bool :=
  decide (budget < d) && decide (p.kNum * base < p.kDen * d)

/-- The verdict code of one sample. -/
inductive Code where
  | noBaseline
  | contended
  | ok
  | slow
  | queued
  | mixed
  | unkeyed
deriving DecidableEq, Repr

/-- The code of sample `s` against window `w`, first match: too short a window, contended, slow, ok. The baseline is the
median of the window (with `n_min = 0` an empty window passes the first test and has baseline 0).
-/
def codeOf (p : Params) (w : List Nat) (s : Sample) : Code :=
  if w.length < p.nMin then .noBaseline
  else if contended p s then .contended
  else if overLimit p (budgetOf p s.tool) (p50 w) s.durMs then .slow
  else .ok

/-- The verdict of one sample: its index, key and duration, the code, the window size, the baseline (p50 of the
window, 0 for an empty window) and the budget.
-/
structure SampleVerdict where
  idx      : Nat
  tool     : String
  step     : String
  host     : Host
  durMs    : Nat
  code     : Code
  n        : Nat
  baseline : Nat
  budgetMs : Nat
  kind     : String := ""
  work     : List (String × String) := []
deriving DecidableEq, Repr

/-- The verdict of sample `s` at index `i` with the earlier samples `hist`: `slow` when it breaches its step's ceiling
(whatever the window), else the code against the window.
-/
def judge (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  let w := windowOf p hist s.key
  { idx := i, tool := s.tool, step := s.step, host := s.host, durMs := s.durMs,
    code := if ceilingBreach p s then .slow else codeOf p w s,
    n := w.length, baseline := p50 w, budgetMs := budgetFor p s, kind := s.kind, work := s.work }

/-- The verdict of a sample that waited for a slot holder: judged on its duration without the wait, and `queued` unless
that is `slow`.
-/
def judgeW (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  if queuedWithin s then
    let v := judge p hist i s.rest
    { v with durMs := s.durMs, code := if v.code = .slow then .slow else .queued }
  else judge p hist i s

/-- The `fw slot run` kinds (`apps/runner/src/slot-core.ts` `KINDS`). -/
def slotKinds : List String := ["check", "test", "land", "sim", "other", "measure"]

/-- The step names of the overflow bucket of slot kind `k`: `slot run k` with no command key, plain, dry, cached or
both.
-/
def bucketSteps (k : String) : List String :=
  let b := s!"slot run {k}"
  [b, b ++ " dry", b ++ " cached", b ++ " dry cached"]

/-- A sample of an overflow bucket: an `fw` span named by `bucketSteps` of a slot kind. Its history pools every command
past the kind's key cap, so its window is no baseline for any one of them.
-/
def Sample.mixed (s : Sample) : Bool := s.tool == "fw" && slotKinds.any fun k => (bucketSteps k).contains s.step

def SampleVerdict.markMixed (v : SampleVerdict) : SampleVerdict := { v with code := .mixed }

def judgeQ0 (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  if s.mixed then (judgeW p hist i s).markMixed else judgeW p hist i s

def Sample.sameStep (s t : Sample) : Bool :=
  s.tool == t.tool && s.step == t.step && decide (s.host = t.host) && s.kind == t.kind

def Sample.unkeyed (s : Sample) : Bool := !(s.work.any fun kv => kv.1 == checksDim || kv.1 == modsDim)

def unkeyedLate (hist : List Sample) (s : Sample) : Bool :=
  s.unkeyed && hist.any (fun t => t.full && !t.unkeyed && s.sameStep t)

def SampleVerdict.markUnkeyed (v : SampleVerdict) : SampleVerdict := { v with code := .unkeyed }

def judgeQ(p : Params) (hist : List Sample) (i : Nat) (s : Sample) : SampleVerdict :=
  if s.mixed then (judgeW p hist i s).markMixed
  else if unkeyedLate hist s then (judgeW p hist i s).markUnkeyed
  else judgeW p hist i s

#guard ({ tool := "fw", step := "slot run check", durMs := 1, host := .«local» } : Sample).mixed
#guard ({ tool := "fw", step := "slot run test dry cached", durMs := 1, host := .«local» } : Sample).mixed
#guard !({ tool := "fw", step := "slot run check sh lean/scripts/check.sh", durMs := 1, host := .«local» } : Sample).mixed
#guard !({ tool := "lean", step := "slot run check", durMs := 1, host := .«local» } : Sample).mixed
#guard !({ tool := "fw", step := "slot wait check", durMs := 1, host := .«local» } : Sample).mixed

/-- One verdict per sample, in input order; sample `i` is judged against the samples before it. -/
def sampleVerdicts (p : Params) (ss : List Sample) : List SampleVerdict :=
  ss.mapIdx (fun i s => judgeQ p (ss.take i) i s)

/-! ## Structural verdicts -/

/-- The final baseline of a key: the p50 of its window over all samples, defined when that window has at least
`n_min` samples.
-/
def finalBaseline (p : Params) (ss : List Sample) (k : Key) : Option Nat :=
  if p.nMin ≤ (windowOf p ss k).length then some (p50 (windowOf p ss k)) else none

/-- The largest value of a list, 0 for the empty list. -/
def maxL (xs : List Nat) : Nat := xs.foldl max 0

/-- A group's baseline: the largest final baseline of its keys, defined when the group has a key and every key has a
final baseline.
-/
def groupBaseline (p : Params) (ss : List Sample) (g : Group) : Option Nat :=
  let bs := g.keys.filterMap (finalBaseline p ss)
  if !g.keys.isEmpty && bs.length == g.keys.length then some (maxL bs) else none

/-- The call on one group of a stage: it sets the stage's time by a wide margin (`structural`), it does not
(`noise`), or there is not enough history to tell (`undecided`).
-/
inductive Call where
  | structural
  | noise
  | undecided
deriving DecidableEq, Repr

/-- A structural verdict: the stage, the group, the call on it, its baseline (0 when it has none) and the largest
sibling baseline (0 when no sibling has one).
-/
structure StructVerdict where
  stage      : String
  group      : String
  call       : Call
  baseline   : Nat
  siblingMax : Nat
deriving DecidableEq, Repr

/-- The test on the sibling baselines: every sibling has one and twice it is below `b`. -/
def below (b : Nat) : Option Nat → Bool
  | some c => decide (2 * c < b)
  | none => false

/-- The sibling baselines of group `g` in stage `S`: the group baselines of the other groups of the stage, in order
(a group listed twice is not its own sibling).
-/
def siblings (p : Params) (ss : List Sample) (st : Stage) (g : Group) : List (Option Nat) :=
  (st.groups.filter (fun g' => decide (g' ≠ g))).map (groupBaseline p ss)

/-- The call on group `g` in stage `S`, first match: `undecided` when `g` has no baseline or no sibling;
`structural` when every sibling has a baseline `c` with `2c < b`; `noise` when every sibling has a baseline (so one
of them has `2c ≥ b`); `undecided` otherwise (a sibling without a baseline).
-/
def callOf (p : Params) (ss : List Sample) (st : Stage) (g : Group) : Call :=
  match groupBaseline p ss g with
  | none => .undecided
  | some b =>
    let sib := siblings p ss st g
    if sib.isEmpty then .undecided
    else if sib.all (below b) then .structural
    else if sib.all Option.isSome then .noise
    else .undecided

/-- The structural verdict of group `g` in stage `S`: the call, the group's baseline (0 without one) and the largest
sibling baseline (0 without one).
-/
def stageVerdict (p : Params) (ss : List Sample) (st : Stage) (g : Group) : StructVerdict :=
  { stage := st.id, group := g.name, call := callOf p ss st g, baseline := (groupBaseline p ss g).getD 0,
    siblingMax := maxL ((siblings p ss st g).filterMap id) }

/-- A job-level CI sample: a CI sample whose step is a job name (no `/`; step spans are `<job>/<step>`). -/
def isJob (s : Sample) : Bool := decide (s.host = .ci) && !s.step.contains '/'

/-- The job family of a job name: the name up to its first `" ("`, so the matrix legs `gate (chromium, s4)` and
`gate (playwright-webkit, s0)` share the family `gate`; a name without `" ("` is its own family.
-/
def family (step : String) : String := (step.splitOn " (").headD step

def jobKeys (ss : List Sample) : List Key := ((ss.filter (fun s => isJob s && s.full)).map Sample.key).eraseDups

/-- The stages derived from the samples when the caller gives none: one stage per CI workflow (tool) that has at
least two job families, with one group per family (named by the family, holding that family's job keys), in first
occurrence order. A workflow is coarser than a parallel stage: sequential jobs count as siblings too.
-/
def autoStages (ss : List Sample) : List Stage :=
  let ks := jobKeys ss
  (ks.map (·.tool)).eraseDups.filterMap fun t =>
    let fams := ((ks.filter (fun k => decide (k.tool = t))).map (fun k => family k.step)).eraseDups
    if fams.length < 2 then none
    else some { id := t, groups := fams.map fun f =>
      { name := f, keys := ks.filter (fun k => decide (k.tool = t) && decide (family k.step = f)) } }

/-- The stages the structural calls are made on: the caller's stages when it gives any, else the derived ones. -/
def stagesOf (p : Params) (ss : List Sample) : List Stage :=
  if p.stages.isEmpty then autoStages ss else p.stages

/-- All structural verdicts: one per group of every stage, stage by stage, group by group. -/
def structuralVerdicts (p : Params) (ss : List Sample) : List StructVerdict :=
  (stagesOf p ss).flatMap (fun st => st.groups.map (stageVerdict p ss st))

/-- A verdict: one per sample, or a structural one. -/
inductive Verdict where
  | sample (v : SampleVerdict)
  | structural (v : StructVerdict)
deriving DecidableEq, Repr

def fullVerdicts (p : Params) (ss : List Sample) : List SampleVerdict :=
  ((ss.zip (sampleVerdicts p ss)).filter (fun x => x.1.full)).map (·.2)

/-- The entry point (wire op `obs.timing`): the full samples in time order give one verdict each, in order, followed
by the structural verdicts.
-/
def timingVerdicts (p : Params) (ss : List Sample) : List Verdict :=
  (fullVerdicts p ss).map .sample ++ (structuralVerdicts p ss).map .structural

/-- A local key for the examples below. -/
private def lk : Key := { tool := "t", step := "s", host := .«local» }

#guard (codeOf {} [] { tool := "t", step := "s", durMs := 999999, host := .ci }) == .noBaseline
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := "t", step := "s", durMs := 30000, host := .ci }) == .ok
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := "t", step := "s", durMs := 30001, host := .ci }) == .slow
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150000, host := .ci }) == .ok
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .ci }) == .slow
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .«local», load := 17 }) == .contended
#guard (codeOf {} [100000, 100000, 100000, 100000, 100000]
  { tool := "t", step := "s", durMs := 150001, host := .ci, load := 99 }) == .slow
#guard budgetOf { budgets := [("ci", 120000), ("ci", 1)] } "ci" == 120000 && budgetOf {} "x" == 30000
#guard windowOf { window := 2 } [{ tool := "t", step := "s", durMs := 1, host := .«local» },
  { tool := "t", step := "s", durMs := 2, host := .«local», load := 17 },
  { tool := "t", step := "s", durMs := 3, host := .«local» },
  { tool := "t", step := "s", durMs := 4, host := .ci },
  { tool := "t", step := "s", durMs := 5, host := .«local» }] lk == [3, 5]
#guard (timingVerdicts { nMin := 1, stages := [{ id := "x", groups := [{ name := "a", keys := [lk] },
  { name := "b", keys := [{ lk with step := "b" }] }] }] }
  [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 49, host := .«local» }]).length == 4
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 50, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .noise
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» },
   { tool := "t", step := "b", durMs := 49, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .structural
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }, { name := "b", keys := [{ lk with step := "b" }] }] }
  { name := "a", keys := [lk] }) == .undecided
#guard (callOf { nMin := 1 } [{ tool := "t", step := "s", durMs := 100, host := .«local» }]
  { id := "x", groups := [{ name := "a", keys := [lk] }] } { name := "a", keys := [lk] }) == .undecided
#guard family "gate (chromium, s4)" == "gate" && family "site" == "site" && family "" == ""
#guard isJob { tool := "w", step := "site", durMs := 1, host := .ci } &&
  !isJob { tool := "w", step := "site/Build", durMs := 1, host := .ci } &&
  !isJob { tool := "w", step := "site", durMs := 1, host := .«local» }
#guard (autoStages [{ tool := "w", step := "gate (c, s0)", durMs := 1, host := .ci },
    { tool := "w", step := "sweeps (c)", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s1)", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s0)/Run", durMs := 1, host := .ci },
    { tool := "v", step := "only", durMs := 1, host := .ci },
    { tool := "w", step := "gate (c, s0)", durMs := 1, host := .ci }]).map
    (fun st => (st.id, st.groups.map (fun g => (g.name, g.keys.map (·.step))))) ==
  [("w", [("gate", ["gate (c, s0)", "gate (c, s1)"]), ("sweeps", ["sweeps (c)"])])]
#guard stagesOf { stages := [{ id := "x", groups := [] }] } [] == [{ id := "x", groups := [] }]

/-! ## Proofs: the verdict of one sample -/

/-- A sample breaches its ceiling exactly when its step has a ceiling `c`, it is not contended and it took longer than `c`. -/
theorem ceilingBreach_iff (p : Params) (s : Sample) :
    ceilingBreach p s = true ↔
      ∃ c, ceilingOf p s.tool s.step = some c ∧ c < s.durMs ∧ contended p s = false := by
  unfold ceilingBreach
  cases h : ceilingOf p s.tool s.step with
  | none => simp
  | some c => simp

/-- The relative rule alone: the code against a window is `slow` exactly when the window is long enough, the sample is
not contended, and its duration exceeds both the budget and `k` times the baseline.
-/
theorem codeOf_slow_iff (p : Params) (w : List Nat) (s : Sample) :
    codeOf p w s = .slow ↔
      p.nMin ≤ w.length ∧ contended p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p50 w < p.kDen * s.durMs := by
  unfold codeOf overLimit
  split
  · constructor
    · intro h; cases h
    · intro h; omega
  · rename_i h1
    split
    · rename_i h2
      constructor
      · intro h; cases h
      · intro h; rw [h2] at h; cases h.2.1
    · rename_i h2
      have h2' : contended p s = false := by simpa using h2
      split
      · rename_i h3
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h3
        exact ⟨fun _ => ⟨by omega, h2', h3⟩, fun _ => rfl⟩
      · rename_i h3
        simp only [Bool.and_eq_true, decide_eq_true_eq] at h3
        constructor
        · intro h; cases h
        · intro h; exact absurd ⟨h.2.2.1, h.2.2.2⟩ h3

/-- When a sample's verdict is `slow`: it breaches its step's ceiling (no window needed), or the window is long
enough, the sample is not contended, and its duration exceeds both the budget and `k` times the baseline.
-/
theorem slow_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code = .slow ↔
      ceilingBreach p s = true ∨
      (p.nMin ≤ (windowOf p hist s.key).length ∧ contended p s = false ∧ budgetOf p s.tool < s.durMs ∧
        p.kNum * p50 (windowOf p hist s.key) < p.kDen * s.durMs) := by
  unfold judge
  simp only
  by_cases hb : ceilingBreach p s = true
  · simp [hb]
  · simp only [hb, Bool.false_eq_true, ite_false, false_or]
    exact codeOf_slow_iff p _ s

/-- No alert within budget: a sample whose duration is at most its budget (its tool's budget, lowered to the step's
ceiling) is never `slow`.
-/
theorem no_alert_within_budget (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : s.durMs ≤ budgetFor p s) : (judge p hist i s).code ≠ .slow := by
  intro hs
  unfold budgetFor at h
  rcases (slow_iff p hist i s).1 hs with hb | hr
  · obtain ⟨c, hc, hlt, _⟩ := (ceilingBreach_iff p s).1 hb
    rw [hc] at h
    simp only at h
    omega
  · have := hr.2.2.1
    cases hc : ceilingOf p s.tool s.step with
    | none => rw [hc] at h; simp only at h; omega
    | some c => rw [hc] at h; simp only at h; omega

theorem mem_sample_full (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) :
    ∃ i, ∃ hi : i < hist.length, hist[i].full = true ∧ v = judgeQ p (hist.take i) i hist[i] := by
  simp only [timingVerdicts, List.mem_append, List.mem_map] at h
  rcases h with ⟨w, hw, he⟩ | ⟨w, _, he⟩
  · cases he
    simp only [fullVerdicts, List.mem_map, List.mem_filter] at hw
    obtain ⟨x, ⟨hx, hf⟩, rfl⟩ := hw
    obtain ⟨i, hi, he⟩ := List.mem_iff_getElem.1 hx
    have hl : i < hist.length := by simp [sampleVerdicts] at hi; omega
    refine ⟨i, hl, ?_, ?_⟩
    · rw [← he] at hf; simpa using hf
    · rw [← he]; simp [sampleVerdicts, List.getElem_mapIdx]
  · cases he

theorem mem_sample (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) :
    ∃ i, ∃ hi : i < hist.length, v = judgeQ p (hist.take i) i hist[i] := by
  obtain ⟨i, hi, _, he⟩ := mem_sample_full p hist v h
  exact ⟨i, hi, he⟩

/-- The ceilings of `fw land`, from the land-speed research targets (a Lean-touching land under 20 s p50, the lock
held under 5 s): 30 s for the whole land (step `total`) and 5 s for the time its lock is held (step `lock held`).
-/
def landCeilings : List (String × String × Nat) :=
  [("fw land", "total", 30000), ("fw land", "lock held", 5000)]

/-- A land over budget alerts. With the land ceilings first in `ceilings`, a not contended `fw land` sample over 30 s for
its `total`, or over 5 s for its `lock held`, has the verdict `slow`, whatever its history (even none: a land that is
slow from its first run is flagged).
-/
theorem land_budget_alert (p : Params) (hp : ∃ rest, p.ceilings = landCeilings ++ rest)
    (hist : List Sample) (i : Nat) (s : Sample) (hn : contended p s = false)
    (hs : (s.tool = "fw land" ∧ s.step = "total" ∧ 30000 < s.durMs) ∨
          (s.tool = "fw land" ∧ s.step = "lock held" ∧ 5000 < s.durMs)) :
    (judge p hist i s).code = .slow := by
  obtain ⟨rest, hr⟩ := hp
  refine (slow_iff p hist i s).2 (Or.inl ((ceilingBreach_iff p s).2 ?_))
  rcases hs with ⟨ht, hst, hd⟩ | ⟨ht, hst, hd⟩
  · exact ⟨30000, by simp [ceilingOf, hr, landCeilings, ht, hst], hd, hn⟩
  · exact ⟨5000, by simp [ceilingOf, hr, landCeilings, ht, hst], hd, hn⟩

theorem budgetOf_wait (p : Params) (h : p.budgets.lookup waitTool = none) : budgetOf p waitTool = p.waitBudgetMs := by
  have e : waitTool == waitTool := by decide
  simp [budgetOf, h, e]

theorem budgetOf_work (p : Params) (t : String) (h : p.budgets.lookup t = none) (hw : t ≠ waitTool) :
    budgetOf p t = p.budgetMs := by
  simp [budgetOf, h, hw]

theorem wait_within_budget_not_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hw : s.tool = waitTool) (hu : p.budgets.lookup waitTool = none) (hc : ceilingOf p s.tool s.step = none)
    (hd : s.durMs ≤ p.waitBudgetMs) : (judge p hist i s).code ≠ .slow := by
  intro hs
  rcases (slow_iff p hist i s).1 hs with hb | hr
  · obtain ⟨c, hc', _⟩ := (ceilingBreach_iff p s).1 hb
    rw [hc] at hc'
    cases hc'
  · have := hr.2.2.1
    rw [hw, budgetOf_wait p hu] at this
    omega

theorem wait_over_budget_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hw : s.tool = waitTool) (hu : p.budgets.lookup waitTool = none) (hn : p.nMin ≤ (windowOf p hist s.key).length)
    (hq : contended p s = false) (hB : p.waitBudgetMs < s.durMs)
    (hk : p.kNum * p50 (windowOf p hist s.key) < p.kDen * s.durMs) : (judge p hist i s).code = .slow :=
  (slow_iff p hist i s).2 (Or.inr ⟨hn, hq, by rw [hw, budgetOf_wait p hu]; exact hB, hk⟩)

#guard (codeOf {} [100, 100, 100, 100, 100] { tool := waitTool, step := "slot wait check", durMs := 40000, host := .ci }) == .ok
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := waitTool, step := "slot wait check", durMs := 1800001, host := .ci }) == .slow
#guard (codeOf {} [100, 100, 100, 100, 100] { tool := "fw", step := "slot run check x", durMs := 40000, host := .ci }) == .slow

/-- Slow is monotone in the duration: with the same history, a sample that is `slow` stays `slow` when it takes
longer.
-/
theorem slow_mono_dur (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (d : Nat)
    (h : (judge p hist i s).code = .slow) (hd : s.durMs ≤ d) :
    (judge p hist i { s with durMs := d }).code = .slow := by
  rcases (slow_iff p hist i s).1 h with hb | ⟨h1, h2, h3, h4⟩
  · obtain ⟨c, hc, hlt, hn⟩ := (ceilingBreach_iff p s).1 hb
    exact (slow_iff p hist i _).2 (Or.inl ((ceilingBreach_iff p _).2 ⟨c, hc, by simp only; omega, hn⟩))
  · refine (slow_iff p hist i _).2 (Or.inr ⟨h1, h2, by simp only; omega, ?_⟩)
    exact Nat.lt_of_lt_of_le h4 (Nat.mul_le_mul_left _ hd)

/-- The verdict is `noBaseline` exactly when the window has fewer than `n_min` samples and the sample does not
breach a ceiling (a breach is `slow` whatever the window).
-/
theorem noBaseline_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code = .noBaseline ↔
      (windowOf p hist s.key).length < p.nMin ∧ ceilingBreach p s = false := by
  by_cases hb : ceilingBreach p s = true
  · simp [judge, hb]
  · have hb' : ceilingBreach p s = false := by simpa using hb
    simp only [judge, hb', Bool.false_eq_true, ite_false, and_true, codeOf]
    by_cases h1 : (windowOf p hist s.key).length < p.nMin
    · simp [h1]
    · simp only [h1, ite_false, iff_false]
      split
      · intro h; cases h
      · split <;> (intro h; cases h)

/-- The window is at most `N` long and at most as long as the number of earlier samples with the same key. -/
theorem window_length (p : Params) (hist : List Sample) (k : Key) :
    (windowOf p hist k).length ≤ p.window ∧
      (windowOf p hist k).length ≤ hist.countP (fun s => decide (s.key = k)) := by
  have hc : (hist.filter (fun s => decide (s.key = k) && counts p s)).length ≤
      hist.countP (fun s => decide (s.key = k)) := by
    rw [← List.countP_eq_length_filter]
    exact List.countP_mono_left (by intro x _ hx; simp only [Bool.and_eq_true] at hx; exact hx.1)
  simp only [windowOf, lastN, List.length_drop, List.length_map]
  omega

/-- Below `n_min`, no verdict: with fewer than `n_min` earlier samples of the same key, or a window shorter than
`n_min`, the verdict is `noBaseline` (unless the sample breaches a ceiling, which needs no window).
-/
theorem noBaseline_below_nmin (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hb : ceilingBreach p s = false)
    (h : hist.countP (fun t => decide (t.key = s.key)) < p.nMin ∨ p.window < p.nMin) :
    (judge p hist i s).code = .noBaseline := by
  have := window_length p hist s.key
  exact (noBaseline_iff p hist i s).2 ⟨by omega, hb⟩

/-- Deterministic and local: the verdict of a sample depends only on the parameters, the sample, its index and the
earlier samples with the same key (samples of other steps or hosts, in any interleaving, change nothing).
-/
theorem deterministic (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judge p hist i s = judge p (hist.filter (fun t => decide (t.key = s.key))) i s := by
  have : windowOf p hist s.key = windowOf p (hist.filter (fun t => decide (t.key = s.key))) s.key := by
    simp only [windowOf, List.filter_filter]
    congr 3
    funext x
    cases decide (x.key = s.key) <;> simp
  simp only [judge, this]

theorem fullVerdicts_all_full (p : Params) (ss : List Sample) (hf : ∀ s ∈ ss, s.full = true) :
    fullVerdicts p ss = sampleVerdicts p ss := by
  have hl : (sampleVerdicts p ss).length ≤ ss.length := by simp [sampleVerdicts]
  unfold fullVerdicts
  rw [List.filter_eq_self.2 (fun x hx => hf x.1 (List.of_mem_zip hx).1)]
  exact List.map_snd_zip hl

theorem timingVerdicts_all_full (p : Params) (ss : List Sample) (hf : ∀ s ∈ ss, s.full = true) :
    timingVerdicts p ss = (sampleVerdicts p ss).map .sample ++ (structuralVerdicts p ss).map .structural := by
  rw [timingVerdicts, fullVerdicts_all_full p ss hf]

theorem windowOf_all_full (p : Params) (hist : List Sample) (k : Key) (hf : ∀ s ∈ hist, s.full = true) :
    windowOf p hist k = lastN p.window ((hist.filter (fun s => decide (s.key = k) && !contended p s && !s.waited)).map (·.durMs)) := by
  unfold windowOf
  congr 2
  apply List.filter_congr
  intro x hx
  simp [counts, hf x hx, Bool.and_assoc]

theorem jobKeys_all_full (ss : List Sample) (hf : ∀ s ∈ ss, s.full = true) :
    jobKeys ss = ((ss.filter isJob).map Sample.key).eraseDups := by
  unfold jobKeys
  congr 2
  apply List.filter_congr
  intro x hx
  simp [hf x hx]

theorem timingVerdicts_total (p : Params) (hist : List Sample) (hf : ∀ s ∈ hist, s.full = true) :
    (timingVerdicts p hist).length = hist.length + (structuralVerdicts p hist).length ∧
      ∀ i (hi : i < hist.length),
        (timingVerdicts p hist)[i]? = some (.sample (judgeQ p (hist.take i) i hist[i])) := by
  rw [timingVerdicts_all_full p hist hf]
  refine ⟨by simp [sampleVerdicts], ?_⟩
  intro i hi
  have hl : i < ((sampleVerdicts p hist).map Verdict.sample).length := by simpa [sampleVerdicts] using hi
  rw [List.getElem?_append_left hl]
  simp [sampleVerdicts, hi]

theorem windowOf_filter_full (p : Params) (hist : List Sample) (k : Key) :
    windowOf p hist k = windowOf p (hist.filter Sample.full) k := by
  simp only [windowOf, List.filter_filter]
  congr 3
  funext x
  cases hx : x.full <;> simp [counts, hx]

theorem judge_filter_full (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judge p hist i s = judge p (hist.filter Sample.full) i s := by
  simp only [judge, ← windowOf_filter_full]

theorem judge_indep (p : Params) (hist hist' : List Sample) (i : Nat) (s : Sample)
    (h : hist.filter Sample.full = hist'.filter Sample.full) : judge p hist i s = judge p hist' i s := by
  rw [judge_filter_full p hist, judge_filter_full p hist', h]

theorem judge_insert_other (p : Params) (a cs b : List Sample) (i : Nat) (s : Sample)
    (hc : ∀ c ∈ cs, c.full = false) : judge p (a ++ cs ++ b) i s = judge p (a ++ b) i s := by
  apply judge_indep
  have h : cs.filter Sample.full = [] := List.filter_eq_nil_iff.2 (fun c h' => by simp [hc c h'])
  simp only [List.filter_append, h, List.append_nil]

theorem windowOf_insert_key (p : Params) (a b : List Sample) (x : Sample) (k : Key) (h : x.key ≠ k) :
    windowOf p (a ++ x :: b) k = windowOf p (a ++ b) k := by
  simp [windowOf, List.filter_append, h]

theorem judge_insert_key (p : Params) (a b : List Sample) (x : Sample) (i : Nat) (s : Sample) (h : x.key ≠ s.key) :
    judge p (a ++ x :: b) i s = judge p (a ++ b) i s := by
  simp only [judge, windowOf_insert_key p a b x s.key h]

theorem windowOf_filter_key (p : Params) (hist : List Sample) (k : Key) :
    windowOf p (hist.filter (fun x => decide (x.key = k))) k = windowOf p hist k := by
  unfold windowOf
  rw [List.filter_filter]
  congr 3
  funext x
  by_cases h : x.key = k <;> simp [h]

theorem rest_key (s : Sample) : s.rest.key = s.key := rfl

theorem judgeW_filter_key (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judgeW p (hist.filter (fun x => decide (x.key = s.key))) i s = judgeW p hist i s := by
  have hj : ∀ t : Sample, t.key = s.key →
      judge p (hist.filter (fun x => decide (x.key = s.key))) i t = judge p hist i t := by
    intro t ht
    simp only [judge, ← ht, windowOf_filter_key]
  unfold judgeW
  rw [hj s rfl, hj s.rest (rest_key s)]

theorem judgeQ0_filter_key (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    judgeQ0 p (hist.filter (fun x => decide (x.key = s.key))) i s = judgeQ0 p hist i s := by
  simp only [judgeQ0, judgeW_filter_key]

theorem filter_key_work (hist : List Sample) (s : Sample) :
    (hist.filter (fun x => decide (x.work = s.work))).filter (fun x => decide (x.key = s.key)) =
      hist.filter (fun x => decide (x.key = s.key)) := by
  rw [List.filter_filter]
  congr 1
  funext x
  by_cases h : x.key = s.key
  · have hw : x.work = s.work := congrArg Key.work h
    simp [h, hw]
  · simp [h]

theorem judgeQ0_same_work (p : Params) (hist hist' : List Sample) (i : Nat) (s : Sample)
    (h : hist.filter (fun x => decide (x.work = s.work)) = hist'.filter (fun x => decide (x.work = s.work))) :
    judgeQ0 p hist i s = judgeQ0 p hist' i s := by
  rw [← judgeQ0_filter_key p hist, ← judgeQ0_filter_key p hist', ← filter_key_work hist, ← filter_key_work hist', h]

theorem judgeQ0_other_work (p : Params) (hist others : List Sample) (i : Nat) (s : Sample)
    (h : ∀ x ∈ others, x.work ≠ s.work) :
    judgeQ0 p (hist ++ others) i s = judgeQ0 p hist i s := by
  apply judgeQ0_same_work
  rw [List.filter_append, List.append_right_eq_self]
  exact List.filter_eq_nil_iff.2 (fun x hx => by simpa using h x hx)

theorem judgeQ0_other_mods (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (w j : Option Nat)
    (c : Option (List String)) (b : Nat) (hs : s.work = spanWork w j c (some b))
    (h : ∀ x ∈ others, ∃ a, x.work = spanWork w j c (some a) ∧ modsLow a ≠ modsLow b) :
    judgeQ0 p (hist ++ others) i s = judgeQ0 p hist i s :=
  judgeQ0_other_work p hist others i s fun x hx => by
    obtain ⟨a, hx, hne⟩ := h x hx
    rw [hx, hs]
    exact spanWork_mods_ne w j c a b hne

theorem judgeQ0_unbuilt (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (w j : Option Nat)
    (c : Option (List String)) (hs : s.work = spanWork w j c none)
    (h : ∀ x ∈ others, ∃ a, x.work = spanWork w j c (some a)) :
    judgeQ0 p (hist ++ others) i s = judgeQ0 p hist i s :=
  judgeQ0_other_work p hist others i s fun x hx => by
    obtain ⟨a, hx⟩ := h x hx
    rw [hx, hs]
    exact spanWork_built_ne_unbuilt w j c a

theorem windowOf_unworked (p : Params) (hist : List Sample) (k : Key) (hk : k.work = [])
    (hh : ∀ x ∈ hist, x.work = []) :
    windowOf p hist k = lastN p.window ((hist.filter (fun s =>
      decide (s.tool = k.tool ∧ s.step = k.step ∧ s.host = k.host ∧ s.kind = k.kind) && counts p s)).map (·.durMs)) := by
  unfold windowOf
  congr 2
  apply List.filter_congr
  intro x hx
  obtain ⟨t, st, h, kd, w⟩ := k
  simp only at hk
  subst hk
  simp [Sample.key, hh x hx]

theorem judgeQ0_unworked (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hs : s.work = []) :
    judgeQ0 p hist i s = judgeQ0 p (hist.filter (fun x => decide (x.work = []))) i s := by
  apply judgeQ0_same_work
  rw [hs, List.filter_filter]
  congr 1
  funext x
  by_cases h : x.work = [] <;> simp [h]

theorem judgeQ_keyed (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : s.unkeyed = false) :
    judgeQ p hist i s = judgeQ0 p hist i s := by
  simp [judgeQ, judgeQ0, unkeyedLate, h]

theorem judgeQ_other_work (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (hs : s.unkeyed = false)
    (h : ∀ x ∈ others, x.work ≠ s.work) :
    judgeQ p (hist ++ others) i s = judgeQ p hist i s := by
  rw [judgeQ_keyed p _ i s hs, judgeQ_keyed p _ i s hs]
  exact judgeQ0_other_work p hist others i s h

/-- The outer `fw slot run check ...` span carries the admitted threads as its width (`slotWork`), so a sample of it is
never judged against a baseline of another width: samples of other widths in the history leave its verdict unchanged. -/
theorem judgeQ_other_width (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (w : Nat) (j : Option Nat)
    (hs : s.work = slotWork (some w) j) (hm : s.mixed = false)
    (hl : unkeyedLate (hist ++ others) s = false) (hl' : unkeyedLate hist s = false)
    (h : ∀ x ∈ others, ∃ w' j', w' ≠ w ∧ x.work = slotWork (some w') j') :
    judgeQ p (hist ++ others) i s = judgeQ p hist i s := by
  have e : judgeQ0 p (hist ++ others) i s = judgeQ0 p hist i s :=
    judgeQ0_other_work p hist others i s fun x hx => by
      obtain ⟨w', j', hne, hx⟩ := h x hx
      rw [hx, hs]
      exact slotWork_width_ne w' w j' j hne
  simpa [judgeQ, judgeQ0, hm, hl, hl'] using e

/-- A sample of the outer span with no recorded width (written before the span carried one) keeps the old key: its
window is the one of the four fields, over the history that has no work either. -/
theorem windowOf_no_width (p : Params) (hist : List Sample) (k : Key) (j : Option Nat) (hk : k.work = slotWork none j)
    (hh : ∀ x ∈ hist, x.work = slotWork none j) :
    windowOf p hist k = lastN p.window ((hist.filter (fun s =>
      decide (s.tool = k.tool ∧ s.step = k.step ∧ s.host = k.host ∧ s.kind = k.kind) && counts p s)).map (·.durMs)) := by
  rw [slotWork_none] at hk hh
  exact windowOf_unworked p hist k hk hh

theorem spanWork_built_keyed (w j : Option Nat) (c : Option (List String)) (b : Nat) :
    ({ tool := "", step := "", durMs := 0, host := .ci, work := spanWork w j c (some b) } : Sample).unkeyed = false := by
  simp [Sample.unkeyed, spanWork, modsWork, modsDim]

theorem judgeQ_other_mods (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (w j : Option Nat)
    (c : Option (List String)) (b : Nat) (hs : s.work = spanWork w j c (some b))
    (h : ∀ x ∈ others, ∃ a, x.work = spanWork w j c (some a) ∧ modsLow a ≠ modsLow b) :
    judgeQ p (hist ++ others) i s = judgeQ p hist i s := by
  have hk : s.unkeyed = false := by
    have := spanWork_built_keyed w j c b
    simpa [Sample.unkeyed, hs] using this
  rw [judgeQ_keyed p _ i s hk, judgeQ_keyed p _ i s hk]
  exact judgeQ0_other_mods p hist others i s w j c b hs h

theorem judgeQ_unbuilt (p : Params) (hist others : List Sample) (i : Nat) (s : Sample) (w j : Option Nat)
    (c : Option (List String)) (hs : s.work = spanWork w j c none) (hk : s.unkeyed = false)
    (h : ∀ x ∈ others, ∃ a, x.work = spanWork w j c (some a)) :
    judgeQ p (hist ++ others) i s = judgeQ p hist i s := by
  rw [judgeQ_keyed p _ i s hk, judgeQ_keyed p _ i s hk]
  exact judgeQ0_unbuilt p hist others i s w j c hs h

theorem judgeQ_rebuild_noBaseline (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (b : Nat)
    (hs : s.work = modsWork b) (hb : 0 < modsLow b) (h : ∀ x ∈ hist, x.work = modsWork 0)
    (hm : s.mixed = false) (hq : queuedWithin s = false) (hc : ceilingBreach p s = false) (hn : 0 < p.nMin) :
    (judgeQ p hist i s).code = .noBaseline := by
  have hs' : s.work = spanWork none none none (some b) := by simpa [spanWork, slotWork] using hs
  have e : judgeQ p ([] ++ hist) i s = judgeQ p [] i s :=
    judgeQ_other_mods p [] hist i s none none none b hs' fun x hx => ⟨0, by simpa [spanWork, slotWork] using h x hx, by
      intro e0
      have : modsLow 0 = 0 := rfl
      omega⟩
  rw [List.nil_append] at e
  rw [e]
  have hk : s.unkeyed = false := by simp [Sample.unkeyed, hs, modsWork, modsDim]
  simp [judgeQ, hm, unkeyedLate, hk, judgeW, hq, judge, hc, windowOf, codeOf, lastN, hn]

def noopHist (tool step : String) (n d : Nat) : List Sample :=
  List.replicate n { tool, step, durMs := d, host := .«local», work := modsWork 0 }

def incidentCheck : Sample :=
  { tool := "lean/check", step := "lake build", durMs := 51053, host := .«local», load := 6, work := modsWork 24 }

def incidentLand : Sample :=
  { tool := "fw land", step := "dry sh -c cd lean && . ../scripts/lake-slot-lib.sh && (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh",
    durMs := 37430, host := .«local», load := 5, work := modsWork 24 }

def unkeyedOf (s : Sample) : Sample := { s with work := [] }

def noopRun (s : Sample) (d : Nat) (w : List (String × String)) : List SampleVerdict :=
  sampleVerdicts {} ((noopHist s.tool s.step 8 d).map (fun x => { x with work := w }) ++ [s])

#guard ((noopRun (unkeyedOf incidentCheck) 780 []).getLast?.map (·.code)) == some .slow
#guard ((noopRun (unkeyedOf incidentLand) 3182 []).getLast?.map (·.code)) == some .slow
#guard ((noopRun incidentCheck 780 (modsWork 0)).getLast?.map (·.code)) == some .noBaseline
#guard ((noopRun incidentLand 3182 (modsWork 0)).getLast?.map (·.code)) == some .noBaseline

theorem incident_not_slow (hist : List Sample) (i b : Nat) (hb : 0 < b) (hc : ∀ x ∈ hist, x.work = modsWork 0) :
    (judgeQ {} hist i { incidentCheck with work := modsWork b }).code = .noBaseline ∧
    (judgeQ {} hist i { incidentLand with work := modsWork b }).code = .noBaseline := by
  have hl : 0 < modsLow b := by
    have : modsLow b = 4 ^ (b.log2 / 2) := by simp [modsLow, Nat.pos_iff_ne_zero.mp hb]
    rw [this]; exact Nat.pow_pos (by decide)
  have q1 : queuedWithin incidentCheck = false := by decide
  have q2 : queuedWithin incidentLand = false := by decide
  have c1 : ceilingBreach {} incidentCheck = false := by decide
  have c2 : ceilingBreach {} incidentLand = false := by decide
  have m1 : incidentCheck.mixed = false := by decide
  have m2 : incidentLand.mixed = false := by decide
  exact ⟨judgeQ_rebuild_noBaseline {} hist i _ b rfl hl hc m1 q1 c1 (by decide),
    judgeQ_rebuild_noBaseline {} hist i _ b rfl hl hc m2 q2 c2 (by decide)⟩

def outerBuilt (xs : List Nat) : Nat := xs.sum

def outerWork (xs : List Nat) : List (String × String) := modsWork (outerBuilt xs)

theorem outerBuilt_eq_zero (xs : List Nat) : outerBuilt xs = 0 ↔ ∀ x ∈ xs, x = 0 := by
  unfold outerBuilt
  induction xs with
  | nil => simp
  | cons a t ih => simp [List.sum_cons, ih]

theorem maxBuilt_le_outerBuilt (xs : List Nat) (x : Nat) (hx : x ∈ xs) : x ≤ outerBuilt xs := by
  unfold outerBuilt
  induction xs with
  | nil => simp at hx
  | cons a t ih =>
    simp only [List.mem_cons] at hx
    rw [List.sum_cons]
    rcases hx with rfl | h
    · omega
    · have := ih h; omega

theorem outer_rebuild_noBaseline (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (xs : List Nat)
    (hs : s.work = outerWork xs) (hx : ∃ x ∈ xs, 0 < x) (h : ∀ y ∈ hist, y.work = modsWork 0)
    (hm : s.mixed = false) (hq : queuedWithin s = false) (hc : ceilingBreach p s = false) (hn : 0 < p.nMin) :
    (judgeQ p hist i s).code = .noBaseline := by
  have hb : 0 < outerBuilt xs := by
    rcases Nat.eq_zero_or_pos (outerBuilt xs) with e | e
    · obtain ⟨x, hxm, hxp⟩ := hx
      have := (outerBuilt_eq_zero xs).1 e x hxm
      omega
    · exact e
  have hl : 0 < modsLow (outerBuilt xs) := by
    have : modsLow (outerBuilt xs) = 4 ^ ((outerBuilt xs).log2 / 2) := by simp [modsLow, Nat.pos_iff_ne_zero.mp hb]
    rw [this]; exact Nat.pow_pos (by decide)
  exact judgeQ_rebuild_noBaseline p hist i s _ hs hl h hm hq hc hn

def outerSteps : List (String × String) :=
  [("fw land", "dry total lake"), ("fw", "slot run land pnpm fw land dry")]

def incidentOuterDurs : List Nat := [46323, 35755, 67391]

def incidentOuter (ts : String × String) (d : Nat) (xs : List Nat) : Sample :=
  { tool := ts.1, step := ts.2, durMs := d, host := .«local», load := 5, exit := some 0, work := outerWork xs }

theorem incident_outer_not_slow (hist : List Sample) (i : Nat) (xs : List Nat) (hx : ∃ x ∈ xs, 0 < x)
    (h : ∀ y ∈ hist, y.work = modsWork 0) :
    ∀ ts ∈ outerSteps, ∀ d ∈ incidentOuterDurs, (judgeQ {} hist i (incidentOuter ts d xs)).code = .noBaseline := by
  intro ts hts d hd
  have key : ∀ ts ∈ outerSteps, ∀ d ∈ incidentOuterDurs, (incidentOuter ts d []).mixed = false ∧
      queuedWithin (incidentOuter ts d []) = false ∧ ceilingBreach {} (incidentOuter ts d []) = false := by decide
  obtain ⟨m, q, c⟩ := key ts hts d hd
  exact outer_rebuild_noBaseline {} hist i _ xs rfl hx h m q c (by decide)

def runSteps : List String :=
  ["run plan", "run dispatch lock", "run dispatch reserve", "run dispatch backoff", "run dispatch call", "run wait", "run file"]

def passSteps : List String :=
  ["watch pass", "watch pass gh lock", "watch pass gh reserve", "watch pass gh call", "watch pass gh backoff", "watch pass other"]

/-- The spans of `fw ci state`: the whole command, then lock wait, fwcore reserve, gh call, backoff and the rest (`reduce`). -/
def ciStateSteps : List String :=
  ["ci state", "ci state gh lock", "ci state gh reserve", "ci state gh call", "ci state gh backoff", "ci state reduce"]

def ciStateLoadStep : String := "ci state gh load"

theorem ciStateSteps_nodup : ciStateSteps.Nodup := by decide

theorem ciStateLoadStep_new : ciStateLoadStep ∉ ciStateSteps := by decide

theorem runSteps_nodup : runSteps.Nodup := by decide

theorem passSteps_nodup : passSteps.Nodup := by decide

def dispatchLockWaitMs : Nat := 60000

def dispatchCallTimeoutMs : Nat := 20000

def watchLockWaitMs : Nat := 3000

def watchCallTimeoutMs : Nat := 10000

def oldLockWaitMs : Nat := 120000

def oldCallTimeoutMs : Nat := 60000

theorem dispatch_limits_lighter : dispatchLockWaitMs < oldLockWaitMs ∧ dispatchCallTimeoutMs < oldCallTimeoutMs := by decide

theorem watch_limits_lighter : watchLockWaitMs < oldLockWaitMs ∧ watchCallTimeoutMs < oldCallTimeoutMs := by decide

/-- gh timeout of the callers that pass none (wait, poller, `fw ci budget --probe`, timing ingest, `fw ci state`). It was 60 s; a
`gh run list --limit 1000` took 22319 ms (MEASURED 2026-10-23, `fw ci state`), so 40 s keeps that call whole. -/
def defaultCallTimeoutMs : Nat := 40000

/-- gh timeout of `fw land`'s own charged call (`land.ts`). -/
def landCallTimeoutMs : Nat := 20000

/-- Every gh timeout a caller of the charged wrapper uses; a lock holder is killed by its timeout at the latest. -/
def callerTimeoutsMs : List Nat :=
  [defaultCallTimeoutMs, dispatchCallTimeoutMs, watchCallTimeoutMs, landCallTimeoutMs]

def maxCallTimeoutMs : Nat := callerTimeoutsMs.foldl max 0

def fwcoreCallMs : Nat := 10000

def fwcoreLoadedCallMs : Nat := 60000

def holderCoreCalls : Nat := 2

def lockMarginMs : Nat := holderCoreCalls * fwcoreCallMs

theorem lock_margin_derived : lockMarginMs = 20000 := by decide

theorem loaded_core_margin_too_big : maxCallTimeoutMs + holderCoreCalls * fwcoreLoadedCallMs > dispatchLockWaitMs := by decide

def pollLockWaitMs : Nat := 10000

def busyRetryS : Nat := 2

/-- Longest list `fw ci state` asks for took this long (MEASURED). -/
def ciStateListMs : Nat := 22319

theorem max_call_timeout_covers : ∀ t ∈ callerTimeoutsMs, t ≤ maxCallTimeoutMs := by decide

/-- One hung holder of any caller is killed before a dispatch's lock wait ends, with the margin to spare, so a hung
non-dispatch call no longer fills the whole wait. -/
theorem hung_holder_fits : maxCallTimeoutMs + lockMarginMs ≤ dispatchLockWaitMs := by decide

theorem every_caller_fits : ∀ t ∈ callerTimeoutsMs, t + lockMarginMs ≤ dispatchLockWaitMs := by decide

theorem default_timeout_lighter : defaultCallTimeoutMs < oldCallTimeoutMs := by decide

theorem state_list_fits : ciStateListMs < defaultCallTimeoutMs := by decide

theorem poll_wait_short : pollLockWaitMs < dispatchLockWaitMs ∧ 0 < busyRetryS := by decide

/-- Two dispatch calls at their 20 s timeout fit inside one 60 s dispatch lock wait (arithmetic on these bounds only). -/
theorem three_dispatches_fit : 2 * dispatchCallTimeoutMs ≤ dispatchLockWaitMs := by decide

theorem watch_gh_block_bound : watchLockWaitMs + watchCallTimeoutMs = 13000 := by decide

theorem judge_insert_step (p : Params) (a b : List Sample) (x s : Sample) (i : Nat)
    (hne : x.step ≠ s.step) : judge p (a ++ x :: b) i s = judge p (a ++ b) i s := by
  apply judge_insert_key
  intro e
  exact hne (congrArg Key.step e)

def SampleVerdict.unindexed (v : SampleVerdict) : SampleVerdict := { v with idx := 0 }

def Verdict.unindexed : Verdict → Verdict
  | .sample v => .sample v.unindexed
  | .structural v => .structural v

theorem sampleVerdicts_snoc (p : Params) (ss : List Sample) (x : Sample) :
    sampleVerdicts p (ss ++ [x]) = sampleVerdicts p ss ++ [judgeQ p ss ss.length x] := by
  apply List.ext_getElem
  · simp [sampleVerdicts]
  · intro n h1 h2
    simp only [sampleVerdicts, List.getElem_mapIdx, List.length_append, List.length_cons, List.length_nil,
      List.length_mapIdx] at h1 ⊢
    rw [List.getElem_append]
    by_cases hn : n < ss.length
    · simp [hn, List.take_append_of_le_length (Nat.le_of_lt hn)]
    · have he : n = ss.length := by omega
      subst he
      simp

theorem fullVerdicts_snoc (p : Params) (ss : List Sample) (x : Sample) :
    fullVerdicts p (ss ++ [x]) = fullVerdicts p ss ++ (if x.full then [judgeQ p ss ss.length x] else []) := by
  unfold fullVerdicts
  rw [sampleVerdicts_snoc, List.zip_append (by simp [sampleVerdicts])]
  cases hx : x.full <;> simp [List.filter_append, hx]

theorem rest_contended (p : Params) (s : Sample) : contended p s.rest = contended p s := rfl

theorem rest_budgetFor (p : Params) (s : Sample) : budgetFor p s.rest = budgetFor p s := rfl

theorem judgeW_queued (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hq : queuedWithin s = true) :
    judgeW p hist i s = { (judge p hist i s.rest) with
      durMs := s.durMs
      code :=(if (judge p hist i s.rest).code = Code.slow then Code.slow else Code.queued) } := by
  simp [judgeW, hq]

theorem judgeW_plain (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hq : queuedWithin s = false) : judgeW p hist i s = judge p hist i s := by
  simp [judgeW, hq]

theorem judgeW_unwaited (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : s.holdMs = 0) :
    judgeW p hist i s = judge p hist i s :=
  judgeW_plain p hist i s (by simp [queuedWithin, h])

theorem judgeQ_unmixed (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : s.mixed = false)
    (hu : unkeyedLate hist s = false) : judgeQ p hist i s = judgeW p hist i s := by
  simp [judgeQ, h, hu]

theorem judgeQ_mixed (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : s.mixed = true) :
    judgeQ p hist i s = (judgeW p hist i s).markMixed := by
  simp [judgeQ, h]

theorem judgeQ_unkeyed (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hm : s.mixed = false)
    (h : unkeyedLate hist s = true) : judgeQ p hist i s = (judgeW p hist i s).markUnkeyed := by
  simp [judgeQ, hm, h]

theorem judgeQ_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : (judgeQ p hist i s).code = .slow) :
    s.mixed = false ∧ (judgeW p hist i s).code = .slow := by
  cases hm : s.mixed
  · cases hu : unkeyedLate hist s
    · rw [judgeQ_unmixed p hist i s hm hu] at h; exact ⟨rfl, h⟩
    · rw [judgeQ_unkeyed p hist i s hm hu] at h; cases h
  · rw [judgeQ_mixed p hist i s hm] at h; cases h

theorem judgeQ_not_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : (judgeW p hist i s).code ≠ .slow) : (judgeQ p hist i s).code ≠ .slow :=
  fun hs => h (judgeQ_slow p hist i s hs).2

/-- **No slow verdict on an overflow bucket**: whatever its history, a mixed sample is never `slow`. -/
theorem judgeQ_mixed_not_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : s.mixed = true) :
    (judgeQ p hist i s).code ≠ .slow := by
  rw [judgeQ_mixed p hist i s h]; simp [SampleVerdict.markMixed]

theorem judge_not_queued (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judge p hist i s).code ≠ .queued := by
  unfold judge codeOf
  simp only
  repeat' split
  all_goals simp

theorem judgeW_durMs (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judgeW p hist i s).durMs = s.durMs := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_budgetMs (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judgeW p hist i s).budgetMs = budgetFor p s := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, rest_budgetFor]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_tool (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).tool = s.tool := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, Sample.rest]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_step (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).step = s.step := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, Sample.rest]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_kind (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).kind = s.kind := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, Sample.rest]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_work (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).work = s.work := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, Sample.rest]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeQ_durMs (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).durMs = s.durMs := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_durMs p hist i s

theorem judgeQ_budgetMs (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judgeQ p hist i s).budgetMs = budgetFor p s := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_budgetMs p hist i s

theorem judgeQ_tool (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).tool = s.tool := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_tool p hist i s

theorem judgeQ_step (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).step = s.step := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_step p hist i s

theorem judgeQ_kind (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).kind = s.kind := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_kind p hist i s

theorem judgeQ_work (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).work = s.work := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_work p hist i s

theorem judgeW_idx (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).idx = i := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeW_host (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeW p hist i s).host = s.host := by
  by_cases hq : queuedWithin s = true
  · simp [judgeW_queued p hist i s hq, judge, Sample.rest]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; simp [judge]

theorem judgeQ_idx (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).idx = i := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_idx p hist i s

theorem judgeQ_host (p : Params) (hist : List Sample) (i : Nat) (s : Sample) : (judgeQ p hist i s).host = s.host := by
  unfold judgeQ; split <;> (try split) <;> exact judgeW_host p hist i s

theorem judge_idx (p : Params) (h : List Sample) (i j : Nat) (s : Sample) :
    judge p h i s = { judge p h j s with idx := i } := rfl

theorem judgeW_unindexed (p : Params) (h h' : List Sample) (i j : Nat) (s : Sample)
    (hh : h.filter Sample.full = h'.filter Sample.full) :
    (judgeW p h i s).unindexed = (judgeW p h' j s).unindexed := by
  have key : ∀ s', judge p h i s' = { judge p h' j s' with idx := i } := by
    intro s'
    rw [judge_filter_full p h, judge_filter_full p h', hh]
    rfl
  by_cases hq : queuedWithin s = true
  · rw [judgeW_queued p h i s hq, judgeW_queued p h' j s hq, key]
    simp [SampleVerdict.unindexed]
  · rw [judgeW_plain p h i s (by simpa using hq), judgeW_plain p h' j s (by simpa using hq), key]
    simp [SampleVerdict.unindexed]

theorem unkeyedLate_filter_full (h : List Sample) (s : Sample) :
    unkeyedLate h s = unkeyedLate (h.filter Sample.full) s := by
  unfold unkeyedLate
  congr 1
  apply Bool.eq_iff_iff.2
  simp only [List.any_eq_true, List.mem_filter]
  constructor
  · rintro ⟨t, ht, hp⟩
    have hf : t.full = true := by simp only [Bool.and_eq_true] at hp; exact hp.1.1
    exact ⟨t, ⟨ht, hf⟩, hp⟩
  · rintro ⟨t, ⟨ht, _⟩, hp⟩; exact ⟨t, ht, hp⟩

theorem judgeQ_unindexed (p : Params) (h h' : List Sample) (i j : Nat) (s : Sample)
    (hh : h.filter Sample.full = h'.filter Sample.full) :
    (judgeQ p h i s).unindexed = (judgeQ p h' j s).unindexed := by
  have hw := judgeW_unindexed p h h' i j s hh
  unfold judgeQ
  rw [unkeyedLate_filter_full h s, unkeyedLate_filter_full h' s, hh]
  split
  · exact congrArg SampleVerdict.markMixed hw
  · split
    · exact congrArg SampleVerdict.markUnkeyed hw
    · exact hw

theorem fullVerdicts_unindexed (p : Params) (ss : List Sample) :
    (fullVerdicts p ss).map SampleVerdict.unindexed =
      (sampleVerdicts p (ss.filter Sample.full)).map SampleVerdict.unindexed := by
  rw [← List.reverse_reverse ss]
  generalize ss.reverse = r
  induction r with
  | nil => simp [fullVerdicts, sampleVerdicts]
  | cons x r ih =>
    rw [List.reverse_cons, fullVerdicts_snoc, List.filter_append]
    cases hx : x.full
    · simp [hx, ih]
    · simp only [hx, ite_true, List.filter_cons, List.filter_nil, List.map_append, ih, sampleVerdicts_snoc]
      simp only [List.map_cons, List.map_nil]
      rw [judgeQ_unindexed p _ (r.reverse.filter Sample.full) _ _ x (by simp [List.filter_filter])]

theorem jobKeys_filter_full (ss : List Sample) : jobKeys (ss.filter Sample.full) = jobKeys ss := by
  unfold jobKeys
  rw [List.filter_filter]
  congr 2
  apply List.filter_congr
  intro x _
  cases x.full <;> simp

theorem groupBaseline_filter_full (p : Params) (ss : List Sample) :
    groupBaseline p (ss.filter Sample.full) = groupBaseline p ss := by
  have hf : finalBaseline p (ss.filter Sample.full) = finalBaseline p ss := by
    funext k
    simp [finalBaseline, ← windowOf_filter_full]
  funext g
  simp only [groupBaseline, hf]

theorem structuralVerdicts_filter_full (p : Params) (ss : List Sample) :
    structuralVerdicts p (ss.filter Sample.full) = structuralVerdicts p ss := by
  have hs : stagesOf p (ss.filter Sample.full) = stagesOf p ss := by
    simp only [stagesOf, autoStages, jobKeys_filter_full]
  have hv : stageVerdict p (ss.filter Sample.full) = stageVerdict p ss := by
    funext st g
    unfold stageVerdict callOf siblings
    rw [groupBaseline_filter_full]
  simp only [structuralVerdicts, hs, hv]

theorem timingVerdicts_indep (p : Params) (ss : List Sample) :
    (timingVerdicts p ss).map Verdict.unindexed = (timingVerdicts p (ss.filter Sample.full)).map Verdict.unindexed := by
  have hf : ∀ s ∈ ss.filter Sample.full, s.full = true := fun s hs => (List.mem_filter.1 hs).2
  rw [timingVerdicts_all_full p _ hf, timingVerdicts, structuralVerdicts_filter_full]
  simp only [List.map_append, List.map_map]
  have hc : (Verdict.unindexed ∘ Verdict.sample) = Verdict.sample ∘ SampleVerdict.unindexed := rfl
  rw [hc, ← List.map_map, ← List.map_map (g := Verdict.sample), fullVerdicts_unindexed]

theorem timingVerdicts_same_full (p : Params) (ss ss' : List Sample)
    (h : ss.filter Sample.full = ss'.filter Sample.full) :
    (timingVerdicts p ss).map Verdict.unindexed = (timingVerdicts p ss').map Verdict.unindexed := by
  rw [timingVerdicts_indep p ss, timingVerdicts_indep p ss', h]

/-! ## Proofs: the order statistic and the outlier bound -/

/-- Every non-empty list of naturals has a largest element. -/
theorem exists_max (xs : List Nat) (h : xs ≠ []) : ∃ u ∈ xs, ∀ x ∈ xs, x ≤ u := by
  induction xs with
  | nil => exact absurd rfl h
  | cons a t ih =>
    by_cases ht : t = []
    · subst ht
      exact ⟨a, by simp, by simp⟩
    · obtain ⟨u, hu, hm⟩ := ih ht
      by_cases hau : a ≤ u
      · refine ⟨u, List.mem_cons_of_mem _ hu, ?_⟩
        intro x hx
        rcases List.mem_cons.1 hx with rfl | hx
        · exact hau
        · exact hm x hx
      · refine ⟨a, List.mem_cons_self, ?_⟩
        intro x hx
        rcases List.mem_cons.1 hx with rfl | hx
        · exact Nat.le_refl _
        · have := hm x hx; omega

/-- `cntLe` is monotone in the bound. -/
theorem cntLe_mono (xs : List Nat) (v w : Nat) (h : v ≤ w) : cntLe xs v ≤ cntLe xs w :=
  List.countP_mono_left (by intro x _ hx; simp only [decide_eq_true_eq] at hx ⊢; omega)

/-- For an index inside the list, `ord` is a value of the list with at least `j + 1` values at or below it, and it is
the least such value.
-/
theorem ord_spec (xs : List Nat) (j : Nat) (hj : j < xs.length) :
    ord xs j ∈ xs ∧ j + 1 ≤ cntLe xs (ord xs j) ∧ ∀ v ∈ xs, j + 1 ≤ cntLe xs v → ord xs j ≤ v := by
  have hne : xs ≠ [] := by intro h'; subst h'; simp at hj
  obtain ⟨u, hu, hm⟩ := exists_max xs hne
  have hcu : cntLe xs u = xs.length :=
    List.countP_eq_length.2 (by intro a ha; simpa using hm a ha)
  have huC : u ∈ cands xs j := List.mem_filter.2 ⟨hu, by simp only [decide_eq_true_eq]; omega⟩
  cases hmin : (cands xs j).min? with
  | none =>
    rw [List.min?_eq_none_iff] at hmin
    rw [hmin] at huC; simp at huC
  | some m =>
    have hord : ord xs j = m := by simp [ord, hmin]
    obtain ⟨hmC, hle⟩ := List.min?_eq_some_iff.1 hmin
    obtain ⟨hmX, hmc⟩ := List.mem_filter.1 hmC
    simp only [decide_eq_true_eq] at hmc
    rw [hord]
    refine ⟨hmX, hmc, ?_⟩
    intro v hv hc
    exact hle v (List.mem_filter.2 ⟨hv, by simpa using hc⟩)

/-- The counting characterization of the order statistic: `ord xs j` is at most `v` exactly when at least `j + 1`
values of the list are at most `v`.
-/
theorem ord_le_iff (xs : List Nat) (j v : Nat) (hj : j < xs.length) :
    ord xs j ≤ v ↔ j + 1 ≤ cntLe xs v := by
  obtain ⟨_, hc, hmin⟩ := ord_spec xs j hj
  constructor
  · intro h; exact Nat.le_trans hc (cntLe_mono xs _ _ h)
  · intro h
    have hF : xs.filter (fun x => decide (x ≤ v)) ≠ [] := by
      intro hF
      have : cntLe xs v = 0 := by simp [cntLe, List.countP_eq_length_filter, hF]
      omega
    obtain ⟨u, hu, hm⟩ := exists_max _ hF
    obtain ⟨huX, huv⟩ := List.mem_filter.1 hu
    simp only [decide_eq_true_eq] at huv
    have hcu : cntLe xs u = cntLe xs v := by
      apply List.countP_congr
      intro x hx
      simp only [decide_eq_true_eq]
      constructor
      · intro hxu; omega
      · intro hxv; exact hm x (List.mem_filter.2 ⟨hx, by simpa using hxv⟩)
    exact Nat.le_trans (hmin u huX (by omega)) huv

/-- The order statistics are sorted: a larger index gives a value at least as large. -/
theorem ord_mono (xs : List Nat) (j j' : Nat) (h : j ≤ j') (hj' : j' < xs.length) :
    ord xs j ≤ ord xs j' := by
  rw [ord_le_iff xs j _ (by omega)]
  have := (ord_spec xs j' hj').2.1
  omega

/-- Counting after one replacement: the count at any bound moves by at most one. -/
theorem cntLe_replace (a b : List Nat) (x y v : Nat) :
    cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v + 1 := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  split <;> split <;> omega

/-- Counting after one replacement, at a bound not below the new value or below it. -/
theorem cntLe_replace_y (a b : List Nat) (x y v : Nat) :
    (y ≤ v → cntLe (a ++ x :: b) v ≤ cntLe (a ++ y :: b) v) ∧
      (v < y → cntLe (a ++ y :: b) v ≤ cntLe (a ++ x :: b) v) := by
  simp only [cntLe, List.countP_append, List.countP_cons]
  constructor <;> intro h <;> split <;> split <;> simp_all <;> omega

/-- Interlacing: replacing one value of a list moves its order statistic of index `j` at most to the neighbouring
order statistics of the old list (indices `j - 1` and `j + 1`, where they exist).
-/
theorem ord_interlace (a b : List Nat) (x y j : Nat) :
    (1 ≤ j → j < (a ++ x :: b).length → ord (a ++ x :: b) (j - 1) ≤ ord (a ++ y :: b) j) ∧
      (j + 1 < (a ++ x :: b).length → ord (a ++ y :: b) j ≤ ord (a ++ x :: b) (j + 1)) := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  constructor
  · intro h1 hj
    rw [ord_le_iff _ _ _ (by omega)]
    have := (ord_spec (a ++ y :: b) j (by omega)).2.1
    have := cntLe_replace a b x y (ord (a ++ y :: b) j)
    omega
  · intro hj
    rw [ord_le_iff _ _ _ (by omega)]
    have := (ord_spec (a ++ x :: b) (j + 1) hj).2.1
    have := cntLe_replace a b y x (ord (a ++ x :: b) (j + 1))
    omega

/-- The new order statistic lies between the old one and the new value. -/
theorem ord_between (a b : List Nat) (x y j : Nat) (hj : j < (a ++ x :: b).length) :
    min (ord (a ++ x :: b) j) y ≤ ord (a ++ y :: b) j ∧ ord (a ++ y :: b) j ≤ max (ord (a ++ x :: b) j) y := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  constructor
  · apply Nat.le_of_not_lt
    intro hlt
    have hq : ord (a ++ y :: b) j < ord (a ++ x :: b) j := by omega
    have hy : ord (a ++ y :: b) j < y := by omega
    have h1 := (ord_spec (a ++ y :: b) j (by omega)).2.1
    have h2 : ¬ (ord (a ++ x :: b) j ≤ ord (a ++ y :: b) j) := by omega
    rw [ord_le_iff _ _ _ hj] at h2
    have h3 := (cntLe_replace_y a b x y (ord (a ++ y :: b) j)).2 hy
    omega
  · rw [ord_le_iff _ _ _ (by omega)]
    have h1 := (ord_spec (a ++ x :: b) j hj).2.1
    have h2 := cntLe_mono (a ++ x :: b) _ (max (ord (a ++ x :: b) j) y) (Nat.le_max_left _ _)
    have h3 := (cntLe_replace_y a b x y (max (ord (a ++ x :: b) j) y)).1 (Nat.le_max_right _ _)
    omega

/-- The rank of p90 is an index of the list: `1 ≤ rank_90(n) ≤ n` for `n ≥ 1`, and
`2 ≤ rank_90(n) < n` for `n ≥ 10`.
-/
theorem rank90_bounds (n : Nat) :
    (1 ≤ n → 1 ≤ rank90 n ∧ rank90 n ≤ n) ∧ (10 ≤ n → 2 ≤ rank90 n ∧ rank90 n < n) := by
  simp only [rank90]; omega

/-- An outlier moves the p90 (the baseline before task `timing-small-n`, still used by the outlier bounds below)
only toward itself: replacing one window value `x` by `y` leaves the new p90 between the old p90 and `y` (any window
length; for a window of fewer than 10 values the p90 is the maximum, so a large `y` can raise it all the way to `y`).
-/
theorem outlier_between (a b : List Nat) (x y : Nat) :
    min (p90 (a ++ x :: b)) y ≤ p90 (a ++ y :: b) ∧ p90 (a ++ y :: b) ≤ max (p90 (a ++ x :: b)) y := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  have hpos : 1 ≤ (a ++ x :: b).length := by
    simp only [List.length_append, List.length_cons]; omega
  have := (rank90_bounds (a ++ x :: b).length).1 hpos
  simp only [p90, hlen]
  exact ord_between a b x y _ (by omega)

/-- The outlier bound: for a window of at least 10 values with p90 rank `r = ⌈ 9n/10 ⌉`, replacing any one
value (by anything, however large or small) leaves the new p90 between the old `(r-1)`-th and `(r+1)`-th smallest
values, that is between the old order statistics adjacent to the old p90 (`ord` is 0-based, so these are the indices
`r-2` and `r`; `r ≥ 2` here, so `r - 2` does not truncate).
-/
theorem outlier_bound (a b : List Nat) (x y : Nat) (hn : 10 ≤ (a ++ x :: b).length) :
    ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 2) ≤ p90 (a ++ y :: b) ∧
      p90 (a ++ y :: b) ≤ ord (a ++ x :: b) (rank90 (a ++ x :: b).length) := by
  have hlen : (a ++ y :: b).length = (a ++ x :: b).length := by simp
  have hr := (rank90_bounds (a ++ x :: b).length).2 hn
  have hi := ord_interlace a b x y (rank90 (a ++ x :: b).length - 1)
  simp only [p90, hlen]
  have e1 : rank90 (a ++ x :: b).length - 1 - 1 = rank90 (a ++ x :: b).length - 2 := by omega
  have e2 : rank90 (a ++ x :: b).length - 1 + 1 = rank90 (a ++ x :: b).length := by omega
  rw [e1, e2] at hi
  exact ⟨hi.1 (by omega) (by omega), hi.2 (by omega)⟩

/-- The outlier bound as a shift: for a window of at least 10 values, one replaced value raises the p90 by at most
the gap from the old p90 to the next order statistic, and lowers it by at most the gap to the previous one
(truncated differences; the gaps are non-negative because `ord` is sorted).
-/
theorem outlier_shift (a b : List Nat) (x y : Nat) (hn : 10 ≤ (a ++ x :: b).length) :
    p90 (a ++ y :: b) - p90 (a ++ x :: b) ≤
        ord (a ++ x :: b) (rank90 (a ++ x :: b).length) - ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) ∧
      p90 (a ++ x :: b) - p90 (a ++ y :: b) ≤
        ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) - ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 2) := by
  have hb := outlier_bound a b x y hn
  have hp : p90 (a ++ x :: b) = ord (a ++ x :: b) (rank90 (a ++ x :: b).length - 1) := rfl
  rw [hp]
  omega

/-! ## Proofs: the median baseline (task `timing-small-n`) -/

/-- Every value is at or below `t` or above it: the two counts add up to the length. -/
theorem cnt_split (xs : List Nat) (t : Nat) :
    cntLe xs t + xs.countP (fun x => decide (t < x)) = xs.length := by
  rw [List.length_eq_countP_add_countP (fun x => decide (x ≤ t))]
  unfold cntLe
  congr 1
  apply List.countP_congr
  intro x _
  simp only [decide_eq_true_eq]
  omega

/-- The median is at most `t` when at most half of the values exceed `t` (also for the empty list, whose median is
0).
-/
theorem p50_le_of_few_above (xs : List Nat) (t : Nat)
    (h : 2 * xs.countP (fun x => decide (t < x)) ≤ xs.length) : p50 xs ≤ t := by
  cases xs with
  | nil => simp [p50, ord, cands]
  | cons a r =>
    have hs := cnt_split (a :: r) t
    have hl : 1 ≤ (a :: r).length := by simp
    unfold p50
    rw [ord_le_iff _ _ _ (by simp only [rank50]; omega)]
    simp only [rank50]
    omega

/-- The median is at least `t` when fewer than half of the values are below `t`. -/
theorem le_p50_of_few_below (xs : List Nat) (t : Nat)
    (h : 2 * xs.countP (fun x => decide (x < t)) < xs.length) : t ≤ p50 xs := by
  rcases Nat.eq_zero_or_pos t with rfl | ht
  · exact Nat.zero_le _
  · apply Classical.byContradiction
    intro hlt
    have hle : p50 xs ≤ t - 1 := by omega
    unfold p50 at hle
    rw [ord_le_iff _ _ _ (by simp only [rank50]; omega)] at hle
    have hc : cntLe xs (t - 1) = xs.countP (fun x => decide (x < t)) :=
      List.countP_congr (by intro x _; simp only [decide_eq_true_eq]; omega)
    simp only [rank50] at hle
    omega

/-- No self-masking: a slowdown is judged against a median that it can only move once it fills more than half the
window. If at most half of the window exceeds a level `t`, a not contended sample over budget with `k_d · d > k_n · t` is `slow` (with the p90 baseline this failed for `n ≤ 9`, where the p90 is the maximum).
-/
theorem no_self_mask (p : Params) (w : List Nat) (s : Sample) (t : Nat)
    (hn : p.nMin ≤ w.length) (hq : contended p s = false) (hB : budgetOf p s.tool < s.durMs)
    (hfew : 2 * w.countP (fun x => decide (t < x)) ≤ w.length) (hk : p.kNum * t < p.kDen * s.durMs) :
    codeOf p w s = .slow :=
  (codeOf_slow_iff p w s).2 ⟨hn, hq, hB,
    Nat.lt_of_le_of_lt (Nat.mul_le_mul_left _ (p50_le_of_few_above w t hfew)) hk⟩

/-- Slow is monotone in the window: a window of the same length with at least as many values at or below every bound
(no slower in distribution, e.g. some values lowered) keeps a `slow` sample `slow`.
-/
theorem slow_mono_window (p : Params) (w w' : List Nat) (s : Sample) (hl : w'.length = w.length)
    (hc : ∀ v, cntLe w v ≤ cntLe w' v) (h : codeOf p w s = .slow) : codeOf p w' s = .slow := by
  obtain ⟨h1, h2, h3, h4⟩ := (codeOf_slow_iff p w s).1 h
  refine (codeOf_slow_iff p w' s).2 ⟨by omega, h2, h3, ?_⟩
  have hle : p50 w' ≤ p50 w := by
    cases w with
    | nil =>
      have : w' = [] := List.eq_nil_of_length_eq_zero (by simpa using hl)
      subst this; exact Nat.le_refl _
    | cons a r =>
      have hpos : 1 ≤ (a :: r).length := by simp
      unfold p50
      rw [hl, ord_le_iff _ _ _ (by rw [hl]; simp only [rank50]; omega)]
      exact Nat.le_trans (ord_spec _ _ (by simp only [rank50]; omega)).2.1 (hc _)
  exact Nat.lt_of_le_of_lt (Nat.mul_le_mul_left _ hle) h4

/-- A value of a window is the duration of a sample of the history. -/
theorem mem_window (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.durMs = x := by
  unfold windowOf lastN at h
  obtain ⟨s, hs, rfl⟩ := List.mem_map.1 (List.mem_of_mem_drop h)
  exact ⟨s, (List.mem_filter.1 hs).1, rfl⟩

/-- A value of a window comes from a sample of exactly that key, so a window never mixes run kinds. -/
theorem mem_window_key (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.key = k ∧ s.durMs = x := by
  unfold windowOf lastN at h
  obtain ⟨s, hs, rfl⟩ := List.mem_map.1 (List.mem_of_mem_drop h)
  have := List.mem_filter.1 hs
  have hk : s.key = k := by
    have h2 := this.2
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h2
    exact h2.1
  exact ⟨s, this.1, hk, rfl⟩

/-- A window never mixes run kinds: every value of the window of key `κ` comes from a sample whose run kind is the
kind of `κ`.
-/
theorem mem_window_kind (p : Params) (hist : List Sample) (k : Key) (x : Nat) (h : x ∈ windowOf p hist k) :
    ∃ s ∈ hist, s.kind = k.kind ∧ s.durMs = x := by
  obtain ⟨s, hs, hk, hd⟩ := mem_window_key p hist k x h
  exact ⟨s, hs, by rw [← hk]; rfl, hd⟩

/-- A stable series is never `slow`: when `n_min ≥ 1`, no sample breaches a ceiling, and every two durations of
the series are within the factor `k` (`k_d · d_s ≤ k_n · d_t`), no sample verdict is `slow`.
-/
theorem stable_never_slow (p : Params) (ss : List Sample) (h1 : 1 ≤ p.nMin)
    (hb : ∀ s ∈ ss, ceilingBreach p s = false)
    (ht : ∀ s ∈ ss, ∀ t ∈ ss, p.kDen * s.durMs ≤ p.kNum * t.durMs) (hw : ∀ s ∈ ss, s.holdMs = 0) :
    ∀ v ∈ sampleVerdicts p ss, v.code ≠ .slow := by
  intro v hv
  obtain ⟨i, hi, he⟩ := List.mem_iff_getElem.1 hv
  have hi' : i < ss.length := by simpa [sampleVerdicts, List.length_mapIdx] using hi
  have hv' : v = judgeQ p (ss.take i) i ss[i] := by
    rw [← he]; simp [sampleVerdicts, List.getElem_mapIdx]
  subst hv'
  apply judgeQ_not_slow
  rw [judgeW_unwaited p _ i _ (hw _ (List.getElem_mem hi'))]
  intro hs
  rcases (slow_iff p _ i _).1 hs with hbr | ⟨hn, _, _, hk⟩
  · rw [hb _ (List.getElem_mem hi')] at hbr; cases hbr
  · have hpos : 0 < (windowOf p (ss.take i) ss[i].key).length := by omega
    have hmem := (ord_spec (windowOf p (ss.take i) ss[i].key)
      (rank50 (windowOf p (ss.take i) ss[i].key).length - 1) (by simp only [rank50]; omega)).1
    obtain ⟨t, htm, hteq⟩ := mem_window p _ _ _ hmem
    have hst := ht ss[i] (List.getElem_mem hi') t (List.mem_of_mem_take htm)
    rw [hteq] at hst
    exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le hk hst)

/-- A site-build sample of the breakpoint gate (CI) with duration `d` ms, for the counterexample of task
`timing-small-n`.
-/
def siteBuild (d : Nat) : Sample := { tool := "breakpoint-gate", step := "site", durMs := d, host := .ci }

/-- The counterexample is now `slow`: after site builds of 2, 1, 2, 27 and 26 s, a 40 s build is `slow` with the
default parameters `p_0` (`{}`: `n_min = 5`, `N = 20`, `k = 3/2`, `B_0 = 30000`, no ceilings, no stages; median 2 s;
with the p90 baseline, 27 s, it was `ok` because `2 · 40 ≤ 3 · 27`).
-/
theorem site_regression_slow :
    (judge {} ([2000, 1000, 2000, 27000, 26000].map siteBuild) 5 (siteBuild 40000)).code = .slow := by
  decide

/-- A repeated regression stays `slow`: after site builds of 2, 1, 2, 27, 26 and 50 s, another 50 s build is `slow`
with the default parameters `p_0` (`{}`; the median is still 2 s; with the p90 baseline, 50 s, it was `ok`).
-/
theorem site_repeat_slow :
    (judge {} ([2000, 1000, 2000, 27000, 26000, 50000].map siteBuild) 6 (siteBuild 50000)).code = .slow := by
  decide

/-- A local `lean/check` stage sample of `d` ms at 1-min load `l`, for the contended-burst cases. -/
def checkStage (d l : Nat) : Sample := { tool := "lean/check", step := "props lint", durMs := d, host := .«local», load := l }

/-! ## Proofs: contended samples (task `local-mem-budget`) -/

/-- **A contended sample is never `slow`.** Whatever the history, a sample that ran locally above the load limit has a
verdict other than `slow`: neither the ceiling branch nor the baseline branch of `slow_iff` holds for it.
-/
theorem contended_not_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : contended p s = true) : (judge p hist i s).code ≠ .slow := by
  intro hs
  rcases (slow_iff p hist i s).1 hs with hb | hr
  · obtain ⟨_, _, _, hn⟩ := (ceilingBreach_iff p s).1 hb
    rw [h] at hn
    cases hn
  · have := hr.2.1
    rw [h] at this
    cases this

/-- A CI sample is never contended, so the contended branch masks no CI regression. -/
theorem ci_not_contended (p : Params) (s : Sample) (h : s.host = .ci) : contended p s = false := by
  simp [contended, h]

/-- A local sample at or below the load limit is not contended. -/
theorem not_contended_of_load_le (p : Params) (s : Sample) (h : s.load ≤ p.loadMax) : contended p s = false := by
  simp only [contended, Bool.and_eq_false_iff, decide_eq_false_iff_not]
  exact Or.inr (Nat.not_lt.2 h)

/-- **A slow sample at normal load still alerts.** A sample at or below the load limit (so also every CI sample) whose
window has at least `n_min` values and whose duration exceeds the budget and `k` times the baseline is `slow`, whatever
the contended samples around it: this is `slow_iff` read at normal load.
-/
theorem slow_at_normal_load (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hl : s.load ≤ p.loadMax) (hn : p.nMin ≤ (windowOf p hist s.key).length) (hB : budgetOf p s.tool < s.durMs)
    (hk : p.kNum * p50 (windowOf p hist s.key) < p.kDen * s.durMs) : (judge p hist i s).code = .slow :=
  (slow_iff p hist i s).2 (Or.inr ⟨hn, not_contended_of_load_le p s hl, hB, hk⟩)

/-- **A ceiling breach at normal load still alerts**, with no history: the sample is at or below the load limit, its
step has the ceiling `c` and it took longer than `c`.
-/
theorem ceiling_at_normal_load (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (c : Nat)
    (hl : s.load ≤ p.loadMax) (hc : ceilingOf p s.tool s.step = some c) (hd : c < s.durMs) :
    (judge p hist i s).code = .slow :=
  (slow_iff p hist i s).2 (Or.inl ((ceilingBreach_iff p s).2 ⟨c, hc, hd, not_contended_of_load_le p s hl⟩))

theorem queued_not_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hq : queuedWithin s = true)
    (hr : (judge p hist i s.rest).code ≠ .slow) : (judgeW p hist i s).code ≠ .slow := by
  rw [judgeW_queued p hist i s hq]; simp [hr]

theorem queued_iff (p : Params) (hist : List Sample) (i : Nat) (s : Sample) :
    (judgeW p hist i s).code = .queued ↔
      queuedWithin s = true ∧ (judge p hist i s.rest).code ≠ .slow := by
  by_cases hq : queuedWithin s = true
  · rw [judgeW_queued p hist i s hq]
    by_cases hs : (judge p hist i s.rest).code = .slow <;> simp [hq, hs]
  · rw [judgeW_plain p hist i s (by simpa using hq)]
    simp [hq, judge_not_queued]

theorem nonholder_judge (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : ∀ w ∈ s.waits, holderWait w.1 = false) : judgeW p hist i s = judge p hist i s := by
  apply judgeW_unwaited
  have : s.waits.filter (fun w => holderWait w.1) = [] := List.filter_eq_nil_iff.2 (fun w hw => by simp [h w hw])
  simp [Sample.holdMs, this]

theorem holdMs_le_sum (ws : List (Fw.Sup.Adapt.WhyTag × Nat)) :
    ((ws.filter (fun w => holderWait w.1)).map (·.2)).sum ≤ (ws.map (·.2)).sum := by
  induction ws with
  | nil => simp
  | cons w r ih =>
    by_cases hw : holderWait w.1 = true <;> simp [hw] <;> omega

theorem rest_ge (s : Sample) (hs : (s.waits.map (·.2)).sum ≤ s.waitMs) : s.durMs - s.waitMs ≤ (s.rest).durMs := by
  have := holdMs_le_sum s.waits
  show s.durMs - s.waitMs ≤ s.durMs - s.holdMs
  unfold Sample.holdMs
  omega

theorem wait_only_queued (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hq : queuedWithin s = true) (hd : s.durMs ≤ s.holdMs) : (judgeW p hist i s).code = .queued := by
  refine (queued_iff p hist i s).2 ⟨hq, no_alert_within_budget p hist i s.rest ?_⟩
  show s.durMs - s.holdMs ≤ _
  omega

theorem queued_remainder_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (hq : queuedWithin s = true) (hs : (judge p hist i s.rest).code = .slow) : (judgeW p hist i s).code = .slow := by
  rw [judgeW_queued p hist i s hq]; simp [hs]

theorem windowOf_append_waited (p : Params) (hist ws : List Sample) (k : Key)
    (hw : ∀ w ∈ ws, w.waited = true) : windowOf p (hist ++ ws) k = windowOf p hist k := by
  have h : ws.filter (fun s => decide (s.key = k) && counts p s) = [] :=
    List.filter_eq_nil_iff.2 (fun c hc' => by simp [counts, hw c hc'])
  simp [windowOf, List.filter_append, h]

theorem contended_not_slow_Q (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : contended p s = true) : (judgeQ p hist i s).code ≠ .slow := by
  apply judgeQ_not_slow
  have h0 := contended_not_slow p hist i s h
  have hr := contended_not_slow p hist i s.rest (by rw [rest_contended]; exact h)
  by_cases hq : queuedWithin s = true
  · rw [judgeW_queued p hist i s hq]; simp [hr]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; exact h0

theorem no_alert_within_budget_Q (p : Params) (hist : List Sample) (i : Nat) (s : Sample)
    (h : s.durMs ≤ budgetFor p s) : (judgeQ p hist i s).code ≠ .slow := by
  apply judgeQ_not_slow
  have h0 := no_alert_within_budget p hist i s h
  have hr := no_alert_within_budget p hist i s.rest (by rw [rest_budgetFor]; show s.durMs - s.holdMs ≤ _; omega)
  by_cases hq : queuedWithin s = true
  · rw [judgeW_queued p hist i s hq]; simp [hr]
  · rw [judgeW_plain p hist i s (by simpa using hq)]; exact h0

/-- No alert within budget, over the whole output: a sample verdict whose duration is at most its budget is not
`slow`.
-/
theorem no_alert_within_budget_list (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) (hb : v.durMs ≤ v.budgetMs) : v.code ≠ .slow := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p hist v h
  rw [judgeQ_durMs, judgeQ_budgetMs] at hb
  exact no_alert_within_budget_Q p _ i _ hb

/-- **No slow verdict on an overflow bucket**, over the whole output: a `slow` sample verdict never names an `fw`
overflow bucket step.
-/
theorem no_slow_bucket (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) (hs : v.code = .slow) :
    ¬ (v.tool = "fw" ∧ ∃ k ∈ slotKinds, v.step ∈ bucketSteps k) := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p hist v h
  rintro ⟨ht, k, hk, hb⟩
  rw [judgeQ_tool] at ht
  rw [judgeQ_step] at hb
  apply judgeQ_mixed_not_slow p _ i _ _ hs
  simp only [Sample.mixed, ht, beq_self_eq_true, Bool.true_and, List.any_eq_true]
  exact ⟨k, hk, by simpa using hb⟩

theorem unkeyed_late_no_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (h : unkeyedLate hist s = true) :
    (judgeQ p hist i s).code ≠ .slow := by
  cases hm : s.mixed
  · rw [judgeQ_unkeyed p hist i s hm h]; simp [SampleVerdict.markUnkeyed]
  · exact judgeQ_mixed_not_slow p hist i s hm

theorem unkeyed_late_code (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hm : s.mixed = false)
    (h : unkeyedLate hist s = true) : (judgeQ p hist i s).code = .unkeyed := by
  rw [judgeQ_unkeyed p hist i s hm h]; rfl

theorem unkeyedLate_iff (hist : List Sample) (s : Sample) :
    unkeyedLate hist s = true ↔
      s.unkeyed = true ∧ ∃ t ∈ hist, t.full = true ∧ t.unkeyed = false ∧ s.sameStep t = true := by
  unfold unkeyedLate
  simp only [Bool.and_eq_true, List.any_eq_true, Bool.not_eq_true']
  constructor
  · rintro ⟨hs, t, ht, ⟨hf, hu⟩, hss⟩; exact ⟨hs, t, ht, hf, hu, hss⟩
  · rintro ⟨hs, t, ht, hf, hu, hss⟩; exact ⟨hs, t, ht, ⟨hf, hu⟩, hss⟩

theorem judgeQ_no_keyed_history (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hm : s.mixed = false)
    (h : ∀ t ∈ hist, t.full = true → t.unkeyed = false → s.sameStep t = false) :
    judgeQ p hist i s = judgeW p hist i s := by
  apply judgeQ_unmixed p hist i s hm
  cases hu : unkeyedLate hist s
  · rfl
  · obtain ⟨_, t, ht, hf, hk, hss⟩ := (unkeyedLate_iff hist s).1 hu
    rw [h t ht hf hk] at hss; cases hss

theorem slow_not_unkeyed_late (p : Params) (hist : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ timingVerdicts p hist) (hs : v.code = .slow) :
    ∃ i, ∃ hi : i < hist.length, v = judgeQ p (hist.take i) i hist[i] ∧ unkeyedLate (hist.take i) hist[i] = false := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p hist v h
  refine ⟨i, hi, rfl, ?_⟩
  cases hu : unkeyedLate (hist.take i) hist[i]
  · rfl
  · exact absurd hs (unkeyed_late_no_slow p _ i _ hu)

theorem norm_key (s : Sample) : s.norm.key = s.key := rfl

theorem norm_of_not_remote (s : Sample) (h : s.remote = false) : s.norm = s := by
  have h1 : s.remoteQueue = false := by simpa [Sample.remote] using (Bool.or_eq_false_iff.1 h).1
  have h2 : s.ciWait = false := by simpa [Sample.remote] using (Bool.or_eq_false_iff.1 h).2
  simp [Sample.norm, Sample.own, h1, h2]

theorem remoteQueue_norm_dur (s : Sample) (h : s.remoteQueue = true) : s.norm.durMs = 0 := by
  simp [Sample.norm, Sample.own, h]

theorem ciWait_norm_dur (s : Sample) (hc : s.ciWait = true) (o : Nat) (ho : s.ownMs = some o) : s.norm.durMs = o := by
  have h1 : s.remoteQueue = false := by
    simp only [Sample.remoteQueue, Bool.and_eq_false_imp, beq_iff_eq]
    simp only [Sample.ciWait, Bool.and_eq_true, beq_iff_eq] at hc
    intro _; rw [hc.2]; decide
  simp [Sample.norm, Sample.own, h1, hc, ho]

theorem ciWait_dur_indep (s : Sample) (d o : Nat) (hc : s.ciWait = true) (ho : s.ownMs = some o) :
    ({ s with durMs := d } : Sample).norm.durMs = s.norm.durMs := by
  rw [ciWait_norm_dur s hc o ho]
  exact ciWait_norm_dur { s with durMs := d } hc o ho

theorem ciWait_unknown_not_full (s : Sample) (hc : s.ciWait = true) (ho : s.ownMs = none) : s.norm.full = false := by
  have h1 : s.remoteQueue = false := by
    simp only [Sample.remoteQueue, Bool.and_eq_false_imp, beq_iff_eq]
    simp only [Sample.ciWait, Bool.and_eq_true, beq_iff_eq] at hc
    intro _; rw [hc.2]; decide
  simp [Sample.norm, Sample.own, Sample.full, fullRun, h1, hc, ho]

theorem remoteQueue_never_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hq : s.remoteQueue = true) :
    (judgeQ p hist i s.norm).code ≠ .slow := by
  apply no_alert_within_budget_Q
  rw [remoteQueue_norm_dur s hq]; exact Nat.zero_le _

theorem ciWait_never_slow (p : Params) (hist : List Sample) (i : Nat) (s : Sample) (hc : s.ciWait = true) (o : Nat)
    (ho : s.ownMs = some o) (hb : o ≤ budgetFor p s) : (judgeQ p hist i s.norm).code ≠ .slow := by
  apply no_alert_within_budget_Q
  rw [ciWait_norm_dur s hc o ho]; exact hb

/-- The entry point with remote waits judged by their own time (wire ops `obs.timing` and `obs.slow`). -/
def verdictsOf (p : Params) (ss : List Sample) : List Verdict := timingVerdicts p (ss.map Sample.norm)

theorem verdictsOf_remoteQueue_not_slow (p : Params) (ss : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ verdictsOf p ss) (ht : v.tool = "fw land") (hs : v.step = "remote queue") :
    v.code ≠ .slow := by
  obtain ⟨i, hi, rfl⟩ := mem_sample p (ss.map Sample.norm) v h
  have hi' : i < ss.length := by simpa using hi
  have hx : (ss.map Sample.norm)[i] = ss[i].norm := by simp
  rw [hx] at ht hs ⊢
  rw [judgeQ_tool] at ht
  rw [judgeQ_step] at hs
  exact remoteQueue_never_slow p _ i ss[i] (by simpa [Sample.remoteQueue, Sample.norm] using And.intro ht hs)

theorem verdictsOf_ciWait_not_slow (p : Params) (ss : List Sample)
    (hb : ∀ s ∈ ss, s.ciWait = true → ∀ o, s.ownMs = some o → o ≤ budgetFor p s)
    (v : SampleVerdict) (h : Verdict.sample v ∈ verdictsOf p ss) (ht : v.tool = "fw") (hs : v.step = "ci wait") :
    v.code ≠ .slow := by
  obtain ⟨i, hi, hf, rfl⟩ := mem_sample_full p (ss.map Sample.norm) v h
  have hi' : i < ss.length := by simpa using hi
  have hx : (ss.map Sample.norm)[i] = ss[i].norm := by simp
  rw [hx] at ht hs hf ⊢
  rw [judgeQ_tool] at ht
  rw [judgeQ_step] at hs
  have hc : ss[i].ciWait = true := by simpa [Sample.ciWait, Sample.norm] using And.intro ht hs
  obtain ⟨o, ho⟩ : ∃ o, ss[i].ownMs = some o := by
    cases hm : ss[i].ownMs with
    | some o => exact ⟨o, rfl⟩
    | none => exact absurd hf (by rw [ciWait_unknown_not_full _ hc hm]; simp)
  exact ciWait_never_slow p _ i ss[i] hc o ho (hb _ (List.getElem_mem hi') hc o ho)

theorem verdictsOf_sample_at (p : Params) (ss : List Sample) (v : SampleVerdict)
    (h : Verdict.sample v ∈ verdictsOf p ss) :
    ∃ hi : v.idx < ss.length, ss[v.idx].host = v.host ∧ ss[v.idx].tool = v.tool ∧ ss[v.idx].step = v.step := by
  obtain ⟨i, hi, _, rfl⟩ := mem_sample_full p (ss.map Sample.norm) v h
  have hi' : i < ss.length := by simpa using hi
  simp only [judgeQ_idx, judgeQ_host, judgeQ_tool, judgeQ_step, List.getElem_map]
  exact ⟨hi', rfl, rfl, rfl⟩

def SampleVerdict.detailWith (label : String) (v : SampleVerdict) : String :=
  let own := if ({ tool := v.tool, step := v.step, durMs := 0, host := v.host } : Sample).remote
    then " (our own time: the remote run's wait is not counted)" else ""
  s!"{label} took {v.durMs} ms{own}, against baseline {v.baseline} ms (p50 of the {v.n} earlier samples of the same tool, step, host, run kind and work), budget {v.budgetMs} ms"

def SampleVerdict.detail (v : SampleVerdict) : String := v.detailWith s!"sample #{v.idx}"

theorem windowOf_append_contended (p : Params) (hist cs : List Sample) (k : Key)
    (hc : ∀ c ∈ cs, contended p c = true) : windowOf p (hist ++ cs) k = windowOf p hist k := by
  have h : cs.filter (fun s => decide (s.key = k) && counts p s) = [] :=
    List.filter_eq_nil_iff.2 (fun c hc' => by simp [counts, hc c hc'])
  simp [windowOf, List.filter_append, h]

/-- **Contended samples do not change any verdict.** The code of a sample against a history followed by contended
samples is its code against the history alone, so a contended burst can neither raise nor hide an alert.
-/
theorem code_append_contended (p : Params) (hist cs : List Sample) (i j : Nat) (s : Sample)
    (hc : ∀ c ∈ cs, contended p c = true) : (judge p (hist ++ cs) j s).code = (judge p hist i s).code := by
  simp only [judge, windowOf_append_contended p hist cs s.key hc]

/-- **A regression is not masked by contended history.** If a sample is `slow` against a history, it is `slow` against
the same history followed by any number of contended samples (the converse also holds, `code_append_contended`).
-/
theorem slow_through_contention (p : Params) (hist cs : List Sample) (i j : Nat) (s : Sample)
    (hc : ∀ c ∈ cs, contended p c = true) (h : (judge p hist i s).code = .slow) :
    (judge p (hist ++ cs) j s).code = .slow := by
  rw [code_append_contended p hist cs i j s hc]
  exact h

/-- The worked case: five `lean/check` stage runs of 20 s at load 4, then ten runs of 120 s at load 20 (contended), then
a 40 s run at load 4 is `slow` (median 20 s, `3 · 20000 < 2 · 40000`, `40000 > 30000`): the contended 120 s runs neither
alert themselves nor lift the baseline.
-/
theorem lean_check_regression_through_contention :
    (judge {} ((List.replicate 5 (checkStage 20000 4)) ++ List.replicate 10 (checkStage 120000 20)) 15
      (checkStage 40000 4)).code = .slow := by
  decide +kernel

/-- The contended runs of that case are themselves not `slow`. -/
theorem lean_check_contended_burst_not_slow :
    (judge {} (List.replicate 5 (checkStage 20000 4)) 5 (checkStage 120000 20)).code = .contended := by
  decide +kernel

/-! ## Proofs: structural verdicts -/

/-- The sibling baselines are exactly the baselines of the other groups of the stage. -/
theorem mem_siblings (p : Params) (ss : List Sample) (st : Stage) (g : Group) (o : Option Nat) :
    o ∈ siblings p ss st g ↔ ∃ g' ∈ st.groups, g' ≠ g ∧ groupBaseline p ss g' = o := by
  simp [siblings, List.mem_map, List.mem_filter, and_assoc]

/-- A group has a sibling exactly when its sibling list is not empty. -/
theorem siblings_ne_nil (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    (siblings p ss st g).isEmpty = false ↔ ∃ g' ∈ st.groups, g' ≠ g := by
  constructor
  · intro h
    cases hs : siblings p ss st g with
    | nil => rw [hs] at h; simp at h
    | cons o _ =>
      obtain ⟨g', hg', hne, _⟩ := (mem_siblings p ss st g o).1 (by rw [hs]; simp)
      exact ⟨g', hg', hne⟩
  · rintro ⟨g', hg', hne⟩
    have hm := (mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩
    cases hs : siblings p ss st g with
    | nil => rw [hs] at hm; simp at hm
    | cons _ _ => rfl

/-- When a group is structural: it has a baseline `b`, its stage has another group, and every other group of the
stage has a baseline `c` with `2c < b`.
-/
theorem structural_iff (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    callOf p ss st g = .structural ↔
      ∃ b, groupBaseline p ss g = some b ∧ (∃ g' ∈ st.groups, g' ≠ g) ∧
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
  unfold callOf
  cases hg : groupBaseline p ss g with
  | none => simp
  | some b =>
    have hall : (siblings p ss st g).all (below b) = true ↔
        ∀ g' ∈ st.groups, g' ≠ g → ∃ c, groupBaseline p ss g' = some c ∧ 2 * c < b := by
      rw [List.all_eq_true]
      constructor
      · intro h g' hg' hne
        have := h _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩)
        cases hc : groupBaseline p ss g' with
        | none => rw [hc] at this; simp [below] at this
        | some c => rw [hc] at this; exact ⟨c, rfl, by simpa [below] using this⟩
      · intro h o ho
        obtain ⟨g', hg', hne, rfl⟩ := (mem_siblings p ss st g o).1 ho
        obtain ⟨c, hc, hlt⟩ := h g' hg' hne
        simp [hc, below, hlt]
    have hne := siblings_ne_nil p ss st g
    simp only
    by_cases he : (siblings p ss st g).isEmpty = true
    · simp only [he, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, h1, _⟩
        have := hne.2 h1; rw [he] at this; cases this
    · have he' : (siblings p ss st g).isEmpty = false := by simpa using he
      simp only [he', Bool.false_eq_true, ite_false]
      by_cases ha : (siblings p ss st g).all (below b) = true
      · simp only [ha, ite_true, true_iff]
        exact ⟨b, rfl, hne.1 he', hall.1 ha⟩
      · simp only [ha, Bool.false_eq_true, ite_false]
        constructor
        · intro h; split at h <;> cases h
        · rintro ⟨b', hb', _, h2⟩
          cases hb'
          exact absurd (hall.2 h2) ha

/-- When a group is noise: it has a baseline `b`, its stage has another group, every other group has a baseline, and
some other group has a baseline `c` with `2c ≥ b`.
-/
theorem noise_iff (p : Params) (ss : List Sample) (st : Stage) (g : Group) :
    callOf p ss st g = .noise ↔
      ∃ b, groupBaseline p ss g = some b ∧ (∃ g' ∈ st.groups, g' ≠ g) ∧
        (∀ g' ∈ st.groups, g' ≠ g → (groupBaseline p ss g').isSome = true) ∧
        ∃ g' ∈ st.groups, g' ≠ g ∧ ∃ c, groupBaseline p ss g' = some c ∧ b ≤ 2 * c := by
  unfold callOf
  cases hg : groupBaseline p ss g with
  | none => simp
  | some b =>
    have hsome : (siblings p ss st g).all Option.isSome = true ↔
        ∀ g' ∈ st.groups, g' ≠ g → (groupBaseline p ss g').isSome = true := by
      rw [List.all_eq_true]
      constructor
      · intro h g' hg' hne; exact h _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne, rfl⟩)
      · intro h o ho
        obtain ⟨g', hg', hne, rfl⟩ := (mem_siblings p ss st g o).1 ho
        exact h g' hg' hne
    have hnotall : (siblings p ss st g).all (below b) = false ↔
        ∃ o ∈ siblings p ss st g, below b o = false := by
      constructor
      · intro h
        apply Classical.byContradiction
        intro hn
        have : (siblings p ss st g).all (below b) = true :=
          List.all_eq_true.2 (fun o ho => by
            cases hb : below b o
            · exact absurd ⟨o, ho, hb⟩ hn
            · rfl)
        rw [this] at h; cases h
      · rintro ⟨o, ho, hb⟩
        cases ha : (siblings p ss st g).all (below b)
        · rfl
        · rw [List.all_eq_true.1 ha o ho] at hb; cases hb
    have hne := siblings_ne_nil p ss st g
    simp only
    by_cases he : (siblings p ss st g).isEmpty = true
    · simp only [he, ite_true]
      constructor
      · intro h; cases h
      · rintro ⟨_, _, h1, _⟩
        have := hne.2 h1; rw [he] at this; cases this
    · have he' : (siblings p ss st g).isEmpty = false := by simpa using he
      simp only [he', Bool.false_eq_true, ite_false]
      by_cases ha : (siblings p ss st g).all (below b) = true
      · simp only [ha, ite_true]
        constructor
        · intro h; cases h
        · rintro ⟨b', hb', _, _, g', hg', hne', c, hc, hle⟩
          cases hb'
          have := List.all_eq_true.1 ha _ ((mem_siblings p ss st g _).2 ⟨g', hg', hne', rfl⟩)
          rw [hc] at this; simp [below] at this; omega
      · have ha' : (siblings p ss st g).all (below b) = false := by simpa using ha
        simp only [ha, Bool.false_eq_true, ite_false]
        by_cases hs : (siblings p ss st g).all Option.isSome = true
        · simp only [hs, ite_true, true_iff]
          obtain ⟨o, ho, hbo⟩ := hnotall.1 ha'
          obtain ⟨g', hg', hne', rfl⟩ := (mem_siblings p ss st g o).1 ho
          have hso := hsome.1 hs g' hg' hne'
          cases hc : groupBaseline p ss g' with
          | none => rw [hc] at hso; cases hso
          | some c =>
            rw [hc] at hbo
            simp only [below, decide_eq_false_iff_not] at hbo
            exact ⟨b, rfl, hne.1 he', hsome.1 hs, g', hg', hne', c, hc, by omega⟩
        · simp only [hs, Bool.false_eq_true, ite_false]
          constructor
          · intro h; cases h
          · rintro ⟨b', hb', _, h3, _⟩
            exact absurd (hsome.2 h3) hs

/-- The stages are the caller's whenever it gives any. -/
theorem stagesOf_given (p : Params) (ss : List Sample) (h : p.stages ≠ []) : stagesOf p ss = p.stages := by
  unfold stagesOf
  cases hs : p.stages with
  | nil => exact absurd hs h
  | cons _ _ => rfl

/-- The structural verdicts of the entry point are exactly the verdicts of the groups of the stages. -/
theorem mem_structural (p : Params) (ss : List Sample) (v : StructVerdict) :
    Verdict.structural v ∈ timingVerdicts p ss ↔
      ∃ st ∈ stagesOf p ss, ∃ g ∈ st.groups, stageVerdict p ss st g = v := by
  simp [timingVerdicts, structuralVerdicts, List.mem_flatMap]

/-- A call is made on every group of every stage: there is one structural verdict per group, and each group's verdict
(with its call) is in the output.
-/
theorem calls_total (p : Params) (ss : List Sample) :
    (structuralVerdicts p ss).length = ((stagesOf p ss).map (fun st => st.groups.length)).sum ∧
      ∀ st ∈ stagesOf p ss, ∀ g ∈ st.groups, Verdict.structural (stageVerdict p ss st g) ∈ timingVerdicts p ss := by
  refine ⟨by simp [structuralVerdicts, List.length_flatMap], ?_⟩
  intro st hst g hg
  exact (mem_structural p ss _).2 ⟨st, hst, g, hg, rfl⟩

/-- Whenever the caller gives stages, the structural call is made on every group of each of them. -/
theorem calls_given_stages (p : Params) (ss : List Sample) (h : p.stages ≠ []) :
    ∀ st ∈ p.stages, ∀ g ∈ st.groups, Verdict.structural (stageVerdict p ss st g) ∈ timingVerdicts p ss := by
  intro st hst g hg
  exact (calls_total p ss).2 st (by rw [stagesOf_given p ss h]; exact hst) g hg

end Fw.Obs.Timing

/-!
# Wire face and golden of `Fw.Obs.Timing`

JSON encoders for the future op `obs.timing` (wired by task `timing-alert` in `Fw.Wire.Obs`) and the golden
`packages/contracts/golden/obs/timing.jsonl`: one line per case, `{"name", "request", "response"}`, where `request`
is `{"op":"obs.timing","params","samples"}` and `response` is `{"verdicts"}` as `timingVerdicts` computes it.
Regenerate from `lean/` with `lake env lean --run scripts/TimingGolden.lean`; with `--check` it compares the file
with the Lean output (`checkGolden`). A structural verdict carries its `call` (`structural` / `noise` / `undecided`).
(Namespace `Fw.Wire.Obs.Timing`: wire code for the math view.)
-/
namespace Fw.Wire.Obs.Timing
open Lean
open Fw.Obs.Timing

def hostStr : Host → String
  | .«local» => "local"
  | .ci => "ci"

def codeStr : Code → String
  | .noBaseline => "noBaseline"
  | .contended => "contended"
  | .ok => "ok"
  | .slow => "slow"
  | .queued => "queued"
  | .mixed => "mixed"
  | .unkeyed => "unkeyed"

def callStr : Call → String
  | .structural => "structural"
  | .noise => "noise"
  | .undecided => "undecided"

def workJson (w : List (String × String)) : Json := Json.mkObj (w.map fun (k, v) => (k, .str v))

def workField (w : List (String × String)) : List (String × Json) := if w.isEmpty then [] else [("work", workJson w)]

def keyJson (k : Key) : Json :=
  Json.mkObj ([("tool", .str k.tool), ("step", .str k.step), ("host", .str (hostStr k.host)),
    ("runKind", .str k.kind)] ++ workField k.work)

def ownPhasesJson (u : Nat) : Json :=
  Json.mkObj [("how", "done"), ("updMs", toJson u), ("tickMs", toJson u), ("pollS", toJson (0 : Nat))]

def sampleJson (s : Sample) : Json :=
  Json.mkObj ([("tool", .str s.tool), ("step", .str s.step), ("durMs", toJson s.durMs),
    ("host", .str (hostStr s.host)), ("load", toJson s.load), ("runKind", .str s.kind),
    ("exit", (s.exit.map toJson).getD .null), ("skipped", toJson s.skipped),
    ("waitMs", toJson s.waitMs),
    ("waits", .arr (s.waits.map (fun (t, ms) => Json.mkObj [("why", .str t.name), ("ms", toJson ms)])).toArray)] ++
    workField s.work ++ (if s.startMs == 0 then [] else [("startMs", toJson s.startMs)]) ++
    (if s.commit == "" then [] else [("commit", .str s.commit)]) ++
    (s.ownMs.map fun o => [("phases", ownPhasesJson (s.startMs + s.durMs - o))]).getD [])

def paramsJson (p : Params) : Json :=
  Json.mkObj [("nMin", toJson p.nMin), ("window", toJson p.window), ("kNum", toJson p.kNum),
    ("kDen", toJson p.kDen), ("budgetMs", toJson p.budgetMs),
    ("budgets", .arr (p.budgets.map (fun (t, b) => Json.mkObj [("tool", .str t), ("ms", toJson b)])).toArray),
    ("ceilings", .arr (p.ceilings.map (fun (t, s, c) =>
      Json.mkObj [("tool", .str t), ("step", .str s), ("ms", toJson c)])).toArray),
    ("loadMax", toJson p.loadMax),
    ("stages", .arr (p.stages.map (fun st => Json.mkObj [("id", .str st.id),
      ("groups", .arr (st.groups.map (fun g => Json.mkObj [("name", .str g.name),
        ("keys", .arr (g.keys.map keyJson).toArray)])).toArray)])).toArray)]

def verdictJson : Verdict → Json
  | .sample v => Json.mkObj ([("kind", Json.str "sample"), ("idx", toJson v.idx), ("tool", .str v.tool),
      ("step", .str v.step), ("host", .str (hostStr v.host)), ("durMs", toJson v.durMs),
      ("code", .str (codeStr v.code)), ("n", toJson v.n), ("baseline", toJson v.baseline),
      ("budgetMs", toJson v.budgetMs), ("runKind", .str v.kind)] ++ workField v.work)
  | .structural v => Json.mkObj [("kind", "structural"), ("stage", .str v.stage), ("group", .str v.group),
      ("call", .str (callStr v.call)), ("baseline", toJson v.baseline), ("siblingMax", toJson v.siblingMax)]

def caseJson (name : String) (p : Params) (ss : List Sample) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", "obs.timing"), ("params", paramsJson p),
      ("samples", .arr (ss.map sampleJson).toArray)]),
    ("response", Json.mkObj [("verdicts", .arr ((verdictsOf p ss).map verdictJson).toArray)])]

def gateTool : String := "ci:breakpoint-gate"

def gateJob (step : String) (s : Nat) : Sample := { tool := gateTool, step, durMs := s * 1000, host := .ci }

def gateKey (step : String) : Key := { tool := gateTool, step, host := .ci }

/-- Breakpoint-gate run 39067656223: the real job durations in s (`gh run view 39067656223 --json jobs`,
completedAt − startedAt), in the listed order. -/
def gateRun : List Sample :=
  [gateJob "plan" 5, gateJob "site" 35, gateJob "sweeps (chromium)" 342, gateJob "sweeps (playwright-webkit)" 345,
   gateJob "gate (chromium, s4)" 59, gateJob "gate (chromium, s7)" 53, gateJob "gate (chromium, s6)" 53,
   gateJob "gate (chromium, s1)" 57, gateJob "gate (playwright-webkit, s3)" 147, gateJob "gate (chromium, s0)" 63,
   gateJob "gate (chromium, s3)" 55, gateJob "gate (playwright-webkit, s1)" 120,
   gateJob "gate (playwright-webkit, s0)" 113, gateJob "gate (chromium, s2)" 53, gateJob "gate (chromium, s5)" 76,
   gateJob "gate (playwright-webkit, s2)" 120, gateJob "gate (playwright-webkit, s5)" 117,
   gateJob "gate (playwright-webkit, s4)" 132, gateJob "gate (playwright-webkit, s7)" 109,
   gateJob "gate (playwright-webkit, s6)" 141, gateJob "merge (playwright-webkit)" 34, gateJob "merge (chromium)" 36]

/-- One run gives one sample per job key, so `nMin := 1`; CI jobs get a 120 s budget. -/
def gateParams : Params :=
  { nMin := 1, budgets := [(gateTool, 120000)],
    stages := [
      { id := "breakpoint-gate:test",
        groups := [{ name := "gate", keys := ((["chromium", "playwright-webkit"].flatMap fun e =>
            (List.range 8).map fun i => s!"gate ({e}, s{i})")).map gateKey },
          { name := "sweeps", keys := [gateKey "sweeps (chromium)", gateKey "sweeps (playwright-webkit)"] }] },
      { id := "breakpoint-gate:merge",
        groups := [{ name := "merge (chromium)", keys := [gateKey "merge (chromium)"] },
          { name := "merge (playwright-webkit)", keys := [gateKey "merge (playwright-webkit)"] }] }] }

/-- The parameters with the `fw land` ceilings (30 s total, 5 s lock held). -/
def landParams : Params := { ceilings := landCeilings }

def run (tool step : String) (host : Host) (load : Nat) (ds : List Nat) : List Sample :=
  ds.map fun d => { tool, step, durMs := d, host, load }

def runK (tool step kind : String) (host : Host) (ds : List Nat) : List Sample :=
  ds.map fun d => { tool, step, durMs := d, host, kind }

def runX (tool step : String) (host : Host) (load : Nat) (xs : List (Nat × Option Int × Bool)) : List Sample :=
  xs.map fun (d, exit, skipped) => { tool, step, durMs := d, host, load, exit, skipped }

def waitS (tool step : String) (load d : Nat) (ws : List (Fw.Sup.Adapt.WhyTag × Nat)) : Sample :=
  { tool, step, durMs := d, host := .«local», load, waitMs := (ws.map (·.2)).sum, waits := ws }

def landDry : List (Nat × Option Int × Bool) :=
  [(256, some 12, false), (19140, some 0, false), (213, some 12, false), (20226, some 0, false),
   (20710, some 0, false), (75, some 16, false), (20102, some 0, false), (12, some 1, false), (72, some 16, false),
   (32103, some 0, false), (103, some 16, false), (28484, some 0, false), (124, some 2, false), (879, some 0, false)]

def gateGapsJudge : List (Nat × Option Int × Bool) :=
  [(44000, some 0, false), (79000, some 0, false), (74000, some 0, false)] ++
    List.replicate 7 (0, some 0, true) ++
    [(82000, some 0, false), (88000, some 0, false), (91000, some 0, false), (76000, some 0, false)]

def gateEngine : List (Nat × Option Int × Bool) :=
  ([18000, 31000, 23000, 18000, 20000, 22000, 19000, 22000, 18000, 22000, 0, 24000, 21000, 20000, 23000, 26000, 0,
    19000, 18000, 0, 33000].map fun d => (d, some 0, decide (d = 0)))

/-- A check.sh history around 2 min (handoffs report 117 s and up to 136 s for check.sh). -/
def checkHist : List Nat := [117000, 124000, 131000, 119000, 136000, 122000]

/-- Five runs of a CI workflow `wf` with jobs `build`, `test (a)`, `test (b)`, `lint` and one step span. -/
def autoRuns : List Sample :=
  (List.range 5).flatMap fun _ =>
    [{ tool := "wf", step := "build", durMs := 10000, host := .ci },
     { tool := "wf", step := "test (a)", durMs := 100000, host := .ci },
     { tool := "wf", step := "test (b)", durMs := 110000, host := .ci },
     { tool := "wf", step := "lint", durMs := 20000, host := .ci },
     { tool := "wf", step := "test (a)/Run tests", durMs := 90000, host := .ci }]

def group (w : Option Nat) (load d : Nat) : Sample :=
  { tool := "lean/check", step := "parallel group", durMs := d, host := .«local», load, exit := some 0,
    work := slotWork w none }

/-- The `parallel group` spans of `timings.jsonl` as (ms, load, width), written before spans had a `slot` member.
The widths are INFERRED from the durations (about 95 s alone, about 48 s two at a time); they were not recorded.
-/
def groupView : List (Nat × Nat × Nat) :=
  [(116691, 3, 1), (49291, 4, 2), (46962, 3, 2), (92010, 2, 1), (47565, 2, 2), (97284, 2, 1), (94807, 1, 1),
   (49426, 5, 2), (94437, 2, 1)]

def groupMix : List Sample :=
  [(92010, 1), (47565, 2), (97284, 1), (49291, 2), (94807, 1), (46962, 2), (91526, 1), (49426, 2), (90470, 1),
   (48630, 2)].map fun (d, w) => group (some w) 2 d

/-- The first three `parallel group` spans with a recorded `slot` member (`timings.jsonl`, 2026-10-23, commits
0f415fc, 6feef2b and 237e75a): width 1 of 97 to 99 jobs.
-/
def groupRecorded : List Sample := [(99840, 3), (99658, 4), (108545, 2)].map fun (d, l) => group (some 1) l d

/-- The outer span `fw slot run check sh lean/scripts/check.sh` of `.fw-console/timings.jsonl`, 2026-10-25T22:40Z to
2026-10-26T01:25Z (commits b4de7bc to 401d607), as (ms, load, exit). The same nine rows are in
`apps/runner/test/fixtures/slot-check-outer.jsonl`; the TS test checks the golden against them. -/
def slotCheckData : List (Nat × Nat × Nat) :=
  [(179360, 3, 0), (99049, 7, 0), (189227, 7, 0), (92795, 4, 0), (95479, 8, 1), (90201, 3, 1), (99798, 5, 0),
   (180178, 4, 0), (177727, 4, 0)]

/-- The width of each row, INFERRED from the duration (width 1 took 175 to 235 s, width 2 took 88 to 100 s; the span did
not carry the width then). -/
def slotCheckWidth (d : Nat) : Nat := if d < 130000 then 2 else 1

def slotCheck (w : Option Nat) (d load e : Nat) : Sample :=
  { tool := "fw", step := "slot run check sh lean/scripts/check.sh", durMs := d, host := .«local», load,
    exit := some (Int.ofNat e), work := slotWork w none }

def slotCheckRun (keyed : Bool) : List Sample :=
  slotCheckData.map fun (d, l, e) => slotCheck (if keyed then some (slotCheckWidth d) else none) d l e

def polish (kinds : List String) (load d : Nat) : Sample :=
  { tool := "fw", step := "polish commit", durMs := d, host := .«local», load, exit := some 0,
    work := spanWork none none (some kinds) }

/-- The 38.2 s `polish commit` span of 2026-10-23T11:10:16Z (commit aa96a910f) and the 20 spans before it, as
(ms, load, heavy checks). The checks are INFERRED: the spans carried no `checks` member, so each span was matched by
time to the polish commit it made and given the kinds `ops.checkMap` returns for that commit's files.
-/
def polishData : List (Nat × Nat × List String) :=
  [(11933, 4, ["lakeBuild", "leanElab"]), (18826, 2, ["lakeBuild"]), (39792, 2, ["lakeBuild", "leanElab"]),
    (39042, 2, ["lakeBuild"]), (1868, 2, ["lakeBuild"]), (26418, 6, ["lakeBuild"]), (10567, 1, ["lakeBuild"]),
    (11008, 1, ["lakeBuild", "leanElab"]), (500, 1, []), (9216, 3, ["lakeBuild", "leanElab"]), (9880, 2, ["lakeBuild"]),
    (11838, 1, ["lakeBuild", "leanElab"]), (32572, 3, ["lakeBuild", "presetCheck"]), (866, 3, []),
    (23918, 3, ["lakeBuild"]), (22774, 3, ["lakeBuild"]), (42892, 5, ["lakeBuild", "presetCheck"]), (549, 4, []),
    (8752, 4, ["lakeBuild"]), (537, 2, []), (38160, 5, ["lakeBuild"])]

def polishRun : List Sample := polishData.map fun (d, l, k) => polish k l d

def polishMods : List Nat := [1, 29, 32, 31, 1, 26, 7, 7, 0, 1, 2, 1, 50, 0, 37, 14, 50, 0, 1, 0, 40]

def polishRunMods : List Sample :=
  (polishData.zip polishMods).map fun ((d, l, k), m) =>
    { polish k l d with work := spanWork none none (some k) (if k.contains "lakeBuild" then some m else none) }

def landDryData : List (Nat × Nat × Nat × Nat) :=
  [(51554, 3, 0, 24), (34947, 3, 0, 0), (29624, 2, 0, 0), (28979, 1, 0, 0), (23900, 1, 17, 0), (23930, 2, 0, 0),
    (25719, 2, 0, 0), (46188, 3, 0, 24), (34806, 3, 0, 6), (25331, 2, 0, 0), (23709, 3, 0, 0), (24166, 2, 17, 0),
    (23757, 1, 0, 0), (27863, 3, 0, 0), (30859, 2, 0, 0), (27223, 3, 0, 0), (23449, 2, 0, 0), (32841, 1, 0, 6),
    (33402, 3, 0, 6), (28904, 3, 0, 0), (33229, 5, 0, 0), (27689, 3, 0, 0), (47126, 2, 0, 29), (47775, 4, 0, 29),
    (36051, 7, 0, 0), (31795, 8, 0, 0), (50000, 3, 0, 29), (29142, 3, 0, 0), (55447, 2, 0, 29), (55092, 4, 0, 29),
    (27436, 3, 0, 0), (32419, 3, 0, 6), (31964, 5, 0, 0), (29406, 3, 0, 0), (25554, 3, 0, 0), (24716, 3, 0, 0),
    (25105, 1, 0, 0), (52693, 3, 0, 30), (46319, 2, 0, 29), (30026, 3, 0, 0), (24882, 2, 0, 0), (26318, 3, 0, 0),
    (24784, 2, 0, 0), (24675, 2, 0, 0), (27111, 2, 0, 0), (26112, 4, 0, 0), (43470, 3, 0, 24)]

def landDryRun (built : Bool) : List Sample :=
  landDryData.map fun (d, l, e, m) =>
    { tool := "fw", step := "land dry lake", durMs := d, host := .«local», load := l, exit := some (Int.ofNat e),
      work := if built then spanWork none none none (some m) else [] }

def landKeyedData : List (Nat × Option Nat × Nat) :=
  [(44947, some 24, 3), (26801, none, 4), (26410, none, 4), (30086, none, 3), (26599, some 0, 3), (28357, none, 3),
   (28350, none, 3), (26396, none, 2), (26823, none, 3), (26490, none, 2), (28192, none, 5), (37163, some 6, 4),
   (33250, some 0, 5), (51092, none, 4), (36623, some 6, 4), (29602, some 0, 4), (34463, some 6, 2), (34173, some 6, 3),
   (39692, some 6, 3), (28563, some 0, 4), (29974, some 0, 3), (26441, some 0, 3), (25264, some 0, 2), (26484, some 0, 3)]

def landKeyedRun (n : Nat) : List Sample :=
  (landKeyedData.take n).map fun (d, m, l) =>
    { tool := "fw", step := "land dry lake", durMs := d, host := .«local», load := l, exit := some 0,
      work := (m.map modsWork).getD [] }

def incidentCheckRun (keyed : Bool) : List Sample :=
  ([812, 780, 755, 801, 790, 846, 770, 783].map fun d =>
    ({ tool := "lean/check", step := "lake build", durMs := d, host := .«local», load := 4, exit := some 0,
       work := if keyed then modsWork 0 else [] } : Sample)) ++
  [{ incidentCheck with exit := some 0, work := if keyed then modsWork 24 else [] }]

def incidentLandRun (keyed : Bool) : List Sample :=
  ([3182, 3301, 2987, 3050, 3410, 3175, 3190, 3120].map fun d =>
    ({ tool := "fw land", step := incidentLand.step, durMs := d, host := .«local», load := 4, exit := some 0,
       work := if keyed then modsWork 0 else [] } : Sample)) ++
  [{ incidentLand with exit := some 0, work := if keyed then modsWork 24 else [] }]

def incidentOuterRun (keyed : Bool) : List Sample :=
  ([23232, 23100, 23500, 23410, 23180, 23300, 23250, 23360].map fun d =>
    ({ tool := "fw land", step := "dry total lake", durMs := d, host := .«local», load := 5, exit := some 0,
       work := if keyed then modsWork 0 else [] } : Sample)) ++
  [{ incidentOuter ("fw land", "dry total lake") 46323 [25] with work := if keyed then outerWork [25] else [] }]

def incidentSlotRun (keyed : Bool) : List Sample :=
  ([23400, 23100, 23500, 23610, 23180, 23300, 23250, 23360].map fun d =>
    ({ tool := "fw", step := "slot run land pnpm fw land dry", durMs := d, host := .«local», load := 5, exit := some 0,
       work := if keyed then modsWork 0 else [] } : Sample)) ++
  [{ incidentOuter ("fw", "slot run land pnpm fw land dry") 67391 [41] with work := if keyed then outerWork [41] else [] }]

#guard (outerBuilt [30, 11], outerBuilt [], outerWork [0, 0]) == (41, 0, modsWork 0)
#guard ((sampleVerdicts {} (incidentOuterRun true)).getLast?.map (·.code)) == some .noBaseline
#guard ((sampleVerdicts {} (incidentOuterRun false)).getLast?.map (·.code)) == some .slow
#guard ((sampleVerdicts {} (incidentSlotRun true)).getLast?.map (·.code)) == some .noBaseline

def ciWaitData : List (Nat × Nat × Nat) :=
  [(316141, 20570, 2), (440814, 16696, 3), (179419, 26169, 4), (335984, 25290, 5), (387370, 27352, 5),
   (293198, 12245, 4), (1377258, 27294, 5)]

#guard ciWaitData.all fun (d, o, _) => o ≤ d

def ciWaitRun : List Sample :=
  ciWaitData.map fun (d, o, l) =>
    { tool := "fw", step := "ci wait", durMs := d, host := .«local», load := l, exit := some 0, ownMs := some o,
      startMs := 1792745374550, commit := "3d0d68a" }

def remoteQueueData : List (Nat × Nat) := [(0, 4), (0, 1), (37079, 4), (0, 3), (0, 2), (0, 4), (36034, 5)]

def remoteQueueRun : List Sample :=
  remoteQueueData.map fun (d, l) =>
    { tool := "fw land", step := "remote queue", durMs := d, host := .«local», load := l, exit := some 0 }

def bucketRun (step : String) : List Sample :=
  runX "fw" step .«local» 4 ([(1261, some 0), (50394, some 0), (621, some 1), (731, some 0), (7957, some 0),
    (13855, some 1), (38629, some 0), (12607, some 0), (516, some 0), (8, some 1), (7824, some 0), (854, some 0),
    (38315, some 0)].map fun (d, e) => (d, e, false))

def cases (_ : Unit := ()) : List (String × Params × List Sample) :=
  [("breakpoint-gate run 39067656223: sweeps (345 s) is structural in stage {gate, sweeps} (gate shards <= 147 s), gate is noise, both merges are noise; one run, so every sample is noBaseline",
      gateParams, gateRun),
   ("lean check.sh 128 s after a history of 117-136 s: ok (not slow)",
      {}, run "lean" "check.sh" .«local» 8 (checkHist ++ [128000])),
   ("lean check.sh 205 s after a history of 117-136 s: slow (median 122 s; 2 * 205000 > 3 * 122000)",
      {}, run "lean" "check.sh" .«local» 8 (checkHist ++ [205000])),
   ("below n_min: 4 earlier samples (nMin 5), a 10 min run is noBaseline",
      {}, run "lean" "lake build" .«local» 3 [60000, 61000, 59000, 60000, 600000]),
   ("exactly k * baseline (150000 = 3/2 * 100000): ok",
      {}, run "ci:lean" "check" .ci 0 [100000, 100000, 100000, 100000, 100000, 150000]),
   ("1 ms above k * baseline: slow",
      {}, run "ci:lean" "check" .ci 0 [100000, 100000, 100000, 100000, 100000, 150001]),
   ("exactly at the budget (30000 ms, 3x the baseline): ok",
      {}, run "fw" "land" .«local» 2 [10000, 10000, 10000, 10000, 10000, 30000]),
   ("1 ms above the budget and above k * baseline: slow",
      {}, run "fw" "land" .«local» 2 [10000, 10000, 10000, 10000, 10000, 30001]),
   ("contended local sample (load 24 > 8): verdict contended, and it stays out of the next window (n = 5)",
      {}, run "lean" "check.sh" .«local» 4 [60000, 60000, 60000, 60000, 60000] ++
        run "lean" "check.sh" .«local» 24 [300000] ++ run "lean" "check.sh" .«local» 4 [61000]),
   ("CI sample at load 40 is never contended: slow",
      {}, run "ci:lean" "check" .ci 40 [60000, 60000, 60000, 60000, 60000, 300000]),
   ("window N = 5 drops the old 400 s outlier: 160 s after five 100 s runs is slow",
      { window := 5 }, run "ci:lean" "check" .ci 0 [400000, 100000, 100000, 100000, 100000, 100000, 160000]),
   ("land ceilings: three real check.sh spans of 2026-10-17 (112.5, 124.1, 152.8 s at load 8-9, lower bounds of the lock-held time) as lock-held samples with no history: all slow at once (5 s ceiling); the relative rule alone gives noBaseline",
      landParams, run "fw land" "lock held" .«local» 8 [112483, 124065, 152813]),
   ("land ceilings: a total of exactly 30000 ms after five 12 s lands: ok",
      landParams, run "fw land" "total" .«local» 4 [12000, 12000, 12000, 12000, 12000, 30000]),
   ("land ceilings: a first-ever total of 30001 ms (no history) is slow",
      landParams, run "fw land" "total" .«local» 4 [30001]),
   ("land ceilings: a lock held of exactly 5000 ms after five 1 s locks: ok",
      landParams, run "fw land" "lock held" .«local» 4 [1000, 1000, 1000, 1000, 1000, 5000]),
   ("land ceilings: a first-ever lock held of 5001 ms is slow",
      landParams, run "fw land" "lock held" .«local» 4 [5001]),
   ("land ceilings: a lock held of 150 s at load 24 on the local Mac is contended, not an alert",
      landParams, run "fw land" "lock held" .«local» 4 [1000, 1000, 1000, 1000, 1000] ++
        run "fw land" "lock held" .«local» 24 [150000]),
   ("slow-site-build regression: 40 s after 2, 1, 2, 27, 26 s is slow (median 2 s; the old p90 baseline 27 s gave ok)",
      {}, run "breakpoint-gate" "site" .ci 0 [2000, 1000, 2000, 27000, 26000, 40000]),
   ("repeated regression: a second 50 s site build after 2, 1, 2, 27, 26, 50 s is still slow (median 2 s)",
      {}, run "breakpoint-gate" "site" .ci 0 [2000, 1000, 2000, 27000, 26000, 50000, 50000]),
   ("stable series (every two durations within k = 3/2): 100-140 s, never slow",
      {}, run "ci:lean" "check" .ci 0 [100000, 120000, 140000, 110000, 130000, 100000, 140000]),
   ("a lasting shift is accepted once it fills more than half the window: 2 s x4 then 50 s x7, slow while the median is 2 s, ok from the 6th 50 s on (median 50 s)",
      {}, run "ci:w" "build" .ci 0 [2000, 2000, 2000, 2000, 50000, 50000, 50000, 50000, 50000, 50000, 50000]),
   ("auto stages (no params.stages): workflow wf over 5 runs; job family test (matrix legs 100 s and 110 s) is structural against build (10 s) and lint (20 s), which are noise; step spans are not jobs",
      {}, autoRuns),
   ("run kinds: chromium-counts of input digest d1 after 10 s x5 takes 60 s (slow); the first run of digest d2 takes 60 s (no baseline of its own)",
      {}, runK "ci:w" "chromium-counts" "d1" .ci [10000, 10000, 10000, 10000, 10000, 60000] ++ runK "ci:w" "chromium-counts" "d2" .ci [60000]),
   ("run kinds: a 60 s run of digest d1 after 10 s x5 (d1) and 60 s x5 (d2) is slow, d2 history does not hide it",
      {}, runK "ci:w" "chromium-counts" "d1" .ci [10000, 10000, 10000, 10000, 10000] ++
          runK "ci:w" "chromium-counts" "d2" .ci [60000, 60000, 60000, 60000, 60000] ++ runK "ci:w" "chromium-counts" "d1" .ci [60000]),
   ("contended burst then regression (lean_check_regression_through_contention): props lint 20 s x5 at load 4, 120 s x10 at load 20 (contended, no window entry, no alert), then 40 s at load 4 is slow (median 20 s)",
      {}, run "lean/check" "props lint" .«local» 4 [20000, 20000, 20000, 20000, 20000] ++
        run "lean/check" "props lint" .«local» 20 [120000, 120000, 120000, 120000, 120000, 120000, 120000, 120000, 120000, 120000] ++
        run "lean/check" "props lint" .«local» 4 [40000]),
   ("fw land dry 2026-10-22: early refusals (exit 1, 2, 12, 16) get no verdict and stay out of windows; the 32.1 s dry land has 4 full runs before it (noBaseline; pooled with the refusals its median was 256 ms and it was slow), the last is ok",
      {}, runX "fw" "land dry" .«local» 3 landDry),
   ("gate-gaps judge: 7 skipped 0 s jobs get no verdict and stay out of windows; 82 and 88 s are noBaseline, 91 s is ok (median 79 s; pooled with the skipped jobs the median was 0 s and all four were slow)",
      {}, runX "gate-gaps" "judge" .ci 0 gateGapsJudge),
   ("run 39722879593: land (chromium) gate-engine 33 s after 17 full and 3 skipped steps is slow (median 21 s over the full steps)",
      {}, runX "land" "land (chromium)/Run ./.github/actions/gate-engine" .ci 0 gateEngine),
   ("a slow full dry land followed by an early refusal: the refusal gets no verdict, so the slow verdict stays the latest of its key",
      {}, runX "fw" "land dry" .«local» 3 ((List.replicate 5 (20000, some 0, false)) ++ [(45000, some 0, false), (100, some 16, false)])),
   ("unknown exit (null) counts as a full run: 45 s after five 20 s runs with no exit code is slow",
      {}, runX "fw" "land dry" .«local» 3 ((List.replicate 5 (20000, none, false)) ++ [(45000, none, false)])),
   ("2026-10-22 fw/slot acquire sim (reasons INFERRED: the span of that day carried no per-reason ms; read as simBusy): 1523 s of which 1521 s under simBusy after five 2 s acquires is queued (it was a slow alert before: 1523 s > 3/2 of 2 s and over the 30 s budget)",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 1523000 [(.simBusy, 1521000)]]),
   ("the same 1523 s wait read as 1480 s under simBusy and 41 s under memory: the 43 s remainder is judged and is slow (30 s budget); this shows the limit, memory wait time stays judged",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 1523000 [(.simBusy, 1480000), (.memory, 41000)]]),
   ("a serial wait, 100 s under simBusy then 200 s under queued, with 2 s of its own work: queued",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 302000 [(.simBusy, 100000), (.queued, 200000)]]),
   ("the legacy sim-lock (no lease) held for 300 s: 300 s under simBusy, queued",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 302000 [(.simBusy, 300000)]]),
   ("a wait for a live measure window, 120 s under gap: queued",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire measure" 3 122000 [(.gap, 120000)]]),
   ("a wait of 100 s under memLow only is judged as before: slow",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 102000 [(.memLow, 100000)]]),
   ("waitMs 100 s with no waits (an old span or only unknown reasons) is judged as before: slow",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [{ tool := "fw", step := "slot acquire sim", durMs := 102000, host := .«local», load := 3, waitMs := 100000 }]),
   ("no wait (waitMs 0): unchanged, 2.5 s after five 2 s acquires is ok",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000, 2500]),
   ("a refused acquire after maxWaitS (1800 s, no queue field) is judged plain: slow, the alert path for a holder that never leaves",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        run "fw" "slot acquire sim" .«local» 3 [1800000]),
   ("a 100 s wait under simBusy and then 60 s of its own work (median 2 s): the remainder is judged, slow",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 160000 [(.simBusy, 100000)]]),
   ("a queued sample stays out of the window: five 2 s acquires, one 400 s acquire with a 390 s simBusy wait, then 3 s is ok against the median 2 s",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 3 400000 [(.simBusy, 390000)]] ++ run "fw" "slot acquire sim" .«local» 3 [3000]),
   ("a contended local sample (load 24) that waited 1900 s under simBusy is not slow: queued (the remainder is contended)",
      {}, run "fw" "slot acquire sim" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++
        [waitS "fw" "slot acquire sim" 24 1902000 [(.simBusy, 1900000)]]),
   ("run split: a dispatch lock wait of 31 s after five 1 s waits is slow while the plan and the gh call history are steady (timings of 2026-10-23: dispatches took 31-35 s when 2-3 started in the same second)",
      {}, run "fw" "run dispatch lock" .«local» 3 [1000, 1000, 1000, 1000, 1000] ++
        run "fw" "run dispatch call" .«local» 3 [2000, 2000, 2000, 2000, 2000] ++ run "fw" "run plan" .«local» 3 [500, 500, 500, 500, 500] ++
        run "fw" "run dispatch lock" .«local» 3 [31000]),
   ("run split: the gh call of that same slow dispatch (2.5 s after five 2 s calls) is ok: a slow lock does not slow the call part",
      {}, run "fw" "run dispatch lock" .«local» 3 [1000, 1000, 1000, 1000, 1000, 31000] ++
        run "fw" "run dispatch call" .«local» 3 [2000, 2000, 2000, 2000, 2000, 2500]),
   ("run split: a plan of 31 s after five 500 ms plans is slow (the fwcore plan and the checks, not the dispatch call)",
      {}, run "fw" "run plan" .«local» 3 [500, 500, 500, 500, 500] ++ run "fw" "run dispatch call" .«local» 3 [2000, 2000, 2000, 2000, 2000, 2000] ++
        run "fw" "run plan" .«local» 3 [31000]),
   ("run split: a watch pass gh lock wait of 115 s after five 1 s waits is slow while the rest of the pass (8 s after five 8 s) is ok",
      {}, run "fw" "watch pass gh lock" .«local» 3 [1000, 1000, 1000, 1000, 1000, 115000] ++
        run "fw" "watch pass other" .«local» 3 [8000, 8000, 8000, 8000, 8000, 8000]),
   ("run split: a 115 s watch pass gh lock wait after five 1 s waits, judged on its own, is slow",
      {}, run "fw" "watch pass gh lock" .«local» 3 [1000, 1000, 1000, 1000, 1000, 115000]),
   ("run split: the first sample of a new split step has no history of its own, so the old run dispatch history does not judge it: noBaseline",
      {}, run "fw" "run dispatch" .«local» 3 [5000, 5000, 5000, 5000, 5000] ++ run "fw" "run dispatch lock" .«local» 3 [20000]),
   ("slot width: fw watch at 3d0d68a without the width: the 94 s group after a median of 49 s is slow",
      {}, groupView.map fun (d, l, _) => group none l d),
   ("slot width: the same groups with their width: 046ff5f (width 2) and 3d0d68a (width 1) have fewer than 5 same-width groups before them, noBaseline",
      {}, groupView.map fun (d, l, w) => group (some w) l d),
   ("slot width: a 150 s width-1 group after five width-1 groups near 92 s is slow, width-2 groups between them",
      {}, groupMix ++ [group (some 1) 2 150000]),
   ("slot width: a 94 s width-1 group after five width-1 groups near 92 s and five width-2 groups near 48 s is ok",
      {}, groupMix ++ [group (some 1) 2 94437]),
   ("slot width: a span without a width is judged on the spans without one: 94 s after five 48 s is slow, the width-1 spans between them do not count",
      {}, [48000, 47000, 49000, 48000, 47500].map (group none 3) ++ [92000, 95000, 93000].map (group (some 1) 2) ++
        [group none 2 94437]),
   ("slot width recorded: the first three parallel group spans with a recorded width 1 (99.8, 99.7, 108.5 s) have no baseline among themselves",
      {}, groupRecorded),
   ("slot width recorded after inferred: the nine spans with INFERRED widths, then the three recorded ones; 108.5 s against seven width-1 spans (p50 97.3 s) is ok",
      {}, groupView.map (fun (d, l, w) => group (some w) l d) ++ groupRecorded),
   ("slot width outer: fw slot run check, 2026-10-26T00:16Z (180 s) and 01:25Z (178 s) without the width: both are slow after the width-2 runs before them (p50 about 99 s)",
      {}, slotCheckRun false),
   ("slot width outer: the same nine runs with their admitted width (INFERRED from the duration): the two width-1 runs have too few width-1 runs before them, noBaseline, not slow",
      {}, slotCheckRun true),
   ("slot width outer: a 330 s width-1 run after six width-1 runs near 185 s, width-2 runs between them, is still slow",
      {}, [189227, 181464, 183210, 181173, 178339, 182020].flatMap (fun d => [slotCheck (some 1) d 4 0, slotCheck (some 2) 95000 4 0]) ++
        [slotCheck (some 1) 330000 4 0]),
   ("polish commit by checks class: the 38.2 s lakeBuild commit of 2026-10-23T11:10Z is judged on the nine lakeBuild commits before it (p50 18.8 s): slow",
      {}, polishRun),
   ("polish commit without a checks class: the same 21 durations pooled with the light commits are slow",
      {}, polishRun.map fun s => { s with work := [] }),
   ("polish commit by checks class: a 20 s lakeBuild commit after five light commits near 0.5 s has no lakeBuild history: noBaseline",
      {}, [500, 866, 549, 537, 610].map (polish ["nodeCheck"] 2) ++ [polish ["lakeBuild", "nodeCheck"] 2 20000]),
   ("polish commit by checks and rebuilt modules: the 38.2 s lakeBuild commit that rebuilt 40 modules has four lakeBuild commits of 16-63 modules before it: noBaseline",
      {}, polishRunMods),
   ("land dry lake without the rebuilt modules: the 43.5 s run of 2026-10-23T12:39Z (24 modules) against the last 20 runs, most of 0 modules: slow",
      {}, landDryRun false),
   ("land dry lake by rebuilt modules: the same run against the nine earlier runs of 16-63 modules: ok",
      {}, landDryRun true),
   ("slot run overflow bucket: the 38.3 s slot run check of 2026-10-23T11:37Z after the bare slot run check spans before it is mixed, never slow",
      {}, bucketRun "slot run check"),
   ("slot run overflow bucket: a dry cached bucket step is mixed too",
      {}, bucketRun "slot run land dry cached"),
   ("slot run with a command key: the same durations under one command's step are judged: slow",
      {}, bucketRun "slot run check sh lean/scripts/check.sh"),
   ("land dry lake: the 51.1 s span of commit ffb7792 without a lake member comes after keyed spans (24, 0, 6 modules): unkeyed, no verdict (it was slow against the unkeyed history)",
      {}, landKeyedRun 14),
   ("land dry lake: the built-0 spans of 19dd16e (26.4, 25.3, 26.5 s) and d08e461 (30.0 s) are judged on the built-0 history alone (p50 28.6 s over seven): ok",
      {}, landKeyedRun 24),
   ("lean/check lake build, incident of d5babdb: 51.1 s after a main merge (an assumed 24 modules, the count was not recorded; class 16) against eight cached no-op builds (p50 0.78 s, class 0): noBaseline",
      {}, incidentCheckRun true),
   ("lean/check lake build, the same samples recorded without a mods class: 51.1 s against the 0.78 s p50 is slow (the false alarm)",
      {}, incidentCheckRun false),
   ("fw land dry lake build and axiom-check, incident of 8517344: 37.4 s (an assumed 24 modules, the count was not recorded; class 16) against eight no-op steps (p50 3.2 s, class 0): noBaseline",
      {}, incidentLandRun true),
   ("fw land dry lake build and axiom-check, the same samples recorded without a mods class: 37.4 s against the 3.2 s p50 is slow",
      {}, incidentLandRun false),
   ("fw land dry total lake: the 46.3 s span of 2026-10-25 (the checks built 25 modules, class 16) against eight dry lands that built nothing (p50 near 23.3 s, class 0): noBaseline",
      {}, incidentOuterRun true),
   ("fw land dry total lake: the same spans recorded without a mods class: the 46.3 s span is slow against the 23.3 s p50 (the false alarm)",
      {}, incidentOuterRun false),
   ("slot run land dry: the 67.4 s span carrying the checks' 41 modules (MEASURED total, class 16) against eight class-0 spans: noBaseline",
      {}, incidentSlotRun true),
   ("fw ci wait: the 23 min wait is judged by its own 27.3 s against the six waits before it (own p50 20.6 s): ok, though 23 min is far over 1.5 times its raw p50",
      {}, ciWaitRun),
   ("fw land remote queue: the 36.0 s runner queue wait is judged as 0 ms of our time: ok",
      {}, remoteQueueRun),
   ("fw ci wait of an old span without phases: no own time, no verdict (the last verdict is the sixth wait's)",
      {}, ciWaitRun.take 6 ++ [{ tool := "fw", step := "ci wait", durMs := 900000, host := .«local», load := 3, exit := some 0 }])]

#guard ((cases ()).filter fun c => c.1.startsWith "run split:").length == 6

def lastCode (p : Params) (ss : List Sample) : Option Code :=
  ((fullVerdicts p (ss.map Sample.norm)).getLast?).map (·.code)

#guard (structuralVerdicts gateParams gateRun).map (fun v => (v.stage, v.group, v.call, v.baseline, v.siblingMax)) ==
  [("breakpoint-gate:test", "gate", .noise, 147000, 345000), ("breakpoint-gate:test", "sweeps", .structural, 345000, 147000),
   ("breakpoint-gate:merge", "merge (chromium)", .noise, 36000, 34000),
   ("breakpoint-gate:merge", "merge (playwright-webkit)", .noise, 34000, 36000)]
#guard (sampleVerdicts gateParams gateRun).all (·.code == .noBaseline)
#guard ((cases ()).drop 1).map (fun (_, p, ss) => lastCode p ss) ==
  [some .ok, some .slow, some .noBaseline, some .ok, some .slow, some .ok, some .slow, some .ok, some .slow, some .slow,
   some .slow, some .ok, some .slow, some .ok, some .slow, some .contended, some .slow, some .slow, some .ok, some .ok,
   some .noBaseline, some .noBaseline, some .slow, some .slow, some .ok, some .ok, some .slow, some .slow, some .slow,
   some .queued, some .slow, some .queued, some .queued, some .queued, some .slow, some .slow, some .ok, some .slow,
   some .slow, some .ok, some .queued,
   some .slow, some .ok, some .slow, some .ok, some .slow, some .noBaseline,
   some .slow, some .noBaseline, some .slow, some .ok, some .slow,
   some .noBaseline, some .ok, some .slow, some .noBaseline, some .slow,
   some .slow, some .slow, some .noBaseline, some .noBaseline, some .slow, some .ok,
   some .mixed, some .mixed, some .slow,
   some .unkeyed, some .ok, some .noBaseline, some .slow, some .noBaseline, some .slow,
   some .noBaseline, some .slow, some .noBaseline, some .ok, some .ok, some .ok]
#guard ((landKeyedRun 14)[13]?).map (fun s => (judgeW {} ((landKeyedRun 14).take 13) 13 s).code) == some .slow
#guard ((sampleVerdicts {} (landKeyedRun 14))[13]?).map (·.code) == some .unkeyed
#guard ((landKeyedRun 14)[13]?).map (unkeyedLate ((landKeyedRun 14).take 13)) == some true
#guard ((landKeyedRun 14)[13]?).map (unkeyedLate (((landKeyedRun 14).drop 1).take 2)) == some false
#guard ((sampleVerdicts {} (landKeyedRun 24)).drop 20).map (fun v => (v.n, v.baseline, v.code)) ==
  [(4, 28563, .noBaseline), (5, 29602, .ok), (6, 28563, .ok), (7, 28563, .ok)]
#guard ((sampleVerdicts {} (landKeyedRun 24))[23]?).map (·.detail) ==
  some "sample #23 took 26484 ms, against baseline 28563 ms (p50 of the 7 earlier samples of the same tool, step, host, run kind and work), budget 30000 ms"
#guard ((sampleVerdicts {} ciWaitRun)[6]?).map (·.code) == some .slow
#guard ((sampleVerdicts {} (ciWaitRun.map Sample.norm))[6]?).map (·.code) == some .ok
#guard ((sampleVerdicts {} (remoteQueueRun.map Sample.norm))[6]?).map (·.durMs) == some 0
#guard (fullVerdicts {} ((ciWaitRun.take 6 ++ [({ tool := "fw", step := "ci wait", durMs := 900000, host := .«local», exit := some 0 } : Sample)]).map Sample.norm)).length == 6
#guard ((sampleVerdicts {} (ciWaitRun.map Sample.norm))[6]?).map (·.detail) ==
  some "sample #6 took 27294 ms (our own time: the remote run's wait is not counted), against baseline 20570 ms (p50 of the 6 earlier samples of the same tool, step, host, run kind and work), budget 30000 ms"
#guard (fullVerdicts {} (groupView.map (fun (d, l, w) => group (some w) l d) ++ groupRecorded)).getLast?.map
    (fun v => (v.n, v.baseline)) == some (7, 97284)
#guard ((sampleVerdicts {} (slotCheckRun false)).drop 7).map (·.code) == [.slow, .slow]
#guard ((sampleVerdicts {} (slotCheckRun true)).drop 7).map (·.code) == [.noBaseline, .noBaseline]
#guard (fullVerdicts {} polishRun).getLast?.map (fun v => (v.n, v.baseline)) == some (9, 18826)
#guard (fullVerdicts {} polishRunMods).getLast?.map (fun v => (v.n, v.code)) == some (4, .noBaseline)
#guard (fullVerdicts {} (landDryRun true)).getLast?.map (fun v => (v.n, v.baseline, v.code)) == some (9, 50000, .ok)
#guard (sampleVerdicts {} (bucketRun "slot run check")).all (·.code == .mixed)
#guard (sampleVerdicts {} (groupView.map fun (d, l, w) => group (some w) l d)).map (·.code) == List.replicate 9 .noBaseline
#guard ((sampleVerdicts {} (groupView.map fun (d, l, _) => group none l d)).map (·.code)).drop 5 ==
  [.slow, .slow, .ok, .slow]
#guard (fullVerdicts {} (runX "fw" "land dry" .«local» 3 landDry)).map (fun v => (v.durMs, v.code)) ==
  [(19140, .noBaseline), (20226, .noBaseline), (20710, .noBaseline), (20102, .noBaseline), (32103, .noBaseline),
   (28484, .ok), (879, .ok)]
#guard ((sampleVerdicts {} ((runX "fw" "land dry" .«local» 3 landDry).map fun s => { s with exit := none })).map
    (·.code))[9]? == some .slow
#guard (fullVerdicts {} (runX "gate-gaps" "judge" .ci 0 gateGapsJudge)).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .ok, .ok]
#guard ((sampleVerdicts {} ((runX "gate-gaps" "judge" .ci 0 gateGapsJudge).map fun s => { s with skipped := false })).map
    (·.code)).drop 10 == [.slow, .slow, .slow, .slow]
#guard (sampleVerdicts {} (run "ci:w" "build" .ci 0
    [2000, 2000, 2000, 2000, 50000, 50000, 50000, 50000, 50000, 50000, 50000])).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .slow, .slow, .slow, .slow, .ok, .ok]
#guard (sampleVerdicts {} (run "ci:lean" "check" .ci 0
    [100000, 120000, 140000, 110000, 130000, 100000, 140000])).all (·.code != .slow)
#guard (structuralVerdicts {} autoRuns).map (fun v => (v.stage, v.group, v.call, v.baseline, v.siblingMax)) ==
  [("wf", "build", .noise, 10000, 110000), ("wf", "test", .structural, 110000, 20000),
   ("wf", "lint", .noise, 20000, 110000)]
#guard (sampleVerdicts landParams (run "fw land" "lock held" .«local» 8 [112483, 124065, 152813])).all (·.code == .slow)
#guard (sampleVerdicts {} (run "fw land" "lock held" .«local» 8 [112483, 124065, 152813])).all (·.code == .noBaseline)
#guard (sampleVerdicts {} (run "lean" "check.sh" .«local» 4 [60000, 60000, 60000, 60000, 60000] ++
  run "lean" "check.sh" .«local» 24 [300000] ++ run "lean" "check.sh" .«local» 4 [61000])).map (·.code) ==
  [.noBaseline, .noBaseline, .noBaseline, .noBaseline, .noBaseline, .contended, .ok]

def goldenText (_ : Unit := ()) : String :=
  String.join ((cases ()).map fun (n, p, ss) => (caseJson n p ss).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/timing.jsonl"

def spanJson (d : Nat) (slot : Option (Nat × Nat)) (checks : Option (Nat × List String)) (lake : Option Nat := none) :
    Json :=
  Json.mkObj ([("tool", .str (if checks.isSome || lake.isSome then "fw" else "lean/check")),
    ("step", .str (if checks.isSome then "polish commit" else if lake.isSome then "land dry lake" else "parallel group")),
    ("startMs", toJson (1792745374550 : Nat)),
    ("durMs", toJson d), ("exit", toJson (0 : Nat)), ("commit", .str "3d0d68a"), ("load", toJson (2 : Nat)),
    ("host", .str "local")] ++
    (slot.map fun (w, j) => [("slot", Json.mkObj [("width", toJson w), ("jobs", toJson j)])]).getD [] ++
    (checks.map fun (n, ks) => [("checks", Json.mkObj [("n", toJson n), ("kinds", toJson ks)])]).getD [] ++
    (lake.map fun b => [("lake", Json.mkObj [("built", toJson b)])]).getD [])

def workCases : List (String × Nat × Option (Nat × Nat) × Option (Nat × List String)) :=
  [("a span written before the slot member has no work dimensions", 94437, none, none),
   ("width 1 of 30 jobs", 94437, some (1, 30), none),
   ("width 2 of 30 jobs", 49426, some (2, 30), none),
   ("width 2 of 31 jobs: the job count is recorded, not a work dimension", 49426, some (2, 31), none),
   ("width 8 of 30 jobs", 30000, some (8, 30), none),
   ("polish commit of node and sh checks only: light", 537, none, some (2, ["nodeCheck", "shParse"])),
   ("polish commit with no checkmap command: light", 420, none, some (0, [])),
   ("polish commit with lake build: the command count is recorded, not a dimension", 38160, none,
      some (3, ["lakeBuild", "nodeCheck", "shParse"])),
   ("polish commit with the preset check listed before lake build: heavy kinds in fixed order", 42892, none,
      some (2, ["presetCheck", "lakeBuild"])),
   ("polish commit with a Lean script elaborated and lake build", 11008, none,
      some (4, ["leanElab", "lakeBuild", "leanElab", "jsonParse"])),
   ("checks and slot width together", 30000, some (2, 30), some (1, ["leanElab"]))]

#guard heavyChecks.all fun h => workCases.any fun (_, _, _, c) => (c.map (·.2.contains h)).getD false

def lakeWorkCases : List (String × Nat × Option (Nat × Nat) × Option (Nat × List String) × Nat) :=
  [("land dry lake that built no module: class 0", 24675, none, none, 0),
   ("land dry lake that built 6 modules: class 4", 32419, none, none, 6),
   ("land dry lake that built 24 modules: class 16", 43470, none, none, 24),
   ("land dry lake that built 30 modules: class 16, as 24", 52693, none, none, 30),
   ("land dry lake that built 1 module: class 1", 9000, none, none, 1),
   ("land dry lake that built 64 modules: class 64", 90000, none, none, 64),
   ("polish commit with lake build that built 40 modules: checks class, then modules class", 38160, none,
      some (3, ["lakeBuild", "nodeCheck", "shParse"]), 40),
   ("modules class and slot width together", 30000, some (2, 30), none, 3)]

def workGoldenText (_ : Unit := ()) : String :=
  String.join (workCases.map fun (n, d, slot, checks) =>
    (Json.mkObj [("name", .str n), ("span", spanJson d slot checks),
      ("work", workJson (spanWork (slot.map (·.1)) (slot.map (·.2)) (checks.map (·.2))))]).compress ++ "\n") ++
  String.join (lakeWorkCases.map fun (n, d, slot, checks, b) =>
    (Json.mkObj [("name", .str n), ("span", spanJson d slot checks (some b)),
      ("work", workJson (spanWork (slot.map (·.1)) (slot.map (·.2)) (checks.map (·.2)) (some b)))]).compress ++ "\n")

def workGoldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-work.jsonl"

def lakeCases : List (String × String) :=
  [("no build: lake prints no Built line", "Build completed successfully (843 jobs).\n"),
   ("two modules, a warning mark, the exe and a C object of a facet",
      "✔ [795/843] Built Fw.Wire (1.3s)\n⚠ [797/843] Built FwTest.Mutants.Wire (834ms)\nwarning: unused variable\n" ++
      "✔ [840/843] Built fwcore:exe (2.1s)\n✔ [12/843] Built Fw:c.o (90ms)\nBuild completed successfully (843 jobs).\n"),
   ("a failed module is not built", "✖ [4/9] Building Fw.Obs.Timing (1.2s)\nerror: build failed\n"),
   ("a Built line without a progress counter is not lake's", "Built Fw.Wire\n✔ [a/9] Built Fw.Wire (1s)\n"),
   ("a Built line without a time, and a last line without a newline",
      "✔ [1/3] Built Fw.A\n✔ [2/3] Built Fw.B (1s)\n✔ [3/3] Built Fw.C (2s)"),
   ("two Built markers in one line are not lake's", "✔ [1/3] Built Fw.A (1s) ] Built Fw.B\n"),
   ("a Replayed line is a cache hit, not a build", "✔ [78/448] Replayed Fw.Console.Preview\nBuild completed successfully (448 jobs).\n"),
   ("real output of lake build on this repo (2026-10-25, after an edit of Fw.Obs.Timing): 8 modules, a facet object, the exe, warnings between",
      "⚠ [865/929] Built Fw.Obs.Timing (5.0s)\nwarning: Fw/Obs/Timing.lean:1252:21: This simp argument is unused:\n  e\n\nHint: Omit it from the simp argument list.\n  [apply] simp [budgetOf, h]\n\nNote: This linter can be disabled with `set_option linter.unusedSimpArgs false`\n✔ [866/929] Built Fw.Sup.MeasureWindow (1.6s)\n✔ [868/929] Built Fw.Plan.WritesClosure (1.9s)\n✔ [870/929] Built Fw.Sup.AdaptGolden (868ms)\n✔ [872/929] Built Fw.Obs.Timing:c.o (2.6s)\n⚠ [873/929] Built Fw.Obs.Health (15s)\nwarning: Fw/Obs/Health.lean:121:22: This simp argument is unused:\n  List.lookup\n\nHint: Omit it from the simp argument list.\n  [apply] simp [ciSlowFor, h]\n\nNote: This linter can be disabled with `set_option linter.unusedSimpArgs false`\n✔ [875/929] Built Fw.Obs.Next (1.6s)\n✔ [877/929] Built Fw.Wire.Obs (4.0s)\n✔ [927/929] Built Main (1.1s)\n✔ [929/929] Built fwcore:exe (1.9s)\nBuild completed successfully (929 jobs).\n")]

def lakeGoldenText (_ : Unit := ()) : String :=
  String.join (lakeCases.map fun (n, out) =>
    (Json.mkObj [("name", .str n), ("out", .str out), ("built", toJson (builtModules out)),
      ("member", toJson (lakeBuilt? out))]).compress ++ "\n")

#guard lakeCases.map (builtModules ·.2) == [0, 2, 0, 0, 3, 0, 0, 8]
#guard lakeCases.map (lakeBuilt? ·.2) == [some 0, some 2, none, none, some 3, none, some 0, some 8]

def lakeGoldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-lake.jsonl"

def outerCases : List (String × List Nat) :=
  [("no check built a module", [0, 0]), ("no check ran", []), ("one check rebuilt 24 modules", [0, 24]),
   ("two builds of 30 and 11 modules: the sum is 41, class 16", [30, 11]),
   ("two builds of 3 modules are class 4, not class 1", [3, 3]), ("one build of 1 module", [1])]

def outerGoldenText (_ : Unit := ()) : String :=
  String.join (outerCases.map fun (n, xs) =>
    (Json.mkObj [("name", .str n), ("builds", toJson xs), ("built", toJson (outerBuilt xs)),
      ("work", workJson (outerWork xs))]).compress ++ "\n")

#guard outerCases.map (outerBuilt ·.2) == [0, 0, 24, 41, 6, 1]

def outerGoldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-outer.jsonl"

def boundsText (_ : Unit := ()) : String :=
  "// Generated from lean/Fw/Obs/Timing.lean by lean/scripts/TimingGolden.lean; do not edit.\n" ++
  "export const GH_BOUNDS = {\n" ++
  String.join ([("dispatchLockWaitMs", dispatchLockWaitMs), ("dispatchCallTimeoutMs", dispatchCallTimeoutMs),
    ("watchLockWaitMs", watchLockWaitMs), ("watchCallTimeoutMs", watchCallTimeoutMs),
    ("defaultCallTimeoutMs", defaultCallTimeoutMs), ("landCallTimeoutMs", landCallTimeoutMs), ("fwcoreCallMs", fwcoreCallMs), ("pollLockWaitMs", pollLockWaitMs), ("busyRetryS", busyRetryS)].map
      fun (n, v) => "  " ++ n ++ ": " ++ toString v ++ ",\n") ++
  "} as const;\n"

def boundsPath : System.FilePath := "../packages/gh-budget/src/bounds.gen.ts"

structure OwnCase where
  name : String
  s : Nat
  d : Nat
  how : String := "done"
  u : Option Nat
  t : Option Nat
  p : Option Nat := none
  q : Option Nat
  r : Option Nat := none
  w : Option Nat := none

def OwnCase.own (c : OwnCase) : Option Nat := ownOfPhases c.s c.d c.how c.u c.t c.p c.q c.r c.w

def netSrcStr : NetSrc → String
  | .observed => "observed"
  | .state => "state"

def ownCases : List OwnCase :=
  [{ name := "c1fdb56: the 6.9 s wait began 203 s after its run finished; 3.8 s of detection fell inside the wait",
     s := 1792784208219, d := 6921, u := some 1792784005000, t := some 1792784212000, q := some 10 },
   { name := "c1fdb56: the same wait at the 120 s agent poll interval: the same own time",
     s := 1792784208219, d := 6921, u := some 1792784005000, t := some 1792784212000, q := some 120 },
   { name := "c1fdb56: the same wait as recorded, without the interval: no own time, no verdict",
     s := 1792784208219, d := 6921, u := some 1792784005000, t := some 1792784212000, q := none },
   { name := "c1fdb56: the run's first wait saw its deciding tick 12 s after the one before: all 11 s of detection netted",
     s := 1792783668155, d := 405554, u := some 1792784005000, t := some 1792784016000, p := some 1792784004000,
     q := some 10 },
   { name := "c1fdb56: the same wait without the earlier tick: the state's 10 s interval is netted",
     s := 1792783668155, d := 405554, u := some 1792784005000, t := some 1792784016000, q := some 10 },
   { name := "c1fdb56: the same observed gap on a span without pollS: the gap alone decides",
     s := 1792783668155, d := 405554, u := some 1792784005000, t := some 1792784016000, p := some 1792784004000,
     q := none },
   { name := "a failure backoff spaced the ticks 60 s apart: all 50 s of detection netted, not the state's 10 s",
     s := 0, d := 300000, u := some 50000, t := some 100000, p := some 40000, q := some 10 },
   { name := "a list still unfinished 195 s after the finish, ticks 12 s apart: 12 s netted",
     s := 0, d := 300000, u := some 50000, t := some 257000, p := some 245000, q := some 10 },
   { name := "a 207 s detection at a 10 s interval: the poller stalled, 197 s count as own time",
     s := 0, d := 300000, u := some 50000, t := some 257000, q := some 10 },
   { name := "an earlier tick not before the deciding one: the state's interval is netted",
     s := 0, d := 300000, u := some 50000, t := some 57000, p := some 57000, q := some 10 },
   { name := "a wait that timed out has no own time", s := 0, d := 900000, how := "timeout", u := some 5, t := some 5,
     q := some 10 },
   { name := "a run marked done after the span ended has no own time", s := 0, d := 10, u := some 99, t := some 99,
     q := some 10 },
   { name := "a span without a tick time has no own time", s := 0, d := 300000, u := some 50000, t := none,
     p := some 40000, q := some 10 },
   { name := "ticks 217 s apart at a 10 s interval, no backoff after the earlier tick: 10 s netted, 197 s own time again",
     s := 0, d := 300000, u := some 50000, t := some 257000, p := some 40000, q := some 10, r := some 30 },
   { name := "the same stalled gap on a span recorded before the cap (no retryUntilS): the whole gap nets",
     s := 0, d := 300000, u := some 50000, t := some 257000, p := some 40000, q := some 10 },
   { name := "a backoff until 110 s spaced the ticks 71 s apart, within interval plus backoff: all 61 s of detection netted",
     s := 0, d := 300000, u := some 50000, t := some 111000, p := some 40000, q := some 10, r := some 110 },
   { name := "the interval shrank from 60 s at the earlier tick to 10 s at the deciding one: the 55 s gap it scheduled nets in full",
     s := 0, d := 300000, u := some 50000, t := some 95000, p := some 40000, q := some 10, r := some 30, w := some 60 },
   { name := "the same shrunk gap without the earlier tick's interval: only the deciding 10 s nets, 35 s count as own time",
     s := 0, d := 300000, u := some 50000, t := some 95000, p := some 40000, q := some 10, r := some 30 },
   { name := "the interval grew from 10 s at the earlier tick to 30 s at the deciding one: the deciding 30 s caps a 217 s gap",
     s := 0, d := 300000, u := some 50000, t := some 257000, p := some 40000, q := some 30, r := some 30, w := some 10 },
   { name := "a 217 s gap past the earlier tick's 60 s interval: 60 s netted, the stall counts as own time",
     s := 0, d := 300000, u := some 50000, t := some 257000, p := some 40000, q := some 10, r := some 30, w := some 60 }]

def ownSpanJson (c : OwnCase) : Json :=
  let opt (k : String) (x : Option Nat) : List (String × Json) := (x.map fun n => [(k, toJson n)]).getD []
  Json.mkObj [("tool", "fw"), ("step", "ci wait"), ("startMs", toJson c.s), ("durMs", toJson c.d), ("host", "local"),
    ("exit", toJson (0 : Nat)),
    ("phases", Json.mkObj ([("how", .str c.how)] ++ opt "updMs" c.u ++ opt "prevTickMs" c.p ++ opt "tickMs" c.t ++
      opt "pollS" c.q ++ opt "retryUntilS" c.r ++ opt "prevPollS" c.w))]

def ownGoldenText (_ : Unit := ()) : String :=
  String.join (ownCases.map fun c =>
    (Json.mkObj [("name", .str c.name), ("span", ownSpanJson c), ("netSrc", .str (netSrcStr (netSrc c.t c.p))),
      ("capMs", ((gapCapMs c.p c.q c.r c.w).map toJson).getD .null),
      ("netMs", ((netMsOf c.t c.p c.q c.r c.w).map toJson).getD .null), ("ownMs", (c.own.map toJson).getD .null)]).compress ++
      "\n")

#guard ownCases.map OwnCase.own ==
  [some 3140, some 3140, none, some 57709, some 58709, some 57709, some 200000, some 238000, some 240000, some 243000,
   none, none, none, some 240000, some 43000, some 189000, some 205000, some 240000, some 220000, some 190000]
#guard ownCases.map (fun c => netSrc c.t c.p) ==
  [.state, .state, .state, .observed, .state, .observed, .observed, .observed, .state, .state, .state, .state, .state,
   .observed, .observed, .observed, .observed, .observed, .observed, .observed]

def capReasonStr : Fw.Ci.Budget.Reason → String
  | .failures => "failures" | .idle => "idle" | .tooBig => "tooBig" | .retryAfter => "retryAfter"
  | .floor => "floor" | .hour => "hour" | .minute => "minute" | .interval => "interval"

structure CapNetsCase where
  c : OwnCase
  waits : List (Fw.Ci.Budget.Reason × Nat)

def capNetsCases : List CapNetsCase :=
  [{ c := { name := "a 50 s floor wait after the 10 s interval spaced the ticks 60 s apart: only the 10 s cap nets, the floor wait counts as own time",
            s := 0, d := 300000, u := some 50000, t := some 100000, p := some 40000, q := some 10, r := some 30 },
     waits := [(.interval, 10000), (.floor, 50000)] },
   { c := { name := "a backoff to 110 s and a 40 s hour-share wait after the 10 s interval: the cap adds the 70 s backoff to the 10 s interval it overlaps, so 10 s of the share wait is netted and 30 s counts as own time",
            s := 0, d := 300000, u := some 50000, t := some 150000, p := some 40000, q := some 10, r := some 110 },
     waits := [(.interval, 10000), (.retryAfter, 60000), (.hour, 40000)] },
   { c := { name := "a 20 s minute-share wait inside the earlier tick's 60 s interval: the cap's slack absorbs it, no own time in the gap",
            s := 0, d := 300000, u := some 50000, t := some 70000, p := some 40000, q := some 10, r := some 30, w := some 60 },
     waits := [(.interval, 10000), (.minute, 20000)] }]

def CapNetsCase.gapOwn (k : CapNetsCase) : Option Nat :=
  match k.c.t, k.c.p, netMsOf k.c.t k.c.p k.c.q k.c.r k.c.w with
  | some t, some p, some n => some (t - p - n)
  | _, _, _ => none

def CapNetsCase.holds (k : CapNetsCase) : Bool :=
  match k.c.t, k.c.p, gapCapMs k.c.p k.c.q k.c.r k.c.w with
  | some t, some p, some c =>
    decide (p < t) && t - p == waitsMs true k.waits + waitsMs false k.waits && decide (waitsMs true k.waits ≤ c) &&
      k.gapOwn == some (waitsMs false k.waits - (c - waitsMs true k.waits))
  | _, _, _ => false

#guard capNetsCases.all CapNetsCase.holds
#guard capNetsCases.map CapNetsCase.gapOwn == [some 50000, some 30000, some 0]
#guard capNetsCases.map (·.c.own) == [some 240000, some 170000, some 230000]

theorem floor_row_is_golden : capNetsCases.head?.map (fun k => (k.c.t, k.c.p, k.c.q, k.c.r, k.c.w, k.waits)) =
    some (some 100000, some 40000, some 10, some 30, none, [(.interval, 10000), (.floor, 50000)]) := rfl

def capNetsGoldenText (_ : Unit := ()) : String :=
  String.join (capNetsCases.map fun k =>
    (Json.mkObj [("name", .str k.c.name), ("span", ownSpanJson k.c),
      ("waits", .arr (k.waits.map fun (why, ms) => Json.mkObj [("why", .str (capReasonStr why)), ("ms", toJson ms),
        ("nets", toJson (capNets why))]).toArray),
      ("capMs", ((gapCapMs k.c.p k.c.q k.c.r k.c.w).map toJson).getD .null),
      ("netMs", ((netMsOf k.c.t k.c.p k.c.q k.c.r k.c.w).map toJson).getD .null),
      ("gapOwnMs", (k.gapOwn.map toJson).getD .null), ("ownMs", (k.c.own.map toJson).getD .null)]).compress ++ "\n")

def capNetsGoldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-capnets.jsonl"

def ownGoldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-own.jsonl"

def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText; IO.FS.writeFile boundsPath boundsText; IO.FS.writeFile workGoldenPath workGoldenText
  IO.FS.writeFile lakeGoldenPath lakeGoldenText; IO.FS.writeFile ownGoldenPath ownGoldenText
  IO.FS.writeFile capNetsGoldenPath capNetsGoldenText; IO.FS.writeFile outerGoldenPath outerGoldenText

def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile boundsPath) == boundsText &&
    (← IO.FS.readFile workGoldenPath) == workGoldenText && (← IO.FS.readFile lakeGoldenPath) == lakeGoldenText &&
    (← IO.FS.readFile ownGoldenPath) == ownGoldenText && (← IO.FS.readFile capNetsGoldenPath) == capNetsGoldenText &&
    (← IO.FS.readFile outerGoldenPath) == outerGoldenText

end Fw.Wire.Obs.Timing

namespace Fw.Obs.Timing.SlotKey

def valueFlags : List String := ["--filter", "-F", "-C", "--dir", "--kind"]

def filterFlags : List String := ["--filter", "-F"]

def base (t : String) : String := (t.splitOn "/").getLast?.getD t

def okTok (t : String) : Bool :=
  decide (0 < t.length) && decide (t.length ≤ 60) &&
    t.all fun c => c.isAlphanum || c == '.' || c == '_' || c == '-' || c == '/'

def launchWords : List String := ["exec", "dlx"]

def skipWords : List String := ["run"]

def scan (filt : Option String) : List String → Option String × Option String × List String
  | [] => (filt, none, [])
  | [t] => if t.startsWith "-" || skipWords.contains t then (filt, none, []) else (filt, some t, [])
  | t :: v :: r =>
    if valueFlags.contains t then
      scan (if filterFlags.contains t then filt.orElse fun _ => some v else filt) r
    else if t.startsWith "-" || skipWords.contains t then scan filt (v :: r)
    else (filt, some t, v :: r)
termination_by l => l.length

def tidy (a : String) : String := if a.startsWith "/" then base a else a

def core (h : String) (args : List String) : List String :=
  let (_, first, _) := scan none args
  [base h] ++ (first.map tidy).toList

def fwLauncher : String := "fw"

def subOf (args : List String) : Option String := (args.find? fun a => !a.startsWith "-").map tidy

def cmdKey : List String → Option String
  | [] => none
  | h :: args =>
    let (filt, first, rest) := scan none args
    let parts :=
      match first, rest with
      | some w, p :: more =>
        if launchWords.contains w then [base h] ++ (filt.map base).toList ++ core p more
        else if w == fwLauncher then [base h] ++ (filt.map base).toList ++ [w] ++ (subOf (p :: more)).toList
        else [base h] ++ (filt.map base).toList ++ [tidy w]
      | some w, [] => [base h] ++ (filt.map base).toList ++ [tidy w]
      | none, _ => [base h] ++ (filt.map base).toList
    if parts.all okTok then some (" ".intercalate parts) else none

def capKey (seen : List String) (cap : Nat) (k : Option String) : Option String :=
  match k with
  | some x => if seen.contains x || decide (seen.length < cap) then some x else none
  | none => none

def kindCap (kind : String) : Nat := if kind == "land" then 8 else if kind == "sim" then 4 else 24

def runStep (kind : String) (seen : List String) (argv : List String) : String :=
  match capKey seen (kindCap kind) (cmdKey argv) with
  | some k => s!"slot run {kind} {k}"
  | none => s!"slot run {kind}"

def dropSuffix (suf s : String) : String := if s.endsWith suf then (s.dropEnd suf.length).toString else s

def stepKey (kind step : String) : Option String :=
  let pre := s!"slot run {kind} "
  if step.startsWith pre then
    let k := dropSuffix " dry" (dropSuffix " cached" (step.drop pre.length).toString)
    if k == "" || k == "dry" || k == "cached" then none else some k
  else none

def seenKeys (kind : String) (steps : List String) : List String := (steps.filterMap (stepKey kind)).eraseDups

theorem seenKeys_mem (kind : String) (steps : List String) (k : String) :
    k ∈ seenKeys kind steps ↔ ∃ s ∈ steps, stepKey kind s = some k := by
  simp [seenKeys, List.mem_eraseDups, List.mem_filterMap]

theorem seenKeys_append (kind : String) (a b : List String) (k : String) :
    k ∈ seenKeys kind (a ++ b) ↔ k ∈ seenKeys kind a ∨ k ∈ seenKeys kind b := by
  simp only [seenKeys_mem, List.mem_append]
  constructor
  · rintro ⟨s, hs | hs, h⟩
    · exact Or.inl ⟨s, hs, h⟩
    · exact Or.inr ⟨s, hs, h⟩
  · rintro (⟨s, hs, h⟩ | ⟨s, hs, h⟩)
    · exact ⟨s, Or.inl hs, h⟩
    · exact ⟨s, Or.inr hs, h⟩

theorem stepKey_prefix (kind step k : String) (h : stepKey kind step = some k) :
    step.startsWith s!"slot run {kind} " = true := by
  by_cases hp : step.startsWith s!"slot run {kind} " = true
  · exact hp
  · exfalso
    simp [stepKey, hp] at h

theorem cmdKey_nil : cmdKey [] = none := rfl

theorem capKey_none (seen : List String) (cap : Nat) : capKey seen cap none = none := rfl

theorem capKey_seen (seen : List String) (cap : Nat) (x : String) (h : x ∈ seen) : capKey seen cap (some x) = some x := by
  simp [capKey, h]

theorem capKey_full (seen : List String) (cap : Nat) (x : String) (h : x ∉ seen) (hc : cap ≤ seen.length) :
    capKey seen cap (some x) = none := by
  simp [capKey, h, Nat.not_lt.2 hc]

theorem capKey_room (seen : List String) (cap : Nat) (x : String) (hc : seen.length < cap) : capKey seen cap (some x) = some x := by
  simp [capKey, hc]

theorem capKey_some (seen : List String) (cap : Nat) (k : Option String) (x : String) (h : capKey seen cap k = some x) :
    x ∈ seen ∨ seen.length < cap := by
  cases k with
  | none => simp [capKey] at h
  | some y =>
    by_cases hc : x ∈ seen ∨ seen.length < cap
    · exact hc
    · exfalso
      simp [capKey] at h
      grind

theorem capKey_bounded (seen : List String) (cap : Nat) (k : Option String) (x : String) (hs : seen.length ≤ cap)
    (h : capKey seen cap k = some x) : (if x ∈ seen then seen else x :: seen).length ≤ cap := by
  rcases capKey_some seen cap k x h with hx | hl
  · simp [hx, hs]
  · by_cases hx : x ∈ seen <;> simp [hx] <;> omega

def waitStep (kind : String) : String := s!"slot wait {kind}"

theorem wait_ne_run (kind : String) (seen : List String) (argv : List String) : waitStep kind ≠ runStep kind seen argv := by
  unfold waitStep runStep
  intro h
  have e1 : (toString "slot wait ").toList[5]? = some 'w' := by decide
  have e2 : (toString "slot run ").toList[5]? = some 'r' := by decide
  have l1 : 5 < (toString "slot wait ").toList.length := by decide
  have l2 : 5 < (toString "slot run ").toList.length := by decide
  split at h
  · have := congrArg (fun s : String => s.toList[5]?) h
    simp only [String.toList_append, List.append_assoc, List.getElem?_append_left l1, List.getElem?_append_left l2, e1, e2] at this
    exact absurd this (by decide)
  · have := congrArg (fun s : String => s.toList[5]?) h
    simp only [String.toList_append, List.getElem?_append_left l1, List.getElem?_append_left l2, e1, e2] at this
    exact absurd this (by decide)

def cases : List (String × String × List String × List String) :=
  [("check.sh", "check", [], ["sh", "lean/scripts/check.sh"]),
   ("vitest file", "test", [], ["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/land-inputs.test.ts"]),
   ("pnpm test of a package", "test", [], ["pnpm", "--filter", "./apps/runner", "test"]),
   ("pnpm test of another package", "test", [], ["pnpm", "-F", "console-api", "test"]),
   ("dry land", "land", [], ["pnpm", "-s", "fw", "land", "b", "--task", "t", "--dry"]),
   ("flags only", "check", [], ["lake", "--quiet"]),
   ("lake build", "check", [], ["lake", "build"]),
   ("absolute program and script", "check", [], ["/usr/bin/env", "/opt/x/check.sh"]),
   ("token outside the set", "check", [], ["sh", "a b"]),
   ("equals sign in an argument", "check", [], ["node", "--x=1", "y=2"]),
   ("empty argv", "check", [], []),
   ("seen key at the cap", "check", (List.range 24).map (fun i => s!"k{i}") ++ ["sh lean/scripts/check.sh"], ["sh", "lean/scripts/check.sh"]),
   ("new key at the cap", "check", (List.range 24).map (fun i => s!"k{i}"), ["sh", "lean/scripts/check.sh"]),
   ("new key one below the cap", "check", (List.range 23).map (fun i => s!"k{i}"), ["sh", "lean/scripts/check.sh"]),
   ("fw subcommand after flags", "check", [], ["pnpm", "-s", "fw", "--json", "ci", "wait", "--branch", "b"]),
   ("fw without a subcommand", "check", [], ["pnpm", "fw"]),
   ("fw with flags only", "check", [], ["pnpm", "fw", "--json"]),
   ("fw subcommand outside the token set", "check", [], ["pnpm", "fw", "a b"]),
   ("land kind new key at its cap of 8", "land", (List.range 8).map (fun i => s!"k{i}"), ["pnpm", "fw", "land"]),
   ("land kind new key one below its cap", "land", (List.range 7).map (fun i => s!"k{i}"), ["pnpm", "fw", "land"]),
   ("check kind with 8 keys is under its cap of 24", "check", (List.range 8).map (fun i => s!"k{i}"), ["pnpm", "fw", "land"]),
   ("sim kind new key at its cap of 4", "sim", (List.range 4).map (fun i => s!"k{i}"), ["pnpm", "fw", "slot"])]

#guard cases.map (fun (_, k, seen, a) => runStep k seen a) ==
  ["slot run check sh lean/scripts/check.sh", "slot run test pnpm runner vitest test/land-inputs.test.ts", "slot run test pnpm runner test",
   "slot run test pnpm console-api test", "slot run land pnpm fw land", "slot run check lake", "slot run check lake build",
   "slot run check env check.sh", "slot run check", "slot run check", "slot run check",
   "slot run check sh lean/scripts/check.sh", "slot run check", "slot run check sh lean/scripts/check.sh",
   "slot run check pnpm fw ci", "slot run check pnpm fw", "slot run check pnpm fw", "slot run check",
   "slot run land", "slot run land pnpm fw land", "slot run check pnpm fw land", "slot run sim"]

def seenCases : List (String × String × List String) :=
  [("keys, suffixes and repeats", "check",
    ["slot run check sh a.sh", "slot run check sh a.sh cached", "slot run check", "slot run check cached", "slot run check dry",
     "slot run check dry cached", "slot run check pnpm fw land dry", "slot run check pnpm fw land dry cached", "slot run land pnpm fw land dry",
     "slot run test pnpm x test", "slot wait check", "slot run checks y", "slot run check sh a.sh"]),
   ("other kind", "land", ["slot run land pnpm fw land dry", "slot run land pnpm fw land", "slot run check sh a.sh"]),
   ("empty", "test", [])]

#guard seenCases.map (fun (_, k, st) => seenKeys k st) ==
  [["sh a.sh", "pnpm fw land"], ["pnpm fw land"], []]

end Fw.Obs.Timing.SlotKey

namespace Fw.Wire.Obs.SlotKey
open Lean
open Fw.Obs.Timing.SlotKey

def caseJson (n k : String) (seen argv : List String) : Json :=
  Json.mkObj [("name", n), ("request", Json.mkObj [("kind", k), ("seen", toJson seen), ("argv", toJson argv)]),
    ("response", Json.mkObj [("step", runStep k seen argv), ("wait", waitStep k)])]

def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, k, seen, a) => (caseJson n k seen a).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/slot-key.jsonl"

def seenJson (n k : String) (steps : List String) : Json :=
  Json.mkObj [("name", n), ("request", Json.mkObj [("kind", k), ("steps", toJson steps)]),
    ("response", Json.mkObj [("seen", toJson (seenKeys k steps))])]

def seenText (_ : Unit := ()) : String :=
  String.join (seenCases.map fun (n, k, st) => (seenJson n k st).compress ++ "\n")

def seenPath : System.FilePath := "../packages/contracts/golden/obs/slot-seen.jsonl"

def writeGolden : IO Unit := do IO.FS.writeFile goldenPath goldenText; IO.FS.writeFile seenPath seenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile seenPath) == seenText

end Fw.Wire.Obs.SlotKey
