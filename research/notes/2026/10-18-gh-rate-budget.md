---
id: 2026-10-18-gh-rate-budget
kind: note
title: "GitHub API rate budget: one shared CI poller per machine, a charged ledger in Lean, and theorems that bound requests per hour regardless of how many agents wait"
status: review
created: 2026-10-18
topics: [ci, github-api, rate-limit, lean, fwcore, polling, agents, work-graph]
---

# GitHub API rate budget: make "bucket empty" impossible by construction

**Question (user, 2026-10-18).** How do we stop the GitHub rate-limit failure from happening again? The fix should be
a reproducible script plus a Lean proof.

**Incident (reported in the task context, not re-measured).** At about 01:07 +0700 on 2026-10-18, the REST `core`
bucket of the token used by this session's shell and its ~12 background agents reached `X-Ratelimit-Used 5000`,
`Remaining 0`. The user's own terminal kept working on a different token with its own bucket.

**Inputs.**
- Two investigations from the same day:
  - the call inventory, with gh 2.86.0 source read at tag `v2.86.0` and agent transcripts grepped;
  - the GitHub limits read from docs.github.com.
- My own re-reads, marked "re-read" below:
  - gh `v2.86.0`;
  - go-gh `v2.13.0` and httpretty `v0.1.4`, the versions pinned in gh's `go.mod:18,130@v2.86.0`;
  - the repo at `a8c05f4`.

## 0. Answer first

- **Cause (CONFIRMED by source, the share of blame is INFERRED).**
  - `gh run watch` with no `-i` polls every 3 s (`pkg/cmd/run/watch/watch.go:20@v2.86.0`, re-read: `defaultInterval
    int = 3`).
  - Each tick costs 3 + J requests, where J is the number of jobs still in progress. The extra requests are
    annotation re-fetches (`watch.go:219-251`, re-read).
  - One such watcher uses about 3,200 to 4,800 requests an hour, and 66 of the 157 agent `run watch` calls used the
    default interval.
  - `apps/runner/src/run.ts:192@a8c05f4` also passes no `-i`.
  - On top of that, 12 agents each polled `gh run view` every 30 s, which is 2,880 requests an hour. Together these
    are well over the 5,000 bucket.
- **Fix: one charged choke point.**
  - Every GitHub call made by our tools goes through one wrapper, `ghCharged`.
  - Before each call, the wrapper asks Lean (fwcore op `ci.budget.reserve`) for permission against a ledger shared by
    the whole machine. The ledger is a file under the git common dir, so all worktrees share it.
  - A single elected poller watches every run that any agent waits on, using one list request per tick.
  - Agents call `pnpm fw ci wait <run>`. This blocks on a local state file and makes no GitHub requests of its own.
- **Proved in Lean (`Fw.Ci.Budget`, §3).**
  - (a) The ledger never holds more than B charged requests in any 3600 s window, and B does not depend on the
    number of waiters N.
  - (b) No request is made while the headers say remaining ≤ F before reset, or before `retry-after` has passed.
  - (c) Every watched run is polled at least once every P seconds while the guards allow it.
  - (d) The formula for P, and the matching bound for each poller under the old scheme, which grows linearly in N.
- **Defaults** (Lean-generated constants):
  - B = 3000 of 5000 per hour, split as 1800 for poll ticks and R = 1200 for one-off calls.
  - Floor F = 500.
  - P_min = 30 s.
  - 60 requests per 60 s, well under the 900-point secondary limit.
  - At P = 30 s the shared poller uses at most **240 requests/h for any N**. Today's load was ≥ 5,000/h.
- **Reading headers without `gh api`.**
  - **A (works today):** run `gh run list` with `GH_DEBUG=api` and parse `x-ratelimit-*` and `retry-after` from
    stderr. Authorization is redacted by default (CONFIRMED, §2).
  - **B (needs the user's approval):** the poller calls `gh api --method GET --include` with `If-None-Match` on a
    fixed path. This costs 1 request per tick, or 0 primary when the response is a 304.
  - A Node `fetch` with a token taken from `gh auth token` is rejected (§2).
- **Who decides what.**
  - fwcore runs every decision as wire ops, like `store.ciRun` does today.
  - Lean also emits golden request/reply vectors and the constants JSON for the TS glue tests.
  - TS keeps only the lock, the process spawn, sleeping and the filtering of header lines.
- **Can start now.**
  - The work runs in parallel with the ports. Only the runner migration waits for the tasks that own
    `apps/runner/**` (`fw-ci`, `store-*`). See §6.

## 1. Budget arithmetic (INFERRED from the CONFIRMED per-call costs)

Per-call request counts come from the gh source (inventory note; re-read where marked):

| gh command | requests per call | source @v2.86.0 |
|---|---|---|
| `run list` without `--workflow` | 2 + D: runs page, `GetWorkflows`, plus 1 per deleted workflow id | `run/shared/shared.go:363-450` (re-read: `preloadWorkflowNames` runs whenever no workflow name is given) |
| `run list --workflow X` | 2: workflow by file, then its runs | `run/list/list.go:136-143` |
| `run view --json status` | 2 | `shared.go:539,561` |
| `run view --json …,jobs` | 3 | `run/view/view.go:259-261,445` |
| `run watch` (per tick) | 3 + J | `watch.go:219-251` (re-read) |
| `run download` | 1 + artifacts | `run/download/http.go` |
| `gh api … --include` | 1 per page (0 primary when the response is 304 and authorized) | GitHub best-practices page |

`run list` follows the `Link: next` header until it has `limit` rows (`shared.go` pagination loop, re-read). So
`--limit 100` with `per_page=100` stays at 1 runs page.

**Rate for each poller.** A poller with cost c and interval P costs $3600\,c/P$ requests per hour, and N such pollers
cost N times that.

| load | requests/h |
|---|---|
| 12 agents × `run view` every 30 s | 2,880 |
| 12 agents × `run view` every 120 s (today's stopgap) | 720 |
| 1 `run watch` at 3 s, J = 1 | ≈ 3,200 to 4,800 |
| 1 `run watch` at 3 s, J = 8 | ≈ 8,800 to 13,200 |
| **shared poller, option A, P = 30 s, any N** | **240** |
| **shared poller, option B, P = 30 s, any N** | **≤ 120**, less when the response is 304 |

Fixed vs rolling window: GitHub reports `x-ratelimit-reset` per window, and the docs do not say whether the window is
fixed or rolling (INFERRED fixed). Our bound is over **every** 3600 s interval, so it also holds over GitHub's window,
whichever one it is.

## 2. Reading headers without `gh api`: the options

| option | headers | ETag/304 | cost per tick | token exposure | policy change |
|---|---|---|---|---|---|
| **A. `GH_DEBUG=api gh run list …` with stderr parsed** | yes | no (gh run sends no conditional requests: no `If-None-Match` in `pkg/cmd/run`, INFERRED from the inventory grep) | 2 + D | none: see below | none |
| **B. `gh api --method GET --include -H 'If-None-Match: <etag>' repos/{o}/{r}/actions/runs?…`** | yes, on stdout | yes | 1, or 0 primary on 304 | none: the token stays inside gh | the user approves that fw (not agents) may run these fixed GET paths |
| C. Node `fetch` with a token from `gh auth token` | yes | yes | 1 or 0 | the token sits in our process memory and environment, and can reach crash dumps and logs | requires `gh auth token`; **rejected** |

- **Option A is safe to log (CONFIRMED, re-read).**
  - `GH_DEBUG` set to a value containing `api` turns on `LogVerboseHTTP` (`api/http_client.go:81-88@go-gh v2.13.0`).
  - The httpretty logger then prints request and response headers and bodies (`http_client.go:93-101`). Bodies are
    capped at 100 kB.
  - go-gh does not set `SkipSanitize`, so httpretty runs `header.Sanitize(header.DefaultSanitizers, h)`
    (`printer.go:487-488@httpretty v0.1.4`). The `Authorization` value is masked.
  - The glue still keeps only the status line, `x-ratelimit-*`, `retry-after` and `etag`. It drops the rest of the
    trace at once, because response bodies can name accounts.
- **Option B and 304 responses (CONFIRMED, re-read).**
  - `gh api` turns any status > 299 into an error (`pkg/cmd/api/api.go:522-523@v2.86.0`). With `--include` it prints
    headers first (`api.go:460`).
  - So a 304 exits non-zero with the status line `304` on stdout, and the glue must map that to "unchanged".
  - The agent deny rule on `gh api*` stays. Option B is a narrow exception for one code path, and the user has to
    grant it explicitly.
  - It is not a workaround: the Bash permission layer does not see subprocesses of `pnpm fw`, so fw calling `gh api`
    on its own would quietly bypass the deny. That is exactly why the exception needs the user's yes first.
- **Recommendation.**
  - Build A first, because it needs no permission change.
  - Keep B behind a flag that the user enables.
  - The Lean decisions are the same for both; only the cost table changes (`listCost := 2 + D` vs `1`).
- **Different buckets (INFERRED).** The docs say all tokens of one user share 5,000 an hour, so the user's terminal
  probably uses a different account. Check this with `gh auth status`, which shows the login and masks the token, and
  with `x-ratelimit-resource`. Never print the token.

## 3. Lean module `Fw.Ci.Budget` (`lean/Fw/Ci/Budget.lean`)

**State and decision** (all times are integer seconds; everything here is pure):

```lean
structure Limits where       -- generated to packages/contracts/golden/ci-budget/limits.json
  W := 3600; B := 3000; R := 1200        -- window, cap per window, one-off share (ticks get B - R)
  W1 := 60; B1 := 60                     -- per-minute cap (secondary limit is 900 points/min)
  F := 500; Pmin := 30                   -- header floor, minimum tick interval
  back0 := 60; backMax := 3600; maxFails := 6

structure Obs where          -- reduced from response headers by `observe`
  remaining : Option Nat; reset : Option Nat; retryUntil : Nat; fails : Nat; etag : Option String

structure Watch where runId : Nat; createdAt : Nat; lastCovered : Option Nat

structure State where
  now : Nat
  ledger : List Entry        -- Entry = (at : Nat, cost : Nat, kind : tick | oneoff)
  obs : Obs
  watched : List Watch       -- registered by waiters; N waiters on one run = one entry
  lastTick : Option Nat

inductive Req | tick (pages : Nat) | oneoff (k : OneOff) (cost : Nat)   -- dispatch, view, log, download, probe
inductive Decision | issue (r : Req) (s' : State) | waitUntil (t : Nat) (why : Reason) | stop (why : Reason)

def reserve (L : Limits) (s : State) (r : Req) : Decision
def next    (L : Limits) (s : State) : Decision          -- the poller's "tick now or sleep until t"
def observe (L : Limits) (s : State) (h : Headers) (actual : Nat) : State
def step    (L : Limits) : State → Event → State         -- clock (now := max now t), register, unregister, response
```

**Rules.**
- `reserve` issues only when all of these hold:
  1. Σ cost over the ledger in (now − W, now] for its share (B − R for ticks, R for one-offs), plus the new cost,
     stays within that share. The same check applies to W1/B1.
  2. now ≥ `retryUntil`.
  3. remaining > F, or remaining is unknown, or now ≥ reset.
- `observe` updates the state from each response:
  - It sets `retryUntil := max(retryUntil, now + retry-after)`.
  - On a 403/429 with remaining 0 it sets `retryUntil := max(…, reset)`.
  - On a 403/429 with neither header it sets `retryUntil := now + back0·2^fails` (at most `backMax`), and moves to
    `stop` after `maxFails` failures in a row.
  - It replaces the charged cost of the entry with `max(charged, actual)`, where `actual` is the number of responses
    in the trace.
- `next` returns `tick` once now ≥ lastTick + P(s), where P(s) is formula (d) below. Otherwise it returns
  `waitUntil`.
- A tick's query is `created>=min(createdAt over watched)&per_page=100&exclude_pull_requests=true`, page 1 only. So
  **one request covers every watched run** whenever ≤ 100 runs were created since the oldest watched run (pages ≤ 2
  in general, charged per page).

**Theorems.** Each docstring carries the LaTeX statement below. ℓ is the ledger, $\Sigma_W(\ell,t)=\sum_{(\tau,c)\in
\ell,\ t-W<\tau\le t} c$, and Reach is the set of states reachable from `init` by `step`/`reserve`.

| id | name | statement |
|---|---|---|
| a | `window_bound` | $\forall s\in\mathrm{Reach},\ \forall t:\ \Sigma_W(s.\ell,t)\le B \ \wedge\ \Sigma_{W_1}(s.\ell,t)\le B_1$ |
| a′ | `register_free` | $\forall s,w:\ \mathrm{step}(s,\mathrm{reg}(w)).\ell=s.\ell \wedge \mathrm{step}(s,\mathrm{unreg}(w)).\ell=s.\ell$ (so the bound does not depend on N) |
| a″ | `tick_cost_indep_N` | $\mathrm{cost}(\mathrm{tick}(s)) = c_{\text{list}}\cdot\lceil m(s)/100\rceil$, with $m$ = runs created since $\min_{w\in s.\mathit{watched}} w.\mathit{createdAt}$, not $\lvert\mathrm{waiters}\rvert$ |
| a‴ | `overrun_absorbed` | if an actual cost exceeds its charge by Δ, then $\Sigma_W\le B+\Delta$, and `reserve` issues nothing until $\Sigma_W\le B$ again |
| b | `no_issue_when_exhausted` | $\mathrm{reserve}(s,r)=\mathrm{issue}\Rightarrow s.now\ge s.\mathit{retryUntil}\ \wedge\ \big(s.\mathit{rem}=\bot \vee s.\mathit{rem}>F \vee s.now\ge s.\mathit{reset}\big)$ |
| b′ | `guard_persists` | if `observe` at $t_0$ sees (rem = 0, reset = T) or retry-after a, then no `issue` at any $t\in[t_0,\max(T,t_0+a))$ |
| b″ | `backoff` | $\mathit{wait}_k=\min(\mathit{backMax},\ 60\cdot 2^k)\ \ge 60$, it is monotone in k, and $k\ge\mathit{maxFails}\Rightarrow\mathrm{stop}$ |
| c | `poll_live` | if $c_{\max}\lceil W/P\rceil\le B-R$, $c_{\max}\lceil W_1/P\rceil\le B_1$ and no guard is active on $[t,t+P]$, then $\forall w\in s.\mathit{watched}\ \exists\tau\in[t,t+P]:\ \mathrm{tick}(\tau)\wedge w\in\mathrm{cover}(\tau)$ (one-offs cannot starve ticks because the shares are separate) |
| d | `interval_sound` | $P(s)=\max\!\Big(P_{\min},\ \Big\lceil\tfrac{W\,c}{B-R}\Big\rceil,\ \Big\lceil\tfrac{c\,(T_{\text{reset}}-t)}{\max(1,\ \mathit{rem}-F)}\Big\rceil\Big)$ gives $\lceil W/P\rceil c\le B-R$ and ticks before reset $\le \mathit{rem}-F$ |
| d′ | `per_agent_interval` (contrast) | N independent pollers of cost c stay within B only if $P\ge \tfrac{W\,c\,N}{B}$ (12 agents, c = 2: P ≥ 29 s; `run watch`, c = 4: P ≥ 58 s) |
| e | `clock_monotone` | $\mathrm{step}(s,e).now\ge s.now$ (the glue's `Date.now` may jump backwards, and Lean clamps it) |

**Proof sketch for (a).**
- Every ledger timestamp is ≤ now, and `now` never decreases (e).
- So for t ≥ now, $\Sigma_W(\ell,t)\le\Sigma_W(\ell,\mathrm{now})$, because the window loses old entries and gains no
  new ones.
- `reserve` appends (now, c) only when $\Sigma_W(\ell,\mathrm{now})+c\le B$.
- For t < now the new entry lies outside the window.
- The result follows by induction over the trace. N never appears in it, which is (a′).

**Run or generate (Lean-first rule).**
- **fwcore runs it.** New wire ops: `ci.budget.reserve`, `ci.budget.observe` (raw filtered header lines in, so header
  parsing is Lean too), `ci.budget.next` and `ci.budget.status`. They live in `lean/Fw/Ci/Wire.lean` and are
  registered in `lean/Fw/Wire.lean` with one dispatch line.
- Ticks are ≥ 30 s apart, so one `spawnSync` of fwcore per decision, as `fwcoreCall` does (`run.ts:73-81@a8c05f4`),
  is cheap.
- **Lean generates** `limits.json` and the wire golden vectors (`packages/contracts/golden/ci-budget/wire-*.txt`), the
  same pattern as `Fw/Wire/SchedGolden.lean`.
- **Fail closed.** If fwcore is missing or returns an error, `ghCharged` makes no GitHub call. There is no TS fallback
  decision.

## 4. Reproducible parts

- **Shared state.**
  - It lives in `<dirname(git rev-parse --git-common-dir)>/.cache/gh-budget/`, so every worktree on the machine
    shares one state. `.cache/` is already gitignored.
  - Files: `ledger.jsonl`, `state.json` (atomic rename), `watch/<runId>.json` (one per waiter) and
    `lock` (`open(..., 'wx')` with pid and start time; stale if the pid is dead).
  - Every `reserve` → gh call → `observe` sequence happens under the lock, so two processes can never both spend the
    same headroom.
- **Replay test (Lean, `lean/FwTest/CiBudget.lean`).**
  - It feeds fixture traces through `step`/`next`/`reserve` on a simulated clock.
  - It checks: the maximum of $\Sigma_W$ and $\Sigma_{W_1}$ over the trace stays ≤ B and ≤ B1; nothing is issued
    under a guard; every watched run is covered within P.
  - Fixtures go in `packages/contracts/golden/ci-budget/fixtures/`, as header records only:
    - `incident-10-18.jsonl`: 12 waiters and one default watch, rebuilt from the inventory counts. The old scheme
      goes over 5000 and the new one holds ≤ 240/h.
    - `remaining-zero.jsonl`: a 403 with rem = 0 and reset in the future.
    - `retry-after.jsonl`: a secondary limit, 403 with `retry-after: 60`.
    - `bare-429.jsonl`: no headers, so the poller backs off and then stops.
    - `n-sweep.jsonl`: N = 1, 12 and 50 waiters, with identical ledgers.
    - `recorded-1.jsonl`: one real `GH_DEBUG=api gh run list --limit 1 --workflow lean.yml` trace (2 requests),
      sanitized to the status line and `x-ratelimit-*`.
- **Glue test (TS, `packages/gh-budget/test/`).**
  - The same fixtures go through fwcore over the wire.
  - A fake `gh` on `PATH` counts its invocations. 50 concurrent `wait` processes on 3 runs must produce one tick per
    P, and fake-gh calls must stay ≤ the bound.
  - A lint test fails if any tracked script spawns `gh run|workflow|api` outside `packages/gh-budget`.
- **CLI.**
  - `pnpm fw ci budget` prints the limit, remaining, used and reset from the last observed headers, $\Sigma_W$ and B,
    P, the watched runs and the backoff state. It makes **0 requests**.
  - `--probe` makes 1 charged call: `gh run list --limit 1 --workflow lean.yml` under option A, or
    `gh api rate_limit` under B, which does not count against the primary limit.
  - Until `fw.ts` is integrated, the same CLI runs as `node packages/gh-budget/src/cli.ts`.

## 5. Migration

- **New commands, all charged:**
  - `fw ci wait <runId|--branch b --workflow f>`: blocks for at most 9 min, so it fits a Bash call; exits 0, 1, or 3
    on timeout; idempotent to re-call.
  - `fw ci view <runId>`, `fw ci log <runId> [--job]` (gh caches the log zip itself, `view.go:318-326`) and
    `fw ci download <runId> [--pattern]`.
  - `fw ci dispatch <workflow> <ref>`: detects the new run through the shared tick, which replaces `newestRun`'s
    24 × 5 s polling.
- **Runner** (after its owners land, §6):
  - `run.ts:192` `run watch` → `ciWait`.
  - `run.ts:188-217` → `fw ci dispatch` / `wait`.
  - `ci.ts:57,65,73` → `ghCharged`.
  - `watch-collect.ts:516` `gh run list` → read `state.json` (0 requests, which also removes `fw watch`'s 24/h).
- **Permissions (user decision; `.claude/settings.json:52-56`).**
  - Replace the allows for `gh run list*`, `view*`, `watch*` and `download*` with `pnpm fw ci *`.
  - Add a deny for `gh run watch*`.
  - Keep `gh api*` denied for agents.
- **Docs to change:**
  - `CLAUDE.md:50` (the "read results with" line);
  - `.claude/agents/measure-engineer.md:13`;
  - `.github/README.md:31-32`;
  - `docs/team/public-ci-brief.md:85`;
  - `docs/team/tools/fw-ci.md`, `docs/team/tools/watch.md:67` and `docs/team/token-policy.md` (the CI-wait rule);
  - `packages/measure-*/README.md`.
  - Handoff notes are history and stay as they are.
- **One-offs (counted, INFERRED from the inventory).**
  - 153 downloads at 1 + 5..15 artifacts each: about 500 to 1,200 requests over 2 h.
  - Logs at about 4 requests each.
  - Both draw from the separate R = 1200 per hour share, so they can no longer starve polling or empty the bucket.
  - A download larger than the remaining share waits, and `fw ci budget` shows why.
- **Now, before any code:**
  - Retire the session scratch loops: `wait.sh` and `wait2.sh` at 20 s, 360/h each.
  - Keep `waitrun.sh` at ≥ 120 s.
  - Agent prompts say "never `gh run watch` without `-i 120`".

## 6. Task list for the work graph (none touches the port files)

| id | size | deps | writes | owner |
|---|---|---|---|---|
| `ghb-lean` | M | none | `lean/Fw/Ci/Budget.lean` | lean-prover |
| `ghb-wire` | S | `ghb-lean` | `lean/Fw/Ci/Wire.lean`, `lean/Fw/Ci/Golden.lean`, `packages/contracts/golden/ci-budget/**` (the lead adds one line each to `lean/Fw/Wire.lean` and `lean/Fw.lean`) | lean-prover |
| `ghb-replay` | S | `ghb-lean` | `lean/FwTest/CiBudget.lean`, `packages/contracts/golden/ci-budget/fixtures/**` (the lead registers it in `FwTestMain.lean`) | lean-prover |
| `ghb-trace` | S | `ghb-lean` (record format) | `packages/contracts/golden/ci-budget/fixtures/recorded-1.jsonl` (one 2-request debug call, sanitized) | measure-engineer |
| `ghb-glue` | M | `ghb-wire` | `packages/gh-budget/**` (lock, ledger, `ghCharged`, poller, CLI, tests, lint) | measure-engineer |
| `ghb-policy` | S | `ghb-glue` + user yes (option B and settings) | `.claude/settings.json` | lead |
| `ghb-runner` | M | `ghb-glue`, `fw-ci`, `store-and-run`, `store-target`, `store-cirun` | `apps/runner/src/{run,ci,watch-collect,fw}.ts`, `apps/runner/test/{run,ci}*.ts` | measure-engineer |
| `ghb-docs` | S | `ghb-glue` | `.claude/agents/measure-engineer.md`, `.github/README.md`, `docs/team/public-ci-brief.md`, `docs/team/tools/{fw-ci,watch}.md`, `docs/team/token-policy.md`, `packages/measure-*/README.md` (the lead edits `CLAUDE.md`) | plan-editor |

**Critical path:** `ghb-lean` → `ghb-wire` → `ghb-glue` → `ghb-policy`. `ghb-runner` waits only for the in-flight
`apps/runner/**` owners.

## 7. Open items

- Option B needs the user's decision, and it is the only route to free 304 polls.
- Check which account and bucket each token draws from (`gh auth status`, `x-ratelimit-resource`) without printing
  either token.
- Secondary limits: whether a 304 still costs secondary points is not documented. The W1/B1 cap assumes it does.
