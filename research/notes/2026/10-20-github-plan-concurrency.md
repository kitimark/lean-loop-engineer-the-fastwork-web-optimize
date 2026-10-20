---
id: 2026-10-20-github-plan-concurrency
kind: note
title: "GitHub Actions plans: which one raises our macOS concurrency"
status: draft
created: 2026-10-20
topics: [ci, capacity, macos, github-actions]
---

Question (user, 2026-10-20): can GitHub Actions pricing scale our macOS capacity? Pages read 2026-10-20.

## Answer

- Our limit is macOS concurrency, not minutes: minutes are free for public repositories on every plan (CONFIRMED [3]).
- Free, Pro and Team all cap macOS at 5 concurrent jobs; only Enterprise raises it to 50 (CONFIRMED [1]).
- Larger macOS runners do not help: they share the same macOS cap and are billed for public repositories too
  ($0.077/min 12-core, $0.102/min M2 Pro 5-core; CONFIRMED [1][2]).
- Enterprise Cloud costs $21 per user per month ("for the first 12 months"), with a 30-day free trial (CONFIRMED [3]).
  One seat would give 50 macOS and 500 total concurrent jobs while minutes stay free (INFERRED: the limits table is per
  plan and does not say whether it applies to public-repository minutes; a trial settles it).
- It needs the repository in an organization under an enterprise account (a transfer; GitHub redirects the old URL).
- "Enterprise with personal accounts" does not avoid the move: members sign in with their personal accounts, but the
  enterprise owns and bills organizations, and "Repositories are owned by organizations and are not directly accessible
  under the enterprise account" [4]; billing covers "usage within all organizations owned by the enterprise" [5]. A
  repository in a personal account stays on that account's plan (Free or Pro: 5 macOS) (INFERRED from [4][5]; neither page
  names personal repositories explicitly).

## Facts

| Plan | Price | Total concurrent | macOS concurrent | Status |
|---|---|---|---|---|
| Free | $0 | 20 | 5 | CONFIRMED [1] |
| Pro | paid | 40 | 5 | CONFIRMED [1] |
| Team | $4/user/month | 60 | 5 | CONFIRMED [1][3] |
| Enterprise Cloud | $21/user/month | 500 | 50 | CONFIRMED [1][3] |
| Larger runners (Team / Enterprise) | per minute | 1000 | 5 / 50, shared with standard | CONFIRMED [1] |

Job limit: 6 h per job on GitHub-hosted runners [1]. Per-minute list prices for private use: macOS standard $0.062,
Linux 2-core x64 $0.006, arm64 $0.005 [2].

## Context

- Other free macOS sources are under 1 % of demand each: CircleCI Free about 150 m4pro min/month at concurrency 1
  (10-20-circleci-free-tier.md), Bitrise Hobby about 150 to 300 min/month (10-20-bitrise-macos.md).
- The user's rule "never paid runners" (2026-10-18): an Enterprise seat is not a runner charge, but it is a payment;
  the decision is the user's.

## Sources

1. https://docs.github.com/en/actions/reference/limits
2. https://docs.github.com/en/billing/reference/actions-runner-pricing
3. https://github.com/pricing
4. https://docs.github.com/en/enterprise-cloud@latest/admin/concepts/enterprise-fundamentals/enterprise-accounts
5. https://docs.github.com/en/enterprise-cloud@latest/admin/managing-your-enterprise-account/creating-an-enterprise-account
