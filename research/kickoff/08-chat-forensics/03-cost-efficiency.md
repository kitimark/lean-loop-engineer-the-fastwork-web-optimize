# 08-03. Chat forensics: what v1's tokens bought, and what v2's budget gets wrong

2026-10-17. Part of kickoff note 08 (forensics of v1's raw chat transcripts). Lens: token cost and efficiency.
Input for `docs/plan/PLAN.md` §8 (agent teams) and §8.4 (token budget).

**Sources.** The v1 transcripts (10 lead sessions and 838 subagent/teammate transcripts under
`~/.claude/projects/<v1-project>/`, read-only), the pre-extracted digest in `.local/v1-chat-digest/out`
(`agents.json`, written "digest" below), `v1:fixes/BEST_BUILDS.md` and `v1:` git history. No Fastwork code and no
personal data is copied. The user is "the user".

**Status words.** **MEASURED**: computed from the data by the command shown. **QUOTED**: text from a transcript or a
v1 file. **INFERRED**: my reading, an estimate or a recommendation; not checked.

**Reproducing.** Every number comes from one of three commands, all run in the digest directory
(`.local/v1-chat-digest/out`):
1. `node ../cost-pass.mjs ~/.claude/projects/<v1-project> cost-raw.json`: one streaming pass (about 15 s) over all
   848 transcripts. It writes per-transcript cost aggregates. The script is in Appendix A.
2. `node ../cost-report.js` (Appendix B): the family table and the v2 counterfactual.
3. The inline `node -e` one-liners next to each number. `D` below means `require("./cost-raw.json")` and `A` means
   `require("./agents.json")`.

**Price assumptions** (list price per million tokens; CONFIRMED in kickoff note 07 §4.1 from the pricing page,
2026-10-17. The bundled `claude-api` skill, cached 2026-10-06, agrees on base input and output prices and on the
1.25× / 2× cache-write multipliers):

| Model | Input | 5m cache write | 1h cache write | Cache read | Output |
|---|---|---|---|---|---|
| Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
| Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 | $10 |
| Haiku 5.5 (prompt ≤ 100k / > 100k) | $0.10 / $0.50 | $0.125 / $0.625 | $0.20 / $1 | $0.01 / $0.05 | $0.50 / $2.50 |

One open point: the skill's Sonnet 5.5 paragraph gives a cache read of "$0.20", but note 07's table gives $0.10
(0.05×). v1 hardly used Sonnet (2.4 % of spend), so v1 figures barely move. The v2 counterfactual (§5) is given for
both values. Dollars are list-price estimates, not a bill: v1 ran on a subscription.

---

## 0. Answer first

1. **v1 cost about $11,400 at list price**: 135,449 requests, 97.6 % on Opus, 99.6 % at effort `high` (MEASURED). By
   dollars, **cache reads were 44 %, cache writes 41 % and output 14 %**. The "96 % of tokens are cache reads" figure
   in PLAN §8.4 is true for tokens but hides the fact that writes cost almost as much as reads.
2. **The largest single waste is idle agents waking up cold.** 2,924 requests rewrote a whole context after the
   agent had been idle 5-60 minutes. Each rewrite cost about $0.94, **$2,763 in all, 24 % of all spend** (MEASURED).
   Agents in v1 used the 5-minute cache. The lead used the 1-hour cache and lost only $3 this way. Had every subagent
   used the 1-hour cache, v1 would have cost **$9,714 instead of $11,395 (−15 %)** (INFERRED counterfactual). This
   contradicts PLAN §8.4 lever 3, which argues a wide 1h TTL "would likely lose money".
3. **Twenty long-lived contexts made up 52 % of spend**: the lead (16.4 %) plus 19 agents that lived more than 24 h
   (36.1 %). The 645 agents that lived under an hour cost 11 % (MEASURED).
4. **Polling was cheap per run but large in total.** The lead ran 3,761 scheduled prompts (1,889 of them "check
   iphone connection"). They cost $656, **35 % of the lead's spend**. Agents re-waking for "Agent … finished" and
   Monitor events cost another $472 on the lead and $1,618 on agents (MEASURED, attributed by turn trigger).
5. **Effort is a small lever.** All output, thinking included, was $1,640 (14 %). Even cutting output by a quarter
   saves about 3.6 %. The context levers are larger: clipping prompts at 200k saves about 8 %, and 1h TTL or "do not
   idle" saves 15-24 %.
6. **Cost per outcome fell 4.5× in the phase with fewer agents** (co-occurrence; that fewer agents caused it is
   INFERRED, because gates, the less-work rule and step size changed at the same time). v1 spent about $922 per best-build step on
   30 Sep-5 Oct (44-291 agents a day), and about $206 per step on 6-10 Oct (25-46 agents a day) (MEASURED cost;
   landings from `v1:fixes/BEST_BUILDS.md`). Later steps were smaller, so part of this gap is not efficiency
   (INFERRED).
7. **PLAN §8.4's budget is about 4× too small for v1-like activity.** With v2's roster applied to v1's work, the
   estimate is **$6.2k-$7.2k for about 12 days, or $520-600 a day**. §8.4 budgets **$127 a day** ($5,730 over 45
   days). The budget also gives the lead 51 % of spend (v1: 16 %) and measuring and tooling 7 % (v1 toolsmiths:
   16 %) (INFERRED from MEASURED inputs).
8. **A meter bug to avoid copying.** The digest's output total (23.5 M) counts the first streaming record of each
   subagent request. The final record holds the full count, so the real total is **84.3 M, 3.6× more** (MEASURED).
   v2's `usage-record.mjs` must keep the **last** record per `message.id`.

---

## 1. Where the money went

### 1.1 Totals and the split by token type (MEASURED)

| Token type | Tokens | $ | Share of $ |
|---|---|---|---|
| Cache read | 25.73 B | 5,053 | 44.3 % |
| Cache write, 5 min (subagents) | 903.6 M | 4,374 | 38.4 % |
| Cache write, 1 h (lead only) | 40.9 M | 327 | 2.9 % |
| Output (including thinking) | 84.3 M | 1,640 | 14.4 % |
| Uncached input | 0.3 M | 1 | 0.0 % |
| **Total** | | **11,395** | |

`node -e 'const D=require("./cost-raw.json");const t={},u={};for(const x of Object.values(D)){for(const k in x.usd)t[k]=(t[k]||0)+x.usd[k];for(const k in x.tok)u[k]=(u[k]||0)+x.tok[k]}console.log(t,u)'`

v1's own readout after 4 d 8 h was $8,576 (QUOTED, kickoff note 07 §1). The list-price recompute for 30 Sep-4 Oct
is $6,801 (`byDay` below). The gap is not explained. A different price basis in the in-app readout is one candidate
(INFERRED).

**Digest correction.** `node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");let a=0,b=0;for(const r of A){a+=r.usage.output;b+=D[r.file]?.tok.out||0}console.log(a,b)'`
prints 23,514,662 and 84,316,112. In subagent transcripts each request's first record is a partial stream record
(for example 8 output tokens) and the final record holds the full count (for example 210). The lead transcripts do
not have this split, which is why the lead's figures agree.

### 1.2 By role family (MEASURED; `node ../cost-report.js`)

Families come from name prefixes (`fix-`, `ts-`, `mgmt-`/`ops-`, `de-`/`arch-`/`res-`/`ver-` = research,
`iphone-`/`cap-` = device, `int-`/`wi-` = integrate, `review-`, `map-`/`sum-` = mapper, `art-` = article). The
mapping is in Appendix B.

| Family | Agents | $ | Share | Read $ | Write $ | Output $ | Requests | Avg prompt | Cold 5-60 min $ |
|---|---|---|---|---|---|---|---|---|---|
| fix owners | 50 | 3,810 | 33.4 % | 1,528 | 1,758 | 525 | 39,084 | 205k | 1,170 |
| lead (10 sessions) | 10 | 1,868 | 16.4 % | 1,290 | 327 | 250 | 27,533 | 236k | 3 |
| toolsmiths | 133 | 1,777 | 15.6 % | 683 | 833 | 262 | 19,775 | 182k | 555 |
| research (de, arch, res, ver) | 106 | 1,154 | 10.1 % | 499 | 466 | 189 | 14,320 | 187k | 241 |
| mgmt / ops | 47 | 847 | 7.4 % | 315 | 413 | 118 | 10,514 | 174k | 281 |
| device (iphone-runner, cap-*) | 9 | 571 | 5.0 % | 190 | 326 | 55 | 5,079 | 201k | 253 |
| integrators | 6 | 485 | 4.3 % | 211 | 208 | 65 | 5,135 | 215k | 119 |
| other / unnamed | 296 | 324 | 2.8 % | 124 | 133 | 67 | 6,052 | 123k | 57 |
| article | 44 | 261 | 2.3 % | 118 | 93 | 51 | 3,243 | 189k | 31 |
| reviewers | 71 | 253 | 2.2 % | 80 | 125 | 48 | 3,048 | 140k | 54 |
| mappers / summaries | 76 | 45 | 0.4 % | 14 | 20 | 10 | 1,666 | 93k | 0 |

Readings:
- **Per agent** (MEASURED): the 50 fix owners had a median of about 350 requests (336-367; even count, so two middle
  values) and about $38 ($37.7-38.6), mean $76.2 ($3,810 / 50). Toolsmiths had a median of $7.1, reviewers $2.8
  (38 requests), de/res/ver research $2.2, arch $4.7.
  `node -e 'const A=require("./agents.json"),D=require("./cost-raw.json"),md=a=>{a=[...a].sort((x,y)=>x-y);return [a[(a.length-1)>>1],a[a.length>>1]]},f=A.filter(x=>x.kind=="agent"&&/^fix-/.test(x.name||"")),u=f.map(x=>D[x.file].usdTotal);console.log(f.length,md(u),md(f.map(x=>D[x.file].n)),u.reduce((a,b)=>a+b)/u.length)'`
- **Reviewers stayed cheap on Opus/high** because they start fresh and end quickly. PLAN keeps this, rightly.
- **Toolsmiths were the third-largest family.** That was 133 agents, almost all on Opus/high, writing measuring and
  console code. v2's equivalents (measure-engineer, console-builder) get 7 % and 10 % of §8.4's budget.

### 1.3 By session, day, model, effort and prompt size (MEASURED)

- **Session.** The main lead session 391f6dee and its agents cost $10,960 (96.2 %). The 12-13 Oct sessions
  (distillation, release) cost $189 and $175.
  `node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");const s={};for(const x of A){const k=x.kind=="session"?x.who.slice(5):x.session;s[k]=(s[k]||0)+(D[x.file]?.usdTotal||0)}console.log(s)'`
- **Model.** Opus $11,126 (97.6 %), Sonnet $269, Haiku $0.5. **Effort**: `high` $11,344 (99.6 %), `medium` $51.
  `node -e 'const D=require("./cost-raw.json");const m={},e={};for(const x of Object.values(D)){for(const k in x.byModel)m[k]=(m[k]||0)+x.byModel[k];for(const k in x.byEff)e[k]=(e[k]||0)+x.byEff[k]}console.log(m,e)'`
- **Prompt size.** 43 % of requests ran above 200k and cost 57 % of the dollars ($6,497). 66 % ran above 150k and
  cost 77 %, which matches v1's own "75 % above 150k".

| Prompt size | Requests | $ |
|---|---|---|
| ≤ 100k | 17,880 | 939 |
| 100-150k | 28,643 | 1,687 |
| 150-200k | 30,040 | 2,272 |
| 200-400k | 52,429 | 5,498 |
| > 400k | 6,457 | 999 |

`node -e 'const D=require("./cost-raw.json");const t={};for(const x of Object.values(D))for(const [k,v] of Object.entries(x.byCtx)){t[k]=t[k]||{n:0,usd:0};t[k].n+=v.n;t[k].usd+=v.usd}console.log(t)'`

### 1.4 Cost per useful outcome (MEASURED cost, landings from `v1:fixes/BEST_BUILDS.md`)

A landing is a row that became the best build on main. There are 21: wave 1, v1-v4, v6-v8, v9-final, v14, and
g0.0b-g0.0m without g0.0g. Count them with
`grep -E '^\| ' fixes/BEST_BUILDS.md | grep -E 'current best|replaced|folded' | grep -vE 'not yet|not landed|candidate'`
(19 rows; one row holds v1, v2 and v3). Dates are UTC; +0700 times are converted.

| Day | $ | Agents active | Requests | Best-build steps |
|---|---|---|---|---|
| 30 Sep | 519 | 291 | 8,316 | 0 |
| 1 Oct | 2,060 | 119 | 21,502 | 1 |
| 2 Oct | 897 | 44 | 11,257 | 3 |
| 3 Oct | 1,477 | 56 | 16,707 | 1 |
| 4 Oct | 1,848 | 73 | 23,455 | 3 |
| 5 Oct | 1,499 | 88 | 18,102 | 1 |
| 6 Oct | 758 | 46 | 8,535 | 0 |
| 7 Oct | 645 | 34 | 7,670 | 3 |
| 8 Oct | 561 | 25 | 6,123 | 5 |
| 9 Oct | 297 | 26 | 3,260 | 3 |
| 10 Oct | 215 | 25 | 2,324 | 1 |
| 11-16 Oct (write-up, release) | 620 | | | 0 |

- `$`: `node -e 'const D=require("./cost-raw.json");const t={};for(const x of Object.values(D))for(const k in x.byDay)t[k]=(t[k]||0)+x.byDay[k];console.log(t)'`
- Agents and requests: `node -e 'const A=require("./agents.json");const d={};for(const x of A)for(const [k,v] of Object.entries(x.perDay||{}))if(v.asst){d[k]=d[k]||[0,0];if(x.kind=="agent")d[k][0]++;d[k][1]+=v.asst}console.log(d)'`

Readings:
- 30 Sep-5 Oct: $8,300 for 9 steps, **$922 per step**. 6-10 Oct: $2,476 for 12 steps, **$206 per step**.
  Over the whole experiment it was about $513 per step (MEASURED).
- The cheaper phase had about 25-46 active agents a day, measured gates and the "less-work" landing rule. It also
  had smaller steps (corner clips, a clock layer), so the 4.5× is an upper bound on the efficiency gain (INFERRED).
- The 30 Sep spike of 291 agents cost only $519. Spawning many short agents is cheap. Keeping them alive is not
  (§2.1, §2.5).

---

## 2. Waste, quantified

### 2.1 Cold rewrites after idling: the largest waste (MEASURED)

A request counts as "cold" when its cache write is more than half of a prompt above 20k tokens. Each cold request is
classified by what came before it (`coldWhy`, `coldGap` in Appendix A):

| Cause | Requests | Write $ |
|---|---|---|
| Idle 5-60 min since the agent's previous request | 2,924 | **2,763** |
| Idle > 60 min | 197 | 196 |
| First request after a compaction | 819 | 222 |
| First request of a new agent (spawn) | 531 | 91 |
| Other (< 5 min; cache invalidated) | 87 | 60 |

`node -e 'const D=require("./cost-raw.json");const W={},G={};for(const x of Object.values(D)){for(const [k,v] of Object.entries(x.coldWhy)){W[k]=W[k]||{n:0,usd:0};W[k].n+=v.n;W[k].usd+=v.usd}for(const [k,v] of Object.entries(x.coldGap)){G[k]=G[k]||{n:0,usd:0};G[k].n+=v.n;G[k].usd+=v.usd}}console.log(W,G)'`

- **The cache rewrite when waking an idle 200k Opus agent cost about $0.94; a spawn's first cache write cost about
  $0.17** ($91 / 531) (MEASURED). The two are not like-for-like: a fresh agent also rebuilds its working context over
  its later requests, which the $0.17 leaves out. "Spawning fresh is cheaper than waking" is therefore INFERRED.
- Agents idled while they waited for the phone lock, builds, peer replies and the lead. A full JSON parse finds
  6,424 unique tool calls that ran `lock.mjs status` (README B14). The earlier figure here (about 3,900) and the
  counts of about 1,100 `iphone.mjs status`, 665 `idle.mjs` and 630 `sleep N` came from a regex window
  (`"command":"[^"]{0,200}`) that stops at the first quote in a command, so they undercount (MEASURED, lower bounds).
- **Counterfactual, 1-hour cache for every subagent** (the lead already had it). Every write is priced at 2× instead
  of 1.25×, and a rewrite after a 5-60 min gap becomes a cache read. The total falls from **$11,395 to $9,714**
  (`cf1h` in Appendix A, INFERRED model):
  `node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");const L=new Set(A.filter(x=>x.kind=="session").map(x=>x.file));let c=0;for(const [f,x] of Object.entries(D))c+=L.has(f)?x.usdTotal:x.cf1h;console.log(c)'`
- Idle gaps by family (`gaps` in Appendix A): fix owners had about 1,250 gaps of 5-60 min, toolsmiths 666, mgmt 405 and
  device 279. The lead had 339 in 27k requests, because it was almost always busy.

### 2.2 Polling and cron loops (MEASURED)

Scheduled prompts, all in the lead session. The user's five `/loop` prompts fired 2,897 times (the first two rows plus
20 in "others"); crons the lead created itself fired 864 times (check-ins, usage checks, hourly report, window reset)
(README B12). Fires come from
`grep -h '"subtype":"scheduled_task_fire"' ~/.claude/projects/<v1-project>/*.jsonl | node -e '…count by .prompt…'`.
The cost is that of the lead requests in turns the prompt started (`byTrig`).

| Prompt (first words, QUOTED) | Cron | Fires | Lead $ |
|---|---|---|---|
| "check iphone connection" | every 5 min | 1,889 | 282 |
| the user's poll to check that all agents work together (paraphrased) | every 10 min | 988 | 185 |
| "Usage check … every 30 min" (lead-created, at the user's request) | :13, :43 | 334 | 75 |
| "Lead check-in (delegated mode): ask mgmt-ops for its digest" (lead-created) | :07, :37 and every 30 min | 365 | 60 |
| "Hourly team-measures report" (lead-created) | hourly | 164 | 46 |
| others (three small user loops, one window reset) | | 21 | 9 |
| **total** | | **3,761** | **656 (35 % of the lead)** |

`node -e 'const D=require("./cost-raw.json");const t={};for(const x of Object.values(D))for(const [k,v] of Object.entries(x.byTrig))if(k.startsWith("scheduled:"))t[k]=(t[k]||0)+v;console.log(t)'`

- Each fire was cheap: the lead stayed warm on the 1-hour cache, so a fire cost $0.15-0.28. The total was large
  because of the rate (about 300 fires a day).
- The table understates the cost. A "Lead check-in" woke mgmt-ops, and an "all agents work together" check sent
  messages that woke idle agents cold (§2.1). Those costs land in the agents' rows. How much is unknown (INFERRED).
- **Other wake-ups by turn trigger** (`byTrig`):
  - Lead: peer messages $581, task notifications $472, human turns $82.
  - Agents: coordinator messages $1,930, task notifications $1,618, peer messages $1,498.
  - The lead's notifications are dominated by the Monitor "lead triage listener" (338 events) and repeated "Agent …
    finished" notices: one integrator's task finished 83 times and one GPU fix 79 times (MEASURED; grep
    `"turnOrigin":"task_notification"` in the lead file, grouped by `<summary>`).

### 2.3 Compaction churn (MEASURED + INFERRED)

- **822 compactions** (lead 135, fix owners 313, toolsmiths 112). They averaged 303k tokens before and 14k after
  (MEASURED: `preTokens` 248.9 M, `postTokens` 11.6 M).
- The first request after a compaction rewrote the cache: $222 (MEASURED).
- The compaction call itself is not in the transcripts. If it reads the pre-compaction context at the cache price
  and writes the summary as output, it cost about $50 + $233 (INFERRED). **Total about $500 (4.4 %).**
- A 200k cap (PLAN §8.2) makes compactions about 1.6× as frequent: the growth per cycle falls from about 290k to
  about 186k (INFERRED).

### 2.4 Long-lived agents with giant contexts (MEASURED)

| Lifetime | Agents | $ | Share |
|---|---|---|---|
| < 1 h | 645 | 1,265 | 11.1 % |
| 1-6 h | 132 | 2,074 | 18.2 % |
| 6-24 h | 39 | 2,080 | 18.3 % |
| > 24 h | 19 | 4,108 | **36.1 %** |

The lead is not in this table: it is one more long-lived context, at 16.4 %. Lifetime is the first to last
timestamp from the digest (3 `journal` agents with no timestamps and no cost are left out); cost is from `cost-raw.json`.

Top agents:

| Agent | $ | Requests | Lifetime | Compactions |
|---|---|---|---|---|
| fix-nav-morph | 458 | 4,603 | 119 h | 44 |
| iphone-runner | 434 | 4,013 | 102 h | 32 |
| fix-hero-exit-threaded | 381 | 4,329 | 63 h | 46 |
| int-v8 | 356 | 3,762 | 51 h | 33 |
| mgmt-ops-10 | 351 | 4,778 | 53 h | 46 |

### 2.5 Agents left parked, and regenerated roles (MEASURED, INFERRED reading)

- **85 agents' last message says they were waiting, queued or idle**, for example "#2 in the queue. Still waiting."
  Their **lifetime** spend was $1,816. That is not idle cost: how much of it was spent idling was not measured. The
  reading that they were stopped while parked is INFERRED. Every hour parked at 5-minute TTL did pay the cold rewrites
  in §2.1.
  `node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");let n=0,u=0;for(const x of A)if(x.kind=="agent"&&/\b(wait|waiting|queued|idle)\b/i.test((x.lastText||"").slice(0,200))){n++;u+=D[x.file].usdTotal}console.log(n,u)'`
- 255 agents ended with an empty last text ($238). Most were short.
- Roles regenerated many times:
  - `mgmt-ops-*`: 10 hub instances (9 named transcripts plus the unnamed mgmt-ops-8) and a 14-turn editor named
    mgmt-ops-11, $645 in all (README B15).
  - `ops-reader-P*`: 30 one-card readers on Opus, $85. Each followed a fixed 7-step "pre-data read" brief.
  - `int-v*` and `wave-*` integrators.
- Duplicate research was small in dollars: `res-video-host` ran three times for $0.9. v1 split research into
  cheap, short agents. The cost went to idling and to long lives, not to duplicate questions.

### 2.6 Effort `high` on mechanical work (MEASURED + INFERRED)

- All but $51 ran at `high`. Output in total cost $1,640.
- Mechanical families had $299 of output: device $55, mgmt/ops $118, integrate $65, article $51, mappers $10.
- If `medium` cuts output by a quarter on all work (INFERRED; not measured in v1), the saving is about $410 (3.6 %).
  Effort is worth setting right, but it is not where the budget is.

### 2.7 Opus where Sonnet, Haiku or a script would do (sample of 20; INFERRED classification)

**Sample.** The 470 non-lead agents that used Opus were sorted by cost, and every 23rd was taken. The script is in
Appendix B (`sample`). Each was classified from its spawn prompt, description and last message.

| Agent | $ | Work | Needs |
|---|---|---|---|
| fix-nav-morph | 458.1 | engine-level nav morph fix, 119 h | Opus (but not 119 h) |
| ts-i017 | 72.4 | measurement-code incidents | Sonnet |
| art-worst-cases | 44.2 | article scene capture | Sonnet |
| ts-i109 | 25.6 | tool incidents | Sonnet |
| fix-infinite-anims | 18.3 | pause off-screen animations | Sonnet |
| de-illusion-composite | 15.0 | compositing research | Opus |
| ts-tryit (unnamed) | 12.3 | serve preview pages on demand | Sonnet |
| de-safari | 9.2 | Safari tool research | Opus |
| art-p1days | 7.5 | blog draft | Sonnet |
| cap-finger-hero | 6.7 | run a fixed phone protocol | script + Sonnet |
| measure-parallel | 5.9 | parallel-measurement experiment | Sonnet |
| review-release-tooling | 5.0 | adversarial code review | Opus |
| arch-team-ops | 4.3 | coordination plan | Opus |
| de-tools-synth | 3.7 | synthesis report | Sonnet |
| review-loop | 3.4 | document review | Opus |
| arch-render | 3.0 | rendering research | Opus |
| art-upload-rerun | 2.5 | make a script re-runnable | Sonnet |
| ops-reader-P140 | 2.2 | fixed 7-step card read | script |
| review-commission-2 | 1.5 | code re-review | Opus |
| de-gpu-webkit | 1.1 | cited web research | Sonnet |

- **By count:** 8 need Opus, 10 Sonnet, 2 a script.
- **By dollars:** Opus $499 (71 %), Sonnet $194, script $9. The dollar weight sits in long-lived Opus owners, so a
  model switch alone does less than limiting their lifetime.

---

## 3. v2's roster on v1's workload (INFERRED counterfactual)

**Method** (`node ../cost-report.js`, Appendix B). Each family's v1 spend is adjusted in this order:
1. Drop the lead's scheduled-turn spend (scripts take it over).
2. Clip cache reads at a 200k prompt (`crCap200`). This ignores the extra compactions.
3. Cut output by 25 % for the lower effort.
4. Keep only the share of the work v2 still gives to agents: integrate and device 50 %, mgmt 10 %.
5. Re-price the non-Opus share at Sonnet (0.5× Opus at list prices; 0.72× if Sonnet cache reads are $0.20) or at
   Haiku. The Opus share kept is: lead, eng-* research and reviewers 100 %; fix work 50 % (per-call Opus for
   engine, hero exit and morph, which covers three of the five most expensive v1 fix owners); measuring and
   tooling 10 %.

| Family → v2 role | v1 $ | v2 $ |
|---|---|---|
| fix → part-builder (Sonnet, Opus per call) | 3,810 | 2,554 |
| lead → lead (Opus, medium, 200k) | 1,868 | 976 |
| toolsmith → measure / console builders (Sonnet) | 1,777 | 896 |
| research → eng-* (Opus, high) | 1,154 | 1,029 |
| mgmt/ops → console-api and hooks | 847 | 39 |
| device → scripts and a Sonnet steward | 571 | 131 |
| integrate → `fw gate` and the lead lands | 485 | 106 |
| other, article, review, mapper | 883 | 501 |
| **total** | **11,395** | **6,233 (7,167 at 0.72×)** |

- **Opus share of the v2 estimate:** about 66 %. PLAN says about 81 %.
- **Not modelled:**
  - The 1h-TTL saving of §2.1. With it, the estimate drops by roughly another 10-15 %.
  - Extra compactions under the cap, which add cost.
  - Rework from lost context.

---

## 4. Where PLAN §8.4 is wrong or thin

1. **Lever 3 reaches the wrong conclusion.**
   - §8.4 says writes were "roughly half of input-side spend (INFERRED), so a global 1h TTL would likely lose
     money". The first half is right: writes were $4,701 of $9,755 input-side spend.
   - But 59 % of those write dollars were rewrites after a 5-60 min idle ($2,763), which a 1h TTL turns into reads.
   - Measured on v1's request timing, a 1h TTL for all subagents would have **saved 15 %**.
   - Limiting 1h to eng-* and exp-* leaves out the families that idled most: fix owners ($1,170 of cold rewrites)
     and toolsmiths ($555).
2. **The lever ranking does not match measured effect.** Measured on v1:
   - Not idling, or 1h TTL: 15-24 %.
   - Scripts for mgmt, device and cron work: about 13 % ($656 cron + $847 mgmt + part of $571 device).
   - Sonnet for builders: about 15 % (half of fix spend and 90 % of toolsmith spend at 0.5×).
   - Context cap at 200k: about 8 %.
   - Effort: about 3.6 %.

   §8.4 puts "keep the lead lean" and the context cap first, and does not list idling at all.
3. **The daily rate is about 4× below v1-like activity.**
   - §8.4 is $5,730 over 45 days, $127 a day.
   - v2's roster on v1's work is about $520-600 a day.
   - Even v1's quietest landing days (8-10 Oct, 25-26 agents) ran $215-561 a day on Opus, or about $120-310 at v2
     prices.
   - So the budget assumes v2 runs at v1's quietest pace all the time. It does not say this. It needs a stated
     activity assumption (requests per day per role), or the 15 % stop rule will fire every week.
4. **The lead line is over-provisioned, and the builder and measuring lines are under-provisioned.**
   - Lead: $2,925 (51 %). v1's lead cost $0.067 per request at a 236k average prompt, so 600 requests a day cost
     about $40 before medium effort and the cap. $65 a day buys about 970 v1-sized requests.
   - Part and console builders: $600 over 45 days. v1 fix owners had a median of about 350 requests and about $38 each
     on Opus (§1.2; 205k family-average prompt), so about $19 each on Sonnet at 0.5×.
   - Note 07 §4.4's envelope of 200 requests at 80k ($5.60 per part) assumes 1.6× fewer requests and a 2.5×
     smaller context than v1 measured. Under a 200k cap the sawtooth average is about 110k, not 80k (INFERRED).
   - Measuring: $400 (7 %), against v1 toolsmiths at 15.6 %.
5. **Missing line items.**
   - Compaction: about 4 % in v1, and more often under a 200k cap.
   - Cold wakes: 24 % in v1.
   - Spawns: a first cache write of about $0.17 each, plus the requests a fresh agent needs to rebuild context
     (not measured).
   - The budget should carry them explicitly, or the meter's "cold-wake share" has nothing to compare against.
6. **The source figures need correcting.**
   - "Reviewers 0.4 %" is 2.2 % by dollars.
   - "Lead 20 %" is 16.4 %.
   - "Cache reads 96 %" is by tokens. By dollars it is 44 %.
   - The v1 output total used in the forensics digest is undercounted 3.6×.

---

## Improvements for v2

Each item gives its evidence and the PLAN section it changes.

1. **Rewrite §8.4 lever 3 and the §8.2 "Cache TTL" column.**
   - Evidence: §2.1, $2,763 (24 %) of cold rewrites after 5-60 min idle; counterfactual −15 %.
   - Change: default `experimental.cacheTtl: 1h` for every role that waits on gates, the device, builds or peers
     (part-builder, measure-engineer, lean-prover, eng-*, exp-*). Keep 5m only for roles that start fresh and end
     within minutes (reviewer, source-locator, librarian, Explore).
   - Have the M0 meter confirm it with the measured gap distribution. The `gaps` and `coldGap` fields of Appendix A
     are the method.
2. **Add a "do not idle" rule to §8.2 and §9.**
   - Evidence: §2.1 and §2.5. Re-waking an idle Opus context cost a $0.94 rewrite; a spawn's first write cost $0.17
     (not like-for-like, INFERRED). 85 agents' last message says waiting or queued (lifetime spend $1,816; idle share
     unmeasured).
   - Change: an agent that must wait longer than about 10 minutes writes its handoff note to `research/notes/` and
     exits. The script that ends the wait (gate, device run, build) spawns a fresh agent with the note.
   - `session-brief` (§8.3) lists live agents with their idle minutes and context size.
3. **Bound lifetime, not only context.**
   - Evidence: §2.4. 19 agents over 24 h made up 36 % of spend; the top fix owner made 4,603 requests in 119 h.
   - §8.2: keep `maxTurns` on every role file, including the eng-* teammates. part-builder already has 150; v1's fix
     median was about 350 requests.
   - §8.4: state the time box as a request count the meter can check.
4. **Re-derive the §8.4 budget table from measured rates.**
   - Evidence: §1.2, §3 and §4.3-4.5.
   - Change: state requests per day and the average prompt per role. Size builder and measuring lines from v1's
     medians (fix owner about $38 on Opus, so about $19 on Sonnet; toolsmith $7.1 on Opus, so about $3.5 on Sonnet). Add compaction (about
     4 %) and cold-wake lines.
   - Move about $1,000 from the lead line to the builders and measuring.
   - State outright that $127 a day means about a quarter of v1's daily agent activity.
5. **Make the lead's request cap real.**
   - Evidence: §2.2. The lead averaged about 2,100 requests a day (peak 3,805 on 4 Oct, digest `perDay`). 35 % of
     its spend was cron prompts. Lead notifications included 83 repeats of one agent's "finished".
   - §8.2 lead row and §8.3 hooks: no `CronCreate` in the lead. Recurring checks run as `pnpm fw status` under OS
     cron and write to the console. Only state changes wake the lead.
   - Coalesce repeated "Agent … finished" and Monitor notices in console-api, not in the lead's context.
6. **Fix the meter before trusting it (§8.3 `usage-record.mjs`, §8.4 "Reporting").**
   - Evidence: §1.1. The digest undercounted output 3.6× by keeping the first streaming record.
   - Change: dedupe by `message.id`, keep the record with the final `output_tokens` (the last one), and split
     `cache_creation.ephemeral_5m` from `ephemeral_1h`.
   - Add a unit test with a two-record fixture: 8 output tokens, then 210.
7. **Turn fixed-procedure roles into scripts (§8.2 "(no agent)" row, §3.3).**
   - Evidence: §1.2 and §2.5. mgmt/ops cost $847 (10 mgmt-ops hub instances plus one editor, $645). device cost $571 (iphone-runner
     $434 on Opus/high, 102 h). 30 Opus `ops-reader-P*` agents ran a fixed 7-step brief.
   - Change: the device protocol and the card "pre-data read" become `pnpm fw` commands. An agent reads only the
     result.
8. **Treat effort as a minor lever (§8.4 lever list, §8.2 effort column).**
   - Evidence: §2.6. Output was 14 % of spend, and a 25 % cut saves about 3.6 %.
   - Change: keep `medium` as the default, but do not count on effort to meet the budget. Do not spend review time
     tuning it before the TTL, idle and lifetime rules exist.
9. **Budget the Opus escalations of part-builders explicitly (§8.2 part-builder row, §8.4 table).**
   - Evidence: §2.7 and §3. Three of the five most expensive v1 fix owners (nav-morph, hero-exit-threaded,
     scroll-engine; $1,123 of $1,554) did engine, hero-exit or morph work, exactly the per-call Opus cases.
   - Change: in v1 terms, about half of fix spend stays on Opus. Give that its own column or line so the meter can
     show escalation drift.
10. **Keep many short agents, few long ones (§8.2 caps).**
    - Evidence: §1.4. On 30 Sep, 291 short agents cost $519. The later cheaper-per-step phase had 25-46 agents a
      day, with gates as code.
    - The caps (3 teammates, 4 worktree subagents) are right. Add: no agent alive across two milestone days without
      a handoff note.

---

## Appendix A. `cost-pass.mjs` (save as `.local/v1-chat-digest/cost-pass.mjs`)

```js
// node cost-pass.mjs <projects-dir> <out.json>
// One streaming pass over every lead and subagent transcript. Dedupes requests by message.id, keeping the record
// with the larger output_tokens (the final stream record), prices them at list price, and attributes each request
// to the input that started its turn.
import fs from 'node:fs'; import readline from 'node:readline'; import path from 'node:path';
const [ROOT, OUT] = process.argv.slice(2);
const P = { opus: [4, 5, 8, .2, 20], sonnet: [2, 2.5, 4, .1, 10], haiku: [.1, .125, .2, .01, .5],
  haikuL: [.5, .625, 1, .05, 2.5], fable: [10, 12.5, 20, .25, 50] }; // in, w5m, w1h, read, out per MTok
const fam = m => /opus/.test(m) ? 'opus' : /sonnet/.test(m) ? 'sonnet' : /haiku/.test(m) ? 'haiku' : /fable/.test(m) ? 'fable' : null;
function price(m, u) {
  let f = fam(m); const prompt = u.in + u.cr + u.w5 + u.w1;
  if (f === 'haiku' && prompt > 100000) f = 'haikuL';
  const p = P[f]; const parts = { in: u.in * p[0], w5: u.w5 * p[1], w1: u.w1 * p[2], cr: u.cr * p[3], out: u.out * p[4] };
  for (const k in parts) parts[k] /= 1e6; return parts;
}
const files = [];
for (const f of fs.readdirSync(ROOT)) {
  if (f.endsWith('.jsonl')) files.push(f);
  const sub = path.join(ROOT, f, 'subagents');
  if (fs.existsSync(sub)) for (const g of fs.readdirSync(sub, { recursive: true })) if (g.endsWith('.jsonl')) files.push(path.join(f, 'subagents', g));
}
const bucket = c => c <= 100e3 ? '<=100k' : c <= 150e3 ? '100-150k' : c <= 200e3 ? '150-200k' : c <= 400e3 ? '200-400k' : '>400k';
const out = {};
for (const rel of files) {
  const reqs = new Map(); let trig = 'start'; const comp = []; let pendingCompact = null;
  const rl = readline.createInterface({ input: fs.createReadStream(path.join(ROOT, rel)), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.includes('"type":"user"') && !line.includes('"type":"assistant"') && !line.includes('compact_boundary')) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    if (r.type === 'system' && r.subtype === 'compact_boundary') {
      pendingCompact = { ts: r.timestamp, pre: r.compactMetadata?.preTokens || 0, post: r.compactMetadata?.postTokens || 0 };
      comp.push(pendingCompact); continue;
    }
    if (r.type === 'user') {
      const c = r.message?.content;
      if (Array.isArray(c) && c.length && c.every(b => b.type === 'tool_result')) continue;
      if (r.isCompactSummary) continue;
      const o = r.turnOrigin || r.origin?.kind || (r.isMeta ? 'meta' : 'user');
      let key = o;
      if (o === 'scheduled') { const t = typeof c === 'string' ? c : (c?.[0]?.text || ''); key = 'scheduled:' + t.slice(0, 60).replace(/\s+/g, ' '); }
      trig = key; continue;
    }
    const m = r.message; if (!m?.usage || !m.id || !fam(m.model || '')) continue;
    const u = m.usage, cc = u.cache_creation || {};
    const w1 = cc.ephemeral_1h_input_tokens || 0, wAll = u.cache_creation_input_tokens || 0;
    const rec = { model: m.model, ts: r.timestamp, trig, eff: r.effort || r.perTurnEffort || '?',
      u: { in: u.input_tokens || 0, out: u.output_tokens || 0, cr: u.cache_read_input_tokens || 0, w1, w5: Math.max(0, wAll - w1) } };
    if (!reqs.has(m.id)) { if (pendingCompact) { rec.postCompact = pendingCompact; pendingCompact = null; } reqs.set(m.id, rec); }
    else { const old = reqs.get(m.id); old.u = rec.u.out >= old.u.out ? rec.u : old.u; }
  }
  const A = { n: 0, tok: { in: 0, out: 0, cr: 0, w5: 0, w1: 0 }, usd: { in: 0, w5: 0, w1: 0, cr: 0, out: 0 }, byModel: {}, byDay: {}, byTrig: {}, byCtx: {}, byEff: {},
    cold: { n: 0, usd: 0 }, coldWhy: {}, compactPost: 0, cf1h: 0, crCap200: 0, promptSum: 0, coldGap: { '5-60': { n: 0, usd: 0 }, '>60': { n: 0, usd: 0 } },
    gaps: { lt5: 0, '5to60': 0, gt60: 0 }, compactions: comp.length, compactPre: 0, postCompactUsd: 0 };
  let prevTs = null; const add = (o, k, v) => { o[k] = (o[k] || 0) + v; };
  for (const q of [...reqs.values()].sort((a, b) => a.ts < b.ts ? -1 : 1)) {
    const pr = price(q.model, q.u); const usd = Object.values(pr).reduce((a, b) => a + b, 0);
    A.n++; for (const k in q.u) A.tok[k] += q.u[k]; for (const k in pr) A.usd[k] += pr[k];
    const prompt = q.u.in + q.u.cr + q.u.w5 + q.u.w1;
    add(A.byModel, q.model, usd); add(A.byDay, q.ts.slice(0, 10), usd); add(A.byTrig, q.trig, usd); add(A.byEff, q.eff, usd);
    A.crCap200 += pr.cr * Math.min(1, 200000 / Math.max(prompt, 1)); A.promptSum += prompt;
    const b = bucket(prompt); A.byCtx[b] = A.byCtx[b] || { n: 0, usd: 0 }; A.byCtx[b].n++; A.byCtx[b].usd += usd;
    const gapMin = prevTs ? (Date.parse(q.ts) - prevTs) / 60000 : null;
    if (prompt > 20000 && (q.u.w5 + q.u.w1) > 0.5 * prompt) { A.cold.n++; A.cold.usd += pr.w5 + pr.w1;
      const why = q.postCompact ? 'compact' : gapMin === null ? 'spawn' : gapMin >= 5 ? 'gap>=5m' : 'other';
      if (why === 'gap>=5m') { const G = A.coldGap[gapMin <= 60 ? '5-60' : '>60']; G.n++; G.usd += pr.w5 + pr.w1; }
      const W = A.coldWhy[why] = A.coldWhy[why] || { n: 0, usd: 0 }; W.n++; W.usd += pr.w5 + pr.w1; }
    { // counterfactual: every write at the 1h price; a cold rewrite after a 5-60 min gap becomes a cache read
      let f = fam(q.model); if (f === 'haiku' && prompt > 100000) f = 'haikuL'; const p = P[f]; const w = q.u.w5 + q.u.w1;
      const warm = prompt > 20000 && w > 0.5 * prompt && !q.postCompact && gapMin !== null && gapMin >= 5 && gapMin <= 60;
      A.cf1h += usd - (pr.w5 + pr.w1) + (warm ? w * p[3] : w * p[2]) / 1e6; }
    if (prevTs) { const g = gapMin; if (g < 5) A.gaps.lt5++; else if (g <= 60) A.gaps['5to60']++; else A.gaps.gt60++; }
    prevTs = Date.parse(q.ts);
    if (q.postCompact) A.postCompactUsd += pr.w5 + pr.w1;
  }
  for (const c of comp) { A.compactPost += c.post; A.compactPre += c.pre; }
  A.usdTotal = Object.values(A.usd).reduce((a, b) => a + b, 0);
  out[rel] = A;
}
fs.writeFileSync(OUT, JSON.stringify(out));
console.log('files', files.length);
```

Limits (INFERRED):
- Turn attribution follows the last non-tool-result user record. Queued peer messages injected mid-turn move later
  requests to "peer".
- The gap is measured between request timestamps, so generation time counts against the TTL, as the docs describe.
- A "cold" request is a heuristic: a write above 50 % of a prompt over 20k tokens.

## Appendix B. `cost-report.js` (save as `.local/v1-chat-digest/cost-report.js`, run in `out/`)

```js
// node ../cost-report.js [sonnetFactor]   (0.5 at list prices; 0.72 if Sonnet cache reads were $0.20)
const a = require('./agents.json'), d = require('./cost-raw.json'), R = Math.round;
const M = { fix: 'fix', int: 'integrate', wi: 'integrate', wave: 'integrate', ts: 'toolsmith', tool: 'toolsmith', mgmt: 'mgmt/ops',
  ops: 'mgmt/ops', arch: 'research', de: 'research', res: 'research', research: 'research', ver: 'research', review: 'review',
  read: 'review', check: 'review', audit: 'review', map: 'mapper', bm: 'mapper', wk: 'mapper', sum: 'mapper', iphone: 'device',
  apple: 'device', cap: 'device', art: 'article', dev: 'article', export: 'article', story: 'article', edit: 'article' };
const fam = x => { if (x.kind === 'session') return 'lead'; const n = x.name || '', p = (n.match(/^[a-z]+(?=-)/) || [n])[0];
  return M[p] || (p === 'agent' && /bundle-mapper|Explore/.test(x.agentType) ? 'mapper' : 'other'); };
const F = {}; let T = 0;
for (const x of a) { const r = d[x.file]; if (!r) continue; const f = fam(x), g = F[f] = F[f] || { k: 0, usd: 0, cr: 0, cw: 0, out: 0, n: 0, prompt: 0, crCap: 0, cold: 0, sched: 0, comp: 0 };
  g.k++; g.usd += r.usdTotal; g.cr += r.usd.cr; g.cw += r.usd.w5 + r.usd.w1; g.out += r.usd.out; g.n += r.n; g.prompt += r.promptSum; g.crCap += r.crCap200;
  g.cold += r.coldGap['5-60'].usd; g.comp += r.compactions; T += r.usdTotal;
  g.sched += Object.entries(r.byTrig).filter(([k]) => k.startsWith('scheduled:')).reduce((s, [, v]) => s + v, 0); }
console.log('family | agents | $ | share | read$ | write$ | out$ | requests | avg prompt k | $ over 200k clipped | cold 5-60m $ | scheduled $ | compactions');
for (const [f, g] of Object.entries(F).sort((p, q) => q[1].usd - p[1].usd))
  console.log([f, g.k, R(g.usd), (100 * g.usd / T).toFixed(1) + '%', R(g.cr), R(g.cw), R(g.out), g.n, R(g.prompt / g.n / 1e3), R(g.cr - g.crCap), R(g.cold), R(g.sched), g.comp].join(' | '));
// v2 roster on the same work: [share kept as agent work, share left on Opus, price factor of the non-Opus model vs Opus]
const S = +(process.argv[2] || 0.5);
const V2 = { lead: [1, 1], fix: [1, .5], toolsmith: [1, .1], integrate: [.5, 0], 'mgmt/ops': [.1, 0], research: [1, 1], device: [.5, 0],
  article: [1, 0], review: [1, 1], mapper: [1, 0, .05], other: [1, 0] };
let v2 = 0; for (const [f, g] of Object.entries(F)) { const [keep, opus, alt = S] = V2[f]; let b = g.usd - (f === 'lead' ? g.sched : 0);
  b -= (g.cr - g.crCap) * b / g.usd; b -= .25 * g.out * b / g.usd; b *= keep; const c = b * opus + b * (1 - opus) * alt; v2 += c; console.log('v2', f, R(c)); }
console.log('v1 total', R(T), '| v2 roster, same workload', R(v2));
```

The lifetime table (§2.4) and the sample (§2.7) use the same join:

```sh
# lifetime buckets (§2.4)
node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");const b={};for(const x of A){if(x.kind!=="agent")continue;const h=(Date.parse(x.last)-Date.parse(x.first))/36e5;if(isNaN(h))continue;const k=h<1?"<1h":h<6?"1-6h":h<24?"6-24h":">24h";b[k]=b[k]||[0,0];b[k][0]++;b[k][1]+=D[x.file].usdTotal}console.log(b)'
# 20-agent sample (§2.7): non-lead agents that used Opus, by cost, every 23rd
node -e 'const A=require("./agents.json"),D=require("./cost-raw.json");const o=A.filter(x=>x.kind=="agent"&&Object.keys(x.models).some(m=>m.includes("opus"))).map(x=>[x,D[x.file].usdTotal]).sort((p,q)=>q[1]-p[1]);for(let i=0;i<20;i++){const [x,u]=o[i*Math.floor(o.length/20)];console.log(x.who,u.toFixed(1),x.description)}'
```
