// Observations of a breakpoint-gate CI run for the shard plan (task gate-shard-balance): writes lean/Fw/Gate/ShardObs.lean,
// the raw data that Fw.Gate.ShardCosts.reduce turns into the cost table of Fw.Gate.Shard. Glue only: it measures times and
// copies weights; every decision (overhead, rounding, setup mean, the plan) is Lean's.
//   gh run view <run> --json jobs > jobs.json;  gh run view <run> --log > run.log;  gh run download <run> -D art
//   node packages/gate-breakpoints/scripts/shard-obs.mjs --run <id> --commit <sha> --jobs jobs.json --log run.log --art art \
//        [--out lean/Fw/Gate/ShardObs.lean] [--check]
// Per gate job (`gate <engine> j<k>`):
//   probes      each probe id of its artifact (gate-<engine>-j<k>/<engine>.json) with weight = the settle waits of its two
//               arms (raw.settleWait.waitedMs + settle.animations.waitedMs);
//   sweeps      each whole sweep with its wall time: the `sweep <id> done (..., <ms> ms)` line when present, else from the
//               previous phase boundary to its `done` line;
//   probeWall   the `probes done (..., <ms> ms)` line when present, else from the start of the run step to the start of the
//               first sweep (its first `resize` line less the gap to the next resize of the same arm), or to the step
//               end without sweeps;
//   setup       the job's wall time less probeWall and its sweeps.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const argv = process.argv.slice(2);
const arg = (n, d) => { const i = argv.indexOf(`--${n}`); return i < 0 ? d : argv[i + 1]; };
const die = (m) => { console.error(`shard-obs: ${m}`); process.exit(1); };
const runId = arg('run') ?? die('--run <id> missing');
const commit = arg('commit') ?? die('--commit <sha> missing');
const jobsJson = JSON.parse(readFileSync(resolve(arg('jobs') ?? die('--jobs missing')), 'utf8'));
const logText = readFileSync(resolve(arg('log') ?? die('--log missing')), 'utf8');
const artDir = resolve(arg('art') ?? die('--art missing'));
const outPath = resolve(arg('out', 'lean/Fw/Gate/ShardObs.lean'));
const STEP = 'Run the job (probes, then whole sweeps)';
const ms = (s) => Date.parse(s);

// log lines: "<job name>\t<step name>\t<ISO time> <text>"
const lines = new Map();
for (const l of logText.split('\n')) {
  const [job, step, rest] = l.split('\t');
  if (!rest || step !== STEP) continue;
  const sp = rest.indexOf(' ');
  const t = ms(rest.slice(0, sp));
  if (Number.isNaN(t)) continue;
  if (!lines.has(job)) lines.set(job, []);
  lines.get(job).push({ t, text: rest.slice(sp + 1) });
}

const short = (id) => id.split('-')[0];
const out = { chromium: [], 'playwright-webkit': [] };
for (const job of jobsJson.jobs) {
  const m = /^gate (\S+) (j\d+)$/.exec(job.name);
  if (!m) continue;
  const [, engine, slot] = m;
  if (job.conclusion !== 'success') die(`${job.name}: conclusion ${job.conclusion}`);
  const step = job.steps.find((s) => s.name === STEP) ?? die(`${job.name}: no run step`);
  const stepStart = ms(step.startedAt);
  const stepEnd = ms(step.completedAt);
  const wall = ms(job.completedAt) - ms(job.startedAt);
  const ls = lines.get(job.name) ?? die(`${job.name}: no log lines`);

  const file = join(artDir, `gate-${engine}-${slot}`, `${engine}.json`);
  if (!existsSync(file)) die(`${file} missing`);
  const rec = JSON.parse(readFileSync(file, 'utf8'));
  const armWait = (a) => (a?.raw?.settleWait?.waitedMs ?? 0) + (a?.settle?.animations?.waitedMs ?? 0);
  const probes = rec.probes.map((p) => [p.id, Math.round(armWait(p.orig) + armWait(p.rewrite))]);

  const done = ls.filter((l) => / sweep \S+ done \(/.test(l.text));
  const probesDone = ls.find((l) => / probes done \(\d+ loads, \d+ ms\)/.test(l.text));
  let probeWall;
  let boundary;
  if (probesDone) {
    probeWall = Number(/, (\d+) ms\)/.exec(probesDone.text)[1]);
    boundary = probesDone.t;
  } else if (probes.length === 0) {
    probeWall = 0;
    boundary = stepStart;
  } else if (done.length === 0) {
    probeWall = stepEnd - stepStart;
    boundary = stepEnd;
  } else {
    // the two arms of a sweep run at once: take the gap between the first two resizes of the same arm
    const rs = ls.filter((l) => / resize /.test(l.text));
    const arm = (l) => / resize \S+ (\S+) /.exec(l.text)?.[1];
    const next = rs.find((l, i) => i > 0 && arm(l) === arm(rs[0]));
    if (!next) die(`${job.name}: cannot place the first sweep's start`);
    const start = rs[0].t - (next.t - rs[0].t);
    probeWall = start - stepStart;
    boundary = start;
  }
  const sweeps = done.map((l) => {
    const id = / sweep (\S+) done/.exec(l.text)[1];
    const own = / stops, (\d+) ms\)/.exec(l.text);
    const t = own ? Number(own[1]) : l.t - boundary;
    boundary = l.t;
    return [short(id), t];
  });
  const setup = wall - probeWall - sweeps.reduce((a, [, t]) => a + t, 0);
  if (setup < 0 || probeWall < 0 || sweeps.some(([, t]) => t < 0)) die(`${job.name}: negative time`);
  out[engine]?.push({ slot, setup, probeWall, probes, sweeps }) ?? die(`unknown engine ${engine}`);
  console.error(`${job.name}: wall ${wall} setup ${setup} probes ${probes.length} in ${probeWall} sweeps ${sweeps.map((s) => s.join(' ')).join(', ') || 'none'}`);
}

const str = (s) => JSON.stringify(s);
const pairs = (ps) => {
  const items = ps.map(([n, v]) => `(${str(n)}, ${v})`);
  const rows = [];
  for (let i = 0; i < items.length; i += 6) rows.push(items.slice(i, i + 6).join(', '));
  return `[${rows.join(',\n      ')}]`;
};
const job = (j) => `  -- ${j.slot}\n  { setup := ${j.setup}, probeWall := ${j.probeWall},\n    probes := ${pairs(j.probes)},\n    sweeps := ${pairs(j.sweeps)} }`;
const eng = (name, js) => `def ${name} : List JobObs := [\n${js.sort((a, b) => a.slot.localeCompare(b.slot)).map(job).join(',\n')}]\n`;
const lean = `-- GENERATED by node packages/gate-breakpoints/scripts/shard-obs.mjs from breakpoint-gate run ${runId}: do not edit by hand
import Fw.Gate.ShardCosts
/-! Observed gate jobs of breakpoint-gate run ${runId} at ${commit}, in milliseconds. -/
namespace Fw.Gate.ShardCosts

/-- The CI run the observations come from. -/
def source : String := ${str(`breakpoint-gate run ${runId} at ${commit}`)}

${eng('chromiumJobs', out.chromium)}
${eng('webkitJobs', out['playwright-webkit'])}
/-- Measured costs of both engines: the reduction of the observed jobs. -/
def measured : Fw.Gate.Shard.Costs := { chromium := reduce chromiumJobs, webkit := reduce webkitJobs }

end Fw.Gate.ShardCosts
`;
if (argv.includes('--check')) {
  if (!existsSync(outPath) || readFileSync(outPath, 'utf8') !== lean) die(`${outPath} differs from the observations of run ${runId}`);
  console.error(`identical: ${outPath}`);
} else {
  writeFileSync(outPath, lean);
  console.error(`wrote ${outPath}`);
}
