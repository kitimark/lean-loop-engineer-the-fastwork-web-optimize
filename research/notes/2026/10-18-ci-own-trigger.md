# CI runs start only when asked: the commit-message intent (task `ci-own-trigger`)

Date 2026-10-18. Lean: `lean/Fw/Ci/Intent.lean` (over `lean/Fw/Ci/Trigger.lean`). Golden:
`packages/contracts/golden/ci/intent.jsonl`. Glue: `.github/scripts/changed-inputs.mjs` (the guard), the guard job `if:` in
all 14 workflows (written by `scripts/ci-paths.mjs`), `scripts/ci-push.mjs` (`pnpm fw ci push`).

## The problem (forensics, 300 runs over 8 h, MEASURED by the task's forensics pass)

Only 56 of 300 runs (19 %) were read. About 3,400 of about 5,900 runner minutes (57 %) and about 460 of about 730 macOS
minutes went to unread runs. 156 of 159 cancels were manual. There were 41 ci pushes, and each started 6.5 workflows on average.

| class | runs | runner min | macOS min |
|---|---:|---:|---:|
| fan-out cancelled at once (≤ 3 min) | 115 | 194 | 11 |
| fan-out completed, nobody read it | 63 | 1,640 | 214 |
| fan-out cancelled late | 22 | 637 | 75 |
| integrate-ports-3 full run, unread | 13 | 494 | 95 |
| main push record | 10 | 224 | 3 |
| dispatch plus push duplicate | 17 | 41 | 1 |
| landed branch still running | 2 | 63 | 61 |
| superseded by concurrency | 2 | 15 | 0 |

Root causes:

- **(a) The push is the trigger.** `Fw.Ci.Trigger` answers "could this push change the workflow's result?". Nothing asks
  "does anyone want this result?". So a push starts every lane whose inputs it touched, and agents cancelled what they
  would not read, as fw-ci.md told them to.
- **(b) The guard's base `origin/main` was stale, by up to 11 h.** Agents cannot push main. So for a merge-main push or a
  first push the premise of `merge_starts_nothing` (∀x ∈ diff, ¬differs x) failed, and the fan-out started anyway.
- **(c) No rule stops a landed branch's runs.**
- **(d) Shared push/dispatch concurrency groups.** webkit-sim's group killed a dispatched run that the agent meant to read.

## Options weighed

| option | removes | why not chosen / chosen |
|---|---|---|
| A dispatch only (`on.push` off for ci/**) | a, d | agents need `gh workflow run` for every lane, which asks for permission; settings may not change. Dispatch stays the way to re-run or pass inputs |
| **B intent token in the head commit** | a; b only matters for lanes you asked for | **chosen**. Works with a plain `git push`. GitHub can evaluate it in the guard job's `if:` before any runner starts. The guard script re-checks it in full |
| C intent file in the tree | a | the file persists across pushes (stale intent) and adds diffs that need their own trigger rule |
| D fix the base only (merged-in main parent) | b | still fans out to every touched lane on a normal push; (a) stays |
| **E superseded / landed checks in the guard** | c, the backstop for supersede | **chosen with B** |
| F job-level concurrency | d | changes 14 hand-written groups; left as an open item |
| G a polling scheduler | a, c | needs a long-running service and a token with write rights |
| H default lanes only | part of a | it is B's no-intent default |

**Design: B + E.** On a push to `ci/**`, a lane (one workflow) starts iff all four hold:

1. **want.** The head commit message asks for it.
   - Intent format: the token `[ci:<lane>]`, anywhere in the message, in any case. `<lane>` is the workflow file stem
     (`lean`, `wktr`, `wktr-fixtures`, `webkit-sim`, `engine-premises`, `breakpoint-gate`, ...).
   - With any `[ci:` present, exactly the named lanes are wanted, and `[ci:none]` asks for nothing.
   - **No-intent default**: a message with no `[ci:` at all wants only the default lanes, which are just `lean` (ubuntu).
     A macOS lane is never a default (`default_no_macos`).
2. **changed.** This push changed one of the lane's inputs to something that differs from the base (`Trigger.starts_iff`
   on `effective`).
3. **not superseded.** No newer push on the branch changed one of its inputs. The guard reads the tip with `git ls-remote`.
4. **not landed.** The commit is not an ancestor of `origin/main` or of `origin/ci/landed`.

A main push, a dispatch or a schedule always runs, because a run there is a record.

**Where it is evaluated.**

- The guard job's `if:` is Lean `ifExpr`, a GitHub expression of `gate`. `contains()` is case-insensitive (GitHub docs,
  "Expressions → contains", CONFIRMED). When the lane is not wanted, GitHub skips the guard job and so every job that
  needs it: no runner starts.
- The guard script decides `start` in full.
- The YAML and the helper hold no decision. The `if:` text is generated from Lean, and the JS `decide` is replayed
  against the Lean cases in `scripts/ci-paths.test.mjs`. That test also evaluates every generated `if:` against Lean
  `gate`.

## Lean (lean/Fw/Ci/Intent.lean, all proved, standard axioms)

| theorem | statement (short) |
|---|---|
| `no_unrequested_start` | ci push ∧ start ⇒ (intent ∧ requested) ∨ (¬intent ∧ default lane) |
| `requested_and_changed_starts` | requested ∧ inputs changed ∧ ¬superseded ∧ ¬landed ⇒ start |
| `default_no_macos` | ℓ ∈ lanes ∧ ci push ∧ ¬intent ∧ start ⇒ default ∧ ¬macOS |
| `superseded_never_runs_heavy` | ci push ∧ superseded ⇒ ¬start |
| `landed_never_runs_heavy` | ci push ∧ landed ⇒ ¬start |
| `start_ci_iff` | `Trigger.starts_iff` restated: under intent, start ⇔ want ∧ (∃ changed input) ∧ ¬sup ∧ ¬landed |
| `no_lane_lost` | `coarse_sound` still holds: ConeWithin ∧ start ⇒ GitHub's paths filter passes ∧ the `if:` passes |
| `gate_eq`, `start_gate` | the `if:` equals ¬ci ∨ want, so it never skips a start |
| `tok_infix_inj` | for valid names, `[ci:a]` inside `[ci:b]` ⇒ a = b (`[ci:wktr-fixtures]` does not request `wktr`) |
| `unsuperseded_replays` | not superseded ⇒ the run's result equals the tip's (from `skipped_replays`) |
| `record_always_runs`, `intent_of_requested`, `default_lane_not_macos`, `close_inj` | helpers |

**What changes in `Trigger`.**

- `starts_iff` and `coarse_sound` are unchanged and are still used. `start_ci_iff` is their restatement under intent, and
  `no_lane_lost` reuses `push_filter_passes`.
- `merge_starts_nothing` still holds only under its premise. Under intent, a failed premise (cause b) can start only the
  lanes the head commit asked for, plus `lean` when it carries no token.
- The guard prefers `origin/ci/landed` over `origin/main` when that ref exists and contains main. That ref is a mirror of
  the landed main, which the lead's land step may push (open item).

## Replay on the 300-run history (INFERRED, by class; assuming agents name only the lanes they read)

| | before | after: plain push (no token) | after: `fw ci push --lanes <read lanes>` |
|---|---:|---:|---:|
| runs started per ci push | 6.5 (266 / 41) | ≤ 1 (`lean`, only if its inputs changed) | ≈ 1.2 (the read lanes plus their re-pushes) |
| macOS min per ci push | ≈ 17.7 (727 / 41) | 0 | ≈ 6.5 (the read macOS lanes only) |
| runner min per ci push | ≈ 138 | ≈ 10 (one `lean` run) | ≈ 66 |

**Removed: about 3,000 runner minutes and about 457 macOS minutes of the 8 h window.**

| removed | runs | runner min | macOS min |
|---|---:|---:|---:|
| instant cancels | 115 | 194 | 11 |
| late cancels | 22 | 637 | 75 |
| completed unread, except about 19 `lean` default runs (≈ 190 min stay) | 44 | ≈ 1,450 | 214 |
| integrate-ports-3, except its `lean` | 12 | ≈ 460 | 95 |
| duplicates | 17 | 41 | 1 |
| landed-still-running | 2 | 63 | 61 |

Unchanged:

- the 10 main records, by design;
- the 2 concurrency cancels, which are cause (d): see the open items;
- the 56 read runs.

## Measured on CI (branch `ci/ci-own-trigger`, 3 pushes)

Two pushes covered all three checks (MEASURED, `gh run list` / `gh run view`); a third was not needed.

| push | head message | runs created | runs started (≥ 1 runner job) | macOS min |
|---|---|---:|---|---:|
| 1 `3da2c3d` (via `fw ci push --lanes engine-premises`) | `ci: request [ci:engine-premises]` | 13 | 1: engine-premises 39106170371 (guard `run=true`, "2 of 56 changed files match") | 3.3 (webkit j1, then cancelled by push 2) |
| 2 `74ea297` (via `fw ci push --lanes lean`, no token needed) | no `[ci:` | 13 | 1: lean 39106360843, success (guard 6 s, lean 1.7 min, mathview 3.4 min) | 0 |

- In both pushes the other 12 runs ended `skipped` at the guard `if:`, so no runner started (for example lean 39106170390
  on push 1, and wktr 39106360904 and engine-premises 39106360862 on push 2).
- **Supersede.** Push 2 came 3 min after push 1 and changed `.github/scripts/changed-inputs.mjs`, an input of
  engine-premises.
  - Run 39106170371 was cancelled at 07:05:16Z, 2 s after the push, through workflow concurrency.
  - Its queued macOS jobs webkit j2 and j3 never ran. Only j1, already running, lost 3.3 macOS minutes.
  - Push 2's own engine-premises run was skipped because push 2 did not request it.
- Before, the same push touched all 13 workflows' inputs (as ci-trigger-lean did), so it would have started 13 runs,
  4 of them with macOS jobs. After, 1 run per push and 0 macOS minutes for the no-token push.
- The local preview of `fw ci push` ("2 of 56") matched the guard on CI exactly.

## Round 2: verdict, job-level concurrency, lean always (MEASURED on `ci/ci-own-trigger`, Linux lanes only)

- **Verdict.** `fw ci wait` used to pass every `success`. GitHub marks a run whose guard ran and decided `run=false`
  `success` (its other jobs are skipped), and a run skipped at the guard `if:` `skipped`. Now one charged
  `gh run view --json jobs` per finished run feeds fwcore `ci.verdict` (Lean `Fw.Ci.Verdict.pass_iff`).
  - (a) Push A 27b708f `[ci:difftest]`: premise-tests 39109453735 (not asked, `skipped`):
    `fw ci wait` → `not-run (guard if: the head commit does not ask for this lane)`, exit 4.
  - Push C 5e54c56 `[ci:difftest]` reverting B's line (no effective input change): difftest 39109671732 is
    `success` on GitHub; `fw ci wait --branch --workflow difftest` → `not-run (none of the 0 file(s) this push changed
    (and that differ from main) match the inputs)`, exit 4. The old wait would have passed it: a false pass, caught.
  - A's difftest 39109453745 → `pass`, exit 0 (guard 7 s, fwcore 49 s, fixed 13 s, rotating 19 s).
- **Past false passes** (13 charged gh calls: 1 list + 12 jobs views): of the 36 run ids cited in docs since the guard
  landed (fdb1468), 6 are this task's round 1 and 12 predate the guard's runs; of the 18 left, 12 are `success` and all
  12 ran their heavy jobs (6 on branches whose workflows had no guard yet). False passes found: **0**.
- **Job-level concurrency** (b). Push B ac589a4 (no request) touched a difftest input at 07:57:54Z while A's difftest
  ran: B's difftest 39109637694 was `skipped`; A's run was not cancelled and passed. Inconclusive on its own: A's last
  job ended 07:58:12Z, the second B's run was created. Repeated with a longer lane: B2_PLACEHOLDER
- **Lean always**: push A started lean 39109453769 with `[ci:difftest]` only (its inputs changed), `success`.

## Limits and open items

- ~~Workflow-level concurrency cancels in-flight runs on any newer push whose paths match~~ (cause d): fixed in round 2
  by job-level groups (see below).
- Supersede reads the newest tip's own push diff and message. If the tip wants lane X but an intermediate push (not
  wanting X) changed X's inputs and the tip's push did not, the older run is not superseded by the guard; its job group
  is then cancelled only when the tip's X job starts (INFERRED, by the Lean model `cancel_needs_newer_start`).
- A newer push that GitHub has not yet turned into runs is caught by the guard's ls-remote check. The concurrency cancel
  covers the rest. `superseded_never_runs_heavy` speaks about the guard.
- `landed` is only as fresh as `origin/main` or `origin/ci/landed`. Until the land step pushes `ci/landed`, a run whose
  guard ran before the user pushed main is not stopped (cause c, in part).
- Empty-commit pushes: GitHub's `on.push.paths` filter sees no changed file, so no run is created. `fw ci push` previews
  this and refuses. Re-running an unchanged lane is a dispatch.
- Case folding: Lean lowers ASCII only. GitHub's `contains` folds case more broadly. The tokens are ASCII
  (`lanes.all validName`), so the two can differ only on non-ASCII look-alikes in a message (INFERRED, harmless: it can
  only add a gate pass, and the guard script then decides by Lean's rule).
