# Handoff: shells (Q36)

Branch `worktree-agent-ad57130e33d8fc12a` (pushed as `ci/shells`). Four static shells, one folder each under
`apps/site/src/parts/`: `people`, `pain`, `commission`, `platform`. NOT built: `hero` (the pilots hero.countdown/hero.exit
already make the 200vh track), nav, overlays (port-nav / port-overlays start without a shell).

## How it works
- `src/shells/samples.json`: MEASURED outer heights of the original's sections (desktop Chromium, 296 rows: ~150 widths x h 600/900,
  incl. every matrix width). Regenerate: `node scripts/shell-measure.mjs samples`.
- `src/shells/model.ts` (pure fit, TS stand-in: no Lean spec yet) -> `scripts/gen-shells.mjs` writes `src/shells/boxes.gen.json` and
  `parts/<id>/box.module.css` (`pnpm gen:shells`; `check:shells` runs inside `build`). Heights = sum of clamped vw ramps (no @media), plus
  the h-forms: people >=861 adds 3.15svh+clamp(743,vh-80,820); pain max(300svh, 200svh+P(w)); commission >=1001 max(.06svh+D, 1.06svh+48).
  Margins restated: people 1px-100svh, pain/commission -100svh.
- Check: `pnpm build && pnpm check:shell-boxes` = 43 matrix probes, rewrite vs original in one browser: sections within 0.5 px (worst 0.02), page height minus
  the pilots' placeholder scaffold (sticky AppBar + countdown block, 136-172 px) within 1 px. Unit test `src/shells/model.test.ts`.
- Shared edits: App.tsx (tabs/cards placeholder removed, 4 shells added), registry/index.ts, package.json scripts. Part ids/variant `shell`.

## Open
- Between sample widths heights are linear interpolation (10 px grid); unit uses vw (scrollbar-less match). svh used where original is svh/unknown.
- A port deletes its folder's box.module.css and gen entry (remove id from SECTION_IDS in model.ts) and registers `faithful`.
