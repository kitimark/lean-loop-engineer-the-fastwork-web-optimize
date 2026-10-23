import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { KINDS, ZONES, medianNat, zoneVerdict, profileFromRaw } from './reduce.mjs';
import { readRaws } from './raw.mjs';
import { acrossDecisive, agreeNeeded, decisive, hitchVerdict, armRate, repOf, quantile, enoughN, countsOf, sumCounts } from '../../../gate-breakpoints/src/smooth/reduce.mjs';

export const PAIRS = [['orig', 'base'], ['base', 'look'], ['orig', 'look'], ['base', 'v2'], ['base', 'bound']];
export const KEY_KINDS = ['RecalculateStyles', 'Layout', 'Paint', 'Composite', 'FunctionCall', 'FireAnimationFrame'];
const ALL_ARMS = ['orig', 'base', 'aa', 'look', 'v2', 'bound'];

const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const med = (l) => (l.length ? medianNat(l) : null);

export function rereduce(file, windows) {
  const raw = new Map(windows.map((w) => [`${w.arm}|${w.window}|${w.rep}`, w.raw]));
  for (const r of file.rows) {
    const w = raw.get(`${r.arm}|${r.window}|${r.rep}`);
    if (r.mode !== 'events' || !w || r.timeline === false) continue;
    const pw = profileFromRaw(w);
    Object.assign(r, { ok: pw.ok, reason: pw.reason ?? null, off: pw.off ?? null, offA: pw.offA ?? null, offB: pw.offB ?? null, profiles: pw.profiles });
  }
}

export function loadRuns(dir) {
  const files = [];
  const skipped = [];
  for (const id of readdirSync(dir).filter((n) => /^\d+$/.test(n)).sort()) {
    for (const f of walk(join(dir, id)).filter((p) => /\/(mac|sim)\.json$/.test(p))) {
      const file = JSON.parse(readFileSync(f, 'utf8'));
      const rawFile = f.replace(/\.json$/, '.raw.json.gz');
      if (existsSync(rawFile)) rereduce(file, readRaws(rawFile).windows);
      const label = `${id}:${f.slice(join(dir, id).length + 1).split('/')[0]}`;
      if (file.refused || !file.rows?.length) { skipped.push({ run: label, why: file.refused ? 'refused' : 'empty' }); continue; }
      files.push({ label, leg: file.leg, file });
    }
  }
  return { files, skipped };
}

export function zoneReps(file, arm, zone) {
  return file.rows
    .filter((r) => r.arm === arm && r.mode === 'events' && r.ok && r.profiles?.[zone]?.frames > 0)
    .sort((a, b) => a.rep - b.rep)
    .map((r) => ({ rep: r.rep, window: r.window, ...r.profiles[zone] }));
}

const cellOfKind = (p, k) => p.cells.find((c) => c[0] === k) ?? [k, 0, 0];

function cellOf(ps) {
  const kinds = Object.fromEntries(KINDS.map((k) => [k, { n: med(ps.map((p) => cellOfKind(p, k)[1])), dur: med(ps.map((p) => cellOfKind(p, k)[2])) }]));
  return { reps: ps.length, frames: med(ps.map((p) => p.frames)), perFrame: med(ps.map((p) => p.perFrame)), perFrameAll: ps.map((p) => p.perFrame), work: med(ps.map((p) => p.work)), span: med(ps.map((p) => p.span)), share: med(ps.map((p) => (p.span ? Math.floor((1000 * p.work) / p.span) : 0))), kinds };
}

export function jobCell(file, arm, zone) {
  return cellOf(zoneReps(file, arm, zone));
}

export function armWindows(jobs, arm, zone) {
  return jobs.flatMap((j) => zoneReps(j.file, arm, zone).map((p) => ({ job: j.label, ...p })));
}

export function poolCell(jobs, arm, zone) {
  const ps = armWindows(jobs, arm, zone);
  return { ...cellOf(ps), split: jobs.map((j) => ps.filter((p) => p.job === j.label).length) };
}

export function jobVerdicts(file, zone) {
  const pf = (arm) => zoneReps(file, arm, zone).map((p) => p.perFrame);
  return Object.fromEntries(PAIRS.filter(([a, b]) => [a, b].every((x) => file.arms.includes(x))).map(([a, b]) => [`${a}|${b}`, zoneVerdict(pf(a), pf(b), pf('base'), pf('aa'))]));
}

export function acrossJobs(perJob) {
  const pairs = [...new Set(perJob.flatMap((v) => Object.keys(v)))];
  return Object.fromEntries(pairs.map((p) => {
    const vs = perJob.map((v) => v[p]).filter((x) => x !== undefined);
    return [p, { jobs: vs.length, first: vs.filter((x) => x === 'first').length, second: vs.filter((x) => x === 'second').length, same: vs.filter((x) => x === 'same').length, insufficient: vs.filter((x) => x === 'insufficient').length, need: agreeNeeded(decisive(vs)), verdict: acrossDecisive(vs) }];
  }));
}

// an end window pushed by real touches is its own window: it is not the same measurement as the synthetic wheel
const winOf = (r) => (r.window === 'end' && r.push === 'touch' ? 'end touch' : r.window);
const cadRows = (file, arm, win, mode) => file.rows.filter((r) => r.arm === arm && winOf(r) === win && r.mode === mode && r.ivs).sort((a, b) => a.rep - b.rep);

const countsOfRows = (rs) => (rs.length && rs.every((r) => r.th) ? sumCounts(rs.map((r) => countsOf(r.ivs, r.th))) : null);

export function jobCadence(file, win, mode) {
  const hs = (arm) => cadRows(file, arm, win, mode).map((r) => r.hitches);
  const arms = Object.fromEntries(file.arms.map((a) => {
    const rs = cadRows(file, a, win, mode);
    const ivs = rs.flatMap((r) => r.ivs);
    const reps = rs.map((r) => repOf(r.ivs));
    return [a, { reps: rs.length, hitches: hs(a), counts: countsOfRows(rs), rate: armRate(reps), p50: quantile(ivs, 50), p95: quantile(ivs, 95), max: ivs.length ? Math.max(...ivs) : null }];
  }));
  const verdicts = Object.fromEntries(PAIRS.filter(([a, b]) => [a, b].every((x) => file.arms.includes(x))).map(([a, b]) => [`${a}|${b}`, hitchVerdict(hs(a), hs(b), hs('base'), hs('aa'))]));
  return { arms, verdicts };
}

export function poolCadence(jobs, arms, win, mode) {
  return Object.fromEntries(arms.map((a) => {
    const per = jobs.map((j) => cadRows(j.file, a, win, mode));
    const rs = per.flat();
    const ivs = rs.flatMap((r) => r.ivs);
    return [a, { reps: rs.length, split: per.map((r) => r.length), hitches: rs.map((r) => r.hitches), counts: countsOfRows(rs), p50: quantile(ivs, 50), p95: quantile(ivs, 95), max: ivs.length ? Math.max(...ivs) : null }];
  }));
}

export function legSummary(jobs, classify) {
  const arms = ALL_ARMS.filter((a) => jobs.some((j) => j.file.arms.includes(a)));
  const zones = {};
  for (const z of ZONES) {
    const cells = Object.fromEntries(arms.map((a) => [a, jobs.map((j) => ({ job: j.label, ...jobCell(j.file, a, z) }))]));
    const pool = Object.fromEntries(arms.map((a) => [a, poolCell(jobs, a, z)]));
    const perJobV = jobs.map((j) => jobVerdicts(j.file, z));
    const classes = {};
    for (const a of arms) {
      const runs = cells[a].filter((c) => c.reps > 0).map((c) => [{ counts: Object.fromEntries(KINDS.map((k) => [k, c.kinds[k].n ?? 0])) }]);
      classes[a] = runs.length >= 3 ? classify(runs, 4, 24) : null;
    }
    zones[z] = { pool, cells, verdicts: acrossJobs(perJobV), perJob: perJobV.map((v, i) => ({ job: jobs[i].label, ...v })), classes };
  }
  const cadence = {};
  for (const win of ['hero', 'end', 'end touch']) for (const mode of ['events', 'cadence']) {
    const per = jobs.map((j) => ({ job: j.label, ...jobCadence(j.file, win, mode) })).filter((c) => Object.values(c.arms).some((a) => a.reps > 0));
    if (per.length) cadence[`${win}|${mode}`] = { jobs: per, pool: poolCadence(jobs, arms, win, mode), verdicts: acrossJobs(per.map((c) => c.verdicts)) };
  }
  return { arms, zones, cadence };
}


const ms2 = (h) => (h == null ? '-' : (h / 100).toFixed(2));
const fmt = (x) => (x == null ? '-' : String(x));
const row = (cells) => `| ${cells.join(' | ')} |`;
const head = (cols) => `${row(cols)}\n${row(cols.map(() => '---'))}`;
const nOf = (c) => `${c.reps} (${c.split.join('+')})`;
const sufficient = (c) => enoughN({ length: c.reps });
const insufficient = (c) => `insufficient (n=${c.reps})`;
const cellOr = (c, f, show = fmt) => (sufficient(c) ? show(f(c)) : insufficient(c));
const range = (c) => (c.perFrameAll.length ? `${Math.min(...c.perFrameAll)}-${Math.max(...c.perFrameAll)}` : '-');

export function headlineTable(leg) {
  const out = [];
  for (const z of ZONES) {
    out.push(`**${z}**\n`);
    out.push(head(['arm', 'n windows (per job)', 'frames', 'render work ms / window (median)', 'render work us/frame (median, range)', ...KEY_KINDS.map((k) => `${k} n`)]));
    for (const a of leg.arms) {
      const c = leg.zones[z].pool[a];
      out.push(row([a, nOf(c), cellOr(c, (x) => x.frames), cellOr(c, (x) => x.work, ms2), cellOr(c, (x) => `${fmt(x.perFrame)} (${range(x)})`, String), ...KEY_KINDS.map((k) => cellOr(c, (x) => x.kinds[k].n))]));
    }
    out.push('');
  }
  return out.join('\n');
}

export function kindTable(leg) {
  const out = [];
  for (const z of ZONES) {
    out.push(`**${z}** (median count / median covered ms per window over all kept windows of all jobs; covered = union of the kind's intervals in the window, never above the window span; Composite is a count)\n`);
    out.push(head(['kind', ...leg.arms]));
    out.push(row(['n windows (per job)', ...leg.arms.map((a) => nOf(leg.zones[z].pool[a]))]));
    for (const k of KINDS) out.push(row([k, ...leg.arms.map((a) => cellOr(leg.zones[z].pool[a], (x) => `${fmt(x.kinds[k].n)} / ${k === 'Composite' ? 'count only' : ms2(x.kinds[k].dur)}`, String))]));
    out.push('');
  }
  return out.join('\n');
}

const ratio = (a, b) => (a == null || b == null || b === 0 ? '-' : (a / b).toFixed(1));

export function ratioTable(leg) {
  const out = [];
  for (const z of ZONES) {
    const c = (a) => leg.zones[z].pool[a];
    if (!leg.arms.includes('base') || !(leg.arms.includes('orig') || leg.arms.includes('aa'))) continue;
    const bound = leg.arms.includes('bound');
    out.push(`**${z}**\n`);
    out.push(head(['metric', ...leg.arms, 'orig / base', 'base / aa', ...(bound ? ['bound / base'] : [])]));
    out.push(row(['n windows (per job)', ...leg.arms.map((a) => nOf(c(a))), '', '', ...(bound ? [''] : [])]));
    const metrics = [
      ['frames in zone', (x) => x.frames, fmt],
      ['window span ms', (x) => x.span, ms2],
      ['render work ms / window', (x) => x.work, ms2],
      ['render work share of the window span %', (x) => x.share, (v) => (v == null ? '-' : (v / 10).toFixed(1))],
      ['render work us / frame', (x) => x.perFrame, fmt],
      ...['RecalculateStyles', 'Layout', 'Paint'].flatMap((k) => [[`${k} n`, (x) => x.kinds[k].n, fmt], [`${k} ms`, (x) => x.kinds[k].dur, ms2]]),
      ['Composite n', (x) => x.kinds.Composite.n, fmt],
      ...['FunctionCall', 'FireAnimationFrame'].flatMap((k) => [[`${k} n`, (x) => x.kinds[k].n, fmt], [`${k} ms`, (x) => x.kinds[k].dur, ms2]]),
    ];
    for (const [name, f, show] of metrics) {
      const v = Object.fromEntries(leg.arms.map((a) => [a, sufficient(c(a)) ? f(c(a)) : null]));
      out.push(row([name, ...leg.arms.map((a) => cellOr(c(a), f, show)), ratio(v.orig, v.base), ratio(v.base, v.aa), ...(bound ? [ratio(v.bound, v.base)] : [])]));
    }
    out.push('');
  }
  return out.join('\n');
}

export function verdictTable(leg) {
  const out = [head(['zone', 'pair (first, second)', 'jobs', 'first', 'second', 'same', 'insufficient', 'verdict over jobs'])];
  for (const z of ZONES) for (const [p, v] of Object.entries(leg.zones[z].verdicts)) out.push(row([z, p.replace('|', ', '), v.jobs, v.first, v.second, v.same, v.insufficient, v.verdict]));
  return out.join('\n');
}

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

const COUNT_COLS = ['over25', 'over34', 'over50', 'skips', 'frames'];

export function cadenceTable(leg) {
  const out = [head(['window', 'timeline', 'arm', 'reps n (per job)', 'hitches per rep (median)', 'over 25 ms', 'over 34 ms', 'over 50 ms', 'skipped slots', 'frames', 'p50 ms', 'p95 ms', 'max ms'])];
  for (const [key, c] of Object.entries(leg.cadence)) {
    const [win, mode] = key.split('|');
    for (const a of leg.arms) {
      const p = c.pool[a];
      if (!p || !p.reps) continue;
      out.push(row([win, mode === 'events' ? 'on' : 'off', a, nOf(p), cellOr(p, (x) => med(x.hitches)), ...COUNT_COLS.map((f) => fmt(p.counts?.[f])), cellOr(p, (x) => x.p50, (v) => (v / 10).toFixed(1)), cellOr(p, (x) => x.p95, (v) => (v / 10).toFixed(1)), cellOr(p, (x) => x.max, (v) => (v / 10).toFixed(1))]));
    }
  }
  return out.join('\n');
}

export function cadenceVerdictTable(leg) {
  const out = [head(['window', 'timeline', 'pair (first, second)', 'jobs', 'first', 'second', 'same', 'insufficient', 'verdict over jobs'])];
  for (const [key, c] of Object.entries(leg.cadence)) {
    const [win, mode] = key.split('|');
    for (const [p, v] of Object.entries(c.verdicts)) out.push(row([win, mode === 'events' ? 'on' : 'off', p.replace('|', ', '), v.jobs, v.first, v.second, v.same, v.insufficient, v.verdict]));
  }
  return out.join('\n');
}

const shortWhy = (w) => String(w ?? '').split('; driver log tail')[0];
const pushOf = (f) => {
  if (f.leg === 'mac') return 'wheel';
  const ends = f.rows.filter((r) => r.mode === 'events' && r.window === 'end');
  const touched = ends.filter((r) => r.push === 'touch').length;
  if (touched === 0 && !f.push) return 'synthetic wheel';
  const why = touched < ends.length && f.push?.why ? `; then synthetic wheel: ${shortWhy(f.push.why)}` : '';
  return `touch ${touched} of ${ends.length} end windows${why}`;
};

export function runTable(jobs) {
  const out = [head(['job', 'leg', 'engine', 'version / runtime', 'arms', 'dropped by flags', 'windows', 'kept', 'refused (reason)', 'end push', 'wall s'])];
  for (const j of jobs) {
    const f = j.file;
    const ev = f.rows.filter((r) => r.mode === 'events');
    const refused = ev.filter((r) => !r.ok);
    const why = [...new Set(refused.map((r) => r.reason))].join(', ');
    out.push(row([j.label, f.leg, f.engine, f.version ?? f.runtime ?? '-', f.arms.join(', '), f.plan.dropped.map((d) => `${d.arm} = ${d.sameAs}`).join(', ') || '-', ev.length, ev.length - refused.length, `${refused.length}${why ? ` (${why})` : ''}`, pushOf(f), fmt(f.wallSeconds)]));
  }
  return out.join('\n');
}

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

export function blocksOf(summary, jobs, minutes) {
  const b = { runs: runTable(jobs) };
  for (const leg of ['mac', 'sim']) {
    const s = summary[leg];
    if (!s) continue;
    b[`${leg}-headline`] = headlineTable(s);
    b[`${leg}-ratios`] = ratioTable(s);
    b[`${leg}-verdict`] = verdictTable(s);
    b[`${leg}-class`] = classTable(s);
    b[`${leg}-kinds`] = kindTable(s);
    b[`${leg}-cadence`] = cadenceTable(s);
    b[`${leg}-cadence-verdict`] = cadenceVerdictTable(s);
  }
  b.minutes = minutesTable(minutes);
  return b;
}

export function minutesOf(byRun) {
  const out = [];
  for (const run of Object.keys(byRun).sort()) {
    for (const j of byRun[run].jobs ?? []) {
      const leg = /^webkit mac/.test(j.name) ? 'mac' : /^webkit sim/.test(j.name) ? 'sim' : null;
      if (!leg || !j.startedAt || !j.completedAt) continue;
      const ms = Date.parse(j.completedAt) - Date.parse(j.startedAt);
      out.push({ run, leg, job: j.name, conclusion: j.conclusion, minutes: Math.round(ms / 6000) / 10, billed: Math.ceil(ms / 60000) });
    }
  }
  return out;
}

const medianF = (l) => { const t = [...l].sort((x, y) => x - y); const n = t.length; return n % 2 ? t[(n - 1) / 2] : Math.round(((t[n / 2 - 1] + t[n / 2]) / 2) * 10) / 10; };

export function minutesTable(minutes) {
  if (!minutes?.length) return 'no job minutes were recorded';
  const out = [head(['run', 'leg', 'job', 'result', 'wall min', 'billed min'])];
  for (const m of minutes) out.push(row([m.run, m.leg, m.job, m.conclusion ?? 'success', m.minutes, m.billed]));
  for (const leg of ['mac', 'sim']) {
    const ok = minutes.filter((m) => m.leg === leg && (m.conclusion ?? 'success') === 'success').map((m) => m.minutes);
    if (ok.length) out.push(row(['median of successes', leg, '', `n=${ok.length}`, medianF(ok), '']), row(['longest success', leg, '', '', Math.max(...ok), '']));
    const all = minutes.filter((m) => m.leg === leg);
    if (all.length) out.push(row(['all jobs billed', leg, '', `n=${all.length}`, '', all.reduce((acc, m) => acc + m.billed, 0)]));
  }
  return out.join('\n');
}

export async function reportMain({ runs, out, note, jobsDir, classify }) {
  const { files, skipped } = loadRuns(runs);
  const summary = {};
  for (const leg of ['mac', 'sim']) {
    const jobs = files.filter((f) => f.leg === leg);
    if (jobs.length) summary[leg] = legSummary(jobs, classify);
  }
  let minutes = null;
  try {
    const byRun = {};
    for (const f of readdirSync(jobsDir).filter((n) => /^\d+\.json$/.test(n))) byRun[f.replace('.json', '')] = JSON.parse(readFileSync(join(jobsDir, f), 'utf8'));
    minutes = minutesOf(byRun);
  } catch { }
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
