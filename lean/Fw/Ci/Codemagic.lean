import Lean.Data.Json
/-!
# The Codemagic pilot minutes ledger (task `codemagic-pilot`)

The free personal plan gives 500 Mac mini M2 minutes per calendar month. The pilot stops at 400, so a wrong estimate of the
minutes a build bills (or a month boundary that is off by a day) still leaves 100 minutes. A trigger is allowed only when the
minutes already used this month plus the longest the new build may run (`max_build_duration`) stay within 400.
-/
namespace Fw.Ci.Codemagic

open Lean (Json)

/-- Free Mac minutes per calendar month on the personal plan (codemagic.io/pricing, checked 2026-10-21). -/
def freeMinutes : Nat := 500

/-- The pilot trigger stops when `used + cap` would pass this many minutes of the month. -/
def stopAt : Nat := 400

/-- The longest `max_build_duration` the pilot allows, in minutes (the one cell, one session of two passes, took 33 min on GitHub). -/
def maxCapMin : Nat := 40

/-- At most this many pilot builds ever (the task's accepted limit). -/
def maxBuilds : Nat := 3

/-- Minutes a build of `durMs` milliseconds bills: rounded up to a whole minute, and a started build bills at least one. -/
def billedMin (durMs : Nat) : Nat := max 1 ((durMs + 59999) / 60000)

theorem billed_ge_dur (d : Nat) : d ≤ 60000 * billedMin d := by unfold billedMin; omega

theorem billed_pos (d : Nat) : 1 ≤ billedMin d := by unfold billedMin; omega

theorem billed_mono {d e : Nat} (h : d ≤ e) : billedMin d ≤ billedMin e := by unfold billedMin; omega

/-- A build that stays within its `max_build_duration` of `c ≥ 1` minutes bills at most `c` minutes. -/
theorem billed_le_cap {d c : Nat} (hc : 1 ≤ c) (h : d ≤ 60000 * c) : billedMin d ≤ c := by unfold billedMin; omega

/-- One recorded pilot build: its id, the calendar month (`YYYY-MM`, UTC) it started in, and the minutes it billed. -/
structure Row where
  id : String
  month : String
  minutes : Nat
deriving DecidableEq, Repr

/-- Minutes the ledger rows of `month` used. -/
def usedIn (month : String) : List Row → Nat
  | [] => 0
  | r :: rs => (if r.month == month then r.minutes else 0) + usedIn month rs

theorem usedIn_append (m : String) (a b : List Row) : usedIn m (a ++ b) = usedIn m a + usedIn m b := by
  induction a with
  | nil => simp [usedIn]
  | cons r rs ih => simp [usedIn, ih]; omega

/-- Why a trigger is refused, in this order. -/
inductive Refusal where
  | minutes  -- `used + cap` passes the stop line
  | builds   -- the pilot already ran its builds
  | cap      -- the build's own cap passes `maxCapMin`
deriving DecidableEq, Repr

def Refusal.name : Refusal → String
  | .minutes => "minutes" | .builds => "builds" | .cap => "cap"

/-- Every reason to refuse a trigger of a build that may run `cap` minutes, in the month `month`, given the ledger rows. -/
def refusals (month : String) (rows : List Row) (cap : Nat) : List Refusal :=
  (if stopAt < usedIn month rows + cap then [.minutes] else [])
    ++ (if maxBuilds ≤ rows.length then [.builds] else [])
    ++ (if maxCapMin < cap then [.cap] else [])

/-- The adapter triggers only when nothing refuses. -/
def mayTrigger (month : String) (rows : List Row) (cap : Nat) : Bool := (refusals month rows cap).isEmpty

/-- The stop rule: used + cap over the line, no trigger. -/
theorem no_trigger_over (month : String) (rows : List Row) (cap : Nat) (h : stopAt < usedIn month rows + cap) :
    mayTrigger month rows cap = false := by
  simp [mayTrigger, refusals, h]

/-- The build count: the pilot's builds are used up, no trigger. -/
theorem no_trigger_builds (month : String) (rows : List Row) (cap : Nat) (h : maxBuilds ≤ rows.length) :
    mayTrigger month rows cap = false := by
  simp [mayTrigger, refusals, h]

/-- The build cap: a cap above `maxCapMin`, no trigger. -/
theorem no_trigger_cap (month : String) (rows : List Row) (cap : Nat) (h : maxCapMin < cap) :
    mayTrigger month rows cap = false := by
  simp [mayTrigger, refusals, h]

/-- A trigger is allowed exactly when all three conditions hold. -/
theorem trigger_iff (month : String) (rows : List Row) (cap : Nat) :
    mayTrigger month rows cap = true ↔ usedIn month rows + cap ≤ stopAt ∧ rows.length < maxBuilds ∧ cap ≤ maxCapMin := by
  simp only [mayTrigger, refusals]
  by_cases h1 : stopAt < usedIn month rows + cap <;> by_cases h2 : maxBuilds ≤ rows.length <;>
    by_cases h3 : maxCapMin < cap <;> simp [h1, h2, h3] <;> omega

/-- An allowed trigger never reaches the end of the free plan. -/
theorem trigger_within_plan {month : String} {rows : List Row} {cap : Nat} (h : mayTrigger month rows cap = true) :
    usedIn month rows + cap ≤ freeMinutes := by
  have := ((trigger_iff month rows cap).1 h).1
  unfold stopAt at this; unfold freeMinutes; omega

/-- The ledger invariant: after an allowed trigger, the build's row (it billed at most its cap) keeps the month within the stop line. -/
theorem ledger_invariant {month : String} {rows : List Row} {cap : Nat} (h : mayTrigger month rows cap = true)
    (r : Row) (hm : r.month = month) (hr : r.minutes ≤ cap) : usedIn month (rows ++ [r]) ≤ stopAt := by
  have := ((trigger_iff month rows cap).1 h).1
  rw [usedIn_append]; simp [usedIn, hm]; omega

/-- A row of another month does not count toward this month. -/
theorem other_month_free {month : String} (rows : List Row) (r : Row) (hm : r.month ≠ month) :
    usedIn month (rows ++ [r]) = usedIn month rows := by
  rw [usedIn_append]; simp [usedIn, hm]

/-- The pilot's three builds at the largest cap fit under the stop line. -/
theorem pilot_fits : maxBuilds * maxCapMin ≤ stopAt := by decide

/-- The margin left under the plan after the stop line. -/
theorem margin : freeMinutes - stopAt = 100 := by decide

/-- A month in which no row was recorded starts at zero used minutes. -/
theorem fresh_month (month : String) (rows : List Row) (h : ∀ r ∈ rows, r.month ≠ month) : usedIn month rows = 0 := by
  induction rows with
  | nil => rfl
  | cons r rs ih =>
    have hr := h r (by simp)
    have := ih (fun x hx => h x (by simp [hx]))
    simp [usedIn, hr, this]

-- ------------------------------------------------------------------------------------------------ calendar month

/-- The `YYYY-MM` (UTC) of a Unix time in milliseconds: the civil-from-days algorithm (Hinnant), on `Nat` because the pilot's
times are after 1970. -/
def monthOf (ms : Nat) : String :=
  let z := ms / 86400000 + 719468
  let era := z / 146097
  let doe := z % 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let m := if mp < 10 then mp + 3 else mp - 9
  let y := yoe + era * 400 + (if m ≤ 2 then 1 else 0)
  s!"{y}-{if m < 10 then "0" else ""}{m}"

#guard monthOf 0 == "1970-01"
#guard monthOf 951782400000 == "2000-02"
#guard monthOf 1004572799999 == "2001-10"
#guard monthOf 1004572800000 == "2001-11"
#guard monthOf 1798761599999 == "2026-12"
#guard monthOf 1798761600000 == "2027-01"

-- ---------------------------------------------------------------------------------------------------------- status

/-- The exit code of a wait at a build status, or `none` while the build goes on: finished 0, failed or timeout 1,
canceled or skipped 4 (the Codemagic API v3 `BuildStatus` values). -/
def exitOf : String → Option Nat
  | "finished" => some 0
  | "failed" => some 1
  | "timeout" => some 1
  | "canceled" => some 4
  | "skipped" => some 4
  | _ => none

/-- Every status the API names. -/
def statuses : List String :=
  ["initializing", "queued", "preparing", "fetching", "testing", "building", "publishing", "finishing", "finished",
   "failed", "canceled", "timeout", "skipped"]

theorem only_finished_passes : ∀ s ∈ statuses, exitOf s = some 0 → s = "finished" := by decide

theorem running_has_no_exit : ∀ s ∈ ["initializing", "queued", "preparing", "fetching", "testing", "building", "publishing", "finishing"],
    exitOf s = none := by decide

-- ------------------------------------------------------------------------------------------------------------ golden

private def row (id month : String) (m : Nat) : Row := ⟨id, month, m⟩

/-- Ledger cases of the golden: (name, month, rows, cap). -/
def triggerCases : List (String × String × List Row × Nat) :=
  [("fresh", "2026-10", [], 40),
   ("two builds, 80 used", "2026-10", [row "a" "2026-10" 38, row "b" "2026-10" 42], 40),
   ("stop line exact: 360 + 40", "2026-10", [row "a" "2026-10" 180, row "b" "2026-10" 180], 40),
   ("over by one: 361 + 40", "2026-10", [row "a" "2026-10" 180, row "b" "2026-10" 181], 40),
   ("cap 41", "2026-10", [], 41),
   ("three builds done", "2026-10", [row "a" "2026-10" 5, row "b" "2026-10" 5, row "c" "2026-10" 5], 40),
   ("last month does not count", "2026-11", [row "a" "2026-10" 390], 40),
   ("last month still counts toward builds", "2026-11", [row "a" "2026-10" 150, row "b" "2026-10" 150, row "c" "2026-10" 90], 40),
   ("all three refusals", "2026-10", [row "a" "2026-10" 150, row "b" "2026-10" 150, row "c" "2026-10" 90], 41)]

def durVectors : List Nat := [0, 1, 59999, 60000, 60001, 119999, 120000, 2400000, 2400001]

def monthVectors : List Nat := [0, 951782400000, 1004572799999, 1004572800000, 1798761599999, 1798761600000]

private def rowJson (r : Row) : Json := Json.mkObj [("id", r.id), ("month", r.month), ("minutes", r.minutes)]

/-- The golden `packages/contracts/golden/ci/codemagic.jsonl`. -/
def goldenText : String :=
  let lines : List Json :=
    [Json.mkObj [("kind", "constants"), ("freeMinutes", freeMinutes), ("stopAt", stopAt), ("maxCapMin", maxCapMin), ("maxBuilds", maxBuilds),
       ("status", "CONFIRMED"), ("source", "codemagic.io/pricing checked 2026-10-21 (500 min/month); stopAt, maxCapMin, maxBuilds: task codemagic-pilot")]]
    ++ durVectors.map (fun (d : Nat) => Json.mkObj [("kind", "billed"), ("durMs", d), ("minutes", billedMin d)])
    ++ monthVectors.map (fun (t : Nat) => Json.mkObj [("kind", "month"), ("ms", t), ("month", monthOf t)])
    ++ triggerCases.map (fun (n, m, rs, c) => Json.mkObj [("kind", "trigger"), ("name", n), ("month", m), ("rows", Json.arr (rs.map rowJson).toArray),
         ("cap", c), ("used", usedIn m rs), ("refusals", Json.arr ((refusals m rs c).map (fun x => Json.str x.name)).toArray),
         ("mayTrigger", mayTrigger m rs c)])
    ++ statuses.map (fun (s : String) => Json.mkObj [("kind", "status"), ("status", s), ("exit", match exitOf s with | some n => Json.num n | none => Json.null)])
  String.join (lines.map (·.compress ++ "\n"))

#guard billedMin 0 == 1
#guard billedMin 60000 == 1
#guard billedMin 60001 == 2
#guard billedMin 2400000 == 40
#guard triggerCases.map (fun (_, m, rs, c) => mayTrigger m rs c) == [true, true, true, false, false, false, true, false, false]
#guard (refusals "2026-10" [row "a" "2026-10" 150, row "b" "2026-10" 150, row "c" "2026-10" 90] 41).map Refusal.name == ["minutes", "builds", "cap"]
#guard exitOf "finished" == some 0 && exitOf "building" == none && exitOf "timeout" == some 1

end Fw.Ci.Codemagic
