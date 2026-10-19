# port-completeness-gate (L7), round 1

State: branch `worktree-wf_ebd5ee90-ef5-1`. CI ran on `ci/port-completeness-gate` (visual-diff lane, `port` job).
- Lean: `lean/Fw/Port/{Sections,Text,Attrs,Svg}.lean` and `lean/Fw/Site/Assets.lean` hold 29 theorems. Exclusion
  lists are one per check: text excludes hero/morph countdown "*"; attrs, assets and svg are empty.
- Goldens: `lean/scripts/PortGolden.lean` writes `packages/contracts/golden/port/{sections.json,exclusions.json,
  assets.jsonl,svg.jsonl}`. check.sh runs it as job "port golden check".
- Site side: `scripts/port/digest.mjs` holds checks 3+4 and the report. The tests are `apps/site/test/port-{assets,svg,sections}.test.mjs`
  and run in the site `test` script. Built-page tests run only when `FW_SITE_DIST` is set.
- CI: the `port` job in `.github/workflows/visual-diff.yml` needs `site`. Its gate step is `continue-on-error`
  (advisory) until the gap lanes land, so remove it once checks 3+4 pass. Trigger row G11 adds `scripts/port/**` and
  `golden/port/**`. land.ts site reads add port goldens, `scripts/port/**` and `anchors.json`.

Flagged on main (MEASURED, CI run 39217249207, artifact `port-report`): assets 3 of 111 missing:
`/fonts/fastwork-Bold.ttf`, `commission/direct-client-arrow.svg`, `compact-your-client-arrow.svg`. Svg check, 31 orig
vs 30 rewrite: 2 missing (nav wordmark, which loses its `<g>`, 10 vs 9 elements; a platform.entries 24x24 icon) and 1
extra (the rewrite's nav wordmark). The gate step failed (advisory); goldens and head tests passed.

Design:
- Check 3 decides per URL. Original URLs are crawled from snapshot index.html plus reachable js/css, skipping `/__vendor/`.
  Rename F = rows with byte-identical referenced rewrite files first, then manifest rows. Only existing files count.
- Check 4 is page-wide. One unit is one outermost `<svg>`, keyed by sha256(canonical skeleton JSON)[0:16].
  Matching is the multiset difference, and owner labels come from the Sections table.
- TS stand-ins (unproved glue): the HTML tokenizer, the selector subset and the URL scanner in digest.mjs.

Open items:
- Checks 1 and 2: Lean only; implement them in digest.mjs next round.
- Check 5: after C3.
- No checker helper ran because this session had no agent tool. The docstrings were self-reviewed against the checklist.

Read first: `lean/Fw/Port/Sections.lean`, then `scripts/port/digest.mjs`.
