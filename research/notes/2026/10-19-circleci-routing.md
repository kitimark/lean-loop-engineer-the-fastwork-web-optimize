---
id: 2026-10-19-circleci-routing
kind: note
title: "Routing some ci/* jobs to CircleCI from a GitHub repo: GitHub App, API trigger, status, tokens, fork security"
status: draft
created: 2026-10-19
topics: [ci, circleci, github-app, security, tokens, routing]
---

# Routing some jobs to CircleCI while the rest stay on GitHub Actions

**Answer.** Use the CircleCI GitHub App integration, installed on this one repository only. Delete the default
"All pushes" trigger and start each CircleCI pipeline from our own script through the API v2 endpoint
`POST /api/v2/project/<slug>/pipeline/run`, with `config.branch` and `checkout.branch` set to the `ci/<task>` branch
and pipeline parameters naming the lanes to run. Two facts force the API path (both CONFIRMED). A GitHub App push
trigger has no branch-pattern filter, so it would create a pipeline for every push to every branch. And GitHub App
pipelines are "never triggered ... when a new branch is created if there are no new commits on the branch", which is
what `git branch -f ci/<name> HEAD` plus a push often does. CircleCI then posts one commit status per job
(`ci/circleci: <job>`) to the commit. Our script reads results and artifacts through API v2 with a personal API
token held in the macOS Keychain and passed to curl as a header file through process substitution, so it never
reaches argv, logs or the terminal. Fork PRs are safe by construction: GitHub App projects cannot build fork PRs at
all, and our CircleCI jobs need no secrets. The user must sign up, install the app, create the project and the token;
the lead does the config, scripts and Lean routing rule.

Docs read 2026-10-19 from the docs source, `circleci/circleci-docs@1ba9a0b` (paths below are relative to
`docs/guides/modules/`); live pages at `https://circleci.com/docs/guides/<module>/<page>/`. Plan limits and credit
rates are in `research/notes/2026/10-20-circleci-free-tier.md` and are not repeated here.

## GitHub App or OAuth

| Point | GitHub App | GitHub OAuth | Status | Source |
|---|---|---|---|---|
| Repository access | A chosen subset of repositories | All repos the user can reach; OAuth asks for "Add deploy keys" and "Add service hooks" admin rights | CONFIRMED | integration/pages/version-control-system-integration-overview.adoc:107; permissions-authentication/pages/users-organizations-and-integrations-guide.adoc:234-247 |
| Deploy key needed for checkout | No | Yes | CONFIRMED | version-control-system-integration-overview.adoc:96 |
| API trigger (`pipeline/run`) | Yes | Yes | CONFIRMED | version-control-system-integration-overview.adoc (API Triggers row); orchestrate/pages/triggers-overview.adoc:64-68 |
| Custom config path | Yes | No (fixed `.circleci/config.yml`) | CONFIRMED | version-control-system-integration-overview.adoc:118 |
| Build fork PRs, pass secrets to fork PRs | Not supported | Supported, both off by default | CONFIRMED | version-control-system-integration-overview.adoc:349-360; integration/pages/oss.adoc:97, 101, 108, 112 |
| GitHub Checks (workflow level) | Yes | Yes | CONFIRMED | version-control-system-integration-overview.adoc:184 |
| Run a GitHub Actions workflow file on CircleCI (Preview) | Yes | No | CONFIRMED | orchestrate/pages/use-a-github-actions-workflow-file-as-your-pipeline-configuration.adoc:9, 20 |
| How the org is created | `circleci` org created in the web app, then the app is added; or added to a `github` org | `github` org created at GitHub social login | CONFIRMED | users-organizations-and-integrations-guide.adoc:66-82 |
| Installing the app on a personal (non-org) GitHub account | Docs say "installed into an organization"; personal accounts are not mentioned | n/a | UNKNOWN | integration/pages/set-up-vcs-connections.adoc:31 |

Pick the GitHub App: least repository access, no deploy key, and no fork-PR builds to secure. OAuth would only add
fork-PR builds, which we do not want.

## Triggering on ci/* only

- **Push triggers.** The default first trigger is "All pushes"; the other GitHub App options are tag pushes, default
  branch, merge queue, and PR events. None takes a branch pattern (CONFIRMED,
  orchestrate/pages/github-trigger-event-options.adoc:27, 52-63). GitLab triggers have custom filters; GitHub App
  triggers do not (CONFIRMED, orchestrate/pages/set-up-triggers.adoc:100 is GitLab only).
- **Config-level filter.** A workflow `when: pipeline.git.branch starts-with "ci/"` or a job `filters:` expression
  skips work on other branches (CONFIRMED, orchestrate/pages/using-branch-filters.adoc:33, 57). The pipeline is
  still created on every push; whether an empty pipeline posts a status is not stated (UNKNOWN).
- **Branch-creation gap.** No GitHub App pipeline for a new branch without new commits (CONFIRMED,
  github-trigger-event-options.adoc:40-47). Our push form `git branch -f ci/<name> HEAD` then `git push origin
  ci/<name>` usually points the branch at a commit GitHub already has, so a push trigger would silently miss it
  (INFERRED from that rule).
- **API trigger (chosen).** `curl -X POST https://circleci.com/api/v2/project/<project-slug>/pipeline/run` with JSON
  `definition_id`, `config.branch`, `checkout.branch` and optional `parameters` (CONFIRMED,
  triggers-overview.adoc:68-100). The project slug and definition ID come from Project Settings (same lines). With
  the push trigger deleted, CircleCI runs only when our script asks. Pipeline parameters plus workflow `when:` pick
  the lanes (CONFIRMED, orchestrate/pages/selecting-a-workflow-to-run-using-pipeline-parameters.adoc exists; the
  pattern is in orchestrate/pages/orchestration-cookbook.adoc:143-147).
- **Rate limits.** API v2 throttles with HTTP 429 and usually a `Retry-After` header; no number is published
  (CONFIRMED, toolkit/pages/api-developers-guide.adoc:142-150). Same hygiene as gh: poll at a slow interval, honour
  `Retry-After`.

## Status back to GitHub

- Commit status updates are on by default, one per job, named `ci/circleci: <job>` (approval and no-op jobs get a
  workflow prefix) (CONFIRMED, integration/pages/status-updates.adoc:51, 57, 112). They attach to the commit, so
  they also appear on API-triggered runs of a `ci/*` branch (INFERRED).
- GitHub Checks (workflow level) need the separate "CircleCI Checks" GitHub App; with the GitHub App integration a
  check is named `<workflow> <first 8 chars of definition ID>` (CONFIRMED, status-updates.adoc:36, 146, 172).
  Optional for us.
- Reading these statuses from GitHub needs `gh api` (denied here) or a PR (`gh pr checks`). Read results from the
  CircleCI API instead (INFERRED from CLAUDE.md rules).

## Reading results and artifacts from a script

- Endpoints: `GET /api/v2/project/<slug>/pipeline`, `GET /api/v2/workflow/<id>/job`,
  `GET /api/v2/project/<slug>/job/<n>`, `GET /api/v2/project/<slug>/<n>/artifacts`, then download each artifact
  URL with the same header (CONFIRMED, toolkit/pages/api-developers-guide.adoc:333, 512-525, 590-653;
  optimize/pages/artifacts.adoc:188-201).
- Artifacts keep 30 days by default, which is also the maximum; one file at most 3 GB (CONFIRMED, artifacts.adoc:27,
  37). Artifacts are "protected with your CircleCI account for private projects", so on our public project they are
  likely public (INFERRED, artifacts.adoc:27). Whether API v2 reads of a public project work without a token is not
  stated (UNKNOWN).
- Auth header: `Authorization: Bearer <token>` (recommended) or `Circle-Token: <token>` (CONFIRMED,
  api-developers-guide.adoc authentication section).

## Token handling

- Only a **personal API token** works on API v2. It has full read and write rights on everything the user can reach
  and an expiry date set at creation, with mandatory reminder emails at 30, 15, 7 and 1 days. Project tokens are
  v1-only (Read Only, Admin) or status-only (CONFIRMED, toolkit/pages/managing-api-tokens.adoc:18, 23-26, 90-92).
  A leaked token is therefore an account-wide write credential (INFERRED).
- CircleCI's own guidance: pass the header from a 0600 file or from a secret store by process substitution,
  `curl --header @<(command_to_retrieve_password)`, so it never shows in `ps` (CONFIRMED,
  security/pages/security-recommendations.adoc:80-97). Our form:
  `curl --header @<(printf 'Circle-Token: %s\n' "$(security find-generic-password -s <service> -w)") ...`. The
  `security` call runs inside the substitution, so the token is never echoed (INFERRED; `printf` is a zsh/bash
  builtin, so the token never appears in argv).
- Our script must never run with `set -x`, never log request headers, and should redact any 401 body (INFERRED).

## Security model for this public repo

- Build logs of a public project are public; project environment variables stay hidden and are masked as `****` in
  output (CONFIRMED, oss.adoc:20-21; security/pages/env-vars.adoc:115-117).
- Fork PRs: off by default under OAuth, and secrets are withheld from fork builds by default (env vars, deploy and
  user keys, SSH keys, AWS settings; OIDC tokens too) (CONFIRMED, oss.adoc:101, 112-121). Under the GitHub App,
  fork-PR builds are not supported at all (CONFIRMED, overview :349-360).
- Who can start a run: only someone holding the personal token (API trigger) or push access (if a push trigger is
  kept) (INFERRED).
- Our measurement jobs need no CircleCI secrets, so even a mistaken setting exposes nothing (INFERRED). Keep it so: no
  project env vars and no contexts.

## Who does what

| Step | Who | Status |
|---|---|---|
| Sign up at circleci.com (GitHub social login or email) | User | CONFIRMED needs an account, users-organizations-and-integrations-guide.adoc:66-82 |
| Install the CircleCI GitHub App, selecting only this repository (needs repo admin) | User | CONFIRMED app install flow, set-up-vcs-connections.adoc:31; admin need INFERRED |
| Create the project and pipeline, choose the config path, delete the "All pushes" trigger | User in the web app (the API could do it once a token exists) | CONFIRMED, triggers-overview.adoc:39-44; set-up-triggers.adoc:40-58 |
| Turn on the open-source credit setting | User | see 10-20-circleci-free-tier.md |
| Create a personal API token with a short expiry and store it with `security add-generic-password` (a `!` command from the lead) | User | CONFIRMED token page, managing-api-tokens.adoc:30-33 |
| Optional: install CircleCI Checks | User | CONFIRMED, status-updates.adoc:158-165 |
| Write `.circleci/config.yml` (parameters, `when:` per lane, `m4pro.medium` with `xcode: 27.x` if ever used) | Lead or a teammate | Xcode 27.0, 27.1, 27.2 on macOS 26.6.2 CONFIRMED, ROOT/partials/execution-resources/xcode-silicon-vm.adoc:13-37 |
| Lean routing rule (which lane goes where) and its golden vectors | Lead or lean-prover | per CLAUDE.md |
| Extend `scripts/ci-push.mjs` to trigger, poll and download from CircleCI with the Keychain token | Lead or a teammate | INFERRED |

## Not a shortcut

The Preview feature that runs a `.github/workflows` file on CircleCI accepts only `ubuntu-latest`, `ubuntu-24.04`,
`ubuntu-22.04`, `ubuntu-20.04` or `self-hosted`, and rejects every other label, including `ubuntu-24.04-arm` and all
macOS labels. It also ignores `on:` filters (CONFIRMED, use-a-github-actions-workflow-file-as-your-pipeline-configuration.adoc:22,
231-235, 339). Our arm64 and macOS jobs would need a native CircleCI config anyway.

## What this changes in the plan

- **PLAN §4.1 Three lanes (CI routing):** if a CircleCI overflow lane is adopted, route it by API trigger from
  `scripts/ci-push.mjs`, never by a CircleCI push trigger; the lane set is a pipeline parameter decided by a Lean
  routing function. Use the GitHub App on this repo only, no CircleCI secrets, token in the Keychain.
- **docs/team/work-graph.json:** any CircleCI task starts blocked on four user steps (sign-up, app install, project
  with trigger deleted, token in the Keychain); macOS lanes stay on GitHub Actions per the free-tier note.
