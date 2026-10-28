# timed-m0-webkit: the 3 WebKit m=0 failures of run 40553185213 are an old reader, not the flip

Question: under `morph.geom:on,morph.tween:geom-timed`, why do 3 of 24 flip-cell readings fail on WebKit at m=0 (lang edges 80.97 px at 430x932 and 640x1000; columns 0, images 0 at 1920x1080) while Chromium passes 24 of 24?

## Forensics (MEASURED, run 40553185213 artifacts, results/timed-m0-webkit/run/timed-wk.json)
- The run is a push of `ci/geom-veil-restore` at 47f7fd747. That commit does not contain the reader fixes of task flip-verify-auto (e56ef0507 scroll-settle, 59fd94946 panel-mount agreement): `git merge-base --is-ancestor e56ef0507 47f7fd747` exits 1. Its JSON rows carry no `live`, `mount` or `recheck` fields, which the current reader writes (packages/gate-breakpoints/src/flip-cell.mjs:185-205).
- 1920x1080: flag page columns 0 and images 0, base 5 and 21. The morph panel mounts and unmounts on timers and an IntersectionObserver, so two pages differ in whether the columns exist (10-2x-flip-verify-auto.md, run 40525667335). Class (c) harness: the old reader did not wait for equal mount. Current reader: `waitMountAgree` and `bandNow` with cols 0 (flip-cell.mjs:127-139, 189).
- 430x932 and 640x1000: both pages are `is-hero-pill is-hero-chrome-ready` with equal pill rects, but the earn button is open (77 px) on one page and closed (0 px) on the other. At 430 the base is open, at 640 the flag is open. A rest difference caused by the arm would have the same sign in both bands; this one flips sign, so it follows page timing, not the flag. Class (b)/(c): the old reader scrolled back to the top without waiting for the target (the flip-verify-auto note measured the base page left at scrollY 2236 while the flag page was at 0) and read after a fixed sleep.
- (a) real rest difference: refuted by the sign flip and by later runs: with the current reader the timed cell passed m=0 in 12 of 12 bands on both engines (runs 40537879823, 40544410328, per 10-2x-flip-verify-auto.md).
- The premise fails: no site change and no Lean rest rule are needed for these 3 cells. The unit closes as a finding if the CI run below shows 24 of 24 on both engines at HEAD.

## Confirmation run (MEASURED, push 1 of 3)
Run 40660480093 (breakpoint-gate, ci/timed-m0-webkit at 4a8e758da, current reader, no site or Lean change): the geom-timed cell has 24 readings on each engine, 0 failed on Chromium and 0 failed on WebKit (12 m=0 readings graded and passing, 12 m=1 readings skipped as before: "flip not engaged"). Panel mount agreed on both pages in 12 of 12 bands; earn width 0 on both pages in every band (the new `earnW` field of `live`). JSON: results/timed-m0-webkit/run/timed-wk-40660480093.json, timed-cr-40660480093.json.
Note on "24 of 24": 12 of the 24 rows are m=1 rows, which the timed cell never grades (it scrolls, it does not wheel-push); the graded count is 12 per engine, the same rows that failed 3 times in the old run.

## Lesson (CONFIRMED)
A CI run's verdict belongs to the reader at the run's commit. Before chasing an engine difference, compare the run commit against the reader fixes with `git merge-base --is-ancestor`. Follow-up (not done): a reader-version stamp in the JSON.
