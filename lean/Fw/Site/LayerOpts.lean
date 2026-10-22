import Lean.Data.Json
import Fw.Console.Layers
import Fw.Parts.FootprintData

/-! Layer options on the site: the `?fwl=` entries `layer:c`, `layer:s`, `layer:cs` become one unlayered `<style>`.

`table` holds, for every declared layer and every option string, the CSS text the site injects. The site parses the
entries (`BuildsOpen.validate` is the proved mirror of `resolve.ts`), looks each pair up in `apps/site/src/registry/
layer-opts.gen.ts` and joins the answers: it decides nothing. `lean/scripts/LayerOptsGolden.lean` writes that file and
`packages/contracts/golden/console/layer-opts.jsonl` from the same definitions and checks both byte for byte.

The composite option writes `will-change` for the layer's properties on the layer's own box, selected by
`[data-fw-layer]`. An unlayered rule beats the `@layer parts` rules, so it wins. Snap rules come from per-layer snap
tables; none exist yet, so snap adds no rule (design 2.3, 6a). -/

namespace Fw.Site.LayerOpts

open Lean Fw.Console.Layers Fw.Console.BuildsOpen

/-- The properties a layer may animate when its declaration lists none: the design's `will-change` set. -/
def defaultProps : List String := ["opacity", "filter", "transform"]

/-- The `will-change` property list of a layer: its declared properties, else `defaultProps`. -/
def layerProps (l : LayerL) : List String := l.props.getD defaultProps

/-- The composite rule of one layer box. -/
def willChangeRule (id : String) (ps : List String) : String :=
  "[data-fw-layer=\"" ++ id ++ "\"] { will-change: " ++ ", ".intercalate ps ++ " }"

/-- The snap rules of a layer: its variant's Lean-generated snapped table. No table exists yet, so none. -/
def snapRules (_ : LayerL) : List String := []

/-- The rules an option string adds to one layer, composite first. -/
def rules (l : LayerL) (o : String) : List String :=
  (if composite o then [willChangeRule l.id (layerProps l)] else []) ++ (if snap o then snapRules l else [])

/-- The CSS text of one layer and option string. -/
def css (l : LayerL) (o : String) : String := "\n".intercalate (rules l o)

theorem layerProps_none (l : LayerL) (h : l.props = none) : layerProps l = defaultProps := by
  simp [layerProps, h]

theorem layerProps_some (l : LayerL) (ps : List String) (h : l.props = some ps) : layerProps l = ps := by
  simp [layerProps, h]

theorem rules_composite (l : LayerL) (o : String) (h : composite o = true) :
    willChangeRule l.id (layerProps l) ∈ rules l o := by
  simp [rules, h]

theorem rules_not_composite (l : LayerL) (o : String) (h : composite o = false) : rules l o = (if snap o then snapRules l else []) := by
  simp [rules, h]

theorem rules_snap_only (l : LayerL) : rules l "s" = snapRules l := by
  simp [rules, composite, snap]

theorem snapRules_nil (l : LayerL) : snapRules l = [] := rfl

theorem css_snap_only (l : LayerL) : css l "s" = "" := by
  simp [css, rules_snap_only, snapRules_nil]

/-- Every declared layer, as the footprint extractor lists it. -/
def layers : List LayerL := Fw.Parts.FootprintData.layerDecls.map fun r => { id := r.2.1, text := r.2.2 }

/-- One row per declared layer and option string: layer id, option string, CSS text. -/
def table : List (String × String × String) :=
  layers.flatMap fun l => layerOpts.map fun o => (l.id, o, css l o)

theorem table_length : table.length = layers.length * layerOpts.length := by
  unfold table
  induction layers with
  | nil => rfl
  | cons l ls ih => simp only [List.flatMap_cons, List.length_append, List.length_map, ih, List.length_cons]; rw [Nat.add_mul, Nat.one_mul, Nat.add_comm]

/-- The CSS text of one entry; an undeclared pair gives the empty text. -/
def lookup (e : String × String) : String :=
  ((table.find? fun r => r.1 == e.1 && r.2.1 == e.2).map (·.2.2)).getD ""

/-- The style text of an entry list, in the given order, without empty parts. -/
def styleOf (es : List (String × String)) : String := "\n".intercalate ((es.map lookup).filter (· != ""))

theorem styleOf_nil : styleOf [] = "" := rfl

#guard (layers.map (·.id)).eraseDups.length == layers.length
#guard layers.length > 0
#guard table.all fun r => lookup (r.1, r.2.1) == r.2.2
#guard lookup ("nope", "c") == ""
#guard lookup ("hero_copy", "c") == "[data-fw-layer=\"hero_copy\"] { will-change: opacity, filter, transform }"
#guard lookup ("hero_copy", "s") == ""
#guard lookup ("hero_copy", "cs") == lookup ("hero_copy", "c")
#guard styleOf [("hero_copy", "c"), ("hero.cue_cue", "cs")] ==
  lookup ("hero_copy", "c") ++ "\n" ++ lookup ("hero.cue_cue", "cs")
#guard styleOf [("hero_copy", "s")] == ""
#guard layers.all fun l => (l.id.toList.all okChar)

/-- Entry lists of the golden: every declared pair alone, then the combinations the site meets. -/
def vectors : List (String × List (String × String)) :=
  [("no entries", []), ("an undeclared layer", [("nope", "c")]), ("an undeclared option", [("hero_copy", "x")]),
   ("two layers keep the given order", [("hero.cue_cue", "cs"), ("hero_copy", "c")]),
   ("snap alone adds nothing", [("hero_copy", "s"), ("hero.cue_cue", "c")]),
   ("a repeated pair repeats its text", [("hero_copy", "c"), ("hero_copy", "c")])] ++
  table.map fun r => (s!"{r.1}:{r.2.1}", [(r.1, r.2.1)])

def entryJson (e : String × String) : Json := Json.mkObj [("layer", .str e.1), ("opts", .str e.2)]

/-- Text of `packages/contracts/golden/console/layer-opts.jsonl`. -/
def goldenText : String :=
  String.join (vectors.map fun (n, es) =>
    (Json.mkObj [("name", .str n), ("entries", Json.arr (es.map entryJson).toArray), ("style", .str (styleOf es))]).compress ++ "\n")

/-- Text of `apps/site/src/registry/layer-opts.gen.ts`. -/
def tsText : String :=
  let byLayer := layers.map fun l => (l.id, Json.mkObj (layerOpts.map fun o => (o, Json.str (css l o))))
  "// Generated by lean/scripts/LayerOptsGolden.lean (Fw.Site.LayerOpts). Do not edit.\n" ++
  "export const layerOptsTable: Readonly<Record<string, Readonly<Record<string, string>>>> = " ++
  (Json.mkObj byLayer).compress ++ ";\n"

/-- Command-line driver. `--write <ts> <golden>` writes both files; `--check <ts> <golden>` exits 0 when both hold
exactly the generated bytes, 1 otherwise; any other arguments exit 2. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--write", ts, g] =>
    IO.FS.writeFile ts tsText
    IO.FS.writeFile g goldenText
    return 0
  | ["--check", ts, g] =>
    let a ← IO.FS.readBinFile ts
    let b ← IO.FS.readBinFile g
    if a.data == tsText.toUTF8.data && b.data == goldenText.toUTF8.data then
      IO.eprintln "layer-opts: the site table and the golden are up to date"
      return 0
    IO.eprintln "layer-opts: the site table or the golden differs from the generated bytes"
    return 1
  | _ => IO.eprintln "usage: LayerOptsGolden (--write | --check) <layer-opts.gen.ts> <layer-opts.jsonl>"; return 2

end Fw.Site.LayerOpts
