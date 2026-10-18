// Summary of a fixture run: per fixture arm, variant and pass, the per-step styleRecalcs / renderingUpdates.
//   node summarize.mjs <dir>...      each <dir> holds <fixture>-f<frames>/counts-<variant>-<pass>.json (one CI job each)
// Prints a markdown table and, with --json, the rows. Counts only; no decisions (classes are fwcore's, see wktr-fixtures.yml).
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const dirs = args.filter((a) => !a.startsWith('--'));

/** Per-pass row from a counts file (schema fw.wktr.scroll/1). */
export function rowOf(run) {
  const fr = run.frames;
  const col = (k) => fr.map((f) => f.counts[k] ?? 0);
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const sr = col('styleRecalcs'), ru = col('renderingUpdates');
  // steps 1..: step 0 starts from the initial position (no scroll delivered before it)
  const hist = {};
  for (const v of sr) hist[v] = (hist[v] || 0) + 1;
  return {
    steps: fr.length, styleRecalcs: sum(sr), renderingUpdates: sum(ru), layoutUpdates: sum(col('layoutUpdates')),
    compositingUpdates: sum(col('compositingUpdates')), styleInvalidations: sum(col('styleInvalidations')),
    perStepMin: Math.min(...sr), perStepMax: Math.max(...sr), stepsWithNoRecalc: sr.filter((v) => v === 0).length,
    recalcsPerRenderingUpdate: ru.some((v) => v > 0) ? +(sum(sr) / sum(ru)).toFixed(3) : null,
    hist, animActive: sum(col('ev_animActive')), page: { innerWidth: run.meta.page.innerWidth, docH: run.meta.page.docH, endY: run.meta.page.endY },
  };
}

const rows = [];
for (const d of dirs) {
  for (const arm of readdirSync(d).sort()) {
    const dir = join(d, arm);
    if (!existsSync(dir) || !/-f\d+$/.test(arm)) continue;
    for (const f of readdirSync(dir).sort()) {
      const m = /^counts-(.+)-(\d+)\.json$/.exec(f);
      if (!m) continue;
      rows.push({ job: d, arm, variant: m[1], pass: Number(m[2]), ...rowOf(JSON.parse(readFileSync(join(dir, f), 'utf8'))) });
    }
  }
}
if (asJson) { console.log(JSON.stringify(rows)); process.exit(0); }
console.log('| arm | variant | job | pass | steps | styleRecalcs | renderingUpdates | recalcs/update | per-step min..max | steps with 0 recalcs | animActive |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|');
for (const r of rows) {
  console.log(`| ${r.arm} | ${r.variant} | ${r.job.split('/').pop()} | ${r.pass} | ${r.steps} | ${r.styleRecalcs} | ${r.renderingUpdates} | ${r.recalcsPerRenderingUpdate} | ${r.perStepMin}..${r.perStepMax} | ${r.stepsWithNoRecalc} | ${r.animActive} |`);
}
