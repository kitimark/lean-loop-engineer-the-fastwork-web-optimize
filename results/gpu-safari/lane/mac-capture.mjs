import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { openLane, loadArm, sleep } from './session.mjs';
import { decodePng, sameImage } from '../../../packages/measure-webkit/src/pathpix-png.mjs';
import { FREEZE_EXPR } from '../../../packages/measure-webkit/src/pathpix-page.mjs';
import { statesOf, zoneArms } from './plan.mjs';
import { SET_MORPH, NAV_STATE, PAIN_STATE, FLIP_SCAN, PUSH_EXPR, STEP_EXPR, wantEffects, HERO_RANGE, HERO_SPLASH_DONE, HERO_STATE } from './sim-capture.mjs';

const FACE = `document.querySelector('[data-selenium^="start-selling.people.button.preview."]')`;
export const PEOPLE_SETUP = `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  const f = ${FACE};
  if (!f) return JSON.stringify({ ok: false, why: 'no face' });
  scrollTo({ top: scrollY + f.getBoundingClientRect().top - 250, behavior: 'instant' });
  await raf(); await raf();
  return JSON.stringify({ ok: true, scrollY: Math.round(scrollY), faceTop: Math.round(f.getBoundingClientRect().top) });
})()`;
export const PEOPLE_HOVER = `(async () => {
  const f = ${FACE};
  f.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window }));
  return 1;
})()`;
export const PEOPLE_SCROLL = (frames, dy) => `(async () => {
  const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
  for (let i = 0; i < ${Number(frames)}; i++) { scrollBy(0, ${Number(dy)}); await raf(); }
  await raf(); await raf();
  return scrollY;
})()`;
export const PEOPLE_STATE = `(() => {
  const t = document.querySelector('[role="tooltip"]'), f = ${FACE};
  const r = t ? t.getBoundingClientRect() : null, fr = f.getBoundingClientRect();
  return JSON.stringify({ scrollY: Math.round(scrollY), vw: innerWidth, tooltip: !!t, style: t ? { top: t.style.top, left: t.style.left, translate: t.style.translate, opacity: getComputedStyle(t).opacity } : null,
    rect: r ? [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 100) / 100) : null, face: [fr.left, fr.top].map((v) => Math.round(v * 100) / 100) });
})()`;

const BOX = `document.querySelector('[data-fw="people-carousel"]')`;
export const CAROUSEL_ARM = `(async () => {
  const w = window, box = ${BOX};
  if (!box) return JSON.stringify({ ok: false, why: 'no carousel' });
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return JSON.stringify({ ok: false, why: 'reduced motion: the loop never runs' });
  const lane = w.__lane = { parked: false, swap: null, wrapped: 0, fired: 0, anims: [] };
  const native = w.setInterval.bind(w);
  w.setInterval = (cb, ms, ...a) => { lane.wrapped++; return native(() => { if (lane.parked) return; lane.fired++; cb(...a); }, ms, ...a); };
  const mo = new MutationObserver(() => {
    if (lane.swap || box.children.length !== 5) return;
    lane.parked = true;
    lane.anims = document.getAnimations().filter((a) => a.effect && box.contains(a.effect.target));
    for (const a of lane.anims) { a.pause(); a.currentTime = 0; }
    lane.swap = { at: Math.round(performance.now()), anims: lane.anims.length };
  });
  mo.observe(box, { childList: true, subtree: true });
  box.scrollIntoView({ block: 'center', behavior: 'instant' });
  for (let i = 0; i < 100 && !lane.swap; i++) await new Promise((r) => setTimeout(r, 100));
  mo.disconnect();
  return JSON.stringify({ ok: !!lane.swap, why: lane.swap ? null : 'no swap row in 10 s', swap: lane.swap, wrapped: lane.wrapped, fired: lane.fired });
})()`;
export const CAROUSEL_STEP = (ms) => `(async () => {
  const lane = window.__lane, box = ${BOX};
  for (const a of lane.anims) { a.pause(); a.currentTime = ${Number(ms)}; }
  for (let i = 0; i < 50; i++) { if ([...box.querySelectorAll('img')].every((im) => im.complete && im.naturalWidth > 0)) break; await new Promise((r) => setTimeout(r, 100)); }
  return 1;
})()`;
export const CAROUSEL_STATE = `(() => {
  const lane = window.__lane, box = ${BOX};
  const r = box.getBoundingClientRect();
  const imgs = [...box.querySelectorAll('img')];
  const cs = (e) => { const c = getComputedStyle(e); return { opacity: c.opacity, transform: c.transform, translate: c.translate, width: c.width, marginRight: c.marginRight }; };
  return JSON.stringify({ scrollY: Math.round(scrollY), rect: [r.left, r.top, r.width, r.height].map((v) => Math.round(v * 1e6)), n: imgs.length, parked: lane.parked, swapRow: lane.swap,
    src: imgs.map((e) => e.getAttribute('src').split('/').pop()), cls: imgs.map((e) => e.className), style: imgs.map(cs),
    anims: lane.anims.map((a) => ({ name: a.animationName, playState: a.playState, currentTime: a.currentTime, idx: imgs.indexOf(a.effect.target) })) });
})()`;

export function flat(png) {
  const { rgba } = decodePng(png);
  for (let i = 4; i < rgba.length; i += 4) if (rgba[i] !== rgba[0] || rgba[i + 1] !== rgba[1] || rgba[i + 2] !== rgba[2]) return false;
  return true;
}

export async function captureZoneMac({ zone, siteDir, shotsDir, settleMs = 2500, loads = 3, log = (s) => console.error(s) }) {
  mkdirSync(shotsDir, { recursive: true });
  const arms = zoneArms(zone, loads);
  const mk = (a) => ({ id: a.id, site: 'rewrite', tree: { dir: siteDir, search: a.search }, search: a.search });
  const lane = await openLane({ arms: arms.map(mk), width: zone === 'people' ? 1280 : 430, height: zone === 'people' ? 1000 : 932, log });
  const ex = (e) => lane.wd.expr(e);
  try {
    const out = { session: null, arms: {}, states: null, flip: null };
    const settle = async (id, stateId) => {
      let prev = null;
      for (let rep = 0; rep < 6; rep++) {
        const png = await lane.x.screenshot();
        if (flat(png)) throw new Error('the screenshot is one flat colour: the display is locked or off');
        if (prev && (sameImage(decodePng(prev), decodePng(png)) || rep === 5)) {
          const files = [];
          for (const [n, b] of [[0, prev], [1, png]]) { const f = `${id}_${stateId}_${n}.png`; writeFileSync(join(shotsDir, f), b); files.push(f); }
          return { files, settled: sameImage(decodePng(prev), decodePng(png)), tries: rep + 1 };
        }
        prev = png;
        await sleep(500);
      }
      throw new Error('unreachable');
    };
    {
      const info = await loadArm(lane, mk(arms[0]), { settleMs });
      const maxY = Number(await ex('document.documentElement.scrollHeight - innerHeight'));
      out.session = { ua: info.ua, dpr: info.dpr, vw: info.vw, vh: info.vh, maxY, device: 'macOS Safari (safaridriver)', timing: 'cadence only: the Lean quiet rule refuses a loaded Mac', pinnedClock: false };
      if (zone === 'pain') {
        out.flip = JSON.parse(await ex(FLIP_SCAN(maxY))).flip;
        if (out.flip === null) throw new Error('the faithful arm never sets is-pain-dark while scrolling');
      }
      if (zone === 'hero') {
        if (!(await ex(HERO_SPLASH_DONE))) throw new Error('the hero splash never reached done in the faithful arm');
        out.flip = Number(await ex(HERO_RANGE));
      }
      out.states = statesOf(zone, out.flip);
    }
    for (const arm of arms) {
      const info = await loadArm(lane, mk(arm), { settleMs });
      const maxY = Number(await ex('document.documentElement.scrollHeight - innerHeight'));
      const rows = [];
      if (zone === 'hero') {
        if (!(await ex(HERO_SPLASH_DONE))) throw new Error(`arm ${arm.id}: the hero splash never reached done`);
      } else if (zone !== 'pain' && zone !== 'people' && zone !== 'carousel') await ex(`(async () => { scrollTo({ top: ${maxY}, behavior: 'instant' }); await new Promise((r) => requestAnimationFrame(() => r())); return 1; })()`);
      let pushSeen = null;
      if (zone === 'people') {
        const su = JSON.parse(await ex(PEOPLE_SETUP));
        if (!su.ok) throw new Error(`arm ${arm.id}: people setup failed (${su.why})`);
        await sleep(2600);
        await ex(FREEZE_EXPR); await sleep(300);
        await ex(PEOPLE_HOVER); await sleep(900);
        await ex(FREEZE_EXPR); await sleep(300);
        const hv = JSON.parse(await ex(PEOPLE_STATE));
        if (!hv.tooltip) throw new Error(`arm ${arm.id}: the hover card did not open (${JSON.stringify(hv)})`);
        log(`  ${arm.id}: card open ${JSON.stringify(hv.style)} at scrollY ${hv.scrollY}`);
      }
      if (zone === 'carousel') {
        const ca = JSON.parse(await ex(CAROUSEL_ARM));
        if (!ca.ok) throw new Error(`arm ${arm.id}: carousel setup failed (${ca.why})`);
        await sleep(1500);
        const held = JSON.parse(await ex(CAROUSEL_STATE));
        if (held.n !== 5 || held.anims.length < 1) throw new Error(`arm ${arm.id}: the swap row did not stay parked (${JSON.stringify(held)})`);
        log(`  ${arm.id}: swap row parked, ${ca.swap.anims} animations paused, ${ca.wrapped} timers wrapped`);
        pushSeen = { taken: true, ...ca, anims: held.anims };
      }
      if (zone === 'morph') {
        await ex(FREEZE_EXPR); await sleep(400);
        pushSeen = JSON.parse(await ex(PUSH_EXPR));
        if (!pushSeen.taken || pushSeen.parked < 1) throw new Error(`arm ${arm.id}: the driver did not take the wheel push (${JSON.stringify(pushSeen)})`);
        log(`  ${arm.id}: push taken, ${pushSeen.anims} effects started, ${pushSeen.parked} frame parked`);
      }
      let prevFrames = null;
      for (const st of out.states) {
        let step = null;
        if (st.drive === 'push') {
          step = JSON.parse(await ex(STEP_EXPR(st.elapsedMs, st.m)));
          if (step.anims.length !== wantEffects(arm)) throw new Error(`arm ${arm.id}: ${step.anims.length} effects started, expected ${wantEffects(arm)}`);
          await sleep(1200);
        } else if (st.kind === 'swap') { await ex(CAROUSEL_STEP(st.elapsedMs)); await sleep(700); }
        else if (st.kind === 'hover-scroll') { await ex(PEOPLE_SCROLL(st.frames - (prevFrames ?? 0), st.dy)); prevFrames = st.frames; await sleep(900); }
        else if (st.kind === 'morph') { await ex(SET_MORPH(st.m)); await sleep(1200); }
        else { await ex(`(async () => { const raf = () => new Promise((r) => requestAnimationFrame(() => r())); scrollTo({ top: ${st.y}, behavior: 'instant' }); await raf(); await raf(); return scrollY; })()`); await sleep(900); }
        if (st.drive !== 'push' && st.kind !== 'swap') { await ex(FREEZE_EXPR); await sleep(400); await ex(FREEZE_EXPR); await sleep(300); }
        const state = JSON.parse(await ex(zone === 'hero' ? HERO_STATE : zone === 'people' ? PEOPLE_STATE : zone === 'carousel' ? CAROUSEL_STATE : st.kind === 'morph' ? NAV_STATE : PAIN_STATE));
        if (zone === 'hero' && arm.search.includes('hero.exit:threaded') && !(state.live && state.scrollAnims > 0)) throw new Error(`arm ${arm.id}: the threaded exit is not live (${JSON.stringify(state)})`);
        rows.push({ id: st.id, ...(await settle(arm.id, st.id)), state, push: step ? { ...step, taken: pushSeen.taken } : zone === 'carousel' ? pushSeen : null, census: null });
      }
      out.arms[arm.id] = { search: arm.search, states: rows, dpr: info.dpr };
    }
    return out;
  } finally {
    await lane.close();
  }
}
