---
id: 2026-10-18-chrome-agent-tools-install
kind: note
title: "Installing Chrome Modern Web Guidance and chrome-devtools-mcp: pin the MCP now, guides as a pinned source, no plugins"
status: review
created: 2026-10-18
topics: [tooling, chrome-devtools-mcp, modern-web-guidance, install, privacy, evidence]
---

# Installing the Chrome agent tools in this experiment

Install, config and trial; what the tools are: `10-18-chrome-agent-docs.md`. Trials ran in scratch, nothing installed globally.

## Answer first

| Tool | Install? | Adds to the experiment | Now | After C3 (2026-10-19 23:15) | After report |
|---|---|---|---|---|---|
| chrome-devtools-mcp 1.11.0 (MCP + `chrome-devtools` CLI) | Yes: Homebrew formula, pinned, project `.mcp.json` entry with privacy flags | Diagnosis our harness lacks: `CLSCulprits`, `ForcedReflow`, `LCPBreakdown`, INP breakdown, Lighthouse a11y/SEO | User applies the pinned entry (overrides user-scope `@latest` in this repo only) | Agent `tools:` and allow lines (user); per-part triage (which part shifts or reflows); Lighthouse a11y pass; short `cdt-explore` skill | Offline TraceEngine lane for Web Vitals as JSON |
| Modern Web Guidance 0.0.194 (skill + CLI) | No plugin, no `npx @latest`. Guides as a pinned upstream source; CLI as an exact devDependency later | Cited feature advice for optimized and proposal variants; the trial returned `carousel-snap-highlights`, `visually-stable-font-fallbacks`, `optimize-preload-priority`, `state-aware-sticky-headers`, `resilient-context-menus-and-nested-dropdowns` | Decision only: no plugin. Pin the guides now only if `guidance-proofs` starts before C3 | Guides pin in `sources.lock.yaml` | Pinned CLI, own `web-guidance` skill, allow rules with `DISABLE_TELEMETRY=1` in the command + deny rules, Lean feature-support gate |

- Evidence does not change: Lean proofs plus CI counts. A DevTools trace or Lighthouse score is a development aid and is
  never reported as a result. A guide is advice, never a premise.
- Neither install shortens the critical path to C3, so only zero-cost decisions and the MCP privacy fix happen before C3.
- C3 closes the proof ledger (docs/plan/PLAN.md:1082@975bd5c2, CONFIRMED). A variant a guide suggests after C3 cannot
  enter `v2-proved` before the report, so the CLI, skill and gate wait for after the report (INFERRED).

## chrome-devtools-mcp

### Install (pinned)

1. `brew install chrome-devtools-mcp && brew pin chrome-devtools-mcp`. Formula stable 1.11.0, bottled, depends on `node`
   (CONFIRMED, `brew info --json=v2`). Bins `chrome-devtools-mcp` and `chrome-devtools` in `$(brew --prefix)/bin`: INFERRED, check with `ls`.
2. User applies the `.mcp.json` entry below; Claude Code then asks to approve the project server. In this repo the
   project entry overrides the user-scope `npx chrome-devtools-mcp@latest` (no flags, CONFIRMED by
   `claude mcp get chrome-devtools`): same-name servers use the whole entry of the highest scope, local > project >
   user (https://code.claude.com/docs/en/mcp, CONFIRMED). The user-scope entry stays; other repos are untouched.
3. No plugin. Its `mcp.json` runs `npx --prefix ${PLUGIN_DATA} chrome-devtools-mcp@1.11.0` with no flags, so telemetry,
   CrUX, a headed browser and a persistent profile stay on (CONFIRMED, mcp.json@a878bca).

Tag `chrome-devtools-mcp-v1.11.0` = a878bcad39584337e055778353246820deafa7c0 (CONFIRMED, `git ls-remote`). Citations below are @a878bca.

### Config diff (user applies; agents never edit `.mcp.json`)

```diff
   "mcpServers": {
+    "chrome-devtools": {
+      "command": "chrome-devtools-mcp",
+      "args": ["--headless", "--isolated", "--no-usage-statistics", "--no-performance-crux",
+        "--chrome-arg=--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE localhost, EXCLUDE 127.0.0.1"],
+      "env": { "CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS": "1" }
+    },
     "serena": {
```

No agent may use the tools today: no `tools:` frontmatter and no settings rule names `chrome-devtools` (`git grep -i
devtools 975bd5c2 -- .claude`: none, CONFIRMED). After C3 the user applies:

```diff
# .claude/agents/part-builder.md and .claude/agents/researcher.md, frontmatter (user, after C3)
-tools: Read, ..., mcp__serena__find_declaration
+tools: Read, ..., mcp__serena__find_declaration, mcp__chrome-devtools__*
# .claude/settings.json permissions.allow (user, after C3)
+      "mcp__chrome-devtools__*",
+      "Bash(chrome-devtools *)",
```

- Flags exist as kebab aliases (docs/configuration.md:107,197,202); the env var disables statistics (src/config/ConfigParser.ts:245).
  Both CONFIRMED. A stdio probe of 1.11.0 parsed this set: 32 tools, 29.4 KB of schemas (MEASURED).
- Resolver rule as in packages/measure-chromium/src/run.mjs:50@975bd5c2: no GTM, Amplitude or Hotjar in a trace. The
  trial checked it only through the CLI daemon; the stdio probe ran `initialize` and `tools/list`, so the rule taking
  effect in MCP mode is INFERRED.
- Without Homebrew: `"command": "npx"`, args prefixed with `"-y", "chrome-devtools-mcp@1.11.0"`.
- Keep `--slim` off: it leaves 3 tools (1.0 KB) and drops the trace and Lighthouse tools (MEASURED).

### Trial (local debug run, MEASURED, not a result)

Built `apps/site` (`pnpm -s build`, 3.3 s, gates PASS), served it and `snapshot/site` on ports 47300-47302, drove
the CLI daemon with `--sessionId`, `--headless --isolated --no-usage-statistics --no-performance-crux`.

| Step | Wall time | Output |
|---|---|---|
| daemon start / first `new_page` | 0.78 s / 4.0 s | browser launch on first page |
| trace, snapshot, repo server, third parties blocked | 10.5 s | LCP 94 ms, CLS 0.38; 6 insights |
| trace, rewrite (`apps/site/dist/aot`) | 6.5 s | LCP 77 ms, CLS 0.00 |
| `performance_analyze_insight` | 0.38-0.43 s | `CLSCulprits`: `DIV.pain-canvas` 0.3839; `ForcedReflow`: top function and 10 ms total |
| interaction trace (click, Escape) | 0.45-0.93 s per call | INP 11 ms (input 3, processing 3, presentation 4) |
| `lighthouse_audit` mobile, snapshot / rewrite | 8.1 s / 6.8 s | snapshot: 500-state page (python server), not representative, not re-run on `server.mjs`; rewrite: a11y 0.96, fails `color-contrast`, `meta-description` |

- Serving `snapshot/site` with `python -m http.server` left the page in the SvelteKit `500` state (LCP 589 ms, live third
  parties). Use `packages/measure-chromium/src/server.mjs` (MEASURED).
- `autoStop` traces ended in 6.5-10.5 s; no v1-style ~1 h hang outside the BeginFrame container (MEASURED once).

### Per role

| Role | Use | When |
|---|---|---|
| part-builder | `take_snapshot`, `get_css_styles`, `emulate` while porting | after C3, once the user adds the tools below |
| researcher | Per part, compare `CLSCulprits`/`ForcedReflow`/`LCPBreakdown` of original vs rewrite to pick what to prove | after C3 |
| page-writer | Lighthouse a11y/SEO on the rewrite (`color-contrast`, `meta-description`) | after C3 |
| lean-prover, math-reviewer | none; trace numbers are never premises | never |
| measure-engineer | none in measure lanes; offline `@paulirish/trace_engine` lane only after the report | after report |

### Overlap with ours

- Our harness counts style, layout and paint events per frame in virtual time (BeginFrameControl) and computes no LCP,
  CLS, INP or culprit attribution (packages/measure-chromium/src/trace.mjs:20-30@975bd5c2, CONFIRMED by grep). The MCP
  traces on wall clock with fixed categories (src/tools/performance.ts:81-91, CONFIRMED).
- Navigation, snapshots and screenshots already exist (current MCP entry, Claude-in-Chrome); new are insights and Lighthouse.

### Risks and limits

- Only the last trace is kept (src/McpContext.ts:743-750, CONFIRMED). Subagents sharing one session's MCP server
  overwrite each other's insights (INFERRED); use the CLI with a per-agent `--sessionId`.
- `--output-format=json` returns `{}` for insight details; only Lighthouse is structured (src/McpResponse.ts:1201-1233, CONFIRMED).
- Lighthouse 13.x here has no performance category (src/tools/lighthouse.ts:164, CONFIRMED). The trial's report says
  `lighthouseVersion` 13.4.1 (trial run output, MEASURED once); package.json:83 says 13.5.0 (CONFIRMED).
- Numbers swing with server and third parties (LCP 589 vs 94 ms above); the planned `cdt-explore` skill will forbid quoting them.
- Shell use per agent: `chrome-devtools --sessionId <hex> <tool>`, then `chrome-devtools stop --sessionId <hex>`.
- Without MCP roots, file outputs are limited to the temp dir (docs/configuration.md:232-240, CONFIRMED); the committed
  config cannot hold a home path. Whether Claude Code sends roots: untested.
- Never attach `--browserUrl` to the BeginFrameControl container; never a CI measure lane (v1 hang, wall clock).

## Modern Web Guidance

### Install (pinned)

- No Homebrew formula (CONFIRMED, `brew search modern-web-guidance`: none).
- Do not use any official path: `claude plugin install modern-web-guidance@claude-plugins-official` (marketplace pins
  b31dc0a, CONFIRMED), `/plugin marketplace add GoogleChrome/modern-web-guidance`, `npx modern-web-guidance@latest install`,
  `npx skills add ...`, `gh skill install ...`. The installed SKILL.md calls `npx -y modern-web-guidance@latest`
  (skills/modern-web-guidance/SKILL.md:38,65,75@b31dc0a, CONFIRMED) and asks to allowlist that command (line 102), so
  the code that runs floats even when the plugin is pinned. The plugin also brings `chrome-extensions` (26 KB), off-topic.
- Guides as source (after C3, or now if `guidance-proofs` starts before C3): entry below, then
  `node scripts/refs-fetch.mjs modern-web-guidance`. The git `guides/` tree equals the npm 0.0.194 guides except
  generated files (CONFIRMED, `diff -rq`).
- CLI (after report): root devDependency `"modern-web-guidance": "0.0.194"` (exact), `pnpm install` records integrity
  `sha512-fjmKYa3N...` (CONFIRMED, `npm view`); 0 dependencies, 23.3 MB tarball. `modern-web-guidance list`
  printed 186 entries (trial run output, MEASURED once); the tarball holds 187 `.md` files under `guides/` (review
  count), gap unexplained.

Distribution repo tag v0.0.194 = b31dc0a43ff5d19bcf386a3476a216f3b39a6f55; generator repo `modern-web-guidance-src` @ f9b3ce6.

### Config diff

```diff
# refs/upstream/sources.lock.yaml (lead)
+  - id: modern-web-guidance
+    repo: GoogleChrome/modern-web-guidance
+    tag: v0.0.194
+    version: Modern Web Guidance 0.0.194 (skill-version 2026_10_12-dacb5911)
+    sha: b31dc0a43ff5d19bcf386a3476a216f3b39a6f55
+    status: CONFIRMED
+    why: web-feature advice for optimized and proposal variants (advice, not evidence)
+    paths:
+      - skills/modern-web-guidance/guides
# refs/upstream/PINS.md, table row (lead, with the lock entry)
+| Modern Web Guidance | `modern-web-guidance` 0.0.194 (npm) | `GoogleChrome/modern-web-guidance` `v0.0.194` | `b31dc0a43ff5d19bcf386a3476a216f3b39a6f55` | Tag resolved with `git ls-remote`; `skills/modern-web-guidance/guides` at the sha equals the npm 0.0.194 guides except generated files (`diff -rq`) | CONFIRMED |
# package.json (lead, after report)
-    "katex": "0.16.11"
+    "katex": "0.16.11",
+    "modern-web-guidance": "0.0.194"
# .claude/settings.json (user, after report, with the devDependency; no "env" entry)
   allow: + "Bash(DISABLE_TELEMETRY=1 pnpm -s exec modern-web-guidance search *)", "...retrieve *)", "...list*)"
   deny:  + "Bash(npx -y modern-web-guidance*)", "Bash(npx modern-web-guidance*)", "Bash(pnpx modern-web-guidance*)",
            "Bash(npx skills add*)", "Bash(pnpm -s exec modern-web-guidance install*)", "...update*)"
```

`DISABLE_TELEMETRY` sits in the command, not in settings `env`: Claude Code reads the same variable, and any non-empty
value turns off its own telemetry and its feature-flag fetching (https://code.claude.com/docs/en/env-vars, CONFIRMED).
In the command it reaches only the CLI.

New skill (after report): `.claude/skills/web-guidance/SKILL.md`, our words, under 2.5 KB, description under 300 B. Rules:
guides are advice ranked below CLAUDE.md and Lean proofs; target engines are WebKit iOS 27 and the pinned CI Chromium,
so no `@supports` branches or polyfills when web-features lists both; check `safari_ios` in web-features data; never
copy guide comments (name `no-comments`); no `### Modern Web Guidance` section, cite guide path@sha7 instead (name `no-slop`).

### Trial (CLI from scratch, `DISABLE_TELEMETRY=1`, MEASURED once, debug only)

| Query (our part) | Top guide | Similarity |
|---|---|---|
| carousel | carousel-snap-highlights | 0.68 |
| font fallback | visually-stable-font-fallbacks | 0.70 |
| hero LCP | optimize-preload-priority | 0.62 |
| sticky header | state-aware-sticky-headers | 0.70 |
| nav dropdown | resilient-context-menus-and-nested-dropdowns | 0.60 |

One search 0.72 s wall on node 24.14 (trial run output, MEASURED once); retrieving 4 guides gave 20 KB with `Baseline status` and `Supported by` lines.

### Per role

| Role | Use | When |
|---|---|---|
| lean-prover | `guidance-proofs`: each rendering rule is a conjecture under both engine models; cite the pinned guide path | when the guides are pinned |
| researcher | grep pinned guides for candidate features per part; confirm support in web-features data and engine source | after C3 |
| part-builder | feature choice for optimized and proposal variants (not faithful ports) via the `web-guidance` skill | after report |
| page-writer, measure-engineer | none worth the trigger cost | never |

### Overlap with ours

No overlap with the evidence chain: the guides measure nothing and cite Baseline data, not engine source. They overlap
with researcher work that lists optimization candidates per part (`10-18-optimization-inventory.md`).

### Risks and limits

- Telemetry on by default: query text, guide ids and agent name (`CLAUDECODE` detected) go to `play.googleapis.com`
  (npm modern-web.mjs:247,306-347; watchdog/main.js:13-90, CONFIRMED). Off with `DISABLE_TELEMETRY=1` or `true`
  (modern-web.mjs:266-275, CONFIRMED).
- Prompt pressure: SKILL.md:4 "MANDATORY: Execute FIRST for all HTML/CSS"; line 93 forces a disclosure section in every
  answer; a stale `--skill-version` makes the CLI print "insist that the user upgrade" (modern-web.mjs:575-590). All CONFIRMED.
- `Supported by` omits `safari_ios` when it equals desktop and never lists it as missing (src/core/baseline.ts:325-345@f9b3ce6,
  CONFIRMED). An iOS-only gap is invisible in guide text.
- Data lag: 0.0.194 (2026-10-12) predates web-features 3.43.0 (2026-10-15) (INFERRED from dates).
- Default policy is Widely available plus mandatory fallbacks (SKILL.md:115-131); fallbacks add style work on our fixed engines.
- Upstream SKILL.md is 7851 B with a 1011 B description and an em dash, over our skill budgets (CONFIRMED, `wc -c`).

## What this changes in the plan

- docs/plan/PLAN.md tooling section: add chrome-devtools-mcp 1.11.0 via Homebrew, project-scope, with the four flags and
  resolver rule; Modern Web Guidance enters only as a pinned upstream source before the report, CLI and skill after.
- research/kickoff/06-architecture-and-tooling.md:484: add `--headless`, `--no-performance-crux`, the resolver rule,
  "serve with measure-chromium server.mjs" and "only the last trace is kept".
- docs/team/work-graph.json: after-C3 task `cdt-triage` (researcher, per-part insight compare; needs the user's `tools:` and allow edit); after-report
  tasks `mwg-cli` (devDependency, skill, settings) and `feature-support-gate` (Lean, web-features subset, per-feature decision).
