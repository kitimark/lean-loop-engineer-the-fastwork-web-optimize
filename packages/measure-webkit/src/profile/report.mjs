// Tables of the smoothness-webkit-cadence lane from the downloaded leg files (mac.json, sim.json). Reads only; groups and prints.
// Every decision is a twin of Lean: the per-zone profile and its verdict (reduce.mjs, WebKitProfile.lean), the cadence hitch rule and
// the agreement over jobs (gate-breakpoints smooth/reduce.mjs, Gate/Smooth.lean), the determinism class (fwcore `classify`).
// Layout read: <runs>/<runId>/<artifact>/{mac,sim}.json; one file is one CI job, one sample.
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { KINDS, ZONES, medianNat, zoneVerdict } from './reduce.mjs';
import { across, agreeNeeded, hitchVerdict, armRate, repOf, quantile } from '../../../gate-breakpoints/src/smooth/reduce.mjs';

/** The pairs judged, each against the A/A pair (base, aa): [first arm, second arm]. `first` = the first arm does less. */
export const PAIRS = [['orig', 'base'], ['base', 'look'], ['orig', 'look'], ['base', 'v2']];
export const KEY_KINDS = ['RecalculateStyles', 'Layout', 'Paint', 'Composite', 'FunctionCall', 'FireAnimationFrame'];
const ALL_ARMS = ['orig', 'base', 'aa', 'look', 'v2'];

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const med = (l) => (l.length ? medianNat(l) : null);

/** The leg files under `dir`: [{ label, leg, file }]; an unreadable or refused file is listed in `skipped`. */
export function loadRuns(dir) {
  const files = [];
  const skipped = [];
  for (const id of readdirSync(dir).filter((n) => /^\d+$/.test(n)).sort()) {
    for (const f of walk(join(dir, id)).filter((p) => /\/(mac|sim)\.json$/.test(p))) {
      const file = JSON.parse(readFileSync(f, 'utf8'));
      const label = `${id}:${f.slice(join(dir, id).length + 1).split('/')[0]}`;
      if (file.refused || !file.rows?.length) { skipped.push({ run: label, why: file.refused ? 'refused' : 'empty' }); continue; }
      files.push({ label, leg: file.leg, file });
    }
  }
  return { files, skipped };
}

/** The kept event windows of an arm in a zone, by rep: the zone's profile, only where the zone had frames. */
export function zoneReps(file, arm, zone) {
  return file.rows
    .filter((r) => r.arm === arm && r.mode === 'events' && r.ok && r.profiles?.[zone]?.frames > 0)
    .sort((a, b) => a.rep - b.rep)
    .map((r) => ({ rep: r.rep, window: r.window, ...r.profiles[zone] }));
}

const cellOfKind = (p, k) => p.cells.find((c) => c[0] === k) ?? [k, 0, 0];

/** One job, one arm, one zone: medians over the kept windows. Durations are hundredths of ms, work per frame is microseconds. */
export function jobCell(file, arm, zone) {
  const ps = zoneReps(file, arm, zone);
  const kinds = Object.fromEntries(KINDS.map((k) => [k, { n: med(ps.map((p) => cellOfKind(p, k)[1])), dur: med(ps.map((p) => cellOfKind(p, k)[2])) }]));
  return { reps: ps.length, frames: med(ps.map((p) => p.frames)), perFrame: med(ps.map((p) => p.perFrame)), perFrameAll: ps.map((p) => p.perFrame), work: med(ps.map((p) => p.work)), kinds };
}

/** Lean `zoneVerdict` for one job and zone, on the per-window render work per frame, against the A/A pair (base, aa). */
export function jobVerdicts(file, zone) {
  const pf = (arm) => zoneReps(file, arm, zone).map((p) => p.perFrame);
  return Object.fromEntries(PAIRS.filter(([a, b]) => [a, b].every((x) => file.arms.includes(x))).map(([a, b]) => [`${a}|${b}`, zoneVerdict(pf(a), pf(b), pf('base'), pf('aa'))]));
}

/** The verdict over jobs per pair: Lean `across` with `agreeNeeded n`. */
export function acrossJobs(perJob) {
  const pairs = [...new Set(perJob.flatMap((v) => Object.keys(v)))];
  return Object.fromEntries(pairs.map((p) => {
    const vs = perJob.map((v) => v[p]).filter((x) => x !== undefined);
    return [p, { jobs: vs.length, first: vs.filter((x) => x === 'first').length, second: vs.filter((x) => x === 'second').length, same: vs.filter((x) => x === 'same').length, insufficient: vs.filter((x) => x === 'insufficient').length, verdict: across(agreeNeeded(vs.length), vs) }];
  }));
}

/** Cadence of one job window and arm: the rows of the given mode, repeats ordered by rep. */
const cadRows = (file, arm, win, mode) => file.rows.filter((r) => r.arm === arm && r.window === win && r.mode === mode && r.ivs).sort((a, b) => a.rep - b.rep);

/** Hitch counts per repeat and the Lean hitch verdict on them, per job, window and mode. */
export function jobCadence(file, win, mode) {
  const hs = (arm) => cadRows(file, arm, win, mode).map((r) => r.hitches);
  const arms = Object.fromEntries(file.arms.map((a) => {
    const rs = cadRows(file, a, win, mode);
    const ivs = rs.flatMap((r) => r.ivs);
    const reps = rs.map((r) => repOf(r.ivs));
    return [a, { reps: rs.length, hitches: hs(a), rate: armRate(reps), p50: quantile(ivs, 50), p95: quantile(ivs, 95), max: ivs.length ? Math.max(...ivs) : null }];
  }));
  const verdicts = Object.fromEntries(PAIRS.filter(([a, b]) => [a, b].every((x) => file.arms.includes(x))).map(([a, b]) => [`${a}|${b}`, hitchVerdict(hs(a), hs(b), hs('base'), hs('aa'))]));
  return { arms, verdicts };
}

/** Everything for one leg over its jobs. */
export function legSummary(jobs, classify) {
  const arms = ALL_ARMS.filter((a) => jobs.some((j) => j.file.arms.includes(a)));
  const zones = {};
  for (const z of ZONES) {
    const cells = Object.fromEntries(arms.map((a) => [a, jobs.map((j) => ({ job: j.label, ...jobCell(j.file, a, z) }))]));
    const perJobV = jobs.map((j) => jobVerdicts(j.file, z));
    const classes = {};
    for (const a of arms) {
      const runs = cells[a].filter((c) => c.reps > 0).map((c) => [{ counts: Object.fromEntries(KINDS.map((k) => [k, c.kinds[k].n ?? 0])) }]);
      classes[a] = runs.length >= 3 ? classify(runs, 4, 24) : null;
    }
    zones[z] = { cells, verdicts: acrossJobs(perJobV), perJob: perJobV.map((v, i) => ({ job: jobs[i].label, ...v })), classes };
  }
  const cadence = {};
  for (const win of ['hero', 'end']) for (const mode of ['events', 'cadence']) {
    const per = jobs.map((j) => ({ job: j.label, ...jobCadence(j.file, win, mode) })).filter((c) => Object.values(c.arms).some((a) => a.reps > 0));
    if (per.length) cadence[`${win}|${mode}`] = { jobs: per, verdicts: acrossJobs(per.map((c) => c.verdicts)) };
  }
  return { arms, zones, cadence };
}

// ---- printing ----

const ms2 = (h) => (h == null ? '-' : (h / 100).toFixed(2));
const fmt = (x) => (x == null ? '-' : String(x));
const row = (cells) => `| ${cells.join(' | ')} |`;
const head = (cols) => `${row(cols)}\n${row(cols.map(() => '---'))}`;
const pooled = (cells, f) => med(cells.filter((c) => c.reps > 0).map(f).filter((x) => x != null));
const range = (cells) => {
  const all = cells.flatMap((c) => c.perFrameAll);
  return all.length ? `${Math.min(...all)}-${Math.max(...all)}` : '-';
};

/** Headline table of a leg: per zone and arm, the median over jobs of the per-job medians (frames, render work per frame, key counts). */
export function headlineTable(leg) {
  const out = [];
  for (const z of ZONES) {
    out.push(`**${z}**\n`);
    out.push(head(['arm', 'jobs', 'windows', 'frames', 'render us/frame (median, range)', ...KEY_KINDS.map((k) => `${k} n`)]));
    for (const a of leg.arms) {
      const cs = leg.zones[z].cells[a];
      out.push(row([a, cs.filter((c) => c.reps > 0).length, cs.reduce((s, c) => s + c.reps, 0), fmt(pooled(cs, (c) => c.frames)), `${fmt(pooled(cs, (c) => c.perFrame))} (${range(cs)})`, ...KEY_KINDS.map((k) => fmt(pooled(cs, (c) => c.kinds[k].n)))]));
    }
    out.push('');
  }
  return out.join('\n');
}

/** Per-kind table (count and summed ms) of a leg, per zone. */
export function kindTable(leg) {
  const out = [];
  for (const z of ZONES) {
    out.push(`**${z}** (median count / median summed ms per window)\n`);
    out.push(head(['kind', ...leg.arms]));
    for (const k of KINDS) out.push(row([k, ...leg.arms.map((a) => { const cs = leg.zones[z].cells[a]; return `${fmt(pooled(cs, (c) => c.kinds[k].n))} / ${ms2(pooled(cs, (c) => c.kinds[k].dur))}`; })]));
    out.push('');
  }
  return out.join('\n');
}

/** Verdict table of a leg: per zone and pair, the jobs that said first / second / same, and the verdict over jobs. */
export function verdictTable(leg) {
  const out = [head(['zone', 'pair (first, second)', 'jobs', 'first', 'second', 'same', 'insufficient', 'verdict over jobs'])];
  for (const z of ZONES) for (const [p, v] of Object.entries(leg.zones[z].verdicts)) out.push(row([z, p.replace('|', ', '), v.jobs, v.first, v.second, v.same, v.insufficient, v.verdict]));
  return out.join('\n');
}

/** Class counts per type (deterministic, stable, quarantined) per zone and arm over jobs. */
export function classTable(leg) {
  const out = [head(['zone', 'arm', 'jobs', 'deterministic', 'stable', 'quarantined'])];
  for (const z of ZONES) for (const a of leg.arms) {
    const cl = leg.zones[z].classes[a];
    const jobs = leg.zones[z].cells[a].filter((c) => c.reps > 0).length;
    const n = (c) => (cl ? Object.values(cl).filter((x) => x.class === c).length : '-');
    out.push(row([z, a, jobs, n('deterministic'), n('stable'), n('quarantined')]));
  }
  return out.join('\n');
}

/** Cadence table of a leg: per window and mode, per arm the pooled hitch counts (frames over 60 ms) and interval quantiles (ms). */
export function cadenceTable(leg) {
  const out = [head(['window', 'timeline', 'arm', 'jobs', 'reps', 'hitches per rep (median)', 'p50 ms', 'p95 ms', 'max ms'])];
  for (const [key, c] of Object.entries(leg.cadence)) {
    const [win, mode] = key.split('|');
    for (const a of leg.arms) {
      const ps = c.jobs.map((j) => j.arms[a]).filter((x) => x && x.reps > 0);
      if (!ps.length) continue;
      out.push(row([win, mode === 'events' ? 'on' : 'off', a, ps.length, ps.reduce((s, p) => s + p.reps, 0), fmt(med(ps.flatMap((p) => p.hitches))), (med(ps.map((p) => p.p50)) / 10).toFixed(1), (med(ps.map((p) => p.p95)) / 10).toFixed(1), (Math.max(...ps.map((p) => p.max)) / 10).toFixed(1)]));
    }
  }
  return out.join('\n');
}

/** Cadence verdicts over jobs (the Lean hitch rule), per window, mode and pair. */
export function cadenceVerdictTable(leg) {
  const out = [head(['window', 'timeline', 'pair (first, second)', 'jobs', 'first', 'second', 'same', 'insufficient', 'verdict over jobs'])];
  for (const [key, c] of Object.entries(leg.cadence)) {
    const [win, mode] = key.split('|');
    for (const [p, v] of Object.entries(c.verdicts)) out.push(row([win, mode === 'events' ? 'on' : 'off', p.replace('|', ', '), v.jobs, v.first, v.second, v.same, v.insufficient, v.verdict]));
  }
  return out.join('\n');
}

/** What each leg ran: engine, version, arms kept and dropped (by resolved flags), reps, windows kept and refused. */
export function runTable(jobs) {
  const out = [head(['job', 'leg', 'engine', 'version / runtime', 'arms', 'dropped by flags', 'windows', 'kept', 'refused (reason)', 'wall s'])];
  for (const j of jobs) {
    const f = j.file;
    const ev = f.rows.filter((r) => r.mode === 'events');
    const refused = ev.filter((r) => !r.ok);
    const why = [...new Set(refused.map((r) => r.reason))].join(', ');
    out.push(row([j.label, f.leg, f.engine, f.version ?? f.runtime ?? '-', f.arms.join(', '), f.plan.dropped.map((d) => `${d.arm} = ${d.sameAs}`).join(', ') || '-', ev.length, ev.length - refused.length, `${refused.length}${why ? ` (${why})` : ''}`, fmt(f.wallSeconds)]));
  }
  return out.join('\n');
}

/** Replace every `<!-- gen:NAME -->...<!-- /gen:NAME -->` block of `text` with blocks[NAME]; returns the new text and the names not found. */
export function fillBlocks(text, blocks) {
  let out = text;
  const missing = [];
  for (const [name, body] of Object.entries(blocks)) {
    const re = new RegExp(`(<!-- gen:${name} -->)[\\s\\S]*?(<!-- /gen:${name} -->)`);
    if (!re.test(out)) { missing.push(name); continue; }
    out = out.replace(re, (_, a, b) => `${a}\n${body}\n${b}`);
  }
  return { text: out, missing };
}

/** All blocks of the note, by leg. */
export function blocksOf(summary, jobs, minutes) {
  const b = { runs: runTable(jobs) };
  for (const leg of ['mac', 'sim']) {
    const s = summary[leg];
    if (!s) continue;
    b[`${leg}-headline`] = headlineTable(s);
    b[`${leg}-verdict`] = verdictTable(s);
    b[`${leg}-class`] = classTable(s);
    b[`${leg}-kinds`] = kindTable(s);
    b[`${leg}-cadence`] = cadenceTable(s);
    b[`${leg}-cadence-verdict`] = cadenceVerdictTable(s);
  }
  b.minutes = minutesTable(minutes);
  return b;
}

/** Job minutes per leg from `minutes.json` ([{ run, leg, job, minutes }]). */
export function minutesTable(minutes) {
  if (!minutes?.length) return 'no job minutes were recorded';
  const out = [head(['run', 'leg', 'job', 'minutes'])];
  for (const m of minutes) out.push(row([m.run, m.leg, m.job, m.minutes]));
  for (const leg of ['mac', 'sim']) {
    const ms = minutes.filter((m) => m.leg === leg).map((m) => m.minutes);
    if (ms.length) out.push(row(['median', leg, '', med(ms)]));
  }
  return out.join('\n');
}

/** Read `<runs>`, write `<out>/summary.json` and `<out>/tables.md`, and fill the blocks of `<note>` when given. */
export async function reportMain({ runs, out, note, minutesFile, classify }) {
  const { files, skipped } = loadRuns(runs);
  const summary = {};
  for (const leg of ['mac', 'sim']) {
    const jobs = files.filter((f) => f.leg === leg);
    if (jobs.length) summary[leg] = legSummary(jobs, classify);
  }
  let minutes = null;
  try { minutes = JSON.parse(readFileSync(minutesFile, 'utf8')); } catch { /* none recorded */ }
  const blocks = blocksOf(summary, files, minutes);
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'summary.json'), `${JSON.stringify({ skipped, jobs: files.map((f) => f.label), summary }, null, 1)}\n`);
  writeFileSync(join(out, 'tables.md'), `${Object.entries(blocks).map(([n, t]) => `<!-- gen:${n} -->\n${t}\n<!-- /gen:${n} -->`).join('\n\n')}\n`);
  let missing = [];
  if (note) {
    const r = fillBlocks(readFileSync(note, 'utf8'), blocks);
    writeFileSync(note, r.text);
    missing = r.missing;
  }
  return { jobs: files.length, skipped, missing };
}
