import Lean.Data.Json
import Fw.Parts.ComboScroll
import Fw.Parts.MorphEndGolden
namespace Fw.Parts.MorphEndComboGolden
open Lean Fw.Parts.MorphEnd Fw.Parts.ComboScroll Fw.Parts.MorphEndGolden

def cevJ (p : Ev × Bool) : Json :=
  match evJ p.1 with
  | .obj kvs => .obj (kvs.insert "cancelable" (.bool p.2))
  | j => j

def woutJ (o : Out) (w : W) : Json :=
  match outJ o w.s with
  | .obj kvs => .obj (kvs.insert "held" (.bool w.held))
  | j => j

def run (h : Hooks) : W → List (Ev × Bool) → List (Ev × Out × W)
  | _, [] => []
  | w, (e, c) :: t => (e, (wstep h w e c).2, (wstep h w e c).1) :: run h (wstep h w e c).1 t

def mv (finger y now : Rat) : Ev := .touchmove (some finger) (ComboScroll.rd y now)

def sameTouch : Rat × List (Ev × Bool) :=
  (5188, [(.touchstart (some 700), true), (mv 690 5188 0, true), (.tick 700, true), (mv 900 5188 700, true),
    (mv 850 4900 800, false), (.scroll 4950 5188, true), (.tick 900, true), (.scroll 4880 5188, true), (.resize 4880 5188, true),
    (mv 800 4930 820, false), (.scroll 4930 5188, true)])

def momentum : Rat × List (Ev × Bool) :=
  (5188, [(.touchstart (some 700), true), (mv 690 5188 0, true), (.tick 700, true), (mv 900 5188 700, true), (.tick 900, true),
    (.scroll 4700 5188, true), (.touchstart (some 500), true), (mv 450 4650 1000, false), (.scroll 4600 5188, true), (.tick 1200, true),
    (.scroll 4550 5188, true), (.touchstart (some 500), true), (mv 495 4550 1300, true), (.scroll 4551 5188, true), (.scroll 4550 5188, true)])

def heldReopen : Rat × List (Ev × Bool) :=
  (5188, [(.touchstart (some 700), true), (mv 690 5188 0, true), (.tick 700, true), (mv 900 5188 700, true),
    (.touchstart (some 500), true), (mv 450 4900 800, true), (.scroll 4950 5188, true), (.tick 900, true), (.scroll 4900 5188, true)])

def plainOpen : Rat × List (Ev × Bool) :=
  (5100, [(.touchstart (some 600), true), (mv 560 5188 0, true), (.scroll 5188 5188, true), (.tick 100, true), (.scroll 5150 5188, true),
    (mv 540 5188 120, true), (.scroll 5188 5188, true)])

def cases : List (String × Rat × List (Ev × Bool)) :=
  [("same-touch", sameTouch), ("momentum", momentum), ("held-reopen", heldReopen), ("plain-open", plainOpen)]

def caseLine (name : String) (y : Rat) (t : List (Ev × Bool)) (c : Cfg) : String :=
  (Json.mkObj [("fn", "morph.end.combo"),
    ("in", Json.mkObj [("case", .str name), ("cfg", cfgJ c), ("init", numJ y), ("events", .arr (t.map cevJ).toArray)]),
    ("out", .arr ((run c.hooks (W.init y) t).map fun (_, o, w) => woutJ o w).toArray)]).compress

def lines (_ : Unit) : List String := cases.flatMap fun (n, y, t) => Cfg.all.map (caseLine n y t)

#guard (lines ()).length == 4 * 8
#guard cases.all fun (_, y, t) => Cfg.all.all fun c =>
  (run c.hooks (W.init y) t).map (fun (e, o, _) => (e, o)) == wtrace c.hooks (W.init y) t
#guard cases.all fun (_, _, t) => t.all fun
  | (.touchmove (some f) r, _) => f.den == 1 && r.scrollY.den == 1 && r.now.den == 1
  | (.touchstart (some f), _) => f.den == 1
  | (.scroll y m, _) | (.resize y m, _) => y.den == 1 && m.den == 1
  | (.tick now, _) => now.den == 1
  | _ => false

def wouts (c : Cfg) (cs : Rat × List (Ev × Bool)) : List Out := (wtrace c.hooks (W.init cs.1) cs.2).map (·.2)
def iouts (c : Cfg) (cs : Rat × List (Ev × Bool)) : List Out := (trace c.hooks (init cs.1) (cs.2.map (·.1))).map (·.2)

#guard (iouts ⟨true, true, true⟩ sameTouch).map (·.write) ==
  [none, none, none, none, none, some 4900, none, some 4900, some 4900, none, some 4900]
#guard (wouts ⟨true, true, true⟩ sameTouch).map (·.write) ==
  [none, none, none, none, none, none, none, none, none, none, none]
#guard (wouts ⟨true, true, true⟩ momentum).map (·.write) ==
  [none, none, none, none, none, none, none, none, none, none, none, none, none, some 4550, none]
#guard (iouts ⟨true, true, true⟩ momentum).map (·.write) ==
  [none, none, none, none, none, none, none, none, some 4650, none, some 4650, none, none, some 4650, some 4650]
#guard cases.all fun cs => Cfg.all.all fun c => !c.release || cs.1 != "plain-open" || wouts c cs.2 == iouts c cs.2
#guard cases.all fun cs => Cfg.all.all fun c => c.release || wouts c cs.2 == iouts c cs.2
#guard wouts ⟨true, true, true⟩ heldReopen == iouts ⟨true, true, true⟩ heldReopen

def text (_ : Unit) : String := String.intercalate "\n" (lines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == text () then
      IO.eprintln s!"combo-scroll golden: {path} is up to date"
      return 0
    IO.eprintln s!"combo-scroll golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (text ())
    return 0

end Fw.Parts.MorphEndComboGolden
