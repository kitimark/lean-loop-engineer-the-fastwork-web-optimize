// node results/morph-push-sim/pool.mjs <dir> [<dir> ...] > pooled.md
// <dir> holds the toolbar-throttle-<job> artifacts of one run (any arms); a VM is one job of one run, so the id is the run index and the job.
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import * as M from '../../packages/measure-webkit/src/throttle/morph-push.mjs';

const LABELS = { base: 'morph-base', geom: 'morph-geom', timed: 'morph-timed' };
const byLabel = { base: [], geom: [], timed: [] }, lost = [], runs = [];
process.argv.slice(2).forEach((dir, di) => {
  const jobs = [];
  for (const job of [1, 2, 3]) {
    const f = join(resolve(dir), `toolbar-throttle-${job}`, `${job}-throttle.json`);
    let j;
    try { j = JSON.parse(readFileSync(f, 'utf8')); } catch { lost.push(`run ${di + 1} job ${job}: no result file`); continue; }
    jobs.push({ ...j, job });
    for (const x of j.failed ?? []) lost.push(`run ${di + 1} job ${job}: ${x}`);
  }
  runs.push(`run ${di + 1} = ${dir.split('/').pop()}`);
  for (const [label, arm] of Object.entries(LABELS)) byLabel[label].push(...M.vmsOf(jobs, arm, (j) => (di + 1) * 100 + j.job));
});
const labels = Object.keys(LABELS).map((l) => [l]);

const out = ['# Morph push on the Simulator: per-push windows (Lean PushCycle.armVerdict, minVms 3)', ''];
out.push('| arm | VMs (>= 3 windows) | job:passes:windows | style | layout | paint | rAF | slow |', '| --- | --- | --- | --- | --- | --- | --- | --- |');
for (const [label] of labels) {
  const vs = byLabel[label];
  const cols = M.KEYS.map((_, k) => vs.map((v) => (v.wins.length ? Math.round(M.rate(v.wins.map((w) => w[k])) / 100) / 10 : '-')).join(' / '));
  out.push(`| ${label} | ${M.vmCount(vs)} | ${vs.map((v) => `${v.vm % 100}:${v.passes}:${v.wins.length}`).join(' ')} | ${cols.join(' | ')} |`);
}
out.push('', 'Counts per push window (mean over the VM windows), one value per VM.', '');
out.push('| arm against | verdict | counters (style, layout, paint, rAF, slow) |', '| --- | --- | --- |');
const pairs = [['geom', 'base'], ['timed', 'base'], ['timed', 'geom']];
for (const [a, b] of pairs) {
  if (!byLabel[a] || !byLabel[b]) continue;
  out.push(`| ${a} vs ${b} | ${M.armVerdict(byLabel[b], byLabel[a])} | ${M.armCmps(byLabel[b], byLabel[a]).join(' ')} |`);
}
out.push('', '| arm | no style, layout, paint, rAF in any window | no page rAF in any window |', '| --- | --- | --- |');
for (const [label] of labels) out.push(`| ${label} | ${M.quietVerdict(M.quiet, byLabel[label])} | ${M.quietVerdict(M.rafFree, byLabel[label])} |`);
const sums = (label) => {
  const ws = byLabel[label].flatMap((v) => v.wins);
  return M.KEYS.map((_, k) => `${Math.max(0, ...ws.map((w) => w[k]))}`).join(' ');
};
out.push('', `Largest window count per arm (style layout paint rAF slow): ${labels.map(([l]) => `${l} ${sums(l)}`).join('; ')}`);
if (lost.length) out.push('', 'Lost:', ...lost.map((l) => `- ${l}`));
console.log(out.join('\n'));
