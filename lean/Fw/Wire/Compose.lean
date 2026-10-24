import Fw.Ops.Wire
import Fw.Console.Compose
import Fw.Parts.Gpu
/-!
# JSON for the Compose tab (`console.compose`)

| op | request | reply |
|---|---|---|
| `console.compose` | `registry` {parts [{id, slot, impls, variants [{name, kind, limit?}] (head = default), requires {key: [keys]}, conflicts {key: [keys]}}], presets [{name, extends?, fw {part: variant or variant@impl}}]}, `ledger` [{part, candidate, status, flags [part:variant], flag?, id?, supersededBy?}] (an error unless each row's `flags` names registered variants and holds its `flag`, each `supersededBy` chain reaches a row with none, each superseding row keeps the flags of the row it supersedes and each `id` is unique), `picks`? [{part, variant}] | `regions` (page order), `parts` [{id, slot, group, pageLevel, variants [{name, kind, isDefault, class, why, rows (ledger indices), refusal, gpu (the mechanism text when the variant is a GPU optimization, `Fw.Parts.Gpu.entries`, else null), gpuEngines (one of both engines, WebKit only, Chromium only, else null)}], other (ledger indices)}], `presets` [{name, picks, ok, link, reasons, notes}], `decision` {ok, link, reasons, notes} for `picks`, `rules` (the class names with their one-line reasons) (`Fw.Console.Compose.table`, `decide`) |
-/
namespace Fw.Wire.Compose
open Lean Fw.Wire.Ops Fw.Console.Compose Fw.Console.BuildsOpen

/-- An object of string lists as pairs. -/
def listPairs (k : String) : Json → Except String (List (String × List String))
  | .obj kvs => kvs.toList.mapM fun kv => do
      match kv.2 with
      | .arr a => pure (kv.1, ← a.toList.mapM (asStr k))
      | _ => throw s!"field {k}: expected an array of strings"
  | _ => throw s!"field {k}: expected an object"

/-- An object of strings as pairs. -/
def pairs (k : String) : Json → Except String (List (String × String))
  | .obj kvs => kvs.toList.mapM fun kv => do pure (kv.1, ← asStr k kv.2)
  | _ => throw s!"field {k}: expected an object"

/-- An optional string-list field: absent is `none`, a value other than an array of strings is an error. -/
def strsOpt (j : Json) (k : String) : Except String (Option (List String)) :=
  match opt j k with
  | none => pure none
  | some (.arr a) => some <$> a.toList.mapM (asStr k)
  | some _ => throw s!"field {k}: expected an array of strings"

/-- An optional string field: absent is `none`, a value other than a string is an error. -/
def strOpt (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => pure none
  | some (.str s) => pure (some s)
  | some _ => throw s!"field {k}: expected a string"

/-- The parts, presets and ledger rows of a request; an error for each `flagErrors` and `supersedeErrors` entry. -/
def facts (req : Json) : Except String (List PartInfo × List PresetFact × List LRow) := do
  let r ← field req "registry"
  let parts ← (← arrD r "parts").mapM fun p => do
    pure ({ id := ← str p "id", slot := ← strD p "slot" "",
            variants := ← (← arrD p "variants").mapM fun v => do
              pure ({ name := ← str v "name", kind := ← strD v "kind" "optimized", limit := ← strD v "limit" "" } : VariantFact),
            impls := ← (← arrD p "impls").mapM (asStr "impls"),
            requires := ← (match opt p "requires" with | none => pure [] | some v => listPairs "requires" v),
            conflicts := ← (match opt p "conflicts" with | none => pure [] | some v => listPairs "conflicts" v) } : PartInfo)
  let presets ← (← arrD r "presets").mapM fun p => do
    pure ({ name := ← str p "name",
            base := (match opt p "extends" with | some (.str b) => some b | _ => none),
            fw := ← (match opt p "fw" with | none => pure [] | some v => pairs "fw" v) } : PresetFact)
  let rows ← (← arrD req "ledger").mapM fun l => do
    pure ({ part := ← str l "part", candidate := ← str l "candidate", status := ← str l "status",
            flag := (match opt l "flag" with | some (.str f) => some f | _ => none), flags := ← strsOpt l "flags",
            id := ← strOpt l "id", supersededBy := ← strOpt l "supersededBy" } : LRow)
  match flagErrors parts rows ++ supersedeErrors rows with
  | [] => pure (parts, presets, rows)
  | es => throw ("; ".intercalate es)

/-- The decision as JSON. -/
def decisionJson (d : Decision) : Json :=
  Json.mkObj [("ok", .bool d.link.isSome), ("link", match d.link with | some l => .str l | none => .null),
    ("reasons", Json.arr (d.reasons.map Json.str).toArray), ("notes", Json.arr (d.notes.map Json.str).toArray)]

/-- One variant of the table as JSON; `gpu` is its mechanism and `gpuEngines` the engines it holds on when it is a GPU optimization (`Fw.Parts.Gpu`), else null. -/
def varJson (pid : String) (v : VarOut) : Json :=
  Json.mkObj [("name", .str v.name), ("kind", .str v.kind), ("isDefault", .bool v.isDefault), ("class", .str v.cls.name),
    ("why", .str v.cls.why), ("rows", toJson v.rows),
    ("refusal", match v.refusal with | some r => .str r | none => .null),
    ("gpu", match Fw.Parts.Gpu.mechanism pid v.name with | some m => .str m | none => .null),
    ("gpuEngines", match Fw.Parts.Gpu.engines pid v.name with | some e => .str e | none => .null)]

/-- One part of the table as JSON. -/
def partJson (p : PartOut) : Json :=
  Json.mkObj [("id", .str p.id), ("slot", .str p.slot), ("group", .str p.group), ("pageLevel", .bool p.pageLevel),
    ("variants", Json.arr (p.variants.map (varJson p.id)).toArray), ("other", toJson p.other)]

/-- A preset as a combination: its picks and the decision for it. A preset that does not resolve is refused with the reasons. -/
def presetJson (parts : List PartInfo) (rows : List LRow) (presets : List PresetFact) (p : PresetFact) : Json :=
  let r := presetEntries presets p.name [] [] (presets.length + 2)
  let picks := r.1.map fun e => (e.1, (e.2.splitOn "@").headD "")
  let d := decide parts rows presets picks
  let ir := implReasons presets p.name
  let d := if r.2.isEmpty && ir.isEmpty then d else { link := none, reasons := r.2 ++ ir, notes := [] }
  Json.mkObj [("name", .str p.name), ("picks", Json.arr (picks.map fun e => Json.mkObj [("part", .str e.1), ("variant", .str e.2)]).toArray),
    ("ok", .bool d.link.isSome), ("link", match d.link with | some l => .str l | none => .null),
    ("reasons", Json.arr (d.reasons.map Json.str).toArray), ("notes", Json.arr (d.notes.map Json.str).toArray)]

/-- `console.compose` (`Fw.Console.Compose.table`, `decide`). -/
def opCompose (req : Json) : Except String Reply := do
  let (parts, presets, rows) ← facts req
  let picks ← (← arrD req "picks").mapM fun e => do pure ((← str e "part"), (← str e "variant"))
  let classes := [Cls.original, .proved, .lookChange, .ledgerProved, .measured, .refuted, .unrated]
  pure [("regions", Json.arr (regions.map Json.str).toArray),
    ("parts", Json.arr ((table parts rows presets).map partJson).toArray),
    ("presets", Json.arr (presets.map (presetJson parts rows presets)).toArray),
    ("decision", decisionJson (decide parts rows presets picks)),
    ("rules", Json.mkObj (classes.map fun c => (c.name, Json.str c.why)))]

end Fw.Wire.Compose
