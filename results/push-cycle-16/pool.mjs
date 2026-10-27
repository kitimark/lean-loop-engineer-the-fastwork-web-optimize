// node results/push-cycle-16/pool.mjs <label>=<dir of toolbar-throttle-N artifacts> ... > pooled.md
// One report over the jobs of several runs of the same lane; a job is named "<label> job <vm>", expected jobs are 1 to 6 of every run.
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { reportMd } from '../../packages/measure-webkit/src/throttle/push-cycle-report.mjs';

const jobs = [], expect = [];
for (const arg of process.argv.slice(2)) {
  const [label, dir] = arg.split('=');
  for (const vm of [1, 2, 3, 4, 5, 6]) {
    expect.push(`${label} job ${vm}`);
    const d = join(resolve(dir), `toolbar-throttle-${vm}`);
    let files = [];
    try { files = readdirSync(d).filter((f) => f === `${vm}-throttle.json`); } catch { files = []; }
    if (files.length) {
      const j = JSON.parse(readFileSync(join(d, files[0]), 'utf8'));
      const name = `${label} job ${vm}`;
      jobs.push({ ...j, vm: name, passes: j.passes.map((p) => ({ ...p, vm: name })) });
    }
  }
}
console.log(reportMd(jobs, expect));
