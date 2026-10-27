// node results/morph-push-sim/pool.mjs base=<dir> geom=<dir> timed=<dir> ... > pooled.md
// <dir> holds the toolbar-throttle-<job> artifacts of one dispatch of an arm; a VM is one job of one run, so the id is the dispatch index and the job.
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import * as M from '../../packages/measure-webkit/src/throttle/morph-push.mjs';

const LABELS = { base: 'morph-base', geom: 'morph-geom', timed: 'morph-timed' };
const byLabel = {}, lost = [];
const labels = process.argv.slice(2).map((a) => a.split('='));
labels.forEach(([label, dir], di) => {
  const jobs = [];
  for (const job of [1, 2, 3]) {
    const d = join(resolve(dir), `toolbar-throttle-${job}`);
    let files = [];
    try { files = readdirSync(d).filter((f) => f === `${job}-throttle.json`); } catch { files = []; }
    if (!files.length) { lost.push(`${label} job ${job}: no result file`); continue; }
    jobs.push({ ...JSON.parse(readFileSync(join(d, files[0]), 'utf8')), job });
  }
  byLabel[label] = M.vmsOf(jobs, LABELS[label], (j) => (di + 1) * 100 + j.job);
  for (const j of jobs) for (const f of j.failed ?? []) lost.push(`${label} job ${j.job}: ${f}`);
});

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
