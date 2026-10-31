import Lean.Data.Json
import Fw.Parts.HeroAccentPause
import Fw.Parts.HeroCuePause
import Fw.Parts.PlatformSweepPauseGolden
/-! # Golden vectors for `hero.accent:offscreen-pause` and `hero.cue:offscreen-pause` -/
namespace Fw.Parts.OffscreenPauseGolden
open Lean Fw.Parts.PlatformSweepPause
open Fw.Parts.PlatformSweepPauseGolden (numJ frameJ leaveReturn mountedOff flicker)

abbrev Look := Rat → Json

def accentLook : Look := fun t =>
  .arr #[numJ (Fw.Parts.HeroAccentPause.shown 0 t), numJ (Fw.Parts.HeroAccentPause.shown 1 t),
    numJ (Fw.Parts.HeroAccentPause.shown 2 t)]

def cueLook : Look := fun t => numJ (Fw.Parts.HeroCuePause.cueY id t)

def outs (look : Look) (o : Rat) (tr : List Step) : List Json :=
  let rec go (s : St) : List Step → List Json
    | [] => []
    | f :: t =>
      let a := seek s f
      Json.mkObj [("loc", numJ a.loc), ("look", look a.loc), ("ticks", .num (ticks f)),
        ("paused", .bool a.paused)] :: go (step s f) t
  go (init o) tr

def traceLine (look : Look) (name : String) (o : Rat) (tr : List Step) : String :=
  (Json.mkObj [("fn", "trace"),
    ("in", Json.mkObj [("case", .str name), ("off", numJ o), ("frames", .arr (tr.map frameJ).toArray)]),
    ("out", .arr (outs look o tr).toArray)]).compress

def origLine (look : Look) (o : Rat) (tr : List Step) : String :=
  (Json.mkObj [("fn", "orig"), ("in", Json.mkObj [("off", numJ o), ("frames", .arr (tr.map frameJ).toArray)]),
    ("out", Json.mkObj [("loc", numJ (orig o tr)), ("look", look (orig o tr))])]).compress

def cases : List (String × Rat × List Step) :=
  [("leave-return", leaveReturn), ("mounted-offscreen", mountedOff), ("flicker", flicker)]

def constLine (cycle : Rat) (flag variant : String) : String :=
  (Json.mkObj [("fn", "const"), ("in", Json.mkObj []),
    ("out", Json.mkObj [("cycleMs", numJ cycle), ("flag", .str flag), ("variant", .str variant)])]).compress

def lines (look : Look) (cycle : Rat) (flag variant : String) : List String :=
  constLine cycle flag variant :: (cases.flatMap fun (n, o, t) => [traceLine look n o t, origLine look o t])

def text (look : Look) (cycle : Rat) (flag variant : String) : String :=
  String.join ((lines look cycle flag variant).map (· ++ "\n"))

def accentText : String := text accentLook Fw.Parts.HeroAccentPause.cycleMs "hero.accent:offscreen-pause" "offscreen-pause"
def cueText : String := text cueLook Fw.Parts.HeroCuePause.cycleMs "hero.cue:offscreen-pause" "offscreen-pause"

def sameOnVisible (look : Look) (o : Rat) (tr : List Step) : Bool :=
  (List.range tr.length).all fun k =>
    let f := tr.getD k (0, true, false)
    !f.2.1 || look (seek (run (init o) (tr.take k)) f).loc == look (orig o (tr.take k))

#guard cases.all fun (_, o, t) => sameOnVisible (fun x => .arr #[numJ (Fw.Parts.HeroAccentPause.shown 0 x)]) o t
#guard cases.all fun (_, o, t) => sameOnVisible cueLook o t
#guard (lines cueLook 2200 "" "").length == 7

def run' (args : List String) : IO UInt32 := do
  let pick (w : String) : Option (String × String) :=
    if w == "accent" then some ("hero-accent-pause", accentText)
    else if w == "cue" then some ("hero-cue-pause", cueText) else none
  match args with
  | [w, "--check", path] =>
    match pick w with
    | none => IO.eprintln "hero-pause golden: first argument is accent or cue"; return 2
    | some (name, txt) =>
      if (← IO.FS.readFile path) == txt then
        IO.eprintln s!"{name} golden: {path} is up to date"
        return 0
      IO.eprintln s!"{name} golden: {path} differs from the generated text"
      return 1
  | [w] =>
    match pick w with
    | none => IO.eprintln "hero-pause golden: first argument is accent or cue"; return 2
    | some (_, txt) => IO.print txt; return 0
  | _ => IO.eprintln "usage: OffscreenPauseGolden <accent|cue> [--check path]"; return 2

end Fw.Parts.OffscreenPauseGolden
