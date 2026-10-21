import Lean.Data.Json
import Fw.Oracle.Redact
import Fw.Oracle.Questions
/-!
# Fw.Oracle.Body: the exact bytes of an oracle request

`bodyText q S` is the only text the client ever sends for question `q` and (redacted) state `S`: the send gate
(`Fw.Oracle.pre`) builds it and returns it with its `send` verdict, so the TypeScript client sends a string Lean made
(`body_from_lean`). Everything in it is a constant of this repository (the pinned model, the question's name,
instructions and option descriptions, the field names) except the state's lines.

The criteria of a Choice question are listed in the order `shuffle (fnv stateText)`, so the same state gives the same
bytes (a logged request replays) and the first-listed option varies between states.
-/
namespace Fw.Oracle
open Lean

/-- A state as a JSON object: a one-line field as a string, any other as an array of strings (keys sorted by the
JSON object). A field name that occurs more than once keeps only its last entry. -/
def stateJ (st : State) : Json :=
  Json.mkObj (st.map fun (k, ls) => (k, match ls with
    | [s] => .str s
    | _ => .arr (ls.map Json.str).toArray))

#guard (stateJ [("b", ["x", "y"]), ("a", ["z"])]).compress == "{\"a\":\"z\",\"b\":[\"x\",\"y\"]}"
#guard (stateJ [("a", ["x"]), ("a", ["y"])]).compress == "{\"a\":\"y\"}"

/-- The criteria of a question as the API wants them: an option map (choice), `true`/`false` meanings (noul), the
level list (score). -/
def criteriaJ (q : Question) : Json :=
  match q.spec with
  | .score ls => toJson ls
  | _ => Json.mkObj (q.criteria.map fun (k, v) => (k, Json.str v))

/-- A JSON object text with its keys in the given order. -/
def objText (kvs : List (String × String)) : String :=
  "{" ++ ",".intercalate (kvs.map fun (k, v) => (Json.str k).compress ++ ":" ++ (Json.str v).compress) ++ "}"

/-- The criteria text of a request: a choice's options in the order `shuffle seed`, each with its description (the
first one listed for that key, should a key repeat; a repeated key is then listed as often as it repeats), else the
compact `criteriaJ`. -/
def criteriaText (q : Question) (seed : Nat) : String :=
  match q.spec with
  | .choice .. => objText ((shuffle seed (q.criteria.map (·.1))).filterMap fun k => (q.criteria.lookup k).map (k, ·))
  | _ => (criteriaJ q).compress

/-- The wire name of a question's answer type. -/
def Spec.wireType : Spec → String
  | .choice .. => "choice"
  | .noul => "noul"
  | .score _ => "score"

/-- **The request bytes**: the keys `model`, `questions`, `state`, with the criteria of a choice in the order
shuffled by the seed `fnv` of the compact state text (so the same state gives the same bytes). -/
def bodyText (q : Question) (st : State) : String :=
  let sj := (stateJ st).compress
  "{\"model\":" ++ (Json.str model).compress ++ ",\"questions\":{" ++ (Json.str q.name).compress ++
    ":{\"criteria\":" ++ criteriaText q (fnv sj) ++ ",\"instructions\":" ++ (Json.str q.instructions).compress ++
    ",\"type\":\"" ++ q.spec.wireType ++ "\"}},\"state\":" ++ sj ++ "}"

-- two states can list the options in different orders
#guard bodyText ciTriage [("log", ["a"])] != bodyText ciTriage [("log", ["b"])] ||
  bodyText ciTriage [("log", ["c"])] != bodyText ciTriage [("log", ["d"])]
#guard (bodyText ciTriage [("log", ["x"])]).startsWith "{\"model\":\"jev-1.13.0\",\"questions\":{\"ci-triage\":"

end Fw.Oracle
