import { mkdirSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { withSession } from './session.mjs';
import { loadFresh, pageInfo, scrollHold } from './page.mjs';
import { reconnect } from './wip.mjs';
import { attempts } from './timeouts.mjs';
import { takeCensus } from './census.mjs';
import { findDevice, sleep } from './sim.mjs';
import { decodePng, encodePng, cropImage, sameImage } from './pathpix-png.mjs';
import { FREEZE_EXPR, HOLD_EXPR, NEAR_IMAGES_EXPR, VIDEO_EXPR, MARK_ON, MARK_OFF } from './pathpix-page.mjs';
import { ACCENT_SERVED_EXPR, ACCENT_SIG_EXPR, EXIT_BOX_EXPR, EXIT_GEOM_EXPR, EXIT_LIVE_EXPR, EXIT_NUDGE_EXPR, EXIT_WAIT_EXPR } from './pathpix-exit-page.mjs';
import { exitOffsets, armPin, hookSearch } from './pathpix-exit.mjs';
import { magentaBox, navigateHeld, screenshot, pinStatusBar } from './pathpix-webkit.mjs';

export async function runWebkitExitLane({ siteDir, out, run, flag, offsetIdx = null, settleMs = 6000, holdMs = 800, log: log0 = (s) => console.error(s) }) {
  const t0 = Date.now();
  const log = (m) => { const s = Math.round((Date.now() - t0) / 1000); log0(`[${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}] ${m}`); };
  const tmp = mkdtempSync(join(tmpdir(), 'fw-pathpix-exit-'));
  mkdirSync(join(out, 'shots'), { recursive: true });
  const dev = findDevice();
  // The prerendered config is chosen by the flag alone (session.mjs `arms`); the hook only rides on the URL the page opens.
  const searchA = '', searchP = `?fw=${flag}`;
  try {
    return await withSession(async (ctx) => {
      pinStatusBar(dev.udid, log);
      const handover = {};
      const loadArm = async (arm) => {
        const search = hookSearch(arm === 'P' ? searchP : searchA);
        ctx.setArm(arm === 'P' ? 'P' : 'A');
        const url = `${ctx.base}/${search}`;
        ctx.setClient(await navigateHeld(ctx.c, url, log));
        ctx.url = url;
        await loadFresh(ctx.c, { clock: 'pinned', settleMs, timers: 'hold' });
        log(`  timers held ${await ctx.c.runAsync(HOLD_EXPR)}`);
        if (armPin(arm) === 'accent-hook') {
          const pin = JSON.parse(await ctx.c.evaluate(ACCENT_SERVED_EXPR));
          if (!pin.hooked || !pin.same) throw new Error(`accent hook not in effect for arm ${arm}: ${JSON.stringify(pin)}`);
          handover.pin = { ...handover.pin, [arm]: pin };
          log(`  accent held by the site hook (live ${pin.live}, served ${pin.ssr})`);
        }
        await ctx.c.evaluate(FREEZE_EXPR);
        if (arm === 'P') {
          const frames = await ctx.c.runAsync(EXIT_WAIT_EXPR);
          let live = JSON.parse(await ctx.c.evaluate(EXIT_LIVE_EXPR));
          let nudged = false;
          if (!live.live) {
            nudged = (await ctx.c.evaluate(EXIT_NUDGE_EXPR)) === 1;
            await ctx.c.runAsync(EXIT_WAIT_EXPR);
            live = JSON.parse(await ctx.c.evaluate(EXIT_LIVE_EXPR));
          }
          handover.P = { framesWaited: frames, nudged, ...live };
          log(`  P hand-over: live ${live.live}, variant ${live.variant}, splash ${live.splash}, scroll-driven animations ${live.nonDoc}, nudged ${nudged}`);
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

      await loadArm('A');
      const info = await pageInfo(ctx.c);
      const geom = JSON.parse(await ctx.c.evaluate(EXIT_GEOM_EXPR));
      if (!geom) throw new Error('no hero exit track on the default page');
      const exit = { T: geom.T, h: geom.h, v: geom.v, n: Math.max(1, geom.h - geom.v), variant: geom.variant };
      const offs = exitOffsets(exit.T, exit.n);
      const content = await place(info);
      const frame = { w: content[2], h: content[3] };
      log(`lane webkit exit: dpr ${info.dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h} at ${content.slice(0, 2).join(',')}, maxY ${info.maxY}, track T ${exit.T} h ${exit.h} n ${exit.n}, offsets ${offs.join(',')}`);

      const arms = ['A', 'A2', 'P'];
      const samples = {};
      const cut = [];
      const writeManifest = () => {
        const manifest = {
          schema: 'fw.path-pix/1', mode: 'exit', flag, engine: 'webkit', lane: 'ios-simulator', run, lossless: true, compositing: 'gpu-simulator (no real GPU)',
          ua: info.ua, dpr: info.dpr, vw: info.vw, vh: info.vh, frame, content, maxY: info.maxY, exit, offsets: offs, cut, handover,
          arms: arms.map((arm) => ({ arm, search: hookSearch(arm === 'P' ? searchP : searchA) })), samples,
        };
        writeFileSync(join(out, 'manifest.json'), JSON.stringify(manifest) + '\n');
        return manifest;
      };
      async function captureArm(arm) {
        const rows = offs.map(() => null);
        for (let k = 0; k < offs.length; k++) {
          if (offsetIdx && !offsetIdx.includes(k)) continue;
          await scrollHold(ctx.c, offs[k], { holdMs });
          await ctx.c.runAsync(NEAR_IMAGES_EXPR);
          const video = await ctx.c.runAsync(VIDEO_EXPR);
          await ctx.c.evaluate(FREEZE_EXPR);
          await sleep(400);
          await ctx.c.evaluate(FREEZE_EXPR);
          await sleep(300);
          const census = await takeCensus(ctx.c, { paintWindowMs: 0 });
          const here = JSON.parse(await ctx.c.evaluate(EXIT_BOX_EXPR));
          const live = JSON.parse(await ctx.c.evaluate(EXIT_LIVE_EXPR));
          const files = [];
          let prev = null, tries = 0;
          const accentBefore = JSON.parse(await ctx.c.evaluate(ACCENT_SIG_EXPR));
          for (let rep = 0; rep < 6; rep++) {
            const png = cropImage(decodePng(screenshot(dev.udid, join(tmp, 'shot.png'))), content[0], content[1], frame.w, frame.h);
            tries++;
            if (prev && (sameImage(prev, png) || rep === 5)) {
              for (const [n, img] of [[0, prev], [1, png]]) {
                const f = `shots/${arm}_${k}_${n}.png`;
                writeFileSync(join(out, f), encodePng(img));
                files.push(f);
              }
              break;
            }
            prev = png;
            await sleep(500);
          }
          const accentAfter = JSON.parse(await ctx.c.evaluate(ACCENT_SIG_EXPR));
          rows[k] = {
            accent: { shotStart: accentBefore, shotEnd: accentAfter },
            i: k, y: offs[k], scrollY: here.scrollY, dateNow: here.dateNow, boxes: here.boxes, alpha: here.alpha, cover: here.cover, parts: here.parts, live, files, tries, video: typeof video === 'string' ? JSON.parse(video) : video, dprMilli: census.dprMilli,
            layers: census.layers.filter((l) => l.layer).map((l) => ({ layer: l.layer, boundsU: l.boundsU, compositedBounds: l.compositedBounds, memory: l.memory, reasons: l.reasons })),
            layerCount: census.layerCount,
          };
        }
        return rows;
      }
      for (let a = 0; a < arms.length; a++) {
        const arm = arms[a];
        let rows = null;
        for (let attempt = 1; !rows; attempt++) {
          try {
            await ctx.check?.();
            if (a > 0 || attempt > 1) await loadArm(arm);
            rows = await captureArm(arm);
          } catch (e) {
            if (attempt >= attempts()) {
              if (a < 2) throw e;
              cut.push(`${arm} (failed: ${e.message})`);
              log(`  arm ${arm} given up after ${attempt} attempts: ${e.message}`);
              break;
            }
            log(`  arm ${arm} attempt ${attempt} failed (${e.message}); reconnecting and repeating the arm`);
            await reconnect(ctx, { log });
          }
        }
        if (!rows) { writeManifest(); continue; }
        samples[arm] = rows;
        log(`arm ${arm}: ${rows.filter(Boolean).length} of ${offs.length} offsets captured`);
        writeManifest();
      }
      return writeManifest();
    }, {
      keep: true, log,
      arms: { A: { dir: siteDir, search: searchA }, P: { dir: siteDir, search: searchP } },
    });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
