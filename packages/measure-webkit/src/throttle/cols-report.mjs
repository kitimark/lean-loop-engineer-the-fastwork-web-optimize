// WebKit Simulator side of the column picture probe (Lean Fw.Device.ColsProbe, twin packages/measure-chromium/src/cols-verdict.mjs).
// Input: the per-VM job files of push-cycle-cli.mjs run --morph-push (arms morph-base, morph-base-off, morph-timed, morph-timed-off).
// Per job and arm: layerCount and backingBytes from the census after the last cycle (page at its end), Paint as thousandths of Paint rows
// per push window (Lean PushCycle windows, morph-push.mjs), and the flip log (pushes, takes, on-dark at push).
import { ARMS, contrast, wkArmOf } from '../../../measure-chromium/src/cols-verdict.mjs';
import { takeStats } from '../../../measure-chromium/src/cols-reduce.mjs';
import { MIN_WINS, passRec, passUsable, vmVec, windows } from './morph-push.mjs';

const floorMean = (xs) => (xs.length ? Math.floor(xs.reduce((a, b) => a + b, 0) / xs.length) : null);

/** One arm in one job file: the usable passes' metrics, or null when the job has fewer than MIN_WINS push windows. */
export function armJob(job, wkArm) {
  const ps = (job.passes ?? []).filter((p) => p.arm === wkArm && passUsable(p));
  const wins = ps.flatMap((p) => windows(passRec(p), p.push.starts));
  if (wins.length < MIN_WINS) return { passes: ps.length, windows: wins.length, metrics: null, log: { pushes: 0, took: 0, dark: 0 } };
  const last = ps.map((p) => p.census?.at(-1)).filter(Boolean);
  const log = ps.map((p) => takeStats(p.takeLog)).reduce((a, t) => ({ pushes: a.pushes + t.pushes, took: a.took + t.took, dark: a.dark + t.dark }), { pushes: 0, took: 0, dark: 0 });
  return {
    passes: ps.length, windows: wins.length, log,
    metrics: { layerCount: floorMean(last.map((x) => x.layers)), backingBytes: floorMean(last.map((x) => x.bytes)), Paint: vmVec({ wins })[2] },
  };
}

export function reduceJobs(jobs) {
  const jobsBy = {}; const logs = {}; const perJob = [];
  for (const a of ARMS) {
    jobsBy[a.id] = []; logs[a.id] = { took: 0, pushes: 0, dark: 0 };
    jobs.forEach((job, i) => {
      const r = armJob(job, wkArmOf(a));
      perJob.push({ job: job.vm ?? i + 1, arm: a.id, passes: r.passes, windows: r.windows, metrics: r.metrics, log: r.log });
      if (!r.metrics) return;
      jobsBy[a.id].push(r.metrics);
      for (const k of ['took', 'pushes', 'dark']) logs[a.id][k] += r.log[k];
    });
  }
  const contrasts = { base: contrast('webkit', jobsBy, 'base+off', logs), flip: contrast('webkit', jobsBy, 'timed-fixed+off', logs) };
  return { engine: 'webkit', jobs: jobs.length, perJob, logs, contrasts };
}

export function colsMd(r) {
  const out = ['# Column picture probe, WebKit Simulator push lane', '', `${r.jobs} job files`, '', '| job | arm | passes | windows | layerCount | backingBytes | Paint per 1000 pushes | pushes | took | dark |', '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  for (const j of r.perJob) out.push(`| ${j.job} | ${j.arm} | ${j.passes} | ${j.windows} | ${j.metrics?.layerCount ?? '-'} | ${j.metrics?.backingBytes ?? '-'} | ${j.metrics?.Paint ?? '-'} | ${j.log.pushes} | ${j.log.took} | ${j.log.dark} |`);
  out.push('');
  for (const [name, c] of Object.entries(r.contrasts)) {
    out.push(`## ${name}: ${c.ref} vs ${c.off}: ${c.reading}${c.valid ? '' : ' (flip arm below the take share)'}`, '');
    for (const m of c.cells) out.push(`- ${m.metric}: ref [${m.ref.join(', ')}] off [${m.off.join(', ')}] -> ${m.cell}`);
    out.push('');
  }
  return `${out.join('\n')}\n`;
}
