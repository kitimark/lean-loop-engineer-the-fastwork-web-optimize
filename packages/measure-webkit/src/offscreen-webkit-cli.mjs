import { readdirSync, readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { ZONES, cmpKeys, passOf, passVerdict, undecided, verdict, vmCount, windowSteps, windowVec } from './offscreen-webkit.mjs';

const range = (xs) => (xs.length === 0 ? '-' : Math.min(...xs) === Math.max(...xs) ? String(xs[0]) : `${Math.min(...xs)}-${Math.max(...xs)}`);

export function vmOfDir(dir) {
  const m = /^webkit-sim-r(\d+)$/.exec(basename(dir));
  if (!m) throw new Error(`${dir}: not a webkit-sim-r<k> artifact dir, no VM id`);
  return Number(m[1]);
}

export function passesOfDir(dir) {
  const vm = vmOfDir(dir);
  return readdirSync(dir).filter((f) => /session-\d+\.json$/.test(f)).sort().flatMap((f) => {
    const j = JSON.parse(readFileSync(join(dir, f), 'utf8'));
    return (j.passes ?? []).filter((p) => p.scroll?.reduced?.perStep).map((p) => ({ file: f, ...passOf(p, vm) }));
  });
}

export function report(arms, shown = ['Paint', 'Layout', 'RecalculateStyles', 'Composite', 'FireAnimationFrame', 'ObserverCallback']) {
  const [base, ...rest] = arms;
  const rows = [];
  for (const z of ZONES) {
    const steps = windowSteps(z.lo, z.hi, base.passes[0] ?? { ys: [] }).length;
    for (const arm of rest) {
      const v = verdict(z.lo, z.hi, base.passes, arm.passes);
      const open = undecided(base.passes, arm.passes);
      const pv = passVerdict(z.lo, z.hi, base.passes, arm.passes);
      const diff = pv === 'noData' ? {} : Object.fromEntries(Object.entries(cmpKeys(z.lo, z.hi, base.passes, arm.passes)).filter(([, c]) => c !== 'same'));
      const col = (ps, k) => ps.map((p) => windowVec(z.lo, z.hi, p).vals[k]);
      rows.push({
        zone: z.name, steps, arm: arm.name, passes: [base.passes.length, arm.passes.length],
        vms: [vmCount(base.passes), vmCount(arm.passes)], undecided: open, verdict: v,
        passVerdict: pv, differing: diff,
        ranges: Object.fromEntries(shown.map((k) => [k, { base: range(col(base.passes, k)), arm: range(col(arm.passes, k)) }])),
      });
    }
  }
  return rows;
}

export const label = (r) => (r.undecided ? `undecided (n=${r.vms.join('+')} VMs)` : r.verdict);

export function markdown(rows, shown = Object.keys(rows[0]?.ranges ?? {})) {
  const head = `| zone | steps | arm | passes | VMs | verdict | pass rule only | differing | ${shown.map((k) => `${k} base / arm`).join(' | ')} |`;
  const sep = `|${' --- |'.repeat(8 + shown.length)}`;
  const body = rows.map((r) => `| ${r.zone} | ${r.steps} | ${r.arm} | ${r.passes.join('+')} | ${r.vms.join('+')} | ${label(r)} | ${r.passVerdict} | ${Object.entries(r.differing).map(([k, c]) => `${k} ${c}`).join(', ') || '-'} | ${shown.map((k) => `${r.ranges[k].base} / ${r.ranges[k].arm}`).join(' | ')} |`);
  return [head, sep, ...body].join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const arms = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] !== '--arm') continue;
    const [name, dirs] = args[++i].split('=');
    arms.push({ name, passes: dirs.split(',').flatMap(passesOfDir) });
  }
  if (arms.length < 2) throw new Error('usage: --arm base=dir[,dir] --arm name=dir[,dir] [--json]');
  const rows = report(arms);
  console.log(args.includes('--json') ? JSON.stringify(rows, null, 1) : markdown(rows));
}
