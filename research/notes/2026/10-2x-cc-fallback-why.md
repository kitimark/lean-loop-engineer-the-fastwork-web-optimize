---
id: 2026-10-22-cc-fallback-why
kind: note
title: "Why the land did not overflow to CircleCI while GitHub Actions was degraded"
status: final
created: 2026-10-22
authors: [agent:researcher]
topics: [land, circleci, concurrency, overflow, storage, incident]
---

# Why the land did not overflow to CircleCI while GitHub Actions was degraded

Code read at commit 4cf7d910. Times are +07:00.

## Answer

- The second land of `gate-settle-scroll-timeline` (decision at 21:21:46) did ask CircleCI for all five legs. The storage
  stop refused it: the ledger read 1297 thousandths of a GB-month against a stop of 1000 (MEASURED from
  `.local/circleci-ledger.json`; rule `lean/Fw/Ci/Overflow.lean:132`, `lean/Fw/Ci/Provider.lean:224,265`). By
  `storage_stop_keeps_github` (`Overflow.lean:254`) every leg then stays on GitHub.
- The 1297 is an over-count of about 2x. The ledger holds every cache byte for 30 days, but CircleCI Free keeps caches 15
  days (CONFIRMED, `research/notes/2026/10-20-circleci-free-tier.md` Retention row). At the documented retention the same
  bytes are about 650, under the stop (INFERRED from the ledger bytes).
- The stop of 1000 is half the Free allowance (2 GB-months, CONFIRMED, same note, Storage row). It was the pilot's stop
  rule ("storage passes 1 GB-month", same note :177), reused for the overflow. The docstrings call it "the storage
  allowance" (`Provider.lean:223`, `Overflow.lean:101`), which is wrong by a factor of 2.
- The ledger never forgets a pipeline: `storageSoFar` sums every entry ever fetched (`scripts/circleci.mjs:446`), while
  `creditsSoFar` keeps a 30-day window (`scripts/circleci.mjs:451-454`). Today all entries are from 2026-10-21, so the
  missing window did not cause this refusal. It would keep the overflow off for good once the stop is passed.
- Refusing when storage is over the stop and GitHub is degraded is the intended policy (theorem
  `storage_stop_keeps_github`; module doc `Overflow.lean:8-9`). The defect is the storage number and the stop it is
  compared to, not the rule.
- The first land (decision about 21:07, 10 free GitHub slots, Actions operational) could not overflow: the status first
  read degraded at 21:22:34. Its refusal came from GitHub's lagging job status, which the land reads as a failed leg. The
  overflow plan is made once when the remote tier starts and never re-routes a leg that is pending or failed.

## (1) The storage value

| quantity | value | status |
|---|---|---|
| ledger file | `.local/circleci-ledger.json` in the main checkout (`apps/runner/src/land-overflow.ts:128`), last written 2026-10-21 23:06 | MEASURED |
| pipelines in it | 7, fetched 2026-10-21 21:49 to 23:06; one has no `at` | MEASURED |
| cache bytes | 1,294,676,789; four saves of 9.4, 371.1, 406.1 and 448.1 MiB | MEASURED |
| artifact and workspace bytes | 1,668,534 and 73,728 | MEASURED |
| `storageSoFar` (all bytes held 30 days) | 1297 thousandths of a GB-month | MEASURED, recomputed with `storageMilli` |
| caches and workspaces at 15 days, artifacts at 30 | 650 | INFERRED |
| stop `storageMaxMilli` | 1000 | CONFIRMED, `Provider.lean:224` |
| Free allowance | 2000 | CONFIRMED, free-tier note |
| credits in the 30-day window | 819 (the pool check passed) | MEASURED |

- Path of the number: `land.ts:610` gives `overflowFor` the `budget` of `realCircle`; `budget` calls
  `m.storageSoFar({ ledgerPath })` (`land-overflow.ts:161`); `storageSoFar` is `storageMilli(ledgerBytes(...), 30)`
  (`scripts/circleci.mjs:440,443,446`). `RETENTION_DAYS = 30` is documented as "an upper bound: caches and workspaces
  expire sooner" (`circleci.mjs:442`). CONFIRMED.
- The bytes are real: `pollOnce` writes what each `save_cache` step uploaded (`circleci.mjs:556-567`, Lean
  `cacheSavedBytes`, an upper bound by one tenth of a MiB). No unit error and no deleted artifacts. CONFIRMED.
- The reading is wrong in two ways. Retention is doubled for caches and workspaces. The sum has no time window, so it
  never resets for a new month (CircleCI bills a save once, at save time, as size times retention: free-tier note
  Storage row). CONFIRMED by reading the code; the size of the second error is 0 today (all entries younger than 30 days).
- `reason` checks credits before storage and storage before the key (`Overflow.lean:158-164`), so the checkout key
  was never judged in this decision. UNKNOWN whether it would have passed.

## (2) Is "storage over, keep every leg on GitHub" intended?

- Yes. `goesCc` requires `ccReady`, which requires `storageClear` (`Overflow.lean:132,138,149`); the theorems
  `overflow_needs_storage` (:244) and `storage_stop_keeps_github` (:254) state it. GitHub is the only other provider, so
  a refused overflow waits on GitHub. CONFIRMED.
- The user's rule is overflow on free budgets only (memory `ci-overflow-github-first`, `never-paid-runners`). Storage
  past 2 GB-months is not a payment: the overage is 420 credits per GB-month, drawn from the free credit pool
  (free-tier note Storage row and :119-121, CONFIRMED for the price, INFERRED for the pool). So a stop at half the
  allowance is stricter than the user's rule; it is a pilot safety margin, not a requirement.
- The same storage gate also removes CircleCI macOS from the pool tier (`lean/Fw/Ci/PoolTier.lean:46`,
  theorem `cc_storage_line` :191), so the over-count blocks that lane too. CONFIRMED.

## (3) Would the overflow have caught the lagging job status?

- No. The overflow plan is made once, when the remote tier starts (`land-overflow.ts:90-93`, "the plan made once").
  CONFIRMED.
- First land: the decision read Actions `operational` (health log 21:07:15 and 21:17:28 operational, first
  `degraded_performance` at 21:22:34, MEASURED from `.fw-console/health.jsonl`) and 10 free slots, so `github-first`.
  Its run 39792901389 completed with success while 4 jobs still read `in_progress` with an empty conclusion;
  `legResults` maps the empty string to a failed leg (`apps/runner/src/land-remote.ts:65-67`; incident
  `inc-land-leg-unfinished`). A failed leg is a refusal (`remote-lane-failed`), never a re-route. CONFIRMED.
- Second land: the slot snapshot at 21:21:46 held `webkit-sim` x2, `visual-diff`, `path-pix` = 6 + 39 + 4 = 49 slots
  (`.git/fw-gh-budget/overflow-slots.json`, widths `Overflow.lean:65-67`), so `ghFree` = 0 and `kept` = 0 whether or not
  the degraded flag was already open (MEASURED). Had storage been clear, all five legs would have run on CircleCI and
  GitHub's job-status lag could not have refused them (INFERRED).
- `ghStatusOnce()` is called without the watch's last flag (`land.ts:610`, default `prevDegraded = false`,
  `land-overflow.ts:166`), so an unreadable status page counts as not degraded in the land. Minor; it did not apply
  here. CONFIRMED.

## (4) Smallest fixes, each a Lean rule change

1. **Storage by documented retention and a 30-day window** (fixes this refusal). In `Fw.Ci.Provider`, add
   `retentionDays : Kind → Nat` (cache 15, workspace 15, artifact 30, cited to the free-tier note) and
   `storageNow (saves) now := Σ s ∈ saves, if now < s.at + 30 d then storageMilli s.bytes (retentionDays s.kind) else 0`,
   with an entry without `at` counted (the safe side). Theorems: `storageNow ≤` the old 30-day sum, and a save older
   than 30 days adds 0. `circleci.mjs` `storageSoFar` then checks against goldens of `storageNow`. Today's ledger gives 650,
   under 1000, and the second land would have gone to CircleCI.
2. **Name the stop for what it is.** Rename `storageMaxMilli` to `storageStopMilli` with the doc "half the 2000
   allowance (policy)", add `storageAllowMilli := 2000` and the theorem `storageStopMilli ≤ storageAllowMilli`; fix the
   `Facts.storage` doc to "thousandths of a GB-month". No behaviour change.
3. **Charge the overflow's own saves before it starts** (keeps fix 1 safe). `storageClear f n := f.storage + saveMilli
   ≤ storageStopMilli`, where `saveMilli` is one Lake save at 15 days (about 153, MEASURED in
   `research/notes/2026/10-2x-circleci-lean-cache.md`). One added term in `ccReady`.
4. **A pending leg is pending, not failed** (fixes the first refusal; already task `land-leg-pending`). Lean
   `laneState`: a job without status `completed` is pending. This is the fix for the lagging status, not the overflow.
5. **Follow-up, larger:** a re-route rule. When a GitHub leg has been pending past a deadline and `ghDegraded` reads
   true at that wait slice, start the same leg on CircleCI if `ccReady`, and take the first verdict
   (`binds_provider_blind` :283 already makes a result provider-blind). Not needed for this case once 1 and 4 land.

## What this changes in the plan

- CI overflow section: the storage gate counts saves at CircleCI's retention (cache and workspace 15 days, artifacts 30)
  within a 30-day window, and the stop is named as half the 2 GB-month allowance (fixes 1 to 3, one Lean task on
  `Fw.Ci.Provider` and `Fw.Ci.Overflow`, ahead of the next degraded-Actions land).
- Land section: `land-leg-pending` stays the fix for the refusals of 2026-10-22; a degraded-time re-route is a
  follow-up task, not part of it.
