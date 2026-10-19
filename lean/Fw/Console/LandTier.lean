import Lean.Data.Json
/-!
# Land tiers: which checks run on this Mac and which on the CI land lane

`tier` is an allowlist: the heavy suites are `onCi`, every other check id is `onMac`. Golden:
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

/-- The heavy suites, in the id form of `candidateChecks` (the allowlist). -/
def remoteIds : List String :=
  ["apps/runner", "apps/console-api", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium",
   "packages/engine-check"]

/-- The tier of a check id: `onCi` iff the id is on the allowlist. -/
def tier (id : String) : Tier := if remoteIds.contains id then .onCi else .onMac

/-- The ids of `ids` that run in tier `t`, in order. -/
def pick (t : Tier) (ids : List String) : List String := ids.filter (fun i => decide (tier i = t))

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

/-- The three gates that are not suites stay local. -/
theorem gates_local : tier "install" = .onMac ∧ tier "check.sh" = .onMac ∧ tier "reads-scan" = .onMac := by decide

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

#guard remoteIds.length == 6
#guard tier "apps/runner" == .onCi
#guard tier "packages/difftest" == .onMac
#guard pick .onCi ["install", "apps/runner", "check.sh", "packages/gh-budget"] == ["apps/runner", "packages/gh-budget"]

/-- The ids a golden case lists: the gates, the allowlist and a few local suites and a stranger. -/
def goldenIds : List String :=
  ["install", "check.sh", "reads-scan"] ++ remoteIds ++
  ["apps/console-web", "apps/site", "packages/contracts", "packages/difftest", "packages/measure-webkit",
   "packages/measure-wktr", "packages/visual-diff", "packages/not-a-package"]

private def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- One golden line. -/
def line (name : String) (ids : List String) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj [("op", .str "console.landTier"), ("ids", strs ids)]),
    ("response", Json.mkObj [("local", strs (pick .onMac ids)), ("remote", strs (pick .onCi ids))])]

/-- The golden cases: one per id, the whole list, and the empty list. -/
def cases : List Json :=
  goldenIds.map (fun i => line s!"tier of {i}" [i]) ++ [line "all ids" goldenIds, line "no ids" [],
    line "selection order is kept" ["packages/gh-budget", "install", "apps/runner", "check.sh"]]

/-- What the land lane says about one check. -/
inductive Lane where
  | pass | fail | skipped
deriving DecidableEq, Repr

/-- The word after `VERDICT` in the lane output. -/
def Lane.name : Lane → String
  | .pass => "pass" | .fail => "fail" | .skipped => "skipped"

/-- The lane verdict of a check: a failing exit fails; a passing fwcore user that skipped a test is `skipped`, which fails the lane. -/
def laneVerdict (exitOk coreUser : Bool) (skipped : Nat) : Lane :=
  if !exitOk then .fail else if coreUser && decide (0 < skipped) then .skipped else .pass

/-- A lane passes only on `pass`. -/
def Lane.ok : Lane → Bool
  | .pass => true | _ => false

/-- A failing exit fails the check, whatever was skipped. -/
theorem laneVerdict_exit_fail (c : Bool) (n : Nat) : laneVerdict false c n = .fail := by
  simp [laneVerdict]

/-- A skipped test of an fwcore user fails the lane even when the exit was 0. -/
theorem laneVerdict_core_skip (n : Nat) (h : 0 < n) : (laneVerdict true true n).ok = false := by
  simp [laneVerdict, Lane.ok, h]

/-- A suite that does not run fwcore may skip tests. -/
theorem laneVerdict_other_skip (n : Nat) : laneVerdict true false n = .pass := by
  simp [laneVerdict]

/-- No skip, exit 0: pass. -/
theorem laneVerdict_clean (c : Bool) : laneVerdict true c 0 = .pass := by
  simp [laneVerdict]

/-- The lane passes iff the exit is 0 and no fwcore user skipped. -/
theorem laneVerdict_ok_iff (e c : Bool) (n : Nat) :
    (laneVerdict e c n).ok = true ↔ e = true ∧ ¬ (c = true ∧ 0 < n) := by
  cases e <;> cases c <;> by_cases h : 0 < n <;> simp [laneVerdict, Lane.ok, h]

#guard !(laneVerdict true true 2).ok
#guard (laneVerdict true false 2).ok

/-- One lane golden line. -/
def laneLine (name : String) (e c : Bool) (n : Nat) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj [("op", .str "console.landLane"), ("exitOk", .bool e), ("coreUser", .bool c), ("skipped", .num n)]),
    ("response", Json.mkObj [("verdict", .str (laneVerdict e c n).name), ("ok", .bool (laneVerdict e c n).ok)])]

/-- The lane cases: every branch of `laneVerdict`. -/
def laneCases : List Json :=
  [laneLine "exit failed" false true 0, laneLine "exit failed, others skipped" false false 3,
   laneLine "fwcore user skipped a test" true true 1, laneLine "other suite skipped a test" true false 1,
   laneLine "clean fwcore user" true true 0, laneLine "clean other suite" true false 0]

/-- The golden file text. -/
def goldenText : String := String.join ((cases ++ laneCases).map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-tier.jsonl"


/-- The pnpm filter selector of a check id: the workspace package named like the last path segment, with its dependencies. -/
def selector (id : String) : String := "@fw/" ++ (id.splitOn "/").getLast! ++ "..."

/-- The selectors the land lane installs: one per remote id, in order. -/
def filterList : List String := remoteIds.map selector

/-- One selector per remote suite. -/
theorem filterList_length : filterList.length = remoteIds.length := by
  simp [filterList]

/-- Every remote suite has its selector in the installed set, so a suite added to the allowlist is installed. -/
theorem selector_mem (id : String) (h : id ∈ remoteIds) : selector id ∈ filterList := by
  simp only [filterList, List.mem_map]
  exact ⟨id, h, rfl⟩

#guard filterList.head? == some "@fw/runner..."
#guard filterList.length == 6

/-- The text of `.github/land-filter.txt`: the selectors separated by one space, one line. -/
def filterText : String := " ".intercalate filterList ++ "\n"

/-- The filter file, relative to `lean/`. -/
def filterPath : System.FilePath := "../.github/land-filter.txt"

/-- Write the golden file and the filter file. -/
def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText
  IO.FS.writeFile filterPath filterText

/-- Are the golden file and the filter file the Lean output? -/
def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile filterPath) == filterText

end Fw.Console.LandTier
