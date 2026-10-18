# lean-first-gate: enforce "Lean first" at land, not by prompt

Design only (base 707cd5e). Answers the user's question: no, agents do not all work this way today. CLAUDE.md asks
for it, but no step checks it. Three audits found 15 new TS decisions with no Lean, about 25 vacuous or definitional
theorems on main, 701 of 703 new theorems with no mutant, 7 refuted premises still accepted by citeLint, and 10
incidents that came from properties nobody stated. This note turns the rule into a land gate that decides in Lean,
plus a task workflow that puts properties before code.

## 0. Shape: one Lean verdict, TS only collects facts

- New module `Fw.Ops.LeanFirst`, exposed as the fwcore op `ops.leanFirst`.
  - Input: `Facts`, all structured and with no prose.
  - Output: `Out = {kind, exit, lines}`.
- `fw land --dry` and `fw land` run one new check, `lean-first`, with declared reads (see land-speed P5).
  - The check gathers facts, calls the op, writes `out.lines` to stdout verbatim and exits with `out.exit`.
  - The TS has no printing branch. The exactly-one-VERDICT property then holds of the real stdout, not of a Lean
    list that TS copies by hand (that copying is the trap of the vacuous `dry_prints_one_verdict`).
- Fact sources, all glue:
  1. MathView JSON, extended (section 6): theorems, props, kill witnesses, Assume hypotheses, reach, deep hashes.
     It already runs on every Lean land, cached in 1-3 s (land-speed P4).
  2. `kills.jsonl`, the CI artifact of the mutants job, keyed by each theorem's deep statement hash.
  3. `ts-lean-lint --json` over the changed TS/JS files.
  4. `docs/team/props/signoffs.jsonl`. Only the lead writes it; no task's `writes` glob contains it, so the land
     scope check refuses a branch that edits it.
  5. Git order facts: the commit that first adds a search guard or a theorem name.
  6. `Fw.Ops.Premise.registry`, compiled into fwcore.
  7. Task facts from work-graph.json: `leanFirst`, `props` module, `writes`, `claimedAt`.
- Each refusal names its rule: `VERDICT refused lean-first:<rule> <decl|file:line>`. That is one line per land, and
  the reasons go on `REASON` lines.

## 1. Property-first

### Convention (`Fw.Spec.Props`)

1. A task's never-happen properties live in `lean/Fw/Props/<TaskCamel>.lean`, one Prop-valued def each. Each def is
   stated over the signature of the implementation, not over the implementation itself:
   `def NoSilentExit (run : LandFacts → Out) : Prop := ∀ f, ((run f).lines.filter isVerdict).length = 1`.
   It can therefore be written before the code exists.
2. Each property ships with at least one bad implementation that it rejects, proved in the same file:
   `theorem NoSilentExit.rejects_emptyDone : ¬ NoSilentExit badEmptyDone`. The bad implementations are the incident
   classes: an empty branch gives `done`, an exception has no verdict, an empty set passes, a shift leaves local
   cells unchanged, a state has no exit edge. This makes the property non-vacuous before any proof exists.
3. Each property ships with a bounded search entry (rule 5).
4. Every property docstring carries `$$` math plus one English sentence, as for every theorem.

### Review

- **math-reviewer** checks that the math equals the Lean. This is the existing role.
- **adversary** is a new read-only role: `reviewer` with a fixed checklist. It answers in writing and proposes extra
  bad implementations:
  - What must never happen?
  - Under which transformations must the verdict stay the same? (page offset)
  - Does every state have an exit and a witness? (task-state-truth)
  - Who else starts this, or writes it? This is the closed-world question. (workflow-unbound, admit-reads)
  - Is a key injective over time? (pid marker)
  - Does an empty input pass?
  - Is every conjunct of the stated property in the theorem? (Exit.lean flags, scope and head)
- The lead appends one row per reviewer to `docs/team/props/signoffs.jsonl`:
  `{task, decl, stmtHash, docHash, role: "math" | "adversary", verdict}`.
- The lead then lands the Props module on main as a "spec land": no implementation, a `lake build` of one module.

### Land check (`props`)

For a task with `leanFirst ≥ 1`, each property `P` in its Props module must meet all of these:

- (a) At least one property exists if the task's `writes` touch decision code (`lean/Fw/**` except `Props`,
  `apps/*/src/**`, `packages/*/src/**`, `.github/workflows/**`).
- (b) The current stmtHash and docHash of `P` equal a signed row with `verdict=agree` for **both** roles. Weakening
  the property on the branch makes the hash stale, so the land refuses. This catches the Exit.lean case, where the
  theorem dropped conjuncts.
- (c) There is a theorem `t` whose type is syntactically `P impl`, with standard axioms only.
- (d) `impl` is reachable from the fwcore dispatcher `Fw.Wire.handle` or from a golden generator in
  `lean/scripts/*Golden.lean`. This catches "rule proved but never called", the admit `wconf` case, at the Lean
  boundary.
- (e) `P` has a kill witness (`rejects_*`).

- **Runs in:** `fw land --dry` and `fw land`. A pre-commit hook (optional, advisory) only checks that the Props file
  exists.
- **Cost:** < 1 s on top of MathView. Basis: the op is a fold over at most a few hundred decls (the MEASURED fwcore
  ops in the land path return in tens of ms), and MathView is already paid (10.2 s, or 1-3 s cached; MEASURED in
  10-18-land-speed.md).

## 2. Non-vacuity: every new theorem has a killing mutant

There are two tiers, and either one satisfies the rule.

- **Tier K (in-kernel, preferred).** The theorem has the shape `P impl`, where `P` is a predicate over the
  implementation (section 1). A kill is a theorem `t.kill_<m> : ¬ P m`, with the mutant `m` written in
  `lean/FwTest/Mutants/<Module>/<m>.lean`. Its docstring names the mutation, for example "drops the empty-branch
  case". MathView checks:
  - the head constant of the kill's type (under `¬`) equals the head constant of `t`'s type;
  - `m` is a different constant with the same type as `impl`.
  - Cost: zero at land, because it elaborates in `lake build`.
  - Bonus: `¬ P m` forces the hypotheses of `P` to be satisfiable, which kills the vacuous-hypothesis class.
- **Tier T (textual).** Use this for theorems not in `P impl` shape. `mutants.sh` gets a first-kill mode,
  `-T <theorem>`:
  - It lists the gen.mjs mutants of the defs the theorem reaches (MathView reach), deepest def first.
  - It runs them until one is `killed:proof` **naming this theorem**. `gen.mjs classify` is extended to report the
    failing declaration.
  - It writes `{thm, deepHash, mutantId, verdict}` to `kills.jsonl`. The deep-hash key means a rebase that does not
    change any reached def reuses the result.
  - It runs in `mutants.yml` on the `ci/*` push. Its paths widen from the 9 M0 modules to `lean/Fw/**`, but it only
    searches theorems that are new or changed against main.
- **Exempt.** A theorem need not have a kill if it is either:
  - (i) a **lemma**: referenced by a theorem that has a kill (MathView reach, mechanical); or
  - (ii) a **data lint**: a closed statement with no binders, proved by `decide` or `rfl`, listed by name in
    `FwTest/Mutants/exempt.tsv` with class `data`.
  Neither kind can discharge a property obligation (1c), so the 21 bare `rfl`/`decide` proofs and the defining
  equations stop counting as behaviour proofs.
- **Mutant templates.** The adversary checklist doubles as templates:
  - a verdict over a set: an empty input must not pass, so the mutant returns pass on `[]`;
  - an output total over states: drop a case;
  - an identity key: make it non-injective;
  - a list of conjuncts: drop one.

- **Runs in:** CI `mutants.yml` (tier T). `fw land` reads `kills.jsonl` for the head's deep hashes through one
  `fw ci` artifact call (gh hygiene: one list call, no retry on 403). A missing artifact refuses with `kind=pending`
  and exit 75, never a pass.
- **Cost:**
  - Tier K: about 0 s at land, plus a few seconds of elaboration per mutant file.
  - Tier T on CI: about 11.4 s CPU per mutant. Basis: MEASURED 6969 s summed over 613 mutants in the M0 r1 run.
    About 2-3 mutants are tried per theorem until the first kill. Basis: INFERRED from 539 of 613 killed in r1.
    A 20-theorem task therefore costs about 8-12 min CPU, about 3 min wall on 4 shards. That is off the land lock
    and parallel to the other `ci/*` lanes.
  - Land: about 1 s to fetch and read the artifact.

## 3. No TS decision without Lean (ts-lean-lint, in packages/difftest)

- **Fact extraction (glue).** A TS-compiler AST pass over the **changed hunks** of `apps/*/src/**`,
  `packages/*/src/**`, `apps/runner/hooks/**` and `.github/scripts/**`. It skips `test/`, `*.gen.*` and goldens.
- **What counts as a data branch.** A condition, in any of these forms, that reads a non-literal value:
  - `if`, `?:`, `switch case`, `&&`/`||`/`??` in value position;
  - `.filter`, `.find`, `.some`, `.every` with a predicate;
  - regex `.test` or `.match`;
  - `catch` blocks that return a value.
  It also extracts every comment citation `Lean X` or `Fw.X`.
- **Decision (Lean op `lint.tsBranch`, golden `ops/ts-branch.jsonl`).** Each new branch must sit in a function that
  carries one of these markers:
  - `// lean: <op>`: the op exists in the fwcore op list and the function calls fwcore. Or a twin that is in the
    difftest Covered table, because two classifiers of one concept need a difftest (wait-guard, next.ts).
  - `// twin: <golden path>`: the golden exists **and** a test file under the same package reads that path. Static
    check: the path string appears in a `test/**` file.
  - `// glue: io | parse | render`: a closed enum. `io` is accepted only if every identifier in the condition comes
    from an fs, child_process or fetch result, or from an error code. `parse` is accepted only for format checks
    whose failure throws. `render` is accepted only in `apps/console-web` and `apps/site/src/**/view*`. Any other
    use is refused.
- **Also refused:**
  - a citation `Lean X` that does not resolve to a MathView decl (settle-adapter's `Fw.Gate.Settle`);
  - a regex over check or log prose that yields a verdict kind (land.ts:335 `READS_FAIL_RE`). This is caught by
    the `glue:` rule: prose is neither io nor parse.
  - a CLI top-level `catch` that exits without fwcore's `Out`. Exceptions become the fact `exn` (rule 1 property
    `NoSilentExit`).
- **YAML.** A new `if:` on a step or job, or a `continue-on-error`, in `.github/workflows/*.yml` is a data branch.
  It needs `# lean: <op>` (as `ci-paths` does) or `# glue: io`. engine-premises.yml:242 would be refused.
- **Runs in:** pre-commit (advisory, fast), `fw land --dry` and `fw land` (authoritative).
- **Cost:** about 1-2 s. Basis: INFERRED. That is node start plus loading the `typescript` parser (about 0.5 s) and
  parsing only the changed files (ms each), plus one fwcore call.
- **Policy item for the lead.** The rotating difftest job (difftest.yml:138) stays `continue-on-error`. Proposal: a
  mismatch it finds opens an incident and becomes a fixed-seed golden, which then blocks lands that touch that op.

## 4. Premises are explicit

- **Marker.** `Fw.Spec.Props.Assume (p : PremiseId) (claim : Prop) : Prop := claim`. A theorem that rests on a
  premise takes it as a hypothesis, for example `(h : Assume .wkProps (∀ c, webkitAt c = …))`. MathView reports the
  ids.
- **Registry (`Fw.Ops.Premise`).** It is extended with:
  - `kind ∈ {engine, shell, ci, fs, platform, dom}`;
  - `status ∈ {measured runId, untested, refuted runId, unmeasurable}`;
  - `carriers : List Name`: defs that encode a premise inside them, for example `webkitAt`, `chromiumAt`,
    `toggleChanges` and `finiteProducer`.
  New entries come from the audits: the declared-reads premise, determinism of checks, hash injectivity,
  finite-producer ⇒ finite stdin, and `classList.toggle` same state ⇒ no mutation.
- **Check (`premises`).** For each new or changed theorem `t`:
  - (a) every `Assume` id is in the registry;
  - (b) if `t`'s reach meets a carrier of premise `p`, then `t` has `Assume p`. A hidden premise refuses the land.
  - (c) `status = refuted` refuses the land;
  - (d) `untested` passes with a `WARN` line, and the theorem cannot discharge a property unless the property itself
    carries the same `Assume`.
- **citeLint.** It gains `citeLint_refuted_bad`: a row that cites a refuted id is in `bad`. It also gets a mutant
  that drops that check.
- **Existing theorems.** About 25 theorems on refuted cells and about 15 unregistered hypotheses go in a burn-down
  list (stage 3) rather than blocking unrelated lands.
- **Runs in:** `fw land --dry` and `fw land`. CI `engine-premises` keeps writing `status`.
- **Cost:** < 1 s (registry plus MathView facts).

## 5. Edge-case search before proof

- **`Fw.Search`** (core Lean, no Mathlib):
  - a class `Enum α` with `enum : Nat → List α`, all values up to size n;
  - `search (xs) (q : α → Bool) : Option α`.
- **Per property.** The Props module adds:
  - a decidable pointwise form `Q`;
  - `theorem P_iff : P impl ↔ ∀ x, Q impl x = true`, so the search is about the stated property and not about a
    different one;
  - the guards `#guard (search (enum n) (Q impl)).isNone` and `#guard (search (enum n) (Q m)).isSome` for every
    kill mutant `m`. The second guard shows the search can see the bug at all.
- **Inputs.** Facts types get `Enum` instances: branch shapes (empty, merge-only, conflicting, ahead, done), board
  event traces of length ≤ k, pid spaces of size 2-3, and shell token sequences from a small grammar. The shell
  grammar is what would have found `while read … < f` and `bash -c '… &'`.
- **Real-data corpus.** For classifiers of external text (shell, transcripts, ps trees), a corpus golden built from
  real logs is mandatory. A difftest between the two classifiers runs over it (Lean `units` against `next.ts`).
- **Ordering check (`search`).** The commit that adds the search guards for `P` must be a strict ancestor of the
  commit that first adds the proof of `P impl`. The glue fact comes from `git log --diff-filter=A -S<name>`, and
  Lean decides.
- **Bound.** Each search must evaluate ≥ 10^3 points or exhaust a finite type. Each guard must take ≤ 5 s
  elaboration, so lake build time stays bounded.
- **Plausible** (leanprover-community/plausible) is optional. It is a Lake dependency, not a brew formula, so the
  lead decides (CLAUDE.md "ask the lead first"). Whether it runs without Mathlib is INFERRED; verify at the pinned
  sha.
- **Runs in:** `lake build` (guards), and `fw land --dry` / `fw land` (presence and ordering).
- **Cost:** ≤ 5 s elaboration per property, paid in the build. Land check < 1 s.

## 6. MathView extension

For each declaration, add these fields:

- `headConst` and `implArg` (for `P impl`);
- `assumes` (ids);
- `killOf` (target theorem);
- `class`, one of `closed`, `rfl`, `defEq`, `general`;
- `reachFromWire` (true, false or null);
- `reach` (Fw defs).

All of them come from the Expr that MathView already walks for the deep hash.

As built (`lean/Fw/Spec/MathFacts.lean`, task `lfg-mathview-facts`):

- **Wire reach.** $W = \operatorname{closure}([\texttt{Fw.Wire.handle}] \mathbin{+\!\!+} \operatorname{fwIdents}(\texttt{lean/scripts/*Golden.lean}))$, as in check (d). No module is a root by its name. `Fw.Wire.Sched.taskAdmitted` (inc-proof-of-dead-code) is not in $W$ (`#guard`).
- **Subjects.** These are the theorem's operations: the definitions in the implementation argument (or in the statement when there is none) whose type does not end in a sort, so types, aliases and predicates do not count. When no such operation exists, the subjects are the operations named in the constructor types of the statement's inductive predicates.
- **Three values.** `reachFromWire` is null when a theorem has no subjects. Null and false both ask a human to look. True claims the subject is wired, so it must never be emitted for dead code.
- **Stated limit: the `defEq` class depends on the environment.** It sits on a heartbeat budget, and `isDefEq` spends a different number of heartbeats in different environments. The canonical environment is the export's (`lake exe mathview`, `importModules` with `loadExts := false`). Near the budget edge, `facts%` in an elaborated file can disagree (MEASURED once: `MorphMountOpt.cr_swipe_mixed`). The guard `defEqAt% … 1` pins that this case depends on the budget.

## 7. Lean statements the gate itself must satisfy (Fw.Ops.LeanFirst)

With `F` = facts, `g F` = the verdict, and `new F` = theorems not in the baseline `B` of the cutover commit:

$$\mathrm{pass}(F) \iff \mathrm{Props}(F) \land \mathrm{Kills}(F) \land \mathrm{Twins}(F) \land \mathrm{Prem}(F) \land \mathrm{Search}(F)$$ (`pass_iff`)

The parts:

- $\mathrm{Props}(F) := (\mathrm{dec}(F) \Rightarrow |\mathrm{props}(F)| \ge 1) \land \forall P \in \mathrm{props}(F),\ \exists t,\ \mathrm{type}(t) = P(\mathrm{impl}) \land \mathrm{reach}(\mathrm{impl}) \land \mathrm{signed}_{\mathrm{math}}(P) \land \mathrm{signed}_{\mathrm{adv}}(P)$
- $\mathrm{Kills}(F) := \forall t \in \mathrm{new}(F),\ (\exists k \in \mathrm{kills}(F),\ k.\mathrm{target} = t \land k.\mathrm{hash} = \mathrm{hash}(t)) \lor \mathrm{exempt}(t)$
- $\mathrm{Twins}(F) := \forall b \in \mathrm{branches}(F),\ \mathrm{marked}(b) \in \{\mathrm{op}, \mathrm{twin}, \mathrm{glue}_{ok}\}$
- $\mathrm{Prem}(F) := \forall t \in \mathrm{new}(F),\ \mathrm{carriers}(t) \subseteq \mathrm{assumes}(t) \subseteq \mathrm{registry} \land \forall p \in \mathrm{assumes}(t),\ \neg\mathrm{refuted}(p)$
- $\mathrm{Search}(F) := \forall P \in \mathrm{props}(F),\ \mathrm{searchAt}(P) \prec \mathrm{proofAt}(P)$

Theorems:

1. `land_refuses_unproved`
   $$\forall F\, P,\ P \in \mathrm{props}(F) \land \neg\exists t,\ \mathrm{type}(t) = P(\mathrm{impl}) \Rightarrow g(F) = \mathrm{refuse}(\mathrm{unproved}\ P)$$
2. `stale_review_refuses`
   $$\forall F\, P\, r \in \{\mathrm{math}, \mathrm{adv}\},\ \mathrm{hash}(P) \notin \mathrm{signed}_r(F) \Rightarrow g(F) \ne \mathrm{pass}$$
3. `no_props_refuses`
   $$\mathrm{dec}(F) \land \mathrm{props}(F) = [\,] \Rightarrow g(F) \ne \mathrm{pass}$$
   This is the non-vacuity of the gate itself.
4. `mutant_kills_or_refuse`
   $$\forall t \in \mathrm{new}(F),\ (\neg\exists k,\ \mathrm{kills}(k, t)) \land \neg\mathrm{exempt}(t) \Rightarrow g(F) = \mathrm{refuse}(\mathrm{noKill}\ t)$$
5. `exempt_not_discharge`
   $$\mathrm{exempt}(t) \Rightarrow \forall P,\ \neg\mathrm{discharges}(t, P)$$
6. `hidden_premise_refuses`
   $$\mathrm{carriers}(t) \not\subseteq \mathrm{assumes}(t) \Rightarrow g(F) \ne \mathrm{pass}$$
7. `refuted_premise_refuses`
   $$\exists p \in \mathrm{assumes}(t),\ \mathrm{refuted}(p) \Rightarrow g(F) \ne \mathrm{pass}$$
8. `untwinned_branch_refuses`
   $$\exists b \in \mathrm{branches}(F),\ \mathrm{marked}(b) = \bot \Rightarrow g(F) \ne \mathrm{pass}$$
9. `proof_before_search_refuses`
   $$\neg(\mathrm{searchAt}(P) \prec \mathrm{proofAt}(P)) \Rightarrow g(F) \ne \mathrm{pass}$$
10. `missing_fact_not_pass`
    $$\mathrm{kills}(F) = \bot \lor \mathrm{mathview}(F) = \bot \Rightarrow g(F) = \mathrm{pending} \land \mathrm{exit} = 75$$
    Missing facts fail closed and never become a vacuous pass. This contrasts with the wait-guard's fail-open.
11. `one_verdict` (about the real output)
    $$\forall F,\ |\{\ell \in \mathrm{out}(F).\mathrm{lines} : \mathrm{isVerdict}(\ell)\}| = 1$$
    plus `exit_zero_iff`
    $$\mathrm{out}(F).\mathrm{exit} = 0 \iff g(F) = \mathrm{pass}$$
    These are non-vacuous because the TS prints `out` verbatim, which the rule-3 lint checks on `land.ts`, and
    golden rows cover each kind.
12. `gate_mono`
    $$F \le F' \Rightarrow (g(F) = \mathrm{pass} \Rightarrow g(F') = \mathrm{pass})$$
    Here $F \le F'$ means: only extra kills, signoffs or markers, and no new theorems or branches. Adding evidence
    never turns a pass into a refusal.
13. `stage_mono`
    $$s \le s' \Rightarrow (g_{s'}(F) = \mathrm{pass} \Rightarrow g_s(F) = \mathrm{pass})$$
    A stricter stage refuses a superset.
14. `baseline_not_new`
    $$\forall t \in B,\ \mathrm{hash}(t) = \mathrm{hash}_B(t) \Rightarrow t \notin \mathrm{new}(F)$$
    and `changed_is_new`
    $$\mathrm{hash}(t) \ne \mathrm{hash}_B(t) \Rightarrow t \in \mathrm{new}(F)$$
    So an edit to an old theorem is gated.
15. `ratchet_refuses_growth`
    $$|\mathrm{legacy}(\mathrm{main}')| > |\mathrm{legacy}(\mathrm{main})| \Rightarrow g(F) \ne \mathrm{pass}$$
    Here legacy is the set of grandfathered gaps: theorems with no kill, refuted cites, unmarked branches.

**The gate obeys its own rules.**

- Every theorem above has a tier-K kill in `FwTest/Mutants/LeanFirst/`. Examples:
  - `gNoProps` passes with an empty props list, which kills (3);
  - `gPendingPass` maps missing facts to pass, which kills (10);
  - `gTwoVerdicts` prints an extra line, which kills (11).
- It has a golden `packages/contracts/golden/ops/lean-first.jsonl` with one row per refusal kind.
- It has `Enum Facts` search guards.

## 8. Rollout (the 7 running workflows are never blocked mid-flight)

| stage | what enforces | who is affected | exit |
|---|---|---|---|
| 0 shadow | gate runs in `--dry` and `land`, prints `LEANFIRST shadow would-refuse <rule>` and a `REASON` line, never changes VERDICT or exit | everyone, no effect | ≥ 15 lands seen; would-refuse counts per rule in a research note; false refusals fixed |
| 1 new tasks | all 5 rules refuse for tasks with `leanFirst: 1` in work-graph (the lead sets it on every task defined after cutover `C0`) | only new tasks; tasks claimed before C0 (the 7 running workflows included) stay shadow | 5 leanFirst tasks landed |
| 2 all new code | rules 2, 3 and 4 refuse for **every** land, for new or changed theorems and branches only (baseline B = main at C1); rules 1 and 5 stay leanFirst-only | everyone, on the diff only | no shadow-only refusals for a week |
| 3 ratchet | `ratchet_refuses_growth`, plus burn-down tasks per module (the 701 theorems with no kill, about 25 refuted-premise theorems after engine-model-fix, the 9 lean-ops-gap items, the 15 new TS items) | legacy count shrinks only | legacy = 0, then the ratchet is removed |

- C0 and C1 are commits on main, recorded in `docs/team/tools/lean-first.md`.
- The stage is a constant in `Fw.Ops.LeanFirst`, so changing it is a Lean land, reviewed.
- Land order matters, because the gate's own land.ts edit must not collide with `land-dry-full`, which also writes
  `land.ts`, and the premise registry edit must wait for `engine-model-fix`, which writes `Premise.lean`.

## 9. Cost per land (Lean-touching land, today ~13-20 s target, ~126-153 s p50 before land-speed fixes)

| part | where | added per land | basis |
|---|---|---|---|
| props + premises + search order + verdict | land check | < 1 s | fwcore op over MathView JSON already produced (MEASURED mathview 10.2 s / cached 1-3 s) |
| kills.jsonl fetch | land check | ~1 s | one `fw ci` artifact call (INFERRED) |
| ts-lean-lint | land check | ~1-2 s | TS parser on changed files only (INFERRED) |
| tier-K kills + search guards | lake build | ≤ 5 s per property | guard bound (design cap) |
| tier-T kills | CI ci/* push, off lock | ~3 min wall / ~10 min CPU per 20 theorems | 11.4 s CPU per mutant (MEASURED 6969 s / 613), ~2-3 tries (INFERRED from 88 % r1 kill rate) |
| spec land + 2 reviews | before code, per task | 1 lead land (~15 s) + 2 reviewer runs | land-speed target |

Total on the land path: about 3-5 s, plus CI minutes that run in parallel with the existing gates.

## 10. What each audit finding maps to

- Land-dry: no VERDICT / done on an empty branch / exit 1 → rule 1 `NoSilentExit` property, rule 3 catch → `exn`
  fact, gate (11).
- engine-premises.yml vacuous green, gh-budget wait → rule 3 YAML `if:` and the empty-set mutant template.
- wait-guard holes, next.ts twin → rule 5 shell grammar plus a corpus difftest; rule 3 "two classifiers → difftest".
- settle-adapter citing a missing module → rule 3 citation resolution.
- `READS_FAIL_RE` prose regex → rule 3 `glue:` refusal.
- drain.ts unbounded retry → a property with a template "retry bounded".
- Refuted premises hidden in `webkitAt` → rule 4 carriers plus refuted refusal.
- toggle_noop premise inside a def → rule 4 carrier `toggleChanges`, kind dom.
- Exit.lean dropped conjuncts → rule 1(b) hash-signed property.
- Admit `wconf` never called → rule 1(d) reach.
- Page offset, task end state, pid marker, part scope → the adversary checklist plus rule 5 search.
- 701 theorems with no mutant, rfl/decide counted as proofs → rule 2 plus exemptions that cannot discharge
  properties.

## 11. Work-graph task lines (id | title | deps | owner)

- lfg-props-shape | (S) Fw.Spec.Props: property-over-impl convention, Assume marker, Fw.Search (Enum, search, P_iff link), kill naming; doc docs/team/tools/lean-first.md | – | lean-prover
- lfg-spec | (M) Fw.Ops.LeanFirst: Facts, verdict, Out, the 15 theorems of section 7 with their own tier-K kills, golden ops/lean-first.jsonl, fwcore op ops.leanFirst, Enum Facts search | lfg-props-shape | lean-prover
- lfg-mathview-facts | (S) MathView emits headConst, implArg, assumes, killOf, class, reach, reachFromWire; differential job keeps the output hash | lfg-props-shape | lean-prover
- lfg-premise-registry | (S) Premise kinds and status (measured, untested, refuted, unmeasurable) plus carriers; citeLint_refuted_bad and its mutant; register the shell, ci, fs and dom premises from the audits | lfg-props-shape, engine-model-fix | lean-prover
- lfg-kill-ci | (M) mutants.sh -T first-kill mode, gen.mjs classify names the failing theorem, kills.jsonl keyed by deep hash, mutants.yml paths lean/Fw/** on new or changed theorems only, exempt.tsv | lfg-mathview-facts | lean-prover
- lfg-ts-lint | (M) packages/difftest ts-lean-lint: AST data-branch and citation extraction on changed hunks plus YAML if/continue-on-error; Lean op lint.tsBranch with golden ops/ts-branch.jsonl; pre-commit advisory entry | lfg-spec | console-builder
- lfg-workflow | (S) task lifecycle: work-graph fields leanFirst and props; .claude/agents/adversary.md checklist (lead edits agent config); docs/team/props/signoffs.jsonl owned by the lead only; spec-land step in docs/team/tools/land.md | lfg-props-shape | lead + plan-editor
- lfg-land-wire | (S) land.ts lean-first check: gather facts, call ops.leanFirst, print out verbatim, exit 75 on pending, stage constant read from Lean, shadow by default | lfg-spec, lfg-mathview-facts, lfg-kill-ci, lfg-ts-lint, lfg-premise-registry, land-dry-full | console-builder
- lfg-pilot | (S) first property-first task: land-dry-full totality (NoSilentExit with bad implementations emptyDone and exnNoVerdict) through the full workflow, to measure the review and spec-land cost | lfg-workflow, lfg-spec | lean-prover
- lfg-shadow | (S) stage 0: run ≥ 15 lands in shadow, tally would-refuse counts per rule in research/notes, fix false refusals | lfg-land-wire | lean-prover
- lfg-enforce-new | (S) stage 1: set C0, enforce for leanFirst tasks | lfg-shadow, lfg-pilot | lead
- lfg-enforce-all | (S) stage 2: set C1, rules 2, 3 and 4 on every diff; ratchet theorem live | lfg-enforce-new | lead
- lfg-burn-mutants | (L, split per module) stage 3: give the 701 legacy theorems kills or exemptions, module by module (Parts/*, Engine/*, Console/Land*, Ops/Wait first) | lfg-enforce-all | lean-prover
- lfg-burn-ts | (M) stage 3: the 15 new TS items plus the 9 lean-ops-gap items get a Lean op or twin (land.ts kinds, drain.ts retry, settle-adapter, scene clock goldens, snapshot-extract, shaLike, engine-premises verdict) | lfg-enforce-all, lean-ops-gap | lean-prover + console-builder
- lfg-plausible-eval (optional) | (S) evaluate Plausible at a pinned sha without Mathlib against Fw.Search; lead decides on the dependency | lfg-props-shape | lean-prover
