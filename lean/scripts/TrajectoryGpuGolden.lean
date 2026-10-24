import Fw.Gate.TrajectoryGpu

namespace TrajectoryGpuRaw
open Lean Fw.Gate.TrajectoryGpu
open Fw.Gate.PathPix (Grade)

def field (j : Json) (k : String) : Option Json := (j.getObjVal? k).toOption
def elems (j : Option Json) : Option (List Json) := (j.bind fun x => x.getArr?.toOption).map Array.toList
def listOf (j : Option Json) : List Json := (elems j).getD []
def intOf (j : Option Json) : Option Int := j.bind fun x => x.getInt?.toOption

def firstInt (j : Option Json) : Option Int :=
  match elems j with
  | some (Json.num n :: _) => (Json.num n).getInt?.toOption
  | _ => none

def idx (layout : Json) (node prop : String) : Option Nat :=
  ((field layout node).bind fun n => field n prop).bind fun i => i.getNat?.toOption

def ratQ (x : Int) : Rat := (x : Rat) / 1000

def mOf (row : Json) : Option Rat :=
  match field row "m" with
  | some (Json.num n) => (Json.num n).getInt?.toOption.map fun m => (m : Rat) / 10000
  | _ => none

def nodeEntry (row : Json) (node : String) : Option (List Json) :=
  elems ((elems ((field row "nodes").bind fun n => field n node)).bind List.head?)

def navShapeOf (row layout : Json) : Option (List Rat) := do
  let e ← nodeEntry row "nav"
  let ir ← idx layout "nav" "rect"
  let ib ← idx layout "nav" "border-radius"
  let rect ← elems (e[ir]?)
  let rect ← if rect.length == 4 then rect.mapM (fun x => match x with | Json.num n => (Json.num n).getInt?.toOption | _ => none) else none
  let rad ← firstInt (e[ib]?)
  let clip := match idx layout "nav" "clip-path" with
    | some i => ((e[i]?).bind fun c => c.getStr?.toOption).getD "none"
    | none => "none"
  match rect with
  | [x, y, w, h] => (readShape ⟨ratQ x, ratQ y, ratQ w, ratQ h⟩ (ratQ rad) clip).map shapeVec
  | _ => none

def panelEffectOf (row layout : Json) : Option (List Rat) := do
  let e ← nodeEntry row "panel"
  let io ← idx layout "panel" "opacity"
  let op ← firstInt (e[io]?)
  let blur := ((idx layout "panel" "filter.num").bind fun i => firstInt (e[i]?)).map ratQ |>.getD 0
  let scale := ((idx layout "panel" "transform.lin").bind fun i => firstInt (e[i]?)).map ratQ |>.getD 1
  some [ratQ op, blur, scale]

def sample (rows : List Json) (fn : Json → Option (List Rat)) : Series :=
  rows.filterMap fun r => (mOf r).bind fun m => if edge < m ∧ m < 1 - edge then (fn r).map (m, ·) else none

def repOf (r : Json) : Int := (intOf (field r "rep")).getD 0

def dprOf (width : Nat) : Rat := if width ≤ 640 then 2 else 1

def MIN_COVERED : Nat := 8

def tok (g : Option Grade) : String := (g.map Grade.name).getD "null"
def toks (gs : List (Option Grade)) : String := ",".intercalate (gs.map tok)

def morphCells (width : Nat) (base cand layout : Json) (phase : String) :
    List (Option Grade) × List (Option Grade) × List (Option Rat) :=
  let rowsOf (arm : Json) := listOf ((field arm "morph").bind fun m => (field m "phases").bind fun p => field p phase)
  let dpr := dprOf width
  let navTol := List.replicate 5 (tolCss dpr)
  let effTol := effectTols dpr width
  let refNav := seriesOf (sample (rowsOf base) (navShapeOf · layout))
  let refEff := seriesOf (sample (rowsOf base) (panelEffectOf · layout))
  let reps := ((rowsOf cand).map repOf).eraseDups.mergeSort (· ≤ ·)
  let per := reps.map fun rep =>
    let rows := (rowsOf cand).filter fun r => repOf r == rep
    let nav := matchedGrade navTol [0] 1 MIN_COVERED refNav (seriesOf (sample rows (navShapeOf · layout)))
    let frames : Series := rows.filterMap fun r => (mOf r).bind fun m => (panelEffectOf r layout).map (m, ·)
    let lag := lagFrames (frames.map fun f => ⟨f.1, f.2.headD 0⟩)
    (nav, panelCell effTol MIN_COVERED refEff frames, lag)
  (per.map (·.1), per.map (·.2.1), per.map (·.2.2))

def painSeries (rows : List Json) : List Rat :=
  rows.map fun r =>
    let layer : Option Rat := match field r "layer" with
      | some (Json.num n) => some ((((n.mantissa : Rat) / 10 ^ n.exponent * 1000 + 1 / 2).floor : Int) / 1000 : Rat)
      | _ => none
    darkness layer (field r "cls" == some (Json.bool true))

def carouselRows (rows : List Json) : List Row :=
  rows.map fun r => (elems (field r "v")).map fun v => v.map fun x => (x.getInt?.toOption).getD 0

def unitLines (label : String) (raw : Json) : List String := Id.run do
  let layout := (field raw "layout").getD Json.null
  let runs := listOf (field raw "runs")
  let roleRun (role : String) (w : Nat) : Option Json :=
    runs.find? fun r => (field r "role" == some (Json.str role)) && (intOf (field r "width") == some (w : Int))
  let widths := ((runs.filterMap fun r => (intOf (field r "width")).map Int.toNat).eraseDups).mergeSort (· ≤ ·)
  let aa := field raw "hash" == field raw "baseHash"
  let hasClip := (idx layout "nav" "clip-path").isSome
  let mut out : List String := []
  for w in widths do
    let some b := roleRun "base" w | continue
    let some c := roleRun "cand" w | continue
    let pre := s!"{label} {w}"
    let present (r : Json) (k : String) := (field r k).any (· != Json.null)
    if present b "morph" && present c "morph" then
      for phase in ["open", "close"] do
        let (nav, panel, lag) := morphCells w b c layout phase
        let navOk := hasClip || aa
        out := out ++ [s!"{pre} nav-clip {phase} {tok (if navOk then worst nav else none)} {toks nav}"]
        out := out ++ [s!"{pre} panel-effect {phase} {tok (worst panel)} {toks panel} lag={",".intercalate (lag.map fun l => (l.map ratStr).getD "null")}"]
    if present b "pain" && present c "pain" then
      let side (r : Json) (d : String) := painSeries (listOf ((field r "pain").bind fun p => field p d))
      let gs := painCell (side b "up", side c "up") (side b "down", side c "down")
      out := out ++ [s!"{pre} pain-dark scroll {tok (worst gs)} {toks gs}"]
    if present b "carousel" && present c "carousel" then
      let rb := carouselRows (listOf (field b "carousel"))
      let rc := carouselRows (listOf (field c "carousel"))
      let cell := carouselCell (dprOf w) rb rc
      let hs (hh : List Nat) := ",".intercalate (hh.map toString)
      out := out ++ [s!"{pre} carousel swap {tok cell.grade} {toks cell.reps} swaps={cell.swaps.1},{cell.swaps.2} holds={hs (holdsOf rb)}/{hs (holdsOf rc)}"]
  return out

def labelOf (path : String) : String :=
  let name := (path.splitOn "/").getLast!
  let name := if name.startsWith "raw-" then (name.drop 4).toString else name
  if name.endsWith ".json" then (name.dropEnd 5).toString else name

def run (files : List String) : IO UInt32 := do
  for f in files do
    match Json.parse (← IO.FS.readFile f) with
    | .error e => IO.eprintln s!"trajectory-gpu raw: {f}: {e}"; return 1
    | .ok j => for l in unitLines (labelOf f) j do IO.println l
  return 0

end TrajectoryGpuRaw

def main (args : List String) : IO UInt32 :=
  match args with
  | "--raw" :: files@(_ :: _) => TrajectoryGpuRaw.run files
  | _ => Fw.Gate.TrajectoryGpu.main args
