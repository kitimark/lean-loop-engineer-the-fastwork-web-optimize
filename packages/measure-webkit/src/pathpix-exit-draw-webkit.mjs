import { mkdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { withSession } from './session.mjs';
import { loadFresh, pageInfo, scrollHold } from './page.mjs';
import { reconnect } from './wip.mjs';
import { attempts } from './timeouts.mjs';
import { findDevice, sleep } from './sim.mjs';
import { decodePng, encodePng, cropImage, sameImage } from './pathpix-png.mjs';
import { FREEZE_EXPR, HOLD_EXPR, MARK_ON, MARK_OFF } from './pathpix-page.mjs';
import { DRAW_STATE_EXPR, drawAdvanceExpr, drawSeekExpr } from './pathpix-exit-draw-page.mjs';
import { drawTimes } from './pathpix-exit.mjs';
import { drawFile } from './pathpix-exit-draw.mjs';
import { magentaBox, navigateHeld, screenshot, pinStatusBar } from './pathpix-webkit.mjs';

export const DRAW_FLAGS = { N: 'hero.accent:draw-nolayout', F: 'hero.accent:draw-nolayout-full' };
export const drawSearch = (arm) => (DRAW_FLAGS[arm] ? `?fw=${DRAW_FLAGS[arm]}` : '');
const ADVANCE_STEP_MS = 50;
const ADVANCE_CAP_MS = 4000;

/**
 * Path-pix draw window: the accent word is not pinned; its own timer chain runs on the held virtual clock, and each
 * 0.9 s draw (out, then in) is paused and seeked to the same times (Lean `Fw.Gate.PathPix.drawTimes`) per arm.
 * Seeking is allowed in WebKit only.
 */
export async function runWebkitDrawLane({ siteDir, out, run, settleMs = 0, log: log0 = (s) => console.error(s) }) {
  const t0 = Date.now();
  const log = (m) => { const s = Math.round((Date.now() - t0) / 1000); log0(`[${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}] ${m}`); };
  const tmp = mkdtempSync(join(tmpdir(), 'fw-pathpix-draw-'));
  mkdirSync(join(out, 'shots'), { recursive: true });
  const dev = findDevice();
  const times = drawTimes();
  const arms = ['A', 'A2', 'N', 'F'];
  try {
    return await withSession(async (ctx) => {
      pinStatusBar(dev.udid, log);
      const loadArm = async (arm) => {
        for (let tries = 1; ; tries++) {
          ctx.setArm(arm === 'N' || arm === 'F' ? arm : 'A');
          const url = `${ctx.base}/${drawSearch(arm)}`;
          ctx.setClient(await navigateHeld(ctx.c, url, log));
          ctx.url = url;
          await loadFresh(ctx.c, { clock: 'pinned', settleMs, timers: 'hold' });
          const held = await ctx.c.runAsync(HOLD_EXPR, { pollMs: 100 });
          await ctx.c.evaluate(FREEZE_EXPR);
          let st = JSON.parse(await ctx.c.evaluate(DRAW_STATE_EXPR));
          if (st && (st.rect[1] < 0 || st.rect[1] + st.rect[3] > st.vh || st.rect[0] + st.rect[2] > st.vw)) {
            log(`  arm ${arm}: the accent box ${st.rect.map(Math.round)} is not inside the viewport ${st.vw}x${st.vh}; scrolling it into view`);
            await scrollHold(ctx.c, Math.max(0, Math.round(st.rect[1] + st.scrollY - 120)), { holdMs: 300 });
            st = JSON.parse(await ctx.c.evaluate(DRAW_STATE_EXPR));
          }
          if (st && st.idleOnly && !st.pin && st.draw === (arm === 'N' ? 'nolayout' : arm === 'F' ? 'nolayout-full' : null)) {
            log(`  arm ${arm}: timers held ${held}, accent idle "${st.label}", draw attr ${st.draw}`);
            return st;
          }
          if (tries >= 3) throw new Error(`arm ${arm}: the accent was not idle at the hold after ${tries} loads: ${JSON.stringify(st)}`);
          log(`  arm ${arm}: the accent was not idle at the hold (${JSON.stringify(st)}); loading again`);
        }
      };
      const place = async (info) => {
        await ctx.c.evaluate(MARK_ON);
        await sleep(700);
        const shot = decodePng(screenshot(dev.udid, join(tmp, 'mark.png')));
        const box = magentaBox(shot);
        await ctx.c.evaluate(MARK_OFF);
        if (!box) throw new Error('the marker box is not in the screenshot');
        const want = [Math.round(info.vw * info.dpr), Math.round(info.vh * info.dpr)];
        if (box[2] !== want[0] || box[3] > want[1]) throw new Error(`viewport marker ${box[2]}x${box[3]} does not fit the page's ${want.join('x')}`);
        if (box[1] + want[1] > shot.h) throw new Error(`the viewport (${want[1]} device px from y ${box[1]}) runs past the screenshot (${shot.h})`);
        return [box[0], box[1], want[0], want[1]];
      };

      const st0 = await loadArm('A');
      const info = await pageInfo(ctx.c);
      log(`  accent box ${st0.rect.map(Math.round)}, scrollY ${st0.scrollY}`);
      const content = await place(info);
      const frame = { w: content[2], h: content[3] };
      log(`lane webkit draw: dpr ${info.dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h} at ${content.slice(0, 2).join(',')}, times ${times.join(',')}`);

      const samples = {};
      const timeline = {};
      const cut = [];
      const writeManifest = () => {
        const manifest = {
          schema: 'fw.path-pix/1', mode: 'draw', flags: DRAW_FLAGS, engine: 'webkit', lane: 'ios-simulator', run, lossless: true, compositing: 'gpu-simulator (no real GPU)',
          ua: info.ua, dpr: info.dpr, vw: info.vw, vh: info.vh, frame, content, maxY: info.maxY, times, cut, timeline,
          arms: arms.map((arm) => ({ arm, search: drawSearch(arm) })), samples,
        };
        writeFileSync(join(out, 'manifest.json'), JSON.stringify(manifest) + '\n');
        return manifest;
      };
      async function shootFrame(arm, phase, k) {
        const seek = JSON.parse(await ctx.c.runAsync(drawSeekExpr(times[k]), { pollMs: 100 }));
        await sleep(300);
        let prev = null, stable = false, n = 0, img = null;
        while (n < 5 && !stable) {
          const png = cropImage(decodePng(screenshot(dev.udid, join(tmp, 'shot.png'))), content[0], content[1], frame.w, frame.h);
          n++;
          stable = prev !== null && sameImage(prev, png);
          prev = png; img = png;
          if (!stable) await sleep(300);
        }
        const file = drawFile(arm, phase, k);
        writeFileSync(join(out, file), encodePng(img));
        return { k, t: times[k], file, tries: n, stable, n: seek.n, kinds: seek.kinds, rect: seek.rect, times: seek.times };
      }
      async function captureArm(arm) {
        const st = await loadArm(arm);
        const row = { out: [], in: [] };
        const adv0 = JSON.parse(await ctx.c.runAsync(drawAdvanceExpr(st.cls, ADVANCE_CAP_MS, ADVANCE_STEP_MS), { pollMs: 100 }));
        if (!adv0.changed) throw new Error(`arm ${arm}: the accent did not leave idle in ${ADVANCE_CAP_MS} ms of virtual time`);
        for (let k = 0; k < times.length; k++) row.out.push(await shootFrame(arm, 'out', k));
        const adv1 = JSON.parse(await ctx.c.runAsync(drawAdvanceExpr(adv0.cls, ADVANCE_CAP_MS, ADVANCE_STEP_MS), { pollMs: 100 }));
        if (!adv1.changed) throw new Error(`arm ${arm}: the accent did not leave draw-out in ${ADVANCE_CAP_MS} ms of virtual time`);
        const mid = JSON.parse(await ctx.c.evaluate(DRAW_STATE_EXPR));
        if (mid.label === st.label) throw new Error(`arm ${arm}: the word did not change at the end of draw-out ("${mid.label}")`);
        for (let k = 0; k < times.length; k++) row.in.push(await shootFrame(arm, 'in', k));
        timeline[arm] = { idleCls: st.cls, outCls: adv0.cls, inCls: adv1.cls, outAdvanced: adv0.advanced, inAdvanced: adv1.advanced, wordFrom: st.label, wordTo: mid.label, vnow: adv1.wk?.vnow ?? null };
        return row;
      }
      for (const arm of arms) {
        let row = null;
        for (let attempt = 1; !row; attempt++) {
          try {
            await ctx.check?.();
            row = await captureArm(arm);
          } catch (e) {
            if (attempt >= attempts()) {
              if (arm === 'A' || arm === 'A2') throw e;
              cut.push(`${arm} (failed: ${e.message})`);
              log(`  arm ${arm} given up after ${attempt} attempts: ${e.message}`);
              break;
            }
            log(`  arm ${arm} attempt ${attempt} failed (${e.message}); reconnecting and repeating the arm`);
            await reconnect(ctx, { log });
          }
        }
        if (row) {
          samples[arm] = row;
          const unstable = [...row.out, ...row.in].filter((f) => !f.stable).length;
          log(`arm ${arm}: ${row.out.length + row.in.length} frames captured, ${unstable} unstable`);
        }
        writeManifest();
      }
      return writeManifest();
    }, {
      keep: true, log,
      arms: { A: { dir: siteDir, search: '' }, N: { dir: siteDir, search: drawSearch('N') }, F: { dir: siteDir, search: drawSearch('F') } },
    });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
