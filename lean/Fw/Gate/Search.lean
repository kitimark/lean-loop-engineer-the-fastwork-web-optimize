import Lean.Data.Json
/-!
# Which prerendered page a gate run loads: the `fw` and `preset` inputs of `breakpoint-gate.yml`

The rewrite arm of the gate loads one prerendered page, looked up by its search string in `configs.json` (`bySearch`).
The build prerenders `` (default), `?preset=<name>` for each preset and `?fw=<flags>` for each single variant. The old
`fw` input became `?fw=<input>` whatever it held, so `preset:v2-proved` asked for the key `?fw=preset:v2-proved`, which
no build has. Now a second input `preset` maps to `?preset=<name>`, the key `enumerateSearches` writes.

`pick` decides the search string from the two inputs; `.github/scripts/gate-search.mjs` is its TypeScript twin, checked
against `packages/contracts/golden/gate/search.jsonl`. Whether a key exists in a given build is not decided here: the
smoke step of the gate fails when `FW_SEARCH` is missing from `configs.json`.

```
cd lean && lake env lean --run scripts/SearchGolden.lean           # write the file
cd lean && lake env lean --run scripts/SearchGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Gate.Search
open Lean

/-- Why an input pair is refused.

Both inputs set, a preset name outside its alphabet, or a flag set outside its alphabet. -/
inductive Refusal where
  | bothSet
  | badPreset
  | badFw
  deriving DecidableEq, Repr

/-- The outcome: a search string (possibly empty) or a refusal.

What the gate runs with, or why it does not. -/
inductive Pick where
  | search (s : String)
  | refused (r : Refusal)
  deriving DecidableEq, Repr

/-- A preset name character: lowercase letter, digit or hyphen.

The alphabet of the names in `presets/*.json`. -/
def presetChar (c : Char) : Bool := ('a' ≤ c && c ≤ 'z') || ('0' ≤ c && c ≤ '9') || c == '-'

/-- A flag-set character: letter, digit or one of `. : , - _ @`.

The alphabet of `part:variant` lists with an optional `@impl`. -/
def fwChar (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z') || ('0' ≤ c && c ≤ '9') ||
    c == '.' || c == ':' || c == ',' || c == '-' || c == '_' || c == '@'

/-- A valid preset name: non-empty, all `presetChar`. -/
def validPreset (s : String) : Bool := !s.isEmpty && s.toList.all presetChar

/-- A valid flag set: non-empty, all `fwChar`. -/
def validFw (s : String) : Bool := !s.isEmpty && s.toList.all fwChar

/-- The search string of the gate's rewrite arm.

Two inputs never merge into one key: no build prerenders a preset together with extra flags. -/
def pick (fw preset : String) : Pick :=
  if fw.isEmpty && preset.isEmpty then .search ""
  else if !fw.isEmpty && !preset.isEmpty then .refused .bothSet
  else if fw.isEmpty then (if validPreset preset then .search ("?preset=" ++ preset) else .refused .badPreset)
  else if validFw fw then .search ("?fw=" ++ fw) else .refused .badFw

/-- Branch default.

Neither input set: the default page. -/
theorem pick_default : pick "" "" = .search "" := by decide

/-- Branch both set.

Two inputs are refused whatever their content. -/
theorem pick_both (fw preset : String) (hf : fw.isEmpty = false) (hp : preset.isEmpty = false) :
    pick fw preset = .refused .bothSet := by
  simp [pick, hf, hp]

/-- Branch preset.

A valid preset name becomes the key `enumerateSearches` writes for it. -/
theorem pick_preset (preset : String) (hp : preset.isEmpty = false) (hv : validPreset preset = true) :
    pick "" preset = .search ("?preset=" ++ preset) := by
  simp [pick, hp, hv]

/-- Branch bad preset.

A name outside the alphabet is refused before it reaches a URL. -/
theorem pick_bad_preset (preset : String) (hp : preset.isEmpty = false) (hv : validPreset preset = false) :
    pick "" preset = .refused .badPreset := by
  simp [pick, hp, hv]

/-- Branch flag set.

A valid flag set keeps the old behaviour. -/
theorem pick_fw (fw : String) (hf : fw.isEmpty = false) (hv : validFw fw = true) :
    pick fw "" = .search ("?fw=" ++ fw) := by
  simp [pick, hf, hv]

/-- Branch bad flag set.

A flag set outside the alphabet is refused. -/
theorem pick_bad_fw (fw : String) (hf : fw.isEmpty = false) (hv : validFw fw = false) :
    pick fw "" = .refused .badFw := by
  simp [pick, hf, hv]

/-- The proved preset has a key.

The arm `integrate-wave-1` could not run (`?fw=preset:v2-proved` is no key). -/
theorem pick_v2_proved : pick "" "v2-proved" = .search "?preset=v2-proved" := by decide

/-- The old input for the proved preset still maps to the key it always asked for.

No build has that key; the smoke step is what rejects it. -/
theorem pick_old_form : pick "preset:v2-proved" "" = .search "?fw=preset:v2-proved" := by decide

/-- The golden inputs: pairs of (fw, preset).

Every branch of `pick`, the three presets of the build, and inputs with a space, an underscore, `=` or a newline. -/
def inputs : List (String × String) := [
  ("", ""), ("morph.tween:waapi", ""), ("", "v2-proved"), ("", "original"), ("", "strip-demo"),
  ("morph.tween:waapi", "v2-proved"), ("", "V2 proved"), ("", "v2_proved"), ("morph.tween waapi", ""),
  ("preset:v2-proved", ""), ("a=b", ""), ("", "v2-proved\n?x")]

/-- One golden line. -/
def line (fp : String × String) : Json :=
  let base := [("fw", Json.str fp.1), ("preset", Json.str fp.2)]
  match pick fp.1 fp.2 with
  | .search s => Json.mkObj (base ++ [("ok", Json.bool true), ("search", Json.str s)])
  | .refused r =>
    let n := match r with | .bothSet => "bothSet" | .badPreset => "badPreset" | .badFw => "badFw"
    Json.mkObj (base ++ [("ok", Json.bool false), ("refusal", Json.str n)])

/-- Where the golden lives, relative to `lean/`.

The file `gate-search.test.mjs` replays. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/gate/search.jsonl"

/-- Write, or with `--check` verify, the golden file.

Exit 1 when the checked-in file is stale. -/
def run (args : List String) : IO UInt32 := do
  let text := String.join (inputs.map fun fp => (line fp).compress ++ "\n")
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath text
    IO.println s!"search golden: {inputs.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != text then
    IO.println s!"search golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/SearchGolden.lean)"
    return 1
  IO.println s!"search golden: {inputs.length} lines, up to date"
  return 0

end Fw.Gate.Search
