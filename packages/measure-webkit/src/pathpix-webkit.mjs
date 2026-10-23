import { mkdirSync, writeFileSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { withSession } from './session.mjs';
import { loadFresh, pageInfo, scrollHold } from './page.mjs';
import { openTab, reconnect } from './wip.mjs';
import { attachFresh } from './poll.mjs';
import { T, attempts } from './timeouts.mjs';
import { takeCensus } from './census.mjs';
import { findDevice, simctl, sleep } from './sim.mjs';
import { decodePng, encodePng, cropImage, sameImage } from './pathpix-png.mjs';
import { offsets as leanOffsets } from './pathpix.mjs';
import { BOX_EXPR, FREEZE_EXPR, HOLD_EXPR, NEAR_IMAGES_EXPR, VIDEO_EXPR, MARK_ON, MARK_OFF, pathSearch } from './pathpix-page.mjs';
import { mask, maskEmpty } from './pathpix.mjs';

export function inViewPositions(rowsA, layer, dpr, frame) {
  const ks = [];
  rowsA.forEach((row, k) => {
    const box = row?.boxes?.[layer];
    if (box && !maskEmpty(mask(dpr, frame.w, frame.h, box))) ks.push(k);
  });
  return ks;
}

export function magentaBox(img) {
  let x0 = img.w, y0 = img.h, x1 = -1, y1 = -1;
  for (let y = 0; y < img.h; y++) {
    for (let x = 0; x < img.w; x++) {
      const o = (y * img.w + x) * 4;
      if (img.rgba[o] > 235 && img.rgba[o + 2] > 235 && img.rgba[o + 1] < 20) {
        if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  return x1 < 0 ? null : [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
}

export async function navigateHeld(c, url, log) {
  await c.evaluate(`window.__fwNav = 1; queueMicrotask(() => { location.href = ${JSON.stringify(url)}; }); 'nav'`);
  await c.close();
  return attachFresh({
    attach: (ms) => openTab(url, { waitMs: Math.min(ms, T(15000)), log }),
    isFresh: async (x) => (await x.evaluate('window.__fwNav === undefined')) === true,
    ready: async (x) => (await x.evaluate('document.readyState')) === 'complete',
    release: (x) => x.close(),
    timeoutMs: T(60000),
  });
}

export function screenshot(udid, file) {
  const r = simctl(['io', udid, 'screenshot', '--type=png', file], { timeoutMs: 60000 });
  if (r.status !== 0) throw new Error(`simctl screenshot failed: ${(r.stderr || r.stdout).trim().split('\n').slice(-2).join(' | ')}`);
  return readFileSync(file);
}

export function pinStatusBar(udid, log) {
  const r = simctl(['status_bar', udid, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3']);
  if (r.status !== 0) log(`status_bar override failed (the crop leaves the bar out): ${(r.stderr || '').trim().slice(0, 120)}`);
}

export async function runWebkitLane({ siteDir, out, run, layers: onlyLayers = null, pLayers = null, offsetIdx = null, settleMs = 6000, holdMs = 800, deadlineMs = Infinity, log: log0 = (s) => console.error(s) }) {
  const t0 = Date.now();
  const log = (m) => { const s = Math.round((Date.now() - t0) / 1000); log0(`[${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}] ${m}`); };
  const tmp = mkdtempSync(join(tmpdir(), 'fw-pathpix-'));
  mkdirSync(join(out, 'shots'), { recursive: true });
  const dev = findDevice();
  try {
    return await withSession(async (ctx) => {
      pinStatusBar(dev.udid, log);
      let content = null;
      const loadArm = async (search) => {
        const url = `${ctx.base}/${search}`;
        ctx.setClient(await navigateHeld(ctx.c, url, log));
        ctx.url = url;
        await loadFresh(ctx.c, { clock: 'pinned', settleMs, timers: 'hold' });
        log(`  timers held ${await ctx.c.runAsync(HOLD_EXPR)}`);
        await ctx.c.evaluate(FREEZE_EXPR);
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

      await loadArm('');
      const info = await pageInfo(ctx.c);
      const dpr = info.dpr;
      const probe = JSON.parse(await ctx.c.evaluate(BOX_EXPR));
      const declared = Object.keys(probe.boxes).sort();
      const layers = onlyLayers ? onlyLayers.filter((l) => declared.includes(l)) : declared;
      if (!layers.length) throw new Error(`no declared layer to measure (rendered: ${declared.join(', ') || 'none'})`);
      content = await place(info);
      const frame = { w: content[2], h: content[3] };
      const all = leanOffsets(info.maxY);
      const idx = offsetIdx ?? all.map((_, i) => i);
      const offs = idx.map((i) => all[i]);
      log(`lane webkit: dpr ${dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h} at ${content.slice(0, 2).join(',')}, maxY ${info.maxY}, offsets ${offs.join(',')}, layers ${layers.join(', ')}`);

      const pOnly = pLayers ? layers.filter((l) => pLayers.includes(l)) : layers;
      const arms = [['A', '', null], ['A2', '', null], ...pOnly.map((l) => [`P:${l}`, pathSearch(l), l])];
      const samples = {};
      const cut = [];
      const writeManifest = () => {
        const manifest = {
          schema: 'fw.path-pix/1', engine: 'webkit', lane: 'ios-simulator', run, lossless: true, compositing: 'gpu-simulator (no real GPU)',
          ua: info.ua, dpr, vw: info.vw, vh: info.vh, frame, content, maxY: info.maxY, offsets: offs, offsetIndex: idx, layers,
          pLayers: pOnly, cut, arms: arms.map(([arm, search]) => ({ arm, search })), samples,
        };
        writeFileSync(join(out, 'manifest.json'), JSON.stringify(manifest) + '\n');
        return manifest;
      };
      for (let a = 0; a < arms.length; a++) {
        const [arm, search, only] = arms[a];
        if (a > 1 && Date.now() - t0 > deadlineMs) { cut.push(arm); log(`arm ${arm} not run: past the ${Math.round(deadlineMs / 60000)} min deadline`); continue; }
        const ks = only ? inViewPositions(samples.A, only, dpr, frame) : idx.map((_, k) => k);
        let rows = null;
        for (let attempt = 1; !rows; attempt++) {
          try {
            await ctx.check?.();
            if (a > 0 || attempt > 1) await loadArm(search);
            rows = await captureArm(arm, ks);
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
        log(`arm ${arm}: ${rows.filter(Boolean).length} of ${idx.length} offsets captured`);
        writeManifest();
      }
      async function captureArm(arm, ks) {
        const rows = idx.map(() => null);
        for (const k of ks) {
          const y = offs[k];
          await scrollHold(ctx.c, y, { holdMs });
          await ctx.c.runAsync(NEAR_IMAGES_EXPR);
          const video = await ctx.c.runAsync(VIDEO_EXPR);
          await ctx.c.evaluate(FREEZE_EXPR);
          await sleep(400);
          await ctx.c.evaluate(FREEZE_EXPR);
          await sleep(300);
          const census = await takeCensus(ctx.c, { paintWindowMs: 0 });
          const here = JSON.parse(await ctx.c.evaluate(BOX_EXPR));
          const files = [];
          let prev = null, tries = 0;
          for (let rep = 0; rep < 6; rep++) {
            const png = cropImage(decodePng(screenshot(dev.udid, join(tmp, 'shot.png'))), content[0], content[1], frame.w, frame.h);
            tries++;
            if (prev && (sameImage(prev, png) || rep === 5)) {
              for (const [n, img] of [[0, prev], [1, png]]) {
                const f = `shots/${arm.replace(/[^\w.-]/g, '_')}_${idx[k]}_${n}.png`;
                writeFileSync(join(out, f), encodePng(img));
                files.push(f);
              }
              break;
            }
            prev = png;
            await sleep(500);
          }
          rows[k] = {
            i: idx[k], y, scrollY: here.scrollY, boxes: here.boxes, files, tries, video: typeof video === 'string' ? JSON.parse(video) : video, dprMilli: census.dprMilli,
            layers: census.layers.filter((l) => l.layer).map((l) => ({ layer: l.layer, boundsU: l.boundsU, compositedBounds: l.compositedBounds, memory: l.memory, reasons: l.reasons })),
            layerCount: census.layerCount,
          };
        }
        return rows;
      }
      return writeManifest();
    }, { keep: true, site: { dir: siteDir, search: '' }, log });
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}
