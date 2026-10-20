import Fw.Console.LandTier
/-!
# Land legs: the remote tier of the land lane, split into parallel jobs

The land lane (`.github/workflows/land.yml`) runs one matrix job per leg. Each leg builds fwcore, selects the checks the same way
(`fw checks --affected --tier remote`) and then does only its own part: a suites leg runs the remote checks it owns, the `check-sh`
leg runs the Lean gate script (`lean/scripts/check.sh`, off the Mac since task land-check-remote), an engine leg runs the preview
browser suite on its engine. The wall time of a land is the slowest leg, not the sum.

Measured (research/notes/2026/10-20-land-lane-speed.md): the serial remote suites cost 36 to 91 s, the two browser engines
170 s one after the other, and one more leg costs only runner minutes, because every leg pays the same setup in parallel.

What this module decides, each with its own theorems:
- which leg owns which remote check (`pickFor`): the three shards partition `remoteIds`, so no check is dropped or run twice;
- whether an engine leg runs (`engineRuns`): exactly when the selection holds the browser check (`browserRuns`);
- the verdict over all legs (`legsOk`): every leg passes, and a lane with no leg never passes;
- whether the legs' record vetoes a run GitHub called a success (`legsVeto`): a record without per-job conclusions says nothing, else `legsOk` decides.

Golden `packages/contracts/golden/console/land-legs.jsonl` and `lean/land-legs.txt` (the matrix); ops `console.landLeg` and
`console.landLegs` and `console.landLegsVeto` (`Fw.Wire.Console`).
-/
namespace Fw.Console.LandLegs
open Lean Fw.Console.LandTier

/-- The legs of the lane, in matrix order. -/
inductive Leg where
  | checkSh | suitesA | suitesB | chromium | webkit
deriving DecidableEq, Repr

/-- The leg name: the matrix value in land.yml. The engine legs are named like the engine the browser suite runs. -/
def Leg.name : Leg → String
  | .checkSh => "check-sh" | .suitesA => "suites-a" | .suitesB => "suites-b" | .chromium => "chromium" | .webkit => "playwright-webkit"

/-- Every leg, in matrix order. -/
def legs : List Leg := [.checkSh, .suitesA, .suitesB, .chromium, .webkit]

/-- The leg of a name, if any. -/
def Leg.ofName? (s : String) : Option Leg := legs.find? (fun l => l.name == s)

/-- The engine an engine leg runs the browser suite on; a suites leg has none. -/
def Leg.engine : Leg → Option String
  | .chromium => some "chromium" | .webkit => some "playwright-webkit" | _ => none

/-- Remote checks of suites leg A. Weighted by the measured times (runner 35 s, gate-breakpoints 11 s, the rest 1 to 3 s). -/
def shardA : List String :=
  ["apps/runner", "packages/gate-breakpoints", "packages/measure-chromium", "packages/engine-check", "packages/e2e-preview"]

/-- Remote checks of the `check-sh` leg: the Lean gate script alone (it builds and checks all of `lean/`, minutes of its own). -/
def shardC : List String := [checkShId]

/-- Remote checks of suites leg B (console-api 18 s, gh-budget 22 s). -/
def shardB : List String := ["apps/console-api", "packages/gh-budget"]

/-- The remote checks leg `l` runs out of the selected remote ids `sel`, in selection order. An engine leg runs none. -/
def pickFor (l : Leg) (sel : List String) : List String :=
  match l with
  | .checkSh => sel.filter (fun i => shardC.contains i)
  | .suitesA => sel.filter (fun i => shardA.contains i)
  | .suitesB => sel.filter (fun i => shardB.contains i)
  | .chromium | .webkit => []

/-- Does leg `l` run the browser suite for the selected ids `selected`? Only an engine leg, and only with the browser check selected. -/
def engineRuns (l : Leg) (selected : List String) : Bool := (l.engine).isSome && browserRuns selected

#guard shardA.length == 5
#guard shardB.length == 2
#guard shardC == ["check.sh"]
#guard pickFor .checkSh ["apps/console-api", "check.sh", "apps/runner"] == ["check.sh"]
#guard pickFor .suitesA ["apps/console-api", "apps/runner"] == ["apps/runner"]
#guard pickFor .suitesB ["apps/console-api", "apps/runner"] == ["apps/console-api"]

/-- The three shards together are the allowlist, each id once. -/
theorem shards_perm : (shardA ++ shardB ++ shardC).Perm remoteIds := by decide

/-- The shards have no repeats between them, so no check runs twice. -/
theorem shards_nodup : (shardA ++ shardB ++ shardC).Nodup := by decide

/-- No id is in both suites shards. -/
theorem shards_disjoint (id : String) : ¬ (id ∈ shardA ∧ id ∈ shardB) := by
  have h : (shardA ++ shardB).Nodup := by decide
  intro ⟨a, b⟩
  exact (List.nodup_append.1 h).2.2 id a id b rfl

/-- No id is in the `check-sh` shard and a suites shard. -/
theorem shardC_disjoint (id : String) : ¬ (id ∈ shardC ∧ (id ∈ shardA ∨ id ∈ shardB)) := by
  have hA : (shardA ++ shardC).Nodup := by decide
  have hB : (shardB ++ shardC).Nodup := by decide
  intro ⟨c, o⟩
  rcases o with a | b
  · exact (List.nodup_append.1 hA).2.2 id a id c rfl
  · exact (List.nodup_append.1 hB).2.2 id b id c rfl

/-- On the allowlist an id is in exactly one shard: the three tests agree on one of them. -/
theorem shard_one (id : String) (h : id ∈ remoteIds) :
    (shardA.contains id).toNat + (shardB.contains id).toNat + (shardC.contains id).toNat = 1 := by
  have all : ∀ i ∈ remoteIds, (shardA.contains i).toNat + (shardB.contains i).toNat + (shardC.contains i).toNat = 1 := by decide
  exact all id h

/-- How often an id occurs in a filtered list: as often as in the list when the filter keeps it, else never. -/
theorem count_filter_ite (p : String → Bool) (l : List String) (a : String) :
    (l.filter p).count a = if p a = true then l.count a else 0 := by
  by_cases h : p a = true
  · simp [List.count_filter h, h]
  · have : a ∉ l.filter p := by simp [List.mem_filter, h]
    simp [h, List.count_eq_zero.2 this]

/-- The legs together run every selected remote check once: no check is dropped, none runs twice. -/
theorem legs_cover (sel : List String) (h : ∀ i ∈ sel, i ∈ remoteIds) :
    (pickFor .checkSh sel ++ pickFor .suitesA sel ++ pickFor .suitesB sel).Perm sel := by
  rw [List.perm_iff_count]
  intro a
  simp only [pickFor, List.count_append, count_filter_ite]
  by_cases ha : a ∈ sel
  · have := shard_one a (h a ha)
    revert this
    cases shardA.contains a <;> cases shardB.contains a <;> cases shardC.contains a <;> simp
  · have : List.count a sel = 0 := List.count_eq_zero.2 ha
    simp [this]

/-- A selection without repeats stays without repeats across the legs: no check runs twice. -/
theorem legs_nodup (sel : List String) (h : ∀ i ∈ sel, i ∈ remoteIds) (nd : sel.Nodup) :
    (pickFor .checkSh sel ++ pickFor .suitesA sel ++ pickFor .suitesB sel).Nodup :=
  ((legs_cover sel h).nodup_iff).2 nd

/-- The `check-sh` leg owns only the Lean script. -/
theorem checkSh_sound (sel : List String) (x : String) (hx : x ∈ pickFor .checkSh sel) : x ∈ sel ∧ x = checkShId := by
  simp only [pickFor, List.mem_filter, List.contains_iff_mem, shardC, List.mem_singleton] at hx
  exact hx

/-- The `check-sh` leg runs the Lean script whenever the selection holds it. -/
theorem checkSh_runs_of_selected (sel : List String) (h : checkShId ∈ sel) : checkShId ∈ pickFor .checkSh sel := by
  simp [pickFor, shardC, h]

/-- A suites leg owns only checks of its own shard. -/
theorem suitesA_sound (sel : List String) (x : String) (hx : x ∈ pickFor .suitesA sel) : x ∈ sel ∧ x ∈ shardA := by
  simp only [pickFor, List.mem_filter, List.contains_iff_mem] at hx
  exact hx

/-- A suites leg owns only checks of its own shard. -/
theorem suitesB_sound (sel : List String) (x : String) (hx : x ∈ pickFor .suitesB sel) : x ∈ sel ∧ x ∈ shardB := by
  simp only [pickFor, List.mem_filter, List.contains_iff_mem] at hx
  exact hx

/-- The chromium leg runs no remote check. -/
theorem chromium_no_checks (sel : List String) : pickFor .chromium sel = [] := rfl

/-- The webkit leg runs no remote check. -/
theorem webkit_no_checks (sel : List String) : pickFor .webkit sel = [] := rfl

/-- The `check-sh` leg never runs the browser suite. -/
theorem checkSh_no_engine (selected : List String) : engineRuns .checkSh selected = false := rfl

/-- A suites leg never runs the browser suite. -/
theorem suitesA_no_engine (selected : List String) : engineRuns .suitesA selected = false := rfl

/-- A suites leg never runs the browser suite. -/
theorem suitesB_no_engine (selected : List String) : engineRuns .suitesB selected = false := rfl

/-- The chromium leg runs the browser suite when the selection holds the browser check. -/
theorem chromium_runs_of_selected (selected : List String) (h : browserId ∈ selected) : engineRuns .chromium selected = true := by
  simp [engineRuns, Leg.engine, browser_runs_of_selected selected h]

/-- The webkit leg runs the browser suite when the selection holds the browser check. -/
theorem webkit_runs_of_selected (selected : List String) (h : browserId ∈ selected) : engineRuns .webkit selected = true := by
  simp [engineRuns, Leg.engine, browser_runs_of_selected selected h]

/-- No engine leg runs when the selection lacks the browser check: no browser is installed for it. -/
theorem engines_idle_of_unselected (l : Leg) (selected : List String) (h : browserId ∉ selected) : engineRuns l selected = false := by
  simp [engineRuns, browser_idle_of_unselected selected h]

/-- The remote picks of a selection start the engine legs exactly when the whole selection does (`browser_runs_remote_pick`). -/
theorem engineRuns_remote_pick (l : Leg) (ids : List String) : engineRuns l (pick .onCi ids) = engineRuns l ids := by
  simp [engineRuns, browser_runs_remote_pick]

/-- The verdict over the results of all legs, `true` for a leg that passed: every leg passes, and no leg at all is not a pass. -/
def legsOk (results : List Bool) : Bool := !results.isEmpty && results.all id

/-- One failed leg fails the lane, whatever the others did. -/
theorem legsOk_fail_wins (rs : List Bool) (h : false ∈ rs) : legsOk rs = false := by
  have : rs.all id = false := by
    cases hh : rs.all id
    · rfl
    · have := List.all_eq_true.1 hh false h
      simp at this
  simp [legsOk, this]

/-- Every leg passing, with at least one leg, passes the lane. -/
theorem legsOk_all_pass (rs : List Bool) (ne : rs ≠ []) (h : ∀ r ∈ rs, r = true) : legsOk rs = true := by
  have hne : rs.isEmpty = false := by
    cases rs with
    | nil => exact absurd rfl ne
    | cons _ _ => rfl
  have hall : rs.all id = true := List.all_eq_true.2 (fun r hr => by simpa using h r hr)
  simp [legsOk, hne, hall]

/-- A lane with no leg result never passes (a record that lists no job proves nothing). -/
theorem legsOk_empty : legsOk [] = false := rfl

/-- The lane passes only if every leg did. -/
theorem legsOk_iff (rs : List Bool) : legsOk rs = true ↔ rs ≠ [] ∧ ∀ r ∈ rs, r = true := by
  cases rs with
  | nil => simp [legsOk]
  | cons a t => simp [legsOk, List.all_eq_true]

/-- Does the legs' record veto a run GitHub called a success? `none` is a record without per-job conclusions (the poller's cached facts,
a job without a conclusion) and `some []` one that lists no leg: both say nothing, so they do not veto.
Otherwise the run is vetoed exactly when `legsOk` refuses the legs. -/
def legsVeto : Option (List Bool) → Bool
  | none | some [] => false
  | some rs => !legsOk rs

/-- No per-job conclusions: no veto. -/
theorem legsVeto_none : legsVeto none = false := rfl

/-- A record that lists no leg: no veto. -/
theorem legsVeto_empty : legsVeto (some []) = false := rfl

/-- One failed leg vetoes the run, whatever the others did. -/
theorem legsVeto_fail (rs : List Bool) (h : false ∈ rs) : legsVeto (some rs) = true := by
  cases rs with
  | nil => simp at h
  | cons a t => simp [legsVeto, legsOk_fail_wins _ h]

/-- Every leg passing, with at least one leg: no veto. -/
theorem legsVeto_all_pass (rs : List Bool) (ne : rs ≠ []) (h : ∀ r ∈ rs, r = true) : legsVeto (some rs) = false := by
  cases rs with
  | nil => exact absurd rfl ne
  | cons a t => simp [legsVeto, legsOk_all_pass _ ne h]

/-- With at least one leg, the veto is exactly the refusal of `legsOk`. -/
theorem legsVeto_iff (rs : List Bool) (ne : rs ≠ []) : legsVeto (some rs) = !legsOk rs := by
  cases rs with
  | nil => exact absurd rfl ne
  | cons a t => rfl

#guard legsOk [true, true, true, true, true]
#guard !legsVeto none
#guard !legsVeto (some [])
#guard legsVeto (some [true, false])
#guard !legsVeto (some [true, true])
#guard !legsOk [true, false, true, true]
#guard !legsOk []

private def strs (xs : List String) : Json := .arr (xs.map Json.str).toArray

/-- One golden line of `console.landLeg`: leg and selected ids in, the checks the leg runs and whether its engine runs out. -/
def legLine (name : String) (l : Leg) (ids : List String) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "console.landLeg"), ("leg", .str l.name), ("ids", strs ids)]),
    ("response", Json.mkObj [("ids", strs (pickFor l (pick .onCi ids))), ("engine", .bool (engineRuns l ids))])]

/-- One golden line of `console.landLegs`. -/
def okLine (name : String) (rs : List Bool) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "console.landLegs"), ("results", .arr (rs.map Json.bool).toArray)]),
    ("response", Json.mkObj [("ok", .bool (legsOk rs))])]

/-- One golden line of `console.landLegsVeto`; `none` is a record without per-job conclusions (`null` on the wire). -/
def vetoLine (name : String) (rs : Option (List Bool)) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", .str "console.landLegsVeto"),
      ("results", match rs with | none => Json.null | some l => .arr (l.map Json.bool).toArray)]),
    ("response", Json.mkObj [("veto", .bool (legsVeto rs))])]

/-- The selections of the golden: all remote ids with and without the browser check, the local gates, and nothing. -/
def goldenSelections : List (String × List String) :=
  [("all remote", remoteIds), ("without browser", remoteIds.filter (· != browserId)),
   ("mixed with local", ["install", "check.sh", "apps/runner", "packages/difftest", "packages/gh-budget", "packages/e2e-preview"]),
   ("order kept", ["packages/gh-budget", "apps/console-api", "apps/runner"]), ("none", []),
   ("local only", ["install", "packages/difftest"])]

/-- The golden cases. -/
def cases : List Json :=
  (goldenSelections.flatMap fun (n, ids) => legs.map fun l => legLine s!"{l.name} of {n}" l ids) ++
  [okLine "all pass" [true, true, true, true, true], okLine "one fails" [true, false, true, true, true], okLine "the last fails" [true, true, true, true, false],
   okLine "all fail" [false, false], okLine "one leg passes" [true], okLine "no legs" [],
   vetoLine "no per-job conclusions: no veto" none, vetoLine "a record with no leg: no veto" (some []), vetoLine "all legs passed: no veto" (some [true, true, true, true, true]),
   vetoLine "one leg failed: veto" (some [true, false, true, true, true]), vetoLine "the last leg failed: veto" (some [true, true, true, true, false]),
   vetoLine "one leg, passed" (some [true]), vetoLine "one leg, not passed" (some [false])]

/-- The golden text: one compact line per case. -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-legs.jsonl"

/-- The matrix of land.yml: the leg names separated by one space. -/
def legsText : String := " ".intercalate (legs.map Leg.name) ++ "\n"

/-- The matrix file, relative to `lean/`. -/
def legsPath : System.FilePath := "land-legs.txt"

/-- Write the golden file and the matrix file. -/
def writeGolden : IO Unit := do
  IO.FS.writeFile goldenPath goldenText
  IO.FS.writeFile legsPath legsText

/-- Are the golden file and the matrix file the Lean output? -/
def checkGolden : IO Bool := do
  return (← IO.FS.readFile goldenPath) == goldenText && (← IO.FS.readFile legsPath) == legsText

end Fw.Console.LandLegs
