// Summary of a fixture run: per fixture arm, variant and pass, the per-step styleRecalcs / renderingUpdates.
//   node summarize.mjs <dir>... [--json] [--assert]   each <dir> holds <fixture>-f<frames>/counts-<variant>-<pass>.json (one CI job each)
// Prints a markdown table and, with --json, the rows. Classes are fwcore's (see wktr-fixtures.yml).
// --assert: exit 1 unless every pass of the asserted fixtures has its premise rate (lane premise
// wktr_scroll_timeline_restyle: control 0, scroll-timeline 1, time-accel 0 style recalcs per rendering update).
// The decision is Lean's (Fw.Ops.Premise.laneFailures, laneFailures_nil_iff); this is a port, checked against
// packages/contracts/golden/ops/wktr-lane.jsonl by test/summarize.test.mjs.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Lean `wktrExpected`: the asserted fixtures and their style recalcs per rendering update. */
export const WKTR_EXPECTED = [['control', 0], ['scroll-timeline', 1], ['time-accel', 0]];

/** Lean `passOk`: at least one rendering update and exactly mu style recalcs per update. */
export const passOk = (mu, q) => q.renderingUpdates > 0 && q.styleRecalcs === mu * q.renderingUpdates;

/** Lean `laneFailures`: the expected fixtures with no pass or a pass off their rate (empty = the lane passes). */
export function laneFailures(expected, passes) {
  return expected.filter(([x, mu]) => {
    const m = passes.filter((q) => q.fixture === x);
    return m.length === 0 || !m.every((q) => passOk(mu, q));
  }).map(([x]) => x);
}

/** The fixture of an arm directory: the arm without its `-f<frames>` suffix. */
export const fixtureOf = (arm) => arm.replace(/-f\d+$/, '');

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

/** Every pass row of the given job directories. */
export function collect(dirs) {
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
  return rows;
}

function main(args) {
  const asJson = args.includes('--json');
  const rows = collect(args.filter((a) => !a.startsWith('--')));
  if (args.includes('--assert')) {
    const passes = rows.map((r) => ({ fixture: fixtureOf(r.arm), styleRecalcs: r.styleRecalcs, renderingUpdates: r.renderingUpdates }));
    const fails = laneFailures(WKTR_EXPECTED, passes);
    for (const [x, mu] of WKTR_EXPECTED) {
      const m = passes.filter((q) => q.fixture === x);
      const bad = m.filter((q) => !passOk(mu, q));
      console.log(`assert ${x}: expected ${mu} style recalc(s) per rendering update; ${m.length} passes, ${bad.length} off` +
        (bad.length ? ` (e.g. ${bad[0].styleRecalcs} recalcs / ${bad[0].renderingUpdates} updates)` : ''));
    }
    if (fails.length) { console.error(`wktr lane: FAILED for ${fails.join(', ')} (premise wktr_scroll_timeline_restyle)`); process.exit(1); }
    console.log('wktr lane: premise wktr_scroll_timeline_restyle holds on every pass');
    return;
  }
  if (asJson) { console.log(JSON.stringify(rows)); return; }
  console.log('| arm | variant | job | pass | steps | styleRecalcs | renderingUpdates | recalcs/update | per-step min..max | steps with 0 recalcs | animActive |');
  console.log('|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of rows) {
    console.log(`| ${r.arm} | ${r.variant} | ${r.job.split('/').pop()} | ${r.pass} | ${r.steps} | ${r.styleRecalcs} | ${r.renderingUpdates} | ${r.recalcsPerRenderingUpdate} | ${r.perStepMin}..${r.perStepMax} | ${r.stepsWithNoRecalc} | ${r.animActive} |`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
