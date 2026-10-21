import Lean.Data.Json
import Fw.Oracle.Labels

/-! Write (or with `--check`, verify) `packages/contracts/golden/oracle/labels.jsonl` (Fw.Oracle.Labels). -/

open Lean Fw.Oracle.Labels

def strs (l : List String) : Json := .arr (l.map Json.str).toArray

def optStr (o : Option String) : Json := match o with | some s => .str s | none => .null

def gradeName : Grade → String
  | .blocker => "blocker" | .fixBeforeLand => "fix-before-land" | .followUp => "follow-up"

def tierName : Tier → String
  | .exact => "exact" | .legacy => "legacy"

def regradeName : Option Regrade → Option String
  | none => none | some .dismissed => some "dismissed" | some (.grade g) => some (gradeName g)

def causeName : Cause → String
  | .ours => "ours" | .flake => "flake" | .infra => "infra"

def triageName : Triage → String
  | .ignore => "ignore" | .mitigate => "mitigate" | .askUser => "ask-user"

def audName : Audience → String
  | .user => "user" | .lead => "lead" | .unset => "unset"

def endName : End → String
  | .userActed => "user-acted" | .leadCancelled => "lead-cancelled" | .autoResolved => "auto-resolved"
  | .scriptCancelled => "script-cancelled" | .open => "open"

def row (kind : String) (fs : List (String × Json)) : Json := Json.mkObj (("kind", .str kind) :: fs)

def hashIds : List String :=
  ["", "a", "inc-orphan-wait-loop", "inc-ci-hardcoded-expect", "adv:jev-oracle#2", "run-39641571077", "ü", "日本"]

def severityTexts : List String :=
  ["blocker", "fix-before-land", "follow-up", " Blocker ", "FIX-BEFORE-LAND", "high", "High", "major", "critical", "blocking",
   "low", "minor", "nit", "medium", "moderate", "info", "verified", "note", "process", "lead-decision", "",
   "low (follow-up)", "high (follow-up, outside the pinned unit)", "major (blocking, pinned unit: measured medians explained)",
   "medium (follow-up, below pinned unit)", "info (follow-up)", "info (verified)", "minor (follow-up; Linux WebKit is an accepted no-verdict limit)",
   "follow-up (accepted, not in unit)", "medium (do before land)", "major (lead action before land; branch content is correct)"]

def fableLines : List String :=
  ["1. blocker, real defect. Re-ran the reviewer's pair", "R2-4 (G_6 LaTeX block): reviewer error for this task.",
   "R2-5 (premise text incomplete): real, low value. CONFIRMED", "F3 low, prose: real but low value. CONFIRMED",
   "| 3 | minor | real, low value | RenderLayerCompositor", "rule noise: the lint does not apply", "reviewer error but real, low value", "2. major, real."]

def phraseTexts : List String :=
  ["error: SSL connect error (TLS connect error)", "Failed to CreateArtifact: Unable to make request: ECONNRESET",
   "Process completed with exit code 1.", "AssertionError [ERR_ASSERTION]: expected 3", "premises: FAILED",
   "FAIL: fast1: no tab (0 tabs)", "trajectory-line: refused: widths 390,641 is a subset", "src/a.ts(3,1): error TS2322: Type"]

def bools : List Bool := [false, true]

def ciCases : List CiFacts :=
  bools.flatMap fun a => bools.flatMap fun b => bools.flatMap fun c => bools.flatMap fun d => bools.flatMap fun e =>
    bools.map fun f => ⟨a, b, c, d, e, f⟩

def factsJson (f : CiFacts) : Json :=
  Json.mkObj [("failure", .bool f.failure), ("logKnown", .bool f.logKnown), ("covered", .bool f.covered),
    ("passedSameSha", .bool f.passedSameSha), ("infraSig", .bool f.infraSig), ("codeSig", .bool f.codeSig)]

def rows : List Json :=
  [row "split" [("mod", (splitMod : Nat)), ("offset", (fnvOffset : Nat)), ("prime", (fnvPrime : Nat))],
   row "classes" [("ids", strs mistakeClasses)],
   row "words" [("table", .arr (wordTable.map fun p => Json.arr #[.str p.1, .str (gradeName p.2)]).toArray),
     ("exact", strs exactWords), ("followTag", .str followTag)],
   row "fable-phrases" [("dismiss", strs dismissPhrases), ("lowValue", strs lowValuePhrases)],
   row "ci-phrases" [("infra", strs infraPhrases), ("code", strs codePhrases)]]
  ++ hashIds.map (fun id => row "hash" [("id", .str id), ("hash", (fnv1a id : Nat)), ("heldOut", .bool (heldOut id))])
  ++ (mistakeClasses ++ ["c-nonsense", ""]).map (fun c => row "d1" [("class", .str c), ("label", optStr (d1Label c))])
  ++ severityTexts.map (fun t =>
      let r := severity t
      row "severity" [("text", .str t), ("grade", optStr (r.map (gradeName ·.1))), ("tier", optStr (r.map (tierName ·.2))),
        ("inUnit", match r with | some (g, _) => .bool (inUnit g) | none => .null)])
  ++ fableLines.map (fun t => row "fable" [("line", .str t), ("regrade", optStr (regradeName (fableRegrade t)))])
  ++ [(0, 0), (3, 3), (3, 2), (2, 3), (5, 5), (0, 4)].map (fun p =>
      row "applies" [("findings", (p.1 : Nat)), ("parsed", (p.2 : Nat)), ("ok", .bool (regradeApplies p.1 p.2))])
  ++ ([some Grade.blocker, some .followUp, none].flatMap fun o =>
      [none, some (Regrade.grade .followUp), some (.grade .blocker), some .dismissed].map fun rg =>
        row "apply" [("orig", optStr (o.map gradeName)), ("regrade", optStr (regradeName rg)),
          ("label", optStr ((applyRegrade o rg).map gradeName))])
  ++ phraseTexts.map (fun t => row "phrase" [("text", .str t), ("infra", .bool (hasPhrase infraPhrases t)),
      ("code", .bool (hasPhrase codePhrases t))])
  ++ ciCases.map (fun f => row "ci" [("facts", factsJson f), ("cause", optStr ((ciCause f).map causeName))])
  ++ ([Audience.user, .lead, .unset].flatMap fun a =>
      [End.userActed, .leadCancelled, .autoResolved, .scriptCancelled, .open].flatMap fun e =>
        bools.map fun r =>
          row "alert" [("audience", .str (audName a)), ("end", .str (endName e)), ("restartText", .bool r),
            ("triage", optStr ((alertTriage a e r).map triageName))])

def text : String := String.intercalate "\n" (rows.map Json.compress) ++ "\n"

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "oracle" / "labels.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"oracle labels golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OracleLabelsGolden.lean)"
      return 1
    IO.println s!"oracle labels golden: {n} lines, up to date"
    return 0
  if let some d := p.parent then IO.FS.createDirAll d
  IO.FS.writeFile p text
  IO.println s!"oracle labels golden: {n} lines written"
  return 0
