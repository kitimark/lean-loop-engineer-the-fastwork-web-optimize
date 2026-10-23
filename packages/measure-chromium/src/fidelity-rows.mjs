// Font fidelity: the section rows (part, original-page selector) the page function boxes, written from the port gate's
// canonical table (packages/contracts/golden/port/sections.json through scripts/port/fonts.mjs rowsOf), page-level rows left out.
// usage: node fidelity-rows.mjs <out.json> [orig|rewrite]
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { rowsOf } from '../../../scripts/port/fonts.mjs';

const [out, arm = 'orig'] = process.argv.slice(2);
if (!out) { console.error('usage: fidelity-rows.mjs <out.json> [orig|rewrite]'); process.exit(2); }
const rows = rowsOf(arm);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(rows)}\n`);
console.error(`fidelity rows: ${rows.length} (${arm}) -> ${out}`);
