import Fw.Ops.Attrib
namespace Fw.Ops.AttribGolden
open Lean Fw.Ops.Attrib

def run (commit : String) (flags : List (String × String)) (pass : Bool) : Run := ⟨commit, flags, pass⟩

def cases : List (String × Run × Run) :=
  let park := [("engine.scroll", "unthrottle-park"), ("hero.exit", "threaded-park")]
  let pair := [("engine.scroll", "unthrottle"), ("hero.exit", "threaded")]
  let mixed := [("engine.scroll", "unthrottle"), ("hero.exit", "threaded-park")]
  [("park pair fails, the pair without park passes: two parts differ, not attributable",
      run "c1" park false, run "c1" pair true),
   ("park pair fails, baseline with no flags passes: two parts differ, not attributable",
      run "c1" park false, run "c1" [] true),
   ("mixed pair fails, pair without park passes: one part differs, caused by hero.exit",
      run "c1" mixed false, run "c1" pair true),
   ("same runs, flags listed in another order: same verdict",
      run "c1" [("hero.exit", "threaded-park"), ("engine.scroll", "unthrottle")] false, run "c1" pair true),
   ("the passing run is listed first: the failing value is still named first",
      run "c1" pair true, run "c1" mixed false),
   ("park pair fails, mixed pair passes: one part differs, caused by engine.scroll",
      run "c1" park false, run "c1" mixed true),
   ("a part set in the failing run and absent in the passing run is one differing part",
      run "c1" [("x", "y")] false, run "c1" [] true),
   ("one part differs and both pass: no effect",
      run "c1" [("x", "y")] true, run "c1" [] true),
   ("one part differs and both fail: no effect",
      run "c1" [("x", "y")] false, run "c1" [] false),
   ("the same flag set: nothing differs, not attributable",
      run "c1" pair false, run "c1" pair true),
   ("two commits: not attributable although one part differs",
      run "c1" [("x", "y")] false, run "c2" [] true),
   ("a repeated part counts once",
      run "c1" [("x", "y"), ("x", "y")] false, run "c1" [] true),
   ("runs 41054732597 and 41078004214: park pair against the pair without park, two parts and two commits",
      run "768aebf" park false, run "72d0bfd" pair false),
   ("runs 41078004214 and 41058963051: the pair against the faithful build, two parts and two commits",
      run "72d0bfd" pair false, run "8cb6814" [] true),
   ("runs 41054732597 and 41058963051: the park pair against the faithful build, two parts and two commits",
      run "768aebf" park false, run "8cb6814" [] true),
   ("runs 39774976109 and 41058963051: threaded alone against the faithful build, one part but two commits",
      run "ff8c8cd" [("hero.exit", "threaded")] false, run "8cb6814" [] true),
   ("two runs on one commit, threaded alone against no flags: caused by hero.exit",
      run "c1" [("hero.exit", "threaded")] false, run "c1" [] true),
   ("runs 41087718575 and 41086902481 on one commit, threaded alone against no flags, WebKit: caused by hero.exit",
      run "31fdd85" [("hero.exit", "threaded")] false, run "31fdd85" [] true)]

def name : Verdict → String
  | .causedBy .. => "causedBy"
  | .noEffect _ => "noEffect"
  | .notAttributable => "notAttributable"

def part? : Verdict → Json
  | .causedBy p _ _ | .noEffect p => .str p
  | .notAttributable => .null

def opt (o : Option String) : Json := o.elim .null .str

def vals : Verdict → Json
  | .causedBy _ f p => Json.mkObj [("failing", opt f), ("passing", opt p)]
  | _ => .null

def runJson (r : Run) : Json :=
  Json.mkObj [("commit", .str r.commit), ("flags", .arr (r.flags.map fun (p, v) => Json.arr #[.str p, .str v]).toArray),
    ("pass", .bool r.pass)]

def row (c : String × Run × Run) : Json :=
  let v := verdict c.2.1 c.2.2
  Json.mkObj [("name", .str c.1), ("a", runJson c.2.1), ("b", runJson c.2.2),
    ("verdict", .str (name v)), ("part", part? v), ("values", vals v)]

def jsonl (_ : Unit) : String := String.join (cases.map fun c => (row c).compress ++ "\n")

def gen (args : List String) : IO Unit := do
  let path : System.FilePath := "../packages/contracts/golden/ops/attrib.jsonl"
  let want := jsonl ()
  if args.contains "--check" then
    unless (← IO.FS.readFile path) == want do
      throw (IO.userError s!"attrib: {path} is stale; regenerate with Fw.Ops.AttribGolden.gen []")
  else
    IO.FS.writeFile path want

example : verdict (run "c1" [("x", "y")] false) (run "c2" [] true) = .notAttributable := by decide
example : verdict (run "c1" [("x", "y")] false) (run "c1" [] true) = .causedBy "x" (some "y") none := by decide
example : verdict (run "c1" [("a", "1"), ("b", "2")] false) (run "c1" [] true) = .notAttributable := by decide

end Fw.Ops.AttribGolden
