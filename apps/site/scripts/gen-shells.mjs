// Generates the shell boxes from the measured samples: src/shells/boxes.gen.json (the fitted model) and
// src/parts/<id>/box.module.css for each shell. `--check` fails if any committed file differs (used by `pnpm check:shells`).
// The pure fit is src/shells/model.ts (Node strips the types). Samples: `node scripts/shell-measure.mjs samples`.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SECTION_IDS, fit, sectionCss } from '../src/shells/model.ts';

const SITE = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const check = process.argv.includes('--check');
const read = (f) => JSON.parse(readFileSync(join(SITE, f), 'utf8'));
const rows = read('src/shells/samples.json').rows;
const gen = read('src/breakpoints.gen.json');
// widths that must stay exact: every gate probe (a fractional width is hosted at the next whole px) and every edge pair
const must = [...gen.matrix.probes.map((p) => Math.ceil(p.width)), ...gen.edgePairs.width.flat()];
const model = fit(rows, 0.05, must);

const files = new Map([['src/shells/boxes.gen.json', JSON.stringify(model, null, 1) + '\n']]);
// sections that have been ported no longer have a shell box (their part folder owns its CSS; the fit stays in boxes.gen.json)
const PORTED = new Set(['commission', 'pain']);
for (const id of SECTION_IDS) if (!PORTED.has(id)) files.set(`src/parts/${id}/box.module.css`, sectionCss(model, id));

let bad = 0;
for (const [f, text] of files) {
  const p = join(SITE, f);
  if (check) {
    if (!existsSync(p) || readFileSync(p, 'utf8') !== text) {
      console.error(`shells check: ${f} differs from the generator output; run \`pnpm gen:shells\``);
      bad++;
    }
  } else {
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, text);
    console.log(`wrote ${f} (${text.length} bytes)`);
  }
}
process.exit(bad ? 1 : 0);
