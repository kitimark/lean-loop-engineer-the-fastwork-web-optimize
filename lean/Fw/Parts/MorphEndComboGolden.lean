import Lean.Data.Json
import Fw.Parts.ComboScroll
import Fw.Parts.MorphEndGolden
namespace Fw.Parts.MorphEndComboGolden
open Lean Fw.Parts.MorphEnd Fw.Parts.ComboScroll Fw.Parts.MorphEndGolden

def cevJ (p : Ev × Dlv) : Json :=
  match evJ p.1 with
  | .obj kvs => .obj (((kvs.insert "cancelable" (.bool p.2.cancelable)).insert "passive" (.bool p.2.passive)).insert "other" (.bool p.2.other))
  | j => j

def woutJ (o : Out) (w : W) (dp : Bool) : Json :=
  match outJ o w.s with
  | .obj kvs => .obj ((kvs.insert "held" (.bool w.held)).insert "defaultPrevented" (.bool dp))
  | j => j

def dpOf (e : Ev) (d : Dlv) (o : Out) : Bool := e.isMove && d.prevented o

def run (h : Hooks) : W → List (Ev × Dlv) → List (Ev × Out × W)
  | _, [] => []
  | w, (e, c) :: t => (e, (wstep h w e c).2, (wstep h w e c).1) :: run h (wstep h w e c).1 t

def ot : Dlv := ⟨true, true, true⟩

def mv (finger y now : Rat) : Ev := .touchmove (some finger) (ComboScroll.rd y now)

def sameTouch : Rat × List (Ev × Dlv) :=
  (5188, [(.touchstart (some 700), ok), (mv 690 5188 0, ok), (.tick 700, ok), (mv 900 5188 700, ok),
    (mv 850 4900 800, nc), (.scroll 4950 5188, ok), (.tick 900, ok), (.scroll 4880 5188, ok), (.resize 4880 5188, ok),
    (mv 800 4930 820, nc), (.scroll 4930 5188, ok)])

def momentum : Rat × List (Ev × Dlv) :=
  (5188, [(.touchstart (some 700), ok), (mv 690 5188 0, ok), (.tick 700, ok), (mv 900 5188 700, ok), (.tick 900, ok),
    (.scroll 4700 5188, ok), (.touchstart (some 500), ok), (mv 450 4650 1000, nc), (.scroll 4600 5188, ok), (.tick 1200, ok),
    (.scroll 4550 5188, ok), (.touchstart (some 500), ok), (mv 495 4550 1300, ok), (.scroll 4551 5188, ok), (.scroll 4550 5188, ok)])

def heldReopen : Rat × List (Ev × Dlv) :=
  (5188, [(.touchstart (some 700), ok), (mv 690 5188 0, ok), (.tick 700, ok), (mv 900 5188 700, ok),
    (.touchstart (some 500), ok), (mv 450 4900 800, ok), (.scroll 4950 5188, ok), (.tick 900, ok), (.scroll 4900 5188, ok)])

def plainOpen : Rat × List (Ev × Dlv) :=
  (5100, [(.touchstart (some 600), ok), (mv 560 5188 0, ok), (.scroll 5188 5188, ok), (.tick 100, ok), (.scroll 5150 5188, ok),
    (mv 540 5188 120, ok), (.scroll 5188 5188, ok)])

def passiveReopen : Rat × List (Ev × Dlv) :=
  (5188, [(.touchstart (some 700), ok), (mv 690 5188 0, ok), (.tick 700, ok), (mv 900 5188 700, ok),
    (mv 850 4900 800, ps), (.scroll 4950 5188, ok), (.tick 900, ok), (.scroll 4880 5188, ok), (.resize 4880 5188, ok),
    (mv 800 4930 820, ps), (.scroll 4930 5188, ok)])

def otherPrevented : Rat × List (Ev × Dlv) :=
  (5188, [(.touchstart (some 700), ok), (mv 690 5188 0, ok), (.tick 700, ok), (mv 900 5188 700, ok),
    (mv 850 4900 800, ot), (.scroll 4950 5188, ok), (.tick 900, ok), (.scroll 4880 5188, ok)])

def cases : List (String × Rat × List (Ev × Dlv)) :=
  [("same-touch", sameTouch), ("momentum", momentum), ("held-reopen", heldReopen), ("plain-open", plainOpen),
    ("passive-reopen", passiveReopen), ("other-prevented", otherPrevented)]

def caseLine (name : String) (y : Rat) (t : List (Ev × Dlv)) (c : Cfg) : String :=
  (Json.mkObj [("fn", "morph.end.combo"),
    ("in", Json.mkObj [("case", .str name), ("cfg", cfgJ c), ("init", numJ y), ("events", .arr (t.map cevJ).toArray)]),
    ("out", .arr (((t.zip (run c.hooks (W.init y) t)).map fun ((_, d), (e, o, w)) => woutJ o w (dpOf e d o)).toArray))]).compress

def lines (_ : Unit) : List String := cases.flatMap fun (n, y, t) => Cfg.all.map (caseLine n y t)

#guard (lines ()).length == 6 * 8
#guard cases.all fun (_, y, t) => Cfg.all.all fun c =>
  (run c.hooks (W.init y) t).map (fun (e, o, _) => (e, o)) == wtrace c.hooks (W.init y) t
#guard cases.all fun (_, _, t) => t.all fun
  | (.touchmove (some f) r, _) => f.den == 1 && r.scrollY.den == 1 && r.now.den == 1
  | (.touchstart (some f), _) => f.den == 1
  | (.scroll y m, _) | (.resize y m, _) => y.den == 1 && m.den == 1
  | (.tick now, _) => now.den == 1
  | _ => false

def wouts (c : Cfg) (cs : Rat × List (Ev × Dlv)) : List Out := (wtrace c.hooks (W.init cs.1) cs.2).map (·.2)
def iouts (c : Cfg) (cs : Rat × List (Ev × Dlv)) : List Out := (trace c.hooks (init cs.1) (cs.2.map (·.1))).map (·.2)

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
#guard (wouts ⟨true, true, true⟩ passiveReopen).all (·.write == none)
#guard (iouts ⟨true, true, true⟩ passiveReopen).any (·.write != none)
#guard (wouts ⟨true, true, true⟩ otherPrevented).map (·.write) == [none, none, none, none, none, some 4900, none, some 4900]
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
