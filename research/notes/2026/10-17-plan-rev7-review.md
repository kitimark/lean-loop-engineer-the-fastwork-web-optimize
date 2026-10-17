---
title: Adversarial review of PLAN revision 7 (9ffa4fe)
date: 2026-10-17
status: CONFIRMED
---

# Adversarial review of PLAN revision 7

One fresh-context reviewer agent (workflow `review-r7b`, read-only) checked PLAN revision 7 and the explainer against the repo at a0e53b0.
Verdict: **fix-needed**, 15 findings. Fixes go to plan-rev7-1. Line numbers refer to 9ffa4fe.

## 1. high: docs/plan/PLAN.md §4.2 l.475-476, §0 l.125, §12.0 l.1443, A26 l.1527, App D row 4; docs/plan/loop-plan.html l.298, l.507

- Problem: The plan says the prebuilt WKTR 'runs on the iOS 26.5 runtime ... (CONFIRMED)' and 'runs on GitHub macos-26'. Nothing has been run. The source only shows that the archive was built against the iOS 26.5 SDK and that the runtimes exist.
- Evidence: research/notes/2026/10-17-wktr-on-github-actions.md l.17: 'Nothing was pushed and nothing was built'; the note's §0 says 'the spike can run on this Mac first'. docs/team/handoffs/wktr-ci.md: 'Nothing was run end to end. The first real test is the note's §4 steps 1-3'. Also unverified there: webkitpy picking the 27.1 SDK, and free disk on the CI label.
- Fix: In §4.2, write: 'is built with Xcode 26.5 against the iOS 26.5 Simulator SDK, which matches this Mac and the GitHub macos-26 image (MEASURED, 591a815); that it runs there is INFERRED until wktr-local'. Change 'runs on' to 'is planned to run on' in §0, §12.0, Q10, A26, App D row 4 and explainer l.298 and l.507.

## 2. high: docs/plan/PLAN.md §1.2 V-i 'Use' bullet l.182-183 (and the 6b4237e rationale it repeats)

- Problem: The plan rejects 'deterministic only' because it 'would drop trace.Layout, trace.Paint, trace.RasterTask and LayoutCount'. Under the plan's own signed-class rule (worst class over 3 or more runs), trace.Paint is quarantined, so it is dropped anyway. §4.2 l.435 says the same thing (Paint goes from stable to quarantined). The rationale contradicts the rule and hides that the main paint signal cannot be screened in Chromium.
- Evidence: packages/measure-chromium/classes.frozen.json: swipe-v1 trace.Paint class 'quarantined' (k 6, t 5); swipe-touch-v1 trace.Paint 'quarantined' and trace.RasterTask 'quarantined'. spk-i.md l.55: trace.Paint is quarantined in the 2nd and 3rd CI runs.
- Fix: Rewrite the bullet as: 'Deterministic only was rejected because it would drop trace.Layout, trace.RasterTask and LayoutCount (stable in the frozen swipe-v1 table). trace.Paint is quarantined in the frozen table (both profiles), so Chromium paint is not screened; K-model paint comes from WebKit or raster counts.' Add the frozen classes to §4.2.

## 3. high: docs/plan/PLAN.md §4.1 l.385 ('WebKit on the macos-26 image'); docs/plan/loop-plan.html l.497 and l.506 ('GitHub macos-26, iOS 26.5 runtime: WebKit counts on every change')

- Problem: The WebKit Simulator lane runs on the xcode-27 label with the iOS 27.0 (24A434) runtime, not on macos-26 or iOS 26.5. Only WKTR is meant for macos-26. The explainer also says 'on every change', but the CI Simulator runs fail at warm-up and are behind sim-speed.
- Evidence: .github/workflows/webkit-sim.yml:61 'runs-on: xcode-27' (same at 5a1dff2). docs/team/improvements/2026-10-17.md l.383: 'the runner's iOS 27.0 runtime is build 24A434 ... failed at warm-up'. research/notes/2026/10-17-macos-queue.md title: the slots are shared by xcode-27 and macos-26.
- Fix: §4.1: write 'WebKit Simulator counts on the xcode-27 image (iOS 27.0, 24A434); WKTR on macos-26 (iOS 26.5)'. In §4.6 Version skew, add the CI xcode-27 runtime. In the explainer: l.497 '(GitHub xcode-27 runners)'; l.506 'GitHub xcode-27, iOS 27.0 runtime | WebKit counts once sim-speed makes the runs pass'.

## 4. medium: docs/plan/PLAN.md §4.2 table l.434-437, §10.1 l.1317, §10.1 l.1350, §5.1 l.607, R33, App D row 3; docs/plan/loop-plan.html l.548

- Problem: Revision 7 was merged at 21:28, after chromium-ci (da287ff, 21:13), store-and-run (da3632e), gate-unreachable and macos-queue (56fe6c9, 21:18) had already landed. It still lists touch-ci-verify, class-freeze and store-and-run as open, says the `unreachable` cell is 'not built yet', and leaves out the frozen class table and the macOS queue findings. The requested numbers (frozen swipe-v1 27/25/10, touch 16/27/19) and the macos-queue facts appear nowhere in the plan or the explainer.
- Evidence: git log: da287ff 'class table frozen as worst over 3 runs: swipe-v1 27/25/10, touch 16/27/19' and 'touch fix verified on CI: 0 wedges, 9/9'; packages/measure-chromium/README.md l.243-262; the catch-up log df08408 lists chromium-ci and store-and-run as landed. `grep '16/27' PLAN.md` returns nothing. macos-queue note: our own jobs fill the 5 macOS slots (5 busy for 33.7 min), and an origin/main that is 142 commits behind starts every workflow.
- Fix: Either move the catch-up point to df08408 or add a revision 7.1 delta. §4.2: add the row 'CI, one pinned image, worst over 3 workflow runs (MEASURED, da287ff): swipe-v1 27/25/10, swipe-touch-v1 16/27/19; touch 0 wedges in 9 CI jobs'. Replace the local '21 runs' evidence with the CI result. Mark touch-ci-verify, class-freeze, store-and-run and gate-unreachable as done in §10.1 and §5.1. Add the macos-queue cause and budget to R33 (cite 56fe6c9).

## 5. medium: docs/plan/loop-plan.html l.548 (Measuring findings, touch row)

- Problem: The explainer says 'With it off, 21 local runs passed'. One of the 21 runs wedged and needed a retry.
- Evidence: docs/team/handoffs/touch-wedge.md: '21 runs, 11 at the default touch settle (0 wedges ...), 10 at settle 300 (1 wedge, next attempt passed)'.
- Fix: Write: 'With it off, 1 wedge in 21 local runs (passed on retry); on CI 0 wedges in 9 jobs (da287ff)'. In PLAN l.437, replace 'at most 1 wedge' with 'exactly 1 wedge'.

## 6. medium: docs/plan/PLAN.md §12.0 l.1443 (WKTR row in the 'Your decision' table); docs/plan/loop-plan.html l.298

- Problem: The plan presents 'prebuilt on macos-26, cloud Mac a fallback' as a user decision. The user gave no answer: the lead marked the console card done and read it that way.
- Evidence: docs/team/improvements/2026-10-17.md l.460-461: 'wktr-cloud-mac marked done without an answer (read as: no rental now, the prebuilt route first; the cloud Mac stays a fallback)'.
- Fix: Change the cell to: 'Lead reading (INFERRED): the card was closed without an answer, read as prebuilt first, cloud Mac as fallback (591a815; catch-up log seq 22)'. Or move the row to §12.2 defaults and ask the user to confirm.

## 7. medium: docs/plan/PLAN.md §0 l.112-113

- Problem: The plan says 'The Chromium counts lane is fast and deterministic'. That contradicts the revision 7 SPK-i decision: files are never byte-identical, classes drift between CI runs, and 10 to 19 types are quarantined.
- Evidence: PLAN §1.2 V-i 'No byte identity'; spk-i.md l.40 'Classes are not stable across CI workflow runs'; classes.frozen.json 10 and 19 quarantined types.
- Fix: Write: 'The Chromium counts lane is fast, and its counts are classed per type (most deterministic or stable, some quarantined; V-i)'.

## 8. medium: docs/plan/PLAN.md App D row 3 l.1592 and §4.2 l.437

- Problem: The touch fix is reported as 'MEASURED locally, 21 runs'. CLAUDE.md says 'A local run is never reported as a result', and the CI result already existed when revision 7 was merged.
- Evidence: CLAUDE.md, Measure on CI rule; b9bb373/da287ff '0 wedges in 9 jobs'.
- Fix: Cite the CI runs (39038973297, 39038976656, 39038979125; da287ff) as the result. Keep the local runs only as 'debug, cause found'.

## 9. low: docs/plan/PLAN.md §4.2 table l.446 and docs/plan/loop-plan.html (last findings row)

- Problem: The claim that CI Simulator runs take 10-38 min and fail at warm-up cites `10-17-ci-trigger-scope.md`, which contains neither number.
- Evidence: `grep -E '38 min|warm'` on the note returns nothing. The source is docs/team/improvements/2026-10-17.md l.383 and l.489.
- Fix: Change the source to `[CU]` (docs/team/improvements/2026-10-17.md, sim-speed entry) and tag it MEASURED.

## 10. low: docs/plan/PLAN.md R33 l.1414 and §4.1 l.391

- Problem: The plan says '5 macOS jobs at a time on the free plan' as a fact. The macos-queue note says the account's plan tier is unknown, and that a cap of 5 fits Free, Pro or Team (INFERRED).
- Evidence: research/notes/2026/10-17-macos-queue.md l.69-70.
- Fix: Write: '5 concurrent macOS jobs (the cap for Free, Pro and Team; our tier INFERRED), shared by xcode-27 and macos-26 and filled by our own jobs (MEASURED, 56fe6c9)'.

## 11. low: docs/plan/PLAN.md App D row 5 l.1594 (Source column)

- Problem: The source for the user's answers is given as 'the task', which nobody can check.
- Evidence: The answers are recorded in docs/team/improvements/2026-10-17.md l.457-461 ('Your console answers (read from the board, seq 22)').
- Fix: Replace 'the task' with '[CU] console answers seq 22 (docs/team/improvements/2026-10-17.md)'.

## 12. low: docs/plan/PLAN.md App D row 2 l.1591 vs §4.2 l.434

- Problem: Row 2 says 'stale 28/14/8 removed', but §4.2 keeps 28/14/8 as a 'superseded' row.
- Evidence: PLAN l.434: 'Local runs (rev 6): 28 deterministic, 14 stable, 8 quarantined of 50 types; superseded'.
- Fix: Change App D to 'stale 28/14/8 marked superseded', or delete the row in §4.2.

## 13. low: docs/plan/PLAN.md §4.2 findings table l.432-446

- Problem: Most rows have no status word (MEASURED, CONFIRMED or INFERRED); only a commit is given. Examples: the CI class row, the pixel-bound row and the touch-wedge row. The source notes tag them MEASURED.
- Evidence: spk-i.md l.49-51 and pixel-tolerance handoff l.25-29 tag these numbers MEASURED; PLAN rows carry no tag.
- Fix: Add a Status column, or put '(MEASURED, run 39029423874 ...)' in each row. Cite the CI run ids for 33/20/9, 31/21/10 and 27/25/10.

## 14. low: docs/plan/PLAN.md §12.1 Q35 l.1460-1463

- Problem: The plan recommends 'a', but the question lists no options a, b and c, so the user cannot see what 'a' means. Q34 does list its options.
- Evidence: 10-17-css-decisions.md l.136-140: options a (do not port), b (inert sheet with the same rule count), c (inert sheet sized to equal N4, not possible).
- Fix: Add: 'Options: (a) no inert sheet (today), (b) an inert sheet with the original's rule count (+40 % N4 rules), (c) a sheet sized to equal N4 (impossible).'

## 15. low: docs/plan/PLAN.md §0 l.117 vs docs/plan/loop-plan.html l.702 (and the math view l.752)

- Problem: The plan and the explainer give different Lean sizes: the plan says '37 modules, 490 declarations by 28b18ee', the explainer says '42 modules and 1,643 declarations by d41aef0', and the regenerated math view on main says 1898 declarations in 50 modules. Neither text is tagged as a snapshot.
- Evidence: `git show d41aef0:docs/plan/loop-plan.html` mv-count = 1643/42; HEAD mv-count = 1898/50.
- Fix: Use one dated figure in both files, for example '1,898 declarations in 50 modules at a0e53b0 (MEASURED, math view)'. Or have the explainer read the count from the generated block.
