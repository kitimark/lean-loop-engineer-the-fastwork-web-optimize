import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { withPhone } from './device.mjs';
import { loadFresh } from './page.mjs';
import { phoneCounts, phoneFrames } from './device-runs.mjs';
import * as P from './device-phone-arms.mjs';
import { appendOnly, faultOf, handReset, mayAttempt, recordFault } from './device-faults.mjs';

const slug = (id) => id.replace(/[^A-Za-z0-9.-]+/g, '_');
const pad = (i) => String(i).padStart(2, '0');
const rawName = (i, id, lane) => `${pad(i)}-${slug(id)}.${lane}.json`;

export const loadState = (dir) => {
  const f = join(dir, 'state.json');
  return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : { visits: [] };
};
/** Write the state; a visit's named faults only ever grow (Lean appendOnly), so a hand edit that dropped them is refused. */
export const saveState = (dir, st) => {
  mkdirSync(dir, { recursive: true });
  const f = join(dir, 'state.json');
  if (existsSync(f)) {
    for (const v of loadState(dir).visits) {
      const n = st.visits.find((x) => x.index === v.index);
      if (n && !appendOnly(v.faults ?? [], n.faults ?? [])) throw new Error(`visit ${v.index}: faults [${(n.faults ?? []).join(',')}] do not extend [${(v.faults ?? []).join(',')}]`);
    }
  }
  writeFileSync(f, JSON.stringify(st, null, 1) + '\n');
};
/** A hand reset (tab, phone, proxy): noted in the state, the visit's faults stay as they are (Lean handReset). */
export function markHandReset(dir, index, reason) {
  const st = loadState(dir);
  st.leadReset = [...(st.leadReset ?? []), { index, reason }];
  st.visits = st.visits.map((v) => (v.index === index ? { ...v, faults: handReset(v.faults ?? []) } : v));
  saveState(dir, st);
  return st;
}
export const faultsOfVisit = (v) => {
  if (!v) return [];
  const named = v.faults ?? [];
  return named.concat(Array(Math.max(0, (v.attempts ?? 0) - named.length)).fill('other'));
};
const putJson = (file, data) => writeFileSync(file, JSON.stringify(data) + '\n');

export function otherDeviceClis(self = process.pid) {
  const out = execFileSync('ps', ['-axo', 'pid=,command='], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  return out.split('\n').map((l) => l.trim()).filter((l) => /^\d+\s+\S*node\s.*device-cli\.mjs/.test(l)).map((l) => Number(l.split(/\s+/)[0])).filter((p) => p !== self && p !== process.ppid);
}

const TAB_RACE = /expected exactly one about:blank Safari tab/;
export async function whenTabBlank(fn, log, tries = 4, waitMs = 15000) {
  for (let i = 1; ; i++) {
    try { return await fn(); } catch (e) {
      if (!TAB_RACE.test(e.message) || i >= tries) throw e;
      log(`the tab is not blank yet (try ${i} of ${tries}); waiting ${waitMs / 1000} s`);
      await new Promise((r) => setTimeout(r, waitMs));
    }
  }
}

const batteryOf =(...files) => {
  const rs = files.flatMap((f) => f.readouts ?? []);
  const pick = (r) => ({ pct: r.batteryPct, temp: r.batteryVirtualTemp, skin: r.batterySkinTemp, charging: r.charging });
  return { first: pick(rs[0] ?? {}), last: pick(rs[rs.length - 1] ?? {}), maxTemp: Math.max(...rs.map((r) => r.batteryVirtualTemp ?? 0)) };
};

export function planText(distDir) {
  const pages = P.pagesOf(distDir);
  const lines = [];
  lines.push(`arms: ${P.ARMS.length} candidates, ${P.KEPT.length} kept after dropping any that loads the same page`);
  for (const d of P.dropped(P.ARMS)) lines.push(`dropped ${d.id}: it loads the same page as ${d.sameAs}`);
  for (const d of pages.dup) lines.push(`WARNING ${d.id} has the prerender of ${d.sameAs}`);
  P.SESSION.forEach((a, i) => lines.push(`visit ${i}: ${a.id}  [${a.target}] ${pages.rows.find((r) => r.id === a.id).search || '(no flags)'}`));
  P.blocks(P.PA.perBlock, P.SESSION.map((a) => a.id)).forEach((b, k) => lines.push(`block ${k + 1} (when each visit takes ${P.PA.visitMin} min): ${b.join(' | ')}`));
  lines.push(`about ${P.wallMin(P.SESSION.length)} min with a ${P.PA.coolMin} min cool between blocks; one visit = frames lane (${P.PA.reps} reps + warm-up) then counts lane (${P.PA.passes} passes + ${P.PA.warmup} warm-up)`);
  return lines.join('\n');
}

export async function runBlock({ site, dir, log, maxVisits = P.PA.perBlock, clock = 'pinned', settle = 6000, blocked = null }) {
  const others = otherDeviceClis();
  if (others.length > 0) throw new Error(`another device-cli.mjs is running (pid ${others.join(', ')}); one phone run at a time`);
  mkdirSync(dir, { recursive: true });
  const pages = P.pagesOf(site);
  const st = loadState(dir);
  const doneIdx = new Set(st.visits.filter((v) => v.status === 'done' || (v.status === 'lost' && !mayAttempt(faultsOfVisit(v)))).map((v) => v.index));
  const todo = P.SESSION.map((a, index) => ({ a, index })).filter((x) => !doneIdx.has(x.index));
  if (todo.length === 0) return { ran: [], stopped: null, remaining: 0 };
  if (st.lastEndMs) {
    let gap = (Date.now() - st.lastEndMs) / 1000;
    while (!P.coolOk(gap)) {
      const wait = P.PA.coolMin * 60 - gap;
      log(`cooling: ${Math.ceil(wait)} s left of ${P.PA.coolMin} min`);
      await new Promise((r) => setTimeout(r, Math.min(wait, 60) * 1000 + 50));
      gap = (Date.now() - st.lastEndMs) / 1000;
    }
  }
  const t0 = Date.now();
  let longest = P.PA.visitMin * 60;
  const ran = [];
  for (const { a, index } of todo) {
    if (ran.length >= maxVisits) break;
    const elapsed = (Date.now() - t0) / 1000;
    if (!P.mayStart(elapsed, longest)) { log(`block ends after ${ran.length} visits: ${Math.round(elapsed)} s used, a visit may take ${Math.round(longest)} s`); break; }
    const prior = st.visits.filter((v) => v.index === index);
    const attempts = prior.length > 0 ? prior[prior.length - 1].attempts : 0;
    const faults = faultsOfVisit(prior[prior.length - 1]);
    if (!mayAttempt(faults)) { st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'lost', attempts, faults, error: prior[prior.length - 1]?.error }]); saveState(dir, st); continue; }
    const row = pages.rows.find((r) => r.id === a.id);
    const start = Date.now();
    log(`visit ${index} (${a.id}), attempt ${attempts + 1}`);
    try {
      const r = await whenTabBlank(() => withPhone(async (ctx) => {
        const frames = await phoneFrames(ctx, { reps: P.PA.reps, speed: P.PA.speedPxPerS, settleMs: settle, clock, loadFresh, log: ctx.log });
        const counts = await phoneCounts(ctx, { passes: P.PA.passes, warmup: P.PA.warmup, step: P.PA.stepPx, framesPerStep: 2, settleMs: settle, clock, loadFresh, log: ctx.log });
        return { frames, counts };
      }, { site: a.target === 'rewrite' ? { dir: site, search: row.search } : null, log }), log);
      putJson(join(dir, rawName(index, a.id, 'counts')), { target: a.target, arm: a.id, ...r.counts });
      putJson(join(dir, rawName(index, a.id, 'frames')), { target: a.target, arm: a.id, ...r.frames });
      const durationS = Math.round((Date.now() - start) / 1000);
      longest = Math.max(longest, durationS);
      st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'done', attempts: attempts + 1, faults: prior[prior.length - 1]?.faults ?? [], durationS, endedMs: Date.now() }]);
      st.lastEndMs = Date.now();
      saveState(dir, st);
      const vals = P.visitValues(r.counts, r.frames);
      const bat = batteryOf(r.frames, r.counts);
      ran.push({ index, arm: a.id, durationS, vh: vals.vh, maxY: vals.maxY, hash: r.counts.fw?.configHash ?? null, hashOk: a.target === 'original' || r.counts.fw?.configHash === row.hash, battery: bat });
      console.log(JSON.stringify(ran[ran.length - 1]));
      await new Promise((r) => setTimeout(r, 10000));
    } catch (e) {
      st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'failed', attempts: attempts + 1, faults: recordFault(faults, faultOf(String(e.message))), error: String(e.message).slice(0, 300) }]);
      st.lastEndMs = Date.now();
      saveState(dir, st);
      const msg = `visit ${index} (${a.id}) attempt ${attempts + 1} failed: ${String(e.message).slice(0, 300)}`;
      if (blocked) { mkdirSync(resolve(blocked, '..'), { recursive: true }); writeFileSync(blocked, msg + '\n'); }
      return { ran, stopped: msg, remaining: todo.length - ran.length };
    }
  }
  st.lastEndMs = Date.now();
  saveState(dir, st);
  return { ran, stopped: null, remaining: todo.length - ran.length };
}

const LETTER = { beats: 'B', worse: 'W', same: '=', unresolved: '?' };
const fmt = (m, v) => (v === null || v === undefined ? '-' : P.familyOf(m) === 'frames' ? (v / 100).toFixed(2) : m === 'paintArea' ? (v / 1e6).toFixed(2) : String(v));
const med = (l) => { const s = [...l].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : null; };

export function tablesMarkdown(sum) {
  const out = [];
  out.push(`Cells: arm median (base median) verdict; B = beats the base beyond the base spread, W = worse, = same, ? unresolved. Counts are per ${P.PA.zonePx} px bins summed over a zone; frame metrics are moving frames over 34 / 50 ms per 100.`);
  for (const z of P.ZONES) {
    out.push('', `### ${z}`, '', `| arm | ${P.METRICS.join(' | ')} | counts | frames |`, `|---|${P.METRICS.map(() => '---').join('|')}|---|---|`);
    out.push(`| base (n=${sum.base.visits} visits) | ${P.METRICS.map((m) => { const c = sum.base.cells.find((x) => x.zone === z && x.metric === m); return `${fmt(m, c.median)} [${fmt(m, c.min)}-${fmt(m, c.max)}]`; }).join(' | ')} | | |`);
    for (const a of sum.arms) {
      const cs = P.METRICS.map((m) => {
        const c = a.cells.find((x) => x.zone === z && x.metric === m);
        const b = sum.base.cells.find((x) => x.zone === z && x.metric === m);
        return `${fmt(m, med(c.arm))} (${fmt(m, b.median)}) ${LETTER[c.verdict]}`;
      });
      out.push(`| ${a.id} | ${cs.join(' | ')} | ${a.labels.counts[z]} | ${a.labels.frames[z]} |`);
    }
  }
  out.push('', '### Layer census (layers, backing store MB) per scroll state', '', 'Cells: arm median (base median) verdict, as above; the base row shows median [min-max] over all base passes. States are the scripted stops (0, 1500, 3000, 4500 px and the end).');
  for (const [field, unit, f] of [['layers', 'layers', (v) => (v === null || v === undefined ? '-' : String(v))], ['bytes', 'backing MB', (v) => (v === null || v === undefined ? '-' : (v / 1048576).toFixed(1))]]) {
    const states = sum.base.census.map((c) => (typeof c.y === 'number' ? `y=${c.y}` : 'end'));
    out.push('', `#### ${unit}`, '', `| arm | ${states.join(' | ')} |`, `|---|${states.map(() => '---').join('|')}|`);
    out.push(`| base (n=${sum.base.visits} visits) | ${sum.base.census.map((c) => `${f(c[field].median)} [${f(c[field].min)}-${f(c[field].max)}]`).join(' | ')} |`);
    for (const a of sum.arms) out.push(`| ${a.id} | ${a.census.map((c, k) => `${f(med(c[field].arm))} (${f(sum.base.census[k][field].median)}) ${LETTER[c[field].verdict]}`).join(' | ')} |`);
  }
  out.push('', '### Per arm (all zones)', '', '| arm | visits | counts | frames |', '|---|---|---|---|');
  for (const a of sum.arms) out.push(`| ${a.id} | ${a.visits} | ${a.labels.counts.all} | ${a.labels.frames.all} |`);
  return out.join('\n') + '\n';
}

export function reduceDir({ dir, out }) {
  const st = loadState(dir);
  const done = st.visits.filter((v) => v.status === 'done').sort((a, b) => a.index - b.index);
  const lost = st.visits.filter((v) => v.status === 'lost' || v.status === 'failed').map((v) => ({ index: v.index, arm: v.arm, status: v.status, attempts: v.attempts, faults: faultsOfVisit(v), retryable: v.status === 'lost' && mayAttempt(faultsOfVisit(v)) }));
  const visitsDone = [], meta = [];
  let device = null;
  for (const v of done) {
    const counts = JSON.parse(readFileSync(join(dir, rawName(v.index, v.arm, 'counts')), 'utf8'));
    const frames = JSON.parse(readFileSync(join(dir, rawName(v.index, v.arm, 'frames')), 'utf8'));
    device = device ?? counts.device;
    const values = P.visitValues(counts, frames);
    visitsDone.push({ arm: v.arm, values });
    meta.push({ index: v.index, arm: v.arm, durationS: v.durationS, vh: values.vh, maxY: values.maxY, configHash: counts.fw?.configHash ?? null, battery: batteryOf(frames, counts) });
  }
  const sum = P.reduceSession(visitsDone);
  const summary = {
    schema: 'fw.phone.end-counts/1', device, consts: P.PA, order: P.SESSION.map((a) => a.id), visits: meta, notRun: lost,
    anomalies: P.anomalies(visitsDone), base: sum.base, arms: sum.arms,
  };
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'summary.json'), JSON.stringify(summary, null, 1) + '\n');
  writeFileSync(join(out, 'tables.md'), tablesMarkdown(sum));
  return summary;
}
