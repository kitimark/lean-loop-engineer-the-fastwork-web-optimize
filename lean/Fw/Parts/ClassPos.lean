import Lean.Data.Json
namespace Fw.Parts.ClassPos

inductive E where
  | str (s : String)
  | id (n : String)
  | cmp (a b : E)
  | cond (t c a : E)
  | and (l r : E)
  | or (l r : E)
  | nullish (l r : E)
  | tmpl (qs : List String) (es : List E)
  | arr (es : List E)
  | helper (name : String) (args : List E)
  | joined (es : List E)
  | call (name : String) (args : List E)

def tokens (s : String) : List String := ((s.split Char.isWhitespace).toList.map toString).filter (· ≠ "")

mutual
def classes : E → List String
  | .str s => tokens s
  | .id _ => []
  | .cmp _ _ => []
  | .cond _ c a => classes c ++ classes a
  | .and _ r => classes r
  | .or l r => classes l ++ classes r
  | .nullish l r => classes l ++ classes r
  | .tmpl qs es => (qs.flatMap tokens) ++ classesList es
  | .arr es => classesList es
  | .helper _ args => classesList args
  | .joined es => classesList es
  | .call _ _ => []
def classesList : List E → List String
  | [] => []
  | e :: es => classes e ++ classesList es
end

theorem cond_test_irrelevant (t t' c a : E) : classes (.cond t c a) = classes (.cond t' c a) := rfl

theorem and_left_irrelevant (l l' r : E) : classes (.and l r) = classes (.and l' r) := rfl

theorem cmp_empty (a b : E) : classes (.cmp a b) = [] := rfl

theorem or_both (l r : E) : classes (.or l r) = classes l ++ classes r := rfl

theorem nullish_both (l r : E) : classes (.nullish l r) = classes l ++ classes r := rfl

theorem and_right (l r : E) : classes (.and l r) = classes r := rfl

theorem cond_branches (t c a : E) : classes (.cond t c a) = classes c ++ classes a := rfl

theorem joined_all (es : List E) : classes (.joined es) = classesList es := rfl

theorem call_empty (n : String) (args : List E) : classes (.call n args) = [] := rfl

theorem helper_args (n : String) (args : List E) : classes (.helper n args) = classesList args := rfl

theorem tmpl_all (qs : List String) (es : List E) : classes (.tmpl qs es) = qs.flatMap tokens ++ classesList es := rfl

mutual
def render : E → String
  | .str s => "'" ++ s ++ "'"
  | .id n => n
  | .cmp a b => "(" ++ render a ++ " === " ++ render b ++ ")"
  | .cond t c a => "(" ++ render t ++ " ? " ++ render c ++ " : " ++ render a ++ ")"
  | .and l r => "(" ++ render l ++ " && " ++ render r ++ ")"
  | .or l r => "(" ++ render l ++ " || " ++ render r ++ ")"
  | .nullish l r => "(" ++ render l ++ " ?? " ++ render r ++ ")"
  | .tmpl qs es => "`" ++ renderTmpl qs es ++ "`"
  | .arr es => "[" ++ ", ".intercalate (renderList es) ++ "]"
  | .helper n args => n ++ "(" ++ ", ".intercalate (renderList args) ++ ")"
  | .joined es => "[" ++ ", ".intercalate (renderList es) ++ "].filter(Boolean).join(' ')"
  | .call n args => n ++ "(" ++ ", ".intercalate (renderList args) ++ ")"
def renderList : List E → List String
  | [] => []
  | e :: es => render e :: renderList es
def renderTmpl : List String → List E → String
  | [], _ => ""
  | q :: qs, [] => q ++ renderTmpl qs []
  | q :: qs, e :: es => q ++ "${" ++ render e ++ "}" ++ renderTmpl qs es
end

private def s (x : String) : E := .str x
private def v (x : String) : E := .id x

def cases : List E :=
  [ s "a b",
    .cond (.cmp (v "role") (s "exit")) (s "on") (s "off"),
    .cond (v "x") (s "on") (v "y"),
    .and (v "open") (s "is-open"),
    .and (s "gate") (s "kept"),
    .or (s "fallback") (v "x"),
    .or (v "x") (s "fallback"),
    .nullish (v "x") (s "dflt"),
    .nullish (s "first") (s "second"),
    .cmp (s "x") (s "y"),
    .tmpl ["row ", " tail"] [.cond (v "f") (s "flip") (s "")],
    .tmpl ["a ", ""] [.cmp (v "r") (s "exit")],
    .arr [s "p", .and (v "q") (s "q-on"), .cmp (v "r") (s "no")],
    .helper "cx" [v "css.row", .and (v "flip") (s "rowFlip"), .cond (.cmp (v "k") (s "no")) (s "yes") (s "")],
    .helper "clsx" [s "a", .cmp (v "r") (s "exit")],
    .joined [s "o", .and (v "a") (s "is-a"), .and (.cmp (v "b") (s "z")) (s "is-b")],
    .helper "cls" [s "tab", .and (.cmp (v "id") (s "act")) (s "isActive")],
    .call "other" [s "ignored"],
    .and (.cmp (v "r") (s "exit")) (.cond (v "z") (s "deep") (.and (v "w") (s "deeper")))]

def row (e : E) : Lean.Json :=
  Lean.Json.mkObj [("src", render e), ("classes", Lean.Json.arr ((classes e).map Lean.Json.str).toArray)]

def goldenText : String := String.join (cases.map fun e => (row e).compress ++ "\n")

#guard (cases.map classes).take 3 == [["a", "b"], ["on", "off"], ["on"]]
#guard (cases.map classes).getLast? == some ["deep", "deeper"]

/-- Print the golden, or with `--check <file>` compare it byte for byte (exit 1 on a difference). -/
def run (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    let cur ← IO.FS.readFile path
    if cur == goldenText then
      IO.eprintln s!"footprint classpos golden: {path} is up to date ({cases.length} lines)"
      return 0
    IO.eprintln s!"footprint classpos golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print goldenText
    return 0

end Fw.Parts.ClassPos
