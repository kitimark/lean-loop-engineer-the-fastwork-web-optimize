#!/usr/bin/env node
// Per-band table for task geom-page-diff: reads the four look JSONs of CI run 40553185213 (ci-40553185213/) and prints
// markdown to stdout. outside = share of the pixels outside the nav box that differ, derived from the page and nav rows:
//   outside = (page.share * page.px - nav.share * nav.px) / (page.px - nav.px)   (the nav box lies inside the page box)
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const load = (f) => JSON.parse(readFileSync(join(here, 'ci-40553185213', f), 'utf8'));
const f3 = (x) => x.toFixed(3);
for (const arm of ['on', 'timed']) {
  console.log(`\n### look/${arm}, m=1 (share of pixels differing by more than 12 against base)\n`);
  console.log('| band | engine | page | nav box of page | nav | outside nav box |');
  console.log('|---|---|---|---|---|---|');
  const c = load(`look-${arm}-chromium.json`), w = load(`look-${arm}-playwright-webkit.json`);
  for (const r of c.rows.filter((r) => r.m === 1)) {
    const q = w.rows.find((x) => x.band === r.band && x.m === 1);
    for (const [e, x] of [['chromium', r], ['webkit', q]]) {
      const out = (x.page.share * x.page.px - x.nav.share * x.nav.px) / (x.page.px - x.nav.px);
      console.log(`| ${x.band} | ${e} | ${f3(x.page.share)} | ${f3(x.nav.px / x.page.px)} | ${f3(x.nav.share)} | ${f3(out)} |`);
    }
  }
}
