---
id: 2026-10-17-plan-rev5-delta
kind: decision
title: "PLAN revision 5 delta: automated console, Lean-first scope, math view"
status: accepted
created: 2026-10-17
updated: 2026-10-17
authors: [agent:automation-proof-synthesis]
topics: [plan, console, events, lean, math-view]
links:
  plan: docs/plan/PLAN.md (apply on top of revision 4, MUI)
  notes:
    - research/kickoff/10-automation-and-proof/README.md
    - research/kickoff/10-automation-and-proof/01-v1-console-manual-work.md
    - research/kickoff/10-automation-and-proof/02-event-automation-design.md
    - research/kickoff/10-automation-and-proof/03-lean-everywhere-inventory.md
    - research/kickoff/10-automation-and-proof/04-lean-to-math.md
---

# PLAN revision 5: the delta to apply

> **Applied (2026-10-17), and partly superseded.** This delta was applied to `docs/plan/PLAN.md` as revision 5. Its
> Day-N schedule, "before Monday", `~/.fw-console/` and bare-repo text are superseded by your later decisions (no
> calendar; console state in the gitignored `.fw-console/`; `main` a normal branch). PLAN.md Appendix D records each
> override. This file is kept as history.

**Source.** Your three requirements of 2026-10-17: (R1) v1's console needed agents to update parts of it by hand;
automate it so agents do not maintain status. (R2) Prove as much as possible with Lean. (R3) You do not read Lean; show
theorems as math you can read, kept in sync with the Lean. The evidence and designs are notes 10/01-04, summarised in
`research/kickoff/10-automation-and-proof/README.md` (cited below as [10], [10.01] … [10.04]).

**How to apply.** PLAN.md is at revision 4 (MUI) when this is applied. Line numbers are not used. Each item names a
section, quotes the revision-4 text to replace (**Old**) where there is one, and gives the **New** text. "Add" items
name the anchor text they go after. Quoted old text is copied from revision 4 and written on one line (in PLAN.md it may wrap across lines; inside quotes, `\`` stands for a backtick); if a later edit changed it, apply the
intent and log the difference in Appendix D. Label clashes found while writing this delta are resolved here: the
sandbox spike is **SPK-t** (revision 4 already uses SPK-q for the styling-neutrality baseline), and [10.04]'s gap
theorems are cited by Lean name, not by "G1-G7" (PLAN's G1-G4 are outcome goals).

---

## 1. Frontmatter and introduction

**Frontmatter `revision`.**
- Old: `revision: 4 (your decisions of 2026-10-17: MUI everywhere, Lean, private repo, looser budget; see Appendix D)`
- New: `revision: 5 (your requirements of 2026-10-17: automated console, Lean-first, math view; on top of revision 4's MUI decisions; see Appendix D)`

**Frontmatter `links.notes`.** Add `research/kickoff/10-automation-and-proof/README.md`.

**Intro paragraph.**
- Old: `**Revision 4 applies your four decisions of 2026-10-17 (§12.0).** Only Q1 remains to answer before Monday.`
- New: `**Revision 4 applies your four decisions of 2026-10-17; revision 5 applies your three requirements of the same day: nobody hand-writes console state, Lean wherever it can prove something, and math you can read (§12.0).** Q1, Q22 and Q23 remain to answer before Monday.`
- Also add `[10]` to the list of cited notes: "`[10]` is the automation-and-proof study, `research/kickoff/10-automation-and-proof/README.md`, with sub-notes `[10.01]` to `[10.04]`."

## 2. Glossary

- `Q1 … Q21` row: Old `questions and defaults for you (Q2, Q3, Q4 and Q16 are answered; see §12.0)` → New
  `questions and defaults for you (Q2, Q3, Q4, Q12, Q16 are answered; see §12.0); Q22-Q30 added in rev 5`, label
  `Q1 … Q30`.
- `V-a … V-q` → `V-a … V-t` (§1.2 adds V-r, V-s, V-t).
- `SPK-a … SPK-s` → `SPK-a … SPK-u` (Appendix B adds SPK-t, SPK-u).
- `R1 … R22` → `R1 … R27`.
- Add a row: `| **L1 / L1-cond / L2 / L3** | proof levels: proved in Lean; proved but with a named unprovable premise; Lean spec + TS copy kept equal by tests; not provable | §5.1 |`.
- `stages` row: Old `question → build → screen → review → (device) → land, always written as words` → New
  `question → build → screen → review → (device) → land, always written as words; derived from evidence events, never set by hand (§9.2)`.

## 3. §0 The plan in one page

**Pain point 3 row, "v2 answer" cell.**
- Old: `**A small pure core with a thin IO shell.** The few decisions that matter (verdict, flags, screening, frame ticks) live in one Lean 4 project (\`fwcore\`) with theorems. Tools are plugins. Results are content-addressed, so changing a tool re-runs only that tool's tests and artifacts. An explicit MVP tier keeps the tooling small (§3, §5)`
- New: `**A proved core with a thin IO shell.** Every decision, queue and status view that can be proved lives in one Lean 4 project (\`fwcore\`), run as a long-lived process: the console reducer, the phone queue, the gates, the verdict, flags, screening and frame ticks (Lean-first, §5.1). TypeScript moves data. Tools are plugins. Results are content-addressed, so changing a tool re-runs only that tool's tests and artifacts. An explicit MVP tier keeps the tooling small (§3, §5)`

**Add after the "What the chat history adds" paragraph:**

> **Nobody writes status (revision 5).** In v1, 10.9 % of all tool turns did nothing but write or poll the console,
> 31 % for the lead, and 56 % of the 4,412 status-board writes recorded something a machine knew or will know in v2
> [10.01]. In v2 every console view is a formula over one append-only event log that only console-api writes. Agents
> have no write path to it: facts are observed (git, Claude Code hooks, watchers, console-api's own jobs), and agents
> send typed requests that the Lean reducer accepts or refuses (§3.2, §8.5). What is still judgement is one catalogue
> of typed commands (§8.5).
>
> **You read math, not Lean (revision 5).** Every theorem and every definition you read carries its math in its
> docstring. A generated page shows it, the build fails when the Lean (or a definition it uses) changed after the math
> was signed, and a separate reviewer role signs the math (§5.3).

**"What to expect" list.** Add a bullet:
- `**Lean costs more up front.** About 20 Lean modules (4-6k lines) instead of 4, mostly in M0-M2, about $700-1,100 of Lean work instead of $280 (INFERRED [10.03 §7.1]), partly offset by console work that is no longer TypeScript. A module that costs too much without catching bugs moves back to TypeScript by a decision record (§5.1).`

## 4. §1.2 Method goals

**V-l row.**
- Old: `| V-l | **Bug ledger** (replaces "share of logic proved") | every entry has \`kind: request \| incident\`; every incident tagged *proof would have caught it* / *property test caught it* / *adapter (IO, device, container)* | complete ledger; at M4 it decides whether Lean pays (Q12), counting incidents only (v1 filed 45 requests as incidents [08]) | [FR §3.1] |`
- New: `| V-l | **Bug ledger, per module** (replaces "share of logic proved") | every entry has \`kind: request \| incident\`, \`module\`, \`level: L1 \| L1-cond \| L2 \| L3\` and \`caughtBy: proof \| build-mutant \| property-test \| adapter-test \| replay-monitor \| user \| escaped\` | complete ledger; it drives the per-module demotion rule (§5.1), counting incidents only (v1 filed 45 requests as incidents [08]) | [FR §3.1], [10.03 §7.2] |`

**V-m row.**
- Old: `| V-m | **Bugs in proved areas** | incidents in verdict / flag resolution / screening / frame ticks | 0 logic incidents (adapter bugs are counted separately) | bug ledger |`
- New: `| V-m | **Bugs in proved areas** | logic incidents in any L1 module (the console reducer and views, queues, gates, verdict, flags, screening, ticks …) | 0 escaped logic incidents (adapter and L3-premise bugs are counted separately) | bug ledger |`

**Add three rows after V-q:**

| # | Goal | Metric | Target (proposal) | Source |
|---|---|---|---|---|
| V-r | **Mutant kill rate** | each L1 module ships v1 bugs put back on purpose (`FwTest/Mutants/<module>/*.patch`: I-091, I-113, I-145, I-059, I-185, I-011 incl. head-of-line blocking, I-041, plus design mutants) | 100 % make `lake build` fail; a surviving mutant means the theorem has no teeth and blocks the module's next land | [10.03 §7.2] |
| V-s | **Math sign-off** | every `Fw` theorem and every definition marked user-facing has docstring math whose deep statement hash equals the signed hash | 0 missing, 0 stale, 0 unsigned at land; reviewer-vs-judge disagreements are counted and reported | [10.04 §2.3] |
| V-t | **No hand-written status** | console fields an agent can set directly; G1-style replay of v1's log through the v2 reducer | 0 directly settable fields (every agent input is a typed, refusable event in the §8.5 catalogue); the replay reports the share of v1 hand states that contradicted git or the steps at the time | [10.02 §6.5] |

## 5. §2.2 Drop

**Row "Many writers to many JSON stores; agents writing board state", Replacement cell.**
- Old: `One writer (console-api), one append-only event log, status as a projection`
- New: `One writer (console-api), one append-only event log, status as a projection computed by the Lean reducer. Agents have no write path to it (sandbox + deny rules + state outside the repo, §8.3) and no command that sets a status field; their only inputs are typed, refusable requests (§8.5). v1: 10.9 % of all tool turns were console upkeep; 56 % of status writes were derivable [10.01]`

## 6. §3.1 Overview (diagram)

- Node `FW`: Old `FW["lean/ fwcore: verdict, ticks, flags, screen (later: stage, step)"]` → New
  `FW["lean/ fwcore serve: console reducer + views, queues, gates, verdict, ticks, flags, screen"]`
- Node `API`: Old `API["console-api: Node 24 + Hono, single writer, events.jsonl, run + device queues, watchers"]` →
  New `API["console-api: Node 24 + Hono, single writer (append + fsync), CLI socket, reconcilers, watchers, jobs"]`
- Add a node and two edges:
  ```
  OBS(["observed facts: git refs (reconciler), Claude Code hooks (spool), watchers, transcripts"])
  MV[("docs/math: generated math view")]
  OBS -- "facts with idempotency keys" --> API
  FW -- "lake exe mathview" --> MV
  ```
- Edge Old `API <-- "JSON-lines ops with ids" --> FW` → New `API <-- "events in, accepted/refused + changed rows out; queries" --> FW`.

## 7. §3.2 Modules and their narrow contracts

**Row "TS → fwcore".**
- Old: `| TS → fwcore | one JSON-lines request per decision, MVP ops: \`verdict\`, \`ticks\`, \`twins\`, \`flags.resolve\`, \`screen\`, \`samples\` (later: \`stage.step\`, \`step.step\`) | Long-lived child process; ~140 µs per round trip (MEASURED [05 §1]). **Hardening below** |`
- New: `| TS → fwcore | \`fwcore serve\` is long-lived and **stateful**: it holds the reducer state, the queues and the gates. Ops: \`console.apply\` (one event → accepted \| refused(reason) + changed rows), \`console.replay\`, \`console.query\` (rows, steps, queues, plan), plus stateless decisions (\`verdict\`, \`ticks\`, \`twins\`, \`flags.resolve\`, \`flags.enumerate\`, \`screen\`, \`samples\`) | Node → fwcore round trip 17.6 µs (MEASURED [10.03 §4.2]; [05 §1] measured ≈141 µs with the same method and a different binary, not yet explained; re-measured on Day 9). 100k events replay in under 1 s. The state loop uses \`modifyGet\` (a get-then-set copy was 66× slower, MEASURED). **Hardening below** |`

**Row "console-api → status and steps".**
- Old: `| console-api → status and steps | each status row: stage, owner, next step, ETA, age of its last event, and \`needs-you: yes/no + the exact action\` (set only by an open step or proposal event); a step is shown only after a script checks it is ready, and has a retry | v1: 25 "what does this mean" asks, rows saying "waiting on you" with nothing to do [08] |`
- New: `| console-api → status and steps | each status row is **computed, never written**: stage (from evidence keyed by commit), owner (whose move, by stage), next action (the exact next command or button), ETA (queue position × median duration, sample count shown), age and staleness (λ frozen at stage entry; a row with a live wait is never stale), and \`needs-you: yes/no + the exact action\` (an open step, proposal, decision, permission prompt or landing violation). Every cell has a "why" popover listing the events behind it. A step is shown only after a script checks it is ready, and has a retry | v1: 25 "what does this mean" asks, rows saying "waiting on you" with nothing to do [08]; 4,412 hand-written status entries [10.01] |`

**Add rows after "console-api → status and steps":**

| From → to | Contract | Notes |
|---|---|---|
| agent → console-api | `pnpm fw <verb>` sends one typed request to `~/.fw-console/<repo-id>/run/cli.sock`; a synchronous PreToolUse hook on `pnpm fw *` appends a single-use capability `HMAC(secret, agent_type ‖ tool_use_id ‖ sha256(cmd))`; console-api verifies it and stamps `actor` and `signedBy`; the reducer accepts or refuses; `fw` prints the outcome and exits non-zero on refusal | The socket never produces `user`, `script` or `git`. A request without a valid, unused capability is refused [10.02 §6.4] |
| observers → console-api | facts with an idempotency key built from fields the hook and the reconciler both see; Claude Code hooks write a spool file synchronously (< 100 ms, no stdout); git facts come only from console-api's ref reconciler; transcript usage is an upsert (last record per `message.id` wins); device states are keyed by transition | A key is marked seen only when its event is accepted, so a fact that arrived early is applied on re-send [10.02 §6.2] |

**Hardening list, item 5 "Numbers".** No change.

## 8. §3.3 Where each decision runs

**Bullet "Exception: code that must run in the browser".**
- Old: `It is a TS mirror, and a TL2 oracle test (fast-check, 2,000 cases) must agree with \`fwcore flags.resolve\` on every change [05 §5.3].`
- New: `It is a TS mirror, and a TL2 test must agree with \`fwcore flags.resolve\` on **every** single-part override of every preset, enumerated by \`fwcore flags.enumerate\` (the domain is finite, so this is as strong as a proof for that registry version), plus 2,000 fast-check cases for multi-part URL overrides [10.03 §2.10].`

**Bullet "Plain bookkeeping stays in TS".**
- Old: `- **Plain bookkeeping stays in TS** with unit tests, for example "which artifact keys are missing" (a set difference). Lean is kept for decisions whose wrong answer would mislead an experiment.`
- New: `- **Bookkeeping is in \`fwcore\` too (Lean-first, revision 5).** The console reducer and its views, the device and run queues, \`fw plan\`'s hits and todo sets, cache prune, the land-time path check, spawn-guard's decision, usage dedupe and the JSON decoders for hook payloads, usage records and the Vite manifest are L1 modules (§5.1). v1's failure areas were exactly these (hand-kept board, scheduler) [10.03 §1].`

**Bullet "Priority is data you own".**
- Old: `The experiment queue and the device queue read it through one pure, table-tested TS function of the list and the job class (user step > calibration > class X/P > spot-check).`
- New: `The experiment queue and the device queue read it through one proved Lean function of the list, the job class (user step > calibration > class X/P > spot-check) and the waiting time (aging: one level per A seconds), which starts the most urgent job **that fits** the booked window (no head-of-line blocking; \`dispatch_sound\`, \`dispatch_conserving\`, \`aged_beats_newer\` [10.03 §5]).`

**Bullet "Numbers that are fitted, not decided".** Add at the end: `An L1 checker must accept the deployed coefficients (all non-negative, exact fractions) before use, so the screening theorems hold for the model actually used [10.03 cm.5].`

## 9. §3.4 MVP tier and later tier

- **console storage** row, MVP cell. Old: `\`events.jsonl\` + in-memory projection; one in-process run queue and one device job queue; three watchers (device, stall, notice coalescer, §8.5)` → New: `\`~/.fw-console/<repo-id>/\` (outside the repo and \`.git\`): \`events.jsonl\` (append + fsync, then apply) + snapshots, spool, CLI socket, secrets, and the bare repo that holds \`main\`; the projection lives in \`fwcore serve\`; one run queue and one device job queue (Lean); reconcilers (git refs, spool, artifacts, transcripts) and three watchers (device, stall, notice coalescer, §8.5); daily exports to \`results/console/\``
- **Lean** row. Old MVP cell: `\`Frames\`, \`Verdict\`, \`Flags\` (+ generated registry), \`Cost\`/\`screen\`` → New: `Lean-first, by milestone (§5.1): M0 console core (reducer, authority, steps, needs-you, landing rule), phone queue, spawn-guard, path check, usage meter, budget, JSON decoders, Frames, Verdict; M1-M3 the rest of the L1 inventory`. Old later cell: `\`Stage\`, \`Step\` (lifecycle). \`Thread\`, \`Log\`, \`Lease\` only after an incident class appears. No engine-rule data in Lean` → New: `only what an incident or a new decision calls for (M5-M6). No engine-rule data in Lean`
- **hooks** row. Old MVP cell: `\`SessionStart\` brief (also after compaction), \`SubagentStop\` usage, one \`PreToolUse(Agent)\` spawn-guard` → New: `\`SessionStart\` brief (also after compaction); one observer emitter \`emit.mjs\` (synchronous, spool-only, silent) on SessionStart, SubagentStart, SubagentStop, TeammateIdle, PreCompact, PostCompact, StopFailure, Notification(permission_prompt\|agent_needs_input), PostToolUseFailure(Bash); the capability hook \`PreToolUse(Bash)\` on \`pnpm fw *\`; \`PreToolUse(Agent)\` spawn-guard (\`onFailure: block\`). Not used: \`http\` hooks (lose events silently), \`WorktreeCreate\` (replaces git behaviour), \`SessionEnd\` as a source of truth (1.5 s timeout)`. Old later cell: `\`SubagentStart\` role brief, \`TeammateIdle\` (only if the stall watcher is not enough), \`TaskCompleted\`` → New: `\`TaskCreated\`/\`TaskCompleted\` observers, \`SubagentStart\` role brief`.

## 10. §5.1 What is proved (replace the section body)

Replace everything from `\`lean/README.md\` lists the inventory.` up to and including the **Not proved** paragraph
with the text below. Keep the **Multiplicity** paragraph unchanged after it.

> **Lean-first (your requirement of 2026-10-17).** [10.03] lists 87 decisions, state machines and pure functions in
> this design and places each at a proof level. `lean/README.md` holds the inventory; the generated math view (§5.3)
> shows each item's math.
>
> | Level | Count | Meaning |
> |---|---|---|
> | **L1** | 54 | Implemented and proved in Lean, run through `fwcore`; inputs are the console's own events, ids and counts |
> | **L1-cond** | 30 | Proved in Lean, but its real-world meaning needs a named L3 premise (for example: the counts are right, every spawn passes the hook, the declared dependencies are complete, the signer's identity) |
> | **L2** | 3 | Lean spec + TS copy kept equal by tests: the site's flag resolver (exhaustive over its finite domain), JSON wire codecs, console-web's optimistic preview |
> | **L3** | 18 categories | Not provable; each names how it is checked and which L1 decision it feeds (below) |
>
> **Modules by milestone** (P = proved in a kickoff sketch: `05-lean-sketch`, or `10-automation-and-proof/lean-scratch`):
>
> | Milestone | Lean modules | v1 bug classes they remove |
> |---|---|---|
> | M0 | `Fw/Console` (reducer, authority table, steps, needs-you, replay, landing rule with violations, review independence, staleness; P in `ConsoleV2.lean` and `03-inventory/Auto/Console.lean`); `Fw/Spec/DeviceQueue` (priority with aging, no starvation, one job at a time, fits-the-window, no head-of-line blocking, hard stop at the window end; P); `Fw/Ops` (spawn-guard, path check, usage dedupe, budget alerts); `Fw/Wire` (hardened, + JSON decoders for hook payloads and usage records); `Fw/Spec/Frames`, `Fw/Spec/Verdict` (P; + `land_null_prob`, multiplicity gate, `better_sound_higher`, the tick-vs-34 ms count, both P in [10.04 §5]); the math-view lint | hand-kept board (I-044, I-108, I-145, I-162, I-183, I-248), double-answered steps (I-059), scheduler (I-011, I-041, I-049, I-185), spawn storms |
> | M1 | `Fw/Spec/ArtifactKey`, `Plan`, `Store` (P for keys and minimal invalidation); rows, threads, proposals, notices, stall watcher, digests; run queue, sessions, preflight, lease and user step; stage lifecycle, prediction-before-data, land queue; determinism class; budgets and vsyncs | stale reuse, cherry-picking, lease mid-step (I-122, I-123), a renew that shortens (I-091), a re-queue that loses its place (I-113) |
> | M2 | `Fw/Spec/Flags` + `Fw/Gen/Registry` (P), presets; parity bands and part lifecycle; `Cost`/`screen`, alignment, uncounted families, landing classifier, `land_requires` (full) | arms that changed more than the named thing; over-trusting proxies |
> | M3 | model ladder, fit-certificate checker, WebKit model monotonicity, licence, spot-check schedule, validation metrics, block validity | a model used beyond its evidence |
> | M4 | sequential ABBA, Hodges–Lehmann, union bound; **per-module evidence review** | — |
>
> **Evidence, not a go/no-go.** Each L1 module ships with mutants (V-r) and is counted in the per-module bug ledger
> (V-l). **Demotion rule:** a module moves from L1 to L2 by a decision record when its proofs cost more than 1
> agent-day on each of two consecutive changes while the ledger shows 0 bugs caught by its proofs or mutants, or when
> it blocks a console feature for more than 1 working day. The Lean spec then stays as the oracle for a TS
> implementation. At M4 the lead reviews the per-module table; Lean as a whole is not on trial.
>
> **Still dropped:** engine decision rules as Lean data, metric reducers, part geometry claims. A proof about our
> transcription of an engine rule cannot catch a transcription error; engine rule data is checked by **table tests**
> against `compositeFailed` (Chromium) or WKTR (WebKit).
>
> **Not proved (L3), each with its check:** engine behaviour (rule cards, table tests); work counts (determinism per
> type, V-a, V-b, V-n); coefficient fitting (calibration, holdouts, the L1 certificate checker); run independence
> (A/A, ABBA, contamination flag); sha256 collisions (stated once as an assumption); pixels (tiers vs A/A); the React
> parts (PL0-PL6); IO (adapters with contract suites, `fwcore replay` as a nightly runtime monitor); YAML and CSS
> parsing (golden files); human and LLM judgement (blind protocol, typed commands); the UI (Playwright); `fwcore`
> speed (a speed-budget test); the clock (console-api stamps time; a tick at every window end); **completeness of
> observation** (reconcilers re-read git, transcripts and artifacts; adapter test "every decision emits its close
> event"); **actor identity** (the capability hook, SPK-t); **completeness of declared dependencies** (a hermetic run
> that records the inputs a tool actually read, SPK-u); **"answered / complete" judgements** (your click or a typed
> close).

## 11. §5.2 How TypeScript and Lean connect

- First bullet. Old: `- **Lean decides, TypeScript does** (architecture (i) of [05 §5]). \`lean/\` is one Mathlib-free Lake project that builds the native executable \`fwcore\` (JSON-lines over stdin/stdout, hardened as in §3.2).`
  New: `- **Lean decides and holds the console state; TypeScript moves data** (architecture (B) of [10.03 §4]). \`lean/\` is one Mathlib-free Lake project that builds the native executable \`fwcore\`. \`fwcore serve\` is one long-lived, single-threaded process (JSON-lines over stdin/stdout, hardened as in §3.2). console-api stamps each event with an id and the time, appends and fsyncs it, sends it to \`fwcore\`, and publishes the changed rows over SSE. A refused event is still logged with its reason. Nightly, \`fwcore replay events.jsonl\` must reproduce the live state hash.`
- Add a bullet: `- **One reducer, one data layout.** The production \`Fw/Console\` merges [10.02]'s semantics (actors, cards, authority, landing with violations, review independence, seen-on-accept) with [10.03]'s data structures (\`Std.HashMap\`/\`HashSet\`, \`modifyGet\`). The 100k-event speed test runs in \`lake test\` (budget < 1 s).`

## 12. §5.3 How to read a theorem (replace the "How to read a theorem" paragraph)

- Old: `**How to read a theorem:** the statement (the line after \`theorem … :\`) **is the spec**. You and the reviewer check that the statement says what we mean; Lean checks that the proof is right. \`#guard\` lines are examples that run at build time.`
- New:

> **You read math, not Lean.** Every theorem, and every definition you are expected to read (for example `may`,
> `stage`, `ready`, `stale`, `eff`), carries its math in its docstring: one English sentence, then one `$$…$$` LaTeX
> block, using one notation table ([10.04 §3]). Lean checks the proof; the **math-reviewer** role checks that the math
> says exactly what the Lean says; you check that it is what we mean. `#guard` lines are examples that run at build
> time.
>
> **The math view is generated, never hand-kept** ([10.04 §2]):
> 1. `lake exe mathview` walks every `Fw` module of the compiled project and exports, per declaration: name, kind,
>    file:line, the docstring's English and math, the Lean signature, a machine-made LaTeX form of the Lean statement
>    (no LLM), axioms (`sorryAx` = not proved), and a **deep statement hash** (64-bit): the statement plus the bodies
>    of every `Fw` definition it reaches, transitively.
> 2. A Node script renders `docs/math/index.html` from that export with KaTeX `renderToString(…, {output: 'mathml',
>    throwOnError: true})`. MathML is drawn natively by the browser, so the page needs no script, stylesheet or font
>    files (it can be published as an Artifact or opened in the console). Per entry: math, English, chips (proved /
>    sorry; signed / unsigned / stale), uses, and the Lean collapsed. Sample:
>    `research/kickoff/10-automation-and-proof/math-view-sample.html`.
> 3. **Sign-off is an event, not a file edit.** `pnpm fw math:sign <decl>` sends `math.signed {decl, stmtHash,
>    mathHash}`; only the math-reviewer role and you (console-web) may cause it. console-api exports the signed set to
>    `lean/math.lock.json` (generated; Edit/Write denied to agents; a pre-commit check fails if the committed file
>    differs from the export). An agent that edits a theorem therefore cannot re-sign it.
> 4. **The lint** (`lake exe mathview --lint`, in TL0) fails on: a declaration without math; `sorry` outside a
>    `planned` allowlist; a deep hash that differs from the signed one (the Lean or a definition it uses changed); math
>    text changed since signing; a KaTeX parse error; a lock entry for a declaration that no longer exists; an axiom
>    other than `propext`, `Classical.choice`, `Quot.sound` (this replaces the hand-kept name list in
>    `scripts/Axioms.lean`).
> 5. **Review protocol.** The math-reviewer sees the Lean signature, the machine-made math and the definitions, but not
>    the docstring. It writes its own math and compares clause by clause: quantifiers and domains (ℕ vs ℤ), every
>    hypothesis, ≤ vs <, rounding down and truncated subtraction, empty lists, ties, repeats, override and fold order,
>    `= true` for Bool, and which direction of ⇔/⇒ is proved. Agreement → it signs. Disagreement → a second
>    independent reviewer; if they still disagree, the item comes to you with both versions (Q28).
> 6. A toolchain bump may change hashes; `mathview accept --toolchain-bump` re-signs only entries whose signature text
>    and machine-made LaTeX are unchanged, in one reviewed PR.
>
> Example of a docstring (`Fw/Spec/Frames.lean`):
>
> ```lean
> /-- A frame counts as at least 5 ticks exactly when it lasts at least 37.5 ms.
>
> $$\forall dt \in \mathbb{N}:\quad \operatorname{tick}(dt) \ge 5 \iff dt \ge 37\,500$$
> -/
> theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt := …
> ```

In the worked example that follows, add a math line to each docstring, e.g. for `land_sound`:
`$$\operatorname{land}(C, V) = \mathrm{better} \Rightarrow \forall y \in V,\ \forall x \in C:\ y < x$$`.

## 13. §5.4 Test strategy per layer

- **TL0** row, "What" cell. Old: `proofs, \`#guard\` examples, axiom/\`sorry\` gate, partial-op grep on \`Wire\`/\`Main\`` → New: `proofs, \`#guard\` examples, the math-view lint (missing / stale / unsigned math, sorry, axioms, KaTeX), mutant patches (each must break the build, V-r), the 100k-event speed budget, partial-op grep on \`Wire\`/\`Main\``. "Tool" cell: replace `\`scripts/Axioms.lean\`` with `\`lake exe mathview --lint\``.
- **TL2** row, "What" cell. Old: `contracts: zod ⇄ JSON Schema ⇄ Lean golden round trips (incl. the \`Rat\` wire form); the resolver oracle test` → New: `contracts: zod ⇄ JSON Schema ⇄ Lean golden round trips (incl. the \`Rat\` wire form and every event \`type@n\` with its upcasters); recorded hook payloads and transcript records through the Lean decoders; the resolver test over its whole enumerated domain`.
- Add after the table: `**Console fault injection (TL4, on demand and nightly):** golden event logs replayed with duplicates, drops followed by a reconcile pass, reorders within a subject, a torn last line and skewed producer clocks must give the fault-free state; v1's status history replayed through the v2 reducer measures V-t [10.02 §6.5].`

## 14. §7 Repo layout

**§7.1 tree.**
- Old: `├─ .claude/                   settings.json, agents/*.md, hooks/*.mjs (3 in MVP), skills/*/SKILL.md` → New:
  `├─ .claude/                   settings.json, agents/*.md, hooks/{session-brief,emit,cap,spawn-guard}.mjs, skills/*/SKILL.md`
- Old: `│  ├─ console-api/            Node 24 + Hono; single writer; events.jsonl; run queue; fwcore child` → New:
  `│  ├─ console-api/            Node 24 + Hono; single writer; CLI socket; reconcilers, watchers, jobs; fwcore serve child (state outside the repo, §7.3)`
- Old: `├─ lean/                      Lake project fwcore (seeded from research/kickoff/05-lean-sketch)` → New:
  `├─ lean/                      Lake project fwcore (seeded from 05-lean-sketch and 10-automation-and-proof/lean-scratch); math.lock.json (GENERATED)`
- Add under `docs/`: `├─ docs/math/                  GENERATED: the math view (index.html, mathview.json)`
- Add under `results/`: `│  ├─ console/<date>.events.jsonl.gz   daily exports of the event log (no personal data)`

**§7.3 What never enters git.** Add a bullet: `- The live console state: \`~/.fw-console/<repo-id>/\` (event log, snapshots, spool, socket, secrets, the bare repo that holds \`main\`). It lives outside the repo and outside \`.git\`, because the sandbox lets worktree agents write the shared \`.git\` (CONFIRMED, sandboxing doc). Git gets daily exports only.`

## 15. §8.2 Roster

**lead row, "Writes" cell.** Old: `lands to \`main\`; \`research/decisions/\`` → New: `\`fw land\` requests (console-api fast-forwards \`main\` in its bare repo); \`research/decisions/\``

**console-builder row.** Old "Spawned when" cell: `M0+ console features (the step queue first, §10.2)` → New: `M0+ console shell and UI features (the step queue first, §10.2); paired on one branch with the \`lean-<module>\` that owns the behaviour, which a TS-only change cannot alter`

**lean-prover row.** Old: `| lean-prover (\`lean-<module>\`) | named worktree subagent (from Day 3) | opus / high; fable per call (ask) for a stuck theorem | 200k | 1h | one Lean module each | \`lean/**\`, golden fixtures |` → New: `| lean-prover (\`lean-<module>\`) | named worktree subagent (from Day 3) | opus / high; fable per call (ask) for a stuck theorem | 200k | 1h | one Lean module each; **up to 3 alive at once** in M0-M2 (console core, queues, ops in parallel), 1-2 afterwards; tools: lean-lsp-mcp, \`grind\` first | \`lean/**\` except \`lean/math.lock.json\`, golden fixtures, mutant patches |`

**Add a row after reviewer:**

| Role | Runs as | Model / effort | cW | Cache TTL | Spawned when | Writes |
|---|---|---|---|---|---|---|
| math-reviewer (`mathrev-<module>`) | subagent, fresh context, read-only | opus / high | 150k | 5m | every stale or unsigned entry in the math view, after `lake build`; a second, independent instance on a disagreement | nothing; its only output is `pnpm fw math:sign` (an event, §5.3) or a disagreement report |

**reviewer row, "Spawned when" cell.** Add: `; the reducer refuses a review signed by the card's owner or any agent that built on it`.

**Concurrency paragraph.** Old: `at most **5 teammates** (spawn-guard) and **8 worktree subagents** alive at once` → New: `at most **5 teammates** (spawn-guard) and **8 worktree subagents** alive at once (up to 3 of them lean-provers in M0-M2)`.

**part-builder file, last paragraph.** Old: `Send your result to the agent you report to; the lead gets at most 300 characters plus a file path, and \`waiting-for: lead|device|user\`. To wait an hour or more, write a handoff note and stop.` → New: `Send your result to the agent you report to; the lead gets at most 300 characters plus a file path. Never write status: the console derives it. Your only console inputs are \`pnpm fw\` requests. To wait an hour or more, write a handoff note and stop.`

## 16. §8.3 `.claude/settings.json`

**`permissions.allow`.** Remove `"Bash(git merge --ff-only *)"` (only console-api fast-forwards `main`). Keep
`"Bash(git rebase main)"`: `main` in each worktree is a read-only mirror that console-api updates.

**`permissions.deny`.** Add:
`"Edit(~/.fw-console/**)", "Write(~/.fw-console/**)", "Read(~/.fw-console/secret/**)", "Edit(/lean/math.lock.json)", "Write(/lean/math.lock.json)", "Edit(/docs/math/**)", "Write(/docs/math/**)", "Edit(/results/console/**)", "Write(/results/console/**)"`

**Add a top-level block:**

```jsonc
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,                         // no dangerouslyDisableSandbox retry
    "filesystem": { "denyWrite": ["~/.fw-console"], "denyRead": ["~/.fw-console/secret"] },
    "network":    { "allowUnixSockets": ["~/.fw-console/run/cli.sock"] }   // the only door: requests
    // never list `pnpm fw` in excludedCommands: fw lives in each worktree and could be edited there
  },
```

**`hooks` block.** Old `SubagentStop` entry (`usage-record.mjs (async) …`) → New: usage comes from console-api's
transcript tailer (an upsert per `message.id`, last record wins); `SubagentStop` runs `emit.mjs` only. Add:

```jsonc
    "SessionStart":  [/* session-brief.mjs (unchanged) + emit.mjs */],
    "SubagentStart": [/* emit.mjs */], "SubagentStop": [/* emit.mjs */], "TeammateIdle": [/* emit.mjs */],
    "PreCompact": [/* emit.mjs */], "PostCompact": [/* emit.mjs */], "StopFailure": [/* emit.mjs */],
    "Notification":  [/* emit.mjs, matcher "permission_prompt|agent_needs_input" */],
    "PostToolUseFailure": [/* emit.mjs, matcher "Bash" */],
    "PreToolUse": [/* spawn-guard.mjs, matcher "Agent", onFailure: block (unchanged);
                     cap.mjs, matcher "Bash", only for `pnpm fw *`: appends the single-use capability via updatedInput */]
    // emit.mjs: synchronous, < 100 ms, prints nothing (a hook's stdout can reach Claude); writes one spool file and exits
```

**Notes list.** Add: `- The sandbox is what makes "agents have no write path" hold for scripts: permission deny rules do not cover a Node or Python process that opens files itself (CONFIRMED, permissions doc). SPK-t checks that worktree agents can still gate, test and commit with zero refusals; the fallback is console-api as a separate macOS user with its state at mode 0700 (Q22).`

## 17. §8.4 Cost reporting

**Forecast bullet.** Old: `Revision 4's Opus use and concurrency should run about 20-40 % above it (INFERRED), with calendar time below the §10.1 days.` → New: `Revision 4's Opus use and concurrency should run about 20-40 % above it (INFERRED), with calendar time below the §10.1 days. Revision 5's Lean-first scope adds about $700-1,100 of lean-prover and math-reviewer work in place of the forecast's $280, mostly in M0-M2, minus roughly $200-300 of console TS work that Lean now does (INFERRED [10.03 §7.1]). The console's push design should remove most of v1's polling cost (v1: 9,042 poll-only turns, 1.87 B context tokens [10.01 §3.2]).`

## 18. §8.5 Coordination rules

**Row "No routing agents", Rule cell.** Old: `Queue order, land queue, device dispatch, check-in digests, card pre-data reads and console first response to status questions are \`pnpm fw\` scripts over \`events.jsonl\`. Only judgement questions wake the lead` → New: `Queue order, land queue, device dispatch, check-in digests and card pre-data reads are \`fwcore\` decisions over \`events.jsonl\`. A status or catch-up question in a thread gets a board-rendered reply with no LLM; recognising the question is only a suggestion, and your "not answered" click escalates to the lead (Q29). Only judgement questions wake the lead`

**Row "Owner state from events".** Old: `| **Owner state from events** | \`fw\` stage commands emit events; the lead reads the projection instead of asking. A hand-back carries \`waiting-for: lead\|device\|user\`; the lead sends one message per hand-back | console-api; \`session-brief\` | 39 "crossed" messages, 55 status nags, 1,334 back-to-back lead sends |` → New: `| **Nobody writes status** | Every status field is derived (§3.2). Stage changes come from evidence events (built, screened, reviewed, swiped, landed); an owner is "waiting" whenever its card's stage is someone else's move. Agents' only console inputs are the typed commands below, each refusable by the Lean reducer; an optional note (≤ 200 characters) is shown but never read by the reducer. The lead reads the projection instead of asking and sends one message per hand-back | sandbox + deny rules (§8.3); the CLI socket's authority table \`may\` and capability check; the reducer (Lean, proved: \`unauthorized_rejected\`, \`only_user_answers\`, \`review_independent\`, \`land_requires\`) | v1: 4,412 hand status writes, 10.9 % of all tool turns on upkeep [10.01]; 39 "crossed" messages, 55 status nags, 1,334 back-to-back lead sends [08] |`

**Add after the §8.5 table: "The judgement commands that remain"** (from [10.01 §5], the one catalogue):

| Who | Commands (each one typed event, refused when invalid) |
|---|---|
| you (console-web only) | step answer / cancel; proposal decision; priority list; session booking; decision answer; best-build pick when more than one candidate remains; thread posts and "answered / not answered" |
| lead | card approve; `fw land` (land request: refused unless the card is land-ready); card drop with an enum reason; lead rulings (`decision.answer` on `decision.requested`); queue move with a reason |
| owner | card open; `fw park --until <typed predicate>`; `fw wait --on agent:<id> --for answer\|review\|artifact`; `fw ask-lead --kind go-ahead\|pick\|sign-off\|other`; hand-back result `landed\|no-gain\|refuted\|blocked`; optional note |
| reviewer | `fw review --sha --accept\|--reject --reasons` (refused if the reviewer owns or built the card, or the sha is not the head) |
| math-reviewer | `fw math:sign <decl>` |
| any agent | `fw screen\|gate\|run\|device` job requests (console-api runs the job and emits the result fact as `script`); kb and bug commands |

**Row "Your attention", Rule cell.** Old: `One question per thread, auto-closed; long topics become pages.` → New: `One question per thread, closed by your "answered" click or a typed close with a reason; long topics become pages.` Also add to the same cell: `A landing that bypassed the console shows as a violation on your needs-you list.`

## 19. §9.2 Experiment stages, gates and signatures

- **review** row, "Signed by" cell. Old: `**reviewer**` → New: `**reviewer** (independent: not the owner, not a builder of the card; enforced by the reducer)`
- **land** row, "Gate" cell. Old: `\`land_requires\` holds (checked in TS in MVP, by \`fwcore stage.step\` later)` → New: `the lead's land request is accepted by the Lean reducer only when the card is ready (\`landReq_ready\`); console-api fast-forwards \`main\` in its bare repo; the git reconciler emits \`landed\`; \`land_requires\` (landed ∧ no violation ⇒ all evidence at the landed commit) holds over every log (proved, M0)`
- **land** row, "Signed by" cell. Old: `**lead** (ff-only)` → New: `**lead** (request); console-api (ff-only merge)`
- Paragraph after the class table. Old: `Every stage change is an event, so the console shows each card's stage, owner, next step and ETA without anyone asking (§8.5).` → New: `Every stage is derived from evidence events keyed by the build commit: a new build sends the card back to screen and voids older screen, review and device evidence (\`built_resets\`). Between device and land the derived state is \`landReady\` (the lead's move). So the console shows each card's stage, owner, next action and ETA without anyone writing it (§8.5).`

## 20. §10.1 Milestones

- **M0** row, Content cell. After `the console step queue` add: `; **the console core in Lean** (\`fwcore serve\`: reducer, authority, steps, landing rule) with console-api as single writer, the observer hooks, the capability hook, the sandbox block and SPK-t; the math-view lint and the first signed entries`. In the spike list, Old `spikes SPK-a…e, i, j, k, l, o, p, q` → New `spikes SPK-a…e, i, j, k, l, o, p, q, t`. Exit criteria: add `; SPK-t passed (or the separate-user fallback set up); the M0 Lean modules signed in the math view; every M0 mutant killed`.
- **M1** row, Content cell. Old `\`fwcore\` MVP modules` → New `the M1 Lean modules (§5.1)`.
- **M4** row, Content cell. Old `**Lean go/no-go from the bug ledger**` → New `**per-module Lean evidence review** (demotion rule, §5.1)`.

## 21. §10.2 The first two weeks

- **Day 1**, Deliverable cell. Add at the end: `Bootstrap \`~/.fw-console/<repo-id>/\` with console-api's bare repo holding \`main\` (agents' worktrees fetch from it). No git-hook emitter: git facts come from the reconciler, which backfills from refs and reflogs when console-api starts.`
- **Day 2**, Deliverable cell. Add: `\`emit.mjs\` and the spool format with unit tests (no socket, full disk, bad payload, < 100 ms, silent stdout).`
- **Day 3**, Deliverable cell. Old: `Commit \`settings.json\` + the first agent files (lead, eng-*, measure-engineer, lean-prover, reviewer, part-builder, console-builder) + the 3 hooks; restart the session; the team starts; SPK-o and SPK-p` → New: `Commit \`settings.json\` (with the sandbox block) + the first agent files (lead, eng-*, measure-engineer, lean-prover, reviewer, math-reviewer, part-builder, console-builder) + the hooks (session-brief, emit, cap, spawn-guard); restart the session; the team starts; SPK-o, SPK-p and **SPK-t**. lean-provers start \`Fw/Console\` (merging \`ConsoleV2.lean\` and \`03-inventory/Auto/Console.lean\`) and \`Fw/Spec/DeviceQueue\``. Who cell: `lead; lean-provers (2) from the afternoon`.
- **Day 4-5**, Deliverable cell. Old: `**Console step queue first** (post, Start, answer, Done, on the §3.2 contract), before any Simulator or phone step asks you anything.` → New: `**Console step queue first** (post, Start, answer, Done, on the §3.2 contract), before any Simulator or phone step asks you anything: console-api as single writer (spool drain, \`events.jsonl\` + snapshots, CLI socket with capability check, git reconciler, SSE) on \`fwcore serve\` with the Lean console core; console-web with derived columns only (stage, owner, next action, age, needs-you) and "why" popovers. Fallback if \`fwcore serve\` is not ready by the end of Day 5: a temporary TS reducer with the same semantics, checked against the Lean one by a replay oracle and deleted by Day 9.` Who cell: add `lean-provers`.
- **Day 6**, Deliverable cell. Add: `the transcript tailer (usage upserts) replaces agent-run usage; the meter check reads from it.`
- **Day 9**, Deliverable cell. Old: `\`fwcore\` MVP: frames, verdict (4v4 + \`land_null_prob\`), flags, cost/\`screen\`;` → New: `\`fwcore\` M0 modules complete and signed (console core, queue, ops, frames, verdict with 4v4 + \`land_null_prob\`); flags and cost/\`screen\` started for M1-M2; round trip re-measured (17.6 vs 141 µs, §3.2);`
- **Day 10**, Deliverable cell. Add: `v1 status history replayed through the v2 reducer (V-t) and the stall/staleness alarm precision (≥ 90 %).`
- Paragraph after the table. Old: `and the three later hooks` → New: `and the later hooks (\`TaskCreated\`/\`TaskCompleted\` observers, \`SubagentStart\` brief)`.

## 22. §11 Risks and mitigations

**R6 row, Mitigation cell.** Old: `Reviewer reads statements against the protocol; \`#guard\` examples from v1 data; no proofs about transcribed engine rules` → New: `Math-reviewer back-translation without the docstring, a second reviewer on disagreement, you on a remaining disagreement (§5.3); deep statement hashes so a definition change marks its theorems stale; \`#guard\` examples from v1 data; mutants (V-r); no proofs about transcribed engine rules. Verification of the kickoff notes found 8 math-translation errors and 4 design faults that compiled fine [10]`

**Add rows:**

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R23 | The uniqueness trap: a stateful Lean loop that reads then writes the state copies the whole map per event (66× slower, MEASURED [10.03 §4.2]) | medium / medium | `modifyGet` in the ~30-line IO loop; `seen` as a `HashSet`; a 100k-event speed budget in `lake test` |
| R24 | A toolchain bump changes statement hashes and marks many math entries stale | high on a bump / low | `mathview accept --toolchain-bump` re-signs only entries whose signature text and machine-made LaTeX are unchanged; one reviewed PR per bump (R11) |
| R25 | The Bash sandbox breaks builds or tests for worktree agents, or the `~` path forms behave differently than documented | medium / medium | SPK-t on Day 3 before the team relies on it; fallback: console-api as a separate macOS user under launchd, state at mode 0700 (a one-time setup by you, Q22) |
| R26 | A fact producer misses events (a hook does not fire, a commit is made with hooks off, `SessionEnd` is cut at 1.5 s) and the console is briefly wrong | high / low | reconcilers re-read git refs, transcripts and artifacts every 2-60 s and are the only git producer; agent end = latest of `SubagentStop` and transcript idle; seen-on-accept keys make re-sends converge (`reorder_converges` to prove) |
| R27 | Role claims on the CLI socket are forged, so a builder reviews its own work or an agent acts as lead | medium / high | the capability hook binds each request to Claude Code's agent identity before acceptance (SPK-t); the reducer refuses a review by the owner or a builder regardless of role (`review_independent`); facts and your decisions can never come from the socket |

## 23. §12 Decisions

**§12.0, add rows:**

| # | Question | Your decision | Applied in |
|---|---|---|---|
| Q12 | Lean scope | **Lean-first** (your requirement of 2026-10-17): every decision, queue and status view that can be proved is an L1 module, by milestone; mutants and a per-module demotion rule replace the M4 go/no-go | §0, §1.2, §3.3, §3.4, §5.1, §10.1, R6 |
| — | Console upkeep | **Nobody writes status** (your requirement of 2026-10-17): every view is derived from the event log; agents have no write path; judgement is a typed command | §0, §2.2, §3.2, §7, §8.3, §8.5, §9.2, §10.2 |
| — | Reading proofs | **You read math, not Lean** (your requirement of 2026-10-17): docstring math, a generated math view, a build gate on unsigned or stale math, a math-reviewer role | §0, §5.3, §5.4, §8.2 |

**§12.1, Old heading `### 12.1 Answer before Monday (1 question)` → New `### 12.1 Answer before Monday (3 questions)`. Add after Q1:**

> **Q22. Sandbox for every agent.** May we turn on the Claude Code Bash sandbox for all agents, strict (no
> unsandboxed retry)? It is what makes "agents cannot write console state" an OS-level guarantee, but it may cause
> some build or test friction until SPK-t passes. The fallback is console-api running as a separate macOS user, which
> needs a one-time setup from you. **Recommend:** yes, with the fallback ready.
>
> **Q23. Where the console lives, and who moves `main`.** Live console state goes to `~/.fw-console/<repo-id>/`,
> outside the repo, with daily exports committed to `results/console/`. `main` lives in a bare repo that console-api
> owns, so agents (and the lead) land only through `fw land`; a landing that bypasses it is shown to you as a
> violation. **Recommend:** yes to both.

**§12.2, Old Q12 line `- **Q12 Lean scope:** MVP modules only (Frames, Verdict, Flags, Cost/screen), Stage/Step later, no engine rules in Lean; the bug ledger decides at M4 whether Lean continues.` → remove (moved to §12.0). Add:**

- **Q24 fwcore as the console brain:** the console's behaviour is written and proved in Lean (`fwcore serve`), and TypeScript only moves data; the alternative is rev 4's TS console with Lean for 4 decisions. Default: Lean.
- **Q25 Math view placement and scope:** a tab in console-web that shows the generated page (also openable on its own); math required on every theorem and on every definition you read, not only on theorems. Default: both.
- **Q26 Lease starvation:** the device lease can be renewed forever today (MEASURED [10.04 §5]). Default: no renewing while someone is waiting, plus a cap on total hold time, with a bounded-wait theorem; alternatives: the cap only, or a fairness assumption stated in the theorem.
- **Q27 Aging step:** a waiting job rises one priority level every A = 300 s, so a spot-check overtakes newly arriving user steps only after about 25 h. Default: a tighter bound, every job starts within 2 h of a booked window that fits it.
- **Q28 Math disagreements:** when the math-reviewer and the judge disagree, a second independent reviewer decides first; you see only what stays unresolved. Alternative: ask you every time.
- **Q29 Status questions in threads:** answered automatically from the board (no agent), with a "not answered" button that escalates to the lead. Default: yes.
- **Q30 Small defaults:** class W cards still need the lead's `fw land` (no auto-land); knowledge-base read receipts (v1: 1,006 acks) are dropped, and "read by" is derived from read events; an ETA, if an agent has one, goes in its note and is shown with its age, never used by the scheduler; the best build is the set of versions no head-to-head comparison beats, and you pick when there is more than one.

## 24. Appendix A (conflicts)

- **A1** row, Resolution cell. Old: `[05]'s rule for decisions that matter; a TS mirror + oracle test only in the browser (the flag resolver); plain bookkeeping in TS (§3.3)` → New: `[05]'s rule, widened by [10.03]: decisions **and** bookkeeping in \`fwcore\` (Lean-first); a TS mirror only in the browser (the flag resolver, tested on its whole domain) (§3.3)`. Why cell: Old `One implementation; no Lean round trip for a set difference` → New `One implementation; the round trip costs microseconds, and v1's failures were in the bookkeeping`.
- **A9** row. Old Resolution: `v2's question → … → land (§9); proved later (Stage/Step), checked in TS in MVP` → New: `v2's question → … → land (§9), derived from evidence keyed by commit and proved in M0 (\`Fw/Console\`); [05]'s R/I/D/F/V/L cards become sections of \`card.md\`, not stage transitions`.
- **A14** row, Resolution cell, add: `; an L1 checker accepts the coefficients (non-negative, exact fractions) before deployment`.
- **Add rows:**

| # | Conflict | Resolution | Why |
|---|---|---|---|
| A17 | **Three stage models.** [10.01] stage cards closed by judgement; [10.02] stages derived from evidence; [10.03] a third list | [10.02]'s evidence-derived `Stage`, used by every module | No stage command to forget; a rebuild voids old evidence by itself |
| A18 | **Three manual-input catalogues.** [10.01 §5], [10.02 §5] (13 inputs), [10.03] (`note` events) | One catalogue (§8.5, from [10.01 §5]) | One list to enforce in the `may` table |
| A19 | **Numbers that differ across the notes** | The canonical table in this delta ("Canonical numbers") | Each figure has one command |
| A20 | **Math sync.** [10.02] `math:` lines + regenerated `MATH.md`; [10.03] `#math_doc` tags; [10.04] deep hash + lock + reviewer | [10.04] (§5.3), with the sign-off as an event | The other two passed a retag alone, missed definition bodies or skipped imported modules (MEASURED) |
| A21 | **Who lands.** Rev 4: the lead runs `git merge --ff-only`. [10.02]: console-api merges in its own bare repo | console-api, on the lead's `fw land` request | Agents can write a shared `.git` from a worktree; only a repo outside it makes `main` unwritable |

## 25. Appendix B (spikes)

**Add rows:**

| Spike | Question | Status before running |
|---|---|---|
| SPK-t | With the sandbox on (`allowUnsandboxedCommands: false`, `allowUnixSockets` = the CLI socket, `denyWrite` = `~/.fw-console`): (a) a named worktree subagent can run `pnpm fw gate`, the tests and `git commit` with zero refusals (with SPK-o); (b) `node -e "fs.appendFileSync(<state>/events.jsonl,'x')"` from that agent fails; (c) the Write tool there is denied; (d) `pnpm fw screen` reaches the socket; (e) `git update-ref refs/heads/main …` and `git branch -f main` against console-api's bare repo fail from a sandboxed worktree; (f) the capability hook adds `--cap`, and console-api refuses a missing, wrong or reused capability; (g) `emit.mjs` finishes in < 100 ms and prints nothing | the doc facts are CONFIRMED (sandbox scope, child processes, the shared-`.git` exception, `~` paths, hooks outside the sandbox, `updatedInput`); the combination is open; Day 3 |
| SPK-u | Hermetic dependency recording: can a measurement plugin's run record the files and env it actually read (e.g. `fs` tracing in Node, `sandbox-exec` read logs), so that "declared deps ⊇ actual reads" is checked for artifact keys? | open; M1, with the artifact store |

## 26. Appendix D (review log): add "Revision 5"

> ### Revision 5 (your requirements of 2026-10-17: automated console, Lean-first, math view)
>
> Source: [10] (`research/kickoff/10-automation-and-proof/README.md`) and its notes 01-04, after an independent
> verification pass that found and fixed 4 design faults (seen keys on refused events; refusable git landings;
> forgeable reviews; head-of-line blocking in the phone queue), 8 math-translation errors, a sync check that did not
> sync, and number clashes across the notes.
>
> | # | Change | Where |
> |---|---|---|
> | 1 | Nobody writes status: every console field is derived; agents have no write path (sandbox, deny rules, state outside the repo, `main` in console-api's bare repo); one catalogue of typed judgement commands | §0, §2.2, §3.2, §3.4, §7, §8.3, §8.5, §9.2, §12.0 |
> | 2 | Facts are observed: one synchronous observer emitter, a capability hook, git facts from the reconciler only, usage from a transcript tailer; keys separate identity from version | §3.2, §3.4, §8.3, §10.2 |
> | 3 | Lean-first: 87-item inventory at L1 / L1-cond / L2 / L3; `fwcore serve` holds the console state; modules by milestone; mutants (V-r); per-module ledger and demotion rule replace the M4 go/no-go | §0, §1.2, §3.3, §3.4, §5.1, §5.2, §10.1, §12 |
> | 4 | Math view: docstring LaTeX, `lake exe mathview` generator, MathML page, deep statement hashes, lint in TL0, sign-off as an event by the math-reviewer role (V-s) | §5.3, §5.4, §7.1, §8.2 |
> | 5 | Roster: math-reviewer added; up to 3 lean-provers in M0-M2; console-builder paired with lean-provers; the lead requests landings | §8.2, §8.4 |
> | 6 | Spikes SPK-t (sandbox, socket, bare repo, capability) and SPK-u (hermetic deps); risks R23-R27; questions Q22-Q30 | Appendix B, §11, §12 |

---

## Canonical numbers (resolves the disagreements between notes 01, 02 and 03)

Each figure has one command. "v1" = `../fastwork-com-web-optimize` @ eae1bb99 (read-only);
`$M` = `$V1/.git/fastwork-mirror`; `$RAW` = the v1 transcripts. All MEASURED.

| Quantity | Canonical value | Command / source | Other values in the notes, and why |
|---|---|---|---|
| v1 `status.mjs set` Bash calls | **4,914** | over 105,638 unique Bash tool-use ids: `grep -Ec 'status\.mjs set' v1-bash.jsonl` ([10.03 §9]) | 4,982 (4,992 on a re-run) = `set\|priority\|seed\|sync` ([10.01] Appendix B regex); 2,754 = a **subset** ([10.02]'s regex needs the path in the first 40 characters) |
| Status-board history | **4,412 entries on 299 rows** | `$M/status/*.json`, `python3 -I scripts/status_hist.py $M` ([10.01]) | 4,384 on 296 = the committed export `console/status.json`, an older copy; 8 rows hit the 100-entry cap, so the true total is a little higher |
| Step part acks | **252 ack entries over 166 steps, 6 with a null state** | `jq -r '[.history[]?.action // empty] \| .[]' console/steps/C-*.json \| sort \| uniq -c` ([10.02 §1]) | 246 = the acks with a non-null state ([10.01]) |
| Entries carrying `note` or `next` | **4,140** (865 carry nothing else) | `jq '[.[].history[]\|select(.changes\|(has("note") or has("next")))]\|length' console/status.json` | 6,110 = the two field counts added, double-counting entries with both |
| Upkeep turns | **13,279 of 121,286 tool turns (10.9 %), 2.69 B context tokens**; without blocking waits **12,779 and 2.59 B**; poll-only **9,042 turns, 1.87 B** | `scripts/scan.py`, `agg2.py`, `agg3.py` ([10.01 §3.2]) | an independent re-implementation gave 14,661 of 121,724 (12.0 %), the same order; the push saving is ≈ 1.8 B, not 1.94 B (waits are not polls) |
| Status writes derivable | **19 % from v1 events, 37 % with one new v2 event, 44 % judgement** | [10.01 §3.3] | 33 / 29 / 38 before verification (the hold cross-check had no control class; 290 "waiting on lead" writes were rulings) |
| "Waiting on lead" values | **599: land 307, decision 38, review 28, other 226** | the `jq` command in [10.01 §3.3] | 596 = the first-match classifier's class size |
| Measuring writes inside a logged hold | **131 of 701 (19 %)**, control 20 of 537 (4 %) | `python3 -I scripts/holds_strict.py $M` | 575 of 701 = a ±30 min window that also matched 75 % of judgement-class writes |
| Node → `fwcore` round trip | **17.6 µs** | `node bench-roundtrip.mjs ./.lake/build/bin/autobench events100k.jsonl` ([10.03 §9]) | ≈141 µs in [05 §1], same method (child_process + readline), different binary and payload; not explained; re-measured on Day 9 |
| 100k-event replay | **0.28-0.29 s** warm | `/usr/bin/time -p ./.lake/build/bin/autobench < events100k.jsonl` ([10.03]) | 0.41-0.54 s on the verification re-run; 19.2 s with get-then-set (R23) |
| Cache-write split vs API total | **2 of 248,672 records disagree** | the `jq` command in [10.03 §9] | — (why op.3 defines the total instead of claiming an equality) |

## Questions for you (new in revision 5)

Before Monday: **Q22** (sandbox for every agent), **Q23** (console state outside the repo; `main` in a console-owned
bare repo). Defaults unless you object: **Q24** (Lean console brain), **Q25** (math view as a console tab; math on
definitions too), **Q26** (lease starvation fix), **Q27** (aging bound), **Q28** (who breaks math-review ties),
**Q29** (automatic status replies), **Q30** (no auto-land for class W; drop kb acks; ETA only in notes; you pick the
best build among undominated candidates).
