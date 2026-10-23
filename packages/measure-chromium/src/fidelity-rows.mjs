import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { rowsOf } from '../../../scripts/port/fonts.mjs';

const [out, arm = 'orig'] = process.argv.slice(2);
if (!out) { console.error('usage: fidelity-rows.mjs <out.json> [orig|rewrite]'); process.exit(2); }
const rows = rowsOf(arm);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(rows)}\n`);
console.error(`fidelity rows: ${rows.length} (${arm}) -> ${out}`);
