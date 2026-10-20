import Lean.Data.Json
/-!
# Land tiers: which checks run on this Mac and which on the CI land lane

`tier` is an allowlist: the heavy suites and the Lean gate script `check.sh` are `onCi`, every other check id is `onMac`. Golden:
`packages/contracts/golden/console/land-tier.jsonl`; op `console.landTier` (`Fw.Wire.Console`).
-/
namespace Fw.Console.LandTier
open Lean

/-- Where a check runs. -/
inductive Tier where
  | onMac | onCi
deriving DecidableEq, Repr

/-- The word printed for a tier. -/
def Tier.name : Tier → String
  | .onMac => "local" | .onCi => "remote"

/-- The id of the Lean gate script check (`sh lean/scripts/check.sh`); it is not a workspace package. -/
def checkShId : String := "check.sh"

/-- The heavy suites and the Lean gate script, in the id form of `candidateChecks` (the allowlist). -/
def remoteIds : List String :=
  ["apps/runner", "apps/console-api", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium",
   "packages/engine-check", "packages/e2e-preview", checkShId]

/-- The tier of a check id: `onCi` iff the id is on the allowlist. -/
def tier (id : String) : Tier := if remoteIds.contains id then .onCi else .onMac

/-- The ids of `ids` that run in tier `t`, in order. -/
def pick (t : Tier) (ids : List String) : List String := ids.filter (fun i => decide (tier i = t))

/-- The check whose selection also starts the browser suite (both engines) in the land lane. -/
def browserId : String := "packages/e2e-preview"

/-- Does the land lane run the browser suite? -/
def browserRuns (selected : List String) : Bool := selected.contains browserId

/-- Every id has exactly one tier. -/
theorem tier_exactly_one (id : String) :
    (tier id = .onMac ∧ tier id ≠ .onCi) ∨ (tier id = .onCi ∧ tier id ≠ .onMac) := by
  unfold tier
  split <;> simp

/-- The remote set equals the allowlist. -/
theorem remote_iff (id : String) : tier id = .onCi ↔ id ∈ remoteIds := by
  unfold tier
  split <;> simp_all

/-- Everything off the allowlist is local. -/
theorem local_iff (id : String) : tier id = .onMac ↔ id ∉ remoteIds := by
  unfold tier
  split <;> simp_all

/-- The two gates that are neither suites nor the Lean script, `install` and the reads scan, stay local. -/
theorem gates_local : tier "install" = .onMac ∧ tier "reads-scan" = .onMac := by decide

/-- The Lean gate script runs on the land lane, not on this Mac. -/
theorem check_sh_remote : tier checkShId = .onCi := by decide

/-- The allowlist has no repeats, so no suite is listed twice. -/
theorem remoteIds_nodup : remoteIds.Nodup := by decide

/-- A picked id is selected and has the tier. -/
theorem mem_pick (t : Tier) (ids : List String) (x : String) : x ∈ pick t ids ↔ x ∈ ids ∧ tier x = t := by
  simp [pick]

/-- The two tiers split the selected ids with none lost and none twice. -/
theorem pick_perm (ids : List String) : (pick .onMac ids ++ pick .onCi ids).Perm ids := by
  have h := List.filter_append_perm (fun i => decide (tier i = .onMac)) ids
  have e : ids.filter (fun i => !decide (tier i = .onMac)) = pick .onCi ids := by
    unfold pick
    apply List.filter_congr
    intro i _
    cases h : tier i <;> simp
  rw [e] at h
  exact h

/-- No id is in both tiers. -/
theorem pick_disjoint (ids : List String) (x : String) : ¬ (x ∈ pick .onMac ids ∧ x ∈ pick .onCi ids) := by
  rw [mem_pick, mem_pick]
  intro ⟨⟨_, a⟩, ⟨_, b⟩⟩
  rw [a] at b
  cases b

/-- The browser suite runs when the selection contains its check. -/
theorem browser_runs_of_selected (ids : List String) (h : browserId ∈ ids) : browserRuns ids = true := by
  simp [browserRuns, h]

/-- The browser suite does not run when the selection lacks its check. -/
theorem browser_idle_of_unselected (ids : List String) (h : browserId ∉ ids) : browserRuns ids = false := by
  simp [browserRuns, h]

/-- The browser check is in the remote tier, so the lane that runs the remote tier is the one that can start it. -/
theorem browser_is_remote : tier browserId = .onCi := by decide

/-- Splitting by tier loses no decision: the remote picks start the browser suite exactly when the whole selection does. -/
theorem browser_runs_remote_pick (ids : List String) : browserRuns (pick .onCi ids) = browserRuns ids := by
  by_cases h : browserId ∈ ids
  · rw [browser_runs_of_selected _ h, browser_runs_of_selected]
    exact (mem_pick _ _ _).2 ⟨h, browser_is_remote⟩
  · rw [browser_idle_of_unselected _ h, browser_idle_of_unselected]
    intro hm
    exact h ((mem_pick _ _ _).1 hm).1

#guard browserRuns ["apps/runner", "packages/e2e-preview"]
#guard !browserRuns ["apps/runner", "packages/gh-budget"]
#guard !browserRuns []

/-- The packages whose tests run the `fwcore` binary (the TS list `FWCORE_USERS` in `apps/runner/src/land.ts` equals it; a test pins that). -/
def fwcoreUsers : List String :=
  ["apps/console-api", "apps/runner", "packages/difftest", "packages/e2e-preview", "packages/engine-check",
   "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium", "packages/measure-webkit",
   "packages/measure-wktr"]

/-- Does the check run the `fwcore` binary? -/
def isCoreUser (id : String) : Bool := fwcoreUsers.contains id

/-- One step of the local plan: the `fwcore` build, or a check by id. -/
inductive Step where
  | build
  | check (id : String)

/-- Does the local plan start with the `fwcore` build? Yes iff no build ran yet (`built = false`) and a local check runs the binary. -/
def needsBuild (built : Bool) (ids : List String) : Bool := !built && ids.any isCoreUser

/-- The local plan: the build first when needed, then the local checks in order. -/
def localPlan (built : Bool) (ids : List String) : List Step :=
  (if needsBuild built ids then [Step.build] else []) ++ ids.map Step.check

/-- The build is needed when none ran and some local check runs the binary. -/
theorem needsBuild_of_user (ids : List String) (u : String) (hu : u ∈ ids) (hc : isCoreUser u = true) :
    needsBuild false ids = true := by
  simp only [needsBuild, Bool.not_false, Bool.true_and, List.any_eq_true]
  exact ⟨u, hu, hc⟩

/-- A build that already ran needs no second one. -/
theorem no_build_when_built (ids : List String) : needsBuild true ids = false := by
  simp [needsBuild]

/-- With no local check that runs the binary, no build step is planned. -/
theorem no_build_without_user (built : Bool) (ids : List String) (h : ∀ u ∈ ids, isCoreUser u = false) :
    needsBuild built ids = false := by
  simp only [needsBuild, Bool.and_eq_false_iff, Bool.not_eq_false', List.any_eq_false]
  exact Or.inr (fun u hu => by simp [h u hu])

/-- Every local check that runs the binary has a build step before it, unless a build already ran. This holds for every local
check, not only after a change to the build's inputs (a golden-only change selects `packages/measure-webkit`). -/
theorem core_user_has_build (built : Bool) (ids : List String) (u : String) (hu : u ∈ ids) (hc : isCoreUser u = true) :
    built = true ∨ ∃ i j : Nat, i < j ∧ (localPlan built ids)[i]? = some Step.build ∧ (localPlan built ids)[j]? = some (Step.check u) := by
  cases built with
  | true => exact Or.inl rfl
  | false =>
    refine Or.inr ?_
    obtain ⟨k, hk⟩ := List.mem_iff_getElem?.1 hu
    refine ⟨0, k + 1, by omega, ?_, ?_⟩ <;> simp [localPlan, needsBuild_of_user ids u hu hc, hk]

#guard needsBuild false ["packages/measure-webkit"]
#guard !needsBuild true ["packages/measure-webkit"]
#guard !needsBuild false ["install", "reads-scan", "packages/contracts"]

#guard remoteIds.length == 8
#guard tier "apps/runner" == .onCi
#guard tier "packages/difftest" == .onMac
#guard pick .onCi ["install", "apps/runner", "check.sh", "packages/gh-budget"] == ["apps/runner", "check.sh", "packages/gh-budget"]
#guard pick .onMac ["install", "apps/runner", "check.sh", "reads-scan"] == ["install", "reads-scan"]

/-- The ids a golden case lists: the gates, the allowlist and a few local suites and a stranger. -/
def goldenIds : List String :=
  ["install", "check.sh", "reads-scan"] ++ remoteIds ++
  ["apps/console-web", "apps/site", "packages/contracts", "packages/difftest", "packages/measure-webkit",
   "packages/measure-wktr", "packages/visual-diff", "packages/not-a-package"]

private def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- One golden line. -/
def line (name : String) (ids : List String) (built : Bool := false) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj [("op", .str "console.landTier"), ("ids", strs ids), ("built", .bool built)]),
    ("response", Json.mkObj [("local", strs (pick .onMac ids)), ("remote", strs (pick .onCi ids)),
      ("browser", .bool (browserRuns ids)), ("build", .bool (needsBuild built (pick .onMac ids)))])]

/-- The golden cases: one per id, the whole list, and the empty list. -/
def cases : List Json :=
  goldenIds.map (fun i => line s!"tier of {i}" [i]) ++ [line "all ids" goldenIds, line "no ids" [],
    line "selection order is kept" ["packages/gh-budget", "install", "apps/runner", "check.sh"],
    line "golden-only change: measure-webkit is local, the build is planned" ["install", "check.sh", "packages/measure-webkit", "reads-scan"],
    line "a build that already ran is not planned again" ["install", "packages/measure-webkit"] true,
    line "no local fwcore user, no build" ["install", "packages/contracts", "reads-scan"]]

/-- What the land lane says about one check. -/
inductive Lane where
  | pass | fail | skipped | unknown
deriving DecidableEq, Repr

/-- The word after `VERDICT` in the lane output. -/
def Lane.name : Lane → String
  | .pass => "pass" | .fail => "fail" | .skipped => "skipped" | .unknown => "unknown"

/-- The lane verdict of a check: a failing exit fails; a passing run whose summary was not recognised (`none`) is `unknown`;
a passing fwcore user that skipped a test (or left a todo, counted with skips) is `skipped`. Only `pass` passes. -/
def laneVerdict (exitOk coreUser : Bool) (skipped : Option Nat) : Lane :=
  if !exitOk then .fail else
    match skipped with
    | none => .unknown
    | some n => if coreUser && decide (0 < n) then .skipped else .pass

/-- A lane passes only on `pass`. -/
def Lane.ok : Lane → Bool
  | .pass => true | _ => false

/-- A failing exit fails the check, whatever was skipped. -/
theorem laneVerdict_exit_fail (c : Bool) (n : Option Nat) : laneVerdict false c n = .fail := by
  simp [laneVerdict]

/-- A summary the parser did not recognise is not a pass, for every suite. -/
theorem laneVerdict_unknown (c : Bool) : (laneVerdict true c none).ok = false := by
  simp [laneVerdict, Lane.ok]

/-- A skipped test of an fwcore user fails the lane even when the exit was 0. -/
theorem laneVerdict_core_skip (n : Nat) (h : 0 < n) : (laneVerdict true true (some n)).ok = false := by
  simp [laneVerdict, Lane.ok, h]

/-- A suite that does not run fwcore may skip tests. -/
theorem laneVerdict_other_skip (n : Nat) : laneVerdict true false (some n) = .pass := by
  simp [laneVerdict]

/-- No skip, exit 0: pass. -/
theorem laneVerdict_clean (c : Bool) : laneVerdict true c (some 0) = .pass := by
  simp [laneVerdict]

/-- The lane passes iff the exit is 0, the summary was recognised, and no fwcore user skipped. -/
theorem laneVerdict_ok_iff (e c : Bool) (s : Option Nat) :
    (laneVerdict e c s).ok = true ↔ e = true ∧ ∃ n, s = some n ∧ ¬ (c = true ∧ 0 < n) := by
  cases e <;> cases c <;> rcases s with _ | n <;> simp [laneVerdict, Lane.ok] <;>
    by_cases h : 0 < n <;> simp [h] <;> omega

/-- The checks that run no test framework and print no summary line (only the Lean gate script). Their exit code is the whole
verdict, so nothing was skipped. -/
def summaryless : List String := [checkShId]

/-- The skipped count the lane verdict uses: `0` for a check without a summary line, else what the summary reported. -/
def effectiveSkipped (id : String) (n : Option Nat) : Option Nat := if summaryless.contains id then some 0 else n

/-- The Lean gate script is summaryless. -/
theorem check_sh_summaryless : summaryless.contains checkShId = true := by decide

/-- A summaryless check has `skipped = 0` whatever the parser found. -/
theorem effectiveSkipped_summaryless (id : String) (n : Option Nat) (h : summaryless.contains id = true) :
    effectiveSkipped id n = some 0 := by
  simp only [effectiveSkipped, h]
  simp

/-- Any other check keeps what its summary reported (an unrecognised summary stays `none`, so `unknown`). -/
theorem effectiveSkipped_other (id : String) (n : Option Nat) (h : summaryless.contains id = false) :
    effectiveSkipped id n = n := by
  simp only [effectiveSkipped, h]
  simp

/-- A summaryless check that exits 0 passes. -/
theorem summaryless_exit_pass (id : String) (c : Bool) (n : Option Nat) (h : summaryless.contains id = true) :
    laneVerdict true c (effectiveSkipped id n) = .pass := by
  simp [effectiveSkipped_summaryless id n h, laneVerdict]

#guard !(laneVerdict true true (some 2)).ok
#guard (laneVerdict true false (some 2)).ok
#guard !(laneVerdict true false none).ok

/-- One lane golden line. -/
def laneLine (name : String) (e c : Bool) (n : Option Nat) (id : String := "") : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj [("op", .str "console.landLane"), ("check", .str id), ("exitOk", .bool e), ("coreUser", .bool c), ("skipped", match n with | some k => .num k | none => .null)]),
    ("response", Json.mkObj [("verdict", .str (laneVerdict e c (effectiveSkipped id n)).name), ("ok", .bool (laneVerdict e c (effectiveSkipped id n)).ok),
      ("skipped", match effectiveSkipped id n with | some k => .num k | none => .null)])]

/-- The lane cases: every branch of `laneVerdict`. -/
def laneCases : List Json :=
  [laneLine "exit failed" false true (some 0), laneLine "exit failed, others skipped" false false (some 3),
   laneLine "exit failed, summary unknown" false true none,
   laneLine "fwcore user skipped a test" true true (some 1), laneLine "other suite skipped a test" true false (some 1),
   laneLine "clean fwcore user" true true (some 0), laneLine "clean other suite" true false (some 0),
   laneLine "summary not recognised, fwcore user" true true none, laneLine "summary not recognised, other suite" true false none,
   laneLine "summaryless check.sh passes without a summary" true false none checkShId,
   laneLine "summaryless check.sh still fails on a failing exit" false false none checkShId]

/-- The golden file text. -/
def goldenText : String := String.join ((cases ++ laneCases).map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-tier.jsonl"


/-- The pnpm filter selector of a check id: the workspace package named like the last path segment, with its dependencies. -/
def selector (id : String) : String := "@fw/" ++ (id.splitOn "/").getLast! ++ "..."

/-- The remote ids that are workspace packages: every remote id but the Lean script. -/
def suiteIds : List String := remoteIds.filter (· != checkShId)

/-- The selectors the land lane installs: one per remote suite, in order (the Lean script has no package). -/
def filterList : List String := suiteIds.map selector

/-- One selector per remote suite. -/
theorem filterList_length : filterList.length = remoteIds.length - 1 := by
  decide

/-- Every remote suite has its selector in the installed set, so a suite added to the allowlist is installed. -/
theorem selector_mem (id : String) (h : id ∈ remoteIds) (hs : id ≠ checkShId) : selector id ∈ filterList := by
  simp only [filterList, suiteIds, List.mem_map, List.mem_filter]
  exact ⟨id, ⟨h, by simpa using hs⟩, rfl⟩

#guard filterList.head? == some "@fw/runner..."
#guard filterList.length == 7

/-- The text of `lean/land-filter.txt`: the selectors separated by one space, one line. -/
def filterText : String := " ".intercalate filterList ++ "\n"

/-- The filter file, relative to `lean/`. -/
def filterPath : System.FilePath := "land-filter.txt"

/-- Write the golden file and the filter file. -/
def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText
  IO.FS.writeFile filterPath filterText

/-- Are the golden file and the filter file the Lean output? -/
def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile filterPath) == filterText

end Fw.Console.LandTier
