# variant-regate (handoff)

State: branch `worktree-agent-a692229f4d4a09b4e`, harness commit c558cb4 (CI ran on exactly that), results in
`results/variant-regate.md` (150 rows: 5 variants x 2 engines x 15 parts; 0 rows differ from the flags-off baseline).

What changed
- Merged `worktree-agent-a2abc9e0dbc20eec6` (variant-hidden-pause). morph.columns and morph.countdown were already in
  `lean/Fw/Gate/Scope.lean`; added `engine.scene` (no media conditions, dismissed `js.scene-activation` which the inventory
  already lists), regenerated `packages/gate-breakpoints/src/scope.gen.json` (`node scripts/scopegen.mjs`, needs built lean/),
  added its role to `anchors.json` (existence of `.start-selling-platform` / `[data-fw="platform"]`; animation-* is skipped).
- Wired `<EngineScene variant selector='[data-fw="platform"]'/>` in `App.tsx` and `engineScene` in `registry/index.ts`.
- Harness: `run.mjs` writes `header.flags = {search, configHash}`, reads `data-fw-config` from the loaded rewrite page at
  the phase-0 reference load and throws if it is not the flagged config; `serve.mjs rewriteFor` returns `hash`;
  `summary.mjs` prints `**Flags: ...**` first in every engine section and `flags` in summary.json.

Conventions / gotchas
- The workflow cancels in-progress runs on the same ref: one `ci/variant-regate-<x>` branch per concurrent run. A new branch
  push at an already-seen commit starts no push run; dispatch explicitly.
- Dispatch: `gh workflow run breakpoint-gate.yml --ref ci/<branch> -f fw=<flags>`; artifacts `gate-merged-<engine>` hold summary.json.
- Local worktree: `wt-prep.sh` skips the lean clone while any `lean --server` runs in main; `cp -c -R main/lean/.lake lean/.lake` by hand.

Open items
- morph.panel:rest pending: integrate-ports had not landed (`git log main --grep='Task: integrate-ports'` empty).
- Harness flake: `header.props["nav.hitTest"].nav.originOnly` (WebKit, `opacity`) differs between shards in about 1 of 7 runs,
  making `merge-gate` fail on "header differs". Fix belongs in `.github/scripts/merge-gate.mjs` or in making that list stable.
- WebKit hero.countdown/hero.exit/platform.stageBg fail in the base (flags off); fixing them is not a variant matter.
- The gate loads at the top of the page, so it does not exercise the variants' runtime paths; the counts lanes do.
- `gate-smoke.mjs` still opens the default config only (it does not know FW_SEARCH).

Read first: `results/variant-regate.md`.
