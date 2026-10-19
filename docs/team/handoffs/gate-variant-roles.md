# gate-variant-roles handoff

State: branch worktree-wf_86652ab9-962-2, work commit 63e88923 (pushed as ci/gate-variant-roles); this note is the next commit.
Task: triage row 1 of research/notes/2026/10-19-preset-gate-triage.md. hero.countdown:strip renders one [data-strip]
per digit instead of ten [data-face], so the gate failed the face count (64 vs 0).

Verified:
- `lake build` passes (1:41).
- Golden checks pass: GateGolden `--check` (26 literal cases, 5 new) and coverage golden `--check` (27 claims).
- Tests pass: gate-breakpoints `node --test` (139 pass), apps/runner `tsc` + vitest (1034 pass), `scripts/ci-paths.test.mjs` (32 pass).
- Lean (Fw.Gate.Items, "Variant roles"):
  - `VariantRole` (variant, replaces, role, countOf, why), `variantRole`, `variantSpec`, `variantOrig`, `variantRewrite`, `variantCount`, `variantWellFormed`, `Fresh`.
  - Theorems: `partItems_variant`, `partItems_variant_others` (every other item unchanged), `partItems_variant_role` (replaced role not judged; new role is one count item, original countOf vs rewrite role), `variantCount_equal_iff`, `variantCount_missing`, `partItems_variant_none`, `fresh_of_wellFormed`.
- Wire (Fw.Wire.Gate `gate.state`):
  - Reads `anchors.parts[id].variantRoles` and the request field `variants` {part: variant}.
  - Refuses an entry that is not well formed.
  - Changes the Ctx specs and both arms before `evalStateRoot`. State.lean is unchanged.
- JS:
  - run.mjs collects each variant role on the rewrite arm (count only).
  - run.mjs reads each part root's `data-fw-variant` (the page's identity, not inferred) into `header.variants`.
  - verdict.mjs `context` passes `variants`; summary.mjs and gaps/judge.mjs forward it.
- Data:
  - anchors.json, hero.countdown: `variantRoles` = strip, which replaces face with role strip (`[data-fw="hero-countdown"] [data-strip]`), countOf digit.
  - spec.test.mjs checks the shape of every variant role.

Open:
- No CI run yet. `gh` could not reach api.github.com from this agent's sandbox, so the gate was not dispatched. Command:
  `gh workflow run breakpoint-gate.yml --ref ci/gate-variant-roles -f engines=chromium -f fw=hero.countdown:strip`.
  Read the hero.countdown row from the `gate-merged-chromium` summary.json.
- `gate.stale` (sweep hysteresis) still uses the plain roles: under strip, face is 0/0, which reads as differ.
- apps/runner coverage.ts probes do not list variant roles. Only the Coverage claim (hero.countdown strip count) was added.
- Accepted limit: only hero.countdown:strip uses the map.
- Wrote lean/Fw/Wire/GateGolden.lean, which is outside the listed writes: it holds the new literal cases.

Conventions: regenerate literal.jsonl with `cd lean && lake env lean --run scripts/GateGolden.lean`, and coverage.jsonl per docs/team/tools/coverage.md; then run each with `--check`.
Read first: Items.lean section "Variant roles"; Wire/Gate.lean `variantSelOf` / `opState`.
- Land fix 2026-10-19: the where/with definitions of `variantOrig`, `partItems_variant_others`, `partItems_variant_role` moved into `$$` blocks; mathview lint 0 dangling-where; check.sh green.
