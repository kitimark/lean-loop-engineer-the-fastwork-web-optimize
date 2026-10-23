import { mkdirSync, writeFileSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { withSession } from '../../../packages/measure-webkit/src/session.mjs';
import { loadFresh, pageInfo, scrollHold } from '../../../packages/measure-webkit/src/page.mjs';
import { takeCensus } from '../../../packages/measure-webkit/src/census.mjs';
import { findDevice, simctl, sleep } from '../../../packages/measure-webkit/src/sim.mjs';
import { decodePng, encodePng, cropImage, sameImage } from '../../../packages/measure-webkit/src/pathpix-png.mjs';
import { FREEZE_EXPR, HOLD_EXPR, NEAR_IMAGES_EXPR, VIDEO_EXPR, MARK_ON, MARK_OFF } from '../../../packages/measure-webkit/src/pathpix-page.mjs';
import { magentaBox } from '../../../packages/measure-webkit/src/pathpix-webkit.mjs';
import { statesOf, zoneArms } from './plan.mjs';
import { iosurfaceSample } from './iosurface.mjs';

const NAV = `document.querySelector('[data-fw="nav"]')`;
export const SET_MORPH = (m) => `(() => { const n = ${NAV}; n.style.setProperty('--morph', '${m}'); n.dataset.fwMorph = '${m}'; return 1; })()`;
export const PUSH_EXPR = `(() => {
  const w = window;
  const lane = w.__lane = { parked: [], cap: false, id: 0, t0: 0, anims: [] };
  const nativeRaf = w.requestAnimationFrame.bind(w), nativeCaf = w.cancelAnimationFrame.bind(w);
  w.requestAnimationFrame = (cb) => { if (!lane.cap) return nativeRaf(cb); const id = -(++lane.id); lane.parked.push({ id, cb }); return id; };
  w.cancelAnimationFrame = (h) => { if (h < 0) lane.parked = lane.parked.filter((p) => p.id !== h); else nativeCaf(h); };
  const before = new Set(document.getAnimations());
  const e = new WheelEvent('wheel', { deltaY: 120, cancelable: true, bubbles: true });
  lane.cap = true; lane.t0 = performance.now();
  document.body.dispatchEvent(e);
  lane.cap = false;
  lane.anims = document.getAnimations().filter((a) => !before.has(a));
  for (const a of lane.anims) a.pause();
  return JSON.stringify({ taken: e.defaultPrevented, parked: lane.parked.length, anims: lane.anims.length });
})()`;
export const STEP_EXPR = (ms, m) => `(() => {
  const lane = window.__lane;
  const n = ${NAV};
  for (const a of lane.anims) { a.pause(); a.currentTime = ${Number(ms)}; }
  const tickAt = (t) => { lane.cap = true; const q = lane.parked.splice(0); for (const p of q) p.cb(t); lane.cap = false; return parseFloat(n.style.getPropertyValue('--morph')); };
  let t = lane.t0 + ${Number(ms)}, v = tickAt(t), corrections = 0;
  while (Math.abs(v - ${Number(m)}) > 1e-6 && corrections < 6) { const el = 680 * (1 - Math.pow(1 - Math.min(Math.max(v, 0), 1), 1 / 3)); t += ${Number(ms)} - el; v = tickAt(t); corrections++; }
  const published = v;
  n.style.setProperty('--morph', '${m}'); n.dataset.fwMorph = '${m}';
  return JSON.stringify({ published, corrections, startLag: t - lane.t0 - ${Number(ms)}, parked: lane.parked.length, anims: lane.anims.map((a) => { const t = a.effect.getComputedTiming(); const el = a.effect.target; return { target: el ? (el.getAttribute('data-fw') || el.className || el.tagName).toString().slice(0, 40) : null, playState: a.playState, currentTime: a.currentTime, progress: t.progress, easing: a.effect.getTiming().easing, props: Object.keys((a.effect.getKeyframes()[0] || {})).filter((k) => !['offset', 'computedOffset', 'easing', 'composite'].includes(k)) }; }) });
})()`;
export const NAV_STATE = `(() => { const n = ${NAV}; const r = n.getBoundingClientRect(); return JSON.stringify({ cls: n.className, morph: getComputedStyle(n).getPropertyValue('--morph').trim(), rect: [Math.round(r.left * 1e6), Math.round(r.top * 1e6), Math.round(r.width * 1e6), Math.round(r.height * 1e6)], scrollY: Math.round(scrollY) }); })()`;
export const PAIN_STATE = `(() => { const p = document.querySelector('[data-fw="pain"]'); return JSON.stringify({ dark: !!p && p.classList.contains('is-pain-dark'), variant: p ? p.getAttribute('data-fw-variant') : null, scrollY: Math.round(scrollY) }); })()`;
export const HERO_RANGE = `(() => { const t = document.querySelector('[data-fw="hero-exit"]'); return t.getBoundingClientRect().height - innerHeight; })()`;
export const HERO_SPLASH_DONE = `(async () => { const h = document.querySelector('[data-fw="hero-exit"] > div'); for (let i = 0; i < 300; i++) { if (h && h.dataset.splash === 'done') return true; await new Promise((r) => setTimeout(r, 100)); } return false; })()`;
export const HERO_STATE = `(() => { const t = document.querySelector('[data-fw="hero-exit"]'); const h = t.firstElementChild; return JSON.stringify({ splash: h.dataset.splash, live: t.hasAttribute('data-exit-live'), variant: t.getAttribute('data-fw-variant'), scrollAnims: document.getAnimations().filter((a) => !(a.timeline instanceof DocumentTimeline)).length, exitOpacity: getComputedStyle(h).getPropertyValue('--exit-opacity').trim(), scrollY: Math.round(scrollY) }); })()`;
export const FLIP_SCAN = (maxY) => `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const dark = async (y) => { scrollTo({ top: y, behavior: 'instant' }); await raf(); await raf(); const p = document.querySelector('[data-fw="pain"]'); return !!p && p.classList.contains('is-pain-dark'); };
  let hit = null;
  for (let y = 0; y <= ${Number(maxY)}; y += 8) { if (await dark(y)) { hit = y; break; } }
  if (hit === null) return JSON.stringify({ flip: null });
  for (let y = hit - 7; y < hit; y++) { if (y >= 0 && await dark(y)) { hit = y; break; } }
  scrollTo({ top: 0, behavior: 'instant' }); await raf();
  return JSON.stringify({ flip: hit });
})()`;

export const wantEffects = (arm) => (arm.search.includes('morph.panel:threaded') ? 2 : 0) + (arm.search.includes('platform:fade-threaded') ? 1 : 0);

const shot = (udid, file) => {
  const r = simctl(['io', udid, 'screenshot', '--type=png', file], { timeoutMs: 60000 });
  if (r.status !== 0) throw new Error(`simctl screenshot failed: ${(r.stderr || r.stdout).trim().split('\n').slice(-2).join(' | ')}`);
  return readFileSync(file);
};
const pinBar = (udid, log) => {
  const r = simctl(['status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  if (r.status !== 0) log(`status_bar override failed (the crop leaves the bar out): ${(r.stderr || '').trim().slice(0, 120)}`);
};

export async function captureZone({ zone, siteDir, shotsDir, settleMs = 4500, log = (s) => console.error(s) }) {
  mkdirSync(shotsDir, { recursive: true });
  const tmp = mkdtempSync(join(tmpdir(), 'fw-gpusaf-'));
  const dev = findDevice();
  const arms = zoneArms(zone);
  try {
    return await withSession(async (ctx) => {
      pinBar(dev.udid, log);
      const out = { session: null, arms: {}, states: null, flip: null };
      let content = null, frame = null;
      const load = async (arm) => {
        ctx.setArm(arm.id);
        await ctx.c.evaluate(`history.replaceState(null, '', ${JSON.stringify('/' + arm.search)}); scrollTo({ top: 0, behavior: 'instant' }); location.search`);
        await loadFresh(ctx.c, { clock: 'pinned', settleMs, timers: 'hold' });
        await ctx.c.runAsync(HOLD_EXPR);
        await ctx.c.evaluate(FREEZE_EXPR);
        const info = await pageInfo(ctx.c);
        if (info.fw?.configHash !== ctx.armHash(arm.id)) throw new Error(`arm ${arm.id}: wrong page (${JSON.stringify(info.fw)})`);
        return info;
      };
      const place = async (info) => {
        await ctx.c.evaluate(MARK_ON);
        await sleep(700);
        const box = magentaBox(decodePng(shot(dev.udid, join(tmp, 'mark.png'))));
        await ctx.c.evaluate(MARK_OFF);
        const want = [Math.round(info.vw * info.dpr), Math.round(info.vh * info.dpr)];
        if (!box || box[2] !== want[0] || box[3] > want[1]) throw new Error(`viewport marker ${box} does not fit the page's ${want.join('x')}`);
        return [box[0], box[1], want[0], want[1]];
      };
      const settleShots = async (id, stateId) => {
        let prev = null;
        for (let rep = 0; rep < 6; rep++) {
          const png = cropImage(decodePng(shot(dev.udid, join(tmp, 'shot.png'))), content[0], content[1], frame.w, frame.h);
          if (prev && (sameImage(prev, png) || rep === 5)) {
            const files = [];
            for (const [n, img] of [[0, prev], [1, png]]) {
              const f = `${id}_${stateId}_${n}.png`;
              writeFileSync(join(shotsDir, f), encodePng(img));
              files.push(f);
            }
            return { files, settled: sameImage(prev, png), tries: rep + 1 };
          }
          prev = png;
          await sleep(500);
        }
        throw new Error('unreachable');
      };

      {
        const info = await load(arms[0]);
        content = await place(info);
        frame = { w: content[2], h: content[3] };
        out.session = { ua: info.ua, dpr: info.dpr, vw: info.vw, vh: info.vh, maxY: info.maxY, frame, content, device: dev.name, runtime: dev.runtime };
        if (zone === 'pain') {
          out.flip = JSON.parse(await ctx.c.runAsync(FLIP_SCAN(info.maxY), { pollMs: 250 })).flip;
          if (out.flip === null) throw new Error('the faithful arm never sets is-pain-dark while scrolling');
        }
        out.states = statesOf(zone, out.flip);
        log(`zone ${zone}: dpr ${info.dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h}, maxY ${info.maxY}${zone === 'pain' ? `, flip ${out.flip}` : ''}`);
      }
      for (let a = 0; a < arms.length; a++) {
        const arm = arms[a];
        const info = await load(arm);
        const rows = [];
        if (zone !== 'pain') { await scrollHold(ctx.c, info.maxY, { holdMs: 800 }); }
        let pushSeen = null;
        if (zone === 'morph') {
          await ctx.c.runAsync(NEAR_IMAGES_EXPR);
          await ctx.c.runAsync(VIDEO_EXPR);
          await ctx.c.evaluate(FREEZE_EXPR);
          await sleep(400);
          pushSeen = JSON.parse(await ctx.c.evaluate(PUSH_EXPR));
          if (!pushSeen.taken || pushSeen.parked < 1) throw new Error(`arm ${arm.id}: the driver did not take the wheel push (${JSON.stringify(pushSeen)})`);
          log(`  ${arm.id}: push taken, ${pushSeen.anims} effects started, ${pushSeen.parked} frame parked`);
        }
        for (const st of out.states) {
          let step = null;
          if (st.drive === 'push') {
            step = JSON.parse(await ctx.c.evaluate(STEP_EXPR(st.elapsedMs, st.m)));
            if (step.anims.length !== wantEffects(arm)) throw new Error(`arm ${arm.id}: ${step.anims.length} effects started, expected ${wantEffects(arm)} (${JSON.stringify(step.anims.map((a) => a.target))})`);
            await sleep(1200);
          } else if (st.kind === 'morph') {
            await ctx.c.evaluate(SET_MORPH(st.m));
            await sleep(1200);
          } else {
            await scrollHold(ctx.c, st.y, { holdMs: 900 });
          }
          if (st.drive !== 'push') {
            await ctx.c.runAsync(NEAR_IMAGES_EXPR);
            await ctx.c.runAsync(VIDEO_EXPR);
            await ctx.c.evaluate(FREEZE_EXPR);
            await sleep(400);
            await ctx.c.evaluate(FREEZE_EXPR);
            await sleep(300);
          }
          const state = JSON.parse(await ctx.c.evaluate(st.kind === 'morph' ? NAV_STATE : PAIN_STATE));
          const files = await settleShots(arm.id, st.id);
          const cen = await takeCensus(ctx.c, { paintWindowMs: 0 });
          const iosurface = iosurfaceSample();
          rows.push({ id: st.id, ...files, state, push: step ? { ...step, taken: pushSeen.taken } : null, iosurface, census: { layerCount: cen.layerCount, memoryBytes: cen.memoryBytes, reasonCounts: cen.reasonCounts } });
          log(`  ${arm.id} ${st.id}: ${JSON.stringify(state)} layers ${cen.layerCount} mem ${cen.memoryBytes} iosurf gpu ${iosurface.gpu?.regions ?? '-'}/${Math.round((iosurface.gpu?.virtualBytes ?? 0) / 1e6)}MB`);
        }
        out.arms[arm.id] = { search: arm.search, states: rows };
      }
      return out;
    }, { keep: true, arms: Object.fromEntries(arms.map((a) => [a.id, { dir: siteDir, search: a.search }])), log });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
