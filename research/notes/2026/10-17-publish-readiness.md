---
id: publish-readiness
kind: note
title: Publish-readiness audit of the private repo (read-only)
status: CONFIRMED
created: 2026-10-17
topics: [publish, privacy, ci]
---

# Publish-readiness audit (read-only reviewer, written by the lead)

**Scope:** 378 tracked files, 72 commits, 27 branches (main plus 26 worktree-agent branches), 27 worktrees, at the
time of the audit. Personal values are deliberately not reproduced here; only counts and locations are given.

| # | Finding | Status | Fix if published |
|---|---|---|---|
| 1 | All commits use one GitHub handle and one personal webmail address, as both author and committer. The current tree contains neither | CONFIRMED | `git filter-repo --mailmap` to the GitHub noreply address, then set `user.email` to it; also rewrite or delete the worktree branches |
| 2 | Several recent commits carry a `Claude-Session:` trailer with a session URL | CONFIRMED | Strip it with a filter-repo message callback; leave it out of commits that will be public |
| 3 | No home paths (only synthetic fixtures and scrub regexes), LAN IPs, UDIDs, tokens or keys | CONFIRMED | none |
| 4 | `research/kickoff/08-chat-forensics/*` (5 files) paraphrases the user's v1 messages with timestamps. This is behavioural data, not PII | CONFIRMED | User decides: publish, or exclude the folder |
| 5 | No Fastwork code or assets in history; `snapshot.lock.json` holds only hashes and the origin URL; `refs/` holds only pins | CONFIRMED | Adding the compiled original needs the user's approval wording |
| 6 | `.gitignore` covers `.local/`, `snapshot/`, `.fw-console/`, `.cache/` and `.claude/worktrees/` on every branch | CONFIRMED | Review the wording of `.claude/agents/*` before publishing |
| 7 | No LICENSE, root README or `.github/` | CONFIRMED | LICENSE for our own code, excluding Fastwork material. README framing: personal educational study, not affiliated. Workflows: `permissions: contents: read`, no `pull_request_target`, actions pinned by SHA, fork PRs need approval |

**Options:**
- (a) Publish this repo with its full history. Keeps the timeline, but needs the rewrite in items 1 and 2.
- (b) Start a fresh public repo from a scrubbed snapshot of the tree. Simplest, but loses the history.
- (c) A separate public measure repo, with the harness, the site and the compiled snapshot, while this repo stays
  private. Lowest leak risk and fits the CI offload; the cost is keeping two repos in sync.

The reviewer recommends (c), or (b) if one repo is wanted.

## What this changes in the plan
PLAN §7.3 ("what never enters git") and §12 decisions need a user decision on the publish option, the license and
the commit identity before any public CI exists.
