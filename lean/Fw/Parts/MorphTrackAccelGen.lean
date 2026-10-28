import Lean.Data.Json
import Fw.Parts.MorphTrackAccel
import Fw.Parts.MorphGeomGen
namespace Fw.Parts.MorphTrackAccel
open Lean Fw.Parts.MorphGeom Fw.Engine.TransitionStart

def allProps : List AnimProp := [.translate, .scale, .transformList, .opacity, .blur, .backdropBlur]

def trackKey (a : Anim) : String := s!"{a.el}:{a.key.1}:{a.key.2}:{a.prop.css}"

def propLines (_ : Unit) : List String :=
  [Eng.webkit, .chromium].flatMap fun e =>
    allProps.map fun p =>
      gline "prop" [("eng", .str (engTag e)), ("prop", .str p.css)]
        (Json.mkObj [("why", .str (propWhy e p).name), ("timed", .bool (onCompositor e .timed p)),
          ("scrubbed", .bool (onCompositor e .scrubbed p))])

def modeLines (_ : Unit) : List String :=
  [Mode.scrubbed, .timed].map fun m =>
    gline "mode" [("mode", .str m.name)] (Json.mkObj [("why", .str (playWhy m).name)])

/-- One line per band viewport and engine: every track key, the tracks the main thread keeps in each mode. -/
def trackLines (_ : Unit) : List String :=
  bandVps.flatMap fun v =>
    [Eng.webkit, .chromium].map fun e =>
      let as := anims v (Ctx.sample v e)
      gline "tracks" [("w", .num ⟨v.w.num, 0⟩), ("h", .num ⟨v.h.num, 0⟩), ("eng", .str (engTag e))]
        (Json.mkObj [("n", .num ⟨as.length, 0⟩),
          ("keys", jl (as.map fun a => .str (trackKey a))),
          ("ks", jl (as.map fun a => .str a.ks.name)),
          ("timedMain", jl ((as.filter fun a => !onCompositorTrack e .timed v a).map fun a => .str (trackKey a))),
          ("timedMainWhy", jl ((as.filter fun a => !onCompositorTrack e .timed v a).map fun a => .str (whyTrack e .timed v a).name)),
          ("scrubbedMain", .num ⟨mainTracks e .scrubbed as, 0⟩),
          ("blur", .num ⟨blurTracks as, 0⟩)])

def goldenText (_ : Unit) : String := String.join ((propLines () ++ modeLines () ++ trackLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"morph-track-accel golden: {path} is up to date"
      return 0
    IO.eprintln s!"morph-track-accel golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.MorphTrackAccel
