---
id: 2026-10-20-circleci-free-tier
kind: note
title: "CircleCI Free as a proxy for our CI jobs: capacity, fit, wiring and a pilot"
status: draft
created: 2026-10-19
topics: [ci, circleci, free-tier, measurement, webkit, chromium, lean]
---

Question: can CircleCI's free tier take some of our CI jobs, and how many job-minutes a month does it cover against our
demand? Sources were re-fetched on 2026-10-19. Local cites are at e25e6f97 unless a line names another commit.

## Answer

- CircleCI Free cannot take our macOS lanes. It gives at most about 150 m4pro.medium minutes a month at concurrency 1,
  against about 69,300 minutes a month of macOS-bearing workflow time (INFERRED, arithmetic below). That is 0.2 %.
- It can take part of our Linux Arm load. The open-source pool of 400,000 credits a month buys 33,333 minutes on
  `arm.large.gen2` (about 25 % of our 131,800 Linux minutes a month) or 66,667 on `arm.medium.gen2` (about 51 %, with half
  the vCPU). Both are upper bounds: CircleCI bills job-minutes, and our demand figure is run wall-clock (INFERRED).
- Three limits bind before the credits do: the 1-hour job cap, the 2 GB-month storage allowance, and the Lake cache,
  which saves about 1 GB about 4 times an hour (MEASURED, see Storage).
- No shortcut exists. CircleCI's "GitHub Actions workflow file" Preview rejects `ubuntu-24.04-arm` and macOS labels and
  ignores features we use. Each lane needs a port to `.circleci/config.yml` (CONFIRMED, see Wiring).
- Next step: a pilot on `premise-tests`, which has no Lake cache and short jobs, run 10 times on each of two Arm classes
  and compared with the same commits' GitHub runs (plan below).

## Free plan facts

| Item | Value | Status, source |
|---|---|---|
| Base credits | 30,000 a month, no rollover; Free cannot buy more; 5 active users (OSS projects do not count) | CONFIRMED, https://circleci.com/pricing/ ; credits doc https://circleci.com/docs/guides/plans-pricing/credits/ :56, :268 |
| Open-source credits | up to 400,000 a month for a public repo on Free; the docs say Linux, the pricing FAQ says Linux, Arm and Docker | CONFIRMED, credits doc :50, :293; pricing FAQ |
| How OSS credits turn on | sources disagree: the support article names a "Free and Open Source" toggle in Project Settings > Advanced; credits.adoc:40@circleci/circleci-docs 1ba9a0b says it is automatic and not shown in the web app | CONFIRMED (disagreement), https://support.circleci.com/hc/en-us/articles/360049928971 |
| Builds at 0 credits | OSS builds are "not subject to this block"; behaviour past 400,000 is not stated | CONFIRMED / UNKNOWN, credits doc :58 |
| macOS OSS credits | no extra pool; macOS uses the ordinary 30,000, shared with Windows, DLC and storage overage. The credits FAQ says 25,000 with 2 concurrent (:295), against 30,000 (:52) and concurrency 1 on the pricing page | CONFIRMED (sources disagree), support article; credits doc :52, :295 |
| Concurrency | 30 each for Docker, Linux VM, Arm VM and Windows; 1 for macOS | CONFIRMED, pricing page Key features |
| Soft limits | CircleCI applies "soft concurrency limits for each resource class", so 30 on one Arm class is not assured | CONFIRMED (text), INFERRED (effect on Free), configuration-reference :918 |
| Job cap | 1 hour on Free (GitHub: 6 h) | CONFIRMED, configuration-reference :210-216; https://docs.github.com/en/actions/reference/limits |
| Storage | 2 GB-months, billed once at save as size times retention; overage 420 credits per GB-month | CONFIRMED, credits doc :225-231; pricing page |
| Network | 1 GB, counts only traffic to self-hosted runners | CONFIRMED, pricing page |
| Retention | Free cannot customise it: caches and workspaces 15 days, artifacts 30 days; one artifact file at most 3 GB | CONFIRMED, persist-data :164-170; https://circleci.com/docs/guides/optimize/artifacts/ |
| Cache size cap | none documented | UNKNOWN |

GitHub Free for comparison: 20 concurrent jobs, at most 5 macOS, unlimited standard-runner minutes because the repo is
public (CONFIRMED, docs.github.com limits page; `gh repo view` reports PUBLIC, MEASURED). GitHub's cache is 10 GB per
repo (CONFIRMED earlier, not re-fetched).

## Capacity per resource class

Minutes are pool divided by credits per minute (INFERRED arithmetic on CONFIRMED rates from
https://circleci.com/pricing/price-list/ and https://circleci.com/product/features/resource-classes/). Share is against
131,800 Linux minutes a month.

| Class | Arch, size | Credits/min | Pool | Free min/month | On Free | Concurrency | Share of Linux demand |
|---|---|---|---|---|---|---|---|
| `arm.medium` (VM, Gen 1) | Arm 2 vCPU, 8 GB | 10 | 400k | 40,000 | yes | 30 | 30 % |
| `arm.large` (VM, Gen 1) | Arm 4 vCPU, 16 GB | 20 | 400k | 20,000 | yes | 30 | 15 % |
| `arm.medium.gen2` (VM, Beta) | Arm 2 vCPU | 6 | 400k | 66,667 | yes | 30 | 51 % |
| `arm.large.gen2` (VM, Beta) | Arm 4 vCPU, 16 GB | 12 | 400k | 33,333 | yes | 30 | 25 % |
| Docker `arm.medium` | Arm | 13 | 400k | 30,769 | yes | 30 | 23 % |
| Docker `arm.large` | Arm | 26 | 400k | 15,385 | yes | 30 | 12 % |
| Docker `small` | x86 | 5 | 400k | 80,000 | yes | 30 | not our arch |
| Docker or Linux VM `medium` | x86 | 10 | 400k | 40,000 | yes | 30 | not our arch |
| Windows `medium` | x86 | 40 | 30k | 750 | yes | 30 | none |
| `m4pro.medium` | macOS, 6 vCPU, 28 GB | 200 | 30k | 150 (125 at 25k) | yes | 1 | macOS: 0.2 % |
| `m4pro.large`, X-large, GPU | | 400 and up | | 0 | no | | |

- Gen 2 Arm "performance and pricing are tentative and may change" (CONFIRMED, configuration-reference :1316-1318).
- `ubuntu-2404:current` on Arm runs only on the Gen 2 Beta classes; Gen 1 Arm lists ubuntu-2004 and ubuntu-2204
  (CONFIRMED, https://circleci.com/docs/guides/execute/using-arm/). Our lanes run Ubuntu 24.04, so the Beta classes
  are the real choice.
- `arm.large.gen2` matches GitHub's `ubuntu-24.04-arm` at 4 CPU and 16 GB (CONFIRMED, configuration-reference :1309,
  :1322; https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- x86 classes would move us off arm64. The Lake cache key contains `runner.arch` (.github/actions/setup-lean/action.yml:57),
  and Chromium counts might differ by arch (INFERRED). The pilot stays on Arm.

## Our demand

MEASURED by the lead from `gh run list`, 2026-10-17 11:19Z to 2026-10-19 16:08Z (2.2007 days): 2,152 runs, 14,748
run wall-clock minutes; 1,048 runs were skipped or under 30 s. Scaled to 30 days (INFERRED):

| Group | Window minutes | Per month |
|---|---|---|
| Linux-only workflows | 9,665 | 131,755 |
| Workflows with a macOS job (webkit-sim, wktr, wktr-fixtures, gate-gaps, engine-premises, sim-speed) | 5,083 | 69,293 |

- The macOS figure is an upper bound on macOS time: those workflows also run `ubuntu-24.04-arm` jobs (6, 4, 4 and 4 in
  webkit-sim, wktr, wktr-fixtures and gate-gaps; MEASURED by grep of `runs-on`). Classing by job is pending the lead's
  job-minute sample.
- Job-minutes exceed wall-clock because jobs run in parallel, so every share above is an upper bound (INFERRED).
- 64 `runs-on: ubuntu-24.04-arm` lines in 15 workflows (MEASURED, grep).

**Job-minutes (lead's sample, added 2026-10-20).** Per workflow, the job/wall ratio from the 6 newest runs over 1 min
(87 runs, 405 jobs, MEASURED) times that workflow's wall total gives about 30,200 job-minutes in the window
(INFERRED): Linux Arm about 25,200, macOS about 5,000 (macOS jobs picked by job id from `runs-on`). Per 30-day month at
this pace: Linux Arm about 345,000, macOS about 68,000. So the 400k open-source pool covers about 10 % of our Linux Arm
job-minutes on `arm.large.gen2` (33,333) or about 19 % on `arm.medium.gen2` (66,667). Caveats: run wall time includes
queue time, and part of the sample ran during the 2026-10-19 GitHub Actions incident.

## Fit per workflow

| Workflow | CircleCI fit | Why |
|---|---|---|
| `premise-tests` | best pilot | jobs time out at 5, 15 and 10 min (premise-tests.yml:31, :60, :110); no Lake cache; uses `gate-engine` |
| `lean` | poor until the cache changes | build job timeout 60 min (lean.yml:54) sits on the 1 h cap; the Lake cache costs storage (below) |
| `chromium-counts`, `breakpoint-gate`, `visual-diff` | possible on a machine executor | the counts container runs with `docker run --rm --init --shm-size=1g` (packages/measure-chromium/src/host.mjs:58), so the job needs Docker: machine executor or Remote Docker (CONFIRMED source, INFERRED fit) |
| `gate-gaps` (Linux jobs) | machine executor only | it runs `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` (gate-gaps.yml:142); the docker executor gives no root (CONFIRMED, using-docker page) |
| `mutants` | no | timeout 75 min (mutants.yml:119) exceeds the 1 h cap; 19 other jobs set exactly 60 min (MEASURED, grep) |
| `webkit-sim`, `sim-speed`, `gate-gaps` (macOS) | no | 150 min a month at concurrency 1 |
| `wktr`, `wktr-fixtures`, `engine-premises` (macOS) | no | same budget; also CircleCI lists Xcode 26.5 on macOS 26.3.1 but does not show the iOS 26.5 runtime in it, and our lane selects `/Applications/Xcode_26.5.app` (wktr.yml:163-164) while CircleCI names it `Xcode-26.5.app` (INFERRED miss). The Xcode 27.0 image has iOS 26.5 and 27.0 runtimes (CONFIRMED, https://circle-macos-docs.s3.amazonaws.com/image-manifest/v19446/manifest.txt); 27.2 is a beta image replaced in place (CONFIRMED, using-macos.md:88@1ba9a0b) |

## Storage

- One Lake cache entry is 979.62 MiB, about 1.03 GB (MEASURED, `gh cache list --key lake-`, 2026-10-19).
- At the fixed 15-day retention one save costs about 0.52 GB-month. The 2 GB-month allowance holds about 4 saves a
  month; each further save costs about 216 credits (INFERRED).
- We saved 11 `lake-ARM64` entries between 13:58Z and 16:47Z on 2026-10-19, about 4 an hour (MEASURED). The key hashes
  `lean/*.lean` and `lean/Fw/**` (action.yml:57), so every Lean change saves a new entry.
- At that rate cache storage alone costs hundreds of thousands of credits a month (INFERRED). Overage "draws from your
  monthly credits" (credits doc :56), so by inference the 30k pool pays, which lasts about 139 extra saves. What
  CircleCI does to an OSS project whose 30k pool is empty while storage keeps growing is UNKNOWN.
- So `lean` moves only after the Lake key saves rarely (for example keyed on toolchain and manifest only) or the lane
  uses no CircleCI cache.

## Wiring sketch

Detail and the full user-step list: research/notes/2026/10-19-circleci-routing.md. Sources are in
circleci/circleci-docs@1ba9a0b.

1. Integration: the GitHub App, installed on this repo only, needs no deploy key; OAuth needs a deploy key and admin
   rights for hooks (CONFIRMED, version-control-system-integration-overview.adoc:83, :96-98, :107-109). Whether the
   App installs on a repo owned by a personal GitHub account is UNKNOWN (set-up-vcs-connections.adoc:47). This can
   block setup.
2. Trigger: GitHub App triggers filter event types, never branch patterns, and do not fire when a new branch is pushed
   with no new commits (CONFIRMED, github-trigger-event-options.adoc:27, :40-47, :52-63). Our `git branch -f
   ci/<name> HEAD` push often adds no commit, so `scripts/ci-push.mjs` pushes `ci/<task>` and then calls
   `POST /api/v2/project/<slug>/pipeline/run` with `definition_id`, `config.branch` and `checkout.branch` (CONFIRMED
   endpoint, triggers-overview.adoc:59-95; INFERRED that the branch must exist first).
3. Branch guard: delete the "All pushes" trigger. The docs describe that only for OAuth (set-up-triggers.adoc:134), so
   test that API runs still work after it (INFERRED). As a second guard, gate workflows on `pipeline.git.branch`
   matching `ci/` (CONFIRMED, using-branch-filters.adoc:28-60).
4. Status: CircleCI posts one commit status per job, `ci/circleci: <job>`, by default (CONFIRMED, status-updates.adoc:28-31).
   These are extra statuses; `fw land` keeps reading GitHub Actions only until a Lean rule says otherwise (INFERRED).
5. Results: `scripts/ci-push.mjs` polls `GET /project/{slug}/job/{n}` and downloads `GET /project/{slug}/{n}/artifacts`
   (CONFIRMED, api-developers-guide.adoc:512-525, :590-653). The API returns 429 with Retry-After and publishes no
   number, so poll at our `gh` interval of 120 s or more (CONFIRMED, :142-150). `fw ci wait` needs this second reader.
6. Exposure: build logs of a public project are public; project env vars are masked (CONFIRMED, oss.adoc:20-21,
   env-vars.adoc:115-117). Our jobs need no secrets.
7. No shortcut: the Actions-file Preview runs x86 only and accepts `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`,
   `ubuntu-20.04` and `self-hosted`. It ignores `concurrency` (15 of our files), `on:` filters and `retention-days`,
   always reports `cache-hit` false (1 use) and has no artifact `pattern` or `merge-multiple` (14 uses) (CONFIRMED,
   use-a-github-actions-workflow-file-as-your-pipeline-configuration.adoc:22, :231-235, :339; counts MEASURED by grep).

## Who does what

| User (in the browser or a `!` command) | Lead and teammates |
|---|---|
| Sign up for CircleCI Free | Write `.circleci/config.yml` for the pilot lane |
| Install the CircleCI GitHub App on this repo only, and report whether a personal-account repo is accepted | Specify the routing rule (which lane goes where) in Lean before code |
| Create the project; check Project Settings > Advanced for a "Free and Open Source" switch and turn it on if present | Add trigger, poll and download to `scripts/ci-push.mjs` |
| Delete the "All pushes" trigger | Test that API-triggered runs still work after the delete |
| Create a short-expiry personal API token and store it in the Keychain with a `!` command | Read the token with `security find-generic-password -w` inside `curl --header @<(...)`, so it never shows in `ps` (CONFIRMED guidance, security-recommendations.adoc:80-97) |

Tokens made in the web app have full read and write rights and expire, with reminder emails (CONFIRMED,
managing-api-tokens.adoc:18, :23-26, :88-92).

## Pilot measurement plan

- Lane: `premise-tests` on Linux Arm, both engine matrix legs plus the verdict job.
- Classes: `arm.medium.gen2` and `arm.large.gen2`, 10 runs each on commits that also ran on GitHub.
- Per job record: queue time (created to started), run time, resource class, credits (run minutes times rate, since the
  OSS balance is not shown), cache bytes saved, and the verdict.
- Compare each job with the GitHub run on the same SHA (`gh run list --commit <sha>`): run time ratio, queue time, and
  equal verdicts. A verdict that differs is a finding, not noise.
- Budget: 20 runs at about 25 job-minutes and at most 12 credits a minute is about 6,000 credits, 1.5 % of the pool
  (INFERRED; job length unmeasured until run 1).
- Stop rule: stop and report if any job hits the 1 h cap, a queue wait exceeds 10 min, or storage passes 1 GB-month.
- Output: a MEASURED table in a follow-up note, then a go or no-go for moving `chromium-counts` next.

## What this changes in the plan

- §11, R33: add that CircleCI Free is no mitigation for the macOS lanes (about 150 min a month at concurrency 1).
- §10, "Budget (free runners only)": add CircleCI Free as a candidate Linux Arm overflow lane, gated on the pilot above
  and on a Lake cache key that saves rarely; `mutants` stays on GitHub because of the 1 h cap.
- §12, the "No paid runners" decision row: CircleCI Free fits the rule; record that the pilot spends only free credits.
