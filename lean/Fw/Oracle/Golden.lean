import Fw.Wire
import Fw.Ops.Golden
/-!
# Golden vectors and fixture replies of the oracle ops (`oracle.*`)

Files under `packages/contracts/golden/oracle/`, generated from Lean, never by hand:
- `wire.jsonl`: one line per case, `{"name", "request", "response"}` (`request` carries its `op`; `response` is what
  `fwcore` replies, without the `id`);
- `fixtures.jsonl`: fixture replies in the vendor's response shape, `{"name", "reply", "label", "decide"}`, where
  `reply` is the response body text, `label` the true class, and `decide` the policy's reply at threshold 1/2. The
  TypeScript client tests serve these from a fake `fetch`, so no test needs the network or a key.

`lake test` checks every file; `lake test -- --write-oracle-golden` rewrites them first. The labeled CI replay set
`ci-triage.jsonl` and `thresholds.json` in the same directory are data written by the TypeScript side, not by this
module.
-/
namespace Fw.Wire.Oracle.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)
open Fw.Wire.Oracle (sampleReply)

/-- A request field holding a reply text. -/
def replyField (text : String) : String := (Json.str text).compress

/-- A confident `real` reply. -/
def confReal : String := sampleReply "real" "0.01" "0.01" "0.97" "0.01"

/-- An unsure `flake` reply. -/
def unsureFlake : String := sampleReply "flake" "0.4" "0.3" "0.2" "0.1"

/-- A confident no-match reply. -/
def confUnknown : String := sampleReply "unknown" "0.01" "0.01" "0.01" "0.97"

/-- A reply with a probability missing. -/
def missingProb : String :=
  "{\"model\":\"jev-1.13.0\",\"answers\":{\"ci-triage\":{\"type\":\"choice\",\"choice\":\"real\"," ++
  "\"probabilities\":{\"flake\":0.5,\"real\":0.5}}},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}"

/-- A reply from another model version. -/
def otherModel : String :=
  "{\"model\":\"jev-1.14.0\",\"answers\":{\"ci-triage\":{\"type\":\"choice\",\"choice\":\"real\"," ++
  "\"probabilities\":{\"flake\":0,\"infra\":0,\"real\":1,\"unknown\":0}}},\"usage\":{}}"

/-- A reply whose probabilities sum to 1.2. -/
def badSum : String := sampleReply "real" "0.1" "0.1" "0.9" "0.1"

/-- A reply that picks an option the question does not have. -/
def foreignPick : String := sampleReply "billing" "0.25" "0.25" "0.25" "0.25"

/-- A calibrate request over `k` confident correct rows and `m` unsure wrong rows. -/
def calRows (k m : Nat) : String :=
  "[" ++ ",".intercalate ((List.replicate k s!"\{\"reply\":{replyField confReal},\"label\":\"real\"}") ++
    List.replicate m s!"\{\"reply\":{replyField unsureFlake},\"label\":\"real\"}") ++ "]"

/-- The day list of `n` calls on day `d`. -/
def daysJ (d : String) (n : Nat) : String := (toJson (List.replicate n d)).compress

/-- The wire cases: (name, op, request without op). -/
def cases : List (String × String × Json) := [
  ("question: the CI-triage question", "oracle.question", lit "{\"name\":\"ci-triage\"}"),
  ("question: an unknown name is an error", "oracle.question", lit "{\"name\":\"nope\"}"),
  ("budget: 200 a day, 60 a calibration run", "oracle.budget", lit "{}"),
  ("redact: home path, e-mail, token, address", "oracle.redact",
    lit "{\"text\":\"/Users/example/src/a.ts:3 by a@example.com ghp_ABCDEFGH12345678 at 203.0.113.9\"}"),
  ("redact: a listed name on a word boundary", "oracle.redact",
    lit "{\"names\":[\"octocat\"],\"text\":\"pushed by octocat to main\"}"),
  ("triage.state: job and step of the last line, text of the lines", "oracle.triage.state",
    lit "{\"workflow\":\"lean\",\"lines\":[\"build\\tlake build\\t2026-10-18T06:07:14.1Z error: x\",\"\",\"build\\tlake test\\t2026-10-18T06:07:15.2Z \\u001b[31mFAIL\\u001b[0m t1\"]}"),
  ("request: the body carries the redacted state and the pinned model", "oracle.request",
    lit "{\"name\":\"ci-triage\",\"state\":{\"workflow\":\"lean\",\"log\":[\"at /home/example/w/x.lean:1\",\"ok\"]}}"),
  ("pre: a logged request is replayed", "oracle.pre",
    lit "{\"state\":{\"log\":\"/Users/example/x\"},\"logged\":true,\"today\":\"2026-10-18\"}"),
  ("pre: an unredacted state is refused", "oracle.pre",
    lit "{\"state\":{\"log\":\"/Users/example/x\"},\"logged\":false,\"today\":\"2026-10-18\"}"),
  ("pre: the daily cap reached is over budget", "oracle.pre",
    lit s!"\{\"state\":\{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":{daysJ "2026-10-18" 200}}"),
  ("pre: one under the daily cap sends", "oracle.pre",
    lit s!"\{\"state\":\{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":{daysJ "2026-10-18" 199}}"),
  ("pre: the run cap reached is over budget", "oracle.pre",
    lit "{\"state\":{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"run\":60}"),
  ("pre: a redacted, unlogged state under both caps sends", "oracle.pre",
    lit "{\"state\":{\"log\":\"ok\"},\"today\":\"2026-10-18\",\"days\":[\"2026-10-17\"],\"run\":59}"),
  ("validate: a well-formed reply, gate recomputed exactly", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField confReal}}"),
  ("validate: not JSON is malformed", "oracle.validate", lit "{\"name\":\"ci-triage\",\"reply\":\"<html>\"}"),
  ("validate: a missing probability is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField missingProb}}"),
  ("validate: another model version is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField otherModel}}"),
  ("validate: probabilities summing to 1.2 are a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField badSum}}"),
  ("validate: a pick outside the options is a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField foreignPick}}"),
  ("decide: uncalibrated escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"threshold\":null,\"reply\":{replyField confReal}}"),
  ("decide: calibrated and confident advises", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"threshold\":\{\"num\":\"1\",\"den\":\"2\"},\"reply\":{replyField confReal}}"),
  ("decide: below the threshold escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"threshold\":\{\"num\":\"1\",\"den\":\"2\"},\"reply\":{replyField unsureFlake}}"),
  ("decide: a confident no-match escalates", "oracle.decide",
    lit s!"\{\"name\":\"ci-triage\",\"threshold\":\{\"num\":\"1\",\"den\":\"2\"},\"reply\":{replyField confUnknown}}"),
  ("decide: rate limited (429) escalates", "oracle.decide",
    lit "{\"name\":\"ci-triage\",\"threshold\":{\"num\":\"1\",\"den\":\"2\"},\"failure\":{\"kind\":\"http\",\"status\":429}}"),
  ("decide: a timeout escalates", "oracle.decide",
    lit "{\"name\":\"ci-triage\",\"threshold\":{\"num\":\"1\",\"den\":\"2\"},\"failure\":{\"kind\":\"timeout\"}}"),
  ("decide: no key escalates", "oracle.decide",
    lit "{\"name\":\"ci-triage\",\"threshold\":{\"num\":\"1\",\"den\":\"2\"},\"failure\":{\"kind\":\"noKey\"}}"),
  ("decide: a malformed reply escalates", "oracle.decide",
    lit "{\"name\":\"ci-triage\",\"threshold\":{\"num\":\"1\",\"den\":\"2\"},\"reply\":\"{\"}"),
  ("calibrate: 10 confident hits and 2 unsure misses give the confident gate", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",\"rows\":{calRows 10 2}}"),
  ("calibrate: fewer covered rows than minRows give none", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",\"rows\":{calRows 9 2}}"),
  ("calibrate: no rows give none", "oracle.calibrate", lit "{\"name\":\"ci-triage\",\"rows\":[]}"),
  ("calibrate: a label outside the options is an error", "oracle.calibrate",
    lit s!"\{\"name\":\"ci-triage\",\"rows\":[\{\"reply\":{replyField confReal},\"label\":\"billing\"}]}")]

/-- The fixture replies: (name, reply text, true label). -/
def fixtures : List (String × String × String) := [
  ("confident-real", confReal, "real"),
  ("unsure-flake", unsureFlake, "real"),
  ("confident-unknown", confUnknown, "infra"),
  ("missing-probability", missingProb, "real"),
  ("other-model", otherModel, "real"),
  ("not-json", "<html>", "infra")]

/-- The text of `wire.jsonl`. -/
def wireText : String :=
  String.join (cases.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The text of `fixtures.jsonl`. -/
def fixturesText : String :=
  String.join (fixtures.map fun (name, reply, label) =>
    let req := lit s!"\{\"name\":\"ci-triage\",\"threshold\":\{\"num\":\"1\",\"den\":\"2\"},\"reply\":{replyField reply}}"
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
        IO.println s!"oracle golden: {f} is stale (regenerate: cd lean && lake test -- --write-oracle-golden)"
        stale := stale + 1
  IO.println s!"oracle golden: {files.length} files, {cases.length} wire cases, {stale} stale"
  return stale

end Fw.Wire.Oracle.Golden
