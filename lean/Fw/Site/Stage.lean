import Fw.Parts.Contract

/-! Part stage route: `?only=<target>&stage=y:N,vh:N,vw:N` mounts one part, or the stageable members of one contract
group, under a fixed scroll environment. This module decides the query; `apps/site/src/registry/only.ts` is checked
against `packages/contracts/golden/parts/stage.jsonl` (`lean/scripts/StageGolden.lean`) and holds no decision logic.
Every result rests on the contract table's premise `declared-rows-unverified`. -/

namespace Fw.Site.Stage

open Fw.Parts.Contract (parts pageLevel members Group premise jstr jarr)

/-- Why a stage query is refused. $$e \in \{\mathrm{unknownTarget}, \mathrm{pageLevel}, \mathrm{emptyGroup}, \mathrm{duplicate}, \mathrm{badStage}\}$$ -/
inductive Err | unknownTarget | pageLevel | emptyGroup | duplicate | badStage
deriving Repr, DecidableEq

/-- Wire name of a refusal. $$\operatorname{name}(e)$$ the constructor name. -/
def Err.name : Err → String
  | .unknownTarget => "unknownTarget" | .pageLevel => "pageLevel" | .emptyGroup => "emptyGroup"
  | .duplicate => "duplicate" | .badStage => "badStage"

/-- The fixed scroll environment: scroll position, viewport width and height in CSS pixels.
$$E = (y, v_w, v_h) \in \mathbb{N}^3$$ -/
structure Env where
  y : Nat
  vw : Nat
  vh : Nat
deriving Repr, DecidableEq

/-- Defaults when a stage key is absent. $$E_0 = (0, 1280, 800)$$ -/
def Env.default : Env := { y := 0, vw := 1280, vh := 800 }

/-- Accepted ranges. $$E \text{ valid} \iff y \le 10^6 \land 1 \le v_w \le 10^4 \land 1 \le v_h \le 10^4$$ -/
def Env.valid (e : Env) : Bool := e.y ≤ 1000000 && 1 ≤ e.vw && e.vw ≤ 10000 && 1 ≤ e.vh && e.vh ≤ 10000

/-- A stage that will be mounted: its target, the part ids it mounts and its environment.
$$S = (t, M, E)$$ -/
structure Stage where
  target : String
  members : List String
  env : Env
deriving Repr, DecidableEq

/-- Outcome of a query. $$r \in \{\bot\} \cup \mathrm{Stage} \cup \mathrm{Err}$$ `none`: the query has no `only` key, so it is
not a stage page. -/
inductive Result | none | ok (s : Stage) | err (e : Err)
deriving Repr, DecidableEq

/-- Whether a part id is a stage target.
$$\operatorname{stageable}(i) = \exists P \in \mathrm{parts}:\ P.\mathrm{id} = i \land \lnot\operatorname{pageLevel}(P)$$ -/
def stageable (i : String) : Bool := parts.any fun P => P.id == i && !pageLevel P

/-- Members of a contract group that can be staged.
$$M(g) = [i \in \operatorname{members}(g) \mid \operatorname{stageable}(i)]$$ -/
def stageMembers (g : Group) : List String := (members g).filter stageable

/-- The groups a target name can denote. $$\{G_1, \dots, G_5\}$$ (`solo` is each part on its own). -/
def stageGroups : List Group := [.g1, .g2, .g3, .g4, .g5]

/-- Result of resolving a target. $$r \in \mathrm{ok}(M) \cup \mathrm{err}(e)$$ -/
inductive Res | ok (ms : List String) | err (e : Err)
deriving Repr, DecidableEq

/-- Resolve a target name to the part ids it mounts: a part id mounts itself, a group name (`g1`..`g5`) its stageable
members.

$$\operatorname{resolve}(t) = \begin{cases} [t] & t \in \mathrm{ids} \land \operatorname{stageable}(t) \\
\mathrm{pageLevel} & t \in \mathrm{ids} \land \lnot\operatorname{stageable}(t) \\
M(g) & t = \operatorname{name}(g) \land M(g) \ne [\,] \\ \mathrm{emptyGroup} & t = \operatorname{name}(g) \land M(g) = [\,] \\
\mathrm{unknownTarget} & \text{otherwise}\end{cases}$$ -/
def resolve (t : String) : Res :=
  if parts.any (·.id == t) then
    if stageable t then .ok [t] else .err .pageLevel
  else
    match stageGroups.find? fun g => g.name == t with
    | some g => if (stageMembers g).isEmpty then .err .emptyGroup else .ok (stageMembers g)
    | none => .err .unknownTarget

/-- Page-level parts are never stage targets.
$$\forall P \in \mathrm{parts},\ \operatorname{pageLevel}(P) \Rightarrow \operatorname{resolve}(P.\mathrm{id}) = \mathrm{pageLevel}$$ -/
theorem resolve_refuses_pageLevel :
    ∀ P ∈ parts, pageLevel P → resolve P.id = .err .pageLevel := by decide

/-- The page-level group mounts nothing and $G_2$ drops its page-level member.
$$\operatorname{resolve}(\texttt{g4}) = \mathrm{emptyGroup},\quad \texttt{morph.tween} \notin M(G_2)$$ -/
theorem g4_refused_g2_drops_tween :
    resolve "g4" = .err .emptyGroup ∧ "morph.tween" ∉ stageMembers .g2 := by decide

/-- Digits-only decimal of at most seven characters.
$$\operatorname{nat}(s) = n \iff s \in [0\text{-}9]^{1..7} \land \operatorname{val}(s) = n$$ -/
def nat? (s : String) : Option Nat :=
  if !s.isEmpty && s.length ≤ 7 && s.all Char.isDigit then s.toNat? else none

/-- Parse `y:N,vh:N,vw:N` in any order, each key at most once.

$$\operatorname{env}(s) = E \iff s = \texttt{k:N}(\texttt{,k:N})^* \text{ with distinct } k \in \{y, v_h, v_w\} \land E \text{ valid}$$
Absent keys take the defaults $E_0$. -/
def parseEnv (s : String) : Option Env :=
  let kvs := (s.splitOn ",").map fun kv => match kv.splitOn ":" with
    | [k, v] => (match nat? v with | some n => some (k, n) | none => none)
    | _ => none
  if kvs.any Option.isNone then none else
  let ps := kvs.filterMap id
  let keys := ps.map (·.1)
  if keys.any (fun k => k != "y" && k != "vh" && k != "vw") || keys.eraseDups.length != keys.length then none else
  let get (k : String) (d : Nat) := ((ps.find? (·.1 == k)).map (·.2)).getD d
  let e : Env := { y := get "y" Env.default.y, vw := get "vw" Env.default.vw, vh := get "vh" Env.default.vh }
  if e.valid then some e else none

/-- A parsed environment is always valid.
$$\operatorname{env}(s) = \mathrm{some}(E) \Rightarrow E \text{ valid}$$ -/
theorem parseEnv_valid (s : String) (e : Env) (h : parseEnv s = some e) : e.valid = true := by
  unfold parseEnv at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · rename_i hv
        simp only [Option.some.injEq] at h
        subst h
        exact hv
      · cases h

/-- The query pairs `key=value`, in order; the leading `?` is dropped, an empty pair skipped, a pair without `=` has
value `""`.
$$\operatorname{pairs}(q) = [(k, v) \mid p \in q.\mathrm{split}(\texttt{\&}),\ p \ne \varepsilon]$$ -/
def pairs (q : String) : List (String × String) :=
  let q := if q.startsWith "?" then (q.drop 1).toString else q
  (q.splitOn "&").filterMap fun p =>
    if p.isEmpty then none else
    match p.splitOn "=" with
    | k :: rest => some (k, "=".intercalate rest)
    | [] => none

/-- Decide a query string. Keys other than `only` and `stage` (such as `fw`) are ignored. `stage` without `only` is
`none`. A repeated `only` or `stage` is refused.

$$\operatorname{parse}(q) = \begin{cases} \bot & \text{no } \texttt{only} \\ \mathrm{duplicate} & \text{two } \texttt{only} \lor \text{two } \texttt{stage} \\
\operatorname{resolve}(t) \text{ then } \operatorname{env} & \text{otherwise}\end{cases}$$ -/
def parse (q : String) : Result :=
  let ps := pairs q
  let onlys := (ps.filter (·.1 == "only")).map (·.2)
  let stages := (ps.filter (·.1 == "stage")).map (·.2)
  match onlys with
  | [] => .none
  | _ :: _ :: _ => .err .duplicate
  | [t] =>
    if stages.length > 1 then .err .duplicate else
    match resolve t with
    | .err e => .err e
    | .ok ms =>
      match stages with
      | [] => .ok { target := t, members := ms, env := Env.default }
      | s :: _ => match parseEnv s with
        | some e => .ok { target := t, members := ms, env := e }
        | none => .err .badStage

/-- Everything `resolve` returns is stageable.
$$\operatorname{resolve}(t) = \mathrm{ok}(M) \Rightarrow \forall i \in M:\ \operatorname{stageable}(i)$$ -/
theorem resolve_stageable (t : String) (ms : List String) (hr : resolve t = .ok ms) :
    ∀ i ∈ ms, stageable i = true := by
  intro i hi
  unfold resolve at hr
  split at hr
  · split at hr
    · rename_i hs
      simp only [Res.ok.injEq] at hr
      subst hr
      simp only [List.mem_singleton] at hi
      subst hi
      exact hs
    · cases hr
  · split at hr
    · split at hr
      · cases hr
      · simp only [Res.ok.injEq] at hr
        subst hr
        exact (List.mem_filter.mp hi).2
    · cases hr

/-- A successful parse mounts only stageable parts: a page-level part cannot reach a stage through any query, since
`resolve` is the only producer of members.
$$\operatorname{parse}(q) = \mathrm{ok}(S) \Rightarrow \forall i \in S.M:\ \operatorname{stageable}(i)$$ -/
theorem parse_ok_stageable (q : String) (s : Stage) (h : parse q = .ok s) : ∀ i ∈ s.members, stageable i = true := by
  unfold parse at h
  dsimp only at h
  split at h
  · cases h
  · cases h
  · rename_i t _
    split at h
    · cases h
    · split at h
      · cases h
      · rename_i ms hr
        split at h
        · simp only [Result.ok.injEq] at h
          subst h
          exact resolve_stageable t ms hr
        · split at h
          · simp only [Result.ok.injEq] at h
            subst h
            exact resolve_stageable t ms hr
          · cases h

/-- JSON for a result. `{"kind":"none"}`, `{"kind":"ok","target":..,"members":[..],"y":..,"vw":..,"vh":..,"premise":..}`
or `{"kind":"err","code":..}`. Every `ok` carries the contract premise.
$$\operatorname{json}(\mathrm{ok}(S)) \ni \mathrm{premise} = \texttt{declared-rows-unverified}$$ -/
def Result.json : Result → String
  | .none => "{\"kind\":\"none\"}"
  | .err e => "{\"kind\":\"err\",\"code\":" ++ jstr e.name ++ "}"
  | .ok s => "{\"kind\":\"ok\",\"target\":" ++ jstr s.target ++ ",\"members\":" ++ jarr (s.members.map jstr) ++
      ",\"y\":" ++ toString s.env.y ++ ",\"vw\":" ++ toString s.env.vw ++ ",\"vh\":" ++ toString s.env.vh ++
      ",\"premise\":" ++ jstr premise ++ "}"

/-- Queries of the golden: not a stage page, each target kind, each refusal, each stage-key fault. -/
def vectors : List String :=
  ["", "?", "?fw=original", "?stage=y:100", "?only=nav", "?only=nav&stage=y:300,vh:700,vw:390",
   "?only=hero.exit&stage=vw:1440,y:0", "?only=morph.tween", "?only=engine.scroll", "?only=g1", "?only=g2",
   "?only=g4", "?only=g3", "?only=solo", "?only=nope", "?only=nav&only=pain", "?only=nav&stage=y:1&stage=y:2",
   "?only=nav&stage=y:1,y:2", "?only=nav&stage=z:1", "?only=nav&stage=y:", "?only=nav&stage=y:-1",
   "?only=nav&stage=vh:0", "?only=nav&stage=vw:10001", "?only=nav&stage=y:12345678", "?only=nav&stage=",
   "?fw=v2-proved&only=pain&stage=vh:900", "?only=hero.countdown&stage=y:0,vh:844,vw:390"]

/-- Text of `packages/contracts/golden/parts/stage.jsonl`: one `{"query":..,"result":..}` per vector.
$$\operatorname{stage} = [\{q, \operatorname{parse}(q)\} \mid q \in V]$$ -/
def goldenText : String :=
  String.join (vectors.map fun q => "{\"query\":" ++ jstr q ++ ",\"result\":" ++ (parse q).json ++ "}\n")

/-- Command-line driver (`lean/scripts/StageGolden.lean`): no argument prints the golden; `--check <file>` exits 0 when
the file holds exactly the generated bytes, 1 otherwise; any other arguments exit 2.
$$\operatorname{run}(\texttt{--check}\ f) = 0 \iff \operatorname{bytes}(f) = \operatorname{goldenText}$$ -/
def run (args : List String) : IO UInt32 := do
  match args with
  | [] => IO.print goldenText; return 0
  | ["--check", f] =>
    let cur ← IO.FS.readBinFile f
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"stage golden: {f} is up to date"
      return 0
    IO.eprintln s!"stage golden: {f} differs from the generated bytes"
    return 1
  | _ => IO.eprintln "usage: StageGolden [--check <stage.jsonl>]"; return 2

#guard parse "" == .none
#guard parse "?only=nav&stage=y:300,vh:700,vw:390" == .ok { target := "nav", members := ["nav"], env := { y := 300, vw := 390, vh := 700 } }
#guard parse "?only=morph.tween" == .err .pageLevel
#guard parse "?only=g4" == .err .emptyGroup
#guard parse "?only=nav&stage=y:1,y:2" == .err .badStage
#guard parse "?only=nav&only=pain" == .err .duplicate
#guard (parse "?only=g1") matches .ok _

end Fw.Site.Stage
