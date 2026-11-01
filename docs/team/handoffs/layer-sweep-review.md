# layer-sweep-review handoff (console-builder, branch worktree-wf_d2d9d175-5d6-1)

State: CI strips run pushed (ci/layer-sweep-review at 18a6be4d6, lane visual-diff, tag [strips:layer-sweep]); Lean/TS/web work not started yet.

Done
- Harness: packages/premise-tests/src/{png.mjs,sweep-strips.mjs}, test/sweep-strips.test.mjs (7 pass). Faithful vs layer word,
  4 words stacked (Document, Earn, Secure, Organized), widths 390/1440, moments p0, f1 (16667 us), f2 (33333 us), t500, t2000,
  crop + 4x zoom + heat map; writes strips/<engine>-<w>-sweep-<moment>.png and strips/index.json (per word max/differing/over2).
- CI step: .github/workflows/visual-diff.yml shoot job (s0 shard, push, tip message has [strips:layer-sweep]); artifacts
  sweep-strips-chromium and sweep-strips-playwright-webkit, 30 days. premise-tests is a seeder lane: the push hook refuses it
  alone ("no-measuring"), so the step lives in visual-diff.
- lean/Fw/Ci/Trigger.lean: visual-diff row now reads sweep-strips.mjs and png.mjs (golden triggers.jsonl NOT yet regenerated).

Open (in order)
1. Wait: pnpm -s fw ci wait --branch ci/layer-sweep-review --workflow visual-diff; gh run download <run> -n sweep-strips-chromium
   (and -playwright-webkit); read strips/index.json; name run id R and expiry (+30 d) in the Lean rows.
2. Lean: ReviewStrips Moment (push | sweep), 20 sweep rows, Gen.lookDecisions row (kept, pending, after earn), Review ask text,
   Wire itemJson/stripJson fields, goldens (console/review.jsonl, preset look-change.candidates, ci/triggers.jsonl), guards.
3. research/findings/ledger.json platform.sweep.layer-sweep userDecision (date, "kept ...; visual review deferred to the console", review text with run/artifact/expires).
4. TS routes + Reviews.tsx (moment/label/ask), tests; research note research/notes/2026/11-01-layer-sweep-review.md.
5. Gate: check.sh, package tests, ci-paths test, land-inputs test, merge main, plan lint, dry land.

Limits to state on the card: strips come from a harness page built from the site CSS declarations and the snapshot font at dpr 1, not
the built site; local Chrome 155 debug numbers are not results; use index.json numbers of the CI run.
Read first: lean/Fw/Console/ReviewStrips.lean, lean/Fw/Wire/Review.lean, apps/console-api/src/review/routes.ts.
