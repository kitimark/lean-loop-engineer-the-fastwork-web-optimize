# doc-head-locale handoff

State: branch worktree-wf_ded5198b-b6e-4 (commit on top of afeabad5). Lane L6.

- Lean: `lean/Fw/Site/Head.lean` (entries, locales, hreflang/canonical theorems), `lean/HeadgenMain.lean` driver.
  Generate: `cd lean && lake env lean --run HeadgenMain.lean > ../apps/site/src/head.gen.json`; check: same with `--check <file>`.
  No lake exe added (lakefile is outside the write set); the check is not yet wired into check.sh / CI.
- Build: `apps/site/scripts/head.mjs` renders head + `<html>` attrs from `src/head.gen.json`; `index.html` has `<!--fw-html-attrs-->`.
- Nav renders the sr-only `<nav aria-label="Language">` with hrefLang links (from head.gen.json) as a sibling before the header.
- Countdown aria-label is the literal `Time until launch`; `src/head.test.ts` checks it against the snapshot and head.gen.json (TS stand-in, no Lean golden).
- Icons/manifest files added to `assets.manifest.json` (7 snapshot files).
- Test: `src/head.test.ts` reads the snapshot head at test time; also checks dist/aot/index.html if built.
- Declared differences: CSP meta, analytics.js, GTM, CF beacon, preload hints. og-cover.png is an absolute URL, not served.
- Open: svg-extract.test.ts "no tracked file ... snapshot path" times out at 5 s locally (slow git scan); footprint golden regenerated (nav line shift).
