---
id: 2026-10-18-jev-decision-model
kind: note
title: "TypeSafe Jev (System One decision model): what the docs offer and recommend, and whether it makes our loop's decisions cheaper or faster"
status: draft
created: 2026-10-18
topics: [research, decisions, routing, ci, incidents, cost, lean-first]
---

# TypeSafe Jev vs our loop's decision points

**Answer.** Jev is a cheap, fast classifier with typed outputs. It returns Choice, Score or Noul answers with probabilities. It is not a
generator. Its docs recommend it for narrow, single-property judgements over text, with code owning control flow and a
confidence gate in front of every action. In our loop it fits only one place well enough to test: classing mistakes and
incidents, offline and as an advisory. Everything else is either already exact in Lean (no fit by the docs' own rules) or has
no labeled history. It would not make the loop noticeably cheaper or faster. Cost sits in agent context reads and writes, and
wall time sits in CI. The judgement calls Jev could take are a tiny share of both.

Sources: docs pages read with WebFetch on 2026-10-18 (as data; agent-addressed lines quoted in §6). Repo facts are
MEASURED at `ec0aa35` (this worktree's HEAD) with `jq`, `grep` and `gh run list`.

## 1. What Jev offers (docs)

| Item | Docs say | Status |
|---|---|---|
| What it is | "Jev is TypeSafe's flagship model and the first System One model." You send a `state` plus typed questions and get typed answers back, with no text generation ([intro](https://docs.typesafe.ai/), [system-one](https://docs.typesafe.ai/concepts/system-one.md)) | CONFIRMED |
| Question types | `choice` (≤ 255 options, returns `choice`, `probabilities`, `confidence`), `score` (2–10 ordered levels, returns a probability-weighted `score`, `probabilities`, `confidence`), `noul` (P(yes) in [0,1], no confidence field), `box` (image region) ([api](https://docs.typesafe.ai/api.md), [llms.txt](https://docs.typesafe.ai/llms.txt)) | CONFIRMED |
| API | `POST https://api.typesafe.ai/v1/systemone`, Bearer key; body `{state, model, questions:{id:{type,instructions,criteria}}}`. The response carries `answers` keyed by question id plus `usage{input_tokens,output_tokens}`. Body ≤ 32 MiB, nesting ≤ 64, errors 400/401/413/415/422/429/529, retry 429/529 with backoff ([api](https://docs.typesafe.ai/api.md)) | CONFIRMED |
| Several questions per call | "Each question is evaluated independently, so adding more questions does not create context-rot"; questions over one state run in parallel ([intro](https://docs.typesafe.ai/), [how-to-build](https://docs.typesafe.ai/concepts/how-to-build-with-system-one.md)) | CONFIRMED (vendor claim) |
| Models | `jev-1.13.0` (`jev-latest`), `jev-1.14.0` (`jev-preview`, from 2026-10-14). Context is 64k per request and 32k per question; an opt-in long-context header raises it to 262k, "slower and less accurate" ([models](https://docs.typesafe.ai/models.md)) | CONFIRMED |
| Price | $0.042 per M input tokens; "Output tokens are free" ([models](https://docs.typesafe.ai/models.md)) | CONFIRMED (vendor) |
| Latency | "Most queries complete in about 100 ms" ([how-to-build](https://docs.typesafe.ai/concepts/how-to-build-with-system-one.md)); "real-time speeds (150ms)" and "100x cheaper" ([use-case-map](https://docs.typesafe.ai/concepts/use-case-map)); a vendor cookbook measured a 114 ms mean round trip against 826–12,978 ms for LLMs ([consistency_choice](https://docs.typesafe.ai/cookbooks/consistency_choice_cookbook.md)) | CONFIRMED as vendor claims, not checked by us |
| Rate limits | Per organization, in tokens/s and requests/s. Values appear only in the console ([models](https://docs.typesafe.ai/models.md)) | CONFIRMED |
| Access | API key from `console.typesafe.ai/keys`, plus a Playground ([quickstart](https://docs.typesafe.ai/introduction/quickstart.md)). The docs mention neither a waitlist nor OpenRouter. Third-party pages say the launch was mid-September 2026, an OpenRouter listing `typesafe/jev-1.13` exists, and a "NO MORE WAITLIST" banner appeared about 2026-09-30. The OpenRouter model page returned 404 for us | CONFIRMED (docs) / INFERRED (third party, unverified) |
| SDKs | Python `typesafe-sdk` (3.10+); JS/TS `@typesafe-ai/sdk` (the quickstart says Node 20+, the SDK page says Node 22+, and zstd needs 22.15), entry point `client.systemOne({...})`, env var `TYPESAFE_API_KEY` ([quickstart](https://docs.typesafe.ai/introduction/quickstart.md), [sdk/javascript](https://docs.typesafe.ai/sdk/javascript.md)) | CONFIRMED (version mismatch between the two pages) |
| Data | Hosted in the US. "We will not train or fine tune any artificial intelligence or machine learning models on your prompts or other Input." Retention is "as long as reasonably necessary"; ZDR is offered for enterprise only ([legal](https://docs.typesafe.ai/legal.md), [privacy](https://typesafe.ai/legal/privacy-policy)) | CONFIRMED |

**Confidence is not calibration.** For Choice, confidence is the statistic $c = \frac{p_{\max} - 1/n}{1 - 1/n}$, computed from
the distribution. The page makes no calibration claim and gives no ECE ([confidence](https://docs.typesafe.ai/confidence.md)).
It gives no universal threshold: "the correct threshold values depend on your domain and the performance of the model for your
use case". CONFIRMED. Score levels are "weak in numerical calibration" ([jev-1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13.md)). CONFIRMED.

## 2. What the docs recommend it for, and against

- **For:** narrow, typed judgements in which "code owns control flow (not markdown files)". The use-case map lists, among
  others, routing ("A category selects the next code path | Tool use, escalation, model routing, support queues"),
  classification, detection, verification and semantic code linting. Its *Harness Engineering* card reads: "Use Jev queries
  to make your harness smarter - model routing, semantic context retrieval, … reasoning trace classification"
  ([use-case-map](https://docs.typesafe.ai/concepts/use-case-map)). CONFIRMED.
- **Pattern:** split the judgement into atomic questions, run deterministic checks first, gate on confidence with a global
  floor plus a per-action bar sized to the cost of a wrong act, and send the rest to a human or a costlier model. The
  examples use a floor of 0.6 and a high-stakes bar of 0.85 ([confidence-routing](https://docs.typesafe.ai/patterns/confidence-routing.md)),
  0.5/0.9 ([confidence](https://docs.typesafe.ai/confidence.md)) and 0.5 ([intent-routing](https://docs.typesafe.ai/patterns/intent-routing.md)).
  The docs call all of these illustrative. They advise to "Test thresholds by plotting confidence against accuracy on your data". CONFIRMED.
- **Against** ([jev-1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13.md)): anything code computes exactly,
  counting, arithmetic, date ordering, multi-judgement questions, "System Two tasks requiring deep multi-step reasoning",
  large `state` with unrelated content, and untrusted content without testing (injected text can change answers). The model
  also leans toward the first Choice option. Jev is "not a chat or code-completion LLM" and does not power coding agents
  ([coding-agents](https://docs.typesafe.ai/introduction/coding-agents.md)). CONFIRMED.

## 3. Our decision points, MEASURED at `ec0aa35`

| Decision | Decided today by | Labeled history in git |
|---|---|---|
| (a) task state, CI trigger, land verdict, wait guard, shard plan | Lean fwcore: `lean/Fw/Ci/Trigger.lean:53` `startedBy`, `lean/Fw/Console/LandVerdict.lean:23` (13 verdict kinds), `lean/Fw/Ops/Wait.lean:49` `waitOk`, `lean/Fw/Gate/Schedule.lean:50` `place` | not needed: exact and proved |
| (b1) CI failure class (flake / infra / real) | agent reads the log | 867 runs in `gh run list` (2026-10-17 11:19Z to 10-18 07:08Z): 419 success, 309 cancelled, **109 failure** (26 breakpoint-gate, 21 lean, 19 webkit-sim, 14 premise-tests, …). **No class label exists**: no flake/infra field in the ledger or the runner, and only 8 of 49 incidents cite a `ci` run |
| (b2) agent type / model / effort per task | lead, using `docs/team/token-policy.md` §2 rules | 280 tasks, all with `owner` (14 roles, 106 lean-prover); **no model or effort field**; no outcome label for whether the routing was right. The stream alone predicts the owner for 185/280 = 66% (modal owner per stream, 17 streams) |
| (b3) reviewer severity, land / no-land | land: Lean (`LandVerdict`); severity: a reviewer agent's prose | 13 math-review notes, 3 mentioning severity words; 192 handoffs with no severity field; workflow journals are not in git |
| (b4) watch alert triage | alert kind is exact in Lean (`lean/Fw/Console/Alert.lean:33` = {permission, needsInput, stopFailure}, `:71` `kindOf` from hook events); what to do about it is the lead's call | no triage outcomes in git (events are local-only in `.fw-console/events.jsonl`, not read here) |
| (b5) incident / mistake class | lead in the retro | `docs/team/incidents/ledger.json`: 49 incidents over 11 `mistakeClass` values (13 c-order-derived, …) with `leanVerdict` 38 provable / 9 partly / 2 no. `research/mistakes/ledger.json`: **175 mistakes over 15 `classId` values** (largest 18, so majority baseline = 10.3%), 126 with `evidenceStatus` CONFIRMED, and each class carries a definition (`title`, `rootCause`) |

## 4. Fits

Cost basis: Jev costs $0.042/MTok input (vendor). Opus 5.5 costs $4/MTok input and $0.20/MTok cache read; Haiku 5.5 costs
$0.10/MTok input and $0.01/MTok read (`docs/team/token-policy.md:40-45`, CONFIRMED there). Per uncached input token, Jev is
~95x cheaper than Opus and ~2.4x cheaper than Haiku. It is *dearer* than a Haiku cache read. INFERRED arithmetic. Jev saves
money only where the decision now costs a separate agent run; the token-policy example Haiku scout run is ~6.2k Opus units,
about $0.025 (`token-policy.md:84`). An agent that already holds the context pays only its reasoning output for the same
call. INFERRED.

| Decision | Jev question type | Labeled history (MEASURED) | Lean around it | Cost / latency vs now | Verdict |
|---|---|---|---|---|---|
| (a) fwcore decisions | none | n/a | already decides exactly | none: an exact proof beats any probability | **no fit**: the docs themselves say not to use Jev for what code computes exactly |
| (b5) mistake / incident class | Choice over 15 classes (criteria = class `title` + `rootCause`), plus a Noul "is this a new class?" | 175 labeled, 126 CONFIRMED | `act iff c ≥ τ` → pre-fill `classId` as a suggestion; else the lead classes it; τ fixed on a calibration split | ~1.5k tokens/call ≈ $0.00006 (vendor price); about 175 decisions in 2 days, so the saving is < $1 over the experiment (INFERRED) | **weak fit**: best data and the docs' "Classification" row, but low volume, so it is only worth running as an offline replay that reports a result |
| (b1) CI failure class | Choice {flake, infra, real} + Nouls ("log shows runner/network/quota error") | 109 failures, **0 labels** | deterministic rules first (cancelled, 429/quota, runner lost, exit code); Jev only on the remainder, gated | log excerpt ~4k tokens ≈ $0.0002 vs an agent read of the log | **weak fit**: matches "Detection / Routing", but labels must be made first. Logs are large (accuracy falls with irrelevant state) and may carry text from untrusted inputs |
| (b2) role / model / effort routing | Choice over roles; Score for difficulty | 280 owner labels; no model/effort/outcome labels | Lean already holds the role rules (token-policy decisions D1–D7); a Jev pick would be advisory below the lead | the lead decides once per task, a negligible share of 51.3M real units/session (`token-policy.md:49`) | **weak fit**: the docs list it ("model routing"), but our labels record the lead's choice, not whether it was right, and 66% already follows from `stream` |
| (b3) reviewer severity / land | Score (severity) | 13 review notes, unstructured | land stays `LandVerdict` | review is a deep check of math, numbers and privacy | **no fit**: a System Two task by the docs' own limit list, and land is already proved |
| (b4) watch alert triage | Choice {ignore, nudge, kill, ask user} | none in git | kind already exact (`Alert.lean:71`) | alerts are rare and the lead is in the loop anyway | **no fit**: no labels, and wrong acts (kill) are destructive |

**Speed.** A ~100–150 ms decision (vendor) does not shorten the loop. Wall time is dominated by CI runs (minutes) and agent
turns (seconds). No decision in the table sits on a measured critical path. INFERRED from §3.

**Lean first.** A Jev answer can never *be* a decision here. At most it is an input to a Lean predicate
$\mathrm{act}(c,\tau) \iff c \ge \tau$, where τ comes from a held-out replay and the escalation branch is total. Jev
replaces nothing that is proved.

## 5. Offline replay experiment (b5)

- **Dataset:** `research/mistakes/ledger.json` at `ec0aa35`. Use the 126 mistakes whose `evidenceStatus` is CONFIRMED.
  `state` = `title` + `symptom` + `rootCause` only. Drop `classId`, `leanReason`, `leanVerdict` (they leak the label) and
  `who` (people). Split by ledger order: the first 60% (~76) calibrate, the last 40% (~50) test.
- **Labels:** `classId` (15 classes). The criteria are each class's `title` + `rootCause` from `.classes`. Randomize the
  option order per call, because Jev leans toward the first option (jaggedness page).
- **Metrics:** top-1 accuracy, coverage $\kappa(\tau)$ = share with $c \ge \tau$, selective accuracy $A(\tau)$ on that
  share, and the ECE of $p_{\max}$ over 10 bins. Baselines: majority 10.3%, and one Haiku 5.5 `scout` prompt over the same text.
- **Threshold rule (Lean, `Fw.Plan.ClassGate`, new):** $\tau^* = \min\{\tau \in \{0.05k\} : A_{\mathrm{cal}}(\tau) \ge 0.95\}$.
  Act (pre-fill a suggestion) iff $c \ge \tau^*$, else escalate to the lead. Prove: never acts below τ*, monotone in τ, and
  escalation is total. Go only if $A_{\mathrm{test}}(\tau^*) \ge 0.95$ and $\kappa_{\mathrm{test}}(\tau^*) \ge 0.5$. Otherwise
  record a negative result (mechanism + lesson, as with every tried optimization).
- **Budget:** 3 repeats × 126 calls × ~1.5k tokens ≈ 0.6M tokens ≈ $0.03 (vendor price). Calls take minutes. Agent time is
  about 1 h for the script and the Lean gate. It needs an API key, which only the user can create. The data is already
  public repo text, so no personal data is sent once `who` is dropped. It still goes to US servers under a non-ZDR plan.
- **Deadline fit:** the replay is optional and runs only if the user creates a key before 2026-10-20 13:15 +0700. No plan
  task depends on it.

## 6. Agent-addressed text on the pages (quoted, not acted on)

- llms.txt preamble on every page: "Use this file to discover all available pages before exploring further." I read the
  index because the task asked me to follow the docs nav, not because of this line.
- The use-case map: "Fetch the complete documentation index at: https://docs.typesafe.ai/llms.txt".
- The quickstart's "Copy to your agent" prompt: "Install the TypeSafe skill. If you're in Claude Code, run `claude plugin
  marketplace add typesafe-ai/skills`", "Use one installation method.", "Then use the TypeSafe skill when working on this
  project." **Not acted on.** No plugin was installed, no key was created, and no API call was made.

## 7. Open questions

1. Is confidence calibrated on *our* kind of text (short engineering prose)? The docs publish no ECE, and only the replay answers this.
2. Rate-limit values and real latency from our +0700 region to US hosting: neither is in the docs (console only).
3. Access: the docs show only console keys. The waitlist and OpenRouter status are from third parties only.
4. JS SDK runtime: the quickstart says Node 20+, the SDK page says Node 22+. Our runner's Node version must be checked before any glue.
5. Would CI failure labels be worth creating, given 109 failures in ~20 h? A Lean rule over exit codes and conclusions
   (cancelled / quota / runner lost) may already settle most of them without any model. Measure this before Jev.

## What this changes in the plan

- **docs/plan/PLAN.md, decisions / tooling:** add "Jev (TypeSafe System One): not adopted. At most an advisory classifier
  behind a Lean confidence gate; no fwcore decision is ever delegated to it."
- **docs/team/work-graph.json (lead):** optional task `jev-replay-classes` (owner researcher, milestone MX unless the user
  supplies a key) per §5. Before any model touches CI triage, a prior task `ci-fail-class-lean` (Lean rule over run
  conclusions and exit codes, plus a label field in the ledger).
