# trajectory-stable-followups

- Branch `worktree-wf_e50be261-576-1`, worktree `.claude/worktrees/wf_e50be261-576-1`; round 2 commit b8040523c, main merged at 5b9e8b673.
- Checks at c9b0b6831: gate-breakpoints test 706/706, lean check.sh green (145 s), ci-paths 56, land-inputs 56; dry land `VERDICT dry trajectory-stable-followups`; review ready `review`.
- gate-breakpoints test re-run at 443a4def4 (polish cut comments only): 706/706.
- No CI run made: every claim reads existing runs or re-reduces run 39926829451 offline (dev check).

## Verified
- `byMFam` (`src/trajectory/reduce.mjs`) judges the whole family in one walk; `byMFamEach` is the definition. Test
  `byMFam equals byMFamEach`: 936 cases (golden segments, original plus a shifted copy (values +7, `since` +50) as one more
  pass, and a hand-made window that settles to its epoch end). Mutants checked by hand, both fail the test, reverted:
  (a) member keeps every envelope piece (`pieceOf(r).env.flat()`); (b) `settle` without the epoch-end fallback.
- Run 39926829451, `summary` on the artifact `trajectory-chromium` raw, `byMFamEach` vs `byMFam`:
  timing and units hash are in doc check 2 (Leave-one-out band); units identical both ways (CLEAN, 14416 units).
- CLI exits 2 on every refused input and on a throw (entry line catches into `refuse`); test `cli: a refused input ...`
  runs `summary` on a raw of `{}` as a child process.
- Lean `nil_not_mem_family`: a first pass on an empty original is outside `laneOf_stable_extra` (doc check 2).
- Doc check 2: Linux WebKit open gap p50 120 to 183 ms (median 148.5) over 10 runs; Simulator marks from the
  artifact of run 39511908073, which concluded failure.

## Open
- CI reduce-step time not re-measured on CI.
- A Simulator lane needs a new timed `webkit-sim` pass reading `m`, the probe properties and `t0` per frame.

## Read first
- `docs/team/tools/trajectory-probe.md` check 2 (Leave-one-out band, WebKit cadence, WebKit Simulator rows), check 3.
