import Lean.Data.Json
import Fw.Oracle.Redact
import Fw.Oracle.Questions
/-! The exact bytes of an oracle request: `bodyText q S` is the only text the client sends. -/
namespace Fw.Oracle
open Lean

/-- A state as a JSON object: a one-line field as a string. -/
def stateJ (st : State) : Json :=
  Json.mkObj (st.map fun (k, ls) => (k, match ls with
    | [s] => .str s
    | _ => .arr (ls.map Json.str).toArray))

#guard (stateJ [("b", ["x", "y"]), ("a", ["z"])]).compress == "{\"a\":\"z\",\"b\":[\"x\",\"y\"]}"
#guard (stateJ [("a", ["x"]), ("a", ["y"])]).compress == "{\"a\":\"y\"}"

/-- The criteria of a question as the API wants them. -/
def criteriaJ (q : Question) : Json :=
  match q.spec with
  | .score ls => toJson ls
  | _ => Json.mkObj (q.criteria.map fun (k, v) => (k, Json.str v))

def objText (kvs : List (String × String)) : String :=
  "{" ++ ",".intercalate (kvs.map fun (k, v) => (Json.str k).compress ++ ":" ++ (Json.str v).compress) ++ "}"

def criteriaText (q : Question) (seed : Nat) : String :=
  match q.spec with
  | .choice .. => objText ((shuffle seed (q.criteria.map (·.1))).filterMap fun k => (q.criteria.lookup k).map (k, ·))
  | _ => (criteriaJ q).compress

/-- The wire name of a question's answer type. -/
def Spec.wireType : Spec → String
  | .choice .. => "choice"
  | .noul => "noul"
  | .score _ => "score"

/-- The request bytes: the keys `model`. -/
def bodyText (q : Question) (st : State) : String :=
  let sj := (stateJ st).compress
  "{\"model\":" ++ (Json.str model).compress ++ ",\"questions\":{" ++ (Json.str q.name).compress ++
    ":{\"criteria\":" ++ criteriaText q (fnv sj) ++ ",\"instructions\":" ++ (Json.str q.instructions).compress ++
    ",\"type\":\"" ++ q.spec.wireType ++ "\"}},\"state\":" ++ sj ++ "}"

#guard bodyText ciTriage [("log", ["a"])] != bodyText ciTriage [("log", ["b"])] ||
  bodyText ciTriage [("log", ["c"])] != bodyText ciTriage [("log", ["d"])]
#guard (bodyText ciTriage [("log", ["x"])]).startsWith "{\"model\":\"jev-1.13.0\",\"questions\":{\"ci-triage\":"

end Fw.Oracle
