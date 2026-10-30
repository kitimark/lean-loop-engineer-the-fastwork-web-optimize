import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { startTimeline } from './timeline.mjs';
import { markTimes, markTime, reduceSteps, zones } from './reduce.mjs';
import { PART_PROPS } from './device-record.mjs';
import { captureOf, CAP } from './device-feel-cap.mjs';

export const CARD_SELECTOR = '[data-fw-layer="hero.orbit_card"]';
export const MAX_CARDS = 12;
const CHUNK = 3000;

export const CAP_START_JS = `(() => {
  if (window.__fwCap && window.__fwCap.stop) window.__fwCap.stop();
  const PROPS = ${JSON.stringify(PART_PROPS)};
  const IDLE = ${CAP.idleMs};
  const frames = { t: [], y: [], vh: [], vt: [], p: { hero: [], people: [], fade: [] }, o: [], a: [] };
  const touches = [], pins = [], starts = [];
  const els = {}, last = { hero: 0, people: 0, fade: 0 };
  const read = (name) => {
    let el = els[name];
    if (!el || !el.isConnected) el = els[name] = document.querySelector('[style*="' + PROPS[name] + '"]');
    if (!el) return last[name];
    const v = parseFloat(el.style.getPropertyValue(PROPS[name]));
    if (!Number.isNaN(v)) last[name] = Math.round(Math.min(1, Math.max(0, v)) * 1000);
    return last[name];
  };
  let cards = [];
  const findCards = () => { cards = Array.prototype.slice.call(document.querySelectorAll(${JSON.stringify(CARD_SELECTOR)}), 0, ${MAX_CARDS}); };
  findCards();
  const vv = typeof visualViewport !== 'undefined' ? visualViewport : null;
  const zoom = { frames: 0, min: 1, max: 1 };
  const base = performance.timeOrigin;
  const stamp = (e) => Math.round((e.timeStamp > 1e11 ? e.timeStamp - base : e.timeStamp) * 100) / 100;
  const code = { touchstart: 's', touchmove: 'm', touchend: 'e', touchcancel: 'c' };
  let lastAct = performance.now();
  const onTouch = (e) => {
    lastAct = performance.now();
    const c = e.changedTouches[0];
    if (c) touches.push([stamp(e), code[e.type], Math.round(c.clientX * 10) / 10, Math.round(c.clientY * 10) / 10, e.touches.length]);
  };
  const opt = { passive: true, capture: true };
  for (const k of Object.keys(code)) addEventListener(k, onTouch, opt);
  const origScrollTo = window.scrollTo;
  window.scrollTo = function (a, b) {
    const to = a && typeof a === 'object' ? a.top : b;
    if (typeof to === 'number') pins.push([Math.round(performance.now() * 100) / 100, Math.round(scrollY * 10) / 10, Math.round(to * 10) / 10]);
    return origScrollTo.apply(this, arguments);
  };
  const prevTake = window.__fwTakeTrace;
  window.__fwTakeTrace = (ev) => {
    if (ev && ev.kind === 'push') starts.push([Math.round(performance.now() * 100) / 100, Math.round(ev.from * 1000), Math.round(ev.to * 1000)]);
    if (typeof prevTake === 'function') prevTake(ev);
  };
  let on = true, prevY = null, prevActive = false, k = 0, raf = 0;
  const f = (ts) => {
    if (!on) return;
    const y = Math.round(scrollY * 10) / 10;
    if (prevY !== null && y !== prevY) lastAct = performance.now();
    prevY = y;
    const active = performance.now() - lastAct < IDLE;
    if (cards.length === 0 || cards.some((c) => !c.isConnected)) findCards();
    frames.t.push(Math.round(ts * 100) / 100); frames.y.push(y);
    for (const n of Object.keys(frames.p)) frames.p[n].push(read(n));
    frames.o.push(cards.map((c) => Math.round(parseFloat(getComputedStyle(c).opacity) * 1000)));
    frames.a.push(active ? 1 : 0);
    const sc = vv ? vv.scale : 1;
    if (Math.abs(sc - 1) > 0.001) { zoom.frames++; zoom.min = Math.min(zoom.min, sc); zoom.max = Math.max(zoom.max, sc); }
    frames.vh.push(Math.round((vv ? vv.height : innerHeight) * 10) / 10); frames.vt.push(Math.round((vv ? vv.offsetTop : 0) * 10) / 10);
    if (active || prevActive || k === 0) performance.mark('cap:' + k);
    prevActive = active;
    k++;
    raf = requestAnimationFrame(f);
  };
  raf = requestAnimationFrame(f);
  window.__fwCap = {
    stop() {
      if (!on) return;
      on = false; cancelAnimationFrame(raf);
      performance.mark('cap:end'); setTimeout(() => performance.clearMarks(), 0);
      for (const k2 of Object.keys(code)) removeEventListener(k2, onTouch, opt);
      window.scrollTo = origScrollTo;
      window.__fwTakeTrace = prevTake;
    },
    meta: () => JSON.stringify({ n: frames.t.length, zoom, maxY: Math.round((document.documentElement.scrollHeight - innerHeight) * 10) / 10, viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio }, touches, pins, starts, cards: cards.length }),
    slice(field, a, b) {
      const v = field.startsWith('p.') ? frames.p[field.slice(2)] : frames[field];
      return JSON.stringify(v.slice(a, b));
    },
  };
  return 'on';
})()`;

export const CAP_STOP_JS = `(() => { if (!window.__fwCap) return 'none'; window.__fwCap.stop(); return window.__fwCap.meta(); })()`;

export function inputsOf(raw, rows) {
  const { t, y, o, a } = raw.frames;
  const n = t.length;
  const minY = Math.min(0, ...y);
  const ys10 = (v) => Math.max(0, Math.round((v - minY) * 10));
  const nCards = o.reduce((m, r) => Math.max(m, r.length), 0);
  const cards = Array.from({ length: nCards }, (_, c) => o.map((r) => Math.max(0, r[c] ?? 0)));
  const tm = markTimes(rows ?? [], 'cap:', n);
  const endTime = markTime(rows ?? [], 'cap:end');
  const idx = [];
  tm.forEach((v, i) => { if (v !== null) idx.push(i); });
  let zoneCounts = [];
  let zoneNote = null;
  if (idx.length === 0 || endTime === null) zoneNote = idx.length === 0 ? 'no frame marks in the Timeline' : 'no end mark in the Timeline';
  else {
    const red = reduceSteps(rows, idx.map((i) => tm[i]), endTime);
    const keep = idx.map((i, s) => (a[i] === 1 ? s : -1)).filter((s) => s >= 0);
    const z = zones(keep.map((s) => Math.max(0, y[idx[s]])), keep.map((s) => red.perStep[s]), keep.map((s) => red.perStepPaintArea[s]));
    zoneCounts = z.map((q) => q.counts);
  }
  return {
    ts: t.map((v) => Math.round(v * 100)),
    ys: y.map(ys10),
    pins: raw.pins.map(([pt, from, to]) => [Math.round(pt * 100), ys10(from), ys10(to)]),
    starts: raw.starts.map(([, from, to]) => [from, to]),
    cards,
    zones: zoneCounts,
    zoneNote,
  };
}

export function rawRecord({ arm, pass, raw, rows, marks }) {
  const { zoneNote, ...inputs } = marks;
  return {
    schema: 'fw.phone.record/1', arm, pass, zoom: raw.zoom, maxY: raw.maxY, viewport: raw.viewport,
    frames: { t: raw.frames.t, y: raw.frames.y, vh: raw.frames.vh, vt: raw.frames.vt, p: raw.frames.p },
    touches: raw.touches,
    feel: { active: raw.frames.a, opacity: inputs.cards, pins: raw.pins, starts: raw.starts, cardCount: raw.cards, zoneNote, timelineRows: rows?.length ?? 0 },
  };
}

async function pull(c, meta) {
  const frames = { p: {} };
  const fields = ['t', 'y', 'vh', 'vt', 'o', 'a', 'p.hero', 'p.people', 'p.fade'];
  for (const f of fields) {
    const out = [];
    for (let i = 0; i < meta.n; i += CHUNK) out.push(...JSON.parse(await c.evaluate(`window.__fwCap.slice(${JSON.stringify(f)}, ${i}, ${i + CHUNK})`)));
    if (f.startsWith('p.')) frames.p[f.slice(2)] = out; else frames[f] = out;
  }
  return { ...meta, frames };
}

export function visitCapture({ ctx, visit, dir, log, startTl = startTimeline }) {
  let tl = null;
  let open = false;
  return {
    get open() { return open; },
    async start() {
      try {
        tl = await startTl(ctx.c);
        await ctx.c.evaluate(CAP_START_JS);
        open = true;
        log(`capture on for ${visit.label}`);
        return true;
      } catch (e) {
        log(`capture start failed for ${visit.label}: ${e.message}`);
        if (tl) { await tl.stop().catch(() => {}); tl = null; }
        return false;
      }
    },
    async finish() {
      if (!open) return { error: 'no capture was running' };
      open = false;
      try {
        const metaText = await ctx.c.evaluate(CAP_STOP_JS);
        if (metaText === 'none') throw new Error('the page lost the recorder (it navigated?)');
        const rows = await tl.stop();
        tl = null;
        const raw = await pull(ctx.c, JSON.parse(metaText));
        const inputs = inputsOf(raw, rows);
        const capture = captureOf(inputs);
        const rec = rawRecord({ arm: visit.id, pass: visit.index + 1, raw, rows, marks: inputs });
        mkdirSync(join(dir, 'visits'), { recursive: true });
        const file = join('visits', `${String(visit.index + 1).padStart(2, '0')}-${visit.label}.json`);
        writeFileSync(join(dir, file), JSON.stringify(rec));
        log(`capture ${visit.label}: ${JSON.stringify({ ...capture, zoneWork: capture.zoneWork.length })}${inputs.zoneNote ? ` (zones: ${inputs.zoneNote})` : ''}`);
        return { capture, file, zoneNote: inputs.zoneNote };
      } catch (e) {
        if (tl) await tl.stop().catch(() => {});
        tl = null;
        log(`capture finish failed for ${visit.label}: ${e.message}`);
        return { error: e.message };
      }
    },
  };
}
