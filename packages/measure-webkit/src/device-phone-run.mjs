import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { listPhone, readout, withPhone } from './device.mjs';
import { loadFresh } from './page.mjs';
import { phoneCounts, phoneFrames } from './device-runs.mjs';
import * as P from './device-phone-arms.mjs';
import { USB_WAIT_S, classify, handReset, keepOk, mayAttempt, recordFault, resetPlan, usbWait, writeOk } from './device-faults.mjs';
import { PAUSE_MAX_S, POLL_S, VERDICT_TEXT, pauseOver, preflight, readThermal, resume } from './device-thermal.mjs';
import { assertNoForeignProxy, usbListed, usbReading } from './device-phone-env.mjs';

const slug = (id) => id.replace(/[^A-Za-z0-9.-]+/g, '_');
const pad = (i) => String(i).padStart(2, '0');
const rawName = (i, id, lane) => `${pad(i)}-${slug(id)}.${lane}.json`;

export const loadState = (dir) => {
  const f = join(dir, 'state.json');
  return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : { visits: [] };
};
export const saveState = (dir, st) => {
  mkdirSync(dir, { recursive: true });
  const f = join(dir, 'state.json');
  if (existsSync(f)) {
    const recs = (vs) => vs.map((v) => ({ index: v.index, faults: faultsOfVisit(v) }));
    const old = recs(loadState(dir).visits), next = recs(st.visits);
    if (!writeOk(old, next)) {
      const bad = old.find((v) => !keepOk(next, v));
      const n = next.find((x) => x.index === bad.index);
      throw new Error(n ? `visit ${bad.index}: faults [${n.faults.join(',')}] do not extend [${bad.faults.join(',')}]` : `visit ${bad.index}: removed with faults [${bad.faults.join(',')}]`);
    }
  }
  writeFileSync(f, JSON.stringify(st, null, 1) + '\n');
};
export function markHandReset(dir, index, reason) {
  const st = loadState(dir);
  st.leadReset = [...(st.leadReset ?? []), { index, reason }];
  st.visits = st.visits.map((v) => (v.index === index ? { ...v, faults: handReset(v.faults ?? []) } : v));
  saveState(dir, st);
  return st;
}
export function handResetCommand(dir, idx, reason) {
  const recs = loadState(dir).visits.map((v) => ({ index: v.index, faults: faultsOfVisit(v) }));
  const plan = resetPlan(recs, String(idx), String(reason ?? ''), loadState(dir).session?.length ?? P.SESSION.length);
  if (plan.plan !== 'note') throw new Error(`hand reset refused: ${plan.plan} (index "${idx}", visits in the plan ${loadState(dir).session?.length ?? P.SESSION.length}, reason ${reason ? 'given' : 'missing'})`);
  return markHandReset(dir, plan.index, plan.reason);
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
  return { first: pick(rs[0] ?? {}), last: pick(rs[rs.length - 1] ?? {}), maxTemp: Math.max(...rs.map((r) => r.batteryVirtualTemp ?? 0)), thermal: rs.map((r) => r.thermalState ?? null) };
};

export function planText(distDir, session = P.SESSION) {
  const pages = P.pagesOf(distDir);
  const lines = [];
  lines.push(`arms: ${P.ARMS.length} candidates, ${P.KEPT.length} kept after dropping any that loads the same page`);
  for (const d of P.dropped(P.ARMS)) lines.push(`dropped ${d.id}: it loads the same page as ${d.sameAs}`);
  for (const d of pages.dup) lines.push(`WARNING ${d.id} has the prerender of ${d.sameAs}`);
  session.forEach((a, i) => lines.push(`visit ${i}: ${a.id}  [${a.target}] ${pages.rows.find((r) => r.id === a.id).search || '(no flags)'}`));
  P.blocks(P.PA.perBlock, session.map((a) => a.id)).forEach((b, k) => lines.push(`block ${k + 1} (when each visit takes ${P.PA.visitMin} min): ${b.join(' | ')}`));
  lines.push(`about ${P.wallMin(session.length)} min with a ${P.PA.coolMin} min cool between blocks; one visit = frames lane (${P.PA.reps} reps + warm-up) then counts lane (${P.PA.passes} passes + ${P.PA.warmup} warm-up)`);
  return lines.join('\n');
}

const realDeps = () => {
  let udid = null;
  const id = () => (udid ??= listPhone().udid);
  return {
    visit: ({ a, row, site, settle, clock, log }) => whenTabBlank(() => withPhone(async (ctx) => {
      const frames = await phoneFrames(ctx, { reps: P.PA.reps, speed: P.PA.speedPxPerS, settleMs: settle, clock, loadFresh, log: ctx.log });
      const counts = await phoneCounts(ctx, { passes: P.PA.passes, warmup: P.PA.warmup, step: P.PA.stepPx, framesPerStep: 2, settleMs: settle, clock, loadFresh, log: ctx.log });
      return { frames, counts };
    }, { site: a.target === 'rewrite' ? { dir: site, search: row.search } : null, log }), log),
    others: otherDeviceClis, now: () => Date.now(), sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    proxies: () => assertNoForeignProxy(id()),
    sense: () => {
      const t = readThermal(id());
      const b = readout(id(), { thermal: () => t });
      return { state: t.state, lock: t.lock, error: t.error, tempC: b.batteryVirtualTemp };
    },
    usbNow: (sinceMs) => usbReading(id(), sinceMs),
    usbListed: () => usbListed(id()),
  };
};

export async function runBlock({ site, dir, log, maxVisits = P.PA.perBlock, clock = 'pinned', settle = 6000, blocked = null, session = P.SESSION, deps = realDeps() }) {
  const others = deps.others();
  if (others.length > 0) throw new Error(`another device-cli.mjs is running (pid ${others.join(', ')}); one phone run at a time`);
  mkdirSync(dir, { recursive: true });
  const writeBlocked = (msg) => { if (blocked) { mkdirSync(resolve(blocked, '..'), { recursive: true }); writeFileSync(blocked, msg + '\n'); } };
  const pages = P.pagesOf(site);
  const st = loadState(dir);
  const ids = session.map((a) => a.id);
  if (st.session && JSON.stringify(st.session) !== JSON.stringify(ids)) throw new Error(`this raw dir holds the session plan [${st.session.join(' | ')}], not [${ids.join(' | ')}]`);
  st.session = ids;
  const doneIdx = new Set(st.visits.filter((v) => v.status === 'done' || (v.status === 'lost' && !mayAttempt(faultsOfVisit(v)))).map((v) => v.index));
  const todo = session.map((a, index) => ({ a, index })).filter((x) => !doneIdx.has(x.index));
  if (todo.length === 0) return { ran: [], stopped: null, remaining: 0 };
  try { deps.proxies(); } catch (e) { writeBlocked(e.message); throw e; }
  if (st.lastEndMs) {
    let gap = (deps.now() - st.lastEndMs) / 1000;
    while (!P.coolOk(gap)) {
      const wait = P.PA.coolMin * 60 - gap;
      log(`cooling: ${Math.ceil(wait)} s left of ${P.PA.coolMin} min`);
      await deps.sleep(Math.min(wait, 60) * 1000 + 50);
      gap = (deps.now() - st.lastEndMs) / 1000;
    }
  }
  const nowS = () => deps.now() / 1000;
  let last = null;
  const sense = (phase, index) => {
    const s = deps.sense();
    if (st.firstTemp === undefined && typeof s.tempC === 'number') st.firstTemp = s.tempC;
    const verdict = preflight(s.lock, s.state, s.tempC, st.firstTemp);
    st.thermal = [...(st.thermal ?? []), { at: new Date(deps.now()).toISOString(), phase, index, state: s.state, tempC: s.tempC ?? null, lock: s.lock, verdict, ...(s.error ? { error: s.error } : {}) }];
    last = { s, verdict, phase };
    return last;
  };
  const ran = [];
  const stop = (msg) => { st.lastEndMs = deps.now(); saveState(dir, st); writeBlocked(msg); return { ran, stopped: msg, remaining: todo.length - ran.length }; };

  let pausedS = st.pausedAtS ?? null;
  const readings = [];
  for (;;) {
    const { s, verdict } = sense('block-start', null);
    if (verdict === 'locked') return stop(`the phone is locked: ${VERDICT_TEXT.locked}`);
    readings.push({ atS: nowS(), verdict });
    if (verdict !== 'go' && pausedS === null) pausedS = nowS();
    if (pausedS === null) break;
    if (resume(nowS(), pausedS, readings)) { st.pausedAtS = null; break; }
    if (pauseOver(pausedS, nowS())) return stop(`paused over ${PAUSE_MAX_S} s: ${VERDICT_TEXT[verdict]}${s.error ? ` (${s.error})` : ''}`);
    st.pausedAtS = pausedS;
    saveState(dir, st);
    log(`paused (${verdict}): ${VERDICT_TEXT[verdict]}; next reading in ${POLL_S} s`);
    await deps.sleep(POLL_S * 1000);
  }
  saveState(dir, st);

  const t0 = deps.now();
  let longest = P.PA.visitMin * 60;
  let ready = true;
  let over = false;
  for (const { a, index } of todo) {
    if (over || ran.length >= maxVisits) break;
    for (;;) {
      const elapsed = (deps.now() - t0) / 1000;
      if (!P.mayStart(elapsed, longest)) { log(`block ends after ${ran.length} visits: ${Math.round(elapsed)} s used, a visit may take ${Math.round(longest)} s`); over = true; break; }
      if (!ready) {
        const { verdict } = sense('visit-start', index);
        if (verdict === 'locked') return stop(`the phone is locked: ${VERDICT_TEXT.locked}`);
        if (verdict !== 'go') { st.pausedAtS = nowS(); log(`block ends before visit ${index}: ${VERDICT_TEXT[verdict]}`); over = true; break; }
        ready = true;
      }
      const prior = st.visits.filter((v) => v.index === index);
      const attempts = prior.length > 0 ? prior[prior.length - 1].attempts : 0;
      const faults = faultsOfVisit(prior[prior.length - 1]);
      if (!mayAttempt(faults)) { st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'lost', attempts, faults, error: prior[prior.length - 1]?.error }]); saveState(dir, st); break; }
      const row = pages.rows.find((r) => r.id === a.id);
      const start = deps.now();
      log(`visit ${index} (${a.id}), attempt ${attempts + 1}`);
      try {
        const r = await deps.visit({ a, row, site, settle, clock, log });
        putJson(join(dir, rawName(index, a.id, 'counts')), { target: a.target, arm: a.id, ...r.counts });
        putJson(join(dir, rawName(index, a.id, 'frames')), { target: a.target, arm: a.id, ...r.frames });
        const durationS = Math.round((deps.now() - start) / 1000);
        longest = Math.max(longest, durationS);
        st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'done', attempts: attempts + 1, faults: prior[prior.length - 1]?.faults ?? [], durationS, endedMs: deps.now() }]);
        st.lastEndMs = deps.now();
        saveState(dir, st);
        const vals = P.visitValues(r.counts, r.frames);
        const bat = batteryOf(r.frames, r.counts);
        ran.push({ index, arm: a.id, durationS, vh: vals.vh, maxY: vals.maxY, hash: r.counts.fw?.configHash ?? null, hashOk: a.target === 'original' || r.counts.fw?.configHash === row.hash, battery: bat });
        console.log(JSON.stringify(ran[ran.length - 1]));
        await deps.sleep(10000);
        const { verdict } = sense('visit-end', index);
        saveState(dir, st);
        if (verdict === 'locked') return stop(`the phone is locked: ${VERDICT_TEXT.locked}`);
        if (verdict !== 'go') { st.pausedAtS = nowS(); log(`block ends after visit ${index}: ${VERDICT_TEXT[verdict]}`); over = true; }
        break;
      } catch (e) {
        const msg = String(e.message);
        let usb;
        try { usb = deps.usbNow(start - 60000); } catch { usb = { verdict: 'ok', evidence: [] }; }
        const fault = classify(msg, usb.verdict);
        const faultsNow = recordFault(faults, fault);
        st.visits = st.visits.filter((v) => v.index !== index).concat([{ index, arm: a.id, status: 'failed', attempts: attempts + 1, faults: faultsNow, error: msg.slice(0, 300), ...(fault === 'usbReset' ? { usb: { verdict: usb.verdict, listed: usb.listed ?? null, onBus: usb.onBus ?? null, evidence: usb.evidence.slice(0, 6) } } : {}) }]);
        st.lastEndMs = deps.now();
        saveState(dir, st);
        const text = `visit ${index} (${a.id}) attempt ${attempts + 1} failed (${fault}): ${msg.slice(0, 300)}`;
        if (fault !== 'usbReset' || !mayAttempt(faultsNow)) return stop(text);
        log(`${text}; USB reset${usb.evidence.length ? ` (${usb.evidence.map((x) => `${x.at} ${x.what}`).join('; ')})` : ''}, waiting up to ${USB_WAIT_S} s for the phone`);
        let waitedS = 0;
        for (;;) {
          const w = usbWait(deps.usbListed(), waitedS);
          if (w === 'resume') break;
          if (w === 'giveUp') return stop(`${text}; the phone did not list on USB within ${USB_WAIT_S} s`);
          await deps.sleep(5000);
          waitedS += 5;
        }
        log(`the phone lists again after ${waitedS} s; retrying visit ${index}`);
        await deps.sleep(10000);
        ready = false;
      }
    }
  }
  if (last === null || last.phase !== 'visit-end') {
    const { verdict } = sense('block-end', null);
    if (verdict !== 'go' && verdict !== 'locked') st.pausedAtS = nowS();
  }
  st.lastEndMs = deps.now();
  saveState(dir, st);
  return { ran, stopped: null, remaining: todo.length - ran.length, ...(st.pausedAtS ? { paused: true } : {}) };
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
    schema: 'fw.phone.end-counts/1', device, consts: P.PA, order: st.session ?? P.SESSION.map((a) => a.id), visits: meta, notRun: lost,
    anomalies: P.anomalies(visitsDone), base: sum.base, arms: st.session ? sum.arms.filter((a) => a.visits > 0) : sum.arms,
    thermal: st.thermal ?? [], firstTempC: st.firstTemp ?? null,
  };
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, 'summary.json'), JSON.stringify(summary, null, 1) + '\n');
  writeFileSync(join(out, 'tables.md'), tablesMarkdown(sum));
  return summary;
}
