import Lean.Data.Json
/-!
# Does a cited CI run carry the flag it is cited for (op `gate.runCite`)
-/
namespace Fw.Gate.RunCite
open Lean

/-- The `key=value` pairs of a URL search such as `?preset=v2-proved&fw=a:b,c:d`. -/
def params (search : String) : List (String × String) :=
  let body := match search.toList with
    | '?' :: rest => String.ofList rest
    | _ => search
  (body.splitOn "&").filterMap fun p =>
    match p.splitOn "=" with
    | [] | [""] => none
    | [k] => some (k, "")
    | k :: rest => some (k, "=".intercalate rest)

/-- The flag entries (`part:variant`, maybe `@impl`) of a search's `fw` parameters. -/
def fwOf (search : String) : List String :=
  (params search).flatMap fun (k, v) => if k == "fw" then (v.splitOn ",").filter (· != "") else []

/-- The preset names of a search's `preset` parameters. -/
def presetOf (search : String) : List String :=
  (params search).filterMap fun (k, v) => if k == "preset" && v != "" then some v else none

/-- What a run's own artifacts say: the search of every arm (`""` = no query), or why there is nothing to read. -/
inductive Facts where
  | arms (searches : List String)
  | missing (why : String)
  deriving DecidableEq, Repr

/-- The verdict on one citation of a run for a flag. -/
inductive Verdict where
  | match
  | mismatch (carried : List String)
  | unknown (why : String)
  deriving DecidableEq, Repr

/-- Every flag entry any arm carried, first occurrence first. -/
def carried (as : List String) : List String := (as.flatMap fwOf).eraseDups

/-- Every preset any arm carried, first occurrence first. -/
def presets (as : List String) : List String := (as.flatMap presetOf).eraseDups

/-- The `part:variant` of a flag entry, without its `@impl`. -/
def variantOf (entry : String) : String := (entry.splitOn "@").headD entry

/-- A carried entry stands for the cited flag: equal, or equal once the entry's `@impl` is dropped. -/
def covers (entry flag : String) : Bool := entry == flag || variantOf entry == flag

/-- Why a run with no arm is unknown. -/
def noArm : String := "the run's artifacts record no arm"

/-- Why a run that carried presets but not the flag is unknown. -/
def presetWhy (ps : List String) : String :=
  s!"the run carried preset {", ".intercalate ps}, and its artifacts do not list the preset's flags"

/-- The verdict on citing a run with facts `f` for `flag`. -/
def verdict : Facts → String → Verdict
  | .missing why, _ => .unknown why
  | .arms as, flag =>
    if as.isEmpty then .unknown noArm
    else if (carried as).any (covers · flag) then .match
    else if (presets as).isEmpty then .mismatch (carried as)
    else .unknown (presetWhy (presets as))

theorem mem_carried (as : List String) (e : String) : e ∈ carried as ↔ ∃ s ∈ as, e ∈ fwOf s := by
  simp [carried, List.mem_eraseDups, List.mem_flatMap]

theorem any_carried (as : List String) (flag : String) :
    (carried as).any (covers · flag) = true ↔ ∃ s ∈ as, ∃ e ∈ fwOf s, covers e flag = true := by
  simp only [List.any_eq_true, mem_carried]
  constructor
  · rintro ⟨e, ⟨s, hs, he⟩, hc⟩; exact ⟨s, hs, e, he, hc⟩
  · rintro ⟨s, hs, e, he, hc⟩; exact ⟨e, ⟨s, hs, he⟩, hc⟩

theorem presets_nil_iff (as : List String) : presets as = [] ↔ ∀ s ∈ as, presetOf s = [] := by
  constructor
  · intro h s hs
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    have : p ∈ presets as := by simp [presets, List.mem_eraseDups, List.mem_flatMap]; exact ⟨s, hs, hp⟩
    simp [h] at this
  · intro h
    apply List.eq_nil_iff_forall_not_mem.mpr
    intro p hp
    simp only [presets, List.mem_eraseDups, List.mem_flatMap] at hp
    obtain ⟨s, hs, hp⟩ := hp
    simp [h s hs] at hp

theorem verdict_missing (why flag : String) : verdict (.missing why) flag = .unknown why := rfl

theorem verdict_no_arm (flag : String) : verdict (.arms []) flag = .unknown noArm := rfl

theorem verdict_match_iff (as : List String) (flag : String) :
    verdict (.arms as) flag = .match ↔ ∃ s ∈ as, ∃ e ∈ fwOf s, covers e flag = true := by
  rw [← any_carried]
  cases as with
  | nil => simp [verdict, carried]
  | cons a t =>
    simp only [verdict, List.isEmpty_cons, Bool.false_eq_true, ite_false]
    split <;> rename_i h
    · simp [h]
    · split <;> simp [h]

theorem verdict_mismatch_iff (as : List String) (flag : String) (c : List String) :
    verdict (.arms as) flag = .mismatch c ↔
      as ≠ [] ∧ (∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false) ∧ (∀ s ∈ as, presetOf s = []) ∧
        c = carried as := by
  have hany : (carried as).any (covers · flag) = false ↔ ∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false := by
    rw [← Bool.not_eq_true, any_carried]
    simp
  rw [← hany, ← presets_nil_iff]
  cases as with
  | nil => simp [verdict]
  | cons a t =>
    simp only [verdict, List.isEmpty_cons, Bool.false_eq_true, ite_false, ne_eq, reduceCtorEq,
      not_false_eq_true, true_and]
    split <;> rename_i h
    · simp [h]
    · simp only [Bool.not_eq_true] at h
      split <;> rename_i hp
      · simp only [List.isEmpty_iff] at hp
        simp [h, hp, eq_comm]
      · simp only [List.isEmpty_iff] at hp
        simp [h, hp]

theorem verdict_preset (as : List String) (flag : String) (hne : as ≠ [])
    (hno : ∀ s ∈ as, ∀ e ∈ fwOf s, covers e flag = false) (hp : presets as ≠ []) :
    verdict (.arms as) flag = .unknown (presetWhy (presets as)) := by
  have hany : (carried as).any (covers · flag) = false := by
    rw [← Bool.not_eq_true, any_carried]
    intro ⟨s, hs, e, he, hc⟩
    simp [hno s hs e he] at hc
  cases as with
  | nil => exact absurd rfl hne
  | cons a t =>
    have : (presets (a :: t)).isEmpty = false := by
      cases h : presets (a :: t) with
      | nil => exact absurd h hp
      | cons _ _ => rfl
    simp [verdict, hany, this]

theorem mismatch_lists_every_flag (as : List String) (flag : String) (c : List String)
    (h : verdict (.arms as) flag = .mismatch c) : ∀ s ∈ as, ∀ e ∈ fwOf s, e ∈ c := by
  obtain ⟨-, -, -, rfl⟩ := (verdict_mismatch_iff as flag c).mp h
  intro s hs e he
  exact (mem_carried as e).mpr ⟨s, hs, he⟩

theorem covers_iff (entry flag : String) : covers entry flag = true ↔ entry = flag ∨ variantOf entry = flag := by
  simp [covers]

/-- A citation: the run id and the flag it is cited for. -/
structure Cite where
  run : String
  flag : String
  deriving DecidableEq, Repr

/-- Why a run the caller gave no facts for is unknown. -/
def notFetched : String := "no facts for this run were given"

/-- The facts of `run` in `runs` (the first entry wins). -/
def lookup (runs : List (String × Facts)) (run : String) : Facts :=
  match runs.find? (·.1 == run) with
  | some (_, f) => f
  | none => .missing notFetched

/-- The verdict on each citation, in order. -/
def check (runs : List (String × Facts)) (cs : List Cite) : List Verdict :=
  cs.map fun c => verdict (lookup runs c.run) c.flag

theorem check_length (runs : List (String × Facts)) (cs : List Cite) : (check runs cs).length = cs.length := by
  simp [check]

theorem check_unfetched (cs : List Cite) : ∀ v ∈ check [] cs, v = .unknown notFetched := by
  intro v hv
  simp only [check, List.mem_map] at hv
  obtain ⟨c, -, rfl⟩ := hv
  rfl

#guard fwOf "?fw=morph.tween:waapi-scoped" == ["morph.tween:waapi-scoped"]
#guard fwOf "?preset=v2-proved&fw=a.b:c,d:e@plain" == ["a.b:c", "d:e@plain"]
#guard fwOf "" == []
#guard presetOf "?preset=v2-proved&fw=a:b" == ["v2-proved"]
#guard verdict (.arms ["", "", "?fw=morph.tween:waapi-scoped"]) "morph.tween:waapi" ==
  .mismatch ["morph.tween:waapi-scoped"]
#guard verdict (.arms ["", "", "?fw=morph.tween:waapi-scoped"]) "morph.tween:waapi-scoped" == .match
#guard verdict (.arms ["", "?fw=hero.exit:faithful", "?fw=hero.exit:faithful"]) "morph.tween:waapi" ==
  .mismatch ["hero.exit:faithful"]
#guard verdict (.arms ["", ""]) "nav:earn-no-transition" == .mismatch []
#guard verdict (.arms ["?fw=hero.countdown:one-chain@plain"]) "hero.countdown:one-chain" == .match
#guard verdict (.arms ["?fw=hero.countdown:one-chain@plain"]) "hero.countdown:one-chain@mui" ==
  .mismatch ["hero.countdown:one-chain@plain"]
#guard verdict (.arms ["", "?preset=v2-proved"]) "engine.scroll:batched" == .unknown (presetWhy ["v2-proved"])
#guard verdict (.arms ["?preset=v2-proved&fw=morph.tween:waapi"]) "morph.tween:waapi" == .match
#guard verdict (.arms []) "a:b" == .unknown noArm
#guard verdict (.missing "expired") "a:b" == .unknown "expired"
#guard check [("1", .arms ["?fw=a:b"])] [⟨"1", "a:b"⟩, ⟨"2", "a:b"⟩] == [.match, .unknown notFetched]

/-! ## Wire codec of `gate.runCite` -/

/-- Decode one run: `{run, arms: [search]}` or `{run, missing: why}`. -/
def factsOfJson (j : Json) : Except String (String × Facts) := do
  let run ← j.getObjValAs? String "run"
  match j.getObjValAs? (Array String) "arms" with
  | .ok as => pure (run, .arms as.toList)
  | .error _ =>
    match j.getObjValAs? String "missing" with
    | .ok w => pure (run, .missing w)
    | .error _ => throw s!"run {run}: neither arms nor missing"

/-- Decode one citation `{run, flag}`. -/
def citeOfJson (j : Json) : Except String Cite := do
  pure ⟨← j.getObjValAs? String "run", ← j.getObjValAs? String "flag"⟩

/-- Encode one verdict next to its citation. -/
def verdictJson (c : Cite) : Verdict → Json
  | .match => Json.mkObj [("run", .str c.run), ("flag", .str c.flag), ("verdict", "match")]
  | .mismatch cs => Json.mkObj [("run", .str c.run), ("flag", .str c.flag), ("verdict", "mismatch"),
      ("carried", .arr (cs.toArray.map .str))]
  | .unknown w => Json.mkObj [("run", .str c.run), ("flag", .str c.flag), ("verdict", "unknown"), ("why", .str w)]

/-- `gate.runCite`: `{runs: [{run, arms | missing}], cites: [{run, flag}]}` to `{verdicts: [{run, flag, verdict,
carried? | why?}]}`. -/
def reply (req : Json) : Except String (List (String × Json)) := do
  let runs ← (← req.getObjValAs? (Array Json) "runs").toList.mapM factsOfJson
  let cs ← (← req.getObjValAs? (Array Json) "cites").toList.mapM citeOfJson
  pure [("verdicts", .arr ((cs.zip (check runs cs)).toArray.map fun (c, v) => verdictJson c v))]

private def replyText (s : String) : String :=
  match Json.parse s >>= reply with
  | .ok r => (Json.mkObj r).compress
  | .error e => e

#guard replyText "{\"runs\":[{\"run\":\"7\",\"arms\":[\"\",\"?fw=a:b\"]}],\"cites\":[{\"run\":\"7\",\"flag\":\"a:c\"}]}" ==
  "{\"verdicts\":[{\"carried\":[\"a:b\"],\"flag\":\"a:c\",\"run\":\"7\",\"verdict\":\"mismatch\"}]}"
#guard replyText "{\"runs\":[{\"run\":\"7\"}],\"cites\":[]}" == "run 7: neither arms nor missing"

/-! ## Golden vectors -/

/-- Request text of a golden case. -/
private def req (runs cites : String) : String := s!"\{\"op\":\"gate.runCite\",\"runs\":[{runs}],\"cites\":[{cites}]}"

/-- The golden cases `(name, request)`; the first holds the facts of run 39457767229 at one width. -/
def cases : List (String × String) := [
  ("incident 2026-10-21: run 39457767229 carried morph.tween:waapi-scoped, cited for morph.tween:waapi",
    req "{\"run\":\"39457767229\",\"arms\":[\"\",\"\",\"?fw=morph.tween:waapi-scoped\"]}"
      "{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi\"},{\"run\":\"39457767229\",\"flag\":\"morph.tween:waapi-scoped\"}"),
  ("an A/A run carried only the faithful variant: a flag citation is a mismatch",
    req "{\"run\":\"1\",\"arms\":[\"\",\"\",\"?fw=hero.exit:faithful\"]}"
      "{\"run\":\"1\",\"flag\":\"morph.tween:waapi\"},{\"run\":\"1\",\"flag\":\"hero.exit:faithful\"}"),
  ("a run with no query on any arm carried nothing",
    req "{\"run\":\"2\",\"arms\":[\"\",\"\"]}" "{\"run\":\"2\",\"flag\":\"nav:earn-no-transition\"}"),
  ("an @impl entry stands for its variant; an @impl citation needs that impl",
    req "{\"run\":\"3\",\"arms\":[\"?fw=hero.countdown:one-chain@plain\"]}"
      "{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain\"},{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain@plain\"},{\"run\":\"3\",\"flag\":\"hero.countdown:one-chain@mui\"}"),
  ("several flags in one fw parameter, next to a preset",
    req "{\"run\":\"4\",\"arms\":[\"?preset=v2-proved&fw=hero.countdown:strip,morph.countdown:strip\"]}"
      "{\"run\":\"4\",\"flag\":\"morph.countdown:strip\"},{\"run\":\"4\",\"flag\":\"engine.scroll:batched\"}"),
  ("a preset run: a flag outside its fw parameter is unknown",
    req "{\"run\":\"5\",\"arms\":[\"\",\"?preset=v2-proved\"]}" "{\"run\":\"5\",\"flag\":\"engine.scroll:batched\"}"),
  ("expired or not a gate run: unknown with the reason given",
    req "{\"run\":\"6\",\"missing\":\"no gate artifact\"}" "{\"run\":\"6\",\"flag\":\"a:b\"}"),
  ("no facts for the run; no arm in the artifacts",
    req "{\"run\":\"8\",\"arms\":[]}" "{\"run\":\"9\",\"flag\":\"a:b\"},{\"run\":\"8\",\"flag\":\"a:b\"}"),
  ("a prefix of a carried flag is not that flag",
    req "{\"run\":\"10\",\"arms\":[\"?fw=morph.tween:waapi\"]}" "{\"run\":\"10\",\"flag\":\"morph.tween:waapi-\"},{\"run\":\"10\",\"flag\":\"morph.tween:waap\"}"),
  ("a run without facts: refused", "{\"op\":\"gate.runCite\",\"runs\":[{\"run\":\"11\"}],\"cites\":[]}"),
  ("no cites field: refused", "{\"op\":\"gate.runCite\",\"runs\":[]}")]

/-- One golden line `{name, request, response}`; `response` is the reply `fwcore` gives without its `id`. -/
def line (c : String × String) : Json :=
  let request := (Json.parse c.2).toOption.getD (Json.mkObj [("unparsable", .str c.2)])
  let response := match reply request with
    | .ok r => Json.mkObj r
    | .error e => Json.mkObj [("error", .str e)]
  Json.mkObj [("name", .str c.1), ("request", request), ("response", response)]

/-- Where the golden lives, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/gate/run-cite.jsonl"

/-- Write, or with `--check` verify, the golden file; exit 1 when the checked-in file is stale. -/
def run (args : List String) : IO UInt32 := do
  let text := String.join (cases.map fun c => (line c).compress ++ "\n")
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath text
    IO.println s!"run-cite golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != text then
    IO.println s!"run-cite golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/RunCiteGolden.lean)"
    return 1
  IO.println s!"run-cite golden: {cases.length} lines, up to date"
  return 0

end Fw.Gate.RunCite
