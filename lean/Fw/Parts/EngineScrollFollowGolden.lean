import Lean.Data.Json
import Fw.Parts.EngineScrollFollow
/-!
# Golden vectors for engine.scroll:unthrottle-follow
`lines` is `packages/contracts/golden/parts/engine-scroll-follow.jsonl`; `run ["--check"]` compares, no argument prints.
-/
namespace Fw.Parts.EngineScrollFollowGolden

open Lean Fw.Parts.EngineScrollFollow
open Fw.Parts.EngineScrollUnthrottle (Env)

def stJson (s : St) : Json :=
  Json.mkObj [("last", toJson s.last), ("still", s.still), ("frames", s.frames), ("on", s.on)]

/-- A position series named by its shape, as the site test rebuilds it. -/
inductive Shape where
  | moving (start : Int) (n : Nat)
  | hold (y : Int) (n : Nat)
  | stairs (start : Int) (plateaus : Nat) (p : Nat)

def Shape.ys : Shape → List Int
  | .moving start n => (List.range n).map fun (i : Nat) => start + Int.ofNat i + 1
  | .hold y n => List.replicate n y
  | .stairs start plateaus p => (List.range plateaus).flatMap fun (i : Nat) => List.replicate p (start + Int.ofNat i + 1)

def Shape.json : Shape → Json
  | .moving start n => Json.mkObj [("kind", "moving"), ("start", toJson start), ("n", n)]
  | .hold y n => Json.mkObj [("kind", "hold"), ("y", toJson y), ("n", n)]
  | .stairs start plateaus p => Json.mkObj [("kind", "stairs"), ("start", toJson start), ("plateaus", plateaus), ("p", p)]

private def states : List St :=
  [St.init 100, St.wake 100, ⟨100, 0, 3, true⟩, ⟨100, 7, 3, true⟩, ⟨100, 0, 3599, true⟩, ⟨100, 4, 2, false⟩]

private def traces : List (Int × Shape) :=
  [(100, .moving 100 10), (100, .hold 100 3), (100, .hold 100 7), (100, .hold 100 10), (100, .stairs 100 5 6),
   (100, .stairs 100 5 9), (100, .moving 100 3599), (100, .moving 100 3700)]

def goldenLines (_ : Unit) : List String :=
  let steps := states.flatMap fun (s : St) => ([100, 101] : List Int).flatMap fun (y : Int) => ([false, true] : List Bool).map fun (e : Bool) =>
    (Json.mkObj [("fn", "step"), ("in", Json.mkObj [("state", stJson s), ("y", toJson y), ("ended", e)]),
      ("out", stJson (step s y e))]).compress
  let guards := ([true, false] : List Bool).flatMap fun (coarse : Bool) => ([100, 101] : List Int).map fun (y : Int) =>
    (Json.mkObj [("fn", "guarded"), ("in", Json.mkObj [("coarse", coarse), ("state", stJson (St.init 100)), ("y", toJson y)]),
      ("out", stJson (stepG ⟨.webkitIos, coarse⟩ (St.init 100) y false))]).compress
  let drives := traces.map fun (y0, sh) =>
    let r := drive (St.wake y0) sh.ys
    (Json.mkObj [("fn", "drive"), ("in", Json.mkObj [("wake", toJson y0), ("shape", sh.json)]),
      ("out", Json.mkObj [("state", stJson r.1), ("frames", r.2)])]).compress
  [(Json.mkObj [("fn", "consts"), ("out", Json.mkObj [("stillMax", stillMax), ("frameCap", frameCap)])]).compress,
   (Json.mkObj [("fn", "css"), ("out", Fw.Parts.EngineScrollFollow.css)]).compress] ++ steps ++ guards ++ drives

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "parts" / "engine-scroll-follow.jsonl"

def run (args : List String) : IO Unit := do
  match args with
  | "--check" :: _ =>
    let cur ← IO.FS.readBinFile goldenPath
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"engine.scroll follow golden: {goldenPath} is up to date ({(goldenLines ()).length} lines)"
    else
      throw (IO.userError s!"{goldenPath} differs from Fw.Parts.EngineScrollFollowGolden.goldenText")
  | _ => IO.print (goldenText ())

end Fw.Parts.EngineScrollFollowGolden
