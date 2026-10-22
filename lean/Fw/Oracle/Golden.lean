import Fw.Wire
import Fw.Ops.Golden
import Fw.Oracle.Wire
/-! Golden vectors and fixture replies of the `oracle.*` ops, generated from Lean. -/
namespace Fw.Wire.Oracle.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)
open Fw.Oracle
open Fw.Wire.Oracle (sampleReply)

def replyField (text : String) : String := (Json.str text).compress

def confReal : String := sampleReply "real" "0.01" "0.01" "0.97" "0.01"

def unsureFlake : String := sampleReply "flake" "0.4" "0.3" "0.2" "0.1"

def confUnknown : String := sampleReply "unknown" "0.01" "0.01" "0.01" "0.97"

def missingProb : String :=
  "{\"model\":\"jev-1.13.0\",\"answers\":{\"ci-triage\":{\"type\":\"choice\",\"choice\":\"real\"," ++
  "\"probabilities\":{\"flake\":0.5,\"real\":0.5}}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"

def otherModel : String :=
  "{\"model\":\"jev-1.14.0\",\"answers\":{\"ci-triage\":{\"type\":\"choice\",\"choice\":\"real\"," ++
  "\"probabilities\":{\"flake\":0,\"infra\":0,\"real\":1,\"unknown\":0}}},\"usage\":{}}"

def tieSum : String := sampleReply "real" "0.1" "0.1" "0.9" "0.1"

def overSum : String := sampleReply "real" "0.1" "0.1" "0.9" "0.3"

def roundedSum : String := sampleReply "real" "0.01" "0.01" "0.96" "0.01"

def foreignPick : String := sampleReply "billing" "0.25" "0.25" "0.25" "0.25"

def confFlake : String := sampleReply "flake" "0.97" "0.01" "0.01" "0.01"

def confInfra : String := sampleReply "infra" "0.01" "0.97" "0.01" "0.01"

def pickNotMaxFlake : String := sampleReply "real" "0.97" "0.01" "0.01" "0.01"

def pickNotMaxUnknown : String := sampleReply "real" "0.01" "0.01" "0.01" "0.97"

/-- The first id `r<n>`, `r<n>-1`, ... that `heldOut` puts in the wanted part. -/
def idIn (held : Bool) (n : Nat) : String :=
  let b := s!"r{n}"
  let cands := b :: (List.range 64).map fun k => s!"{b}-{k + 1}"
  (cands.find? (heldOut · == held)).getD b

def rowsIn (held : Bool) (n0 : Nat) (gs : List (Nat × String × String)) : List (String × String × String) :=
  let rs := gs.flatMap fun (n, reply, label) => List.replicate n (reply, label)
  ((List.range rs.length).zip rs).map fun (k, r, l) => (idIn held (n0 + k), r, l)

def setIn (cs hs : List (Nat × String × String)) (extra : Nat := 0) : String :=
  let c := rowsIn false 0 cs
  let h := rowsIn true c.length hs
  let ex := (List.range extra).map fun k => idIn (k % 2 == 1) (c.length + h.length + k)
  let labeled : List (String × String) := ((c ++ h).map fun (i, _, l) => (i, l)) ++ ex.map fun i => (i, "real")
  let replay := labeled.map fun (i, l) => s!"\{\"id\":\"{i}\",\"label\":\"{l}\"}"
  let answers := (c ++ h).map fun (i, r, _) => s!"\{\"id\":\"{i}\",\"reply\":{replyField r}}"
  s!"\"replay\":[{",".intercalate replay}],\"answers\":[{",".intercalate answers}]"

def setJ (gs : List (Nat × String × String)) (extra : Nat := 0) : String := setIn gs gs extra

#guard (rowsIn true 0 [(4, "x", "l")]).all fun (i, _, _) => heldOut i
#guard (rowsIn false 0 [(4, "x", "l")]).all fun (i, _, _) => !heldOut i

def balancedG : List (Nat × String × String) := [(5, confFlake, "flake"), (5, confInfra, "infra"), (5, confReal, "real"),
  (2, unsureFlake, "real")]

def balancedH : List (Nat × String × String) := [(25, confFlake, "flake"), (25, confInfra, "infra"),
  (25, confReal, "real"), (2, unsureFlake, "real")]

/-- The balanced set: `balancedG` in the choose part, `balancedH` in the holdout part. -/
def balanced : String := setIn balancedG balancedH

def lopsided : String := setJ [(27, confReal, "real"), (1, confReal, "flake")]

/-- A holdout evaluation set: 3 confident hits. -/
def heldout : String := setIn [(2, confReal, "flake")] [(3, confReal, "real"), (1, confFlake, "infra"),
  (1, unsureFlake, "flake"), (1, "<html>", "real")]

def contradictG : List (Nat × String × String) := [(5, confFlake, "real"), (5, confInfra, "real"), (5, confReal, "flake")]

def allAt (num den : String) : String :=
  let r := s!"\{\"num\":\"{num}\",\"den\":\"{den}\"}"
  s!"\"thresholds\":\{\"flake\":{r},\"infra\":{r},\"real\":{r}}"

/-- The threshold table with 1/2 for every option. -/
def half : String := allAt "1" "2"

def daysJ (d : String) (n : Nat) : String := (toJson (List.replicate n d)).compress

def constantReal : String := setJ [(5, confReal, "flake"), (5, confReal, "infra"), (90, confReal, "real")]

def round3G : List (Nat × String × String) := [(5, confFlake, "flake"), (11, confFlake, "real"),
  (5, confInfra, "infra"), (90, confReal, "real")]

def round3 : String := setJ round3G

def round5 : String := setIn balancedG round3G

def nearMiss : String := setIn balancedG [(15, confFlake, "flake"), (1, confFlake, "real"),
  (25, confInfra, "infra"), (25, confReal, "real")]

def planJ (logged : List Bool) : String :=
  let rows := (List.range logged.length).map fun i => s!"\{\"id\":\"r{i}\",\"label\":\"real\"}"
  s!"\{\"rows\":[{",".intercalate rows}],\"logged\":{(toJson logged).compress}}"

/-- The wire cases: (name, op, request without op). -/
def cases : List (String × String × Json) := [
  ("question: the CI-triage question", "oracle.question", lit "{\"name\":\"ci-triage\"}"),
  ("question: an unknown name is an error", "oracle.question", lit "{\"name\":\"nope\"}"),
  ("budget: 200 a day, 60 a calibration run", "oracle.budget", lit "{}"),
  ("redact: home path, e-mail, token, address", "oracle.redact",
    lit "{\"text\":\"/Users/example/src/a.ts:3 by a@example.com ghp_ABCDEFGH12345678 at 203.0.113.9\"}"),
  ("redact: a listed name on a word boundary", "oracle.redact",
    lit "{\"names\":[\"octocat\"],\"text\":\"pushed by octocat to main\"}"),
  ("request: the body carries the redacted state and the pinned model", "oracle.request",
    lit "{\"name\":\"ci-triage\",\"state\":{\"job\":\"build\",\"log\":[\"at /home/example/w/x.lean:1\",\"ok\"]}}"),
  ("pre: a logged request is replayed", "oracle.pre",
    lit "{\"name\":\"ci-triage\",\"state\":{\"log\":\"/Users/example/x\"},\"logged\":true,\"today\":\"2026-10-18\"}"),
  ("pre: a field the question does not declare is refused (undeclared)", "oracle.pre",
    lit "{\"name\":\"ci-triage\",\"state\":{\"job\":\"build\",\"note\":\"ok\"},\"today\":\"2026-10-18\"}"),
  ("pre: a declared state sends the body Lean built, with the home path redacted", "oracle.pre",
    lit "{\"name\":\"ci-triage\",\"state\":{\"job\":\"build\",\"step\":\"lake test\",\"log\":[\"/Users/example/x\",\"ok\"]},\"today\":\"2026-10-18\"}"),
  ("pre: the daily cap reached is over budget", "oracle.pre",
    lit s!"\{\"name\":\"ci-triage\",\"state\":\{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":{daysJ "2026-10-18" 200}}"),
  ("pre: one under the daily cap sends", "oracle.pre",
    lit s!"\{\"name\":\"ci-triage\",\"state\":\{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":{daysJ "2026-10-18" 199}}"),
  ("pre: the run cap reached is over budget", "oracle.pre",
    lit "{\"name\":\"ci-triage\",\"state\":{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"run\":60}"),
  ("pre: an unlogged declared state under both caps sends", "oracle.pre",
    lit "{\"name\":\"ci-triage\",\"state\":{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":[\"2026-10-17\"],\"run\":59}"),
  ("plan: 60 logged and 10 missing rows resume within the run cap", "oracle.plan",
    lit (planJ (List.replicate 60 true ++ List.replicate 10 false))),
  ("plan: 70 missing rows do not fit one run", "oracle.plan",
    lit (planJ (List.replicate 70 false))),
  ("plan: unlabeled rows are skipped, both parts are planned; ids from runId", "oracle.plan",
    lit "{\"rows\":[{\"runId\":7,\"label\":\"real\"},{\"id\":\"a\",\"label\":\"real\"},{\"id\":\"c\",\"label\":null},{\"id\":\"b\",\"label\":\"flake\"}]}"),
  ("plan: a row naming a split is an error (Lean splits by id)", "oracle.plan",
    lit "{\"rows\":[{\"id\":\"b\",\"split\":\"heldout\",\"label\":\"real\"}]}"),
  ("validate: a well-formed reply, gate recomputed exactly", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField confReal}}"),
  ("validate: not JSON is malformed", "oracle.validate", lit "{\"name\":\"ci-triage\",\"reply\":\"<html>\"}"),
  ("validate: a missing probability is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField missingProb}}"),
  ("validate: another model version is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField otherModel}}"),
  ("validate: 0.01, 0.01, 0.96, 0.01 (sum 0.99, two decimals) is accepted as a rounding", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField roundedSum}}"),
  ("validate: 0.1, 0.1, 0.9, 0.1 (sum 1.2) rounds 0.05, 0.05, 0.85, 0.05 to one decimal and is accepted", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField tieSum}}"),
  ("validate: 0.1, 0.1, 0.9, 0.3 (sum 1.4) is no one-decimal rounding and is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField overSum}}"),
  ("validate: a pick outside the options is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField foreignPick}}"),
  ("decide: uncalibrated escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField confReal}}"),
  ("decide: calibrated and confident advises", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":{replyField confReal}}"),
  ("decide: below the threshold escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":{replyField unsureFlake}}"),
  ("decide: a confident no-match escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":{replyField confUnknown}}"),
  ("decide: an answer meets only its own option's threshold (flake uncalibrated, real at 1/2)", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"thresholds\":\{\"flake\":null,\"real\":\{\"num\":\"1\",\"den\":\"2\"}},\"reply\":{replyField confFlake}}"),
  ("decide: a key that is not an advisable option is an error", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"thresholds\":\{\"unknown\":\{\"num\":\"1\",\"den\":\"2\"}},\"reply\":{replyField confReal}}"),
  ("decide: rate limited (429) escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"failure\":\{\"kind\":\"http\",\"status\":429}}"),
  ("decide: a timeout escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"failure\":\{\"kind\":\"timeout\"}}"),
  ("decide: no key escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"failure\":\{\"kind\":\"noKey\"}}"),
  ("decide: a malformed reply escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":\"\{\"}"),
  ("calibrate: 5 confident hits per option in the choose part and 25 in the holdout part give the confident gate",
    "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{balanced}}"),
  ("calibrate: an option with fewer than 5 covered rows gives none", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn [(5, confFlake, "flake"), (4, confInfra, "infra"), (5, confReal, "real")] balancedH}}"),
  ("calibrate: a threshold the holdout part contradicts is not certified", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn balancedG contradictG}}"),
  ("calibrate: an empty holdout part certifies nothing", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn balancedG []}}"),
  ("calibrate: an empty choose part certifies nothing", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn [] balancedG}}"),
  ("calibrate: the round-1 lopsided set (27 real, 1 flake, 0 infra) gives none", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{lopsided}}"),
  ("calibrate: target and perOption in the request are ignored", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",\"target\":\{\"num\":\"0\",\"den\":\"1\"},\"perOption\":0,{lopsided}}"),
  ("calibrate: no rows give none and may not write (no labeled ids)", "oracle.calibrate",
    lit "{\"name\":\"ci-triage\",\"replay\":[],\"answers\":[]}"),
  ("calibrate: the round-3 probe (flake advised 16 times, 5 right) never makes flake advisable", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{round3}}"),
  ("calibrate: the round-5 probe on the holdout part (flake advised 16 times, 5 right) certifies real only",
    "oracle.calibrate", lit s!"\{\"name\":\"ci-triage\",{round5}}"),
  ("calibrate: 15 of 16 held-out flake rows right is not certified (Wilson lower bound below 9/10)",
    "oracle.calibrate", lit s!"\{\"name\":\"ci-triage\",{nearMiss}}"),
  ("calibrate: 5 right holdout rows are too few for the Wilson bound at 9/10", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setJ balancedG}}"),
  ("calibrate: the round-2 probe (5 flake, 5 infra, 90 real, always real) gives none", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{constantReal}}"),
  ("calibrate: every labeled id answered may write", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{balanced}}"),
  ("calibrate: one unanswered labeled id may not write", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn balancedG balancedH 1}}"),
  ("calibrate: a cut set (53 ids unanswered) may not write", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setIn balancedG balancedH 53}}"),
  ("calibrate: a label outside the options is an error", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",{setJ [(1, confReal, "billing")]}}"),
  ("calibrate: a row naming a split is an error (Lean splits by id)", "oracle.calibrate",
    lit "{\"name\":\"ci-triage\",\"replay\":[{\"id\":\"a\",\"split\":\"calibrate\",\"label\":\"real\"}],\"answers\":[]}"),
  ("validate: a pick below another option's probability (flake 0.97) is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField pickNotMaxFlake}}"),
  ("validate: a pick below the no-match probability (unknown 0.97) is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField pickNotMaxUnknown}}"),
  ("decide: a pick below another option's probability escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":{replyField pickNotMaxFlake}}"),
  ("decide: threshold 0 is an error", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{allAt "0" "1"},\"reply\":{replyField confReal}}"),
  ("decide: a negative threshold is an error", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{allAt "-1" "2"},\"reply\":{replyField confReal}}"),
  ("decide: a threshold above 1 is an error", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{allAt "3" "2"},\"reply\":{replyField confReal}}"),
  ("decide: threshold 1 is accepted", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",{allAt "1" "1"},\"reply\":{replyField confReal}}"),
  ("eval: holdout rows at 1/2 (3 hits, 1 miss, 1 below, 1 dropped; choose rows not counted)", "oracle.eval",
    lit s!"\{\"name\":\"ci-triage\",{half},{heldout}}"),
  ("eval: no threshold covers nothing", "oracle.eval",
    lit s!"\{\"name\":\"ci-triage\",{heldout}}"),
  ("eval: only real calibrated covers the real answers only", "oracle.eval",
    lit s!"\{\"name\":\"ci-triage\",\"thresholds\":\{\"real\":\{\"num\":\"1\",\"den\":\"2\"}},{heldout}}"),
  ("eval: a threshold outside (0, 1] is an error", "oracle.eval",
    lit s!"\{\"name\":\"ci-triage\",{allAt "2" "1"},{heldout}}"),
  ("store: a short reply is stored unchanged", "oracle.store", lit "{\"text\":\"{\\\"model\\\":\\\"jev-1.13.0\\\"}\"}"),
  ("redact: names match in any letter case", "oracle.redact",
    lit "{\"names\":[\"Octocat\"],\"text\":\"pushed by octocat and OCTOCAT\"}"),
  ("redact: a dash-encoded home path and names bounded by - _ .", "oracle.redact",
    lit "{\"names\":[\"alice\"],\"text\":\"-Users-example-src/x user_alice MacBook-Pro-of-alice.local malice\"}"),
  ("redact: a line over 500 characters is cut with a marker", "oracle.redact",
    lit s!"\{\"text\":\"{String.ofList (List.replicate 600 'x')}\"}"),
  ("request: the same state lists the options in the same seeded order", "oracle.request",
    lit "{\"name\":\"ci-triage\",\"state\":{\"job\":\"build\",\"step\":\"lake test\",\"log\":\"error: x\"}}")]

/-- The fixture replies: (name, reply text, true label). -/
def fixtures : List (String × String × String) := [
  ("confident-real", confReal, "real"),
  ("confident-flake", confFlake, "flake"),
  ("confident-infra", confInfra, "infra"),
  ("pick-not-max-flake", pickNotMaxFlake, "flake"),
  ("pick-not-max-unknown", pickNotMaxUnknown, "real"),
  ("unsure-flake", unsureFlake, "real"),
  ("confident-unknown", confUnknown, "infra"),
  ("missing-probability", missingProb, "real"),
  ("other-model", otherModel, "real"),
  ("not-json", "<html>", "infra")]

/-- The text of `wire.jsonl`. -/
def wireText : String :=
  String.join (cases.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

def fixturesText : String :=
  String.join (fixtures.map fun (name, reply, label) =>
    let req := lit s!"\{\"name\":\"ci-triage\",{half},\"reply\":{replyField reply}}"
    (Json.mkObj [("name", .str name), ("reply", .str reply), ("label", .str label),
      ("decide", respond "oracle.decide" req)]).compress ++ "\n")

/-- Every file: (name in the golden directory, text). -/
def files : List (String × String) := [("wire.jsonl", wireText), ("fixtures.jsonl", fixturesText)]

/-- The golden directory, from the package root `lean/`. -/
def dir (root : System.FilePath) : System.FilePath := root / ".." / "packages" / "contracts" / "golden" / "oracle"

/-- Compare (or write) every file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let mut stale := 0
  if write then IO.FS.createDirAll (dir root)
  for (p, text) in files do
    let f := dir root / p
    if write then
      IO.FS.writeFile f text
    else
      let cur ← try IO.FS.readFile f catch _ => pure ""
      if cur != text then
        IO.println s!"oracle golden: {f} is stale (regenerate: cd lean && lake env lean --run scripts/OracleGolden.lean)"
        stale := stale + 1
  IO.println s!"oracle golden: {files.length} files, {cases.length} wire cases, {stale} stale"
  return stale

end Fw.Wire.Oracle.Golden
