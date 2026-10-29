# gen-merge-retry-bound handoff

- Branch: worktree-wf_52e0813b-89d-1
- Worktree: .claude/worktrees/wf_52e0813b-89d-1
- Last commit: the commit that adds this file (round 2, on top of merge 954f3542c of main 785afab44).
- CI runs: none (the rows of runs 40668662980, 40671695274, 40674554372 were recorded from downloaded artifacts in round 1).
- Verified at round 2: check.sh green through fw slot (3:38, axiom check 0 failing); contracts 11 tests; gate-breakpoints
  830 tests; apps/site presets/v2-proved.test.ts; reader-files.test.mjs; runner ledger-merge, ledger-alloc, land-inputs
  (127 tests); scripts/ci-paths.test.mjs (56); plan lint 0 errors, no writesClosure line for this row.
- Dry land: `pnpm -s fw slot run --kind land --cache -- pnpm -s fw land worktree-wf_52e0813b-89d-1 --task
  gen-merge-retry-bound --dry`, expected last line `VERDICT dry gen-merge-retry-bound`.
- Open: none in the unit. Follow-ups: order readers by commit ancestry; add the probe's lockfile entries to the reader.

State:
- Round 2 fix: `supersede` (lean/Fw/Preset/V2Proved.lean, "Superseded rows") reads `(later st s).getLast?`; a row is
  superseded by reader only when the newest run of its key is at another reader, else the retry branch (no-verdict,
  `streak < retryBound = 2`). `fail_not_hidden` and the lemmas take `hr : ∀ n ∈ (later st s).getLast?, ...`.
  #guards: [A fail 1, B pass 2, A pass 3] = fail; [A fail 1, B pass 2] = pass; [A nv 1, A pass 2] = pass.
- Gen.run re-run: only the `by` run of 8 superseded rows moved to the newest run; no cell or verdict changed.
  hero.exit:threaded: mac morph no-verdict 40671695274 superseded (retry) by the pass 40674554372 (reader 03b75d1b69fa);
  all four cells pass, decision not yet, only blocker `proofs`.

Conventions:
- Never edit v2-proved.trajectory.jsonl by hand: `Gen.record` then `Gen.run []` from lean/ (docs/team/tools/trajectory-probe.md).
- A new reader file needs `Gen.readerFiles` updated; reader-files.test.mjs fails until then.

Read first: research/notes/2026/10-2x-gen-merge-retry-bound.md, then "Superseded rows" in V2Proved.lean.
