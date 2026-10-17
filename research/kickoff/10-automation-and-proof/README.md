---
id: 2026-10-17-automation-and-proof
kind: note
title: "Automated console, Lean-first scope, and a math view you can read (summary of notes 10/01-04)"
status: review
created: 2026-10-17
updated: 2026-10-17
authors: [agent:automation-proof-synthesis]
topics: [console, events, lean, math-view, automation]
links:
  plan: docs/plan/PLAN.md (rev 4; not edited) · docs/plan/rev5-delta.md (the changes for rev 5)
  notes: [01-v1-console-manual-work.md, 02-event-automation-design.md, 03-lean-everywhere-inventory.md, 04-lean-to-math.md]
  scratch: lean-scratch/{01-v1console, 02-events, 03-inventory, 04-mathview} · scripts/ (v1 counts)
---

# Automated console, Lean-first scope, and a math view

**Your three asks (2026-10-17):** (1) v1's agents had to update the console by hand; automate it. (2) Prove as much as
possible in Lean. (3) You do not read Lean, so show the theorems as math, kept in sync with the Lean. This page sums up
notes 01-04 after their verification pass. CONFIRMED = checked against a source; MEASURED = run here, command in the
note; INFERRED = a design choice still to be checked.

## 1. The automated console: nobody writes status

**Why.** In v1, 10.9 % of all tool turns (13,279 of 121,286) did nothing but console upkeep: writing board state or
polling it (MEASURED, 01 §1.1; 12,779 turns without blocking waits). 56 % of the 4,412 status-board writes recorded
something a machine knew or will know in v2 (19 % from events v1 already had, 37 % with one new v2 event); 44 % were
real judgement (01 §3.3, corrected). At least 22 incidents and 7 of your comments were about a stale or unclear board.

**Design** (02, with the verification fixes):

| Piece | What it does |
|---|---|
| One writer, one log | console-api is the only process that appends to `events.jsonl`. Every view (stage, owner, next action, ETA, needs-you, staleness) is a formula over the log: `view = f(π(log))`, with `π` a left fold of the reducer. |
| The reducer is Lean | `apply : State × Event → State` and the views run in `fwcore serve`, a long-lived Lean process. 100k events replay in about 0.3-0.5 s (MEASURED, 03 §4.2). |
| Facts are observed, not reported | git refs (console-api's reconciler; git hooks run inside the agent's sandbox, so they are not producers), Claude Code hooks (one synchronous, silent, spool-only emitter), file and device watchers, transcript tailing, and console-api's own jobs (screen, gate, device). An agent cannot assert a fact; it can only do the real thing. |
| Agents send requests | `pnpm fw` sends typed requests to a socket. A PreToolUse hook attaches a one-time capability that ties the request to the agent's Claude Code identity. The reducer accepts or refuses each one (refusal reason shown at once). |
| No write path | Live state lives outside the repo and outside `.git` (`~/.fw-console/<repo-id>/`), behind the Bash sandbox (`denyWrite`) and Edit/Write deny rules. `main` lives in a bare repo that console-api owns, so an agent cannot move it; it lands only through `fw land`. Spike SPK-t checks all of this. |
| Judgement that remains | one catalogue of 23 typed commands (01 §5): yours (step answers, decisions, priority list, bookings, best-build pick), the lead's (approve, land request, drop, rulings), owners' (card open, park with a typed predicate, wait on an agent, ask the lead, hand-back result) and the reviewer's verdict. An optional note of at most 200 characters is shown but never read by the reducer. |

**What is proved about it** (`lean-scratch/02-events/ConsoleV2.lean`, MEASURED: builds on Lean 4.35.0, 18 theorems,
7 build-time examples, no `sorry`). In words:
- A fact seen twice counts once: δ(δ(s,e),e) = δ(s,e). A refused event changes nothing at all, so a fact that arrived
  too early is applied when it is re-sent (the first sketch got this wrong; verification found it).
- Only you can answer a step. An actor can only cause what the authority table allows.
- In every state any log can produce: a card landed **without a violation** had approval, a passing screen, an
  independent review and (if needed) a device verdict, all at the landed commit. A landing that skipped the console
  is still recorded, flagged as a violation, and put on your needs-you list.
- The recorded reviewer neither owns the card nor built on it.
- A row with a live wait is never stale; a stale row stays stale until an event touches it.

Not proved, and named as such: that hooks fire, that git and the transcripts are read completely, and that the
capability hook identifies agents correctly. Those are tested premises (L3, below).

## 2. Lean-first scope

Rev 4 proves 4 modules (Frames, Verdict, Flags, Cost/screen) and decides at M4 whether Lean continues. Note 03 lists
**87 decisions, state machines and pure functions** in the v2 design and puts each at one of three levels:

| Level | Count | Meaning | Examples |
|---|---|---|---|
| **L1-pure** | 54 | Implemented and proved in Lean, run through `fwcore`; inputs are the console's own events, ids and counts. The theorem is the whole guarantee | console reducer, steps, needs-you, replay; phone queue (priority with aging, no starvation, one job at a time, no head-of-line blocking); verdict and its 1/70 null rate; flags; budgets; bug-ledger tally |
| **L1-conditional** | 30 | Proved in Lean, but its real-world meaning also needs a named L3 premise | screening (counts are right), landing rule ("card complete" is judgement), review independence (identity), artifact invalidation (declared dependencies are complete), spawn-guard (every spawn passes the hook), usage meter (transcript data) |
| **L2** | 3 | Lean spec plus a TS copy kept equal by tests | the browser's flag resolver (checked on its **whole** finite domain), JSON wire codecs, console-web's optimistic preview |
| **L3** | 18 categories | Cannot be proved; each says how it is checked instead | engine behaviour, work counts, coefficient fitting, run independence, sha256, pixels, the React parts, IO, YAML/CSS parsing, human and LLM judgement, UI, speed, the clock, completeness of observation, actor identity, completeness of declared dependencies, "answered / complete" judgements |

**Rollout:** the console core, the phone queue, the hooks' decisions and the math-view gate are proved in M0; the
rest by milestone (03 §7.1). Each L1 module ships with **mutants**, v1 bugs put back on purpose, which must break the
build (100 % kill rate), and the bug ledger records per module what caught each bug. A module that costs more than one
agent-day on two consecutive changes while catching nothing moves to L2 by a decision record. This replaces the
all-or-nothing go/no-go at M4. Cost: Lean work rises to about $700-1,100, mostly in M0-M2, partly offset by TS
console work that Lean now does (INFERRED).

Verification also fixed four places where an earlier sketch or comment claimed more than its theorem: the phone
queue's head-of-line blocking (fixed and re-proved), the lease's "no starvation" (false today: a holder can renew
forever; needs your choice of fix), the review gate (forgeable in the first sketch), and git landings (could be
refused by the first sketch while `main` already had them).

## 3. The math view: you review math, not Lean

**Pipeline** (04 §2, MEASURED prototype on Lean 4.35.0):
1. **The math lives in the Lean docstring**: one English sentence and one `$$…$$` LaTeX block per theorem *and* per
   definition you read. Example (04 §4.1):

   $$\forall dt \in \mathbb{N}:\quad \operatorname{tick}(dt) \ge 5 \iff dt \ge 37\,500$$

   "A frame counts as at least 5 ticks exactly when it lasts at least 37.5 ms."
2. **A generator** (`lake exe mathview`) walks every `Fw` module of the compiled project and exports, per declaration:
   the docstring math, the English line, the Lean signature, a machine-made LaTeX form of the Lean statement (no LLM),
   whether it is proved or uses `sorry`, the axioms, and a **deep hash**: the statement plus the bodies of every `Fw`
   definition it reaches. Changing `minRuns := 3` to `4` changes the hash of `better_needs_runs` although its printed
   statement is identical (MEASURED).
3. **A lint fails the build** when a declaration has no math, uses `sorry`, its deep hash differs from the signed-off
   hash (the Lean or a definition it uses changed), its math text changed without review, KaTeX cannot parse it, or it
   uses an axiom beyond the standard three.
4. **Sign-off is a separate role.** A math-reviewer agent sees only the Lean statement, the machine-made math and the
   definitions (not the docstring), writes its own math, and compares it clause by clause with a checklist (ℕ vs ℤ,
   every hypothesis, ≤ vs <, rounding down, empty lists, ties, repeats, override order, which direction of ⇔ is
   proved). Only this role (or you, in the console) can write the sign-off file. An agent that edits a theorem cannot
   re-sign it. A disagreement comes to you with both versions side by side; that is the only time you are asked.
5. **The page** is generated on every build: math first, English under it, status chips (proved / sorry, signed /
   stale), the Lean collapsed for reviewers. Formulas are rendered by KaTeX as **MathML**, which browsers draw
   natively, so the page needs no external stylesheet or font. Sample: `math-view-sample.html`.

**Why this shape.** The first sync check (03's `#math_doc`) was shown not to keep math and Lean in sync: a retag
alone passed, definition bodies were not hashed, and imported modules were skipped (MEASURED). Note 04 translated all
70 declarations of the current sketch to exact math; an independent verification pass then corrected 8 places in
those translations (for example the stage `advance` cases now say "first match wins" with complete conditions, and an
"unknown variant gives the error" claim was narrowed to "only if it is the last request for its part"). That is the reason
review is a gated role and not a courtesy.

## 4. Where the details are

| Topic | Note |
|---|---|
| v1 forensics: how much hand-kept state, the catalogue, the 23 judgement commands | `01-v1-console-manual-work.md`; scripts in `scripts/` |
| Event producers, keys, reducer, failure modes, enforcement, day plan | `02-event-automation-design.md`; `lean-scratch/02-events/ConsoleV2.lean` |
| The 87-item inventory, L1/L2/L3, `fwcore` as the console brain, rollout, mutants | `03-lean-everywhere-inventory.md`; `lean-scratch/03-inventory/` |
| Every `Fw/Spec` declaration as math, the math-view pipeline, gaps G1-G7 | `04-lean-to-math.md`; `math-view-sample.html`; `lean-scratch/04-mathview/` |
| The exact plan changes for revision 5 | `docs/plan/rev5-delta.md` |
