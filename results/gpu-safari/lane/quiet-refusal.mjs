// How many machine readings the Lean quiet rule (Fw.Measure.Quiet via safari-local-reduce.mjs) would accept for a timing pass right now.
//   node results/gpu-safari/lane/quiet-refusal.mjs [--n 24] [--every 5] [--mine <slot token>] [--out <file>]
// Each reading is `fw slot status --json` (the same read a pass takes). A reading is "quiet" when the rule accepts it against the largest
// idle floor the rule allows (Q.floorMaxCenti): a reading that fails even that cannot start a timing pass. Also reports `baselineFloor` over the window
// (null = no steady idle floor, so no pass runs at all). Reads only; it is the same decision a timing arm gets, counted.
import { writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { readMachine, brief } from '../../../packages/measure-webkit/src/safari-local-run.mjs';
import { quiet, whys, baselineFloor, Q } from '../../../packages/measure-webkit/src/safari-local-reduce.mjs';

const { values: v } = parseArgs({ options: { n: { type: 'string', default: '24' }, every: { type: 'string', default: '5' }, mine: { type: 'string', default: '' }, out: { type: 'string', default: '' } } });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const readings = [];
for (let i = 0; i < Number(v.n); i++) {
  readings.push(await readMachine({ cwd: process.cwd(), mine: v.mine ? [v.mine] : [] }));
  if (i + 1 < Number(v.n)) await sleep(Number(v.every) * 1000);
}
const verdicts = readings.map((r) => ({ ...brief(r), quiet: quiet(r, Q.floorMaxCenti), why: whys(r, Q.floorMaxCenti) }));
const loads = readings.map((r) => r.loadCenti / 100).sort((a, b) => a - b);
const res = {
  schema: 'fw.gpu-safari-quiet/1', at: new Date().toISOString(), readings: readings.length, quiet: verdicts.filter((x) => x.quiet).length, refused: verdicts.filter((x) => !x.quiet).length,
  floorMaxCenti: Q.floorMaxCenti, loadMarginCenti: Q.loadMarginCenti, baseMinSamples: Q.baseMinSamples,
  baselineFloorCenti: baselineFloor(readings), loadMin: loads[0], loadMedian: loads[Math.floor(loads.length / 2)], loadMax: loads[loads.length - 1],
  whyCounts: verdicts.flatMap((x) => (Array.isArray(x.why) ? x.why : [])).reduce((m, w) => ({ ...m, [w]: (m[w] ?? 0) + 1 }), {}),
};
console.log(JSON.stringify(res));
if (v.out) writeFileSync(v.out, JSON.stringify({ ...res, verdicts }, null, 1) + '\n');
