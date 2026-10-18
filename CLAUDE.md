# fastwork-com-web-optimize-lean: agent guide

Experiment 2 of a personal, educational loop-engineering study of the public fastwork.com homepage (not affiliated
with Fastwork). Plan: `docs/plan/PLAN.md`; explainer page: `docs/plan/loop-plan.html`; research: `research/`.
The v1 repo `../fastwork-com-web-optimize` is read-only reference material.

## Team
- The main session is the **orchestrator (lead)**: it splits work, decides, reviews results, commits and talks to
  the user. Teammates and subagents do the work and report back.
- **Who commits:** in the planning phase only the lead commits. Once the build starts, named worktree subagents may
  commit inside their own worktree branch (`git add -- <paths>`, `git commit -m`); only the lead lands on `main`.
  Nobody runs `git push`.
- **Reporting:** send your result to the agent named "reports to" in your spawn prompt (the lead by default): at most
  ~300 characters plus file paths. Never write status; the console derives it from events.
- Each teammate writes only the files its task names. Two teammates never edit the same file at the same time.
- Durable results live in files (`research/`, `docs/`), never only in a message.
- **Handoff before you finish:** write or update `docs/team/handoffs/<your-name>.md` (≤ 30 lines: state with commit,
  conventions you followed, open items, what to read first) so a fresh agent can continue without your context.
- **Cache-aware resumes (lead):** subagent and teammate prompt caches live 5 minutes (MEASURED: all cache writes are
  `ephemeral_5m`). Resume an agent only while it has been idle < its own TTL, or when its context is < 30k tokens;
  never resume one > 250k. Otherwise stop it (`TaskStop`, no model turn) and spawn a fresh agent of the same role
  that starts from the handoff note. Never send a shutdown message to an expired agent: answering it costs a full
  context re-read.
- **Review loops (lead):** after a task's 2nd refused review of the same kind (each round patching the reviewer's
  newest probe), the lead stops patching: it writes the threat model (what the check must catch, what it need not)
  and picks a closed design (allowlist over deny-list, identity over inference, one canonical source over
  author-chosen inputs) before the next round, names it "final design round", and lists accepted limits so the
  reviewer judges against them. Incident `inc-review-loop` (docs/team/incidents/ledger.json).
- **Helpers:** lean-prover, researcher, plan-editor, measure-engineer and console-builder may spawn `scout`/`runner`
  (Haiku) and `checker` (Sonnet) per `docs/team/token-policy.md`; only the lead spawns `patcher`. Helpers are
  read-only unless named for an edit, never commit, write no handoff, and return ≤ 1k tokens to their spawner, not
  the lead.

## Rules
- The repo is going **public** (user decision 2026-10-17; MIT for our own code): treat every committed file as
  public. Only the user pushes `main`, adds remotes and creates repos. Agents may push only `ci/*` branches to
  `origin` to trigger CI (`git push origin ci/<name>`; never force, never delete, never `main`).
- **No personal data** in committed files: no emails, names, LAN IPs, device ids, home paths. `.local/` holds
  local-only data (v1 chat digests) and is gitignored; never copy from it verbatim.
- **Fastwork material:** Fastwork approved publishing its compiled site, fonts included. Its files enter git only
  as the unmodified snapshot under `snapshot/` (added by the publish-prep step, source noted); never copy its code
  into our code, and restate CSS values instead.
- **Install tools with Homebrew** (`brew install` / `brew install --cask`) when a formula or cask exists; otherwise
  ask the lead first.
- Claims carry a status: CONFIRMED (source, doc or measurement cited), INFERRED, MEASURED. Read the source code
  (WebKit, Chromium, Lean, libraries) before guessing; cite file:line@commit.
- **Upstream source, not WebFetch:** WebFetch summarises and truncates (100k chars, lossy), so never read source code
  through it. Read pinned sparse clones in `.cache/upstream/<repo>@<sha7>/` (gitignored; `node scripts/refs-fetch.mjs
  [<repo>] [--paths a,b]`, pins in `refs/upstream/sources.lock.yaml`). For a single file use
  `curl -fsSL https://raw.githubusercontent.com/<o>/<r>/<sha>/<path>`. For GitHub use the authenticated `gh` CLI
  (`gh repo clone`, `gh search code`), which has far higher rate limits; `gh api` stays denied (it can write).
  WebFetch is for docs pages only.
- **Measure on CI, not on this Mac** (user direction 2026-10-17): Chromium counts, WebKit Simulator counts, the
  breakpoint gate and WKTR run on GitHub Actions through a push of your `ci/<task>` branch; read results with
  `gh run view` / `gh run download`, never by re-running locally. This Mac measures only (a) the real phone in a
  session the user booked, (b) one short debug run (≤ 5 min, your own container or the sim-lock) while you change
  harness code, (c) a lane CI cannot run yet, named in docs/team/work-graph.json with the reason. A local run is
  never reported as a result.
- **Lean first** (console, site, measurement, tooling): every pure, reproducible piece (decisions, reducers, gates,
  breakpoint conditions, flag rules, motion curves, count reduction, verdicts, test matrices) is specified and proved
  in Lean *before* it is coded. Then either it runs in Lean (`fwcore`), or Lean generates it (constants, CSS media
  strings, JSON), or the TS/React code is checked against Lean-generated golden vectors. Only I/O, rendering and
  glue stay unproved, and they hold no decision logic. A TS stand-in is temporary and listed in your report.
- **Lean math:** every theorem's docstring carries its statement as LaTeX math, because the user reviews the math,
  not the Lean.
- **Processes:** never kill by app or pattern name (`pkill -f "Google Chrome"` closed the user's browser once); kill
  only PIDs your own run started, use separate browser profile dirs, and clean up child process groups you spawned.
- **Context:** never print > ~150 lines into context: filter (`grep -n`, `tail -40`), send long output to a scratch
  file and read excerpts; Read with offset/limit; do not re-read unchanged files.
- Answers to the user: answer first, short plain bullets, numbers in small tables.
