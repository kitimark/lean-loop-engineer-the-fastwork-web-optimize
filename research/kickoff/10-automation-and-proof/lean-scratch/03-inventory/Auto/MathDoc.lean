import Lean

/-!
# Keeping math and Lean in sync (prototype)

Every theorem in a checked namespace carries a docstring line `math[<tag>]: <formula>`, where
<tag> is a short hash of the theorem's *statement* (its type, pretty-printed). `#math_doc ns`
prints the markdown table the user reads, and fails the build when
  * a theorem has no `math[...]` line, or
  * the statement changed since the math was last written (tag mismatch).
So nobody can change what a theorem says without re-reading and re-signing its math line.
-/
open Lean Elab Command Meta

/-- FNV-1a over the UTF-8 bytes (stable across runs and platforms, unlike the runtime `hash`). -/
def fnv1a (s : String) : UInt64 :=
  s.toUTF8.foldl (fun h b => (h ^^^ b.toUInt64) * 0x100000001b3) 0xcbf29ce484222325

def stmtTag (ty : Expr) : MetaM String := do
  let s := toString (← ppExpr ty)
  return String.ofList (Nat.toDigits 16 ((fnv1a s).toNat % 0x10000))

def mathLine? (doc : String) : Option (String × String) := do
  let line ← (doc.splitOn "\n").find? (fun l => l.trimAscii.toString.startsWith "math[")
  let l := line.trimAscii.toString
  let tag := ((l.drop 5).takeWhile (· != ']')).toString
  let body := ((l.dropWhile (· != ':')).drop 1).trimAscii.toString
  return (tag, body)

elab "#math_doc " ns:ident : command => do
  let env ← getEnv
  let pre := ns.getId
  let mut rows : Array String := #[]
  let mut errs : Array String := #[]
  for (n, ci) in env.constants.map₂.toList do
    unless pre.isPrefixOf n do continue
    if n.isInternalDetail then continue
    let .thmInfo ti := ci | continue
    let tag ← liftTermElabM (stmtTag ti.type)
    let stmt ← liftTermElabM (do return toString (← ppExpr ti.type))
    match (← findDocString? env n) >>= mathLine? with
    | none => errs := errs.push s!"{n}: no math line (statement tag {tag})"
    | some (t, m) =>
      if t != tag then errs := errs.push s!"{n}: statement changed (math tag {t}, now {tag}); re-read and re-tag the math"
      rows := rows.push s!"| `{n.componentsRev.head!}` | {m} | `{stmt.replace "\n" " "}` |"
  let sorted : List String := rows.toList.mergeSort (fun a b => decide (a ≤ b))
  logInfo m!"| theorem | math | Lean statement |\n|---|---|---|\n{"\n".intercalate sorted}"
  unless errs.isEmpty do
    let msg : String := String.intercalate "\n" errs.toList
    throwError msg
