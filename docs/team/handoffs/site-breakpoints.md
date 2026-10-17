# Handoff: site-breakpoints

The site reads only the Lean-generated `apps/site/src/breakpoints.gen.json` (committed, byte-equal to `lake exe breakgen`).

- `pnpm --filter @fw/site gen:breakpoints` regenerates it (build `lean/` first). `check:breakpoints` runs
  `scripts/check-breakpoints.mjs` (`lake exe breakgen --check`); `build`, `build:runtime` and `build:all` run it first and
  fail with a clear message if `lake` is missing or the bytes differ.
- `src/breakpoints.ts`: `conditions` is now an array (`id`, `tsId`, `css`, ...); `mediaCondition(id)` looks up by inventory id.
- `scripts/media-check.mjs`: allowed = `conditions[].css`, neutral = `neutral[].css`, both from the gen file.
  `src/mui-internal-media.json` is deleted. The CSS minifier drops spaces after `:` and `,`, so both sides are normalised
  by removing whitespace around `: , ( )`. A whole query list (the comma conditions c860/c1000/c1000-nodw) is tried first.
- Result (Chrome 155): build ok; census aot 0/0/0, runtime control caught; media-check PASS (hover queries, c1000-nodw,
  w-le-400, w-gt-600, w-le-600, rm-reduce from the gen set; `print`, `(forced-colors: active)` neutral).

## Not mine (part-fix owns `src/parts/*`)
- `hero.countdown/media.test.ts` and `hero.exit/media.test.ts` cast `conditions` as `Record<string,string>`; the gen file has
  an array, so `pnpm typecheck` fails (TS2352) and the tests silently skip (`conds[id]` is undefined). They must look up by
  `conditions.find(c => c.id === id)?.css`, compare to the CSS module text, and fail when missing.
- `pnpm test`: 9 failures in golden conformance for `hero.countdown`, `hero.exit`, `nav.hitTest` (rational `{num,den}` in
  goldens vs numbers); unrelated to media.
- No part CSS media text disagrees with the generated conditions (media-check passes).
