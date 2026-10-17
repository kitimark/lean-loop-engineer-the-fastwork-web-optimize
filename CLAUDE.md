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

## Rules
- The repo is **private**; only the user pushes. Never add remotes or publish anything.
- **No personal data** in committed files: no emails, names, LAN IPs, device ids, home paths. `.local/` holds
  local-only data (v1 chat digests) and is gitignored; never copy from it verbatim.
- **No Fastwork code or assets** in git (the original stays in a gitignored local snapshot).
- **Install tools with Homebrew** (`brew install` / `brew install --cask`) when a formula or cask exists; otherwise
  ask the lead first.
- Claims carry a status: CONFIRMED (source, doc or measurement cited), INFERRED, MEASURED. Read the source code
  (WebKit, Chromium, Lean, libraries) before guessing; cite file:line@commit.
- **Lean:** prove as much as possible. Every theorem's docstring carries its statement as LaTeX math, because the
  user reviews the math, not the Lean.
- Answers to the user: answer first, short plain bullets, numbers in small tables.
