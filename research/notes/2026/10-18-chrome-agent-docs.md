---
id: 2026-10-18-chrome-agent-docs
kind: note
title: "Chrome Modern Web Guidance and DevTools for agents: no gain for the evidence chain; one config fix now, idea input after the report"
status: review
created: 2026-10-18
topics: [tooling, chrome-devtools-mcp, modern-web-guidance, privacy, evidence]
---

# Chrome Modern Web Guidance and DevTools for agents

## Answer first

| Page | Helps the experiment? | Where | Before the report? |
|---|---|---|---|
| [Modern Web Guidance](https://developer.chrome.com/docs/modern-web-guidance) | Yes, as a list of rules to prove or refute in Lean; no as evidence | Task `guidance-proofs`: each rendering rule as a theorem under the Chromium and WebKit engine models | Yes for the proofs (task exists, no deps); tool install after the report |
| [Chrome DevTools for agents](https://developer.chrome.com/docs/devtools/agents/get-started) | No new capability: it is `chrome-devtools-mcp`, which agents already run | Agent page inspection (already in use) | Only a config fix: pin 1.11.0 and add privacy flags (user edits user-scope config, ~5 min) |

- Neither tool counts engine work deterministically on CI. `chrome-devtools-mcp` traces use a fixed DevTools category set and no
  BeginFrameControl; Modern Web Guidance measures nothing. Our Lean-plus-CI-count chain stays as it is.
- Neither covers WebKit, so neither touches half the engine lanes.
- Concrete gains, all small and none evidence:
  1. Trace insights we do not compute: `ForcedReflow` and `LayoutShift` culprit attribution, `LCPBreakdown`
     (`performance_analyze_insight`). Useful to diagnose a part by hand; our `measure-chromium` emits counts, not attribution.
  2. A guide index (`motion`, `defer-rendering-heavy-content`, `optimize-image-priority`) to list candidates per part.
     Each candidate still needs an engine-source read and a Lean proof under both engine models.
  3. Hygiene: our live MCP entry runs `@latest` with no flags, so usage statistics are on, against note 06:484, and CrUX lookups are on as well (README:34-38@a878bca).

## Modern Web Guidance

| Our area | Helps | Why | Cost | When |
|---|---|---|---|---|
| CI work counts (`packages/measure-chromium`, Lean count models) | no | Returns Markdown guidance; produces no counts | n/a | never |
| WebKit lane (Simulator, WKTR) | no | Guides cite Baseline/MDN, not WebKit source; default target "Widely available" can hide iOS WebKit differences | n/a | never |
| Lean premises (engine models) | no | Guide text is not engine source; CLAUDE.md requires `file:line@commit` for premises | n/a | never |
| Lean theorem candidates (task `guidance-proofs`) | yes | Each rendering rule is a conjecture: proved, refuted or out of model under both engine models; a refuted rule is a finding | one lean-prover task | now |
| Part design ideas (React/MUI parts behind flags) | maybe | Indexes compositor-only motion, content-visibility, lazy loading, fetch priority, container queries | ~0 per query: `DISABLE_TELEMETRY=1 npx modern-web-guidance@0.0.194 search "<q>"`; a plugin install is a settings change via the user | after report |
| Report (2026-10-20) | no | Google reports "a 37 percentage point improvement in adherence" on its own graders (CONFIRMED, https://developer.chrome.com/docs/modern-web-guidance/get-started); a vendor benchmark, not engine-work evidence | n/a | never |

## Chrome DevTools for agents (`chrome-devtools-mcp`)

| Our area | Helps | Why | Cost | When |
|---|---|---|---|---|
| CI work counts | no | Fixed trace categories, no BeginFrameControl, officially only Chrome and Chrome for Testing (headless-shell unsupported, README:31@a878bca); load-centric CWV insights | n/a | never |
| WebKit lane | no | Chrome only | n/a | never |
| Breakpoint gate (`packages/gate-breakpoints`) | no | `emulate`/`resize_page` reproduce one viewport by hand; the gate is Lean-generated and CI-checked | n/a | never |
| Agent page inspection (part authoring, MUI style debugging) | already have | Same package agents already use. `get_css_styles` (cascade with `@layer`/`@media`/`@container`), `take_snapshot`, `emulate` (WxHxDPR, mobile, reduced motion) | ~5 min: user pins `chrome-devtools-mcp@1.11.0` with `--no-usage-statistics --no-performance-crux --isolated` | now |
| Diagnosing a part (why a count went up) | maybe | `ForcedReflow`/`LayoutShift`/`LCPBreakdown` insights attribute work to scripts or nodes; our harness does not | none beyond the above; interactive only, never a result | after C3 |
| Lighthouse audits | no | `lighthouse_audit` covers a11y, SEO, best practices, agentic browsing; no Performance; may resize or reload the page | n/a | never |
| Plugin skills, CLI daemon, WebMCP, PWA, memory tools | no | Do not touch our questions; CLI daemon persists in the background | n/a | never |

## Facts

| Fact | Status | Source |
|---|---|---|
| Modern Web Guidance is an agent skill set in early preview; embeds web-platform practice and browser-compat data | CONFIRMED | https://developer.chrome.com/docs/modern-web-guidance |
| npm `modern-web-guidance` 0.0.194, Apache-2.0, node >= 20, 33.4 MB unpacked, 255 files | CONFIRMED (`npm view`) | https://www.npmjs.com/package/modern-web-guidance |
| `search` runs a local TensorFlow.js model over the guides (no network, no key); `retrieve <id>` prints a guide | CONFIRMED | https://github.com/GoogleChrome/modern-web-guidance/blob/b31dc0a43ff5d19bcf386a3476a216f3b39a6f55/README.md |
| Telemetry on by default (agent name, guide ids, search queries) to play.googleapis.com; opt out `DISABLE_TELEMETRY=1` | CONFIRMED | same README, Telemetry & Privacy (opt-out); host from `package/skills/modern-web-guidance/watchdog/main.js` in npm pack 0.0.194 |
| Its skill text marks itself "MANDATORY: Execute FIRST" for HTML/CSS tasks and calls `npx ...@latest` | CONFIRMED (npm pack, `skills/modern-web-guidance/SKILL.md`) | https://www.npmjs.com/package/modern-web-guidance |
| Baseline target set by one CLAUDE.md/AGENTS.md line; default "Widely available" | CONFIRMED | https://developer.chrome.com/docs/modern-web-guidance/get-started |
| DevTools for agents = MCP server + CLI ("a targeted subset" of tools) + agent skills; needs Node LTS and stable Chrome | CONFIRMED | https://developer.chrome.com/docs/devtools/agents/get-started |
| `chrome-devtools-mcp` 1.11.0 is tag `chrome-devtools-mcp-v1.11.0` = a878bca | CONFIRMED (`git ls-remote`) | https://github.com/ChromeDevTools/chrome-devtools-mcp |
| `performance_start_trace` uses `-*` plus DevTools default categories plus JsSampling and Screenshot; not configurable | CONFIRMED | src/tools/performance.ts:81-90@a878bca |
| `performance_analyze_insight` takes insight names such as `DocumentLatency`, `LCPBreakdown` | CONFIRMED | src/tools/performance.ts:176-193@a878bca |
| No BeginFrameControl use in `src/` outside `third_party` | CONFIRMED (grep, research report) | src/@a878bca |
| Only Google Chrome and Chrome for Testing are supported; Chrome will not start as root in containers | CONFIRMED | README.md (Disclaimers), docs/troubleshooting.md:75-95@a878bca |
| Usage statistics on unless `--no-usage-statistics` or env `CI`; trace URLs go to CrUX unless `--no-performance-crux` | CONFIRMED | README.md:34-55@a878bca |
| Lighthouse use case lists a11y, SEO, best practices, agentic browsing; audits may resize or reload | CONFIRMED | https://developer.chrome.com/docs/devtools/agents/use-cases/lighthouse-audit |
| Our harness drives headless-shell with `enableBeginFrameControl`, `HeadlessExperimental.beginFrame` and custom categories (`devtools.timeline`, `cc`, `benchmark`, `blink_style`, ...) | CONFIRMED | packages/measure-chromium/src/run.mjs:63,114@117eaee3; src/trace.mjs:11-14@117eaee3 |
| Our harness computes no forced-reflow or layout-shift attribution | CONFIRMED (grep `ForcedReflow`, `LayoutShift` in `packages/measure*/src`: 0 hits) | @117eaee3 |
| Note 06 pins `chrome-devtools-mcp` 1.11.0 exploration only, `--no-usage-statistics`, `--isolated`; its numbers never count; v1 perf traces hung ~1 h | CONFIRMED | research/kickoff/06-architecture-and-tooling.md:68,484@117eaee3 |
| Project `.mcp.json` lists only serena, serena-lean, lean-lsp; the live chrome-devtools entry is user-scope `npx chrome-devtools-mcp@latest`, no flags | CONFIRMED (grep of repo and user config, 2026-10-18) | .mcp.json@117eaee3 |
| Chrome for Testing 155.0.8059.84 ships linux-arm64 `chrome` and `chrome-headless-shell` | CONFIRMED | https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json |
| The MCP server would run on ubuntu-24.04-arm with CfT Chrome | INFERRED (untested; not needed) | above |
| Insight attribution would shorten diagnosis of a regressed part | INFERRED | no measured case yet |

## Limits

- Modern Web Guidance read from README, npm pack and the docs page; no guide was checked against Chromium or WebKit source.
- `chrome-devtools-mcp` read at a878bca for `performance.ts` only; other claims rely on its README and docs.
- No run of either tool; no timing or token cost measured.
- Deadline rule: no new tooling before C3 (2026-10-19 23:15) unless it shortens the critical path. Neither does. The config fix
  is a privacy correction to an existing tool, not a new task.

## What this changes in the plan

- `docs/plan/PLAN.md` tooling section: no change to the evidence chain; both tools not adopted for evidence; Modern Web Guidance rules enter as theorem candidates through `guidance-proofs`.
- research/kickoff/06-architecture-and-tooling.md:484 (chrome-devtools-mcp row): add `--no-performance-crux` beside
  `--no-usage-statistics` and `--isolated`; lead hands the user the config edit (pin 1.11.0). The user-scope entry is shared with other projects, so a project-scope entry with the flags is the alternative; either is the user's change.
- After the report: optional idea step per part, `DISABLE_TELEMETRY=1 npx modern-web-guidance@0.0.194 search`, output
  labelled INFERRED until an engine-source read and Lean proof back it.
