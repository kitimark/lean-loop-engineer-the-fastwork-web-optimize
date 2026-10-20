---
id: bitrise-macos
kind: note
title: "Bitrise as free macOS overflow for the WebKit lanes (2026-10-20)"
status: draft
created: 2026-10-20
topics: [ci, capacity, free-tier, macos, webkit]
---

# Bitrise as free macOS overflow for the WebKit lanes

**Answer.** The documented free plan (Hobby) gives too little to matter. It has 300 credits a month. That is about 150
macOS minutes if a macOS minute costs 2 credits, and at most 300 if it costs 1. Our macOS demand is about 70,000
min/month, so Hobby covers under 0.5%. The images do fit. The `osx-xcode-27.1.x` stack has the exact iOS 27.0
runtime build that webkit-sim pins (24A434), and `osx-xcode-26.5.x` has Xcode 26.5 with iOS 26.5 for WKTR.

One path could change the answer, and it is unresolved. A Bitrise blog post from 2018, re-dated 2025-10-21, says public
(open source) apps get unlimited builds, 1 dedicated concurrency and a 45 min timeout, with no application. The 2026
pricing page has a "Public apps: Unlimited" row, but it shows no Hobby column. No current doc says whether a public app
uses credits. If the blog's terms still hold, Bitrise adds 1 macOS job slot, 20% on top of GitHub's 5. Only a real
account can settle it: the user adds this repo as a public app, runs one 5 min build and checks whether the credit
counter drops (UNKNOWN until then).

Access date for all URLs: 2026-10-20. Stack data: `bitrise-io/stacks@81a3e6d` (shallow clone, HEAD 2026-10-19).

## Findings

| # | Question | Finding | Status |
|---|---|---|---|
| 1a | Free plan size | Hobby: "1 private app, 5 concurrencies with 90 mins/build timeout and 300 credits per month" [1] | CONFIRMED |
| 1b | Public apps unlimited? | "Public apps … Unlimited" appears only in the paid comparison table (Starter/Pro/Enterprise); Hobby has no column there [1]. The public-projects doc says nothing about billing [2]. The 2018 OSS post lists "Unlimited number of builds", "One dedicated concurrency", "Build times up to 45 minutes" [3] | table CONFIRMED; whether it holds on Hobby in 2026 UNKNOWN |
| 1c | Hobby machines | macOS Medium (M4 5 CPU or M2 Pro 4 CPU, 6 GB RAM), macOS Large (M4 5 CPU or M2 Pro 6 CPU, 14 GB), Linux Medium (x86). No M4 Pro (4Large/4X Large) [1][4] | CONFIRMED |
| 1d | Which chip you get | "automatically assigns machine types from a resource class": M2 Pro or M4, which can differ between runs on the same day [4] | CONFIRMED |
| 2 | Credits per minute | Not stated on the pricing page or the machine-types page [1][4]. The pricing page lists dollars per minute instead (Medium $0.0072, Large $0.0096) [1]. TrustRadius quotes "1 credit = 1 min Linux, 30 s macOS" [8] | UNKNOWN (2 credits per macOS min from a secondary source only) |
| 3a | macOS 26 / Xcode 27 stack | `osx-xcode-27.1.x` rev v2026-10-16: macOS 26.6.2, Xcode 27.1, iOS runtimes 26.5, 27.0 (24A434), 27.1 [S1] | CONFIRMED |
| 3b | Xcode 26.5 stack (WKTR) | `osx-xcode-26.5.x` rev v2026-09-25: macOS 26.6.1, Xcode 26.5 (17F42), iOS 26.5 (23F77) [S2] | CONFIRMED |
| 3c | Safari version | Not in any stack report. Mobile Safari comes from the iOS runtime build, which matches. macOS Safari is UNKNOWN | INFERRED |
| 3d | New-stack speed | An Xcode beta becomes an Edge stack "a few days after" release; a GA Xcode becomes a new Stable stack; Edge stacks update weekly in place [5] | CONFIRMED |
| 4a | Trigger without a GitHub App | `POST /apps/{slug}/builds` with `build_params.branch` and a personal or Workspace API token, needing a developer role [6]. A GitHub Actions step on `ci/*` push (token as a repo secret) or `fw` can call it. Automatic webhooks need an OAuth-linked account with admin rights on the repo [7] | CONFIRMED |
| 4b | Results back | API `artifact-list` / `artifact-show` and `build-log` endpoints [9]. GitHub commit status needs either the GitHub App or a "service credential user" with Write access [10]; otherwise we poll | CONFIRMED |
| 4c | API rate limit | No official figure found. Jentic (third party) says about 60 req/s per token, then HTTP 429 [11] | UNKNOWN |
| 5a | Benchmark workloads | AUP 1.6 forbids crypto-mining and "other resource intensive tasks not related to the purpose of the Services" [12]. The ToS has no benchmark clause (grep of [13]) | CONFIRMED text; our lanes are test automation, so in scope INFERRED |
| 5b | Badge or application | None in the OSS post [3] or the public-projects doc [2]; a status badge is optional | INFERRED |
| 5c | Public logs | Anyone with the build URL can read logs and `bitrise.yml`, and a public app cannot later be made private [2] | CONFIRMED |
| 6a | Disk | 104 GB free (26.5 stack), 110 GB free (27.1 stack), on the M4 Pro host that made the report [S1][S2] | MEASURED by Bitrise; the free figure on Medium is UNKNOWN |
| 6b | sudo | The Linux 26.04 stack keeps "passwordless sudo" [S3]. macOS runs as `vagrant`, and sudo there is not documented. Our lanes use sudo only for `xcode-select`, which per-Xcode stacks make unnecessary | Linux CONFIRMED; macOS UNKNOWN |
| 6c | RAM | Medium has 6 GB; an iOS Simulator plus WKTR on 6 GB is tight, so use Large (14 GB, on Hobby) [1] | INFERRED |
| 6d | Playwright WebKit | Not preinstalled; node is on the stack [S1]. It downloads at run time, like on GitHub | INFERRED works |

## Verdict per path

| Path | macOS capacity/month | Concurrency | Timeout | Setup | Status |
|---|---|---|---|---|---|
| Hobby, private app | about 150 to 300 min (0.2 to 0.4% of demand) | 5 | 90 min | `bitrise.yml`, trigger step, artifact fetch | CONFIRMED credits; minutes INFERRED |
| Public app (2018 OSS terms, if still valid) | up to about 43,000 min (1 slot running all month) | 1 dedicated | 45 min | same, plus public logs | UNKNOWN |

| Lane | Fit on Bitrise | Status |
|---|---|---|
| webkit-sim (Xcode 27, iOS 27.0 24A434) | runtime build matches [S1] | CONFIRMED image; run untested |
| WKTR / wktr-fixtures (Xcode 26.5, iOS 26.5, prebuilt archive) | stack matches [S2]. Our 60 min job timeout exceeds the 45 min public-app cap, so split `passes` | INFERRED |
| Playwright WebKit trajectory probe (gate-gaps, `xcode-27`) | Large machine, Playwright fetched at run time | INFERRED |

**Risks.** (a) Runs land on M2 Pro or M4 at random. Counts are not affected, but any time-based lane is (INFERRED).
(b) A second CI config to keep in step with the GitHub workflows. (c) A Bitrise token as a GitHub secret on a public
repo. (d) Unclear AUP fit for measurement jobs. (e) Public logs show everything the job prints.

**Compared with the 10-19 note.** Hobby is smaller than Codemagic's 500 M2 min and much smaller than the GitLab for
Open Source pool (about 16,700 macOS min, INFERRED there). The only change: if Bitrise's public-app terms still hold,
it beats both. It would add a standing slot with no application and no pull mirror, only a 1-build test.

## Sources
1. https://www.bitrise.io/pricing (Hobby FAQ, machine table, plan table)
2. https://docs.bitrise.io/en/bitrise-platform/projects/public-projects
3. https://bitrise.io/blog/post/free-developer-plan-features-for-open-source-projects-on-bitrise (2018-08-31, "Last updated" 2025-10-21)
4. https://docs.bitrise.io/en/bitrise-platform/infrastructure/build-machines/build-machine-types
5. https://docs.bitrise.io/en/bitrise-platform/infrastructure/build-stacks/macos-stack-update-policy
6. https://docs.bitrise.io/en/bitrise-ci/api/triggering-and-aborting-builds
7. https://docs.bitrise.io/en/bitrise-platform/integrations/webhooks/adding-incoming-webhooks
8. https://www.trustradius.com/products/bitrise/pricing (secondary, via search snippet; direct fetch 403)
9. https://docs.bitrise.io/en/bitrise-api/api-reference/artifact-list
10. https://docs.bitrise.io/en/bitrise-ci/configure-builds/configuring-build-settings/reporting-the-build-status-to-your-git-hosting-provider
11. https://jentic.com/apis/bitrise (secondary)
12. https://bitrise.io/legal/acceptable-use-policy
13. https://bitrise.io/legal/terms-of-service
- S1: `data/osx-xcode-27.1.x/os.json:10,17`, `simctl_plain.txt:134-136`, `stack_rev_id.txt:1` @81a3e6d (github.com/bitrise-io/stacks)
- S2: `data/osx-xcode-26.5.x/os.json:10,17`, `apple.json:10`, `simctl_plain.txt:131`, `stack_rev_id.txt:1` @81a3e6d
- S3: `content/changelogs/ubuntu-resolute-26.04-bitrise-2026-android.md:74` @81a3e6d
- Our pins: `.github/workflows/webkit-sim.yml:253-254`, `.github/workflows/wktr.yml:3-5,116,164` (this repo, main @89eb170d)

## What this changes in the plan
- §11 R33 (CI capacity): add "Bitrise Hobby checked 2026-10-20 (`10-20-bitrise-macos.md`): about 150 to 300 macOS
  min/month, under 0.5% of demand; not a mitigation. Its stacks match the webkit-sim and WKTR pins".
- §12 open questions for the user: add "Bitrise public-app test. Add the repo as a public app on a free account, run one
  5 min build and read the credit counter. If no credits are used, a 1-slot Bitrise lane is worth a plan step". Same
  status as the GitLab for Open Source application. "No paid runners" does not change.

## Adversarial check (2026-10-20)

### Check of bitrise-macos.md (2026-10-20)
Sources re-opened live 2026-10-20: [1] bitrise.io/pricing (+ /pricing/teams, /plans-pricing), [2] public-projects doc,
[3] 2018 OSS blog, [4] build-machine-types doc, [12] AUP, workspace-billing doc; stacks clone @81a3e6dd (clean, HEAD 2026-10-19).

| # | Claim | Verdict | Reason / source |
|---|---|---|---|
| 1a | Hobby: 1 private app, 5 conc, 90 min, 300 credits | kept | [1] FAQ, verbatim |
| 1b | "Public apps Unlimited" only in paid table, no Hobby column | kept | [1] raw HTML: row "Public apps … Unlimited" is a single value after the Starter/Pro/Enterprise "Private apps: Up to 3/Unlimited/Unlimited" row |
| 1b' | OSS terms (unlimited builds, 1 dedicated conc, 45 min) | changed | [3] also says these equal the old paid "Developer Plan" (now gone), and that public apps hide artifacts from the public and block PR secrets. Missing from the note. Stays UNKNOWN for 2026 |
| 1c | Hobby machines Medium + Large, no M4 Pro | kept | [1] Medium "Mobile DevOps Platform Plan, Hobby and Starter"; Large "…, Velocity, Pro and Hobby". Nit: pricing gives M2 Pro @3.7 GHz, [4] gives @3.49 GHz |
| 1d | Random M2 Pro / M4 per run | kept | [4] "automatically assigns machine types from a resource class" |
| 2 | Credits per minute UNKNOWN | kept | No credit definition on [1], [4] or the billing doc. A search summary said the pricing page "confirms" 1 credit = 30 s macOS, but the live page and raw HTML have no such text. Only TrustRadius and KINTO 2023 (M1 Medium, 2 cr/min) say it |
| 2' | Hobby ≈ 150–300 macOS min | kept | arithmetic from 300 credits; INFERRED |
| 3a | osx-xcode-27.1.x: Xcode 27.1, iOS 26.5/27.0 (24A434)/27.1 | kept | data/osx-xcode-27.1.x/simctl_plain.txt:134-136; apple.json "Xcode 27.1 Build 27A9275"; stack_rev v2026-10-16; flavor stable |
| 3a' | "The images do fit" (webkit-sim) | changed | Bitrise host is macOS 26.6.2 (os.json). Our webkit-sim runs-on `xcode-27` = GitHub macOS 27 preview (.github/actionlint.yaml:1, webkit-sim.yml:245). No Bitrise Xcode stack runs a macOS 27 host (27.0.x, 27.1.x-edge, 27.2.x-edge are all 26.6.x; only osx-minimal reports macOS 27.2). Runtime matches, host differs, so counts parity is INFERRED, not CONFIRMED |
| 3b | osx-xcode-26.5.x: Xcode 26.5 (17F42), iOS 26.5 (23F77) | kept | apple.json:10, simctl_plain.txt:131, rev v2026-09-25; matches wktr.yml:3-5,116,164 |
| 4a/4b | API trigger and artifacts | changed | API kept. For a public app, [3] says artifacts are not shown publicly; API access with a token is untested (UNKNOWN). Add this to the pilot checks |
| 5a | AUP 1.6 "resource intensive tasks not related" | kept | [12] verbatim. Its examples also name "web scraping". Our lanes load a committed snapshot, not the live site (INFERRED in scope) |
| 5c | Public logs, never revertible | kept | [2] "You can't change this setting later!" |
| 6a | 104 / 110 GB free | kept | os.json df lines, measured on a g2.mac.m4pro host, not Medium/Large |
| demand | ~70,000 macOS min/month | kept | 10-20-ci-demand.md:8 gives ~68k job-min (10-19 note: 5,100 wall-min / 2.2 d) |
| 1 slot | +20% over GitHub's 5; ≤43,200 min/mo | kept, caveat | upper bound. The machine class of the public-app slot (Medium 6 GB vs Large) is UNKNOWN. On Medium, the RAM concern in 6c applies to the free slot |

## Fixes to bitrise-macos.md
1. Answer para 1: replace "The images do fit" with "The simulator runtimes match (iOS 27.0 24A434, iOS 26.5 23F77); Bitrise's Xcode 27 stacks run on a macOS 26.6.2 host, ours on GitHub's macOS 27 preview, so host parity is INFERRED".
2. Row 1b: add "[3] ties the terms to the retired Developer Plan; public apps hide artifacts publicly and block PR secrets".
3. Row 6c / verdict table: add "public-app slot machine class UNKNOWN (may be Medium, 6 GB)".
4. Pilot (§12): check 4 things in the one 5 min build: credit counter, machine class, host `sw_vers`, artifact fetch via API.
