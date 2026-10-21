---
id: 2026-10-21-azure-pipelines
kind: note
title: "Azure Pipelines as a CI overflow provider for a public GitHub repo (as of 2026-10-21)"
status: final
created: 2026-10-21
authors: [agent:researcher, agent:reviewer, lead]
topics: [ci, azure-pipelines, macos, webkit, providers]
---

Question: is Azure Pipelines (Azure DevOps Services) worth adding as an overflow provider next to GitHub Actions and CircleCI?

## Answer

No. Do not add it. Record it as a closed option.

- The public-project free tier is gone for us. Microsoft retired public projects in April 2026. A new org cannot create
  one, and existing ones convert to private in 2027 (CONFIRMED, [retirement page][ret]). What remains is the private
  free tier: 1 Microsoft-hosted parallel job, 60 min per job, 1,800 min per month. It needs an Azure subscription linked
  for billing (CONFIRMED, [concurrent-jobs][cj]).
- The free pool has no Xcode 27 and no Apple silicon. Its macOS images are macOS-14, macOS-15 and macOS-26, and all
  three run on Intel. The newest Xcode there is 26.6 (CONFIRMED, [hosted][hosted]; `macos-26-Readme.md:162`).
  `xcode-27` and arm64 macOS exist only in the pay-as-you-go "GitHub-hosted Agents" pool, which has no free tier
  (CONFIRMED, [github-hosted][gh]; [blog 2026-08-18][blog]).
- So webkit-sim, gate-gaps and sim-speed cannot run there for free. Of our macos-26 lanes, wktr and trajectory-probe
  would move from arm64 to Intel, which gives a new pool class (INFERRED). The extra capacity is 1 job and 30 h per month.

## 1. Free tier

| Item | State | Status |
|---|---|---|
| Public project, Microsoft-hosted | Unlimited minutes for existing public projects until they convert in 2027. New public projects cannot be created (since April 2026) | CONFIRMED [ret], [cj] |
| Private project (our only option) | 1 parallel job, 60 min per job, 1,800 min per month | CONFIRMED [cj], [hosted] |
| How to get the grant | Link an Azure subscription (set up billing); "the free grant automatically applies to private projects" | CONFIRMED [cj] |
| 2021 request form | Feb 2021: new public projects lost the automatic grant because of crypto-mining abuse. Jun 2021: a request form was added. The current concurrent-jobs page no longer mentions the form | CONFIRMED [blog21]; form status today INFERRED (absent from [cj]) |
| Paid | $40 per Microsoft-hosted parallel job per month, unlimited minutes, 360 min per job | CONFIRMED [cj], [price] |
| macOS in the free job | Parallel jobs count per org across all OSes, with no per-OS split documented. The 1 free job can use a macOS image | CONFIRMED [hosted] "Capabilities and limitations" (the free tier is listed for all Microsoft-hosted agents, macOS included) |

- **Stale product page (checked 2026-10-21 on the user's link).** azure.microsoft.com/en-gb/products/devops/pipelines still says "Get 10 free
parallel jobs with unlimited build minutes for all open-source projects" and carries no date. The docs supersede it: the retirement page
(ms.date 2026-04-30, updated 2026-05-18) says new public projects "can no longer be created", and the parallel-jobs page (updated 2026-06-22)
says existing public projects "retain their current free parallelism grants until they convert to private in 2027" (CONFIRMED, [ret], [cj]).

## 2. Images and hardware

| Pool | macOS | Xcode, iOS Simulator | Arch, spec | Linux arm64 |
|---|---|---|---|---|
| Microsoft-hosted (free tier) | macOS-14 (deprecated), macOS-15 (`macOS-latest`), macOS-26 | macos-26: Xcode 26.0.1 to 26.6 (default 26.6), iOS 26.x simulators; no 27 | Intel Mac Pro, 3 cores, 14 GB, 14 GB SSD. The macOS-15 arm64 preview is paused | none (Linux runs x64 Standard_DS2_v2, 2 vCPU, 7 GB) |
| GitHub-hosted Agents (PAYG, no free tier) | `macos-26-arm64`, `xcode-27` (public preview) | xcode-27 image: Xcode 27.0, 27.1, 27.2 beta; iOS 27.0 to 27.2 simulators | M1, 3 vCPU, 7 GB (standard). M2, 5 vCPU, 14 GB (XL) | none (Linux is x64 8 or 16 cores) |

Sources: [hosted], [gh], [blog]; runner-images `images/macos/macos-26-Readme.md:8-10,162-183`,
`xcode-27-arm64-Readme.md:8-10,158-172` at `467caed` (CONFIRMED). The Apple-silicon roadmap page ([roadmap], ms.date 2024-11-22) is stale: its promise of Apple silicon GA "for newly
introduced macOS images" did not happen (macOS-26 shipped on Intel only), and the 2026-08-18 blog supersedes it. That blog
states that new macOS versions come "in the GitHub-hosted agents pool only" and that the Microsoft-hosted pool continues with
standard Intel agents (CONFIRMED, [blog]), so Xcode 27 is not planned for the free pool.

## 3. Concurrency and queue

- Parallel jobs are org-wide and shared by all projects. A job past the limit queues (CONFIRMED, [cj]). The free tier
  is 1, so one macOS job blocks every other Azure job.
- New orgs can buy at most 25 Microsoft-hosted jobs (CONFIRMED, [cj]). PAYG allows 8 agents per SKU during the preview
  (CONFIRMED, [gh], [blog]). No per-OS cap like GitHub's 5 macOS is documented (INFERRED from [cj]).

## 4. Integration with this GitHub repo

- Connection: install the Azure Pipelines GitHub App on the account that owns the repo, either for all repos or for
  some. This needs a repo admin or org owner (CONFIRMED, [ghrepo] lines on GitHub App installation).
- User-only steps: create the Azure DevOps org and a private project, link an Azure subscription (Azure needs a payment
  method, INFERRED), install the app, and create a pipeline from an `azure-pipelines.yml`.
- Trigger: a `trigger:` branch filter on `ci/*` pushes works, or the REST call
  `POST https://dev.azure.com/{org}/{project}/_apis/pipelines/{id}/runs?api-version=7.1` with
  `resources.repositories.self.refName` and `templateParameters`. The call needs scope `vso.build_execute`
  (CONFIRMED, [runapi]). The PAT goes in the Keychain under its own service name, the same way as `fw-circleci-token`.
- Results: logs via `GET .../_apis/build/builds/{buildId}/logs/{logId}` with scope `vso.build` (CONFIRMED, [logapi]).
  Artifacts come from the Build Artifacts API (INFERRED, same API family, not fetched).
- Fork PRs: fork PR builds run by default once a PR trigger exists. Secrets and service connections are withheld from
  fork builds unless "Make secrets available to builds of forks" is on (CONFIRMED, [ghrepo]). We would set
  `pr: none` (INFERRED).
- Visibility: runs live in a private project, so public readers of the repo cannot see their logs (CONFIRMED, [ret]).

## 5. Fit for our lanes

| Lane | Needs | Free Azure pool | Status |
|---|---|---|---|
| webkit-sim, gate-gaps, sim-speed | Xcode 27, iOS 27 Simulator | Not available. Only PAYG `xcode-27` has it, and that is paid | CONFIRMED [hosted], [gh] |
| wktr | macos-26, Xcode 26.5, WebKit CI archive for the iOS 26.5 simulator | The image has Xcode 26.5, but on Intel. The archive is probably built arm64-only, so it would not run there | image CONFIRMED; archive arch INFERRED |
| trajectory-probe (apple) | macos-26, Playwright WebKit macOS build | Runs on Intel macOS-26 if Playwright ships an x64 macOS 26 build. It would be a different pool class | INFERRED |
| Linux lanes | ubuntu-24.04-arm | No arm64 Linux; x64 with 2 vCPU | CONFIRMED [hosted] |

Job time: the PAYG standard macOS agent has the same spec as a GitHub standard arm64 runner (M1, 3 vCPU, 7 GB). Azure
says those agents run "on the same infrastructure as GitHub Actions larger runners" (CONFIRMED, [gh]). So
`xcode-27` job times would match GitHub's (INFERRED). Times on the free Intel pool are unknown, since we have no
measurement. Booting a Simulator and running Safari is possible on any hosted macOS image with Xcode (INFERRED).
ios_webkit_debug_proxy would be installed by Homebrew in the job, as on GitHub (INFERRED). All our lane caps (38 min
at most, 10-20-macos-pool-v2.md §2) fit the 60-min free job limit (CONFIRMED by comparison).

## 6. Recommendation

Do not add Azure to `ci-route` or to the pool fallback.

| Reason | Detail | Status |
|---|---|---|
| No free Xcode 27 | The lanes that overflow (webkit-sim) need it. Running them on PAYG is macOS spend, which the user rules out | CONFIRMED [gh]; rule from task |
| Capacity | 1 concurrent job and 1,800 min per month. That is 1 Intel macOS slot next to GitHub's 5 arm64 slots. Only Intel-tolerant lanes could use it, and none of those is webkit-sim | CONFIRMED [cj]; lane fit INFERRED |
| Engine identity | Intel macOS-26 is a new (provider, class) pool key. Its results cannot pool with arm64 GitHub results until a pair verdict (`crossPoolOk` empty) | INFERRED from pool-v2 §5 |
| Setup cost | Azure subscription with billing, a private project, GitHub App, PAT, a third provider glue like `scripts/circleci.mjs` | CONFIRMED [cj], [ghrepo] |
| Risks | Free-pool images lag (macOS-15 arm64 preview paused; Xcode 27 is PAYG-only); the provider steers public OSS to GitHub. ToS for long benchmarks: not checked, and moot within 60 min | CONFIRMED [hosted], [ret]; ToS INFERRED |

Revisit only if Xcode 27 or arm64 macOS reaches the Microsoft-hosted free pool (watch [hosted] "macOS images updates").

## What this changes in the plan

- `research/notes/2026/10-20-macos-pool-v2.md` §5 (Fallback route): add one line that Azure Pipelines was checked
  on 2026-10-21 and stays out of `Provider` (no free Xcode 27 or arm64 macOS; free private tier is 1 Intel job). No
  Lean change.
- `docs/plan/PLAN.md` §12.0 Decisions: add "Azure Pipelines: not a provider (this note)".

[ret]: https://learn.microsoft.com/en-us/azure/devops/organizations/projects/public-projects-retirement?view=azure-devops
[cj]: https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops
[hosted]: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops
[gh]: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/github-hosted?view=azure-devops
[blog]: https://devblogs.microsoft.com/devops/apple-silicon-and-xcode-27-images-availabile-in-pay-as-you-go-preview/
[blog21]: https://devblogs.microsoft.com/devops/change-in-azure-pipelines-grant-for-public-projects
[roadmap]: https://learn.microsoft.com/en-us/azure/devops/release-notes/roadmap/macos-agents-apple-silicon
[price]: https://azure.microsoft.com/en-us/pricing/details/devops/azure-devops-services/
[ghrepo]: https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops
[runapi]: https://learn.microsoft.com/en-us/rest/api/azure/devops/pipelines/runs/run-pipeline?view=azure-devops-rest-7.1
[logapi]: https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds/get-build-log?view=azure-devops-rest-7.1
