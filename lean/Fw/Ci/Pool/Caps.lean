import Lean.Data.Json
/-!
# Per-lane macOS job time caps (task `pool-caps`): the cap of a lane is 1.3 x its measured p90 success wall, rounded up
-/
namespace Fw.Ci.Pool.Caps

open Lean (Json)

/-- The cap in whole minutes of a p90 wall given in tenths of a minute: the least `c` with `13 * p90dm ≤ 100 * c`. -/
def capMin (p90dm : Nat) : Nat := (13 * p90dm + 99) / 100

theorem cap_ge_scaled (p : Nat) : 13 * p ≤ 100 * capMin p := by unfold capMin; omega

theorem cap_least (p : Nat) : 100 * capMin p < 13 * p + 100 := by unfold capMin; omega

theorem cap_ge_p90 (p : Nat) : p ≤ 10 * capMin p := by have := cap_ge_scaled p; omega

theorem cap_mono {p q : Nat} (h : p ≤ q) : capMin p ≤ capMin q := Nat.div_le_div_right (by omega)

/-- Below this many measured successes a lane's p90 is `thin` and is re-derived once the lane reaches it. -/
def minSamples : Nat := 10

/-- One capped macOS job: its lane, workflow file, job id, success count and p90 wall in tenths of a minute. -/
structure Row where
  lane : String
  file : String
  job : String
  n : Nat
  p90dm : Nat
deriving DecidableEq, Repr

/-- The job's `timeout-minutes`. -/
def Row.cap (r : Row) : Nat := capMin r.p90dm

/-- Whether the p90 rests on fewer than `minSamples` successes. -/
def Row.thin (r : Row) : Bool := r.n < minSamples

/-- Where the p90 values were measured. -/
def source : String :=
  "research/notes/2026/10-20-macos-pool-v2.md: jobs-an.json, 305 jobs 10-17..10-20, successes only, linear p90 rounded up to 0.1 min"

/-- A sorted insert; the p90 below sorts a short list of walls with it. -/
def insertNat (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insertNat x ys

/-- The walls in ascending order. -/
def sortNat (xs : List Nat) : List Nat := xs.foldr insertNat []

/-- The linear p90 of walls in seconds, in tenths of a minute rounded up: rank `0.9 (n - 1)`, interpolated between its two
neighbours (the rule the other rows use). -/
def p90dmOfSec (xs : List Nat) : Nat :=
  let s := sortNat xs
  let i := 9 * (s.length - 1) / 10
  let r := 9 * (s.length - 1) % 10
  let lo := s.getD i 0
  let hi := s.getD (i + 1) lo
  (10 * lo + r * (hi - lo) + 59) / 60

/-- The `probe-apple` legs of the retry era (task `probe-apple-cap`): (job wall in seconds, extra candidate passes the leg ran).
Runs 40122382227 (legs 390_641 and 640_1280: 749 s with 2 extra, 686 s with 0), 40125557073 (681 s with 0, 737 s with 1) and
40127042262 (833 s with 8, 734 s with 3), all successes, from `gh run view <id> --json jobs` (startedAt to completedAt). -/
def probeWalls : List (Nat × Nat) := [(749, 2), (686, 0), (681, 0), (737, 1), (833, 8), (734, 3)]

/-- Seconds of one extra candidate pass on the Mac: the eight extra reps of the 8-extra leg of run 40127042262 start 18.1 to 18.5
s apart (job log), rounded up. -/
def probePassSec : Nat := 19

/-- The wall of a `probe-apple` leg with no extra pass: the greatest wall of the sample less its extra passes. -/
def probeBaseSec : Nat := (probeWalls.map fun (w, e) => w - e * probePassSec).foldl max 0

/-- The worst-case wall in seconds of a leg of `widths` widths when every width runs `extraCap` extra passes. -/
def legWorstSec (widths extraCap : Nat) : Nat := probeBaseSec + widths * extraCap * probePassSec

/-- Where the `trajectory-probe` p90 was measured (task `probe-apple-cap`, replacing the pre-retry sample of task
`trajectory-probe-speed`): the six `probeWalls` legs, successes only, linear p90 of 681, 686, 734, 737, 749, 833 s is 791 s,
rounded up to 13.2 min. The pre-retry legs (9.1, 9.2, 10.9, 11.3 min) did not run the per-width settle retry and are not counted. -/
def probeSource : String :=
  "runs 40122382227, 40125557073 and 40127042262 (task probe-apple-cap): the six probe-apple width legs of the settle-retry era, successes only, linear p90 rounded up to 0.1 min"

/-- Where the `smoothness-webkit-*` p90 values were measured (task `smoothness-webkit-cadence`): the one job per leg of runs 39612238445,
39617081415 and 39624728525, successes only. The mac jobs took 9.43, 10.40 and 11.22 min, linear p90 11.056, rounded up to 11.1 min; the
sim jobs 29.12, 34.05 and 34.15 min, linear p90 34.13, rounded up to 34.2 min. -/
def smoothSource : String :=
  "runs 39612238445, 39617081415 and 39624728525 (task smoothness-webkit-cadence): one webkit-mac and one webkit-sim job each, wall of the job, successes only, linear p90 rounded up to 0.1 min (thin until 10 successes)"

/-- The capped macOS jobs, one per lane. -/
def rows : List Row :=
  [⟨"wktr", "wktr.yml", "wktr", 93, 119⟩,
   ⟨"wktr-fixtures", "wktr-fixtures.yml", "fixtures", 35, 161⟩,
   ⟨"sim-speed", "sim-speed.yml", "probe", 20, 124⟩,
   ⟨"engine-premises", "engine-premises.yml", "webkit", 15, 56⟩,
   ⟨"gate-gaps", "gate-gaps.yml", "collect-macos", 3, 198⟩,
   ⟨"trajectory-probe", "trajectory-probe.yml", "probe-apple", probeWalls.length, p90dmOfSec (probeWalls.map (·.1))⟩,
   ⟨"smoothness-webkit-mac", "smoothness.yml", "webkit-mac", 3, 111⟩,
   ⟨"smoothness-webkit-sim", "smoothness.yml", "webkit-sim", 3, 342⟩]

def excluded : List (String × String) :=
  [("path-pix.yml", "path-pix-lanes"), ("toolbar-throttle.yml", "toolbar-throttle-probe"), ("webkit-sim.yml", "webkit-sim-failfast"), ("chrome-crash-probe.yml", "chrome-crash-platforms"), ("font-fidelity.yml", "counts-font-fidelity")]

def capOf (file job : String) : Option Nat := (rows.find? fun r => r.file == file && r.job == job).map (·.cap)

theorem rows_cap_ge_p90 : ∀ r ∈ rows, r.p90dm ≤ 10 * r.cap := fun r _ => cap_ge_p90 r.p90dm

theorem rows_jobs_nodup : (rows.map fun r => (r.file, r.job)).Nodup := by decide

theorem rows_lanes_nodup : (rows.map (·.lane)).Nodup := by decide

theorem excluded_disjoint : ∀ e ∈ excluded, e.1 ∉ rows.map (·.file) := by decide

theorem thin_lanes : (rows.filter (·.thin)).map (·.lane) = ["gate-gaps", "trajectory-probe", "smoothness-webkit-mac", "smoothness-webkit-sim"] := by decide

theorem caps_eq : rows.map (fun r => (r.lane, r.cap)) =
    [("wktr", 16), ("wktr-fixtures", 21), ("sim-speed", 17), ("engine-premises", 8), ("gate-gaps", 26),
      ("trajectory-probe", 18), ("smoothness-webkit-mac", 15), ("smoothness-webkit-sim", 45)] := by decide

/-- The retry-era sample has six legs: below `minSamples`, so the lane stays thin. -/
theorem probe_walls_n : probeWalls.length = 6 := by decide

/-- The linear p90 of the retry-era legs is 13.2 min. -/
theorem probe_p90 : p90dmOfSec (probeWalls.map (·.1)) = 132 := by decide

/-- The wall of a leg with no extra pass is at most 718 s: the leg of run 40125557073 with one extra pass, less that pass. -/
theorem probe_base : probeBaseSec = 718 := by decide

/-- The wall model covers every leg of the sample: base plus its extra passes at 19 s. -/
theorem probe_model_covers : ∀ p ∈ probeWalls, p.1 ≤ probeBaseSec + p.2 * probePassSec := by decide

/-- The cap of `probe-apple` is 18 min. -/
theorem probe_cap : capOf "trajectory-probe.yml" "probe-apple" = some 18 := by decide

/-- A leg of two widths that runs 8 extra passes at each stays under the `probe-apple` cap (1022 s of 1080 s). -/
theorem probe_worst_under_cap :
    legWorstSec 2 8 = 1022 ∧ legWorstSec 2 8 ≤ 60 * ((capOf "trajectory-probe.yml" "probe-apple").getD 0) := by decide

/-- The worst-case leg wall grows with the extra passes per width. -/
theorem legWorstSec_mono {w : Nat} {a b : Nat} (h : a ≤ b) : legWorstSec w a ≤ legWorstSec w b := by
  unfold legWorstSec
  have := Nat.mul_le_mul_right probePassSec (Nat.mul_le_mul_left w h)
  omega

/-- The p90 values (tenths of a minute) of the golden's `vector` rows. -/
def vectors : List Nat := [0, 1, 56, 76, 77, 112, 119, 124, 132, 161, 198, 289, 300, 1000]

private def capJson (r : Row) : Json :=
  Json.mkObj [("kind", "cap"), ("lane", r.lane), ("file", r.file), ("job", r.job), ("n", r.n), ("p90dm", r.p90dm),
    ("capMin", r.cap), ("thin", r.thin), ("status", "MEASURED"),
    ("source", if r.lane == "trajectory-probe" then probeSource
      else if r.lane.startsWith "smoothness-webkit" then smoothSource else source)]

/-- The golden `packages/contracts/golden/ci/pool-caps.jsonl`: the cap rows, the excluded workflows, the `capMin` vectors. -/
def goldenText : String :=
  let lines : List Json := rows.map capJson
    ++ excluded.map (fun (e : String × String) => Json.mkObj [("kind", "excluded"), ("file", e.1), ("task", e.2)])
    ++ vectors.map (fun (p : Nat) => Json.mkObj [("kind", "vector"), ("p90dm", p), ("capMin", capMin p)])
  String.join (lines.map (·.compress ++ "\n"))

#guard capMin 289 == 38
#guard capMin 0 == 0
#guard capMin 1 == 1
#guard capMin 76 == 10
#guard capMin 77 == 11
#guard [119, 161, 124, 56, 198, 132].map capMin == [16, 21, 17, 8, 26, 18]
#guard capOf "trajectory-probe.yml" "probe-apple" == some 18
#guard capOf "trajectory-probe.yml" "merge-apple" == none
#guard capOf "wktr.yml" "wktr" == some 16
#guard capOf "gate-gaps.yml" "collect-macos" == some 26
#guard capOf "gate-gaps.yml" "judge" == none
#guard capOf "webkit-sim.yml" "sim" == none

end Fw.Ci.Pool.Caps
