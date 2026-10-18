# integrate-ports-4 handoff (round 2)

Branch worktree-wf_05b51fbd-31a-1. Gate run 1 = CI 39130842197 (ci/integrate-ports-4): all engine jobs green, merge job red.

## Failing Chromium readings (run 39130842197), row|col|reading, probes failing/comparable
- commission | sweep:desktop-1512-320-1512 | all stops: 57/57 (underline opacity+transform, section h 1002.5625 vs 1002, runway height, title display, track h)
- commission | sweep:phone-rotation, sweep:touch-1024-1201, sweep:pain-1440-600-1440 | 4/5 each
- commission.typing | sweep:desktop-1512-320-1512 | 37/57 (visual scale 0.7616 vs 0.8, beat transitions, referral filter)
- commission.typing | sweep:phone-rotation | 3/5; | phone-landscape col, reading phone-landscape-no-preference | 1/2 (avatarLarge 32 vs 11.2, opacity 1 vs 0)
- pain.notes | sweep:desktop-1512-320-1512 | 25/57 (note x, first at #3@1279x900, 125 probe diffs)
- Every other Chromium cell: pass (people.card, people.deck, hero.orbit, commission font cell included).
## WebKit (report lines, not land conditions)
- commission 56/57, 4/5, 4/5, 4/5 (same four sweeps); commission.typing 45/57, 3/5, pass, 2/5; pain.notes 25/57 (desktop sweep)
- hero | ctaButton font-family | 196 probes starting desk-319 (rewrite resolves "-webkit-standard")
- fractional-gaps and hover-pointer-cross: enumerated unreachable exemptions (rows x 4 ids)

## Round 2 state
- Merged main. Kept branch's PainNotes/HeroAccent/People* spec+Opt split (main never had the Opt files; main's combined PainNotes.lean additions from engine-model-fix-2 are NOT merged: lead resolves at land). Took ledger n:21 from branch, kept main's Exit.lean with row counts 18->36 (rows=truth+pilot parts), universe 7056, exit.jsonl, scope.gen.json regenerated; EngineGoldens.lean points to the *Opt modules.
- SweepPage WIP needed (docstring cites exactly the failing cells): finished as two pages, plain/mounted (Lean Freeze.pageOf, plain_part_has_no_history, mounted_part_gets_mount, pages_partition, golden freeze.jsonl 4 page rows). run.mjs reads parts without a mount step on a page that never scrolls. UNVERIFIED on CI: the hypothesis (history differs) is the first builder's.
- Step 3 (CI gate run) NOT done: the user's relayed request says "Ask me for run it", so the push of ci/integrate-ports-4 awaits the user's go.
## Next
`git push origin HEAD:ci/integrate-ports-4` (subject carries [ci:breakpoint-gate]), `pnpm -s fw ci wait`, read gate-merged-chromium/summary.md. If sweeps still fail, the divergence is a real hysteresis difference (orig keeps stale layout while its section is deferred): split the task.
Open: missing port-morph-panel notes in integrate-ports.md; hero.orbit zIndex skip status not re-verified.
