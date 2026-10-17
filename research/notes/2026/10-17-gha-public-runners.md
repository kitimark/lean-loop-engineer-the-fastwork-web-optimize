---
id: 2026-10-17-gha-public-runners
kind: note
title: "GitHub Actions for a public repo: hosted runners, limits, Docker/KVM, noise, security, gh CLI (as of Oct 2026)"
status: draft
created: 2026-10-17
topics: [ci, github-actions, measurement, webkit, chromium, safari]
---

Question: can a public GitHub repo run our Chromium and Safari/WebKit measurements on hosted runners, and does that help?
Status tags: CONFIRMED (doc/source cited, seen 2026-10-17), INFERRED, MEASURED (none here; nothing was run).
Doc pages were read through WebFetch (docs only, which the repo rule allows); runner-image READMEs were read with curl from
`actions/runner-images` `main` (no pinned sha; image versions below identify the snapshot).

## 1. Hosted runner specs, public repo
- CONFIRMED: "Use of the standard GitHub-hosted runners is free and unlimited on public repositories."
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- CONFIRMED (same page, public-repo table):

| Label | OS / arch | vCPU | RAM | Disk |
|---|---|---|---|---|
| ubuntu-latest, ubuntu-24.04, ubuntu-22.04, ubuntu-26.04 | Linux x64 | 4 | 16 GB | 14 GB |
| ubuntu-24.04-arm, ubuntu-22.04-arm, ubuntu-26.04-arm | Linux arm64 | 4 | 16 GB | 14 GB |
| ubuntu-slim | Linux x64 | 1 | 5 GB | 14 GB |
| macos-latest, macos-14, macos-15, macos-26, xcode-27 | macOS arm64 (M1) | 3 | 7 GB | 14 GB |
| macos-15-intel, macos-26-intel | macOS Intel | 4 | 14 GB | 14 GB |

- CONFIRMED: private repos get 2 vCPU / 8 GB for the same Linux labels (same page). So a public repo gets double the Linux box.
- CONFIRMED: `ubuntu-slim` is "hosted in a container on a shared VM" (single CPU); not for measurements.
- CONFIRMED: larger runners (more CPU/RAM, GPU) are a Team/Enterprise Cloud feature and "Larger runners are always charged for, even when used by public repositories"
  https://docs.github.com/en/billing/concepts/product-billing/github-actions . So no free larger or GPU runners.
- CONFIRMED browsers on images (runner-images main READMEs, seen 2026-10-17):

| Image | Version | Browsers |
|---|---|---|
| Ubuntu 24.04 | 20261012.334.1 | Chrome 155.0.8059.39, Chromium 155.0.8059.0, Firefox 157.0, Edge 155 (no Safari, no WebKit listed) |
| Ubuntu 26.04 | 20261012.163.1 | same browser versions |
| macOS 26 arm64 | 20260907.0351.1, macOS 26.6.2 | Safari 26.6.2, SafariDriver 26.6.2, Chrome 152.0.7977.83, Chrome for Testing 152, Firefox 155.0.1 |
| macOS 15 arm64 | 20260907.0337.1, macOS 15.7.9 | Safari 26.6.1, SafariDriver, Chrome 152 |

  Sources: `images/ubuntu/Ubuntu2404-Readme.md:9-11,148-154`, `Ubuntu2604-Readme.md`, `images/macos/macos-26-arm64-Readme.md:8-10,87-94`,
  `macos-15-arm64-Readme.md:8-10,87-89` (raw.githubusercontent.com/actions/runner-images/main/images/...).
- CONFIRMED: Playwright is not listed in any of these READMEs (grep for Playwright and WebKit: no hits). INFERRED: a workflow would install Playwright WebKit itself on Linux; real Safari runs only on the macOS images via SafariDriver.
- INFERRED: macOS runner Safari is whatever macOS ships; version is pinned by image, not by us. The Chrome on macOS (152) and Linux (155) differ from each other.
- Caveat CONFIRMED: the macOS arm64 table says 3 vCPU (M1) / 7 GB. Hardware may change; re-read before relying.

## 2. Cost and limits
- CONFIRMED: minutes for public repos on standard runners are free and unlimited (above). The 2,000/3,000 minute plan quotas apply to private repos only.
- CONFIRMED concurrency (standard, https://docs.github.com/en/actions/reference/limits):

| Plan | Total | macOS |
|---|---|---|
| Free | 20 | 5 |
| Pro | 40 | 5 |
| Team | 60 | 5 |

  The macOS cap is shared with larger runners. Support can raise limits.
- INFERRED: the page does not say whether public repos get a different cap than the table; we should assume the user's plan row applies.
- CONFIRMED: job max 6 h on hosted runners; workflow run max 35 days; matrix max 256 jobs per run; `workflow_dispatch` inputs max 25 properties, 65,535 chars.
- CONFIRMED: a run is discarded if not queued within 30 min of trigger or not picked up by a hosted runner within 45 min
  (https://docs.github.com/en/actions/concepts/runners/about-github-hosted-runners). INFERRED: macOS queues can be long at peak; budget for it.
- CONFIRMED artifacts: storage quota per plan is 500 MB (Free), 1 GB (Pro), shared with Packages (billing page); the limits page lists the same numbers. Retention default 90 days, settable 1 to 90 days for public repos (https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository).
- INFERRED (not stated for public repos): whether the 500 MB artifact quota is enforced for public repos was not found in the docs; the billing page lists storage by plan without a public-repo exception. Keep result artifacts small (JSON, a few MB) and commit or download-and-delete.
- CONFIRMED cache: 10 GB per repo, entries unused for 7 days are evicted, oldest-accessed evicted first when full; PR caches are scoped to the merge ref (https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
- CONFIRMED API rate: `GITHUB_TOKEN` 1,000 requests/hour/repo; PAT 5,000/hour (limits page). `gh run watch` polls at 3 s by default (about 1,200 req/h): use `--interval 30` or poll less.

## 3. Docker, nested virtualization, KVM
- CONFIRMED: Ubuntu images ship Docker Client/Server 28.0.4 (24.04) and 29.4.2 (26.04), Compose, Buildx (`Ubuntu2404-Readme.md:74-78`, `Ubuntu2604-Readme.md:71-75`).
- CONFIRMED: the macOS arm64 READMEs contain no Docker, Colima or Podman (grep count 0 in macos-26-arm64 and macos-15-arm64). So no Docker on macOS hosted runners without installing it. INFERRED: and installing a Linux VM runtime needs nested virtualization, which is not available (next bullet).
- CONFIRMED: "Nested-virtualization is not supported due to the limitation of Apple's Virtualization Framework" for arm64 macOS runners (hosted-runners reference page).
- CONFIRMED: Linux and macOS runners run with passwordless `sudo`.
- CONFIRMED: Linux hosted runners support hardware acceleration for Android SDK tools; the 2 Apr 2024 changelog extended it to 2-vCPU runners and gives the udev rule to open `/dev/kvm` (`KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"`, then `udevadm control --reload-rules` and `udevadm trigger --name-match=kvm`): https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/
- CONFIRMED (negative): the docs do not state "KVM is available" generally and give no guarantee ("no guarantees regarding stability, performance, or compatibility" for nested virtualization). Community reports from 2023 to Jan 2024 in actions/runner-images discussion 7191 say `/dev/kvm` was present on some runners and absent on others, then present on all free `ubuntu-latest` after 17 Jan 2024 (user report, not staff). INFERRED: usable but undocumented; we do not need KVM for browser measurement.

## 4. Noise for timing measurements
- CONFIRMED: Linux and Windows runners are Azure VMs; macOS runners are in GitHub's own macOS cloud / Azure data centers (two docs pages disagree on wording: reference page says "GitHub's own macOS cloud", concept page says "Azure data centers"). Each hosted runner is a new VM per job (except single-CPU). No documented VM size, CPU model, or isolation guarantee.
- CONFIRMED (absence): no official GitHub doc on performance variance or noisy neighbors was found in the pages read.
- Third-party claims, not independently verified: CodSpeed says standard hosted runners show significant variance and wall-time results are inconsistent (https://codspeed.io/docs/integrations/ci/github-actions); vendor marketing from runner resellers makes similar claims. INFERRED from the VM-on-shared-host design: absolute milliseconds will vary run to run and between hosts; per-run baselines and A/B in the same job are the safe design.
- INFERRED recommendation for our loop: use CI for deterministic counts (bytes, requests, DOM nodes, long-task counts, layout-shift sources, rendered pixel diffs) and for cross-engine presence (Chromium and real Safari), and treat wall-clock metrics as noisy: run N repeats inside one job, interleave A and B on the same VM, report medians with spread. Needs MEASURED confirmation: run the same job 10 times and compute the coefficient of variation before trusting any time-based gate.

## 5. Security for a public repo
- CONFIRMED: `pull_request` from forks: secrets (except `GITHUB_TOKEN`) are not passed; `GITHUB_TOKEN` is read-only (events reference page).
- CONFIRMED: `pull_request_target` runs in the base-repo context; running untrusted PR code there "may lead to security vulnerabilities" (events page; secure-use page). INFERRED rule for us: never use `pull_request_target`; never check out PR head with secrets.
- CONFIRMED: default for fork PRs: first-time contributors need approval; option "Require approval for all external contributors"; a user with write access approves. Personal-account repos default `GITHUB_TOKEN` is read-only for contents and packages (repository settings page).
- CONFIRMED: `workflow_dispatch` only runs if the workflow file is on the default branch; "Write access to the repository is required" to run it manually (https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow). So dispatch-only workflows can be triggered only by collaborators with write access. INFERRED: also set no `pull_request` trigger on measurement workflows, so a fork PR cannot burn runner time or read artifacts.
- CONFIRMED: pin third-party actions to a commit SHA; set minimum `permissions:`; pass untrusted `${{ }}` values via env vars; self-hosted runners "should almost never be used for public repositories" (secure-use page).
- CONFIRMED: anyone can read logs and artifacts of a public repo. INFERRED: no secrets, no private data in artifacts; and the repo content (Fastwork source and compiled site) is only published with their approval, which the user states exists (user statement, not verified by us). Our CLAUDE.md rule "private repo, no Fastwork code in git" must change before this plan: it needs the user's explicit decision.

## 6. Local agent: trigger and fetch
- CONFIRMED gh commands (https://cli.github.com/manual/): `gh workflow run <file> [-r <ref>] [-f key=value]` creates a `workflow_dispatch`; `gh run list [-w <wf>] [-b branch] [-L n] --json databaseId,status,conclusion,headSha,url`; `gh run watch <id> [--exit-status] [-i secs]`; `gh run download <id> [-n name | -p glob] [-D dir]`.
- CONFIRMED: `gh run watch` does not support fine-grained PATs (needs `checks:read`). INFERRED: use the classic `gh auth login` token, or poll with `gh run list --json`.
- CONFIRMED (repo file): `.claude/settings.json` allow list contains `gh repo clone`, `gh search code`, `gh search repos`, `gh auth status`; deny list contains `gh api*`, `gh pr *`, `gh repo create*`, `gh release*`, `gh gist*` (`.claude/settings.json:28-31,75-79@00c09bf`). `gh workflow` and `gh run` are in neither list, so they would prompt each time today.
- INFERRED: to use CI we need to add allow rules `Bash(gh workflow run *)`, `Bash(gh run list*)`, `Bash(gh run watch*)`, `Bash(gh run download*)`, `Bash(gh run view*)` (read-only except `workflow run`, which writes only a dispatch event) and keep `gh api*`, `gh pr *` denied. Each of those commands uses the API internally; deny rules match the command string, so they stay compatible. Also needs a remote and a push: CLAUDE.md says "Nobody runs git push; never add remotes". INFERRED: the user must push (or authorise a push of the CI branch), since dispatch runs the workflow file from the remote default branch.
- INFERRED loop: user pushes branch; agent runs `gh workflow run measure.yml -r <branch> -f ...`, waits with `gh run watch <id> --exit-status -i 30`, then `gh run download <id> -D .local/ci/<id>` and reduces the JSON in Lean/TS.

## Does it help? (INFERRED)
- Yes for: real Safari 26.x on macOS arm64 (SafariDriver is on the image), Linux Chromium/Firefox at 4 vCPU/16 GB for free, 20 concurrent jobs (5 macOS) which parallelises repeats, and a clean-VM reproducible environment that frees the local M1 (the local machine is oversubscribed per `10-17-parallel-capacity.md`).
- No for: low-noise absolute timings (shared cloud hosts, undocumented variance), GPU, Docker on macOS, larger runners (paid).
- Open risks: macOS queue latency, 500 MB artifact quota, repo must be public (policy change), push needed, `gh` permission changes.

## What this changes in the plan
- Measurement section: add a "CI lane" (public-repo GitHub Actions: ubuntu-24.04 Chromium + macos-26 Safari via SafariDriver, `workflow_dispatch` only) for counts and cross-engine checks; keep wall-clock gates relative (A/B in one job, median of N), until a 10-run variance MEASUREMENT exists.
- Repo/policy section: the "private repo, no push, no Fastwork code in git" rules must be revisited with the user (publication approval is user-stated); decide who pushes.
- Tooling/permissions section: add allow rules for `gh workflow run`, `gh run list|watch|view|download`; keep `gh api*` and `gh pr *` denied; poll interval 30 s.
- Next research task: MEASURE run-to-run variance on both runner types (10 identical runs) and verify Playwright WebKit and SafariDriver setup (`safaridriver --enable` is INFERRED to be needed; not checked).
