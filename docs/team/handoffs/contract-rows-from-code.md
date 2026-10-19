# contract-rows-from-code handoff
- **State:** branch `worktree-wf_9847872a-d87-3`, round 2 (closed extractor) committed on top of round 1, main
  merged. Findings: `research/notes/2026/10-19-contract-rows-from-code.md`.
- **Pieces:**
  - `apps/site/scripts/part-footprint.mjs`: the `MODELLED` allowlist maps each element, list, animation, style or
    classList call/assign/read to an access, else `unmodelled-api`; unreadable names give `dynamic-name`.
  - `Fw.Parts.Footprint`: new `setContent` op, name-`?` wildcard in `same`, `Access.isOpen`, `flagged`.
  - `Fw.Parts.Contract`: `flagged_total`, `affectsOpen`/`i3Open`, `code_groups_rect_open`; `code_groups_partition`
    docstring states the lower-bound limits.
- **Verified:** full `lake build` (505 jobs, about 15 s); axioms only propext, Quot.sound; fwtest; check-imports;
  mathview lint 0 failing; `ContractsGolden --check`; site typecheck + vitest (72 files);
  `node --test scripts/ci-paths.test.mjs`; runner `land-inputs.test.ts`.
- **Regenerate, in order, from `lean/`:**
  1. `node ../apps/site/scripts/part-footprint.mjs --write`
  2. `lake build Fw.Parts.Contract`
  3. `lake env lean --run scripts/ContractsGolden.lean --rows > Fw/Parts/FootprintRows.lean`, then `lake build`
  4. `... --diff > ../packages/contracts/golden/parts/footprint-diff.gen.json`
  5. `... --check ../packages/contracts/golden/parts/contracts.gen.json ../packages/measure-chromium/scenarios.gen.json`
- **Result:** the groups are one 27-part group, three solos (overlays.drawer, people, people.carousel) and four
  page-level parts. The merge comes from the seek writes at engine.scene/index.tsx:13 (name `?` matches every
  `var()` read with owner `*`); removing them restores round 1.
- **Open:**
  - The lead adds the work-graph writes `lean/Fw/Parts/Footprint*.lean`, `apps/site/src/footprint.test.ts` and the
    note, then runs fw plan sync.
  - Follow-ups: fix-declared-rows, extractor-callsites, extractor-engine, generate moves/listAccess/schedules/plan,
    model the 8 `unmodelled-api` residues. The premise stays `declared-rows-unverified`.
  - The docstring checker was not spawned (this agent has no Agent tool); the 6-point list was self-applied.
- **Read first:** the note, then the `code_groups_partition` docstring, then `Footprint.same` and `writes`.
