import { spawn, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, openSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { startServer } from './server.mjs';
import { sampleAt } from './census.mjs';
import { parseProfile } from './profile.mjs';
import { pathSearch, laneOffsets, exitOffsets, armPin } from './pathpix-pure.mjs';

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const s = a.replace(/^--/, ''); const i = s.indexOf('='); return i < 0 ? [s, true] : [s.slice(0, i), s.slice(i + 1)]; }));
const { profile } = parseProfile(JSON.parse(readFileSync(`/profiles/${args.profile ?? 'swipe-v1'}.json`, 'utf8')));
const exprs = JSON.parse(readFileSync('/exprs/page.json', 'utf8'));
const OUT = args.out ?? '/out';
const RUN = args.run && args.run !== true ? args.run : 'local';
const ONLY_LAYERS = args.layers && args.layers !== true ? args.layers.split(',') : null;
const OFFSET_IDX = args.offsets && args.offsets !== true ? args.offsets.split(',').map(Number) : null;
const MODE = args.mode && args.mode !== true ? args.mode : 'layers';
const FLAG = args.flag && args.flag !== true ? args.flag : null;
const FONT_FAMILIES = [...new Set((spawnSync('fc-list', [':', 'family'], { encoding: 'utf8' }).stdout ?? '').split(/[\n,]/).map((f) => f.trim()).filter(Boolean))].sort();
const PAGE_FONTS = `JSON.stringify([...document.fonts].filter((f) => f.status === 'loaded').map((f) => f.family + ' ' + f.weight + ' ' + f.style))`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dt = 1000 / profile.hz;
const T0 = 5_000_000;
const EPOCH_MS = Date.parse(profile.pinnedDate);
const srv = await startServer('/site');
const CHROME_ARGS = [
  '--remote-debugging-port=9222', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--user-data-dir=/tmp/fw-profile',
  '--enable-begin-frame-control', '--run-all-compositor-stages-before-draw',
  '--disable-new-content-rendering-timeout', '--disable-checker-imaging', '--disable-image-animation-resync', '--num-raster-threads=2',
  '--disable-features=WaitForLateScrollEvents',
  '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE localhost, EXCLUDE 127.0.0.1',
  '--font-render-hinting=none', '--force-color-profile=srgb', '--hide-scrollbars', '--mute-audio',
  '--disable-background-networking', '--disable-breakpad', '--no-first-run', '--lang=en-US', 'about:blank',
];
const chrome = spawn(process.env.FW_CHROME, CHROME_ARGS, { stdio: ['ignore', openSync('/tmp/chrome.log', 'w'), openSync('/tmp/chrome.log', 'a')] });
const log = (s) => console.error(s);

async function main() {
  for (let i = 0; i < 200; i++) { try { await fetch('http://127.0.0.1:9222/json/version'); break; } catch { await sleep(50); } }
  const version = await (await fetch('http://127.0.0.1:9222/json/version')).json();
  const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222', defaultViewport: null, protocolTimeout: 60000 });
  const bs = await browser.target().createCDPSession();
  const shim = readFileSync('/driver/clock-shim.js', 'utf8');
  let tick = 0;

  async function openPage() {
    const { targetId } = await bs.send('Target.createTarget', { url: 'about:blank', enableBeginFrameControl: true, width: profile.viewport.width, height: profile.viewport.height });
    const page = await (await browser.waitForTarget((t) => t._targetId === targetId)).page();
    const c = await page.createCDPSession();
    const ev = async (expression) => {
      const r = await c.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: false });
      if (r.exceptionDetails) throw new Error('evaluate failed: ' + JSON.stringify(r.exceptionDetails).slice(0, 400));
      return r.result.value;
    };
    await c.send('Page.enable'); await c.send('Runtime.enable');
    await c.send('Emulation.setDeviceMetricsOverride', { width: profile.viewport.width, height: profile.viewport.height, deviceScaleFactor: profile.viewport.dpr, mobile: profile.viewport.mobile, screenWidth: profile.viewport.width, screenHeight: profile.viewport.height });
    await c.send('Emulation.setTouchEmulationEnabled', { enabled: profile.viewport.touch, maxTouchPoints: 5 });
    await c.send('Emulation.setTimezoneOverride', { timezoneId: profile.timezone });
    await c.send('Emulation.setLocaleOverride', { locale: profile.locale });
    await c.send('Emulation.setUserAgentOverride', { userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36', acceptLanguage: profile.locale });
    await c.send('Page.addScriptToEvaluateOnNewDocument', { source: `globalThis.__FW_CFG = ${JSON.stringify({ epochMs: EPOCH_MS, seed: profile.seed })};\n${shim}` });
    const beginFrame = async (png) => {
      let bf = null;
      for (let attempt = 0; attempt < 20 && !bf; attempt++) {
        tick++;
        bf = await Promise.race([c.send('HeadlessExperimental.beginFrame', { frameTimeTicks: T0 + tick * dt, interval: dt, ...(png ? { screenshot: { format: 'png' } } : {}) }), sleep(attempt === 0 ? 1500 : 5000).then(() => null)]);
      }
      if (!bf) throw new Error('beginFrame never answered');
      return bf;
    };
    const pump = async (n = 1) => { for (let i = 0; i < n; i++) await beginFrame(false); };
    const shot = async () => {
      const bf = await beginFrame(true);
      if (!bf.screenshotData) throw new Error('beginFrame returned no screenshot (hasDamage ' + bf.hasDamage + ')');
      return Buffer.from(bf.screenshotData, 'base64');
    };
    const close = async () => { await c.detach().catch(() => {}); await bs.send('Target.closeTarget', { targetId }).catch(() => {}); };
    return { c, ev, pump, shot, close };
  }

  async function quietNet(p) {
    let last = -1, stable = 0;
    for (let i = 0; i < 150 && stable < 4; i++) {
      await p.pump(1);
      await sleep(40);
      const r = srv.requests();
      if (r === last && srv.inflight() === 0) stable++; else { stable = 0; last = r; }
    }
  }

  const pins = {};
  async function loadArm(search, arm = null) {
    const p = await openPage();
    const { c, ev, pump } = p;
    const navRes = await c.send('Page.navigate', { url: `http://127.0.0.1:${srv.port}/${search}` });
    if (navRes.errorText) throw new Error('navigation failed: ' + navRes.errorText);
    let vt = 0, quiet = 0, frames = 0;
    for (; frames < profile.load.maxFrames && quiet < profile.load.quietFrames; frames++) {
      vt = frames * dt;
      await ev(`__fwclock.advanceTo(${vt})`).catch(() => {});
      await pump(1);
      await sleep(20);
      const st = await ev(`document.readyState + ',' + (document.fonts ? document.fonts.status : 'loaded') + ',' + (${exprs.imagesReady} ? 1 : 0) + ',' + (window.__fw ? (window.__fw.hydrated ? 1 : 0) : 1)`).catch(() => 'loading,x,0,0');
      const [rs, fonts, imgs, hyd] = st.split(',');
      quiet = rs === 'complete' && fonts === 'loaded' && imgs === '1' && hyd === '1' && srv.inflight() === 0 ? quiet + 1 : 0;
    }
    if (quiet < profile.load.quietFrames) throw new Error(`page not quiet after ${frames} frames (server inflight ${srv.inflight()}, search ${JSON.stringify(search)})`);
    vt = 20_000;
    for (let i = 0; i < profile.load.prerollFrames; i++, vt += dt) { await ev(`__fwclock.advanceTo(${vt})`); await pump(1); }
    if (MODE === 'exit' && arm && armPin(arm) === 'ssr-accent') {
      const pin = JSON.parse(await ev(exprs.pinAccent));
      if (!pin.pinned || !pin.same) throw new Error(`accent pin failed for arm ${arm}: ${JSON.stringify(pin)}`);
      pins[arm] = pin;
      log(`  accent pinned (live ${pin.before}, served ${pin.ssr})`);
      await pump(2);
    }
    await quietNet(p);
    await ev(exprs.freeze);
    await pump(3);
    p.vt = vt;
    return p;
  }

  mkdirSync(`${OUT}/shots`, { recursive: true });
  const probe = async (p) => JSON.parse(await p.ev(exprs.boxes));
  const pa = await loadArm('', 'A');
  const info = await probe(pa);
  const ua = await pa.ev('navigator.userAgent');
  const fonts = { systemFonts: FONT_FAMILIES, pageFonts: JSON.parse(await pa.ev(PAGE_FONTS)) };
  const maxY = await pa.ev('document.documentElement.scrollHeight - innerHeight');
  if (MODE === 'exit') {
    if (!FLAG) throw new Error('--mode=exit needs --flag=<id:variant>');
    const geom = JSON.parse(await pa.ev(exprs.exitGeom));
    if (!geom) throw new Error('no hero exit track on the default page');
    const exit = { T: geom.T, h: geom.h, v: geom.v, n: Math.max(1, geom.h - geom.v), variant: geom.variant };
    const offs = exitOffsets(exit.T, exit.n);
    const png0 = await pa.shot();
    const frame = { w: png0.readUInt32BE(16), h: png0.readUInt32BE(20) };
    const dpr = frame.w / info.vw;
    if (!Number.isInteger(dpr) || dpr < 1 || frame.h !== Math.round(info.vh * dpr)) throw new Error(`screenshot ${frame.w}x${frame.h} does not fit the ${info.vw}x${info.vh} viewport at an integer scale (page dpr ${info.dpr})`);
    const searchP = `?fw=${FLAG}`;
    log(`lane chromium exit: page dpr ${info.dpr}, screenshot scale ${dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h}, track T ${exit.T} h ${exit.h} n ${exit.n}, offsets ${offs.join(',')}`);
    const arms = [['A', ''], ['A2', ''], ['P', searchP]];
    const samples = {}, handover = {};
    const liveNow = async (p) => JSON.parse(await p.ev(exprs.exitLive));
    for (let a = 0; a < arms.length; a++) {
      const [arm, search] = arms[a];
      const p = a === 0 ? pa : await loadArm(search, arm);
      if (arm === 'P') {
        let live = await liveNow(p), frames = 0, nudged = false;
        for (; frames < 90 && !live.live; frames++) { await p.pump(1); await sleep(20); live = await liveNow(p); }
        if (!live.live) {
          nudged = (await p.ev(exprs.exitNudge)) === 1;
          for (let f = 0; f < 30 && !live.live; f++) { await p.pump(1); await sleep(20); live = await liveNow(p); }
        }
        handover.P = { framesWaited: frames, nudged, ...live };
        log(`  P hand-over: live ${live.live}, variant ${live.variant}, splash ${live.splash}, scroll-driven animations ${live.nonDoc}, nudged ${nudged}`);
      }
      const rows = [];
      for (let k = 0; k < offs.length; k++) {
        const y = offs[k];
        await p.ev(`window.scrollTo({ top: ${y}, left: 0, behavior: 'instant' })`);
        let last = null, still = 0;
        for (let f = 0; f < 240 && still < 6; f++) {
          p.vt += dt;
          await p.ev(`__fwclock.advanceTo(${p.vt})`);
          await p.pump(1);
          const now = await p.ev(exprs.exitBoxes);
          still = now === last ? still + 1 : 0;
          last = now;
        }
        await quietNet(p);
        await p.ev(exprs.freeze);
        await p.pump(3);
        const here = JSON.parse(await p.ev(exprs.exitBoxes));
        const live = await liveNow(p);
        const files = [];
        for (let rep = 0; rep < 2; rep++) {
          const f = `shots/${arm}_${k}_${rep}.png`;
          writeFileSync(`${OUT}/${f}`, await p.shot());
          files.push(f);
        }
        const census = await sampleAt(p.c, { ev: p.ev, pump: () => p.pump(1), y });
        rows.push({
          i: k, y, scrollY: here.scrollY, boxes: here.boxes, alpha: here.alpha, live, files, dprMilli: census.dprMilli,
          layers: census.layers.filter((l) => l.layer).map((l) => ({ layer: l.layer, boundsU: l.boundsU, compositedBounds: null, memory: l.memory, reasons: l.reasons })),
          layerCount: census.layerCount, ...(census.error ? { censusError: census.error } : {}),
        });
      }
      samples[arm] = rows;
      log(`arm ${arm}: ${rows.length} offsets captured`);
      await p.close();
    }
    const manifest = {
      schema: 'fw.path-pix/1', mode: 'exit', flag: FLAG, engine: 'chromium', lane: 'chromium-begin-frame', run: RUN, lossless: true,
      compositing: 'software (--disable-gpu), secondary', browser: version.Browser, browserArgs: CHROME_ARGS.filter((x) => !x.startsWith('--user-data-dir') && !x.startsWith('--remote-debugging-port')), ua,
      dpr, pageDpr: info.dpr, vw: info.vw, vh: info.vh, frame, content: [0, 0, frame.w, frame.h], maxY, exit, offsets: offs, handover: { ...handover, pin: pins }, fonts,
      arms: arms.map(([arm, search]) => ({ arm, search })), samples, served: Object.keys(srv.served()).length, missing: srv.missing(),
    };
    writeFileSync(`${OUT}/manifest.json`, JSON.stringify(manifest) + '\n');
    log(`wrote ${OUT}/manifest.json`);
    return;
  }
  const declared = Object.keys(info.boxes).sort();
  const layers = ONLY_LAYERS ? ONLY_LAYERS.filter((l) => declared.includes(l)) : declared;
  if (!layers.length) throw new Error(`no declared layer to measure (rendered: ${declared.join(', ') || 'none'})`);
  const all = laneOffsets(maxY);
  const idx = OFFSET_IDX ?? all.map((_, i) => i);
  const offs = idx.map((i) => all[i]);
  const png0 = await pa.shot();
  const frame = { w: png0.readUInt32BE(16), h: png0.readUInt32BE(20) };
  const dpr = frame.w / info.vw;
  if (!Number.isInteger(dpr) || dpr < 1 || frame.h !== Math.round(info.vh * dpr)) throw new Error(`screenshot ${frame.w}x${frame.h} does not fit the ${info.vw}x${info.vh} viewport at an integer scale (page dpr ${info.dpr})`);
  log(`lane chromium: page dpr ${info.dpr}, screenshot scale ${dpr}, viewport ${info.vw}x${info.vh}, frame ${frame.w}x${frame.h}, maxY ${maxY}, offsets ${offs.join(',')}, layers ${layers.join(', ')}`);

  const arms = [['A', ''], ['A2', ''], ...layers.map((l) => [`P:${l}`, pathSearch(l)])];
  const samples = {};
  for (let a = 0; a < arms.length; a++) {
    const [arm, search] = arms[a];
    const p = a === 0 ? pa : await loadArm(search);
    const rows = [];
    for (let k = 0; k < idx.length; k++) {
      const y = offs[k];
      await p.ev(`window.scrollTo({ top: ${y}, left: 0, behavior: 'instant' })`);
      await p.pump(3);
      await quietNet(p);
      await p.ev(exprs.freeze);
      await p.pump(3);
      const here = await probe(p);
      const files = [];
      for (let rep = 0; rep < 2; rep++) {
        const f = `shots/${arm.replace(/[^\w.-]/g, '_')}_${idx[k]}_${rep}.png`;
        writeFileSync(`${OUT}/${f}`, await p.shot());
        files.push(f);
      }
      const census = await sampleAt(p.c, { ev: p.ev, pump: () => p.pump(1), y });
      rows.push({
        i: idx[k], y, scrollY: here.scrollY, boxes: here.boxes, files, dprMilli: census.dprMilli,
        layers: census.layers.filter((l) => l.layer).map((l) => ({ layer: l.layer, boundsU: l.boundsU, compositedBounds: null, memory: l.memory, reasons: l.reasons })),
        layerCount: census.layerCount, ...(census.error ? { censusError: census.error } : {}),
      });
    }
    samples[arm] = rows;
    log(`arm ${arm}: ${rows.length} offsets captured`);
    await p.close();
  }
  const manifest = {
    schema: 'fw.path-pix/1', engine: 'chromium', lane: 'chromium-begin-frame', run: RUN, lossless: true,
    compositing: 'software (--disable-gpu), secondary', browser: version.Browser, browserArgs: CHROME_ARGS.filter((x) => !x.startsWith('--user-data-dir') && !x.startsWith('--remote-debugging-port')), ua,
    dpr, pageDpr: info.dpr, vw: info.vw, vh: info.vh, frame, content: [0, 0, frame.w, frame.h], maxY, offsets: offs, offsetIndex: idx, layers,
    arms: arms.map(([arm, search]) => ({ arm, search })), samples, served: Object.keys(srv.served()).length, missing: srv.missing(),
    fonts,
  };
  writeFileSync(`${OUT}/manifest.json`, JSON.stringify(manifest) + '\n');
  log(`wrote ${OUT}/manifest.json`);
}

let code = 0;
try {
  await main();
} catch (e) {
  code = 1;
  const tail = (() => { try { return readFileSync('/tmp/chrome.log', 'utf8').split('\n').slice(-30).join('\n'); } catch { return null; } })();
  mkdirSync(OUT, { recursive: true });
  writeFileSync(`${OUT}/error.json`, JSON.stringify({ message: String(e.message ?? e), stack: String(e.stack ?? '').split('\n').slice(0, 12), chromeLogTail: tail, missing: srv.missing() }, null, 1) + '\n');
  log(`path-pix driver failed: ${e.message ?? e}`);
}
chrome.kill('SIGTERM');
process.exit(code);
