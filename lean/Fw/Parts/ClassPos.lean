import Lean.Data.Json
/-!
# Which expression positions hold a class name

The footprint extractor reads `className={...}` and records the string literals that can end up as the element's
class. A literal is a class value only in a position whose value flows into the class string. A literal in the
`test` of a conditional or in an operand of a comparison only picks a branch (`role === 'exit'`) and is never a class.

`E` is the small expression language the rule is stated on, `classes` is the set of class tokens in order, and
`render` prints an `E` as JavaScript so the extractor is checked on the same cases (`golden/parts/footprint.classpos.jsonl`).
-/
namespace Fw.Parts.ClassPos

/-- The expression shapes that matter for the position rule. -/
inductive E where
  /-- A string literal. -/
  | str (s : String)
  /-- An identifier, whose value is not known statically. -/
  | id (n : String)
  /-- `a === b`, a comparison. -/
  | cmp (a b : E)
  /-- `t ? c : a`. -/
  | cond (t c a : E)
  /-- `l && r`. -/
  | and (l r : E)
  /-- `l || r`. -/
  | or (l r : E)
  /-- `l ?? r`. -/
  | nullish (l r : E)
  /-- A template literal: the quasis, then the expressions. -/
  | tmpl (qs : List String) (es : List E)
  /-- An array literal. -/
  | arr (es : List E)
  /-- A call of a class-joining helper (`cx`, `cls`, `clsx`, `classNames`). -/
  | helper (name : String) (args : List E)
  /-- `[a, b].filter(Boolean).join(' ')`: the elements joined into one class string. -/
  | joined (es : List E)
  /-- A call of any other function. -/
  | call (name : String) (args : List E)

/-- Whitespace-separated tokens of a literal. -/
def tokens (s : String) : List String := ((s.split Char.isWhitespace).toList.map toString).filter (· ≠ "")

mutual
/-- The class tokens of an expression, in source order.

Only class-value positions count: the expression itself, the branches of a conditional (never its test), the right
operand of `&&` (never the left), both operands of `||` and `??`, template quasis and expressions, array elements, joined array
elements and helper-call arguments. A comparison and an ordinary call contribute nothing. -/
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
/-- The class tokens of a list of expressions, in order. -/
def classesList : List E → List String
  | [] => []
  | e :: es => classes e ++ classesList es
end

/-- The test of a conditional never changes the classes. -/
theorem cond_test_irrelevant (t t' c a : E) : classes (.cond t c a) = classes (.cond t' c a) := rfl

/-- The left of `&&` never changes the classes. -/
theorem and_left_irrelevant (l l' r : E) : classes (.and l r) = classes (.and l' r) := rfl

/-- A comparison holds no class, whatever its operands. -/
theorem cmp_empty (a b : E) : classes (.cmp a b) = [] := rfl

/-- `||` keeps both operands. -/
theorem or_both (l r : E) : classes (.or l r) = classes l ++ classes r := rfl

/-- `??` keeps both operands. -/
theorem nullish_both (l r : E) : classes (.nullish l r) = classes l ++ classes r := rfl

/-- `&&` keeps only the right operand. -/
theorem and_right (l r : E) : classes (.and l r) = classes r := rfl

/-- A conditional keeps both branches. -/
theorem cond_branches (t c a : E) : classes (.cond t c a) = classes c ++ classes a := rfl

/-- A joined array keeps every element. -/
theorem joined_all (es : List E) : classes (.joined es) = classesList es := rfl

/-- An ordinary call holds no class. -/
theorem call_empty (n : String) (args : List E) : classes (.call n args) = [] := rfl

/-- A helper call keeps every argument. -/
theorem helper_args (n : String) (args : List E) : classes (.helper n args) = classesList args := rfl

/-- A template keeps its quasis and every expression. -/
theorem tmpl_all (qs : List String) (es : List E) : classes (.tmpl qs es) = qs.flatMap tokens ++ classesList es := rfl

mutual
/-- The expression as JavaScript, fully parenthesised. -/
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
/-- Each expression of a list as JavaScript. -/
def renderList : List E → List String
  | [] => []
  | e :: es => render e :: renderList es
/-- Template body: quasi, `${expr}`, quasi, ... -/
def renderTmpl : List String → List E → String
  | [], _ => ""
  | q :: qs, [] => q ++ renderTmpl qs []
  | q :: qs, e :: es => q ++ "${" ++ render e ++ "}" ++ renderTmpl qs es
end

private def s (x : String) : E := .str x
private def v (x : String) : E := .id x

/-- The golden cases: each is a position the rule decides. -/
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

/-- One golden row: the JavaScript source and its class tokens. -/
def row (e : E) : Lean.Json :=
  Lean.Json.mkObj [("src", render e), ("classes", Lean.Json.arr ((classes e).map Lean.Json.str).toArray)]

/-- The contents of `packages/contracts/golden/parts/footprint.classpos.jsonl`. -/
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
