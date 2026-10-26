import fs from 'node:fs';
import { passesOfDir } from '../../packages/measure-webkit/src/offscreen-webkit-cli.mjs';
import { cmpKeys, passVerdict, undecided, verdict, vmCount, windowSteps, windowVec } from '../../packages/measure-webkit/src/offscreen-webkit.mjs';

// Glue only: the window rule, the VM rule and the verdict are the committed reader's functions (Fw.Measure.OffscreenWebKit
// golden). The windows are the hero-exit scroll range instead of the reader's end zones.
// Usage: node read-webkit.mjs <out.json> base=<dir>[,<dir>] flag=<dir>[,<dir>]
const WINDOWS = [
  { name: 'hero-exit', lo: 0, hi: 1000 },
  { name: 'after-exit', lo: 1001, hi: 2500 },
  { name: 'whole', lo: 0, hi: 5200 },
];
const SHOWN = ['Layout', 'RecalculateStyles', 'Paint', 'InvalidateLayout', 'Composite'];

const [out, ...specs] = process.argv.slice(2);
const arms = specs.map((s) => {
  const [name, dirs] = s.split('=');
  return { name, passes: dirs.split(',').flatMap(passesOfDir) };
});
const [base, flag] = arms;
const rows = WINDOWS.map((w) => {
  const col = (ps, k) => ps.map((p) => windowVec(w.lo, w.hi, p).vals[k]);
  const steps = [...base.passes, ...flag.passes].map((p) => windowSteps(w.lo, w.hi, p).length);
  const pv = passVerdict(w.lo, w.hi, base.passes, flag.passes);
  return {
    window: w.name, lo: w.lo, hi: w.hi, steps: [Math.min(...steps), Math.max(...steps)],
    passes: [base.passes.length, flag.passes.length], vms: [vmCount(base.passes), vmCount(flag.passes)],
    undecided: undecided(base.passes, flag.passes), verdict: verdict(w.lo, w.hi, base.passes, flag.passes),
    passVerdict: pv, cmp: pv === 'noData' ? {} : cmpKeys(w.lo, w.hi, base.passes, flag.passes),
    counts: Object.fromEntries(SHOWN.map((k) => [k, { base: col(base.passes, k), flag: col(flag.passes, k) }])),
  };
});
fs.writeFileSync(out, JSON.stringify({ schema: 'hero-relayout-boundary-webkit/1', rows }, null, 1) + '\n');
process.stdout.write(JSON.stringify(rows.map(({ counts, ...r }) => r)) + '\n');
