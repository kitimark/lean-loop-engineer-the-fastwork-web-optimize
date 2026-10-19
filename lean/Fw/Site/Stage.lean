import Fw.Parts.Contract

/-! Part stage route: `?only=<target>&stage=y:N,vh:N,vw:N` mounts one part, or the stageable members of one contract
group, under a fixed scroll environment. This module decides the query and the stage plan (hosts, mounted parts,
stubs, input writes); `apps/site/src/registry/only.ts` and `apps/site/src/stage/{hosts,inputs}.ts` are ports of `parse` and
`plan`, checked against `packages/contracts/golden/parts/stage.jsonl` (`lean/scripts/StageGolden.lean`). Every result
rests on the contract table's premise `declared-rows-unverified`. -/

namespace Fw.Site.Stage

open Fw.Parts.Contract (parts pageLevel members Group premise jstr jarr Signal)

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
M(g) & t \notin \mathrm{ids} \land g \in \{G_1,\dots,G_5\} \land t = \operatorname{name}(g) \land M(g) \ne [\,] \\
\mathrm{emptyGroup} & t \notin \mathrm{ids} \land g \in \{G_1,\dots,G_5\} \land t = \operatorname{name}(g) \land M(g) = [\,] \\
\mathrm{unknownTarget} & \text{otherwise (including } t = \texttt{solo})\end{cases}$$ -/
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

/-- Parse `y:N,vh:N,vw:N` in any order, each key at most once; `N` is `nat?`, one to seven ASCII digits. Absent keys take
the defaults $E_0$.

$$\operatorname{env}(s) = \mathrm{some}(E) \iff s = k_1{:}n_1,\dots,k_m{:}n_m,\ m \ge 1,\ k_j \in \{y, v_h, v_w\} \text{ pairwise distinct},\
n_j \in [0\text{-}9]^{1..7},\ E_k = n_j \text{ if } k = k_j \text{ else } (E_0)_k,\ E \text{ valid}$$ -/
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

/-- The query pairs `key=value`, in order; one leading `?` is dropped, an empty pair skipped, a pair without `=` has
value `""`, the value is everything after the first `=` (no percent-decoding).

$$\operatorname{pairs}(q) = [(k, v) \mid p \in q'.\mathrm{split}(\texttt{\&}),\ p \ne \varepsilon,\ p = k \,(\texttt{=}\, v)^?,\ \texttt{=} \notin k],\quad
q' = q \text{ without one leading } \texttt{?},\ v = \varepsilon \text{ if } p \text{ has no } \texttt{=}$$ -/
def pairs (q : String) : List (String × String) :=
  let q := if q.startsWith "?" then (q.drop 1).toString else q
  (q.splitOn "&").filterMap fun p =>
    if p.isEmpty then none else
    match p.splitOn "=" with
    | k :: rest => some (k, "=".intercalate rest)
    | [] => none

/-- Decide a query string. Keys other than `only` and `stage` (such as `fw`) are ignored. `stage` without `only` is
`none`. A repeated `only` or `stage` is refused. With $O$ and $S$ the values of the `only` and `stage` pairs, cases in
order:

$$\operatorname{parse}(q) = \begin{cases} \bot & |O| = 0 \\
\mathrm{duplicate} & |O| \ge 2 \lor (|O| = 1 \land |S| \ge 2) \\
e & O = [t],\ \operatorname{resolve}(t) = e \\
\mathrm{ok}(t, M, E_0) & O = [t],\ \operatorname{resolve}(t) = \mathrm{ok}(M),\ S = [\,] \\
\mathrm{ok}(t, M, E) & O = [t],\ \operatorname{resolve}(t) = \mathrm{ok}(M),\ S = [s],\ \operatorname{env}(s) = \mathrm{some}(E) \\
\mathrm{badStage} & O = [t],\ \operatorname{resolve}(t) = \mathrm{ok}(M),\ S = [s],\ \operatorname{env}(s) = \bot\end{cases}$$ -/
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

/-- A page piece React renders for a part: the six sections in page order, then nav, the morph panel and the two overlays.
$$H = \{\mathrm{hero}, \mathrm{people}, \mathrm{pain}, \mathrm{commission}, \mathrm{platform}, \mathrm{columns}, \mathrm{nav},
\mathrm{panel}, \mathrm{drawer}, \mathrm{signup}\}$$ -/
inductive Host | hero | people | pain | commission | platform | columns | nav | panel | drawer | signup
deriving Repr, DecidableEq

/-- Wire name of a host. $$\operatorname{name}(h)$$ the constructor name. -/
def Host.name : Host → String
  | .hero => "hero" | .people => "people" | .pain => "pain" | .commission => "commission" | .platform => "platform"
  | .columns => "columns" | .nav => "nav" | .panel => "panel" | .drawer => "drawer" | .signup => "signup"

/-- Hosts in render order. $$\mathrm{order}(H)$$ -/
def Host.order : List Host :=
  [.hero, .people, .pain, .commission, .platform, .columns, .nav, .panel, .drawer, .signup]

/-- The six section hosts in page order; each is a fixed-height stub when nothing staged lives in it.
$$\mathrm{sections} = [\mathrm{hero}, \mathrm{people}, \mathrm{pain}, \mathrm{commission}, \mathrm{platform}, \mathrm{columns}]$$ -/
def sections : List Host := [.hero, .people, .pain, .commission, .platform, .columns]

/-- The host of each part id, by identity (one row per part that has one). Page-level parts have none.
$$\operatorname{hostOf} : \mathrm{ids} \rightharpoonup H$$ -/
def hostTable : List (String × Host) :=
  [("commission", .commission), ("commission.typing", .commission), ("engine.scene", .platform),
   ("hero", .hero), ("hero.accent", .hero), ("hero.countdown", .hero), ("hero.cue", .hero), ("hero.deck", .hero),
   ("hero.exit", .hero), ("hero.orbit", .hero), ("morph.columns", .columns), ("morph.countdown", .panel),
   ("morph.mount", .panel), ("morph.panel", .panel), ("nav", .nav), ("nav.hitTest", .nav), ("nav.langMenu", .nav),
   ("overlays.drawer", .drawer), ("overlays.signup", .signup), ("pain", .pain), ("pain.notes", .pain),
   ("people", .people), ("people.card", .people), ("people.carousel", .people), ("people.deck", .people),
   ("people.o", .people), ("platform", .platform), ("platform.entries", .platform), ("platform.glint", .platform),
   ("platform.marquee", .platform), ("platform.stageBg", .platform), ("platform.sweep", .platform)]

/-- Host of a part id. $$\operatorname{hostOf}(i) = h \iff (i, h) \in \mathrm{hostTable}$$ -/
def hostOf (i : String) : Option Host := (hostTable.find? (·.1 == i)).map (·.2)

/-- Every part that can be staged has a host and no page-level part has one.
$$\forall P \in \mathrm{parts}:\ (\lnot\operatorname{pageLevel}(P) \Rightarrow \operatorname{hostOf}(P.\mathrm{id}) \ne \bot) \land
(\operatorname{pageLevel}(P) \Rightarrow \operatorname{hostOf}(P.\mathrm{id}) = \bot)$$ -/
theorem hostOf_total_on_stageable :
    ∀ P ∈ parts, (pageLevel P = false → (hostOf P.id).isSome = true) ∧ (pageLevel P = true → hostOf P.id = none) := by
  decide

/-- Stub height of a section in hundredths of the stage `vh`: hero 100, people 315, pain 300, commission 106,
platform 200, columns 100 (approximate by design; the exact boxes are gen-shells').
$$\operatorname{x100} = (100, 315, 300, 106, 200, 100)$$ -/
def stubX100 : Host → Nat
  | .hero => 100 | .people => 315 | .pain => 300 | .commission => 106 | .platform => 200 | .columns => 100 | _ => 0

/-- Stub height in CSS pixels, rounded half up. $$\operatorname{px}(h, v_h) = \lfloor (\operatorname{x100}(h)\,v_h + 50) / 100 \rfloor$$ -/
def stubPx (h : Host) (vh : Nat) : Nat := (stubX100 h * vh + 50) / 100

/-- Rest value of an input at page top; none for an input with no known rest value.
$$\operatorname{rest}(\texttt{--exit-opacity}) = 1,\ \operatorname{rest}(\texttt{--morph}) = 0,\ \operatorname{rest}(\texttt{--morph-fade}) = 0$$ -/
def rest : String → Option String
  | "--exit-opacity" => some "1" | "--morph" => some "0" | "--morph-fade" => some "0" | _ => none

/-- An input written once on its owner's element. `class` removes a class (absent at rest), `cssVar` sets a custom
property, `attr` an attribute. $$w = (\mathrm{kind}, o, n, v)$$ -/
structure Write where
  kind : String
  owner : String
  name : String
  value : Option String
deriving Repr, DecidableEq

/-- Wire form `kind:name/owner=value`, without `=value` when the value is none.
$$\operatorname{wire}(w) = k \texttt{:} n \texttt{/} o\,(\texttt{=} v)^?$$ -/
def Write.wire (w : Write) : String :=
  w.kind ++ ":" ++ w.name ++ "/" ++ w.owner ++ (match w.value with | some v => "=" ++ v | none => "")

/-- What one declared input asks of the stage.
$$\epsilon \in \{\mathrm{none}, \mathrm{write}(w), \mathrm{neighbour}(o), \mathrm{unset}(\sigma)\}$$ -/
inductive Effect | none | write (w : Write) | neighbour (o : String) | unset (s : String)
deriving Repr, DecidableEq

/-- Effect of one declared input of a mounted part, given the mounted ids. The environment signals (`scrollY`, `vw`,
`vh`, `clock`, `pointer`) are provided by the stage. A `rect` of an unmounted owner needs a neighbour box (owner with a
host), else the input is unset. For an unmounted owner with a host, a non-`data-` class is always removed (it is absent
at rest); a `cssVar` or a `data-` attribute is written at its rest value when `rest` knows one, otherwise it is unset.
An owner without a host is unset. An owner that is mounted writes its own value. `morphPhase`, `scenePaused`, and a
`cssVar` or `className` string that does not split at `/` into exactly two pieces $n/o$ are unset.

$$\epsilon(\sigma) = \begin{cases}\mathrm{none} & \sigma \in \{\mathrm{scrollY},\mathrm{vw},\mathrm{vh},\mathrm{clock},\mathrm{pointer}\} \lor \sigma \in \{\mathrm{rect}(o), \mathrm{cssVar}(n/o), \mathrm{className}(n/o)\},\ o \in \mathrm{mounted} \\
\mathrm{neighbour}(o) & \sigma = \mathrm{rect}(o),\ o \notin \mathrm{mounted},\ \operatorname{hostOf}(o) \ne \bot \\
\mathrm{write}(\mathrm{cssVar}, o, n, v) & \sigma = \mathrm{cssVar}(n/o),\ o \notin \mathrm{mounted},\ \operatorname{hostOf}(o) \ne \bot,\ \operatorname{rest}(n) = v \\
\mathrm{write}(\mathrm{attr}, o, n, v) & \sigma = \mathrm{className}(n/o),\ n = \texttt{data-}\cdots,\ o \notin \mathrm{mounted},\ \operatorname{hostOf}(o) \ne \bot,\ \operatorname{rest}(n) = v \\
\mathrm{write}(\mathrm{class}, o, n, \bot) & \sigma = \mathrm{className}(n/o),\ n \ne \texttt{data-}\cdots,\ o \notin \mathrm{mounted},\ \operatorname{hostOf}(o) \ne \bot \\
\mathrm{unset}(\sigma) & \text{otherwise}\end{cases}$$

where $n/o$ means the string splits at `/` into exactly the two pieces $n$ and $o$. -/
def effect (mounted : List String) (s : Signal) : Effect :=
  let named (kind : String) (n : String) : Effect :=
    match n.splitOn "/" with
    | [name, owner] =>
      if mounted.contains owner then .none
      else if (hostOf owner).isNone then .unset s.wire
      else if kind == "cssVar" then
        match rest name with
        | some v => .write { kind := "cssVar", owner, name, value := some v }
        | none => .unset s.wire
      else if name.startsWith "data-" then
        match rest name with
        | some v => .write { kind := "attr", owner, name, value := some v }
        | none => .unset s.wire
      else .write { kind := "class", owner, name, value := none }
    | _ => .unset s.wire
  match s with
  | .scrollY | .vw | .vh | .clock | .pointer => .none
  | .morphPhase | .scenePaused => .unset s.wire
  | .rect o => if mounted.contains o then .none else if (hostOf o).isSome then .neighbour o else .unset s.wire
  | .cssVar n => named "cssVar" n
  | .className n => named "className" n

/-- The plan of a stage: which hosts React renders, every part id under them (`mounted`), the fixed-height stubs of the
other sections, the once-written inputs, the neighbour boxes, the inputs left unset, and the scroll engine variant
(fixed per stage). Deduplicated in order of first appearance. $$\Pi = (S, H, \mathrm{mounted}, \mathrm{stubs}, W, N, U, \mathrm{engine})$$ -/
structure Plan where
  stage : Stage
  hosts : List Host
  mounted : List String
  stubs : List (Host × Nat)
  writes : List Write
  neighbours : List String
  unset : List String
  scrollEngine : String
deriving Repr, DecidableEq

/-- Part ids under a set of hosts, in contract order.
$$\operatorname{mountedOf}(H') = [P.\mathrm{id} \mid P \in \mathrm{parts},\ \operatorname{hostOf}(P.\mathrm{id}) \in H']$$ -/
def mountedOf (hs : List Host) : List String :=
  (parts.map (·.id)).filter fun i => match hostOf i with | some h => hs.contains h | none => false

/-- Plan of a stage. $$H = [h \in \mathrm{order} \mid \exists i \in M:\ \operatorname{hostOf}(i) = h]$$ stubs are the sections
not in $H$ with `stubPx`; inputs are the `effect`s of every declared input of every mounted part. -/
def Stage.plan (s : Stage) : Plan :=
  let hosts := Host.order.filter fun h => s.members.any fun i => hostOf i == some h
  let mounted := mountedOf hosts
  let effects := (parts.filter fun P => mounted.contains P.id).flatMap fun P => P.inputs.map (effect mounted)
  { stage := s, hosts, mounted,
    stubs := (sections.filter fun h => !hosts.contains h).map fun h => (h, stubPx h s.env.vh),
    writes := (effects.filterMap fun | .write w => some w | _ => none).eraseDups,
    neighbours := (effects.filterMap fun | .neighbour o => some o | _ => none).eraseDups,
    unset := (effects.filterMap fun | .unset x => some x | _ => none).eraseDups,
    scrollEngine := "faithful" }

/-- The plan of a query: some exactly when `parse` accepts it.
$$\operatorname{plan}(q) = \mathrm{some}(\Pi) \iff \operatorname{parse}(q) = \mathrm{ok}(S) \land \Pi = \Pi(S)$$ -/
def plan (q : String) : Option Plan := match parse q with | .ok s => some s.plan | _ => none

/-- A staged member is mounted: every part the stage targets is under a rendered host.
$$\operatorname{plan}(q) = \mathrm{some}(\Pi) \Rightarrow \forall i \in \Pi.S.M:\ i \in \Pi.\mathrm{mounted}$$ -/
theorem plan_members_mounted (q : String) (p : Plan) (h : plan q = some p) : ∀ i ∈ p.stage.members, i ∈ p.mounted := by
  intro i hi
  unfold plan at h
  split at h
  · rename_i s hs
    simp only [Option.some.injEq] at h
    subst h
    have hst := parse_ok_stageable q s hs i hi
    unfold stageable at hst
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hst
    obtain ⟨P, hP, hid, hpl⟩ := hst
    obtain ⟨h0, hh0⟩ := Option.isSome_iff_exists.mp ((hostOf_total_on_stageable P hP).1 hpl)
    rw [hid] at hh0
    simp only [Stage.plan, mountedOf, List.mem_filter, List.mem_map]
    refine ⟨⟨P, hP, hid⟩, ?_⟩
    rw [hh0]
    simp only [List.contains_eq_any_beq, List.any_eq_true, List.mem_filter, beq_iff_eq]
    have hi' : i ∈ s.members := hi
    have hord : ∀ h : Host, h ∈ Host.order := by intro h; cases h <;> simp [Host.order]
    exact ⟨h0, ⟨hord h0, i, hi', hh0⟩, rfl⟩
  · cases h

/-- Page-level parts are never mounted by a stage: they have no host. In particular `engine.scroll` and `morph.tween`
are not in any `mounted`, while the shared scroll engine they own is created by the mounted parts; `scrollEngine` names
its (fixed) variant. $$\forall P \in \mathrm{parts},\ \operatorname{pageLevel}(P) \Rightarrow P.\mathrm{id} \notin \operatorname{mountedOf}(H')$$ -/
theorem pageLevel_never_mounted (hs : List Host) : ∀ P ∈ parts, pageLevel P = true → P.id ∉ mountedOf hs := by
  intro P hP hpl hm
  have h0 := (hostOf_total_on_stageable P hP).2 hpl
  simp only [mountedOf, List.mem_filter, h0] at hm
  simp at hm

theorem effect_write_unmounted (m : List String) (s : Signal) (w : Write) (h : effect m s = .write w) :
    m.contains w.owner = false := by
  cases s <;> simp only [effect] at h <;> (repeat' split at h) <;> (try cases h) <;> simp_all

theorem hero_host_mounts_exit (hs : List Host) (i : String) (hi : hostOf i = some .hero) (hm : i ∈ mountedOf hs) :
    "hero.exit" ∈ mountedOf hs := by
  simp only [mountedOf, List.mem_filter, hi] at hm ⊢
  exact ⟨by decide, by rw [show hostOf "hero.exit" = some .hero by decide]; exact hm.2⟩

/-- No stage that mounts a hero part writes a rest value on hero.exit: the stage's own CSS default holds instead. -/
theorem exit_owner_never_written (hs : List Host) (i : String) (hi : hostOf i = some .hero) (hm : i ∈ mountedOf hs)
    (s : Signal) (w : Write) (he : effect (mountedOf hs) s = .write w) : w.owner ≠ "hero.exit" := by
  intro hw
  have hu := effect_write_unmounted _ _ _ he
  rw [hw] at hu
  simp [hero_host_mounts_exit hs i hi hm] at hu

theorem exit_readers_on_hero : ["hero", "hero.cue", "hero.orbit", "hero.deck"].all (hostOf · == some .hero) = true := by
  decide

/-- Wire form of a stub: `host=px`. $$\operatorname{wire}(h, p) = h \texttt{=} p$$ -/
def stubWire (x : Host × Nat) : String := x.1.name ++ "=" ++ toString x.2

/-- JSON for a result. `{"kind":"none"}`, `{"kind":"ok","target":..,"members":[..],"y":..,"vw":..,"vh":..,"premise":..,
"hosts":[..],"mounted":[..],"stubs":[..],"writes":[..],"neighbours":[..],"unset":[..],"scrollEngine":..}` or
`{"kind":"err","code":..}`. Every `ok` carries the contract premise.
$$\operatorname{json}(\mathrm{ok}(S)) \ni \mathrm{premise} = \texttt{declared-rows-unverified}$$ -/
def Result.json : Result → String
  | .none => "{\"kind\":\"none\"}"
  | .err e => "{\"kind\":\"err\",\"code\":" ++ jstr e.name ++ "}"
  | .ok s =>
    let p := s.plan
    "{\"kind\":\"ok\",\"target\":" ++ jstr s.target ++ ",\"members\":" ++ jarr (s.members.map jstr) ++
      ",\"y\":" ++ toString s.env.y ++ ",\"vw\":" ++ toString s.env.vw ++ ",\"vh\":" ++ toString s.env.vh ++
      ",\"premise\":" ++ jstr premise ++
      ",\"hosts\":" ++ jarr (p.hosts.map (jstr ·.name)) ++ ",\"mounted\":" ++ jarr (p.mounted.map jstr) ++
      ",\"stubs\":" ++ jarr (p.stubs.map (jstr ∘ stubWire)) ++ ",\"writes\":" ++ jarr (p.writes.map (jstr ·.wire)) ++
      ",\"neighbours\":" ++ jarr (p.neighbours.map jstr) ++ ",\"unset\":" ++ jarr (p.unset.map jstr) ++
      ",\"scrollEngine\":" ++ jstr p.scrollEngine ++ "}"

/-- Queries of the golden: not a stage page, each target kind, each refusal, each stage-key fault, plan rounding and
mounting cases, then one `?only=` query per part id in contract order.
$$V = [q_1, \dots, q_n] \mathbin{+\!\!+} [\texttt{?only=}P.\mathrm{id} \mid P \in \mathrm{parts}]$$ -/
def vectors : List String :=
  ["", "?", "?fw=original", "?stage=y:100", "?only=nav", "?only=nav&stage=y:300,vh:700,vw:390",
   "?only=hero.exit&stage=vw:1440,y:0", "?only=morph.tween", "?only=engine.scroll", "?only=g1", "?only=g2",
   "?only=g4", "?only=g3", "?only=solo", "?only=nope", "?only=nav&only=pain", "?only=nav&stage=y:1&stage=y:2",
   "?only=nav&stage=y:1,y:2", "?only=nav&stage=z:1", "?only=nav&stage=y:", "?only=nav&stage=y:-1",
   "?only=nav&stage=vh:0", "?only=nav&stage=vw:10001", "?only=nav&stage=y:12345678", "?only=nav&stage=",
   "?fw=v2-proved&only=pain&stage=vh:900", "?only=hero.countdown&stage=y:0,vh:844,vw:390", "?only=hero.accent&stage=vh:845", "?only=nav.hitTest",
   "?only=morph.panel&stage=vh:333", "?only=platform.sweep", "?only=overlays.signup", "?only=g5", "?only=nav&only", "?only",
   "?&only=nav", "?only=nav=x", "?only=nav&stage=y:0000001"] ++ parts.map ("?only=" ++ ·.id)

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
#guard (plan "?only=nav").map (·.stubs.map (·.2)) == some [800, 2520, 2400, 848, 1600, 800]
#guard (plan "?only=nav").map (·.hosts) == some [.nav]
#guard (plan "?only=morph.tween").isNone

end Fw.Site.Stage
