# fastwork-com-web-optimize-lean: agent guide

Experiment 2 of a personal, educational loop-engineering study of the public fastwork.com homepage (not affiliated
with Fastwork). Plan: `docs/plan/PLAN.md`; explainer: `docs/plan/loop-plan.html`; research: `research/`.
The v1 repo `../fastwork-com-web-optimize` is read-only reference.

## Team
- The main session is the **lead**: it splits work, decides, reviews, commits and talks to the user.
  Teammates and subagents do the work and report back.
- **Commits:** named worktree subagents commit inside their own branch (`git add -- <paths>`, `git commit -m`); only
  the lead lands on `main`.
- **Reporting:** send your result to the agent named "reports to" in your spawn prompt (the lead by default): at most
  ~300 characters plus file paths. Never write status; the console derives it from events.
- Each teammate writes only the files its task names; two teammates never edit one file at once.
- Durable results live in files (`research/`, `docs/`), never only in a message.
- **Handoff before you finish:** write `docs/team/handoffs/<your-name>.md` (≤ 30 lines: state with commit, what is
  verified, open items, conventions, what to read first) so a fresh agent continues without your context.
- **Resumes (lead):** agent caches live 5 minutes. Resume an agent only while idle < its TTL or its context < 30k
  tokens, never one > 250k; otherwise `TaskStop` it and spawn a fresh agent of the same role from its handoff. Never
  send a shutdown message to an expired agent (it re-reads its whole context).
- **Review loops (lead):** after a task's 2nd refused review of the same kind (each round patching the reviewer's
  newest probe), stop patching: write the threat model (what the check must catch, what it need not), pick a closed
  design (allowlist over deny-list, identity over inference, one canonical source over author-chosen inputs, each unit
  decided on its own over a pooled or any-of aggregate), name the
  next round "final design round" and list its accepted limits for the reviewer to judge against. Incident
  `inc-review-loop` (docs/team/incidents/ledger.json).
- **Helpers:** lean-prover, researcher, plan-editor, measure-engineer and console-builder may spawn `scout`, `runner`,
  `checker` and `slop-checker` per `docs/team/token-policy.md`; only the lead spawns `patcher`. Helpers are read-only
  unless named for an edit, never commit, write no handoff, and return ≤ 1k tokens to their spawner, not the lead.

## Rules
- **Public repo** (MIT for our code): every committed file is public. Only the user pushes `main`, adds remotes
  and creates repos. Agents push only `ci/*` branches to `origin` to trigger CI (`git push origin ci/<name>`; never
  force, never delete, never `main`).
- **No personal data** in committed files: no emails, names, LAN IPs, device ids, home paths. `.local/` holds
  local-only data and is gitignored; never copy from it verbatim.
- **Fastwork material:** Fastwork approved publishing its compiled site, fonts included. It enters git only as the
  unmodified snapshot under `snapshot/` (source noted); never copy its code into ours, restate CSS values instead.
- **Install tools with Homebrew** when a formula or cask exists; otherwise ask the lead.
- **Claims** carry a status: CONFIRMED (source, doc or measurement cited), INFERRED, MEASURED. Read the source code
  (WebKit, Chromium, Lean, libraries) before guessing; cite file:line@commit.
- **Upstream source:** read pinned sparse clones in `.cache/upstream/<repo>@<sha7>/` (`node scripts/refs-fetch.mjs
  [<repo>] [--paths a,b]`, pins in `refs/upstream/sources.lock.yaml`). One file: `curl -fsSL
  https://raw.githubusercontent.com/<o>/<r>/<sha>/<path>`. GitHub: the `gh` CLI (`gh repo clone`, `gh search code`);
  `gh api` stays denied (it can write). WebFetch (truncates, summarises) is for docs pages only.
- **Measure on CI, not on this Mac:** Chromium counts, WebKit Simulator counts, the breakpoint gate and WKTR run on
  GitHub Actions through a push of your `ci/<task>` branch; read results with `gh run view` / `gh run download`,
  never by re-running locally. This Mac measures only (a) the real phone in a session the user booked, (b) one debug
  run (≤ 5 min, your own container or the sim-lock) while you change harness code, (c) a lane CI cannot run yet, named
  with the reason in docs/team/work-graph.json. A local run is never reported as a result.
- **Lean first** (console, site, measurement, tooling): every pure, reproducible piece (decisions, reducers, gates,
  breakpoint conditions, flag rules, motion curves, count reduction, verdicts, test matrices) is specified and proved
  in Lean before it is coded. Then it runs in Lean (`fwcore`), or Lean generates it (constants, CSS media strings,
  JSON), or the TS/React code is checked against Lean-generated golden vectors. Only I/O, rendering and glue stay
  unproved, and they hold no decision logic. A TS stand-in is temporary and listed in your report.
- **Lean math:** every theorem's docstring carries its statement as LaTeX math; the user reviews the math, not the
  Lean. Comment rules: `.claude/skills/no-comments/SKILL.md`.
- **Processes:** kill only PIDs your own run started, never by app or pattern name; use separate browser profile dirs
  and clean up child process groups you spawned.
- **Context:** never print > ~150 lines (filter, or write to a scratch file and read excerpts); grep before reading;
  Read with offset/limit; do not re-read unchanged files. Text agents read: `.claude/skills/no-slop/SKILL.md`.
- **Answers to the user:** answer first, short plain bullets, numbers in small tables.
