import Fw.Wire.Compose
import Fw.Console.Layers
import Fw.Parts.FootprintData
/-!
# JSON for composed arms (`console.compose` with `arms`)

`console.compose` keeps its reply for a request without `arms`. With `arms` it also reads, per registry part, the
variant fields `visClass` and `lean` and the part's `layers`, and the registry's `changes`; it fails on any
`registryErrors` entry and adds `arms`, one decision per requested arm (`Fw.Console.Layers.decideArm`).

| field | request | reply |
|---|---|---|
| `registry.parts[].variants[]` | `visClass`?, `lean`? | |
| `registry.parts[].layers`? | [{id, text, props?, paths? [{path, variant, composited}]}] (absent: the extractor's `layerDecls`) | |
| `registry.changes`? | [{id, label?, picks [{part, variant}], lean?}] | |
| `arms` | [{original?, changes? [id], picks? [{part, variant}], layers? [{layer, opts}]}] | `arms` [{ok, link, reasons [{code, text}], units [{id, kind, picks, proof}], grade, verdict, hyps, notes, premises [{scope, premises}], fix [{part, variant}]}] |

A variant's files are the extractor's `variantFiles`; a variant's `refuted` text is its refusal in `Fw.Console.Compose.table` over the request's ledger; the accesses are
the extractor's (`Fw.Parts.FootprintData.accesses`).
-/
namespace Fw.Wire.Layers
open Lean Fw.Wire.Ops Fw.Wire.Compose Fw.Console.Layers Fw.Console.Compose Fw.Console.BuildsOpen

/-- A `{part, variant}` object as a pair. -/
def pick (e : Json) : Except String (String × String) := do pure ((← str e "part"), (← str e "variant"))

/-- The extractor's files of a variant. -/
def filesOf (part variant : String) : List String :=
  ((Fw.Parts.FootprintData.variantFiles.find? fun r => r.1 == part && r.2.1 == variant).map (·.2.2)).getD []

/-- The extractor's layers of a part. -/
def layersOf (part : String) : List LayerL :=
  (Fw.Parts.FootprintData.layerDecls.filter (·.1 == part)).map fun r => { id := r.2.1, text := r.2.2 }

/-- One declared layer. -/
def layer (l : Json) : Except String LayerL := do
  pure { id := ← str l "id", text := ← boolD l "text" false, props := ← strsOpt l "props",
         paths := ← (← arrD l "paths").mapM fun p => do
           pure ({ path := ← str p "path", variant := ← str p "variant", composited := ← boolD p "composited" false } :
             SnapPath) }

/-- The page of a request: its registry parts with their layer fields, its Changes, the extractor's accesses. -/
def page (req : Json) (rows : List LRow) (presets : List PresetFact) (infos : List PartInfo) : Except String Page := do
  let r ← field req "registry"
  let tbl := table infos rows presets
  let refusal (p v : String) : String :=
    (((tbl.find? (·.id == p)).bind fun po => po.variants.find? (·.name == v)).bind (·.refusal)).getD ""
  let parts ← (← arrD r "parts").mapM fun p => do
    let id ← str p "id"
    let bare : PartInfo := { id, slot := "", variants := [], impls := [], requires := [], conflicts := [] }
    let info := (infos.find? (·.id == id)).getD bare
    let vs ← (← arrD p "variants").mapM fun v => do
      let name ← str v "name"
      pure ({ name, kind := ← strD v "kind" "optimized", limit := ← strD v "limit" "", visClass := ← strD v "visClass" "",
              lean := ← strD v "lean" "", refuted := refusal id name,
              files := filesOf id name } : VarL)
    let layers ← match opt p "layers" with
      | none => pure (layersOf id)
      | some (.arr a) => a.toList.mapM layer
      | some _ => throw "field layers: expected an array"
    pure ({ id, slot := info.slot, variants := vs, impls := info.impls, requires := info.requires,
            conflicts := info.conflicts, layers } : PartL)
  let changes ← (← arrD r "changes").mapM fun c => do
    pure ({ id := ← str c "id", label := ← strD c "label" "", picks := ← (← arrD c "picks").mapM pick,
            lean := ← strD c "lean" "" } : Change)
  pure { parts, changes, accesses := Fw.Parts.FootprintData.accesses }

/-- One requested arm. -/
def arm (a : Json) : Except String Fw.Console.Layers.Arm := do
  pure { original := ← boolD a "original" false, changes := ← (← arrD a "changes").mapM (asStr "changes"),
         picks := ← (← arrD a "picks").mapM pick,
         opts := ← (← arrD a "layers").mapM fun o => do pure ((← str o "layer"), (← str o "opts")) }

/-- A string list as JSON. -/
def strs (l : List String) : Json := Json.arr (l.map Json.str).toArray

/-- A pick as JSON. -/
def pickJson (e : String × String) : Json := Json.mkObj [("part", .str e.1), ("variant", .str e.2)]

/-- The decision for one arm as JSON. -/
def outJson (o : Out) : Json :=
  Json.mkObj [("ok", .bool o.link.isSome), ("link", match o.link with | some l => .str l | none => .null),
    ("reasons", Json.arr (o.reasons.map fun r => Json.mkObj [("code", .str r.code), ("text", .str r.text)]).toArray),
    ("units", Json.arr (o.units.map fun u => Json.mkObj [("id", .str u.id), ("kind", .str u.kind.name),
      ("picks", strs (u.picks.map key)), ("proof", .str u.proof)]).toArray),
    ("grade", .str o.grade.name), ("verdict", match o.verdict with | some g => .str g.name | none => .null),
    ("hyps", strs o.hyps), ("notes", strs o.notes),
    ("premises", Json.arr (o.premises.map fun p => Json.mkObj [("scope", .str p.1), ("premises", strs p.2)]).toArray),
    ("fix", Json.arr (o.fix.map pickJson).toArray)]

/-- `console.compose`: the Compose reply, plus `arms` when the request has them. -/
def opComposeArms (req : Json) : Except String Reply := do
  let base ← opCompose req
  match opt req "arms" with
  | none => pure base
  | some _ =>
    let (infos, presets, rows) ← facts req
    let pg ← page req rows presets infos
    match registryErrors pg with
    | [] =>
      let arms ← (← arrD req "arms").mapM arm
      pure (base ++ [("arms", Json.arr (arms.map fun a => outJson (decideArm pg a)).toArray)])
    | es => throw ("; ".intercalate es)

end Fw.Wire.Layers
