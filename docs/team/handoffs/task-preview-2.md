# task-preview-2 handoff (round 2)

State: branch worktree-wf_06917030-a64-1; lean check.sh green; console-api 18 files / 268 tests green.

Read first: `lean/Fw/Console/Preview.lean` (rules + theorems), `PreviewFacts.lean` (GENERATED), `PreviewTable.lean`
(typed expectations), `apps/console-api/src/preview/{facts,link,owner}.ts`, `scripts/gen-preview-facts.ts`.

Conventions
- Decisions in Lean: `pickHead` over `eligible` = ordered then `Fact.admissible` (merge needs `ownWork`; never `behind`);
  `landOf` = own sha if `fpLine`, else first path commit whose second parent holds it, else main.
- TS only gathers facts. `landFacts` bisects main's first-parent line (`--ancestry-path` is empty for nested merges).
- Facts table is generated from git at `golden/preview-facts.pin.json` (full shas, refs, tips, kids).
  Regenerate: `node apps/console-api/scripts/gen-preview-facts.ts --pin`, then no flag, then OpsGolden
  (`cd lean && lake env lean --run scripts/OpsGolden.lean`). `--check` exits 2 when pinned objects are missing.
- `behind`: another candidate holds non-doc code beyond this one (drops old handoff commits).
- Reissue: SIGUSR2 to the console only after `/api/health` header `x-fw-console-pid` matches; `mayReissue` allows one
  link per 60 s. Same-UID limit: such a process can at most print a fresh link once a minute (see owner.ts).

Changed expectations (git evidence)
- port-platform: head b2e5ff1 -> 5b50ad0 (originCi), land 80d7610 -> 6e968ba. b2e5ff1 is a main commit (second
  parent of 411847d, "merge main"), not task work; 72971b8 is an ancestor of 5b50ad0 (2-line css diff).
- Newest integration tip is 9e23e15 (was b35b541): targets use `r3t`.
- fix-commission-margin gains merge candidate 578235d (fpLine, not own work): inadmissible, head stays 3301169.

Open: none known. TS stand-in: none; owner-link/health glue is I/O only.
