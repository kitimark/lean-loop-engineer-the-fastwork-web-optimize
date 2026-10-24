import Lean.Data.Json
import Fw.Wire.FlagKey
/-!
# Golden of the canonical flag key
-/
namespace Fw.Wire.FlagKey
open Lean

def cases : List (List String) :=
  [[], ["morph.countdown:strip", "hero.countdown:strip"], ["hero.countdown:strip", "morph.countdown:strip"],
   ["a:x", "a:x"], ["a:x", "a.b:y"], ["a.b:y", "a:x"], ["a:y", "a:x"], ["p:v@mui", "o:w"],
   ["nocolon"], ["a:b:c", "d:e"]]

def row (fw : List String) : String :=
  (Json.mkObj [("in", Json.arr (fw.map Json.str).toArray),
    ("key", match keyOf fw with | none => Json.null | some k => Json.str k)]).compress

def goldenLines (_ : Unit) : List String := cases.map row

def jsonl (_ : Unit) : String := String.join ((goldenLines ()).map (· ++ "\n"))

#guard jsonl () == include_str "../../../packages/contracts/golden/wire/flag-key.jsonl"

end Fw.Wire.FlagKey
