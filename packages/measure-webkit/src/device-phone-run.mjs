// I/O glue of the phone end-of-page session (task phone-end-counts): runs Lean's visit list on the real iPhone in blocks, keeps the
// raw files and a state file under a local directory, and packages the reduced tables. Every decision (the visits, when a visit may
// start, the cool gap, the verdicts) is device-phone-arms.mjs's, which is checked against lean/Fw/Device/PhoneArms.lean's golden.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { withPhone } from './device.mjs';
import { loadFresh } from './page.mjs';
import { phoneCounts, phoneFrames } from './device-runs.mjs';
import * as P from './device-phone-arms.mjs';

const slug = (id) => id.replace(/[^A-Za-z0-9.-]+/g, '_');
const pad = (i) => String(i).padStart(2, '0');
const rawName = (i, id, lane) => `${pad(i)}-${slug(id)}.${lane}.json`;

const loadState = (dir) => {
  const f = join(dir, 'state.json');
  return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : { visits: [] };
};
const saveState = (dir, st) => { mkdirSync(dir, { recursive: true }); writeFileSync(join(dir, 'state.json'), JSON.stringify(st, null, 1) + '\n'); };
const putJson = (file, data) => writeFileSync(file, JSON.stringify(data) + '\n');

/** Other device-cli processes on this Mac (a second one would compete for the phone and the proxy ports). */
export function otherDeviceClis(self = process.pid) {
  const out = execFileSync('ps', ['-axo', 'pid=,command='], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  return out.split('\n').map((l) => l.trim()).filter((l) => /^\d+\s+\S*node\s.*device-cli\.mjs/.test(l)).map((l) => Number(l.split(/\s+/)[0])).filter((p) => p !== self && p !== process.ppid);
}

const TAB_RACE = /expected exactly one about:blank Safari tab/;
/** The phone's tab returns to about:blank a moment after the last session ends; a start in that moment waits and tries again (no visit is lost, nothing was loaded). */
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

/** The plan: the visit list, the blocks and the page of each arm. */
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

/**
 * Run the next block: the visits not yet done, in Lean's order, while Lean's `mayStart` allows one more, at most `maxVisits`.
 * Waits out the cool gap since the last block first (Lean's `coolOk`). Returns {ran, stopped}; `stopped` names a failure.
 */
export async function runBlock({ site, dir, log, maxVisits = P.PA.perBlock, clock = 'pinned', settle = 6000, blocked = null }) {
  const others = otherDeviceClis();
  if (others.length > 0) throw new Error(`another device-cli.mjs is running (pid ${others.join(', ')}); one phone run at a time`);
  mkdirSync(dir, { recursive: true });
  const pages = P.pagesOf(site);
  const st = loadState(dir);
  const doneIdx = new Set(st.visits.filter((v) => v.status === 'done' || v.status === 'lost').map((v) => v.index));
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
    if (attempts >= 2) { st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'lost', attempts }]); saveState(dir, st); continue; }
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
      st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'done', attempts: attempts + 1, durationS, endedMs: Date.now() }]);
      st.lastEndMs = Date.now();
      saveState(dir, st);
      const vals = P.visitValues(r.counts, r.frames);
      const bat = batteryOf(r.frames, r.counts);
      ran.push({ index, arm: a.id, durationS, vh: vals.vh, maxY: vals.maxY, hash: r.counts.fw?.configHash ?? null, hashOk: a.target === 'original' || r.counts.fw?.configHash === row.hash, battery: bat });
      console.log(JSON.stringify(ran[ran.length - 1]));
      await new Promise((r) => setTimeout(r, 10000));
    } catch (e) {
      st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'failed', attempts: attempts + 1, error: String(e.message).slice(0, 300) }]);
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
const fmt = (m, v) => (v === null || v === undefined ? '-' : P.familyOf(m) === 'frames' ? (v / 100).toFixed(2) : String(v));
const med = (l) => { const s = [...l].sort((a, b) => a - b); return s.length ? s[Math.floor(s.length / 2)] : null; };

/** Markdown tables of a reduced session: per zone, arms x metrics, each cell "arm median (base median) verdict". */
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
  out.push('', '### Per arm (all zones)', '', '| arm | visits | counts | frames |', '|---|---|---|---|');
  for (const a of sum.arms) out.push(`| ${a.id} | ${a.visits} | ${a.labels.counts.all} | ${a.labels.frames.all} |`);
  return out.join('\n') + '\n';
}

/** Reduce the raw files of a session directory to summary.json and tables.md in `out` (no timestamps, no device id, no address). */
export function reduceDir({ dir, out }) {
  const st = loadState(dir);
  const done = st.visits.filter((v) => v.status === 'done').sort((a, b) => a.index - b.index);
  const lost = st.visits.filter((v) => v.status === 'lost' || v.status === 'failed').map((v) => ({ index: v.index, arm: v.arm, status: v.status, attempts: v.attempts }));
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
