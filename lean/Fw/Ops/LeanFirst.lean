/-!
# The lean-first land gate: facts in, one verdict out

Task `lfg-spec` (research/notes/2026/10-18-lean-first-gate.md, sections 0, 7 and 8). `fw land --dry` and `fw land` will
run one check, `lean-first` (wired by `lfg-land-wire`, not here): the TS gathers `Facts` (MathView JSON, `kills.jsonl`,
`ts-lean-lint --json`, `docs/team/props/signoffs.jsonl`, git order facts, the premise registry, the task row of
work-graph.json), calls the fwcore op `ops.leanFirst`, prints `Out.lines` verbatim and exits with `Out.exit`. Every
decision is here; the TS has no printing branch.

* **Rules** (`Rule`): `props` (rule 1: a task whose writes may cover decision code, i.e. anything outside the
  allowlist `docs/**`, `research/**`, has properties; every property is proved by one theorem whose own implementation
  argument is reached from the wire, signed by both reviewers at its current hashes, and killed), `kills` (rule 2: every new theorem has a
  kill or is exempt), `twins` (rule 3: every new TS/YAML data branch is marked), `premises` (rule 4: carriers are
  assumed, assumed ids are registered and not refuted), `search` (rule 5: the search guards come before the proof in
  git) and `ratchet` (stage 3: the legacy count does not grow).
* **Reasons** (`reasons`): every failure of every rule, one `Reason` each, in the rule order above.
* **Stages** (`Stage`, `enforced`): which rules refuse, for a task with or without `leanFirst`. The deployed stage is
  the constant `stage` (shadow: nothing refuses; the would-refuse reasons are printed on `LEANFIRST` lines).
* **Verdict** (`gate`): missing facts (a source, the reach of a candidate theorem, or exemption classes not read at
  main) with any rule enforced give `pending` (fail closed, exit 75); otherwise the
  enforced reasons, if any, give `refuse`, else `pass`.
* **Output** (`out`): `REASON`, `LEANFIRST` and `WARN` lines, then exactly one `VERDICT` line, last. Every piece of
  fact text is cleaned of line breaks, so a fact cannot forge a second line on stdout.

The properties the gate satisfies (the 15 statements of section 7 and more) are stated over the signature of the gate
in `Fw.Ops.LeanFirstProps` and proved there; the search over `Enum Facts` is in `Fw.Ops.LeanFirstSearch`; the
mutants that kill each property in kernel are in `lean/FwTest/Mutants/LeanFirst/`.
-/
namespace Fw.Ops.LeanFirst

/-! ## Facts -/

/-- The two reviewer roles of a property signoff. -/
inductive Role where
  | math | adversary
deriving DecidableEq, Repr

/-- One row of `docs/team/props/signoffs.jsonl`: the declaration, the deep statement hash it was reviewed at, the
reviewer role and whether the reviewer agreed. -/
structure Signoff where
  decl : String
  stmtHash : String
  role : Role
  agree : Bool
deriving DecidableEq, Repr

/-- One kill: a mutant that the target theorem (or property) rejects, at the target's deep statement hash. Tier-K rows
come from MathView (`killOf`), tier-T rows from `kills.jsonl`. -/
structure KillRow where
  target : String
  hash : String
deriving DecidableEq, Repr

/-- The class of a theorem for rule 2: a general theorem, a data lint (closed, `decide`/`rfl`, listed in
`FwTest/Mutants/exempt.tsv` with class `data`), or a kill witness (`¬ P m`, MathView `killOf`). -/
inductive ThmKind where
  | general | data | kill
deriving DecidableEq, Repr

/-- What MathView reports about one theorem: name, deep statement hash, class, the property `P` when its type is
`P impl` (`proves`, the head constant), the implementation it is about (`implArg`, the argument of `P`; none when the
type is not `P impl` of one definition), whether that implementation is reachable from `Fw.Wire.handle` or a golden
generator (`reachFromWire`: some true, some false, or none when MathView could not decide), whether it uses only the
standard axioms, the theorems whose proofs reach it, the definitions it reaches, and its `Assume` premise ids. The
triple `(name, implArg, reachFromWire)` is one MathView record (`lfg-mathview-facts`), so
the reach of a theorem is always the reach of its own implementation. -/
structure ThmFact where
  name : String
  hash : String
  kind : ThmKind
  proves : Option String
  implArg : Option String
  reachFromWire : Option Bool
  axiomsOk : Bool
  usedBy : List String
  reach : List String
  assumes : List String
deriving DecidableEq, Repr

/-- What MathView and git report about one property of the task's Props module: name, deep statement hash, the
premise ids the property itself assumes, and the commits that first added its search guards and its proof. Reach is
not a property fact: it comes with each theorem's own `implArg`. -/
structure PropFact where
  name : String
  stmtHash : String
  assumes : List String
  searchAt : Option String
  proofAt : Option String
deriving DecidableEq, Repr

/-- The marker `ts-lean-lint` found on the function around a new data branch: none, `// lean: <op>`,
`// twin: <golden>`, an accepted `// glue:` or a `// glue:` the lint refused. -/
inductive Mark where
  | none | op | twin | glueOk | glueBad
deriving DecidableEq, Repr

/-- The marks that satisfy rule 3. -/
def Mark.ok : Mark → Bool
  | .op | .twin | .glueOk => true
  | .none | .glueBad => false

/-- One new data branch in a changed TS/JS/YAML hunk: file, line and mark. -/
structure Branch where
  file : String
  line : Nat
  mark : Mark
deriving DecidableEq, Repr

/-- The status of a premise in `Fw.Ops.Premise`. -/
inductive Status where
  | measured | untested | refuted | unmeasurable
deriving DecidableEq, Repr

/-- One premise registry row: id, status, and the carrier definitions that encode the premise inside them. -/
structure PremRow where
  id : String
  status : Status
  carriers : List String
deriving DecidableEq, Repr

/-- Which fact sources were read: the MathView JSON, the `kills.jsonl` artifact and the `ts-lean-lint` output. A
`false` means the source is missing; its lists are then empty and must not be read as evidence. -/
structure Present where
  mathview : Bool
  kills : Bool
  tsLint : Bool
deriving DecidableEq, Repr

/-- **The facts of one land**, all structured: the task's `leanFirst` flag, its `writes` globs together with the
paths the land changes (a path is a glob without `*`), its properties, the theorems, kills, signoffs, data branches,
premise registry, the baseline `(name, hash)` pairs of the cutover commit, the strict-ancestor pairs of commits, the
legacy gap counts on main and at the head, which sources were present, the main commit the land merges onto, and the
commit at which `FwTest/Mutants/exempt.tsv` and the MathView `killOf` classifier were read (none when not read). The
gate uses the kinds `data` and `kill` only when that commit is main (else `Missing.exempt`), so a branch cannot exempt
its own theorems by editing `exempt.tsv`. -/
structure Facts where
  leanFirst : Bool
  writes : List String
  props : List PropFact
  thms : List ThmFact
  kills : List KillRow
  signoffs : List Signoff
  branches : List Branch
  registry : List PremRow
  baseline : List (String × String)
  ancestry : List (String × String)
  legacyMain : Nat
  legacyHead : Nat
  present : Present
  mainAt : String
  exemptAt : Option String
deriving DecidableEq, Repr

/-! ## Decision code paths (rule 1a) -/

/-- The allowlisted roots of non-decision code (`docs/**` holds the handoffs and the work graph). -/
def allowRoots : List String := ["docs", "research"]

/-- **Is a write glob (or a changed path) decision code?** Yes, unless it equals an allowlisted root or starts with
a root followed by `/`. Fail closed: every other glob, `*`-globs and `.md` globs included, may cover decision code
(`Fw.Ops.LeanFirstProps.DecisionWrite` is the rule this decides). -/
def isDecisionWrite (w : String) : Bool :=
  !allowRoots.any fun d => w.toList == d.toList || (d.toList ++ ['/']).isPrefixOf w.toList

#guard isDecisionWrite "lean/Fw/Ops/LeanFirst*.lean"
#guard isDecisionWrite "lean/**"
#guard isDecisionWrite "apps/runner/**"
#guard isDecisionWrite "lean/Fw/Props/LandDry.lean"
#guard isDecisionWrite "apps/runner/test/land.test.ts"
#guard isDecisionWrite "README.md"
#guard isDecisionWrite "doc*/x.md"
#guard isDecisionWrite "docsx/a"
#guard isDecisionWrite "*"
#guard isDecisionWrite ""
#guard !isDecisionWrite "docs/team/tools/lean-first.md"
#guard !isDecisionWrite "docs/team/handoffs/lfg-spec.md"
#guard !isDecisionWrite "docs/team/work-graph.json"
#guard !isDecisionWrite "research/**"
#guard !isDecisionWrite "docs"

/-- Does the task write decision code (rule 1a)? -/
def decides (F : Facts) : Bool := F.writes.any isDecisionWrite

/-- The first decision write, the subject of a `noProps` refusal (`""` when there is none). -/
def firstDecision (F : Facts) : String := (F.writes.find? isDecisionWrite).getD ""

/-! ## The rule predicates, as Boolean functions of the facts -/

/-- Does the theorem have a kill at its current hash? -/
def hasKill (F : Facts) (t : ThmFact) : Bool := F.kills.any fun k => k.target == t.name && k.hash == t.hash

/-- Is the theorem new: the baseline has no entry for its name, or one with a different hash? (`List.lookup` takes the
first baseline entry of the name.) -/
def isNew (F : Facts) (t : ThmFact) : Bool := F.baseline.lookup t.name != some t.hash

/-- Does some theorem with this name have a kill at its hash? -/
def killedName (F : Facts) (n : String) : Bool := F.thms.any fun u => u.name == n && hasKill F u

/-- **Exempt from its own kill** (rule 2): a data lint or a kill witness, or a lemma: a new theorem without a kill of
its own that a theorem with a kill uses. -/
def exempt (F : Facts) (t : ThmFact) : Bool :=
  t.kind != .general || (isNew F t && !hasKill F t && t.usedBy.any (killedName F))

/-- The status of a premise id: the first registry row with that id, or none. -/
def statusOf (F : Facts) (p : String) : Option Status := (F.registry.find? (·.id == p)).map (·.status)

/-- An untested premise of the theorem may discharge the property only if the property assumes it too (rule 4d). -/
def untestedOk (F : Facts) (t : ThmFact) (P : PropFact) : Bool :=
  t.assumes.all fun p => statusOf F p != some .untested || P.assumes.contains p

/-- **The theorem discharges the property** (rule 1c): its type is `P impl` for a named implementation, it uses only
standard axioms, it is not exempt, and its untested premises are the property's. -/
def discharges (F : Facts) (t : ThmFact) (P : PropFact) : Bool :=
  t.proves == some P.name && t.implArg.isSome && t.axiomsOk && !exempt F t && untestedOk F t P

/-- Is the property proved: some theorem discharges it? -/
def proved (F : Facts) (P : PropFact) : Bool := F.thms.any fun t => discharges F t P

/-- **Proved of a reached implementation** (rules 1c and 1d together): one theorem discharges the property, and the
implementation named by that theorem's own `implArg` is reached from the wire. A reached definition elsewhere does
not count. -/
def provedReached (F : Facts) (P : PropFact) : Bool :=
  F.thms.any fun t => discharges F t P && t.reachFromWire == some true

/-- Is the reach of some candidate theorem unknown: it is `Q impl` for a property `Q` of the task, with a named
implementation, and MathView reports no `reachFromWire`? -/
def reachUnknown (F : Facts) : Bool :=
  F.thms.any fun t => t.reachFromWire.isNone && t.implArg.isSome && F.props.any fun Q => t.proves == some Q.name

/-- Does a signoff row name the property at its current statement hash, for the role? The math of a signoff lives in
an artifact (docs/team/tools/math-artifact.md), so the statement hash alone keys it. -/
def Signoff.matches (s : Signoff) (P : PropFact) (r : Role) : Bool :=
  s.decl == P.name && s.stmtHash == P.stmtHash && s.role == r

/-- **Signed** (rule 1b): an agreeing row at the current hashes for the role, and no disagreeing one. -/
def signed (F : Facts) (P : PropFact) (r : Role) : Bool :=
  F.signoffs.any (fun s => s.matches P r && s.agree) && !F.signoffs.any (fun s => s.matches P r && !s.agree)

/-- Does the property have a kill at its statement hash (rule 1e)? -/
def propKilled (F : Facts) (P : PropFact) : Bool := F.kills.any fun k => k.target == P.name && k.hash == P.stmtHash

/-- **Search before proof** (rule 5): both commits are known and the search commit is a strict ancestor of the proof
commit. -/
def searchFirst (F : Facts) (P : PropFact) : Bool :=
  match P.searchAt, P.proofAt with
  | some a, some b => F.ancestry.contains (a, b)
  | _, _ => false

/-- The premises whose carrier definitions the theorem reaches (rule 4b), in registry order. -/
def carriersOf (F : Facts) (t : ThmFact) : List String :=
  (F.registry.filter fun r => r.carriers.any t.reach.contains).map (·.id)

/-- Is the premise id a registry row? -/
def registered (F : Facts) (p : String) : Bool := F.registry.any (·.id == p)

/-- Is the premise refuted? -/
def refutedId (F : Facts) (p : String) : Bool := statusOf F p == some .refuted

/-! ## Rules and reasons -/

/-- The six rules of the gate. -/
inductive Rule where
  | props | kills | twins | premises | search | ratchet
deriving DecidableEq, Repr

/-- Every rule, in the order the reasons are listed. -/
def Rule.all : List Rule := [.props, .kills, .twins, .premises, .search, .ratchet]

/-- The wire name of a rule. -/
def Rule.name : Rule → String
  | .props => "props" | .kills => "kills" | .twins => "twins" | .premises => "premises" | .search => "search"
  | .ratchet => "ratchet"

/-- One failure of one rule, with its subject. -/
inductive Reason where
  | noProps (path : String)
  | unproved (prop : String)
  | unreached (prop : String)
  | unsigned (prop : String) (role : Role)
  | unkilled (prop : String)
  | noKill (thm : String)
  | branch (file : String) (line : Nat) (mark : Mark)
  | hidden (thm premise : String)
  | unregistered (thm premise : String)
  | refuted (thm premise : String)
  | searchOrder (prop : String)
  | growth (main head : Nat)
deriving DecidableEq, Repr

/-- The rule a reason belongs to. -/
def Reason.rule : Reason → Rule
  | .noProps _ | .unproved _ | .unreached _ | .unsigned _ _ | .unkilled _ => .props
  | .noKill _ => .kills
  | .branch _ _ _ => .twins
  | .hidden _ _ | .unregistered _ _ | .refuted _ _ => .premises
  | .searchOrder _ => .search
  | .growth _ _ => .ratchet

/-- The reason code printed on `REASON` lines (and used by the mutants to drop one kind). -/
def Reason.code : Reason → String
  | .noProps _ => "no-props" | .unproved _ => "unproved" | .unreached _ => "unreached"
  | .unsigned _ .math => "unsigned-math" | .unsigned _ .adversary => "unsigned-adversary"
  | .unkilled _ => "unkilled" | .noKill _ => "no-kill"
  | .branch _ _ .none => "unmarked" | .branch _ _ _ => "glue-refused"
  | .hidden _ _ => "hidden" | .unregistered _ _ => "unregistered" | .refuted _ _ => "refuted"
  | .searchOrder _ => "proof-before-search" | .growth _ _ => "growth"

/-- The subject of a reason: a declaration, `file:line`, `theorem premise`, or `main->head` counts.
Here `dec` writes a natural number in decimal and `" "` is one space. -/
def Reason.subject : Reason → String
  | .noProps w => w | .unproved p | .unreached p | .unsigned p _ | .unkilled p | .searchOrder p => p
  | .noKill t => t
  | .branch f n _ => f ++ ":" ++ toString n
  | .hidden t p | .unregistered t p | .refuted t p => t ++ " " ++ p
  | .growth a b => toString a ++ "->" ++ toString b

/-- The reasons of rule 1 for one property: unproved when no theorem discharges it, else unreached when no
discharging theorem's own implementation is reached; then each missing signoff and a missing kill. -/
def propReasons (F : Facts) (P : PropFact) : List Reason :=
  (if proved F P then (if provedReached F P then [] else [.unreached P.name]) else [.unproved P.name]) ++
  (if signed F P .math then [] else [.unsigned P.name .math]) ++
  (if signed F P .adversary then [] else [.unsigned P.name .adversary]) ++
  (if propKilled F P then [] else [.unkilled P.name])

/-- The reason of rule 2 for one theorem: new, without a kill, and not exempt. -/
def killReasons (F : Facts) (t : ThmFact) : List Reason :=
  if isNew F t && !(hasKill F t || exempt F t) then [.noKill t.name] else []

/-- The reason of rule 3 for one branch: its mark is not accepted. -/
def branchReasons (b : Branch) : List Reason :=
  if b.mark.ok then [] else [.branch b.file b.line b.mark]

/-- The reasons of rule 4 for one theorem, if it is new: each reached carrier it does not assume, each assumed id
that is not registered, each assumed id that is refuted. -/
def premReasons (F : Facts) (t : ThmFact) : List Reason :=
  if isNew F t then
    ((carriersOf F t).filter (fun p => !t.assumes.contains p)).map (.hidden t.name) ++
    (t.assumes.filter (fun p => !registered F p)).map (.unregistered t.name) ++
    (t.assumes.filter (refutedId F)).map (.refuted t.name)
  else []

/-- The reason of rule 5 for one property. -/
def searchReasons (F : Facts) (P : PropFact) : List Reason :=
  if searchFirst F P then [] else [.searchOrder P.name]

/-- **The reasons of one rule.** Rule 1: no property although the task writes decision code, then each property's
reasons; rule 2: per theorem; rule 3: per branch; rule 4: per theorem; rule 5: per property; ratchet: the legacy count
grew. -/
def reasonsOf (F : Facts) : Rule → List Reason
  | .props => (if decides F && F.props.isEmpty then [.noProps (firstDecision F)] else []) ++
      F.props.flatMap (propReasons F)
  | .kills => F.thms.flatMap (killReasons F)
  | .twins => F.branches.flatMap branchReasons
  | .premises => F.thms.flatMap (premReasons F)
  | .search => F.props.flatMap (searchReasons F)
  | .ratchet => if F.legacyHead ≤ F.legacyMain then [] else [.growth F.legacyMain F.legacyHead]

/-- **Every failure of every rule**, in rule order. -/
def reasons (F : Facts) : List Reason := Rule.all.flatMap (reasonsOf F)

/-- The facts that can be missing: the three sources, the reach of a candidate theorem (`reachUnknown`), and the
exemption classes read from main. -/
inductive Missing where
  | mathview | kills | tsLint | reach | exempt
deriving DecidableEq, Repr

/-- The wire name of a missing fact. -/
def Missing.name : Missing → String
  | .mathview => "mathview" | .kills => "kills" | .tsLint => "ts-lint" | .reach => "reach" | .exempt => "exempt-main"

/-- The missing facts, in a fixed order: each absent source, an unknown reach, and exemption classes not read at
the main commit `F.mainAt` (each bracket is the one-element list when its condition holds, else empty). -/
def missing (F : Facts) : List Missing :=
  (if F.present.mathview then [] else [.mathview]) ++ (if F.present.kills then [] else [.kills]) ++
  (if F.present.tsLint then [] else [.tsLint]) ++ (if reachUnknown F then [.reach] else []) ++
  (if F.exemptAt == some F.mainAt then [] else [.exempt])

/-! ## Stages (section 8) -/

/-- The rollout stages: shadow (0), new tasks (1), all new code (2), ratchet (3). -/
inductive Stage where
  | shadow | newTasks | allNew | ratchet
deriving DecidableEq, Repr

/-- The number of a stage. -/
def Stage.rank : Stage → Nat
  | .shadow => 0 | .newTasks => 1 | .allNew => 2 | .ratchet => 3

/-- The wire name of a stage. -/
def Stage.name : Stage → String
  | .shadow => "shadow" | .newTasks => "newTasks" | .allNew => "allNew" | .ratchet => "ratchet"

/-- **Which rules refuse** at a stage, for a task with (`lf`) or without the `leanFirst` flag. Shadow: none. New
tasks: the five rules, for `leanFirst` tasks only. All new code: kills, twins and premises for every task, props and
search for `leanFirst` tasks. Ratchet: as all new code, plus the ratchet for every task. -/
def enforced : Stage → Bool → Rule → Bool
  | .shadow, _, _ => false
  | .newTasks, lf, r => lf && r != .ratchet
  | .allNew, lf, r => match r with
    | .kills | .twins | .premises => true
    | .props | .search => lf
    | .ratchet => false
  | .ratchet, lf, r => match r with
    | .kills | .twins | .premises | .ratchet => true
    | .props | .search => lf

/-- Is any rule enforced? -/
def anyEnforced (s : Stage) (lf : Bool) : Bool := Rule.all.any (enforced s lf)

/-- **The deployed stage**: shadow until the lead lands a change to this constant (C0, C1 in
`docs/team/tools/lean-first.md`). -/
def stage : Stage := .shadow

/-! ## The verdict -/

/-- The verdict: pass, pending on missing sources, or refused with the enforced reasons. -/
inductive Verdict where
  | pass
  | pending (missing : List Missing)
  | refuse (reasons : List Reason)
deriving DecidableEq, Repr

/-- The signature of a gate: the stage and the facts in, the verdict out. -/
abbrev Gate := Stage → Facts → Verdict

/-- **The verdict for a reason function** `R`: pending when a source is missing and some rule is enforced; otherwise
the reasons whose rule is enforced, if any, refuse, else pass. -/
def judge (R : Facts → List Reason) (s : Stage) (F : Facts) : Verdict :=
  if !(missing F).isEmpty && anyEnforced s F.leanFirst then .pending (missing F)
  else match (R F).filter (fun r => enforced s F.leanFirst r.rule) with
    | [] => .pass
    | rs => .refuse rs

/-- **The gate**: `judge` over every reason. -/
def gate : Gate := judge reasons

/-! ## Output lines -/

/-- Replace each line break (`\n`, `\r`) by a space, so a fact cannot start a new stdout line. -/
def clean (s : String) : String := s.map fun c => if c = '\n' || c = '\r' then ' ' else c

/-- The kinds of output line, by prefix. -/
inductive Tag where
  | verdict | reason | shadow | warn
deriving DecidableEq, Repr

/-- The prefix of each kind of line. -/
def Tag.text : Tag → String
  | .verdict => "VERDICT " | .reason => "REASON " | .shadow => "LEANFIRST " | .warn => "WARN "

/-- One output line: the prefix, then the cleaned body. -/
def mkLine (t : Tag) (body : String) : String := t.text ++ clean body

/-- Is a line a verdict line? It starts with `VERDICT ` (with the space). -/
def isVerdict (l : String) : Bool := l.startsWith "VERDICT "

/-- The number of verdict lines. -/
def verdictCount (ls : List String) : Nat := (ls.filter isVerdict).length

/-- The text of a reason after `lean-first:`: rule, code, subject. -/
def Reason.text (r : Reason) : String := r.rule.name ++ " " ++ r.code ++ " " ++ r.subject

/-- The `LEANFIRST` lines: with every source present, one `would-refuse` line per reason whose rule is not enforced;
otherwise one `missing` line per missing source. -/
def shadowLines (s : Stage) (F : Facts) : List String :=
  if (missing F).isEmpty then
    ((reasons F).filter fun r => !enforced s F.leanFirst r.rule).map fun r =>
      mkLine .shadow ("shadow would-refuse " ++ r.text)
  else (missing F).map fun m => mkLine .shadow ("shadow missing " ++ m.name)

/-- The `WARN` lines: one per new theorem and untested premise it assumes (rule 4d). -/
def warnLines (F : Facts) : List String :=
  (F.thms.filter (isNew F)).flatMap fun t =>
    (t.assumes.filter fun p => statusOf F p == some .untested).map fun p =>
      mkLine .warn ("lean-first:premises untested " ++ t.name ++ " " ++ p)

/-- The kind of the check's result. -/
inductive Kind where
  | pass | pending | refused
deriving DecidableEq, Repr

/-- The wire name of a kind. -/
def Kind.name : Kind → String
  | .pass => "pass" | .pending => "pending" | .refused => "refused"

/-- What the check prints and returns: kind, exit code and stdout lines. -/
structure Out where
  kind : Kind
  exit : Nat
  lines : List String
deriving DecidableEq, Repr

/-- The signature of a renderer: the stage and the facts in, the output out. -/
abbrev Render := Stage → Facts → Out

/-- **The output of the check.** Pass: the `LEANFIRST` and `WARN` lines, then `VERDICT pass lean-first`, exit 0.
Pending: one `REASON` line per missing source, then `VERDICT pending lean-first:missing <names>`, exit 75. Refused: one
`REASON` line per enforced reason, the `LEANFIRST` and `WARN` lines, then `VERDICT refused lean-first:<rule> <subject>`
of the first reason, exit 1.
(`refuse []` never comes out of `gate`; it would print `VERDICT refused lean-first:` with exit 1.) -/
def out : Render := fun s F =>
  match gate s F with
  | .pass => ⟨.pass, 0, shadowLines s F ++ warnLines F ++ [mkLine .verdict "pass lean-first"]⟩
  | .pending ms => ⟨.pending, 75, ms.map (fun m => mkLine .reason ("lean-first:missing " ++ m.name)) ++
      [mkLine .verdict ("pending lean-first:missing " ++ ",".intercalate (ms.map Missing.name))]⟩
  | .refuse rs => ⟨.refused, 1, rs.map (fun r => mkLine .reason ("lean-first:" ++ r.text)) ++ shadowLines s F ++
      warnLines F ++ [mkLine .verdict ("refused lean-first:" ++
        match rs with
        | r :: _ => r.rule.name ++ " " ++ r.subject
        | [] => "")]⟩

/-- **The op**: the output at the deployed stage. -/
def run (F : Facts) : Out := out stage F

/-! ## Evidence (the order of `gate_mono`) -/

/-- Extra evidence: kill rows, signoff rows (added as agreeing), marks for the unmarked branches (positionally), and
sources that became present. -/
structure Evidence where
  kills : List KillRow
  signoffs : List Signoff
  marks : List Mark
  present : Present
deriving DecidableEq, Repr

/-- Give the `i`-th branch the `i`-th mark if it has none; marked branches and branches past the marks stay. -/
def fillMarks : List Branch → List Mark → List Branch
  | b :: bs, m :: ms => { b with mark := if b.mark = .none then m else b.mark } :: fillMarks bs ms
  | bs, [] => bs
  | [], _ :: _ => []

/-- **Add evidence** to the facts: append the kills, append the signoffs as agreeing rows, fill marks, or the sources;
everything else (theorems, properties, branches' places, registry, baseline, ancestry, counts, flags) is unchanged. -/
def Facts.add (F : Facts) (e : Evidence) : Facts :=
  { F with
    kills := F.kills ++ e.kills
    signoffs := F.signoffs ++ e.signoffs.map fun s => { s with agree := true }
    branches := fillMarks F.branches e.marks
    present := ⟨F.present.mathview || e.present.mathview, F.present.kills || e.present.kills,
      F.present.tsLint || e.present.tsLint⟩ }

/-! ## Examples of the decision functions (the fault grid is in `Fw.Ops.LeanFirstSearch`) -/

/-- Facts with nothing in them, all sources present and the exemptions read at main, of a lean-first task (for the
examples). -/
def emptyFacts : Facts :=
  { leanFirst := true, writes := [], props := [], thms := [], kills := [], signoffs := [], branches := [],
    registry := [], baseline := [], ancestry := [], legacyMain := 0, legacyHead := 0, present := ⟨true, true, true⟩,
    mainAt := "m", exemptAt := some "m" }

/-- The stub case: property `P` is proved only of `stub`, which the wire does not reach, while another theorem `L`
about a reached definition exists (for the examples). -/
def stubFacts : Facts :=
  { emptyFacts with
    props := [{ name := "P", stmtHash := "hP", assumes := [], searchAt := none, proofAt := none }],
    thms := [{ name := "P_stub", hash := "h1", kind := .general, proves := some "P", implArg := some "stub",
               reachFromWire := some false, axiomsOk := true, usedBy := [], reach := [], assumes := [] },
             { name := "L", hash := "h2", kind := .general, proves := none, implArg := some "impl",
               reachFromWire := some true, axiomsOk := true, usedBy := [], reach := [], assumes := [] }] }

-- the stage table
#guard Rule.all.all fun r => !enforced .shadow true r
#guard Rule.all.filter (enforced .newTasks true) == [.props, .kills, .twins, .premises, .search]
#guard Rule.all.filter (enforced .newTasks false) == []
#guard Rule.all.filter (enforced .allNew false) == [.kills, .twins, .premises]
#guard Rule.all.filter (enforced .ratchet false) == [.kills, .twins, .premises, .ratchet]
#guard Rule.all.filter (enforced .ratchet true) == Rule.all
#guard !anyEnforced .newTasks false && anyEnforced .allNew false
-- marks, missing facts, newline cleaning, verdict lines
#guard [Mark.none, .op, .twin, .glueOk, .glueBad].map Mark.ok == [false, true, true, true, false]
#guard missing { emptyFacts with present := ⟨false, true, false⟩ } == [.mathview, .tsLint]
#guard missing emptyFacts == []
#guard missing { emptyFacts with exemptAt := some "branch" } == [.exempt]
#guard missing { emptyFacts with exemptAt := none } == [.exempt]
#guard missing { stubFacts with thms := stubFacts.thms.map fun t => { t with reachFromWire := none } } == [.reach]
#guard clean "a\nb\rc" == "a b c" && clean "" == ""
#guard isVerdict (mkLine .verdict "pass lean-first") && !isVerdict (mkLine .reason "VERDICT pass")
#guard verdictCount ["VERDICT a", "REASON b", "VERDICT c"] == 2
#guard fillMarks [⟨"a", 1, .none⟩, ⟨"b", 2, .op⟩, ⟨"c", 3, .none⟩] [.twin, .glueBad] ==
  [⟨"a", 1, .twin⟩, ⟨"b", 2, .op⟩, ⟨"c", 3, .none⟩]
-- the gate and its output on empty facts: pass, pending without sources, nothing enforced at shadow
#guard gate .ratchet emptyFacts == .pass
#guard gate .ratchet { emptyFacts with present := ⟨true, false, true⟩ } == .pending [.kills]
#guard gate .ratchet { emptyFacts with exemptAt := some "branch" } == .pending [.exempt]
#guard gate .shadow { emptyFacts with present := ⟨false, false, false⟩ } == .pass
#guard gate .newTasks { emptyFacts with leanFirst := false, present := ⟨false, false, false⟩ } == .pass
#guard gate .ratchet { emptyFacts with legacyMain := 2, legacyHead := 3 } == .refuse [.growth 2 3]
#guard gate .allNew { emptyFacts with legacyMain := 2, legacyHead := 3 } == .pass
#guard gate .ratchet { emptyFacts with writes := ["apps/runner/src/land.ts"] } ==
  .refuse [.noProps "apps/runner/src/land.ts"]
#guard gate .ratchet { emptyFacts with writes := ["docs/x.md", "apps/runner/**"] } == .refuse [.noProps "apps/runner/**"]
#guard gate .ratchet { emptyFacts with writes := ["docs/x.md", "research/**"] } == .pass
-- the stub case: `P` proved of an unreached stub, another reached theorem does not help
#guard reasonsOf stubFacts .props ==
  [.unreached "P", .unsigned "P" .math, .unsigned "P" .adversary, .unkilled "P"]
#guard (reasonsOf { stubFacts with thms := stubFacts.thms.map fun t => { t with reachFromWire := some true } } .props).take 1 ==
  [.unsigned "P" .math]
#guard (reasonsOf { stubFacts with thms := stubFacts.thms.map fun t => { t with implArg := none } } .props).take 1 ==
  [.unproved "P"]
#guard (out .ratchet { emptyFacts with present := ⟨true, false, true⟩ }) ==
  ⟨.pending, 75, ["REASON lean-first:missing kills", "VERDICT pending lean-first:missing kills"]⟩
#guard (out .ratchet { emptyFacts with legacyMain := 2, legacyHead := 3 }) ==
  ⟨.refused, 1, ["REASON lean-first:ratchet growth 2->3", "VERDICT refused lean-first:ratchet 2->3"]⟩
#guard (out .shadow { emptyFacts with legacyMain := 2, legacyHead := 3 }) ==
  ⟨.pass, 0, ["LEANFIRST shadow would-refuse ratchet growth 2->3", "VERDICT pass lean-first"]⟩
#guard (run emptyFacts).exit == 0

end Fw.Ops.LeanFirst
