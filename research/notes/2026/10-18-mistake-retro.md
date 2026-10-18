---
id: note-2026-10-18-mistake-retro
kind: note
title: "Mistake retro: every mistake of the loop run, why it happened, and which Lean proof hardens it"
status: draft
created: 2026-10-18
topics: [process, lean, mistakes, retro, gate, hardening]
---

# Mistake retro

Question (relayed from the user): for every mistake in this experiment loop run, why did it happen, can Lean prove
it, and can a Lean proof prevent the next one?

**Answer.** The ledger lists 174 deduplicated mistakes in 15 root-cause classes. For 99 of them, a pure Lean
decision would have refused the mistake (**provable**). For 48, Lean covers the decision but the fact it decides on
comes from I/O (**partly**). The other 27 are platform, engine or human behaviour (**no**); each of these has an
empirical check instead. Two failures were never really model failures:

- **The gate summary exits 0 when parts fail.** This is still open at 84b9f19.
- **No coverage map links a gate probe to a Lean value.** So the Lean proofs never said anything about the CSS
  values that failed in the ports.

This note proposes 12 new tasks.

Data: `research/mistakes/ledger.json` (schema `fw.mistakes/1`). Each mistake carries an `evidenceStatus`:
- CONFIRMED means a commit, file:line or transcript line was checked in this task.
- INFERRED means it was taken from the harvested lists without a fresh spot-check.

Transcript references:
- `T:<line>` is a line in the lead session transcript.
- `subagent <name> line N` is a line in that agent's transcript.
- Neither is committed (local only), so these references cannot be checked from a public clone.

The method is in the last section.

## Summary per class

Verdict columns count mistakes: P = provable, ~ = partly, N = no.

| class | n | P | ~ | N | hardening module | task |
|---|---:|---:|---:|---:|---|---|
| c-handcopy: value hand-copied, no gen/golden link | 9 | 5 | 4 | 0 | Fw.Gate.Coverage | lean-coverage, fix-proofs (open) |
| c-mathdoc: docstring math not linked to the term | 8 | 4 | 4 | 0 | MathView.BinderLint | NEW mathdoc-binders |
| c-unearned-claim: status/number not earned | 15 | 4 | 7 | 4 | Fw.Plan.Claims | NEW claim-lint |
| c-principle: plan not checked against principles | 7 | 3 | 4 | 0 | Fw.Plan.Principles | NEW plan-principles-lint |
| c-proxy-verdict: success signal does not entail verdict | 8 | 6 | 2 | 0 | Fw.Gate.Exit | NEW gate-exit-verdict |
| c-sample-validity: measurement precondition implicit | 17 | 5 | 6 | 6 | Fw.Gate.Settle + Fw.Measure.Valid | gate-settle (open), NEW measure-valid |
| c-shared-no-lock: shared resource, no owner/lock | 12 | 8 | 3 | 1 | Fw.Sched.Admit read sets | land-hardening (done), NEW admit-reads |
| c-late-check: static check absent or after commit | 13 | 12 | 1 | 0 | Fw.Ops.CheckMap | NEW check-map-lean |
| c-orphan-wait: wait/child with no bound or owner | 10 | 5 | 3 | 2 | Fw.Ops.Wait | obs-signals (open), NEW wait-guard |
| c-quota: shared capacity, no budget | 12 | 9 | 3 | 0 | Fw.Ci.Runners, Fw.Obs.Resume | ghb-lean (done), NEW ci-runner-lint, NEW resume-rule |
| c-identity-heuristic: authority from text/name | 16 | 10 | 6 | 0 | Fw.Ops.Identity (ids only) | cap-diagnose (open), NEW policy-from-lean |
| c-order-derived: state from order/convention | 17 | 15 | 1 | 1 | Plan.Core / Obs.Signals commutation | mostly done; obs-signals (open) |
| c-env-assume: unverified tool/platform belief | 18 | 5 | 1 | 12 | Fw.Ops.Cli (own CLIs only) | check-map-lean (argv golden); rest empirical |
| c-spec-gap: task spec not checked vs deliverable | 5 | 2 | 2 | 1 | Fw.Plan.TaskSpec | NEW task-spec-lint |
| c-policy-prose: safety rule only in prose | 7 | 6 | 1 | 0 | Fw.Ops.Policy | NEW policy-from-lean |
| **total** | **174** | **99** | **48** | **27** | | **12 new** |

Reading the verdicts (INFERRED, from the per-mistake reasons):
- The "no" verdicts cluster in c-env-assume (12) and c-sample-validity (6). These are shell dialect, library
  contents, engine timing and platform delivery; Lean can only state the rule we follow after an empirical probe.
- The classes with the most mistakes that were proved and still went wrong are c-order-derived and c-late-check. In
  both, the theorem existed or was trivial, but it ran too late (at sync or at land) or ran on hand-written state.

## Hardening statements (one per class)

- **c-handcopy** (Fw.Gate.Coverage): every probed value is generated or golden-checked, or carries a named
  exemption.
  $$\forall (p,\pi)\in\mathrm{Probes}(S),\ \mathrm{src}(p,\pi)\in\{\mathrm{gen},\mathrm{golden}\}\lor\big((p,\pi)\in E\land\mathrm{why}(p,\pi)\neq\varepsilon\big)$$
- **c-mathdoc**: the binders of the math equal the binders of the term, up to globals $G$.
  $$\mathrm{fv}(\mathrm{tex}(d))\subseteq\mathrm{binders}(d)\cup G\ \land\ \mathrm{binders}(d)\subseteq\mathrm{fv}(\mathrm{tex}(d))$$
- **c-unearned-claim**:
  - CONFIRMED requires a src@sha or doc reference.
  - MEASURED requires a run id.
  - A bound requires a theorem $\theta$ that the claim cites.
- **c-proxy-verdict**: the exit code is the verdict, under the task's flags, scope and head.
  $$\mathrm{exit}(s)=0\iff\mathrm{rollup}(s)=\mathrm{pass}\land\mathrm{flags}(s)=\mathrm{flags}(t)\land\mathrm{scope}(s)\supseteq\mathrm{scope}(t)\land\mathrm{head}(s)=\mathrm{head}(t)$$
- **c-sample-validity**: if a verdict exists, every sample is settled and has the same key, clock and unit.
  $$\mathrm{verdict}(S)\neq\bot\Rightarrow\forall s\in S,\ \mathrm{settled}(s)\land\mathrm{key}(s)=\mathrm{key}(s_0)\land\mathrm{clock}(s)=\mathrm{clock}(s_0)\land\mathrm{unit}(s)=\mathrm{unit}(\mathrm{tol}(s))$$
- **c-shared-no-lock**: what one running task writes, no other running task reads or writes.
  $$\forall t\neq u\in\mathrm{Run},\ W_t\cap(W_u\cup R_u)=\emptyset$$
- **c-late-check**: every tracked file has a check, and pre-commit runs the checks of every changed file.
  $$\forall f\in\mathrm{Tracked},\ \mathrm{checks}(f)\neq\emptyset\ \land\ \mathrm{precommit}(\Delta)\supseteq\textstyle\bigcup_{f\in\Delta}\mathrm{checks}(f)$$
- **c-orphan-wait**: every wait ends by its deadline and has a live owner.
  $$\forall w,\ \mathrm{end}(w)\le\mathrm{start}(w)+\mathrm{deadline}(w)\land\mathrm{owner}(w)\in\mathrm{Live}$$
- **c-quota**: jobs use free runner labels only, and macOS jobs never exceed 5.
  $$\forall j,\ \mathrm{label}(j)\in F_{\mathrm{free}}\ \land\ \textstyle\sum_w|\{j\in w:\mathrm{os}(j)=\mathrm{mac}\}|\le5$$
  - Resume an agent iff idle < TTL or context < 30k; never resume one over 250k.
- **c-identity-heuristic**: the decision depends on ids only.
  $$\mathrm{ids}(r_1)=\mathrm{ids}(r_2)\Rightarrow\mathrm{decide}(r_1)=\mathrm{decide}(r_2)$$
- **c-order-derived**: the same facts in a different order give the same state.
  $$E\sim_{\mathrm{perm}}E'\Rightarrow\mathrm{board}(E)=\mathrm{board}(E')\land\mathrm{health}(E)=\mathrm{health}(E')$$
- **c-spec-gap**: deliverables and the handoff are in the write set, and the prompt names only the role's tools.
  $$\mathrm{deliv}(t)\cup\{\mathrm{handoff}(t)\}\subseteq W_t\land\mathrm{tools}(\mathrm{prompt}(t))\subseteq\mathrm{tools}(\mathrm{role}(t))$$
- **c-policy-prose**: every forbidden command is denied, and killing a process is allowed only if this agent owns it.
  $$\forall c,\ \mathrm{forbidden}(c)\Rightarrow\mathrm{hook}(c)=\mathrm{deny};\quad\mathrm{kill}(p)\ \text{allowed}\iff\mathrm{owner}(p)=\mathrm{self}$$

## Why the Lean did not catch the port and gate failures (adversarial)

The integrated ports failed 64 Chromium cells and 88 WebKit cells, even though every part had Lean proofs
(CONFIRMED, subagent integrate-ports line 1901). Per failure:

| failure | why Lean was silent | status |
|---|---|---|
| nav border colour, font-family | Nav.lean models motion and hit test only. Its single colour-like mention is a cubic-bezier timing at line 461 (origin/ci/integrate-ports). Static CSS had no model. | CONFIRMED |
| commission heights, display, runway | Commission.lean models bands and runway, not section heights or static display/margins. | CONFIRMED |
| pain.notes stage x | The model premise was transcribed wrong: it binds the wrong container (PainNotes.lean:13). Lean proved properties of the wrong binding. | CONFIRMED |
| platform.stageBg on WebKit | WebKit's aspect-ratio-under-grid-stretch behaviour is outside the model; it is engine layout. | CONFIRMED |
| people.card filter tail, hero.orbit z-index, overlays.signup | These were not model errors. The gate sampled unsettled pages, and fix-misc fixed 0 of 4 cells (b37227c). | CONFIRMED |
| morph.columns order, panel rest state | Page order and rest state were in no spec. | CONFIRMED |
| shard "header differs", mount-order lag | Harness defects: property lists came from timed scans, and prepare ran before collect. No Lean model existed. | CONFIRMED |
| goldens | They covered `logic.ts` only. The CSS and React output were never compared with Lean. | CONFIRMED |
| port handbacks "pass" | The summary step exits 0 regardless of rollup (`packages/gate-breakpoints/src/cli.mjs:25-27@84b9f19`). Agents read job conclusions; scoped local runs (13 probes) were read as full. | CONFIRMED |

The general lesson (INFERRED): a Lean proof covers only what is reachable from a gate probe through a generated
constant or a golden vector. Without the coverage map (Fw.Gate.Coverage), "every part is proved" said nothing
about the probes that failed. Where Lean was in the path, it caught the mistake:
- pilot parts disagreed with an independent Lean reading in 5 places (51eee11);
- the PLAN aging bound was false (4bd850f);
- the lead's attempt to answer a user step was refused (`only_user_answers`, Console.lean:623).

## Open defects found during this retro (still on main at 84b9f19)

| defect | evidence | class | proposed owner task |
|---|---|---|---|
| gate `summary` exits 0 when parts fail | `packages/gate-breakpoints/src/cli.mjs:25-27`, `.github/workflows/breakpoint-gate.yml:280-285` | c-proxy-verdict | NEW gate-exit-verdict |
| `shell-measure.mjs` does not parse (`node --check`: missing `)`) | `apps/site/scripts/shell-measure.mjs:112` | c-late-check | NEW check-map-lean |
| `/api/commands` takes `actor` from the request body; no capability check on that route | `apps/console-api/src/app.ts:23-31`, `packages/contracts/src/index.ts:22` | c-identity-heuristic | cap-diagnose (extend) or NEW policy-from-lean |
| wt-prep counts any `lean`/`lake` process under main/lean (the LSP too) as a build, so the shared clone is skipped | `scripts/wt-prep.sh:21-27` | c-identity-heuristic | NEW check-map-lean or gate-speed-ci (Fw.Ops.Cache) |

All four are CONFIRMED by reading the file at 84b9f19, and for shell-measure.mjs also by running `node --check`.

## NEW tasks proposed (12)

| id | owner role | module and theorem | writes |
|---|---|---|---|
| gate-exit-verdict | measure-engineer | Fw.Gate.Exit `exit_zero_iff` (statement above) plus a handback rule | lean/Fw/Gate/Exit.lean, packages/gate-breakpoints/src/cli.mjs, its tests and golden |
| check-map-lean | lean-prover | Fw.Ops.CheckMap `precommit_covers`, `tracked_mapped`; argv golden for own CLIs | lean/Fw/Ops/CheckMap.lean, scripts/hooks/pre-commit, scripts/check.sh, apps/site/scripts/shell-measure.mjs |
| wait-guard | lean-prover | Fw.Ops.Wait `wait_bounded`, `handback_no_open_bg` | lean/Fw/Ops/Wait.lean, .claude/hooks/wait-guard.mjs, tests |
| ci-runner-lint | measure-engineer | Fw.Ci.Runners `labels_free`, `mac_le_five`, `jobs_le_cap` | lean/Fw/Ci/Runners.lean, scripts/ci-lint.mjs, .github/workflows/* (generated fields) |
| mathdoc-binders | lean-prover | MathView binder coverage both ways, List-cardinality notation lint, pre-push on changed decls | lean/MathView*.lean, scripts/hooks/pre-push |
| claim-lint | lean-prover | Fw.Plan.Claims `claim_ok_iff` (CONFIRMED needs src/doc; MEASURED needs run; bound needs theorem) | lean/Fw/Plan/Claims.lean, packages/plan-lint/** |
| plan-principles-lint | plan-editor + lean-prover | Fw.Plan.Principles: decides needs a Lean dependency; no dates; local lane allow-list; next ranked by critical path | lean/Fw/Plan/Principles.lean, docs/team/work-graph.json schema |
| admit-reads | lean-prover | Fw.Sched.Admit read sets `reads_disjoint`; scratch name injective in agent | lean/Fw/Sched/Admit.lean, docs/team/work-graph.json (reads) |
| task-spec-lint | lean-prover | Fw.Plan.TaskSpec `spec_ok_iff`; land refuses without handoff | lean/Fw/Plan/TaskSpec.lean, apps/runner/src/land*.ts |
| policy-from-lean | lean-prover | Fw.Ops.Policy `forbidden_denied`, `kill_iff_owner`; golden = every violating command in the ledger | lean/Fw/Ops/Policy.lean, .claude/settings.json (generated deny), .claude/hooks/policy.mjs |
| resume-rule | lean-prover | Fw.Obs.Resume `resume_iff` (idle < TTL or ctx < 30k; never > 250k) | lean/Fw/Obs/Resume.lean, apps/runner/src/next*.ts |
| measure-valid | measure-engineer | Fw.Measure.Valid: verdict implies settled, aligned key, one clock, unit-typed tolerance | lean/Fw/Measure/Valid.lean, harness sample records |

The writes are proposals for the lead to narrow, and the theorem names are placeholders (INFERRED). These existing
tasks absorb part of the hardening:

| task | status | covers |
|---|---|---|
| lean-coverage | open | c-handcopy |
| fix-proofs | open | c-handcopy |
| gate-settle | open | c-sample-validity |
| obs-signals | open | c-orphan-wait, c-order-derived |
| cap-diagnose | open | c-identity-heuristic |
| incident-lean-fields | open; depends on this retro | the ledger fields above |

## The lead's own mistakes

These are the 64 ledger entries whose `who` field includes the lead, as the main actor or as the one who accepted
the result. The main ones, grouped by class:

- **c-principle (6):** calendar roadmap (T:2175); TS console logic before the Lean core (T:2562); every-breakpoint
  parity missing (T:1892); device measurement as primary evidence (T:23531); upstream store never scheduled;
  critical path not ranked (T:23684). The user caught every one; the principles lived in prose with no plan lint.
- **c-proxy-verdict (5):** accepted port handbacks on job conclusions; landed `morph.mount:shift` on flags-off runs
  (7ceb81c); landed console-lean with a failing test; trusted an incremental Lean build after a conflict merge
  (T:25713); landed code with no review.
- **c-shared-no-lock (8):** committed on main during `fw land` (80d7610, now locked); hand-kept Fw.lean imports;
  fan-out of four fix agents from an unlanded branch (T:33424 race; fix-nav CONFLICT); merge-order skew (7fcbbfa,
  c67cbe4, aa8d961); ports split before the shared gate machinery was factored; `cd` into a worktree (T:2617).
- **c-quota (6):** resumed idle agents after the cache TTL (~3 M cache tokens, T:3623); messaged contexts over 250k;
  exceeded the agent cap (T:25266); stray macOS runs (4151d8b, df77488); filled the macOS slots; no shared Lake
  cache at first.
- **c-identity-heuristic (7):** worktree roles spawned without isolation (T:26693); cd-prefixed `pnpm fw` (T:16963);
  role files edited with `sed`; ineffective permission rules; TaskStop by name (T:5902); tried to answer the user's
  step (T:11474, refused by Lean); orphan loop attributed to the wrong agent (a8e46f5).
- **c-unearned-claim (3):** load1 read as overload; rate-limit claim told twice before correction (T:25340,
  T:25415); PLAN aging bound (caught by Lean).
- **c-env-assume (11):** general-purpose substitutes for unloaded roles (T:2276, refused by the user at T:2306); env
  var assumed live after a reload; `--help` with side effects; heredoc backticks; `__LOAD__` placeholder (T:4767);
  work-graph reformat (4a6a3e6); forced worktree removals; Serena config change; LICENSE detected as Other;
  non-idempotent profile steps; ad-hoc command errors.
- **c-orphan-wait / c-order-derived / c-spec-gap / c-policy-prose:** fw watch exiting per alert left health stale
  (T:31698); a 5-minute foreground wait; a duplicate sampler; port-nav unlanded ~2 h; fw land bypassed (19 merges,
  0 land events); claim race; crossed plan-rev5 messages; confusing phone-session instructions; write sets that
  conflicted with the task's asks; local measurement on an overloaded Mac.

Pattern (INFERRED): the lead's mistakes are mostly **acceptance** mistakes (taking a proxy signal as done) and
**ordering** mistakes (fan-out before the dependency had landed or before the shared code was factored). The new
tasks gate-exit-verdict, admit-reads, plan-principles-lint and resume-rule target exactly these. All four make the
lead's decision a Lean refusal instead of a judgement call.

## Batch 2: the lead's mistakes of 2026-10-18 afternoon

The lead listed 15 more mistakes. They are rows of `docs/team/incidents/ledger.json` (not of `ledger.json` here),
13 new rows in all, with `occurrences` where a pattern recurred. Merges:
- The four undeclared-read refusals at land (snapshot-extract; gate-exit-verdict twice; gate-align-equiv) are one
  row, `inc-land-undeclared-reads`. The two scope refusals in the same item are a separate row,
  `inc-land-scope-stale-base`.
- The stray chromium-counts and gate-gaps runs on the integrate-ports-2 push are the existing `inc-ci-trigger-drift`
  (its symptom names that push). It got no new row.
- Early evidence (`inc-evidence-before-land`) and "upsert keeps it" (`inc-upsert-keeps-evidence`) are two rows. The
  first is a claim the lead had not earned; the second is stored state that no edit can take back.

| class | rows | provable | partly | no |
|---|---:|---:|---:|---:|
| c-unearned-claim | 3 | 1 | 2 | 0 |
| c-late-check | 2 (6 occurrences) | 2 | 0 | 0 |
| c-identity-heuristic | 2 | 2 | 0 | 0 |
| c-order-derived | 2 | 2 | 0 | 0 |
| c-orphan-wait | 1 (2 occurrences) | 1 | 0 | 0 |
| c-shared-no-lock | 1 (2 occurrences) | 1 | 0 | 0 |
| c-sample-validity | 1 | 0 | 1 | 0 |
| c-env-assume | 1 | 0 | 0 | 1 |
| **total** | **13** | **9** | **3** | **1** |

Eight of the nine provable rows have no hardening task of their own yet. Each names an open task of its class as host, and its
`leanReason` names the proposed task:
- `land-queue` (inc-land-waiters-pgrep, inc-land-retry-text-match, inc-watch-unlanded-queued);
- `land-dry` (inc-land-undeclared-reads, inc-land-scope-stale-base);
- `evidence-on-main` (inc-evidence-before-land, inc-upsert-keeps-evidence);
- `findings-subentries` (inc-findings-shared-entry).

`inc-watch-bg-ampersand` is covered by `wait-guard`.

**Classes that recurred after a hardening landed:**
- **c-identity-heuristic.** spawn-enforce had landed. Identity was still decided by text: a `pgrep -f` pattern made
  four land waiters deadlock, and a loose 'busy' match re-ran a refused land for about 20 min. MEASURED in this task:
  `scripts/wt-prep.sh` took a 12-hour-old `lean --server` (the LSP) for a main build and skipped the clone. That is
  the open wt-prep defect above, still live.
- **c-order-derived.** timing-alert had landed: it silences agent.unlanded for landed and locked branches. "Waiting
  in the land queue" is still no fact of the decision, so the watch churned.
- **c-unearned-claim.** pa-evidence-lint had landed, but it checks the shape of a sha, not that the sha is on main.
  Evidence written before the land passed it.
- **c-orphan-wait.** obs-signals had landed. It detects waiting-own-bg; it does not refuse. `fw watch &` came back a
  second time while wait-guard is still open.
- **c-shared-no-lock.** ledger-merge-driver had landed. It refuses, correctly, when one entry is changed on both
  sides. Three tasks still rewrote one findings entry, so two merges needed resolution by hand.
- **c-late-check** recurred six times, but its hardening (check-map-lean) has not landed. The land checks did their
  job; they only ran too late.

## Batch 3: the lead's mistakes of 2026-10-18 midday

The lead's list held 18 items (the task said 19; the input file has 18 lines). They are rows of
`docs/team/incidents/ledger.json`: 16 new rows, and 2 items are repeats.
- **Repeats.** The 3rd `fw watch &` and the 4th `fw watch ... & disown` are new `occurrences` of
  `inc-watch-bg-ampersand` (now 4). Its `fix.also` gained `policy-from-lean`, so it reads open again.
  wait-guard landed (ddaf278), but it runs in shadow mode (b42769d): it logs and does not refuse.
- **Observation.** Item 11 is not a mistake. It is the open question `inc-obs-matrix-context-commission`, linked to
  integrate-ports (also fix-commission-margin). Its two CI runs, 39083505918 and 39083482125, disagree at one head.
- **`at` field.** Every new row carries the recording time, because the list gave no time per item.

| class | new rows | provable | partly | no |
|---|---:|---:|---:|---:|
| c-late-check | 3 (4 occurrences) | 3 | 0 | 0 |
| c-spec-gap | 3 | 2 | 1 | 0 |
| c-env-assume | 3 | 0 | 2 | 1 |
| c-sample-validity | 2 (1 is the observation) | 1 | 1 | 0 |
| c-quota | 2 | 1 | 1 | 0 |
| c-proxy-verdict | 1 | 1 | 0 | 0 |
| c-identity-heuristic | 1 | 1 | 0 | 0 |
| c-shared-no-lock | 1 | 1 | 0 | 0 |
| c-orphan-wait | 0 (+2 occurrences on the existing row, now 4) | (1) | | |
| **total** | **16** | **10** | **5** | **1** |

No new class was needed. Derived status (`pnpm fw incidents lint`: 49 incidents, 0 errors):
- 1 fixed: `inc-wt-prep-lsp-as-build`, by cap-diagnose (d5b9d00).
- 5 fixing.
- 10 open.

**What the landed work did and did not close:**
- land-queue/dry (809fcd4) landed, but three land-dry defects are still open:
  - the VERDICT line is missing for an empty branch;
  - the mathview lint is not run;
  - the land-inputs scan follows ignored files on disk (`apps/runner/test/land-inputs.test.ts:73-89@b50332c`, an
    `existsSync` filter).
- findings-subentries (dfc1d70) landed. Its handoff conflict (`inc-handoff-write-refused`) is a separate open row.

**Classes that recurred after a hardening landed:**
- **c-orphan-wait:** the guard runs in shadow mode.
- **c-late-check:** land-dry covers part of it.
- **c-shared-no-lock:** Fw.Sched.Admit `wconf` exists, but nothing calls it at spawn.

Each time, the rule existed, but the tool boundary did not enforce it.

**The three hardenings with the biggest payoff** (proposed work-graph lines; the lead adds them):

| id | title | deps |
|---|---|---|
| `wait-guard-enforce` | (S) Fw.Ops.Wait: a while-read loop fed by a file redirect is bounded (golden), then wait-guard switches to enforce (the settings change goes to the user as one ready command) | wait-guard |
| `land-dry-full` | (S) fw land --dry prints exactly one VERDICT line on every path (an `empty` kind), runs the mathview lint (module cache) and scans tracked files only (`git ls-files`) | land-dry, mathview-module-cache |
| `ci-shared-failure` | (S) Fw.Obs shared-failure rule: group ci.failed by (workflow, job) across branches; one job red on 2 or more branches is one lead alert; a 'CI green' claim needs every job of the run green | obs-next-glue, claim-lint |

Why these three:
- **wait-guard-enforce** ends the most repeated mistake: 4 orphans, each found and killed by hand. It also fixes the
  false positive (`inc-wait-guard-while-read-fp`) that blocks enforce mode.
- **land-dry-full** covers 3 rows and 4 occurrences. Each one cost a land refusal under the lock.
- **ci-shared-failure** fixes the case where one shared red job hid every lane's CI verdict for 5+ runs.

Runners-up, now hosted by open tasks:
- `wt-reap`: remove a landed worktree only when `git status --porcelain` is empty (untracked included), plus a
  scratch quota (inc-worktree-force-untracked, inc-disk-scratch-growth).
- `spawn-admit`: the spawn guard asks `ops.admit` (inc-parallel-write-overlap).
- `ci-run-cap`: a push-side counter per ci/* branch (inc-ci-run-cap-prompt).

## Dropped or merged items

- **Unsolved goals in Incident.lean:361:** normal proof iteration inside one task, not a process mistake. Dropped.
- **Docker Hub auth outage:** external. Kept only as the unpinned-image mistake (m162).
- **Duplicates across the three harvested lists were merged.** Examples:
  - rate limit, which appeared in both the lead and agent lists;
  - orphan loops, recorded three times and kept as one entry with three agents;
  - math rounds r3 to r13, kept as one entry plus pattern-specific entries.
- **Census counts are INFERRED (taken from the harvester, not recounted):** the 948 isolation refusals, 37 blocked
  sleeps, 46 oversized Reads, about 50 sed/zsh errors, and 27 calls to unavailable tools.
  - This task hit the isolation refusal twice itself (a for-loop over `git cat-file`, and `node $P`). That is a
    MEASURED instance; the workaround was a file-driven `--batch-check`.

## Method

1. Harvest: the lead transcript, 235 subagent transcripts, and repo records (incidents, improvements logs, handoffs,
   git log).
2. Dedupe by root cause, one level deeper than the symptom ("why did the system allow it").
3. Check existence for all 130+ cited commits (`git cat-file --batch-check`: all exist).
4. Spot-check 21 lead transcript lines and 15 subagent transcript lines against their quoted text. All matched.
5. Re-read the four open defects at 84b9f19.

Existing Lean coverage per class is listed with file:line in `ledger.json` (`existingLean`).

Per the task's write list, this task wrote no handoff file; this note and the ledger are the handoff.

## What this changes in the plan

- **docs/team/work-graph.json:** add the 12 NEW tasks above. Order them on the critical path:
  1. gate-exit-verdict and check-map-lean first. Both fix live defects on main.
  2. policy-from-lean and wait-guard next. They stop the recurring costs: kills, loops and agent-hours.
  3. Then claim-lint, mathdoc-binders, admit-reads, task-spec-lint, plan-principles-lint, resume-rule, ci-runner-lint
     and measure-valid.
- **PLAN, "Lean first" section:** add the rule "a proof counts for a gate probe only through Fw.Gate.Coverage
  (generated constant or golden)". Port tasks then hand back only with exit-0 verdict records at the branch head,
  with full scope and the task's flags.
- **docs/team/work-graph.json (batch 3):** add wait-guard-enforce, land-dry-full and ci-shared-failure (lines above).
  Then repoint the hosted rows' `fix.task` to them: inc-watch-bg-ampersand, inc-wait-guard-while-read-fp,
  inc-land-inputs-untracked-exists, inc-handback-without-check, inc-land-dry-no-verdict and inc-ci-shared-job-red.
- **incident-lean-fields (open):** take `classId`, `leanVerdict`, `empiricalCheck` and `evidenceStatus` from
  `research/mistakes/ledger.json` as the incident schema fields.
