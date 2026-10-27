import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { withPhone, listPhone } from './device.mjs';
import { loadFresh } from './page.mjs';
import { sleep } from './sim.mjs';
import { startTimeline } from './timeline.mjs';
import { toHundredths } from './profile/reduce.mjs';
import { openDriver, TOUCH_PUSH } from './touch-push.mjs';
import { buildPushDriver, startPhoneServer, stopPhoneServer } from './device-push-chan.mjs';
import { PUSH, PUSH_ARMS, PUSH_METRICS, COUNT_KINDS, clockOff, columns, contrastOf, pushCells, pushLabel, pushesOf, slotOf, takenOf, visitVals } from './device-push.mjs';
import { loadState, rawName, whenTabBlank, faultsOfVisit } from './device-phone-run.mjs';

const median = (l) => { const s = [...l].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };

export const ASKS = PUSH.patternAsks + PUSH.burstAsks;
export const GAP_PX = 100;
export const TAIL_MS = 1500;
export const SETTLE_AFTER_SCROLL_MS = 1800;
export const SERVER_MAX_S = 3300;

const NAV = 'header.start-selling-top-nav, [data-fw="nav"]';

export const TRACE_HOOK_JS = `window.__fwTakeTrace = (e) => { st.tr.push([e.kind, Math.round(performance.now() * 100), e.kind === 'take' ? Math.round(e.el * 100) : Math.round(e.from * 1000), e.kind === 'push' ? Math.round(e.to * 1000) : 0]); };`;

export const FRAMES_START_JS = `(() => {
  const st = window.__fwPush = { f: [], ts: [], tr: [], on: true, nav: null };
  ${TRACE_HOOK_JS}
  const nav = () => (st.nav && st.nav.isConnected ? st.nav : (st.nav = document.querySelector(${JSON.stringify(NAV)})));
  addEventListener('touchstart', (e) => { const n = performance.now(); st.ts.push(Math.round((Math.abs(n - e.timeStamp) < 1000 ? e.timeStamp : n) * 100)); }, { capture: true, passive: true });
  const anim = (n) => {
    let ct = 0;
    for (const a of n.getAnimations({ subtree: true })) {
      if (a.playState !== 'running') continue;
      const it = a.effect && a.effect.getComputedTiming ? a.effect.getComputedTiming().endTime : Infinity;
      if (Number.isFinite(it)) ct = Math.max(ct, Math.round(Number(a.currentTime) || 0));
    }
    return ct;
  };
  const tick = (t) => {
    if (!st.on) return;
    const n = nav();
    const m = n ? Math.round(Number(n.style.getPropertyValue('--morph') || n.getAttribute('data-fw-morph') || 0) * 1000) : 0;
    st.f.push([Math.round(t * 100), Math.round(scrollY * 10), m + (n ? anim(n) * 10000 : 0)]);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  return 'started';
})()`;

export const FRAMES_STOP_JS = `(() => {
  const st = window.__fwPush;
  if (!st) return JSON.stringify({ err: 'recorder not started' });
  st.on = false;
  return JSON.stringify({ f: st.f, ts: st.ts, tr: st.tr, nav: !!st.nav, maxY: document.documentElement.scrollHeight - innerHeight, vh: innerHeight, y: scrollY });
})()`;

export const COUNTS_START_JS = `(() => {
  const st = window.__fwPushC = { ts: [], tr: [], a: 0, b: 0 };
  ${TRACE_HOOK_JS}
  addEventListener('touchstart', (e) => { const n = performance.now(); st.ts.push(Math.round((Math.abs(n - e.timeStamp) < 1000 ? e.timeStamp : n) * 100)); }, { capture: true, passive: true });
  performance.clearMarks('wk:a');
  performance.mark('wk:a');
  st.a = performance.getEntriesByName('wk:a').pop().startTime;
  return 'started';
})()`;

export const COUNTS_STOP_JS = `(() => {
  const st = window.__fwPushC;
  if (!st) return JSON.stringify({ err: 'recorder not started' });
  performance.clearMarks('wk:b');
  performance.mark('wk:b');
  st.b = performance.getEntriesByName('wk:b').pop().startTime;
  return JSON.stringify({ ts: st.ts, tr: st.tr, a: Math.round(st.a * 100), b: Math.round(st.b * 100), maxY: document.documentElement.scrollHeight - innerHeight, vh: innerHeight, y: scrollY });
})()`;

export const nearEndJs = (gap) => `(() => {
  const maxY = document.documentElement.scrollHeight - innerHeight;
  window.scrollTo({ top: Math.max(0, maxY - ${Number(gap)}), behavior: 'instant' });
  return JSON.stringify({ maxY, y: scrollY, vh: innerHeight });
})()`;

export function recordsOf(rows) {
  const marks = {};
  const rs = [];
  for (const [type, start, , extra] of rows) {
    if (type === 'TimeStamp' && (extra === 'wk:a' || extra === 'wk:b') && marks[extra] === undefined) marks[extra] = toHundredths(start * 1000);
    if (COUNT_KINDS.includes(type)) rs.push([type, toHundredths(start * 1000)]);
  }
  return { rs, tlA: marks['wk:a'] ?? null, tlB: marks['wk:b'] ?? null };
}

export function valuesOf(counts, frames) {
  if (frames.ts.length !== PUSH.pushes) throw new Error(`the frames lane saw ${frames.ts.length} touch starts, not ${PUSH.pushes}`);
  if (counts.ts.length !== PUSH.pushes) throw new Error(`the counts lane saw ${counts.ts.length} touch starts, not ${PUSH.pushes}`);
  const off = clockOff(counts.tlA, counts.tlB, counts.a, counts.b);
  if (off === null) throw new Error(`the Timeline and page clocks drift apart (marks ${counts.tlA}/${counts.tlB} vs ${counts.a}/${counts.b})`);
  const vals = visitVals(frames.f, frames.hiEnd, frames.ts, counts.ts, off, counts.rs);
  return { vh: frames.vh, maxY: frames.maxY, push: vals };
}

const PRESS_WAIT_MS = 60000;
export async function ask(server, variant = 'springboard', waitMs = PRESS_WAIT_MS) {
  const n = server.next++;
  writeFileSync(join(server.dir, `go-${n}`), variant);
  const doneFile = join(server.dir, `done-${n}`);
  const t0 = Date.now();
  while (!existsSync(doneFile) && !server.run.state.ended && Date.now() - t0 < waitMs) await sleep(50);
  if (!existsSync(doneFile)) return null;
  try { return readFileSync(doneFile, 'utf8').trim().split(/\s+/).slice(1).map(Number); } catch { return []; }
}

async function pushes(server, log, tag) {
  const presses = [];
  for (let k = 0; k < ASKS; k++) {
    const p = await ask(server);
    if (p === null) throw new Error(`the push driver gave no answer to request ${k + 1} of ${ASKS} (${server.run.state.ended ? `ended, code ${server.run.state.code}` : 'still running'})`);
    presses.push(p);
  }
  log(`${tag}: ${ASKS} requests done, presses ${presses.map((p) => p.join('/')).join(' ')} ms`);
  return presses;
}

export async function framesLane(ctx, { server, settleMs, clock, log, gap = GAP_PX }) {
  const readouts = [ctx.readout()];
  await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
  const near = JSON.parse(await ctx.c.evaluate(nearEndJs(gap)));
  await sleep(SETTLE_AFTER_SCROLL_MS);
  if ((await ctx.c.evaluate(FRAMES_START_JS)) !== 'started') throw new Error('the frame recorder did not start');
  const presses = await pushes(server, log, 'frames');
  await sleep(TAIL_MS);
  const r = JSON.parse(await ctx.c.evaluate(FRAMES_STOP_JS));
  if (r.err) throw new Error(r.err);
  readouts.push(ctx.readout());
  const hiEnd = r.f.length ? r.f[r.f.length - 1][0] + 1 : 0;
  return { schema: 'fw.phone.push-frames/1', device: ctx.device, readouts, near, presses, nav: r.nav, vh: r.vh, maxY: r.maxY, endY: r.y, hiEnd, ts: r.ts, tr: r.tr ?? [], f: r.f };
}

export async function countsLane(ctx, { server, settleMs, clock, log, gap = GAP_PX }) {
  const readouts = [ctx.readout()];
  await loadFresh(ctx.c, { clock, settleMs, timers: 'live' });
  const near = JSON.parse(await ctx.c.evaluate(nearEndJs(gap)));
  await sleep(SETTLE_AFTER_SCROLL_MS);
  const tl = await startTimeline(ctx.c);
  let r;
  let rows;
  try {
    if ((await ctx.c.evaluate(COUNTS_START_JS)) !== 'started') throw new Error('the counts recorder did not start');
    const presses = await pushes(server, log, 'counts');
    await sleep(TAIL_MS);
    r = JSON.parse(await ctx.c.evaluate(COUNTS_STOP_JS));
    r.presses = presses;
  } finally {
    rows = await tl.stop().catch(() => null);
  }
  if (r.err) throw new Error(r.err);
  if (!rows) throw new Error('the Timeline did not stop');
  const { rs, tlA, tlB } = recordsOf(rows);
  readouts.push(ctx.readout());
  return { schema: 'fw.phone.push-counts/1', device: ctx.device, readouts, near, presses: r.presses, vh: r.vh, maxY: r.maxY, endY: r.y, ts: r.ts, tr: r.tr ?? [], a: r.a, b: r.b, tlA, tlB, rs };
}

export const pushVisit = ({ server, gapPx = GAP_PX }) => async ({ row, site, settle, clock, log, gate }) => {
  const srv = await server();
  return whenTabBlank(() => withPhone(async (ctx) => {
    const frames = await framesLane(ctx, { server: srv, settleMs: settle, clock, log: ctx.log, gap: gapPx });
    if (gate) await gate();
    const counts = await countsLane(ctx, { server: srv, settleMs: settle, clock, log: ctx.log, gap: gapPx });
    counts.fw = { configHash: row.hash };
    valuesOf(counts, frames);
    return { frames, counts };
  }, { site: { dir: site, search: row.search }, log }), log);
};

export function driverHolder({ dir, log, udid = listPhone().udid, push = TOUCH_PUSH }) {
  let driver = null;
  let srv = null;
  let startedAt = 0;
  const stop = async () => { if (srv) { const s = srv; srv = null; await stopPhoneServer(s).catch(() => {}); } };
  const get = async () => {
    if (srv && !srv.run.state.ended && Date.now() - startedAt < (SERVER_MAX_S - 600) * 1000) return srv;
    await stop();
    if (!driver) {
      const found = openDriver(dir);
      driver = found.driver ?? (await buildPushDriver({ udid, dir, log }));
    }
    srv = await startPhoneServer(driver, { udid, log, push, maxS: SERVER_MAX_S, readyMs: 120000, tag: 'push' });
    startedAt = Date.now();
    return srv;
  };
  return { get, stop };
}

/** Driver trace of one lane: the pushes and takes, and per touch whether a take came before the next touch (TS stand-in for the touch mapping). */
export function traceOf(ts, tr) {
  const evs = (tr ?? []).map((e) => e[0]);
  const perTouch = ts.map((t, i) => (tr ?? []).some((e) => e[0] === 'take' && t <= e[1] && (i + 1 >= ts.length || e[1] < ts[i + 1])));
  return { pushes: pushesOf(evs), taken: takenOf(evs), touches: perTouch.length, touchTaken: perTouch.filter(Boolean).length, perTouch };
}

export function readVisits(dir) {
  const st = loadState(dir);
  const done = st.visits.filter((v) => v.status === 'done').sort((a, b) => a.index - b.index);
  const rows = done.map((v) => {
    const counts = JSON.parse(readFileSync(join(dir, rawName(v.index, v.arm, 'counts')), 'utf8'));
    const frames = JSON.parse(readFileSync(join(dir, rawName(v.index, v.arm, 'frames')), 'utf8'));
    const vals = valuesOf(counts, frames);
    return { index: v.index, arm: v.arm, ...(slotOf(v.index) ?? { round: null, position: null }), durationS: v.durationS, configHash: counts.fw?.configHash ?? null, nav: frames.nav, vh: vals.vh, maxY: vals.maxY, vals: vals.push,
      pushes: frames.ts.length, trace: { frames: traceOf(frames.ts, frames.tr), counts: traceOf(counts.ts, counts.tr) }, maxMorph: frames.f.reduce((m, x) => Math.max(m, x[2] % 10000), 0), device: counts.device };
  });
  const lost = st.visits.filter((v) => v.status !== 'done').map((v) => ({ index: v.index, arm: v.arm, status: v.status, attempts: v.attempts, faults: faultsOfVisit(v) }));
  return { st, rows, lost };
}

export function summarize(rows, arms = PUSH_ARMS) {
  const by = (id) => rows.filter((r) => r.arm === id).map((r) => r.vals);
  const base = by('base');
  return arms.map((a) => {
    const vs = by(a.id);
    const cols = columns(PUSH_METRICS.length, vs);
    return {
      id: a.id, flags: a.flags, n: vs.length,
      metrics: Object.fromEntries(PUSH_METRICS.map((m, i) => [m, cols[i].length ? { median: median(cols[i]), min: Math.min(...cols[i]), max: Math.max(...cols[i]), values: cols[i] } : null])),
      cells: a.id === 'base' ? null : pushCells(base, vs),
      label: a.id === 'base' ? 'base' : pushLabel(base, vs),
    };
  });
}

/** The pair contrasts of the column probe, decided per column by Lean `pushLabel` and `cells`; cause names why a column stays undecided. */
export const contrastsOf = (rows, contrasts) => contrasts.map((c) => {
  const by = (id) => rows.filter((r) => r.arm === id).map((r) => r.vals);
  return { ref: c.ref, arm: c.arm, nRef: by(c.ref).length, nArm: by(c.arm).length, ...contrastOf(by(c.ref), by(c.arm)) };
});

/** Take share per arm: the driver pushes and takes (Lean `pushesOf`, `takenOf`) and the touches with a take, summed over the visits of the arm. */
export const takeShareOf = (rows, arms) => arms.map((a) => {
  const vs = rows.filter((r) => r.arm === a.id && r.trace);
  const sum = (lane, k) => vs.reduce((n, r) => n + r.trace[lane][k], 0);
  return { id: a.id, visits: vs.length, frames: { pushes: sum('frames', 'pushes'), taken: sum('frames', 'taken'), touches: sum('frames', 'touches'), touchTaken: sum('frames', 'touchTaken') },
    counts: { pushes: sum('counts', 'pushes'), taken: sum('counts', 'taken'), touches: sum('counts', 'touches'), touchTaken: sum('counts', 'touchTaken') } };
});

export const writeJson = (file, data) => { mkdirSync(resolve(file, '..'), { recursive: true }); writeFileSync(file, JSON.stringify(data, null, 1) + '\n'); };

const cellOf = (rs) => {
  const cols = columns(PUSH_METRICS.length, rs.map((r) => r.vals));
  return Object.fromEntries(PUSH_METRICS.map((m, i) => [m, cols[i].length ? { median: median(cols[i]), values: cols[i] } : null]));
};

export function positionCheck(rows) {
  const group = (key) => [...new Set(rows.map((r) => r[key]).filter((x) => x !== null))].sort((a, b) => a - b)
    .map((k) => { const rs = rows.filter((r) => r[key] === k); return { [key]: k, n: rs.length, arms: rs.map((r) => r.arm), metrics: cellOf(rs) }; });
  return { byPosition: group('position'), byRound: group('round') };
}
