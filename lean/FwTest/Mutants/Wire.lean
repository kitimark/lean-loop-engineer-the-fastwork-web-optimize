import Fw.Wire

/-! # Mutant killers for `Fw.Wire` (task m0-mutants)

Every enum codec of the console contract round-trips (decode ∘ name = ok) and spells the contract
names; the rational decoder's error messages are pinned. The goldens only used some constructors. -/

namespace FwTest.Mutants.Wire
open Lean Fw.Wire Fw.Console

/-- The value of a successful decode, `none` on an error. -/
def ok? {α : Type} : Except String α → Option α
  | .ok a => some a
  | .error _ => none

/-- The message of a failed decode, `""` on success. -/
def err {α : Type} : Except String α → String
  | .ok _ => ""
  | .error e => e

/-- All actors. -/
def actors : List Actor := [.user, .lead, .owner, .reviewer, .script, .git, .hook]
/-- All step kinds. -/
def stepKinds : List StepKind := [.action, .yes_no, .choice, .text]
/-- All run kinds. -/
def runKinds : List RunKind := [.screen, .gate, .run, .device]
/-- All step statuses. -/
def stepStatuses : List StepStatus := [.waiting, .started, .answered, .done, .cancelled]
/-- All run statuses. -/
def runStatuses : List RunStatus := [.running, .passed, .failed]

-- names are the contract strings, and decoding a name gives the value back
#guard actors.map Actor.name == ["user", "lead", "owner", "reviewer", "script", "git", "hook"]
#guard actors.all fun a => ok? (actorOf a.name) == some a
#guard stepKinds.map stepKindName == ["action", "yes_no", "choice", "text"]
#guard stepKinds.all fun k => ok? (stepKindOf (stepKindName k)) == some k
#guard runKinds.map runKindName == ["screen", "gate", "run", "device"]
#guard runKinds.all fun k => ok? (runKindOf (runKindName k)) == some k
#guard stepStatuses.map StepStatus.name == ["waiting", "started", "answered", "done", "cancelled"]
#guard stepStatuses.all fun s => ok? (stepStatusOf s.name) == some s
#guard runStatuses.map runStatusName == ["running", "passed", "failed"]
#guard runStatuses.all fun s => ok? (runStatusOf (runStatusName s)) == some s
-- unknown names are refused with the name in the message
#guard err (actorOf "robot") == "unknown actor robot" && err (runKindOf "") == "unknown run kind "
#guard err (runStatusOf "ok") == "unknown run status ok" && err (stepStatusOf "x") == "unknown step status x"
#guard err (stepKindOf "x") == "unknown step kind x"

-- rationals: normalized; both error messages
#guard ok? (ratOfJson (Json.mkObj [("num", "2"), ("den", "4")])) == some (1 / 2)
#guard ok? (ratOfJson (Json.mkObj [("num", "-3"), ("den", "1")])) == some (-3)
#guard err (ratOfJson (Json.mkObj [("num", "1"), ("den", "0")])) == "rational: den must be positive"
#guard err (ratOfJson (Json.mkObj [("num", "x"), ("den", "1")])) ==
  "rational: num and den must be decimal integer strings"
#guard err (ratOfJson (Json.mkObj [("num", "1"), ("den", "-1")])) ==
  "rational: num and den must be decimal integer strings"

-- flag parts: names and round trip
#guard [Fw.Flags.Part.nav, .hero, .categories, .carousel, .countdown, .footer].map partName ==
  ["nav", "hero", "categories", "carousel", "countdown", "footer"]
#guard [Fw.Flags.Part.nav, .hero, .categories, .carousel, .countdown, .footer].all fun p =>
  ok? (partOf (partName p)) == some p

/-- A registry rule object of kind `k` from `nav = a` to `hero = b`. -/
def ruleJ (k : String) : Json := Json.mkObj [("kind", Json.str k), ("p", "nav"), ("v", "a"), ("q", "hero"), ("w", "b")]

-- registry rules: both kinds decode to their constructor; another kind is refused
#guard match ruleOfJson (ruleJ "requires") with | .ok (.requires .nav "a" .hero "b") => true | _ => false
#guard match ruleOfJson (ruleJ "conflicts") with | .ok (.conflicts .nav "a" .hero "b") => true | _ => false
#guard match ruleOfJson (ruleJ "") with | .error "unknown rule kind " => true | _ => false

/-- The stateful ops, answered by `fwcore serve` (`Fw/Serve.lean`), not by `handle`. -/
def statefulOps : List String := ["console.replay", "console.query", "console.reset"]

-- every listed stateless op is dispatched by `handle` (an empty request may fail, but not as an unknown op)
#guard ops.all fun o => statefulOps.contains o ||
  !(err (handle (Json.mkObj [("op", Json.str o)]))).startsWith "unknown op"
#guard err (handle (Json.mkObj [("op", "nope")])) == "unknown op nope"
-- the `samples` op replies with one `samples` field holding one entry per sample request
#guard match handle (Json.mkObj [("op", "samples")]) with
  | .ok [("samples", .arr a)] => a.size == sampleRequests.length
  | _ => false
-- every sample request parses and is answered without an error, so the two `"error"` branches of
-- `samples` are dead for the fixed `sampleRequests` (FwTest/Mutants/equivalent.tsv)
#guard sampleRequests.all fun (_, r) => match Json.parse r with
  | .ok j => (handleCore j).toBool
  | .error _ => false

end FwTest.Mutants.Wire
