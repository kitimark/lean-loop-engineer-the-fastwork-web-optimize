#!/usr/bin/env node
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { summarize, ARM_LABEL } from './safari-local-run.mjs';

export const readPasses = (dir) => readdirSync(join(dir, 'passes')).filter((f) => f.endsWith('.json')).sort().map((f) => JSON.parse(readFileSync(join(dir, 'passes', f), 'utf8')));

const ms = (tenths) => (tenths == null ? '-' : (tenths / 10).toFixed(1));

export function table(rows) {
  const head = '| engine | window | arm | passes | refused (before/after/stale) | errors | long>25ms | skipped | p50 ms | p95 ms | max ms | Paint ms | Composite n | vs base (long) | vs base (skipped) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|';
  const line = (r) => `| ${r.engine} | ${r.window} | ${r.arm} | ${r.passes} | ${r.refused.before}/${r.refused.after}/${r.refused.stale} | ${r.refused.error} | ${r.long ?? '-'} | ${r.skipped ?? '-'} | ${ms(r.p50)} | ${ms(r.p95)} | ${ms(r.mx)} | ${r.paintHund == null ? '-' : (r.paintHund / 100).toFixed(1)} | ${r.compositeN ?? '-'} | ${r.vsBaseLong ?? '-'} | ${r.vsBaseSkipped ?? '-'} |`;
  return [head, ...rows.map(line)].join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = resolve(process.argv[2] ?? 'results/mac-safari');
  const rows = summarize(readPasses(dir));
  if (process.argv.includes('--write')) writeFileSync(join(dir, 'summary.json'), JSON.stringify(rows, null, 1) + '\n');
  console.log(table(rows));
  console.log(`\narms: ${Object.entries(ARM_LABEL).map(([k, v]) => `${k} = ${v}`).join('; ')}`);
}
