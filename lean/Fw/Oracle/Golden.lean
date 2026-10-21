import Fw.Wire
import Fw.Ops.Golden
import Fw.Oracle.Wire
/-!
# Golden vectors and fixture replies of the oracle ops (`oracle.*`)

Files under `packages/contracts/golden/oracle/`, generated from Lean, never by hand:
- `wire.jsonl`: one line per case, `{"name", "request", "response"}` (`request` carries its `op`; `response` is what
  `fwcore` replies, without the `id`);
- `fixtures.jsonl`: fixture replies in the vendor's response shape, `{"name", "reply", "label", "decide"}`, where
  `reply` is the response body text, `label` the true class, and `decide` the `oracle.decide` reply with threshold
  1/2 for every option. The TypeScript client tests serve these from a fake `fetch`, so no test needs the network
  or a key.

`lake env lean --run scripts/OracleGolden.lean --check` (a job of `scripts/check.sh`) checks both files; without
`--check` it rewrites them. The labeled replay sets are data written by the TypeScript side, not by this module.
-/
namespace Fw.Wire.Oracle.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)
open Fw.Oracle
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

/-- A confident `flake` reply. -/
def confFlake : String := sampleReply "flake" "0.97" "0.01" "0.01" "0.01"

/-- A confident `infra` reply. -/
def confInfra : String := sampleReply "infra" "0.01" "0.97" "0.01" "0.01"

/-- Round-1 reviewer reply 1: picks `real` while `flake` has 0.97. -/
def pickNotMaxFlake : String := sampleReply "real" "0.97" "0.01" "0.01" "0.01"

/-- Round-1 reviewer reply 2: picks `real` while `unknown` has 0.97. -/
def pickNotMaxUnknown : String := sampleReply "real" "0.01" "0.01" "0.01" "0.97"

/-- The id of row `n` in the holdout part (`held`) or the choose part: the first of `r<n>`, `r<n>-1`, `r<n>-2`, ...
that `heldOut` puts in the wanted part (distinct rows get distinct ids). -/
def idIn (held : Bool) (n : Nat) : String :=
  let b := s!"r{n}"
  let cands := b :: (List.range 64).map fun k => s!"{b}-{k + 1}"
  (cands.find? (heldOut · == held)).getD b

/-- The rows of `(count, reply, label)` groups in one part, numbered from `n0`: `(id, reply, label)`. -/
def rowsIn (held : Bool) (n0 : Nat) (gs : List (Nat × String × String)) : List (String × String × String) :=
  let rs := gs.flatMap fun (n, reply, label) => List.replicate n (reply, label)
  ((List.range rs.length).zip rs).map fun (k, r, l) => (idIn held (n0 + k), r, l)

/-- A replay set as request fields: groups `cs` in the choose part, then groups `hs` in the holdout part, every row
answered by its reply, then `extra` more rows labeled `real` with no answer (alternating parts). -/
def setIn (cs hs : List (Nat × String × String)) (extra : Nat := 0) : String :=
  let c := rowsIn false 0 cs
  let h := rowsIn true c.length hs
  let ex := (List.range extra).map fun k => idIn (k % 2 == 1) (c.length + h.length + k)
  let labeled : List (String × String) := ((c ++ h).map fun (i, _, l) => (i, l)) ++ ex.map fun i => (i, "real")
  let replay := labeled.map fun (i, l) => s!"\{\"id\":\"{i}\",\"label\":\"{l}\"}"
  let answers := (c ++ h).map fun (i, r, _) => s!"\{\"id\":\"{i}\",\"reply\":{replyField r}}"
  s!"\"replay\":[{",".intercalate replay}],\"answers\":[{",".intercalate answers}]"

/-- The same groups in both parts. -/
def setJ (gs : List (Nat × String × String)) (extra : Nat := 0) : String := setIn gs gs extra

#guard (rowsIn true 0 [(4, "x", "l")]).all fun (i, _, _) => heldOut i
#guard (rowsIn false 0 [(4, "x", "l")]).all fun (i, _, _) => !heldOut i

/-- A balanced CI-triage set: 5 confident correct rows per advisable option and 2 unsure wrong rows. -/
def balancedG : List (Nat × String × String) := [(5, confFlake, "flake"), (5, confInfra, "infra"), (5, confReal, "real"),
  (2, unsureFlake, "real")]

/-- A balanced holdout part: 25 confident correct rows per advisable option (the fewest the Wilson bound at 9/10
accepts) and 2 unsure wrong rows. -/
def balancedH : List (Nat × String × String) := [(25, confFlake, "flake"), (25, confInfra, "infra"),
  (25, confReal, "real"), (2, unsureFlake, "real")]

/-- The balanced set: `balancedG` in the choose part, `balancedH` in the holdout part. -/
def balanced : String := setIn balancedG balancedH

/-- The round-1 counterexample: 27 confident `real` rows labeled `real`, 1 labeled `flake`, none `infra` (both
parts). -/
def lopsided : String := setJ [(27, confReal, "real"), (1, confReal, "flake")]

/-- A holdout evaluation set: 3 confident hits, 1 confident miss, 1 unsure row, 1 malformed reply in the holdout part,
and 2 confident misses in the choose part (not counted). -/
def heldout : String := setIn [(2, confReal, "flake")] [(3, confReal, "real"), (1, confFlake, "infra"),
  (1, unsureFlake, "flake"), (1, "<html>", "real")]

/-- Holdout groups that contradict the balanced set: every confident answer is wrong. -/
def contradictG : List (Nat × String × String) := [(5, confFlake, "real"), (5, confInfra, "real"), (5, confReal, "flake")]

/-- A threshold table with `τ` for every CI-triage option. -/
def allAt (num den : String) : String :=
  let r := s!"\{\"num\":\"{num}\",\"den\":\"{den}\"}"
  s!"\"thresholds\":\{\"flake\":{r},\"infra\":{r},\"real\":{r}}"

/-- The threshold table with 1/2 for every option. -/
def half : String := allAt "1" "2"

/-- The day list of `n` calls on day `d`. -/
def daysJ (d : String) (n : Nat) : String := (toJson (List.replicate n d)).compress

/-- The reviewer's round-2 probe: 5 `flake`, 5 `infra`, 90 `real` rows, every reply a confident `real` (both
parts). -/
def constantReal : String := setJ [(5, confReal, "flake"), (5, confReal, "infra"), (90, confReal, "real")]

/-- The reviewer's round-3 and round-5 probe: `flake` is advised 16 times with 5 right (5 rows labeled `flake`, 11
labeled `real`); 5 `infra` and 90 `real` rows are answered right. -/
def round3G : List (Nat × String × String) := [(5, confFlake, "flake"), (11, confFlake, "real"),
  (5, confInfra, "infra"), (90, confReal, "real")]

/-- The probe in both parts. -/
def round3 : String := setJ round3G

/-- The probe in the holdout part behind a choose part on which every option is right: the choice of thresholds
passes, so only the holdout test can refuse `flake`. -/
def round5 : String := setIn balancedG round3G

/-- `flake` advised 16 times on the holdout part with 15 right (point precision 15/16, above 9/10) next to 25 right
rows of `infra` and of `real`. -/
def nearMiss : String := setIn balancedG [(15, confFlake, "flake"), (1, confFlake, "real"),
  (25, confInfra, "infra"), (25, confReal, "real")]

/-- A plan request over labeled rows `r0`, `r1`, ... with the given logged flags. -/
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
  ("validate: probabilities summing to 1.2 are a schema failure", "oracle.validate",
    lit s!"\{\"name\":\"ci-triage\",\"reply\":{replyField badSum}}"),
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

/-- The text of `fixtures.jsonl`. -/
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
