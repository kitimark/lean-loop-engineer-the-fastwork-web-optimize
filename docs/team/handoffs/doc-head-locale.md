# doc-head-locale handoff

State: branch worktree-wf_ded5198b-b6e-4 (final design round on top of 049e609d; see git log). Lane L6.

- Lean: `lean/Fw/Site/Head.lean` (entries, locales, hreflang/canonical theorems), `lean/HeadgenMain.lean` driver.
  Generate: `cd lean && lake env lean --run HeadgenMain.lean > ../apps/site/src/head.gen.json`; check: same with `--check <file>`.
  Wired: `headgen check` job in lean/scripts/check.sh; its read declared in Trigger.lean (lean.yml row), LandSpeed.checkShReads, land.ts CHECK_SH_READS, goldens regenerated.
- Build: `apps/site/scripts/head.mjs` renders head + `<html>` attrs from `src/head.gen.json`; `index.html` has `<!--fw-html-attrs-->`.
- Locale links: `renderLocaleLinks` (head.mjs) emits the sr-only nav (inline style) via `<!--fw-locale-links-->` after #root in index.html: a direct body child after #root, followed only by scripts (position guard: tail regex in head.test.ts); inline style equals the snapshot `.site-locale-links` rule (tested). Nav part untouched.
- Countdown aria-label is the literal `Time until launch`; `src/head.test.ts` checks it against the snapshot and head.gen.json (TS stand-in, no Lean golden).
- Icons/manifest files added to `assets.manifest.json` (7 snapshot files).
- Test: `src/head.test.ts` reads the snapshot head at test time; also checks dist/aot/index.html if built.
- Declared differences (the EXCLUDED predicate, applied to both snapshot and built head lists): CSP meta, analytics.js, GTM, CF beacon, modulepreload hints, stylesheets and inline styles (owned by the CSS lanes). og-cover.png is an absolute URL, not served.
- Built-page tests (head, nav position, sr-only rule, countdown label) skip visibly when dist/aot is absent (at land, git clean); running them after a site build in CI is the port-completeness-gate lane's job.
- Follow-ups: per-locale headFor and non-trivial hreflang reciprocity; `fwcore headgen` subcommand; import gen.countdownAriaLabel in the part; DOM-parsed structure (L7 check 2).
- Out-of-set writes accepted by the lead: Trigger.lean, LandSpeed.lean, land.ts, triggers/land-speed goldens, check.sh.
