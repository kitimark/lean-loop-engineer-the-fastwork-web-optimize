# Public CI for measurement: decision brief (2026-10-17)

Sources: `research/notes/2026/10-17-gha-public-runners.md` (GHA), `research/notes/2026/10-17-ci-measurement-feasibility.md`
(FEAS), `research/notes/2026/10-17-parallel-capacity.md` (CAP). **`research/notes/2026/10-17-publish-readiness.md` is missing**:
the audit agent ran read-only and replied as text. Its findings are summarized in §3 below (AUDIT), and the note still needs
to be written. Status tags: CONFIRMED, MEASURED, INFERRED. Nothing changes until the user decides (§4).

## 1. Does it help? Yes, for the counts and gate lanes. It does not help timing or device lanes.

| Lane | On public GHA? | Runner (free, public repo) | Gain | Status |
|---|---|---|---|---|
| Lean `lake build` + golden checks | yes | `ubuntu-24.04-arm` 4 vCPU / 16 GB | removes the heaviest local job (4-8 cores, 1.5-2.5 GB per clean build, CAP §6) | CONFIRMED runner, INFERRED gain |
| Chromium counts (Docker, BeginFrameControl) | **yes, as-is** | `ubuntu-24.04-arm` | same arm64 image and browser bytes as local (FEAS §1). N runs on N fresh VMs give the cross-machine V-i check that one Mac cannot | CONFIRMED inputs, determinism to MEASURE |
| Breakpoint gate, 124 loads × 2 engines (Chromium + Playwright WebKit/WPE) | **yes, best fit** | `ubuntu-24.04-arm`, 8 shards × ~16 loads | 20 concurrent jobs on Free (5 macOS) | CONFIRMED limits |
| WebKit Simulator totals (iOS 27.0) | probably | `xcode-27` (preview, 3 vCPU M1, 7 GB) | frees 1.5-2.5 GB and 1-3 cores per booted Simulator | runtime build 24A434 not confirmed (INFERRED) |
| Real Safari functional check | yes | `macos-26` / `xcode-27` (SafariDriver) | same 625.1.29 branch as the Simulator. Mac port, so not a counts stand-in | CONFIRMED image |
| Timing lane (ms) | **no** | (local) | shared VMs with undocumented variance | INFERRED |
| Device lane (iPhone over USB) | **no** | (local) | needs the phone | CONFIRMED |

How much it gains, in numbers:

| | Local Mac | Public GHA |
|---|---|---|
| CPU / RAM | 8 cores, 16 GB, load1 ~330-440, 3.5 GB swap in use (CAP, MEASURED) | 4 vCPU / 16 GB per Linux job, 3 vCPU / 7 GB per macOS job (GHA §1, CONFIRMED) |
| Parallel heavy jobs | about 1 Docker run plus 1 lake build at a time (CAP admission rule, INFERRED) | 20 jobs (5 macOS) on Free, 40 on Pro (CONFIRMED) |
| Cost | free | free and unlimited minutes for standard runners (CONFIRMED). Larger and GPU runners are paid even for public repos |
| One 503-frame Chromium run | ~85 s (MEASURED) | unknown until MEASURED. 6 h job limit (CONFIRMED) |

Caveats: macOS queue latency (runs are discarded if no runner picks them up within 45 min). The 500 MB artifact quota may
apply to public repos (unclear). `xcode-27` is a preview image with no SLA. CI counts stay a separate `platform` key until a
local-vs-CI V-b check passes for each count type. Before CI starts, add `--num-raster-threads=2` and `docker run --cpus=4` on
both hosts, because the raster thread count otherwise differs: 4 locally vs 2 on the runner (FEAS §1, CONFIRMED source).

## 2. What must stay local

| Item | Why |
|---|---|
| Timing lane (headed Chrome ms, Simulator Timeline ms) | ms measured on shared VMs are noise and do not come from the target host |
| Device lane, WDA finger-drag profiles | USB phone, UI session, wall-clock driven |
| Reference Simulator lane | stays the reference until CI agrees with it (V-b) |
| `.local/`, `.fw-console/` (events, secrets), `.cache/upstream/`, v1 chat digests | personal or operational data. Public logs and artifacts are world-readable |
| Trace dumps that embed page source | artifacts carry counts JSON only |

## 3. Options for going public (AUDIT verdict: not ready as-is)

AUDIT findings: all 72 commits carry a personal webmail address as author and committer. 4 commits carry a `Claude-Session:` URL
trailer. `research/kickoff/08-chat-forensics/` (5 files) holds personal behavioural data. There is no LICENSE, no README and
no `.github/`. No secrets, LAN IPs or home paths were found, and no Fastwork asset was ever committed. 26 worktree branches exist.

| Option | What | Pros | Cons |
|---|---|---|---|
| (a) | Publish this repo with full history | keeps the experiment timeline | needs a `git filter-repo` rewrite (email to noreply, strip session trailers, maybe drop chat-forensics), then a reset of all clones and the 26 worktree branches |
| (b) | New public repo from a scrubbed snapshot of the tree | simplest single repo, no history risk | timeline stays only in the private repo |
| **(c)** | **Separate public `measure` repo** (harness, Docker/Simulator lanes, workflows, Lean golden vectors, snapshot fetch). This repo stays private | lowest leak risk. Keeps the Fastwork-approved material apart. Fits CI offload exactly. No history rewrite | 2 repos to sync. Golden vectors and the `fwcore` build are vendored or exported per release |

**Recommendation: (c).** Choose (b) only if one repo is a hard requirement. Avoid (a) unless the public timeline is itself a goal.

## 4. Decisions the user must make

| # | Decision | Options / default proposal |
|---|---|---|
| D1 | Which option | (c) recommended / (b) / (a) |
| D2 | License for our own code | e.g. MIT or Apache-2.0. Fastwork material is excluded and keeps its own terms |
| D3 | Commit identity | GitHub noreply address for all public commits. For (a), a rewrite of the 72 commits. Keep or drop the `Claude-Session:` trailer on public commits |
| D4 | Who pushes, to which branches | proposal: only the user pushes to `main`. Agents may run `gh workflow run` (dispatch only) and never `git push`. Or: the user lets agents push a `ci/*` branch |
| D5 | Approval wording and scope | written statement for the README: who approved, what (our source? Fastwork's source? the compiled site?), and whether it covers fonts and images in the 61 MB snapshot (fonts may be third-party licensed, not Fastwork's to grant). Commit the snapshot, attach it as a release asset, or fetch it in the job |
| D6 | Chat-forensics data | publish or exclude `research/kickoff/08-chat-forensics/` |
| D7 | Rule changes | CLAUDE.md: "repo is private", "only the user pushes / never add remotes", "no Fastwork code or assets in git". `.claude/settings.json`: allow `gh workflow run`, `gh run list/view/watch/download`. Keep `gh api*`, `gh pr *` and `gh repo create*` denied |

## 5. Execution plan (waves, if approved)

**Before approval (agents, local only, nothing pushed, no remote):**
- write the missing `publish-readiness` note from AUDIT
- add the raster-thread pin (`--num-raster-threads=2`, `--cpus=4`) and re-MEASURE the local class table
- draft workflows in a local branch, with actions pinned by SHA and `permissions: contents: read`
- draft LICENSE/README text for review
- build the (c) tree layout and a scrub script (dry run)
- spec the result import (reducer, verdicts) in Lean first

| Wave | Work | Who | Exit |
|---|---|---|---|
| W0 publish prep | write the D-decisions into CLAUDE.md/settings. Run the scrub (D3/D6) or build the (c) tree. Add LICENSE, README (approval statement D5), `.gitignore` check. Do a final personal-data grep | agents prepare, user reviews | user creates the repo and pushes |
| W1 workflows | `lean` (build + golden), `chromium-image` (build once, digest), `chromium-counts` matrix, `breakpoint-gate` 8 shards. `workflow_dispatch` + push to `main` only. No `pull_request(_target)`, no secrets, fork PRs need approval, `persist-credentials: false` | agents (local), user pushes | green dispatch run |
| W2 harness | snapshot fetch with sha256 check against `snapshot.lock.json`. Separate `platform` key for CI. `webkit-sim` job on `xcode-27` (fails if the runtime is not 24A434) | agents | Chromium V-i class table MEASURED on 3 runner VMs, equal to the local table. 10-run CV MEASURED per runner type |
| W3 pull-back | `fw ci` = `gh workflow run` → `pnpm fw ci wait <runId>` (the shared poller; never `gh run watch` or a gh loop) → `gh run download -D results/ci/<id>/`. Reduce in Lean (`fwcore`). Console reconciler imports runs as events (CI run card, verdicts) | agents | console shows CI runs next to local runs. V-b local-vs-CI check per count type |
