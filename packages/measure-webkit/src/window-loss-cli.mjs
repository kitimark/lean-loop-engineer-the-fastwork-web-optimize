// Reads <root>/<runId>/smoothness-webkit-sim-<n>[-retry]/{touch-lock.json,sim.log} (data only) and writes the window-loss tables.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { CLASSES, ARM_IDS, PLANNED, slotArm, jobOf, firstStall, jobWindows, jobCounts, armCounts, runCounts, total, sideTotal, rank, sufficient, jobsImplied, logFacts, restartTally } from './window-loss.mjs';
import { MIN_KEPT, MIN_SAMPLES, LATE_JOBS, REPS_WANT } from './walk-budget.mjs';

const JOB_SLOTS = 12;
const STATUS_OK = ['ok', 'noOpen', 'tooShort', 'lockMoved'];

const arg = (flag) => { const i = process.argv.indexOf(flag); return i < 0 ? null : process.argv[i + 1]; };
const root = arg('--root');
const out = arg('--out');
if (!root || !out) { console.error('usage: window-loss-cli.mjs --root <artifact dir> --out <result dir>'); process.exit(2); }

const readJson = (f) => (existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : null);
const readText = (f) => (existsSync(f) ? readFileSync(f, 'utf8') : null);

const runs = readdirSync(root).filter((d) => /^\d+$/.test(d)).sort();
const result = { classes: CLASSES, planned: PLANNED, runs: [] };
const REFUSED = ['noOpen', 'tooShort', 'lockMoved'];
const okIn = (ws, a) => ws.filter((w) => w[0] === a && w[1] === 'ok').length;
const levers = { base: { ok: 0, sufficient: 0 }, retryRefused: { ok: 0, sufficient: 0 }, noStall: { ok: 0, sufficient: 0 }, both: { ok: 0, sufficient: 0 } };
const chain = {};
const noOpenByRep = Array.from({ length: REPS_WANT }, () => [0, 0]);
const noOpenBy = { stalled: [0, 0], clean: [0, 0] };

for (const run of runs) {
  const dirs = readdirSync(`${root}/${run}`);
  const jobs = [];
  for (let n = 1; n <= JOB_SLOTS; n++) {
    const dir = [`smoothness-webkit-sim-${n}-retry`, `smoothness-webkit-sim-${n}`].find((d) => dirs.includes(d));
    const t = dir ? readJson(`${root}/${run}/${dir}/touch-lock.json`) : null;
    const log = dir ? readText(`${root}/${run}/${dir}/sim.log`) : null;
    const job = jobOf(t, log);
    const counts = jobCounts(job);
    const ws = jobWindows(job);
    const st = log ? firstStall(log) : null;
    const noStall = ws.map((w, i) => (st && i > st.after && w[1] !== 'ok' ? [w[0], 'ok'] : w));
    const retried = (v) => v.map((w) => (REFUSED.includes(w[1]) ? [w[0], 'ok'] : w));
    for (const [key, v] of [['base', ws], ['retryRefused', retried(ws)], ['noStall', noStall], ['both', retried(noStall)]]) {
      levers[key].ok += v.filter((w) => w[1] === 'ok').length;
      if (ARM_IDS.every((a) => MIN_KEPT <= okIn(v, a))) levers[key].sufficient++;
    }
    if (st) {
      const c = (chain[st.kind] ??= { jobs: 0, lostAfter: 0, okAfter: 0, readyS: [] });
      const after = ws.slice(st.after + 1);
      c.jobs++; c.lostAfter += after.filter((w) => w[1] !== 'ok').length; c.okAfter += after.filter((w) => w[1] === 'ok').length;
      if (st.readyS !== null) c.readyS.push(st.readyS);
    }
    if (job.fin.present) {
      ws.forEach((w, i) => {
        if (w[1] !== 'ok' && !REFUSED.includes(w[1])) return;
        const cell = noOpenByRep[Math.floor(i / 4)];
        const grp = noOpenBy[st ? 'stalled' : 'clean'];
        cell[1]++; grp[1]++;
        if (w[1] === 'noOpen') { cell[0]++; grp[0]++; }
      });
    }
    const statusOk = Object.fromEntries(ARM_IDS.map((a) => [a, STATUS_OK.reduce((s, c) => s + armCounts(job, a)[c], 0)]));
    jobs.push({
      slot: n,
      dir: dir ?? null,
      reps: job.fin.reps,
      rows: job.rows.length,
      wallSeconds: t?.wallSeconds ?? null,
      end: job.fin.present ? (job.fin.logReason ?? job.fin.incomplete ?? null)?.replace(/\s+/g, ' ').slice(0, 140) ?? null : 'no artifact',
      hardStop: log ? logFacts(log).hardStop : false,
      restart: log ? restartTally(log) : null,
      counts,
      arms: Object.fromEntries(ARM_IDS.map((a) => [a, armCounts(job, a)])),
      sufficient: sufficient(job),
      knownAccepted: ARM_IDS.every((a) => MIN_SAMPLES <= armCounts(job, a).ok),
      sufficientStatusOk: ARM_IDS.every((a) => MIN_KEPT <= statusOk[a]),
      armMismatch: t ? t.rows.filter((r, i) => r.arm !== slotArm(i)).length : 0,
    });
  }
  const k = Object.fromEntries(CLASSES.map((c) => [c, jobs.reduce((s, j) => s + j.counts[c], 0)]));
  result.runs.push({ run, armMismatch: jobs.reduce((n, j) => n + j.armMismatch, 0), jobs, counts: k, total: total(k), sufficient: jobs.filter((j) => j.sufficient).length, sufficientStatusOk: jobs.filter((j) => j.sufficientStatusOk).length, knownAccepted: jobs.filter((j) => j.knownAccepted).length });
}

const all = Object.fromEntries(CLASSES.map((c) => [c, result.runs.reduce((s, r) => s + r.counts[c], 0)]));
result.all = { counts: all, total: total(all), rank: rank(all), sides: Object.fromEntries(['ok', 'harness', 'simulator'].map((s) => [s, sideTotal(all, s)])) };
const slots = result.runs.length * JOB_SLOTS;
const suff = result.runs.reduce((s, r) => s + r.sufficient, 0);
const suffOk = result.runs.reduce((s, r) => s + r.sufficientStatusOk, 0);
const known = result.runs.reduce((s, r) => s + r.knownAccepted, 0);
result.sufficiency = {
  jobs: slots, accepted: suff, statusOk: suffOk, knownAccepted: known, jobsImpliedKnown: jobsImplied(known, slots),
  jobsImpliedAccepted: jobsImplied(suff, slots), jobsImpliedStatusOk: jobsImplied(suffOk, slots),
  perRun: result.runs.map((r) => ({ run: r.run, accepted: r.sufficient, statusOk: r.sufficientStatusOk, jobsAccepted: jobsImplied(r.sufficient, JOB_SLOTS), jobsStatusOk: jobsImplied(r.sufficientStatusOk, JOB_SLOTS) })),
  lateJobs: LATE_JOBS,
};
const stalls = {};
let restarts = 0;
const readyS = [];
for (const r of result.runs) for (const j of r.jobs) if (j.restart) { restarts += j.restart.restarts; readyS.push(...j.restart.readyS); for (const [k, v] of Object.entries(j.restart.stalls)) stalls[k] = (stalls[k] ?? 0) + v; }
result.restarts = { restarts, stalls, ready: readyS.length, readyMedianS: readyS.sort((a, b) => a - b)[Math.floor(readyS.length / 2)] ?? null, readyMaxS: readyS.at(-1) ?? null };

result.levers = levers;
result.chain = chain;
result.noOpenByRep = noOpenByRep;
result.noOpenBy = noOpenBy;

const used = CLASSES.filter((c) => result.runs.some((r) => r.counts[c] > 0));
const md = [];
md.push('# Lost touch-lock windows by class', '', `Planned windows per job: ${PLANNED} (6 reps x 4 arms); ${JOB_SLOTS} job slots per run.`, '');
md.push(`| run | planned | ${used.join(' | ')} |`, `|---|---|${used.map(() => '---').join('|')}|`);
for (const r of result.runs) md.push(`| ${r.run} | ${r.total} | ${used.map((c) => r.counts[c]).join(' | ')} |`);
md.push(`| all | ${result.all.total} | ${used.map((c) => all[c]).join(' | ')} |`, '');
md.push('## Ranked lost classes', '', '| class | windows | share of planned |', '|---|---|---|');
for (const [c, n] of result.all.rank.filter((x) => x[1] > 0)) md.push(`| ${c} | ${n} | ${(100 * n / result.all.total).toFixed(1)}% |`);
md.push('', `Sides: ok ${result.all.sides.ok}, harness ${result.all.sides.harness}, simulator ${result.all.sides.simulator} of ${result.all.total}.`, '');
md.push('## Per job and arm', '', 'Each cell is the class counts of that arm (6 planned windows) as `class:n`, ok first.', '');
for (const r of result.runs) {
  md.push(`### Run ${r.run}`, '', '| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const j of r.jobs) {
    const cell = (a) => CLASSES.filter((c) => j.arms[a][c] > 0).map((c) => `${c}:${j.arms[a][c]}`).join(' ');
    md.push(`| ${j.slot} | ${j.reps} | ${j.rows} | ${j.wallSeconds ?? '-'} | ${(j.end ?? 'complete').replace(/\|/g, '/').slice(0, 70)} | ${ARM_IDS.map(cell).join(' | ')} | ${j.sufficient ? 'yes' : 'no'} |`);
  }
  md.push('');
}
md.push('## Sufficiency and jobs implied', '', `Jobs with every arm at minKept (${MIN_KEPT}) accepted windows: ${suff} of ${slots}; with status-ok windows: ${suffOk} of ${slots}.`);
md.push(`Jobs with every arm at minSamples (${MIN_SAMPLES}) accepted windows: ${known} of ${slots}; WalkBudget.jobsFor at that rate: ${result.sufficiency.jobsImpliedKnown ?? 'not within jobsCap'}.`);
md.push(`WalkBudget.jobsFor at the accepted rate ${suff}/${slots}: ${result.sufficiency.jobsImpliedAccepted ?? 'not within jobsCap'}; at the status-ok rate ${suffOk}/${slots}: ${result.sufficiency.jobsImpliedStatusOk ?? 'not within jobsCap'}.`, '');
md.push('| run | accepted | status ok | jobs at accepted rate (of 12) | jobs at status-ok rate (of 12) |', '|---|---|---|---|---|');
for (const p of result.sufficiency.perRun) md.push(`| ${p.run} | ${p.accepted} | ${p.statusOk} | ${p.jobsAccepted ?? 'none'} | ${p.jobsStatusOk ?? 'none'} |`);
md.push('', `Restarts started: ${restarts}; stalls ${JSON.stringify(stalls)}; push server ready after a restart: ${readyS.length}, median ${result.restarts.readyMedianS} s, max ${result.restarts.readyMaxS} s.`, '');

md.push('## Counterfactual upper bounds (INFERRED, not measured)', '', 'Windows ok and jobs with every arm at minKept if (retryRefused) every refused window were rerun ok, (noStall) every window after the first stall ran ok, or both.', '', '| lever | ok windows | sufficient jobs of ' + slots + ' |', '|---|---|---|');
for (const [k, v] of Object.entries(levers)) md.push(`| ${k} | ${v.ok} | ${v.sufficient} |`);
md.push('', '## First stall of a job and what followed', '', '| first stall | jobs | lost windows after | ok windows after | push server ready after (s) |', '|---|---|---|---|---|');
for (const [k, v] of Object.entries(chain)) md.push(`| ${k} | ${v.jobs} | ${v.lostAfter} | ${v.okAfter} | ${v.readyS.join(', ') || 'never'} |`);
md.push('', '## noOpen share of the windows that ran (status ok), by rep and by job', '', '| rep | ' + noOpenByRep.map((_, i) => i).join(' | ') + ' |', '|---|' + noOpenByRep.map(() => '---').join('|') + '|', '| noOpen / ran | ' + noOpenByRep.map((c) => `${c[0]}/${c[1]}`).join(' | ') + ' |', '', `Jobs with a stall: ${noOpenBy.stalled[0]}/${noOpenBy.stalled[1]}; jobs without: ${noOpenBy.clean[0]}/${noOpenBy.clean[1]}.`, '');

mkdirSync(out, { recursive: true });
writeFileSync(`${out}/window-loss.json`, `${JSON.stringify(result, null, 1)}\n`);
writeFileSync(`${out}/window-loss.md`, `${md.join('\n')}\n`);
console.log(`window-loss: ${result.runs.length} runs, ${result.all.total} planned windows, ${result.all.counts.ok} ok`);
