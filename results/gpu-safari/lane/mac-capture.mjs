// Capture side of the macOS Safari lane (real Apple GPU and display, safaridriver). Same output shape as `captureZone` of sim-capture.mjs.
// It refuses a Safari window that is not visible: on a locked screen `document.visibilityState` is `hidden`, rAF does not run and the
// WebDriver screenshot is black (measured on this Mac: 0 rAF frames in 600 ms, an all-black 860x1760 PNG). It never fakes a frame.
// Differences from the Simulator lane, all recorded in the result: no pinned clock and no timer hold (safaridriver has no bootstrap
// script), so page animations are only frozen with `freezeAnimations`; no layer census (no Inspector). The A/A control and the faithful
// loads (`loads` in the result) quantify what that costs. Run it inside a `measure` slot (pnpm -s fw slot acquire --kind measure).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { openLane, loadArm, sleep } from './session.mjs';
import { decodePng, sameImage } from '../../../packages/measure-webkit/src/pathpix-png.mjs';
import { FREEZE_EXPR } from '../../../packages/measure-webkit/src/pathpix-page.mjs';
import { statesOf, zoneArms } from './plan.mjs';
import { SET_MORPH, NAV_STATE, PAIN_STATE, FLIP_SCAN } from './sim-capture.mjs';

/** True when a PNG is one flat colour: what a locked screen or a hidden window gives. */
export function flat(png) {
  const { rgba } = decodePng(png);
  for (let i = 4; i < rgba.length; i += 4) if (rgba[i] !== rgba[0] || rgba[i + 1] !== rgba[1] || rgba[i + 2] !== rgba[2]) return false;
  return true;
}

export async function captureZoneMac({ zone, siteDir, shotsDir, settleMs = 2500, log = (s) => console.error(s) }) {
  mkdirSync(shotsDir, { recursive: true });
  const arms = zoneArms(zone);
  const mk = (a) => ({ id: a.id, site: 'rewrite', tree: { dir: siteDir, search: a.search }, search: a.search });
  const lane = await openLane({ arms: arms.map(mk), width: 430, height: 932, log });
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
      const info = await loadArm(lane, arms[0], { settleMs });
      const maxY = Number(await ex('document.documentElement.scrollHeight - innerHeight'));
      out.session = { ua: info.ua, dpr: info.dpr, vw: info.vw, vh: info.vh, maxY, device: 'macOS Safari (safaridriver)', timing: 'cadence only: the Lean quiet rule refuses a loaded Mac', pinnedClock: false };
      if (zone === 'pain') {
        out.flip = JSON.parse(await ex(FLIP_SCAN(maxY))).flip;
        if (out.flip === null) throw new Error('the faithful arm never sets is-pain-dark while scrolling');
      }
      out.states = statesOf(zone, out.flip);
    }
    for (const arm of arms) {
      const info = await loadArm(lane, arm, { settleMs });
      const maxY = Number(await ex('document.documentElement.scrollHeight - innerHeight'));
      const rows = [];
      if (zone !== 'pain') await ex(`(async () => { scrollTo({ top: ${maxY}, behavior: 'instant' }); await new Promise((r) => requestAnimationFrame(() => r())); return 1; })()`);
      for (const st of out.states) {
        if (st.kind === 'morph') { await ex(SET_MORPH(st.m)); await sleep(1200); }
        else { await ex(`(async () => { const raf = () => new Promise((r) => requestAnimationFrame(() => r())); scrollTo({ top: ${st.y}, behavior: 'instant' }); await raf(); await raf(); return scrollY; })()`); await sleep(900); }
        await ex(FREEZE_EXPR); await sleep(400); await ex(FREEZE_EXPR); await sleep(300);
        const state = JSON.parse(await ex(st.kind === 'morph' ? NAV_STATE : PAIN_STATE));
        rows.push({ id: st.id, ...(await settle(arm.id, st.id)), state, census: null });
      }
      out.arms[arm.id] = { search: arm.search, states: rows, dpr: info.dpr };
    }
    return out;
  } finally {
    await lane.close();
  }
}
