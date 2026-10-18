# Handoff faithful-checks-rerun (round 2, verdict half)

State: branch worktree-wf_e6ffd6eb-9d3-4 (pushed as ci/faithful-rerun), main merged. This round is the review of record for the
4 faithful-checks commits plus round 1 (no land --allow). The page-root gate anchor is cut out: lean/Fw/Gate/PageRoot.lean, its
import and the anchors.json pageRoot role are removed; task gate-page-root-anchor owns it. Ledger finding gate.pageRoot.fixedInnerWidth
(model with fixed innerWidth refuted by the 645 px run).

Verdict (MEASURED, CI runs 39146329183 swipe-v1, 39146332555 swipe-touch-v1, 3 shards per arm, Lean-decided; unchanged): R fails
y04000, y04500, tail on both profiles, control passes. Note research/notes/2026/10-19-faithful-rerun.md; files results/faithful/*.verdict.json.

New (PROVED in Lean, golden-checked): Fw.Faithful.comparable (lean/Fw/Faithful/Comparable.lean; comparable_iff, refusal_sound,
unfaithful_refused, unobserved_refused, comparable_self; 645x1398 replay refused as "viewport"), op faithful.comparable + golden
packages/contracts/golden/faithful/faithful.comparable.jsonl (12 cases). Measured.lean states swipeV1_comparable and the control/touch twins.
zone-baseline.mjs carries preset, browser, viewport, innerWidthPx, innerHeightPx, scrollWidthPx into the zones file and baseline.source
(shards must agree); the 8 run files were regenerated from gh run download (no new measurement; only those fields changed; verdict blocks identical).
faithful.mjs verdict: per profile either a Lean verdict, or "NO DATA: <p>" / "not comparable: <field>" with verdict null in the file and exit 1.
Tests: packages/measure-chromium/test/faithful.test.mjs (47 pass in the package); lake build, mathview lint (0 failing), golden --check green locally.

Accepted limits: off-band causes (layout 0 vs 24, rAF, compositor census) undiagnosed (wave 1 input); 17/18 unlisted count types stay skipped
until refreeze; no new counts run; the frozen original A recorded no observed viewport, only its declared fields are compared (control is observed);
scrollWidth is recorded, not gated.

Lean CI: run 39150524865 (lean, success) at c0d79175 on ci/faithful-rerun, check.sh incl. the faithful golden check.
Open: (1) 10-18 note line 38 and handoffs/faithful-checks.md cite results/faithful/swipe-touch-v1.finding.json, removed in fe70ab0f (revision 44ab82b2 has it);
outside this task's writes. (2) regenerate after a refreeze:
zone-baseline.mjs baseline ..., faithful.mjs verdict, faithful.mjs lean.
Local: pnpm install --offline --frozen-lockfile first; after a bare lake build run lake build fwcore. Read first: Comparable.lean, then faithful.mjs (prepare, judge).
